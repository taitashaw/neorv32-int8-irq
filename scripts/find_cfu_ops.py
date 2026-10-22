#!/usr/bin/env python3
"""List CFU operations (start_i edges) from a VCD of the CFU ports: time of the clock
edge that samples start_i = 1, kind, rs1, rs2, and the time valid_o is first sampled 1.
usage: find_cfu_ops.py <vcd> <rs1_hex filter or 'all'> [max]"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vcd_trace import parse_vcd, to_int
ch = parse_vcd(sys.argv[1]); flt = sys.argv[2].lower(); mx = int(sys.argv[3]) if len(sys.argv) > 3 else 20
cur, prev_clk, out, pend = {}, '0', [], None
i = 0
while i < len(ch):
    t = ch[i][0]; before = dict(cur)
    while i < len(ch) and ch[i][0] == t:
        cur[ch[i][1]] = ch[i][2]; i += 1
    if cur.get('clk') == '1' and prev_clk == '0':
        s = before
        if pend is not None and s.get('valid_o') == '1':
            pend.append(t // 1000); out.append(pend); pend = None
        if s.get('start_i') == '1':
            kind = 'DOT4ACC' if s.get('is_dot4') == '1' else ('SETACC' if s.get('is_setacc') == '1' else 'OTHER')
            pend = [t // 1000, kind, f"{to_int(s.get('rs1_i')):08x}", f"{to_int(s.get('rs2_i')):08x}", f"{to_int(s.get('acc')) or 0:08x}"]
    prev_clk = cur.get('clk', prev_clk)
n = 0
for o in out:
    if flt == 'all' or o[2] == flt:
        print(f"edge sampling start at {o[0]} ns: {o[1]} rs1={o[2]} rs2={o[3]} acc_before={o[4]} valid sampled at {o[5]} ns ({(o[5]-o[0])//10} cycles)")
        n += 1
        if n >= mx: break
