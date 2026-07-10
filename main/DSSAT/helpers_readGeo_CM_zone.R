###############################################################################
# Script: helpers_readGeo_CM_zone.R
# Purpose: Helper functions for preparing DSSAT weather and soil files.
#
# Authors: Alvaro Carmona-Cabrero, Jemal S. Ahmed (jemal.ahmed@cgiar.org)
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-06-07
###############################################################################


# Read RS data and filter observations. Filtering seems unnecessary due to data storage (by zone)
read_and_filter <- function(file, zone = NA, level2 = NA) {
  x <- readRDS(file)
  # Standardize column names
  if ("Zone" %in% names(x)) names(x)[names(x) == "Zone"] <- "NAME_1"
  if ("lat" %in% names(x)) names(x)[names(x) == "lat"] <- "latitude"
  if ("lon" %in% names(x)) names(x)[names(x) == "lon"] <- "longitude"
  
  if ("country" %in% names(x)) x <- subset(x, select = -country)
  
  # Remove rows with NA values for Soil data
  if (grepl("Soil", tools::file_path_sans_ext(basename(file)))) {
    x <- na.omit(x)
  }
  
  if (!is.na(zone)) {  # Filter by zone
    x <- x[x$NAME_1 == zone, ]
  }
  if (!is.na(level2)) {
    x <- x[x$NAME_2 == level2, ]    # Filter by level2
  }
  x
}


# Define pathIn and check for existence
define_pathIn <- function(general_pathIn, level2, zone, pathIn_zone, Forecast, 
                          create_path = FALSE) {
  if (pathIn_zone && Forecast) {
    pathIn <- file.path(general_pathIn, zone)
    if (!dir.exists(pathIn)) {
      stop(
        "Input path does not exist: ", pathIn, "\n",
        "Please provide a forecast folder containing the required RDS input data."
      )
    }
    return(paste0(pathIn, "/"))
  }
  
  if (pathIn_zone) {
    if (!is.na(level2) && !is.na(zone)) {
      pathIn <- file.path(general_pathIn, zone, level2)
    } else if (is.na(level2) && !is.na(zone)) {
      # Common path
      pathIn <- file.path(general_pathIn, zone)
      if (create_path == TRUE && !dir.exists(pathIn)) {
        dir.create(pathIn, recursive = TRUE)
      }
    } else if (!is.na(level2) && is.na(zone)) {
      stop("You need to define first a zone (administrative level 1) ",
           "to be able to get data for level 2.")
    } else {
      pathIn <- general_pathIn
    }
  } else {
    pathIn <- general_pathIn
  }
  if (!dir.exists(pathIn)) {
    dir.create(pathIn, recursive = TRUE)
    stop(
      "Input path does not exist: ", pathIn, "\n",
      "Please provide a path containing the required RDS input data."
    )
  }
  if (!Forecast) {
    paste0(pathIn, "/")
  } else if (Forecast) {
    pathIn
  }
}


### Define output path ----
define_pathOUT <- function(path.to.extdata, i, zone = NA, level2 = NA) {
  if (!is.na(level2) && is.na(zone)) {
    stop(
      "You need to define a zone (administrative level 1) ",
      "to get data for level 2 (administrative level 2)."
    )
  }
  exte_id <- paste0(
    "EXTE",
    formatC(as.integer(i), width = 4, flag = "0")
  )
  pathOUT <- if (!is.na(zone) && !is.na(level2)) {
    file.path(path.to.extdata, zone, level2, exte_id)
  } else if (!is.na(zone)) {
    file.path(path.to.extdata, zone, exte_id)
  } else {
    file.path(path.to.extdata, exte_id)
  }
  if (!dir.exists(pathOUT)) {
    dir.create(pathOUT, recursive = TRUE)
  }
  return(pathOUT)
}


# Get metadata for weather (Rainfall) and Soil data
get_metadata <- function(AOI, Rainfall, Soil) {
  if(AOI) {
    metaDataWeather <- Rainfall %>%
      select(any_of(c("longitude", 'latitude', "startingDate", "endDate",
                      "NAME_1", "NAME_2")))
  } else {
    metaDataWeather <- Rainfall %>%
      select(any_of(c(
      "longitude", 'latitude', "startingDate", "endDate", "NAME_1", "NAME_2", 
        "yearPi", "yearHi", "pl_j", "hv_j")))
  }
  metaData_Soil <- Soil %>% 
    select(all_of(c("longitude", "latitude", "NAME_1", "NAME_2")))
  # General metadata that has unique virtual experiments with unique weather, soil, planting and harvesting date
  metaData <- merge(metaDataWeather, metaData_Soil)
  metaData
}


# Filter weather data sets by metadata
filter_by_metadata <- function(weather_data, metaData) {
  merge(metaData, weather_data)
}


# Filter Soil data set by metadata
filter_soil_by_meta <- function(Soil, metaData) {
  merge(unique(metaData[, c("longitude", "latitude", "NAME_1", "NAME_2")]),
        Soil)
}


# Get variable name with depth
depth_names <- function(var_name, depths) {
  if (length(depths) == 2) {
    list_depthnames <- list("20" = "0-20cm", "50" = "20-50cm")
  } else {
    list_depthnames <- list(
      "5" = "0-5cm", "15" = "5-15cm", "30" = "15-30cm", 
      "60" = "30-60cm", "100" = "60-100cm", "200" = "100-200cm"
    )
  }
  
  sapply(depths, function(d) {
    # If d is already in the values, use it directly
    if (d %in% list_depthnames) {
      paste0(var_name, "_", d)
    } else {
      # O/w, treat d as a key
      val <- list_depthnames[[as.character(d)]]
      if (is.null(val)) val <- d  # fallback if not found
      paste0(var_name, "_", val)
    }
  })
}


#' Evaporation limit function from Ritchie et al. (1989); cited in Allen et al. (2005)
#' @param clay1 Clay percentage for the top soil horizon
#' @param sand1 Sand percentage for the top soil horizon
#' @keywords internal
#' @export
slu1 <- function(clay1, sand1) {
  ifelse(sand1 >= 80, (20 - 0.15 * sand1),
         ifelse(clay1 >= 50, (11 - 0.06 * clay1),
                (8 - 0.08 * clay1)))
}


#' @description Texture triangle as equations. Equations taken from apsimx package
#' @details It requires the silt and clay percentages to define the texture class
#' Title getting the texture class
#'
#' @param usda_clay percentage of clay (as index or /100)
#' @param usda_silt percentage of silt (as index or /100)
#' @return class (texture class)
#' @examples texture_class(clay,silt)
#'
texture_class <- function (usda_clay, usda_silt) {
  
  if(usda_clay < 0 || usda_clay > 1) stop("usda_clay should be between 0 and 1")
  if(usda_silt < 0 || usda_silt > 1) stop("usda_silt should be between 0 and 1")
  
  intl_clay <- usda_clay
  intl_silt <- usda_silt
  intl_sand <- 1.0 - intl_clay - intl_silt
  
  if ((intl_sand < 0.75 - intl_clay) && (intl_clay >= 0.40)) {
    class <- "silty clay"
  } else if ((intl_sand < 0.75 - intl_clay) && (intl_clay >= 0.26)) {
    class <- "silty clay loam"
  } else if (intl_sand < 0.75 - intl_clay) {
    class <- "silty loam"
  } else if ((intl_clay >= 0.40 + (0.305 - 0.40) / (0.635 - 0.35) * (intl_sand - 0.35))
             && (intl_clay < 0.50 + (0.305 - 0.50) / (0.635 - 0.50) * (intl_sand - 0.50))) {
    class <- "clay"
  } else if (intl_clay >= 0.26 + (0.305 - 0.26) / (0.635 - 0.74) * (intl_sand - 0.74)) {
    class <- "sandy clay"
  } else if ((intl_clay >= 0.26 + (0.17 - 0.26) / (0.83 - 0.49) * (intl_sand - 0.49)) 
             && (intl_clay < 0.10 + (0.305 - 0.10) / (0.635 - 0.775) * (intl_sand - 0.775))) {
    class <- "clay loam"
  } else if (intl_clay >= 0.26 + (0.17 - 0.26) / (0.83 - 0.49) * (intl_sand - 0.49)) {
    class <- "sandy clay loam"
  } else if ((intl_clay >= 0.10 + (0.12 - 0.10) / (0.63 - 0.775) * (intl_sand - 0.775)) &&
             (intl_clay < 0.10 + (0.305 - 0.10) / (0.635 - 0.775) * (intl_sand - 0.775))) {
    class <- "loam"
  } else if (intl_clay >= 0.10 + (0.12 - 0.10) / (0.63 - 0.775) * (intl_sand - 0.775)) {
    class <- "sandy loam"
  } else if (intl_clay < 0.00 + (0.08 - 0.00) / (0.88 - 0.93) * (intl_sand - 0.93)) {
    class <- "loamy sand"
  } else {
    class <- "sand"
  }
  return(class)
}


# Initialize folders for varieties
copy_WTH_SOIL_data_for_variety <- function(
    country, useCaseName, Crop, project_root, AOI = FALSE, varietyids) {
  for (varietyid in varietyids[-1]) {
    usecase_dir <- project_usecase_dir(project_root, country, useCaseName)
    if (AOI) {
      from_path <- file.path(
        usecase_dir, Crop, "transform", "DSSAT", "AOI", varietyids[1])
      to_path <- file.path(
        usecase_dir, Crop, "transform", "DSSAT", "AOI", varietyid)  
    } else if (!AOI) {
      from_path <- file.path(
        usecase_dir, Crop, "transform", "DSSAT", "fieldData", varietyids[1])
      to_path <- file.path(
        usecase_dir, Crop, "transform", "DSSAT", "fieldData", varietyid)
    }
    cmd <- sprintf('cp -r "%s/" "%s/"', from_path, to_path)
    system(cmd)
  }
}


# Select weather data for one pixel 
filter_by_coord <- function(weather_df, coords, i) {
  weather_df[weather_df$longitude == coords$longitude[i] &
               weather_df$latitude  == coords$latitude[i], ]
}


# Pivot long weather data
pivot_weather <- function(df, value_name, AOI = TRUE) {

  id_cols <- if (AOI) {
    c("longitude", "latitude", "NAME_1", "NAME_2",
      "startingDate", "endDate", "ID")
  } else {
    c("longitude", "latitude", "startingDate", "endDate",
      "yearPi", "yearHi", "pl_j", "hv_j",
      "NAME_1", "NAME_2")
  }

  out <- tidyr::pivot_longer(
    df,
    cols = -any_of(id_cols),
    names_to = c("Variable", "Date"),
    names_sep = "_",
    values_to = value_name
  )  %>%
    dplyr::select(-any_of("ID"))

  if (AOI) {
    out <- unique(dplyr::select(
      out, -any_of(c("Variable", "startingDate", "endDate"))))
  } else {
    out <- dplyr::select(out, -any_of("Variable"))
  }

  out
}


# Build Weather file
build_DSSAT_WTH <- function(TMAX, TMIN, SRAD, RAIN) {

  tst <- na.omit(Reduce(merge, list(TMAX, TMIN, SRAD, RAIN)))

  tst <- tst %>%
    mutate(
      DATE = as.POSIXct(Date, format = "%Y-%m-%d", tz = "UTC")
    ) %>%
    dplyr::select(DATE, TMAX, TMIN, SRAD, RAIN) %>%
    mutate(across(c(TMAX, TMIN, SRAD, RAIN), as.numeric)) %>%
    rowwise() %>%
    mutate(
      TMAX = max(TMAX, TMIN),
      TMIN = min(TMAX, TMIN)
    ) %>%
    ungroup()

  tst
}


# Get general information table for DSSAT WTH file
get_DSSAT_WTH_header <- function(tst, location, i) {
  # Calculate long-term average temperature (TAV)
  tav <- tst %>%
    summarise(TAV = mean((TMAX + TMIN) / 2, na.rm = TRUE))
  
  # Calculate monthly temperature amplitude (AMP)
  amp <- tst %>%
    mutate(month = lubridate::month(DATE)) %>%
    group_by(month) %>%
    dplyr::summarise(monthly_avg = mean((TMAX + TMIN) / 2, na.rm = TRUE)) %>%
    dplyr::summarise(AMP = (max(monthly_avg) - min(monthly_avg)) / 2)
  
  # Location name
  INS <- toupper(substr(location, start = 1, stop = 4))
  
  general_new <- tibble(
    INSI = INS,
    LAT = as.numeric(coords[i, 2]),
    LONG = as.numeric(coords[i, 1]),
    TAV = tav,
    AMP = amp,
    REFHT = 2,
    WNDHT = 2
  )
  
  general_new
}


# Get var profile values
get_depth_var <- function(Soil, lon, lat, var, Depth, scale = 1, round_digits = NULL) {
  x <- as.numeric(
    Soil[Soil$longitude == lon & Soil$latitude == lat, 
         depth_names(var, Depth)]) / scale
  
  if (!is.null(round_digits)) {
    x <- round(x, round_digits)
  }
  
  x
}


# Get var value for non-depth dependent vars
get_site_var <- function(Soil, lon, lat, var, scale = 1, round_digits = NULL) {
  x <- as.numeric(Soil[Soil$longitude == lon & Soil$latitude == lat, var]) / scale
  
  if (!is.null(round_digits)) {
    x <- round(x, round_digits)
  }
  
  x
}


# Get soil texture parameters
get_texture_params <- function(LCL, LSI, Sand, Depth) {
  
  texture <- texture_class(LCL[1] / 100, LSI[1] / 100)
  
  textureClasses <- c("clay", "silty clay", "sandy clay", "clay loam",
                      "silty clay loam", "sandy clay loam", "loam",
                      "silty loam", "sandy loam", "silt", "loamy sand",
                      "sand", "NO DATA")
  
  textureClasses_sum <- c("C", "SIC", "SC", "CL", "SICL", "SCL", "L",
                          "SIL", "SL", "SI", "LS", "S", "NO DATA")
  
  # Hard coded from Soil Conservation Services (NRCS) and SWAT probably
  Albedo <- c(0.12, 0.12, 0.13, 0.13, 0.12, 0.13, 0.13, 0.14,
              0.13, 0.13, 0.16, 0.19, 0.13)
  
  # Assumed a certain land cover but which one?
  CN2 <- c(73, 73, 73, 73, 73, 73, 73, 73, 68, 73, 68, 68, 73)
  
  # Kept here but it was never used 
  SWCON <- c(0.25, 0.3, 0.3, 0.4, 0.5, 0.5, 0.5, 0.5, 0.6, 0.5, 0.6, 0.75, 0.5)
  
  # Evaporation limit function from Ritchie et al. (1989); cited in Allen et al. (2005)
  SLU <- slu1(clay1 = LCL[1],
              sand1 = Sand[1])
  
  wtc <- which(textureClasses == texture)
  
  # Soil root growth factor. Based on formula from DSSAT. Not the best option for soils with duripan or other root growth limitations
  layer_center <- c(Depth[1]/2, (Depth[-1] - Depth[-length(Depth)]) / 2 + Depth[-length(Depth)])
  RGF = ifelse(Depth<=15, 1,1 * exp(-0.02 * layer_center))
  
  list(
    texture = texture,
    texture_soil = textureClasses_sum[wtc],
    ALB = Albedo[wtc],
    LRO = CN2[wtc],
    SLU = SLU,
    RGF = RGF
  )
}


# Modify DSSAT Soil template
modify_ex_profile <- function(
    template_ex_profile, texture_soil, texture, location, country, lat, lon,
    ALB, SLU, LRO, LDR, Depth, LL15, SAT, DUL, SSS, BDM, LOC, LCL, LSI, LNI,
    LHW, CEC, RGF, i, soil_p = FALSE, P_data = NULL
) {
  soilid <- template_ex_profile %>%
    mutate(PEDON = paste0('TRAN', formatC(width = 5, (as.integer(i)), flag = "0")),
           SOURCE = "ISRIC V2",
           TEXTURE = texture_soil,
           DESCRIPTION = texture,
           SITE= location,
           COUNTRY = country,
           LAT = lat,
           LONG = lon,
           SALB = list(ALB),
           SLU1 = list(SLU),
           SLRO = list(LRO),
           # SMPX = "SA013",  # Mehlich-3. Requires more variables for running P.
           SMPX = "SA001",  # Olsen. Requires conversion from Mehlich-3 (SoilGrids 0-30cm) using an empirical equation in main/RS/get_geo_spatial_data_w_phosphorus.R
           SLDR = list(LDR),
           SLB = list(Depth),
           SLMH = list(rep(-99, length(Depth))),  # No data about master horizon
           SLLL = list(LL15),
           SSAT = list(SAT),
           SDUL = list(DUL),
           SSKS = list(SSS),
           SBDM = list(BDM),
           SLOC = list(LOC),
           SLCL = list(LCL),
           SLSI = list(LSI),
           SLNI = list(LNI),
           SLHW = list(LHW),
           SCEC = list(CEC),
           SRGF = list(RGF),
           # Phosphorus variables
           SLPX = if (soil_p) list(P_data$SLPX) else list(NULL),
           SLPT = if (soil_p) list(P_data$SLPT) else list(NULL),
           # Additional Mehlich-3 related variables 
           SLPO = if (soil_p) list(P_data$SLPO) else list(NULL),
           CACO3 = if (soil_p) list(P_data$CACO3) else list(NULL),
           SLAL = if (soil_p) list(P_data$SLAL) else list(NULL),
           SLFE = if (soil_p) list(P_data$SLFE) else list(NULL),
           SLMN = if (soil_p) list(P_data$SLMN) else list(NULL),
           SLPA = if (soil_p) list(P_data$SLPA) else list(NULL),
           SLPB = if (soil_p) list(P_data$SLPB) else list(NULL),
           SLKE = if (soil_p) list(P_data$SLKE) else list(NULL),
           SLMG = if (soil_p) list(P_data$SLMG) else list(NULL),
           SLNA = if (soil_p) list(P_data$SLNA) else list(NULL),
           SLSU = if (soil_p) list(P_data$SLSU) else list(NULL),
           SLEC = if (soil_p) list(P_data$SLEC) else list(NULL),
           SLCA = if (soil_p) list(P_data$SLCA) else list(NULL),
           
           
           SLCF = list(SLCF[[1]][1:length(Depth)]),
           SLHB = list(SLHB[[1]][1:length(Depth)]),
           SADC = list(SADC[[1]][1:length(Depth)]))
  soilid
}


### Choose soil variable name
# Function to get the correct variable name depending on the dataset
get_var_name <- function(var, Depth) {
  # Mapping of variable names for each dataset
  var_map <- list(
    ISDA = list(
      PWP = "PWP",
      FC = "FC",
      SWS = "SWS",
      KS = "KS",
      bdod = "db.od",
      soc = "oc",
      clay = "clay.tot.psa",
      silt = "silt.tot.psa",
      sand = "sand.tot.psa",
      nitrogen = "n.tot.ncs",
      P = "p",  # Extractable P
      phh2o = "ph.h2o",
      cec = "ecec.f"
    ),
    ISRIC = list(
      PWP = "PWP",
      FC = "FC",
      SWS = "SWS",
      KS = "KS",
      bdod = "bdod",
      soc = "soc",
      clay = "clay",
      silt = "silt",
      sand = "sand",
      nitrogen = "nitrogen",
      P = "P",  # Extractable P
      Ptot = "Ptot",
      phh2o = "phh2o",
      cec = "cec"
    )
  )
  
  # Detect dataset based on Depth length
  dataset <- if (length(Depth) == 2) "ISDA" else "ISRIC"
  
  # Extract variable mapping for the dataset
  dataset_vars <- var_map[[dataset]]
  
  # Return mapped variable name
  if (!is.null(dataset_vars[[var]])) {
    return(dataset_vars[[var]])
  } else {
    stop(paste("Variable", var, "not found in dataset", dataset))
  }
}

# TODO Compare this function to the one in common_functions.R and see if they can be merged or if one can be removed.
# Produce AOI_GPS.RDS file in a project subdirectory
getGridCoordinates <- function(
    country, useCaseName, Crop, project_root, resltn = 0.05, provinces = NULL, 
    district = NULL) { 
  
  pathOut <- file.path(
    project_usecase_dir(project_root, country, useCaseName),
    Crop, "data_curation", country)
  
  if (!dir.exists(pathOut)) {
    dir.create(file.path(pathOut), recursive = T)
  }
  
  ## get country abbreviation to used in gdam function
  # countryCC <- countrycode(country, origin = 'country.name', destination = 'iso3c')
  
  ## read the relevant shape file from gdam to be used to crop the global data
  countrySpVec <- geodata::gadm(country, level = 2, path = '.')
  
  if(!is.null(provinces)){
    level3 <- countrySpVec[countrySpVec$NAME_1 %in% provinces ]
  }else if (!is.null(district)){
    level3 <- countrySpVec[countrySpVec$NAME_2 %in% district, ]
  }else{
    level3 <- countrySpVec
  }
  
  plot(countrySpVec)
  plot(level3, add = T, col = "green")
  
  xmin <- ext(level3)[1]
  xmax <- ext(level3)[2]
  ymin <- ext(level3)[3]
  ymax <- ext(level3)[4]
  
  ## define a rectangular area that covers the whole study area (with buffer of 10 km around)
  lon_coors <- unique(round(seq(xmin - 0.1, xmax + 0.1, by = resltn),
                            digits = 3))
  lat_coors <- unique(round(seq(ymin - 0.1, ymax + 0.1, by = resltn),
                            digits = 3))
  rect_coord <- as.data.frame(expand.grid(x = lon_coors, y = lat_coors))
  
  if(resltn == 0.05){
    rect_coord$x <- floor(rect_coord$x * 10) / 10 + ifelse(
      rect_coord$x - (floor(rect_coord$x * 10) / 10) < 0.05, 0.025, 0.075)
    rect_coord$y <- floor(rect_coord$y * 10) / 10 + ifelse(
      abs(rect_coord$y) - (floor(abs(rect_coord$y) * 10) / 10) < 0.05, 0.025, 0.075)
  }
  rect_coord <- unique(rect_coord[, c("x", "y")])
  # }else if (resltn == 0.01) {
  #   rect_coord$x <- floor(rect_coord$x*100)/100
  #   rect_coord$y <- floor(rect_coord$y*100)/100
  #   rect_coord <- unique(rect_coord[,c("x", "y")])
  # }else{
  #  names(rect_coord) <- c("x", "y")
  # }
  
  State_LGA <- as.data.frame(raster::extract(countrySpVec, rect_coord))
  State_LGA$lon <- rect_coord$x
  State_LGA$lat <- rect_coord$y
  State_LGA$country <- country
  
  State_LGA <- unique(State_LGA[, c("country", "NAME_1", "NAME_2", "lon", "lat")])
  
  if(!is.null(provinces)){
    State_LGA <- droplevels(State_LGA[State_LGA$NAME_1 %in% provinces, ])
  }else if (!is.null(district)){
    State_LGA <- droplevels(State_LGA[State_LGA$NAME_2 %in% district, ])}
  
  State_LGA <- droplevels(State_LGA[!is.na(State_LGA$NAME_2), ])
  
  saveRDS(State_LGA, paste0(pathOut, "AOI_GPS.RDS"))
  
  return(State_LGA)
}


# Format Depth ("0-20cm", "20-50cm")
depths_to_numeric <- function(Depth) {
  if (is.numeric(Depth)) {
    return(Depth)
  }
  
  max_depths <- strsplit(gsub("cm", "", Depth), "-")
  max_depths <- as.numeric(sapply(max_depths, `[`, 2))
  max_depths
}


# Check for ISDA Soil data. If any zone missing, run script to produce it
check_and_get_ISDA_RDS <- function(
    country, useCaseName, Crop, project_root, Soil_source = "ISRIC",
    inputData = NULL, datasourcing_path = "~/agwise-datasourcing/dataops/datasourcing"
                                   ) {
  if (Soil_source == "ISRIC") {
    message("Skipping producing ISDA files.")
    return(invisible(NULL))
  }
  inputData <- load_or_generate_inputData(
    country = country, useCaseName = useCaseName, Crop = Crop, 
    project_root = project_root, inputData = NULL)
  
  # Get the unique provinces
  provinces <- unique(inputData$NAME_1)
  
  # Flag to track if any RDS file is missing
  missing_file <- FALSE
  
  # Loop through each province
  for (prov in provinces) {
    
    # Build general path
    general_pathIn <- paste0(
      datasourcing_path, "/Data/useCase_", country, "_",
      useCaseName, "/", Crop, "/result/geo_4cropModel"
    )
    
    # Define the full path for this province
    pathIn <- define_pathIn(general_pathIn, level2 = NA, zone = prov,
                            pathIn_zone = TRUE, Forecast = FALSE, create_path = TRUE)
    
    province_Soil_data_path <- paste0(pathIn, "/ISDA_SoilDEM_PointData_AOI_profile.RDS")
    
    # Check if RDS file exists
    if (!file.exists(province_Soil_data_path)) {
      missing_file <- TRUE
      break  # No need to continue checking if one is missing
    }
  }
  
  # If any RDS file is missing, call the function
  if (missing_file) {
    message("One or more RDS files missing. Running get_ISDA_soilRDS()...")
    get_ISDA_soilRDS(country = country, useCaseName = useCaseName, 
                     Crop = Crop, project_root = project_root)
  } else {
    message("All ISDA RDS files exist.")
  }
}

# Simple conversion from Mehlich3 P to Olsen P
mehlich3_to_olsen <- function(mehlich3_P){
  # Equations from: https://www.nature.com/articles/s41597-023-02022-4
  soil_calcareous <- FALSE
  # TODO: add logic for calcareous or soil pH
  if (!soil_calcareous) olsen_P <- 0.47 * mehlich3_P + 2.4
  if (soil_calcareous) olsen_P <- 0.41 * mehlich3_P + 1.1
  return(olsen_P)
}


# Convert ISDA units to ISRIC units
convert_ISDA_units <- function(df) {
  
  db_cols <- grep("^db\\.od", names(df), value = TRUE)
  df[db_cols] <- lapply(df[db_cols], function(x) round(x / 100, 2))
  
  # Later N is scaled by 10. With this ISDA is in the same units as ISRIC
  n_cols <- grep("^n\\.tot\\.ncs", names(df), value = TRUE)
  df[n_cols] <- lapply(df[n_cols], function(x) x / 1000)
  
  # back-transform ISDA log-scaled soc AND scaling by additional /10 so it is in the same units as ISRIC
  oc_cols <- grep("^oc\\_", names(df), value = TRUE)
  df[oc_cols] <- lapply(df[oc_cols], function(x) {
    expm1(x / 10) * 10
  })
  
  p_cols <- grep("^p\\_", names(df), value = TRUE)
  df[p_cols] <- lapply(df[p_cols], function(x) mehlich3_to_olsen(x))
  
  df
}


# Produce ISDA RDS objects from server data
get_ISDA_soilRDS <- function(
    country, useCaseName, Crop, project_root, inputData = NULL) {
  
  baseSoilPath <- file.path(project_root, project_data_dir(project_root), "global", "soil")
  shapefileHC <- st_read(file.path(baseSoilPath, "HC27", "HC27 CLASSES.shp"), quiet = T) %>%
    st_make_valid()
  
  baseSoilPath <- file.path(project_root, project_data_dir(project_root), "global", "soil", "iSDA")
  listRaster_soil <- list.files(path = baseSoilPath, pattern = ".tif$")
  Layers_soil <- terra::rast(paste(baseSoilPath, listRaster_soil, sep = "/"))
  
  
  inputData <- load_or_generate_inputData(
    country = country, useCaseName = useCaseName, Crop = Crop, 
    project_root = project_root, inputData = NULL)
  
  countryShp <- geodata::gadm(country, level = 2, path = '.')
  
  gpsPoints <- inputData[, c("lon", "lat")]
  gpsPoints$lon <- as.numeric(gpsPoints$lon)
  gpsPoints$lat <- as.numeric(gpsPoints$lat)
  
  areasCovered <- unique(inputData$NAME_2)
  areasCovered <- areasCovered[!is.na(areasCovered)]
  
  for(aC in areasCovered) {
    print(aC)
    countryShpA <- countryShp[countryShp$NAME_2 == aC]
    croppedLayer_soil <- terra::crop(Layers_soil, countryShpA)
    
    depths <- c("0-20cm", "20-50cm")  
    
    ### SOM as function of OC
    for(d in depths) {
      croppedLayer_soil[[paste0("SOM_", d)]] <- (croppedLayer_soil[[paste0("oc_", d)]] * 2) / 10
    }
    
    ### PWP (permanent wilting point)
    for(d in depths) {
      croppedLayer_soil[[paste0("PWP_", d)]] <- (-0.024 * croppedLayer_soil[[paste0("sand.tot.psa_", d)]] / 100) + 0.487 *
        croppedLayer_soil[[paste0("clay.tot.psa_", d)]] / 100 + 0.006 * croppedLayer_soil[[paste0("SOM_", d)]] + 
        0.005 * (croppedLayer_soil[[paste0("sand.tot.psa_", d)]] / 100 * croppedLayer_soil[[paste0("SOM_", d)]]) - 
        0.013 * (croppedLayer_soil[[paste0("clay.tot.psa_", d)]] / 100 * croppedLayer_soil[[paste0("SOM_", d)]]) +
        0.068 * (croppedLayer_soil[[paste0("sand.tot.psa_", d)]] / 100 * croppedLayer_soil[[paste0("clay.tot.psa_", d)]] / 100 ) + 0.031
      croppedLayer_soil[[paste0("PWP_", d)]] <- (croppedLayer_soil[[paste0("PWP_", d)]] + (0.14 * croppedLayer_soil[[paste0("PWP_", d)]] - 0.02))
    }
    
    ### FC (field capacity)
    for(d in depths) {
      croppedLayer_soil[[paste0("FC_", d)]] <- -0.251 * croppedLayer_soil[[paste0("sand.tot.psa_", d)]] / 100 + 0.195 * 
        croppedLayer_soil[[paste0("clay.tot.psa_", d)]] / 100 + 0.011 * croppedLayer_soil[[paste0("SOM_", d)]] + 
        0.006 * (croppedLayer_soil[[paste0("sand.tot.psa_", d)]] / 100 * croppedLayer_soil[[paste0("SOM_", d)]]) - 
        0.027 * (croppedLayer_soil[[paste0("clay.tot.psa_", d)]] / 100 * croppedLayer_soil[[paste0("SOM_", d)]]) + 
        0.452 * (croppedLayer_soil[[paste0("sand.tot.psa_", d)]] / 100 * croppedLayer_soil[[paste0("clay.tot.psa_", d)]] / 100) + 0.299
      croppedLayer_soil[[paste0("FC_", d)]] <- (croppedLayer_soil[[paste0("FC_", d)]] + (1.283 * croppedLayer_soil[[paste0("FC_", d)]] ^ 2 - 0.374 * croppedLayer_soil[[paste0("FC_", d)]] - 0.015))
      
    }
    
    ### SWS (soil water at saturation)
    for(d in depths) {
      croppedLayer_soil[[paste0("SWS_", d)]] <- 0.278 * (croppedLayer_soil[[paste0("sand.tot.psa_", d)]] / 100) + 0.034 *
        (croppedLayer_soil[[paste0("clay.tot.psa_", d)]] / 100) + 0.022 * croppedLayer_soil[[paste0("SOM_", d)]] -
        0.018 * (croppedLayer_soil[[paste0("sand.tot.psa_", d)]] / 100 * croppedLayer_soil[[paste0("SOM_", d)]]) - 0.027 *
        (croppedLayer_soil[[paste0("clay.tot.psa_", d)]] / 100 * croppedLayer_soil[[paste0("SOM_", d)]])-
        0.584 * (croppedLayer_soil[[paste0("sand.tot.psa_", d)]] / 100 * croppedLayer_soil[[paste0("clay.tot.psa_", d)]] / 100) + 0.078
      croppedLayer_soil[[paste0("SWS_", d)]] <- (croppedLayer_soil[[paste0("SWS_", d)]] + (0.636*croppedLayer_soil[[paste0("SWS_", d)]] - 0.107))
      croppedLayer_soil[[paste0("SWS_", d)]] <- (croppedLayer_soil[[paste0("FC_", d)]] + croppedLayer_soil[[paste0("SWS_", d)]] - (0.097 * croppedLayer_soil[[paste0("sand.tot.psa_", d)]] / 100) + 0.043)
      
    }
    
    ### KS (saturated conductivity) (mm/h)
    for(d in depths) {
      b = (log(1500) - log(33))/(log(croppedLayer_soil[[paste0("FC_", d)]]) - log(croppedLayer_soil[[paste0("PWP_", d)]]))
      lambda <- 1 / b
      croppedLayer_soil[[paste0("KS_", d)]] <- 1930 * ((croppedLayer_soil[[paste0("SWS_", d)]] - croppedLayer_soil[[paste0("FC_", d)]]) ^ (3 - lambda))
    }
    
    soilData <- c(croppedLayer_soil)
    
    if(aC == areasCovered[1]) {
      soilData_allregion <- soilData
    } else {
      soilData_allregion <- merge(soilData_allregion, soilData)
    }
    
  }
  
  pointDataSoil <- as.data.frame(raster::extract(soilData_allregion, gpsPoints))
  pointDataSoil <- subset(pointDataSoil, select = -c(ID))
  pointDataSoil <- cbind(inputData,
                         pointDataSoil)
  
  pointDataSoil <- convert_ISDA_units(pointDataSoil)
  
  coordinates_df <- data.frame(lat = pointDataSoil$lat, lon = pointDataSoil$lon)
  coordinates_sf <- st_as_sf(coordinates_df, coords = c("lon", "lat"), crs = 4326)
  intersecting_polygons <- st_join(coordinates_sf, shapefileHC)
  # Extract the geometry (latitude and longitude) from the 'joined_data' object
  intersecting_polygons <- intersecting_polygons %>%
    mutate(lon = st_coordinates(intersecting_polygons)[, "X"], 
           lat = st_coordinates(intersecting_polygons)[, "Y"])
  intersecting_polygons <- as.data.frame(intersecting_polygons)
  intersecting_polygons$geometry <- NULL
  intersecting_polygons$ID <- NULL
  
  
  # Join the LDR (drainage rate) values to the intersecting_polygons data
  LDR_data <- data.frame(LDR = c(rep(0.2, 9), rep(0.5, 9), rep(0.75, 9)),
                         GRIDCODE = seq(1:27))
  
  LDR_data <- merge(intersecting_polygons, LDR_data)
  LDR_data$GRIDCODE <- NULL
  pointDataSoil <- unique(merge(pointDataSoil, LDR_data, by = c("lon", "lat")))
  
  for (prov in unique(inputData$NAME_1)) {
    general_pathIn <- file.path(
      project_usecase_dir(project_root, country, useCaseName),
      Crop, "result", "geo_4cropModel")
    pathIn <- define_pathIn(general_pathIn, level2 = NA, zone = prov,
                            pathIn_zone = T, Forecast = F, create_path = T)
    pointDataSoil_prov <- pointDataSoil %>% filter(NAME_1 == prov)
    pointDataSoil_prov <- na.omit(pointDataSoil_prov)
    saveRDS(pointDataSoil_prov, paste0(pathIn, "/ISDA_SoilDEM_PointData_AOI_profile.RDS"))
  }
}
