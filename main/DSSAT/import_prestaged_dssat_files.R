###############################################################################
# Script: import_prestaged_dssat_files.R
# Purpose: For usecases whose weather/soil files were prepared by another
#          pipeline (e.g. agwise-datasourcing) rather than generated here by
#          readGeo_CM_zone.R, locate and stage those already-DSSAT-formatted
#          files into this repo's usual transform/DSSAT/AOI layout, and
#          generate the per-site onset_planting_dates.RDS Step 2 needs.
#
# Author: Alvaro Carmona-Cabrero
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
###############################################################################


### Locate the exported product folder for one country/zone/season/usecase
#
# Two naming conventions have been observed among agwise-datasourcing's
# DSSAT-ready exports: "{ISO3}_{Zone}_forecast{year}_{usecase}" (Zambia,
# Malawi, Mozambique) and "{ISO3}_ADM1_{Zone}_forecast{year}_{usecase}"
# (Kenya). Both are tried, in that order; neither is assumed correct without
# checking the filesystem.
resolve_prestaged_dssat_source_dir <- function(
    country_code, zone, season_year, use_case_name,
    datasourcing_products_dir = "~/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Processed/products") {

  candidate_names <- c(
    paste0(country_code, "_", zone, "_forecast", season_year, "_", use_case_name),
    paste0(country_code, "_ADM1_", zone, "_forecast", season_year, "_", use_case_name)
  )
  candidate_paths <- file.path(datasourcing_products_dir, candidate_names)

  found <- candidate_paths[dir.exists(candidate_paths)]
  if (length(found) == 0) {
    stop(
      "No pre-staged DSSAT export found for country_code='", country_code,
      "', zone='", zone, "', season_year=", season_year,
      ", use_case_name='", use_case_name, "'.\n",
      "Tried:\n  ", paste(candidate_paths, collapse = "\n  "), "\n",
      "Available in ", datasourcing_products_dir, ":\n  ",
      paste(list.files(datasourcing_products_dir), collapse = "\n  ")
    )
  }
  found[[1]]
}


### Copy one zone's per-site EXTE#### weather/soil folders into this repo
#
# Only WHTE####.WTH and SOIL.SOL are copied - Jupyter's stray
# .ipynb_checkpoints/ artifacts (observed in at least one prior export) are
# excluded. Idempotent: if target_dir already has as many EXTE#### folders
# as source_dir, the copy is skipped (existing onset dates, if any, are
# preserved rather than needlessly redone). force_weather_refresh bypasses
# that skip to overwrite .WTH/.SOL in place (e.g. a lead_months change) -
# .MZX (FILEX) files already in target_dir are never matched by the copy
# pattern, so they survive untouched either way.
stage_prestaged_dssat_zone <- function(source_dir, target_dir, force_weather_refresh = FALSE) {
  source_exte <- list.files(source_dir, pattern = "^EXTE", full.names = FALSE)
  if (length(source_exte) == 0) {
    stop("No EXTE#### folders found in source dir: ", source_dir)
  }

  if (dir.exists(target_dir)) {
    if (!force_weather_refresh) {
      existing_exte <- list.files(target_dir, pattern = "^EXTE", full.names = FALSE)
      if (length(existing_exte) >= length(source_exte)) {
        message(
          "Pre-staged files already present in ", target_dir, " (",
          length(existing_exte), " sites) - skipping copy.")
        return(invisible(target_dir))
      }
    }
  } else {
    dir.create(target_dir, recursive = TRUE)
  }

  message(
    "Copying ", length(source_exte), " site(s) from ", source_dir,
    " to ", target_dir,
    if (force_weather_refresh) " (forced weather-only refresh, FILEX preserved)" else "", "...")
  for (exte_name in source_exte) {
    from_dir <- file.path(source_dir, exte_name)
    to_dir <- file.path(target_dir, exte_name)
    if (!dir.exists(to_dir)) dir.create(to_dir, recursive = TRUE)
    site_files <- list.files(from_dir, pattern = "\\.(WTH|SOL)$", full.names = TRUE)
    file.copy(site_files, to_dir, overwrite = TRUE)
  }
  invisible(target_dir)
}


### Generate onset_planting_dates.RDS for every site in a staged zone
#
# Reuses get_agronomic_onset_pdates() (helpers_readGeo_CM_zone.R) unmodified,
# fed by the real RAIN/DATE series parsed out of each site's own WHTE####.WTH
# file, so the real onset-detection algorithm runs on real data - nothing is
# fabricated. DSSAT::read_wth() misparses this on-disk 4-digit-year DATE
# format (e.g. "2026183") by exactly 100 years - confirmed against both
# this repo's own generated files and imported ones - so the correction is
# applied before handing dates to the onset function. Idempotent: sites that
# already have onset_planting_dates.RDS are left untouched.
generate_onset_dates_for_zone <- function(
    target_dir, season_start_month, zone, mc_cores = 4) {

  exte_dirs <- sort(list.files(target_dir, pattern = "^EXTE", full.names = FALSE))
  pending <- exte_dirs[!file.exists(file.path(target_dir, exte_dirs, "onset_planting_dates.RDS"))]

  if (length(pending) == 0) {
    message("Onset planting dates already present for all sites in ", target_dir)
    return(invisible(NULL))
  }

  message("Generating onset planting dates for ", length(pending), " site(s) in ", target_dir, "...")

  process_one <- function(exte_name) {
    i <- as.integer(gsub("[^0-9]", "", exte_name))
    pathOUT <- file.path(target_dir, exte_name)
    wth_file <- file.path(pathOUT, sprintf("WHTE%04d.WTH", i))

    wth <- tryCatch(DSSAT::read_wth(wth_file), error = function(e) NULL)
    if (is.null(wth)) {
      return(paste0("FAILED read_wth: ", exte_name))
    }

    wth_date <- as.Date(wth$DATE) + lubridate::years(100)
    Rainfall_i <- data.frame(Date = wth_date, RAIN = as.numeric(wth$RAIN))

    tryCatch({
      get_agronomic_onset_pdates(
        Rainfall_i = Rainfall_i, target_month = season_start_month,
        pathOUT = pathOUT, n_alternative_pdates = 7, spacing = 7,
        i = i, zone = zone)
      "OK"
    }, error = function(e) paste0("FAILED onset: ", exte_name, " - ", conditionMessage(e)))
  }

  results <- unlist(parallel::mclapply(pending, process_one, mc.cores = mc_cores))
  failed <- results[results != "OK"]
  if (length(failed) > 0) {
    # A site failing here (typically FAILED read_wth: an empty placeholder
    # directory - agwise-datasourcing skips sites with no valid weather
    # data at generation time, but the source export's EXTE#### numbering
    # can be non-contiguous as a result, e.g. jumping from EXTE0299 to
    # EXTE0301 - while stage_prestaged_dssat_zone() still creates a
    # contiguous working range) must not abort the whole zone. Logged, not
    # fatal: that site simply has no onset_planting_dates.RDS afterward,
    # and Step 2 (dssat.expfile()) already skips a site gracefully when
    # its onset file is missing rather than crashing its whole batch.
    warning(
      length(failed), " of ", length(pending),
      " site(s) failed onset-date generation in ", target_dir,
      " - skipped, will be skipped again at FILEX creation:\n  ",
      paste(head(failed, 10), collapse = "\n  "), call. = FALSE
    )
  }
  invisible(NULL)
}


### Spin-up month for lead_months = 0
#
# FILEX starts the simulation one month before the first planting date, but
# a lead-0 forecast's WTH starts on the init date. That month is taken from
# the previous month's init forecast (same bias correction and ensemble
# reduction), which a monthly schedule has usually already exported; if not,
# it's generated through agwise-datasourcing first.

# Text-level WTH parse (read_wth() shifts 4-digit-year dates by 100 years)
parse_wth_file <- function(wth_file) {
  lines <- readLines(wth_file, warn = FALSE)
  date_hdr <- grep("^@ +DATE", lines)[1]
  site <- strsplit(trimws(lines[grep("^@ +INSI", lines)[1] + 1]), " +")[[1]]
  rows <- lines[(date_hdr + 1):length(lines)]
  rows <- rows[nzchar(trimws(rows))]
  list(
    lines = lines, date_hdr = date_hdr, rows = rows,
    dates = as.Date(sub(" .*", "", trimws(rows)), format = "%Y%j"),
    key = sprintf("%.3f_%.3f", as.numeric(site[2]), as.numeric(site[3])))
}

# Site coordinate keys of every WTH in a folder, read from the headers only
wth_site_keys <- function(dir) {
  vapply(Sys.glob(file.path(dir, "EXTE*", "WHTE*.WTH")), function(f) {
    head_lines <- readLines(f, n = 15, warn = FALSE)
    site <- strsplit(trimws(head_lines[grep("^@ +INSI", head_lines)[1] + 1]), " +")[[1]]
    sprintf("%.3f_%.3f", as.numeric(site[2]), as.numeric(site[3]))
  }, character(1), USE.NAMES = FALSE)
}

# Init date of an export: manifest.json when present, else its first WTH date
export_init_date <- function(export_dir) {
  manifest <- file.path(export_dir, "manifest.json")
  if (file.exists(manifest)) {
    p <- jsonlite::fromJSON(manifest)$parameters
    if (!is.null(p$init_month) && !is.null(p$forecast_year)) {
      return(as.Date(sprintf("%d-%02d-01", as.integer(p$forecast_year), as.integer(p$init_month))))
    }
  }
  wth <- Sys.glob(file.path(export_dir, "EXTE*", "WHTE*.WTH"))
  if (length(wth) == 0) return(as.Date(NA))
  first_date <- parse_wth_file(wth[[1]])$dates[1]
  lubridate::floor_date(first_date, "month")
}

resolve_spinup_source_dir <- function(complete_usecase, zone, products_dir, repo_root, target_dir) {
  init <- forecast_init_from_usecase(complete_usecase)
  prev_init <- as.Date(sprintf("%d-%02d-01", init$year, init$month)) %m-% months(1)

  find_exports <- function() {
    dirs <- Sys.glob(file.path(
      path.expand(products_dir),
      paste0(complete_usecase$country_code, c("_", "_ADM1_"), zone, "_forecast*")))
    dirs <- dirs[dir.exists(dirs)]
    dirs[vapply(dirs, function(d) isTRUE(export_init_date(d) == prev_init), logical(1))]
  }

  found <- find_exports()
  if (length(found) == 0) {
    if (!isTRUE(complete_usecase$generate_dssat_via_datasourcing)) {
      stop("No ", format(prev_init, "%Y-%m"), " init export found for spin-up of zone '", zone,
           "' in ", products_dir, " and generate_dssat_via_datasourcing is FALSE.")
    }
    message("No ", format(prev_init, "%Y-%m"), " init export for spin-up of zone '", zone,
            "' - generating it via agwise-datasourcing...")
    generate_prestaged_dssat_via_datasourcing(
      complete_usecase = complete_usecase, repo_root = repo_root,
      datasourcing_products_dir = products_dir, res_km = complete_usecase$resolution_km,
      init = list(year = lubridate::year(prev_init), month = lubridate::month(prev_init)),
      # Same "<mon>_init" name a monthly usecase uses, so either run reuses it
      out_suffix = paste0(tolower(month.abb[lubridate::month(prev_init)]), "_init"))
    found <- find_exports()
    if (length(found) == 0) stop("Spin-up export generation did not produce a usable folder for zone '", zone, "'.")
  }

  # Several exports of the same init can exist on different grids (e.g. a
  # 10 km "full" and a 5 km "sep_init"): prefer the one covering the most
  # target sites, then one with a manifest, then the newest
  target_keys <- wth_site_keys(target_dir)
  coverage <- vapply(found, function(d) mean(target_keys %in% wth_site_keys(d)), numeric(1))
  has_manifest <- file.exists(file.path(found, "manifest.json"))
  ord <- order(-coverage, !has_manifest, -as.numeric(file.mtime(found)))
  message(sprintf(
    "Spin-up weather for zone '%s' from: %s (covers %.0f%% of sites)",
    zone, found[[ord[1]]], 100 * coverage[[ord[1]]]))
  found[[ord[1]]]
}

# Prepend spin-up rows (window_start up to the day before each site's first
# WTH date), matching sites by coordinates since EXTE numbering can have gaps
prepend_spinup_weather <- function(target_dir, spinup_dir, window_start) {
  spin <- lapply(Sys.glob(file.path(spinup_dir, "EXTE*", "WHTE*.WTH")), parse_wth_file)
  spin_keys <- vapply(spin, `[[`, character(1), "key")

  n_spliced <- 0L
  n_already <- 0L
  not_spliced <- character(0)
  for (f in Sys.glob(file.path(target_dir, "EXTE*", "WHTE*.WTH"))) {
    w <- parse_wth_file(f)
    if (w$dates[1] <= window_start) {
      n_already <- n_already + 1L
      next
    }
    j <- match(w$key, spin_keys)
    s <- if (is.na(j)) NULL else spin[[j]]
    keep <- if (is.null(s)) logical(0) else s$dates >= window_start & s$dates < w$dates[1]
    contiguous <- any(keep) && min(s$dates[keep]) == window_start &&
      max(s$dates[keep]) == w$dates[1] - 1 &&
      identical(trimws(s$lines[s$date_hdr]), trimws(w$lines[w$date_hdr]))
    if (!contiguous) {
      not_spliced <- c(not_spliced, basename(dirname(f)))
      next
    }
    writeLines(c(w$lines[seq_len(w$date_hdr)], s$rows[keep], w$rows), f)
    n_spliced <- n_spliced + 1L
  }

  message(sprintf(
    "Spin-up weather from %s in %s: %d site(s) spliced, %d already covered, %d not spliced",
    window_start, target_dir, n_spliced, n_already, length(not_spliced)))
  if (length(not_spliced) > 0) {
    warning(
      length(not_spliced), " site(s) got no spin-up weather (no matching point or ",
      "incomplete coverage) - their simulation start will be clamped to the first ",
      "weather date:\n  ", paste(head(not_spliced, 10), collapse = "\n  "), call. = FALSE)
  }
  invisible(n_spliced)
}


### Entry point: stage every zone's pre-built DSSAT files for one usecase
#
# Called from run_dssat_pipeline.R's Step 1 when skip_weather_soil_creation
# is TRUE. Only ever needs to stage varietyids[[1]] - run_dssat_pipeline.R's
# existing copy_WTH_SOIL_data_for_variety() call (unconditional, outside the
# skip_weather_soil_creation branch) already replicates that data to the
# usecase's other varieties. Safe to call unconditionally: every step it
# calls is idempotent.
import_prestaged_dssat_files <- function(
    complete_usecase, repo_root,
    datasourcing_products_dir = "~/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Processed/products") {

  products_dir <- complete_usecase$dssat_source_products_dir
  if (is.null(products_dir)) products_dir <- datasourcing_products_dir

  varietyid <- complete_usecase$varietyids[[1]]
  path.to.extdata <- create_extdata_path(
    project_root = repo_root, country = complete_usecase$country_name,
    useCaseName = complete_usecase$use_case_name, Crop = complete_usecase$crop,
    varietyid = varietyid, AOI = complete_usecase$aoi)

  # reuse_existing_filex doubles as "this is a weather-refresh rerun": Step 2
  # already skips regenerating FILEX when it's set, so staging must likewise
  # force fresh .WTH/.SOL in rather than skipping on folder-count match.
  force_weather_refresh <- isTRUE(complete_usecase$reuse_existing_filex)

  # Only lead-0 forecasts start on the init date and need a spin-up month
  needs_spinup <- identical(as.integer(complete_usecase$lead_months %||% 1L), 0L)
  if (needs_spinup) {
    if (!exists("forecast_init_from_usecase", mode = "function")) {
      source(file.path(repo_root, "usecases", "00_usecase_helpers.R"))
    }
    spinup_window_start <- as.Date(sprintf(
      "%d-%02d-01", as.integer(complete_usecase$season_year),
      as.integer(complete_usecase$season_start_month))) %m-% months(1)
  }

  for (zone in complete_usecase$zones) {
    message("Importing pre-staged DSSAT files for zone: ", zone)
    source_dir <- resolve_prestaged_dssat_source_dir(
      country_code = complete_usecase$country_code, zone = zone,
      season_year = complete_usecase$season_year,
      use_case_name = complete_usecase$dssat_source_use_case_name %||%
        complete_usecase$use_case_name,
      datasourcing_products_dir = products_dir)

    target_dir <- file.path(path.to.extdata, zone)
    stage_prestaged_dssat_zone(
      source_dir = source_dir, target_dir = target_dir,
      force_weather_refresh = force_weather_refresh)
    if (needs_spinup) {
      spinup_dir <- resolve_spinup_source_dir(
        complete_usecase = complete_usecase, zone = zone,
        products_dir = products_dir, repo_root = repo_root, target_dir = target_dir)
      prepend_spinup_weather(
        target_dir = target_dir, spinup_dir = spinup_dir, window_start = spinup_window_start)
    }
    generate_onset_dates_for_zone(
      target_dir = target_dir, season_start_month = complete_usecase$season_start_month,
      zone = zone)
  }
  invisible(NULL)
}
