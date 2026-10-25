#!/usr/bin/env python3
"""Summarize one test-walk log.

The reflex layer's thresholds should be argued from these numbers rather than
from impressions of what the app did. The two that matter most:

  * the noise floor of `drop` on level floor: how big a false drop normal gait
    manufactures. It has to stay far below stepDownDrop or warnings are random.
  * the margin between that noise and a real step, which is what a threshold is
    choosing between.

Usage: tools/analyze-log.py logs/session-....jsonl
"""
import json
import sys
from collections import Counter


def pct(sorted_vals, q):
    if not sorted_vals:
        return float("nan")
    return sorted_vals[min(len(sorted_vals) - 1, int(len(sorted_vals) * q))]


def main(path):
    rows = [json.loads(line) for line in open(path) if line.strip()]
    if not rows:
        print(f"{path}: empty")
        return
    t0 = rows[0]["t"]
    readings = [r for r in rows if r["kind"] == "reading"]
    events = [r for r in rows if r["kind"] == "event"]
    marks = [r for r in rows if r["kind"] == "mark"]

    print(f"\n=== {path.split('/')[-1]} ===")
    print(f"{rows[-1]['t'] - t0:.0f}s, {len(readings)} readings, "
          f"{len(events)} event-frames, {len(marks)} marks")

    # Events fire every frame the condition holds; group them into what he heard.
    episodes = []
    for e in events:
        if episodes and episodes[-1]["name"] == e["event"] and e["t"] - episodes[-1]["end"] < 1.0:
            episodes[-1]["end"] = e["t"]
        else:
            episodes.append({"name": e["event"], "start": e["t"], "end": e["t"]})

    print("\nwhat he actually heard:")
    for e in episodes:
        print(f"  {e['start'] - t0:6.1f}s  ({e['end'] - e['start']:4.2f}s)  {e['name']}")
    if marks:
        print("\nMARKED WRONG by the tester:")
        for m in marks:
            print(f"  {m['t'] - t0:6.1f}s  {json.dumps(m.get('reading', {}), sort_keys=True)}")

    # The number that decides whether the thresholds are sane.
    level = sorted(abs(r["drop"]) for r in readings
                   if "drop" in r and abs(r["drop"]) < 0.05)
    steps = sorted(abs(r["drop"]) for r in readings
                   if "drop" in r and abs(r["drop"]) >= 0.05)
    if level:
        print(f"\nnoise floor of |drop| on level ground  "
              f"p50={pct(level, .5):.3f}  p90={pct(level, .9):.3f}  max={max(level):.3f} m")
    if steps:
        print(f"real level changes                     "
              f"p50={pct(steps, .5):.3f}  max={max(steps):.3f} m  ({len(steps)} frames)")
    if level and steps:
        print(f"  -> margin between noise and signal: {min(steps) / max(max(level), 1e-6):.0f}x")

    for key in ("pitch", "swing", "speed"):
        vals = sorted(r[key] for r in readings if key in r)
        if vals:
            print(f"  {key:6s} p50={pct(vals, .5):6.1f}  p90={pct(vals, .9):6.1f}  max={vals[-1]:6.1f}")

    empty = sum(1 for r in readings if r.get("near", 1) == 0)
    if empty:
        print(f"  frames with no reference slice: {empty}/{len(readings)} (aim too high?)")

    kinds = Counter(e["event"].split(":")[0] for e in events)
    if kinds:
        print("  event frames:", dict(kinds))


if __name__ == "__main__":
    for p in sys.argv[1:] or ["logs/s1.jsonl"]:
        main(p)
