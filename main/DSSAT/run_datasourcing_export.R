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


### Call agwise-data forecast-to-dssat directly, with a timeout and retries
#
# ad_forecast_to_dssat() (agwise_data.R) shells out via a plain system2()
# with no timeout, so a hang inside the CLI blocks forever. Confirmed live
# during Kenya's 47-zone run (2026-08-16/17): the CLI's calibration read
# step (opening all calib_years' CHIRPS files before any per-site output is
# written) deadlocks intermittently - wchan=futex_wait_queue_me, 0% CPU,
# recurring roughly every 5-10 zones, always before any EXTE#### output
# exists for that zone (confirmed on disk each time) - so a kill at this
# point never leaves partial/corrupt output behind for the idempotent
# skip-check above to mistake for a finished zone.
#
# R's own timeout mechanisms (setTimeLimit/withTimeout) cannot interrupt a
# system2() call already blocked in the OS waitpid() syscall - the timeout
# has to be passed into system2() itself (supported since R 3.5). This
# reimplements the same CLI call ad_forecast_to_dssat() makes (identical
# argument set) so that timeout is available, then retries on timeout by
# killing the stuck process tree and trying again - a real (non-timeout)
# CLI failure still stops immediately, matching ad_run()'s own behavior.
ad_forecast_to_dssat_with_retry <- function(
    points, init_month, forecast_year, calib_years, bbox, country_name,
    out_dir, ensemble = "mean", timeout_secs = 3600, max_attempts = 3) {

  points_csv <- points
  if (is.data.frame(points)) {
    points_csv <- tempfile(fileext = ".csv")
    utils::write.csv(points, points_csv, row.names = FALSE)
  }
  args <- c("forecast-to-dssat", "--points", points_csv,
            "--init-month", as.character(init_month),
            "--forecast-year", as.character(forecast_year),
            "--calib-years", paste0(min(calib_years), ":", max(calib_years)),
            "--ensemble", ensemble,
            "--out-dir", out_dir,
            "--country-name", country_name,
            "--bbox", paste(bbox, collapse = ","))

  for (attempt in seq_len(max_attempts)) {
    timed_out <- FALSE
    out <- withCallingHandlers(
      system2(ad_bin(), shQuote(args), stdout = TRUE, stderr = "", timeout = timeout_secs),
      warning = function(w) {
        if (grepl("timed out", conditionMessage(w))) timed_out <<- TRUE
        invokeRestart("muffleWarning")
      })

    if (timed_out) {
      message(
        "  agwise-data forecast-to-dssat timed out after ", timeout_secs,
        "s (attempt ", attempt, "/", max_attempts, ") - killing stuck process(es) and retrying...")
      system2("pkill", c("-9", "-f", shQuote("agwise-data forecast-to-dssat")),
               stdout = FALSE, stderr = FALSE)
      Sys.sleep(2)
      next
    }

    status <- attr(out, "status")
    json_lines <- grep("^\\{", out, value = TRUE)
    if (length(json_lines) > 0) {
      res <- jsonlite::fromJSON(tail(json_lines, 1), simplifyDataFrame = FALSE)
      if (isTRUE(res$ok) && (is.null(status) || status == 0)) {
        return(invisible(NULL))
      }
    }
    stop("agwise-data forecast-to-dssat failed (attempt ", attempt, "/", max_attempts,
         "). Output:\n", paste(utils::tail(out, 20), collapse = "\n"))
  }
  stop("agwise-data forecast-to-dssat timed out ", max_attempts,
       " times in a row (", timeout_secs, "s each) for out_dir=", out_dir, " - giving up.")
}


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
    # Own clone (not the shared ~/agwise-datasourcing install) so pipeline-
    # side fixes to the R wrapper (e.g. quoting multi-word admin_name
    # values like "Cabo Delgado" before they hit system2()) land without
    # touching shared files. The CLI binary itself is still the shared,
    # already-installed conda env - only the R source differs.
    datasourcing_repo_dir = "~/Alvaro_repos/data_sourcing",
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

    # Pass an explicit bbox (derived from the grid's own point extent, with
    # a small buffer - the same convention agwise-datasourcing's own code
    # uses when no region is given at all) rather than country/admin_name.
    # Confirmed by direct reproduction: admin_name-based clipping fails with
    # "NoDataInBounds" for at least one real admin unit (Zambia's Lusaka
    # province) despite its geometry being valid and non-degenerate - a bug
    # in agwise-datasourcing's own clip_geometry() domain resolution, not a
    # real data gap (the identical request via --bbox succeeds). A bbox is
    # always a superset of the admin polygon it's derived from, and the
    # final per-site values only depend on which grid cell each point
    # lands in, so this is a strictly safe substitution - it never changes
    # what data ends up at any site, only sidesteps the buggy polygon clip.
    buffer_deg <- 0.5
    bbox <- c(
      min(grid$lon) - buffer_deg, min(grid$lat) - buffer_deg,
      max(grid$lon) + buffer_deg, max(grid$lat) + buffer_deg)

    ad_forecast_to_dssat_with_retry(
      points = grid, init_month = init$month, forecast_year = init$year,
      calib_years = calib_years, bbox = bbox,
      country_name = complete_usecase$country_code,
      out_dir = out_dir, ensemble = ensemble)
  }
  invisible(NULL)
}
