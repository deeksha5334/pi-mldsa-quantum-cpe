# M1 CLOSED - boot latency overhead of ML-DSA verification (2026-09-30)

Target: PQC verification adds less than 2 s to boot.
Result: 122 ms = 6.1% of budget. PASS.

## Method (D-03 compliant)
B1 = RSA signed boot, NO ML-DSA. 33 MB boot.img, 19 MB initramfs.
B2 = RSA signed boot + ML-DSA 4-stage verity script. 37 MB boot.img,
     23 MB initramfs (includes 12 MB verity hash tree).
M1 = B2 - B1. B0 (unsigned) is NOT used: comparing against it would charge
     ML-DSA for the cost of performing any verification at all.

Identical in both: kernel, cmdline (panic=10, no quiet), services,
EEPROM config, SD card, network state (CometNet), console verbosity.

## Data - kernel segment, cluster-matched

              B1              B2            delta
LOW   n=4  5.055 s    n=3  5.110 s        + 55 ms
HIGH  n=7  5.334 s    n=7  5.494 s        +160 ms
weighted                                   +122 ms

Excluded: 3 boots with userspace 11-13.5 s. Cause identified from per-boot
blame: dev-mmcblk0p2.device 5.892 s, rpi-resize-swap-file 3.758 s,
systemd-udevd 3.617 s - simultaneous storage contention (R-3), not
verification. One B1 and one B2 boot excluded for kernel > 5.8 s, same cause.

## Cross-check - two independent methods agree

Whole-boot delta (this document)        122 ms
Direct kernel-log instrumentation       118.2 ms (n=11, sigma 0.5 ms)
Agreement                               3%

The direct measurement is the more precise of the two and shows verification
is stable at sigma 0.5 ms. The 105 ms spread between the LOW and HIGH cluster
deltas is therefore a measurement artifact of the bimodal environment, not
variation in the verifier. Quote 118.2 ms for the verifier cost and 122 ms
for the end-to-end boot delta.

## Breakdown of the 118.2 ms

stage 1  ML-DSA-65 signature over the manifest      8.0 ms   ( 7%)
stage 2  parse verity params from verified manifest 20.6 ms  (17%)
stage 3  cross-check hash device superblock         65.6 ms  (56%)
stage 4  device presence check                      17.9 ms  (15%)

The lattice cryptography is 7% of the cost. Text parsing and reading the
12 MB hash device account for the rest. Third independent confirmation that
the post-quantum operation is not where boot time goes (see also 8A.3e,
5.12.7).

## Bimodal split - three hypotheses eliminated

Present in BOTH B1 and B2 at the same magnitude (~330 ms in Run /init), so it
is environmental and affects both arms equally.
  NOT entropy         - random: crng init done at 0.000000
  NOT decompression   - initramfs unpack 0.435 to 0.801 s, over before the gap
  NOT our verifier    - identical split with the verifier absent (B1)
Localised to a 1.717 s window with NO log output between
  1.293936  printk: legacy console ttyS0 enabled
  3.011201  bcm2835-wdt ... watchdog timer
Remaining candidate: a device probe or firmware load in that window.
