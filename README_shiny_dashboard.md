# DSSAT results dashboard (Shiny)

An interactive Shiny app for browsing DSSAT planting-date/cultivar
recommendation results (maps of estimated yield, recommended cultivar and
recommended planting date, a yield-by-cultivar boxplot, and a filterable/
downloadable table). It replaces the older per-country/crop crosstalk HTML
dashboards (`dashboard_template.Rmd`), which embed every row in the browser
for client-side filtering - fine for a small usecase, but a 150+ MB HTML
file that freezes on open for a full country like Zambia.

Instead, this app stores all results in one combined data store on disk at
`data/usecases/results/dashboard_store/`, split into subfolders by
country/crop/usecase. When you filter the app to "just Kenya, just Maize",
only that subfolder is read off disk and sent to the browser - not every
country's data every time.

**This module is independent of the rest of the pipeline.** It doesn't run
during, or get invoked by, `run_dssat_pipeline.R` or any other pipeline
step - it only *reads* dashboard extracts those steps already produce. Build
its data store and run the app as a separate, manual step, on this server or
after downloading it to a laptop.

## How to run it (2 commands, on this server)

```r
# 1. Build/rebuild the data store from whatever usecase results currently
#    exist under data/usecases/ (run this again any time new results land):
Rscript main/DSSAT/build_dashboard_store.R

# 2. Launch the app in a browser tab:
Rscript -e 'shiny::runApp("main/DSSAT/dashboard_app")'
```

That's it - `app.R` finds the store and country boundaries on its own, no
paths or arguments to pass. Leave the terminal running command 2; it prints
a local URL and keeps serving the app until you stop it (Ctrl+C) or close
the terminal. See "Running it on a laptop" below if you instead want to hand
someone a self-contained copy that needs no server access.

## What it contains

- `main/DSSAT/merge_usecases.R` - optional, standalone pre-step. Merges
  several already-run usecases for one country (e.g. Nigeria's maize, split
  across `useCase_Nigeria_full_apr/_jul/_jun/_mar` - one per region's
  planting month) into one new usecase directory, so the dashboard shows the
  country as a single coherent result instead of several partial ones. See
  "Merging split usecases" below.
- `main/DSSAT/build_dashboard_store.R` - the script run in step 1 above.
  Scans `data/usecases/` for every `*_dashboard_data.RDS` file already produced by
  the pipeline's `build_crop_dashboard()` (see
  `get_pdate_cultivar_recommendation.R`) and consolidates them into the
  combined store at
  `data/usecases/results/dashboard_store/`. Re-run it any time new or
  updated usecase results should show up in the dashboard - it always
  rebuilds the whole store from scratch. Takes an optional `--usecases` flag
  to restrict which usecase directories are ingested (see "Excluding
  old/incomplete usecases" below).
  Every successful run also repackages the laptop bundle (next bullet) from
  the store just built, so the two never drift apart - pass `--skip-bundle`
  to build only the store.
- `main/DSSAT/dashboard_app/app.R` - the Shiny app itself, launched in step
  2 above. Reads the data store plus this repo's cached country boundaries
  (`data/countries/<ISO3>/admin/gadm/`) to draw country outlines, and
  `maps`-package data for the world/lake background - all offline, no map
  tiles or other network calls at runtime.
- `main/DSSAT/package_dashboard_app_for_laptop.R` - packaging script,
  called automatically by `build_dashboard_store.R` above (also runnable on
  its own, e.g. to re-zip without rebuilding the store). Bundles `app.R`,
  the data store, and only the country boundaries actually needed into
  one self-contained, downloadable folder and `.zip` at
  `data/usecases/results/dashboard_app_bundle{,.zip}`, for running on a
  laptop with no access to this server or the rest of the repo.

The dashboard shows, per country/crop/usecase: for every simulated grid
point, the DSSAT-simulated cultivar/planting-date combinations ranked by
yield (Rank 1 = best-performing at that point), with filters for cultivar,
recommendation rank, and cropland-mask membership. See the app's own "About
this data" panel for the full explanation of what's simulated and the
season-onset assumption behind the planting-date candidates.

## Merging split usecases

Both scripts below are standalone and run independently of
`run_dssat_pipeline.R` - nothing invokes them automatically.

If a country's results are split across several separately-run usecases
(e.g. Nigeria's maize, simulated as four usecases -
`useCase_Nigeria_full_apr/_jul/_jun/_mar` - each covering a different,
non-overlapping set of states with the planting month appropriate for that
region), merge them into one usecase before building the dashboard store:

```r
Rscript main/DSSAT/merge_usecases.R \
  --country Nigeria \
  --usecases full_apr,full_jul,full_jun,full_mar \
  --merged-name full
```

This reads each source usecase's raw per-pixel results (not their
`transform/` working files - nothing downstream needs those), combines them,
and re-derives the ranked dashboard extract, `dashboard_data.RDS`, and HTML
dashboard for a brand-new `useCase_Nigeria_full` directory - the source
usecases are left untouched on disk. Ranking is recomputed per pixel, so
this is correct whether or not the source usecases' locations overlap.

### Excluding old/incomplete usecases

Once a merged usecase exists, exclude its now-superseded sources from the
dashboard store (without deleting them - they stay on disk as raw
provenance) with `build_dashboard_store.R --usecases`, naming exactly the
usecase directories (basenames under `data/usecases/`) you want included:

```r
Rscript main/DSSAT/build_dashboard_store.R --usecases \
  useCase_Nigeria_full,useCase_Kenya_full,useCase_Malawi_full,useCase_Mozambique_full,useCase_Rwanda_rab,useCase_Rwanda_august_init,useCase_Zambia_full
```

Omit `--usecases` to ingest every usecase found under `data/usecases/`
(current default behavior, still skipping dev-only `*test*` usecases unless
`--include-test` is also given).

## Running it on a laptop (portable bundle, no server/internet needed)

Step 1 above already wrote `data/usecases/results/dashboard_app_bundle.zip`
- no separate packaging step needed. (To re-zip without rebuilding the
store, e.g. after only editing `app.R`, run
`Rscript main/DSSAT/package_dashboard_app_for_laptop.R` directly.)

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
