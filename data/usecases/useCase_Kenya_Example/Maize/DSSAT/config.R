###############################################################################
# Script: config.R
# Purpose: DSSAT template configuration for the Kenya maize example use case.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
###############################################################################

### Load common helper functions
source(file.path(project_root, "main", "DSSAT", "common_helpers.R"))

################
### Settings ###
################
# 1.a. General Settings (edit as necessary)
country <- "Kenya"
useCaseName <- "Example"
Crop <- "Maize"

# 1.b. Paths
filex_temp <- "KEAG8104.MZX"
# Input file (.csv) for fertilizer, planting dates, varieties, ...
temp_file <- "planting_date_rec_template.csv"
# temp_file <- "Fertilizer_recommendation_template_V2.csv"
geneticfiles <- "MZCER048"

path.to.temdata <- create_dssat_temdata_path(
  project_root = project_root, country = country, useCaseName = useCaseName,
  Crop = Crop)

# 1.c. Experimental settings
Soil_source <- "ISRIC"
# Soil_source <- "ISDA"
AOI <- T
Forecast <- T
fertilizer <- F  # All treatments have one fertilizer level defined in the DSSAT template
fert_factorial <- F  # Fertilizer (from CSV template) and plant date (from RS code) as levels
fert_grid_RS <- F  # Fertilizer (from NPK grid) and plant dates (from CSV template) as levels 

season <- 1
pathIn_zone <- T
level2 <- NA
index_soilwat <- 1
ID <- "TLID"

# 1.d. Forecast inputs
country_code <- "KEN"
init_month_user <- 3
season_length_months <- 4
forecast_year <- 2025

# NPK_ranges <- list(N = seq(0, 200, 50),
#                    P = seq(0, 50, 50),  # Insufficient soil P data provided.
#                    K = seq(0, 0, 0),  # Model K module not implemented for Maize
#                    n_split_applications = 2,  # Number of split applications (fertilizer ammount is divided by this number)
#                    F.dap = c(0, 42),    # Number of days after planting the second application is applied
#                    FMCD = "FE006",  # Will use the same for all fertilizers
#                    FACD = "AP004",  # Will use the same for all fertilizers
#                    FDEP = 5,  # Will use the same for all fertilizers
#                    FAMC = -99,  # Will use the same for all fertilizers
#                    FAMO = -99,  # Will use the same for all fertilizers
#                    FOCD = -99)  # Will use the same for all fertilizers


# TODO: make below initialization into a function in the mother script
# 1.e. Read inputs
template_df <- read.csv(paste0(path.to.temdata, temp_file))
provinces <- unique(template_df$NAME_1)
# countryShp <- geodata::gadm(country, level = 2, path = ".")
# provinces <- unique(countryShp$NAME_1)
varietyids <- unique(template_df$INGENO)

# 1.f. Other inputs
# month-day placeholders; real planting dates come from rs_schedule_df below
# TODO: Make this unnecessary
Planting_month_date <- "08-01"; Harvest_month_date <- "06-30"
plantingWindow <- 4  # ignored when rs_schedule_df is provided


# 2. Variable assignment based on inputs
Depth <- if(Soil_source == "ISRIC") c(5, 15, 30, 60, 100, 200) else 
  if(Soil_source == "ISDA") c("0-20cm", "20-50cm")

# Create and load AOI_GPS.RDS file
inputData <- load_or_generate_inputData(
  country = country, useCaseName = useCaseName, Crop = Crop, 
  project_root = project_root, inputData = NULL)

