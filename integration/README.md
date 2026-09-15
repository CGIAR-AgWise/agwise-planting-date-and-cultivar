# AgWise–IWMI integration contract

This folder defines the small data contract shared by the AgWise planting-date
and cultivar workflow and the IWMI Limpopo Digital Twin integration.

The contract is deliberately advisory-focused. AgWise remains the source of
seasonal climate and DSSAT simulation results, while IWMI contributes
water-management context. Neither platform has to depend on the other
platform's internal files or database schema.

## Data flow

```text
AgWise forecast ─┐
                 ├─> normalized integration payload ─> advisory consumer
IWMI context  ───┘
                       ^
                 DSSAT simulations
```

## Contract files

- [`agwise_iwmi_advisory.schema.json`](./agwise_iwmi_advisory.schema.json) is
  the JSON Schema for one normalized payload.
- [`examples/chokwe_maize_advisory.json`](./examples/chokwe_maize_advisory.json)
  is a technical Chókwè example using the current DSSAT smoke-test outputs.

## Required distinctions

- `source` identifies where a value came from; it is not an endorsement of
  scientific validation.
- `status` distinguishes available, unavailable, and not-requested external
  context.
- `provenance` records the run and model assumptions needed to reproduce or
  qualify a recommendation.
- `recommendations` contains ranked planting-date/cultivar combinations, not
  only the single best option.

The current example is **not an agronomic recommendation**. It uses one point,
one provisional regional cultivar, a generic soil profile, and one forecast
season. It exists to establish the interface before the IWMI adapter is built.

## Validation

Any JSON Schema draft-2020-12 validator can validate a payload. The schema is
intended to be used at the adapter boundary and before publishing an advisory
to a dashboard or API.
