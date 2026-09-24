# Signed boot enabled, EEPROM-only mode (2026-09-23)

The chain of trust is closed. The Pi 4 now boots ONLY from an RSA-signed
boot.img, and that boot.img contains the ML-DSA-65 verifier.

    BCM2711 ROM        RSA-2048, fixed in silicon
      EEPROM bootloader  config signed with our RSA key, SIGNED_BOOT=1
        boot.img         verified against boot.sig        <- NEW
          ML-DSA-65 verifier (initramfs, enforcing)
            manifest -> kernel / rootfs

OTP is still BLANK. SIGNED_BOOT is set in the EEPROM config only, which is
reversible. No irreversible operation has been performed.

## What was built

boot.img  34 MB  kernel8.img, initramfs8 (contains pt-verify), start4.elf,
                 fixup4.dat, config.txt, cmdline.txt, Pi 4 DTBs, overlays
  sha256  8bae0316c17325ce6b7cc5330e57cfd88c131fa45190a6d86d5240656b409931
boot.sig  602 B  SHA-256 + RSA-2048 signature (rpi-eeprom-digest)

pieeprom.bin  512 KB  bootloader 2026-05-17 (UNCHANGED version) + signed config
pieeprom.sig   80 B

EEPROM config now active:
  BOOT_UART=1            bootloader serial output retained
  WAKE_ON_GPIO=1         unchanged from baseline
  POWER_OFF_ON_HALT=0    unchanged from baseline
  BOOT_ORDER=0x1         SD ONLY - removes USB/network alternate boot paths
  ENABLE_SELF_UPDATE=0   no silent bootloader self-update (R-8 class)
  SIGNED_BOOT=1          load only boot.img, verify against boot.sig

## How it was built

  # 1. stage the boot partition, minus rollback copies and macOS junk
  rsync -a --exclude='._*' --exclude='.Spotlight-V100' --exclude='.Trashes' \
        --exclude='*.known-good' --exclude='*.bak' --exclude='*.audit-ok' \
        /boot/firmware/ ~/bootimg-stage/

  # 2. boot.img must be self-contained: name kernel and initramfs explicitly
  #    (added to ~/bootimg-stage/config.txt, auto_initramfs commented out)
  kernel=kernel8.img
  initramfs initramfs8 followkernel

  # 3. build - NOTE -a 64 is REQUIRED, see trap below
  sudo ~/usbboot/tools/rpi-make-boot-image -a 64 -b pi4 -d ~/bootimg-stage -o ~/boot.img

  # 4. sign
  ~/usbboot/tools/rpi-eeprom-digest -i ~/boot.img -o ~/boot.sig -k rsa-dev-private.pem

  # 5. EEPROM image with SIGNED_BOOT=1 (boot.conf in this directory)
  cd ~/usbboot/secure-boot-recovery
  sudo ../tools/update-pieeprom.sh -k ~/pi-trust-signing/rsa-dev-private.pem

  # 6. install boot.img + boot.sig BEFORE flashing the EEPROM
  sudo cp ~/boot.img ~/boot.sig /boot/firmware/

  # 7. flash via the running system - NO rpiboot, NO GPIO jumper, NO OTP write
  sudo rpi-eeprom-update -d -f pieeprom.bin
  sudo reboot

## Traps

TRAP 1 - rpi-make-boot-image defaults to 32-bit and DELETES kernel8.img.
  Line 354: if ARCH = 32 then rm -f staging/kernel8.img
  Without -a 64 you get a 24 MB boot.img with NO KERNEL and no error.
  Always mount the result and check: kernel8.img, initramfs8, start4.elf,
  fixup4.dat, config.txt, cmdline.txt.

TRAP 2 - config.txt relies on defaults. Raspberry Pi OS has no kernel= line
  and uses auto_initramfs=1. The pruning step then has no way to know the
  kernel is needed. boot.img must name both explicitly.

TRAP 3 - the documented rpiboot flashing route needs program_rpiboot_gpio on
  a Pi 4B, which is an IRREVERSIBLE OTP write. rpi-eeprom-update -d -f does
  the same job from the running system with no OTP change. Use it.

TRAP 4 - without -d, rpi-eeprom-update RETAINS the existing config and
  discards SIGNED_BOOT=1. The config is the entire point of this image.

## Tests - positive and negative, on hardware

  Verify good image        rpi-eeprom-digest -v  ->  Verified OK, exit 0
  Verify 1 byte changed    (offset 5,000,000)    ->  Verification failure, exit 1
  Boot with good boot.img  ->  boots; ENFORCE RESULT VALID from pt-verify
  Boot with +1 byte        ->  DEVICE DOES NOT BOOT, sustained ping timeouts
  Restore boot.img.good    ->  boots normally

Two independent layers now each demonstrated to halt the boot:
  RSA-2048  tamper boot.img   -> rejected by the BOOTLOADER, before Linux
  ML-DSA-65 tamper manifest   -> rejected by the initramfs verifier

## Recovery

boot.img.good and boot.sig.good are kept on the boot partition. If boot.img
is bad: card into a host, open bootfs, delete boot.img, rename boot.img.good.
If the EEPROM is bad: the EEPROM RECOVERY SD card.

## Still open

- OTP blank. SIGNED_BOOT is reversible today. Burning program_pubkey=1 is
  irreversible and is the LAST step, on one designated board.
- boot.img is a SNAPSHOT. Any change to the kernel, initramfs, cmdline.txt or
  config.txt requires rebuilding AND re-signing boot.img, or the Pi boots the
  old contents inside the image.
- The manifest inside the initramfs is still the TEST manifest. It does not
  yet cover the real kernel or the real rootfs via dm-verity.
- The RSA-2048 link is quantum-vulnerable and cannot be changed on BCM2711.
- DEV RSA key generated on the device with no ceremony. rpi-eeprom-digest -H
  supports an HSM wrapper; that is the production path.
- boot.img is 34 MB, mostly a general-purpose Debian initramfs (19.7 MB).
  "Large image size" warning is informational. R-14 size ceiling still unknown.
