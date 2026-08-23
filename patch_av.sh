#!/bin/sh
# Build PyAV (av) from a patched source tree.
# Copyright (C) 2026 Andrew Youll
#
# av 17.0.1's av/container/pyio.py redeclares `seek_func: seek_func_t = ...`,
# which Cython 3.1.7+ rejects ("'seek_func' redeclared"). HA pins av==17.0.1,
# which predates the upstream fix. We apply that one-line fix (drop the redundant
# type annotation, as av 18.1 does) then build against the base image's FFmpeg 8
# using the base image's Cython (--no-build-isolation, no ~15min recompile).
#
# IMPORTANT: we fetch the sdist with curl, NOT `pip download`. `pip download
# --no-binary` resolves sdist metadata by running the PEP517 build hook, which
# cythonizes the UNPATCHED source and fails before we ever patch it.
set -eu

CONSTRAINTS="${1:?usage: patch_av.sh <constraints-file>}"
SRC=/tmp/avsrc
rm -rf "$SRC"; mkdir -p "$SRC"

AV_VER=$(grep -iE '^av==' "$CONSTRAINTS" | head -1 | cut -d= -f3)
[ -n "$AV_VER" ] || { echo "!!! no av== pin in $CONSTRAINTS" >&2; exit 1; }
echo "--- resolving av $AV_VER sdist URL"
URL=$(python -c "import json,urllib.request; d=json.load(urllib.request.urlopen('https://pypi.org/pypi/av/${AV_VER}/json')); print(next(u['url'] for u in d['urls'] if u['packagetype']=='sdist'))")
echo "    $URL"

echo "--- downloading sdist"
curl -fsSL "$URL" -o "$SRC/av.tar.gz"
tar xf "$SRC/av.tar.gz" -C "$SRC"

PYIO=$(echo "$SRC"/av-*/av/container/pyio.py)
echo "--- patching $PYIO"
sed -i -E 's/^([[:space:]]*)seek_func: seek_func_t = pyio_seek/\1seek_func = pyio_seek/' "$PYIO"

if grep -q 'seek_func: seek_func_t = pyio_seek' "$PYIO"; then
  echo "!!! PATCH DID NOT APPLY - pyio.py still has the redeclaration" >&2
  grep -n 'seek_func' "$PYIO" >&2
  exit 1
fi
echo "--- patch applied:"; grep -n 'seek_func' "$PYIO"

echo "--- building av (no build isolation: base image Cython + FFmpeg 8)"
pip install --no-build-isolation "$SRC"/av-*/ -c "$CONSTRAINTS"

# The requirements batch (an earlier, cached layer) tries av from PyPI, fails on
# the Cython issue, and logs it to the failed-requirements file. We just built av
# correctly, so drop that stale entry to avoid a false "did NOT install" warning.
sed -i '/^av==/d' /etc/ha-armv7-failed-requirements.txt 2>/dev/null || true

rm -rf "$SRC"
