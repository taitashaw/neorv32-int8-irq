#!/usr/bin/env python3
"""Collect LUT/FF/BRAM/DSP, WNS (clock setup and reset recovery separately), WHS and the
CFU and monitor shares from the post-route reports in impl/<tag>_<f>mhz/
(adapted from the profiler project's scripts/impl_table.py)."""
import re, sys, os
B = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'impl')
def util(p):
    t = open(p).read()
    g = lambda pat: float(re.search(pat, t, re.M).group(1))
    return dict(lut=int(g(r'^\| CLB LUTs\s+\|\s+(\d+)')), ff=int(g(r'^\| CLB Registers\s+\|\s+(\d+)')),
                bram=g(r'^\| Block RAM Tile\s+\|\s+([\d.]+)'), dsp=int(g(r'^\| DSPs\s+\|\s+(\d+)')),
                lutram=int(g(r'^\|\s+LUT as Memory\s+\|\s+(\d+)')))
def timing(p):
    t = open(p).read()
    m = re.search(r'WNS\(ns\).*?\n.*?\n\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)\s+(-?[\d.]+)', t)
    met = 'All user specified timing constraints are met.' in t
    c = re.search(r'From Clock:  clk\s+To Clock:  clk\s+Setup :\s+\d+\s+Failing Endpoints,\s+Worst Slack\s+(-?[\d.]+)ns', t)
    a = re.search(r'\*\*async_default\*\*\s+clk\s+clk\s+(-?[\d.]+)', t)
    return dict(wns=float(m.group(1)), tns=float(m.group(2)), whs=float(m.group(5)), met=met,
                clk=float(c.group(1)), asy=float(a.group(1)) if a else None)
def hier(p, key):
    for l in open(p):
        if key in l:
            c = [x.strip() for x in l.split('|')]
            return dict(lut=int(c[3]), lutram=int(c[5]), ff=int(c[7]), dsp=int(c[11]))
    return None
def crit(d):
    p = d + '/vivado_console.log'
    return sum(1 for l in open(p, errors='replace') if l.startswith('CRITICAL WARNING')) if os.path.exists(p) else None
names = {'cfu_mon': 'CPU + 2-stage CFU + monitor (the combined design)',
         'cfu3_mon': 'CPU + 3-stage CFU + monitor (fallback)',
         'nocfu_nomon': 'CPU alone (same configuration, no CFU, no monitor)'}
print("| design | f (MHz) | LUT | of which LUTRAM | FF | BRAM tiles | DSP | WNS (ns) | clock setup slack (ns) | reset recovery slack (ns) | WHS (ns) | met | CFU LUT / FF | monitor LUT / FF | critical warnings |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for tag in ('cfu_mon', 'cfu3_mon', 'nocfu_nomon'):
    for f in (100, 200, 300):
        d = f"{B}/{tag}_{f}mhz"
        if not os.path.exists(d + '/post_route_timing_summary.rpt'):
            continue
        u = util(d + '/post_route_utilization.rpt'); t = timing(d + '/post_route_timing_summary.rpt')
        hc = hier(d + '/post_route_utilization_hier.rpt', 'cpu_alu_cfu_inst')
        hm = hier(d + '/post_route_utilization_hier.rpt', 'mon_inst')
        cs = f"{hc['lut']} / {hc['ff']}" if hc else 'none'
        ms = f"{hm['lut']} / {hm['ff']}" if hm else 'none'
        asy = f"{t['asy']:+.3f}" if t['asy'] is not None else 'n/a'
        print(f"| {names[tag]} | {f} | {u['lut']} | {u['lutram']} | {u['ff']} | {u['bram']:g} | {u['dsp']} | {t['wns']:+.3f} | {t['clk']:+.3f} | {asy} | {t['whs']:+.3f} | {'yes' if t['met'] else 'NO'} | {cs} | {ms} | {crit(d)} |")
