#!/usr/bin/env python3
"""Worst-case interrupt-latency gate.

Reads the XSim console log (IRQLAT lines printed by the program from the
hardware monitor registers) and the testbench per-sample CSV, then checks per
scenario:
  1. the scenario ran, the monitor counted at least N_IRQ samples, no orphan
     responses and no overruns
  2. the bound the program loaded into the monitor equals scripts/bounds.json
  3. hardware statistics (count, min, max, sum, histogram) equal the values
     recomputed from the per-sample CSV (checks the monitor's own arithmetic)
  4. measured worst case <= bound                       -> PASS, else FAIL
It also checks that the VHDL assertion gate fired exactly for the scenarios
whose hardware violation counter is non-zero.

usage: gate.py <xsim_console.log> <irq_samples.csv> <bounds.json>
exit code 0 = PASS, 1 = FAIL
"""
import csv
import json
import re
import sys
from collections import defaultdict


def main():
    log_path, csv_path, bounds_path = sys.argv[1:4]
    bounds = {k: v for k, v in json.load(open(bounds_path)).items() if not k.startswith('_')}
    log = open(log_path, errors='replace').read()

    m = re.search(r'IRQLAT start N_IRQ=(\d+) CRIT_N=(\d+)', log)
    n_irq, crit_n = (int(m.group(1)), int(m.group(2))) if m else (None, None)
    hw = {}
    for line in log.splitlines():
        if line.startswith('IRQLAT id='):
            kv = dict(re.findall(r'(\w+)=([^ ]+)', line))
            kv['hist'] = [int(x) for x in kv['hist'].split(':')]
            hw[kv['name']] = kv
    tb_fail = defaultdict(int)
    for t in re.findall(r'\[TB:GATE\] FAIL: interrupt latency above bound, tag=(\d+)', log):
        tb_fail[int(t)] += 1

    samples = defaultdict(list)
    for r in csv.DictReader(open(csv_path)):
        samples[int(r['tag'])].append(int(r['latency']))

    print(f"gate: log={log_path}")
    print(f"gate: N_IRQ={n_irq} CRIT_N={crit_n}")
    print(f"{'scenario':8} {'n':>5} {'min':>5} {'max':>5} {'mean':>8} {'bound':>6} {'headroom':>8}  result")
    overall = True
    notes = []
    for name, bound in bounds.items():
        if name not in hw:
            print(f"{name:8} missing from log -> FAIL")
            overall = False
            continue
        h = hw[name]
        tag = int(h['id'])
        n, lo, hi, sm = int(h['n']), int(h['min']), int(h['max']), int(h['sum'])
        ok = True
        # 1. coverage and error counters
        if n_irq is not None and n < n_irq:
            ok = False; notes.append(f"{name}: only {n} samples, expected >= {n_irq}")
        if int(h['orphan']) or int(h['overrun']):
            ok = False; notes.append(f"{name}: orphan={h['orphan']} overrun={h['overrun']}")
        # 2. bound loaded into hardware equals the bounds file
        if int(h['bound']) != bound:
            ok = False; notes.append(f"{name}: hardware bound {h['bound']} != bounds.json {bound}")
        # 3. hardware statistics equal the per-sample CSV
        s = samples.get(tag, [])
        shift = int(h['shift'])
        hist = [0] * 16
        for v in s:
            hist[min(v >> shift, 15)] += 1
        if (len(s), min(s, default=-1), max(s, default=-1), sum(s), hist) != (n, lo, hi, sm, h['hist']):
            ok = False; notes.append(f"{name}: hardware statistics differ from the per-sample CSV")
        # VHDL assertion gate consistency
        nviol = int(h['nviol'])
        if (nviol > 0) != (tb_fail.get(tag, 0) > 0):
            ok = False; notes.append(f"{name}: hardware nviol={nviol} but TB assertion count={tb_fail.get(tag, 0)}")
        # 4. the gate itself
        within = hi <= bound
        res = 'PASS' if (within and ok) else 'FAIL'
        if not within:
            notes.append(f"{name}: worst case {hi} cycles exceeds bound {bound} by {hi - bound} "
                         f"({nviol} of {n} samples above the bound)")
        overall &= (within and ok)
        print(f"{name:8} {n:5d} {lo:5d} {hi:5d} {sm / n:8.2f} {bound:6d} {bound - hi:8d}  {res}")
    for x in notes:
        print("note: " + x)
    print("GATE " + ("PASS" if overall else "FAIL"))
    return 0 if overall else 1


if __name__ == '__main__':
    sys.exit(main())
