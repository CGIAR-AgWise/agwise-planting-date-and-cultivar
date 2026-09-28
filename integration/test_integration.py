# integration/test_integration.py
from datetime import date

from iwmi_adapter import overlaps
from run_advisory import load_recommendations, parse_date


def test_parse_date_iso_datetime():
    assert parse_date("2025-11-09T00:00:00Z") == date(2025, 11, 9)
    assert parse_date("2025-11-09") == date(2025, 11, 9)


def test_parse_date_day_of_year():
    assert parse_date("2025313") == date(2025, 11, 9)
    assert parse_date("25313") == date(2025, 11, 9)


def test_overlap_boundary_day():
    assert overlaps(
        "2026-02-28T00:00:00Z", "2026-03-31T00:00:00Z", "2025-11-01", "2026-02-28"
    )


ROW = """Cultivar,PDAT,n_simulations,maturity_failure_rate_pct,HWAH_mean,HWAH_median,HWAH_sd,HWAH_cv_pct,HWAH_p10,HWAH_p90
Short,2025-11-09T00:00:00Z,62,0,2471.41,2598.5,313.3,12.68,2062.1,2781.5
"""


def test_load_recommendations_aggregated(tmp_path):
    path = tmp_path / "summary.csv"
    path.write_text(ROW)
    best = load_recommendations(path, 5)[0]
    assert best["planting_date"] == "2025-11-09"
    assert best["yield_kg_ha"] == 2598.5
    assert best["yield_p10_kg_ha"] == 2062.1
    assert best["n_simulations"] == 62