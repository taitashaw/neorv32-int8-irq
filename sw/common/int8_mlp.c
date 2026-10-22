/*
 * INT8 inference of the hls4ml KERAS_3layer jet-tagging MLP (16-64-32-32-5) on NEORV32.
 * Build with USE_CFU=0 (plain RV32 software) or USE_CFU=1 (custom INT8 dot-product instruction).
 * Every output logit is compared with the Python reference (model/quantize.py).
 * Cycles per inference are read from the mcycle CSR (Zicntr) around each inference.
 */
#include <neorv32.h>
#include <stdint.h>
#include "model_int8.h"
#include "test_vectors.h"

#ifndef USE_CFU
#error "define USE_CFU to 0 or 1"
#endif

#if USE_CFU
/* CFU R-type instructions on the custom-0 opcode (see rtl/core/neorv32_cpu_alu_cfu.vhd):
 *   funct3 = 0: acc = acc + sum of 4 int8 x int8 products of rs1 and rs2 lanes, rd = new acc
 *   funct3 = 1: acc = rs1, rd = rs1 */
#define CFU_SETACC(a)   RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 1, 0, (uint32_t)(a), 0)
#define CFU_DOT4(w, x)  RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 0, 0, (w), (x))
#endif

/* one output neuron: bias + dot(w[0..n-1], x[0..n-1]); n is a multiple of 4,
 * w and x are 4-byte aligned */
static inline int32_t neuron(const int8_t *w, const int8_t *x, int n, int32_t bias) {
#if USE_CFU
  const uint32_t *wp = (const uint32_t *)w;
  const uint32_t *xp = (const uint32_t *)x;
  int32_t acc = (int32_t)CFU_SETACC(bias);
  for (int k = 0; k < n / 4; k++) {
    acc = (int32_t)CFU_DOT4(wp[k], xp[k]);
  }
  return acc;
#else
  int32_t acc = bias;
  for (int k = 0; k < n; k++) {
    acc += (int32_t)w[k] * (int32_t)x[k];
  }
  return acc;
#endif
}

/* requantize to int8 activation: (acc * M0 + 2^(sh-1)) >> sh, then ReLU and saturate to 127 */
static inline int8_t requant_relu(int32_t acc, int32_t m0, int sh) {
  int64_t y = ((int64_t)acc * (int64_t)m0 + ((int64_t)1 << (sh - 1))) >> sh;
  if (y < 0) y = 0;
  if (y > 127) y = 127;
  return (int8_t)y;
}

static int8_t a1[64] __attribute__((aligned(4)));
static int8_t a2[32] __attribute__((aligned(4)));
static int8_t a3[32] __attribute__((aligned(4)));

static void infer(const int8_t *x, int32_t *logits) {
  for (int j = 0; j < 64; j++) a1[j] = requant_relu(neuron(&W0[j * 16], x,  16, B0[j]), M0_0, SH_0);
  for (int j = 0; j < 32; j++) a2[j] = requant_relu(neuron(&W1[j * 64], a1, 64, B1[j]), M0_1, SH_1);
  for (int j = 0; j < 32; j++) a3[j] = requant_relu(neuron(&W2[j * 32], a2, 32, B2[j]), M0_2, SH_2);
  for (int j = 0; j < 5;  j++) logits[j] = neuron(&W3[j * 32], a3, 32, B3[j]);
}

int main(void) {
  neorv32_rte_setup();
  neorv32_uart0_setup(19200, 0);

  uint32_t isa = neorv32_cpu_csr_read(CSR_MXISA);
  neorv32_uart0_printf("\nINT8 MLP 16-64-32-32-5, %s, %u test vectors\n",
                       USE_CFU ? "CFU dot4 instruction" : "plain software", (uint32_t)N_VEC);
  neorv32_uart0_printf("MISA=0x%x MXISA=0x%x Xcfu=%u\n", neorv32_cpu_csr_read(CSR_MISA), isa,
                       (isa >> CSR_MXISA_XCFU) & 1);
#if USE_CFU
  if (((isa >> CSR_MXISA_XCFU) & 1) == 0) {
    neorv32_uart0_printf("ERROR: CFU not implemented\nINT8 RESULT: FAIL\n");
    return 1;
  }
#endif

  static int32_t out[5];
  uint32_t errors = 0, cls_err = 0, keras_agree = 0;
  uint32_t cyc_sum = 0, cyc_min = 0xffffffffu, cyc_max = 0, ins_sum = 0;

  for (int v = 0; v < N_VEC; v++) {
    uint32_t i0 = neorv32_cpu_csr_read(CSR_MINSTRET);
    uint32_t c0 = neorv32_cpu_csr_read(CSR_MCYCLE);
    infer(&X_Q[v * 16], out);
    uint32_t c1 = neorv32_cpu_csr_read(CSR_MCYCLE);
    uint32_t i1 = neorv32_cpu_csr_read(CSR_MINSTRET);
    uint32_t c = c1 - c0;
    cyc_sum += c; ins_sum += i1 - i0;
    if (c < cyc_min) cyc_min = c;
    if (c > cyc_max) cyc_max = c;

    int best = 0;
    for (int j = 0; j < 5; j++) {
      if (out[j] != Y_EXP[v * 5 + j]) {
        errors++;
        neorv32_uart0_printf("MISMATCH vec %d logit %d: got %d expected %d\n", v, j, out[j], Y_EXP[v * 5 + j]);
      }
      if (out[j] > out[best]) best = j;
    }
    if (best != CLS_EXP[v]) cls_err++;
    if (best == CLS_KERAS[v]) keras_agree++;
    if (v < 4) {
      neorv32_uart0_printf("vec %d: logits %d %d %d %d %d class %d cycles %u\n", v,
                           out[0], out[1], out[2], out[3], out[4], best, c);
    }
  }

  neorv32_uart0_printf("logit mismatches: %u of %u\n", errors, (uint32_t)(N_VEC * 5));
  neorv32_uart0_printf("class mismatches vs INT8 reference: %u of %u\n", cls_err, (uint32_t)N_VEC);
  neorv32_uart0_printf("class agreement with Keras float: %u of %u\n", keras_agree, (uint32_t)N_VEC);
  neorv32_uart0_printf("cycles per inference: mean %u (total %u / %u), min %u, max %u\n",
                       cyc_sum / N_VEC, cyc_sum, (uint32_t)N_VEC, cyc_min, cyc_max);
  neorv32_uart0_printf("instructions per inference: mean %u (total %u)\n", ins_sum / N_VEC, ins_sum);
  neorv32_uart0_printf("INT8 RESULT: %s\n", (errors == 0 && cls_err == 0) ? "PASS" : "FAIL");
  return 0;
}
