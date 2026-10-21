#!/usr/bin/env python3
"""Verify and summarize HMF1 fixtures or length-prefixed captures (see Docs/testing/parity-harness.md)."""
import struct, sys

FNV_OFFSET, FNV_PRIME = 14695981039346656037, 1099511628211

def fnv(data):
    h = FNV_OFFSET
    for b in data:
        h = ((h ^ b) * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return h

def inspect(blob, label):
    if len(blob) < 16 or len(blob) % 4:
        sys.exit(f'{label}: bad length')
    magic, version, abi, program, module = struct.unpack_from('<5I', blob)
    if magic != 0x31464D48 or version != 1:
        sys.exit(f'{label}: unknown magic/version')
    stored, = struct.unpack_from('<Q', blob, len(blob) - 8)
    if stored != fnv(blob[:-8]):
        sys.exit(f'{label}: content hash mismatch')
    tic, seed, source = struct.unpack_from('<3Q', blob, 20)
    status, = struct.unpack_from('<I', blob, 52)
    print(f'{label}: module 0x{module:08x} program {program} tic {tic} seed 0x{seed:016x} '
          f'source 0x{source:016x} status {status} hash {stored:016x}')

data = open(sys.argv[1], 'rb').read()
if len(sys.argv) > 2 and sys.argv[2] == '--capture':
    at = n = 0
    while at < len(data):
        size, = struct.unpack_from('<I', data, at)
        inspect(data[at + 4:at + 4 + size], f'fixture {n}')
        at += 4 + size; n += 1
else:
    inspect(data, sys.argv[1])
