import csv
import json
from datetime import date
from pathlib import Path

import pytest

from generate_daily_rainfall import main


def test_generation_matches_existing_usecase(monkeypatch, tmp_path):
    source = tmp_path / "monthly.csv"
    source.write_text(
        "month,rainfall_mm\n"
        + "\n".join(f"2020-{month:02d},10" for month in range(1, 13))
        + "\n",
        encoding="utf-8",
    )
    output = tmp_path / "daily.csv"
    monkeypatch.setattr(
        "sys.argv",
        [
            "generate_daily_rainfall.py",
            "--monthly-csv",
            str(source),
            "--season-start",
            "2025-11-01",
            "--season-end",
            "2026-02-28",
            "--output",
            str(output),
            "--seed",
            "1",
        ],
    )
    main()

    with output.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))

    assert len(rows) == (date(2026, 2, 28) - date(2025, 11, 1)).days + 1
    assert rows[0]["date"] == "2025-11-01"
    assert rows[-1]["date"] == "2026-02-28"
    for month in ("2025-11", "2025-12", "2026-01", "2026-02"):
        total = sum(
            float(row["rain_mm"]) for row in rows if row["date"].startswith(month)
        )
        assert abs(total - 10) < 0.00001

    metadata = json.loads(
        (tmp_path / "daily.csv.metadata.json").read_text(encoding="utf-8")
    )
    assert metadata["monthly_mode"] == "target-year-fallback"
    assert metadata["climatology_fallback_months"] == [
        "2025-11",
        "2025-12",
        "2026-01",
        "2026-02",
    ]
    assert metadata["daily_values_are_synthetic"] is True


def test_target_year_totals_are_used_when_available(monkeypatch, tmp_path):
    source = tmp_path / "monthly.csv"
    source.write_text(
        "month,rainfall_mm\n"
        + "\n".join(
            [
                *(f"2025-{month:02d},10" for month in range(1, 13)),
                *(f"2026-{month:02d},20" for month in range(1, 13)),
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    output = tmp_path / "daily.csv"
    monkeypatch.setattr(
        "sys.argv",
        [
            "generate_daily_rainfall.py",
            "--monthly-csv",
            str(source),
            "--season-start",
            "2025-11-01",
            "--season-end",
            "2026-02-28",
            "--monthly-mode",
            "target-year",
            "--output",
            str(output),
        ],
    )
    main()

    with output.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    for month, expected in (("2025-11", 10), ("2025-12", 10), ("2026-01", 20), ("2026-02", 20)):
        total = sum(
            float(row["rain_mm"]) for row in rows if row["date"].startswith(month)
        )
        assert abs(total - expected) < 0.00001


def test_target_year_mode_fails_for_missing_month(monkeypatch, tmp_path):
    source = tmp_path / "monthly.csv"
    source.write_text(
        "month,rainfall_mm\n"
        + "\n".join(f"2025-{month:02d},10" for month in range(1, 13))
        + "\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(
        "sys.argv",
        [
            "generate_daily_rainfall.py",
            "--monthly-csv",
            str(source),
            "--season-start",
            "2025-11-01",
            "--season-end",
            "2026-02-28",
            "--monthly-mode",
            "target-year",
            "--output",
            str(tmp_path / "daily.csv"),
        ],
    )
    with pytest.raises(ValueError, match="Missing target-year monthly rainfall"):
        main()
