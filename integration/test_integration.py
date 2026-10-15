# integration/test_integration.py
from datetime import date
import json
from pathlib import Path

from advisory import build_advisory, classify_water_stress
from compare_advisories import compare_payloads
from iwmi_adapter import overlaps
from run_advisory import (
    IWMI_RANKING_UNAVAILABLE,
    load_recommendations,
    load_iwmi_ranking_policy,
    parse_date,
    validate_iwmi_ranking_enabled,
    validate_iwmi_ranking_inputs,
    apply_iwmi_ranking_rule,
)


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

    assert (
        "IWMI does not provide a current-season layer for this advisory period."
        in advisory
    )
    assert "Historical and static IWMI context is shown where available." in advisory
    assert (
        "The target-season precipitation source is the AgWise forecast used by DSSAT."
        in advisory
    )
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
    assert "Temporal yield uncertainty: not estimated" in advisory


def test_water_stress_uses_provisional_project_bands():
    assert classify_water_stress(0.32) == "low"
    assert classify_water_stress(0.33) == "moderate"
    assert classify_water_stress(0.65) == "moderate"
    assert classify_water_stress(0.66) == "high"


def test_iwmi_ranking_is_disabled_until_validated():
    assert validate_iwmi_ranking_enabled(False) is False
    assert validate_iwmi_ranking_enabled(True) is True
    assert IWMI_RANKING_UNAVAILABLE


def test_iwmi_ranking_policy_is_draft_and_disabled():
    policy_path = (
        Path(__file__).parent / "policies" / "maize_water_stress_v1.json"
    )
    with open(policy_path, encoding="utf-8") as handle:
        policy = json.load(handle)
    assert policy["status"] == "draft"
    assert policy["approved"] is False
    assert policy["direction"] == "unset"


def test_experimental_policy_is_explicitly_non_operational():
    policy_path = (
        Path(__file__).parent / "policies" / "maize_water_stress_experimental_v1.json"
    )
    policy = load_iwmi_ranking_policy(policy_path, allow_experimental=True)
    assert policy["status"] == "experimental"
    assert policy["approved"] is False
    try:
        load_iwmi_ranking_policy(policy_path, allow_experimental=False)
    except ValueError:
        pass
    else:
        raise AssertionError("Experimental policy was accepted as approved")


def test_iwmi_ranking_rejects_missing_and_historical_inputs():
    for measure in (
        {"status": "unavailable"},
        {
            "status": "available",
            "temporal_role": "historical_reference",
            "period": {
                "start": "2024-12-01T00:00:00Z",
                "end": "2024-12-31T23:59:59Z",
            },
        },
    ):
        try:
            validate_iwmi_ranking_inputs(
                {"water_stress": measure}, "2025-11-01", "2026-02-28"
            )
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid IWMI ranking input was accepted")


def test_iwmi_ranking_accepts_only_current_nonprovisional_input():
    validate_iwmi_ranking_inputs(
        {
            "water_stress": {
                "status": "available",
                "temporal_role": "current_season",
                "period": {
                    "start": "2025-12-01T00:00:00Z",
                    "end": "2026-01-31T23:59:59Z",
                },
                "stress_category_policy": "approved policy v1",
            }
        },
        "2025-11-01",
        "2026-02-28",
    )


def test_iwmi_ranking_preserves_dssat_and_records_adjustment():
    recommendations = [
        {
            "rank": 1,
            "planting_date": "2025-11-30",
            "cultivar_id": "Short",
            "yield_kg_ha": 3000,
        },
        {
            "rank": 2,
            "planting_date": "2025-11-23",
            "cultivar_id": "Short",
            "yield_kg_ha": 2900,
        },
    ]
    policy = {
        "policy_id": "test-v1",
        "measure": "water_stress",
        "penalty": {"moderate": 0.05, "high": 0.15},
        "penalty_by_planting_date": {"high": {"2025-11-30": 0.2}},
    }
    result = apply_iwmi_ranking_rule(
        recommendations,
        {"water_stress": {"stress_category": "high"}},
        policy,
    )
    assert result[0]["planting_date"] == "2025-11-23"
    assert result[1]["dssat_yield_kg_ha"] == 3000
    assert result[1]["iwmi_adjusted_yield_kg_ha"] == 2400


def test_iwmi_ranking_supports_a_bounded_bonus():
    recommendations = [
        {
            "rank": 1,
            "planting_date": "2025-11-30",
            "cultivar_id": "Short",
            "yield_kg_ha": 3000,
        }
    ]
    policy = {
        "policy_id": "test-bonus-v1",
        "measure": "water_stress",
        "adjustment_fraction": {"moderate": 0.05, "high": -0.15},
    }
    result = apply_iwmi_ranking_rule(
        recommendations,
        {"water_stress": {"stress_category": "moderate"}},
        policy,
    )
    assert result[0]["iwmi_adjusted_yield_kg_ha"] == 3150
    assert result[0]["iwmi_ranking_effect"]["effect"] == "bonus"


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
