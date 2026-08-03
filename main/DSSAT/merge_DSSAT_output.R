###############################################################################
# Script: merge_DSSAT_output.R
# Purpose: Merge DSSAT simulation outputs for multiple locations.
#
# Authors: Alvaro Carmona-Cabrero, Jemal S. Ahmed (jemal.ahmed@cgiar.org), P. Moreno, A. Sila, S. Mkuhlani, E. Bendito Garcia
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-07-09
###############################################################################


prepare_data_to_save <- function(results_df, project_root, country, useCaseName, Crop,
                                 complete_usecase) {
  path.to.temdata <- check_dssat_temdata_path(project_root = project_root)
  
  cul_file <- DSSAT::read_cul(file.path(
    path.to.temdata, paste0(complete_usecase$geneticfiles, '.CUL')))

  # Cultivar-name column header isn't standardized across crop models
  # (VRNAME for Maize, VAR-NAME for Potato/Wheat) - select positionally.
  var_map <- cul_file %>%
    select(1, 2) %>%
    deframe()
  
  # Cultivar naming isn't consistent across crop genetic files or countries:
  # Rwanda's Maize varieties are prefixed with the full country name
  # (RWANDA_SHORT); Rwanda's Potato/Wheat are suffixed with the ISO2 code
  # (SHORT_RW); Kenya's Maize are suffixed with the full country name
  # (SHORT_KENYA); Malawi/Zambia/Mozambique's Maize share one regional block
  # suffixed "_ZB" (SHORT_ZB) - not any of those countries' own ISO2 code, so
  # stripping a country-derived prefix/suffix pattern (the previous approach)
  # missed this case entirely, leaving "Short_zb" etc. in the data, which
  # then read as NA wherever downstream code factors Cultivar to the
  # canonical c("Short","Medium","Long","Longer") levels (e.g. the
  # planting-date/yield gradient plots).
  #
  # Every convention observed always embeds one of the four canonical
  # maturity-class words somewhere in the name, regardless of which
  # country/region tag surrounds it - so extract that word directly instead
  # of guessing at the tag. "Longer" is checked before "Long" so a Longer
  # cultivar doesn't get truncated to "Long" via a substring match.
  results_df <- results_df %>%
    mutate(Cultivar = unname(var_map[as.character(Variety)])) %>%
    mutate(Cultivar = dplyr::case_when(
      grepl("LONGER", Cultivar, ignore.case = TRUE) ~ "Longer",
      grepl("LONG", Cultivar, ignore.case = TRUE) ~ "Long",
      grepl("MEDIUM", Cultivar, ignore.case = TRUE) ~ "Medium",
      grepl("SHORT", Cultivar, ignore.case = TRUE) ~ "Short",
      TRUE ~ str_to_title(Cultivar)
    ))
  return(results_df)
}


#' @param country country name
#' @param useCaseName use case name  name
#' @param Crop the name of the crop to be used in creating file name to write out the result.
#' @param AOI True if the data is required for target area, and false if it is for trial sites
#' @param season when data is needed for more than one season, this needs to be provided to be used in the file name
#' @param varietyids ids of the varieties based on the cultivar file of DSSAT (column @VAR# in the cultivar file and parameter INGENO in the experimental file *.**X)
#' @param zone_folder When TRUE the output folders are organized by administrative level 1.
#' @param level2_foler When TRUE the output folders are organized by administrative level 2 (has to be part of the administrative level 1 or "zone" of the country) 
#'        for the specific location the experimental file is created
#'        
#' @return merged results from DSSAT in RDS format
#'
#' @examples merge_DSSAT_output(country="Rwanda", useCaseName="RAB",Crop="Maize",varietyids=c("890011","890012"), zone_folder=T, level2_folder=F)

merge_DSSAT_output <- function(
    complete_usecase, country, useCaseName, Crop, project_root, Soil_source, AOI = F,
    season = NULL, varietyids, zone_folder = T, level2_folder = F) {
  
  usecase_dir <- project_usecase_dir(project_root, country, useCaseName)
  all_results <- data.frame()
  for (varietyid in varietyids) {
    if (AOI) {
      if (is.null(season)) {
        stop("With AOI=TRUE, season cannot be null. Please provide a season number.")
      }
      path.to.extdata <- file.path(
        usecase_dir, Crop, "transform", "DSSAT", "AOI", varietyid)
    } else {
      path.to.extdata <- file.path(
        usecase_dir, Crop, "transform", "DSSAT", "fieldData", varietyid)
    }
    
    if (!dir.exists(file.path(path.to.extdata))) {
      message("Experiments not found for varietyid: ", varietyid, ". Process stopped for this varietyid.")
      next
    }
    setwd(path.to.extdata)
    
    a <- list.files(path = path.to.extdata, pattern = "^EXTE.*\\.OUT$", include.dirs = TRUE, full.names = TRUE, recursive = TRUE)
    b <- list.files(path = path.to.extdata, pattern = "^WHTE.*\\.WTH$", include.dirs = TRUE, full.names = TRUE, recursive = TRUE)
    
    
    results <- future_map_dfr(a, function(.x) {
      tryCatch({
        file <- read_output(.x)

        # Work around a bug in DSSAT::read_output()'s internal (unexported)
        # convert_to_date(): after parsing a date, it subtracts 100 years from
        # it whenever the result is later than Sys.time(), assuming the value
        # came from an ambiguous 2-digit-year (YYDDD) rollover. This misfires
        # for genuine future dates within the current forecast run (e.g. a
        # 2026 season processed mid-2026 with planting dates later in 2026),
        # turning 2026 into 1926. Undo that shift here on the affected columns.
        date_cols <- intersect(c("PDAT", "ADAT", "MDAT", "HDAT"), names(file))
        for (col in date_cols) {
          if (inherits(file[[col]], "POSIXct")) {
            shifted <- !is.na(file[[col]]) & file[[col]] < as.POSIXct("2000-01-01", tz = "UTC")
            file[[col]][shifted] <- file[[col]][shifted] + lubridate::years(100)
          }
        }

        file <- file[, c("XLAT", "LONG", "TRNO", "TNAM", "PDAT","ADAT","MDAT",
                         "HDAT", "CWAM", "HWAH", "CNAM", "GNAM", "NDCH",
                         "TMAXA", "TMINA", "SRADA", "PRCP", "ETCP", "ESCP", "CRST")]
        file$file_name <- .x
        file$WUE <- file$HWAH / file$PRCP
        
        # Your folder logic here...
        if (level2_folder & zone_folder) {
          test <- mgsub(.x, c(path.to.extdata, "/EXTE.*"), c("", ""))
          test <- strsplit(test, "/")[[1]]
          test <- test[test != ""]
          file$zone <- test[1]
          file$Loc <- file$zone
          file$level2 <- test[2]
        } else if (!level2_folder && zone_folder) {
          file$zone <- mgsub(.x, c(path.to.extdata, "/", "/EXTE.*"), c("", "", ""))
          file$Loc <- file$zone
          file$level2 <- NA
        } else if (level2_folder && !zone_folder) {
          stop("Level 2 requires a zone. Process stopped.")
        } else {
          file$zone <- NA
          file$level2 <- NA
          file$Loc <- NA
        }
        
        file$Variety <- varietyid
        
        base <- gsub("^EXTE_|\\.OUT$", "", basename(.x))   # extract core piece
        wht_path <- b[grepl(base, b)]
        
        wht_file <- read_filea(wht_path[1])
        
        file$Lat <- unique(wht_file$LAT)
        file$Long <- unique(wht_file$LONG)
        
        file
      }, error = function(e) {
        cat("Error processing file:", .x, "\n", e$message, "\n")
        NULL
      })
    })
    
    
    all_results <- bind_rows(all_results, results)
  }
  
  all_results <- prepare_data_to_save(
    all_results, project_root, country, useCaseName, Crop, complete_usecase)
  
  if (AOI) {
    dir_path <- file.path(usecase_dir, Crop, "result", "DSSAT", "AOI")
  } else {
    dir_path <- file.path(usecase_dir, Crop, "result", "DSSAT", "fieldData")
  }
  
  if (!dir.exists(dir_path)) {
    dir.create(dir_path, recursive = T)
  }
  
  if (AOI) {
    saveRDS(
      all_results,
      file = file.path(
        dir_path,
        paste0(Soil_source, "_useCase_", country, "_", useCaseName, "_",
               Crop, "_AOI_season_", season, ".RDS")))
  }else{
    saveRDS(
      all_results,
      file = file.path(
        dir_path,
        paste0(Soil_source, "_useCase_", country, "_", useCaseName, "_",
               Crop, "_fieldData_season_", season, ".RDS")))
  }
  
  return(all_results)
}
