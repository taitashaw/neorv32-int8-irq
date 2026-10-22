// =============================================================================
// dot4_irq: interrupt latency while the CPU runs INT8 inference on the CFU
// =============================================================================
// Combined design: NEORV32 + INT8 CFU (DOT4ACC, SETACC) + irq_lat_mon.
// 1. Reference pass: all 64 test vectors, interrupts off, cycles per inference.
// 2. Scenario DOT4 (tag 6): the real INT8 inference (the same infer() as the
//    INT8 project, CFU build) runs pass after pass over the 64 test vectors while
//    the testbench generator raises pseudo-random interrupts, until N_IRQ were
//    handled. Every logit of every inference is compared with the Python INT8
//    reference, so a CFU accumulator disturbed by an interrupt would show up.
// 3. Scenario DOT4BB (tag 7): back-to-back CFU instructions in assembly
//    (1 SETACC + 7 DOT4ACC per iteration), like the profiler's DIV loop.
// Monitor results are printed in the profiler's IRQLAT line format, so the
// profiler's scripts/gate.py checks them unchanged (bounds in bounds_dot4.json).

#include <neorv32.h>
#include <stdint.h>
#include "model_int8.h"
#include "test_vectors.h"

#ifndef N_IRQ
#define N_IRQ 500
#endif
#ifndef HANDLER_TOUCHES_CFU
#define HANDLER_TOUCHES_CFU 0
#endif

// monitor (irq_lat_mon) on the XBUS
#define MON ((volatile uint32_t *)0xF0000000u)
enum { M_CTRL = 0, M_BOUND, M_COUNT, M_MIN, M_MAX, M_SUM, M_LAST, M_NVIOL, M_ERRS, M_TAG, M_MAXB };
#define M_HIST 16

// testbench interrupt generator on the XBUS
#define GEN ((volatile uint32_t *)0xF1000000u)
enum { G_CTRL = 0, G_DMIN, G_DMASK, G_ACK, G_NREQ, G_DONE };

volatile uint32_t g_count;

extern void irq_entry(void);
extern uint32_t loop_dot4bb(uint32_t n, uint32_t a, uint32_t b);

// ---- INT8 inference: copied from the INT8 project's sw/common/int8_mlp.c (USE_CFU = 1) ----
#define CFU_SETACC(a)   RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 1, 0, (uint32_t)(a), 0)
#define CFU_DOT4(w, x)  RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 0, 0, (w), (x))

static inline int32_t neuron(const int8_t *w, const int8_t *x, int n, int32_t bias) {
  const uint32_t *wp = (const uint32_t *)w;
  const uint32_t *xp = (const uint32_t *)x;
  int32_t acc = (int32_t)CFU_SETACC(bias);
  for (int k = 0; k < n / 4; k++) {
    acc = (int32_t)CFU_DOT4(wp[k], xp[k]);
  }
  return acc;
}

static inline int8_t requant_relu(int32_t acc, int32_t m0, int sh) {
  int64_t y = ((int64_t)acc * (int64_t)m0 + ((int64_t)1 << (sh - 1))) >> sh;
  if (y < 0) y = 0;
  if (y > 127) y = 127;
  return (int8_t)y;
}

static int8_t a1[64] __attribute__((aligned(4)));
static int8_t a2[32] __attribute__((aligned(4)));
static int8_t a3[32] __attribute__((aligned(4)));

static void __attribute__((noinline)) infer(const int8_t *x, int32_t *logits) {
  for (int j = 0; j < 64; j++) a1[j] = requant_relu(neuron(&W0[j * 16], x,  16, B0[j]), M0_0, SH_0);
  for (int j = 0; j < 32; j++) a2[j] = requant_relu(neuron(&W1[j * 64], a1, 64, B1[j]), M0_1, SH_1);
  for (int j = 0; j < 32; j++) a3[j] = requant_relu(neuron(&W2[j * 32], a2, 32, B2[j]), M0_2, SH_2);
  for (int j = 0; j < 5;  j++) logits[j] = neuron(&W3[j * 32], a3, 32, B3[j]);
}
// ---- end of copied inference ----

typedef struct { uint32_t vec, mism, cls_err, cyc_sum, cyc_min, cyc_max; } pass_stat_t;

// one pass over all 64 vectors; returns statistics, checks every logit
static void run_pass(pass_stat_t *p, int print_first) {
  static int32_t out[5];
  for (int v = 0; v < N_VEC; v++) {
    uint32_t c0 = neorv32_cpu_csr_read(CSR_MCYCLE);
    infer(&X_Q[v * 16], out);
    uint32_t c = neorv32_cpu_csr_read(CSR_MCYCLE) - c0;
    p->vec++; p->cyc_sum += c;
    if (c < p->cyc_min) p->cyc_min = c;
    if (c > p->cyc_max) p->cyc_max = c;
    int best = 0;
    for (int j = 0; j < 5; j++) {
      if (out[j] != Y_EXP[v * 5 + j]) {
        if (p->mism < 8) {
          neorv32_uart0_printf("MISMATCH vec %d logit %d: got %d expected %d\n", v, j, out[j], Y_EXP[v * 5 + j]);
        }
        p->mism++;
      }
      if (out[j] > out[best]) best = j;
    }
    if (best != CLS_EXP[v]) p->cls_err++;
    if (print_first && (v < 2)) {
      neorv32_uart0_printf("vec %d: logits %d %d %d %d %d class %d cycles %u\n", v,
                           out[0], out[1], out[2], out[3], out[4], best, c);
    }
  }
}

static void mon_start(uint32_t id, uint32_t bound, uint32_t shift, uint32_t dmin, uint32_t dmask) {
  MON[M_TAG]   = id;
  MON[M_BOUND] = bound;
  MON[M_CTRL]  = 1u | (shift << 8); // clear statistics, set bin width
  g_count = 0;
  GEN[G_DMIN]  = dmin;
  GEN[G_DMASK] = dmask;
  neorv32_cpu_csr_write(CSR_MTVEC, (uint32_t)&irq_entry);
  neorv32_cpu_csr_set(CSR_MIE, 1u << CSR_MIE_MEIE);
  neorv32_cpu_csr_set(CSR_MSTATUS, 1u << CSR_MSTATUS_MIE);
}

static void mon_report(uint32_t id, const char *name, uint32_t bound, uint32_t shift) {
  uint32_t i, h[16];
  neorv32_cpu_csr_clr(CSR_MSTATUS, 1u << CSR_MSTATUS_MIE);
  neorv32_cpu_csr_clr(CSR_MIE, 1u << CSR_MIE_MEIE);
  for (i = 0; i < 16; i++) { h[i] = MON[M_HIST + i]; }
  uint32_t errs = MON[M_ERRS];
  neorv32_uart0_printf("IRQLAT id=%u name=%s n=%u min=%u max=%u sum=%u maxb=%u nviol=%u orphan=%u overrun=%u bound=%u shift=%u handled=%u hist=",
    id, name, MON[M_COUNT], MON[M_MIN], MON[M_MAX], MON[M_SUM], MON[M_MAXB], MON[M_NVIOL],
    errs & 0xffff, errs >> 16, bound, shift, g_count);
  for (i = 0; i < 16; i++) {
    neorv32_uart0_printf("%u%s", h[i], (i < 15) ? ":" : "\n");
  }
}

int main(void) {
  neorv32_uart0_setup(19200, 0);
  neorv32_uart0_printf("IRQLAT start N_IRQ=%u CRIT_N=%u\n", N_IRQ, 0);
  neorv32_uart0_printf("DOT4 build: handler touches CFU = %u\n", (uint32_t)HANDLER_TOUCHES_CFU);
  uint32_t isa = neorv32_cpu_csr_read(CSR_MXISA);
  if (((isa >> CSR_MXISA_XCFU) & 1) == 0) {
    neorv32_uart0_printf("ERROR: CFU not implemented\n");
    GEN[G_DONE] = 1;
    while (1) {}
  }

  // 1. reference pass, interrupts off
  pass_stat_t ref = {0, 0, 0, 0, 0xffffffffu, 0};
  run_pass(&ref, 1);
  neorv32_uart0_printf("DOT4REF vectors=%u logit_mismatches=%u class_mismatches=%u cycles_mean=%u cycles_min=%u cycles_max=%u\n",
    ref.vec, ref.mism, ref.cls_err, ref.cyc_sum / ref.vec, ref.cyc_min, ref.cyc_max);

  // 2. DOT4: real INT8 inference under interrupts
  pass_stat_t s = {0, 0, 0, 0, 0xffffffffu, 0};
  uint32_t passes = 0;
  mon_start(6, BOUND_DOT4, 3, 64, 255);
  GEN[G_CTRL] = 1;
  while (g_count < N_IRQ) {
    run_pass(&s, 0);
    passes++;
  }
  uint32_t c = g_count;
  while (g_count == c) {}   // stop right after a handled request (next one is >= 64 cycles away)
  GEN[G_CTRL] = 0;
  mon_report(6, "DOT4", BOUND_DOT4, 3);
  neorv32_uart0_printf("DOT4RUN passes=%u vectors=%u logits_checked=%u logit_mismatches=%u class_mismatches=%u cycles_mean=%u cycles_min=%u cycles_max=%u\n",
    passes, s.vec, s.vec * 5, s.mism, s.cls_err, s.cyc_sum / s.vec, s.cyc_min, s.cyc_max);

  // 3. DOT4BB: back-to-back CFU instructions
  // a = lanes (127, -128, 1, -1), b = lanes (-128, 127, -1, 1) -> dot4 = -16256 - 16256 - 1 - 1 = -32514
  uint32_t a = (uint32_t)(uint8_t)127 | ((uint32_t)(uint8_t)-128 << 8) | ((uint32_t)(uint8_t)1 << 16) | ((uint32_t)(uint8_t)-1 << 24);
  uint32_t b = (uint32_t)(uint8_t)-128 | ((uint32_t)(uint8_t)127 << 8) | ((uint32_t)(uint8_t)-1 << 16) | ((uint32_t)(uint8_t)1 << 24);
  int32_t expect = (int32_t)a + 7 * (-32514);
  mon_start(7, BOUND_DOT4BB, 3, 64, 255);
  uint32_t got = loop_dot4bb(N_IRQ, a, b);
  mon_report(7, "DOT4BB", BOUND_DOT4BB, 3);
  neorv32_uart0_printf("DOT4BBRUN acc_last=%d expected=%d %s\n", (int32_t)got, expect, ((int32_t)got == expect) ? "OK" : "WRONG");

  int ok = (ref.mism == 0) && (ref.cls_err == 0) && (s.mism == 0) && (s.cls_err == 0) && ((int32_t)got == expect);
  neorv32_uart0_printf("DOT4 INT8 RESULT: %s\n", ok ? "PASS" : "FAIL");
  neorv32_uart0_printf("IRQLAT done\n");
  GEN[G_DONE] = 0; // tell the testbench to finish
  while (1) {}
  return 0;
}
