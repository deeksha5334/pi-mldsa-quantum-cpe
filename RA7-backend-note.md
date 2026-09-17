# RA-7 note: ML-DSA-65 backend selection (2026-09-17)

Shipping build uses the **pure C backend**. MLD_CONFIG_USE_NATIVE_BACKEND_ARITH
is unset (mldsa_native_config.h line 370).

| Backend | Library code (text) | % of 128 KB |
|---|---|---|
| C (shipping) | 19,976 B | 15.2% |
| AArch64 asm (compile only) | 26,516 B | 20.2% |

data = 0, bss = 0 in both: no static state.

The asm backend COMPILES but does not LINK from the monolithic mldsa_native.c
alone: 44 .S files under mldsa_native/src/**/native/aarch64/ must be assembled
and linked separately (undefined refs: mldsa_ntt_aarch64_asm,
mldsa_poly_pointwise_montgomery_aarch64_asm, mldsa_rej_uniform_aarch64_asm, etc).
Enabling it is a build-system change, not a one-flag change.

Notebook 8A.3g reports 35,968 B, matching neither figure -> different build
configuration. Resolve before the final report; the reportable M2 must match
the binary that actually ships.

Measured C backend: 200 sequential verifications in 0.506 s wall
(~2.53 ms each incl. process spawn). In-boot double verify: 4.234 ms.

Decision: keep C. 85% memory headroom, verify is 0.2% of the 2 s M1 budget,
and the C path is the CBMC-verified one.
