#!/usr/bin/env python3
"""
Build a single HTML report for one task attempt.

Usage: python ./report.py results/<run_dir>
Writes results/<run_dir>/report.html
"""

import json
import sys
import html
from pathlib import Path


def read(path):
    return path.read_text(errors="replace") if path.exists() else ""


def load_events(transcript):
    """Return assistant/user/result events, deduplicated by uuid."""
    seen = set()
    events = []
    for line in transcript.splitlines():
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("type") not in ("assistant", "user", "result"):
            continue
        key = ev.get("uuid") or line
        if key in seen:
            continue
        seen.add(key)
        events.append(ev)
    return events


def tool_result_text(content):
    if isinstance(content, list):
        return "".join(
            c.get("text", "") for c in content if isinstance(c, dict))
    return str(content)


def parse_pidstat(text):
    """Return (peak_rss_mb, peak_cpu_percent, samples) summed per timestamp."""
    cols = None
    per_time = {}
    for line in text.splitlines():
        if line.startswith("#"):
            cols = line[1:].split()
            continue
        if not cols or not line.strip():
            continue
        parts = line.split()
        if len(parts) < len(cols):
            continue
        row = dict(zip(cols, parts))
        t = row.get("Time")
        try:
            rss = float(row.get("RSS", 0)) / 1024
            cpu = float(row.get("%CPU", 0))
        except ValueError:
            continue
        acc = per_time.setdefault(t, [0.0, 0.0])
        acc[0] += rss
        acc[1] += cpu
    if not per_time:
        return 0, 0, 0
    peak_rss = max(v[0] for v in per_time.values())
    peak_cpu = max(v[1] for v in per_time.values())
    return round(peak_rss), round(peak_cpu), len(per_time)


def parse_top(text):
    """Return (peak_rss_mb, peak_cpu_percent, samples) from top -b output, summed per snapshot."""
    units = {"k": 1 / 1024, "m": 1, "g": 1024, "t": 1024 * 1024}
    snapshots = []
    cols = None
    for line in text.splitlines():
        if line.startswith("top - "):
            snapshots.append([0.0, 0.0])
            cols = None
            continue
        if not snapshots:
            continue
        parts = line.split()
        if cols is None:
            if "PID" in parts and "RES" in parts:
                cols = parts
            continue
        if len(parts) < len(cols):
            continue
        row = dict(zip(cols, parts))
        res = row.get("RES", "0")
        try:
            if res[-1].lower() in units:
                rss = float(res[:-1]) * units[res[-1].lower()]
            else:
                rss = float(res) / 1024
            cpu = float(row.get("%CPU", 0))
        except ValueError:
            continue
        snapshots[-1][0] += rss
        snapshots[-1][1] += cpu
    if not snapshots:
        return 0, 0, 0
    peak_rss = max(s[0] for s in snapshots)
    peak_cpu = max(s[1] for s in snapshots)
    return round(peak_rss), round(peak_cpu), len(snapshots)


def resource_peaks(out):
    """Use pidstat.log if present, otherwise top.log."""
    if (out / "pidstat.log").exists():
        return parse_pidstat(read(out / "pidstat.log"))
    return parse_top(read(out / "top.log"))


def list_files(root):
    if not root.exists():
        return []
    return sorted(
        str(p.relative_to(root)) for p in root.rglob("*") if p.is_file())


def main():
    if len(sys.argv) != 2:
        print("usage: report.py results/<run_dir>")
        sys.exit(1)

    run_dir = Path(sys.argv[1])
    out = run_dir / "out"

    events = load_events(read(out / "transcript.jsonl"))
    result = next((e for e in events if e["type"] == "result"), {})
    usage = result.get("usage", {})

    peak_rss, peak_cpu, samples = resource_peaks(out)

    h = []
    esc = html.escape
    h.append("<!doctype html><meta charset='utf-8'>")
    h.append(f"<title>{esc(run_dir.name)}</title>")
    h.append(
        "<style>body{font-family:sans-serif;max-width:1100px;margin:2em auto;padding:0 1em}"
        "pre{background:#f4f4f4;padding:.6em;overflow-x:auto;white-space:pre-wrap}"
        ".cmd{background:#e8f0fe}.think{background:#fff8e1}.text{background:#e8f5e9}"
        "table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:.3em .6em;text-align:left}"
        "</style>")
    h.append(f"<h1>{esc(run_dir.name)}</h1>")
    status = read(run_dir / "status.txt").strip() or "UNKNOWN"
    color = {"PASS": "#c8e6c9", "FAIL": "#ffcdd2", "MISSING": "#ffe0b2"}.get(status, "#eeeeee")
    h.append(f"<h2 style='background:{color};padding:.4em'>Solution check: {esc(status)}</h2>")
    h.append("<pre>" + esc(read(run_dir / "solution.diff")) + "</pre>")

    # summary
    h.append("<h2>Summary</h2><table>")
    rows = [
        ("prompt", read(run_dir / "prompt.md").strip()),
        ("exit_code", read(out / "exit_code").strip()),
        ("num_turns", result.get("num_turns")),
        ("duration_s", round(result.get("duration_ms", 0) / 1000, 1)),
        ("api_s", round(result.get("duration_api_ms", 0) / 1000, 1)),
        ("output_tokens", usage.get("output_tokens")),
        ("is_error", result.get("is_error")),
        ("peak_rss_mb_sum", peak_rss),
        ("peak_cpu_percent_sum", peak_cpu),
        ("pidstat_samples", samples),
        ("final_result", result.get("result", "")),
        ("subtype", result.get("subtype")),
    ]
    for k, v in rows:
        h.append(
            f"<tr><th>{esc(k)}</th><td><pre>{esc(str(v))}</pre></td></tr>")
    h.append("</table>")
    h.append("<h3>meta.txt</h3><pre>" + esc(read(out / "meta.txt")) + "</pre>")
    h.append("<h3>time.txt</h3><pre>" + esc(read(out / "time.txt")) + "</pre>")

    # trace
    h.append("<h2>Trace</h2>")
    for ev in events:
        if ev["type"] == "result":
            continue
        for block in ev.get("message", {}).get("content", []) or []:
            if not isinstance(block, dict):
                continue
            kind = block.get("type")
            if kind == "thinking":
                h.append("<pre class='think'>THINKING\n" +
                         esc(block.get("thinking", "")) + "</pre>")
            elif kind == "text":
                h.append("<pre class='text'>ASSISTANT\n" +
                         esc(block.get("text", "")) + "</pre>")
            elif kind == "tool_use":
                inp = block.get("input", {})
                body = inp.get("command") or inp.get(
                    "file_path") or json.dumps(inp, indent=1)
                desc = inp.get("description", "")
                h.append(
                    f"<pre class='cmd'>TOOL {esc(block.get('name', ''))}  {esc(desc)}\n{esc(str(body))}</pre>"
                )
            elif kind == "tool_result":
                h.append("<pre>RESULT\n" +
                         esc(tool_result_text(block.get("content", ""))) +
                         "</pre>")

    # cluster side
    h.append("<h2>Slurm jobs (sacct)</h2><pre>" +
             esc(read(out / "sacct.txt")) + "</pre>")
    h.append("<h2>stderr</h2><pre>" + esc(read(out / "stderr.txt")) + "</pre>")

    # leftovers
    h.append("<h2>Disk usage</h2><pre>" + esc(read(out / "du.txt")) + "</pre>")
    h.append("<h2>All files after run (type size mtime path)</h2><pre>" + esc(read(out / "files.txt")) + "</pre>")
    h.append("<h2>Files pulled to home_after</h2><pre>" + esc("\n".join(list_files(run_dir / "home_after"))) + "</pre>")

    (run_dir / "report.html").write_text("\n".join(h))
    print(run_dir / "report.html")


if __name__ == "__main__":
    main()
