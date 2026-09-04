# AgWISE Use-Case Scenarios

This folder stores reusable runners and YAML configs for country/crop/use-case
scenarios. Each `.yml` file (a plain-text settings file, see the root
`README.md` if you haven't edited YAML before) is the single source of truth
for one country/crop scenario - country, crop, zones, season dates, etc. all
live there. The numbered country R scripts (`01_rwanda_maize_forecast.R`
etc.) are optional convenience wrappers: they just call the generic runner
below with a fixed YAML path already filled in, for people who'd rather run
`Rscript usecases/01_rwanda_maize_forecast.R` than remember a config path.
You don't need to edit any `.R` script in this repo to add or change a
scenario - only its `.yml` file (or a new one, see "Create a new use case"
below).

Config layout (`<ISO3>` is the country's 3-letter code, e.g. `KEN` for
Kenya; `<crop_usecase>` is a made-up name like `maize_example`):

```bash
usecases/configs/<ISO3>/<crop_usecase>.yml
```

Run one country:

```bash
Rscript usecases/run_usecase.R usecases/configs/KEN/maize_example.yml
```

Preview without running downloads or bias correction:

```bash
Rscript usecases/run_usecase.R usecases/configs/KEN/maize_example.yml --dry-run
```

Run all configured country scenarios:

```bash
Rscript usecases/run_multi_country.R
```

Create a new country/crop use case without editing `main/Forecast` or
`main/DSSAT`:

```bash
Rscript usecases/create_usecase_config.R \
  --country TZA \
  --country-name Tanzania \
  --use-case National \
  --crop Maize \
  --zones Arusha,Dodoma \
  --season-start-month 11 \
  --season-year 2026 \
  --season-length-months 4 \
  --lead-months 1 \
  --n-cores 4 \
  --extent -1.234,29.123,-11.222,40.987
```

The creator writes `usecases/configs/<ISO3>/<crop_usecase>.yml`, creates the
standard data folders, and writes a thin wrapper script in `usecases/`. It
also rounds the bounding box you pass with `--extent` outward to the nearest
`0.01` degree - a technical requirement of the CDS (Copernicus Climate Data
Store, the forecast data source), not something you need to calculate
yourself.

Validate the generated use case:

```bash
Rscript usecases/run_usecase.R usecases/configs/TZA/maize_national.yml --dry-run --n-cores 4
```

Common overrides (add any of these after a `Rscript usecases/run_usecase.R
<config.yml>` command to override that one YAML setting for this run only,
without editing the file):

```bash
--season-year 2026        # run a different year than the one in the YAML
--n-cores 8                # how many CPU cores to use for bias correction
--force-download           # re-download even if cached data already exists
--skip-dssat                # stop after the forecast step; skip DSSAT files
--format-zones              # (re)generate DSSAT WTH/SOL files for the zones
--py-path /path/to/python   # use a different Python install than the default
--base-dir /path/to/data    # write outputs somewhere other than data/
```

Current scenarios:

```bash
run_usecase.R
run_multi_country.R
create_usecase_config.R
configs/KEN/maize_example.yml
configs/RWA/maize_rab.yml
configs/ETH/maize_national.yml
configs/GHA/maize_national.yml
configs/MWI/maize_national.yml
06_kenya_maize_example_forecast.R
07_kenya_maize_example_workflow.R
01_rwanda_maize_forecast.R
02_ethiopia_maize_forecast.R
03_ghana_maize_forecast.R
04_malawi_maize_forecast.R
05_multi_country_maize_forecast.R
```
