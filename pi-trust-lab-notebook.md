# Team Singularity — ML-DSA Secure Boot on Raspberry Pi 4B
## Lab Notebook & Report Source Document

**Project:** AT&T Quantum Network — "Bedrock of Trust" (UTD Senior Design Capstone)
**Team:** Singularity (hardware / root-of-trust)
**Sister team:** Event Horizon (secure inter-node messaging)
**Document status:** Living document — append each session, do not rewrite history
**Last updated:** 2026-09-08

---

## 0. How to use this document

Sections 1–4 are frozen reference material (scope, constraints, environment). Section 5 is the
append-only session log. Sections 6–12 are trackers that get updated as work proceeds. Section 13
records mistakes deliberately — reviewers value a documented dead end more than a suspiciously
clean narrative.

Every claim in this document should be traceable to either (a) a raw capture in Appendix A, or
(b) a cited external standard. Anything not yet verified is tagged **[TO VERIFY]**.

---

## 1. Scope and team boundary

### 1.1 In scope for Team Singularity
Establishing that a Raspberry Pi 4B network-edge CPE device boots only firmware and OS images
authenticated with post-quantum signatures, and can prove that fact to a relying party.

### 1.2 Out of scope
The secure transaction between the two demo nodes. That is owned by the software team. Our
deliverable to them is a **trust anchor and an attestation interface**, not transport security.

### 1.3 Integration contract with software team — **OPEN, ACTION REQUIRED**
"The device is trusted" is only useful to the software team if it is something their code can
*check at runtime*. This interface must be agreed early, not at integration.

Candidate forms:
- Signed attestation blob produced at boot, readable by their application
- TPM 2.0 quote over PCRs populated during measured boot
- Device identity keypair released/unsealed only on a verified boot

**Owner:** TBD. **Deadline:** before Phase II implementation begins.

---

## 2. Foundational architecture constraint (Phase I key finding)

> **The Raspberry Pi 4's hardware root of trust cannot be made post-quantum.**

The BCM2711 on-die boot ROM and the EEPROM bootloader implement **RSA-2048 with SHA-256 only**.
This code is immutable (mask ROM) and closed-source. There is no mechanism — documented or
otherwise — to replace the ROM's signature algorithm with ML-DSA.

### 2.1 Consequence for architecture
The chain must be:

```
BCM2711 mask ROM        [immutable, RSA-2048]     ← cannot change
  └─ EEPROM bootloader  [RSA-2048, pieeprom.sig]  ← cannot change
       └─ boot.img      [RSA-2048 signed]         ← anchored classically
            └─ ML-DSA verifier                    ← OUR INSERTION POINT
                 └─ kernel / rootfs               [ML-DSA-65 verified]
```

### 2.2 Why this is a result, not a failure
This is precisely the **"Hybrid Signatures"** avenue named in the sponsor brief: the device
requires both a classical RSA signature and a PQC signature during the transition period.
Identifying the exact boundary where classical crypto is unavoidable — and quantifying the
residual exposure it creates — is a legitimate Tier-1 engineering finding.

### 2.3 Residual risk to state explicitly in the report
An adversary with a CRQC could forge the RSA-2048 signature on `boot.img` and substitute a
malicious early stage that never invokes our ML-DSA verifier. **Our PQC chain is therefore only
as strong as the classical link above it on this silicon.** Mitigation on Pi 4 is limited to
defence-in-depth (OTP lockdown, external TPM measurement, tamper detection). Full remediation
requires silicon with a PQC-capable ROM. This limitation should be stated plainly and framed as
a hardware-generation constraint, not an implementation defect.

---

## 3. Frozen environment baseline

> **Do not change any item in this section mid-project.** Every entry here is a variable that,
> if altered, invalidates the boot-time comparison in Section 9.

### 3.1 Device under test
| Field | Value | Source |
|---|---|---|
| Board | Raspberry Pi 4 Model B | boardrev decode |
| Board revision code | `c03115` | bootloader trace |
| → Revision | 1.5 | bits 0–3 = 5 |
| → Model | Pi 4 Model B | bits 4–11 = 0x11 |
| → Processor | BCM2711 | bits 12–15 = 3 |
| → Manufacturer | Sony UK | bits 16–19 = 0 |
| → RAM | **4 GB** (confirmed) | bits 20–22 = 4 → 2⁴ × 256 MB |
| Board serial | `a88e9ee2` | bootloader trace |
| Boot ROM version (OTP) | `8b0` | `OTP boardrev c03115 bootrom 8b0 8b0` |
| eth0 MAC | `88:a2:9e:34:46:4d` | `ip a` |
| wlan0 MAC | `88:a2:9e:34:46:4e` | `ip a` |
| Hostname | `pi-mldsa-cpe` | — |
| User | `team_singularity` | — |

**Note on the three memory figures.** Three different numbers appear and all are consistent once
interpreted correctly:

| Source | Value | Meaning |
|---|---|---|
| `MEM GPU: 76 ARM: 948 TOTAL: 1024` | 1024 MB | Legacy 32-bit-addressable split only — **not** total RAM |
| `total-size: 32Gbit` | 32 Gbit = 4 GB | Total SDRAM |
| `free -h` | 3.7 GiB | 4 GB minus GPU carve-out and kernel reserves |
| Revision code bits 20–22 = 4 | 2⁴ × 256 MB = 4 GB | Total RAM |

**Correction (2026-09-08):** an earlier revision of this document recorded 8 GB. That was an
arithmetic error in the revision-code decode — memory field 4 encodes 4 GB, field 5 encodes 8 GB.
Corrected against `free -h`.

**BOM deviation:** the sponsor brief specifies an 8 GB unit ("best for compiling PQC libraries").
Actual is 4 GB. Adequate for building ML-DSA libraries, but record the deviation, and expect
longer compile times. If linking becomes memory-constrained, the 2 GB swap file (§3.5) absorbs it
at the cost of SD wear.

### 3.2 SPI flash (EEPROM)
| Field | Value |
|---|---|
| EEPROM ID | `0xef3013` (0xEF = Winbond) |
| SFDP | None |
| Part number decode | **[TO VERIFY]** |

### 3.3 Bootloader — **UPDATED 2026-09-08, see §5.3**
| Field | As-received | Current |
|---|---|---|
| Date | 2023/01/11 17:40:52 | **2026/05/17 20:13:18** |
| Git version | `8ba17717fbcedd4c3b6d4bce7e50c7af4155cba9` | `224877da90f82a72dbcc9db10bcf059259f54680` |
| Build timestamp | 1673458852 | 1779045198 |
| Update time | 0 | 1781743605 |
| Capabilities | `0x0000007f` | `0x0000007f` |
| MFG_VER | — | 1 |
| VL805 USB3 firmware | `000138c0` | `000138c0` (unchanged, current) |

### 3.4 VideoCore firmware
| Field | Value |
|---|---|
| Firmware hash | `288930ab4712b99596f32732664aaaeb881ef1e0` |
| Firmware build | May 21 2026 11:20:25 |
| `start4.elf` size | 2,305,632 bytes |
| `fixup4.dat` size | 5,499 bytes |

### 3.5 Operating system
| Field | Value |
|---|---|
| Distribution | Debian GNU/Linux 13 (trixie) |
| Image | Raspberry Pi OS Lite 64-bit |
| Image reference | Raspberry Pi reference 2026-06-18 |
| pi-gen commit | `ca8aeed0ae300c2a89f55ce9617d5f96a27e99e5`, stage4 |
| Kernel | `6.18.34+rpt-rpi-v8` |
| Kernel package | `1:6.18.34-1+rpt1` (2026-06-09) |
| Architecture | aarch64 |

**Rationale for Lite over Desktop:** the desktop environment adds seconds of unrelated userspace
startup, inflating the variance of `T_boot` and obscuring a sub-2-second PQC delta.

### 3.6 Storage — **PINNED, DO NOT SWAP**
| Field | Value |
|---|---|
| Reported capacity | 29.8 GiB (32 GB class) |
| CID | `001b534d454231515430a1f463e40155` |
| CSD | `400e00325b590000ee7f7f800a404000` |
| Manufacturer ID | `0x1b` (Samsung) |
| Product name | `EB1QT` |
| OCR | `c0ff8000` |
| SCR | `0x02858482` |
| Bus width | 4-bit |
| Spec version | 2 |
| **Negotiated mode** | **UHS-I DDR50** (not SDR104) |
| **Negotiated clock** | **50,000,000 Hz** |
| Controller | SDHCI on `fe340000.mmc`, ADMA |

**Deviation from BOM:** brief specifies 64 GB industrial-grade (SLC/pSLC). Actual is a 32 GB
consumer card negotiating DDR50 rather than the faster SDR104. **Document this deviation.**

**Endurance risk:** tamper testing (§8, metric M4) requires hundreds of power cycles, many
deliberately unclean mid-boot. This is aggressive wear for a consumer card. A worn card slows
down, which would make a late-semester measurement non-comparable to the early baseline even on
the same physical card. **Mitigation:** capture the card benchmark (§4.4) periodically, not once,
and record it alongside each timing run.

### 3.7 Partition layout
| LBA start | Sectors | Type | Purpose |
|---|---|---|---|
| `0x00004000` (16384) | 1,048,576 | `0x0c` FAT32 LBA | `bootfs` — 512 MB |
| `0x00104000` | 61,456,384 | `0x83` Linux | rootfs — ~29.3 GB |

Boot partition mounts at **`/boot/firmware`** on Bookworm/Trixie, *not* `/boot`.

### 3.9 Frozen service configuration — **DO NOT CHANGE AFTER B0 CAPTURE**

| Service | State | Reason |
|---|---|---|
| `NetworkManager-wait-online` | disabled | 7.2s pure timeout; largest variance source |
| `bluetooth` | disabled | Unused; attack surface on a security device |
| `avahi-daemon` | disabled | mDNS unused (serial + static IP) |
| `udisks2` | disabled | Removable-media handling, headless |
| `accounts-daemon` | disabled | Desktop user management, headless |
| `rpi-eeprom-update` | **masked** | **R-8 — prevents automatic EEPROM change mid-project** |
| `cloud-init` | disabled via `/etc/cloud/cloud-init.disabled` | Imager customization already applied |
| `e2scrub_reap` | disabled | LVM scrub reaping, not applicable |
| `NetworkManager` | **kept** | Required for Wi-Fi during library builds |
| `systemd-fsck` | **kept** | Safety mechanism; tamper testing involves many unclean power cuts |
| Default target | `multi-user.target` | Was `graphical.target` |
| `FIRMWARE_RELEASE_STATUS` | `default` | From `/etc/default/rpi-eeprom-update` |

EEPROM updates remain possible on demand via `sudo rpi-eeprom-update -a`. Masking makes an EEPROM
change a deliberate decision rather than something that happens automatically.

### 3.10 Boot time reduction (pre-baseline conditioning)

| Stage | Kernel | Userspace | Total |
|---|---|---|---|
| As-received | 2.113s | 15.998s | **18.112s** |
| After trim round 1 | 2.493s | 8.498s | **10.992s** |
| After trim round 2 (frozen) | 2.107s | 6.074s | **8.182s** |

**Reduction: 9.93s (55%).**

**Measured noise floor.** Kernel time across those three boots was 2.113s / 2.493s / 2.107s with
no kernel changes whatsoever — a 386 ms spread from run-to-run variance alone. Against an M1
target of < 2s that is a material fraction of the signal. This is the empirical justification for
§9.2 (n ≥ 10, report σ), and should be cited in the report rather than asserted.

Remaining top contributors after freeze: `NetworkManager` 2.288s, `dev-mmcblk0p2.device` 988ms,
`systemd-fsck` 692ms, `user@1000` 487ms. Further trimming has diminishing returns and would
remove functionality the project needs.

### 3.8 Host and serial console
| Field | Value |
|---|---|
| Host | macOS (MacBook Pro) |
| Serial device | `/dev/cu.usbserial-0001` |
| Terminal | picocom v3.1 |
| Line settings | 115200 8N1, no flow control, no parity |

Use the `/dev/cu.*` node. The `/dev/tty.*` node blocks waiting for carrier detect and will hang.

---

## 4. Reproducible bench setup

### 4.1 Serial console wiring (3.3V USB-TTL)
```
Adapter GND → Pi pin 6    (GND)
Adapter RX  → Pi pin 8    (GPIO14 / Pi TXD)
Adapter TX  → Pi pin 10   (GPIO15 / Pi RXD)
```

**Rule:** adapter *receive* listens to the Pi's *transmit*. TX/RX cross over.
**Do not connect the adapter's 5V line.** The Pi is powered from its USB-C PSU; backfeeding 5V
with both sources connected can damage the board.
**Adapter must be in 3.3V mode.** Pi GPIO is not 5V tolerant.

### 4.2 Two independent UART enables — both required
| Setting | File / tool | Enables output from |
|---|---|---|
| `enable_uart=1` | `/boot/firmware/config.txt` | Kernel and userspace |
| `BOOT_UART=1` | `rpi-eeprom-config --edit` | **EEPROM bootloader (pre-Linux)** |

`enable_uart=1` additionally pins the core clock so the mini-UART baud rate stays stable under
CPU load — without it, output corrupts precisely when the system is busy, i.e. during PQC
verification.

`BOOT_UART=1` is the one that matters for Phase II. Signature verification failures occur before
Linux exists; without it the failure mode is a dead board with no diagnostic output on any
interface. HDMI shows nothing at this stage.

Also confirm `console=serial0,115200` is present in `/boot/firmware/cmdline.txt` (single line,
unwrapped).

### 4.3 Recovery assets — **BUILD BEFORE PHASE II**
| Asset | Purpose | Status |
|---|---|---|
| EEPROM recovery SD card | Reflash EEPROM to known state after a bricking bootloader change | **NOT YET BUILT** |
| Known-good OS image card | Restore a working system without re-deriving config | **NOT YET BUILT** |
| Exported EEPROM config | `rpi-eeprom-config --out eeprom-baseline.txt` | **NOT YET CAPTURED** |

Build via Raspberry Pi Imager → Misc utility images → Bootloader → SD Card Boot.

### 4.4 Storage benchmark (repeat periodically, log each result)
```bash
cd /sys/block/mmcblk0/device/
for f in name manfid oemid serial date fwrev hwrev; do echo "$f: $(cat $f)"; done
dmesg | grep -i mmc0
sudo hdparm -t /dev/mmcblk0
sudo apt install -y fio
fio --name=randread --filename=/tmp/fiotest --size=512M \
    --rw=randread --bs=4k --iodepth=8 --numjobs=1 --runtime=30 \
    --time_based --group_reporting
```
Random 4k read IOPS predicts systemd startup time far better than sequential throughput.

---

## 5. Session log

### 5.1 Session 1 — 2026-09-08 — Bench bring-up
**Objective:** establish serial console and capture factory environment state.

**Actions:**
1. Flashed Raspberry Pi OS Lite 64-bit via Imager; preset hostname, user, SSH, Wi-Fi.
2. Wired 3.3V USB-TTL serial to GPIO header.
3. Added `enable_uart=1` to `/boot/firmware/config.txt` before first boot.
4. First boot; serial console established at 115200 8N1.
5. Captured environment fingerprint (§3).

**Result:** serial console operational. OS boots cleanly from SD.

### 5.2 Session 1 — Network status
`eth0` and `wlan0` both `NO-CARRIER` / `DOWN`. Wi-Fi never associated with the configured
hotspot SSID. Login banner reports `127.0.1.1`, which is Debian's `/etc/hosts` fallback entry,
not a real address.

**Not blocking today** (EEPROM images ship on-disk). **Blocking at Phase I step 3**, which
requires `apt` and git access to build the ML-DSA library.

**Recommendation carried forward:** move the bench to wired Ethernet or a dedicated lab router.
A phone hotspot is unsuitable as the foundation for the two-node demo, and `NetworkManager-
wait-online.service` sits in the systemd boot path — flaky association adds seconds of variance
directly on top of the sub-2-second delta being measured.

### 5.3 Session 1 — EEPROM update (**methodologically critical**)
As-received bootloader dated **2023-01-11**; latest available **2026-05-17**. Over three years of
bootloader changes were missing, including work in the signed-boot path that Phase II depends on.

```bash
sudo rpi-eeprom-update -a
sudo reboot
```

**Why this had to happen before baseline capture:** a bootloader update changes boot timing. If
`T_boot_classical` were captured on the 2023 EEPROM and `T_boot_pqc` on the 2026 EEPROM, the
measured delta would conflate the PQC cost with three years of unrelated bootloader changes. The
comparison would be invalid and the error would be invisible in the final number.

**Verified post-update:** `vcgencmd bootloader_version` reports 2026/05/17 20:13:18, matching
LATEST. VL805 unchanged (`000138c0`, already current).

### 5.4 Session 1 — `BOOT_UART=1` enabled
Set via `sudo -E rpi-eeprom-config --edit`. Confirmed effective: full pre-Linux bootloader trace
now appears on serial (Appendix A.1).

**Outstanding:** capture `rpi-eeprom-config` output verbatim into Appendix A.2. — **DONE**, see A.2.

EEPROM config as read back:
```
[all]
BOOT_UART=1
WAKE_ON_GPIO=1
POWER_OFF_ON_HALT=0
```

**Observation — no `BOOT_ORDER` set.** Default `0xf41` applies (SD → USB → restart), consistent
with `order f4` in the trace. **Phase II action:** pin `BOOT_ORDER` to SD only before enabling
signed boot, so an attacker cannot present a USB device as an alternate boot path.

### 5.5 Session 1 — Pre-baseline boot profile (unsigned, no network)

```
Startup finished in 2.113s (kernel) + 15.998s (userspace) = 18.112s
graphical.target reached after 8.655s in userspace
```

Top contributors (`systemd-analyze blame`):

| Service | Time | Assessment |
|---|---|---|
| `NetworkManager-wait-online.service` | **7.205s** | Pure timeout — no interface will ever come up. Largest single cost and largest variance source. **Disable.** |
| `NetworkManager.service` | 2.317s | Required if Wi-Fi is used |
| `cloud-init-main.service` | 1.749s | Applies Imager customization; already applied. Candidate for removal |
| `rpi-eeprom-update.service` | 1.120s | **See R-8 — this is a risk, not just a cost** |
| `dev-mmcblk0p2.device` | 1.078s | Storage enumeration |
| `accounts-daemon.service` | 960ms | Unnecessary on headless CPE |
| `udisks2.service` | 908ms | Unnecessary on headless CPE |
| `systemd-fsck@…` | 662ms | Variable — runs conditionally |
| `avahi-daemon.service` | 429ms | mDNS; unnecessary if using serial + static IP |
| `bluetooth.service` | 427ms | Unnecessary; also an attack surface on a security device |
| `cloud-init-local.service` | 376ms | See above |

**Note:** userspace total (15.998s) exceeds `graphical.target` (8.655s) because
`NetworkManager-wait-online` continues past target reach. Both figures should be recorded.

**Methodology consequence:** ~18s of boot with ~7s of pure network timeout is a poor substrate for
resolving a sub-2-second PQC delta. Service trimming must happen **before** B0 capture, and the
trimmed configuration becomes part of the frozen environment (§3). See §9.6.

---

### 5.6 Session 1 — B0 baseline capture (n=5, Linux segment only)

Method: `systemd-analyze >> ~/b0-results.txt && sudo reboot`, repeated. Network absent
throughout (D-07 state). No other sessions logged in.

| Run | Kernel | Userspace | Total |
|---|---|---|---|
| 1 | 2.116s | 6.094s | 8.210s |
| 2 | 2.460s | 6.089s | 8.550s |
| 3 | 2.129s | 6.148s | 8.278s |
| 4 | 2.458s | 6.038s | 8.497s |
| 5 | 2.466s | 6.087s | 8.553s |

| Statistic | Kernel | Userspace | Total |
|---|---|---|---|
| Mean | 2.326s | 6.091s | **8.418s** |
| σ | 186 ms | 39 ms | 162 ms |

**Finding — kernel init time is bimodal, not noisy.**

Values cluster into two tight groups roughly 340 ms apart:
- Low cluster: 2.116, 2.129 (internal spread 13 ms)
- High cluster: 2.458, 2.460, 2.466 (internal spread 8 ms)

Nothing lands between them. Earlier measurements taken under three *different* service
configurations show the same split (2.113 low, 2.493 high, 2.107 low), so this is not an artifact
of the trimming in §3.9.

**Why this matters:** reporting "8.418s ± 162ms" would misrepresent a bimodal distribution. More
seriously, if B0 draws mostly low-cluster boots and a later capture draws mostly high-cluster, a
340 ms difference appears that has nothing to do with cryptography — 17% of the M1 budget as pure
artifact. Userspace by contrast is stable at σ = 39 ms; effectively all variance is this one
kernel-side binary behaviour.

**Open — cause not yet identified.** Leading hypothesis is a kernel RNG entropy wait or a device
probe retry path. Diagnostic: capture `dmesg | head -60` on one fast and one slow boot and diff
the kernel timestamps to localise the 340 ms. Note this is not merely a nuisance — if boot-time
entropy availability is implicated, it connects directly to research avenue RA-8.

**Status: provisional.** n=5 rather than the n≥10 required by D-02. Sufficient to establish the
bimodality; extend to n≥10 before the figure is quoted in the report.

### 5.7 Session 1 — Checkpoint

**Completed:**

| Item | Outcome |
|---|---|
| Serial console | Operational, both UART levels (§4.2) |
| Environment fingerprint | Captured and frozen (§3) |
| EEPROM | Updated 2023-01 → 2026-05 **before** any measurement (§5.3) |
| Boot conditioning | 18.112s → 8.182s, 55% reduction, config frozen (§3.9, §3.10) |
| B0 baseline | n=5, Linux segment, bimodality identified (§5.6) |
| Phase I findings | F-01, F-02, F-03 recorded with hardware evidence (§7) |
| Methodology decisions | D-01 through D-08 recorded (§9) |
| Cross-team review | Measurement-point gap raised and resolved into M1a/M1b split (§9.8) |

**Not completed / blocked:**

| Item | Blocker |
|---|---|
| Network on Pi | Hotspot unavailable; campus Wi-Fi requires OIT registration (R-2, R-9) |
| ML-DSA library build | Blocked on network |
| Recovery cards | Not yet built — **blocks Phase II** (R-4) |
| OD-01 U-Boot decision | Open |
| B0 extension to n≥10 | Deferred, bench time |

**Time cost of documented errata this session:** approximately 30 minutes across E-01 through
E-05. All recorded in §13.

---

## 6. Observed boot chain — annotated

Full trace in Appendix A.1. Stage structure as observed:

| Stage | Evidence | Crypto |
|---|---|---|
| BOOTSYS | `RPi: BOOTSYS release VERSION:224877da` | — |
| SDRAM init | `init_sdram_1350`, `DDR 3200 Mbps dual-rank:1` | — |
| OTP read | `OTP boardrev c03115 bootrom 8b0 8b0` | — |
| BOOTLOADER | `RPi: BOOTLOADER release VERSION:224877da` | — |
| PCIe / xHCI init | `PCIe scan 00001106:00003483` | — |
| SD init | `OCR c0ff8000`, mode negotiation to 50 MHz | — |
| Partition select | `Trying partition: 0` → `1` | — |
| Config read | `Read config.txt bytes 1286` | — |
| **EEPROM self-check** | **`pieeprom.sig` + SHA-256 hash** | **RSA-2048** |
| Firmware load | `Read start4.elf bytes 2305632` | — |
| Handoff | `Starting start4.elf @ 0xfec00200 partition 1` | — |
| Linux | `Debian GNU/Linux 13 pi-mldsa-cpe ttyS0` | — |

### 6.1 Boot mode
`BOOTMODE: 0x06 partition 0` — SD card boot. `Boot mode: SD (01) order f4`.

### 6.2 Timestamps are NOT monotonic — **do not use for timing**
The trace shows `3.92` followed by `3.32`, and `4.55` followed by `4.26`. The bootloader prints
from more than one clock source and the values are not a single consistent timebase.

**Consequence:** `T_boot_classical` and `T_boot_pqc` must be derived from **host-side
timestamping** of the serial stream, never from these figures. See §9.1.

---

## 7. Threat model — evidence-backed findings

These are observations from our own hardware, not literature citations. That distinction matters
in the writeup: an observed finding is stronger evidence than a cited one.

### 7.1 F-01 — OTP customer key slot is empty (factory state)
**Evidence:** `Customer key hash 0000000000000000000000000000000000000000000000000000000000000000`

No customer public key is programmed. Secure boot is **not** enabled. This is the documented
factory baseline and the exact field that changes when OTP is burned in Phase II step 10.

**Action:** screenshot preserved. This "before" state cannot be recreated after burning — OTP is
one-time programmable and irreversible.

### 7.2 F-02 — VideoCore JTAG is unlocked
**Evidence:** `VC-JTAG unlocked`

The VideoCore JTAG interface is not locked in OTP. This is a physical-access attack surface
reported by the device itself.

**Research required** (do not assert exploitability without demonstrating it): what is reachable
over VC-JTAG in this state, whether it permits observation or modification of the boot flow, and
whether locking it is a separate OTP operation from `SIGNED_BOOT`. This maps directly to the
sponsor brief's "Key in the Clear" question about bypassing OTP with physical access.

### 7.3 F-03 — RSA-2048 mechanism confirmed, but it does NOT verify the OS today
**Revised 2026-09-08 after second boot trace. The original wording overstated the finding.**

Boot 1 (immediately post-EEPROM-update) showed:
```
pieeprom.sig
hash: b637fee5fc6e78791ecb631b1e3b7a49c7f91cd5ca9d0bd8249d7acaeed3413d
ts: 1781743727
SELF-UPDATE timestamp current 1781743727 new 1781743727 skip
```

Boot 2 (after `rpi-eeprom-update.service` cleaned up the staged files) showed:
```
[sdcard] pieeprom.upd not found
```

**Interpretation:** `pieeprom.sig` belongs to the **EEPROM self-update** path. It authenticates a
staged replacement EEPROM image (`pieeprom.upd`), not `boot.img` and not the kernel. Once the
staged files were removed, the lines disappeared entirely.

**Corrected finding — and this is the stronger one:**

> With `Customer key hash` all zeros and `SIGNED_BOOT` unset, the device currently performs
> **no cryptographic verification whatsoever** of the OS image it boots. Any modification to
> `boot.img`, the kernel, or the rootfs boots without complaint. The RSA-2048 mechanism exists in
> the bootloader but is presently exercised only for EEPROM self-updates.

This is the true "before" state for M4 (tamper resilience) and makes the Phase II delta sharper:
the project moves the device from *zero* verification to ML-DSA-65 verification, with RSA-2048
gating the first link.

**Method note:** this correction only became visible because the same trace was captured twice
under different conditions. Single-capture conclusions are fragile — repeat traces before
asserting a mechanism.

### 7.4 F-04 — Shor's algorithm impact on this specific chain
Per the brief's Phase I requirement, quantify: a CRQC running Shor's algorithm reduces RSA-2048
to negligible security. Applied to F-03, this means the *entire* classical anchor above our
ML-DSA insertion point collapses. Write this up against the observed chain in §6, not in the
abstract.

### 7.5 F-05 — SPI bus exposure (pending, Phase III)
The EEPROM is external SPI flash (`0xef3013`). The bus between SoC and flash is unencrypted on
PCB traces. Same class of exposure as the TPM SPI-snooping avenue in the brief. Investigate
whether EEPROM contents can be observed or modified in transit with a logic analyser.

---

## 8. Metrics register

Derived from the sponsor brief. Status updated each session.

| ID | Metric | Definition | Target | Status |
|---|---|---|---|---|
| **M1a** | **Bootloader-segment overhead** | Time delta across the ML-DSA verify call, measured *inside* the bootloader | < 2 s combined with M1b | **Not started — this is where PQC cost actually appears** |
| M1b | Linux-segment overhead | `systemd-analyze` delta, Linux init → login | No regression | **B0 captured, n=5** |
| M2 | Memory footprint | Code size of PQC verify library in bootloader | < 128 KB | Not started |
| M3 | Signature size efficiency | Ratio of signature size to firmware size | Minimise | Not started |
| M4 | Tamper resilience | Failure-to-boot on single-bit firmware modification | 100% detection | Not started |
| M5 | Quantum security level | NIST security category achieved | ≥ Category 3 | ML-DSA-65 selected |
| M6 | Peak stack / SRAM | Peak memory during early-boot verification | Fits early-boot SRAM | Not started |

**Why M1 was split (2026-09-08).** See §9.8. A single `systemd-analyze` number cannot measure
this project's headline metric, because signature verification happens before Linux starts.

### 8.1 M5 — parameter set selection
FIPS 204 parameter sets:

| Set | NIST category | Public key | Signature | Private key |
|---|---|---|---|---|
| ML-DSA-44 | 2 | 1,312 B | 2,420 B | 2,560 B |
| **ML-DSA-65** | **3** | **1,952 B** | **3,309 B** | **4,032 B** |
| ML-DSA-87 | 5 | 2,592 B | 4,627 B | 4,896 B |

**ML-DSA-65 selected** — the smallest parameter set meeting the brief's Category 3 floor.

---

## 8A. Measured results — Session 2 (2026-09-09)

Implementation under test: `pq-code-package/mldsa-native`, AArch64 backend, ML-DSA-65,
built and measured on the Pi 4B target (not cross-compiled, not estimated).

### 8A.1 D-05 correctness — SATISFIED (Phase I deliverable)

`make test` passed, including **241 ACVP verify test cases** (`tcId=1..241 ... ok`,
`241 verify tests passed`, `ALL GOOD!`). ACVP is NIST's own validation vector format, so this is
known-answer validation against the standard rather than self-consistency testing.

Additionally passed: Wycheproof test vectors, ABI checks for every AArch64 assembly routine, and
RNG-failure handling tests.

**Claim now supportable:** a formally verified ML-DSA-65 implementation passes NIST known-answer
tests on the target hardware. This is materially stronger than "we used a library."

### 8A.2 M2 — code size (upper bounds)

`size` output, `text` segment = code:

| Binary | Text (bytes) | % of 128 KB |
|---|---|---|
| `gen_KAT65` | 56,586 | 43% |
| `wycheproof_mldsa65` | 59,725 | 46% |
| `acvp_mldsa65` | 67,160 | 51% |
| `test_sign_hook65` | 67,676 | 52% |
| `test_unit65` | 69,409 | 53% |
| `test_rng_fail65` | 76,665 | 59% |
| `test_mldsa65` | 78,737 | 60% |
| `test_alloc65` | 84,057 | 64% |

**These are upper bounds, not the reportable M2 figure.** Every binary includes keygen, sign,
verify, the test harness, and libc startup. The bootloader needs verify only, for one parameter
set. A verify-only monolithic build (`examples/monolithic_build`) is required for the honest
number. **Action: build and measure it.**

Even so, the worst case sits at 64% of budget, so there is no order-of-magnitude risk.

### 8A.3 M6 — peak stack (verify path)

Measured with `scripts/stack` (GCC `-fstack-usage` + valgrind massif):

| API | Peak stack |
|---|---|
| KeyGen | 56,720 B |
| Sign | 82,032 B |
| **Verify** | **46,400 B** |

**The bootloader figure is Verify: 46,400 bytes (~45.3 KB).** Sign and KeyGen belong to the
offline host signing infrastructure and are out of scope for the device budget.

**ADR-001 prediction confirmed.** The expanded public matrix A for ML-DSA-65 is
6 × 5 × 256 × 4 = **30,720 bytes**, which is **66% of measured verify stack**. Matrix expansion
dominates, exactly as predicted in §10.1. This identifies `MLD_CONFIG_REDUCE_RAM` /
`examples/basic_lowram` as the correct lever, and makes the on-the-fly vs expanded comparison a
directly measurable result rather than a hypothesis.

### 8A.3b RA-7 / M6 — `MLD_CONFIG_REDUCE_RAM` comparison

Same binary (`test/build/mldsa65/bin/test_stack65`), same build target, one variable changed:
line 263 of `mldsa/mldsa_native_config.h`.

| Measure | Baseline | REDUCE_RAM | Change |
|---|---|---|---|
| Verify peak stack | 46,400 B | **16,736 B** | −29,664 B (−63.9%) |
| Sign peak stack | 82,032 B | 22,448 B | −59,584 B (−72.6%) |
| KeyGen peak stack | 56,720 B | 23,600 B | −33,120 B (−58.4%) |
| Code size (`text`) | 56,536 B | **53,172 B** | −3,364 B (−5.9%) |
| Combined (code + verify stack) | 102,936 B | **69,908 B** | −33,028 B |
| % of 128 KB budget | 80.4% | **54.6%** | −25.8 pts |

**Analytic prediction confirmed to within 3.4%.** ADR-001 (§10.1) predicted that expansion of the
public matrix A dominates verify memory, at 6 × 5 × 256 × 4 = **30,720 bytes**. Measured stack
saving from enabling REDUCE_RAM: **29,664 bytes**. The mechanism is therefore identified, not
merely observed — REDUCE_RAM generates rows of A on demand rather than materialising all thirty
polynomials at once.

**Result is not a trade on the measured axes.** REDUCE_RAM reduces *both* stack and code size.
The code reduction is explained by the lazy path omitting the bulk expand-and-store routines
entirely. The cost must therefore fall on **runtime**, which is not yet measured.

**Open — third axis (feeds M1a):** measure verify wall-clock time on the Pi 4 under both
configurations. A three-axis table (stack / code / time) is the substantive RA-7 deliverable;
without the time column the result looks implausibly free.

**Caveat:** both code-size figures are from a test binary including harness and libc startup, so
they are upper bounds. A verify-only monolithic build (`examples/monolithic_build`) is still
required for the reportable M2 figure.

### 8A.3c RA-7 — complete three-axis characterisation

Benchmarked on target: Pi 4B rev 1.5, **1.8 GHz** (stock for this revision — no overclock in
`config.txt`), `performance` governor pinned, 44–48 °C, no thermal throttling.
`make bench_65 CYCLES=PERF`.

#### Verify path — the only operation the bootloader performs

| Axis | Baseline | REDUCE_RAM | Change |
|---|---|---|---|
| Peak stack | 46,400 B | **16,736 B** | **−63.9%** |
| Code size (`text`) | 56,536 B | **53,172 B** | −5.9% |
| Verify cycles | 382,097 | 549,048 | **+43.7%** |
| Verify wall-clock @ 1.8 GHz | 0.212 ms | **0.305 ms** | **+0.093 ms** |
| Combined memory (code + stack) | 102,936 B | **69,908 B** | −32.1% |
| % of 128 KB budget | 80.4% | **54.6%** | −25.8 pts |

#### All operations (cycles, average)

| Operation | Baseline | REDUCE_RAM | Ratio |
|---|---|---|---|
| KeyGen | 390,870 | 556,178 | 1.42× |
| Sign | 1,020,132 | 3,339,375 | 3.27× |
| **Verify** | **382,097** | **549,048** | **1.44×** |

Sign degrades far more than verify because Fiat-Shamir rejection sampling repeats the matrix
operation per attempt. Irrelevant to the device: signing is offline, on a host.

#### DECISION — enable `MLD_CONFIG_REDUCE_RAM` in the bootloader build

**Rationale.** Memory is the binding constraint in early boot; time is not. The trade buys 29,664
bytes of stack for **0.093 ms**, which is **0.005% of the 2-second M1 budget**. Roughly 320 KB of
stack saved per millisecond spent. In a context where SRAM is measured in tens of kilobytes and
the latency budget in seconds, this is not a close call.

**To revisit** only if verify time ever becomes the binding constraint — which, given the I/O
analysis below, it will not.

#### 8A.3d Verify timing is deterministic — an argument for ML-DSA in a boot path

| Operation | 1st pct | 99th pct | Spread |
|---|---|---|---|
| Verify (baseline) | 381,496 | 383,000 | **0.39%** |
| Verify (REDUCE_RAM) | 548,463 | 549,799 | **0.24%** |
| Sign (baseline) | 477,293 | 3,216,191 | 6.7× |
| Sign (REDUCE_RAM) | 717,453 | 13,918,327 | **19.4×** |

Verification is essentially constant-time in the performance sense; signing varies by up to 19×
because of rejection sampling. The architecture places the deterministic operation on the device
and the variable one offline.

**This is a positive argument for the design, not just an observation.** A boot-time signature
check with a 0.24% timing spread is predictable enough to budget for exactly; a signing operation
with 19× variance would not be.

#### 8A.3e Consequence for M1a — ML-DSA is not the cost

Verify of a short message costs **0.305 ms**. Real boot verification must hash the entire signed
artifact — kernel plus initramfs, tens of megabytes — read from a **DDR50 card negotiated at
50 MHz** (§3.6).

**Expectation: M1a will be dominated by storage I/O and SHA-3 hashing of the payload, not by
lattice arithmetic.** The ML-DSA signature check itself is ~0.3 ms against a 2,000 ms budget.

This confirms D-04 (§9.4) with measured data and sharpens the instrumentation requirement from
§9.8: M1a instrumentation must separate **artifact read**, **payload hash**, and **signature
verify**, or the reported "PQC overhead" will be almost entirely storage time misattributed to
cryptography.

### 8A.3f M2 FINAL — monolithic library build

Built from `examples/monolithic_build`, which produces the single auto-generated
`mldsa_native.c` compilation unit — the same artifact intended for U-Boot embedding. Measured on
the library object only (`mldsa_native65.o`), excluding test harness and libc.

Note: this example carries its **own** config header (`mldsa_native/mldsa_native_config.h`,
line 278), separate from the main tree. Both were measured.

| Configuration | `text` | `data` | `bss` |
|---|---|---|---|
| REDUCE_RAM off | 39,864 B | 0 | 0 |
| **REDUCE_RAM on** | **35,968 B** | **0** | **0** |
| Saving | 3,896 B (−9.8%) | — | — |

**`data` and `bss` are both zero.** The library carries no static or global state; all working
memory is on the stack. Two consequences worth stating in the report:
- Nothing to initialise and no writable data section to place — near-ideal for a bootloader.
- **M2 (code) + M6 (stack) is the complete memory picture.** There is no hidden third component.

#### Final memory budget — chosen configuration (ML-DSA-65, REDUCE_RAM, AArch64)

Budget taken as 128 KiB = 131,072 bytes.

| Component | Bytes | % of budget |
|---|---|---|
| Library code (`text`) | 35,968 | 27.4% |
| Verify peak stack | 16,736 | 12.8% |
| Static / global data | 0 | 0.0% |
| **Total** | **52,704** | **40.2%** |

**Headroom: 78,368 bytes (59.8%).**

**Still an upper bound.** This build includes keygen and signing, which the bootloader never
invokes. A verify-only build would be smaller again. Given 60% headroom, further reduction is not
required — noted for completeness rather than pursued.

#### 8A.3g Summary — measured metrics, ML-DSA-65 on Pi 4B @ 1.8 GHz

| Metric | Target | Measured | Status |
|---|---|---|---|
| M2 code size | < 128 KB | **35,968 B (27.4%)** | **PASS** |
| M6 verify stack | Fits early-boot SRAM | **16,736 B (12.8%)** | **PASS** |
| M2 + M6 combined | < 128 KB | **52,704 B (40.2%)** | **PASS** |
| M5 security level | ≥ Category 3 | **Category 3** | **PASS** |
| D-05 correctness | NIST KAT | **241 ACVP vectors passed** | **PASS** |
| Verify latency | (contributes to M1) | **0.305 ms** | Measured |

**Phase I conclusion: ML-DSA-65 secure boot is feasible on BCM2711 within the sponsor's stated
memory constraint, with approximately 60% headroom, using a formally verified implementation
validated against NIST test vectors on the target hardware.**

### 8A.4 Combined feasibility

Verify-only code (< 57 KB upper bound) + verify stack (46.4 KB) ≈ **under 105 KB against a 128 KB
budget**, before any low-RAM optimisation. **Conclusion: ML-DSA-65 verification is feasible within
the stated early-boot memory constraint on BCM2711.**

### 8A.5 Incidental finding — verification consumes no randomness

Build output reported `Skipping verify (no randombytes() calls)`. ML-DSA verification operates
solely on public data (public key, message, signature).

Two consequences for the research avenues:
- **RA-4 (side-channel defence):** power and EM analysis target secret-dependent operations. The
  bootloader verify path handles no secrets, so side-channel hardening is properly scoped to the
  **offline signing** infrastructure, not the device. This narrows RA-4 substantially and should
  be stated explicitly.
- **RA-8 (entropy / HRNG):** the boot verification path requires no entropy source, decoupling
  secure boot from RNG availability at boot.

Both findings are supported by tool output rather than literature.

---

## 8B. Milestone 2 progress — signing infrastructure (Session 3, 2026-09-10)

Implements ADR-001 action items 3 and 4. Source in `pi-trust-signing/`.

### 8B.1 Toolchain built and working end-to-end

| Tool | Runs on | Function |
|---|---|---|
| `pt-keygen` | host | ML-DSA-65 keypair → `<name>.pk` (0644), `<name>.sk` (0600) |
| `pt-manifest.sh` | host | SHA-256 each artifact into a signed-manifest text file |
| `pt-sign` | host | manifest + secret key → 3,309-byte signature |
| `pt-verify` | **device** | manifest + signature + public key → exit 0 / 1 |

Built on target with `-Wall -Wextra -std=c99 -O2` against the monolithic
`mldsa_native.c`. **No warnings.**

### 8B.2 Observed sizes match FIPS 204 exactly

| Artifact | Observed | FIPS 204 spec |
|---|---|---|
| Public key | 1,952 B | 1,952 B |
| Secret key | 4,032 B | 4,032 B |
| Signature | 3,309 B | 3,309 B |

Independent confirmation that the build is genuinely ML-DSA-65 (Category 3),
not a mis-selected parameter set — supports M5.

### 8B.3 Manifest format v1

```
# pi-trust-manifest v1
# created: 2026-09-10T20:39:56Z
# algorithm: ML-DSA-65 (FIPS 204)
# context: pi-trust-manifest-v1
# artifacts: 1
9583169dead8df8f0216be4b7555f350ec314a538143696be63437d5804fda47  fake-kernel.img
```

Design points:
- **The whole file is signed, headers included.** Version, algorithm, and
  context fields cannot be altered without breaking the signature.
- **Hash lines are `sha256sum -c` compatible.** After the signature verifies,
  artifact integrity can be checked with standard tooling.
- **Observed manifest size: 218 bytes.** This is why verify cost is independent
  of kernel size — the lattice operation runs over a few hundred bytes
  regardless. Payload hashing scales; the signature check does not.

**Verification order is mandatory:** signature first, then hashes. Checking
hashes from an unverified manifest proves nothing.

### 8B.4 Domain separation

All signatures use FIPS 204 context string `"pi-trust-manifest-v1"`. A
signature over a boot manifest cannot be replayed as valid for any other
purpose using a different context, even under the same key. Changing the string
invalidates all prior signatures; it is part of the format version.

### 8B.5 M4 — first tamper-resilience evidence

| Test | Input | Result |
|---|---|---|
| Positive | unmodified manifest | `SIGNATURE VALID` |
| **Negative** | **one byte appended (218 → 219)** | **`SIGNATURE INVALID`** |

**The negative test is the load-bearing one.** A verifier that returns success
unconditionally passes the positive test. Only the rejection demonstrates the
check is real.

**Not yet full M4.** The sponsor metric requires failure-to-boot on a
**single-bit** modification of the firmware. This test appended a whole byte to
the manifest. Remaining work:
1. Single-bit flip inside an artifact → manifest hash mismatch detected
2. Single-bit flip inside the signature → `mldsa_verify` rejects
3. Single-bit flip inside the manifest → `mldsa_verify` rejects
4. All three wired to actual boot failure, not just a non-zero exit code

### 8B.6 Security properties implemented

- **Fail-closed.** `rc` initialised to 1 in `pt_verify.c`; only explicit success
  sets it to 0. No "verification unavailable, proceeding anyway" branch exists.
- **Key separation.** Secret key never present on the device. `pt-verify` links
  no signing or keygen code path.
- **Real entropy.** `getrandom(2)` replaces the test-only RNG shipped with
  mldsa-native. `pt-verify` links no RNG at all — verification makes zero
  `randombytes()` calls (§8A.5).
- **No silent overwrite.** `pt_write_file` uses `O_EXCL`; replacing a key is a
  deliberate act.

### 8B.7 Known gaps — carry to Phase II

| Gap | Impact | Plan |
|---|---|---|
| **No anti-rollback** | An old validly-signed manifest can be replayed | OTP counter or monotonic version enforcement |
| DEV key only | Laptop-generated, no ceremony, no HSM | Production key ceremony is a Phase II deliverable |
| `memset` key scrub | Compiler may optimise it away | Use `explicit_bzero()` before handling a production key |
| Manifest paths not canonical | `sha256sum` records paths as given | Run from the artifact directory; consider path normalisation |

**Anti-rollback is the significant one.** Signature verification alone does not
prevent an attacker presenting an older, genuinely signed firmware with a known
vulnerability. Worth naming explicitly in the report rather than leaving as an
unstated assumption.

---

## 8C. External findings — literature review (Session 3, 2026-09-10)

Sourced from Raspberry Pi official documentation and engineer statements on the
official forums. **All three items below need first-hand verification before
they drive a decision** — they are recorded here as leads, not settled facts.

### 8C.1 F-06 — Raspberry Pi OS may be unusable as the signed-boot target

**Source:** Raspberry Pi engineer, official forums (thread 352061). The stated
position is that Raspberry Pi OS does not support secure-boot, and that a
custom buildroot- or Yocto-style OS image is required. The `usbboot` repository
ships a secure-boot example generated from a `raspberrypi-signed-boot`
buildroot configuration.

**Why this matters.** The current device (§3.5) runs Raspberry Pi OS Lite
(Debian 13). If secure boot requires a buildroot/Yocto image, then:

1. The Phase II target OS is **not** the OS currently installed.
2. Buildroot/Yocto work must start earlier than Milestone 2 currently assumes.
3. **B0 becomes non-comparable.** A different OS has entirely different boot
   timing, so the n=5 baseline in §5.6 would need re-capturing against the new
   image. The service-trim work in §3.9 would also not transfer.

**This is potentially the largest schedule risk identified so far** and is
larger than the U-Boot integration itself.

**VERIFY FIRST:** read `usbboot/docs/secure-boot.md` and the
`secure-boot-example` directory directly. Determine whether RPi OS is genuinely
incompatible, or merely unsupported-but-workable. The distinction decides
whether this is a plan change or a footnote.

### 8C.2 F-07 — OTP key is readable from a running secure-boot system

**Source:** `usbboot/docs/secure-boot.md`, Raspberry Pi official.

The documentation states that Raspberry Pi computers have no secure hardware
enclave; within a secure-boot OS image the key is accessible to any process
with access to `/dev/vcio` (vcmailbox), and it is not possible to prevent code
running in ARM supervisor mode — e.g. kernel code — from accessing OTP hardware
directly.

**Significance.** This is a vendor-documented limitation, which makes it
stronger evidence than F-02 (JTAG unlocked, observed) for the brief's
**RA-5 "Key in the Clear"** avenue. It establishes that on this platform:

- OTP protects the *boot flow*, not the *key confidentiality*.
- Any kernel-level compromise yields the OTP contents.
- The security boundary is "unsigned code cannot boot", **not** "the key cannot
  be extracted".

**Consequence for the threat model (§2.3).** The residual-risk statement should
be widened. It currently covers only the quantum-vulnerable RSA link. It should
also cover: a post-boot kernel compromise can read OTP, so the root of trust
protects boot integrity but not key secrecy. This strengthens the argument for
the external TPM in Tier 2 of the BOM (RA-2) — a discrete secure element does
have the enclave property the SoC lacks.

### 8C.3 F-08 — Device tree blobs live outside the FIT image on Pi

**Source:** Embedded Computing Design, "How to Enable Secure Boot on Raspberry
Pi 4".

DTBs are reported to reside in the bootloader partition rather than inside the
FIT image, unlike the typical U-Boot arrangement.

**Consequence for ADR-001.** If the DTB is outside the signed FIT, it is
outside ML-DSA coverage — and a device tree is powerful enough to matter
(it can alter memory maps, disable devices, change kernel command line
handling). Determine during Milestone 3 whether the DTB can be brought inside
the signed payload, and if not, document it as an explicit gap in coverage
rather than allowing it to pass unexamined.

### 8C.4 Corroboration of §2 architecture

A Raspberry Pi engineer's forum description of the boot flow matches the
architecture recorded in §2 and ADR-001: everything in `bootfs` (`start4.elf`,
`fixup4.dat`, `config.txt`, and U-Boot if used) is packed into a `boot.img`,
which is signed with an **RSA-2048** keypair; the firmware runs it only if the
signature checks out, after which maintaining the chain of trust is U-Boot's
responsibility.

This is independent corroboration of the central constraint (RSA-2048, not
replaceable) and of the U-Boot chainload approach chosen in ADR-001. It remains
a forum statement rather than a specification; verify against
`usbboot/docs/secure-boot.md`.

---

## 8D. R-10 RESOLVED — primary-source research (Session 3, 2026-09-10)

**Sources (authoritative, fetched directly):**
- `raspberrypi/usbboot` → `docs/secure-boot.md`
- `raspberrypi/rpi-image-gen` → README

### 8D.1 VERDICT — buildroot is NOT required. R-10 downgraded.

Raspberry Pi's own secure-boot documentation states that before programming
secure-boot a suitable OS image must be created, and **recommends `rpi-image-gen`
to generate custom Debian-based operating system images**, noting that Yocto or
Buildroot are also possible.

`rpi-image-gen`'s quick-start config is `config/trixie-minbase.yaml`, producing
`deb13-arm64-min.img` — **Debian 13 Trixie, arm64**. That is the same
distribution and release already running on the device (§3.5).

**F-06 was directionally right but overstated.** The forum statement that "RPi OS
doesn't support secure-boot" is accurate as far as it goes — a stock Raspberry Pi
OS *install* cannot be signed as-is — but the conclusion "therefore buildroot" was
wrong. The supported path is a custom **Debian** image built with a
Raspberry-Pi-maintained tool.

| Original fear | Reality |
|---|---|
| Must abandon Debian for buildroot/Yocto | Debian 13 stays; `rpi-image-gen` is the *recommended* route |
| Unfamiliar toolchain from scratch | Declarative YAML config, pre-built Debian packages |
| Build host required | Runs natively on Raspberry Pi OS 64-bit — buildable on our own Pi |
| Secure-boot setup done by hand | `rpi-sb-provisioner` automates signed boot + encrypted FS |

**Residual truth in F-06:** the current install still cannot be signed as-is,
because `boot.img` must be a self-contained ramdisk (§8D.3). A custom image build
*is* required — just not a different OS family. B0 will still need re-capturing
against the new image; §3.9 service trim may partially transfer since the base is
the same Debian release.

### 8D.2 Verified chain of trust — supersedes §6 inference

Actual stage names and verification steps, per official documentation:

| # | Stage | Verifies | Key |
|---|---|---|---|
| 1 | SoC BootROM (fused silicon, immutable root of trust) | `bootsys` is signed by a valid Raspberry Pi BootROM key | **Raspberry Pi's** |
| 2 | `bootsys` | Customer public key from EEPROM against customer key hash in OTP | — |
| 3 | `bootsys` | Each firmware dependency's hash against a list embedded in `bootsys` at build time | hash list |
| 4 | `bootmain` | `boot.img` hash matches `boot.sig`, and the RSA signature in `boot.sig` validates against the customer public key | **Customer's RSA-2048** |
| 5 | `bootmain` | Loads `start.elf` and starts the OS **only from the verified ramdisk** | — |

On any signature or hash failure, the boot mode is aborted and firmware advances
to the next boot mode.

**§2 CONFIRMED.** RSA-2048 is stated three separate ways: secure boot requires a
2048-bit RSA keypair; the key length must be 2048 bits; and `rpi-eeprom-digest`
produces sha256 + a hex-format RSA PKCS#1 v1.5 signature. The central constraint
in §2 and ADR-001 is verified against primary source.

Chain-of-trust diagram for our SoC:
`usbboot/docs/secure-boot-chain-of-trust-2711.pdf` — obtain and include in the
report.

### 8D.3 `boot.img` contents — defines the ML-DSA insertion point

`boot.img` is a self-contained ramdisk (FAT image) that must contain:

- `config.txt`
- **Device tree and overlay files**
- GPU firmware (`start.elf`, `fixup.dat`)
- Linux kernel image
- Linux initramfs containing the application, or scripts to mount/create an
  encrypted filesystem

Everything in it is covered by the single RSA-2048 signature in `boot.sig`.

### 8D.4 F-08 CORRECTED — device trees ARE inside the signed image

The earlier finding (§8C.3), sourced from a third-party article, claimed DTBs sit
in the bootloader partition outside the FIT image. **Primary source contradicts
this:** device tree and overlay files are explicitly listed as `boot.img`
contents, therefore covered by the RSA signature.

The third-party claim likely referred to a U-Boot FIT-image arrangement, which is
a different structure. **R-12 is closed.** No unsigned-DTB gap exists in the
stock flow — though if ADR-001's U-Boot path is taken, DTB placement relative to
the FIT must be re-examined at that point.

**Method note:** this is the second time a third-party source has been corrected
by primary documentation this session. Prefer `raspberrypi/*` repositories and
`raspberrypi.com/documentation` over blogs and forum posts for anything
load-bearing.

### 8D.5 F-09 (NEW) — Pi 4 cannot pin the bootloader version; Pi 5 can

Directly stated in the documentation:

- **BCM2711 (Pi 4, our hardware):** the boot ROM checks only that `bootsys` is
  signed by *Raspberry Pi's* key.
- **BCM2712 (Pi 5):** when secure-boot is enabled the boot ROM requires `bootsys`
  to be signed by Raspberry Pi's private key **and counter-signed with the
  customer's private key**, allowing the customer to authorise specific bootloader
  firmware versions — a firmware update cannot be installed unless the customer
  signs it.

**Security consequence for this project.** On our SoC, the customer key gates
`boot.img` but **not the bootloader firmware itself**. Any bootloader image
carrying a valid Raspberry Pi signature satisfies the ROM — including older
releases. We cannot cryptographically pin which bootloader version runs.

**Attack to investigate (RA-5):** can an attacker with physical access install an
older, genuinely Raspberry-Pi-signed bootloader that predates or mishandles
secure-boot enforcement, and thereby bypass verification entirely? This is a
concrete, testable hypothesis on our exact hardware, and it is a *stronger*
finding than F-02 (JTAG unlocked) because it is a documented architectural
difference rather than an observed state.

**Report framing:** this is a second hardware-generation limitation of the Pi 4,
alongside the RSA-only ROM in §2. Both point the same direction — BCM2711 predates
the threat model this project addresses. Stating both plainly is stronger than
implying the platform is more capable than it is.

### 8D.6 F-10 (NEW) — official tooling already supports HSM signing

`rpi-eeprom-digest` accepts `-H <wrapper>` to delegate the RSA signing operation
to an external HSM wrapper script instead of reading a private key from a `.pem`
file. The wrapper interface is:

```
hsm-wrapper -a rsa2048-sha256 INPUT_FILE
```

writing the raw signature as a hex string to stdout. The same mechanism works via
`update-pieeprom.sh` for signing the EEPROM config, keeping the private key
entirely inside the HSM.

**Why this matters.** The Phase II key-ceremony deliverable (§10.2 / README) now
has a defined integration point rather than being an abstract requirement. This
connects directly to **Tier 2 of the BOM** — the Infineon OPTIGA TPM 2.0 and
Zymkey 4i are candidate backends for that wrapper. A working HSM-backed signing
flow would be a substantive Phase II result and addresses RA-2.

### 8D.7 No firmware-level disk encryption — dm-verity is ours to build

The documentation states plainly that there is **no support in the ROM or
firmware for full-disk encryption**. Secure boot loads kernel + initramfs from a
single `boot.img` on an unencrypted FAT/EFI partition. The recommended approach is
a LUKS container mounted by scripts inside the initramfs, with the passphrase
derivable from a key stored in OTP.

**Our variant:** we need *integrity*, not confidentiality, so **dm-verity with an
ML-DSA-signed root hash** replaces LUKS in that slot. Same architectural position
— initramfs gates the rootfs — different primitive, and a defensible deviation to
document.

Note the OTP-derived-passphrase pattern is undermined by F-07 anyway (OTP readable
via `/dev/vcio`), which is a further argument for the integrity-based approach.

### 8D.8 Consequences for ADR-001

The decision stands, but the calculus is refined now that `boot.img` contents are
known.

| Path | Coverage |
|---|---|
| **Option B — initramfs verifier** | `boot.img` (config.txt + DTB + firmware + kernel + initramfs) under **RSA-2048**; rootfs under **ML-DSA** via dm-verity |
| **Option A — U-Boot** | `boot.img` (config.txt + DTB + firmware + `u-boot.bin`) under **RSA-2048**; kernel *and* rootfs under **ML-DSA** |

Two updates to the ADR:

1. **Option B is cheaper than estimated.** `rpi-sb-provisioner` automates signed
   boot and encrypted-filesystem setup, and the initramfs-gates-rootfs pattern is
   the documented, supported arrangement. Milestone 2 leans on official tooling
   rather than bespoke work.
2. **Option A's advantage is now precisely stated.** It moves the *kernel* from
   RSA to ML-DSA coverage. Under Option B the kernel is inside `boot.img` and
   therefore RSA-only. That remains the argument for finishing at U-Boot, and it
   remains the only way M2/M6 are measurable in a bare-metal context.

**Also note:** `boot.img` is loaded into RAM in full. Under Option B it carries the
kernel and initramfs and is correspondingly large; under Option A it carries only
U-Boot. Investigate whether a `boot.img` size ceiling exists — it may independently
favour the U-Boot path.

### 8D.9 OTP irreversibility — restated from primary source

> Once secure-boot has been enabled by programming the one-time programmable (OTP)
> fuses, it cannot be disabled and a different key cannot be programmed.

Confirms R-1 in the strongest terms. Combined with §8B.7 (loss of the secret key
bricks the device's ability to accept firmware), this makes the key ceremony a
genuine one-shot operation. **Burn OTP on one designated unit only; keep at least
one board with blank OTP for the remainder of the project.**

### 8D.10 Revised action items

| # | Action | Note |
|---|---|---|
| 1 | Clone `rpi-image-gen`, build `config/trixie-minbase.yaml` | Runs natively on our Pi; produces Debian 13 arm64 |
| 2 | Read `rpi-sb-provisioner` — the officially supported provisioning app | May automate much of Milestone 2 |
| 3 | Obtain `secure-boot-chain-of-trust-2711.pdf` | Report figure, our exact SoC |
| 4 | Check firmware supports secure boot: `strings start4.elf \| grep VC_BUILD_` | Minimum-version gate |
| 5 | Test F-09 — can an older RPi-signed bootloader be installed to bypass enforcement? | RA-5, testable on our hardware |
| 6 | Prototype an HSM wrapper against `rpi-eeprom-digest -H` | F-10, connects to Tier 2 BOM |
| 7 | Determine whether `boot.img` has a size ceiling | Feeds ADR-001 |

---

## 8E. M4 — single-bit tamper resilience (Session 3, 2026-09-10)

Harness: `pi-trust-signing/pt-bitflip.py`. Method — flip one randomly chosen bit
in a protected file, run the relevant check, restore, repeat. Control run first
to confirm the unmodified chain is accepted.

### 8E.1 Results

| Test | Target | Size | Bit positions | Flips detected | Caught by |
|---|---|---|---|---|---|
| Control | unmodified | — | — | accepted ✓ | — |
| 1 | `manifest.txt` | 218 B | 1,744 | **50/50** | ML-DSA-65 signature |
| 2 | `manifest.sig` | 3,309 B | 26,472 | **50/50** | ML-DSA-65 signature |
| 3 | `fake-kernel.img` | 25 B | 200 | **50/50** | SHA-256 hash line |

**Total: 150/150 single-bit modifications detected. Zero false accepts, zero
false rejects on the control.**

### 8E.2 Test 3 is the one to explain in the report

Flipping a bit in the **artifact** does not modify the manifest, so the ML-DSA
signature over the manifest **remains cryptographically valid**. Detection comes
from the SHA-256 hash line instead.

This is a concrete demonstration of why the design needs two layers:

| Layer | Protects | Against |
|---|---|---|
| ML-DSA-65 signature | the manifest | forged or altered *hash lists* |
| SHA-256 hash lines | the artifacts | altered *payloads* |

Neither alone is sufficient. A signature with no hashes attests to nothing about
the artifacts; hashes with no signature can simply be rewritten by the attacker.
And it explains the mandatory verification order (§8B.3): signature first, then
hashes.

### 8E.3 Honest scope — M4 is PARTIALLY satisfied

The sponsor metric reads: *"Successful Failure to Boot when the firmware is
modified by even a single bit."*

**What is proven:** the cryptographic layer detects single-bit modification with
100% success across 150 trials on three distinct protected components.

**What is NOT yet proven:** that detection causes a **boot failure**. Currently a
detected modification produces a non-zero exit code from a userspace binary.
Nothing yet halts the boot.

Remaining work to close M4 fully:
1. Wire `pt-verify` into the initramfs so a non-zero result aborts boot
2. Demonstrate an actual failure-to-boot on the serial console, captured
3. Confirm the failure is fail-closed under adverse conditions — missing
   signature file, missing public key, truncated manifest, corrupt initramfs

**Report the metric as two rows**, not one: "cryptographic detection" (PASS,
evidence above) and "boot enforcement" (pending Milestone 2). Claiming M4
outright on the current evidence would overstate the result.

### 8E.4 EXHAUSTIVE RESULT — complete single-bit coverage achieved

Upgraded from random sampling to exhaustive enumeration.
Harness: `pt-bitflip-full.py`.

| Target | Bit positions | Tested | Detected | Time | Caught by |
|---|---|---|---|---|---|
| `manifest.txt` | 1,744 | **all 1,744** | **1,744** | 5 s | ML-DSA-65 signature |
| `fake-kernel.img` | 200 | **all 200** | **200** | 1 s | SHA-256 hash line |
| `manifest.sig` | 26,472 | 50 sampled | 50 | — | ML-DSA-65 signature |

**Claim now supportable:** *every* single-bit modification of the manifest and of
the artifact is detected — not a sample, the complete space. This is a
qualitatively stronger statement than a sampled result and should be worded that
way in the report.

**Incidental performance note.** 1,744 full verification cycles completed in 5
seconds — roughly 2.9 ms each, including process spawn, three file reads, and
signature verification. Consistent with the measured 0.305 ms of actual ML-DSA
work (§8A.3c); the remainder is process and I/O overhead. Reinforces §8A.3e: the
lattice arithmetic is not the expensive part.

### 8E.5 Original sampled result (superseded by 8E.4, retained for record)

Tests 1 and 3 have small enough bit-spaces to test **exhaustively** rather than
by random sampling:

| Target | Positions | Feasibility |
|---|---|---|
| `fake-kernel.img` | 200 | Trivial — seconds |
| `manifest.txt` | 1,744 | ~1–2 minutes |
| `manifest.sig` | 26,472 | ~20 minutes; sampling is reasonable here |

Exhaustive coverage upgrades the claim from *"50 random flips detected"* to
*"every single-bit modification in the 1,744-bit manifest space is detected"* —
a materially stronger statement, and cheap to obtain. Recommended before the
final report.

## 8F. dm-verity — rootfs integrity layer proven (Session 3, 2026-09-10)

Proof-of-concept on a 32 MB loopback image, deliberately isolated from the live
system (R-4 recovery cards still outstanding). Tooling: `cryptsetup-bin` 2:2.7.5-2,
`veritysetup`.

### 8F.1 Merkle tree parameters and cost

| Property | Value |
|---|---|
| Data blocks | 8,192 × 4,096 B = 32 MB |
| Hash blocks | 65 |
| Hash algorithm | SHA-256 |
| Hash device size | 270,336 B |
| **Storage overhead** | **0.81%** |
| Root hash | 32 B |
| Salt | 32 B |

**Under 1% storage cost to make every block of a filesystem verifiable, and the
entire filesystem is represented by a 32-byte root hash.** That 32 bytes is what
goes into the ML-DSA-signed manifest — one line covering an arbitrarily large
rootfs.

### 8F.2 Complete Milestone 2 chain, demonstrated

```
ML-DSA-65 signature ──> manifest ──> verity root hash ──> Merkle tree ──> every block
    (3,309 B)          (~250 B)        (32 B)            (270 KB)        (32 MB)
```

Each link verified independently this session: signature (§8B, §8E) and
block-level integrity (this section). Integration remains.

### 8F.3 Tamper test — single byte in 32 MB

Method: single byte written at offset 5,000,000 (block 1220) directly into the
backing image, bypassing the filesystem, then re-opened against the **original**
root hash.

```
device-mapper: verity: 7:2: data block 1220 is corrupted
Buffer I/O error on dev dm-0, logical block 1220, async page read
dd: error reading '/dev/mapper/protected-root': Input/output error
```

**Detected, exact block identified, data withheld.** The kernel does not return
corrupted data — it fails the read.

### 8F.4 F-11 — verification is lazy, and this cuts both ways

**Observed:** after tampering, `veritysetup open` **succeeded** and
`mount -o ro` **succeeded** with no error. Corruption surfaced only when block
1220 was actually read. Mounting touches the superblock and some metadata; it
never touched block 1220.

This is dm-verity's designed behaviour — verification happens on access, never up
front — and it has two consequences that belong in the report as a pair:

| | |
|---|---|
| **Advantage** | Boot time is **independent of filesystem size**. A 30 GB rootfs costs the same at boot as a 30 MB one, because nothing is hashed until read. This is the property that makes M1 achievable at all — a boot-time full-image hash of a real rootfs would blow the 2-second budget by itself. |
| **Limitation** | A tampered block that is **never read** is **never detected**. dm-verity guarantees "everything actually used was authentic", not "the entire filesystem is clean". |

**Framing for the report:** state the limitation explicitly rather than letting
"the rootfs is verified" stand unqualified. For a CPE appliance the trade is
correct — a block never read cannot influence behaviour — but the guarantee
should be stated precisely.

### 8F.5 F-12 — the salt must be pinned in the signed manifest

`veritysetup format` generates a **random salt per invocation** (observed: two
different salts across two runs of the same command). The salt is required to
verify, and by default `veritysetup` reads it from the hash device header.

**In our threat model the hash device is attacker-controllable.** Therefore the
manifest must pin **both** the root hash and the salt explicitly, and the verifier
must pass them rather than trusting the header.

Manifest v2 additions:
```
# verity-root-hash: c0d6eeede1271eecc7e47203540d1634d92928bbd94ada439db90f858a94c39c
# verity-salt: caa2c85e9b2081e53b99c4130c21d3763a59a899c2592ed6346dd96a19e6041c
# verity-data-blocks: 8192
# verity-block-size: 4096
```

Block count and block size are included for the same reason — all are verification
parameters, and any parameter read from an untrusted source is an attack surface.

### 8F.6 E-07 — block size mismatch on small images

First attempt failed at mount:
```
EXT4-fs (dm-0): bad block size 1024
```

`mkfs.ext4` selects **1024-byte** blocks for small filesystems, while dm-verity
presented the device with **4096-byte** blocks. Fixed with `mkfs.ext4 -b 4096`.

Artifact of the small demo image — a real multi-GB rootfs gets 4096 automatically.
Recorded because the error message points at ext4 rather than at the block-size
mismatch, and it would cost an evening if met unexpectedly on real hardware.

### 8F.7 Next — integration

Individually proven; not yet joined. Remaining:

1. Extend `pt-manifest.sh` to emit the verity fields in §8F.5
2. Extend `pt-verify` to parse them and invoke `veritysetup open` with explicit
   root hash and salt
3. Verify the ordering holds: **ML-DSA signature first, then verity setup**.
   Configuring dm-verity from an unverified manifest proves nothing.
4. Move the whole sequence into an initramfs hook (Milestone 2 proper)
5. Demonstrate failure-to-boot, closing the second half of M4 (§8E.3)

## 8G. INTEGRATION — end-to-end verified boot chain working (Session 3, 2026-09-10)

The signing layer (§8B) and the integrity layer (§8F) are now joined.
Orchestrator: `pi-trust-signing/pt-boot.sh`.

### 8G.1 Successful run — all four stages

```
pt-boot: [1/4] verifying manifest signature
SIGNATURE VALID
  manifest : manifest.txt (644 bytes)
  algorithm: ML-DSA-65
  context  : "pi-trust-manifest-v1"
pt-boot: [2/4] reading parameters from SIGNED manifest
         root hash : 74109d1a9272eeac58af28c7b0cb12654aa99adda2a012f05f8248dc3d781f42
         blocks    : 8192 x 4096 B
pt-boot: [3/4] cross-checking hash device against signed parameters
         ok: salt
         ok: data blocks
         ok: data block size
         ok: hash block size
pt-boot: [4/4] activating dm-verity

pt-boot: VERIFIED ROOT ACTIVE at /mnt/verified-root
```

### 8G.2 The chain, complete

```
ML-DSA-65 signature  ──>  manifest  ──>  verity params  ──>  Merkle tree  ──>  every block
     3,309 B              644 B          root hash + salt      270 KB          32 MB
                                         + block geometry
```

**Every link is now enforced by code, in order.** The manifest carries both the
artifact hashes (§8B) and the dm-verity parameters (§8F.5); the signature covers
all of it; nothing is read from an unverified source.

### 8G.3 Ordering is the security property

`pt-boot.sh` enforces, and will refuse to proceed past, this sequence:

| Stage | Action | On failure |
|---|---|---|
| 1 | ML-DSA-65 signature check over the manifest | **ABORT** — dm-verity never configured |
| 2 | Read verity parameters from the *now-authenticated* manifest | ABORT if any field missing |
| 3 | Cross-check hash-device superblock against signed parameters | **ABORT on any mismatch** |
| 4 | `veritysetup open` using the root hash from the *signed* manifest | ABORT, mapping torn down |

Reversing 1 and 2 would mean configuring dm-verity from an unauthenticated file —
an attacker able to modify the rootfs could equally modify an unsigned manifest to
match it. The order is not stylistic.

### 8G.4 F-12 mitigation implemented — superblock cross-check

§8F.5 identified the hash-device superblock as attacker-controllable. Rather than
using `--no-superblock`, stage 3 **requires the superblock to agree with the signed
manifest** on salt, data blocks, data block size, and hash block size.

Advantages of this approach:
- No dependency on `veritysetup` flag semantics for passing explicit parameters
- Tampering surfaces as an **explicit named mismatch**, not as silently different
  verification parameters
- Works with the standard `veritysetup format` workflow

### 8G.5 Fail-closed demonstrated — unplanned, and worth reporting

During integration, `pt-sign` refused to overwrite an existing `manifest.sig`
(the `O_EXCL` guard, §8B.6). The stale signature — over a *previous* manifest —
remained on disk. The subsequent `pt-boot.sh` run produced:

```
pt-boot: [1/4] verifying manifest signature
SIGNATURE INVALID
pt-boot: ABORT - signature invalid - refusing to configure dm-verity
```

**A stale signature produced a refusal to boot, not a silently incorrect boot.**
This was an accidental test of exactly the property the design is meant to have,
arising from a realistic operator error (forgetting to regenerate a signature after
editing a manifest). Worth citing in the report — unplanned failures that fail in
the right direction are good evidence.

### 8G.6 E-08 — root-owned artifacts silently excluded from the manifest

`pt-verity-format.sh` run under `sudo` produced a root-owned `hashtree.img`. The
subsequent unprivileged `pt-manifest.sh` emitted:

```
sha256sum: hashtree.img: Permission denied
```

to stderr — but **still produced a manifest**, one covering only `rootfs.img`. The
hash tree would have gone unprotected while the manifest looked plausible.

**Fix applied:** `chown` the artifact back before manifest generation.

**Design defect — CORRECTED 2026-09-10.** `pt-manifest.sh` now checks the
`sha256sum` exit status and aborts:

```sh
if ! sha256sum "$@"; then
    echo "pt-manifest: FATAL - could not hash one or more artifacts" >&2
    exit 1
fi
```

Verified by making `hashtree.img` unreadable and re-running:

```
sha256sum: hashtree.img: Permission denied
pt-manifest: FATAL - could not hash one or more artifacts
exit code: 1
```

Previously this produced exit code 0 and a manifest silently covering only
`rootfs.img`. **A manifest that omits an artifact while appearing complete is
worse than no manifest at all** — the failure is invisible at sign time and the
gap only surfaces if someone later notices the artifact was never protected.

Generalisable lesson for the report: in a signing pipeline, **every step that
contributes to what gets signed must fail loudly**. Silent partial success is the
dangerous failure mode, because the signature then attests to something narrower
than intended while looking exactly as authoritative.

### 8G.7 Verify cost unchanged at 644 bytes

The manifest grew from 218 B to 644 B (verity parameters plus a second hash line).
ML-DSA verification cost is unaffected — the signature operates on the manifest,
not the 32 MB image it describes. Confirms the §8B.3 design rationale: **manifest
size, not payload size, drives signature cost, and manifest size is roughly
constant.**

### 8G.8 Remaining for Milestone 2

1. Negative tests against `pt-boot.sh` (§8G.9)
2. Fix E-08 — hard failure on unhashable artifacts
3. Move the sequence into an initramfs hook
4. Demonstrate actual failure-to-boot, closing the second half of M4 (§8E.3)

### 8G.9 Negative tests to run

| # | Tamper with | Expected abort stage | Tests |
|---|---|---|---|
| 1 | `manifest.txt` | Stage 1 — signature | ML-DSA detection |
| 2 | `hashtree.img` salt field | **Stage 3 — cross-check** | **F-12 mitigation specifically** |
| 3 | `rootfs.img` block | None; mount succeeds, read fails | F-11 lazy verification |
| 4 | Wrong public key | Stage 1 — signature | Key binding |
| 5 | Delete `manifest.sig` | Stage 0 — file check | Fail-closed on missing input |

Test 2 is the one with no prior coverage — it exercises the mitigation added this
session and nothing else does.

## 8H. Negative tests against `pt-boot.sh` (Session 3, 2026-09-10)

### 8H.1 Test 2 — salt tampering, stage-3 cross-check

Method: single byte written at offset 88 of `hashtree.img` (start of the salt
field in the dm-verity superblock), leaving the superblock structurally valid.

```
pt-boot: [1/4] verifying manifest signature
SIGNATURE VALID
pt-boot: [2/4] reading parameters from SIGNED manifest
pt-boot: [3/4] cross-checking hash device against signed parameters
         MISMATCH salt
           signed : 40d9ef6ce9dcc798a2ee5ebade69ad95f637d0c295ce7361caf6a65c595ed90c
           device : 5ad9ef6ce9dcc798a2ee5ebade69ad95f637d0c295ce7361caf6a65c595ed90c
pt-boot: ABORT - hash device does not match signed manifest
```

Stages 1 and 2 pass (the manifest is untouched and genuinely signed); stage 3
detects the disagreement, names the field, prints both values, and aborts before
`veritysetup open` is reached. **F-12 mitigation validated on its intended
branch.**

### 8H.2 Bonus — algorithm-field tampering, different abort path

An earlier attempt wrote to offset 32 (the hash-algorithm string), producing
`sha256` → `Zha256`:

```
Hash algorithm Zha256 not supported.
Device hashtree.img is not a valid VERITY device.
pt-boot: ABORT - cannot read hash superblock
```

A structurally invalid superblock aborts at stage 3 via a **different** branch —
`veritysetup dump` fails and the script treats that as fatal rather than
continuing with empty comparison values. Two distinct stage-3 failure modes now
covered.

### 8H.3 dm-verity superblock layout (read from `od`, for reference)

| Offset | Field | Observed |
|---|---|---|
| 0 | Magic | `verity` |
| 8 | Version | 1 |
| 12 | Hash type | 1 |
| 16 | UUID | 16 B |
| 32 | Algorithm name | `sha256` |
| 64 | Data block size | `00 10 00 00` = 4096 LE |
| 68 | Hash block size | `00 10 00 00` = 4096 LE |
| 72 | Data blocks | `00 20 00 00` = 8192 LE |
| 80 | Salt size | `20` = 32 |
| 88 | **Salt** | 32 B |

Useful for constructing further tamper tests without trial and error.

### 8H.4 HONEST ASSESSMENT — what the cross-check actually buys

The salt is an input to the hash computation, so `root_hash = H(salt, data…)`.
Because `pt-boot.sh` always passes the root hash **from the signed manifest**, a
tampered salt would produce a tree that fails verification on first read anyway,
even with no cross-check.

**So the salt comparison is not closing an otherwise-open hole.** Its value is:

| Benefit | Weight |
|---|---|
| **Fail fast** — aborts at setup instead of surfacing as an I/O error on first read | Real |
| **Clear diagnostic** — names the mismatched field and both values, rather than a bare `data block N is corrupted` | Real |
| **Prevents activation of a known-bad mapping** | Real |
| Closes a cryptographic gap that would otherwise exist | **No — overstating this would be wrong** |

**The block-geometry checks are more load-bearing.** A mismatched
`data-block-size` or `data-blocks` value could cause the mapping to be
constructed over the wrong region or with the wrong stride, and it is less
obvious that this always fails safely. Pinning geometry in the signed manifest
is the part that most clearly needs to be there.

**Report framing:** describe the cross-check as defence-in-depth and fail-fast
diagnostics, with geometry pinning as the security-relevant element. Claiming it
prevents an otherwise-viable attack would not survive scrutiny.

### 8H.5 Remaining negative tests

| # | Tamper with | Expected | Status |
|---|---|---|---|
| 1 | `manifest.txt` | Abort stage 1 | Covered by §8E (exhaustive) |
| 2 | `hashtree.img` salt | Abort stage 3 | **DONE** |
| 2b | `hashtree.img` algorithm | Abort stage 3, other branch | **DONE** |
| 3 | `rootfs.img` block | Mount OK, read fails | Covered by §8F.3 |
| 4 | Wrong public key | Abort stage 1 | **DONE** |
| 5 | Missing `manifest.sig` | Abort stage 1 (see 8H.7) | **DONE** |

**Full negative-test matrix now covered.**

### 8H.6 Test 4 — key binding

A second, independently generated ML-DSA-65 keypair (`attacker.pk`, first bytes
`ff42c062…`) was used to verify a manifest signed with `dev.sk`:

```
pt-boot: [1/4] verifying manifest signature
SIGNATURE INVALID
pt-boot: ABORT - signature invalid - refusing to configure dm-verity
```

**Significance.** The signature under test is a structurally valid ML-DSA-65
signature — well-formed, correct length, produced by the same implementation. It
is rejected solely because it does not verify under the presented public key.

This is the only test in the suite that distinguishes *"the verifier checks the
signature against a specific key"* from *"the verifier checks the signature is
well-formed"*. Every other test would pass against a verifier that merely
parsed the signature. Worth calling out in the report for exactly that reason.

### 8H.7 Test 5 — missing signature file, and a diagnostic defect

```
pt-boot: [1/4] verifying manifest signature
pt: cannot open does-not-exist.sig: No such file or directory
pt-boot: ABORT - signature invalid - refusing to configure dm-verity
```

**Behaviour correct — fails closed.** A missing signature is treated as failure,
never as permission to proceed.

**E-09 (minor) — misleading diagnostic.** The abort message reports "signature
invalid" when the actual cause is a missing file. The abort came from inside
`pt-verify` rather than from `pt-boot.sh`'s own pre-flight file-existence checks.

Cause: the version deployed to the device (transcribed over serial) omitted the
`[ -f "$MANIFEST" ]`, `[ -f "$SIG" ]`, `[ -f "$PUBKEY" ]` guards present in the
canonical `pt-boot.sh`. Restore them when the tree is moved into version control.

No security impact — the outcome is identical. But an operator debugging a failed
boot would be sent looking for a corrupted signature rather than a missing file,
and boot failures are exactly when diagnostics matter most.

## 9. Measurement methodology decisions

### 9.1 D-01 — Boot timing must be host-side
Bootloader timestamps are non-monotonic (§6.2). Timing derives from the picocom stream.

**Correction:** an earlier revision of this document used `stty -F`. That is the Linux flag.
**macOS uses `-f`.**

```bash
brew install moreutils
mkdir -p ~/pi-baselines && cd ~/pi-baselines
stty -f /dev/cu.usbserial-0001 115200 raw -echo
cat /dev/cu.usbserial-0001 | ts '%.s' | tee b0-capture.log
```

**Anchor points:** measure from the `RPi: BOOTSYS` line (first bootloader output) to the
`login:` prompt. This is well defined for both cold boots and warm reboots, unlike "first byte
received", which is meaningless on a continuous stream.

**Extraction** — handles multiple reboots in a single capture file:
```bash
awk '/RPi: BOOTSYS/{s=$1} /login:/{if(s!=""){printf "%.3f\n", $1-s; s=""}}' b0-capture.log
```

**Convention:** use `sudo reboot` rather than physical power cycling. Warm reboot is far more
repeatable (no human variance in replug timing) and both paths traverse BOOTSYS. Because M1 is a
delta, any cold/warm offset cancels. **Declare this convention in the report.**

Supplement with `systemd-analyze` and `systemd-analyze blame` for the userspace breakdown.

### 9.7 D-07 — Network state must be identical across all captures
`NetworkManager.service` is the largest remaining userspace item (2.288s) and its duration
depends on whether an interface associates. Capturing B0 with no network and B1/B2 with Wi-Fi
connected would inject an uncontrolled multi-second difference into M1.

**Rule:** all timing captures are taken in the same network state. Record which state was used.
Wi-Fi may be brought up between capture sessions for library builds, but must be returned to the
recorded state before any timing run.

### 9.2 D-02 — Report mean and standard deviation over ≥10 runs
Pi boot time varies run to run. A single number cannot support a claim about a sub-2-second
delta. Establish the noise floor before claiming any signal. Report n, mean, σ.

### 9.3 D-03 — Three baselines, not two — **important**
Comparing ML-DSA-signed boot against *unsigned* boot would charge PQC for the cost of performing
any verification at all, and (if U-Boot is added) for the cost of an entire extra boot stage.
That inflates the measured PQC overhead with work that is not cryptographic.

| Capture | Configuration | Role |
|---|---|---|
| B0 | Stock, unsigned | Context only |
| **B1** | **RSA-signed, same architecture** | **True baseline for M1** |
| B2 | ML-DSA-signed | Treatment |

**M1 is B2 − B1.** Isolate one variable.

### 9.4 D-04 — Separate I/O time from computation time
ML-DSA-65 signature reads are trivial (3,309 B). But verification hashes the *entire* signed
artifact — kernel plus initramfs, tens of MB. That hashing is partly I/O-bound, and on a DDR50
card (§3.6) storage latency is material. Instrument artifact read separately from verify
computation, or M1 is contaminated with storage time and a reviewer will catch it.

### 9.6 D-06 — Trim services first, freeze, then measure
Every disabled service changes boot time. Trimming after B0 invalidates the comparison. Therefore:

1. Trim all services now (§5.5 table)
2. Record the exact trimmed set into §3 as part of the frozen environment
3. Only then capture B0

The goal is **low variance and reproducibility**, not the fastest possible boot. A trimmed
configuration is also more representative of a real network-edge CPE appliance than a stock
desktop-oriented image, which is a defensible point in the writeup.

**Do not trim further after B0 without re-capturing all baselines.**

### 9.8 D-08 — PQC overhead must be instrumented inside the bootloader
**Source: cross-team methodology review, 2026-09-08 (Event Horizon / advisor). Accepted.**

`systemd-analyze` begins counting when the Linux kernel starts. On this board the bootloader
consumes roughly 4.5 s before that point, and none of it is visible to systemd. Signature
verification happens entirely within that invisible window.

**Consequence:** adding or removing ML-DSA verification in a bootloader stage would produce
**zero change** in `systemd-analyze` output. A completely unverified boot chain and a fully
verified one would report identical numbers. M1 as originally defined could not detect its own
subject.

**Required method:** emit an explicit timestamp immediately before and immediately after the
ML-DSA verification call, from inside the bootloader itself, and compute the delta there. The
reviewing team measured their own classical baseline this way (a U-Boot `fatload` timing of
435 ms captured live at the U-Boot prompt), not from Linux logs after the fact.

**Two corrections to the review, recorded for accuracy:**

1. The review characterised the B0 kernel spread (2.1–2.5 s) as "tight consistency." It is not —
   it is **bimodal** (§5.6), two clusters ~340 ms apart with nothing between them. Reading it as
   scatter would leave a systematic artifact unexamined.
2. The review's `fatload` method presumes a U-Boot prompt. This platform has no U-Boot; the Pi 4
   uses a closed-source EEPROM bootloader, and whether U-Boot is introduced at all remains open
   (OD-01). The method is correct but not yet applicable — it becomes applicable if and only if
   the U-Boot path is chosen, which is an additional argument in favour of that path.

**Status of B0:** the review asked whether B0 is a true `T_classical` or a mismeasured `T_pqc`.
Neither. Per F-03, this device currently performs no signature verification of any kind. B0 is a
pre-instrumentation baseline of an unverified system — valid for M1b, silent on M1a by
construction.
**Do not write an ML-DSA implementation.** Use a vetted implementation and validate it against
**NIST ACVP known-answer test vectors**. Passing KATs is a concrete, checkable Phase I
deliverable; "we used a library" is not.

---

## 10. Open decisions

### 10.1 ADR-001 — Verifier host: U-Boot vs initramfs

**Status:** Accepted (target), staged delivery
**Date:** 2026-09-09
**Deciders:** Team Singularity; sponsor visibility recommended
**Supersedes:** OD-01 (open question)

#### Context

Per §2, the Pi 4's BCM2711 ROM and EEPROM bootloader are RSA-2048 only and immutable. ML-DSA can
therefore only be introduced *below* the first RSA-verified artifact. The open question is which
component hosts the ML-DSA verifier, because that choice determines:

- how far up the chain the classical (quantum-vulnerable) link extends
- whether M2 (< 128 KB verifier code) and M6 (early-boot SRAM) are measurable at all
- whether M1a can be instrumented inside the bootloader, per the cross-team review in §9.8

Constraints in play: two-semester schedule, no prior U-Boot experience on the team, one Pi
currently at the bench, and a sponsor brief that explicitly specifies "the secondary bootloader
verifies the Linux kernel using PQC signatures."

#### Decision

**Target architecture is Option A (U-Boot).** Delivery is staged so that Option B exists as a
working intermediate milestone and a schedule fallback.

#### Options considered

##### Option A — U-Boot chainloaded

```
EEPROM bootloader  [RSA-2048]
  └─ boot.img  [RSA-signed, contains u-boot.bin as "kernel"]
       └─ U-Boot
            └─ FIT image: kernel + dtb + initramfs   [ML-DSA-65 verified]
                 └─ Linux
```

| Dimension | Assessment |
|---|---|
| Complexity | High |
| Schedule risk | High |
| Team familiarity | None |
| Requirement match | Full |
| Metric coverage | M1a, M2, M6 all measurable |

**Build items:**
1. U-Boot for Pi 4 (`rpi_4_defconfig` / `rpi_arm64_defconfig`)
2. Device-side ML-DSA-65 verify added to U-Boot's FIT signature algorithm table
   (`image-sig.c`, alongside `rsa.c` — documented extension point)
3. Host-side signing: `mkimage` must emit ML-DSA signatures
4. Public key pinned in `u-boot.dtb` (U-Boot control FDT, standard mechanism)
5. `boot.img` packaging with `u-boot.bin` in the kernel slot

**Pros:** ML-DSA protects the kernel itself; RSA exposure stops at U-Boot. Satisfies the brief as
written. M2/M6 become real bare-metal measurements. M1a instrumentable (§9.8).

**Cons:** An additional self-compiled bootloader stage running before Linux, with no console
recovery on failure. ML-DSA is **not** in upstream U-Boot (verified 2026-09-09: current FIT
signature docs list only RSA and ECDSA variants), so both verify and signing paths must be
written. Highest bricking risk of any option.

##### Option B — Initramfs verifier

```
EEPROM bootloader  [RSA-2048]
  └─ boot.img  [RSA-signed, contains kernel + initramfs]
       └─ Linux + initramfs
            └─ ML-DSA-65 verify in early userspace
                 └─ dm-verity root hash → rootfs
```

| Dimension | Assessment |
|---|---|
| Complexity | Low–Medium |
| Schedule risk | Low |
| Team familiarity | Moderate (ordinary Linux userspace) |
| Requirement match | Partial |
| Metric coverage | M1b only; M2/M6 not meaningful |

**Build items:** initramfs hook; ML-DSA verify binary (liboqs or OpenSSL 3.5+ both viable);
dm-verity on rootfs; signed manifest carrying the verity root hash.

**Pros:** Substantially less work. Ordinary userspace tooling and debugging. Very low bricking
risk. Produces a demonstrable end-to-end PQC chain early.

**Cons:** Kernel and initramfs remain RSA-only, so the quantum-vulnerable link extends further up
the chain. M2 and M6 become userspace numbers that do not reflect the constraint the brief
specifies — meaning two sponsor metrics cannot be honestly reported.

#### Trade-off analysis

Three factors decide this:

1. **Requirement text.** The brief specifies the secondary bootloader verifying the kernel. Only
   Option A does that. Option B verifies the *rootfs*, after Linux is already running from an
   RSA-only kernel.
2. **Metric coverage.** M2 and M6 are only measurable in a bare-metal bootloader. Choosing B alone
   means reporting "not measured" against two sponsor requirements.
3. **Schedule risk.** This is the only factor favouring B, and it is a real one. The mitigation is
   sequencing, not option choice.

The sequencing insight that resolves the tension: **most of the work is shared.** ML-DSA library
selection, ACVP KAT validation (D-05), signing infrastructure, key ceremony, manifest format, and
the tamper-test harness are identical under either option. Only the verifier *host* differs.
Building B first is therefore not wasted effort — it is the shared plumbing plus a thin userspace
verifier, which is later relocated into U-Boot.

#### Consequences

**Easier:**
- A working, demonstrable PQC boot chain exists early (end of Milestone 2), de-risking the demo
- If U-Boot integration stalls, there is a defensible deliverable rather than nothing
- Signing infrastructure gets exercised and debugged before the harder integration

**Harder:**
- Two integration efforts rather than one
- U-Boot work cannot begin until the shared plumbing is proven
- Requires discipline not to stop at Milestone 2 once it demos successfully

**To revisit:**
- If ML-DSA FIT support lands upstream in U-Boot, Milestone 3 effort drops sharply — recheck
  upstream at the start of each milestone
- If Milestone 3 is not started by the end of week 10, escalate the schedule risk rather than
  silently descoping

#### Known technical risk — verify-time memory (M6)

The M6 constraint is **not** driven by the 3,309-byte signature. It is driven by expansion of the
public matrix A. For ML-DSA-65, A is a 6×5 matrix of degree-256 polynomials; held fully expanded
as 32-bit coefficients that is 6 × 5 × 256 × 4 = **30,720 bytes**, before accounting for the
public key vector, the signature's z vector, and intermediate w values.

Memory-constrained implementations generate rows of A on the fly instead of expanding it fully,
trading time for space. **This time/space trade-off is the substance of M6 and should be measured
both ways** — it is a more interesting result than a single pass/fail number, and it is the kind
of hardware-reality finding the brief's "PQC Size Penalty" avenue (RA-7) is asking for.

#### Action items

1. [ ] Select ML-DSA implementation; validate against NIST ACVP vectors (D-05)
2. [ ] Measure verify-only code size and peak stack in userspace first — early M2/M6 estimate
3. [ ] Build signing infrastructure and document key ceremony
4. [ ] Define signed manifest format
5. [ ] **Milestone 2:** initramfs verifier + dm-verity working end-to-end
6. [ ] Recheck upstream U-Boot for ML-DSA FIT support
7. [ ] Build stock U-Boot on Pi 4, confirm chainload works *before* adding any crypto
8. [ ] **Milestone 3:** relocate verifier into U-Boot FIT path; instrument M1a
9. [ ] Compare on-the-fly vs expanded matrix A for M6

### 10.2 OD-02 — Justify ML-DSA over the brief's LMS/XMSS recommendation
The sponsor brief names **LMS or XMSS (NIST SP 800-208)** as the *primary* recommendation for
firmware signing. We selected ML-DSA (FIPS 204). This deviation must be argued explicitly in
Phase I, not left unexplained.

Argument to develop:
- **Stateless.** LMS/XMSS are stateful; reusing a one-time key breaks the scheme catastrophically.
  State management across a signing infrastructure is an operational hazard.
- **FIPS 204** is the general-purpose NIST signature standard.
- Counter-argument to address honestly: SP 800-208 recommends hash-based signatures for firmware
  specifically, on maturity grounds and because verification code is smaller — which bears
  directly on our M2 budget. Address this, don't dodge it.

Consider measuring both if schedule allows. A comparative M1/M2/M3 table across ML-DSA-65 and LMS
would be a genuinely strong result and would answer the deviation question with data.

### 10.3 OD-03 — Attestation interface to software team
See §1.3. Unassigned.

---

## 11. Research avenues tracker

Mapped from the sponsor brief. Each needs a written deliverable.

| ID | Avenue | Source | Status |
|---|---|---|---|
| RA-1 | Hybrid dual-signature boot (RSA + PQC) | Brief §2 | **Forced by §2 architecture — already in scope** |
| RA-2 | Off-chip TPM 2.0 over SPI/I2C; SPI bus snooping mitigation | Brief §2 | Phase III, Step 12 |
| RA-3 | FPGA acceleration of lattice math (MachXO3) | Brief §2 | Not started (Tier 3 BOM) |
| RA-4 | Side-channel defence: power analysis / EMA on PQC | Brief §2 | Not started |
| RA-5 | "Key in the clear" — OTP bypass via voltage glitching | Brief §3 | **Linked to F-02 (JTAG unlocked)** |
| RA-6 | TPM vs SoC — why external keys, SPI snooping | Brief §3 | Overlaps RA-2 |
| RA-7 | PQC size penalty — SRAM consumed by signature pre-OS | Brief §3 | Feeds M3, M6 |
| RA-8 | Quantum-resistant entropy / HRNG | Brief Phase III | Not started |
| RA-9 | PUF from BCM2711 silicon characteristics | Brief Phase III | Not started |

---

## 12. Risk register

| ID | Risk | Impact | Mitigation | Status |
|---|---|---|---|---|
| R-1 | OTP burn is irreversible; a wrong key hash permanently bricks secure boot on that board | Loss of a Pi | Burn only on a designated unit, only after full EEPROM-only testing | Open |
| R-2 | No network on the Pi | Blocks library build at Step 3 | Move to wired Ethernet | **Open, near-term** |
| R-3 | Card wear from tamper-test power cycling degrades timing comparability | Invalidates M1 late in project | Re-benchmark card per §4.4 each session; log alongside timings | Open |
| R-4 | No recovery card built | An EEPROM brick halts the project | Build both recovery cards (§4.3) before Phase II | **Open, blocking Phase II** |
| R-5 | Baseline captured under a config that later changes | M1 invalid | Freeze §3; record any forced change as a new baseline capture | Managed |
| R-6 | Attestation interface undefined | Late integration failure with software team | Agree §1.3 contract now | Open |
| R-7 | Classical RSA link remains quantum-vulnerable | Residual risk in final result | State plainly as hardware-generation limitation (§2.3) | Accepted |
| **R-8** | **`rpi-eeprom-update.service` runs every boot and may stage a new EEPROM mid-semester** | **Silently changes boot timing → invalidates all prior baselines, and could alter signed-boot behaviour after OTP burn** | **Set update policy to `never` via `raspi-config`, or mask the service. Re-verify `vcgencmd bootloader_version` at every measurement session.** | **Open, high priority** |
| R-10 | Custom OS image required for signed boot — current install cannot be signed as-is (F-06, revised §8D.1) | B0 baseline needs re-capture against the new image; §3.9 trim may partially transfer | Use `rpi-image-gen` (`trixie-minbase.yaml`) — Debian 13 arm64, same release as current. **Buildroot NOT required.** | **DOWNGRADED — resolved §8D.1** |
| R-11 | OTP key readable via `/dev/vcio` from a compromised kernel (F-07) | Root of trust protects boot integrity but not key confidentiality | Widen §2.3 residual-risk statement; strengthens case for external TPM (RA-2) | Open |
| R-12 | ~~DTB may sit outside the signed FIT image (F-08)~~ | — | Primary source confirms DTBs ARE inside `boot.img` and RSA-covered | **CLOSED — §8D.4** |
| **R-13** | **Pi 4 boot ROM cannot pin bootloader version; only Pi 5 supports customer counter-signing (F-09)** | **An older Raspberry-Pi-signed bootloader may bypass secure-boot enforcement entirely** | **Test on hardware (RA-5). Document as a hardware-generation limitation alongside §2.3** | **Open, HIGH** |
| R-14 | `boot.img` is loaded into RAM in full; size ceiling unknown | May constrain Option B (kernel + initramfs in `boot.img`) | Determine ceiling; may independently favour ADR-001 Option A | Open |
| R-9 | University Wi-Fi (`utdiot` / `ResearchIoT`) may enforce client isolation | Two-node demo cannot connect Pi-to-Pi | Confirm policy with OIT; use direct Ethernet cable between Pis as primary transaction link | Open |

---

## 13. Errata and lessons learned

Recording these deliberately. A documented dead end demonstrates methodology.

### 13.1 E-01 — Serial TX/RX miswired
Initial wiring connected adapter TX → pin 8. Pin 8 is the Pi's *TX*, so two outputs faced each
other and two inputs faced each other. **Symptom: complete silence, no error.** Corrected to
adapter RX → pin 8, adapter TX → pin 10.
**Lesson:** a dead serial link presents identically to a dead board. Verify wiring direction
before suspecting the target.

### 13.2 E-02 — Roughly 20 minutes lost to a network dead end
SSH was attempted while the Mac was on **iPhone USB tethering** (`192.0.0.2/32`) and the Pi was
expected on the **Wi-Fi hotspot** (`172.20.10.0/28`). iOS keeps these on separate subnets and does
not route between them. **SSH could never have worked in that configuration**, independent of the
Pi's state.
**Lesson:** confirm the host has an address on the target's subnet (`ipconfig getifaddr en0`)
before scanning for a device. An empty result is itself the finding.

### 13.3 E-03 — Misread LED state
Green ACT LED dark was read as a boot failure. On Pi 4 the green LED indicates **SD card activity
only**; it goes dark when an idle system finishes booting. Solid red + dark green is a healthy
idle Pi. There is no network-association LED on this board.

### 13.4 E-04 — picocom shows only live output
Serial terminals cannot display output printed before they attached. Open the listener *first*,
then power on. Pressing Enter on an already-booted system re-prints the login prompt and is the
fastest way to test a link.

---

### 13.5 E-05 — First 13 baseline reboots lost
Thirteen reboots were performed before discovering that (a) `systemd`'s "Startup finished" line
is written to the journal, not to the serial console, and (b) the journal on this image is
**volatile** — RAM-backed, wiped every boot. `journalctl --list-boots` showed only the current
boot. All 13 measurements were unrecoverable.

**Fix adopted:** append to a file on disk before each reboot —
`systemd-analyze >> ~/b0-results.txt && sudo reboot`. Persistent journald was deliberately *not*
enabled, as it writes to the SD card on every boot and would worsen R-3 (card wear).

**Lesson:** verify that a measurement is actually being *persisted* before doing N repetitions of
it. Confirm the capture path on run 1, not run 13.

### 13.6 E-06 — Orphaned picocom held the serial port
Piping picocom through `ts`/`tee` left an orphaned picocom process holding
`/dev/cu.usbserial-0001` after Ctrl-C; subsequent launches failed with
`cannot lock … Resource temporarily unavailable`.

**Fix:** `lsof /dev/cu.usbserial-0001`, then kill the reported PID. Use picocom's own
`--logfile` rather than shell piping — piped sessions orphan easily because the pipe dies before
picocom does.

---

## 14. Immediate next actions

| # | Action | Blocks | Owner |
|---|---|---|---|
| 0 | ~~VERIFY F-06~~ **DONE §8D — buildroot not required; use `rpi-image-gen`** | — | |
| 0a | **Clone `rpi-image-gen`, build `config/trixie-minbase.yaml`** | Milestone 2 target image | |
| 0b | **Read `rpi-sb-provisioner`** — may automate much of Milestone 2 | Milestone 2 scope | |
| 0c | Test F-09 — can an older RPi-signed bootloader bypass enforcement? | RA-5, R-13 | |
| 1 | **Build EEPROM recovery card + known-good OS card** (§4.3) | **Phase II — R-4** | |
| 2 | Get Pi on a network: request `ResearchIoT` / `utdiot` access from OIT or advisor; confirm whether client isolation is enabled | Library build, two-node demo | |
| 3 | Decide OD-01 — U-Boot vs initramfs verifier | Whole Phase II architecture | |
| 4 | Agree attestation interface with software team (§1.3, OD-03) | Integration | |
| 5 | Extend B0 to n ≥ 10 | M1b confidence | |
| 6 | Diagnose the 340 ms bimodal kernel split (§5.6) | M1b interpretation | |
| 7 | Draft OD-02 justification: ML-DSA vs brief's LMS/XMSS recommendation | Phase I deliverable | |
| 8 | Run storage benchmark (§4.4) and record | R-3 tracking |  |
| 9 | Order/confirm direct Ethernet cable for Pi-to-Pi demo link | R-9 mitigation | |

**Sequencing note:** items 1–3 gate everything downstream. Item 1 is cheap and removes the
largest project-halting risk. Item 3 determines what Phase II actually looks like and should be a
team decision, not a default.


---

## Appendix A — Raw captures

### A.1 Full bootloader trace, post-EEPROM-update, `BOOT_UART=1` (2026-09-08)
```
  0.45 RPi: BOOTSYS release VERSION:224877da DATE: 2026/05/17 TIME: 20:13:18
  0.46 MFG_VER: 1
  0.46 BOOTMODE: 0x06 partition 0 build-ts BUILD_TIMESTAMP=1779045198 serial a88e9ee2 boardrev c03115 stc 463745
  0.47 PM_RSTS 00000020
  0.47 POWER_OFF_ON_HALT: 0 WAIT_FOR_POWER_BUTTON 0 power-on-reset 0
  0.48 EEPROM ID 0xef3013
  0.48 SFDP None
  0.49 part 00000000 reset_info 00000000
  0.49 uSD voltage 3.3V
  0.50 init_sdram_1350
  0.53 Initialising SDRAM rank 2 total-size: 32Gbit part: 0 (0x15 0x00) odt: 0
  0.54 memsys_init: 0 32Gbit MCB 0x80015ff0: 11696
  0.54 DDR 3200 Mbps dual-rank:1 byte-mode:0 size-gbit:32 part-config:0 odt:0
  1.94 SD_SB 11013120
  2.11 OTP boardrev c03115 bootrom 8b0 8b0
  2.11 Customer key hash 0000000000000000000000000000000000000000000000000000000000000000
  2.12 VC-JTAG unlocked

  2.42 RPi: BOOTLOADER release VERSION:224877da DATE: 2026/05/17 TIME: 20:13:18
  2.44 MFG_VER: 1
  2.44 BOOTMODE: 0x06 partition 0 build-ts BUILD_TIMESTAMP=1779045198 serial a88e9ee2 boardrev c03115 stc 2447995
  2.45 EEPROM ID 0xef3013
  2.46 SFDP None
  2.46 PCI0 init
  2.46 PCI0 reset
  2.64 PCIe scan 00001106:00003483
  2.74 XHCI-STOP
  2.74 xHC0 ver: 256 HCS: 05000420 fc000031 00e70004 HCC: 002841eb
  2.75 USBSTS 1
  2.75 xHC0 ver: 256 HCS: 05000420 fc000031 00e70004 HCC: 002841eb
  2.75 xHC0 ports 5 slots 32 intrs 4
  2.82 SD_OC: 0
  2.28 Boot mode: SD (01) order f4
  2.31 USB2[1] 400202e1 connected
  2.46 USB2 root HUB port 1 init
  2.84 DEV [01:00] 2.16 000000:01 class 9 VID 2109 PID 3431
  2.85 HUB init [01:00] 2.16 000000:01
  3.76 SD HOST: 200000000 CTL0: 0x00800000 BUS: 400000 Hz actual: 390625 HZ div: 512 (256) status: 0x1fff0000 delay: 276
  3.77 SD HOST: 200000000 CTL0: 0x00800f00 BUS: 400000 Hz actual: 390625 HZ div: 512 (256) status: 0x1fff0000 delay: 276
  3.89 OCR c0ff8000 [145]
CID: 001b534d454231515430a1f463e40155
CSD: 400e00325b590000ee7f7f800a404000
  3.90 SD: bus-width: 4 spec: 2 SCR: 0x02858482 0x00000000
  3.90 SD HOST: 200000000 CTL0: 0x00800f04 BUS: 50000000 Hz actual: 50000000 HZ div: 4 (2) status: 0x1fff0000 delay: 2
  3.91 MBR: 0x00004000, 1048576 type: 0x0c
  3.92 MBR: 0x00104000,61456384 type: 0x83
  3.92 MBR: 0x00000000,       0 type: 0x00
  3.92 MBR: 0x00000000,       0 type: 0x00
  3.32 Trying partition: 0
  3.35 type: 32 lba: 16384 'mkfs.fat' ' bootfs     ' clusters 1032412 (1)
  3.94 rsc 32 fat-sectors 8066 root dir cluster 2 sectors 0 entries 0
  3.94 FAT32 clusters 1032412
  3.96 [sdcard] autoboot.txt not found
  3.96 Select partition rsts 0 C(boot_partition) 0 EEPROM config 0 result 1
  3.67 Trying partition: 1
  3.70 type: 32 lba: 16384 'mkfs.fat' ' bootfs     ' clusters 1032408 (1)
  3.97 rsc 32 fat-sectors 8066 root dir cluster 2 sectors 0 entries 0
  3.98 FAT32 clusters 1032408
  3.93 Read config.txt bytes     1286 hnd 0x39cd8
  3.99 pieeprom.sig
  3.99 hash: b637fee5fc6e78791ecb631b1e3b7a49c7f91cd5ca9d0bd8249d7acaeed3413d
  4.00 ts: 1781743727
  4.96 SELF-UPDATE timestamp current 1781743727 new 1781743727 skip
  4.10 [sdcard] recover4.elf not found
  4.10 [sdcard] recovery.elf not found
  4.43 Read start4.elf bytes  2305632 hnd 0x1a003
  4.50 Read fixup4.dat bytes     5499 hnd 0x933
  4.52 0x00c03115 0x00000000 0x00003fff
  4.55 MEM GPU: 76 ARM: 948 TOTAL: 1024
  4.26 Firmware: 288930ab4712b99596f32732664aaaeb881ef1e0 May 21 2026 11:20:25
  4.62 Starting start4.elf @ 0xfec00200 partition 1
  4.36 XHCI-STOP
  4.36 xHC0 ver: 256 HCS: 05000420 fc000031 00e70004 HCC: 002841eb
  4.37 USBSTS 18
  4.37 PCI0 reset
  4.38 +

Debian GNU/Linux 13 pi-mldsa-cpe ttyS0
```

### A.2 `rpi-eeprom-config` output (2026-09-08, post `BOOT_UART=1`)
```
[all]
BOOT_UART=1
WAKE_ON_GPIO=1
POWER_OFF_ON_HALT=0
```

### A.7 `free -h` (2026-09-08)
```
               total        used        free      shared  buff/cache   available
Mem:           3.7Gi       324Mi       3.1Gi        29Mi       350Mi       3.4Gi
Swap:          2.0Gi          0B       2.0Gi
```

### A.8 `systemd-analyze` / `blame` — unsigned, no network (2026-09-08)
```
Startup finished in 2.113s (kernel) + 15.998s (userspace) = 18.112s
graphical.target reached after 8.655s in userspace.

7.205s NetworkManager-wait-online.service
2.317s NetworkManager.service
1.749s cloud-init-main.service
1.120s rpi-eeprom-update.service
1.078s dev-mmcblk0p2.device
 960ms accounts-daemon.service
 908ms udisks2.service
 662ms systemd-fsck@dev-disk-by\x2dpartuuid-56bd4a66\x2d01.service
 439ms user@1000.service
 429ms avahi-daemon.service
 427ms bluetooth.service
 376ms cloud-init-local.service
 365ms dbus.service
 358ms systemd-udev-trigger.service
 350ms rp1-test.service
```

### A.9 Wi-Fi scan — campus environment (2026-09-08)
Available SSIDs at bench location: `eduroam`, `CometNet` (WPA2-Enterprise 802.1X);
`UTDGuest` (open, probable captive portal); `utdiot`, `ResearchIoT` (WPA2-PSK);
plus non-university APs. Target hotspot `Slow iPhone` **not present in scan** — not broadcasting
at time of capture. `rfkill` shows phy0 `Soft blocked: no`, radio functional (scanned 2.4 and
5 GHz, channels 7–136).

### A.3 `rpi-eeprom-update` before update (2026-09-08)
```
*** UPDATE AVAILABLE ***
BOOTLOADER: update available
   CURRENT: Wed 11 Jan 17:40:52 UTC 2023 (1673458852)
    LATEST: Sun 17 May 19:13:18 UTC 2026 (1779045198)
   RELEASE: default (/usr/lib/firmware/raspberrypi/bootloader-2711/default)
  VL805_FW: Using bootloader EEPROM
     VL805: up to date
   CURRENT: 000138c0
    LATEST: 000138c0
```

### A.4 `vcgencmd bootloader_version` after update
```
2026/05/17 20:13:18
version 224877da90f82a72dbcc9db10bcf059259f54680 (release)
timestamp 1779045198
update-time 1781743605
capabilities 0x0000007f
```

### A.5 `dmesg | grep -i mmc0`
```
[    1.318604] mmc0: SDHCI controller on fe340000.mmc [fe340000.mmc] using ADMA
[    1.426730] mmc0: new UHS-I speed DDR50 SDHC card at address 0001
[    1.427427] mmcblk0: mmc0:0001 EB1QT 29.8 GiB
[    1.430663] mmcblk0: mmc0:0001 EB1QT 29.8 GiB
```

### A.6 `ip a`
```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
2: eth0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc mq state DOWN group default qlen 1000
    link/ether 88:a2:9e:34:46:4d brd ff:ff:ff:ff:ff:ff
3: wlan0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc fq_codel state DOWN group default qlen 1000
    link/ether 88:a2:9e:34:46:4e brd ff:ff:ff:ff:ff:ff
```

---

## Appendix B — Primary sources

| Topic | Source |
|---|---|
| ML-DSA specification | NIST FIPS 204 |
| ML-DSA validation vectors | NIST ACVP known-answer tests |
| Stateful hash-based signatures | NIST SP 800-208 (LMS / XMSS) |
| Pi secure boot (RSA path) | raspberrypi.com documentation; `raspberrypi/rpi-eeprom` repository |
| U-Boot verified boot | U-Boot FIT signature documentation |
| Security categories | NIST PQC standardization category definitions |

**Note on sourcing:** there is no official Raspberry Pi documentation for ML-DSA secure boot,
because it does not exist. The Pi 4's documented secure boot path is RSA-2048 only. Everything in
§4 (UART, serial, boot configuration) is standard documented Pi 4 material. The ML-DSA
integration in Phase II is novel work — that is the capstone contribution, and it is why §9.5
(KAT validation) matters.

### A.10 B0 baseline raw capture (2026-09-08, n=5, no network)
```
Startup finished in 2.116s (kernel) + 6.094s (userspace) = 8.210s
multi-user.target reached after 6.092s in userspace.
Startup finished in 2.460s (kernel) + 6.089s (userspace) = 8.550s
multi-user.target reached after 6.087s in userspace.
Startup finished in 2.129s (kernel) + 6.148s (userspace) = 8.278s
multi-user.target reached after 6.146s in userspace.
Startup finished in 2.458s (kernel) + 6.038s (userspace) = 8.497s
multi-user.target reached after 6.036s in userspace.
Startup finished in 2.466s (kernel) + 6.087s (userspace) = 8.553s
multi-user.target reached after 6.074s in userspace.
```

### A.11 `systemd-analyze` after full service freeze (§3.9)
```
Startup finished in 2.107s (kernel) + 6.074s (userspace) = 8.182s
multi-user.target reached after 6.073s in userspace.

2.288s NetworkManager.service
 988ms dev-mmcblk0p2.device
 692ms systemd-fsck@dev-disk-by\x2dpartuuid-56bd4a66\x2d01.service
 487ms user@1000.service
 337ms systemd-udev-trigger.service
 332ms rpi-resize-swap-file.service
 233ms systemd-udevd.service
 230ms keyboard-setup.service
 220ms systemd-binfmt.service
 220ms systemd-journald.service
```
