"""Translate IWMI water context into auditable DSSAT scenarios.

This module does not modify DSSAT yields. It selects feasible management
scenarios that should be simulated by DSSAT before comparing their results.
"""

from __future__ import annotations

from datetime import date


SCENARIO_NAMES = ("rainfed", "supplemental_irrigation", "irrigated")
WATER_ACCESS_VALUES = ("unknown", "none", "supplemental", "reliable")


def _as_float(value):
    return float(value) if isinstance(value, (int, float)) else None


def _period_overlaps(period, season_start, season_end):
    start = period.get("start")
    end = period.get("end")
    if not start or not end:
        return False
    start_date = date.fromisoformat(start[:10])
    end_date = date.fromisoformat(end[:10])
    return start_date <= season_end and end_date >= season_start


def _current_season_measure(iwmi, season_start, season_end):
    measure = iwmi.get("irrigation", {})
    value = _as_float(measure.get("value"))
    usable = (
        measure.get("status") == "available"
        and measure.get("temporal_role") == "current_season"
        and _period_overlaps(measure.get("period", {}), season_start, season_end)
        and value is not None
        and 0 <= value <= 1
    )
    return measure, value, usable


def plan_water_management(
    iwmi,
    season_start,
    season_end,
    water_access="unknown",
    policy=None,
):
    """Return feasible and conditional DSSAT water-management scenarios.

    The primary scenario is selected from feasibility and evidence, not from
    an unrun yield comparison. DSSAT must simulate the returned scenarios.
    """
    if water_access not in WATER_ACCESS_VALUES:
        raise ValueError(
            f"water_access must be one of: {', '.join(WATER_ACCESS_VALUES)}"
        )
    policy = policy or {}
    thresholds = policy.get(
        "irrigation_probability_thresholds",
        {"supplemental_min": 0.20, "reliable_min": 0.60},
    )
    supplemental_min = float(thresholds["supplemental_min"])
    reliable_min = float(thresholds["reliable_min"])
    if not 0 <= supplemental_min < reliable_min <= 1:
        raise ValueError("Irrigation probability thresholds must satisfy 0 <= supplemental < reliable <= 1.")

    season_start = date.fromisoformat(season_start)
    season_end = date.fromisoformat(season_end)
    measure, probability, usable = _current_season_measure(
        iwmi, season_start, season_end
    )
    reasons = []
    if not usable:
        reasons.append(
            "current-season irrigation probability is unavailable or does not overlap the season"
        )
    else:
        reasons.append(
            f"current-season irrigation probability is {probability:.2f}"
        )

    scenarios = [
        {
            "name": "rainfed",
            "dssat_management": "rainfed",
            "status": "feasible",
            "requires": "rainfall and soil water only; no scheduled irrigation",
        }
    ]
    if water_access in ("supplemental", "reliable"):
        scenarios.append(
            {
                "name": "supplemental_irrigation",
                "dssat_management": "supplemental_irrigation",
                "status": "feasible",
                "requires": "confirmed access to limited irrigation water",
            }
        )
    else:
        scenarios.append(
            {
                "name": "supplemental_irrigation",
                "dssat_management": "conditional",
                "requires": "confirmed access to limited irrigation water",
            }
        )
    if water_access == "reliable":
        scenarios.append(
            {
                "name": "irrigated",
                "dssat_management": "irrigated",
                "status": "feasible",
                "requires": "reliable irrigation access and a validated schedule",
            }
        )
    else:
        scenarios.append(
            {
                "name": "irrigated",
                "dssat_management": "irrigated",
                "status": "conditional",
                "requires": "reliable irrigation access and a validated schedule",
            }
        )

    if usable and probability >= reliable_min and water_access == "reliable":
        primary = "irrigated"
        reasons.append("irrigation access is reliable and probability supports an irrigated scenario")
    elif usable and probability >= supplemental_min and water_access in ("supplemental", "reliable"):
        primary = "supplemental_irrigation"
        reasons.append("irrigation access is available and probability supports supplemental water")
    else:
        primary = "rainfed"
        reasons.append("rainfed is the conservative feasible baseline")

    for scenario in scenarios:
        scenario.setdefault("status", "conditional")
        scenario["selected"] = scenario["name"] == primary

    return {
        "selection_method": "feasibility_then_expected_value",
        "primary_scenario": primary,
        "scenarios_to_simulate": [
            scenario["name"]
            for scenario in scenarios
            if scenario["status"] == "feasible" or scenario["selected"]
        ],
        "scenarios": scenarios,
        "iwmi_evidence": {
            "measure": "irrigation",
            "value": probability,
            "period": measure.get("period"),
            "temporal_role": measure.get("temporal_role"),
            "usable_for_scenario_selection": usable,
        },
        "selection_reasons": reasons,
        "yield_selection_deferred": True,
        "yield_selection_note": (
            "Run DSSAT for each feasible scenario first. Choose among simulated "
            "results only after applying water feasibility, cost, and material "
            "benefit rules; do not select irrigation solely because it has the "
            "highest simulated yield."
        ),
        "operational_status": "experimental",
        "not_for_operational_advice": True,
    }


def choose_simulated_scenario(results, primary_scenario, min_benefit_kg_ha=0):
    """Choose a scenario after DSSAT has simulated feasible scenarios.

    ``results`` maps scenario names to ``{"yield_kg_ha": number, "cost": number}``.
    The primary scenario is the fallback. A higher-yield alternative must exceed
    the configured material benefit after its cost.
    """
    if primary_scenario not in results:
        raise ValueError("DSSAT results must include the primary scenario.")
    baseline = results[primary_scenario]
    baseline_net = float(baseline["yield_kg_ha"]) - float(baseline.get("cost", 0))
    candidates = []
    for name, result in results.items():
        net = float(result["yield_kg_ha"]) - float(result.get("cost", 0))
        candidates.append((net, name))
    best_net, best_name = max(candidates)
    if best_net - baseline_net < min_benefit_kg_ha:
        best_name = primary_scenario
    return {
        "selected_scenario": best_name,
        "selection_method": "feasibility_then_expected_value",
        "primary_scenario": primary_scenario,
        "net_scores_kg_ha": {
            name: float(result["yield_kg_ha"]) - float(result.get("cost", 0))
            for name, result in results.items()
        },
        "minimum_material_benefit_kg_ha": min_benefit_kg_ha,
    }
