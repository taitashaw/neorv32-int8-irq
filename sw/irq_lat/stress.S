// =============================================================================
// irq_lat: trap handler and stress loops (RV32, assembly so the instruction mix
// is exactly what the scenario names say)
// =============================================================================
// All loop functions: a0 = number of interrupts to wait for. Each loop starts
// the testbench interrupt generator as its first action and stops it as its
// last action, so every measured request arrives while the stress pattern runs
// (requests are never raised while C code runs). The loop returns when the
// handler has counted a0 interrupts (g_count in DMEM). Only caller-saved
// registers are used.

.macro GEN_ON
  lui  t2, 0xF1000
  li   t3, 1
  sw   t3, 0(t2)           // generator CTRL = 1: start pseudo-random requests
.endm
.macro GEN_OFF
  sw   zero, 0(t2)         // generator CTRL = 0: stop requests, drop the line
.endm

#ifndef CRIT_N
#define CRIT_N 50          // iterations of the interrupts-disabled delay loop
#endif

  .option norvc            // fixed 32-bit encodings: no compressed instructions here

// -----------------------------------------------------------------------------
// Machine external interrupt handler (direct mode, mtvec = irq_entry).
// Position independent except for absolute I/O and DMEM addresses, so the
// block irq_entry..irq_entry_end can be copied to slow memory and run there.
// -----------------------------------------------------------------------------
  .section .text.irq_entry
  .balign 64
  .global irq_entry
  .global irq_entry_end
irq_entry:
  addi sp, sp, -16         // first handler instruction: the measured response
  sw   t0, 0(sp)
  sw   t1, 4(sp)
  csrr t0, mcause
  li   t1, 0x8000000B      // machine external interrupt
  bne  t0, t1, irq_bad
  lui  t0, 0xF1000         // interrupt generator base
  sw   zero, 12(t0)        // ACK: drops the request line
  lui  t0, %hi(g_count)
  lw   t1, %lo(g_count)(t0)
  addi t1, t1, 1
  sw   t1, %lo(g_count)(t0)
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
irq_entry_end:

  .section .text.loops
  .balign 4

// S0 BASE: single-cycle ALU instructions
  .global loop_base
loop_base:
  lui  a7, %hi(g_count)
  GEN_ON
1:
  addi a1, a1, 1
  addi a2, a2, 3
  xor  a3, a1, a2
  add  a4, a3, a1
  addi a1, a1, 1
  addi a2, a2, 3
  xor  a3, a1, a2
  add  a4, a3, a1
  lw   t0, %lo(g_count)(a7)
  bltu t0, a0, 1b
  GEN_OFF
  ret

// S1 DIV: back-to-back integer divides (serial divider)
  .global loop_div
loop_div:
  lui  a7, %hi(g_count)
  GEN_ON
  li   a1, 0x7FFFFFFF
  li   a2, 3
1:
  div  a3, a1, a2
  div  a4, a1, a2
  div  a5, a1, a2
  div  a6, a1, a2
  div  a3, a1, a2
  div  a4, a1, a2
  div  a5, a1, a2
  div  a6, a1, a2
  lw   t0, %lo(g_count)(a7)
  bltu t0, a0, 1b
  GEN_OFF
  ret

// S2 LDST: loads and stores to the slow XBUS memory (0x40000000, MEM_LATE wait cycles)
  .global loop_ldst
loop_ldst:
  lui  a7, %hi(g_count)
  GEN_ON
  lui  a1, 0x40000
1:
  lw   a2, 0(a1)
  sw   a2, 4(a1)
  lw   a3, 8(a1)
  sw   a3, 12(a1)
  lw   a2, 16(a1)
  sw   a2, 20(a1)
  lw   a3, 24(a1)
  sw   a3, 28(a1)
  lw   t0, %lo(g_count)(a7)
  bltu t0, a0, 1b
  GEN_OFF
  ret

// S3 CRIT: critical section with mstatus.MIE = 0 for CRIT_N delay-loop iterations
  .global loop_crit
loop_crit:
  lui  a7, %hi(g_count)
  GEN_ON
1:
  csrci mstatus, 8         // interrupts off
  li   t1, CRIT_N
2:
  addi t1, t1, -1
  bnez t1, 2b
  csrsi mstatus, 8         // interrupts on
  addi a1, a1, 1
  addi a2, a2, 1
  addi a3, a3, 1
  addi a4, a4, 1
  lw   t0, %lo(g_count)(a7)
  bltu t0, a0, 1b
  GEN_OFF
  ret

// S5 ICOLD: invalidate the i-cache every iteration, so a handler that lives in
// slow memory is always fetched cold through the i-cache
  .global loop_icold
loop_icold:
  lui  a7, %hi(g_count)
  GEN_ON
1:
  fence.i
  addi a1, a1, 1
  addi a2, a2, 3
  xor  a3, a1, a2
  add  a4, a3, a1
  addi a1, a1, 1
  addi a2, a2, 3
  xor  a3, a1, a2
  add  a4, a3, a1
  lw   t0, %lo(g_count)(a7)
  bltu t0, a0, 1b
  GEN_OFF
  ret
