#!/usr/bin/env bash
# Bump all docs for a new Home Assistant release.
# Copyright (C) 2026 Andrew Youll
#
#   ./bump_docs.sh <new_version> [old_version] [changelog notes...]
#
# Examples:
#   ./bump_docs.sh 2026.9.4
#   ./bump_docs.sh 2026.10.0 2026.9.3 "Monthly minor release; review integration deps."
#
# Does the doc half of a release:
#   - replaces <old> -> <new> in README.md and HOWTO (literal string, Python)
#   - inserts a CHANGELOG entry
#   - writes RELEASE-<new>.md from the template
# It does NOT touch git or build anything - run `./build.sh <new> --push` first,
# then this, then commit. Old version is auto-detected from the README if omitted.
#
# NB: all text substitution is done with python3 (literal replace), NOT sed.
# sed differs between GNU (Linux) and BSD (macOS), and a bad pattern once turned
# every '#' in the docs into the version string. python3 is identical everywhere.
set -euo pipefail
cd "$(dirname "$0")"

command -v python3 >/dev/null || { echo "ERROR: python3 required" >&2; exit 1; }

NEW="${1:?usage: ./bump_docs.sh <new_version> [old_version] [notes]}"
OLD="${2:-}"
NOTES="${3:-Patch release. No build-recipe changes; all armv7 fixes carried over.}"
REV="${REV:-r1}"
DATE="$(date +%Y-%m-%d)"

# Auto-detect the current version from the README status line if not given.
if [[ -z "$OLD" ]]; then
  OLD="$(python3 -c 'import re,sys; m=re.search(r"2026\.\d+\.\d+", open("README.md").read()); print(m.group(0) if m else "")')"
  [[ -n "$OLD" ]] || { echo "ERROR: could not auto-detect old version - pass it as arg 2." >&2; exit 1; }
fi
[[ "$NEW" != "$OLD" ]] || { echo "ERROR: new version equals old version ($NEW)." >&2; exit 1; }

# Basic sanity: versions must look like YYYY.M.P so we never substitute junk.
for v in "$OLD" "$NEW"; do
  [[ "$v" =~ ^2[0-9]{3}\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: '$v' is not a YYYY.M.P version." >&2; exit 1; }
done

echo "Bumping docs: $OLD -> $NEW  (rev $REV, $DATE)"

# --- README + HOWTO: literal string replace via python3 ------------------------
OLD="$OLD" NEW="$NEW" python3 - <<'PY'
import os
old, new = os.environ["OLD"], os.environ["NEW"]
for f in ("README.md", "HOWTO-armv7-home-assistant.md"):
    s = open(f, encoding="utf-8").read()
    n = s.count(old)
    open(f, "w", encoding="utf-8").write(s.replace(old, new))
    print(f"  {f}: replaced {n} occurrence(s)")
PY

# --- CHANGELOG: insert a new entry before the first existing '## ' heading ------
NEW="$NEW" REV="$REV" DATE="$DATE" NOTES="$NOTES" python3 - <<'PY'
import os, re
new, rev, date, notes = (os.environ[k] for k in ("NEW", "REV", "DATE", "NOTES"))
entry = (f"## {new}-{rev} — {date}\n\n"
         f"- Rebuilt against Home Assistant **{new}**.\n"
         f"- Refreshed dependency pins from the official {new} arm64 image.\n"
         f"- {notes}\n\n"
         f"Tags: `{new}-{rev}`, `{new}`, `latest`\n\n")
s = open("CHANGELOG.md", encoding="utf-8").read()
i = s.find("\n## ")
if i == -1:
    raise SystemExit("ERROR: no '## ' heading in CHANGELOG.md")
i += 1  # keep the newline before the first heading
open("CHANGELOG.md", "w", encoding="utf-8").write(s[:i] + entry + s[i:])
print("  CHANGELOG.md: inserted entry")
PY

# --- RELEASE-<new>.md from template --------------------------------------------
REL="RELEASE-${NEW}.md"
cat > "$REL" <<EOF
# Home Assistant ${NEW} for ARMv7 — \`${NEW}-${REV}\`

Unofficial 32-bit ARM (armv7) build of Home Assistant **${NEW}**, for Raspberry
Pi 2/3 and other armv7 boards on a 32-bit OS. Home Assistant stopped publishing
official armv7 images after \`2025.11.3\`; this rebuilds a current release from
source.

## Pull

\`\`\`bash
docker pull ghcr.io/adyoull/ha-armv7:${NEW}-${REV}
\`\`\`

Also tagged \`${NEW}\` and \`latest\`. Pin to **\`${NEW}-${REV}\`** for a stable,
unchanging reference.

| Tag | Meaning |
|---|---|
| \`${NEW}-${REV}\` | This exact image. Immutable — safe to pin. |
| \`${NEW}\` | Rolling pointer for HA ${NEW}. |
| \`latest\` | Newest build overall. Will change under you. |

## What changed since \`${OLD}-r1\`

**Home Assistant upstream bumped ${OLD} → ${NEW}.** This image rebuilds against it
with the official ${NEW} dependency pins. Still Python 3.14.

${NOTES}

Everything carried over from \`${OLD}-r1\`: base + app image split, PyAV source
patch (\`patch_av.sh\`), libstdc++ relink, \`pyatv\`/\`miniaudio\` (Apple TV),
\`bleak-smlight\` from source, MFA modules, and the HTTPS-aware healthcheck.

## Verify the image

\`\`\`bash
docker run --rm --platform linux/arm/v7 --entrypoint python \\
  ghcr.io/adyoull/ha-armv7:${NEW}-${REV} \\
  -c "from homeassistant.const import __version__; from importlib.metadata import version; import av; \\
      print(__version__, '| av', version('av'), '| pyatv', version('pyatv'), \\
            '| pyotp', version('pyotp'), '| bleak-smlight', version('bleak-smlight'))"
\`\`\`

Expected: \`${NEW} | av <pin> | pyatv 0.18.0 | pyotp 2.9.0 | bleak-smlight 1.1.0\`

## Notes

Unofficial and unsupported — Home Assistant will not accept issue reports for it.
Full build recipe and troubleshooting are in
[\`HOWTO-armv7-home-assistant.md\`](./HOWTO-armv7-home-assistant.md).

If your hardware allows it, the durable fix remains reflashing to **64-bit
Raspberry Pi OS** — a Pi 3 supports it — which puts you back on official images.

---

_Copyright (C) 2026 Andrew Youll._
EOF
echo "  wrote $REL"

cat <<EOF

Docs bumped $OLD -> $NEW. Review, then commit:

  git add README.md HOWTO-armv7-home-assistant.md CHANGELOG.md \\
          $REL official-${NEW}.txt
  git commit -m "docs: ${NEW}-${REV}"
  git push

Then draft the GitHub release: tag ${NEW}-${REV}, paste $REL.
EOF
