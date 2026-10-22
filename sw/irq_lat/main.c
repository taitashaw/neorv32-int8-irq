// =============================================================================
// irq_lat: interrupt-latency stress program for NEORV32 + irq_lat_mon
// =============================================================================
// For each scenario: program the monitor (tag, bound, histogram shift, clear),
// program the testbench interrupt generator (pseudo-random delay), enable the
// machine external interrupt, run the stress loop until N interrupts were
// handled, then read the monitor and print one result line over UART0.

#include <neorv32.h>
#include <stdint.h>

#ifndef N_IRQ
#define N_IRQ 500
#endif

// monitor (irq_lat_mon) on the XBUS
#define MON ((volatile uint32_t *)0xF0000000u)
enum { M_CTRL = 0, M_BOUND, M_COUNT, M_MIN, M_MAX, M_SUM, M_LAST, M_NVIOL, M_ERRS, M_TAG, M_MAXB };
#define M_HIST 16

// testbench interrupt generator on the XBUS
#define GEN ((volatile uint32_t *)0xF1000000u)
enum { G_CTRL = 0, G_DMIN, G_DMASK, G_ACK, G_NREQ, G_DONE };

// handler copy location in the slow XBUS memory
#define SLOW_HANDLER_ADDR 0x40000800u

volatile uint32_t g_count;

extern void irq_entry(void);
extern void irq_entry_end(void);
extern void loop_base(uint32_t n);
extern void loop_div(uint32_t n);
extern void loop_ldst(uint32_t n);
extern void loop_crit(uint32_t n);
extern void loop_icold(uint32_t n);

typedef struct {
  const char *name;
  void (*loop)(uint32_t n);
  uint32_t dmin, dmask; // generator delay: dmin + (random & dmask) cycles
  uint32_t bound;       // latency bound in cycles (same values as scripts/bounds.json)
  uint32_t shift;       // histogram bin width = 2^shift cycles
  int      slow_handler;
} scenario_t;

static const scenario_t scn[] = {
  { "BASE",  loop_base,  64, 255,  BOUND_BASE,  1, 0 },
  { "DIV",   loop_div,   64, 255,  BOUND_DIV,   3, 0 },
  { "LDST",  loop_ldst,  64, 255,  BOUND_LDST,  3, 0 },
  { "CRIT",  loop_crit,  64, 1023, BOUND_CRIT,  5, 0 },
  { "B2B",   loop_base,  0,  3,    BOUND_B2B,   3, 0 },
  { "ICOLD", loop_icold, 64, 255,  BOUND_ICOLD, 5, 1 },
};

static void run(uint32_t id, const scenario_t *s) {
  uint32_t i, h[16];
  uint32_t handler = (uint32_t)&irq_entry;

  if (s->slow_handler) {
    // copy the handler into slow memory and point mtvec there
    uint32_t *src = (uint32_t *)&irq_entry, *end = (uint32_t *)&irq_entry_end;
    volatile uint32_t *dst = (volatile uint32_t *)SLOW_HANDLER_ADDR;
    while (src < end) { *dst++ = *src++; }
    asm volatile ("fence.i");
    handler = SLOW_HANDLER_ADDR;
  }

  MON[M_TAG]   = id;
  MON[M_BOUND] = s->bound;
  MON[M_CTRL]  = 1u | (s->shift << 8); // clear statistics, set bin width
  g_count = 0;
  GEN[G_DMIN]  = s->dmin;
  GEN[G_DMASK] = s->dmask;

  neorv32_cpu_csr_write(CSR_MTVEC, handler);
  neorv32_cpu_csr_set(CSR_MIE, 1u << CSR_MIE_MEIE);
  neorv32_cpu_csr_set(CSR_MSTATUS, 1u << CSR_MSTATUS_MIE);
  s->loop(N_IRQ); // the loop starts and stops the generator itself

  neorv32_cpu_csr_clr(CSR_MSTATUS, 1u << CSR_MSTATUS_MIE);
  neorv32_cpu_csr_clr(CSR_MIE, 1u << CSR_MIE_MEIE);

  for (i = 0; i < 16; i++) { h[i] = MON[M_HIST + i]; }
  uint32_t errs = MON[M_ERRS];
  neorv32_uart0_printf("IRQLAT id=%u name=%s n=%u min=%u max=%u sum=%u maxb=%u nviol=%u orphan=%u overrun=%u bound=%u shift=%u handled=%u hist=",
    id, s->name, MON[M_COUNT], MON[M_MIN], MON[M_MAX], MON[M_SUM], MON[M_MAXB], MON[M_NVIOL],
    errs & 0xffff, errs >> 16, s->bound, s->shift, g_count);
  for (i = 0; i < 16; i++) {
    neorv32_uart0_printf("%u%s", h[i], (i < 15) ? ":" : "\n");
  }
}

int main(void) {
  uint32_t i;
  neorv32_uart0_setup(19200, 0);
  neorv32_uart0_printf("IRQLAT start N_IRQ=%u CRIT_N=%u\n", N_IRQ, CRIT_N);
  for (i = 0; i < sizeof(scn) / sizeof(scn[0]); i++) {
    run(i, &scn[i]);
  }
  neorv32_uart0_printf("IRQLAT done\n");
  GEN[G_DONE] = 0; // tell the testbench to finish
  while (1) {}
  return 0;
}
