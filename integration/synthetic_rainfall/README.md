# Synthetic IWMI rainfall experiment

This experiment uses the IWMI monthly rainfall analysis exported for the
Chókwè-area station `s24851s29487e` / channel `cha1099` and creates a
synthetic daily rainfall series for the existing four-month use-case window:

```text
2025-11-01 through 2026-02-28
```

The generator supports three monthly modes:

- `target-year`: require the exact year/month total for every requested month.
- `climatology`: use the calendar-month mean across all source years.
- `target-year-fallback` (default): use exact year/month totals when available
  and the calendar-month mean only for missing months.

The repository includes a validated export covering 2001-01 through 2026-09:

```text
integration/raw_data/iwmi_chokwe_monthly_rainfall_2001_2026_09.csv
```

The generated values are **not IWMI daily observations**. The API export
contains monthly analysis totals; the generator creates a reproducible
synthetic daily pattern that preserves each selected monthly total.

## Generate the rainfall replacement

From the repository root:

```bash
python integration/synthetic_rainfall/generate_daily_rainfall.py \
  --monthly-csv integration/raw_data/iwmi_chokwe_monthly_rainfall_2001_2026_09.csv \
  --season-start 2025-11-01 \
  --season-end 2026-02-28 \
  --monthly-mode target-year \
  --output integration/synthetic_rainfall/output/chokwe_2025_26_target_year_rainfall.csv
```

The output has one row per day:

```text
date,rain_mm
2025-11-01,...
```

The monthly sums are constrained to the selected target-year totals or
climatological means. `--seed` makes the synthetic event placement
reproducible. A JSON sidecar is written next to the CSV with the selected
monthly totals, fallback months, mode, wet-day fraction, Gamma parameters, and
seed.

To require complete target-year coverage and fail if a requested month is
missing:

```bash
python integration/synthetic_rainfall/generate_daily_rainfall.py \
  --monthly-csv path/to/iwmi_monthly_2001_2026.csv \
  --season-start 2025-11-01 \
  --season-end 2026-02-28 \
  --monthly-mode target-year \
  --output path/to/target_year_daily_rainfall.csv
```

## Merge into AgWise weather data

The merge command expects an AgWise daily CSV containing `DATE` or `date` and
`PRCP` or `RAIN`. It replaces only that rainfall column and preserves the
other AgWise variables:

```bash
python integration/synthetic_rainfall/merge_prcp.py \
  --agwise-csv path/to/agwise_daily_weather.csv \
  --rainfall-csv integration/synthetic_rainfall/output/chokwe_2025_26_target_year_rainfall.csv \
  --output integration/synthetic_rainfall/output/chokwe_2025_26_iwmi_prcp_weather.csv
```

This is an experimental mixed-source input:

```text
PRCP/RAIN: synthetic series constrained by IWMI monthly rainfall
TMAX:      AgWise
TMIN:      AgWise
SRAD:      AgWise
```

It is not enabled by default. Pass the generated CSV as `IWMI_PRCP_CSV` to the
opt-in forecast or workflow target. The resulting weather input must still be
validated and compared with the normal AgWise run before being used for an
advisory.

The API metadata records the requested station and the station identifier
returned by the service. The current export matches the existing 2001–2016
values exactly, but the returned station identifier differs from the requested
identifier and should be confirmed with IWMI before operational use.
