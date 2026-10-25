###############################################################################
# DSSAT results dashboard (Shiny prototype)
#
# Replaces the per-country/crop crosstalk HTML dashboards (dashboard_template
# .Rmd), which embed every row of data in the browser for client-side
# filtering - fine for Mozambique (~62k rows, 83 MB html) but a 152 MB file
# that freezes on open for Zambia (~231k rows). This app instead keeps the
# data in a partitioned Parquet store (built by ../build_dashboard_store.R)
# and pushes country/crop/rank/cultivar filtering down to arrow, so the
# browser only ever receives the current filtered subset - independent of how
# many countries/crops accumulate in the store over time.
#
# Fully offline: no basemap tiles are fetched (leaflet::addProviderTiles
# needs a live tile server); the map instead draws each country's boundary
# from the GADM outline already cached on disk elsewhere in this pipeline
# (data/countries/<ISO3>/admin/gadm/), same file dashboard_template.Rmd's
# fetch_admin_outline() reads. If a country has no cached boundary, points
# still render, just without an outline.
#
# Data resolution - works two ways, so the SAME app.R runs both as a
# standalone bundle on someone's laptop and as part of this repo on a server:
#  1. Portable bundle: a "data/" folder copied in next to this app.R (see
#     package_for_laptop.R, one directory up) - self-contained, nothing else
#     needed, no internet at any point.
#  2. In-repo: no local "data/" next to this file, so it falls back to
#     ../../../data (this repo's own data/dashboard_store, built by
#     build_dashboard_store.R) - what a future hosted deployment would use,
#     pointed at a shared/updated store instead of a laptop-local copy.
#
# Run:
#   shiny::runApp("dashboard_app")   # from the folder containing dashboard_app/
#   # or open this file in RStudio/Positron and click "Run App"
###############################################################################

suppressPackageStartupMessages({
  library(shiny)
  library(arrow)
  library(dplyr)
  library(leaflet)
  library(plotly)
  library(DT)
  library(countrycode)
})

# In a portable bundle (see ../package_dashboard_app_for_laptop.R),
# dashboard_store/ and countries/ are siblings directly under a local data/
# folder next to this app.R. In this repo, they live in their own established
# spots instead - dashboard_store under data/usecases/results/ (this repo's
# existing home for cross-country shareable output; see build_dashboard_store
# .R), and countries/ at the top-level data/countries/ used throughout the
# rest of the pipeline - so the two are resolved independently rather than
# assumed to share one parent.
resolve_first_existing <- function(candidates, what) {
  for (candidate in candidates) {
    if (dir.exists(candidate)) return(normalizePath(candidate))
  }
  stop(
    "Could not find ", what, ". Looked in:\n  ", paste(candidates, collapse = "\n  "),
    "\nIf this is the repo copy, build the store first with:\n",
    "  Rscript main/DSSAT/build_dashboard_store.R")
}

STORE_DIR <- resolve_first_existing(
  c(file.path(getwd(), "data", "dashboard_store"),
    file.path(getwd(), "..", "..", "..", "data", "usecases", "results", "dashboard_store")),
  "dashboard_store")

GADM_ROOT <- resolve_first_existing(
  c(file.path(getwd(), "data", "countries"),
    file.path(getwd(), "..", "..", "..", "data", "countries")),
  "countries")

ds <- arrow::open_dataset(STORE_DIR)

# Daily rain for the rainfall maps (built by build_dashboard_store.R next to
# dashboard_store/). Optional: without it the maps show a note instead.
RAIN_DIR <- Filter(dir.exists, c(
  file.path(getwd(), "data", "rain_store"),
  file.path(getwd(), "..", "..", "..", "data", "usecases", "results", "rain_store")))[1]
rain_ds <- if (!is.na(RAIN_DIR)) arrow::open_dataset(RAIN_DIR) else NULL

# Recommended rainfall windows (days); see the note under the rainfall maps
X_AFTER_DEFAULT <- 30
X_BEFORE_DEFAULT <- 14

# Available (country, crop, usecase) combinations - arrow prunes this to the
# partition directory names rather than scanning any row data, so it's
# instant even once the store holds many countries/crops.
combos <- ds %>%
  dplyr::distinct(country, crop, usecase) %>%
  dplyr::collect() %>%
  dplyr::arrange(country, crop, usecase)

if (nrow(combos) == 0) stop("Dashboard store at ", STORE_DIR, " is empty.")

CANONICAL_CULTIVAR_ORDER <- c("Short", "Medium", "AVERAGE", "Long", "Longer")

# Orders cultivar labels by the canonical maturity-class vocabulary where
# possible, but APPENDS (rather than drops) any label this dashboard doesn't
# recognize - a prior bug (Nigeria's Kaduna usecase naming its middle
# cultivar "AVERAGE" instead of "MEDIUM") silently vanished from a dashboard
# that only knew Short/Medium/Long/Longer, and this app deliberately can't
# repeat that for whatever the next unanticipated label turns out to be.
order_cultivars <- function(x) {
  present <- unique(as.character(x))
  known <- intersect(CANONICAL_CULTIVAR_ORDER, present)
  unknown <- sort(setdiff(present, CANONICAL_CULTIVAR_ORDER))
  c(known, unknown)
}

# Cultivar color scale, fixed across the WHOLE store (every cultivar label
# that appears anywhere), not just the current country/crop/usecase - a
# colorFactor() domain built per-scope would reassign "Short"'s color every
# time the visible set of cultivars changes size (e.g. 3 cultivars in one
# scope, 5 in another shifts which palette slot each one lands in), making
# color meaningless for comparing across countries/crops in the same
# session. Computed once at startup - cheap, this only scans one column.
GLOBAL_CULTIVAR_ORDER <- ds %>%
  dplyr::distinct(Cultivar) %>% dplyr::collect() %>%
  dplyr::pull(Cultivar) %>% order_cultivars()
GLOBAL_CULTIVAR_PAL <- leaflet::colorFactor("Dark2", domain = GLOBAL_CULTIVAR_ORDER, na.color = "transparent")
# Same hex values as the map's legend, keyed by cultivar name, so the
# boxplot's per-cultivar colors visually match the cultivar map instead of
# plotly picking its own independent (and per-scope-shifting) palette.
GLOBAL_CULTIVAR_COLORS <- setNames(GLOBAL_CULTIVAR_PAL(GLOBAL_CULTIVAR_ORDER), GLOBAL_CULTIVAR_ORDER)

# sf defaults to spherical (s2) geometry for lon/lat data, under which
# st_simplify() silently does nothing (GEOS's Douglas-Peucker simplifier
# only runs in planar mode) - without this, GADM's full-resolution
# coastlines (Mozambique's alone is ~191k vertices) get reloaded and
# re-serialized to the browser, unsimplified, on every country switch, which
# is what was freezing the app. Planar mode's small accuracy loss is
# irrelevant here - these boundaries are only ever drawn as visual context
# at country zoom, never used for area/distance calculations.
sf::sf_use_s2(FALSE)

# Offline world map background (see file header re: no internet/tiles) -
# built once at startup, reused under every map. `maps`'s bundled low-res
# world coastlines (no data download - the package ships them), same
# source dashboard_template.Rmd already falls back to via
# ggplot2::map_data("world").
WORLD_OUTLINE <- sf::st_as_sf(maps::map("world", plot = FALSE, fill = TRUE))

# Major lakes worldwide (includes the African Great Lakes - Victoria,
# Tanganyika, Malawi, Albert - plus Lake Chad and Lake Tana), bundled with
# `maps` itself, same offline-data approach as WORLD_OUTLINE above. There is
# no offline river dataset in this environment's installed packages, so
# rivers are left out rather than silently mislabeling this as "water
# bodies" in general.
WATER_BODIES <- sf::st_as_sf(maps::map("lakes", plot = FALSE, fill = TRUE))

# Cached-only country boundary (see file header re: offline), simplified for
# fast rendering (see sf_use_s2() note above) and repaired afterwards -
# simplifying a complex coastline can leave a self-intersection even with
# preserveTopology = TRUE. Returns an sf polygon/multipolygon object, or
# NULL if nothing is cached for this country.
load_country_outline <- function(country_name) {
  iso3 <- suppressWarnings(countrycode::countrycode(country_name, "country.name", "iso3c"))
  if (is.na(iso3)) return(NULL)
  cache_file <- file.path(GADM_ROOT, iso3, "admin", "gadm", paste0("gadm41_", iso3, "_0_pk.rds"))
  if (!file.exists(cache_file)) return(NULL)
  tryCatch({
    outline <- sf::st_as_sf(terra::vect(cache_file))
    outline <- sf::st_simplify(outline, dTolerance = 0.02, preserveTopology = TRUE)
    sf::st_make_valid(outline)
  }, error = function(e) NULL)
}

pdat_label_format <- function(type, cuts, p) {
  d <- as.Date(cuts, origin = "1970-01-01")
  paste0(as.integer(format(d, "%d")), " - ", format(d, "%b"))
}

# One base map (world background, country boundary, fitted view, no markers
# yet) - rebuilt only when country/crop/usecase changes, not on every filter
# tweak.
base_map <- function(elementId, outline, bounds) {
  m <- leaflet::leaflet(elementId = elementId, options = leaflet::leafletOptions(preferCanvas = TRUE)) %>%
    leaflet::addPolygons(
      data = WORLD_OUTLINE, fillColor = "#f0efe9", fillOpacity = 1,
      color = "#cfcabf", weight = 0.5) %>%
    leaflet::addPolygons(
      data = WATER_BODIES, fillColor = "#a6cee3", fillOpacity = 1,
      color = "#a6cee3", weight = 0.5)
  if (!is.null(outline)) {
    m <- leaflet::addPolygons(
      m, data = outline, fill = FALSE, color = "black", weight = 1, opacity = 0.6)
  }
  if (!is.null(bounds)) {
    m <- leaflet::fitBounds(m, bounds$lng1, bounds$lat1, bounds$lng2, bounds$lat2)
  }
  m
}

pixel_key <- function(lat, lon) sprintf("%.3f_%.3f", lat, lon)

# One usecase's daily rain as a pixel x day cumulative-sum matrix, so any
# window sum is two lookups: cum[, end + 1] - cum[, start]. Missing days
# count as 0 mm.
build_rain_cum <- function(rain) {
  if (is.null(rain) || nrow(rain) == 0) return(NULL)
  keys <- unique(pixel_key(rain$XLAT, rain$LONG))
  dates <- sort(unique(rain$DATE))
  m <- matrix(0, length(keys), length(dates))
  m[cbind(match(pixel_key(rain$XLAT, rain$LONG), keys), match(rain$DATE, dates))] <-
    ifelse(is.na(rain$RAIN), 0, rain$RAIN)
  cum <- cbind(0, m)
  for (j in seq_len(ncol(m))) cum[, j + 1] <- cum[, j] + m[, j]
  list(keys = keys, first = dates[1], last = dates[length(dates)], cum = cum)
}

# Rain summed over [start, end] (inclusive) at each point. A window starting
# before the data is NA; one running past the data end is clipped to it.
rain_window_sum <- function(rc, lat, lon, start, end) {
  n <- length(lat)
  if (is.null(rc) || n == 0) return(list(value = rep(NA_real_, n), n_na = n, n_clipped = 0L))
  row <- match(pixel_key(lat, lon), rc$keys)
  n_days <- ncol(rc$cum) - 1L
  s <- as.integer(as.Date(start) - rc$first) + 1L
  e <- as.integer(as.Date(end) - rc$first) + 1L
  clipped <- !is.na(e) & e > n_days
  e <- pmin(e, n_days)
  ok <- !is.na(row) & !is.na(s) & !is.na(e) & s >= 1L & s <= n_days
  value <- rep(NA_real_, n)
  value[ok] <- ifelse(
    e[ok] < s[ok], 0,
    rc$cum[cbind(row[ok], e[ok] + 1L)] - rc$cum[cbind(row[ok], s[ok])])
  list(value = value, n_na = sum(!ok), n_clipped = sum(clipped & ok))
}

fmt_day <- function(d) format(as.Date(d), "%d %b %Y")

# Pure cascade-resolution logic (country -> crop -> usecase), factored out of
# the observeEvent()s below so it can be unit-tested directly - testServer()
# can't verify this any other way, since it can't simulate the browser-side
# JS that echoes updateSelectInput()'s selection back into input$x.
resolve_crop <- function(country, current_crop, combos) {
  crops <- sort(unique(combos$crop[combos$country == country]))
  list(choices = crops, selected = if (isTRUE(current_crop %in% crops)) current_crop else crops[1])
}

resolve_usecase <- function(country, crop, current_usecase, combos) {
  usecases <- sort(unique(combos$usecase[combos$country == country & combos$crop == crop]))
  list(choices = usecases, selected = if (isTRUE(current_usecase %in% usecases)) current_usecase else usecases[1])
}

ui <- fluidPage(
  title = "DSSAT planting-date and cultivar recommendations",
  tags$head(tags$style(HTML("
    .filter-note { color: #666; font-size: 0.85em; margin-top: -6px; }
    .status-line { font-weight: bold; margin: 8px 0; }
    .mask-note { color: #8a6d3b; background: #fcf8e3; border: 1px solid #faebcc;
                 border-radius: 4px; padding: 6px 10px; font-size: 0.85em; margin: 6px 0; }
    .outline-note { color: #666; font-size: 0.8em; font-weight: normal; }
    .about-note { color: #31708f; background: #f0f7fa; border: 1px solid #bce8f1;
                  border-radius: 4px; padding: 8px 12px; font-size: 0.9em; margin: 6px 0 14px 0; }
    .about-note summary { cursor: pointer; font-weight: bold; }
    .about-note p { margin: 6px 0 0 0; }
    .about-note ul { margin: 4px 0 0 0; padding-left: 1.2em; }
    .rank-quick-buttons .btn { padding: 1px 8px; font-size: 0.8em; margin-right: 4px; margin-bottom: 4px; }
    /* Shiny adds this class to any output element while its reactive is
       recomputing - fading it gives visible feedback during scope switches
       (loading a country's boundary + requerying can take up to ~1s),
       instead of the map/table/plot just sitting inert with no cue. */
    .recalculating { opacity: 0.4; transition: opacity 0.15s linear; }
  "))),
  titlePanel("DSSAT planting-date and cultivar recommendations"),
  tags$details(class = "about-note", open = NA,
    tags$summary("About this data"),
    tags$p(
      "Every point shown here is a simulation, not an observation: the DSSAT crop model was run at each grid ",
      "location for a set of candidate cultivars (maturity classes) crossed with a set of candidate planting ",
      "dates, and the combinations at each point were ranked by simulated yield. \"Rank 1\" is the ",
      "highest-yielding cultivar/planting-date combination the model found for that point; higher ranks are ",
      "progressively lower-yielding alternatives - not separate predictions of what will actually happen."),
    tags$p(tags$b("Key assumptions:")),
    tags$ul(
      tags$li(
        "Planting date candidates are derived from this pipeline's season-onset logic (rainfall-based ",
        "detection of the start of the growing season at each point/year), not tested across arbitrary ",
        "calendar dates - so a recommended date reflects the best-performing option among onset-plausible ",
        "dates, not a search of the whole year."),
      tags$li(
        "\"Crop mask only\" restricts the map/table to locations inside that crop's estimated cropland mask, ",
        "where one exists for the country; some country/crop combinations have no mask yet, in which case ",
        "every simulated point is shown regardless of this filter (flagged below the filters when it applies)."),
      tags$li(
        "Results depend on the weather, soil, and management inputs used for each simulation and on DSSAT's ",
        "own modeling assumptions - they are a decision-support estimate, not a guarantee of field outcomes."),
      tags$li(
        "Rainfall maps show the bias-corrected seasonal forecast rain (ensemble mean) that the simulations ",
        "were run with, not observed rain."))
  ),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput("country", "Country", choices = sort(unique(combos$country))),
      selectInput("crop", "Crop", choices = NULL),
      selectInput("usecase", "Usecase / run", choices = NULL),
      hr(),
      checkboxInput("mask_only", "Crop mask only", value = TRUE),
      uiOutput("mask_note"),
      checkboxGroupInput("cultivar", "Cultivar", choices = NULL),
      checkboxGroupInput("rank", "Recommendation rank", choices = NULL, inline = TRUE),
      div(class = "rank-quick-buttons",
          actionButton("rank_top1", "Rank 1 only", class = "btn-default btn-xs"),
          actionButton("rank_all", "All ranks", class = "btn-default btn-xs")),
      div(class = "filter-note",
          "Rank 1 = each location's best-performing planting-date/cultivar ",
          "combination; higher numbers are progressively lower-yielding ",
          "alternatives. All filtering happens in the data store, not in ",
          "the browser, so this stays fast at any dataset size.")
    ),
    mainPanel(
      width = 9,
      div(class = "status-line", textOutput("status_line")),
      uiOutput("outline_note"),
      fluidRow(
        column(4, h5("Estimated Yields"), leafletOutput("map_yield", height = 420)),
        column(4, h5("Recommended Cultivar"), leafletOutput("map_cultivar", height = 420)),
        column(4, h5("Recommended Planting Date"), leafletOutput("map_pdat", height = 420))
      ),
      fluidRow(
        column(6, h4("Yield distribution by cultivar"), plotlyOutput("boxplot", height = 320)),
        column(6, h4("Planting dates of the selected recommendations"),
               plotlyOutput("pdat_hist", height = 320))
      ),
      h4("Rainfall (bias-corrected forecast used in the simulations)"),
      uiOutput("rain_note"),
      div(class = "filter-note",
          "Default windows: 30 days after onset or planting covers germination, emergence and early ",
          "growth, the window where a false start shows (FAO-56 initial stage: 20-30 d maize, 15-20 d ",
          "soybean; onset studies check dry spells over the 20-30 d after onset). 14 days before planting ",
          "reflects seedbed moisture at sowing, since topsoil dries out within about two weeks."),
      fluidRow(
        column(6,
          h5("Rain in the first X days after season onset"),
          sliderInput("x_onset", "X (days)", min = 7, max = 60, value = X_AFTER_DEFAULT, step = 1),
          leafletOutput("map_rain_onset", height = 380), uiOutput("cap_onset")),
        column(6,
          h5("Rain X days before / after planting"),
          radioButtons("plant_mode", NULL, inline = TRUE, selected = "after",
                       choices = c("Before planting" = "before", "After planting" = "after")),
          sliderInput("x_plant", "X (days)", min = 7, max = 60, value = X_AFTER_DEFAULT, step = 1),
          leafletOutput("map_rain_plant", height = 380), uiOutput("cap_plant"))
      ),
      fluidRow(
        column(6,
          h5("Rain from planting to maturity (or harvest if maturity isn't reached)"),
          leafletOutput("map_rain_season", height = 380), uiOutput("cap_season")),
        column(6,
          h5("Rain from the start of the rainfall data to sowing"),
          leafletOutput("map_rain_presow", height = 380), uiOutput("cap_presow"))
      ),
      h4("Recommendations table"),
      DTOutput("table")
    )
  )
)

server <- function(input, output, session) {

  # --- Cascading selectors: crop options depend on country, usecase options
  # depend on country+crop - each narrowed to what actually exists rather
  # than a fixed vocabulary, so a new country/crop dropped into the store by
  # re-running build_dashboard_store.R just shows up with no code change.
  #
  # Always pass an explicit `selected` here, and have the country handler set
  # BOTH crop and usecase itself rather than relying on the crop observer
  # below to cascade automatically. updateSelectInput() with no `selected`
  # only resets choices; if the previously-selected crop (e.g. "Maize") is
  # still valid for the new country, its VALUE never changes, so an
  # observeEvent(input$crop) below would never fire - leaving usecase
  # pointed at the OLD country's run. scope() would then silently resolve to
  # a nonexistent (country, crop, usecase) combo, and every downstream
  # output would go blank via req() with no visible error - indistinguishable
  # from a freeze. Setting both explicitly here removes that gap entirely.
  observeEvent(input$country, {
    crop_res <- resolve_crop(input$country, input$crop, combos)
    updateSelectInput(session, "crop", choices = crop_res$choices, selected = crop_res$selected)

    usecase_res <- resolve_usecase(input$country, crop_res$selected, input$usecase, combos)
    updateSelectInput(session, "usecase", choices = usecase_res$choices, selected = usecase_res$selected)
  }, ignoreNULL = TRUE)

  # Covers the user changing crop directly (country unchanged) - keeps the
  # current usecase selected if it's still valid for the new crop (e.g. two
  # crops sharing one usecase run), else falls back to the first available.
  observeEvent(input$crop, {
    req(input$country)
    usecase_res <- resolve_usecase(input$country, input$crop, input$usecase, combos)
    updateSelectInput(session, "usecase", choices = usecase_res$choices, selected = usecase_res$selected)
  }, ignoreNULL = TRUE)

  # Everything for the selected country/crop/usecase, unfiltered by
  # rank/cultivar/mask - used only to compute fixed color-scale domains and
  # populate the cultivar/rank checkboxes, so those stay stable as the user
  # toggles filters (matches the old dashboard's "fixed scale" behavior).
  scope <- reactive({
    req(input$country, input$crop, input$usecase)
    ds %>% dplyr::filter(country == input$country, crop == input$crop, usecase == input$usecase)
  })

  scope_meta <- reactive({
    s <- scope() %>%
      dplyr::select(Cultivar, Combination_Rank, HWAH, PDAT, in_crop_mask) %>%
      dplyr::collect()
    # Defensive only - every (country, crop, usecase) triple offered in the
    # dropdowns comes from `combos`, which is derived from this same store,
    # so scope() should never actually resolve to zero rows. Guarding anyway
    # so a future edge case degrades to an empty view instead of an
    # Inf-domain error out of colorNumeric()/fitBounds().
    if (nrow(s) == 0) {
      return(list(
        cultivar_order = character(0), ranks = integer(0), hwah_range = c(0, 1),
        pdat_range = c(0, 1), has_crop_mask = FALSE))
    }
    list(
      cultivar_order = order_cultivars(s$Cultivar),
      ranks = sort(unique(s$Combination_Rank)),
      hwah_range = range(s$HWAH, na.rm = TRUE),
      pdat_range = range(as.numeric(s$PDAT), na.rm = TRUE),
      # build_dashboard_extract() (get_pdate_cultivar_recommendation.R) sets
      # EVERY row's in_crop_mask to TRUE when a crop has no real crop-mask
      # raster for this country yet, so the "crop mask only" filter is a
      # silent no-op rather than an error. Same signal used here: if literally
      # every simulated point in scope is (trivially) "in the mask", treat it
      # as no real mask rather than an implausibly complete one, and say so -
      # the original crosstalk dashboard surfaced this explicitly and this
      # app dropped it by accident.
      has_crop_mask = !all(s$in_crop_mask)
    )
  })

  observeEvent(scope_meta(), {
    meta <- scope_meta()
    updateCheckboxGroupInput(session, "cultivar", choices = meta$cultivar_order, selected = meta$cultivar_order)
    updateCheckboxGroupInput(session, "rank", choices = meta$ranks, selected = meta$ranks[1])
  })

  observeEvent(input$rank_top1, {
    req(scope_meta()$ranks)
    updateCheckboxGroupInput(session, "rank", selected = scope_meta()$ranks[1])
  })
  observeEvent(input$rank_all, {
    req(scope_meta()$ranks)
    updateCheckboxGroupInput(session, "rank", selected = scope_meta()$ranks)
  })

  output$mask_note <- renderUI({
    if (isTRUE(scope_meta()$has_crop_mask)) return(NULL)
    div(class = "mask-note",
        sprintf(
          "No cropland mask is available yet for %s in %s - \"Crop mask only\" has no effect; all simulated locations are shown.",
          input$crop, input$country))
  })

  output$outline_note <- renderUI({
    if (!is.null(outline())) return(NULL)
    div(class = "outline-note", sprintf("No cached boundary outline for %s - showing points only.", input$country))
  })

  # The subset actually shown - country/crop/usecase from `scope()`, plus the
  # cheap, frequently-changing rank/cultivar/mask filters. Pushed down to
  # arrow and only collected (pulled into R/the browser) here.
  #
  # Unchecking every cultivar/rank box is a valid selection meaning "show
  # nothing", not an absent one - using req() here (which silently halts the
  # whole reactive chain on a NULL/empty input) would leave every output
  # frozen on its last rendered state with no indication anything happened,
  # rather than updating to reflect the now-empty result.
  filtered_data <- reactive({
    empty_cols <- scope() %>% utils::head(0) %>% dplyr::collect()
    if (length(input$cultivar) == 0 || length(input$rank) == 0) {
      return(dplyr::mutate(empty_cols, Cultivar = factor(Cultivar, levels = scope_meta()$cultivar_order)))
    }
    # Cast to integer OUTSIDE the filter() call, into a plain local variable,
    # not inline as `Combination_Rank %in% as.integer(input$rank)` -
    # arrow's dplyr translation mishandles a multi-element as.integer() call
    # made inline inside filter() (misreads it as an Arrow-side cast on a
    # list-typed array rather than a local R vector to evaluate first),
    # raising "Unsupported cast from list<item: string> to int32" as soon as
    # more than one rank checkbox is selected. A precomputed local variable
    # is unambiguous - dplyr always treats it as a value from the R
    # environment, exactly as intended.
    rank_int <- as.integer(input$rank)
    q <- scope() %>% dplyr::filter(
      Cultivar %in% input$cultivar,
      Combination_Rank %in% rank_int)
    if (isTRUE(input$mask_only)) q <- q %>% dplyr::filter(in_crop_mask)
    q %>% dplyr::collect() %>%
      dplyr::mutate(Cultivar = factor(Cultivar, levels = scope_meta()$cultivar_order))
  })

  output$status_line <- renderText({
    d <- filtered_data()
    sprintf(
      "%s %s (%s): %s rows shown, %s grid points",
      input$crop, input$country, input$usecase,
      format(nrow(d), big.mark = ","),
      format(nrow(unique(d[, c("XLAT", "LONG")])), big.mark = ","))
  })

  # --- Base maps: rebuilt only when country/crop/usecase changes.
  map_bounds <- reactive({
    d <- scope() %>% dplyr::select(XLAT, LONG) %>% dplyr::collect()
    if (nrow(d) == 0) return(NULL)  # defensive - see scope_meta() note above
    lng_range <- range(d$LONG, na.rm = TRUE)
    lat_range <- range(d$XLAT, na.rm = TRUE)
    lng_pad <- max(diff(lng_range) * 0.1, 0.05)
    lat_pad <- max(diff(lat_range) * 0.1, 0.05)
    list(
      lng1 = lng_range[1] - lng_pad, lat1 = lat_range[1] - lat_pad,
      lng2 = lng_range[2] + lng_pad, lat2 = lat_range[2] + lat_pad)
  })

  outline <- reactive(load_country_outline(input$country))

  output$map_yield <- renderLeaflet(base_map("map_yield", outline(), map_bounds()))
  output$map_cultivar <- renderLeaflet(base_map("map_cultivar", outline(), map_bounds()))
  output$map_pdat <- renderLeaflet(base_map("map_pdat", outline(), map_bounds()))

  # --- Marker layers: refreshed via leafletProxy on every filter change,
  # without rebuilding the map/boundary/view (keeps current zoom/pan intact).
  observeEvent(filtered_data(), {
    d <- filtered_data()
    meta <- scope_meta()
    # addCircleMarkers(label = character(0)) errors ("invalid 'type' (list)
    # of argument") rather than just adding zero markers - sprintf() on a
    # 0-row data frame returns character(0), which is exactly what happens
    # whenever every cultivar/rank checkbox is unchecked (a normal, supported
    # state - see filtered_data() above). NULL is the value addCircleMarkers
    # actually expects for "no labels".
    label <- if (nrow(d) == 0) NULL else sprintf("%s | %s | %.0f kg/ha", d$Cultivar, format(d$PDAT, "%Y-%m-%d"), d$HWAH)

    pal_yield <- leaflet::colorNumeric("YlOrRd", domain = meta$hwah_range, na.color = "transparent")
    leaflet::leafletProxy("map_yield") %>%
      leaflet::clearMarkers() %>% leaflet::clearControls() %>%
      leaflet::addCircleMarkers(
        data = d, lng = ~LONG, lat = ~XLAT, radius = 5, stroke = FALSE, fillOpacity = 0.8,
        color = ~pal_yield(HWAH), label = label) %>%
      leaflet::addLegend("bottomright", pal = pal_yield, values = meta$hwah_range, title = "Yield (kg/ha)")

    leaflet::leafletProxy("map_cultivar") %>%
      leaflet::clearMarkers() %>% leaflet::clearControls() %>%
      leaflet::addCircleMarkers(
        data = d, lng = ~LONG, lat = ~XLAT, radius = 5, stroke = FALSE, fillOpacity = 0.8,
        color = ~GLOBAL_CULTIVAR_PAL(Cultivar), label = label) %>%
      leaflet::addLegend("bottomright", pal = GLOBAL_CULTIVAR_PAL, values = GLOBAL_CULTIVAR_ORDER, title = "Cultivar")

    pal_pdat <- leaflet::colorNumeric(
      "RdYlBu", domain = meta$pdat_range, na.color = "transparent", reverse = TRUE)
    leaflet::leafletProxy("map_pdat") %>%
      leaflet::clearMarkers() %>% leaflet::clearControls() %>%
      leaflet::addCircleMarkers(
        data = d, lng = ~LONG, lat = ~XLAT, radius = 5, stroke = FALSE, fillOpacity = 0.8,
        color = ~pal_pdat(as.numeric(PDAT)), label = label) %>%
      leaflet::addLegend(
        "bottomright", pal = pal_pdat, values = meta$pdat_range, title = "Planting date",
        labFormat = pdat_label_format)
  })

  output$boxplot <- renderPlotly({
    d <- filtered_data()
    plotly::plot_ly(
      d, x = ~Cultivar, y = ~HWAH, color = ~Cultivar, colors = GLOBAL_CULTIVAR_COLORS, type = "box",
      boxpoints = "all", jitter = 0.4, pointpos = 0,
      fillcolor = "rgba(0,0,0,0)", line = list(color = "rgba(0,0,0,0)"),
      showlegend = FALSE) %>%
      plotly::layout(xaxis = list(title = "Cultivar"), yaxis = list(title = "Yield (kg/ha)"))
  })

  output$pdat_hist <- renderPlotly({
    d <- filtered_data()
    if (nrow(d) == 0) return(plotly::plotly_empty(type = "scatter", mode = "markers"))
    # Shared 7-day bins (one per candidate-date spacing), starting at the
    # scope's earliest date so the stacked cultivar bars line up
    bin_start <- as.Date(scope_meta()$pdat_range[1], origin = "1970-01-01")
    plotly::plot_ly(
      d, x = ~PDAT, color = ~Cultivar, colors = GLOBAL_CULTIVAR_COLORS, type = "histogram",
      xbins = list(start = format(as.POSIXct(bin_start) - 43200, "%Y-%m-%d %H:%M:%S"), size = 7 * 86400000)) %>%
      plotly::layout(
        barmode = "stack", xaxis = list(title = "Planting date"),
        yaxis = list(title = "Grid points x cultivars"))
  })

  # --- Rainfall maps
  scope_rain <- reactive({
    req(input$country, input$usecase)
    if (is.null(rain_ds)) return(NULL)
    rain_ds %>%
      dplyr::filter(country == input$country, usecase == input$usecase) %>%
      dplyr::select(XLAT, LONG, DATE, RAIN) %>%
      dplyr::collect() %>%
      build_rain_cum()
  })

  # Every rank of the scope, for colour domains that stay fixed while the
  # rank/cultivar filters change (like the other maps)
  scope_all <- reactive({
    scope() %>%
      dplyr::select(XLAT, LONG, PDAT, MDAT, HDAT, onset_date, maturity_failed, in_crop_mask) %>%
      dplyr::collect()
  })

  output$rain_note <- renderUI({
    if (!is.null(scope_rain())) return(NULL)
    div(class = "mask-note", sprintf(
      "No daily rain stored for %s (%s) - rainfall maps are empty. Run add_rain_onset_to_results.R and rebuild the store.",
      input$country, input$usecase))
  })

  observeEvent(input$plant_mode, {
    updateSliderInput(session, "x_plant",
                      value = if (input$plant_mode == "before") X_BEFORE_DEFAULT else X_AFTER_DEFAULT)
  }, ignoreInit = TRUE)

  output$map_rain_onset <- renderLeaflet(base_map("map_rain_onset", outline(), map_bounds()))
  output$map_rain_plant <- renderLeaflet(base_map("map_rain_plant", outline(), map_bounds()))
  output$map_rain_season <- renderLeaflet(base_map("map_rain_season", outline(), map_bounds()))
  output$map_rain_presow <- renderLeaflet(base_map("map_rain_presow", outline(), map_bounds()))

  # Each window is (start, end) per row of a data frame with PDAT/MDAT/...
  window_onset <- function(d) list(start = d$onset_date, end = d$onset_date + input$x_onset - 1)
  window_plant <- function(d) {
    if (input$plant_mode == "before") list(start = d$PDAT - input$x_plant, end = d$PDAT - 1)
    else list(start = d$PDAT, end = d$PDAT + input$x_plant - 1)
  }
  window_season <- function(d) list(start = d$PDAT, end = dplyr::if_else(d$maturity_failed, d$HDAT, d$MDAT))
  window_presow <- function(d) {
    first <- if (is.null(scope_rain())) as.Date(NA) else scope_rain()$first
    list(start = rep(first, nrow(d)), end = d$PDAT - 1)
  }

  rain_layer <- function(d, window_fn, all_rows) {
    rc <- scope_rain()
    w <- window_fn(d)
    r <- rain_window_sum(rc, d$XLAT, d$LONG, w$start, w$end)
    w_all <- window_fn(all_rows)
    dom <- range(rain_window_sum(rc, all_rows$XLAT, all_rows$LONG, w_all$start, w_all$end)$value, na.rm = TRUE)
    if (!all(is.finite(dom))) dom <- c(0, 1)
    c(r, list(d = d, start = w$start, end = w$end, domain = dom))
  }

  # Map 2 is per pixel (onset doesn't depend on rank/cultivar), only masked
  onset_pixels <- reactive({
    p <- dplyr::distinct(scope_all(), XLAT, LONG, onset_date, in_crop_mask)
    if (isTRUE(input$mask_only)) p <- p[p$in_crop_mask, ]
    p
  })
  layer_onset <- reactive(rain_layer(onset_pixels(), window_onset, dplyr::distinct(scope_all(), XLAT, LONG, onset_date)))
  layer_plant <- reactive(rain_layer(filtered_data(), window_plant, scope_all()))
  layer_season <- reactive(rain_layer(filtered_data(), window_season, scope_all()))
  layer_presow <- reactive(rain_layer(filtered_data(), window_presow, scope_all()))

  draw_rain <- function(map_id, layer, show_cultivar = TRUE) {
    d <- layer$d
    pal <- leaflet::colorNumeric("YlGnBu", domain = layer$domain, na.color = "#bdbdbd")
    label <- if (nrow(d) == 0) NULL else sprintf(
      "%s%.0f mm (%s - %s)",
      if (show_cultivar) sprintf("%s | %s | ", d$Cultivar, format(d$PDAT, "%d %b")) else "",
      layer$value, format(as.Date(layer$start), "%d %b"), format(as.Date(layer$end), "%d %b"))
    leaflet::leafletProxy(map_id) %>%
      leaflet::clearMarkers() %>% leaflet::clearControls() %>%
      leaflet::addCircleMarkers(
        data = d, lng = ~LONG, lat = ~XLAT, radius = 5, stroke = FALSE, fillOpacity = 0.8,
        color = pal(layer$value), label = label) %>%
      leaflet::addLegend("bottomright", pal = pal, values = layer$domain, title = "Rain (mm)")
  }

  rain_caption <- function(layer, text) {
    rc <- scope_rain()
    notes <- c(
      if (!is.null(rc)) sprintf("Rain data: %s to %s.", fmt_day(rc$first), fmt_day(rc$last)),
      if (layer$n_na > 0) sprintf("%s point(s) with no rain value (grey).", format(layer$n_na, big.mark = ",")),
      if (layer$n_clipped > 0) sprintf("%s window(s) cut at the end of the data.", format(layer$n_clipped, big.mark = ",")))
    div(class = "filter-note", style = "margin-top: 4px;", text, " ", paste(notes, collapse = " "))
  }

  observe(draw_rain("map_rain_onset", layer_onset(), show_cultivar = FALSE))
  observe(draw_rain("map_rain_plant", layer_plant()))
  observe(draw_rain("map_rain_season", layer_season()))
  observe(draw_rain("map_rain_presow", layer_presow()))

  output$cap_onset <- renderUI(rain_caption(
    layer_onset(), sprintf("Onset day through day %d after it.", input$x_onset - 1)))
  output$cap_plant <- renderUI(rain_caption(layer_plant(), if (input$plant_mode == "before") {
    sprintf("The %d days before the planting date (planting day excluded).", input$x_plant)
  } else {
    sprintf("Planting day and the %d days after it.", input$x_plant - 1)
  }))
  output$cap_season <- renderUI(rain_caption(
    layer_season(), "Planting date to maturity; to the harvest date when the crop doesn't mature."))
  output$cap_presow <- renderUI(rain_caption(
    layer_presow(), "First day of rain data to the day before planting."))

  output$table <- DT::renderDT({
    d <- filtered_data()[, c(
      "zone", "Combination_Rank", "TRNO", "XLAT", "LONG", "Cultivar", "PDAT",
      "HWAH", "CWAM", "in_crop_mask")]
    d$in_crop_mask <- ifelse(d$in_crop_mask, "Yes", "No")
    # server-side processing is controlled by renderDT()'s own `server`
    # argument (defaults to TRUE) - datatable() itself has no such parameter;
    # passing one here throws "unused argument".
    DT::datatable(
      d, rownames = FALSE,
      colnames = c(
        "Zone" = "zone", "Rank" = "Combination_Rank", "Treatment" = "TRNO",
        "Latitude" = "XLAT", "Longitude" = "LONG", "Cultivar" = "Cultivar",
        "Planting date" = "PDAT", "Yield (kg/ha)" = "HWAH", "Biomass (kg/ha)" = "CWAM",
        "In crop mask" = "in_crop_mask"),
      extensions = "Buttons",
      # order: column index 1 (0-based) = Combination_Rank - with more than
      # one rank selected, groups rows by recommendation rank by default
      # rather than leaving them in arbitrary storage order.
      options = list(
        dom = "Blfrtip", buttons = c("csv", "excel"), pageLength = 15,
        order = list(list(1, "asc")))) %>%
      # format*() functions reference columns by their DISPLAYED name (after
      # the colnames= relabeling above), not the original data.frame names -
      # "HWAH"/"XLAT" here would error with "You specified the columns: ...
      # but the column names of the data are ...".
      DT::formatRound(columns = c("Yield (kg/ha)", "Biomass (kg/ha)"), digits = 0) %>%
      DT::formatRound(columns = c("Latitude", "Longitude"), digits = 3)
  })
}

shinyApp(ui, server)
