# Kenya Data Workspace

Active country code: `KEN`

Active configuration:

```bash
data/countries/KEN/config/KEN_config_agwise.json
```

Current config summary:

```bash
season: OND
season year: 2025
season start: 2025-10-01
forecast lead: 1 month
forecast initialization: 2025-09-01
```

## Active Folders

```bash
config/                     # Country run configuration
observations/               # Daily observed reference data
forecast/raw/               # Raw September-initialized model data after next run
forecast/bias_corrected/    # Bias-corrected September-initialized forecast after next run
forecast/geo_4cropModel/    # Active DSSAT point-source folder
forecast/dssat_handoff/     # Generated DSSAT-ready RDS forecast outputs
forecast/logs/              # Current run logs
forecast/diagnostics/       # Skill/verification outputs
forecast/manifests/         # Output manifests
```

## Point Data

The active Kenya point-source folder is:

```bash
forecast/geo_4cropModel/Kisumu/
```

It contains the complete soil profile points used to sample bias-corrected
forecast weather for DSSAT.

## Archive Note

Older October-initialized raw forecasts, bias-corrected outputs, DSSAT RDS
outputs, DSSAT transform files, and misfiled Rwanda zone point folders were
moved to:

```bash
data/archive/legacy_20260528/KEN/pre_one_month_lead_oct_init/
```

This prevents old October outputs from being confused with the new one-month
lead-time setup.
