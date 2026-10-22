#!/usr/bin/env python3
"""Group interrupt samples by the instruction they fired in.
Reads the testbench's second CSV (irq_pc.csv: tag, latency, drain, fired_pc,
fired_instr_cycles, handler_pc, time_ns) and a disassembly (objdump -d), and prints
per fired instruction: count, latency min/max, drain max, entry max.
usage: pc_summary.py <irq_pc.csv> <disasm.txt> [tag]"""
import csv, re, sys, collections
rows = list(csv.DictReader(open(sys.argv[1])))
tag = sys.argv[3] if len(sys.argv) > 3 else None
dis, func = {}, {}
cur = '?'
for line in open(sys.argv[2]):
    m = re.match(r'^([0-9a-f]+) <(.+)>:', line)
    if m: cur = m.group(2); continue
    m = re.match(r'^\s+([0-9a-f]+):\s+[0-9a-f]+\s+(.*)$', line)
    if m:
        a = int(m.group(1), 16); dis[a] = m.group(2).split('#')[0].strip(); func[a] = cur
g = collections.defaultdict(list)
for r in rows:
    if tag is not None and r['tag'] != tag: continue
    pc = int(r['fired_pc'], 16)
    g[pc].append((int(r['latency']), int(r['drain'])))
tot = sum(len(v) for v in g.values())
print(f"samples: {tot}")
print(f"{'pc':>10} {'function':24} {'instruction':34} {'n':>6} {'Lmin':>5} {'Lmax':>5} {'drain max':>9} {'entry max':>9}")
for pc in sorted(g, key=lambda p: -max(l for l, d in g[p])):
    v = g[pc]
    print(f"0x{pc:08x} {func.get(pc,'?')[:24]:24} {dis.get(pc,'?')[:34]:34} {len(v):6d} {min(l for l,d in v):5d} {max(l for l,d in v):5d} {max(d for l,d in v):9d} {max(l-d for l,d in v):9d}")
