# How to read the pictures

This project has a small computer brain (a RISC-V CPU called NEORV32) with two extras on the same chip:

* a **math helper** that does four multiplications at once, so the brain can run a small neural network faster, and
* a **stopwatch** that measures how long the brain takes to answer a doorbell (an interrupt).

The big question: if the doorbell rings while the brain is busy with the math helper, does the answer come later, and by how much?

A second question came up on the way: the math helper keeps a running total between jobs. If the doorbell answer also uses the helper, that total is lost. The final design adds one more helper job, GETACC ("give me the running total"), so the doorbell answer can keep a copy and put it back. Picture 6 shows it.

All pictures are made by the real AMD Vivado tools, not drawn by hand. To open them on your screen:

```
cd .
scripts/open_view.sh                 # block design, helper schematic, worst doorbell during the network
scripts/open_view.sh all             # all seven pictures
scripts/open_view.sh dot4ins irqcfu  # just the ones you name
```

The names you can give: `bd`, `schematic`, `dot4ins`, `irqdot4`, `irqcfu`, `getacc`, `fail`, `all`. The waveform windows first replay the simulation up to the moment they show: `dot4ins` takes a few seconds, `fail` about 1 minute, `irqdot4`, `irqcfu` and `getacc` about 3 minutes each. The Vivado and XSim windows stay open until you close them.

The screenshots in `docs/gui_test_screenshots/` show what each window looks like.

Row names in the waveforms are the RTL names. The part before the dot is the instance: `ctrl` is the CPU control unit, `cfu` the INT8 math helper, `mon` the stopwatch (latency monitor), `trace` the CPU's trace port, and `helper` a simulation-only viewing helper (`tb/int8irq_wave_helper.vhd`) that splits words into bytes and names the helper's jobs. `clk`, `rstn`, `irq_mei`, `p_ic_stb`, `p_ic_ack`, `smp_valid`, `smp_lat` and `viol` are testbench signals.

## Picture 1: the block design (`bd`, Vivado "Diagram" tab)

Screenshot: `vivado_bd.png`. Read it from left to right: things come in on the left and go out on the right.

| Block or pin | What it is, in plain words |
|---|---|
| `doorbell_button` | A real push button on the ZCU104 board (SW0). Pressing it rings the doorbell. |
| `doorbell_sync` | Two tiny memory cells that tidy up the button signal so it lines up with the clock tick. |
| `clock_and_reset` (bottom left) | A box with two parts inside. `zynq_ps_makes_the_clock` is the big Zynq chip part; here it only makes the 100 MHz clock (100 million ticks per second). `reset_helper` keeps everything asleep until the clock is steady. |
| `riscv_brain_with_int8_math_helper` | The brain. The math helper is built inside it, so the helper has its own picture (picture 2). The brain's memory already holds the program and the network's numbers. |
| `address_switch` | A mail sorter. When the brain sends a message, the address decides where it goes: addresses 0xF00000xx go to the stopwatch, everything else goes to `nothing_else_on_bus`. |
| `nothing_else_on_bus` | No other device is fitted. Any message to another address gets the answer "nobody here" (a bus error). |
| `stopwatch_latency_monitor` | The stopwatch. It starts when the doorbell rings and stops when the brain finishes the first instruction of its answer (the "handler"). It keeps the fastest time, the slowest time and a count of "too slow" answers. |
| `trace_valid`, `trace_intr` (wires from brain to stopwatch) | The brain reports each instruction it finishes (`trace_valid`) and marks the first one of its answer (`trace_intr`). That is how the stopwatch knows when to stop. |
| `too_slow_led` | Board light. On if one answer took longer than allowed. |
| `doorbell_led` | Board light that shows the doorbell signal. |
| `awake_led` | Board light that is on once the brain is out of reset. |
| `talking_led` | Board light that flickers while the brain sends text. `talking_light_not_gate` flips the text wire, because the wire is high when it is quiet. |
| `uart_text_out`, `uart_text_in` | The serial text line to a computer, so the program can print its numbers. |

How this picture differs from the simulation in the waveforms:
* In simulation the doorbell comes from a random doorbell machine in the testbench, exactly on a clock tick, so there is no `doorbell_sync`. With the button, the brain and the stopwatch both see the doorbell after the 2-tick tidy-up, so the measured numbers stay the same; only the time from the finger to the answer is 2 ticks longer.
* In simulation, addresses other than the stopwatch go to a slow test memory and to the doorbell machine. On the board picture they go to `nothing_else_on_bus`. So the test program cannot run unchanged on this board design; it needs a board version. Nothing has been run on a board.
* The two extra lights (`awake_led`, `talking_led`) are only on the board picture.
* The brain, the helper, the stopwatch and the address sorting are the same logic as the simulated design `rtl/int8_irq_top.vhd`, split into separate blocks by thin wrappers in `rtl/bd/`.

Tip: if the Diagram looks empty or tiny, click the "Fit View" button (four arrows pointing out) in the Diagram toolbar. Double-click the "Diagram" tab title to make it fill the window.

## Picture 2: inside the math helper (`schematic`, Vivado "int8_helper_schematic" tab)

Screenshot: `vivado_cfu_schematic.png`. This is the helper alone, as Vivado reads it from the code.

* The yellow boxes on the left, `s1_a_reg` and `s1_b_reg`, are the helper's notepad: it copies the two words the brain hands over.
* The four circles marked `RTL_MULT` are four multipliers. Each multiplies one small number (from -128 to 127) from the first word by one from the second word, all four at once.
* The circles marked `RTL_ADD` after them add the four answers together, then `acc0_i` adds that to the running total.
* `acc_reg` on the right remembers the running total. `done_reg` makes the "answer ready" signal, `valid_o`.
* The small boxes along the bottom (`RTL_EQ`, `RTL_AND`) read the instruction and decide: is this a "multiply and add" job (DOT4ACC), a "start the total at this number" job (SETACC) or a "give me the total" job (GETACC)?

The toolbar says "124 Cells" and the list on the left says "Leaf Cells (126)" (119 and 121 before GETACC was added). The two counts differ by 2; the reason was not checked.

## Picture 3: one math-helper job (`dot4ins`, XSim)

Screenshot: `xsim_dot4ins_one_instruction.png`. A waveform is like a movie strip of the wires: time goes from left to right, each row is one wire, and you can read its value at any moment. This one shows the first multiply job (DOT4ACC) for the second test input of the network, with the doorbell switched off. Just before it, a SETACC job set the running total to the neuron's starting number.

Two markers (lines with labels at the top):
* **A start_i** at 640,645 ns: the brain hands the helper a job.
* **B valid_o** at 640,665 ns: the helper hands back the answer.

| Group | What to look for |
|---|---|
| 0 clock and reset | `cfu.clk_i`: the drum beat, one tick every 10 ns. `cfu.rstn_i` stays high: the design is out of reset (the testbench releases it after 600 ns). |
| 1 CFU inputs | `cfu.start_i` jumps up for one tick and `helper.instruction` says DOT4ACC. `cfu.rs1_i` (6226f40a) is four weights packed side by side: 10, -12, 38, 98. `cfu.rs2_i` (cbef06ce) is four inputs: -50, 6, -17, -53. The weight and input rows change one tick after "go", because the helper first copies them into its notepad. |
| 2 lane products | 10 x -50 = -500, -12 x 6 = -72, 38 x -17 = -646, 98 x -53 = -5,194. `cfu.dot4` is -6,412. |
| 3 accumulator | Before: -3,113 (the neuron's starting number, its "bias"). After the answer: -3,113 + -6,412 = -9,525. |
| 4 result | `cfu.valid_o` is high for exactly one tick at the second marker, and `cfu.result_o` shows -9,525. `helper.ticks_since_go` counts 1, 2: two ticks from go to answer. |
| 5 CPU | `ctrl.exec.state` shows `S_ALU_WAIT`: the brain waits at address 0x2ac while the helper works, then moves on. `irq_mei` stays off here. |

## Picture 4: the slowest doorbell while the network runs (`irqdot4`, XSim)

Screenshot: `xsim_irqdot4_worst_dot4_interrupt.png`. While the brain ran the network over all 64 test inputs, the doorbell rang 19,175 times, and every doorbell answer used the math helper and saved its running total. This is the slowest answer of all: 74 ticks.

Three markers:
* **A irq** (27,353,955 ns): the first clock tick that sees the doorbell. The stopwatch starts here.
* **B entry +74** (27,354,695 ns): the brain has finished the first instruction of its answer. The stopwatch stops. From A to B is 740 ns, 74 ticks of 10 ns, the same number the stopwatch logged.
* There is also a **C bound +133** marker at A + 133 ticks (the allowed time), off to the right of this zoom. Scroll right to see it.

| Group | What to look for |
|---|---|
| 0 clock and reset | `clk`: one tick every 10 ns. `rstn` stays high: the design is out of reset (the testbench releases it after 600 ns). |
| 1 interrupt request | `irq_mei` goes high just before A; the brain notices it in the next ticks. |
| 2 execute | The brain is returning from the previous answer (`ctrl.exec.pc` 0x814, `mret`) and then reaches 0x412, a jump back to 0x2d2 inside the network's loop; that jump takes 25 ticks to finish (`ctrl.exec.state` sits in `S_DISPATCH` while code arrives). The `cfu.start_i` and `cfu.valid_o` rows stay flat between A and B: the helper is not part of this slowest answer (their blink just after B is the answer's own GETACC). |
| 3 trap entry | `p_ic_stb` and `p_ic_ack`: between A and B the cache fetches 48 words of code from memory, three 64-byte lines, in 48 of the 74 ticks (`sim/logs/count_ic_irqdot4.log`). `ctrl.irq_fire[0]` and `ctrl.env_enter` are the moment the brain decides to answer; `trace.intr` marks the answer. |
| 4 latency monitor | `mon.pend` is high from A to B and `mon.cnt` counts the ticks. At B, `smp_valid` blinks and `smp_lat` changes from 15 (the answer before) to 74; `mon.st_max` becomes 74. |
| 5 gate | `mon.bound` is 133. 74 is less, so the `viol` stays low and `mon.st_nviol` stays 0. |

**Why the stopwatch count says 73 at B, not 74.** The stopwatch count starts at 0 on the first tick after A, so after 74 ticks it shows 73. When it saves the answer it adds 1 (`lat_v := cnt + 1` in `rtl/irq_lat_mon.vhd`). So "73" on the count row and "74" on the measured row are the same answer. The check file `scripts/wave_views/int8irq_irqdot4_check.txt` records both: `stopwatch=73`, then `smp_lat=74`.

## Picture 5: the slowest doorbell that landed on a math-helper job (`irqcfu`, XSim)

Screenshot: `xsim_irqcfu_worst_interrupt_in_dot4acc.png`. Same rows as picture 4. For 2,674 of the 19,175 doorbells, the last instruction the brain finished before its answer was a helper job (`fired_pc` in `sim/run_dot4_getacc/irq_pc.csv`); this is the slowest of them, 50 ticks (markers A at 32,474,745 ns and B at 32,475,245 ns). The helper job is at address 0x3ee.

What to look for:
* At A the brain is still returning from the previous answer (`ctrl.exec.pc` 0x814, `ctrl.exec.ir` 30200073 = `mret`) and waits while the cache brings the code at 0x3ee (`p_ic_stb`, `p_ic_ack`). The helper job has not started yet.
* The brain takes an interrupt only while an instruction executes (`irq_fire` in `neorv32/rtl/core/neorv32_cpu_control.vhd`, state `S_EXECUTE`). So the first instruction back, the helper job at 0x3ee, runs first: `ctrl.irq_fire[0]` blinks as it starts, `cfu.start_i` blinks and `cfu.valid_o` follows 2 ticks later. The brain never leaves a job half done; only then does `ctrl.env_enter` blink in group 3.
* Between A and B the cache spends 26 ticks fetching code from memory (`sim/logs/count_ic_irqcfu.log`). The helper job itself costs 3 ticks more than a simple instruction would (5 ticks instead of 2 to finish).
* `mon.cnt` shows 49 at B and `smp_lat` changes from 35 (the answer before) to 50. `mon.st_max` shows 74 here because picture 4's answer came earlier in the run.

## Picture 6: the running total is saved and put back (`getacc`, XSim)

Screenshot: `xsim_getacc_save_restore.png`. The same doorbell as picture 5, followed through the whole answer until the brain is back in the network. Groups: 0 clock and reset, 1 interrupt and latency (`irq_mei`, `trace.intr`, `smp_lat`), 2 execute (addresses), 3 CFU (`cfu.start_i`, `helper.instruction`, `cfu.rs1_i`, `cfu.valid_o`, `cfu.result_o`), 4 accumulator and stack copy (`cfu.acc`, `trace.mem_wdata`, `trace.mem_rdata`).

Four markers, C to F (from `scripts/wave_views/int8irq_getacc_check.txt`). Markers A and B of this doorbell are in picture 5; here they would sit too close to C for the labels to fit.
* The yellow cursor at the left (32,475,245 ns) is B of picture 5: the answer starts. The helper job at 0x3ee has just finished, and the running total is 6 (it was -21 before that job).
* **C GETACC** (32,475,345 ns): `helper.instruction` shows GETACC, and 2 ticks later `cfu.result_o` is 6 while the running total stays 6. The next instruction stores that 6 on the stack (`trace.mem_wdata` 00000006). The memory rows and `cfu.rs1_i` are in hex, so a stack address reads 80001f38, not a negative number.
* **D SETACC 0** (32,475,615 ns): the doorbell answer uses the helper itself. SETACC with 0 sets the running total to 0. Without the copy, this is the moment the network's answer would be lost.
* **E SETACC t0** (32,475,855 ns): SETACC with the saved 6 sets the running total back to 6: `cfu.result_o` and `cfu.acc` go from 0 to 6. The load that brings the 6 back from the stack lasts one tick, too short to read on `trace.mem_rdata` at this zoom; the check file records `rs1=6` at E.
* **F back** (32,476,315 ns): the first instruction back in the network, at 0x3f2, with the running total 6. The next DOT4ACC adds to 6, as if the doorbell had never rung.

Saving and restoring costs 4 instructions and about 20 ticks per doorbell answer.

## Picture 7: the "too slow" example (`fail`, XSim)

Screenshot: `xsim_fail_gate_failure.png`. This is the deliberate mistake, from the stopwatch project's test program: the program keeps the doorbell switched off twice as long (CRIT_N = 100). It shows the first answer that was too slow.

* Marker A (19,181,615 ns) is the doorbell, marker **C bound +521** is where the allowed time runs out, and marker B (19,190,665 ns) is the answer, 905 ticks after A. C comes before B.
* The `ctrl.exec.state` and address rows are packed tight: the brain runs a small loop many times with the doorbell switched off.
* At B, the `viol` goes high and stays high, `mon.st_nviol` goes from 0 to 1, `mon.st_max` jumps from 447 to 905, and `mon.cnt` shows 904 (905 minus 1, as before).
* This is the same failure that makes the gate script print GATE FAIL. Later in that run one answer took 918 ticks, the run's worst.

## The test screenshots

The screenshots in `docs/gui_test_screenshots/` were taken on test screens without a window manager, one window per screen, so each window is smaller than on a normal screen and the block design's Diagram is small. On your screen, maximise the window and use "Fit View" as in picture 1. The pictures from before GETACC are kept in `archive_pre_getacc_21oct/docs/gui_test_screenshots/`.

## Tips

* To make the waves wider, double-click the waveform tab title so it fills the window.
* Each view opens zoomed so that all its markers are in frame (getacc: A to F, 32,474,665 to 32,476,415 ns). After zooming in, reopen the window with `scripts/open_view.sh <view>` to get that framing back.
* To read a value at one moment, click in the wave area: the yellow cursor moves there and the Value column shows every row at that time.
* Every number in this guide comes from the check files in `scripts/wave_views/` and the logs in `sim/logs/`.
