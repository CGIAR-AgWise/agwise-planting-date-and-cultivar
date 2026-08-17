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
# preserved rather than needlessly redone).
stage_prestaged_dssat_zone <- function(source_dir, target_dir) {
  source_exte <- list.files(source_dir, pattern = "^EXTE", full.names = FALSE)
  if (length(source_exte) == 0) {
    stop("No EXTE#### folders found in source dir: ", source_dir)
  }

  if (dir.exists(target_dir)) {
    existing_exte <- list.files(target_dir, pattern = "^EXTE", full.names = FALSE)
    if (length(existing_exte) >= length(source_exte)) {
      message(
        "Pre-staged files already present in ", target_dir, " (",
        length(existing_exte), " sites) - skipping copy.")
      return(invisible(target_dir))
    }
  } else {
    dir.create(target_dir, recursive = TRUE)
  }

  message(
    "Copying ", length(source_exte), " site(s) from ", source_dir,
    " to ", target_dir, "...")
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

  for (zone in complete_usecase$zones) {
    message("Importing pre-staged DSSAT files for zone: ", zone)
    source_dir <- resolve_prestaged_dssat_source_dir(
      country_code = complete_usecase$country_code, zone = zone,
      season_year = complete_usecase$season_year,
      use_case_name = complete_usecase$use_case_name,
      datasourcing_products_dir = products_dir)

    target_dir <- file.path(path.to.extdata, zone)
    stage_prestaged_dssat_zone(source_dir = source_dir, target_dir = target_dir)
    generate_onset_dates_for_zone(
      target_dir = target_dir, season_start_month = complete_usecase$season_start_month,
      zone = zone)
  }
  invisible(NULL)
}
