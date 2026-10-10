# BIP-340 Schnorr (reference implementation, pure Python)
import hashlib

p = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)

def tagged_hash(tag, msg):
    t = hashlib.sha256(tag.encode()).digest()
    return hashlib.sha256(t + t + msg).digest()

def is_infinite(P): return P is None
def x(P): return P[0]
def y(P): return P[1]

def point_add(P1, P2):
    if P1 is None: return P2
    if P2 is None: return P1
    if x(P1) == x(P2) and y(P1) != y(P2): return None
    if P1 == P2:
        lam = (3 * x(P1) * x(P1) * pow(2 * y(P1), p - 2, p)) % p
    else:
        lam = ((y(P2) - y(P1)) * pow(x(P2) - x(P1), p - 2, p)) % p
    x3 = (lam * lam - x(P1) - x(P2)) % p
    return (x3, (lam * (x(P1) - x3) - y(P1)) % p)

def point_mul(P, k):
    R = None
    for i in range(256):
        if (k >> i) & 1: R = point_add(R, P)
        P = point_add(P, P)
    return R

def bytes_from_int(i): return i.to_bytes(32, "big")
def int_from_bytes(b): return int.from_bytes(b, "big")
def has_even_y(P): return y(P) % 2 == 0
def bytes_from_point(P): return bytes_from_int(x(P))

def lift_x(b):
    xx = int_from_bytes(b)
    if xx >= p: return None
    y_sq = (pow(xx, 3, p) + 7) % p
    yy = pow(y_sq, (p + 1) // 4, p)
    if pow(yy, 2, p) != y_sq: return None
    return (xx, yy if yy % 2 == 0 else p - yy)

def pubkey_gen(seckey: bytes) -> bytes:
    d0 = int_from_bytes(seckey)
    if not (1 <= d0 <= n - 1): raise ValueError("invalid secret key")
    return bytes_from_point(point_mul(G, d0))

def schnorr_sign(msg: bytes, seckey: bytes, aux_rand: bytes) -> bytes:
    d0 = int_from_bytes(seckey)
    if not (1 <= d0 <= n - 1): raise ValueError("invalid secret key")
    P = point_mul(G, d0)
    d = d0 if has_even_y(P) else n - d0
    t = bytes_from_int(d ^ int_from_bytes(tagged_hash("BIP0340/aux", aux_rand)))
    k0 = int_from_bytes(tagged_hash("BIP0340/nonce", t + bytes_from_point(P) + msg)) % n
    if k0 == 0: raise RuntimeError("k0 == 0")
    R = point_mul(G, k0)
    k = n - k0 if not has_even_y(R) else k0
    e = int_from_bytes(tagged_hash("BIP0340/challenge",
            bytes_from_point(R) + bytes_from_point(P) + msg)) % n
    sig = bytes_from_point(R) + bytes_from_int((k + e * d) % n)
    assert schnorr_verify(msg, bytes_from_point(P), sig)
    return sig

def schnorr_verify(msg: bytes, pubkey: bytes, sig: bytes) -> bool:
    if len(pubkey) != 32 or len(sig) != 64: return False
    P = lift_x(pubkey)
    if P is None: return False
    r = int_from_bytes(sig[0:32]); s = int_from_bytes(sig[32:64])
    if r >= p or s >= n: return False
    e = int_from_bytes(tagged_hash("BIP0340/challenge", sig[0:32] + pubkey + msg)) % n
    R = point_add(point_mul(G, s), point_mul(P, n - e))
    if R is None or (not has_even_y(R)) or x(R) != r: return False
    return True
