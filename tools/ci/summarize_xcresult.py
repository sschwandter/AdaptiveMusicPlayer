#!/usr/bin/env python3
import json
import subprocess
import sys


def main() -> int:
    bundle_path = sys.argv[1]

    try:
        raw = subprocess.check_output(
            [
                "xcrun",
                "xcresulttool",
                "get",
                "--legacy",
                "--path",
                bundle_path,
                "--format",
                "json",
            ],
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        print("## Test Results")
        print("")
        print(f"Could not read `{bundle_path}`: exit code {exc.returncode}")
        return 0

    data = json.loads(raw)
    metrics = data.get("metrics", {})
    total = metrics.get("testsCount", {}).get("_value", "0")
    failed = metrics.get("testsFailedCount", {}).get("_value", "0")

    print("## Test Results")
    print("")
    print(f"- Total tests: {total}")
    print(f"- Failed tests: {failed}")
    print("")

    actions = data.get("actions", {}).get("_values", [])
    failure_summaries = []
    for action in actions:
        issues = action.get("actionResult", {}).get("issues", {})
        failure_summaries.extend(
            issues.get("testFailureSummaries", {}).get("_values", [])
        )

    if not failure_summaries:
        print("All tests passed.")
        return 0

    print("### Failures")
    print("")
    for failure in failure_summaries:
        test_name = failure.get("testCaseName", {}).get("_value", "Unknown test")
        message = failure.get("message", {}).get("_value", "No message")
        print(f"- `{test_name}`")
        print(f"  {message}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
