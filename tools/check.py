#!/usr/bin/env python3
"""Checks on the code and project that tests can't easily make.

REQ-SAFE-01: no networking code in the app or the core.
REQ-PRIV-01: the camera is the only permission asked for, and the privacy
             manifest declares no tracking and no collected data.

Usage: tools/check.py   (exit 1 on any failure)
"""
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Sources", ROOT / "Core" / "Sources"]

# APIs that open a connection or load web content.
NETWORK = re.compile(
    r"\b(URLSession|URLRequest|NWConnection|NWListener|NWPathMonitor|WKWebView|SFSafariViewController"
    r"|URLSessionWebSocketTask|CFStream|Socket|import\s+Network\b|import\s+WebKit\b)")
PERMISSION = re.compile(r"(NS\w+UsageDescription)")


def main():
    failures = []

    for base in SOURCES:
        for f in sorted(base.rglob("*.swift")):
            for n, line in enumerate(f.read_text().splitlines(), 1):
                code = line.split("//", 1)[0]
                if NETWORK.search(code):
                    failures.append(f"REQ-SAFE-01: networking API in {f.relative_to(ROOT)}:{n}: {line.strip()}")

    project = (ROOT / "project.yml").read_text()
    asked = sorted(set(PERMISSION.findall(project)))
    if asked != ["NSCameraUsageDescription"]:
        failures.append(f"REQ-PRIV-01: permissions requested {asked}, expected only the camera")

    manifest = plistlib.loads((ROOT / "Resources" / "PrivacyInfo.xcprivacy").read_bytes())
    if manifest.get("NSPrivacyTracking") is not False:
        failures.append("REQ-PRIV-01: privacy manifest does not declare NSPrivacyTracking false")
    if manifest.get("NSPrivacyCollectedDataTypes"):
        failures.append("REQ-PRIV-01: privacy manifest declares collected data")
    if manifest.get("NSPrivacyTrackingDomains"):
        failures.append("REQ-PRIV-01: privacy manifest lists tracking domains")

    for f in failures:
        print("check:", f)
    print(f"check: {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
