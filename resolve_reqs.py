#!/usr/bin/env python3
# Copyright (C) 2026 Andrew Youll
"""
Resolve the pip requirements needed by a set of Home Assistant integrations.

`pip install homeassistant` only installs the core framework. Each integration
declares its own pip requirements in components/<domain>/manifest.json, which
the official HA image pre-installs. This walks the dependency graph and prints
the full requirement set so the Dockerfile can install it at build time.

Usage:  python resolve_reqs.py default_config [more_integrations...]
"""

import json
import pathlib
import sys

import homeassistant.components

COMPONENTS = pathlib.Path(homeassistant.components.__file__).parent

# HA components import each other's modules WITHOUT declaring the relationship in
# manifest.json "dependencies", so a pure dependency walk misses them and you get
# ModuleNotFoundError at runtime. Each of these was an actual boot failure:
#
#   analytics, homeassistant_alerts  -> import components.hassio  -> aiohasupervisor
#   usb                              -> import serialx            -> aioesphomeapi
#   infrared                         -> infrared_protocols
#   radio_frequency                  -> rf_protocols
#   google_translate (default TTS)   -> gtts
ALWAYS = [
    "hassio",
    "esphome",
    "google_translate",
    "infrared",
    "radio_frequency",
    "usb",
    "bluetooth",
    "stream",
]

# Not integration requirements, but HA whines about them and they're cheap wins:
#   WARNING [aiohttp_fast_zlib] zlib_ng and isal are not available ...
EXTRA_PACKAGES = ["zlib-ng", "isal"]


def manifest(domain: str) -> dict | None:
    path = COMPONENTS / domain / "manifest.json"
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def main() -> int:
    roots = sys.argv[1:] or ["default_config"]

    seen: set[str] = set()
    queue: list[str] = list(roots) + ALWAYS
    reqs: set[str] = set(EXTRA_PACKAGES)
    missing: list[str] = []

    while queue:
        domain = queue.pop()
        if domain in seen:
            continue
        seen.add(domain)

        m = manifest(domain)
        if m is None:
            # Custom/HACS components aren't shipped with HA - expected.
            missing.append(domain)
            continue

        reqs.update(m.get("requirements", []))
        # Walk BOTH edges. after_dependencies matters: integrations import each
        # other across that edge and blow up at runtime if the deps are absent.
        queue.extend(m.get("dependencies", []))
        queue.extend(m.get("after_dependencies", []))

    print(f"# {len(seen)} integrations -> {len(reqs)} requirements", file=sys.stderr)
    if missing:
        print(f"# not built-in (custom/HACS?): {', '.join(sorted(missing))}", file=sys.stderr)

    for r in sorted(reqs):
        print(r)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
