#!/usr/bin/env python3
"""Per-instruction cycle counts from a VCD dump that has the probe signals.
Duration of an instruction = clock edges between the trace commit of the previous
instruction and its own trace commit (includes its fetch wait, execute and
memory/ALU wait states). Prints min/max per instruction address.
usage: instr_cycles.py <file.vcd>"""
import sys, collections
sys.path.insert(0, __import__('os').path.dirname(__file__))
from vcd_trace import parse_vcd, to_int
ch = parse_vcd(sys.argv[1])
cur, prev_clk, edges = {}, '0', []
i = 0
while i < len(ch):
    t = ch[i][0]; before = dict(cur)
    while i < len(ch) and ch[i][0] == t:
        cur[ch[i][1]] = ch[i][2]; i += 1
    if cur.get('clk') == '1' and prev_clk == '0':
        edges.append((t, before))
    prev_clk = cur.get('clk', prev_clk)
last = None; d = collections.defaultdict(list)
for n, (t, s) in enumerate(edges):
    if n and t - edges[n-1][0] > 10000:
        last = None  # window gap
    if s.get('p_tr_valid') == '1':
        pc = to_int(s.get('p_tr_pc'))
        if last is not None and s.get('p_tr_intr') != '1':
            d[pc].append(n - last)
        last = n
for pc in sorted(d):
    v = d[pc]
    print(f"pc=0x{pc:08x} n={len(v):4d} min={min(v):3d} max={max(v):3d} common={collections.Counter(v).most_common(3)}")
