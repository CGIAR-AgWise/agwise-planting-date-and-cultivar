################################################################################
# ## Create experimental data in DSSAT format (RS-bounded planting windows)
################################################################################
source("~/agwise-fertilizer/Script/generic/DSSAT/dssat_expfile_zone_RS_Dates_fert_factorial.R")

# Settings
country <- "Kenya"
useCaseName <- "KALRO_app2"
Crop <- "Maize"
filex_temp <- "KEAGFERT.MZX"
fert_file <- "fert_fact_KEN.csv"

fertilizer <- FALSE  # All treatments have the same fertilizer 
fert_factorial <- FALSE  # Fertilizer (CSV template) and plant date (RS code) as levels
fert_grid_RS <- TRUE  # Fertilizer (grid) and plant dates (CSV template) as levels 

# NPK grid
NPK_ranges <- list(N = seq(0, 200, 50),
                   P = seq(0, 50, 25),  # Insufficient soil P data provided.
                   K = seq(0, 50, 25))  # Model K module not implemented for Maize


# Run the code. Normally nothing needs to be changed below this line
path.to.temdata <- paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", 
                          country, "_", useCaseName, "/", Crop, 
                          "/Landing/DSSAT/")

template_df <- read_csv(paste0(path.to.temdata, fert_file),
                        show_col_types = FALSE, progress = FALSE)

template_df$split_application <- "No"  # Temporal modification of the template

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

# varieties <- c("999993")  # Set to only one variety for testing
varieties <- unique(template_df$INGENO)

countryShp <- geodata::gadm(country, level = 2, path = ".")
# prov <- unique(countryShp$NAME_1)
prov <- unique(template_df$NAME_1)  # Set to only one province for testing
prov <- c("Kisumu")

path.to.extdata <- paste(
  "/home/jovyan/agwise-fertilizer/Data/useCase_",
  country, "_", useCaseName, "/", Crop, "/transform/DSSAT/AOI/", sep = ""
)
if (!dir.exists(path.to.extdata)) dir.create(path.to.extdata, recursive = TRUE)

log_file <- file.path(path.to.extdata, "progress_log_create_exp_file.txt")
if (file.exists(log_file)) file.remove(log_file)

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
        pathIn_zone = pathIn_zone
        
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
path.to.extdata <- paste("/home/jovyan/agwise-fertilizer/Data/useCase_",
                         country, "_",useCaseName, "/", Crop, "/transform/DSSAT/AOI/", sep="")

log_file <- paste(path.to.extdata, "progress_log_execute.txt", sep='/')

if (file.exists(log_file)) {
  file.remove(log_file)
}

start_time <- Sys.time()
source("~/agwise-fertilizer/Script/generic/DSSAT/dssat_exec.R")

for (j in seq_along(varieties)){
  for (i in seq_along(prov)){
    execmodel_AOI <- dssat.exec(country = country,  useCaseName = useCaseName, 
                                Crop = Crop, AOI = AOI, TRT = 1:40, 
                                varietyid = varieties[j], zone = prov[i])
    
    message <- paste("Province finished:", i, Sys.time())
    cat(message, "\n", file = log_file, append = TRUE)
  }
}
end_time <- Sys.time()
duration <- end_time - start_time
cat(duration, "\n", file = log_file, append = TRUE)
