# OD-02: ML-DSA-65 over the brief's LMS/XMSS recommendation
Drafted 2026-09-17. Full argument in pi-trust-lab-notebook.md section 10.2.

DECISION: keep ML-DSA-65 primary; adopt LMS as a SECOND signature, not a replacement.

The brief's case for LMS, stated fairly:
  1. Hash-only security assumption (Merkle 1979) vs lattice (M-LWE/M-SIS, much younger)
  2. Verifier is hash evaluations only - no NTT, no matrix expansion. Smaller code.
  3. Tiny public key. (Moot here: the Pi stores a 32-byte key HASH in OTP either way.)

Why ML-DSA anyway:
  1. STATEFULNESS IS THE DECIDING FACTOR. One-time key per signature; reuse is
     catastrophic, not gradual. A restore from a backup taken before the last
     signature causes it silently. Student team, laptop DEV key, no HSM yet.
  2. Finite signature budget (2^h) is a schedule liability across rebuilds and
     tamper tests.
  3. The M2 advantage buys nothing HERE - measured 38,200 B = 29.1% of 128 KB,
     70.9% headroom (8I.7, 8I.8). Code size is not our binding constraint.
  4. Verify timing deterministic: 0.24% bench spread, 1.8% across 11 real boots.
  5. FIPS 204 general-purpose standard; OpenSSL 3.5+ makes the U-Boot host path
     plausible. LMS tooling maturity in the FIT path is [TO VERIFY].

HONEST WEAKNESS: assumption diversity is NOT answered by any of the above. We
chose the younger assumption for operational reasons. State that in the report.

RESOLUTION - dual signature:
  RSA-2048  (factoring) - fixed by silicon, quantum-vulnerable
  ML-DSA-65 (lattice)   - primary, stateless, measured
  LMS       (hash)      - secondary, release images only, low signature volume
Both PQC signatures required => attacker must break lattice AND hash.

OPEN [TO VERIFY]:
  - SP 800-208 state-management requirements, exact wording
  - LMS pk/sig sizes for the actual parameter set (RFC 8554)
  - LMS support in U-Boot FIT / mkimage
  - Select an LMS impl with ACVP vectors; measure M1/M2/M3/M6 for the table
