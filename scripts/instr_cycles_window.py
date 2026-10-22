#!/usr/bin/env python3
"""Per-instruction commit-to-commit cycle counts from a VCD with the probe signals,
restricted to one time window (copy of the profiler's instr_cycles.py with a window).
Duration of an instruction = clock edges between the trace commit of the previous
instruction and its own commit (fetch wait, execute, memory/ALU/CFU wait states).
The first handler instruction (intr = 1) is not counted (that time is the
interrupt latency itself); every other instruction, handler included, is.
usage: instr_cycles_window.py <file.vcd> <t_start_ns> <t_end_ns> [disasm.txt]"""
import sys, re, collections, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vcd_trace import parse_vcd, to_int
ch = parse_vcd(sys.argv[1]); t0 = int(sys.argv[2]) * 1000; t1 = int(sys.argv[3]) * 1000
dis = {}
if len(sys.argv) > 4:
    for l in open(sys.argv[4]):
        m = re.match(r'\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.*)', l)
        if m: dis[int(m.group(1), 16)] = m.group(2).split('#')[0].split('<')[0].strip()
cur, prev_clk, edges = {}, '0', []
i = 0
while i < len(ch):
    t = ch[i][0]; before = dict(cur)
    while i < len(ch) and ch[i][0] == t:
        cur[ch[i][1]] = ch[i][2]; i += 1
    if cur.get('clk') == '1' and prev_clk == '0' and t0 <= t <= t1:
        edges.append((t, before))
    prev_clk = cur.get('clk', prev_clk)
last = None; d = collections.defaultdict(list)
for n, (t, s) in enumerate(edges):
    if n and t - edges[n-1][0] > 10000:
        last = None
    if s.get('p_tr_valid') == '1':
        pc = to_int(s.get('p_tr_pc'))
        if s.get('p_tr_intr') == '1':
            last = n; continue
        if last is not None:
            d[pc].append(n - last)
        last = n
print(f"window {sys.argv[2]} to {sys.argv[3]} ns, {len(edges)} clock edges, {sum(len(v) for v in d.values())} commits")
for pc in sorted(d):
    v = d[pc]
    print(f"pc=0x{pc:08x} {dis.get(pc, ''):28.28} n={len(v):5d} min={min(v):3d} max={max(v):3d} common={collections.Counter(v).most_common(3)}")
