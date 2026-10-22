#!/usr/bin/env python3
"""Condense vcd_trace.py CSV rows into per-event phase markers (edge offsets from the request edge k).
usage: phase_summary.py <vcd_trace_rows.csv> <disasm.txt>"""
import csv, sys, re, collections
dis = {}
for l in open(sys.argv[2]):
    m = re.match(r'\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.*)', l)
    if m: dis[int(m.group(1), 16)] = m.group(2).split('#')[0].split('<')[0].strip()
ev = collections.defaultdict(list)
for r in csv.DictReader(open(sys.argv[1])):
    ev[int(r['event'])].append(r)
def name(pc):
    try: p = int(pc, 16)
    except ValueError: return pc
    return f"0x{p:x} {dis.get(p, '(not in table)')}"
for e, rows in ev.items():
    rows = [r for r in rows if int(r['rel']) >= 0]
    def first(cond):
        for r in rows:
            if cond(r): return int(r['rel'])
        return None
    k_pc = rows[0]['pc_cur']
    buf = first(lambda r: r['buf'] == '1')
    fire = first(lambda r: r['fire'] not in ('0', 'None'))
    fire_pc = next((r['pc_cur'] for r in rows if int(r['rel']) == fire), '?')
    pend = first(lambda r: r['env_pend'] == '1')
    trap = first(lambda r: r['trap'] == '1')
    hexec = first(lambda r: r['exec'] == '1' and trap is not None and int(r['rel']) > trap)
    resp = first(lambda r: r['tr_valid'] == '1' and r['tr_intr'] == '1')
    stb = [int(r['rel']) for r in rows if r['ic_stb'] == '1']
    # group i-cache bus strobes into bursts
    bursts, cur = [], None
    for s in stb:
        if cur and s - cur[1] <= 3: cur[1] = s
        else:
            cur = [s, s]; bursts.append(cur)
    print(f"event {e}: in progress at k: {name(k_pc)} | irq_buf=1 at k+{buf} | fired at k+{fire} in EXECUTE of {name(fire_pc)}"
          f" | env_pend k+{pend} | trap entry k+{trap} | handler EXECUTE k+{hexec} | response k+{resp}"
          f" | i-cache bus strobes (refills) {['k+%d..k+%d' % tuple(b) for b in bursts]}")
