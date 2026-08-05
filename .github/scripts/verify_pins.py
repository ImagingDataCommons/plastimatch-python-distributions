#!/usr/bin/env python3
"""
Verify that every archive pinned in ``plastimatchUrls.cmake`` is still downloadable and still
has the checksum recorded for it.

This guards the seam between the two layers. The pins point at GitHub release assets, and a
release can be re-cut with new assets under the same tag -- in particular a rolling "latest"
prerelease, whose assets are replaced on every upstream commit. When that happens every wheel
job fails deep inside CMake with an opaque hash mismatch. Failing here instead says plainly
which archive moved and what to do about it.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

CMAKE_FILE = Path(__file__).parents[2] / "plastimatchUrls.cmake"
PLATFORMS = ("linux", "macos_arm64", "macos_x86_64", "win64")
CHUNK = 1 << 20


def _scalar(text: str, name: str) -> str:
    """Read a set(<name> "<literal>") value, ignoring lines that reference variables."""
    match = re.search(rf'^set\({re.escape(name)}\s+"([^"$]*)"', text, re.MULTILINE)
    if match is None:
        msg = f"Could not find a literal value for '{name}' in {CMAKE_FILE.name}"
        raise SystemExit(msg)
    return match.group(1)


def main() -> int:
    text = CMAKE_FILE.read_text(encoding="utf-8")

    repo = _scalar(text, "PLASTIMATCH_BINARIES_REPO")
    tag = _scalar(text, "PLASTIMATCH_BINARIES_TAG")
    base = f"https://github.com/{repo}/releases/download/{tag}"
    print(f"checking pinned archives in {repo}@{tag}\n")

    failures = 0
    for platform in PLATFORMS:
        filename = _scalar(text, f"{platform}_filename")
        expected = _scalar(text, f"{platform}_sha256")
        url = f"{base}/{filename}"
        print(f"--- {platform}: {filename}")

        digest = hashlib.sha256()
        try:
            with urlopen(url) as response:
                while chunk := response.read(CHUNK):
                    digest.update(chunk)
        except (HTTPError, URLError) as exc:
            print(f"::error::{filename} could not be downloaded from {base}: {exc}")
            failures += 1
            continue

        actual = digest.hexdigest()
        if actual == expected:
            print("    ok")
        else:
            print(
                f"::error::{filename} checksum mismatch: pinned {expected}, got {actual}"
            )
            failures += 1

    if failures:
        print(
            f"\n{failures} pinned archive(s) no longer match. If the release was "
            "intentionally re-cut, refresh the pins with:\n"
            f"    python scripts/update_plastimatch_urls.py --repo {repo} --tag {tag}"
        )
        return 1

    print("\nall pins verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
