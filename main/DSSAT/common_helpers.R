###############################################################################
# Script: common_helpers.R
# Purpose: Shared DSSAT path, package, and workflow helper functions.
#
# Authors: Alvaro Carmona-Cabrero, Jemal S. Ahmed (jemal.ahmed@cgiar.org)
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-06-07
###############################################################################


### Load or install required packages ----
load_or_install <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}


### Data directory path ----
project_data_dir <- function(project_root) {
  lower_path <- file.path(project_root, "data")
  if (dir.exists(lower_path)) "data" else "Data"
}


### Usecases path ----
project_usecases_dir <- function(project_root) {
  file.path(project_root, project_data_dir(project_root), "usecases")
}


### Usecase-specific path ----
project_usecase_dir <- function(project_root, country, useCaseName) {
  data_root <- file.path(project_root, project_data_dir(project_root))
  usecase_name <- paste0("useCase_", country, "_", useCaseName)
  preferred_path <- file.path(data_root, "usecases", usecase_name)
  legacy_path <- file.path(data_root, usecase_name)
  if (dir.exists(legacy_path) && !dir.exists(preferred_path)) {
    legacy_path
  } else {
    preferred_path
  }
}


### Common EXTpath ----
create_extdata_path <- function(project_root, country, useCaseName, Crop,
                                varietyid, AOI = FALSE) {
  subfolder <- ifelse(AOI, "AOI", "fieldData")
  path <- file.path(
    project_usecase_dir(project_root, country, useCaseName),
    Crop, "transform", "DSSAT", subfolder, varietyid)
  
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE)
  }
  
  return(path)
}


### Common DSSAT template data path ----
create_dssat_temdata_path <- function(project_root, country, useCaseName, Crop) {
  usecase_dir <- project_usecase_dir(project_root, country, useCaseName)
  candidates <- c(
    file.path(usecase_dir, Crop, "Landing", "DSSAT"),
    file.path(usecase_dir, Crop, "DSSAT")
  )
  path.to.temdata <- candidates[dir.exists(candidates)][1]
  if (is.na(path.to.temdata) || !dir.exists(path.to.temdata)) {
    stop("Directory with DSSAT Template Data (soil and weather files) does ", 
         "not exist, please add the template files. Process will stop.")
  }
  paste0(path.to.temdata, "/")
}


### Common DSSAT working path ----
create_dssat_working_path <- function(path.to.extdata, i, zone = NA,
 level2 = NA) {
  # sanity check
  if (!is.na(level2) && is.na(zone)) {
    stop(
      "You need to define a zone (administrative level 1) ",
      "to be able to get data for level 2 (administrative level 2)."
    )
  }

  exte_id <- paste0("EXTE", formatC(as.integer(i), width = 4, flag = "0"))

  sub_path <- dplyr::case_when(
    !is.na(zone) & !is.na(level2) ~ file.path(zone, level2, exte_id),
    !is.na(zone) &  is.na(level2) ~ file.path(zone, exte_id),
    is.na(zone)  &  is.na(level2) ~ exte_id
  )

  working_path <- file.path(path.to.extdata, sub_path)

  if (!dir.exists(working_path)) {
    dir.create(working_path, recursive = TRUE)
  }

  working_path
}


### Produce the AOI_GPS.RDS file ----
getGridCoordinates <- function(
    country, useCaseName, Crop, resltn = 0.05, project_root, provinces = NULL,
    district = NULL, force_reanalysis = TRUE) {
  
  pathOut <- file.path(
    project_usecase_dir(project_root, country, useCaseName),
    Crop, "data_curation", country)
  
  if (!dir.exists(pathOut)) {
    dir.create(file.path(pathOut), recursive = T)
  }
  
  # Do not compute if not requested and AOI_GPS.RDS exists
  if (!force_reanalysis && file.exists(paste0(pathOut, "AOI_GPS.RDS"))) {
    State_LGA <- readRDS(paste0(pathOut, "AOI_GPS.RDS"))
    
    return(State_LGA)
  }

  # Read the relevant shape file from gdam to be used to crop the global data
  countrySpVec <- geodata::gadm(country, level = 2, path = '.')
  
  if(!is.null(provinces)) {
    level3 <- countrySpVec[countrySpVec$NAME_1 %in% provinces ]
  } else if (!is.null(district)) {
    level3 <- countrySpVec[countrySpVec$NAME_2 %in% district, ]
  } else {
    level3 <- countrySpVec
  }
  
  plot(countrySpVec)
  plot(level3, add = T, col = "green")
  
  xmin <- ext(level3)[1]
  xmax <- ext(level3)[2]
  ymin <- ext(level3)[3]
  ymax <- ext(level3)[4]
  
  # Define a rectangular area that covers the whole study area (buffer of 10 km)
  lon_coors <- unique(round(seq(xmin - 0.1, xmax + 0.1, by = resltn),
                            digits = 3))
  lat_coors <- unique(round(seq(ymin - 0.1, ymax + 0.1, by = resltn),
                            digits = 3))
  rect_coord <- as.data.frame(expand.grid(x = lon_coors, y = lat_coors))
  
  if(resltn == 0.05) {
    rect_coord$x <- floor(rect_coord$x * 10) / 10 + ifelse(
      rect_coord$x - (floor(rect_coord$x * 10) / 10) < 0.05, 0.025, 0.075)
    rect_coord$y <- floor(rect_coord$y * 10) / 10 + ifelse(
      abs(rect_coord$y) - (floor(abs(rect_coord$y) * 10) / 10) < 0.05, 0.025, 0.075)
  }
  
  rect_coord <- unique(rect_coord[, c("x", "y")])
  # } else if (resltn == 0.01) {
  #   rect_coord$x <- floor(rect_coord$x*100)/100
  #   rect_coord$y <- floor(rect_coord$y*100)/100
  #   rect_coord <- unique(rect_coord[,c("x", "y")])
  # } else {
  #  names(rect_coord) <- c("x", "y")
  # }
  
  State_LGA <- as.data.frame(raster::extract(countrySpVec, rect_coord))
  State_LGA$lon <- rect_coord$x
  State_LGA$lat <- rect_coord$y
  State_LGA$country <- country
  
  State_LGA <- unique(State_LGA[, c("country", "NAME_1", "NAME_2", "lon", "lat")])
  
  if(!is.null(provinces)) {
    State_LGA <- droplevels(State_LGA[State_LGA$NAME_1 %in% provinces, ])
  } else if (!is.null(district)) {
    State_LGA <- droplevels(State_LGA[State_LGA$NAME_2 %in% district, ])
  }
  
  State_LGA <- droplevels(State_LGA[!is.na(State_LGA$NAME_2), ])
  
  saveRDS(State_LGA, file.path(pathOut, "AOI_GPS.RDS"))
  
  return(State_LGA)
}


### Detect available RAM in GB ----
detect_available_ram_gb <- function() {
  ram_limit_file <- "/sys/fs/cgroup/memory/memory.limit_in_bytes"
  if (file.exists(ram_limit_file)) {
    ram_limit_bytes <- suppressWarnings(as.numeric(readLines(ram_limit_file, warn = FALSE)))
    if (!is.na(ram_limit_bytes) && ram_limit_bytes < 2 ^ 60) {
      return(ram_limit_bytes / 1024 ^ 3)
    }
  }

  if (file.exists("/proc/meminfo")) {
    mem_line <- grep("^MemAvailable:", readLines("/proc/meminfo", warn = FALSE), value = TRUE)
    mem_kb <- suppressWarnings(as.numeric(sub("^MemAvailable:[[:space:]]+([0-9]+).*", "\\1", mem_line[1])))
    if (length(mem_kb) && is.finite(mem_kb)) return(mem_kb / 1024 / 1024)
  }

  sysctl_bytes <- suppressWarnings(as.numeric(system2("sysctl", c("-n", "hw.memsize"), stdout = TRUE, stderr = FALSE)))
  if (length(sysctl_bytes) && is.finite(sysctl_bytes)) return(sysctl_bytes / 1024 ^ 3)

  NA_real_
}

### Plan multisession ----
plan_multisession <- function(per_worker_gb, max_workers = NULL,
 only_get_workers = FALSE) {

  requested_workers <- max_workers
  if (is.null(requested_workers)) {
    env_workers <- Sys.getenv("AGWISE_N_CORES", unset = NA_character_)
    requested_workers <- suppressWarnings(as.integer(env_workers))
  }
  if (!length(requested_workers) || is.na(requested_workers) || requested_workers < 1) {
    requested_workers <- NULL
  }

  available_ram_gb <- detect_available_ram_gb()
  
  # Compute safe number of workers
  memory_workers <- if (is.finite(available_ram_gb)) {
    max(1L, floor(available_ram_gb / per_worker_gb))
  } else {
    Inf
  }
  detected_cores <- suppressWarnings(availableCores())
  if (is.na(detected_cores)) detected_cores <- 1
  detected_cores <- max(1L, as.integer(detected_cores))

  if (is.null(requested_workers)) {
    workers <- min(memory_workers, max(1L, detected_cores - 1L))
  } else {
    workers <- min(as.integer(requested_workers), memory_workers)
  }
  workers <- max(1L, as.integer(workers))

  # Just get workers
  if (only_get_workers) {
    return(workers)
  }

  # Activate plan
  if (!is.null(requested_workers)) {
    options(parallelly.maxWorkers.localhost = Inf)
  }
  backend <- if (
    workers > 1L &&
      .Platform$OS.type != "windows" &&
      isTRUE(future::supportsMulticore())
  ) {
    future::multicore
  } else {
    future::multisession
  }
  backend_name <- if (identical(backend, future::multicore)) "multicore" else "multisession"
  suppressWarnings(plan(backend, workers = workers))
  
  message(
    "Parallel plan: ", workers, " workers (", backend_name,
    "), estimated per-worker RAM: ", per_worker_gb, " GB"
  )
}


### Load inputData. If missing, produce it ----
load_or_generate_inputData <- function(country, useCaseName, Crop, project_root,
                                       inputData = NULL) {

  if (is.null(inputData)) {

    inputData_path <- file.path(
      project_usecase_dir(project_root, country, useCaseName),
      Crop, "data_curation", country, "AOI_GPS.RDS")

    if (file.exists(inputData_path)) {
      inputData <- readRDS(inputData_path)
    } else {
      getGridCoordinates(country, useCaseName, Crop, project_root, 
                         resltn = 0.05, provinces = NULL, district = NULL)
      inputData <- readRDS(inputData_path)
    }
  }

  return(inputData)
}


### Function to write DSSAT progress log files ----
write_dssat_log <- function(messages_list, file) {
  file_path <- file.path(
    project_usecase_dir(project_root, country, useCaseName),
    Crop,
    file)
  dir.create(dirname(file_path), recursive = TRUE, showWarnings = FALSE)

  # Flatten list to single character vector
  log_lines <- unlist(messages_list)

  # Write to file
  writeLines(log_lines, con = file_path)

  message("Log written to: ", file_path)
}
