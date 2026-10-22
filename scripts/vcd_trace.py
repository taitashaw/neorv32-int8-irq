#!/usr/bin/env python3
"""Cycle-by-cycle view of interrupts in an XSim VCD dump (hand cross-check).

For every request edge on irq_mei found in the VCD, prints one row per rising
clock edge from 2 cycles before the edge to the monitor's sample output, using
the values each edge samples (the values just before the edge). Also prints the
latency counted by hand from the rows and the monitor's own value.

usage: vcd_trace.py <file.vcd> [max_events] [csv_out]
"""
import sys


def parse_vcd(path):
    ids, vals, changes = {}, {}, []
    scope = []
    with open(path) as f:
        defs = True
        t = 0
        for line in f:
            line = line.strip()
            if not line:
                continue
            if defs:
                if line.startswith('$scope'):
                    scope.append(line.split()[2])
                elif line.startswith('$upscope'):
                    scope.pop()
                elif line.startswith('$var'):
                    p = line.split()
                    ids.setdefault(p[3], p[4])
                elif line.startswith('$enddefinitions'):
                    defs = False
                continue
            if line[0] == '#':
                t = int(line[1:])
            elif line[0] in '01xzXZUuWwLlHh-':
                changes.append((t, ids.get(line[1:]), line[0]))
            elif line[0] == 'b':
                v, i = line[1:].split()
                changes.append((t, ids.get(i), v))
    return changes


def to_int(v):
    try:
        return int(v, 2)
    except (ValueError, TypeError):
        return None


def main():
    path = sys.argv[1]
    max_ev = int(sys.argv[2]) if len(sys.argv) > 2 else 99
    changes = parse_vcd(path)
    cur, samples = {}, []
    # build per-edge samples: the value of every signal just before each clk rising edge
    i = 0
    clk_prev = '0'
    while i < len(changes):
        t = changes[i][0]
        batch = []
        while i < len(changes) and changes[i][0] == t:
            batch.append(changes[i])
            i += 1
        before = dict(cur)
        for _, n, v in batch:
            cur[n] = v
        if cur.get('clk') == '1' and clk_prev == '0':
            samples.append((t, before))
        clk_prev = cur.get('clk', clk_prev)

    cols = ['irq_mei', 'pnd', 'buf', 'fire', 'env_pend', 'trap', 'dispatch', 'exec',
            'fe_valid', 'ic_stb', 'ic_ack', 'tr_valid', 'tr_intr', 'pc_cur', 'smp_valid', 'smp_lat']
    out = []
    n_ev = 0
    k = 0
    while k < len(samples) and n_ev < max_ev:
        t, s = samples[k]
        prev = samples[k - 1][1] if k else {}
        if s.get('irq_mei') == '1' and prev.get('irq_mei') == '0':
            n_ev += 1
            k0 = k
            print(f"\n=== request edge at t={t/1000:.0f} ns (edge k) ===")
            print('rel ' + ' '.join(f"{c:>8}" for c in cols))
            j = max(0, k - 2)
            resp_rel = None
            while j < len(samples):
                tj, sj = samples[j]
                if j > k0 and tj - samples[j - 1][0] > 10000:  # VCD window ended (gap > 1 cycle)
                    print("window ended before the response; event skipped")
                    break
                pnd = to_int(sj.get('irq_pnd'))
                buf = to_int(sj.get('irq_buf'))
                row = {
                    'irq_mei': sj.get('irq_mei'), 'pnd': (pnd >> 2) & 1 if pnd is not None else '?',
                    'buf': (buf >> 2) & 1 if buf is not None else '?',
                    'fire': to_int(sj.get('irq_fire')), 'env_pend': sj.get('env_pend'),
                    'trap': sj.get('p_trap'), 'dispatch': sj.get('p_dispatch'), 'exec': sj.get('p_exec'),
                    'fe_valid': sj.get('p_fe_valid'), 'ic_stb': sj.get('p_ic_stb'), 'ic_ack': sj.get('p_ic_ack'),
                    'tr_valid': sj.get('p_tr_valid'), 'tr_intr': sj.get('p_tr_intr'),
                    'pc_cur': '%08x' % to_int(sj.get('p_pc_cur')) if to_int(sj.get('p_pc_cur')) is not None else '?',
                    'smp_valid': sj.get('smp_valid'), 'smp_lat': to_int(sj.get('smp_lat')),
                }
                rel = j - k0
                print(f"{rel:3d} " + ' '.join(f"{str(row[c]):>8}" for c in cols))
                out.append([n_ev, rel] + [row[c] for c in cols])
                if resp_rel is None and rel > 0 and row['tr_valid'] == '1' and row['tr_intr'] == '1':
                    resp_rel = rel
                if row['smp_valid'] == '1' and rel > 0:
                    print(f"hand count: response (trace valid=1 intr=1) sampled at edge k+{resp_rel}"
                          f" -> latency {resp_rel} cycles; monitor reported {row['smp_lat']}"
                          f" -> {'MATCH' if resp_rel == row['smp_lat'] else 'MISMATCH'}")
                    break
                j += 1
                if rel > 700:
                    print("no response within 700 cycles of this window")
                    break
            k = j
        k += 1
    if len(sys.argv) > 3:
        with open(sys.argv[3], 'w') as f:
            f.write('event,rel,' + ','.join(cols) + '\n')
            for r in out:
                f.write(','.join(str(x) for x in r) + '\n')


if __name__ == '__main__':
    main()
