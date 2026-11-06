# End-of-Internship Report
## AgWise Planting Date and Cultivar and DSSAT maize advisory development in Chókwè, Mozambique

**Project period:** 2026
**Case study:** Chókwè, Mozambique | Maize | 2025/26 season
**Primary workflow:** AgWise seasonal forecast → DSSAT → planting-date/cultivar advisory

## 1. Introduction

Maize planting-date and cultivar decisions must be made before the season
unfolds, even though rainfall timing, soil conditions, and crop responses are
uncertain. This creates an agronomic and data-science challenge: seasonal
climate information must be converted into a reproducible crop simulation and
then into an actionable advisory.

This internship implemented and tested the AgWise Planting Date and Cultivar
(PDate) workflow with DSSAT for a maize advisory in Chókwè, Mozambique. The
work focused on reproducible Windows execution, DSSAT-compatible weather and
soil preparation, spatial treatment ranking, and a controlled rainfall-input
comparison.

## 2. Objectives and study design

The work aimed to:

1. Run the Mozambique Chókwè use case from YAML configuration through DSSAT.
2. Apply AgWise daily bias correction to precipitation, temperature, and solar
   radiation forecasts.
3. Prepare DSSAT-compatible weather and soil inputs and rank planting-date and
   cultivar treatments.
4. Test an alternative rainfall input by changing only precipitation while
   retaining the other AgWise weather variables.
5. Compare the resulting DSSAT output with a baseline run using the normal
   AgWise workflow.

The Chókwè configuration uses a four-month season (`2025-11-01` to
`2026-02-28`), one-month forecast lead, maize cultivar ID `900111`, and the
manual extent `-23.5, 32.5, -25.5, 33.5` in `[N,W,S,E]` order. The controlled
comparison used the same 13 localized, crop-masked cells for both runs.

## 3. Methodology

### 3.1 AgWise baseline

The baseline run used the normal AgWise workflow without any IWMI rainfall or
other IWMI data in the weather or DSSAT execution path. AgWise downloads
forecast and hindcast data for `PRCP`, `TMAX`, `TMIN`, and `SRAD`. Historical
observations and hindcasts are used to learn systematic model errors, and the
correction is applied to the new forecast. The corrected fields are then
prepared for DSSAT.

This baseline is essential because it provides the reference against which the
alternative-rainfall run can be evaluated. The DSSAT executable, soil inputs,
cultivar options, forecast period, grid-cell set, and model settings were held
constant.

### 3.2 IWMI rainfall input

The IWMI Digital Twins `/chatbot/rainfall_analyses` export supplied **309
monthly values covering 2001-01 through 2026-09**. The API response was a
generated CSV report, not a daily observational dataset. The export matched
the existing 2001–2016 repository values over all 192 overlapping months.
Metadata records `daily_observations: false`, and the returned station
identifier still requires confirmation with IWMI.

For each month, the generator:

1. Selects the exact target-year monthly total when available.
2. Selects a reproducible set of wet days using a default wet-day fraction of
   0.25.
3. Draws positive Gamma-distributed event weights.
4. Allocates the monthly total across the selected wet days.

The resulting daily values are synthetic, but their monthly sums preserve the
selected IWMI monthly totals. For the 2025/26 season, the selected totals were
139.50 mm for November, 140.35 mm for December, 209.99 mm for January, and
16.47 mm for February. No climatology fallback was required.

At the DSSAT handoff, the synthetic IWMI series replaces only `PRCP`/`RAIN` on
covered dates. AgWise `TMAX`, `TMIN`, and `SRAD` remain unchanged. The
synthetic series is not passed through AgWise bias correction because the
purpose of this phase is to test the input connection while preserving the
selected IWMI monthly totals. When IWMI supplies daily observations, those
observations will replace the synthetic series at this same handoff.

## 4. Results

The comparison below is controlled: the AgWise-only baseline and the
IWMI-derived rainfall run use the same 13 cells and DSSAT settings. The only
weather-input change is the rainfall series.

| Metric | AgWise-only baseline | IWMI-derived synthetic rainfall |
|---|---:|---:|
| Rainfall source in DSSAT | AgWise bias-corrected PRCP | Synthetic daily rainfall constrained by IWMI monthly totals |
| Recommended planting date | 30 Nov 2025 | 30 Nov 2025 |
| Cultivar | Short | Short |
| Median simulated yield | 2,996 kg/ha | 2,973 kg/ha |
| Difference | — | -23 kg/ha (-0.77%) |
| DSSAT simulations | 13 | 13 |

```text
Median HWAH yield (kg/ha)

AgWise-only baseline       ██████████████████████████████  2,996
IWMI synthetic rainfall    █████████████████████████████   2,973
```

The recommendation was unchanged: both runs selected 30 November 2025 and the
Short cultivar. The median yield difference was small in this controlled
13-cell comparison, but it should not be interpreted as validation that
synthetic rainfall is equivalent to observed daily rainfall. The experiment
demonstrates that the IWMI rainfall input can pass through the pipeline and
produce a complete DSSAT and advisory result.

An earlier broad run used 62 cells and reported approximately 2,976 kg/ha with
a 2,025–3,132 kg/ha spatial range. That result is not directly comparable to
the current 13-cell comparison because the spatial populations differ.

## 5. Deliverables, limitations, and next steps

### Deliverables

- Reproducible Chókwè YAML use case and Windows-safe execution.
- AgWise bias-correction and DSSAT handoff documentation.
- A controlled AgWise-only baseline and IWMI-derived rainfall comparison.
- Optional rainfall replacement at the DSSAT handoff without changing
  AgWise temperature or solar-radiation inputs.
- IWMI monthly exporter, target-year synthesis modes, metadata sidecars, and
  tests.
- Advisory output containing the planting-date and cultivar results and
  rainfall provenance.

### Limitations

Synthetic daily rainfall cannot recover observed wet-day timing, storm
persistence, extremes, spatial rainfall variation, or rainfall–temperature
dependence. The current result covers one season, a generic soil setup,
limited cultivar coverage, and 13 localized cells. Yield percentiles describe
spatial variation across those cells, not year-to-year weather uncertainty.
The IWMI station-identifier mismatch and product metadata must be resolved
before operational use.

### Next steps

1. Obtain IWMI daily rainfall for Chókwè with documented units, timestamps,
   coordinates or grid definition, quality flags, missing-value rules, and
   confirmed station/channel identity.
2. Replace the synthetic rainfall file with the IWMI daily observations in the
   same DSSAT input path.
3. Validate daily totals, wet-day frequency, dry spells, extremes, seasonal
   totals, completeness, and bias against the AgWise reference.
4. Repeat the controlled comparison over multiple seasons using identical
   cells, soils, cultivars, forecast periods, and model settings.
5. Confirm whether the observed-data results support operational advisory use.

**Conclusion:** the internship delivered a working and transparent rainfall
integration checkpoint. The AgWise-only baseline was compared with an
IWMI-derived synthetic rainfall run, demonstrating that the proposed input
path is executable. Synthetic rainfall is being used because IWMI daily data
were not yet available; it is a workflow-proving substitute, not a claim of
observational accuracy. The next phase is to plug the IWMI daily rainfall
into the same validated workflow and quantify the resulting changes.
