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
    fertilizer          = FALSE,
    fert_factorial      = FALSE,
    fert_grid_RS        = FALSE,
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
    dssat_source_products_dir = NULL
  )
  
  # Combine keeping user choices first
  complete_usecase <- utils::modifyList(dssat_defaults, usecase)
  
  # Dynamic assignments based on parameters
  complete_usecase$soil_depths <- if (complete_usecase$soil_source == "ISRIC") c(5, 15, 30, 60, 100, 200) else c("0-20cm", "20-50cm")
  
  complete_usecase$use_case_name <- str_to_lower(usecase$use_case_name)
  
  return(complete_usecase)
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
  source(file.path(repo_root, "main/DSSAT/DSSAT_expfile.R"))
  source(file.path(repo_root, "main/DSSAT/helpers_DSSAT_expfile.R"))
  source(file.path(repo_root, "main/DSSAT/dssat_exec.R"))
  source(file.path(repo_root, "main/DSSAT/merge_DSSAT_output.R"))
  source(file.path(repo_root, "main/DSSAT/DSSAT_analyze_results.R"))
  source(file.path(repo_root, "main/DSSAT/helpers_DSSAT_analyze_results.R"))
  source(file.path(repo_root, "main/DSSAT/get_pdate_cultivar_recommendation.R"))
  
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
    wth_sol_files_msg <- NULL
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
      }
    }
    if (exists("future::plan")) future::plan(future::sequential)
    if (exists("write_dssat_log") && !is.null(wth_sol_files_msg)) {
      write_dssat_log(wth_sol_files_msg, file = "readGeo_CM_zone.log",
                      repo_root, country, useCaseName, Crop)
    }
  } else {
    message("skip_weather_soil_creation = TRUE - checking for pre-staged DSSAT files...")
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
  expfile_msg <- NULL
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
    }
  }
  if (exists("future::plan")) future::plan(future::sequential)
  if (exists("write_dssat_log") && !is.null(expfile_msg) && length(expfile_msg) > 0) {
    write_dssat_log(expfile_msg, file = "dssat.expfile.log",
                    repo_root, country, useCaseName, Crop)
  }
  
  # --- STEP 3: Run DSSAT Simulations ---
  message("Running DSSAT simulations... Number of treatments set to 8 planting dates")
  TRT <- 1:8
  
  exemodel_msg <- NULL
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
    }
  }
  if (exists("future::plan")) future::plan(future::sequential)
  if (exists("write_dssat_log") && !is.null(exemodel_msg)) {
    write_dssat_log(exemodel_msg, file = "dssat.exec.log",
                    repo_root, country, useCaseName, Crop)
  }
  
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

  # --- STEP 6: Build the results dashboard ---
  # force_rebuild = TRUE: this run just (re)computed results_df above, so any
  # dashboard_extract.RDS already on disk necessarily predates it and would
  # otherwise be served stale.
  if (isTRUE(complete_usecase$build_dashboard)) {
    message("Building results dashboard...")
    build_crop_dashboard(
      crop = complete_usecase$crop, result_dir = result_output_dir,
      base_filename = dssat_output_base_filename, crop_mask_dir = crop_mask_dir,
      repo_root = repo_root, country_name = complete_usecase$country_name,
      force_rebuild = TRUE)
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
