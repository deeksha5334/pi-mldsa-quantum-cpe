# RA-7 / M2: optimisation level dominates verifier code size (2026-09-17)

## Resolves the M2 discrepancy

Notebook 8A.3f reports 35,968 B. The shipping binary measured 19,976 B. Same
source, same C backend, same MLD_CONFIG_REDUCE_RAM, same parameter set.

Cause: examples/monolithic_build/Makefile line 27 uses -O3. pi-trust-signing
builds with -O2. Rebuilding our source at -O3 gives 36,200 B, within 232 B
(0.6%) of the notebook figure. Discrepancy CLOSED - not a backend difference.

Confirmed: mldsa_native65.o (Sep 9 build) contains ZERO aarch64_asm symbols.
Both builds are the pure C backend.

## Three-axis result, ML-DSA-65, REDUCE_RAM on, C backend, Pi 4B

| Flag | text | % of 128 KB | 200 verifies | per run | code vs -O2 | time vs -O2 |
|---|---|---|---|---|---|---|
| -Os  | 15,372 B | 11.7% | 0.517 s | 2.59 ms | -23.1% | +6.2% |
| -O2  | 19,976 B | 15.2% | 0.487 s | 2.44 ms | -       | -      |
| -O3  | 36,200 B | 27.6% | 0.483 s | 2.42 ms | +81.2% | -0.8%  |

data = 0, bss = 0 at every level.

## Finding

-O3 costs 81% more code than -O2 for a 0.8% speed change, which is inside
measurement noise. In a boot verifier, where code size is the binding
constraint (M2) and the latency budget is 2,000 ms, -O3 is the wrong
trade. -Os saves a further 23% of code for 0.15 ms.

Caveat: each timed run includes process spawn and three file reads, so the
ML-DSA share is a fraction of the 2.4 ms and the true compute deltas are
compressed. A cycle-accurate comparison would separate them. The size figures
are exact.

## Decisions

1. Keep -O2 as shipping for now; revisit -Os when M6 stack is re-measured,
   since -Os may also change peak stack.
2. Report M2 as 19,976 B (-O2, the binary that ships), and present the table
   above as the RA-7 deliverable.
3. Mark 8A.2 / 8A.3f as -O3 figures rather than deleting them.

## Open

M6 (16,736 B) was measured under the -O3 build. Re-measure peak stack at -O2
and -Os before the final report.

## M6 re-measured on the shipping binary (2026-09-17)

Method: valgrind massif --stacks=yes on the actual static pt-verify binary
(fault-hardened, double verify), not the upstream test harness. Figure therefore
includes libc startup, i.e. it is the honest whole-program number.

| Flag | Code | Peak stack | Code+stack | % of 128 KB |
|---|---|---|---|---|
| -Os | 15,372 B | 18,096 B | 33,468 B | 25.5% |
| -O2 | 19,976 B | 18,224 B | 38,200 B | 29.1% |
| -O3 | 36,200 B | 18,224 B | 54,424 B | 41.5% |

Peak stack is FLAT across optimisation levels: 128 B spread (0.7%). Optimisation
level changes code size, not stack. This is consistent with 8A.3b - matrix A
expansion, governed by MLD_CONFIG_REDUCE_RAM, is what drives verify stack.

Comparison to the notebook figure: 8A.3b reports 16,736 B from the upstream
test_stack65 harness at -O3. Ours is 18,224 B whole-program. The ~1.5 KB delta
is libc/startup, not ML-DSA. Both are valid; state which one is being quoted.

M6 VERDICT: 18,224 B = 13.9% of 128 KB. PASS.
M2+M6 combined, shipping -O2 build: 38,200 B = 29.1%. Headroom 70.9%.
