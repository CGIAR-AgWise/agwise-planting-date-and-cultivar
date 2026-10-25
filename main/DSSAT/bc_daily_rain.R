###############################################################################
# Daily rainfall at the AOI points and season onset, for the results dashboard
#
# agwise-data's forecast_to_dssat() writes each init's bias-corrected PRCP
# cube to products/<region>/Seasonal_PRCP_i<MM>_<YYYY>_BC.nc and fills the WTH
# files with its ensemble mean at each point's nearest cell. Sampling the same
# cubes here reproduces the WTH rain (to its 0.1 mm rounding) without
# re-reading one WTH file per site.
###############################################################################

### Bias-corrected PRCP cubes for one init, with their lat/lon extent
bc_prcp_files <- function(products_dir, year, month) {
  files <- Sys.glob(file.path(
    path.expand(products_dir), "*", sprintf("Seasonal_PRCP_i%02d_%d_BC.nc", month, year)))
  if (length(files) == 0) return(NULL)
  do.call(rbind, lapply(files, function(f) {
    nc <- ncdf4::nc_open(f)
    on.exit(ncdf4::nc_close(nc))
    lat <- ncdf4::ncvar_get(nc, "lat")
    lon <- ncdf4::ncvar_get(nc, "lon")
    half <- abs(lat[2] - lat[1]) / 2
    data.frame(
      file = f, lat_min = min(lat) - half, lat_max = max(lat) + half,
      lon_min = min(lon) - half, lon_max = max(lon) + half)
  }))
}

### Nearest grid index of each value (same as xarray's sel(method = "nearest"))
nearest_index <- function(grid, x) {
  vapply(x, function(v) which.min(abs(grid - v)), integer(1))
}

### Ensemble-mean daily rain at the nearest cell of each point (points x days)
#
# Read in blocks matching the file's chunking (13 members x 92 days): a
# single-point read still decompresses whole chunks, ~10 s per point.
read_bc_prcp_at_points <- function(file, lat, lon, member_block = 13, time_block = 92) {
  nc <- ncdf4::nc_open(file)
  on.exit(ncdf4::nc_close(nc))
  dim_names <- vapply(nc$var$PRCP$dim, function(d) d$name, character(1))
  if (!identical(dim_names, c("lon", "lat", "time", "member"))) {
    stop("Unexpected PRCP dimension order in ", file, ": ", paste(dim_names, collapse = ", "))
  }
  glat <- ncdf4::ncvar_get(nc, "lat")
  glon <- ncdf4::ncvar_get(nc, "lon")
  origin <- as.Date(sub("^days since ", "", ncdf4::ncatt_get(nc, "time", "units")$value))
  dates <- origin + as.numeric(ncdf4::ncvar_get(nc, "time"))

  ilat <- nearest_index(glat, lat)
  ilon <- nearest_index(glon, lon)
  lat0 <- min(ilat); lon0 <- min(ilon)
  nlat <- max(ilat) - lat0 + 1L; nlon <- max(ilon) - lon0 + 1L
  cell <- (ilon - lon0 + 1L) + (ilat - lat0) * nlon
  ucell <- unique(cell)

  n_member <- nc$dim$member$len
  n_time <- length(dates)
  sums <- counts <- matrix(0, length(ucell), n_time)
  for (m0 in seq(1, n_member, by = member_block)) {
    mc <- min(member_block, n_member - m0 + 1)
    for (t0 in seq(1, n_time, by = time_block)) {
      tc <- min(time_block, n_time - t0 + 1)
      x <- ncdf4::ncvar_get(
        nc, "PRCP", start = c(lon0, lat0, t0, m0), count = c(nlon, nlat, tc, mc),
        collapse_degen = FALSE)
      dim(x) <- c(nlon * nlat, tc, mc)
      x <- x[ucell, , , drop = FALSE]
      tt <- t0:(t0 + tc - 1)
      sums[, tt] <- sums[, tt] + rowSums(x, dims = 2, na.rm = TRUE)
      counts[, tt] <- counts[, tt] + rowSums(!is.na(x), dims = 2)
    }
  }
  ens_mean <- ifelse(counts > 0, sums / counts, NA_real_)
  list(dates = dates, rain = round(ens_mean[match(cell, ucell), , drop = FALSE], 1))
}

### One init's daily rain for every point, long format (XLAT, LONG, DATE, RAIN)
#
# Uses the smallest cube containing ALL points - the run's shared country
# bbox. Cubes of neighbouring countries overlap it and their QDM values differ
# slightly, so a per-point choice is only the fallback, for older per-zone
# runs that have no single cube covering everything.
bc_daily_rain_for_init <- function(pts, year, month, products_dir) {
  cubes <- bc_prcp_files(products_dir, year, month)
  if (is.null(cubes)) {
    stop(sprintf("No Seasonal_PRCP_i%02d_%d_BC.nc under %s", month, year, products_dir))
  }
  cubes$area <- (cubes$lat_max - cubes$lat_min) * (cubes$lon_max - cubes$lon_min)
  cubes <- cubes[order(cubes$area), ]
  inside <- outer(pts$lat, cubes$lat_min, `>=`) & outer(pts$lat, cubes$lat_max, `<=`) &
    outer(pts$lon, cubes$lon_min, `>=`) & outer(pts$lon, cubes$lon_max, `<=`)
  covers_all <- which(colSums(inside) == nrow(pts))
  pick <- if (length(covers_all) > 0) {
    rep(covers_all[1], nrow(pts))
  } else {
    apply(inside, 1, function(r) if (any(r)) which(r)[1] else NA_integer_)
  }
  if (anyNA(pick)) {
    warning(sum(is.na(pick)), " point(s) outside every i", sprintf("%02d", month),
            " cube - no rain extracted for them.", call. = FALSE)
  }

  out <- list()
  for (k in sort(unique(stats::na.omit(pick)))) {
    sel <- which(pick == k)
    message("  Reading ", basename(dirname(cubes$file[k])), "/", basename(cubes$file[k]),
            " for ", length(sel), " point(s)")
    r <- read_bc_prcp_at_points(cubes$file[k], pts$lat[sel], pts$lon[sel])
    out[[length(out) + 1]] <- data.frame(
      XLAT = rep(pts$XLAT[sel], times = length(r$dates)),
      LONG = rep(pts$LONG[sel], times = length(r$dates)),
      DATE = rep(r$dates, each = length(sel)),
      RAIN = as.vector(r$rain))
  }
  do.call(rbind, out)
}

### Full-precision AOI points of a usecase, keyed by the results' 3-dp XLAT/LONG
#
# Regenerated with the same ad_make_grid() call as run_datasourcing_export.R
# (offline, seconds per zone). The results only keep 3 dp, and a point on a
# cell edge (e.g. lat -16.55 on the 0.05 deg grid) then can't tell which
# neighbour cell its WTH was sampled from; the exact point can.
aoi_grid_points <- function(
    complete_usecase,
    datasourcing_repo_dir = "~/agwise-datasourcing/code/data_sourcing",
    datasourcing_bin = "~/agwise-datasourcing/envs/agwise_data/bin/agwise-data") {
  if (!nzchar(Sys.getenv("AGWISE_DATA_BIN"))) {
    Sys.setenv(AGWISE_DATA_BIN = path.expand(datasourcing_bin))
  }
  source(file.path(path.expand(datasourcing_repo_dir), "r", "agwise_data.R"))
  grids <- lapply(complete_usecase$zones, function(zone) ad_make_grid(
    country = complete_usecase$country_name, admin_level = 1, admin_name = zone,
    res_km = complete_usecase$resolution_km %||% 5, tag_admin_level = 1))
  g <- do.call(rbind, grids)
  data.frame(XLAT = round(g$lat, 3), LONG = round(g$lon, 3), lat = g$lat, lon = g$lon)
}

### Daily rain the simulations used, from the init date to the end of the cube
#
# points: XLAT/LONG (the results' keys), plus optional full-precision lat/lon
# from aoi_grid_points(); without them the 3-dp keys are used, and a point
# on a cell edge may land in the neighbouring cell (<= 0.3 mm/day seen).
# lead_months = 0 runs splice the previous init's month in front of the
# current init (see import_prestaged_dssat_files.R), so the same is done here.
extract_bc_daily_rain <- function(points, init_year, init_month, lead_months, products_dir) {
  pts <- if (all(c("lat", "lon") %in% names(points))) {
    unique(data.frame(XLAT = points$XLAT, LONG = points$LONG, lat = points$lat, lon = points$lon))
  } else {
    unique(data.frame(XLAT = points$XLAT, LONG = points$LONG, lat = points$XLAT, lon = points$LONG))
  }
  init_date <- as.Date(sprintf("%d-%02d-01", init_year, init_month))
  message("Extracting bias-corrected daily rain for ", nrow(pts), " point(s), init ", init_date)
  rain <- bc_daily_rain_for_init(pts, init_year, init_month, products_dir)
  rain <- rain[rain$DATE >= init_date, ]
  if (identical(as.integer(lead_months), 0L)) {
    prev <- seq(init_date, by = "-1 month", length.out = 2)[2]
    spinup <- bc_daily_rain_for_init(
      pts, as.integer(format(prev, "%Y")), as.integer(format(prev, "%m")), products_dir)
    rain <- rbind(spinup[spinup$DATE < init_date, ], rain)
  }
  rain[order(rain$XLAT, rain$LONG, rain$DATE), ]
}

### Season onset per pixel, joined onto the merged results
#
# get_agronomic_onset_pdates() sets the candidate planting dates to onset +
# 0, 7, 14, ... days, and every FILEX mode names the first one "1st plant
# date" (or "<fert> 1st pd" in fertilizer modes), so onset is that row's
# PDAT. A pixel whose 1st-date run is missing gets NA rather than a later date.
add_onset_dates <- function(results_df) {
  first_rows <- grepl("1st (plant date|pd)$", results_df$TNAM)
  if (!any(first_rows)) {
    warning("No '1st plant date' treatments found - onset_date left NA.", call. = FALSE)
    results_df$onset_date <- as.Date(NA)
    return(results_df)
  }
  onset <- results_df[first_rows, c("XLAT", "LONG", "PDAT")] %>%
    dplyr::group_by(XLAT, LONG) %>%
    dplyr::summarise(onset_date = as.Date(min(PDAT)), .groups = "drop")
  results_df$onset_date <- NULL
  dplyr::left_join(results_df, onset, by = c("XLAT", "LONG"))
}

### Save the daily rain of one usecase crop next to its merged results
#
# Writes <base_filename>_daily_rain.RDS (XLAT, LONG, DATE, RAIN) for every
# pixel in results_df. Falls back to the 3-dp result coordinates if the exact
# AOI grid can't be regenerated.
write_daily_rain <- function(
    complete_usecase, results_df, output_dir, base_filename,
    datasourcing_products_dir = "~/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Processed/products") {
  # Only agwise-data exports were filled from these cubes; weather from the
  # legacy main/Forecast pipeline (e.g. Rwanda august_init) is not
  if (!isTRUE(complete_usecase$generate_dssat_via_datasourcing)) {
    message("Weather not generated via agwise-data - no daily rain written (no rainfall maps).")
    return(invisible(NULL))
  }
  products_dir <- complete_usecase$dssat_source_products_dir %||% datasourcing_products_dir
  init <- forecast_init_from_usecase(complete_usecase)
  pixels <- unique(results_df[, c("XLAT", "LONG")])

  points <- tryCatch({
    g <- aoi_grid_points(complete_usecase)
    g <- g[!duplicated(g[, c("XLAT", "LONG")]), ]
    dplyr::left_join(pixels, g, by = c("XLAT", "LONG"))
  }, error = function(e) {
    warning("Could not regenerate the AOI grid (", conditionMessage(e),
            "); using 3-dp result coordinates.", call. = FALSE)
    pixels
  })
  if ("lat" %in% names(points) && anyNA(points$lat)) {
    message(sum(is.na(points$lat)), " pixel(s) not in the regenerated grid - using their 3-dp coordinates.")
    points$lat[is.na(points$lat)] <- points$XLAT[is.na(points$lat)]
    points$lon[is.na(points$lon)] <- points$LONG[is.na(points$lon)]
  }

  rain <- extract_bc_daily_rain(
    points, init_year = init$year, init_month = init$month,
    lead_months = as.integer(complete_usecase$lead_months %||% 1L),
    products_dir = products_dir)
  out_path <- file.path(output_dir, paste0(base_filename, "_daily_rain.RDS"))
  saveRDS(rain, out_path)
  message("Daily rain saved to: ", out_path)
  invisible(out_path)
}
