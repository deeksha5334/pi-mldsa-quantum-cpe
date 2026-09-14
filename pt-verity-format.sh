#!/bin/sh
set -eu
[ $# -eq 2 ] || { echo "usage: $0 <rootfs.img> <hashtree.img>" >&2; exit 2; }
DATA="$1"; HASH="$2"
[ -f "$DATA" ] || { echo "not a file: $DATA" >&2; exit 1; }
REPORT=$(veritysetup format "$DATA" "$HASH")
field() { echo "$REPORT" | grep "^$1:" | sed 's/.*:[[:space:]]*//' | tr -d '[:space:]'; }
ROOT_HASH=$(field "Root hash")
SALT=$(field "Salt")
DATA_BLOCKS=$(field "Data blocks")
DBS=$(field "Data block size")
HBS=$(field "Hash block size")
ALGO=$(field "Hash algorithm")
for v in "$ROOT_HASH" "$SALT" "$DATA_BLOCKS" "$DBS" "$HBS" "$ALGO"; do
  [ -n "$v" ] || { echo "parse failed" >&2; echo "$REPORT" >&2; exit 1; }
done
echo "# verity-data-image: $DATA"
echo "# verity-hash-image: $HASH"
echo "# verity-root-hash: $ROOT_HASH"
echo "# verity-salt: $SALT"
echo "# verity-data-blocks: $DATA_BLOCKS"
echo "# verity-data-block-size: $DBS"
echo "# verity-hash-block-size: $HBS"
echo "# verity-hash-algorithm: $ALGO"
echo "pt-verity-format: root hash $ROOT_HASH" >&2
