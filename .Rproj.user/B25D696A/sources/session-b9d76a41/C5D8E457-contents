

# TODO: Move this to config file
# [5.5, 33.5, -4.7, 42.0]
lonLim <- c(33.5 , 42.0)
latLim <- c(-4.7, 5.5)

###############################################################
# 4. Loop over variables: PRCP, TMAX, TMIN, TEMP, SRAD, ...
###############################################################
for (var_code in variables_to_bc) {
  
  cfg <- VAR_CONFIG[[var_code]]
  message("===================================================")
  message("Variable: ", var_code)
  message(" -> obs_file_pattern: ", cfg$obs_file_pattern)
  message(" -> obs_var: ", cfg$obs_var, " | model_var: ", cfg$model_var)
  
  ###########################################################
  # 4.1 Observation file (from Python AgWise_AgroIndicators)
  ###########################################################
  obs_year_start <- min(years_calib)
  obs_year_end   <- max(years_calib)
  
  obs_file <- file.path(
    dir_obs_raw,
    sprintf(cfg$obs_file_pattern, obs_year_start, obs_year_end)
  )
  
  if (!file.exists(obs_file)) {
    message("  !! Obs file not found, skipping variable ", var_code, ": ", obs_file)
    next
  }
  
  ###########################################################
  # 4.2 Hindcast & forecast files for this variable
  #     Python naming:
  #       hindcast_<modelid>_<VAR>_...
  #       forecast_<modelid>_<VAR>_...
  ###########################################################
  hind_pattern <- sprintf("^hindcast_.*_%s_.*\\.nc$", var_code)
  fcst_pattern <- sprintf("^forecast_.*_%s_.*\\.nc$", var_code)
  
  hind_files <- list.files(
    dir_mod_raw,
    pattern = hind_pattern,
    full.names = TRUE
  )
  fcst_files <- list.files(
    dir_mod_raw,
    pattern = fcst_pattern,
    full.names = TRUE
  )
  
  if (length(hind_files) == 0) {
    message("  !! No hindcast files for ", var_code, " in: ", dir_mod_raw)
    next
  }
  if (length(fcst_files) == 0) {
    message("  !! No forecast files for ", var_code, " in: ", dir_mod_raw)
    next
  }
  
  ## Extract model IDs (e.g. "ecmwf51") so we can pair hindcast + forecast
  hind_ids <- sub("^hindcast_([^_]+)_.+\\.nc$", "\\1", basename(hind_files))
  fcst_ids <- sub("^forecast_([^_]+)_.+\\.nc$", "\\1", basename(fcst_files))
  
  model_ids <- intersect(unique(hind_ids), unique(fcst_ids))
  if (length(model_ids) == 0) {
    message("  !! No common model IDs between hindcast and forecast for ", var_code)
    next
  }
  
  ###########################################################
  # 4.3 Load observed calibration data (reference)
  ###########################################################
  # Load NetCDF as raster stack
  nc_obs <- rast(obs_file, subds = cfg$obs_var)
  # Crop to lon/lat limits if specified
  if (!is.null(lonLim) & !is.null(latLim)) {
    ext_obs <- ext(lonLim[1], lonLim[2], latLim[1], latLim[2])
    nc_obs <- crop(nc_obs, ext_obs)
  }
  # Assign units
  attr(nc_obs, "units") <- cfg$units
  
  
  # Get layer dates
  nlyr_obs <- nlyr(nc_obs)
  start_date <- as.Date("1985-01-01")  # adjust to your NetCDF start date
  dates <- seq(start_date, by = "day", length.out = nlyr_obs)
  
  # Select calibration years
  years_calib <- 2014:2016
  keep_idx <- which(format(dates, "%Y") %in% years_calib)
  nc_obs_calib <- nc_obs[[keep_idx]]
  dates_calib <- dates[keep_idx]
  
  # Compute multi-year daily climatology (average per day-of-year)
  doy <- as.numeric(format(dates_calib, "%j"))
  clim_list <- lapply(1:366, function(d) {
    idx <- which(doy == d)
    if (length(idx) == 0) return(NULL)
    mean(nc_obs_calib[[idx]], na.rm = TRUE)
  })
  clim_list <- clim_list[!sapply(clim_list, is.null)]  # remove empty (e.g., Feb 29)
  
  # Combine into SpatRaster
  obs_clim <- rast(clim_list)
  names(obs_clim) <- paste0("DOY_", 1:nlyr(obs_clim))
  
  # Assign units
  attr(obs_clim, "units") <- cfg$units
  
  ###########################################################
  # 4.4 Loop over models that have both hindcast & forecast
  ###########################################################
  for (m in model_ids) {
    
    message("---------------------------------------------------")
    message("Processing ", var_code, " for model ID: ", m)
    
    ## Select matching hindcast & forecast files
    hind_file <- hind_files[hind_ids == m][1]
    fcst_file <- fcst_files[fcst_ids == m][1]
    
    message("  Hindcast file: ", hind_file)
    message("  Forecast file: ", fcst_file)
    
    if (!file.exists(hind_file) || !file.exists(fcst_file)) {
      message("  -> Hindcast or forecast file missing, skipping model ", m)
      next
    }
    
    #--------------------------------------------------------
    # 4.4.1 Load hindcast (calibration) data
    #--------------------------------------------------------
    # Load the NetCDF variable
    r <- rast(hind_file, subds = cfg$model_var)
    
    # Crop to lon/lat limits if provided
    if (!is.null(lonLim) && !is.null(latLim)) {
      ext_hind <- ext(lonLim[1], lonLim[2], latLim[1], latLim[2])
      r <- crop(r, ext_hind)
    }
    
    # Subset to the calibration years (assuming daily time dimension)
    if (!is.null(years_calib)) {
      # Extract the time vector from the NetCDF
      t <- time(r)  # terra function returns POSIXct vector
      year_idx <- format(t, "%Y") %in% as.character(years_calib)
      r <- r[[which(year_idx)]]
    }
    
    r
    
    #--------------------------------------------------------
    # 4.4.2 Load forecast data (to be bias-corrected)
    #--------------------------------------------------------
    # Load forecast raster
    nc_fcst <- rast(fcst_file, subds = cfg$model_var)
    
    # Crop to lon/lat limits if specified
    if (!is.null(lonLim) & !is.null(latLim)) {
      ext_fcst <- ext(lonLim[1], lonLim[2], latLim[1], latLim[2])
      nc_fcst <- crop(nc_fcst, ext_fcst)
    }
    
    # Assign units
    attr(nc_fcst, "units") <- cfg$units
    
    
    #--------------------------------------------------------
    # 4.4.3 Bias correction: hindcast calibrates, forecast is newdata
    #     y       = obs (calibration period)
    #     x       = hindcast model (calibration period)
    #     newdata = forecast model (to correct)
    #--------------------------------------------------------
    message("  -> Running biasCorrection (hindcast→forecast)...")
    
    nc_fcst_bc <- biasCorrection(
      y = nc_obs,
      x = nc_hind,
      newdata = nc_fcst,
      precipitation = cfg$is_precip,
      method = "qdm",
      cross.val = "none",
      consecutive = cfg$is_precip,
      scaling.type = cfg$scaling.type,
      max.ncores = n_cores
    )
    
    #--------------------------------------------------------
    # 4.4.4 Export bias-corrected FORECAST only
    #--------------------------------------------------------
    ## Use model ID 'm' and forecast years for naming
    fcst_years_str <- paste(forecast_years, collapse = "-")
    
    outFile <- file.path(
      dir_bc_fcst,
      sprintf("%s_day_%s_forecast_BC_%s.nc",
              var_code, m, fcst_years_str)
    )
    
    message("  -> Writing bias-corrected FORECAST NetCDF: ", outFile)
    
    grid2nc(
      data          = nc_fcst_bc,
      NetCDFOutFile = outFile,
      missval       = -999,
      compression   = 7
    )
    
    #--------------------------------------------------------
    # 4.4.5 Bias maps (optional, still useful to check performance)
    #         Here we compare:
    #           - Hindcast climatology vs obs (raw bias)
    #           - Bias-corrected forecast climatology vs obs
    #         (strictly speaking, the latter is 'future' period, but
    #          this is still useful for sanity plotting—optional)
    #--------------------------------------------------------
    mask <- gridArithmetics(nc_obs, 0, operator = "*")
    
    ## Hindcast regridded to obs grid
    nc_hind_interp <- interpGrid(nc_hind, getGrid(nc_obs), ncores = n_cores)
    nc_hind_interp <- gridArithmetics(nc_hind_interp, mask, operator = "+")
    
    ## Bias-corrected forecast regridded to obs grid
    nc_fcst_bc_interp <- interpGrid(nc_fcst_bc, getGrid(nc_obs), ncores = n_cores)
    nc_fcst_bc_interp <- gridArithmetics(nc_fcst_bc_interp, mask, operator = "+")
    
    ## Climatologies
    hind_clim   <- climatology(nc_hind_interp)
    fcstbc_clim <- climatology(nc_fcst_bc_interp)
    
    ## Bias relative to obs climatology
    bias_hind  <- gridArithmetics(hind_clim,  obs_clim, operator = "-")
    bias_fcst  <- gridArithmetics(fcstbc_clim, obs_clim, operator = "-")
    
    brks <- cfg$brks_bias
    
    fig_file <- file.path(
      dir_fig_bias,
      sprintf("Bias_%s_%s.png", var_code, m)
    )
    message("  -> Saving bias map (hindcast & BC forecast): ", fig_file)
    
    png(fig_file, width = 1800, height = 800, res = 150)
    
    p1 <- spatialPlot(
      climatology(bias_hind),
      at   = brks, backdrop.theme = "countries",
      scales = list(draw = TRUE),
      main  = paste(m, var_code, "HINDCAST bias (model - obs) [", cfg$units, "]")
    )
    
    p2 <- spatialPlot(
      climatology(bias_fcst),
      at   = brks, backdrop.theme = "countries",
      scales = list(draw = TRUE),
      main  = paste(m, var_code, "BC FORECAST bias (model - obs) [", cfg$units, "]")
    )
    
    p3 <- spatialPlot(
      climatology(nc_obs),
      main = paste(country_name, var_code, "Observed climatology [", cfg$units, "]")
    )
    
    p4 <- spatialPlot(
      climatology(nc_hind),
      main = paste(m, var_code, "Hindcast climatology [", cfg$units, "]")
    )
    
    grid.arrange(p1, p2, p3, p4, ncol = 2)
    dev.off()
    
    #--------------------------------------------------------
    # 4.4.6 Clean up RAM
    #--------------------------------------------------------
    rm(nc_hind, nc_fcst, nc_fcst_bc,
       nc_hind_interp, nc_fcst_bc_interp,
       hind_clim, fcstbc_clim,
       bias_hind, bias_fcst,
       p1, p2, p3, p4)
    gc()
    
    message("  -> Finished ", var_code, " for model ID: ", m)
  }
}

message("All variables for this country (FORECASTS) bias-corrected.")
