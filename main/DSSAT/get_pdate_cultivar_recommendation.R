### Locate the crop mask raster for a given crop
#
# Two mask naming conventions coexist: most crops have three raster variants
# (_PD_min/_PD_max/_PD_sd - per-pixel statistics of historical planting
# date), which share the same NA footprint (presence/absence of the crop,
# not the statistic value, is what defines the mask), so any one of them
# works as the mask - `_max` is used arbitrarily. Others (e.g. Wheat) instead
# have a single dedicated binary _mask.tif (e.g. MAPSPAM-derived). Both are
# only ever consulted for their NA/non-NA footprint (see apply_crop_mask()
# below), so no other code needs to know which convention a given crop uses.
find_crop_mask_file <- function(crop, crop_mask_dir = "Landing/crop_masks", must_exist = TRUE, country = NULL) {
  if (is.null(crop) || is.na(crop) || !nzchar(crop)) {
    if (must_exist) stop("use_crop_mask = TRUE requires `crop` to be provided.")
    return(NA_character_)
  }
  candidates <- list.files(
    crop_mask_dir,
    pattern = paste0(crop, ".*(_PD_max|_mask)\\.tif$"),
    full.names = TRUE,
    ignore.case = TRUE
  )
  # Multiple countries can each have their own crop mask file in the same
  # shared crop_mask_dir (e.g. <country>_maize_mapspam2020_mask.tif per
  # country) - if a country is given, prefer files whose name mentions it.
  # A single untagged file (e.g. a legacy crop-wide mask) is still used as-is
  # for backward compatibility; but if there are MULTIPLE crop matches and
  # none is tagged with this country, refuse rather than silently guessing
  # (list.files()'s ordering is not something to rely on for correctness).
  has_country <- !is.null(country) && nzchar(country)
  if (has_country && length(candidates) > 0) {
    country_candidates <- candidates[grepl(country, basename(candidates), ignore.case = TRUE)]
    if (length(country_candidates) > 0) {
      candidates <- country_candidates
    } else if (length(candidates) > 1) {
      if (must_exist) {
        stop(
          "use_crop_mask = TRUE: multiple crop mask files match crop '", crop,
          "' in ", crop_mask_dir, " but none is tagged for country '", country,
          "' - refusing to guess. Matches: ", paste(basename(candidates), collapse = ", ")
        )
      }
      return(NA_character_)
    }
  } else if (!has_country && length(candidates) > 1) {
    # No country given at all and more than one crop match exists - refuse
    # rather than picking whichever list.files() happens to return first.
    if (must_exist) {
      stop(
        "use_crop_mask = TRUE: multiple crop mask files match crop '", crop,
        "' in ", crop_mask_dir, " and no `country` was given to disambiguate. ",
        "Matches: ", paste(basename(candidates), collapse = ", ")
      )
    }
    return(NA_character_)
  }
  if (length(candidates) == 0) {
    if (must_exist) {
      stop(
        "use_crop_mask = TRUE but no crop mask raster found for crop '", crop,
        "' in ", crop_mask_dir, ". Available files: ",
        paste(list.files(crop_mask_dir), collapse = ", ")
      )
    }
    return(NA_character_)
  }
  candidates[[1]]
}


### Restrict a results data.frame to pixels covered by the crop mask
apply_crop_mask <- function(df, crop, crop_mask_dir = "Landing/crop_masks", country = NULL) {
  mask_file <- find_crop_mask_file(crop, crop_mask_dir, country = country)
  mask_rast <- terra::rast(mask_file)
  extracted <- terra::extract(mask_rast, df[, c("LONG", "XLAT")])
  df[!is.na(extracted[[2]]), , drop = FALSE]
}


### Save a crop-mask-filtered copy of the full (pre-ranking) merged results
#
# Unlike apply_crop_mask()'s other callers (which mask an already-ranked/
# exported view on request via use_crop_mask), this filters the complete
# per-pixel x cultivar x treatment grid straight out of merge_DSSAT_output(),
# and is meant to run unconditionally as a pipeline artifact for every crop -
# so a missing mask is a graceful skip, not an error.
export_cropmask_full_results <- function(
    results_df, crop, crop_mask_dir = "Landing/crop_masks",
    output_dir = ".", base_filename = crop, country = NULL) {
  mask_file <- find_crop_mask_file(crop, crop_mask_dir, must_exist = FALSE, country = country)
  if (is.na(mask_file)) {
    message(
      "No crop mask available for '", crop, "' in ", crop_mask_dir,
      " - skipping crop-mask-filtered export.")
    return(invisible(NULL))
  }

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  masked_df <- apply_crop_mask(results_df, crop = crop, crop_mask_dir = crop_mask_dir, country = country)

  file_path <- file.path(output_dir, paste0(base_filename, "_cropmask.RDS"))
  saveRDS(masked_df, file = file_path)
  message("Crop-mask-filtered full results saved to: ", file_path)
  invisible(file_path)
}


### Rank planting dates for each pixel and cultivar based on yields
add_date_rank <- function(df, metric = "HWAH") {
  df %>%
    group_by(XLAT, LONG, Cultivar) %>%
    mutate(Date_Rank = dplyr::row_number(dplyr::desc(.data[[metric]]))) %>%
    ungroup()
}


### Rank planting-date-cultivar combination for each pixel based on a chosen metric
add_combination_rank <- function(df, metric = "HWAH") {
  df %>%
    dplyr::group_by(XLAT, LONG) %>%
    dplyr::mutate(
      Combination_Rank = dplyr::row_number(dplyr::desc(.data[[metric]]))) %>%
    dplyr::ungroup()
}


### Build a small, dashboard-ready cache of one crop's full results
#
# Reads the unmasked raw RDS (merge_DSSAT_output()'s save) and, if present,
# export_cropmask_full_results()'s masked companion file - reusing that
# already-computed artifact instead of re-running apply_crop_mask() /
# re-reading the mask raster here. Trims to the columns a dashboard needs,
# adds the same ranking already used for the other Step 5 exports, and flags
# which rows fall inside the crop mask (all TRUE if no mask exists for this
# crop, so a "crop mask" toggle downstream is a no-op rather than emptying
# the data).
#
# top_n caps rows to each pixel's best `top_n` combinations by Combination_Rank
# (default 8, vs. up to 32 in the full cultivar x treatment grid) - a static
# HTML dashboard embeds every row in every linked widget (crosstalk filters
# hide rows client-side, they don't reduce what's downloaded/parsed), so the
# uncapped full grid made the rendered file large enough to freeze a browser
# on open. Pass Inf to keep the full grid if size/speed isn't a concern.
build_dashboard_extract <- function(
    crop, output_dir = ".", base_filename = crop, metric = "HWAH", top_n = 8) {
  raw_path <- file.path(output_dir, paste0(base_filename, ".RDS"))
  if (!file.exists(raw_path)) {
    stop("Raw merged results not found for crop '", crop, "': ", raw_path)
  }
  raw_df <- readRDS(raw_path)

  dashboard_cols <- c(
    "XLAT", "LONG", "zone", "Cultivar", "TRNO", "PDAT", "HWAH", "CWAM", "WUE")
  extract_df <- raw_df[, dashboard_cols]
  extract_df$maturity_failed <- is.na(raw_df$MDAT)

  extract_df <- extract_df %>%
    add_date_rank(metric = metric) %>%
    add_combination_rank(metric = metric) %>%
    dplyr::filter(Combination_Rank <= top_n)

  masked_path <- file.path(output_dir, paste0(base_filename, "_cropmask.RDS"))
  if (file.exists(masked_path)) {
    masked_df <- readRDS(masked_path)
    masked_pixels <- unique(masked_df[, c("XLAT", "LONG")])
    extract_df$in_crop_mask <- paste(extract_df$XLAT, extract_df$LONG) %in%
      paste(masked_pixels$XLAT, masked_pixels$LONG)
  } else {
    extract_df$in_crop_mask <- TRUE
  }

  file_path <- file.path(output_dir, paste0(crop, "_dashboard_extract.RDS"))
  saveRDS(extract_df, file = file_path)
  message("Dashboard extract saved to: ", file_path)
  invisible(extract_df)
}


### Build (or refresh) one crop's self-contained HTML results dashboard
#
# Loads the crop's dashboard extract - reusing an existing one if present, or
# building it fresh (via build_dashboard_extract(), first generating its
# export_cropmask_full_results() companion if that's also missing) - then
# renders dashboard_template.Rmd into <result_dir>/<crop>_dashboard.html.
# Shared by both build_usecase_dashboard.R (standalone, multi-crop CLI) and
# run_dssat_pipeline.R (automatic, one crop per pipeline run) so the two
# don't duplicate this logic.
#
# force_rebuild = TRUE skips any existing cached extract and rebuilds it from
# the current base_filename RDS regardless - used when the caller (e.g. a
# pipeline run that just recomputed this crop's results) knows any existing
# extract predates the data now on disk and would otherwise be silently
# stale. build_usecase_dashboard.R instead defaults to FALSE, since its
# whole point is to cheaply reuse already-good extracts for crops it isn't
# actively recomputing.
#
# result_dir/repo_root are normalized to absolute paths up front:
# rmarkdown::render() evaluates the Rmd's chunks with the working directory
# set to the Rmd's own folder, not the caller's - a relative result_dir here
# would resolve to the wrong place inside the Rmd's readRDS(params$data_rds)
# and fail with a confusing "cannot open the connection" error.
build_crop_dashboard <- function(crop, result_dir, base_filename, crop_mask_dir,
                                  repo_root, country_name, force_rebuild = FALSE) {
  result_dir <- normalizePath(result_dir, mustWork = TRUE)
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  extract_path <- file.path(result_dir, paste0(crop, "_dashboard_extract.RDS"))

  if (!force_rebuild && file.exists(extract_path)) {
    message("Loading cached dashboard extract for ", crop)
    dat <- readRDS(extract_path)
  } else {
    message("Building dashboard extract for ", crop)
    masked_path <- file.path(result_dir, paste0(base_filename, "_cropmask.RDS"))
    if (!file.exists(masked_path)) {
      raw_path <- file.path(result_dir, paste0(base_filename, ".RDS"))
      results_df <- readRDS(raw_path)
      export_cropmask_full_results(
        results_df = results_df, crop = crop, crop_mask_dir = crop_mask_dir,
        output_dir = result_dir, base_filename = base_filename, country = country_name)
    }
    dat <- build_dashboard_extract(crop = crop, output_dir = result_dir, base_filename = base_filename)
  }

  dat$row_key <- paste(dat$XLAT, dat$LONG, dat$TRNO, dat$Cultivar, sep = "_")
  has_crop_mask <- !is.na(find_crop_mask_file(crop, crop_mask_dir, must_exist = FALSE, country = country_name))

  # Country name embedded in the shareable filenames themselves (not just
  # the folder path) - colleagues collecting dashboards from several
  # countries into one downloads folder would otherwise end up with several
  # indistinguishable "Maize_dashboard.html" files.
  country_slug <- gsub("[^A-Za-z0-9]+", "_", country_name)
  output_basename <- paste0(crop, "_", country_slug, "_dashboard")

  dashboard_rds_path <- file.path(result_dir, paste0(output_basename, "_data.RDS"))
  saveRDS(dat, dashboard_rds_path)

  rmarkdown::render(
    input = file.path(repo_root, "main/DSSAT/dashboard_template.Rmd"),
    output_file = paste0(output_basename, ".html"),
    output_dir = result_dir,
    params = list(
      data_rds = dashboard_rds_path,
      crop_name = crop,
      country_name = country_name,
      has_crop_mask = has_crop_mask,
      project_root = repo_root
    ),
    envir = new.env()
  )
  out_path <- file.path(result_dir, paste0(output_basename, ".html"))
  message("Dashboard rendered to: ", out_path)
  invisible(out_path)
}


### Plot maps of preferred planting dates for top 3 highest yields by cultivar
plot_planting_date_gradients <- function(
    df, country_name = "Rwanda", output_dir = ".", file_prefix = "",
    crop = NA_character_, use_crop_mask = FALSE,
    crop_mask_dir = "Landing/crop_masks", project_root = ".") {
  if (isTRUE(use_crop_mask)) {
    df <- apply_crop_mask(df, crop = crop, crop_mask_dir = crop_mask_dir, country = country_name)
    file_prefix <- paste0(file_prefix, "cropmask_")
  }
  plot_df <- df %>%
    dplyr::mutate(
      
      PDAT_clean = as.Date(PDAT)
    ) %>%
    
    dplyr::filter(Date_Rank <= 3)
  
  # Build the ordered factor labels for 4x3 plot rows/columns
  plot_df <- plot_df %>%
    dplyr::mutate(
      Rank_Label = factor(
        paste("Rank", Date_Rank), 
        levels = c("Rank 1", "Rank 2", "Rank 3")
      ),
      Cultivar = factor(
        Cultivar,
        # Not every crop has all 4 maturity classes (e.g. Potato/Wheat only
        # have Short/Medium/Long) - keep whichever are actually present, in
        # the canonical short-to-long order.
        levels = intersect(c("Short", "Medium", "Long", "Longer"), unique(as.character(Cultivar)))
      )
    )
  
  
  # Update the Rank_Label based on the input data
  plot_df <- plot_df %>%
    dplyr::mutate(
      Rank_Label = factor(
        dplyr::case_when(
          Date_Rank == 1 ~ "Top Recommendation",
          Date_Rank == 2 ~ "Second Choice",
          Date_Rank == 3 ~ "Third Choice"
        ),
        levels = c("Top Recommendation", "Second Choice", "Third Choice")
      )
    )
  
  # Fetch the requested country outline map. Prefer the high-resolution GADM
  # boundary already used/cached elsewhere in this pipeline (see
  # main/Forecast/00_config_function.R's build_country_config()) over the
  # coarse outline from the base "maps" package: the low-res outline clips
  # off real territory near the border, making genuinely in-country pixels
  # look like they sit outside the drawn line (verified for Rwanda/Maize -
  # all 770 pixels fall inside the GADM boundary, but ~28 of them fall
  # outside the old maps::world outline). geodata::gadm() reuses the same
  # on-disk cache other pipeline steps already populate, so this is normally
  # instant; falls back to the old low-res outline if GADM can't be reached
  # (e.g. no cache and no network) rather than failing the whole plot.
  country_outline <- tryCatch({
    country_code <- countrycode::countrycode(
      country_name, origin = "country.name", destination = "iso3c")
    admin_dir <- file.path(project_root, "data", "countries", country_code, "admin")
    adm0 <- geodata::gadm(country = country_code, level = 0, path = admin_dir)
    adm0_sf <- sf::st_as_sf(adm0)
    coords <- sf::st_coordinates(adm0_sf)
    data.frame(
      long = coords[, "X"], lat = coords[, "Y"],
      group = paste(coords[, "L2"], coords[, "L1"], sep = "."))
  }, error = function(e) {
    message("Falling back to low-resolution country outline: ", conditionMessage(e))
    ggplot2::map_data("world", region = country_name)
  })

  # Calculate calendar math directly from the dynamic data boundaries
  min_date <- min(plot_df$PDAT_clean, na.rm = TRUE)
  max_date <- max(plot_df$PDAT_clean, na.rm = TRUE)
  mid_date <- min_date + (max_date - min_date) / 2
  date_breaks <- c(min_date, mid_date, max_date)
  
  # Generate the map
  rec <- ggplot() +
    geom_tile(data = plot_df, aes(x = LONG, y = XLAT, fill = as.numeric(PDAT_clean))) +
    geom_path(data = country_outline, aes(x = long, y = lat, group = group), 
              color = "black", linewidth = 0.4, inherit.aes = FALSE) +
    
    facet_grid(Rank_Label ~ Cultivar, scales = "fixed") +
    
    # X Axis
    scale_x_continuous(
      breaks = scales::breaks_pretty(n = 3),
      labels = function(x) paste0(abs(x), "°", ifelse(x >= 0, "E", "W"))
    ) +
    
    # Y Axis
    scale_y_continuous(
      breaks = scales::breaks_pretty(n = 4),
      labels = function(y) paste0(abs(y), "°", ifelse(y >= 0, "N", "S"))
    ) +
    
    scale_fill_gradient2(
      name = "Planting Date",
      low = "dodgerblue4",
      mid = "gold",
      high = "firebrick",
      midpoint = as.numeric(mid_date),
      breaks = as.numeric(date_breaks),
      labels = format(date_breaks, "%b %d"),
      guide = guide_colorbar(reverse = TRUE)
    ) +
    
    coord_equal() +
    theme_bw() +
    labs(x = NULL, y = NULL) + 
    theme(
      
      strip.background = element_blank(),
      strip.text = element_text(face = "bold"),
      
      legend.position = "right", 
      legend.key.height = unit(1.5, "cm"),
      axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
    )
  
  plot_path <- file.path(output_dir, paste0(file_prefix, "planting_date_gradients.png"))
  ggplot2::ggsave(
    filename = plot_path,
    plot = rec,
    width = 10,
    height = 8,
    dpi = 300
  )
  message("Planting date plot saved to ", plot_path)
  
}


### Plot maps of top 3-highest yields by cultivar
plot_yield_gradients <- function(
    df, yield_col = "HWAH", country_name = "Rwanda", output_dir = ".", file_prefix = "",
    crop = NA_character_, use_crop_mask = FALSE,
    crop_mask_dir = "Landing/crop_masks", project_root = ".") {
  if (isTRUE(use_crop_mask)) {
    df <- apply_crop_mask(df, crop = crop, crop_mask_dir = crop_mask_dir, country = country_name)
    file_prefix <- paste0(file_prefix, "cropmask_")
  }
  plot_df <- df %>%
    dplyr::mutate(
      
      PDAT_clean = as.Date(PDAT)
    ) %>%
    
    dplyr::filter(Date_Rank <= 3)
  
  # Build the ordered factor labels for 4x3 plot rows/columns
  plot_df <- plot_df %>%
    dplyr::mutate(
      Rank_Label = factor(
        paste("Rank", Date_Rank), 
        levels = c("Rank 1", "Rank 2", "Rank 3")
      ),
      Cultivar = factor(
        Cultivar,
        # Not every crop has all 4 maturity classes (e.g. Potato/Wheat only
        # have Short/Medium/Long) - keep whichever are actually present, in
        # the canonical short-to-long order.
        levels = intersect(c("Short", "Medium", "Long", "Longer"), unique(as.character(Cultivar)))
      )
    )
  # Update the Rank_Label based on the input data
  plot_df <- plot_df %>%
    dplyr::mutate(
      Rank_Label = factor(
        dplyr::case_when(
          Date_Rank == 1 ~ "Top Recommendation",
          Date_Rank == 2 ~ "Second Choice",
          Date_Rank == 3 ~ "Third Choice"
        ),
        levels = c("Top Recommendation", "Second Choice", "Third Choice")
      )
    )
  
  # Fetch the requested country outline map. Prefer the high-resolution GADM
  # boundary already used/cached elsewhere in this pipeline (see
  # main/Forecast/00_config_function.R's build_country_config()) over the
  # coarse outline from the base "maps" package - see the identical fix in
  # plot_planting_date_gradients() for the full rationale/verification.
  country_outline <- tryCatch({
    country_code <- countrycode::countrycode(
      country_name, origin = "country.name", destination = "iso3c")
    admin_dir <- file.path(project_root, "data", "countries", country_code, "admin")
    adm0 <- geodata::gadm(country = country_code, level = 0, path = admin_dir)
    adm0_sf <- sf::st_as_sf(adm0)
    coords <- sf::st_coordinates(adm0_sf)
    data.frame(
      long = coords[, "X"], lat = coords[, "Y"],
      group = paste(coords[, "L2"], coords[, "L1"], sep = "."))
  }, error = function(e) {
    message("Falling back to low-resolution country outline: ", conditionMessage(e))
    ggplot2::map_data("world", region = country_name)
  })

  # Use data masking to evaluate the chosen yield column safely
  max_yield <- max(plot_df[[yield_col]], na.rm = TRUE)
  yield_breaks <- seq(0, max_yield, length.out = 4)
  
  # Generate the map
  yields <- ggplot() +
    geom_tile(data = plot_df, aes(x = LONG, y = XLAT, fill = .data[[yield_col]])) +
    geom_path(data = country_outline, aes(x = long, y = lat, group = group), 
              color = "black", linewidth = 0.4, inherit.aes = FALSE) +
    
    facet_grid(Rank_Label ~ Cultivar, scales = "fixed") +
    
    # X & Y Axis scales
    scale_x_continuous(
      breaks = scales::breaks_pretty(n = 3),
      labels = function(x) paste0(abs(x), "°", ifelse(x >= 0, "E", "W"))
    ) +
    scale_y_continuous(
      breaks = scales::breaks_pretty(n = 4),
      labels = function(y) paste0(abs(y), "°", ifelse(y >= 0, "N", "S"))
    ) +
    

    scale_fill_gradientn(
      name = "Harvested Yield",
      colors = c("dodgerblue4", "gold", "firebrick"),
      breaks = scales::breaks_pretty(n = 4),
      labels = scales::label_comma(accuracy = 1)
    ) +
    
    coord_equal() +
    theme_bw() +
    labs(x = NULL, y = NULL) + 
    theme(
      strip.background = element_blank(),
      strip.text = element_text(face = "bold"),
      legend.position = "right", 
      legend.key.height = unit(1.5, "cm"),
      axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
    )
  
  plot_path <- file.path(output_dir, paste0(file_prefix, "yield_by_pdate_cultivar.png"))
  ggplot2::ggsave(
    filename = plot_path,
    plot = yields,
    width = 10,
    height = 8,
    dpi = 300
  )
  
  message("Yield plot by planting dates and cultivars saved to ", plot_path)
}


### Get statistics for DSSAT results
summarize_and_save_dssat <- function(
    df, outputs = c("HWAH", "CWAM", "WUE"), output_dir = ".", file_prefix = "",
    crop = NA_character_, use_crop_mask = FALSE,
    crop_mask_dir = "Landing/crop_masks", country = NULL) {

  if (isTRUE(use_crop_mask)) {
    df <- apply_crop_mask(df, crop = crop, crop_mask_dir = crop_mask_dir, country = country)
    file_prefix <- paste0(file_prefix, "cropmask_")
  }

  # Grouping
  group_vars <- c("Cultivar", "PDAT")
  
  missing_vars <- setdiff(outputs, names(df))
  if (length(missing_vars) > 0) {
    stop("The following requested output variables do not exist in df: ", 
         paste(missing_vars, collapse = ", "))
  }
  
  # Compute stats for requested output variables
  summary_df <- df %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_vars))) %>%
    dplyr::summarise(
      n_simulations = dplyr::n(),
      
      # Track crop failure rate (where MDAT failed to simulate)
      maturity_failure_rate_pct = (sum(is.na(MDAT)) / dplyr::n()) * 100,
      
      # Compute stats across each requested variable in `outputs`
      dplyr::across(
        dplyr::all_of(outputs),
        list(
          mean   = ~ mean(.x, na.rm = TRUE),
          median = ~ median(.x, na.rm = TRUE),
          sd     = ~ sd(.x, na.rm = TRUE),
          cv_pct = ~ (sd(.x, na.rm = TRUE) / mean(.x, na.rm = TRUE)) * 100,
          p10    = ~ quantile(.x, 0.10, na.rm = TRUE),
          p90    = ~ quantile(.x, 0.90, na.rm = TRUE)
        ),
        .names = "{.col}_{.fn}"
      ),
      .groups = "drop"
    )
  
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  
  fixed_filename <- paste0(file_prefix, "treatment_summary.csv")
  file_path <- file.path(output_dir, fixed_filename)
  
  write_csv(summary_df, file_path)
  message("Summary statistics successfully saved to: ", file_path)
  
  
  return(summary_df)
}


### Save NC file of top combinations
#
# Writes one CF-conventional variable per physical quantity (cultivar,
# planting_date, <metric>), each with a labeled "rank" dimension, rather than
# stacking all of them into anonymous numbered bands of a single variable.
#
# @param crop, country, forecast_year, season, bc_method: recorded as global
#   attributes so the file is self-describing without its companion CSV/code.
export_top_combinations_nc <- function(
    df, metric = "HWAH", top_n = 5, output_dir = ".", file_prefix = "",
    crop = NA_character_, country = NA_character_, forecast_year = NA_integer_,
    season = NA_integer_, bc_method = NA_character_, use_crop_mask = FALSE,
    crop_mask_dir = "Landing/crop_masks") {

  if (isTRUE(use_crop_mask)) {
    df <- apply_crop_mask(df, crop = crop, crop_mask_dir = crop_mask_dir, country = country)
    file_prefix <- paste0(file_prefix, "cropmask_")
  }

  # Ensure target directory exists
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # 1. Fixed, canonical cultivar order (not unique()'s arbitrary first-
  #    appearance order) so the same name always gets the same code, and a
  #    legend is embeddable in the file regardless of which subset of
  #    maturity classes this crop has.
  cultivar_order <- intersect(
    c("Short", "Medium", "Long", "Longer"),
    unique(as.character(df$Cultivar[!is.na(df$Cultivar)]))
  )

  # 2. Add ranking across (XLAT, LONG) without grouping by Cultivar
  df_ranked <- df %>%
    add_combination_rank(metric = metric) %>%
    dplyr::filter(Combination_Rank <= top_n) %>%
    dplyr::mutate(
      PDAT_clean = as.Date(PDAT),
      # Days since epoch, not day-of-year: PDAT_doy would alias Dec 31 (365)
      # and Jan 2 (2) as if the January date were earlier, which is a real
      # risk here since the planting window can cross a calendar year.
      PDAT_days_since_epoch = as.numeric(PDAT_clean),
      Cultivar_ID = as.numeric(factor(Cultivar, levels = cultivar_order))
    )

  # 3. Build one multi-layer SpatRaster per quantity, one layer per rank
  #
  # Pixel centers here come from a geospatial point grid (e.g. a
  # cos-latitude-scaled km grid, clipped to an admin boundary) rather than
  # this repo's own fixed-degree grid, so consecutive point spacing isn't
  # always bit-for-bit constant (observed: LONG steps alternating 0.046/
  # 0.047 deg, XLAT steps 0.044/0.045 deg for a Zambia usecase) - too small
  # to be a real difference, but `terra::rast(df, type = "xyz")` demands
  # exact regularity and errors ("cell sizes are not regular") on this kind
  # of near-regular input. Build one shared template raster (resolution
  # taken as the median observed step, extent from the full ranked data so
  # every rank layer aligns) and terra::rasterize() each rank's points onto
  # it instead - tolerant of the same few-thousandths-of-a-degree jitter
  # that broke the strict xyz path.
  all_lon <- sort(unique(df_ranked$LONG))
  all_lat <- sort(unique(df_ranked$XLAT))
  res_lon <- stats::median(diff(all_lon))
  res_lat <- stats::median(diff(all_lat))
  template <- terra::rast(
    xmin = min(all_lon) - res_lon / 2, xmax = max(all_lon) + res_lon / 2,
    ymin = min(all_lat) - res_lat / 2, ymax = max(all_lat) + res_lat / 2,
    resolution = c(res_lon, res_lat), crs = "EPSG:4326")

  build_rank_layers <- function(value_col) {
    layers <- lapply(seq_len(top_n), function(r) {
      rank_df <- df_ranked %>%
        dplyr::filter(Combination_Rank == r) %>%
        dplyr::select(LONG, XLAT, dplyr::all_of(value_col))
      terra::rasterize(
        as.matrix(rank_df[, c("LONG", "XLAT")]), template,
        values = rank_df[[value_col]])
    })
    rr <- terra::rast(layers)
    terra::depth(rr) <- seq_len(top_n)
    terra::depthName(rr) <- "rank"
    names(rr) <- paste0("rank_", seq_len(top_n))
    rr
  }

  cultivar_rast <- build_rank_layers("Cultivar_ID")
  pdate_rast    <- build_rank_layers("PDAT_days_since_epoch")
  metric_rast   <- build_rank_layers(metric)

  # 4. Combine into one multi-variable dataset - each quantity keeps its own
  #    name, units and long_name instead of being flattened into one variable.
  sds_obj <- terra::sds(cultivar_rast, pdate_rast, metric_rast)
  names(sds_obj) <- c("cultivar", "planting_date", metric)
  cultivar_legend <- paste(seq_along(cultivar_order), cultivar_order, sep = "=", collapse = ", ")
  terra::units(sds_obj) <- c(
    paste0("categorical code (", cultivar_legend, ")"),
    "days since 1970-01-01",
    if (metric %in% c("HWAH", "CWAM")) "kg/ha" else "unknown"
  )
  terra::longnames(sds_obj) <- c(
    "Recommended cultivar maturity class (categorical code, see units for legend)",
    "Recommended planting date",
    paste0("Simulated ", metric, " for the recommended cultivar/date combination, rank ", 1, "-", top_n)
  )

  # 5. Export to NetCDF, named so it's identifiable outside its own folder
  file_path <- file.path(output_dir, paste0(
    file_prefix, "top_", top_n, "_", metric, "_combination_recommendation.nc"))

  # Note: terra::writeCDF's `atts` values must not contain commas - it splits
  # on them when parsing "key=value" pairs, so the cultivar legend (which does
  # contain commas) is deliberately left out here; it's already correctly
  # attached to the cultivar variable itself as flag_values/flag_meanings.
  global_atts <- c(
    paste0("crop=", crop),
    paste0("country=", country),
    paste0("forecast_year=", forecast_year),
    paste0("season=", season),
    paste0("bias_correction_method=", bc_method),
    paste0("rank_meaning=rank 1 is the best combination by ", metric, " at each pixel"),
    paste0("generated=", as.character(Sys.time()))
  )

  terra::writeCDF(
    sds_obj,
    filename = file_path,
    overwrite = TRUE,
    atts = global_atts
  )

  # 6. terra's writeCDF has no per-variable custom-attribute hook, so patch
  #    in proper CF flag_values/flag_meanings on the cultivar variable, and a
  #    calendar attribute on the date variable, directly via ncdf4.
  nc <- ncdf4::nc_open(file_path, write = TRUE)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  ncdf4::ncatt_put(nc, "cultivar", "flag_values", as.integer(seq_along(cultivar_order)))
  ncdf4::ncatt_put(nc, "cultivar", "flag_meanings", paste(cultivar_order, collapse = " "))
  ncdf4::ncatt_put(nc, "planting_date", "calendar", "standard")
  ncdf4::ncatt_put(nc, "rank", "long_name", paste0("Recommendation rank (1 = best by ", metric, ")"))
  ncdf4::ncatt_put(nc, "rank", "units", "1")

  message("Exported Top ", top_n, " NetCDF (cultivar/planting_date/", metric, ") to: ", file_path)
  invisible(file_path)
}


### Save CSV file of top combinations
export_top_combinations_csv <- function(
    df, metric = "HWAH", top_n = 5, output_dir = ".", file_prefix = "",
    crop = NA_character_, use_crop_mask = FALSE,
    crop_mask_dir = "Landing/crop_masks", country = NULL) {

  if (isTRUE(use_crop_mask)) {
    df <- apply_crop_mask(df, crop = crop, crop_mask_dir = crop_mask_dir, country = country)
    file_prefix <- paste0(file_prefix, "cropmask_")
  }

  # Ensure target directory exists
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # 1. Rank combinations and select the top N per pixel
  df_ranked <- df %>%
    add_combination_rank(metric = metric) %>%
    dplyr::filter(Combination_Rank <= top_n) %>%
    dplyr::mutate(
      PDAT_clean = format(as.Date(PDAT), "%Y-%m-%d")
    )
  
  # 2. Reshape from long to wide format (1 row per XLAT, LONG pixel)
  df_wide <- df_ranked %>%
    dplyr::select(
      XLAT, LONG, Combination_Rank, Cultivar, PDAT_clean, Metric_Value = .data[[metric]]
    ) %>%
    tidyr::pivot_wider(
      id_cols = c(XLAT, LONG),
      names_from = Combination_Rank,
      values_from = c(Cultivar, PDAT_clean, Metric_Value),
      names_glue = "{.value}_Rank_{Combination_Rank}"
    )
  
  # 3. Interleave columns by rank (Rank 1 Cultivar, Date, Metric -> Rank 2 Cultivar, Date, Metric...)
  ordered_cols <- c("XLAT", "LONG")
  for (r in 1:top_n) {
    ordered_cols <- c(
      ordered_cols,
      paste0("Cultivar_Rank_", r),
      paste0("PDAT_clean_Rank_", r),
      paste0("Metric_Value_Rank_", r)
    )
  }
  
  # Select available columns (handles cases where a pixel has fewer than top_n options)
  existing_cols <- intersect(ordered_cols, names(df_wide))
  
  df_output <- df_wide %>%
    dplyr::select(dplyr::all_of(existing_cols)) %>%
    # Rename Metric_Value columns to match the actual metric name (e.g., HWAH_Rank_1)
    dplyr::rename_with(
      ~ gsub("Metric_Value", metric, .x),
      dplyr::starts_with("Metric_Value")
    ) %>%
    dplyr::rename_with(
      ~ gsub("PDAT_clean", "PDAT", .x),
      dplyr::starts_with("PDAT_clean")
    ) %>%
    dplyr::arrange(XLAT, LONG)
  
  # 4. Save to CSV
  file_path <- file.path(output_dir, paste0(
    file_prefix, "top_", top_n, "_", metric, "_combination_recommendation.csv"))
  
  write.csv(df_output, file = file_path, row.names = FALSE)
  
  message("Exported Top ", top_n, " CSV recommendations to: ", file_path)
  
  return(df_output)
}

