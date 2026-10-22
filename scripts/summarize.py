#!/usr/bin/env python3
"""Per-scenario summary of the per-sample CSV: latency stats and the drain/entry split.
usage: summarize.py <irq_samples.csv>"""
import csv, sys, collections, statistics
N = ['BASE', 'DIV', 'LDST', 'CRIT', 'B2B', 'ICOLD', 'DOT4', 'DOT4BB']  # tags 6, 7 added for the combined design
by = collections.defaultdict(list)
for r in csv.DictReader(open(sys.argv[1])):
    by[int(r['tag'])].append({k: int(v) for k, v in r.items()})
print("| scenario | n | min | median | mean | p99 | max | max drain | max entry | most common entry values (cycles: count) |")
print("|---|---|---|---|---|---|---|---|---|---|")
for t, v in sorted(by.items()):
    L = sorted(r['latency'] for r in v)
    ent = collections.Counter(r['entry'] for r in v).most_common(4)
    print(f"| {N[t]} | {len(L)} | {L[0]} | {statistics.median(L):g} | {sum(L)/len(L):.2f} | {L[int(0.99*len(L))-1]} | {L[-1]} | "
          f"{max(r['drain'] for r in v)} | {max(r['entry'] for r in v)} | {', '.join(f'{a}: {b}' for a, b in ent)} |")
