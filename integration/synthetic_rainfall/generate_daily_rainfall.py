#!/usr/bin/env python3
"""Create an IWMI-constrained synthetic daily rainfall series.

The IWMI input is monthly rainfall, so the generated daily values are
synthetic and must not be described as IWMI daily observations.
"""

from __future__ import annotations

import argparse
import csv
import calendar
import random
from collections import defaultdict
from datetime import date
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--monthly-csv", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--season-start", type=date.fromisoformat, required=True)
    parser.add_argument("--season-end", type=date.fromisoformat, required=True)
    parser.add_argument("--wet-day-fraction", type=float, default=0.25)
    parser.add_argument("--seed", type=int, default=2025)
    return parser.parse_args()


def load_monthly(path: Path) -> dict[int, list[float]]:
    values: dict[int, list[float]] = defaultdict(list)
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            year, month = (int(part) for part in row["month"].split("-", 1))
            value = float(row["rainfall_mm"])
            if value < 0:
                raise ValueError(f"Rainfall cannot be negative: {row}")
            values[month].append(value)
    if set(values) != set(range(1, 13)):
        raise ValueError("Monthly input must contain all calendar months")
    return values


def daterange(start: date, end: date):
    current = start
    while current <= end:
        yield current
        current = date.fromordinal(current.toordinal() + 1)


def main() -> None:
    args = parse_args()
    if args.season_end < args.season_start:
        raise ValueError("season-end must not precede season-start")
    if not 0 < args.wet_day_fraction <= 1:
        raise ValueError("wet-day-fraction must be greater than 0 and at most 1")

    monthly = load_monthly(args.monthly_csv)
    climatology = {
        month: sum(values) / len(values) for month, values in monthly.items()
    }
    rng = random.Random(args.seed)
    rows = []
    for day in daterange(args.season_start, args.season_end):
        month_total = climatology[day.month]
        days_in_month = calendar.monthrange(day.year, day.month)[1]
        wet_days = max(1, round(days_in_month * args.wet_day_fraction))
        day_index = day.day - 1
        # Use a deterministic monthly event pattern and scale it to the IWMI
        # climatological total. This preserves the monthly constraint.
        event_days = sorted(rng.sample(range(days_in_month), wet_days))
        weights = [rng.gammavariate(1.5, 1.0) for _ in event_days]
        total_weight = sum(weights)
        rainfall = (
            month_total * weights[event_days.index(day_index)] / total_weight
            if day_index in event_days
            else 0.0
        )
        rows.append({"date": day.isoformat(), "rain_mm": round(rainfall, 6)})

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["date", "rain_mm"])
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
