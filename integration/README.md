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

## IWMI adapter

[`iwmi_adapter.py`](./iwmi_adapter.py) is a credential-free adapter. It does
not invent or embed IWMI endpoint URLs; provide the endpoint URLs verified for
the Digital Twin deployment at runtime:

```bash
python integration/iwmi_adapter.py \
  --input integration/examples/chokwe_maize_advisory.json \
  --output integration/examples/chokwe_maize_advisory_with_iwmi.json \
  --endpoint rainfall="https://<iwmi-host>/<rainfall-endpoint>" \
  --endpoint et_fraction="https://<iwmi-host>/<et-endpoint>" \
  --endpoint irrigation="https://<iwmi-host>/<irrigation-endpoint>" \
  --endpoint water_stress="https://<iwmi-host>/<water-stress-endpoint>"
```

The adapter preserves the endpoint response under `iwmi.<name>.value`,
records its source URL, and stops on HTTP, network, or invalid-JSON failures.
Use `--allow-missing` only when an advisory is explicitly allowed to carry
unavailable context. For deployments using bearer authentication, provide
`IWMI_BEARER_TOKEN` at runtime; credentials must not be committed.

The public IWMI STAC catalog can be used for a live product-availability
adapter. The collection metadata is retained under `value`; this does not
claim to be a point-level measurement:

```bash
python integration/iwmi_adapter.py \
  --input integration/examples/chokwe_maize_advisory.json \
  --output integration/examples/chokwe_maize_advisory_with_iwmi.json \
  --stac-collection rainfall=limpopo_jfm_rainfall \
  --stac-collection et_fraction=et_fraction_africa \
  --stac-collection irrigation=irrigated_areas_limpopo \
  --stac-collection water_stress=evaporative_stress_index_africa \
  --allow-missing
```

For spatial item discovery at the Chókwè point, add the coordinates. The
adapter returns the matching STAC item and raster asset URL; it does not yet
pretend that a raster URL is a sampled value:

```bash
python integration/iwmi_adapter.py \
  --input integration/examples/chokwe_maize_advisory.json \
  --output integration/examples/chokwe_maize_advisory_with_iwmi.json \
  --latitude -24.500676 --longitude 33.001806 \
  --stac-collection rainfall=limpopo_jfm_rainfall \
  --stac-collection et_fraction=et_fraction_africa \
  --stac-collection irrigation=irrigated_areas_limpopo \
  --stac-collection water_stress=evaporative_stress_index_africa \
  --allow-missing
```

Add `--sample-raster` to read the nearest GeoTIFF cell at Chókwè. The adapter
uses a windowed remote read where supported; it does not download the entire
large raster into memory:

```bash
python integration/iwmi_adapter.py \
  --input integration/examples/chokwe_maize_advisory.json \
  --output integration/examples/chokwe_maize_advisory_with_iwmi_values.json \
  --latitude -24.500676 --longitude 33.001806 \
  --season-start 2025-11-01 --season-end 2026-02-28 \
  --sample-raster \
  --stac-collection rainfall=limpopo_jfm_rainfall \
  --stac-collection et_fraction=et_fraction_africa \
  --stac-collection irrigation=irrigated_areas_limpopo \
  --stac-collection water_stress=evaporative_stress_index_africa \
  --allow-missing
```

The resulting measure includes `value`, `unit`, and the sampling coordinates.
Product units remain qualified because IWMI products can use different scales
and meanings; they must be confirmed against the product metadata before
changing DSSAT ranking.

The terminal advisory currently makes only a conservative interpretation:
negative or positive rainfall anomaly is described as below or above the
product reference average. ET fraction, irrigation class/probability, and
water-stress values are displayed but are not assigned high/low thresholds
until the corresponding IWMI product legends are confirmed.

When season dates are supplied, each STAC item is classified as
`current_season`, `historical_reference`, or `static_spatial_context`. A
historical or static match is retained for context but is never described as
a direct observation of the target season.

## Terminal recommendation

After a normalized advisory JSON has been produced, render the result as
plain-language text:

```bash
python integration/advisory.py \
  integration/examples/chokwe_maize_advisory.json
```

The terminal message identifies the highest-ranked DSSAT option, reports the
simulated yield, states whether IWMI context is available, and lists the
limitations. It is intentionally cautious: it does not present the current
technical smoke test as a validated farm instruction.

## End-to-end DSSAT-to-advisory command

Use [`run_advisory.py`](./run_advisory.py) when a DSSAT treatment summary CSV
is available. It ranks the CSV rows by `HWAH`, retrieves the Chókwè IWMI
context, samples the rasters when requested, writes the normalized JSON, and
prints the natural-language recommendation:

```bash
python integration/run_advisory.py \
  --dssat-summary data/usecases/useCase_Mozambique_chokwe/Maize/result/DSSAT/AOI/Maize_2025_treatment_summary.csv \
  --country-code MOZ \
  --location Chokwe \
  --crop Maize \
  --latitude -24.500676 --longitude 33.001806 \
  --season-start 2025-11-01 --season-end 2026-02-28 \
  --sample-raster \
  --output integration/examples/chokwe_maize_advisory_with_iwmi_values.json
```

The command expects the summary to contain `PDAT`, a cultivar column such as
`Cultivar` or `INGENO`, and `HWAH`. Use `--allow-missing` to print the DSSAT
recommendation when IWMI is temporarily unavailable.

Locations are resolved from [`locations.json`](./locations.json), so registered
locations do not need coordinates on every command:

```bash
python integration/run_advisory.py \
  --dssat-summary path/to/treatment_summary.csv \
  --location Chokwe \
  --crop Maize \
  --season-start 2025-11-01 --season-end 2026-02-28
```

The registry currently contains Chokwe. Add a reviewed location record with
its country code and coordinates before using another place. For a one-off
unregistered location, provide `--latitude`, `--longitude`, and optionally
`--country-code`; explicit coordinates override the registry.

## Validation

Any JSON Schema draft-2020-12 validator can validate a payload. The schema is
intended to be used at the adapter boundary and before publishing an advisory
to a dashboard or API.
