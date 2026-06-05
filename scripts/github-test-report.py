#!/usr/bin/env python3
"""Generate GitHub Actions Markdown and JUnit reports from an xcresult bundle."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def run_json(command: list[str]) -> dict:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def first_statistic(summary: dict, title: str) -> str:
    for statistic in summary.get("statistics", []):
        if statistic.get("title") == title:
            return statistic.get("subtitle", "")
    return ""


def write_markdown(summary: dict, output_path: Path) -> None:
    total = summary.get("totalTestCount", 0)
    passed = summary.get("passedTests", 0)
    failed = summary.get("failedTests", 0)
    skipped = summary.get("skippedTests", 0)
    expected = summary.get("expectedFailures", 0)
    result = summary.get("result", "unknown")
    duration = first_statistic(summary, "Duration")
    environment = summary.get("environmentDescription", "")
    failures = summary.get("testFailures", [])

    lines = [
        "## GPGManager Test Report",
        "",
        f"**Result:** {result}",
        "",
        "| Total | Passed | Failed | Skipped | Expected failures | Duration |",
        "|---:|---:|---:|---:|---:|---:|",
        f"| {total} | {passed} | {failed} | {skipped} | {expected} | {duration or 'n/a'} |",
    ]

    if environment:
        lines.extend(["", f"**Environment:** {environment}"])

    if failures:
        lines.extend(["", "### Failures", ""])
        for failure in failures:
            name = failure.get("testName", "Unknown test")
            target = failure.get("targetName", "Unknown target")
            text = failure.get("failureText", "").strip()
            lines.append(f"- `{target}` / `{name}`")
            if text:
                lines.append(f"  `{text}`")
    else:
        lines.extend(["", "No test failures reported."])

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def flatten_test_cases(node: dict, inherited_classname: str = "") -> list[dict]:
    node_type = node.get("nodeType", "")
    name = node.get("name", "Unknown")
    classname = inherited_classname
    if node_type in {"Unit test bundle", "UI test bundle", "Test Suite"}:
        classname = name
    if node_type == "Test Case":
        case = dict(node)
        case["classname"] = classname or "GPGManager"
        return [case]

    cases = []
    for child in node.get("children", []):
        cases.extend(flatten_test_cases(child, classname))
    return cases


def write_junit(summary: dict, tests: dict, output_path: Path) -> None:
    cases = []
    for node in tests.get("testNodes", []):
        cases.extend(flatten_test_cases(node))

    failures = summary.get("testFailures", [])
    failure_by_name = {
        failure.get("testName", ""): failure.get("failureText", "")
        for failure in failures
    }
    skipped = sum(1 for case in cases if case.get("result") == "Skipped")
    duration = sum(float(case.get("durationInSeconds", 0) or 0) for case in cases)

    suite = ET.Element(
        "testsuite",
        {
            "name": "GPGManager",
            "tests": str(len(cases)),
            "failures": str(len(failures)),
            "skipped": str(skipped),
            "time": f"{duration:.3f}",
        },
    )

    for case_data in cases:
        case = ET.SubElement(
            suite,
            "testcase",
            {
                "classname": case_data.get("classname", "GPGManager"),
                "name": case_data.get("name", "UnknownTest"),
                "time": f"{float(case_data.get('durationInSeconds', 0) or 0):.3f}",
            },
        )
        if case_data.get("result") == "Skipped":
            ET.SubElement(case, "skipped")
        failure_text = failure_by_name.get(case_data.get("name", ""))
        if failure_text:
            node = ET.SubElement(case, "failure", {"message": failure_text})
            node.text = failure_text

    tree = ET.ElementTree(suite)
    ET.indent(tree, space="  ")
    tree.write(output_path, encoding="utf-8", xml_declaration=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xcresult", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    summary = run_json(
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "summary",
            "--path",
            str(args.xcresult),
        ]
    )
    tests = run_json(
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "tests",
            "--path",
            str(args.xcresult),
        ]
    )

    (args.out_dir / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (args.out_dir / "tests.json").write_text(
        json.dumps(tests, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    write_markdown(summary, args.out_dir / "summary.md")
    write_junit(summary, tests, args.out_dir / "junit.xml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
