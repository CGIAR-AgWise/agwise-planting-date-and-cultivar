# AgWISE Use-Case Scenarios

This folder stores reusable runners and YAML configs for country/crop/use-case
scenarios. YAML files are the source of truth; the country R scripts are thin
compatibility wrappers.

Config layout:

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

Create a new YAML config:

```bash
Rscript usecases/create_usecase_config.R \
  --country RWA \
  --country-name Rwanda \
  --use-case RAB \
  --crop Maize \
  --zones Amajyaruguru,Amajyepfo,Iburasirazuba \
  --season-start-month 9 \
  --season-year 2025 \
  --season-length-months 4 \
  --lead-months 1 \
  --extent -0.8,28.7,-2.9,31.1
```

Common overrides:

```bash
--season-year 2026
--n-cores 8
--force-download
--skip-dssat
--format-zones
--py-path /path/to/python
--base-dir /path/to/data
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
07_kenya_maize_example_rstudio_workflow.R
01_rwanda_maize_forecast.R
02_ethiopia_maize_forecast.R
03_ghana_maize_forecast.R
04_malawi_maize_forecast.R
05_multi_country_maize_forecast.R
```
