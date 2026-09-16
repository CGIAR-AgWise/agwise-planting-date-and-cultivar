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


### Call agwise-data forecast-to-dssat directly, with stall detection and retries
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
# IMPORTANT: this used to be a flat wall-clock timeout (kill after N seconds
# elapsed, no matter what) - which is wrong, because it can't tell a genuine
# 0%-CPU deadlock apart from a slow-but-actively-progressing fetch, and will
# kill the latter just as readily as the former. Confirmed live: a real
# 4-variable whole-country fetch (Mozambique, 2026-09-05) was killed 3 times
# in a row by a 3600s wall-clock timeout while it was still making real
# progress (each kill discarded whatever variable was mid-fetch, since only
# a fully-finished variable gets written to the on-disk cache) - net effect
# was 3 wasted hours and zero output, for a fetch that just needed more time,
# not a restart.
#
# First fix attempt (output silence instead of wall-clock) was ALSO wrong for
# the same underlying reason: a process can go silent while still doing real,
# CPU-bound work with no per-step logging (e.g. opening/decompressing 24
# years of local calibration files, exactly the step the documented deadlock
# happens in - see below) - silence alone doesn't prove it's stuck. The
# documented deadlock's own signature is specifically "wchan=futex_wait_
# queue_me, 0% CPU" - i.e. CPU activity, not output, is the real signal.
#
# Fixed to require BOTH: no new output AND ~0% CPU (summed across the child
# and any of its own child processes) for `stall_secs` straight (default 20
# minutes) before treating it as a genuine stall. A process that's silently
# burning CPU is left alone no matter how long it takes; only a process
# that's both silent AND idle - matching the documented deadlock exactly -
# gets killed and retried. A real (non-stall) CLI failure still stops
# immediately, matching ad_run()'s own behavior.
cpu_pct_tree <- function(pid) {
  children <- suppressWarnings(system2("pgrep", c("-P", as.character(pid)), stdout = TRUE, stderr = FALSE))
  pids <- c(pid, as.integer(children))
  cpu <- suppressWarnings(system2(
    "ps", c("-o", "%cpu=", "-p", paste(pids, collapse = ",")),
    stdout = TRUE, stderr = FALSE))
  vals <- suppressWarnings(as.numeric(trimws(cpu)))
  sum(vals, na.rm = TRUE)
}

# Kill exactly this call's process tree (the launched pid and its own
# children) - NOT a blanket `pkill -f <command substring>`, which would also
# kill any OTHER concurrently-running call with the same command string
# (confirmed live: this collateral-killed a second, healthy, unrelated
# usecase run during testing on 2026-09-05).
kill_process_tree <- function(pid) {
  children <- suppressWarnings(system2("pgrep", c("-P", as.character(pid)), stdout = TRUE, stderr = FALSE))
  for (p in c(as.integer(children), pid)) {
    system2("kill", c("-9", as.character(p)), stdout = FALSE, stderr = FALSE)
  }
}

ad_forecast_to_dssat_with_retry <- function(
    points, init_month, forecast_year, calib_years, bbox, country_name,
    out_dir, ensemble = "mean", stall_secs = 1200, poll_secs = 20,
    cpu_active_pct = 1.0, max_attempts = 3) {

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
    out_file <- tempfile(fileext = ".log")
    # Launch in the background via a shell so we can capture the child's
    # own PID (`$!`) - system2(..., wait = FALSE) doesn't hand back a PID,
    # and R's own timeout mechanisms can't interrupt a system2() call
    # already blocked in the OS waitpid() syscall, so polling a real PID
    # from outside is the only reliable way to watch (and, if needed, kill)
    # a specific run without touching any other concurrent zone's call.
    launch_cmd <- paste0(
      shQuote(ad_bin()), " ", paste(shQuote(args), collapse = " "),
      " > ", shQuote(out_file), " 2>&1 & echo $!")
    pid <- as.integer(trimws(system(launch_cmd, intern = TRUE)))

    # Stream new output as it's polled (via message(), so it flows through
    # to this call's own stderr exactly as it would have with the old
    # direct system2(stdout=TRUE) approach) - preserves live progress
    # visibility (CDS status lines, download progress, etc.) instead of
    # only surfacing output after the fact. Output growth and CPU activity
    # are both "not stalled" signals - either one resets the stall clock.
    last_byte_size <- 0
    lines_streamed <- 0
    last_change <- Sys.time()
    stalled <- FALSE
    repeat {
      Sys.sleep(poll_secs)
      alive <- identical(
        system2("kill", c("-0", as.character(pid)), stdout = FALSE, stderr = FALSE), 0L)
      if (!alive) break

      cur_byte_size <- suppressWarnings(file.info(out_file)$size)
      output_grew <- !is.na(cur_byte_size) && cur_byte_size > last_byte_size
      if (output_grew) {
        new_lines <- readLines(out_file, warn = FALSE)
        if (length(new_lines) > lines_streamed) {
          message(paste(new_lines[(lines_streamed + 1):length(new_lines)], collapse = "\n"))
          lines_streamed <- length(new_lines)
        }
        last_byte_size <- cur_byte_size
      }

      cpu_active <- cpu_pct_tree(pid) > cpu_active_pct
      if (output_grew || cpu_active) {
        last_change <- Sys.time()
      }
      if (as.numeric(Sys.time() - last_change, units = "secs") > stall_secs) {
        stalled <- TRUE
        break
      }
    }

    if (stalled) {
      message(
        "  agwise-data forecast-to-dssat produced no output AND no CPU ",
        "activity for ", stall_secs, "s (attempt ", attempt, "/", max_attempts,
        ") - treating as a genuine stall, killing and retrying...")
      kill_process_tree(pid)
      Sys.sleep(2)
      next
    }

    out <- readLines(out_file, warn = FALSE)
    json_lines <- grep("^\\{", out, value = TRUE)
    if (length(json_lines) > 0) {
      res <- jsonlite::fromJSON(tail(json_lines, 1), simplifyDataFrame = FALSE)
      if (isTRUE(res$ok)) {
        return(invisible(NULL))
      }
    }
    stop("agwise-data forecast-to-dssat failed (attempt ", attempt, "/", max_attempts,
         "). Output:\n", paste(utils::tail(out, 20), collapse = "\n"))
  }
  stop("agwise-data forecast-to-dssat stalled (no output for ", stall_secs, "s) ",
       max_attempts, " times in a row for out_dir=", out_dir, " - giving up.")
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
  buffer_deg <- 0.5

  zone_out_dir <- function(zone) file.path(
    path.expand(datasourcing_products_dir),
    paste0(
      complete_usecase$country_code, "_", zone, "_forecast",
      complete_usecase$season_year, "_", complete_usecase$use_case_name))

  # --- Pass 1: which zones still need generating, and their (cheap,
  # offline - no network calls) point grids ---
  pending_zones <- character(0)
  grids <- list()
  for (zone in complete_usecase$zones) {
    out_dir <- zone_out_dir(zone)
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
    pending_zones <- c(pending_zones, zone)
    grids[[zone]] <- ad_make_grid(
      country = complete_usecase$country_name, admin_level = 1,
      admin_name = zone, res_km = res_km, tag_admin_level = 1)
  }

  if (length(pending_zones) == 0) {
    message("All zones already pre-staged - nothing to generate.")
    return(invisible(NULL))
  }

  # --- One shared bbox for the whole country: union of every PENDING
  # zone's point-grid extent, with the same buffer applied once. Passing
  # this SAME bbox to every zone's forecast-to-dssat call (rather than a
  # fresh bbox per zone, as before) collapses them onto ONE CDS/SEAS5
  # cache domain in the external CLI - its cache key is derived only from
  # the (rounded) bbox, never from the points list, so the first zone
  # processed pays the real CDS fetch and every later zone in this run
  # becomes a cache hit. `points`/`out_dir` stay per-zone below, so the
  # EXTE#### output layout (admin-level structure) is unaffected. For a
  # single-zone usecase this union is bit-for-bit identical to the old
  # per-zone bbox.
  #
  # Pass an explicit bbox (rather than country/admin_name) for the same
  # reason as before: admin_name-based clipping fails with "NoDataInBounds"
  # for at least one real admin unit (Zambia's Lusaka province) despite its
  # geometry being valid and non-degenerate - a bug in agwise-datasourcing's
  # own clip_geometry() domain resolution, not a real data gap (the
  # identical request via --bbox succeeds). A bbox is always a superset of
  # the admin polygon(s) it's derived from, and the final per-site values
  # only depend on which grid cell each point lands in, so this remains a
  # strictly safe substitution.
  all_lon <- unlist(lapply(grids[pending_zones], `[[`, "lon"))
  all_lat <- unlist(lapply(grids[pending_zones], `[[`, "lat"))
  shared_bbox <- c(
    min(all_lon) - buffer_deg, min(all_lat) - buffer_deg,
    max(all_lon) + buffer_deg, max(all_lat) + buffer_deg)

  # --- Pass 2: actually generate, same shared_bbox, own grid/out_dir ---
  for (zone in pending_zones) {
    message(
      "Generating DSSAT export via agwise-datasourcing for zone: ", zone,
      " (init_month=", init$month, ", forecast_year=", init$year, ")")

    ad_forecast_to_dssat_with_retry(
      points = grids[[zone]], init_month = init$month,
      forecast_year = init$year, calib_years = calib_years,
      bbox = shared_bbox, country_name = complete_usecase$country_code,
      out_dir = zone_out_dir(zone), ensemble = ensemble)
  }
  invisible(NULL)
}
