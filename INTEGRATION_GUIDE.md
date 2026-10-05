# AgWise-DSSAT and IWMI Advisory Integration Guide

## Purpose

This document explains how the AgWise seasonal forecast and DSSAT crop-model
workflow is combined with IWMI water-context products to produce the normalized
advisory used by the advisory layer.

The integration is an advisory-focused data contract. AgWise and DSSAT remain
responsible for the seasonal recommendation. IWMI contributes additional
historical and spatial water context. IWMI values are currently displayed for
context and do not re-rank DSSAT treatments.

Target-season precipitation remains the AgWise forecast `PRCP` used by DSSAT.
The IWMI rainfall composite is retained as historical context and is never
presented as a target-season observation.

## High-level architecture

```text
AgWise configuration
        |
        v
Seasonal forecast download
        |
        v
Bias correction and DSSAT handoff
        |
        v
DSSAT simulations
        |
        v
Treatment summary (CSV)
        |
        +------------------------------+
        |                              |
        v                              v
Ranked planting-date/          IWMI STAC search
cultivar options               and raster sampling
        |                              |
        +--------------+---------------+
                       v
             Normalized advisory JSON
                       |
                       v
             Terminal/dashboard consumer
```

## Why these parameters are used

### AgWise and DSSAT parameters

| Parameter | Current Chokwe value | Purpose |
| --- | --- | --- |
| `country_code` | `MOZ` | Selects the country-level configuration and output workspace. |
| `location` / zone | `Chokwe` / `Chókwè` | Identifies the advisory location and the AgWise use-case zone. |
| `crop` | `Maize` | Selects crop-specific DSSAT files, cultivar definitions, and output fields. |
| `season_start` | `2025-11-01` | Defines the target planting season used by the advisory request. |
| `season_end` | `2026-02-28` | Defines the target season window used for IWMI temporal matching. |
| `season_length_months` | `4` | Describes the season duration in the advisory contract. |
| `lead_months` | `1` | Records the forecast lead time used by the AgWise workflow. |
| `PRCP` | Daily rainfall | DSSAT rainfall input in `mm day-1`. |
| `TMAX` | Daily maximum temperature | DSSAT maximum temperature input in degrees Celsius. |
| `TMIN` | Daily minimum temperature | DSSAT minimum temperature input in degrees Celsius. |
| `SRAD` | Daily solar radiation | DSSAT solar-radiation input in `MJ m-2 day-1`. |
| `HWAH` | Harvested yield | DSSAT output metric used to rank treatments. |
| `PDAT` | Planting date | Identifies the planting-date treatment in the summary. |
| `Cultivar` / `INGENO` | Cultivar identifier | Identifies the cultivar treatment in the summary. |
| `n_simulations` | Number of rows per treatment | Describes the simulation coverage behind an aggregate result. |
| `HWAH_p10` / `HWAH_p90` | Yield percentiles | Shows spatial variation across simulated grid cells. |
| `maturity_failure_rate_pct` | Maturity failure percentage | Warns when treatments fail to reach maturity. |

The DSSAT summary is aggregated by cultivar and planting date. The integration
sorts treatments by the selected yield statistic, which is median by default,
and returns the top-ranked combinations rather than only one result.

The Chokwe example currently recommends:

- Planting date: 30 November 2025.
- Cultivar: `Short`.
- Median simulated yield: approximately `2,975.5 kg/ha`.
- Spatial P10-P90 range: approximately `2,025.2-3,132.1 kg/ha`.
- Simulation coverage: 62 grid cells.

## DSSAT ranking effect of IWMI context

### Current state

IWMI does **not** currently change the DSSAT ranking. The ranking is produced
from the DSSAT treatment-summary CSV using the configured yield statistic
(`HWAH_median` by default), grouped by planting date and cultivar. IWMI values
are added after that ranking as contextual measures.

The current data is not sufficient for a ranking effect:

- The rainfall layer is a 1950-2022 historical composite.
- The ET and water-stress layers are historical monthly products.
- The irrigation layer is static spatial context.
- The water-stress bands are provisional project presentation bands, not an
  IWMI-approved crop-impact legend.
- The current DSSAT summary does not contain a validated relationship between
  an IWMI measure and treatment yield.

Applying a penalty with these inputs could change the recommended planting date
without demonstrating that the change improves agronomic decisions. The
integration therefore uses the safety boundary:

```text
DSSAT and AgWise target-season weather -> rank treatments
IWMI historical/static context        -> qualify and explain the result
```

### When an IWMI ranking effect can be implemented

An IWMI effect should be enabled only after all of the following are true:

1. The selected IWMI item overlaps the DSSAT advisory season.
2. The item covers the advisory location.
3. Units, scale/offset, direction, and product meaning are verified.
4. The stress thresholds or transformation are approved for the product and
   crop, rather than being presentation-only defaults.
5. A documented agronomic rule defines how the measure affects a treatment.
6. The rule is validated against multi-season DSSAT runs or observed yields.
7. The rule is versioned, tested, and recorded in the advisory provenance.

The ranking effect should remain disabled when any of these checks fails. A
missing or historical IWMI layer must never be silently converted into a
penalty or a zero value.

### How it would be implemented in code

The safest design is to keep the existing DSSAT ranking unchanged and add an
explicit, opt-in adjustment stage in `run_advisory.py`:

```python
recommendations = load_recommendations(
    args.dssat_summary, args.top, args.rank_by
)

if args.enable_iwmi_ranking:
    validate_iwmi_ranking_inputs(payload["iwmi"], payload["request"]["season"])
    recommendations = apply_iwmi_ranking_rule(
        recommendations,
        payload["iwmi"],
        policy=load_iwmi_ranking_policy(args.iwmi_ranking_policy),
    )
    recommendations = rerank_recommendations(recommendations)
```

`validate_iwmi_ranking_inputs` should reject the adjustment unless the
required IWMI measure is available, marked `current_season`, overlaps the
requested season, and carries verified metadata. It should also reject
provisional categories and unresolved product direction.

The policy should be a versioned configuration, not a hidden constant. For
example:

```json
{
  "policy_id": "maize-water-stress-v1",
  "measure": "water_stress",
  "direction": "higher_values_mean_more_stress",
  "penalty": {
    "moderate": 0.05,
    "high": 0.15
  },
  "validated_for": ["MOZ-Chokwe", "Maize"]
}
```

The adjustment must preserve the original DSSAT result and record the effect:

```json
{
  "yield_kg_ha": 2975.5,
  "dssat_yield_kg_ha": 2975.5,
  "iwmi_adjusted_yield_kg_ha": 2829.7,
  "iwmi_ranking_effect": {
    "policy_id": "maize-water-stress-v1",
    "measure": "water_stress",
    "penalty_fraction": 0.05,
    "applied": true
  }
}
```

The advisory should display both the original DSSAT rank and the adjusted
rank, along with the policy version and reason. If the validation fails, the
command should either stop with an explicit error when ranking was requested,
or continue with the normal DSSAT-only ranking when the feature is not enabled.

### IWMI parameters

The IWMI adapter uses the public STAC catalog to discover a product item near
the advisory coordinates:

```text
https://odc-explorer.iwmi.org/stac
```

| Advisory field | STAC collection | Current role |
| --- | --- | --- |
| `rainfall` | `limpopo_jfm_rainfall` | Historical JFM rainfall anomaly composite. |
| `et_fraction` | `et_fraction_africa` | Monthly ET-fraction product interpreted using the ODC product definition. |
| `irrigation` | `irrigated_areas_limpopo` | Static irrigation context; the `prob` asset is selected. |
| `water_stress` | `evaporative_stress_index_africa` | Monthly, unitless evaporative-stress index. |

The location coordinates are used to construct a small STAC search bounding box
and to sample the selected raster at the nearest raster cell:

```text
latitude:  -24.500676
longitude: 33.001806
```

The adapter records the following metadata for every sampled measure:

- Collection name.
- STAC item ID.
- Selected asset key and URL.
- Start and end dates.
- Temporal role.
- Raw raster value.
- Raster scale and offset.
- Decoded value.
- Sampling coordinates and CRS.

### Units and raster decoding

Raster values are decoded using:

```text
decoded_value = raw_value * scale + offset
```

The Chokwe example contains:

| Product | Raw value | Scale | Published value | Interpretation |
| --- | ---: | ---: | ---: | --- |
| JFM rainfall anomaly | `-12.9096` | `1.0` | `-12.9096%` | Below the product reference average. |
| ET fraction | `6` | `0.1` | `0.60%` | Percentage according to the ODC product definition. |
| Irrigation probability | `0.0358` | `1.0` | `0.0358` | Approximately 3.6% probability. |
| Water stress | `5` | `0.1` | `0.50` | Unitless decoded IWMI index. |

The ET asset has conflicting public metadata: the ODC product definition
describes an ET fraction percentage, while linked GeoTIFF metadata contains
Green ET wording and `mm/month` terminology. The integration follows the ODC
collection and measurement definition, while retaining the conflict as a
provenance warning.

The water-stress product is shown numerically with a provisional project
category: low below `0.33`, moderate from `0.33` to below `0.66`, and high at
or above `0.66`. The public IWMI product metadata does not provide a
product-specific category legend, so this category is explicitly provisional
and does not change DSSAT ranking.

## How the integration is done

The integration boundary is the DSSAT treatment-summary CSV. This keeps the
platforms loosely coupled:

```text
AgWise/DSSAT result
  -> treatment summary CSV
  -> run_advisory.py
  -> normalized contract
  -> advisory consumer
```

`run_advisory.py` does not read AgWise's internal forecast files or IWMI's
internal databases. It accepts a stable DSSAT summary, requests IWMI products
through STAC, and writes one self-describing JSON payload.

### 1. Normalize DSSAT results

The adapter accepts common DSSAT column names (`PDAT`, `Cultivar` or `INGENO`,
and `HWAH`) and normalizes them to:

```json
{
  "rank": 1,
  "planting_date": "2025-11-30",
  "cultivar_id": "Short",
  "yield_kg_ha": 2975.5
}
```

Optional uncertainty and quality fields are carried through:
`yield_p10_kg_ha`, `yield_p90_kg_ha`, `yield_cv_pct`, `n_simulations`, and
`maturity_failure_rate_pct`.

### 2. Discover and classify IWMI context

For each configured collection, the adapter:

1. Searches the STAC catalog around the advisory coordinates.
2. Applies the requested season window when supported.
3. Selects the matching item or the most recent available item.
4. Classifies it as `current_season`, `historical_reference`, or
   `static_spatial_context`.
5. Selects the intended asset (`prob` for irrigation).
6. Samples the nearest raster cell.
7. Applies raster scale, offset, and nodata metadata.
8. Stores raw and decoded values together.

This makes a value auditable without coupling the advisory layer to a
particular IWMI storage implementation.

### 3. Produce the normalized contract

The output joins the two sources under six explicit sections:

```text
contract_version
request
agwise
iwmi
recommendations
provenance
```

The advisory consumer can therefore display the DSSAT recommendation and IWMI
context independently. A failure to retrieve an IWMI layer does not corrupt the
DSSAT recommendation; it is represented with `status: "unavailable"` and an
error message when missing context is allowed.

### 4. Build the advisory

```bash
make advisory \
  DSSAT_SUMMARY='data/usecases/useCase_Mozambique_chókwè/Maize/result/DSSAT/AOI/Maize_2025_treatment_summary.csv' \
  LOCATION=Chokwe \
  CROP=Maize \
  SEASON_START=2025-11-01 \
  SEASON_END=2026-02-28 \
  FORCE=1
```

The command above is the integration-stage command. It:

1. Reads and validates the DSSAT summary.
2. Parses planting dates.
3. Ranks treatment rows by the configured DSSAT yield statistic.
4. Resolves the advisory location.
5. Queries each IWMI STAC collection.
6. Selects the appropriate data asset.
7. Samples the nearest raster cell when requested.
8. Applies scale and offset metadata.
9. Writes the normalized advisory JSON.
10. Prints a cautious terminal advisory.

## Important components in `integration/`

### [`run_advisory.py`](./integration/run_advisory.py)

The end-to-end DSSAT-to-advisory builder. It reads the treatment summary,
creates ranked recommendations, discovers IWMI context, and writes the
normalized payload.

Important responsibilities:

- DSSAT summary column compatibility.
- Planting-date parsing.
- Treatment ranking.
- Location resolution.
- Season metadata.
- Provenance and limitations.

### [`iwmi_adapter.py`](./integration/iwmi_adapter.py)

The IWMI STAC and raster adapter. It supports either direct JSON endpoints or
STAC collection discovery.

Important responsibilities:

- STAC spatial and temporal searches.
- Historical/current/static temporal classification.
- Asset selection.
- Remote GeoTIFF sampling.
- Scale/offset decoding.
- Raw-value audit fields.
- Optional bearer-token authentication.
- Explicit unavailable-source handling.

The irrigation collection has multiple data assets. The adapter selects `prob`
for the advisory probability value instead of relying on arbitrary asset order.

### [`advisory.py`](./integration/advisory.py)

The terminal renderer. It turns the normalized JSON into a human-readable
technical advisory.

It intentionally:

- Shows alternative planting-date/cultivar options.
- Shows spatial yield ranges.
- Separates DSSAT recommendations from IWMI context.
- Reports historical and static temporal roles.
- Avoids unsupported agronomic thresholds.
- Warns that the output is not yet a validated farm instruction.

### [`agwise_iwmi_advisory.schema.json`](./integration/agwise_iwmi_advisory.schema.json)

The JSON Schema for the integration contract. It validates the structure of:

- Request metadata.
- AgWise forecast status.
- DSSAT status and metric.
- IWMI measures.
- Ranked recommendations.
- Provenance and limitations.

### [`workflow_state.py`](./integration/workflow_state.py)

The checkpoint manager used by the Makefile. Checkpoints are content-keyed:
they include hashes of the relevant configuration or summary inputs and verify
that expected output files still exist and are non-empty.

### [`test_integration.py`](./integration/test_integration.py)

Focused Python tests for date parsing, season overlap, and DSSAT summary
normalization. These tests should be extended as raster-decoding behavior is
expanded.

### [`inspect_stac.py`](./integration/inspect_stac.py)

A small inspection utility for examining STAC items and assets while debugging
product selection and metadata.

### [`local_summary.R`](./integration/local_summary.R)

R helper code used to create local treatment summaries from DSSAT outputs.

## Contract structure

The normalized payload has six main sections:

```text
contract_version
request
agwise
iwmi
recommendations
provenance
```

The current example is:

[`integration/examples/chokwe_maize_advisory.json`](./integration/examples/chokwe_maize_advisory.json)

The schema is deliberately explicit about availability. A layer may be:

- `available`: metadata and/or a sampled value are present.
- `unavailable`: retrieval or sampling failed.
- `not_requested`: the consumer did not request that context.

Transient IWMI HTTP and network failures are retried twice. With
`--allow-missing`, failed layers remain visible with per-layer error messages
and the payload declares an `agwise_dssat_only` fallback. This preserves the
AgWise/DSSAT recommendation without silently treating missing IWMI context as
zero or as a current-season observation.

DSSAT yield ranges are also explicit in the contract: `yield_uncertainty`
records `spatial_grid_cells` as the range basis and `not_estimated` for
temporal uncertainty. The advisory therefore cannot present the spatial
P10-P90 range as year-to-year weather risk. Multi-season DSSAT runs remain a
separate future dataset requirement if temporal uncertainty is needed.

## Limitations and solutions

| Limitation | Current solution | Remaining action |
| --- | --- | --- |
| IWMI provider coverage does not match every advisory season | The current Chokwe payload records the available product periods explicitly: rainfall composite `1950-01-01` to `2022-12-31`, ET fraction `2021-12-01` to `2021-12-31`, water stress `2024-12-01` to `2024-12-31`, and irrigation probability `2026-06-01` to `2026-06-30`. These are labelled historical or static context rather than current-season observations. | Use a newer IWMI item only when its `start_datetime` and `end_datetime` overlap the advisory season and its product meaning and metadata are verified. |
| ET catalogue metadata conflicts | The integration follows the `et_fraction_africa` ODC definition, applies scale/offset, and records the conflict in the unit and interpretation text. | Confirm the asset metadata upstream or switch to a product whose collection and GeoTIFF metadata agree. |
| IWMI context does not re-rank DSSAT | This is an intentional safety boundary: DSSAT ranks treatments and IWMI qualifies them. | If re-ranking is required, define and validate an agronomic decision rule separately, then version and test it. |
| Technical result is not a farm instruction | The output includes limitations and recommends local agronomic review. | Validate soils, cultivars, management assumptions, and recommendations across seasons and locations. |

## Focused validation checklist

The integration can be validated without rerunning the forecast or DSSAT:

```bash
python -m pytest integration -q
python -m json.tool integration/examples/chokwe_maize_advisory.json
python integration/advisory.py integration/examples/chokwe_maize_advisory.json
```

For a new DSSAT run, confirm that the summary contains `PDAT`, a cultivar
identifier, and `HWAH`; then record the generated JSON, STAC item IDs, asset
keys, temporal roles, and limitations with the deliverable.
