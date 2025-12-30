################################################################################
### Create experimental data in DSSAT format (RS-bounded planting windows)
################################################################################
# TODO: Check the paths are right inside the scripts.
# TODO: Run this script and all experiments. See if they produce outputs
source("~/agwise-planting-date-and-cultivar/Scripts/generic/DSSAT/dssat_expfile_zone_RS_Dates_fert_factorial.R")

# Settings
country <- "Kenya"
useCaseName <- "KALRO_app2"
Crop <- "Maize"
filex_temp <- "KEAG8104.MZX"
# fert_file <- "fert_fact_KEN.csv"

fertilizer <- FALSE  # All treatments have the same fertilizer 
fert_factorial <- FALSE  # Fertilizer (CSV template) and plant date (RS code) as levels
fert_grid_RS <- FALSE  # Fertilizer (grid) and plant dates (CSV template) as levels 

NPK_ranges <- NULL
# NPK grid
# NPK_ranges <- list(N = seq(0, 200, 50),
#                    P = seq(0, 50, 25),  # Insufficient soil P data provided.
#                    K = seq(0, 50, 25))  # Model K module not implemented for Maize


# Run the code. Normally nothing needs to be changed below this line
path.to.temdata <- paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", 
                          country, "_", useCaseName, "/", Crop, 
                          "/Landing/DSSAT/")

template_df <- NULL
# template_df <- read_csv(paste0(path.to.temdata, fert_file),
#                         show_col_types = FALSE, progress = FALSE)

# template_df$split_application <- "No"  # Temporal modification of the template

AOI <- TRUE
season <- 1
pathIn_zone <- TRUE
level2 <- NA
# month-day placeholders; real planting dates come from rs_schedule_df below
Planting_month_date <- "08-01"; Harvest_month_date <- "06-30"
plantingWindow <- 4  # ignored when rs_schedule_df is provided
ID <- "TLID"
index_soilwat <- 1
geneticfiles <- "MZCER048"

varieties <- c("999993")  # Set to only one variety for testing
# varieties <- unique(template_df$INGENO)

countryShp <- geodata::gadm(country, level = 2, path = ".")
# prov <- unique(countryShp$NAME_1)
# prov <- unique(template_df$NAME_1)  # Set to only one province for testing
prov <- c("Kisumu")

path.to.extdata <- paste(
  "/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_",
  country, "_", useCaseName, "/", Crop, "/transform/DSSAT/AOI/", sep = ""
)
if (!dir.exists(path.to.extdata)) dir.create(path.to.extdata, recursive = TRUE)

log_file <- file.path(path.to.extdata, "progress_log_create_exp_file.txt")
if (file.exists(log_file)) file.remove(log_file)

RS_Date_Range <- read_csv(
  "~/agwise-planting-date-and-cultivar/Data/useCase_Kenya_KALRO_app2/Maize/result/RSPlantingDate/Kenya_KALRO_app2_Maize_Coordinates_SpatialCropModelling_with_RSPlantingDates_Quantiles.csv",
  show_col_types = FALSE
)

# Normalize lon/lat names, fill missing quantiles, convert to Dates, build 4 planting dates
# and add rounded join keys (lon_r, lat_r) for robust matching.
Coordinate_Date_Range <- RS_Date_Range %>%
  {
    nm <- names(.)
    if ("lon" %in% nm)  rename(., longitude = lon) else .
  } %>%
  {
    nm <- names(.)
    if ("lat" %in% nm)  rename(., latitude  = lat) else .
  } %>%
  select(longitude, latitude, q25, q50, q75) %>%
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
  select(longitude, latitude, lon_r, lat_r, planting_dates, startingDate, harvestDate)
rs_schedule_df <- Coordinate_Date_Range


start_time <- Sys.time()

# ------------------------------------------------------------------------------
# --- RUN: per variety x province (dssat.expfile consumes rs_schedule_df) ------
# ------------------------------------------------------------------------------
for (j in seq_along(varieties)) {
  for (i in seq_along(prov)) {
    invisible(
      dssat.expfile(
        country = country, useCaseName = useCaseName, Crop = Crop, AOI = AOI,
        filex_temp = filex_temp,
        # month-day placeholders; real planting dates come from rs_schedule_df below
        Planting_month_date = Planting_month_date,
        Harvest_month_date  = Harvest_month_date,
        ID = ID, season = season,
        plantingWindow = plantingWindow,  # ignored when rs_schedule_df is provided
        varietyid = varieties[j],
        zone = prov[i], level2 = level2, fertilizer = fertilizer,
        fert_factorial = fert_factorial, template_df = template_df,
        fert_grid_RS = fert_grid_RS, NPK_ranges = NPK_ranges,
        geneticfiles = geneticfiles, index_soilwat = index_soilwat,
        pathIn_zone = pathIn_zone, rs_schedule_df = rs_schedule_df
        
      )
    )
    
    # cat(paste(
    #   "Province finished:", i, "/", length(prov), "|",
    #   "name:", prov[i], "| variety:", varieties[j], "| time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    # ),
    # "\n", file = log_file, append = TRUE)
  }
}

end_time <- Sys.time()
duration <- end_time - start_time
cat(duration, "\n", file = log_file, append = TRUE)



################################################################################
# ## Run the DSSAT model
################################################################################
path.to.extdata <- paste("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_",
                         country, "_",useCaseName, "/", Crop, "/transform/DSSAT/AOI/", sep="")

log_file <- paste(path.to.extdata, "progress_log_execute.txt", sep='/')

if (file.exists(log_file)) {
  file.remove(log_file)
}

start_time <- Sys.time()
source("~/agwise-planting-date-and-cultivar/Scripts/generic/DSSAT/dssat_exec.R")

for (j in seq_along(varieties)) {
  for (i in seq_along(prov)) {
    execmodel_AOI <- dssat.exec(country = country,  useCaseName = useCaseName, 
                                Crop = Crop, AOI = AOI, TRT = 1:4, 
                                varietyid = varieties[j], zone = prov[i])
    
    message <- paste("Province finished:", i, Sys.time())
    cat(message, "\n", file = log_file, append = TRUE)
  }
}
end_time <- Sys.time()
duration <- end_time - start_time
cat(duration, "\n", file = log_file, append = TRUE)
