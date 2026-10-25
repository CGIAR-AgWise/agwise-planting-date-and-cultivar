load_dssat_defaults <- function(usecase, repo_root) {
  # Set up all your standard parameters as background fallbacks
  
  crop_code <- get_DSSAT_crop_code(usecase$crop)
  
  dssat_defaults <- list(
    filex_temp          = paste0("PDVAR.", crop_code, "X"),  # Template for this repo
    geneticfiles        = paste0(crop_code, get_DSSAT_crop_submodel(crop_code), "048"),  # Country/crop specific genetic files
    # SMODEL code as registered in this DSSAT install's SIMULATION.CDE (5
    # chars, no version suffix - e.g. "MZCER", matching what the proven-good
    # Maize template already used). Usually matches the geneticfiles prefix,
    # but not always: Wheat's genotype files are WHCER048.* while this
    # install's SIMULATION.CDE registers the model itself as CSCER, not
    # WHCER. Override per-usecase (dssat_model: ...) when they diverge.
    dssat_model         = paste0(crop_code, get_DSSAT_crop_submodel(crop_code)),
    soil_source         = "ISRIC",
    aoi                 = TRUE,
    forecast            = TRUE,
    # Fertilizer modes (at most one TRUE): simple_fertilizer uses the FILEX
    # template's own preset fertilizer; fert_grid_search runs an NPK rate
    # factorial (fert_*_rates); fert_factorial_preset runs every treatment
    # listed in fert_treatments_file and compares them.
    simple_fertilizer     = FALSE,
    fert_grid_search      = FALSE,
    fert_factorial_preset = FALSE,
    fert_N_rates          = NULL,
    fert_P_rates          = 0,
    fert_K_rates          = 0,
    fert_application_dap  = c(0, 42),
    fert_material         = "FE005",
    fert_method           = "AP002",
    fert_depth            = 5,
    fert_treatments_file  = NULL,
    # No soil P/K data in the current soil sources - keep P/K unsimulated
    # unless the soil files support it.
    simulate_P            = FALSE,
    simulate_K            = FALSE,
    # ISRIC AfSoilGrids250m Mehlich-3 P (0-30 cm), used to add soil P to the
    # FILEX when a fertilizer mode is on and SOIL.SOL has no P block.
    soil_p_raster         = "~/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/Soil/soilGrids/af_p_0-30cm_30s.tif",
    # Optional, ranks fertilizer treatments by net return when the
    # treatments file has a cost column.
    crop_price            = NULL,
    season              = 1,
    path_in_zone        = TRUE,
    level2              = NA,
    index_soilwat       = 1,
    id                  = "TLID",
    planting_month_date = NULL,
    harvest_month_date  = NULL,
    planting_window     = 7,
    use_crop_mask       = FALSE,
    build_dashboard     = TRUE,
    skip_weather_soil_creation = FALSE,
    # Only consulted when skip_weather_soil_creation is TRUE - overrides
    # import_prestaged_dssat_files()'s own default products directory for a
    # usecase that needs a non-standard source location.
    dssat_source_products_dir = NULL,
    # Only consulted when skip_weather_soil_creation is TRUE - defaults to
    # TRUE so a usecase needing pre-staged files gets them generated via
    # agwise-datasourcing's own pipeline automatically; safe to leave on
    # even when a matching export already exists on disk, since
    # generate_prestaged_dssat_via_datasourcing() is idempotent (skips
    # generation whenever the target already has EXTE#### sites). Set to
    # FALSE explicitly for a usecase that must only ever import
    # already-staged files and never trigger a fresh generation.
    generate_dssat_via_datasourcing = TRUE,
    # Step 2 (dssat.expfile()) skips any site whose FILEX already exists
    # when TRUE - lets an interrupted run resume mid-zone instead of
    # redoing every already-finished site. Set to FALSE to force every
    # FILEX to be rebuilt regardless of what's on disk - e.g. re-running
    # the same usecase after a newer month's forecast has been released
    # (a different lead_months means different weather, and therefore
    # potentially different onset planting dates and FILEX content, so
    # stale FILEX from the prior forecast vintage should not be reused).
    reuse_existing_filex = TRUE,
    # Site-grid spacing (km) passed to agwise-datasourcing's ad_make_grid()
    # when generate_dssat_via_datasourcing generates a fresh export. Only
    # consulted then - has no effect when pre-staged files already exist or
    # skip_weather_soil_creation is FALSE. Default 5 matches this pipeline's
    # historical grid density; a usecase can widen it (e.g. 10) to cut the
    # site count ~4x for faster/coarser runs.
    resolution_km = 5,
    # Reuse another usecase's pre-staged export (e.g. a derived test
    # usecase) instead of generating a new one.
    dssat_source_use_case_name = NULL
  )
  
  # Combine keeping user choices first
  complete_usecase <- utils::modifyList(dssat_defaults, usecase)
  
  # Dynamic assignments based on parameters
  complete_usecase$soil_depths <- if (complete_usecase$soil_source == "ISRIC") c(5, 15, 30, 60, 100, 200) else c("0-20cm", "20-50cm")
  
  complete_usecase$use_case_name <- str_to_lower(usecase$use_case_name)

  complete_usecase <- build_fertilizer_inputs(complete_usecase, repo_root)
  
  return(complete_usecase)
}


# Validate fertilizer flags and build the inputs each mode reads downstream
build_fertilizer_inputs <- function(complete_usecase, repo_root) {
  modes <- c("simple_fertilizer", "fert_grid_search", "fert_factorial_preset")
  active <- modes[vapply(modes, function(m) isTRUE(complete_usecase[[m]]), logical(1))]
  if (length(active) > 1) {
    stop("Only one fertilizer mode can be TRUE, got: ", paste(active, collapse = ", "))
  }
  complete_usecase$NPK_ranges <- NULL
  complete_usecase$fert_treatments_df <- NULL

  if (isTRUE(complete_usecase$fert_grid_search)) {
    if (is.null(complete_usecase$fert_N_rates)) {
      stop("fert_grid_search = TRUE requires fert_N_rates.")
    }
    dap <- as.numeric(unlist(complete_usecase$fert_application_dap))
    complete_usecase$NPK_ranges <- list(
      N = as.numeric(unlist(complete_usecase$fert_N_rates)),
      P = as.numeric(unlist(complete_usecase$fert_P_rates)),
      K = as.numeric(unlist(complete_usecase$fert_K_rates)),
      F.dap = dap,
      n_split_applications = length(dap),
      FMCD = complete_usecase$fert_material,
      FACD = complete_usecase$fert_method,
      FDEP = complete_usecase$fert_depth,
      FAMC = -99, FAMO = -99, FOCD = -99)
  }

  if (isTRUE(complete_usecase$fert_factorial_preset)) {
    if (is.null(complete_usecase$fert_treatments_file)) {
      stop("fert_factorial_preset = TRUE requires fert_treatments_file.")
    }
    path <- complete_usecase$fert_treatments_file
    if (!file.exists(path)) path <- file.path(repo_root, path)
    complete_usecase$fert_treatments_df <- read_fert_treatments(path)
  }

  complete_usecase
}


# Read and validate a fertilizer treatments list (one row per application)
read_fert_treatments <- function(path) {
  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("FERNAME", "F.dap", "FMCD", "FACD", "FDEP", "FAMN", "FAMP", "FAMK")
  missing <- setdiff(required, names(df))
  if (length(missing) > 0) {
    stop("Fertilizer treatments file ", path, " is missing columns: ",
         paste(missing, collapse = ", "))
  }
  # "<FERNAME> 8th pd" must fit DSSAT's 25-char TNAME
  too_long <- unique(df$FERNAME[nchar(df$FERNAME) > 16])
  if (length(too_long) > 0) {
    stop("FERNAME must be <= 16 characters: ", paste(too_long, collapse = ", "))
  }
  if (any(grepl("\\d+(st|nd|rd|th) (app|pd)", df$FERNAME))) {
    stop("FERNAME must not contain '<n>th app' / '<n>th pd' patterns.")
  }
  for (col in c("FAMC", "FAMO", "FOCD")) {
    if (!col %in% names(df)) df[[col]] <- -99
  }
  df$F <- match(df$FERNAME, unique(df$FERNAME))
  df
}


# Number of fertilizer treatments per planting date (1 when no fertilizer mode)
get_n_fert_treatments <- function(complete_usecase) {
  if (!is.null(complete_usecase$NPK_ranges)) {
    r <- complete_usecase$NPK_ranges
    return(length(r$N) * length(r$P) * length(r$K))
  }
  if (!is.null(complete_usecase$fert_treatments_df)) {
    return(length(unique(complete_usecase$fert_treatments_df$FERNAME)))
  }
  1
}


get_DSSAT_crop_submodel <- function(crop_code) {
  mapping <- c(
    "CS" = "YCA",
    "MZ" = "CER",
    "PT" = "SUB",
    "SB" = "GRO",
    "WH" = "CER"
  )
  
  return(unname(mapping[crop_code]))
}


run_dssat_pipeline <- function(
    usecase, repo_root = usecase_repo_root()) {
  
  project_root <- repo_root
  
  # Source Required DSSAT Components ---
  source(file.path(repo_root, "main/DSSAT/00_load_packages.R"))
  source(file.path(repo_root, "main/DSSAT/common_helpers.R"))
  source(file.path(repo_root, "main/DSSAT/readGeo_CM_zone.R"))
  source(file.path(repo_root, "main/DSSAT/helpers_readGeo_CM_zone.R"))
  source(file.path(repo_root, "main/DSSAT/import_prestaged_dssat_files.R"))
  source(file.path(repo_root, "main/DSSAT/run_datasourcing_export.R"))
  source(file.path(repo_root, "main/DSSAT/DSSAT_expfile.R"))
  source(file.path(repo_root, "main/DSSAT/helpers_DSSAT_expfile.R"))
  source(file.path(repo_root, "main/DSSAT/dssat_exec.R"))
  source(file.path(repo_root, "main/DSSAT/merge_DSSAT_output.R"))
  source(file.path(repo_root, "main/DSSAT/DSSAT_analyze_results.R"))
  source(file.path(repo_root, "main/DSSAT/helpers_DSSAT_analyze_results.R"))
  source(file.path(repo_root, "main/DSSAT/get_pdate_cultivar_recommendation.R"))
  source(file.path(repo_root, "main/DSSAT/bc_daily_rain.R"))
  
  # Expand usecase forecast config with DSSAT default config
  complete_usecase <- load_dssat_defaults(usecase, repo_root)
  
  # Extract Variables from Config context ---
  zones  <- complete_usecase$zones
  varietyids <- complete_usecase$varietyids
  country <- complete_usecase$country_name
  useCaseName <- complete_usecase$use_case_name
  Crop <- complete_usecase$crop
  
  
  # --- STEP 1: Soil and Weather Input File Creation ---
  # ISDA creation script would go here
  # skip_weather_soil_creation lets a usecase supply its transform/DSSAT/AOI
  # weather+soil files itself (e.g. pre-staged DSSAT-ready files from another
  # pipeline) instead of generating them here from RDS forecast handoff data.
  if (!isTRUE(complete_usecase$skip_weather_soil_creation)) {
    message("Creating DSSAT weather and soil input files")
    # Logged per-zone (appending), not once after the whole double loop, so
    # a crash partway through still leaves a log covering every zone that
    # completed before it, instead of nothing at all.
    log_started <- FALSE
    for (varietyid in varietyids) {
      for (zone in zones) {
        message("Creating DSSAT weather and soil input files for ", zone)
        wth_sol_files_msg <- readGeo_CM_zone(
          complete_usecase = complete_usecase,
          project_root    = repo_root,
          zone            = zone,
          varietyid       = varietyid,
          fc_month = complete_usecase$season_start_month
        )
        if (exists("write_dssat_log") && !is.null(wth_sol_files_msg)) {
          write_dssat_log(wth_sol_files_msg, file = "readGeo_CM_zone.log",
                          repo_root, country, useCaseName, Crop,
                          append = log_started)
          log_started <- TRUE
        }
      }
    }
    if (exists("future::plan")) future::plan(future::sequential)
  } else {
    message("skip_weather_soil_creation = TRUE - checking for pre-staged DSSAT files...")
    if (isTRUE(complete_usecase$generate_dssat_via_datasourcing)) {
      generate_prestaged_dssat_via_datasourcing(
        complete_usecase = complete_usecase, repo_root = repo_root,
        res_km = complete_usecase$resolution_km)
    }
    import_prestaged_dssat_files(complete_usecase = complete_usecase, repo_root = repo_root)
  }
  
  if (length(varietyids) > 1 && exists("copy_WTH_SOIL_data_for_variety")) {
    copy_WTH_SOIL_data_for_variety(
      country     = complete_usecase$country_name, 
      useCaseName = complete_usecase$use_case_name,
      Crop        = complete_usecase$crop,
      project_root = repo_root, 
      AOI         = complete_usecase$aoi, 
      varietyids  = varietyids
    )
  }
  
  
  # --- STEP 2: Create DSSAT Input Files ---
  message("Creating DSSAT experimental input files...")
  # Logged per-zone (appending) - see Step 1's comment for why.
  log_started <- FALSE
  for (varietyid in varietyids) {
    for (zone in zones) {
      expfile_msg <- invisible(
        dssat.expfile(
          complete_usecase = complete_usecase,
          project_root = repo_root,
          varietyid = varietyid,
          zone = zone
        )
      )
      if (exists("write_dssat_log") && !is.null(expfile_msg) && length(expfile_msg) > 0) {
        write_dssat_log(expfile_msg, file = "dssat.expfile.log",
                        repo_root, country, useCaseName, Crop,
                        append = log_started)
        log_started <- TRUE
      }
    }
  }
  if (exists("future::plan")) future::plan(future::sequential)

  # --- STEP 3: Run DSSAT Simulations ---
  # Every site has 8 onset planting dates x the same fertilizer treatments
  n_fert <- get_n_fert_treatments(complete_usecase)
  TRT <- 1:(8 * n_fert)
  message("Running DSSAT simulations... ", length(TRT), " treatments per site (8 planting dates x ",
          n_fert, " fertilizer treatment(s))")

  # Logged per-zone (appending) - see Step 1's comment for why. This is the
  # step that previously crashed mid-run with no tryCatch and no log at all
  # to show for it; both are now fixed (see dssat.exec()).
  log_started <- FALSE
  for (varietyid in varietyids) {
    for (zone in zones) {
      exemodel_msg <- dssat.exec(
        country     = complete_usecase$country_name,
        useCaseName = complete_usecase$use_case_name,
        Crop        = complete_usecase$crop,
        project_root = repo_root,
        AOI         = complete_usecase$aoi,
        TRT         = TRT,
        varietyid   = varietyid,
        zone        = zone
      )
      if (exists("write_dssat_log") && !is.null(exemodel_msg)) {
        write_dssat_log(exemodel_msg, file = "dssat.exec.log",
                        repo_root, country, useCaseName, Crop,
                        append = log_started)
        log_started <- TRUE
      }
    }
  }
  if (exists("future::plan")) future::plan(future::sequential)

  # --- STEP 4: Merge Outputs ---
  message("Merging DSSAT output files...")
  results_df <- merge_DSSAT_output(
    complete_usecase = complete_usecase,
    country       = complete_usecase$country_name, 
    useCaseName   = complete_usecase$use_case_name, 
    Crop          = complete_usecase$crop, 
    project_root  = repo_root, 
    Soil_source   = complete_usecase$soil_source, 
    AOI           = complete_usecase$aoi, 
    season        = complete_usecase$season, 
    varietyids    = varietyids, 
    zone_folder   = TRUE, 
    level2_folder = FALSE
  )
  
  result_output_dir <- file.path(
    project_usecase_dir(
      repo_root, complete_usecase$country_name, complete_usecase$use_case_name),
    complete_usecase$crop, "result", "DSSAT", "AOI")

  # --- STEP 4.5: Crop-mask-filtered full results (all treatments/cultivars,
  # pre-ranking) - a general-purpose artifact for future consumers (e.g. the
  # results dashboard), produced whenever a crop mask is available regardless
  # of whether use_crop_mask is requested for Step 5's own outputs below.
  # base_filename mirrors merge_DSSAT_output()'s own AOI save name so the
  # masked file sits right next to the unmasked one it already writes.
  dssat_output_base_filename <- paste0(
    complete_usecase$soil_source, "_useCase_", complete_usecase$country_name,
    "_", complete_usecase$use_case_name, "_", complete_usecase$crop,
    "_AOI_season_", complete_usecase$season)
  export_cropmask_full_results(
    results_df = results_df, crop = complete_usecase$crop,
    crop_mask_dir = file.path(repo_root, "Landing", "crop_masks"),
    output_dir = result_output_dir, base_filename = dssat_output_base_filename,
    country = complete_usecase$country_name)

  # --- STEP 4.6: Daily rain at the result pixels, for the dashboard's
  # rainfall maps. Read from the bias-corrected cubes; a missing cube only
  # skips the maps, it must not fail the run.
  tryCatch(
    write_daily_rain(
      complete_usecase, results_df, output_dir = result_output_dir,
      base_filename = dssat_output_base_filename),
    error = function(e) {
      warning("Daily rain extraction failed; results are saved, continuing: ",
              conditionMessage(e), call. = FALSE)
    })

  # --- STEP 5: Produce Final Outputs ---
  message("Saving nc, plots, and statistics...")
  plot_df <- add_date_rank(results_df, metric = "HWAH")

  # Every result file is prefixed with crop + forecast year so it stays
  # identifiable if copied out of its per-crop folder.
  file_prefix <- paste0(complete_usecase$crop, "_", complete_usecase$season_year, "_")

  use_crop_mask <- isTRUE(complete_usecase$use_crop_mask)
  crop_mask_dir <- file.path(repo_root, "Landing", "crop_masks")

  plot_planting_date_gradients(
    df = plot_df, country_name = complete_usecase$country_name,
    output_dir = result_output_dir, file_prefix = file_prefix,
    crop = complete_usecase$crop, use_crop_mask = use_crop_mask,
    crop_mask_dir = crop_mask_dir, project_root = repo_root)

  plot_yield_gradients(
    df = plot_df, yield_col = "HWAH", complete_usecase$country_name,
    output_dir = result_output_dir, file_prefix = file_prefix,
    crop = complete_usecase$crop, use_crop_mask = use_crop_mask,
    crop_mask_dir = crop_mask_dir, project_root = repo_root)

  summary_df <- summarize_and_save_dssat(
    df = plot_df, outputs = c("HWAH", "CWAM"), output_dir = result_output_dir,
    file_prefix = file_prefix, crop = complete_usecase$crop,
    use_crop_mask = use_crop_mask, crop_mask_dir = crop_mask_dir,
    country = complete_usecase$country_name)

  export_top_combinations_nc(
    df = results_df, metric = "HWAH", top_n = 5, output_dir = result_output_dir,
    file_prefix = file_prefix, crop = complete_usecase$crop,
    country = complete_usecase$country_name, forecast_year = complete_usecase$season_year,
    season = complete_usecase$season,
    # Bias-correction method isn't threaded from the forecast/BC config into
    # the DSSAT usecase, so this reflects current pipeline convention rather
    # than a value read at run time - update if that convention changes.
    bc_method = "qdm",
    use_crop_mask = use_crop_mask, crop_mask_dir = crop_mask_dir
  )

  comb_df <- export_top_combinations_csv(
    df = results_df, metric = "HWAH", top_n = 5, output_dir = result_output_dir,
    file_prefix = file_prefix, crop = complete_usecase$crop,
    use_crop_mask = use_crop_mask, crop_mask_dir = crop_mask_dir,
    country = complete_usecase$country_name
  )

  if (isTRUE(complete_usecase$fert_grid_search) ||
      isTRUE(complete_usecase$fert_factorial_preset)) {
    run_fertilizer_comparison(
      results_df = results_df, output_dir = result_output_dir,
      file_prefix = file_prefix, metric = "HWAH",
      crop_price = complete_usecase$crop_price)
  }

  # --- STEP 6: Build the results dashboard ---
  # force_rebuild = TRUE: this run just (re)computed results_df above, so any
  # dashboard_extract.RDS already on disk necessarily predates it and would
  # otherwise be served stale.
  # A failed render (e.g. pandoc OOM-killed on large countries) must not fail
  # the run: all results are already saved and the HTML is only a viewer.
  if (isTRUE(complete_usecase$build_dashboard)) {
    message("Building results dashboard...")
    tryCatch(
      build_crop_dashboard(
        crop = complete_usecase$crop, result_dir = result_output_dir,
        base_filename = dssat_output_base_filename, crop_mask_dir = crop_mask_dir,
        repo_root = repo_root, country_name = complete_usecase$country_name,
        force_rebuild = TRUE),
      error = function(e) {
        warning("Results dashboard build failed; results are saved, continuing: ",
                conditionMessage(e), call. = FALSE)
      })
  }

}


# run_usecase <- function(usecase) {
#   cli <- parse_usecase_args()
#   repo_root <- usecase_repo_root()
#   
#   # Enrich configuration with defaults safely
#   usecase <- load_dssat_defaults(usecase, repo_root)
#   
#   # Step 0: Run their forecast workspace setup
#   run_forecast_usecase(usecase, cli = cli)
#   
#   # Step 1: Run their over-engineered environment file generator
#   format_dssat_zones(usecase, cli = cli)
#   
#   # Steps 2-4: Run your clean pipeline directly
#   results <- run_dssat_pipeline(usecase, cli = cli, repo_root = repo_root)
#   
#   usecase$results <- results
#   invisible(usecase)
# }
# 
# run_usecase_config <- function(config_path) {
#   cli <- parse_usecase_args()
#   repo_root <- usecase_repo_root()
#   config_path <- usecase_config_file(config_path, repo_root)
#   usecase <- read_usecase_yaml(config_path)
#   usecase$yml_config_path <- config_path
#   
#   run_usecase(usecase)
# }
