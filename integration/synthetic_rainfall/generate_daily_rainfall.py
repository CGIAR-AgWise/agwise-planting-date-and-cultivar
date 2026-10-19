#!/usr/bin/env python3
"""Create an IWMI-constrained synthetic daily rainfall series.

The IWMI input is monthly rainfall, so the generated daily values are
synthetic and must not be described as IWMI daily observations.
"""

from __future__ import annotations

import argparse
import csv
import calendar
import json
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
    parser.add_argument(
        "--monthly-mode",
        choices=("target-year", "climatology", "target-year-fallback"),
        default="target-year-fallback",
        help="Use target-year totals, climatology, or target-year with climatology fallback",
    )
    parser.add_argument("--wet-day-fraction", type=float, default=0.25)
    parser.add_argument("--seed", type=int, default=2025)
    return parser.parse_args()


def load_monthly(path: Path) -> tuple[dict[tuple[int, int], float], dict[int, list[float]]]:
    by_year_month: dict[tuple[int, int], float] = {}
    by_month: dict[int, list[float]] = defaultdict(list)
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            year, month = (int(part) for part in row["month"].split("-", 1))
            value = float(row["rainfall_mm"])
            if value < 0:
                raise ValueError(f"Rainfall cannot be negative: {row}")
            key = (year, month)
            if key in by_year_month:
                raise ValueError(f"Monthly input contains duplicate month: {row['month']}")
            by_year_month[key] = value
            by_month[month].append(value)
    if set(by_month) != set(range(1, 13)):
        raise ValueError("Monthly input must contain at least one value for all calendar months")
    return by_year_month, by_month


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

    by_year_month, by_month = load_monthly(args.monthly_csv)
    climatology = {
        month: sum(values) / len(values) for month, values in by_month.items()
    }
    rng = random.Random(args.seed)
    rows = []
    synthetic_months: dict[tuple[int, int], dict[int, float]] = {}
    selected_month_totals: dict[str, float] = {}
    climatology_fallback_months: list[str] = []
    for day in daterange(args.season_start, args.season_end):
        month_key = (day.year, day.month)
        if month_key not in synthetic_months:
            exact_total = by_year_month.get(month_key)
            if args.monthly_mode == "target-year" and exact_total is None:
                raise ValueError(
                    f"Missing target-year monthly rainfall for {day.year:04d}-{day.month:02d}"
                )
            if args.monthly_mode == "climatology" or exact_total is None:
                month_total = climatology[day.month]
                if args.monthly_mode == "target-year-fallback" and exact_total is None:
                    climatology_fallback_months.append(f"{day.year:04d}-{day.month:02d}")
            else:
                month_total = exact_total
            selected_month_totals[f"{day.year:04d}-{day.month:02d}"] = month_total
            days_in_month = calendar.monthrange(day.year, day.month)[1]
            wet_days = max(1, round(days_in_month * args.wet_day_fraction))
            event_days = sorted(rng.sample(range(days_in_month), wet_days))
            weights = [rng.gammavariate(1.5, 1.0) for _ in event_days]
            total_weight = sum(weights)
            synthetic_months[month_key] = {
                day_index: month_total * weight / total_weight
                for day_index, weight in zip(event_days, weights)
            }

        day_index = day.day - 1
        rainfall = synthetic_months[month_key].get(day_index, 0.0)
        rows.append({"date": day.isoformat(), "rain_mm": round(rainfall, 6)})

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["date", "rain_mm"])
        writer.writeheader()
        writer.writerows(rows)
    metadata = {
        "source_monthly_csv": str(args.monthly_csv),
        "season_start": args.season_start.isoformat(),
        "season_end": args.season_end.isoformat(),
        "monthly_mode": args.monthly_mode,
        "wet_day_fraction": args.wet_day_fraction,
        "gamma_shape": 1.5,
        "gamma_scale": 1.0,
        "random_seed": args.seed,
        "selected_month_totals_mm": selected_month_totals,
        "climatology_fallback_months": climatology_fallback_months,
        "daily_values_are_synthetic": True,
        "daily_observations_recovered": False,
    }
    metadata_path = Path(f"{args.output}.metadata.json")
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
