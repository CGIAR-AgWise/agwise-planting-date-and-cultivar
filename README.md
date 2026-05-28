# AgWISE Planting Date And Cultivar

Production workflow for preparing seasonal climate forecasts, bias-correcting
daily weather variables, and creating DSSAT-ready inputs for planting date and
cultivar advisories.

## Project Layout

```text
main/       Forecast and DSSAT production code
usecases/   YAML configs and runner scripts for country/crop scenarios
data/       Country forecast data, shared geodata, DSSAT use-case data
docs/       Workflow documentation and figures
tests/      Smoke and validation checks
archive/    Legacy code and unused scripts
```

## Run A Use Case

```bash
Rscript usecases/run_usecase.R usecases/configs/RWA/maize_rab.yml --dry-run
```

Kenya can also be run step-by-step from RStudio:

```text
usecases/07_kenya_maize_example_rstudio_workflow.R
```

Country forecast outputs are written under `data/countries/<ISO3>/`.
Crop/use-case DSSAT templates and outputs are stored under `data/usecases/`.
