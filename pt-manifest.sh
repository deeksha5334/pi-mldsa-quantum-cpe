#!/bin/sh
set -eu

if [ $# -lt 1 ]; then
    echo "usage: $0 <artifact> [<artifact> ...]" >&2
    exit 2
fi

for f in "$@"; do
    if [ ! -f "$f" ]; then
        echo "pt-manifest: not a file: $f" >&2
        exit 1
    fi
done

echo "# pi-trust-manifest v1"
echo "# created: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# algorithm: ML-DSA-65 (FIPS 204)"
echo "# context: pi-trust-manifest-v1"
echo "# artifacts: $#"

if ! sha256sum "$@"; then
    echo "pt-manifest: FATAL - could not hash one or more artifacts" >&2
    exit 1
fi
