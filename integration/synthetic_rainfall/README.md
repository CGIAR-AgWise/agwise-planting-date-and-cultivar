# Synthetic IWMI rainfall experiment

This experiment uses the IWMI monthly rainfall analysis exported for the
Chókwè-area station `s24851s29487e` / channel `cha1099` and creates a
synthetic daily rainfall series for the existing four-month use-case window:

```text
2025-11-01 through 2026-02-28
```

The source file covers 2001–2016. Since it does not contain the target
2025–2026 months, the generator uses the calendar-month climatological mean
of that source period. It allocates each monthly total across a deterministic
set of synthetic wet days. The generated values are **not IWMI daily
observations**.

## Generate the rainfall replacement

From the repository root:

```bash
python integration/synthetic_rainfall/generate_daily_rainfall.py \
  --monthly-csv integration/raw_data/iwmi_chokwe_monthly_rainfall_2001_2016.csv \
  --season-start 2025-11-01 \
  --season-end 2026-02-28 \
  --output integration/synthetic_rainfall/output/chokwe_2025_26_synthetic_rainfall.csv
```

The output has one row per day:

```text
date,rain_mm
2025-11-01,...
```

The monthly sums are constrained to the IWMI calendar-month climatology.
`--seed` makes the synthetic event placement reproducible.

## Merge into AgWise weather data

The merge command expects an AgWise daily CSV containing `DATE` or `date` and
`PRCP` or `RAIN`. It replaces only that rainfall column and preserves the
other AgWise variables:

```bash
python integration/synthetic_rainfall/merge_prcp.py \
  --agwise-csv path/to/agwise_daily_weather.csv \
  --rainfall-csv integration/synthetic_rainfall/output/chokwe_2025_26_synthetic_rainfall.csv \
  --output integration/synthetic_rainfall/output/chokwe_2025_26_iwmi_prcp_weather.csv
```

This is an experimental mixed-source input:

```text
PRCP/RAIN: synthetic series constrained by IWMI monthly rainfall
TMAX:      AgWise
TMIN:      AgWise
SRAD:      AgWise
```

It is not yet wired into the default forecast or DSSAT targets. The resulting
weather file must be validated and compared with the normal AgWise run before
being used for an advisory.
