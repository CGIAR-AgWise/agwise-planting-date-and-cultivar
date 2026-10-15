#!/usr/bin/env python3
"""Replace an AgWise daily PRCP/RAIN column with synthetic IWMI rainfall."""

from __future__ import annotations

import argparse
import csv
from datetime import date
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--agwise-csv", type=Path, required=True)
    parser.add_argument("--rainfall-csv", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    with args.rainfall_csv.open(newline="", encoding="utf-8") as handle:
        rainfall = {
            row["date"]: row["rain_mm"] for row in csv.DictReader(handle)
        }
    if not rainfall:
        raise ValueError("Synthetic rainfall input is empty")

    with args.agwise_csv.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        rain_column = next(
            (name for name in ("PRCP", "RAIN", "rain") if name in fieldnames),
            None,
        )
        if rain_column is None:
            raise ValueError("AgWise CSV must contain PRCP or RAIN")
        date_column = next(
            (name for name in ("DATE", "date") if name in fieldnames), None
        )
        if date_column is None:
            raise ValueError("AgWise CSV must contain DATE or date")

        rows = []
        for row in reader:
            day = date.fromisoformat(row[date_column][:10]).isoformat()
            if day not in rainfall:
                raise ValueError(f"Missing synthetic rainfall for {day}")
            row[rain_column] = rainfall[day]
            rows.append(row)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
