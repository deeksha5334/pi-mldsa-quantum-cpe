#!/bin/bash
# pt-finalize-image.sh - Team Singularity
# Post-build, pre-hash finalize of the rpi-image-gen output, then dm-verity (hash LAST),
# manifest v4 (firmware-version: 1), ML-DSA-65 sign, and bench rehearsal of boot stages 1-3.
# Touches ONLY the build-output image file. Never the running card, the EEPROM or OTP.
set -euo pipefail

IMG="$HOME/rpi-image-gen/work/image-pi-trust-sb/pi-trust-sb.img"
SRC="$HOME/pt-imagegen"
SIGN="$HOME/pi-trust-signing"
BIN="$SRC/pt-verify"
W="$HOME/pt-build-v040-$(date +%m%d-%H%M%S)-$$"
MNT=/mnt/ptroot
LOOP=""

cleanup() {
  if mountpoint -q "$MNT"; then sudo umount "$MNT" || true; fi
  if [ -n "$LOOP" ]; then sudo losetup -d "$LOOP" 2>/dev/null || true; fi
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo; echo "=== $* ==="; }

step "0. preconditions"
[ -f "$IMG" ] || fail "no image at $IMG"
ls -la "$IMG"
[ "$(sha256sum < "$BIN" | cut -d' ' -f1)" = "eb2a3d6fba405ed6a1da4184b23dbd4a09a2d0ac285e99beeb8230139da46ce0" ] || fail "staged verifier is not eb2a3d6f"
[ "$(sha256sum < "$SRC/fstab-verity" | cut -d' ' -f1)" = "59863164234ad8f31c0d8449ca4d29ae5ede9b55c193617f58b1e02b87e4d94f" ] || fail "fstab-verity is not 59863164"
KEY=$(grep -E ' singularity-pi-a$' "$HOME/.ssh/authorized_keys" | head -1 || true)
[ -n "$KEY" ] || fail "Mac key 'singularity-pi-a' not found in ~/.ssh/authorized_keys"
if mountpoint -q "$MNT"; then fail "$MNT is already mounted"; fi
mkdir "$W"; cd "$W"; echo "output dir: $W"

step "1. attach image read-write, mount root partition"
LOOP=$(sudo losetup -Pf --show "$IMG"); echo "loop=$LOOP"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -b "${LOOP}p2" ] && break; sleep 0.5; done
[ -b "${LOOP}p2" ] || fail "partition node ${LOOP}p2 did not appear"
sudo mount "${LOOP}p2" "$MNT"
R="$MNT"

step "2. finalize: verity fstab, pi SSH key (key-only), pi sudo"
sudo install -m 644 -o root -g root "$SRC/fstab-verity" "$R/etc/fstab"
sudo install -d -m 700 -o 1000 -g 1000 "$R/home/pi/.ssh"
printf '%s\n' "$KEY" | sudo tee "$R/home/pi/.ssh/authorized_keys" >/dev/null
sudo chown 1000:1000 "$R/home/pi/.ssh/authorized_keys"
sudo chmod 600 "$R/home/pi/.ssh/authorized_keys"
printf '%s\n' 'pi ALL=(ALL) NOPASSWD: ALL' | sudo tee "$R/etc/sudoers.d/020_pi-nopasswd" >/dev/null
sudo chmod 440 "$R/etc/sudoers.d/020_pi-nopasswd"
sudo visudo -cf "$R/etc/sudoers.d/020_pi-nopasswd"

step "3. check what was set + services enabled at boot"
sha256sum "$R/etc/fstab"
sudo ssh-keygen -lf "$R/home/pi/.ssh/authorized_keys"
sudo ls -ln "$R/home/pi/.ssh/authorized_keys" "$R/etc/sudoers.d/020_pi-nopasswd"
[ -x "$R/usr/bin/sudo" ] || fail "sudo is not installed in the image"
ls "$R/etc/systemd/system/multi-user.target.wants/" | grep -E 'ssh|NetworkManager' || echo "WARN: ssh/NetworkManager not enabled"
ls "$R/etc/systemd/system/" | grep -E 'resolve' || echo "WARN: systemd-resolved may not be enabled"
sudo grep -rhE '^(PasswordAuthentication|PermitRootLogin|AllowUsers|PubkeyAuthentication)' "$R/etc/ssh/sshd_config" "$R/etc/ssh/sshd_config.d/" 2>/dev/null || true

step "4. unmount, fsck (must be clean), then hash LAST (F-14)"
sudo umount "$MNT"
set +e; sudo e2fsck -fp "${LOOP}p2"; rc=$?; set -e
[ "$rc" -le 1 ] || fail "e2fsck exit $rc"
echo "e2fsck exit $rc (0/1 = clean)"
sudo veritysetup format "${LOOP}p2" "$W/verity-hash.img" | tee "$W/verity-format.txt"
sudo chown "$(id -u):$(id -g)" "$W/verity-hash.img"
RH=$(awk -F':[ \t]+' '/^Root hash/{print $2}' "$W/verity-format.txt")
SALT=$(awk -F':[ \t]+' '/^Salt/{print $2}' "$W/verity-format.txt")
DB=$(awk -F':[ \t]+' '/^Data blocks/{print $2}' "$W/verity-format.txt")
[ "${#RH}" -eq 64 ] && [ "${#SALT}" -eq 64 ] && [ -n "$DB" ] || fail "could not parse veritysetup output"
PSZ=$(sudo blockdev --getsize64 "${LOOP}p2")
[ $((DB * 4096)) -eq "$PSZ" ] || fail "data blocks $DB do not cover the whole partition ($PSZ bytes)"
echo "verity covers the whole partition: $DB blocks x 4096 = $PSZ bytes"

step "5. bench-verify every block against the new root hash (reads 1.7 GB, ~1 min)"
sudo veritysetup verify "${LOOP}p2" "$W/verity-hash.img" "$RH"
echo "veritysetup verify: OK"

step "6. provenance"
P2SHA=$(sudo sha256sum "${LOOP}p2" | cut -d' ' -f1)
FSUUID=$(sudo blkid -s UUID -o value "${LOOP}p2")
HSHA=$(sha256sum "$W/verity-hash.img" | cut -d' ' -f1)
RECIPE=$(git -C "$SRC" rev-parse --short HEAD)
sudo losetup -d "$LOOP"; LOOP=""
echo "partition 2 sha256: $P2SHA"; echo "fs uuid: $FSUUID"; echo "recipe: $RECIPE"

step "7. write manifest v4"
{
printf '# pi-trust-manifest v4\n'
printf '# created: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '# algorithm: ML-DSA-65 (FIPS 204)\n'
printf '# context: pi-trust-manifest-v1\n'
printf '#\n'
printf '# ENFORCED AT BOOT - anti-rollback, checked by the verifier after the signature\n'
printf '# firmware-version: 1\n'
printf '#\n'
printf '# ENFORCED AT BOOT - verity parameters, cross-checked before activation\n'
printf '# verity-root-hash: %s\n' "$RH"
printf '# verity-salt: %s\n' "$SALT"
printf '# verity-data-blocks: %s\n' "$DB"
printf '# verity-data-block-size: 4096\n'
printf '# verity-hash-block-size: 4096\n'
printf '# verity-hash-algorithm: sha256\n'
printf '#\n'
printf '# PROVENANCE ONLY - recorded at build time, NOT checked at boot\n'
printf '# The boot path verifies the rootfs by root hash, per block, on read.\n'
printf '# The hash tree is authenticated through verity-root-hash by dm-verity,\n'
printf '# so the hash-file digest below is a record, not a boot-time check.\n'
printf '%s  verity-hash.img\n' "$HSHA"
printf '# build-image-sha256: %s\n' "$P2SHA"
printf '# build-image-name: pi-trust-sb.img partition 2\n'
printf '# build-image-uuid: %s\n' "$FSUUID"
printf '# build-date: %s\n' "$(date -u +%Y-%m-%d)"
printf '# build-recipe: pt-imagegen %s (layer 0.4.0)\n' "$RECIPE"
} > manifest.txt
cat manifest.txt

step "8. sign, then verify: device key VALID, attacker key INVALID"
"$SIGN/build/pt-sign" manifest.txt "$SIGN/dev.sk" manifest.sig
"$BIN" manifest.txt manifest.sig "$SRC/dev.pk"
if "$BIN" manifest.txt manifest.sig "$SIGN/attacker.pk" >/dev/null 2>&1; then
  fail "attacker key verified the manifest"
fi
echo "attacker key: INVALID (good)"

step "9. rehearse boot stages 1-3 on these exact files (stops before stage 4)"
cp "$SRC/dev.pk" pk
sed -e 's|^\. /scripts/functions|panic() { echo "PANIC: $*"; exit 1; }|' -e 's|> /dev/kmsg||' -e '/sysrq-trigger/d' \
    -e "s|^MAN=.*|MAN=$W/manifest.txt|" -e "s|^SIG=.*|SIG=$W/manifest.sig|" -e "s|^PK=.*|PK=$W/pk|" \
    -e "s|^HASHIMG=.*|HASHIMG=$W/verity-hash.img|" -e "s|^BIN=.*|BIN=$BIN|" -e 's|^DATADEV=.*|DATADEV=/nonexistent|' \
    -e "s|/tmp/vout|$W/vout|g" -e "s|/tmp/vdump|$W/vdump|g" "$SRC/script-pt-verify" > rehearse.sh
sh rehearse.sh || true

step "DONE"
echo "root hash: $RH"
echo "outputs:"; ls -la "$W"
