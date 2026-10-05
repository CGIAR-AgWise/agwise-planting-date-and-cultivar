# integration/test_integration.py
from datetime import date

from advisory import build_advisory, classify_water_stress
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


def test_advisory_separates_iwmi_temporal_roles():
    payload = {
        "request": {
            "country_code": "MOZ",
            "location": {"name": "Chokwe"},
            "crop": "Maize",
            "season": {"year": 2025},
        },
        "recommendations": [
            {
                "rank": 1,
                "planting_date": "2025-11-30",
                "cultivar_id": "Short",
                "yield_kg_ha": 2975.5,
            }
        ],
        "agwise": {
            "forecast": {
                "precipitation": {
                    "source": "AgWise forecast PRCP used by DSSAT",
                    "period": {"start": "2025-11-01", "end": "2026-02-28"},
                }
            }
        },
        "iwmi": {
            "status": "available",
            "rainfall": {
                "status": "available",
                "period": {
                    "start": "1950-01-01T00:00:00Z",
                    "end": "2022-12-31T00:00:00Z",
                },
                "temporal_role": "historical_reference",
            },
            "irrigation": {
                "status": "available",
                "period": {
                    "start": "2026-06-01T00:00:00Z",
                    "end": "2026-06-30T23:59:59Z",
                },
                "temporal_role": "static_spatial_context",
            },
        },
    }

    advisory = build_advisory(payload)

    assert "No current-season IWMI layers were available." in advisory
    assert "Target-season rainfall:" in advisory
    assert (
        "- AgWise forecast PRCP used by DSSAT: 2025-11-01 to 2026-02-28"
        in advisory
    )
    assert "Historical reference layers:" in advisory
    assert (
        "- Historical JFM rainfall anomaly composite (Limpopo domain): "
        "1950-01-01 to 2022-12-31"
    ) in advisory
    assert "Static spatial-context layers:" in advisory
    assert "- Irrigation context: 2026-06-01 to 2026-06-30" in advisory


def test_water_stress_uses_provisional_project_bands():
    assert classify_water_stress(0.32) == "low"
    assert classify_water_stress(0.33) == "moderate"
    assert classify_water_stress(0.65) == "moderate"
    assert classify_water_stress(0.66) == "high"
