# integration/test_integration.py
from datetime import date

from advisory import build_advisory, classify_water_stress
from compare_advisories import compare_payloads
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
    assert best["yield_uncertainty"]["range_basis"] == "spatial_grid_cells"
    assert best["yield_uncertainty"]["temporal_uncertainty"] == "not_estimated"


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
                "yield_p10_kg_ha": 2025.2,
                "yield_p90_kg_ha": 3132.1,
                "n_simulations": 62,
                "yield_uncertainty": {
                    "range_basis": "spatial_grid_cells",
                    "temporal_uncertainty": "not_estimated",
                    "interpretation": "Spatial variation only.",
                },
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

    assert "Rainfall used by DSSAT:" in advisory
    assert (
        "- AgWise forecast PRCP used by DSSAT: 2025-11-01 to 2026-02-28"
        in advisory
    )
    assert "- Irrigation context: product located" in advisory
    assert "Temporal yield uncertainty: not estimated" in advisory
    assert "Technical demonstration; review with local agronomic knowledge." in advisory


def test_water_stress_uses_provisional_project_bands():
    assert classify_water_stress(0.32) == "low"
    assert classify_water_stress(0.33) == "moderate"
    assert classify_water_stress(0.65) == "moderate"
    assert classify_water_stress(0.66) == "high"


def test_compare_advisories_reports_changed_recommendation():
    baseline = {
        "request": {
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
            },
            {
                "rank": 2,
                "planting_date": "2025-11-23",
                "cultivar_id": "Short",
                "yield_kg_ha": 2822,
            },
        ],
    }
    experimental = {
        **baseline,
        "provenance": {
            "iwmi_ranking": {
                "mode": "experimental",
                "policy_id": "test-v1",
            }
        },
        "recommendations": [
            {
                "rank": 1,
                "planting_date": "2025-11-23",
                "cultivar_id": "Short",
                "yield_kg_ha": 2765.56,
                "dssat_yield_kg_ha": 2822,
                "iwmi_ranking_effect": {"adjustment_fraction": -0.02},
            },
            {
                "rank": 2,
                "planting_date": "2025-11-30",
                "cultivar_id": "Short",
                "yield_kg_ha": 2529.175,
                "dssat_yield_kg_ha": 2975.5,
                "iwmi_ranking_effect": {"adjustment_fraction": -0.15},
            },
        ],
    }
    result = compare_payloads(baseline, experimental)
    assert result["best_recommendation_changed"] is True
    assert result["experimental"]["best"]["planting_date"] == "2025-11-23"
    first = next(
        item for item in result["treatments"] if item["planting_date"] == "2025-11-30"
    )
    assert first["rank_change"] == -1
