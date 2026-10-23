#!/usr/bin/env python3
"""Symmetric INT8 post-training quantization of the hls4ml KERAS_3layer jet-tagging MLP.

Scheme (the C code and the CFU reproduce it bit for bit):
  * weights: per-tensor symmetric int8, s_w = max|W| / 127, q_w = round_half_even(W / s_w), range [-127, 127]
  * input:   s_x = 1/127 (x_test lies in [-1, 1)), q_x = clip(round_half_even(x * 127), -127, 127)
  * hidden activations: ReLU output, s_a = max(ReLU activation over the calibration set) / 127,
    stored as int8 in [0, 127]
  * bias:    int32, q_b = round_half_even(b / (s_in * s_w))
  * accumulate: int32, acc = q_b + sum(q_w * q_in)
  * requantize (hidden layers): M = s_in * s_w / s_out = M0 * 2^-sh with M0 in [2^30, 2^31),
    y = (acc * M0 + 2^(sh-1)) >> sh   (int64 product, arithmetic shift = floor, so round half up)
    then ReLU and saturate: y = min(max(y, 0), 127)
  * output layer: int32 logits acc (no requantization); class = argmax (softmax is monotonic,
    first index wins on ties)
Calibration set: x_test[0:500]. Exported test vectors: x_test[0:64].
"""
import os, sys, json, h5py, numpy as np

# Inputs: the trained model and test data of https://github.com/taitashaw/hls4ml-fpga-classifier,
# cloned next to this repo (or give its path as the first argument). Outputs go into this repo.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '..', 'hls4ml-fpga-classifier')
OUT = ROOT
NVEC = 64
CAL = slice(0, 500)

f = h5py.File(f'{D}/KERAS_3layer_weights.h5', 'r')
names = ['fc1_relu', 'fc2_relu', 'fc3_relu', 'output_softmax']
W = [f[n][n]['kernel:0'][()].astype(np.float64) for n in names]   # (in, out)
B = [f[n][n]['bias:0'][()].astype(np.float64) for n in names]
nparam = sum(w.size + b.size for w, b in zip(W, B))
x = np.load(f'{D}/x_test.npy').astype(np.float64)
y_keras = np.load(f'{D}/y_keras.npy')
y_hls = np.load(f'{D}/y_hls_csim.npy')

# ---- float reference (checks the weights were read correctly) ----
def float_fwd(xx):
    a = xx; acts = []
    for i in range(4):
        z = a @ W[i] + B[i]
        if i < 3:
            a = np.maximum(z, 0); acts.append(a)
    e = np.exp(z - z.max(1, keepdims=True))
    return e / e.sum(1, keepdims=True), acts
p_float, acts_f = float_fwd(x)

# ---- quantization parameters ----
s_x = 1.0 / 127
s_w = [np.abs(w).max() / 127 for w in W]
qW = [np.clip(np.round(w / s), -127, 127).astype(np.int64) for w, s in zip(W, s_w)]
_, acts_cal = float_fwd(x[CAL])
s_a = [a.max() / 127 for a in acts_cal]
s_in = [s_x] + s_a[:3]
qB = [np.round(b / (si * sw)).astype(np.int64) for b, si, sw in zip(B, s_in, s_w)]

def mult_shift(m):
    sh = 0
    while m < 2**30:
        m *= 2; sh += 1
    while m >= 2**31:
        m /= 2; sh -= 1
    return int(round(m)), sh
MS = [mult_shift(s_in[i] * s_w[i] / s_a[i]) for i in range(3)]
for m0, sh in MS:
    assert 2**30 <= m0 < 2**31 and 1 <= sh <= 62, (m0, sh)

def quant_input(xx):
    return np.clip(np.round(xx * 127), -127, 127).astype(np.int64)

I32 = 2**31
def int8_fwd(qx):
    a = qx
    for i in range(4):
        acc = a @ qW[i] + qB[i]
        assert np.all(np.abs(acc) < I32), 'int32 overflow'
        if i < 3:
            m0, sh = MS[i]
            y = (acc * m0 + (1 << (sh - 1))) >> sh     # python ints in int64: check range
            assert np.all(np.abs(acc.astype(object) * m0) < 2**62)
            a = np.clip(y, 0, 127)
    return acc  # int32 logits

qx = quant_input(x)
logits = int8_fwd(qx)
am_k = y_keras.argmax(1); am_h = y_hls.argmax(1); am_f = p_float.argmax(1); am_q = logits.argmax(1)
held = slice(500, 1000)
rep = {
    'n_params': int(nparam),
    'float_reimpl_vs_y_keras_max_abs_err': float(np.abs(p_float - y_keras).max()),
    'float_reimpl_vs_y_keras_argmax_agree': int((am_f == am_k).sum()),
    'int8_vs_y_keras_argmax_agree_all_1000': int((am_q == am_k).sum()),
    'int8_vs_y_keras_argmax_agree_heldout_500_999': int((am_q[held] == am_k[held]).sum()),
    'int8_vs_y_hls_csim_argmax_agree_all_1000': int((am_q == am_h).sum()),
    'hls_csim_vs_y_keras_argmax_agree_all_1000': int((am_h == am_k).sum()),
    'int8_vs_y_keras_argmax_agree_first_64': int((am_q[:NVEC] == am_k[:NVEC]).sum()),
    's_x': s_x, 's_w': s_w, 's_a': s_a, 'M0_shift': MS,
    'max_abs_acc_per_layer': [int(np.abs(z).max()) for z in []],
}
# max |acc| per layer (headroom check)
a = qx; mx = []
for i in range(4):
    acc = a @ qW[i] + qB[i]; mx.append(int(np.abs(acc).max()))
    if i < 3:
        m0, sh = MS[i]; a = np.clip((acc * m0 + (1 << (sh - 1))) >> sh, 0, 127)
rep['max_abs_acc_per_layer'] = mx
print(json.dumps(rep, indent=1))
json.dump(rep, open(f'{OUT}/model/quant_report.json', 'w'), indent=1)

# ---- C header export ----
def carr(ctype, name, vals, per=16, align=True):
    vals = [int(v) for v in np.asarray(vals).ravel()]
    al = ' __attribute__((aligned(4)))' if align else ''
    s = f'static const {ctype} {name}[{len(vals)}]{al} = {{\n'
    for i in range(0, len(vals), per):
        s += '  ' + ', '.join(str(v) for v in vals[i:i + per]) + ',\n'
    return s + '};\n'

h = ['/* Generated by model/quantize.py. Do not edit. */', '#ifndef MODEL_INT8_H', '#define MODEL_INT8_H', '#include <stdint.h>', '']
h.append('#define N_LAYERS 4')
dims = [16, 64, 32, 32, 5]
h.append('static const int LAYER_IN[4]  = {16, 64, 32, 32};')
h.append('static const int LAYER_OUT[4] = {64, 32, 32, 5};')
for i in range(4):
    # row-major per output neuron: w[j][k], k = input index (contiguous, 4-byte aligned rows)
    h.append(carr('int8_t', f'W{i}', qW[i].T))
    h.append(carr('int32_t', f'B{i}', qB[i], per=8))
for i in range(3):
    h.append(f'#define M0_{i} {MS[i][0]}')
    h.append(f'#define SH_{i} {MS[i][1]}')
h.append('#endif')
open(f'{OUT}/sw/common/model_int8.h', 'w').write('\n'.join(h) + '\n')

t = ['/* Generated by model/quantize.py. Do not edit. */', '#ifndef TEST_VECTORS_H', '#define TEST_VECTORS_H', '#include <stdint.h>', '']
t.append(f'#define N_VEC {NVEC}')
t.append('/* x_test[0:64], quantized: q = clip(round(x*127), -127, 127) */')
t.append(carr('int8_t', 'X_Q', qx[:NVEC]))
t.append('/* expected int32 logits of the INT8 model */')
t.append(carr('int32_t', 'Y_EXP', logits[:NVEC], per=5))
t.append('/* expected class (argmax of the INT8 logits) and the Keras float class */')
t.append(carr('uint8_t', 'CLS_EXP', am_q[:NVEC], align=False))
t.append(carr('uint8_t', 'CLS_KERAS', am_k[:NVEC], align=False))
t.append('#endif')
open(f'{OUT}/sw/common/test_vectors.h', 'w').write('\n'.join(t) + '\n')
np.save(f'{OUT}/model/int8_logits_all1000.npy', logits)
print('headers written')
