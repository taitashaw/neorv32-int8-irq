// =============================================================================
// dot4_ctx: trap handler and the back-to-back CFU loop for the DOT4 scenarios,
// with the CFU accumulator saved across the trap
// =============================================================================
// Copy of the combined project's sw/dot4_irq/dot4_stress.S. main.c is the same file,
// byte for byte. The handler is the profiler project's irq_entry; build options:
//   HANDLER_TOUCHES_CFU = 1: the handler executes SETACC x0, x0 (acc = 0), so the CFU
//                            is really used inside the handler (the negative control
//                            of the combined project).
//   CFU_SAVE = 0: nothing saved (the combined project's handler).
//   CFU_SAVE = 1: GETACC t0 + sw at entry, lw + SETACC x0, t0 before mret
//                 (needs rtl/neorv32_cpu_alu_cfu_getacc.vhd or the bank CFU).
//   CFU_SAVE = 2: SELBANK 1 at entry, SELBANK 0 before mret; the handler's CFU work
//                 lands in bank 1 (needs rtl/neorv32_cpu_alu_cfu_bank.vhd).
//   CFU_SAVE = 3: like 1, but the read is DOT4ACC t0, x0, x0 (acc + 0 = acc), which
//                 the original 2-stage CFU already supports (no new hardware).
// The first handler instruction stays "addi sp, sp, -16": the monitor measures the
// response up to that instruction.

.macro GEN_ON
  lui  t2, 0xF1000
  li   t3, 1
  sw   t3, 0(t2)           // generator CTRL = 1: start pseudo-random requests
.endm
.macro GEN_OFF
  sw   zero, 0(t2)         // generator CTRL = 0: stop requests, drop the line
.endm

#ifndef HANDLER_TOUCHES_CFU
#define HANDLER_TOUCHES_CFU 0
#endif
#ifndef CFU_SAVE
#define CFU_SAVE 0
#endif

  .option norvc            // fixed 32-bit encodings: no compressed instructions here

  .section .text.irq_entry
  .balign 64
  .global irq_entry
irq_entry:
  addi sp, sp, -16         // first handler instruction: the measured response
  sw   t0, 0(sp)
  sw   t1, 4(sp)
#if CFU_SAVE == 1
  .insn r CUSTOM_0, 2, 0, t0, x0, x0   // GETACC t0: t0 = acc (acc unchanged)
  sw   t0, 8(sp)
#elif CFU_SAVE == 2
  .insn r CUSTOM_0, 3, 1, x0, x0, x0   // SELBANK 1: the handler works on bank 1
#elif CFU_SAVE == 3
  .insn r CUSTOM_0, 0, 0, t0, x0, x0   // DOT4ACC t0, x0, x0: acc += 0, t0 = acc
  sw   t0, 8(sp)
#endif
  csrr t0, mcause
  li   t1, 0x8000000B      // machine external interrupt
  bne  t0, t1, irq_bad
  lui  t0, 0xF1000         // interrupt generator base
  sw   zero, 12(t0)        // ACK: drops the request line
#if HANDLER_TOUCHES_CFU
  .insn r CUSTOM_0, 1, 0, x0, x0, x0   // SETACC x0, x0: acc = 0 (the handler uses the CFU)
#endif
  lui  t0, %hi(g_count)
  lw   t1, %lo(g_count)(t0)
  addi t1, t1, 1
  sw   t1, %lo(g_count)(t0)
#if (CFU_SAVE == 1) || (CFU_SAVE == 3)
  lw   t0, 8(sp)
  .insn r CUSTOM_0, 1, 0, x0, t0, x0   // SETACC x0, t0: acc = saved value
#elif CFU_SAVE == 2
  .insn r CUSTOM_0, 3, 0, x0, x0, x0   // SELBANK 0: back to the interrupted code's bank
#endif
  lw   t0, 0(sp)
  lw   t1, 4(sp)
  addi sp, sp, 16
  mret
irq_bad:                   // any other trap: report and stop the simulation
  lui  t0, 0xF1000
  csrr t1, mcause
  sw   t1, 20(t0)          // DONE register, exit code = mcause
1:
  j    1b

  .section .text.loops
  .balign 4

// DOT4BB: back-to-back CFU instructions, 1 SETACC + 7 DOT4ACC per iteration
// (the same shape as one 28-input neuron), like the profiler's DIV loop.
// a0 = number of interrupts to wait for; a1, a2 = operand words.
// Returns in a0 the accumulator after the last iteration (checked in C).
  .global loop_dot4bb
loop_dot4bb:
  lui  a7, %hi(g_count)
  mv   a5, a0
  GEN_ON
1:
  .insn r CUSTOM_0, 1, 0, a3, a1, x0   // SETACC  a3, a1      : acc = a1
  .insn r CUSTOM_0, 0, 0, a3, a1, a2   // DOT4ACC a3, a1, a2  : acc += dot4(a1, a2)
  .insn r CUSTOM_0, 0, 0, a3, a1, a2
  .insn r CUSTOM_0, 0, 0, a3, a1, a2
  .insn r CUSTOM_0, 0, 0, a3, a1, a2
  .insn r CUSTOM_0, 0, 0, a3, a1, a2
  .insn r CUSTOM_0, 0, 0, a3, a1, a2
  .insn r CUSTOM_0, 0, 0, a3, a1, a2
  lw   t0, %lo(g_count)(a7)
  bltu t0, a5, 1b
  GEN_OFF
  mv   a0, a3
  ret
