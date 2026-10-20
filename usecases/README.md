# AgWISE use cases

Each `.yml` file under `configs/<ISO3>/` describes one country/crop/season
scenario and is the only thing you edit to run or add a use case. The fields
are explained in the main `README.md` ("Use cases" -> "YAML configuration").

Run one use case (check it first with `--dry-run`):

```bash
Rscript usecases/run_usecase.R usecases/configs/RWA/maize_demo.yml --dry-run
Rscript usecases/run_usecase.R usecases/configs/RWA/maize_demo.yml
```

Or with Docker, without installing anything: see "Run the Rwanda demo with
Docker" in the main `README.md`.

## Current vs. legacy configs

Configs with `skip_weather_soil_creation: true` use the current pipeline
(forecast, bias correction and soil from the `agwise-data` CLI):

```text
KEN/maize_sep_init.yml
MOZ/maize_oct_init.yml   MOZ/soybean_oct_init.yml
MWI/maize_oct_init.yml   MWI/soybean_oct_init.yml
NGA/maize_full_mar.yml   NGA/maize_full_apr.yml
NGA/maize_full_jun.yml   NGA/maize_full_jul.yml
RWA/maize_sep_init.yml   RWA/maize_sep_init_fert.yml   RWA/maize_demo.yml
ZMB/maize_oct_init.yml   ZMB/soybean_oct_init.yml
```

The other configs (`ETH/maize_national`, `GHA/maize_national` and the RWA
`*_august_init` ones) still run the legacy
R forecast workflow in `main/Forecast/`. So do the numbered wrapper scripts
(`01_rwanda_maize_forecast.R` ... `07_kenya_maize_example_workflow.R`),
`run_multi_country.R` (runs every config, legacy ones included) and
`create_usecase_config.R` (generates legacy-style configs). See
`main/Forecast/LEGACY_PIPELINE.md`.

## Adding a use case

1. Copy a current config, e.g. `configs/ZMB/maize_oct_init.yml`, to
   `configs/<ISO3>/<crop>_<name>.yml`.
2. Change `country_code`, `country_name`, `use_case_name`, `crop`, `zones`
   (admin level-1 names), the season dates, `lead_months` and `varietyids`.
   With `lead_months: 0` the previous month's forecast is also needed, as
   spin-up weather (see the main `README.md`).
3. Keep `skip_weather_soil_creation: true` and
   `generate_dssat_via_datasourcing: true`.
4. Run it with `--dry-run`, then for real. For a quick first check, add
   `resolution_km: 10` (about 4x fewer sites).
