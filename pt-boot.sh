#!/bin/sh
# pt-boot - verified boot orchestrator. ORDER IS THE SECURITY PROPERTY:
#   1 verify signature -> 2 read params -> 3 cross-check -> 4 activate
set -eu
VERIFY="./build/pt-verify"
MAPPER="pt-root"
die() { echo "pt-boot: ABORT - $*" >&2; exit 1; }

[ $# -eq 4 ] || { echo "usage: $0 <manifest> <sig> <key.pk> <mountpoint>" >&2; exit 2; }
MANIFEST="$1"; SIG="$2"; PUBKEY="$3"; MOUNTPOINT="$4"
[ -x "$VERIFY" ] || die "verifier missing: $VERIFY"

echo "pt-boot: [1/4] verifying manifest signature"
"$VERIFY" "$MANIFEST" "$SIG" "$PUBKEY" || die "signature invalid - refusing to configure dm-verity"

echo "pt-boot: [2/4] reading parameters from SIGNED manifest"
mfield() { grep "^# $1:" "$MANIFEST" | head -1 | sed "s|^# $1:[[:space:]]*||" | tr -d '[:space:]'; }
DATA_IMG=$(mfield "verity-data-image")
HASH_IMG=$(mfield "verity-hash-image")
ROOT_HASH=$(mfield "verity-root-hash")
SALT=$(mfield "verity-salt")
DATA_BLOCKS=$(mfield "verity-data-blocks")
DBS=$(mfield "verity-data-block-size")
HBS=$(mfield "verity-hash-block-size")
for n in DATA_IMG HASH_IMG ROOT_HASH SALT DATA_BLOCKS DBS HBS; do
  eval "v=\$$n"; [ -n "$v" ] || die "signed manifest missing $n"
done
[ -f "$DATA_IMG" ] || die "data image not found: $DATA_IMG"
[ -f "$HASH_IMG" ] || die "hash image not found: $HASH_IMG"
echo "         root hash : $ROOT_HASH"
echo "         blocks    : $DATA_BLOCKS x $DBS B"

echo "pt-boot: [3/4] cross-checking hash device against signed parameters"
DUMP=$(veritysetup dump "$HASH_IMG") || die "cannot read hash superblock"
dfield() { echo "$DUMP" | grep "^$1:" | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '[:space:]'; }
check() {
  if [ "$2" != "$3" ]; then
    echo "         MISMATCH $1" >&2
    echo "           signed : $2" >&2
    echo "           device : $3" >&2
    die "hash device does not match signed manifest"
  fi
  echo "         ok: $1"
}
check "salt" "$SALT" "$(dfield 'Salt')"
check "data blocks" "$DATA_BLOCKS" "$(dfield 'Data blocks')"
check "data block size" "$DBS" "$(dfield 'Data block size')"
check "hash block size" "$HBS" "$(dfield 'Hash block size')"

echo "pt-boot: [4/4] activating dm-verity"
if veritysetup status "$MAPPER" >/dev/null 2>&1; then
  veritysetup close "$MAPPER" || die "stale mapping stuck"
fi
veritysetup open "$DATA_IMG" "$MAPPER" "$HASH_IMG" "$ROOT_HASH" || die "veritysetup open failed"
mkdir -p "$MOUNTPOINT"
mount -o ro "/dev/mapper/$MAPPER" "$MOUNTPOINT" || {
  veritysetup close "$MAPPER" 2>/dev/null || true
  die "mount failed - check dmesg for verity corruption"
}
echo ""
echo "pt-boot: VERIFIED ROOT ACTIVE at $MOUNTPOINT"
echo "  ML-DSA-65 sig -> manifest -> verity root hash -> every block"
echo "  Note: verification is lazy. A clean mount != a clean image (F-11)."
