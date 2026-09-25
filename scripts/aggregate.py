#!/usr/bin/env python3
"""
Aggregate every run directory under results/ into results/summary.csv.

Usage: python ./aggregate.py [results_dir]
"""

import csv
import sys
sys.dont_write_bytecode = True
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from report import read, load_events, resource_peaks

COLUMNS = [
    "task", "label", "timestamp", "status", "exit_code", "subtype", "is_error",
    "num_turns", "output_tokens", "duration_s", "api_s",
    "wall_s", "user_cpu_s", "sys_cpu_s", "peak_rss_mb", "peak_cpu_pct",
    "jobs_submitted", "claude_version", "host", "run_dir",
]


def parse_time_txt(text):
    values = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2:
            values[parts[0]] = parts[1]
    return values


def parse_meta(text):
    values = {}
    for line in text.splitlines():
        if ": " in line:
            key, value = line.split(": ", 1)
            values[key] = value
    return values


def count_jobs(sacct_text):
    lines = [l for l in sacct_text.splitlines() if l and not l.startswith("JobID")]
    return len([l for l in lines if "." not in l.split("|")[0]])


def summarize(run_dir):
    out = run_dir / "out"
    name_parts = run_dir.name.rsplit("_", 2)
    if len(name_parts) != 3:
        return None
    task, label, timestamp = name_parts

    events = load_events(read(out / "transcript.jsonl"))
    result = next((e for e in events if e["type"] == "result"), {})
    usage = result.get("usage", {})
    timing = parse_time_txt(read(out / "time.txt"))
    meta = parse_meta(read(out / "meta.txt"))
    peak_rss, peak_cpu, _ = resource_peaks(out)

    duration_s = result.get("duration_ms", 0) / 1000
    api_s = result.get("duration_api_ms", 0) / 1000

    return {
        "task": task,
        "label": label,
        "timestamp": timestamp,
        "status": read(run_dir / "status.txt").strip(),
        "exit_code": read(out / "exit_code").strip(),
        "subtype": result.get("subtype", ""),
        "is_error": result.get("is_error", ""),
        "num_turns": result.get("num_turns", ""),
        "output_tokens": usage.get("output_tokens", ""),
        "duration_s": round(duration_s, 1),
        "api_s": round(api_s, 1),
        "wall_s": timing.get("wall_seconds", ""),
        "user_cpu_s": timing.get("user_cpu_seconds", ""),
        "sys_cpu_s": timing.get("sys_cpu_seconds", ""),
        "peak_rss_mb": peak_rss,
        "peak_cpu_pct": peak_cpu,
        "jobs_submitted": count_jobs(read(out / "sacct.txt")),
        "claude_version": meta.get("claude_version", ""),
        "host": meta.get("host", ""),
        "run_dir": run_dir.name,
    }


def main():
    results = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("results")
    rows = []
    for run_dir in sorted(results.iterdir()):
        if run_dir.is_dir() and (run_dir / "out").exists():
            row = summarize(run_dir)
            if row:
                rows.append(row)

    out_path = results / "summary.csv"
    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"{len(rows)} runs written to {out_path}")


if __name__ == "__main__":
    main()
