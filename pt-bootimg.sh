#!/bin/bash
# pt-bootimg.sh - Team Singularity
# Second pass after pt-finalize-image.sh: put the signed manifest + hash tree into the image's
# initramfs, build boot.img (-a 64), RSA-sign it, and install boot.img + boot.sig on the image's
# boot partition. Touches ONLY the build-output image file. Never the running card, EEPROM or OTP.
set -euo pipefail

IMG="$HOME/rpi-image-gen/work/image-pi-trust-sb/pi-trust-sb.img"
SRC="$HOME/pt-imagegen"
SIGN="$HOME/pi-trust-signing"
UB="$HOME/usbboot/tools"
VFAT="$HOME/rpi-image-gen/work/image-pi-trust-sb/boot.vfat"   # pristine boot partition from the build
P1=/mnt/ptboot
BI=/mnt/ptbootimg
VF=/mnt/ptvfat
LOOP=""

cleanup() {
  for m in "$BI" "$VF" "$P1"; do if mountpoint -q "$m"; then sudo umount "$m" || true; fi; done
  if [ -n "$LOOP" ]; then sudo losetup -d "$LOOP" 2>/dev/null || true; fi
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo; echo "=== $* ==="; }
sha() { sha256sum < "$1" | cut -d' ' -f1; }
ssha() { sudo sha256sum -- "$1" | cut -d' ' -f1; }

step "0. preconditions"
B=$(ls -td "$HOME"/pt-build-v040-* 2>/dev/null | head -1 || true)
[ -n "$B" ] || fail "no ~/pt-build-v040-* folder (run pt-finalize-image.sh first)"
echo "build folder (newest): $B"
for f in manifest.txt manifest.sig verity-hash.img; do [ -f "$B/$f" ] || fail "missing $B/$f"; done
for f in "$UB/rpi-make-boot-image" "$UB/rpi-eeprom-digest" "$SIGN/rsa-dev-private.pem" "$SIGN/rsa-dev-public.pem" \
         "$SIGN/signed-boot/config.txt.card" "$SIGN/signed-boot/cmdline.txt.card"; do
  [ -e "$f" ] || fail "missing $f"
done
for t in unmkinitramfs cpio gzip python3; do command -v "$t" >/dev/null || fail "tool not found: $t"; done
for m in "$P1" "$BI" "$VF"; do if mountpoint -q "$m"; then fail "$m is already mounted"; fi; done
[ -e "$B/PACKAGED" ] && fail "$B was already packaged and installed (delete $B/PACKAGED only if you mean to redo it)"
[ -f "$VFAT" ] || fail "missing pristine $VFAT"
"$SRC/pt-verify" "$B/manifest.txt" "$B/manifest.sig" "$SRC/dev.pk" | grep -q PT_VERIFY_OK_A5C3 || fail "manifest signature does not verify"
RH=$(sed -n 's/^# verity-root-hash: //p' "$B/manifest.txt")
P2WANT=$(sed -n 's/^# build-image-sha256: //p' "$B/manifest.txt")
echo "manifest OK, root hash $RH"
sudo mkdir -p "$P1" "$BI" "$VF"

step "1. attach image; partition 2 must be exactly what was hashed and signed"
LOOP=$(sudo losetup -Pf --show "$IMG"); echo "loop=$LOOP"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -b "${LOOP}p2" ] && break; sleep 0.5; done
[ -b "${LOOP}p1" ] && [ -b "${LOOP}p2" ] || fail "partition nodes did not appear"
P2NOW=$(ssha "${LOOP}p2")
[ "$P2NOW" = "$P2WANT" ] || fail "partition 2 changed since signing ($P2NOW != $P2WANT) - rerun pt-finalize-image.sh"
echo "partition 2 matches the signed manifest: $P2NOW"

step "2. stage the boot files from the pristine build boot.vfat (card config.txt + cmdline.txt from Oct 7)"
S="$B/stage"; IRD="$B/ird"; CHK="$B/ird-check"
sudo rm -rf -- "$S" "$IRD" "$CHK" "$B/initramfs8.new" "$B/boot.img" "$B/boot.sig" "$B/tamper.img"
mkdir "$S"
sudo mount -o loop,ro "$VFAT" "$VF"
sudo cp -r "$VF"/. "$S"/
sudo umount "$VF"
sudo cp "$SIGN/signed-boot/config.txt.card" "$S/config.txt"
sudo cp "$SIGN/signed-boot/cmdline.txt.card" "$S/cmdline.txt"
echo "cmdline: $(cat "$S/cmdline.txt")"

step "3. initramfs surgery: add manifest, signature, hash tree; repack (gzip -9, as Oct 7)"
sudo unmkinitramfs "$S/initramfs8" "$IRD"
[ -d "$IRD/main" ] && fail "initramfs has an early/main split - not handled, stop"
[ "$(ssha "$IRD/scripts/local-top/pt-verify")" = "946dbb3e3a28c2e196b417c59d7c3438f4b0736a13bd024d5f73cd9f3f0513ad" ] || fail "boot script in initramfs is not 946dbb3e"
[ "$(ssha "$IRD/usr/local/bin/pt-verify")" = "eb2a3d6fba405ed6a1da4184b23dbd4a09a2d0ac285e99beeb8230139da46ce0" ] || fail "verifier in initramfs is not eb2a3d6f"
sudo cmp "$IRD/etc/pi-trust/device.pk" "$SRC/dev.pk" || fail "device.pk in initramfs differs from dev.pk"
sudo install -m 644 -o root -g root "$B/manifest.txt" "$IRD/etc/pi-trust/manifest.txt"
sudo install -m 644 -o root -g root "$B/manifest.sig" "$IRD/etc/pi-trust/manifest.sig"
sudo install -m 644 -o root -g root "$B/verity-hash.img" "$IRD/etc/pi-trust/verity-hash.img"
( cd "$IRD" && sudo sh -c 'find . | cpio -o -H newc --quiet' ) | gzip -9 > "$B/initramfs8.new"
echo "repacked initramfs: $(stat -c %s "$B/initramfs8.new") bytes"
mkdir "$CHK"
( cd "$CHK" && gunzip -c "$B/initramfs8.new" | sudo cpio -id --quiet )
for f in manifest.txt manifest.sig verity-hash.img; do
  [ "$(ssha "$CHK/etc/pi-trust/$f")" = "$(sha "$B/$f")" ] || fail "repacked initramfs has wrong $f"
done
[ "$(ssha "$CHK/scripts/local-top/pt-verify")" = "946dbb3e3a28c2e196b417c59d7c3438f4b0736a13bd024d5f73cd9f3f0513ad" ] || fail "repacked boot script wrong"
[ "$(ssha "$CHK/usr/local/bin/pt-verify")" = "eb2a3d6fba405ed6a1da4184b23dbd4a09a2d0ac285e99beeb8230139da46ce0" ] || fail "repacked verifier wrong"
echo "repacked initramfs verified: manifest, signature, hash tree, script, verifier all exact"
sudo cp "$B/initramfs8.new" "$S/initramfs8"

step "4. build boot.img (-a 64 is required: TRAP 1) and check what is inside"
sudo "$UB/rpi-make-boot-image" -a 64 -b pi4 -d "$S" -o "$B/boot.img"
sudo chown "$(id -u):$(id -g)" "$B/boot.img"
sudo mount -o loop,ro "$B/boot.img" "$BI"
for f in kernel8.img initramfs8 start4.elf fixup4.dat config.txt cmdline.txt bcm2711-rpi-4-b.dtb; do
  [ -f "$BI/$f" ] || fail "boot.img is missing $f"
done
[ "$(sha "$BI/initramfs8")" = "$(sha "$B/initramfs8.new")" ] || fail "boot.img initramfs8 is not the repacked one"
cmp "$BI/cmdline.txt" "$SIGN/signed-boot/cmdline.txt.card" || fail "boot.img cmdline.txt wrong"
cmp "$BI/config.txt" "$SIGN/signed-boot/config.txt.card" || fail "boot.img config.txt wrong"
ls -la "$BI" | head -20
sudo umount "$BI"
echo "boot.img: $(stat -c %s "$B/boot.img") bytes"

step "5. RSA-sign boot.img, verify, and prove a 1-byte change is rejected"
"$UB/rpi-eeprom-digest" -k "$SIGN/rsa-dev-private.pem" -i "$B/boot.img" -o "$B/boot.sig"
"$UB/rpi-eeprom-digest" -k "$SIGN/rsa-dev-public.pem" -i "$B/boot.img" -v "$B/boot.sig"
cp "$B/boot.img" "$B/tamper.img"
python3 -c "import sys;f=open(sys.argv[1],'r+b');f.seek(5000000);b=f.read(1);f.seek(5000000);f.write(bytes([b[0]^0xff]))" "$B/tamper.img"
if "$UB/rpi-eeprom-digest" -k "$SIGN/rsa-dev-public.pem" -i "$B/tamper.img" -v "$B/boot.sig" >/dev/null 2>&1; then
  fail "tampered boot.img verified"
fi
rm -f "$B/tamper.img"
echo "1-byte-tampered boot.img: REJECTED (good)"

step "6. install boot.img + boot.sig on the image's boot partition"
sudo mount "${LOOP}p1" "$P1"
df -h "$P1" | tail -1
# Signed boot loads ONLY boot.img; the loose kernel/initramfs are unsigned copies of what is inside it.
sudo rm -f "$P1/kernel8.img" "$P1/initramfs8"
sudo cp "$SIGN/signed-boot/config.txt.card" "$P1/config.txt"
sudo cp "$SIGN/signed-boot/cmdline.txt.card" "$P1/cmdline.txt"
sudo cp "$B/boot.img" "$B/boot.sig" "$P1/"
sync
[ "$(ssha "$P1/boot.img")" = "$(sha "$B/boot.img")" ] || fail "boot.img on partition 1 does not match"
sudo cmp "$P1/boot.sig" "$B/boot.sig" || fail "boot.sig on partition 1 does not match"
df -h "$P1" | tail -1
sudo umount "$P1"

step "7. final proof: partition 2 still exactly what was signed"
[ "$(ssha "${LOOP}p2")" = "$P2WANT" ] || fail "partition 2 changed"
echo "partition 2 unchanged: $P2WANT"
sudo losetup -d "$LOOP"; LOOP=""
date -u +%Y-%m-%dT%H:%M:%SZ > "$B/PACKAGED"

step "DONE - image ready to flash"
echo "image:     $IMG"
echo "boot.img:  $(sha "$B/boot.img")  ($(stat -c %s "$B/boot.img") bytes)"
echo "root hash: $RH"
