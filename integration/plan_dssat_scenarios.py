#!/usr/bin/env python3
"""Create an IWMI-informed, pre-DSSAT water-management scenario plan."""

import argparse
import json
from datetime import date
from pathlib import Path

from iwmi_dssat_scenarios import plan_water_management


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iwmi-payload", required=True)
    parser.add_argument("--season-start", required=True)
    parser.add_argument("--season-end", required=True)
    parser.add_argument(
        "--water-access",
        choices=("unknown", "none", "supplemental", "reliable"),
        default="unknown",
    )
    parser.add_argument(
        "--policy",
        default="integration/scenarios/water_management_v1.json",
    )
    parser.add_argument("--output")
    args = parser.parse_args()
    date.fromisoformat(args.season_start)
    date.fromisoformat(args.season_end)
    with open(args.iwmi_payload, encoding="utf-8") as handle:
        payload = json.load(handle)
    with open(args.policy, encoding="utf-8") as handle:
        policy = json.load(handle)
    plan = plan_water_management(
        payload.get("iwmi", payload),
        args.season_start,
        args.season_end,
        args.water_access,
        policy,
    )
    rendered = json.dumps(plan, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
    print(rendered, end="")


if __name__ == "__main__":
    main()
