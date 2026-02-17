#!/usr/bin/env python3
"""
Run repeated quality cycles (tests + compile checks) and emit a report.
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime


ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
REPORT_DIR = os.path.join(ROOT_DIR, "output", "quality_cycles")


def run_command(cmd, cwd):
    start = time.time()
    completed = subprocess.run(
        cmd,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    duration = round(time.time() - start, 3)
    return {
        "cmd": cmd,
        "returncode": completed.returncode,
        "duration_sec": duration,
        "output": completed.stdout,
    }


def build_cycle_commands():
    python = sys.executable
    return [
        [python, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
        [python, "-m", "compileall", "pages", "src", "tests", "main.py"],
    ]


def parse_args():
    parser = argparse.ArgumentParser(description="Run repeated quality validation cycles.")
    parser.add_argument("--cycles", type=int, default=40, help="Number of cycles to run.")
    parser.add_argument(
        "--xlsx-path",
        type=str,
        default="",
        help="Optional path to run backtest_generation_quality.py once after cycles.",
    )
    parser.add_argument(
        "--backtest-limit",
        type=int,
        default=8,
        help="Limit passed to backtest script when --xlsx-path is provided.",
    )
    return parser.parse_args()


def write_reports(report):
    os.makedirs(REPORT_DIR, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    json_path = os.path.join(REPORT_DIR, f"quality_cycles_{stamp}.json")
    md_path = os.path.join(REPORT_DIR, f"quality_cycles_{stamp}.md")

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)

    lines = [
        "# Quality Cycle Report",
        "",
        f"- Generated at: {report['generated_at']}",
        f"- Requested cycles: {report['requested_cycles']}",
        f"- Completed cycles: {report['completed_cycles']}",
        f"- Passed: {report['passed']}",
        "",
        "## Cycle Results",
    ]

    for cycle in report["cycles"]:
        status = "PASS" if cycle["passed"] else "FAIL"
        lines.append(f"- Cycle {cycle['cycle']}: {status} ({cycle['duration_sec']}s)")
        for step in cycle["steps"]:
            lines.append(
                f"  - `{ ' '.join(step['cmd']) }` -> rc={step['returncode']} ({step['duration_sec']}s)"
            )
            if step["returncode"] != 0:
                output_lines = (step.get("output") or "").strip().splitlines()
                preview = "\n".join(output_lines[-20:])
                if preview:
                    lines.append("```text")
                    lines.append(preview)
                    lines.append("```")

    if report.get("post_backtest"):
        backtest = report["post_backtest"]
        lines.append("")
        lines.append("## Post-Loop Backtest")
        lines.append(
            f"- `{ ' '.join(backtest['cmd']) }` -> rc={backtest['returncode']} ({backtest['duration_sec']}s)"
        )
        if backtest["output"]:
            lines.append("```text")
            lines.extend(backtest["output"].strip().splitlines()[-20:])
            lines.append("```")

    with open(md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    return json_path, md_path


def main():
    args = parse_args()
    cycles = max(1, int(args.cycles))
    commands = build_cycle_commands()

    report = {
        "generated_at": datetime.now().isoformat(),
        "requested_cycles": cycles,
        "completed_cycles": 0,
        "passed": False,
        "cycles": [],
    }

    for cycle_index in range(1, cycles + 1):
        cycle_start = time.time()
        cycle_steps = []
        cycle_passed = True

        for command in commands:
            result = run_command(command, cwd=ROOT_DIR)
            cycle_steps.append(result)
            if result["returncode"] != 0:
                cycle_passed = False
                break

        report["cycles"].append(
            {
                "cycle": cycle_index,
                "passed": cycle_passed,
                "duration_sec": round(time.time() - cycle_start, 3),
                "steps": cycle_steps,
            }
        )
        report["completed_cycles"] = cycle_index

        if not cycle_passed:
            report["passed"] = False
            break
    else:
        report["passed"] = True

    if args.xlsx_path:
        backtest_cmd = [
            sys.executable,
            "scripts/backtest_generation_quality.py",
            "--xlsx-path",
            args.xlsx_path,
            "--limit",
            str(max(0, int(args.backtest_limit))),
        ]
        report["post_backtest"] = run_command(backtest_cmd, cwd=ROOT_DIR)

    json_path, md_path = write_reports(report)
    print(
        f"Quality cycles complete. Requested={report['requested_cycles']} "
        f"Completed={report['completed_cycles']} Passed={report['passed']}"
    )
    print(f"JSON report: {json_path}")
    print(f"Markdown report: {md_path}")

    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
