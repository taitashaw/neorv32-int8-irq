#!/usr/bin/env python3
"""Cycle-accounting constants for the DOT4 bounds, read from the smoke-run VCD windows
(sim/run_vcd_dot4_smoke/dot4_smoke.vcd) BEFORE the final run:
  T  = longest commit-to-commit time of one instruction in the code that runs while the
       generator is on, per scenario (instr_cycles_dot4_smoke_*.txt), and which instruction
  R  = longest i-cache line refill seen (first i-cache bus strobe to last ack of one burst)
  CFU instruction time and CFU start-to-done gap
usage: dot4_constants.py <vcd> <disasm.txt> <w2_file> <w3_file>"""
import sys, re, os, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vcd_trace import parse_vcd
vcd, disf, w2, w3 = sys.argv[1:5]
func = {}
cur = None
for l in open(disf):
    m = re.match(r'^([0-9a-f]+) <(.+)>:', l)
    if m: cur = m.group(2); continue
    m = re.match(r'\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.*)', l)
    if m: func[int(m.group(1), 16)] = cur
def tmax(path, funcs):
    best = (0, None, None)
    for l in open(path):
        m = re.match(r'pc=0x([0-9a-f]+) (.*?)\s+n=\s*(\d+) min=\s*(\d+) max=\s*(\d+)', l)
        if not m: continue
        pc = int(m.group(1), 16)
        if func.get(pc) in funcs and int(m.group(5)) > best[0]:
            best = (int(m.group(5)), pc, m.group(2).strip())
    return best
print("T DOT4   (infer, run_pass, main, irq_entry; window W2):", tmax(w2, {'infer.constprop.0', 'run_pass', 'main', 'irq_entry'}))
print("T DOT4BB (loop_dot4bb, irq_entry; window W3):         ", tmax(w3, {'loop_dot4bb', 'irq_entry'}))
# refill bursts and CFU start/done gaps
ch = parse_vcd(vcd)
curv, prev_clk, n = {}, '0', 0
burst = None; bursts = []; gaps = collections.Counter(); cfu_start = None
i = 0
while i < len(ch):
    t = ch[i][0]; before = dict(curv)
    while i < len(ch) and ch[i][0] == t:
        curv[ch[i][1]] = ch[i][2]; i += 1
    if curv.get('clk') == '1' and prev_clk == '0':
        n += 1
        s = before
        if s.get('p_ic_stb') == '1':
            if burst is None or n - burst[1] > 3:
                if burst: bursts.append(burst[1] - burst[0] + 1)
                burst = [n, n]
        if s.get('p_ic_ack') == '1' and burst is not None:
            burst[1] = n
        if s.get('p_cfu_start') == '1': cfu_start = n
        if s.get('p_cfu_done') == '1' and cfu_start is not None:
            gaps[n - cfu_start] += 1; cfu_start = None
    prev_clk = curv.get('clk', prev_clk)
if burst: bursts.append(burst[1] - burst[0] + 1)
c = collections.Counter(bursts)
print("i-cache refill bursts (first strobe to last ack, cycles): ", sorted(c.items()))
print("CFU start to done (cycles):", sorted(gaps.items()))
