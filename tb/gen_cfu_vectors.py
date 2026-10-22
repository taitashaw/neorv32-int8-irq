#!/usr/bin/env python3
"""Reference vectors for the INT8 CFU unit testbench (tb/tb_cfu_int8.vhd).
Line format (hex, 32-bit): <op> <rs1> <rs2> <expected rd>
op: 0 = DOT4ACC, 1 = SETACC, 7 = illegal encoding (expects no valid pulse; acc unchanged).
The reference model is plain Python integers, independent of the VHDL."""
import random
random.seed(20261020)
M = 1 << 32
def lanes(w):
    return [((w >> (8 * i)) & 0xff) - (256 if (w >> (8 * i)) & 0x80 else 0) for i in range(4)]
def pack(l):
    return sum((v & 0xff) << (8 * i) for i, v in enumerate(l))
acc = 0
out = []
def emit(op, a, b):
    global acc
    if op == 0:
        acc = (acc + sum(x * y for x, y in zip(lanes(a), lanes(b)))) % M
        out.append((0, a, b, acc))
    elif op == 1:
        acc = a % M
        out.append((1, a, b, acc))
    else:
        out.append((7, a, b, acc))
# directed
emit(1, 0, 0)
emit(0, pack([-128] * 4), pack([-128] * 4))            # +65536
emit(0, pack([127] * 4), pack([-128] * 4))             # -65024
emit(0, pack([-128, 127, 0, 1]), pack([127, -128, 5, -1]))
emit(0, 0, 0)
emit(0, 0xffffffff, 0xffffffff)                         # 4 * (-1 * -1) = 4
emit(0, 0x01020304, 0x05060708)
emit(1, 0x7ffffff0, 0)
emit(0, pack([-128] * 4), pack([-128] * 4))            # wraps past 2^31 - 1
emit(1, 0x80000005, 0)
emit(0, pack([127] * 4), pack([-128] * 4))             # wraps below -2^31
emit(7, 0x12345678, 0x9abcdef0)                        # illegal: acc must stay
emit(0, pack([1, 0, 0, 0]), pack([1, 0, 0, 0]))
emit(1, 0xdeadbeef, 0x55555555)                        # rs2 ignored by SETACC
for i in range(256):                                    # every lane-0 value times -128 and 127
    emit(1, 0, 0)
    emit(0, pack([i - 128, 0, 0, 0]), pack([-128, 0, 0, 0]))
    emit(0, pack([0, 0, 0, i - 128]), pack([0, 0, 0, 127]))
# random
for i in range(20000):
    r = random.random()
    a = random.getrandbits(32); b = random.getrandbits(32)
    emit(1 if r < 0.08 else (7 if r < 0.09 else 0), a, b)
with open('../neorv32-int8-cfu/tb/cfu_vectors.txt', 'w') as f:
    for op, a, b, e in out:
        f.write(f'{op:x} {a:08x} {b:08x} {e:08x}\n')
print(len(out), 'vectors;', sum(1 for o in out if o[0] == 0), 'DOT4ACC,', sum(1 for o in out if o[0] == 1), 'SETACC,', sum(1 for o in out if o[0] == 7), 'illegal')
