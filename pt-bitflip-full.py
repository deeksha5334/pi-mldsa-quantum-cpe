#!/usr/bin/env python3
import os, shutil, subprocess, sys, time

VERIFY, MANIFEST, SIG, PUBKEY = "./build/pt-verify", "manifest.txt", "manifest.sig", "dev.pk"

def flip(path, pos, bit):
    with open(path, "r+b") as f:
        f.seek(pos); b = f.read(1)[0]; f.seek(pos); f.write(bytes([b ^ (1 << bit)]))

def sig_ok():
    return subprocess.run([VERIFY, MANIFEST, SIG, PUBKEY],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def hash_ok():
    return subprocess.run(["sha256sum", "-c", "--status", MANIFEST],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def exhaustive(label, target, check, caught_by):
    size = os.path.getsize(target)
    total = size * 8
    bak = target + ".bak"
    shutil.copy2(target, bak)
    missed, done, t0 = [], 0, time.time()
    print("  %s: %d bytes, %d bit positions" % (label, size, total))
    try:
        for pos in range(size):
            for bit in range(8):
                flip(target, pos, bit)
                accepted = check()
                shutil.copy2(bak, target)
                done += 1
                if accepted:
                    missed.append((pos, bit))
                if done % 200 == 0:
                    print("    %d/%d  (%.0fs)" % (done, total, time.time() - t0))
    finally:
        shutil.copy2(bak, target); os.remove(bak)
    ok = not missed
    print("  [%s] %d/%d detected in %.0fs -- %s"
          % ("PASS" if ok else "FAIL", total - len(missed), total,
             time.time() - t0, caught_by))
    if missed:
        print("    MISSED: %s" % missed[:20])
    return ok

print("pt-bitflip-full - EXHAUSTIVE single-bit coverage\n")
if not (sig_ok() and hash_ok()):
    print("baseline broken - regenerate manifest and sig first"); sys.exit(1)
print("  [PASS] control: unmodified chain accepted\n")

r = []
r.append(exhaustive("manifest.txt", MANIFEST, sig_ok, "ML-DSA-65 signature"))
print()
for line in open(MANIFEST):
    line = line.strip()
    if line and not line.startswith("#"):
        p = line.split(None, 1)
        if len(p) == 2 and os.path.exists(p[1]):
            r.append(exhaustive(p[1], p[1], hash_ok, "SHA-256 hash line"))
            print()

print("=" * 60)
print("EXHAUSTIVE M4: %s" % ("PASS - every single-bit modification detected" if all(r) else "FAIL"))
sys.exit(0 if all(r) else 1)
