# M4 CLOSED - boot enforcement demonstrated (2026-09-17)

Sponsor metric: "Successful Failure to Boot when the firmware is modified by
even a single bit." Both halves now satisfied.

| Half | Evidence | Status |
|---|---|---|
| Cryptographic detection | 1,944 exhaustive single-bit flips (8E.4) | PASS |
| In-boot detection | audit mode, n=11 (8I.2, 8I.3) | PASS |
| BOOT ENFORCEMENT | tampered manifest -> device does not boot | PASS (this doc) |

## Test

One byte appended to /etc/pi-trust/manifest.txt inside the initramfs, rebuilt,
rebooted. Result: >250 consecutive ICMP timeouts (~4 min). Device never reached
a state where it could respond. Restoring initramfs8.audit-ok from the boot
partition (host-side, card reader) recovered it.

Control before and after: ENFORCE RESULT VALID, normal boot.

## E-17 - THE IMPORTANT FINDING: detection is not enforcement

First enforce attempt LOGGED the abort and BOOTED ANYWAY:

    [4.353947] pt-verify: ENFORCE START
    [4.359833] pt-verify: ABORT signature invalid rc=1
    -> system booted to a login prompt

Cause: panic() is a shell function defined in /scripts/functions. A
local-top script must source it. Without that line, panic was an undefined
command; the shell reported failure, run-scripts ignored it, boot continued.

Why this matters more than the fix: the KERNEL LOG WAS CORRECT. Anyone reading
logs would have concluded the device was secure. The verifier detected the
tamper, reported it accurately, and enforced nothing. A security control whose
abort path silently no-ops is worse than no control, because it manufactures
confidence.

This is only visible if you run the NEGATIVE test on real hardware. A positive
test (good manifest boots) passes identically in both the broken and fixed
versions.

Generalises 8G.5 and E-08: silent partial success is the dangerous failure mode
in a trust pipeline.

## Fix

    . /scripts/functions          # makes panic() available

plus halt_boot(), which calls panic() and then, if panic() ever returns or is
unavailable, syncs, triggers sysrq reboot, and spins forever. The abort path no
longer depends on a single external function resolving correctly.

Also restored the file-existence pre-checks lost in E-09: missing manifest,
signature, or public key now report the actual cause, not "signature invalid".

## Configuration

cmdline.txt: added panic=10 (reboot rather than drop to a rescue shell);
removed "quiet splash plymouth.ignore-serial-consoles" so failures are visible.
Backup at /boot/firmware/cmdline.txt.bak.

Side effect on M1c: verify wall time rose from 4.24 ms to ~7.6 ms and the start
offset moved from ~1.8 s to ~4.0 s, because console output now goes to serial
at 115200. CONSOLE VERBOSITY AFFECTS M1c - state the console configuration
alongside any timing figure.

## Scope - what this does NOT yet prove

The initramfs sits on the ordinary unsigned bootfs partition. An attacker with
write access to that partition can replace the initramfs, or restore
initramfs8.audit-ok, exactly as WE did to recover. This is enforcement of a
signature, not yet a chain of trust. It becomes one when the initramfs is
inside an RSA-signed boot.img (8D.2 step 4).

Recovery procedure is itself evidence: a device that fails closed remains
recoverable by an operator with physical access and the boot partition.
