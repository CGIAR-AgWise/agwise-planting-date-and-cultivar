# IWMI-informed DSSAT water-management scenarios

This guide describes the pre-DSSAT integration path on branch
`mhmd-review-2`. It is intentionally separate from the existing post-DSSAT
experimental penalty/bonus workflow.

## Design principle

IWMI does not overwrite DSSAT yield and does not automatically choose the
highest-yielding irrigation scenario. It helps identify which water-management
scenarios are feasible and worth simulating:

```text
IWMI provider data
    -> temporal/spatial/data-quality checks
    -> feasible water-management scenarios
    -> DSSAT simulations
    -> yield, water-use, cost, and risk comparison
    -> recommendation
```

## Supported scenarios

| Scenario | DSSAT interpretation | Requirement |
| --- | --- | --- |
| `rainfed` | Rainfall and soil water only | No scheduled irrigation |
| `supplemental_irrigation` | Limited irrigation using a validated trigger/schedule | Confirmed access to some irrigation water |
| `irrigated` | Reliable irrigation using a validated schedule | Reliable water access |

The planner currently creates a scenario plan. It does not yet write DSSAT
experiment files because the repository's DSSAT experiment-file conventions
must be wired to the exact irrigation fields and schedules used by each
use-case.

## Why the planner does not select by yield immediately

Before DSSAT runs, there are no scenario yields to compare. After DSSAT runs,
choosing the largest yield alone would favor irrigation even when water is not
available or affordable.

The selection rule is:

1. Determine which scenarios are feasible from declared water access.
2. Require current-season IWMI evidence before using its probability for
   scenario selection.
3. Run DSSAT for feasible scenarios.
4. Compare net value, not yield alone:

```text
net score = simulated yield - water/management cost
```

5. Require the best alternative to exceed the primary scenario by a configured
   material-benefit threshold.
6. Keep the rainfed scenario as the fallback when evidence or access is weak.

## Run the planner

First generate an advisory JSON using the existing workflow. Then run:

```bash
python integration/plan_dssat_scenarios.py \
  --iwmi-payload integration/examples/chokwe_dssat_baseline.json \
  --season-start 2025-11-01 \
  --season-end 2026-02-28 \
  --water-access unknown \
  --output integration/examples/chokwe_water_scenario_plan.json
```

For a farmer or project known to have reliable irrigation access:

```bash
python integration/plan_dssat_scenarios.py \
  --iwmi-payload integration/examples/chokwe_dssat_baseline.json \
  --season-start 2025-11-01 \
  --season-end 2026-02-28 \
  --water-access reliable
```

The current Chókwè IWMI irrigation layer is not current-season for the
2025-2026 advisory period, so the planner will keep rainfed as the conservative
primary scenario. This is intentional.

## Policy status

[`scenarios/water_management_v1.json`](./scenarios/water_management_v1.json)
is experimental and not approved for operational advice. Its thresholds are
engineering placeholders. They must be replaced or approved only after:

- confirming the irrigation product meaning and period;
- confirming local water access;
- mapping each scenario to valid DSSAT irrigation management;
- validating against observed irrigation and yield outcomes;
- testing multiple seasons and locations.

## Next DSSAT wiring step

The next implementation step is to add a scenario-aware DSSAT handoff that
generates explicit management variants from the plan:

```text
rainfed                  -> no irrigation events
supplemental_irrigation  -> validated trigger and water amount
irrigated                -> validated schedule and water amount
```

Each variant must produce its own DSSAT summary. The advisory should then show
the primary and conditional scenario recommendations side by side.
