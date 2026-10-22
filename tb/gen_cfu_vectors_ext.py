#!/usr/bin/env python3
"""Reference vectors for the extended INT8 CFU unit testbench (tb/tb_cfu_int8_ext.vhd).

Extends the combined project's tb/gen_cfu_vectors.py (copied in source_copies/tb/) with
GETACC (funct3 = 010) and, for the bank CFU, SELBANK (funct3 = 011, bank in funct7 bit 0).
The reference model is plain Python integers, independent of the VHDL.

Line format (hex, 32-bit fields): <op> <inst> <rs1> <rs2> <expected rd>
  op: 0 = DOT4ACC, 1 = SETACC, 2 = GETACC, 3 = SELBANK, 7 = illegal encoding
      (op 7 expects no valid pulse and no state change; the testbench reads the
      instruction word from the file, so the model alone defines the encodings).

usage: gen_cfu_vectors_ext.py <getacc|bank> <out_file> [<original cfu_vectors.txt>]
Part 1 is the original 20,782-vector sequence (same seed, same order). The only change:
the original illegal encoding "funct3 = 010" is now GETACC, so that illegal slot uses
funct3 = 111 instead. If the original file is given, part 1 is compared with it
(op, rs1, rs2, expected) and the result is printed.
"""
import random, sys

variant = sys.argv[1]
assert variant in ('getacc', 'bank')
out_path = sys.argv[2]
orig_path = sys.argv[3] if len(sys.argv) > 3 else None
BANKS = (variant == 'bank')

M = 1 << 32
OPC_C0, OPC_C1, OPC_C2 = 0x0B, 0x2B, 0x5B

def rtype(f7, f3, opc=OPC_C0, rs2=2, rs1=1, rd=3):
    return ((f7 & 0x7f) << 25) | (rs2 << 20) | (rs1 << 15) | ((f3 & 7) << 12) | (rd << 7) | opc

def lanes(w):
    return [((w >> (8 * i)) & 0xff) - (256 if (w >> (8 * i)) & 0x80 else 0) for i in range(4)]

def pack(l):
    return sum((v & 0xff) << (8 * i) for i, v in enumerate(l))

acc = [0, 0]   # bank 0, bank 1 (bank 1 exists only in the bank CFU)
bank = 0
out = []

def emit(op, a, b, inst=None, bnum=0):
    """op 0..3 legal, 7 illegal (inst must be given for 7)."""
    global bank
    if op == 0:
        acc[bank] = (acc[bank] + sum(x * y for x, y in zip(lanes(a), lanes(b)))) % M
        inst = rtype(0, 0b000) if inst is None else inst
        e = acc[bank]
    elif op == 1:
        acc[bank] = a % M
        inst = rtype(0, 0b001) if inst is None else inst
        e = acc[bank]
    elif op == 2:
        inst = rtype(0, 0b010) if inst is None else inst
        e = acc[bank]
    elif op == 3:
        assert BANKS
        bank = bnum
        inst = rtype(bnum, 0b011)
        e = acc[bank]
    else:
        assert inst is not None
        e = acc[bank]          # don't-care for the testbench (no valid expected)
    out.append((op, inst, a % M, b % M, e))

# ---------------------------------------------------------------- part 1: original sequence
random.seed(20261020)
illegal_kind = [0]
def illegal_orig(a, b):
    k = illegal_kind[0]
    if k == 0:
        inst = rtype(0, 0b111)                       # was funct3 = 010 (now GETACC)
    elif k == 1:
        inst = rtype(1, 0b000)                       # funct7 /= 0
    else:
        inst = 0x0000302B | rtype(0, 0b000)          # custom-1 opcode, funct3 = 011
    illegal_kind[0] = (k + 1) % 3
    emit(7, a, b, inst)

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
illegal_orig(0x12345678, 0x9abcdef0)                   # illegal: acc must stay
emit(0, pack([1, 0, 0, 0]), pack([1, 0, 0, 0]))
emit(1, 0xdeadbeef, 0x55555555)                        # rs2 ignored by SETACC
for i in range(256):                                    # every lane-0 value times -128 and 127
    emit(1, 0, 0)
    emit(0, pack([i - 128, 0, 0, 0]), pack([-128, 0, 0, 0]))
    emit(0, pack([0, 0, 0, i - 128]), pack([0, 0, 0, 127]))
for i in range(20000):
    r = random.random()
    a = random.getrandbits(32); b = random.getrandbits(32)
    if r < 0.08:
        emit(1, a, b)
    elif r < 0.09:
        illegal_orig(a, b)
    else:
        emit(0, a, b)
n_part1 = len(out)

part1_same = None
if orig_path:
    orig = []
    for l in open(orig_path):
        f = l.split()
        orig.append((int(f[0], 16), int(f[1], 16), int(f[2], 16), int(f[3], 16)))
    mine = [(op, a, b, e) for (op, inst, a, b, e) in out]
    # the original file writes the current acc as "expected" for illegal lines too
    part1_same = (orig == mine)

# ---------------------------------------------------------------- part 2: GETACC directed
rng = random.Random(20261021)
g = lambda: rng.getrandbits(32)
emit(1, 0x12345678, g())
emit(2, g(), g())                                       # rs1, rs2 ignored
emit(2, g(), g())                                       # reading twice changes nothing
emit(0, 0x01020304, 0x05060708)                         # 0x12345678 + 70
emit(2, 0, 0)
emit(1, 0x7fffffff, 0); emit(2, g(), g())
emit(0, pack([-128] * 4), pack([-128] * 4)); emit(2, g(), g())   # wrapped value read back
emit(1, 0x80000000, 0); emit(2, g(), g())
emit(7, g(), g(), rtype(0, 0b111)); emit(2, g(), g())  # illegal leaves acc
emit(7, g(), g(), rtype(1, 0b010)); emit(2, g(), g())  # GETACC with funct7 = 1 is illegal
emit(7, g(), g(), rtype(0, 0b010, OPC_C1)); emit(2, g(), g())  # custom-1 opcode is illegal
# the trap-handler pattern: save, clobber, restore, continue
for rep in range(64):
    bias = g(); w = [g() for _ in range(4)]; x = [g() for _ in range(4)]
    emit(1, bias, g())
    emit(0, w[0], x[0]); emit(0, w[1], x[1])
    saved = acc[bank]
    emit(2, g(), g())                                   # handler: GETACC (save)
    emit(1, 0, 0)                                       # handler: SETACC x0 (clobber)
    emit(0, g(), g())                                   # handler may even compute
    emit(1, saved, 0)                                   # handler: SETACC saved (restore)
    emit(0, w[2], x[2]); emit(0, w[3], x[3])            # interrupted code continues

# ---------------------------------------------------------------- part 4: SELBANK directed
if BANKS:
    emit(3, g(), g(), bnum=0)
    emit(1, 0x0badf00d, 0)                              # bank 0 = A
    emit(3, g(), g(), bnum=1)                           # rd = bank 1 value
    emit(1, 0x13572468, 0)                              # bank 1 = B
    emit(2, g(), g())
    emit(0, 0x01020304, 0x05060708)
    emit(3, g(), g(), bnum=0)                           # rd = A
    emit(2, g(), g())
    emit(0, pack([-128] * 4), pack([-128] * 4))
    emit(3, g(), g(), bnum=1)
    emit(3, g(), g(), bnum=1)                           # selecting the same bank again
    emit(3, g(), g(), bnum=0)
    emit(7, g(), g(), rtype(2, 0b011)); emit(2, g(), g())    # funct7 = 2: illegal, bank unchanged
    emit(7, g(), g(), rtype(0x41, 0b011)); emit(2, g(), g()) # funct7 bit 6 set: illegal
    emit(7, g(), g(), rtype(1, 0b011, OPC_C1)); emit(2, g(), g())
    for rep in range(64):                               # the handler pattern with banks
        bias = g(); w = [g() for _ in range(4)]; x = [g() for _ in range(4)]
        emit(1, bias, g())
        emit(0, w[0], x[0]); emit(0, w[1], x[1])
        emit(3, g(), g(), bnum=1)                       # handler: SELBANK 1
        emit(1, 0, 0)                                   # handler: SETACC x0 (clobbers bank 1 only)
        emit(0, g(), g())
        emit(3, g(), g(), bnum=0)                       # handler: SELBANK 0 (rd = interrupted acc)
        emit(0, w[2], x[2]); emit(0, w[3], x[3])

# ---------------------------------------------------------------- part 3: random mix
if BANKS:
    ill = [rtype(0, 0b100), rtype(0, 0b101), rtype(0, 0b110), rtype(0, 0b111),
           rtype(2, 0b011), rtype(3, 0b011), rtype(0x40, 0b011), rtype(1, 0b010), rtype(0x20, 0b000),
           rtype(0, 0b010, OPC_C1), rtype(0, 0b010, OPC_C2), rtype(1, 0b011, OPC_C1)]
else:
    ill = [rtype(0, 0b011), rtype(1, 0b011), rtype(0, 0b100), rtype(0, 0b101), rtype(0, 0b110),
           rtype(0, 0b111), rtype(1, 0b010), rtype(0x40, 0b010), rtype(0x20, 0b000),
           rtype(0, 0b010, OPC_C1), rtype(0, 0b010, OPC_C2)]
k_ill = 0
for i in range(8000):
    r = rng.random(); a = g(); b = g()
    if r < 0.15:
        emit(2, a, b)
    elif r < 0.23:
        emit(1, a, b)
    elif r < 0.25:
        emit(7, a, b, ill[k_ill % len(ill)]); k_ill += 1
    elif BANKS and r < 0.35:
        emit(3, a, b, bnum=rng.getrandbits(1))
    else:
        emit(0, a, b)

with open(out_path, 'w') as f:
    for op, inst, a, b, e in out:
        f.write(f'{op:x} {inst:08x} {a:08x} {b:08x} {e:08x}\n')
cnt = {k: sum(1 for o in out if o[0] == k) for k in (0, 1, 2, 3, 7)}
print(f'{variant}: {len(out)} vectors (part 1 = {n_part1}); DOT4ACC {cnt[0]}, SETACC {cnt[1]}, '
      f'GETACC {cnt[2]}, SELBANK {cnt[3]}, illegal {cnt[7]}; checked results expected {len(out) - cnt[7]}')
if part1_same is not None:
    print(f'part 1 (op, rs1, rs2, expected) equals the original cfu_vectors.txt line for line: {part1_same}')
