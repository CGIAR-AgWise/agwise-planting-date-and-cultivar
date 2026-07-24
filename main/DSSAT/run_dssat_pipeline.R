load_dssat_defaults <- function(usecase, repo_root) {
  # Set up all your standard parameters as background fallbacks
  
  crop_code <- get_DSSAT_crop_code(usecase$crop)
  
  dssat_defaults <- list(
    filex_temp          = paste0("PDVAR.", crop_code, "X"),  # Template for this repo
    geneticfiles        = paste0(crop_code, get_DSSAT_crop_submodel(crop_code), "048"),  # Country/crop specific genetic files
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
    planting_window     = 7
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
  
  # --- STEP 5: Produce Final Outputs ---
  message("Saving nc, plots, and statistics...")
  plot_df <- add_date_rank(results_df, metric = "HWAH")
  
  result_output_dir <- file.path(
    project_usecase_dir(
      repo_root, complete_usecase$country_name, complete_usecase$use_case_name),
    complete_usecase$crop, "result", "DSSAT", "AOI")

  plot_planting_date_gradients(
    df = plot_df, country_name = complete_usecase$country_name, 
    output_dir = result_output_dir)
  
  plot_yield_gradients(
    df = plot_df, yield_col = "HWAH", complete_usecase$country_name,
    output_dir = result_output_dir)
  
  summary_df <- summarize_and_save_dssat(
    df = plot_df, outputs = c("HWAH", "CWAM"), output_dir = result_output_dir)
  
  export_top_combinations_nc(
    df = results_df, metric = "HWAH", top_n = 5, output_dir = result_output_dir
  )
  
  comb_df <- export_top_combinations_csv(
    df = results_df, metric = "HWAH", top_n = 5, output_dir = result_output_dir
  )
  
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
