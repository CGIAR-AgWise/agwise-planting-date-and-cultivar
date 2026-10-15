from iwmi_dssat_scenarios import choose_simulated_scenario, plan_water_management


def current_iwmi(probability=0.04):
    return {
        "irrigation": {
            "status": "available",
            "value": probability,
            "period": {
                "start": "2025-12-01T00:00:00Z",
                "end": "2026-01-31T23:59:59Z",
            },
            "temporal_role": "current_season",
        }
    }


def test_unknown_access_keeps_rainfed_primary_and_marks_irrigation_conditional():
    plan = plan_water_management(
        current_iwmi(0.80), "2025-11-01", "2026-02-28", "unknown"
    )
    assert plan["primary_scenario"] == "rainfed"
    assert plan["scenarios"][1]["status"] == "conditional"
    assert plan["yield_selection_deferred"] is True


def test_reliable_access_can_select_irrigated_primary():
    plan = plan_water_management(
        current_iwmi(0.80), "2025-11-01", "2026-02-28", "reliable"
    )
    assert plan["primary_scenario"] == "irrigated"
    assert plan["scenarios_to_simulate"] == [
        "rainfed",
        "supplemental_irrigation",
        "irrigated",
    ]


def test_historical_irrigation_data_does_not_select_irrigation():
    payload = current_iwmi(0.80)
    payload["irrigation"]["temporal_role"] = "static_spatial_context"
    plan = plan_water_management(
        payload, "2025-11-01", "2026-02-28", "supplemental"
    )
    assert plan["primary_scenario"] == "rainfed"
    assert plan["iwmi_evidence"]["usable_for_scenario_selection"] is False


def test_simulated_choice_uses_cost_and_material_benefit():
    result = choose_simulated_scenario(
        {
            "rainfed": {"yield_kg_ha": 2800, "cost": 0},
            "supplemental_irrigation": {"yield_kg_ha": 2900, "cost": 50},
            "irrigated": {"yield_kg_ha": 3100, "cost": 400},
        },
        "rainfed",
        min_benefit_kg_ha=40,
    )
    assert result["selected_scenario"] == "supplemental_irrigation"
