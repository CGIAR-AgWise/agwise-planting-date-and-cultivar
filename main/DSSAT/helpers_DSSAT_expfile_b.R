
# 
# packages_required <- c(
#   "tidyverse", "lubridate", "DSSAT", "furrr", "future", "future.apply",
#   "stringr", "geodata", "readr", "purrr")
# 
# installed_packages <- packages_required %in% rownames(installed.packages())
# if(any(installed_packages == F)) {
#   install.packages(packages_required[!installed_packages])}
# 
# invisible(lapply(packages_required, library, character.only = T))
# 
select <- dplyr::select
mutate <- dplyr::mutate
rename <- dplyr::rename

####################
# Helper functions #
####################


################################################################################
# Helper functions
################################################################################
create_rs_schedule <- function(template_df, fc_year = NA) {
  if (!is.na(fc_year)) {
    rs_schedule_df <- template_df %>%
      {
        nm <- names(.)
        if ("lon" %in% nm)  rename(., longitude = lon) else .
      } %>%
      {
        nm <- names(.)
        if ("lat" %in% nm)  rename(., latitude  = lat) else .
      } %>%
      dplyr::select(longitude, latitude, q25, q50, q75) %>%
      mutate(
        longitude = as.numeric(longitude),
        latitude  = as.numeric(latitude)
      ) %>%
      fill(q25, q50, q75, .direction = "downup") %>%
      mutate(
        q25_date = doy_to_date(q25, year = fc_year),
        q75_date = doy_to_date(q75, year = fc_year)
      ) %>%
      rowwise() %>%
      mutate(
        planting_dates = list(seq(q25_date, q75_date, length.out = 4)),
        startingDate   = min(planting_dates) %m-% months(1),
        harvestDate    = max(planting_dates) %m+% months(8)
      ) %>%
      ungroup() %>%
      mutate(
        lon_r = round(longitude, 3),
        lat_r = round(latitude, 3)
      ) %>%
      dplyr::select(-c(q25, q50, q75, q25_date, q75_date))
  } else if (is.na(fc_year)) {
    rs_schedule_df <- template_df %>%
      {
        nm <- names(.)
        if ("lon" %in% nm)  rename(., longitude = lon) else .
      } %>%
      {
        nm <- names(.)
        if ("lat" %in% nm)  rename(., latitude  = lat) else .
      } %>%
      dplyr::select(longitude, latitude, q25, q50, q75) %>%
      mutate(
        longitude = as.numeric(longitude),
        latitude  = as.numeric(latitude)
      ) %>%
      fill(q25, q50, q75, .direction = "downup") %>%
      mutate(
        q25_date = doy_to_date(q25),
        q75_date = doy_to_date(q75)
      ) %>%
      rowwise() %>%
      mutate(
        planting_dates = list(seq(q25_date, q75_date, length.out = 4)),
        startingDate   = min(planting_dates) %m-% months(1),
        harvestDate    = max(planting_dates) %m+% months(8)
      ) %>%
      ungroup() %>%
      mutate(
        lon_r = round(longitude, 3),
        lat_r = round(latitude, 3)
      ) %>%
      dplyr::select(-c(q25, q50, q75, q25_date, q75_date))
  }
  
  return(rs_schedule_df)
}


# DOY -> Date (year is arbitrary; DSSAT uses mm-dd derived from these Dates)
doy_to_date <- function(x, year = 2001L) {
  x <- suppressWarnings(as.integer(x))
  as.Date(x - 1L, origin = paste0(year, "-01-01"))
}


# Approach 2: Fertilizer (from preset grid) x RS plant dates (from template) 
# grid factorial
create_grid_factorial_design <- function(
    file_x, ex_profile, template_df, NPK_ranges, plant_dates, FMCD = "FE027", 
    FACD = "AP004", FDEP = 5, F.dap = 42, FAMC = -99, FAMO = -99, FOCD = -99) {
  
  fert_x <- dplyr::slice(file_x$`FERTILIZERS (INORGANIC)`, 0)
  
  fert_factorial_df <- expand.grid(
    FAMN = NPK_ranges$N,
    FAMP = NPK_ranges$P,
    FAMK = NPK_ranges$K
  ) %>%
    mutate(FMCD = FMCD,
           FACD = FACD,
           FDEP = FDEP,
           FAMC = FAMC,
           FAMO = FAMO,
           FOCD = FOCD,
           FERNAME = paste0(FAMN, "N.", FAMP, "P.", FAMK, "K"),
           F = NA,
           FDATE = NA) %>%
    dplyr::select(all_of(colnames(fert_x)))
  
  # template_df <- template_df_ori
  
  template_df <- template_df %>%
    dplyr::filter(lat == ex_profile$LAT & lon == ex_profile$LON)
  
  split_app <- unique(template_df$split_application)
  
  file_x$CULTIVARS$CNAME <- unique(template_df$CNAME)
  
  template_df <- template_df %>%
    dplyr::select(-c(CNAME, INGENO))  # Remove non-DSSAT columns
  
  # Populate fertilizer levels
  fert_x <- dplyr::slice(file_x$`FERTILIZERS (INORGANIC)`, 0)
  for (i in seq_along(plant_dates)) {
    # Split application for Nitrogen
    if (split_app %in% c("Yes", T)) {
      # Half N and all P and K applied at planting
      first_application_df <- fert_factorial_df %>%
        mutate(F = as.numeric(row.names(fert_factorial_df)) + 
                 (i - 1) * dim(fert_factorial_df)[1],
               FDATE = plant_dates[i],
               FAMN = FAMN/2)
      # Half N and zero P and K applied F.dap days after planting
      second_application_df <- fert_factorial_df %>%
        mutate(F = as.numeric(row.names(fert_factorial_df)) + 
                 (i - 1) * dim(fert_factorial_df)[1],
               FDATE = plant_dates[i] + F.dap,
               FAMN = FAMN/2,
               FAMP = 0,
               FAMK = 0)
      # Interleave rows
      fert_x_ij <- bind_rows(
        first_application_df %>% mutate(.idx = row_number(), .src = 1),
        second_application_df %>% mutate(.idx = row_number(), .src = 2)
      ) %>%
        arrange(.idx, .src) %>%
        dplyr::select(-.idx, -.src)
      
    } else {
      # All fertilizer applied at planting
      fert_x_ij <- fert_factorial_df %>%
        mutate(F = as.numeric(row.names(fert_factorial_df)) + 
                 (i - 1) * dim(fert_factorial_df)[1],
               FDATE = plant_dates[i])
    }
    
    fert_x <- bind_rows(fert_x, fert_x_ij)
  }
  file_x$`FERTILIZERS (INORGANIC)` <- fert_x
  
  file_x$FIELDS$ID_FIELD <- unique(template_df$NAME_2)
  file_x$FIELDS$XCRD <- unique(template_df$lon)
  file_x$FIELDS$YCRD <- unique(template_df$lat)
  
  planting_details_df <- file_x$`PLANTING DETAILS`[rep(seq_len(nrow(
    file_x$`PLANTING DETAILS`)), 4), ] %>%
    mutate(P = 1:length(plant_dates),
           PDATE = as.POSIXct(plant_dates))
  file_x$`PLANTING DETAILS` <- planting_details_df
  
  initial_conditions_df <- file_x$`INITIAL CONDITIONS`[rep(seq_len(nrow(
    file_x$`INITIAL CONDITIONS`)), 4), ] %>%
    mutate(C = 1:length(plant_dates),
           ICDAT = as.POSIXct(plant_dates %m-% months(1)))
  file_x$`INITIAL CONDITIONS` <- initial_conditions_df
  
  harvest_details_df <- file_x$`HARVEST DETAILS`[rep(seq_len(nrow(
    file_x$`HARVEST DETAILS`)), 4), ] %>%
    mutate(H = 1:length(plant_dates),
           HDATE = as.POSIXct(plant_dates %m+% months(8)))
  file_x$`HARVEST DETAILS` <- harvest_details_df
  
  sim_controls_df <- file_x$`SIMULATION CONTROLS`[rep(seq_len(nrow(
    file_x$`SIMULATION CONTROLS`)), 4), ] %>%
    mutate(N = 1:length(plant_dates),
           SDATE = as.POSIXct(plant_dates %m-% months(1)),
           NITRO = "Y",
           PHOSP = "Y",
           POTAS = "N")
  if (AOI) sim_controls_df$NYERS <- number_years
  file_x$`SIMULATION CONTROLS` <- sim_controls_df
  
  trt_x_original <- file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`
  trt_x <- dplyr::slice(trt_x_original, 0)
  trt_ij <- 0
  
  for (i in seq_along(plant_dates)){
    for (j in 1:length(unique(fert_x$FERNAME))){
      trt_ij <- trt_ij + 1
      trt_x_ij <- trt_x_original
      
      Tname <- fert_x %>%
        dplyr::filter(F == j) %>%
        dplyr::select(FERNAME) %>%
        mutate(FERNAME = substr(FERNAME, 1, 12)) %>%
        unique()
      
      trt_x_ij <- trt_x_ij %>%
        mutate(
          N = trt_ij,
          TNAME = case_when(
            length(plant_dates) == 1 ~ Tname[[1, 1]],
            TRUE ~ paste0(Tname[1, ], "@", format(plant_dates[i], "%m-%d"))
          ),
          MF = trt_ij,
          across(c(MH, MP, IC, SM), ~ i)
        )
      
      trt_x <- bind_rows(trt_x, trt_x_ij)
    }
  }
  file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` <- trt_x
  
  return(file_x)
}


# Approach 1: Fertilizer factorial (from template)
populate_dssat_exp_fert_approach1 <- function(file_x, template_df, ex_profile) {
  template_df <- template_df %>%
    mutate(PDATE = gsub("[^0-9]", "", PDAT)) %>%
    dplyr::filter(lat == ex_profile$LAT & lon == ex_profile$LON)
  
  file_x$CULTIVARS$CNAME <- unique(template_df$CNAME)
  
  template_df <- template_df %>%
    dplyr::select(-c(CNAME, INGENO))  # Remove non-DSSAT columns
  
  plant_date <- doy_to_date(unique(template_df$PDATE))
  
  file_x$FIELDS$ID_FIELD <- unique(template_df$NAME_2)
  file_x$FIELDS$XCRD <- unique(template_df$lon)
  file_x$FIELDS$YCRD <- unique(template_df$lat)
  file_x$`PLANTING DETAILS`$PLNAME <- unique(template_df$PDAT)
  
  template_df <- template_df %>%
    dplyr::select(-c(PDATE, NAME_1, NAME_2, lon, lat, PDAT))
  
  file_x$`PLANTING DETAILS`$PDATE <- as.POSIXct(plant_date)
  file_x$`INITIAL CONDITIONS`$ICDAT <- as.POSIXct(plant_date %m-% months(1))
  file_x$`HARVEST DETAILS`$HDATE <- as.POSIXct(plant_date %m+% months(8))
  file_x$`SIMULATION CONTROLS`$SDATE <- as.POSIXct(plant_date %m-% months(1))
  if (AOI) file_x$`SIMULATION CONTROLS`$NYERS <- number_years
  
  fert_x <- dplyr::slice(file_x$`FERTILIZERS (INORGANIC)`, 0)
  f_ij <- 0
  for (i in seq_along(plant_date)){
    for (j in 1:max(template_df$F)) {  # Loop through all fertilizer levels
      f_ij <- f_ij + 1
      
      fert_x_ij <- template_df %>% 
        dplyr::filter(F == j) %>%
        mutate(FDATE = as.POSIXct(plant_date[i] + F.dap),
               F = f_ij) %>%
        dplyr::select(-F.dap)
      
      fert_x <- bind_rows(fert_x, fert_x_ij)
    }
  }
  
  file_x$`FERTILIZERS (INORGANIC)` <- fert_x
  
  trt_x_original <- file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`
  trt_x <- dplyr::slice(trt_x_original, 0)
  trt_ij <- 0
  
  for (i in seq_along(plant_date)){
    for (j in 1:max(template_df$F)){
      trt_ij <- trt_ij + 1
      trt_x_ij <- trt_x_original
      
      Tname <- template_df %>%
        dplyr::filter(F == j) %>%
        dplyr::select(FERNAME) %>%
        mutate(FERNAME = substr(FERNAME, 1, 9))
      
      trt_x_ij <- trt_x_ij %>%
        mutate(
          N = trt_ij,
          TNAME = case_when(
            length(plant_date) == 1 ~ Tname[[1, 1]],
            TRUE ~ paste(Tname[1, ], "@", format(plant_date[i], "%m-%d"),
                         sep = " ")
          ),
          MF = trt_ij,
          across(c(MH, MP, IC, SM), ~ i)
        )
      
      trt_x <- bind_rows(trt_x, trt_x_ij)
    }
  }
  file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` <- trt_x
  
  return(file_x)
}


# Approach 0: Fertilizer (from template) x RS plant dates (from template)
populate_fert_n_trt_factorial <- function(
    file_x, template_df, plant_dates, file_x_original) {
  
  template_df <- template_df %>% 
    dplyr::select(-c(NAME_1, NAME_2, lon, lat))  # Remove non-DSSAT columns
  
  fert_x <- dplyr::slice(file_x_original$`FERTILIZERS (INORGANIC)`, 0)
  f_ij <- 0
  for (i in seq_along(plant_dates)){
    for (j in 1:max(template_df$F)){  # Loop through all fertilizer levels
      f_ij <- f_ij + 1
      
      fert_x_ij <- template_df %>% 
        dplyr::filter(F == j) %>%
        mutate(FDATE = as.POSIXct(plant_dates[i] + F.dap),
               F = f_ij) %>%
        dplyr::select(-F.dap)
      
      fert_x <- bind_rows(fert_x, fert_x_ij)
    }
  }
  
  file_x$`FERTILIZERS (INORGANIC)` <- fert_x
  
  trt_x_original <-  file_x_original$`TREATMENTS                        -------------FACTOR LEVELS------------`
  trt_x <- dplyr::slice(trt_x_original, 0)
  trt_ij <- 0
  for (i in seq_along(plant_dates)){
    for (j in 1:max(template_df$F)){
      trt_ij <- trt_ij + 1
      trt_x_ij <- trt_x_original
      
      Tname <- template_df %>%
        dplyr::filter(F == j) %>%
        dplyr::select(FERNAME) %>%
        mutate(FERNAME = substr(FERNAME, 1, 9))
      
      trt_x_ij <- trt_x_ij %>%
        mutate(
          N = trt_ij,
          TNAME = paste(Tname[1, ], "@", format(plant_dates[i], "%m-%d"), sep= " "),
          MF = trt_ij,
          across(c(MH, MP, IC, SM), ~ i)
        )
      
      trt_x <- bind_rows(trt_x, trt_x_ij)
    }
  }
  file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` <- trt_x
  
  return(file_x)
}


# Get DSSAT crop code
get_DSSAT_crop_code <- function(Crop) {
  crops <- c("Maize", "Potato", "Rice", "Soybean", "Wheat", "Beans", "Cassava")
  cropcode_supported <- c("MZ", "PT", "RI", "SB", "WH", "BN", "CS")
  cropid <- which(crops == Crop)
  crop_code <- cropcode_supported[cropid]
  crop_code
}


# Produce a dataframe with coords of available soil data and RS planting dates
get_zone_coords_pdates <- function(
    country, useCaseName, Crop, zone, Soil_source, rs_schedule_df,
    datasourcing_path = "~/agwise-datasourcing/dataops/datasourcing") {
  
  if (Soil_source == "ISDA") soil_path <- paste0(
    datasourcing_path, "/Data/useCase_", country, "_", useCaseName, "/", Crop,
    "/result/geo_4cropModel/", zone, "/ISDA_SoilDEM_PointData_AOI_profile.RDS")
  if (Soil_source == "ISRIC") soil_path <- paste0(
    datasourcing_path, "/Data/useCase_", country, "_", useCaseName, "/", Crop,
    "/result/geo_4cropModel/", zone, "/SoilDEM_PointData_AOI_profile.RDS")
  
  Soil <- readRDS(soil_path)
  Soil <- na.omit(Soil) %>%
    rename(longitude = lon,
           latitude = lat)
  
  new_coords <- Soil %>%
    dplyr::select("longitude", "latitude", "NAME_1", "NAME_2") %>%
    mutate(longitude = round(longitude, 3),
           latitude = round(latitude, 3))
  
  new_coords <- new_coords %>%
    mutate(lat_lon = paste(latitude, longitude))
  
  rs_schedule_df <- rs_schedule_df %>% 
    mutate(longitude = round(longitude, 3),
           latitude = round(latitude, 3))
  
  merged <- inner_join(new_coords, rs_schedule_df, 
                       by = c("latitude", "longitude")) %>%
    unique()
  
  row.names(merged) <- NULL
  
  return(merged)
}


# Get number years from WTH File
get_number_years_from_WTH_file <- function(working_path, i) {
  wth_file <- DSSAT::read_wth(paste0(working_path, "/WHTE", formatC(width = 4, (as.integer(i)), flag = "0"), ".WTH"))
  number_years <- max(year(max(wth_file$DATE)) - year(min(wth_file$DATE)), 1)
  number_years
}


# Create list of fertilizer flags for the Simulation Controls DSSAT information
create_fertilizer_flags <- function(NPK_ranges = NULL, template_df = NULL) {
  # Default flags
  fert_list <- list(NITRO = "N", PHOSP = "N", POTAS = "N", FERTI = "N")
  
  # From NPK_ranges
  if (!is.null(NPK_ranges)) {
    fert_list$NITRO <- if (!is.null(NPK_ranges$N) && any(NPK_ranges$N != 0)) "Y" else "N"
    fert_list$PHOSP <- if (!is.null(NPK_ranges$P) && any(NPK_ranges$P != 0)) "Y" else "N"
    fert_list$POTAS <- if (!is.null(NPK_ranges$K) && any(NPK_ranges$K != 0)) "Y" else "N"
    
  # From template_df
  } else if (all(c("FAMN","FAMP","FAMK") %in% names(template_df))) {
    fert_list$NITRO <- if (any(template_df$FAMN > 0, na.rm = TRUE)) "Y" else "N"
    fert_list$PHOSP <- if (any(template_df$FAMP > 0, na.rm = TRUE)) "Y" else "N"
    fert_list$POTAS <- if (any(template_df$FAMK > 0, na.rm = TRUE)) "Y" else "N"
  }
  
  
  fert_list$FERTI <- if (any(unlist(fert_list[1:3]) == "Y")) "R" else "N"
  
  return(fert_list)
}


# Cardinal to ordinal for naming
ordinal <- function(x) {
  s <- ifelse(x %% 100 %in% 11:13, "th",
              ifelse(x %% 10 == 1, "st",
                     ifelse(x %% 10 == 2, "nd",
                            ifelse(x %% 10 == 3, "rd", "th"))))
  paste0(x, s)
}


# Produce Initial Conditions df that is common for all DSSAT experiment design approaches
get_filex_initial_conditions <- function(ex_profile, crop_code, plant_dates, file_x) {
  plant_dates <- sort(as.Date(plant_dates))
  n_pd <- length(plant_dates)
  
  ### Ensure ex_profile is ordered by SLB
  slb <- ex_profile$SLB[[1]]
  ord <- order(slb)
  
  ex_profile_sorted <- ex_profile
  
  list_cols <- sapply(ex_profile, is.list)
  
  ex_profile_sorted[list_cols] <- lapply(
    ex_profile[list_cols],
    function(col) list(col[[1]][ord])
  )
  
  n_layers <- length(slb)
  # TODO: So far, we have one IC for each PD
  n_ic <- n_pd
  
  fixed_SNH4 <- 0.6
  fixed_SNO3 <- 3
  
  ic_df <- file_x$`INITIAL CONDITIONS`
  
  ic_df <- ic_df[rep(1, n_ic), ]
  
  ic_df <- ic_df %>% 
    mutate(
      PCR = crop_code
    )
  ic_df$ICBL <- rep(list(sort(slb)), nrow(ic_df))
  ic_df$C <- 1:n_ic
  ic_df$ICDAT <- as.POSIXct(plant_dates %m-% months(1))
  ic_df$SNH4 <- rep(list(rep(fixed_SNH4, n_layers)), nrow(ic_df))
  ic_df$SNO3 <- rep(list(rep(fixed_SNO3, n_layers)), nrow(ic_df))
  ic_df$SH2O <- mapply(function(sdul, slll, index) {
    slll + ((sdul - slll) * index)
  }, ex_profile_sorted$SDUL, ex_profile_sorted$SLLL, MoreArgs = list(index = index_soilwat),
  SIMPLIFY = FALSE)
  
  ic_df
}


# Produce General df that is common for all DSSAT experiment design approaches
get_filex_general <- function(ex_profile, file_x) {
  gen_df <- file_x$GENERAL
  gen_df <- gen_df %>%
    mutate(
      SITE = ex_profile$SITE
    )
  
  gen_df
}


# Produce Fields df that is common for all DSSAT experiment design approaches
get_filex_fields <- function(ex_profile, file_x, i, wsta_prefix) {
  fields_df <- file_x$FIELDS
  fields_df <- fields_df %>%
    mutate(
      WSTA = paste0(wsta_prefix, formatC(
        width = 4, as.integer((i)), flag = "0")),
      ID_SOIL = paste0('TRAN', formatC(
        width = 5, as.integer((i)), flag = "0")),
      XCRD = ex_profile$LONG,
      YCRD = ex_profile$LAT
    )
  
  fields_df
}


# Produce Cultivars df that is common for all DSSAT experiment design approaches
get_filex_cultivars <- function(file_x, crop_code, varietyid, path.to.temdata, geneticfiles) {
  cname <- DSSAT::read_cul(file.path(path.to.temdata, paste0(geneticfiles, '.CUL'))) %>%
    dplyr::filter(`VAR#` == varietyid)
  cultivars_df <- file_x$CULTIVARS
  cultivars_df <- cultivars_df %>%
    mutate(
      CR = crop_code,
      INGENO = varietyid,
      CNAME = cname$VRNAME
    )
  
  cultivars_df
}


# Produce Planting Details df that is common for all DSSAT experiment design approaches
get_filex_plantdetails <- function(file_x, plant_dates) {
  plant_dates <- sort(as.Date(plant_dates))
  n_pd <- length(plant_dates)
  
  pd_df <- file_x$`PLANTING DETAILS`
  
  pd_df <- pd_df[rep(1, n_pd), ]
  
  pd_df$P <- 1:n_pd
  pd_df$PDATE <- as.POSIXct(plant_dates)
  pd_df$PLNAME <- paste(ordinal(1:n_pd), "plant date")
  
  pd_df
}


# Produce Harvest Details df that is common for all DSSAT experiment design approaches
get_filex_harvestdetails <- function(file_x, plant_dates) {
  plant_dates <- sort(as.Date(plant_dates))
  n_pd <- length(plant_dates)
  n_hd <- n_pd
  
  hd_df <- file_x$`HARVEST DETAILS`
  
  hd_df <- hd_df[rep(1, n_hd), ]
  
  hd_df$H <- 1:n_hd
  hd_df$HDATE <- as.POSIXct(max(plant_dates) %m+% months(8))
  
  hd_df
}


# Produce Simulation Controls df that is common for all DSSAT experiment design approaches
# fert_list: Y/N for nutrients. R/N for "FERTI". Check DSSAT R repo
get_filex_simulationcontrols <- function(
    file_x, plant_dates, number_years,
    fert_list = list(NITRO = "N", PHOSP = "N", POTAS = "N", FERTI = "R")) 
{
  plant_dates <- sort(as.Date(plant_dates))
  n_pd <- length(plant_dates)
  # TODO: So far, we have one SC for each PD
  n_sc <- n_pd
  
  sc_df <- file_x$`SIMULATION CONTROLS`
  
  sc_df <- sc_df[rep(1, n_sc), ]
  
  sc_df$N <- 1:n_sc
  sc_df$NYERS <- number_years
  sc_df$SDATE <- as.POSIXct(plant_dates %m-% months(1))
  sc_df$SNAME <- paste(ordinal(1:n_pd), "plant date")
  sc_df$FMOPT <- NULL
  sc_df$HFRST <- -99
  sc_df$NITRO <- fert_list$NITRO
  sc_df$PHOSP <- fert_list$PHOSP
  sc_df$POTAS <- fert_list$POTAS
  sc_df$FERTI <- fert_list$FERTI
  
  sc_df
}


# Produce Fertilizers Inorganic df that is common for all DSSAT experiment design approaches
# If no Fertilizers return NULL so there is no addition
get_filex_fertilizersinorganic <- function(
    file_x, plant_dates, template_df, NPK_ranges, longitude, latitude, varietyid,
    fert_list = NULL) {
  fi_df <- file_x$`FERTILIZERS (INORGANIC)`
  
  # Path: fertilizer from template file
  if(!is.null(template_df$FAMN)) {
    fi_df <- template_df %>%
      dplyr::filter(lon == longitude,
             lat == latitude)  # INGENO has been removed from template_df,
             # INGENO == varietyid)
    n_split_applications <- length(unique(fi_df$F.dap))
    
    # TODO: if plant_dates from template_df 
    # n_fi <- dim(fi_df)[1]
    fi_df <- fi_df[rep(1:nrow(fi_df), times = length(plant_dates)), ]
    row.names(fi_df) <- NULL
    
    n0 <- nrow(fi_df) / length(plant_dates)
    # fi_df$FDATE <- as.POSIXct(fi_df$F.dap + rep(plant_dates, each = n0))
    fi_df$FDATE_date <- as.Date(fi_df$F.dap + rep(plant_dates, each = n0))
    fi_df$FDATE <- as.integer(
      format(fi_df$FDATE_date, "%y")) * 1000 +
        as.integer(format(fi_df$FDATE_date, "%j"))
    
    fi_df <- fi_df %>% dplyr::select(-FDATE_date)
    
    fi_df$F <- rep(seq_len(dim(fi_df)[1]/n_split_applications), each = n_split_applications)
    
    fi_df <- fi_df %>% 
      dplyr::select(any_of(
        c("F", "FDATE", "FMCD", "FACD", "FDEP", "FAMN", "FAMP", "FAMK", "FAMC",
          "FAMO", "FOCD", "FERNAME")))
    return(fi_df)
    
  } else
    # Path: fertilizer from NPK_ranges
    if (exists("NPK_ranges") && !is.null(NPK_ranges)) {
      n_split_applications <- NPK_ranges$n_split_applications
      
      fi_df <- expand.grid(
        FAMN = NPK_ranges$N,
        FAMP = NPK_ranges$P,
        FAMK = NPK_ranges$K,
        plant_date = plant_dates,
        n_split = n_split_applications
      ) %>% 
        mutate(F = row_number())
      
      fi_expanded <- fi_df %>%
        mutate(
          FAMN = FAMN / n_split,
          FAMP = FAMP / n_split,
          FAMK = FAMK / n_split,
          pd_index = match(plant_date, plant_dates)
        ) %>%
        uncount(n_split, .id = "application_index") %>%
        mutate(
          F.dap = NPK_ranges$F.dap[application_index],
          FDATE = as.POSIXct(plant_date + F.dap),
          FERNAME = paste(
            ordinal(F), "fert",
            ordinal(application_index), "app",
            ordinal(pd_index), "pd"
          ),
          FMCD = NPK_ranges$FMCD,
          FACD = NPK_ranges$FACD,
          FDEP = NPK_ranges$FDEP,
          FAMC = NPK_ranges$FAMC,
          FAMO = NPK_ranges$FAMO,
          FOCD = NPK_ranges$FOCD
        ) %>%
        select(-c(application_index, plant_date, pd_index, F.dap)) %>%
        select(c(F, FDATE, FMCD, FACD, FDEP, FAMN, FAMP, FAMK, FAMC, FAMO, FOCD,
                 FERNAME))
      
      return(fi_expanded)
    } else {
      # No fertilizer in the experiment
      message("Continuing without modifying fertilizer tab in DSSAT template.")
      NULL
    }
}


# Produce Treatments df that is common for all DSSAT experiment design approaches
get_filex_treatments <- function(file_x, fert_list = NULL) {
  treatments_df <- file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`
  fi_df <- file_x$`FERTILIZERS (INORGANIC)`
  sc_df <- file_x$`SIMULATION CONTROLS`
  pd_df <- file_x$`PLANTING DETAILS`
  ic_df <- file_x$`INITIAL CONDITIONS`
  plant_dates <- pd_df$PDATE
  number_years <- unique(sc_df$NYERS)
  
  if (!is.null(fi_df)) {
    # Fertilizer levels already consider planting dates levels
    n_t <- max(fi_df$F)
    n_sc <- max(sc_df$N)
    treatments_df <- treatments_df[rep(1, n_t), ]
    
    treatments_df$N <- 1:n_t
    treatments_df$MF <- 1:n_t
    n_pd <- max(pd_df$P)
    fert_levels <- unique(gsub("\\s*\\d+(st|nd|rd|th) app", "", fi_df$FERNAME))
    pd_levels <- paste0(1:n_pd, c("st","nd","rd","th")[1:n_pd], " pd")
    if (length(fert_levels) == max(treatments_df$N)) {
      treatments_df$TNAME <- fert_levels
    } else {
      treat_names <- expand.grid(
        fert = fert_levels,
        pd  = pd_levels,
        stringsAsFactors = FALSE
      )
      treat_names$TNAME <- paste(treat_names$fert, treat_names$pd)
      treatments_df$TNAME <- treat_names$TNAME
      
    }

    # IC, MP, SM and MH are the same
    pd_index <- as.integer(sub(".*\\b(\\d+)(st|nd|rd|th) pd.*", "\\1",
                               treatments_df$TNAME))
    treatments_df$IC <- pd_index
    treatments_df$MP <- pd_index
    treatments_df$MH <- pd_index
    treatments_df$SM <- pd_index
    
    sc_df <- sc_df[rep(1, n_sc), ]
    sc_df$N <- 1:n_sc
    sc_df$NYERS <- number_years
    sc_df$SDATE <- as.POSIXct(plant_dates %m-% months(1))
    sc_df$SNAME <- paste(ordinal(1:n_pd), "plant date")
    sc_df$FMOPT <- NULL
    sc_df$HFRST <- -99
    sc_df$NITRO <- fert_list$NITRO
    sc_df$PHOSP <- fert_list$PHOSP
    sc_df$POTAS <- fert_list$POTAS
    sc_df$FERTI <- fert_list$FERTI
    
    return(treatments_df)
  } else if (is.null(fi_df)) {
    # Only Planting date is a treatment
    n_pd <-max(pd_df$P)
    n_t <- n_pd
    treatments_df <- treatments_df[rep(1, n_t), ]
    
    treatments_df$TNAME <- pd_df$PLNAME
    treatments_df$N <- 1:n_t
    treatments_df$IC <- 1:n_t
    treatments_df$MP <- 1:n_t
    treatments_df$MH <- 1:n_t
    return(treatments_df)
  }
}


# Ensure layers are correctly ordered
check_layers_order <- function(ex_profile) {
  ex_profile <- ex_profile %>%
    unnest(cols = everything()) %>%   # unnest all list-columns
    arrange(SLB)
  return(ex_profile)
}


# Get range of treatments
get_n_treatments <- function(
    template_df, Forecast, fertilizer, fert_factorial, fert_grid_RS,
    NPK_ranges = NULL) {
  
  if (fert_factorial) {
    n_applications <- length(unique(template_df$F.dap))
    
    one_location_levels <- template_df %>%
      dplyr::filter(lon == template_df$lon[1],
             lat == template_df$lat[1])
    n_fert <- dim(one_location_levels)[1] / n_applications
    # Columns that define the RS planting date
    n_pd <- length(colnames(template_df)[grep("^q", colnames(template_df))]) + 1
    TRT <- 1:(n_fert * n_pd)
  } else if (!is.null(NPK_ranges)) {
    n_pd <- length(colnames(template_df)[grep("^q", colnames(template_df))]) + 1
    NPK_ranges2 <- NPK_ranges
    NPK_ranges2$F.dap <- NULL
    TRT <- 1:(dim(expand_grid(NPK_ranges2))[1] * n_pd)
  }
    else {
    message("get_n_treatments() not implemented for your type of experiment")
    stop()
  }
  
  return(TRT)
}

