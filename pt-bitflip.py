#!/usr/bin/env python3
import os, random, shutil, subprocess, sys

VERIFY = "./build/pt-verify"
MANIFEST = "manifest.txt"
SIG = "manifest.sig"
PUBKEY = "dev.pk"

def flip_bit(path, byte_pos, bit):
    with open(path, "r+b") as f:
        f.seek(byte_pos)
        original = f.read(1)[0]
        f.seek(byte_pos)
        f.write(bytes([original ^ (1 << bit)]))

def verify_signature():
    r = subprocess.run([VERIFY, MANIFEST, SIG, PUBKEY],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return r.returncode == 0

def verify_hashes():
    r = subprocess.run(["sha256sum", "-c", "--status", MANIFEST],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return r.returncode == 0

def run_flip_test(label, target, trials, check, caught_by):
    size = os.path.getsize(target)
    backup = target + ".bak"
    shutil.copy2(target, backup)
    detected = 0
    missed = []
    try:
        for _ in range(trials):
            byte_pos = random.randrange(size)
            bit = random.randrange(8)
            flip_bit(target, byte_pos, bit)
            accepted = check()
            shutil.copy2(backup, target)
            if accepted:
                missed.append((byte_pos, bit))
            else:
                detected += 1
    finally:
        shutil.copy2(backup, target)
        os.remove(backup)
    ok = detected == trials
    print("  [%s] %s" % ("PASS" if ok else "FAIL", label))
    print("         %d/%d flips detected (%d bytes, %d bit positions)"
          % (detected, trials, size, size * 8))
    print("         caught by: %s" % caught_by)
    if missed:
        print("         MISSED at (byte,bit): %s" % missed[:10])
    return ok

def main():
    trials = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    print("pt-bitflip - M4 single-bit tamper resilience")
    print("trials per test: %d\n" % trials)
    print("  Control:")
    if not verify_signature():
        print("  [FAIL] baseline signature invalid - regenerate first"); return 1
    if not verify_hashes():
        print("  [FAIL] baseline hashes mismatch - regenerate first"); return 1
    print("  [PASS] unmodified manifest accepted, hashes match\n")

    results = []
    print("  Test 1 - manifest:")
    results.append(run_flip_test("single-bit flip in manifest.txt", MANIFEST,
                   trials, verify_signature, "ML-DSA-65 signature verification"))
    print()
    print("  Test 2 - signature:")
    results.append(run_flip_test("single-bit flip in manifest.sig", SIG,
                   trials, verify_signature, "ML-DSA-65 signature verification"))
    print()

    artifacts = []
    with open(MANIFEST) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                parts = line.split(None, 1)
                if len(parts) == 2 and os.path.exists(parts[1]):
                    artifacts.append(parts[1])

    for art in artifacts:
        print("  Test 3 - artifact %s:" % art)
        results.append(run_flip_test("single-bit flip in %s" % art, art, trials,
                       verify_hashes, "SHA-256 hash line (signature stays valid)"))
        print()

    print("=" * 60)
    if all(results):
        print("M4 RESULT: PASS - %d tests, %d flips each, 100%% detection"
              % (len(results), trials))
        return 0
    print("M4 RESULT: FAIL - %d of %d tests missed a flip"
          % (results.count(False), len(results)))
    return 1

sys.exit(main())
