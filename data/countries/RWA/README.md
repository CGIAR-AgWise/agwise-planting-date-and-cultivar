# Rwanda Data Area

This folder is the active data area for the Rwanda maize forecast use case.

Related use case script:

```text
usecases/01_rwanda_maize_forecast.R
```

Operational calendar:

```text
season start: 2025-09-01
forecast initialization: 2025-08-01
lead time: 1 month
season length: 4 months
```

Folder purpose:

```text
config/                      country run configuration
observations/                observed weather NetCDF inputs
forecast/raw/                raw seasonal forecast NetCDF files
forecast/bias_corrected/     bias-corrected daily forecast NetCDF files
forecast/geo_4cropModel/     soil and point-source inputs for DSSAT formatting
forecast/dssat_handoff/      climate-soil merged RDS inputs for DSSAT
forecast/dssat_weather/      final DSSAT weather files when exported
forecast/logs/               country run logs
forecast/diagnostics/        hindcast or forecast verification outputs
forecast/manifests/          output manifests
```

Status: scaffold only. The production runner creates the config and populates
outputs when the Rwanda use case is executed.
