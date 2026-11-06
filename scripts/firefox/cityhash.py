import struct

K0 = 0xC3A5C85C97CB3127
K1 = 0xB492B66FBE98F273
K2 = 0x9AE16A3B2F90404F
K3 = 0xC949D7C7509E6557
MASK = (1 << 64) - 1


def _fetch64(data, pos):
    return struct.unpack_from("<Q", data, pos)[0]


def _fetch32(data, pos):
    return struct.unpack_from("<I", data, pos)[0]


def _rotate(value, shift):
    if shift == 0:
        return value
    return ((value >> shift) | (value << (64 - shift))) & MASK


def _rotate_by_at_least_1(value, shift):
    return ((value >> shift) | (value << (64 - shift))) & MASK


def _shift_mix(value):
    return (value ^ (value >> 47)) & MASK


def _hash_len16(u, v):
    mul = 0x9DDFEA08EB382D69
    a = ((u ^ v) * mul) & MASK
    a ^= a >> 47
    b = ((v ^ a) * mul) & MASK
    b ^= b >> 47
    return (b * mul) & MASK


def _hash_len0to16(data, length):
    if length > 8:
        a = _fetch64(data, 0)
        b = _fetch64(data, length - 8)
        return _hash_len16(a, _rotate_by_at_least_1((b + length) & MASK, length)) ^ b
    if length >= 4:
        a = _fetch32(data, 0)
        return _hash_len16((length + (a << 3)) & MASK, _fetch32(data, length - 4))
    if length > 0:
        a = data[0]
        b = data[length >> 1]
        c = data[length - 1]
        y = (a + (b << 8)) & 0xFFFFFFFF
        z = (length + (c << 2)) & 0xFFFFFFFF
        return (_shift_mix(((y * K2) & MASK) ^ ((z * K3) & MASK)) * K2) & MASK
    return K2


def _hash_len17to32(data, length):
    a = (_fetch64(data, 0) * K1) & MASK
    b = _fetch64(data, 8)
    c = (_fetch64(data, length - 8) * K2) & MASK
    d = (_fetch64(data, length - 16) * K0) & MASK
    return _hash_len16(
        (_rotate((a - b) & MASK, 43) + _rotate(c, 30) + d) & MASK,
        (a + _rotate(b ^ K3, 20) - c + length) & MASK,
    )


def _weak_hash_len32_with_seeds(data, offset, a, b):
    w = _fetch64(data, offset)
    x = _fetch64(data, offset + 8)
    y = _fetch64(data, offset + 16)
    z = _fetch64(data, offset + 24)
    a = (a + w) & MASK
    b = _rotate((b + a + z) & MASK, 21)
    c = a
    a = (a + x) & MASK
    a = (a + y) & MASK
    b = (b + _rotate(a, 44)) & MASK
    return ((a + z) & MASK, (b + c) & MASK)


def _hash_len33to64(data, length):
    z = _fetch64(data, 24)
    a = (_fetch64(data, 0) + (length + _fetch64(data, length - 16)) * K0) & MASK
    b = _rotate((a + z) & MASK, 52)
    c = _rotate(a, 37)
    a = (a + _fetch64(data, 8)) & MASK
    c = (c + _rotate(a, 7)) & MASK
    a = (a + _fetch64(data, 16)) & MASK
    vf = (a + z) & MASK
    vs = (b + _rotate(a, 31) + c) & MASK
    a = (_fetch64(data, 16) + _fetch64(data, length - 32)) & MASK
    z = _fetch64(data, length - 8)
    b = _rotate((a + z) & MASK, 52)
    c = _rotate(a, 37)
    a = (a + _fetch64(data, length - 24)) & MASK
    c = (c + _rotate(a, 7)) & MASK
    a = (a + _fetch64(data, length - 16)) & MASK
    wf = (a + z) & MASK
    ws = (b + _rotate(a, 31) + c) & MASK
    r = _shift_mix(((vf + ws) * K2 + (wf + vs) * K0) & MASK)
    return (_shift_mix((r * K0 + vs) & MASK) * K2) & MASK


def city_hash64(data):
    length = len(data)
    if length <= 32:
        if length <= 16:
            return _hash_len0to16(data, length)
        return _hash_len17to32(data, length)
    if length <= 64:
        return _hash_len33to64(data, length)
    x = _fetch64(data, 0)
    y = _fetch64(data, length - 16) ^ K1
    z = _fetch64(data, length - 56) ^ K0
    v = _weak_hash_len32_with_seeds(data, length - 64, length, y)
    w = _weak_hash_len32_with_seeds(data, length - 32, (length * K1) & MASK, K0)
    z = (z + _shift_mix(v[1]) * K1) & MASK
    x = (_rotate((z + x) & MASK, 39) * K1) & MASK
    y = (_rotate(y, 33) * K1) & MASK
    length = (length - 1) & ~63
    offset = 0
    while True:
        x = (_rotate((x + y + v[0] + _fetch64(data, offset + 16)) & MASK, 37) * K1) & MASK
        y = (_rotate((y + v[1] + _fetch64(data, offset + 48)) & MASK, 42) * K1) & MASK
        x ^= w[1]
        y ^= v[0]
        z = _rotate(z ^ w[0], 33)
        v = _weak_hash_len32_with_seeds(data, offset, (v[1] * K1) & MASK, (x + w[0]) & MASK)
        w = _weak_hash_len32_with_seeds(data, offset + 32, (z + w[1]) & MASK, y)
        z, x = x, z
        offset += 64
        length -= 64
        if length == 0:
            break
    return _hash_len16(
        (_hash_len16(v[0], w[0]) + _shift_mix(y) * K1 + z) & MASK,
        (_hash_len16(v[1], w[1]) + x) & MASK,
    )


def install_hash(install_path):
    utf8 = install_path.encode("utf-8", "surrogateescape").decode("utf-8", "replace")
    return f"{city_hash64(utf8.encode('utf-16-le')):X}"
