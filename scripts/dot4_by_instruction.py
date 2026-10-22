#!/usr/bin/env python3
"""DOT4 scenario samples grouped by code region and by the kind of instruction the
interrupt fired in (from the testbench's irq_pc.csv and the program disassembly).
usage: dot4_by_instruction.py <irq_pc.csv> <disasm.txt>"""
import csv, re, sys, collections
dis, fn, cur = {}, {}, '?'
for l in open(sys.argv[2]):
    m = re.match(r'^([0-9a-f]+) <(.+)>:', l)
    if m: cur = m.group(2); continue
    m = re.match(r'\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.*)', l)
    if m:
        a = int(m.group(1), 16); dis[a] = m.group(2).split('#')[0].strip(); fn[a] = cur
rows = list(csv.DictReader(open(sys.argv[1])))
def kind(a):
    s = dis.get(a, '?')
    if s.startswith('.insn'): return 'CFU (DOT4ACC or SETACC)'
    op = s.split()[0]
    if op in ('lw', 'lb', 'lbu', 'lh', 'lhu'): return 'load'
    if op in ('sw', 'sb', 'sh'): return 'store'
    if op.startswith('mul'): return 'multiply'
    if op.startswith('b') or op in ('j', 'jal', 'jalr', 'ret'): return 'branch or jump'
    if op.startswith('csr'): return 'CSR access'
    return 'ALU or other'
def stats(name, s):
    L = [int(r['latency']) for r in s]; Dr = [int(r['drain']) for r in s]; T = [int(r['fired_instr_cycles']) for r in s]
    E = [a - b for a, b in zip(L, Dr)]
    print(f"| {name} | {len(s)} | {min(L)} | {sum(L)/len(L):.2f} | {max(L)} | {max(Dr)} | {max(E)} | {max(T)} |")
for tag, title in (('6', 'DOT4'), ('7', 'DOT4BB')):
    s = [r for r in rows if r['tag'] == tag]
    if not s: continue
    print(f"\n{title}: by function (where the interrupt fired)")
    print("| function | n | min | mean | max | max drain | max entry | max cycles of the fired instruction |")
    print("|---|---|---|---|---|---|---|---|")
    g = collections.defaultdict(list)
    for r in s: g[fn.get(int(r['fired_pc'], 16), '?')].append(r)
    for k in sorted(g, key=lambda k: -len(g[k])): stats(k, g[k])
    print(f"\n{title}: by kind of fired instruction")
    print("| kind | n | min | mean | max | max drain | max entry | max cycles of the fired instruction |")
    print("|---|---|---|---|---|---|---|---|")
    g = collections.defaultdict(list)
    for r in s: g[kind(int(r['fired_pc'], 16))].append(r)
    for k in sorted(g, key=lambda k: -len(g[k])): stats(k, g[k])
    c = [r for r in s if kind(int(r['fired_pc'], 16)).startswith('CFU')]
    if c:
        cc = collections.Counter(int(r['fired_instr_cycles']) for r in c)
        print(f"\n{title}: commit-to-commit cycles of the fired CFU instruction: {sorted(cc.items())}")
