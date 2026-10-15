import csv
from datetime import date
from pathlib import Path

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
