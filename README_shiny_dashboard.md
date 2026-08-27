# DSSAT results dashboard (Shiny)

An interactive Shiny app for browsing DSSAT planting-date/cultivar
recommendation results (maps of estimated yield, recommended cultivar and
recommended planting date, a yield-by-cultivar boxplot, and a filterable/
downloadable table). It replaces the older per-country/crop crosstalk HTML
dashboards (`dashboard_template.Rmd`), which embed every row in the browser
for client-side filtering - fine for a small usecase, but a 150+ MB HTML
file that freezes on open for a full country like Zambia. This app instead
keeps the data in a partitioned Parquet store and pushes filtering down to
`arrow`, so the browser only ever receives the current filtered subset, no
matter how many countries/crops accumulate over time.

**This module is independent of the rest of the pipeline.** It doesn't run
during, or get invoked by, `run_dssat_pipeline.R` or any other pipeline
step - it only *reads* dashboard extracts those steps already produce. Build
its data store and run the app as a separate, manual step, on this server or
after downloading it to a laptop.

## What it contains

- `main/DSSAT/build_dashboard_store.R` - ETL script. Scans
  `data/usecases/` for every `*_dashboard_data.RDS` file already produced by
  the pipeline's `build_crop_dashboard()` (see
  `get_pdate_cultivar_recommendation.R`) and consolidates them into one
  partitioned Parquet dataset at
  `data/usecases/results/dashboard_store/` (partitioned by
  country/crop/usecase). Re-run it any time new or updated usecase results
  should show up in the dashboard - it always rebuilds the whole store from
  scratch.
- `main/DSSAT/dashboard_app/app.R` - the Shiny app itself. Reads the Parquet
  store plus this repo's cached country boundaries
  (`data/countries/<ISO3>/admin/gadm/`) to draw country outlines, and
  `maps`-package data for the world/lake background - all offline, no map
  tiles or other network calls at runtime.
- `main/DSSAT/package_dashboard_app_for_laptop.R` - optional packaging
  script. Bundles `app.R`, the Parquet store, and only the country
  boundaries actually needed into one self-contained, downloadable folder
  and `.zip` at `data/usecases/results/dashboard_app_bundle{,.zip}`, for
  running on a laptop with no access to this server or the rest of the repo.

The dashboard shows, per country/crop/usecase: for every simulated grid
point, the DSSAT-simulated cultivar/planting-date combinations ranked by
yield (Rank 1 = best-performing at that point), with filters for cultivar,
recommendation rank, and cropland-mask membership. See the app's own "About
this data" panel for the full explanation of what's simulated and the
season-onset assumption behind the planting-date candidates.

## Running it on this server (in-repo)

```r
# 1. Build (or rebuild, after new usecase results land) the data store:
Rscript main/DSSAT/build_dashboard_store.R

# 2. Run the app:
Rscript -e 'shiny::runApp("main/DSSAT/dashboard_app")'
```

`app.R` looks for the store at `data/usecases/results/dashboard_store` and
boundaries at `data/countries/` automatically - no arguments needed.

## Running it on a laptop (portable bundle, no server/internet needed)

```r
# On the server, after building the store (step 1 above):
Rscript main/DSSAT/package_dashboard_app_for_laptop.R
# -> writes data/usecases/results/dashboard_app_bundle.zip
```

Download and unzip `dashboard_app_bundle.zip`, then on the laptop:

```r
# One-time setup (needs internet, to install R packages):
install.packages(c(
  "shiny", "arrow", "dplyr", "leaflet", "plotly", "DT", "countrycode",
  "sf", "terra"))

# Run (no internet needed from here on - everything the app reads is
# already inside the unzipped folder):

Rscript app.R
```

## Requirements

R packages: `shiny`, `arrow`, `dplyr`, `leaflet`, `plotly`, `DT`,
`countrycode`, `sf`, `terra`. All already installed on this server; the
laptop bundle's `README.txt` lists the same for a fresh laptop install.
