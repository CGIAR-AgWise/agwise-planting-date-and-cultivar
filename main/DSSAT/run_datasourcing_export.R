###############################################################################
# Script: run_datasourcing_export.R
# Purpose: For usecases with no pre-staged DSSAT export yet, generate one by
#          calling into the sibling agwise-datasourcing repo's own data
#          pipeline (agwise_data package / agwise-data CLI) - NOT this
#          repo's own forecast-download pipeline (main/Forecast). The
#          resulting Processed/products/<...> folder is then picked up by
#          import_prestaged_dssat_files.R exactly as if it had been staged
#          manually.
#
# Author: Alvaro Carmona-Cabrero
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
###############################################################################


### Generate one zone's pre-staged DSSAT export via agwise-datasourcing
#
# Sources agwise-datasourcing's R wrapper (r/agwise_data.R), which shells out
# to the `agwise-data` CLI installed in its own conda env - no reticulate/
# conda-activate wiring needed here, just pointing AGWISE_DATA_BIN at that
# env's binary. Builds an AOI point grid for the zone (ad_make_grid) then
# runs the bias-corrected SEAS5-to-DSSAT export (ad_forecast_to_dssat),
# writing directly into the same Processed/products/<ISO3>_<Zone>_forecast
# <year>_<usecase> layout resolve_prestaged_dssat_source_dir() already knows
# how to find. Idempotent: skips generation (message only) if that folder
# already has EXTE#### sites, so re-running a usecase never re-downloads.
generate_prestaged_dssat_via_datasourcing <- function(
    complete_usecase, repo_root,
    datasourcing_repo_dir = "~/agwise-datasourcing/code/data_sourcing",
    datasourcing_bin = "~/agwise-datasourcing/envs/agwise_data/bin/agwise-data",
    datasourcing_products_dir = "~/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Processed/products",
    res_km = 5, calib_years = 1993:2016, ensemble = "mean") {

  if (!nzchar(Sys.getenv("AGWISE_DATA_BIN"))) {
    Sys.setenv(AGWISE_DATA_BIN = path.expand(datasourcing_bin))
  }
  source(file.path(path.expand(datasourcing_repo_dir), "r", "agwise_data.R"))

  # forecast_init_from_usecase() lives in usecases/00_usecase_helpers.R,
  # which isn't guaranteed to already be sourced by the caller.
  if (!exists("forecast_init_from_usecase", mode = "function")) {
    source(file.path(repo_root, "usecases", "00_usecase_helpers.R"))
  }
  init <- forecast_init_from_usecase(complete_usecase)

  for (zone in complete_usecase$zones) {
    out_dir <- file.path(
      path.expand(datasourcing_products_dir),
      paste0(
        complete_usecase$country_code, "_", zone, "_forecast",
        complete_usecase$season_year, "_", complete_usecase$use_case_name))

    existing_exte <- if (dir.exists(out_dir)) {
      list.files(out_dir, pattern = "^EXTE", full.names = FALSE)
    } else {
      character(0)
    }
    if (length(existing_exte) > 0) {
      message(
        "Pre-staged export already present in ", out_dir, " (",
        length(existing_exte), " sites) - skipping datasourcing generation.")
      next
    }

    message(
      "Generating DSSAT export via agwise-datasourcing for zone: ", zone,
      " (init_month=", init$month, ", forecast_year=", init$year, ")")

    grid <- ad_make_grid(
      country = complete_usecase$country_name, admin_level = 1,
      admin_name = zone, res_km = res_km, tag_admin_level = 1)

    ad_forecast_to_dssat(
      points = grid, init_month = init$month, forecast_year = init$year,
      calib_years = calib_years, country = complete_usecase$country_name,
      admin_level = 1, admin_name = zone,
      country_name = complete_usecase$country_code,
      out_dir = out_dir, ensemble = ensemble)
  }
  invisible(NULL)
}
