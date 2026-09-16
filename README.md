# AgWISE–Limpopo Digital Twin Integration

## AgWISE Planting Date and Cultivar Workflow

AgWISE prepares seasonal climate forecasts for DSSAT crop-model simulations
and uses those simulations to compare planting dates and cultivars. This
branch also contains an integration prototype that combines AgWISE results
with water-management context from the IWMI Limpopo Digital Twin.

The project has two layers:

```text
AgWISE forecast and DSSAT simulation
  -> ranked planting-date/cultivar results
  -> AgWISE-IWMI advisory contract
  -> IWMI context and terminal recommendation
```

AgWISE remains responsible for the climate forecast and crop-model result.
IWMI supplies additional rainfall, evapotranspiration, irrigation, and water
stress context. The IWMI context qualifies the recommendation; it does not
change the DSSAT ranking unless product meanings and agronomic thresholds have
been formally validated.

## What the workflow does

For a configured country, location, crop, and season, the workflow:

1. Downloads seasonal forecast and hindcast data from the Copernicus Climate
   Data Store.
2. Converts and prepares the climate variables used by DSSAT.
3. Applies daily bias correction.
4. Creates DSSAT-ready weather, soil, and handoff files.
5. Runs the configured DSSAT simulations.
6. Ranks planting-date and cultivar treatments by simulated yield (`HWAH`).
7. Resolves the location and queries the public IWMI STAC catalog.
8. Optionally samples the nearest remote raster cell at the location.
9. Writes a normalized JSON payload and prints a natural-language advisory.

The core forecast variables are:

```text
PRCP  daily rainfall, mm day-1
TMAX  daily maximum temperature, degC
TMIN  daily minimum temperature, degC
SRAD  daily solar radiation, MJ m-2 day-1
```

## Quick start

### 1. Create the environment

The reproducible environment includes Python, R, geospatial libraries, CDS
client support, and raster sampling dependencies:

```bash
conda env create -f environment.yml
conda activate agwise-integration
Rscript install_pkgs.R
```

If the environment already exists:

```bash
conda env update -f environment.yml --prune
```

### 2. Configure local paths

Copy the local settings template:

```bash
cp .env.example .env
```

Set the local DSSAT executable and, if necessary, the Python executable:

```text
DSSAT_CSM=C:/DSSAT48/DSCSM048.EXE
AGWISE_PYTHON=python
AGWISE_N_CORES=2
```

Keep CDS credentials in the user-level `~/.cdsapirc` file. Never commit
`.env`, `.cdsapirc`, API tokens, passwords, or downloaded data.

### 3. Preview before running

Always begin with:

```bash
make dry-run
```

The dry run checks the configured AgWISE YAML wiring without downloading
forecast data or running the long processing steps.

### 4. Run the Chokwe demonstration

The configured demonstration is maize in Chokwe, Mozambique:

```bash
make workflow \
  LOCATION=Chokwe \
  CROP=Maize \
  SEASON_START=2025-11-01 \
  SEASON_END=2026-02-28
```

This runs the configured AgWISE use case first and then builds the IWMI-aware
advisory from the DSSAT treatment summary.

The current demonstration is a technical integration test, not a validated
farm instruction. It uses one point, a generic soil profile, a provisional
regional cultivar, and one forecast season.

## Makefile commands

Run commands from the repository root. The Makefile is intended for GNU Make,
Git Bash, or another POSIX-compatible shell.

| Command | Purpose |
| --- | --- |
| `make setup` | Print environment setup instructions |
| `make dry-run` | Preview the configured AgWISE use case |
| `make forecast` | Run the configured AgWISE/DSSAT use case |
| `make advisory` | Build the advisory from an existing DSSAT summary |
| `make workflow` | Run `forecast`, then `advisory` |
| `make clean-python-cache` | Remove generated Python bytecode caches |

The most important Makefile variables are:

```text
LOCATION          Location name, default: Chokwe
CROP              Crop name, default: Maize
SEASON_START      Target season start, default: 2025-11-01
SEASON_END        Target season end, default: 2026-02-28
SEASON_YEAR       AgWISE season year, default: 2025
USECASE_CONFIG    AgWISE YAML configuration
DSSAT_SUMMARY     DSSAT treatment summary CSV
ADVISORY_OUTPUT   Normalized advisory JSON output
```

For example:

```bash
make dry-run \
  USECASE_CONFIG=usecases/configs/MOZ/maize_chokwe.yml
```

## Use-case scenarios

A use case is one complete experiment:

```text
location or zone + country + crop + season + forecast settings + DSSAT inputs
```

### Scenario 1: Run the complete Chokwe workflow

Use this for the main internship demonstration:

```bash
make workflow \
  LOCATION=Chokwe \
  CROP=Maize \
  SEASON_START=2025-11-01 \
  SEASON_END=2026-02-28
```

Expected flow:

```text
Chokwe YAML
  -> forecast download
  -> bias correction
  -> DSSAT preparation and simulation
  -> best planting date and cultivar
  -> IWMI context
  -> terminal recommendation
```

### Scenario 2: Regenerate an advisory without rerunning the forecast

Use this when a DSSAT treatment summary already exists:

```bash
make advisory \
  LOCATION=Chokwe \
  CROP=Maize \
  DSSAT_SUMMARY=path/to/treatment_summary.csv
```

This reads the CSV, ranks rows by `HWAH`, resolves the location, retrieves
IWMI context, writes the normalized JSON payload, and prints the
recommendation. It avoids repeating the expensive forecast and DSSAT stages.

The CSV is expected to contain:

```text
PDAT       planting date
Cultivar   or INGENO, cultivar identifier
HWAH       simulated harvested yield
```

### Scenario 3: Run another existing AgWISE configuration

The repository includes configurations for:

```text
usecases/configs/ETH/maize_national.yml
usecases/configs/GHA/maize_national.yml
usecases/configs/KEN/maize_example.yml
usecases/configs/MWI/maize_national.yml
usecases/configs/MOZ/maize_chokwe.yml
usecases/configs/MOZ/maize_full.yml
usecases/configs/MOZ/maize_test.yml
usecases/configs/MOZ/soybean_full.yml
usecases/configs/RWA/maize_rab.yml
```

Preview Malawi, for example:

```bash
make dry-run \
  USECASE_CONFIG=usecases/configs/MWI/maize_national.yml
```

Run it with the Makefile:

```bash
make workflow \
  USECASE_CONFIG=usecases/configs/MWI/maize_national.yml \
  LOCATION=MalawiLocation \
  CROP=Maize \
  SEASON_START=2025-11-01 \
  SEASON_END=2026-02-28
```

The YAML must contain suitable country, location or zone, crop, season,
forecast extent, soil, cultivar, and DSSAT settings. Changing only
`LOCATION=...` or `CROP=...` does not create those scientific inputs.

### Scenario 4: Compare two locations

Run the same crop and season for two reviewed use cases and compare:

```bash
make workflow LOCATION=Chokwe CROP=Maize \
  SEASON_START=2025-11-01 SEASON_END=2026-02-28

make workflow LOCATION=OtherLocation CROP=Maize \
  SEASON_START=2025-11-01 SEASON_END=2026-02-28
```

Compare the recommended planting date, cultivar, simulated yield, rainfall
context, irrigation context, and water-stress context. Different results are
expected because climate, soil, forecast, and water conditions vary by place.

### Scenario 5: Compare different seasons

Keep the location and crop fixed, but change the target season:

```bash
make workflow LOCATION=Chokwe CROP=Maize \
  SEASON_START=2026-10-01 SEASON_END=2027-01-31
```

The advisory records whether each IWMI source overlaps the requested season.
Historical and static context is retained, but it must not be described as a
direct observation of the target season.

### Scenario 6: Test a new location using coordinates

The advisory can be tested for an unregistered location by supplying
coordinates directly:

```bash
python integration/run_advisory.py \
  --dssat-summary path/to/treatment_summary.csv \
  --location "New Location" \
  --latitude -23.0000 \
  --longitude 32.5000 \
  --crop Maize \
  --season-start 2025-11-01 \
  --season-end 2026-02-28 \
  --sample-raster \
  --allow-missing
```

This tests IWMI point lookup and advisory formatting. A full AgWISE forecast
still requires a reviewed YAML configuration and supporting DSSAT data.

## Integration components

The `integration/` folder contains the AgWISE-IWMI boundary:

| File | Purpose |
| --- | --- |
| `integration/run_advisory.py` | Reads DSSAT CSV, ranks treatments, queries IWMI, and prints the advisory |
| `integration/iwmi_adapter.py` | Discovers IWMI STAC items and optionally samples remote rasters |
| `integration/advisory.py` | Formats the normalized payload as plain-language terminal text |
| `integration/locations.json` | Registry of reviewed locations and coordinates |
| `integration/agwise_iwmi_advisory.schema.json` | JSON Schema for the normalized payload |
| `integration/examples/` | Technical example advisory payloads |

### Direct advisory command

The registered Chokwe coordinates are resolved automatically:

```bash
python integration/run_advisory.py \
  --dssat-summary data/usecases/useCase_Mozambique_chokwe/Maize/result/DSSAT/AOI/Maize_2025_treatment_summary.csv \
  --country-code MOZ \
  --location Chokwe \
  --crop Maize \
  --season-start 2025-11-01 \
  --season-end 2026-02-28 \
  --sample-raster \
  --output integration/examples/chokwe_maize_advisory_with_iwmi_values.json
```

Use `--allow-missing` when IWMI is temporarily unavailable and the DSSAT
recommendation should still be printed.

### IWMI products and interpretation

The adapter currently supports these public STAC collections:

```text
limpopo_jfm_rainfall
et_fraction_africa
irrigated_areas_limpopo
evaporative_stress_index_africa
```

The adapter records the source item, period, asset URL, value, unit, CRS,
coordinates, and sampling method. It classifies source periods as:

```text
current_season
historical_reference
static_spatial_context
```

Interpretation is deliberately conservative:

- A negative rainfall anomaly is described as below the product reference
  average.
- A positive rainfall anomaly is described as above the product reference
  average.
- ET fraction, irrigation, and water-stress values are displayed but are not
  labeled high or low until official legends and thresholds are confirmed.
- IWMI context does not re-rank DSSAT planting dates or cultivars.

## Location registry

Registered locations are stored in
[`integration/locations.json`](integration/locations.json). A record contains:

```json
{
  "name": "Chokwe",
  "country_code": "MOZ",
  "latitude": -24.500676,
  "longitude": 33.001806,
  "iwmi_region": "Limpopo"
}
```

Add a new location only after its coordinates, country, IWMI region, soil,
crop calendar, and DSSAT assumptions have been reviewed. For one-off advisory
tests, explicit `--latitude` and `--longitude` values override the registry.

## Full AgWISE use cases versus advisory inputs

The advisory layer is generalized around:

```text
location + latitude/longitude + crop + season + DSSAT summary
```

The full AgWISE forecast remains configuration-driven because it needs
scientific inputs that cannot safely be inferred from a location name:

```text
country code
forecast extent
season length and lead time
climate variables
soil profile
cultivar and variety identifiers
crop calendar
DSSAT templates and management settings
```

The correct process for a new crop or location is:

1. Create or adapt a YAML use-case configuration.
2. Review the extent, season, soil, cultivar, and DSSAT inputs.
3. Run `make dry-run`.
4. Run the forecast and DSSAT workflow.
5. Register the location if it will be reused by the advisory.
6. Run the advisory and review its limitations.

This separation prevents a technically valid command from being mistaken for
a scientifically validated recommendation.

## Direct R workflow

The Makefile is the recommended entry point for the integrated workflow. The
underlying AgWISE runner can also be called directly:

```bash
Rscript usecases/run_usecase.R \
  usecases/configs/MOZ/maize_chokwe.yml \
  --dry-run
```

Run an existing YAML configuration:

```bash
Rscript usecases/run_usecase.R \
  usecases/configs/MOZ/maize_chokwe.yml \
  --season-year 2025
```

Run all configured country use cases:

```bash
Rscript usecases/run_multi_country.R
```

The scripts under `main/Forecast/` and `main/DSSAT/` are the shared engine.
Normal users should change YAML configuration and runtime variables rather
than editing those shared scripts.

## Repository structure

```text
main/
  Forecast/                  Forecast download, bias correction, and DSSAT handoff
  DSSAT/                     DSSAT weather, soil, and simulation workflow

usecases/
  configs/                   Country and crop YAML configurations
  run_usecase.R              Single use-case runner
  run_multi_country.R        Multi-country runner
  create_usecase_config.R    New YAML configuration helper

integration/
  run_advisory.py            DSSAT-to-IWMI advisory orchestration
  iwmi_adapter.py            IWMI STAC and raster adapter
  advisory.py                Terminal recommendation formatter
  locations.json             Reviewed location registry

data/
  countries/                 Country forecast workspaces
  global/                    Shared soil and geospatial inputs
  usecases/                  DSSAT templates and generated outputs
```

## Outputs and reproducibility

Forecast and DSSAT outputs are written under the configured `data/` use-case
directories. The integration command writes a normalized JSON payload, for
example:

```text
integration/examples/chokwe_maize_advisory_with_iwmi_values.json
```

The payload is intended for downstream dashboards, APIs, or other platform
consumers. It contains the request, AgWISE result, ranked recommendations,
IWMI context, provenance, source periods, and limitations.

Generated logs, NetCDF/RDS files, DSSAT outputs, downloaded source trees,
Python caches, `.env`, and credentials should remain uncommitted unless they
are intentionally being versioned as a small example fixture.

## Troubleshooting

### `make` is not available

Install GNU Make or use Git Bash. Alternatively, run the underlying
`Rscript` and Python commands directly as shown above.

### CDS download fails

Check that `~/.cdsapirc` exists, contains valid credentials, and that the
selected forecast dates and extent are supported by the CDS service.

### DSSAT executable is not found

Set the executable path in `.env`:

```text
DSSAT_CSM=C:/DSSAT48/DSCSM048.EXE
```

### IWMI data are unavailable

Use `--allow-missing` for an advisory that reports DSSAT results while
marking missing IWMI context explicitly. Do not replace missing measurements
with invented values.

### The result is not an agronomic recommendation

The current integration is a reproducible technical prototype. Validate
multiple seasons, locations, soils, cultivars, and official IWMI product
legends before presenting output as operational farm advice.

## Related documentation

- [`integration/README.md`](integration/README.md): detailed contract and
  adapter reference.
- [`environment.yml`](environment.yml): Conda environment specification.
- [`.env.example`](.env.example): local runtime settings template.
- [`Makefile`](Makefile): workflow targets and overridable variables.
- [`usecases/README.md`](usecases/README.md): use-case configuration details.
