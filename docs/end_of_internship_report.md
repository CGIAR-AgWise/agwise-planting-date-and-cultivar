# End-of-Internship Report
## AgWise–DSSAT–IWMI integration for maize advisory development in Chókwè, Mozambique

**Project period:** 2026
**Case study:** Chókwè, Mozambique | Maize | 2025/26 season
**Primary workflow:** AgWise seasonal forecast → DSSAT → planting-date/cultivar advisory

## 1. Introduction

This internship developed and documented an integration between the AgWise
seasonal climate-forecast pipeline, the DSSAT crop model, and IWMI water-context
products for a maize advisory in Chókwè, Mozambique. The work addressed three
practical needs: making the forecast-to-DSSAT workflow reproducible on Windows,
exposing ranked planting-date and cultivar results in an advisory payload, and
testing how IWMI rainfall information could complement or eventually improve
the precipitation input.

The final operational direction is an **IWMI-supported, scenario-based DSSAT
workflow**. The requested IWMI daily observations will replace the temporary
synthetic rainfall input when available. An interim experiment was therefore
implemented using IWMI monthly analysis totals and reproducible synthetic daily
disaggregation. The synthetic series is clearly labelled as temporary and is
not presented as observed daily weather.

## 2. Objectives and implemented workflow

The work aimed to:

1. Run the Mozambique Chókwè use case from YAML configuration through DSSAT.
2. Apply the existing AgWise daily bias-correction workflow to forecast
   precipitation, temperature, and solar radiation.
3. Prepare DSSAT-compatible weather and soil inputs and rank planting-date/
   cultivar treatments.
4. Add IWMI context without allowing uncertain products to silently change the
   DSSAT ranking.
5. Test an IWMI rainfall sensitivity experiment and document the path toward
   daily-observation integration.

![AgWise–DSSAT–IWMI integration workflow](./agwise_iwmi_workflow.svg)

The Chókwè configuration uses a four-month season (`2025-11-01` to
`2026-02-28`), one-month forecast lead, maize cultivar ID `900111`, and the
manual extent `-23.5, 32.5, -25.5, 33.5` in `[N,W,S,E]` order.

## 3. Methodology

### 3.1 Forecast and bias correction

AgWise downloads forecast and hindcast data for `PRCP`, `TMAX`, `TMIN`, and
`SRAD`. Historical observations and hindcasts are used to learn systematic
model errors; the learned correction is applied to the new forecast. The
corrected fields are regridded and sampled at DSSAT soil/crop points.

Bias correction is applied to the AgWise model forecast, not to the IWMI
synthetic series. In the interim experiment, the corrected AgWise `TMAX`,
`TMIN`, and `SRAD` remain unchanged. Only `PRCP` is optionally replaced at the
DSSAT handoff.

### 3.2 IWMI data and synthetic rainfall

The IWMI Digital Twins `/chatbot/rainfall_analyses` export produced **309
monthly values covering 2001-01 through 2026-09**. The API response was a
generated CSV report, not a daily observational series. The export matches the
existing 2001–2016 repository values over all 192 overlapping months. Metadata
records `daily_observations: false`; the returned station identifier still
requires confirmation with IWMI.

For each target month, the generator:

1. Selects the exact `YYYY-MM` total when available.
2. Selects reproducible wet days (default fraction 0.25).
3. Draws positive Gamma weights, \(w_i \sim Gamma(1.5,1.0)\).
4. Allocates \(R_i = M w_i / \sum_j w_j\), preserving monthly total \(M\).

Thus the daily sequence is synthetic, while the monthly total is constrained by
the IWMI analysis. For the 2025/26 season, no climatology fallback was needed.

## 4. Three integration approaches

| Approach | Purpose | Status | Interpretation |
|---|---|---|---|
| **1. IWMI contextual advisory** | Add rainfall anomaly, ET, irrigation probability, and water-stress context | Implemented | Context is displayed and qualified; it does not rerank DSSAT treatments |
| **2. Temporary synthetic PRCP** | Keep the scenario workflow testable while IWMI daily observations are unavailable | Implemented as a temporary bridge | Synthetic daily rainfall replaces PRCP only; it will be replaced by IWMI daily observations |
| **3. IWMI-supported DSSAT scenarios** | Run DSSAT scenarios using validated IWMI daily rainfall and compare them with the AgWise baseline | **Main target approach; pending IWMI delivery** | Approaches 2 and 3 use the same scenario interface; only the rainfall source changes |

Approaches 2 and 3 use the same DSSAT scenario interface. Approach 2 uses
synthetic daily rainfall only because the required IWMI daily observations are
not yet available. Approach 3 is the intended version of that same scenario
workflow: replace the temporary synthetic series with provider-confirmed IWMI
daily observations and compare the resulting DSSAT scenarios with the AgWise
baseline.

## 5. Results

The end-to-end workflow completed successfully for Chókwè. The recommended
treatment was stable:

| Metric | 13-cell AgWise reference | 13-cell IWMI synthetic PRCP |
|---|---:|---:|
| Recommended planting date | 30 Nov 2025 | 30 Nov 2025 |
| Cultivar | Short | Short |
| Median simulated yield | 2,996 kg/ha | 2,973 kg/ha |
| Change | — | -23 kg/ha (-0.77%) |
| DSSAT simulations | 13 | 13 |

```text
Median HWAH yield (kg/ha)

AgWise PRCP       ██████████████████████████████  2,996
IWMI synthetic    █████████████████████████████   2,973
```

The earlier broad run used 62 cells and reported 2,976 kg/ha with a
2,025–3,132 kg/ha spatial range. The current localized run used 13 cells and
reported 2,973 kg/ha with a 2,895–3,065 kg/ha range. This is not a controlled
rainfall comparison because the spatial populations differ. The valid
rainfall sensitivity comparison is the matched 13-cell result above.

## 6. Deliverables, limitations, and next steps

### Deliverables

- Reproducible Chókwè YAML use case and Windows-safe execution.
- DSSAT handoff with optional PRCP override and checkpointed workflow.
- Normalized advisory JSON schema and current Chókwè example.
- IWMI adapter for contextual STAC values with provenance and warnings.
- IWMI monthly exporter, target-year synthesis modes, metadata sidecars, and
  tests.
- Documentation for setup, Makefile commands, comparison design, and
  scientific limitations.

### Limitations

The synthetic rainfall does not recover observed wet-day timing, storm
persistence, extremes, spatial rainfall variation, or rainfall–temperature
dependence. The advisory represents one season, one generic soil setup, and
limited cultivar coverage. Yield percentiles describe spatial variation across
the selected DSSAT cells, not year-to-year weather uncertainty. The IWMI
station mismatch and product metadata must be resolved before operational use.

### Recommended next steps

1. Obtain IWMI daily observations for Chókwè with documented units,
   timestamps, coordinates/grid, quality flags, and missing-value rules.
2. Compare IWMI daily observations with the AgWise reference for the common
   historical period (ideally 1994–2016).
3. Evaluate bias, wet-day frequency, dry spells, extremes, and seasonal totals;
   then replace the temporary synthetic scenario input.
4. Repeat baseline-versus-IWMI scenario comparisons using the same DSSAT cells,
   soils, cultivars, forecast period, and model settings.
6. Only after multi-season validation consider operational advisory use.

**Conclusion:** the internship delivered a working and transparent integration
prototype. The synthetic monthly-to-daily experiment is temporary; the
preferred final solution is an IWMI-supported DSSAT scenario workflow using
validated daily rainfall alongside the AgWise baseline.
