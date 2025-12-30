# Aggregated DSSAT output and ONI classification of aggregated DSSAT output

# Introduction: 
# This script allows : 
# (1) to aggregate/merge DSSAT output
# (2) To classify aggregated outputs from DSSAT simulation in terms of ONI index: Nina, Nino and Neutral year
# It provides also graphics of aggregated DSSAT output according to the ONI
# For more info regarding ONI : https://origin.cpc.ncep.noaa.gov/products/analysis_monitoring/ensostuff/ONI_v5.php
# Authors : P.Moreno, E.Bendito Garcia, L.Leroux
# Credentials : EiA, 2024

#### Getting started #######

# 1. Sourcing required packages -------------------------------------------
packages_required <- c("DSSAT","tidyverse", "ggridges","patchwork", "Rmisc", "terra", "cowplot", "foreach","doParallel","future","future.apply")

installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
   install.packages(packages_required[!installed_packages])
  }

# load required packages
suppressWarnings(suppressPackageStartupMessages(invisible(lapply(packages_required, library, character.only = TRUE))))

# get number of cores and set for parallel computing
num_cores <- parallel::detectCores() - 1
registerDoParallel(num_cores)

options(future.globals.maxSize = 6 * 1024^3)  # Example for 6 GB

# 2. Defining required functions -------------------------------------------

add_TRNO_suffix <- function(n) {
  paste0(
    n,
    ifelse(
      n %% 100 %in% 11:13, "th",
      ifelse(n %% 10 == 1, "st",
             ifelse(n %% 10 == 2, "nd",
                    ifelse(n %% 10 == 3, "rd", "th")))
    )
  )
}


oni_map <- function(data, x, y, fill, HWAH, shp,shp0, limits,varieties_grid=FALSE){
  
  # Mean plot
  if(varieties_grid ==FALSE){
    if (HWAH == TRUE){
      ggplot(data = data) +
        geom_raster(aes(x = {{x}}, y = {{y}}, fill = {{fill}})) +
        facet_grid(rows = vars(ENSO), switch=c('y'))+
        scale_fill_stepsn(n.breaks = 9, colours = viridis::magma(9),limits = limits)+ theme_bw()+
        labs(fill = expression(bold("Yield"~(kg~ha^{-1}))))+
        theme(legend.position = "right",
              axis.text.x =element_text(angle=90, hjust=1, size=16, face='bold'),
              axis.text.y =element_text(size=16, face='bold'),
              axis.title.x = element_text(size = 12, face = "bold"),
              axis.title.y = element_text(size = 12, face = "bold"),
              legend.title = element_text(size = 11, face = "bold"),
              legend.text = element_text(size = 9),
              plot.title = element_text(size = 14, face = "bold"),
              strip.text = element_text(size = 11, face = "bold"),
              strip.background = element_blank(),
              strip.placement = "outside")+
        geom_sf(data=shp, fill=NA, color="white", linewidth=0.5)+
        geom_sf(data=shp0, fill=NA, color="black", linewidth=0.5)+
        coord_sf(expand = FALSE, xlim=c(min(data$Long), max(data$Long)), ylim=c(min(data$Lat), max(data$Lat)))+
        xlab("Longitude")+ ylab("Latitude") + ggtitle(label="Mean") #Mean
      # labs(title = "Rwanda-Wheat ENSO based potential yield predictions")   # Add title
      
    } else {
      ggplot(data = data) +
        geom_raster(aes(x = {{x}}, y = {{y}}, fill = {{fill}})) +
        facet_grid(rows = vars(ENSO), switch=c('y'))+
        scale_fill_stepsn(n.breaks = 6, colours = viridis::magma(9),limits = limits)+ theme_bw()+
        labs(fill = expression(bold("Yield"~(kg~ha^{-1}))))+
        theme(legend.position = "right",
              axis.text.x =element_text(angle=90, hjust=1, size=11, face='bold'),
              axis.text.y =element_text(size=11, face='bold'),
              axis.title.x = element_text(size = 12, face = "bold"),
              axis.title.y = element_text(size = 12, face = "bold"),
              legend.title = element_text(size = 11, face = "bold"),
              legend.text = element_text(size = 9),
              plot.title = element_text(size = 14, face = "bold"),
              strip.text = element_text(size = 11, face = "bold"),
              strip.background = element_blank(),
              strip.placement = "outside")+
        geom_sf(data=shp, fill=NA, color="white", linewidth=0.5)+
        geom_sf(data=shp0, fill=NA, color="black", linewidth=0.5)+
        coord_sf(expand = FALSE, xlim=c(min(data$Long), max(data$Long)), ylim=c(min(data$Lat), max(data$Lat)))+
        xlab("Longitude")+ ylab("Latitude") + ggtitle(label="Standard Deviation")
    }
  }else{
    # Mean plot
    if (HWAH == TRUE){
      ggplot(data = data) +
        geom_raster(aes(x = {{x}}, y = {{y}}, fill = {{fill}})) +
        #facet_grid(cols = vars(Wheather), switch=c('x'), labeller=as_labeller(c(`A`="Niño",`B`="Neutral", `C`="Niña")))+
        facet_grid(Variety~ENSO)+
        scale_fill_gradientn(colours = viridis::viridis(9),limits = limits)+ theme_bw()+
        labs(fill = expression(bold("Yield"~(kg~ha^{-1}))))+
        theme(legend.position = "right",
              axis.text.x =element_text(angle=90, hjust=1, size=11, face='bold'),
              axis.text.y =element_text(size=11, face='bold'),
              axis.title.x = element_text(size = 12, face = "bold"),
              axis.title.y = element_text(size = 12, face = "bold"),
              legend.title = element_text(size = 11, face = "bold"),
              legend.text = element_text(size = 9),
              plot.title = element_text(size = 14, face = "bold"),
              strip.text = element_text(size = 11, face = "bold"),
              strip.background = element_blank(),
              strip.placement = "outside")+
        
        
        
        geom_sf(data=shp, fill=NA, color="white", linewidth=0.5)+
        geom_sf(data=shp0, fill=NA, color="black", linewidth=0.5)+
        coord_sf(expand = FALSE, xlim=c(min(data$Long), max(data$Long)), ylim=c(min(data$Lat), max(data$Lat)))+
        xlab("Longitude")+ ylab("Latitude") + ggtitle(label="Mean") #Mean
    } else {
      ggplot(data = data) +
        geom_raster(aes(x = {{x}}, y = {{y}}, fill = {{fill}})) +
        #facet_grid(cols = vars(Wheather), switch=c('x'), labeller=as_labeller(c(`A`="Niño",`B`="Neutral", `C`="Niña")))+
        facet_grid(Variety~ENSO)+
        scale_fill_gradientn(colours = viridis::magma(9), limits = limits)+ theme_bw()+
        labs(fill = expression(bold("Yield"~(kg~ha^{-1}))))+
        theme(legend.position = "right",
              axis.text.x =element_text(angle=90, hjust=1, size=11, face='bold'),
              axis.text.y =element_text(size=11, face='bold'),
              axis.title.x = element_text(size = 12, face = "bold"),
              axis.title.y = element_text(size = 12, face = "bold"),
              legend.title = element_text(size = 11, face = "bold"),
              legend.text = element_text(size = 9),
              plot.title = element_text(size = 14, face = "bold"),
              strip.text = element_text(size = 11, face = "bold"),
              strip.background = element_blank(),
              strip.placement = "outside")+
        
        
        geom_sf(data=shp, fill=NA, color="white", linewidth=0.5)+
        geom_sf(data=shp0, fill=NA, color="black", linewidth=0.5)+
        coord_sf(expand = FALSE, xlim=c(min(data$Long), max(data$Long)), ylim=c(min(data$Lat), max(data$Lat)))+
        xlab("Longitude")+ ylab("Latitude") + ggtitle(label="Standard Deviation") 
    }
  }
  
}


### Create a function to determine the category
get_oni_category <- function(anom_values) {
  anom_values <- round(anom_values,1)
  n <- length(anom_values)
  categories <- rep("Neutral", n)
  
  i <- 1
  while (i <= n) {
    if (anom_values[i] <= -0.5) {
      count <- 0
      j <- i
      while (j <= n && anom_values[j] <= -0.5) {
        count <- count + 1
        j <- j + 1
      }
      if (count >= 5) {
        categories[i:(i+count-1)] <- "Niña"
        i <- i + count
      } else {
        i <- i + 1
      }
    } else if (anom_values[i] >= 0.5) {
      count <- 0
      j <- i
      while (j <= n && anom_values[j] >= 0.5) {
        count <- count + 1
        j <- j + 1
      }
      if (count >= 5) {
        categories[i:(i+count-1)] <- "Niño"
        i <- i + count
      } else {
        i <- i + 1
      }
    } else {
      i <- i + 1
    }
  }
  return(categories)
}

#### Compute the mode from caterogical ONI over the cropping season 

calculate_mode <- function(x) {
  unique_x <- unique(x)
  tab <- tabulate(match(x, unique_x))
  mode_value <- unique_x[which.max(tab)]
  return(mode_value)
}
# 3. Aggregated DSSAT output  -------------------------------------------
#(To check if function from L. Leroux is more efficient)
#' @param country country name
#' @param useCaseName use case name  name
#' @param Crop the name of the crop to be used in creating file name to write out the result.
#' @param AOI True if the data is required for target area, and false if it is for trial sites
#' @param season when data is needed for more than one season, this needs to be provided to be used in the file name
#' @param varietyids ids of the varieties based on the cultivar file of DSSAT (column @VAR# in the cultivar file and parameter INGENO in the experimental file *.**X)
#' @param zone_folder When TRUE the output folders are organized by administrative level 1.
#' @param level2_foler When TRUE the output folders are organized by administrative level 2 (has to be part of the administrative level 1 or "zone" of the country) 
#'        for the specific location the experimental file is created
#'        
#' @return merged results from DSSAT in RDS format
#'
#' @examples merge_DSSAT_output(country="Rwanda", useCaseName="RAB",Crop="Maize",varietyids=c("890011","890012"), zone_folder=T, level2_folder=F)

source("~/agwise-fertilizer/Script/generic/DSSAT/merge_DSSAT_output.R")

# 4. Get ONI Index  -------------------------------------------

  #' @description Function that will classify each DSSAT simulation based on ONI index
  #' @param country country name
  #' @param useCaseName use case name
  #' @param Crop targeted crop
  #' @param AOI TRUE if the data is required for target area, and FALSE if it is for trial sites, default =TRUE
  #' @param season integer, cropping season concerned, default = 1 
  #' @param Plot, provide somes plots of the output, default = TRUE
  #' @param short_variety variety ID with short growing period duration
  #' @param medium_variety variety ID with medium growing period duration 
  #' @param long_variety variety ID with long growing period duration
  #'
  #' @return A table with the aggregated DSSAT simulation classified based on ONI index - Output table is written out in "~/agwise-fertilizer/Data/useCaseName/Crop/result/DSSAT/Extent/useCase_country_useCaseName_crop_Extent_season_X_ONI.RDS")
  #'
  #' @examples get_ONI(country= "Kenya", useCaseName = "KALRO", Crop="Maize", AOI=T, season=1, Plot=TRUE, short_variety="900111", medium_variety="900112",long_variety="900113")
  #' 

get_ONI <- function(country, useCaseName, Crop, AOI=TRUE, season, Plot=TRUE, short_variety, medium_variety, long_variety,justplot=FALSE){

  ## 4.1. Creating a directory to store output table and graphics ####
  if (AOI == TRUE){
    pathOut <- paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName,"/",Crop,"/result/DSSAT/AOI/", sep="")
  } else {
    pathOut <- paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName,"/",Crop,"/result/DSSAT/fieldData/",  sep="")
  }
  
  if (justplot == FALSE) {
    if (!dir.exists(pathOut)){
      dir.create(file.path(pathOut), recursive = TRUE)
    }
    
    ## 4.2. Read the input data ####
    ### 4.2.1. Get the ONI data ####
    # Check if the ONI table is already available
    
    url <- "https://www.cpc.ncep.noaa.gov/data/indices/oni.ascii.txt"
    destfile <- "/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/ONI/"
    file_name <- "oni.txt"
    
    # Download it if doesn't exist
    if (!file.exists(paste(destfile, file_name, sep = ""))){
      download.file(url, paste(destfile, file_name, sep = ""), mode="wb")
    } else {
      # Update the ONI version with the last version
      unlink("/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/ONI/oni.txt")
      download.file(url, paste(destfile, file_name, sep = ""), mode="wb")
    }
    
    # Open the ONI data
    oni <- read_table(paste0(destfile,file_name))
    
    # Reshape the ONI data
    month_mapping <- c(
      'DJF'= 'January',
      'JFM'= 'February',
      'FMA'= 'March',
      'MAM'= 'April',
      'AMJ'= 'May',
      'MJJ'= 'June',
      'JJA'= 'July',
      'JAS'= 'August',
      'ASO'= 'September',
      'SON'= 'October',
      'OND'= 'November',
      'NDJ'= 'December'
    )
    oni$month <- month_mapping[oni$SEAS]
    oni$date <- as.Date(paste0(oni$YR, "-", oni$month, "-01"), format="%Y-%B-%d")
    oni$year <-year(oni$date)
    oni$num_month <-month(oni$date)
    
    oni <- oni %>% arrange(year, num_month)
    
    # Apply the function to the oni data frame
    oni <- oni %>%
      mutate(oni_category = get_oni_category(ANOM))
    
    # Print the data frame to check the result
    path_to_save = "/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/ONI/"
    write.table(oni, paste0(path_to_save,"oni_categorical.txt"), row.names = FALSE)
    
    ### 4.2.2. Get the aggregated DSSAT output and reshape the data ####
    # Open the aggregated DSSAT output
    if(AOI ==TRUE){
      dssat_path <- paste0(pathOut,"useCase_", country, "_" ,useCaseName,"_",Crop,"_AOI_season_",season,".RDS", sep="")
    }else{
      dssat_path <- paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,".RDS", sep="")
    }
    
    # Check if the object all_results with newly aggregated data is still in memory to be put into the path if not read the saved object        
    #ifelse(file.exists(dssat_path)==FALSE, dssat <- all_results, dssat <- readRDS(dssat_path))
    dssat <- readRDS(dssat_path)
    if(Crop %in% c('Cassava','Potato')) {
      dssat <- dssat %>%
        mutate(final_date = HDAT)
    }else{
      dssat <- dssat %>%
        mutate(final_date = as.Date(ifelse(!is.na(MDAT), as.character(MDAT), as.character(HDAT))))
    }
    ## 4.3. Get the mode ONI over the cropping season for aggregated DSSAT output ####
    # Ranges of date of analysis
    date_ranges <- data.frame (
      initial_date = dssat$PDAT, # Planting Date
      final_date = dssat$final_date    # Harvesting Date
    )
    
    date_ranges <- unique(date_ranges)
    
    # medoni <- foreach::foreach(i=1:nrow(date_ranges)) %dopar% {
    #   filtered_data <- oni %>%
    #     filter(date >= as.Date(date_ranges$initial_date[i]) & date<= as.Date(date_ranges$final_date[i]))
    #   vars <- filtered_data$oni_category
    #   if(i%%10000==0){
    #     print(i)}
    #   calculate_mode(vars)}
    # medoni <- do.call(rbind, medoni)
    num_cores <- availableCores() -3
    plan(multisession, workers = num_cores)
    
    # Use future_lapply for parallel processing
    medoni <- future_lapply(1:nrow(date_ranges), function(i) {
      filtered_data <- oni %>%
        filter(date >= as.Date(date_ranges$initial_date[i]) & date <= as.Date(date_ranges$final_date[i]))
      vars <- filtered_data$oni_category
      if(i %% 10000 == 0) {
        print(i)
      }
      calculate_mode(vars)
    })
    medoni <- do.call(rbind, medoni)
    
    # Convert medoni to a dataframe with a specific column name
    medoni_df <- tibble(mode_variable = medoni)
    
    date_ranges_oni <- bind_cols(date_ranges,medoni_df)
    
    # Merge with DSSAT output
    dssat_oni <- merge(dssat, date_ranges_oni, by.x = c('PDAT', 'final_date'), by.y = c('initial_date', 'final_date'))
    rm(dssat)
    
    
    #colnames(dssat_oni) <- c(colnames(dssat_oni)[-27],'med_variable')
    
    ## 4.4. Classify tbe ONI into three classes (now using the categorical classification directly) ####
    # med ONI > 0.5, Nino, med ONI < -0.5 Nina, -0.5 > ONI > 0.5 Neutral 
    # 
    #   dssat_oni$ENSO <- ifelse(dssat_oni$med_variable > 0.5,"Niño",
    #                              ifelse(dssat_oni$med_variable< -0.5,"Niña", "Neutral"))
    
    dssat_oni$ENSO  <- dssat_oni$mode_variable
    
    
    dssat_oni <- dssat_oni %>%
      mutate(year = year(PDAT),
             num_month = month(PDAT))
    
    # Replace ENSO na values with the oni_category at planting
    dssat_oni <- dssat_oni %>%
      left_join(oni %>% select(year, num_month, oni_category), by = c("year", "num_month")) %>%
      mutate(ENSO = ifelse(is.na(ENSO), oni_category, ENSO)) %>%
      select(-year, -num_month, -oni_category)  
    
    
    
    #Change the name of the varieties by their growing duration
    # Apply conditional transformation using case_when
    dssat_oni <- dssat_oni %>%
      mutate(Variety = case_when(
        Variety ==short_variety ~ "Short",
        Variety ==medium_variety ~ "Medium",
        Variety ==long_variety ~ "Long"
      ))
    
    dssat_oni$TNAM <- reorder(dssat_oni$TNAM, dssat_oni$TRNO)											   
    
    dssat_oni <- dssat_oni %>% 
      mutate(RS_PDAT = paste(add_TRNO_suffix(TRNO), "Sow Date"))
    
    # Save the aggregated DSSAT output with ONI information
    if(AOI ==TRUE){
      saveRDS(dssat_oni,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_ONI.RDS" ))
    }else{
      saveRDS(dssat_oni,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_ONI.RDS" ))
    }
  }else{
    if(AOI ==TRUE){
      dssat_oni <- readRDS(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_ONI.RDS" ))
    }else{
      dssat_oni <- readRDS(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_ONI.RDS" ))
    }
  }
 
  
  ## 4.5. Basic plots ####
  if (Plot == TRUE){
    ### 4.5.1. Global plot ####
    #dssat_oni <- na.omit(dssat_oni)
    # Define a manual scale
    val <- c("Neutral" = "gold",
             "Niño" = "tomato1",
             "Niña" = "royalblue2")
    
    dssat_oni <- dssat_oni %>%mutate(doy = yday(PDAT))
    dssat_oni <- dssat_oni %>% mutate(date = ymd("2023-01-01") + days(doy - 1)) 
    dssat_oni$Planting_date <- format(dssat_oni$date, "%d-%b")
    dssat_oni$Planting_date <- factor(dssat_oni$Planting_date, 
                                      levels = unique(dssat_oni$Planting_date[order(dssat_oni$TRNO)]))
    
						 
  # Meand and SEM plot
  pd <- position_dodge(0.2)
  dssat_oni %>%
    # summarySE(measurevar="HWAH", groupvars=c("Planting_date", "ENSO"))%>%
    summarySE(measurevar="HWAH", groupvars=c("RS_PDAT", "ENSO"))%>%
    # ggplot(aes(x = Planting_data, 
    ggplot(aes(x = RS_PDAT, 
             y = HWAH, 
             group=ENSO, 
             color=ENSO)) +
    geom_point(position = pd, size = 3) +
    geom_line(position = pd,linewidth = 1) +
    #geom_errorbar(aes(ymin = HWAH - sd, ymax = HWAH + sd), width = .1, position= pd)+
    theme_bw()+
    scale_color_manual(values=val)+ theme(axis.text.x =element_text(angle=45, hjust=1))+
    ylab(expression(bold('Yield'~(kg~ha^{-1})))) + xlab(expression(bold("Planting time")))
  if(AOI==TRUE){
    ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_ONI_DotPlot_Global.pdf"),dpi=300, width = 8, height=7, units=c("in"))
  }else{
    ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_ONI_DotPlot_Global.pdf"),dpi=300, width = 8, height=7, units=c("in"))
  }
  

  # Heat map
  p1 <- dssat_oni %>%
    # summarySE(measurevar="HWAH", groupvars=c("Variety","Planting_date", "ENSO"))%>%
    summarySE(measurevar="HWAH", groupvars=c("Variety","RS_PDAT", "ENSO"))%>%
    ggplot(aes(x=RS_PDAT, y=ENSO, fill=HWAH))+
    # ggplot(aes(x=Planting_date, y=ENSO, fill=HWAH))+
    geom_tile(color="white", linewidth=0.1)+ 
    labs(fill = expression(bold("Yield"~(kg~ha^{-1}))))+
    theme_bw()+
    scale_fill_viridis_c()+
    theme(axis.text.x =element_text(angle=90, hjust=1, size=11),
          axis.text.y =element_text(size=11),
          legend.title = element_text(size = 11, face = "bold"),
          legend.text = element_text(size = 9),
          plot.title = element_text(size = 14, face = "bold"))+
    coord_equal()+
    ylab(expression(bold("ENSO")))+xlab(expression(bold("Planting time")))+
    ggtitle("Mean yield")
  
  p2 <-  dssat_oni %>%
    # summarySE(measurevar="HWAH", groupvars=c("Variety","Planting_date", "ENSO"))%>%
    summarySE(measurevar="HWAH", groupvars=c("Variety","RS_PDAT", "ENSO"))%>%
    ggplot(aes(x=RS_PDAT, y=ENSO, fill=sd))+
    # ggplot(aes(x=Planting_date, y=ENSO, fill=sd))+
    geom_tile(color="white", linewidth=0.1)+
    labs(fill = expression(bold("Yield"~(kg~ha^{-1}))))+
    theme_bw()+
    scale_fill_viridis_c()+
    theme(axis.text.x =element_text(angle=90, hjust=1, size=11),
          axis.text.y =element_text(size=11),
          legend.title = element_text(size = 11, face = "bold"),
          legend.text = element_text(size = 9),
          plot.title = element_text(size = 14, face = "bold"))+
    coord_equal()+
    ylab(expression(bold("ENSO")))+xlab(expression(bold("Planting time")))+
    ggtitle("Standard Deviation")
  
 p1+p2+plot_layout(ncol = 1) 
 
 if(AOI==TRUE){
   ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_ONI_HeatMap_Global.pdf"),dpi=300, width = 8, height=7, units=c("in"))
 }else{
   ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_ONI_HeatMap_Global.pdf"),dpi=300, width = 8, height=7, units=c("in"))
 }
 
 
 ### 4.5.2. Plot by variety ####
 # Mean and SEM plot
 pd <- position_dodge(0.2)
 dssat_oni %>%
   summarySE(measurevar="HWAH", groupvars=c("Variety","RS_PDAT", "ENSO"))%>%
   # summarySE(measurevar="HWAH", groupvars=c("Variety","Planting_date", "ENSO"))%>%
   # ggplot(aes(x = Planting_date, 
   ggplot(aes(x = RS_PDAT, 
              y = HWAH, 
              group=ENSO, 
              color=ENSO)) +
   facet_grid(cols = vars(Variety))+
   geom_point(position = pd, size = 3) +
   geom_line(position = pd,linewidth = 1) +
   #geom_errorbar(aes(ymin = HWAH - sd, ymax = HWAH + sd), width = .1, position= pd)+
   theme_bw()+
   scale_color_manual(values=val)+ 
   theme(axis.text.x =element_text(angle=90, hjust=1),
         legend.title = element_text(size = 11, face = "bold"),
         strip.text = element_text(size = 14, face = "bold"),
         strip.background = element_blank())+
   ylab(expression(bold('Yield'~(kg~ha^{-1})))) + xlab(expression(bold("Planting time")))

 if(AOI==TRUE){
   ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_ONI_DotPlot_Variety.pdf"),dpi=300, width = 8, height=7, units=c("in"))
 }else{
   ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_ONI_DotPlot_Variety.pdf"),dpi=300, width = 8, height=7, units=c("in"))
 }
 
 
 # Heat map
 p1 <- dssat_oni %>%
   # summarySE(measurevar="HWAH", groupvars=c("Variety","Planting_date", "ENSO"))%>%
   summarySE(measurevar="HWAH", groupvars=c("Variety","RS_PDAT", "ENSO"))%>%
   ggplot(aes(x=RS_PDAT, y=ENSO, fill=HWAH))+
   # ggplot(aes(x=Planting_date, y=ENSO, fill=HWAH))+
   facet_grid(rows = vars(Variety))+
   geom_tile(color="white", linewidth=0.1)+
   labs(fill = expression(bold("Yield"~(kg~ha^{-1}))))+
   theme_bw()+
   theme(axis.text.x =element_text(angle=90, hjust=1),
         legend.title = element_text(size = 11, face = "bold"),
         legend.text = element_text(size = 9),
         plot.title = element_text(size = 14, face = "bold",margin = margin(b = -90)))+
   scale_fill_viridis_c()+
   coord_equal()+
   ylab(expression(bold("ENSO")))+xlab(expression(bold("Planting time")))+
   ggtitle("Mean yield")
 
 p2 <-  dssat_oni %>%
   # summarySE(measurevar="HWAH", groupvars=c("Variety","Planting_date", "ENSO"))%>%
   summarySE(measurevar="HWAH", groupvars=c("Variety","RS_PDAT", "ENSO"))%>%
   # ggplot(aes(x=Planting_date, y=ENSO, fill=sd))+
   ggplot(aes(x=RS_PDAT, y=ENSO, fill=sd))+
   facet_grid(rows = vars(Variety))+
   geom_tile(color="white", linewidth=0.1)+
   labs(fill = expression(bold("Yield"~(kg~ha^{-1}))))+
   theme_bw()+
   theme(axis.text.x =element_text(angle=90, hjust=1),
         legend.title = element_text(size = 11, face = "bold"),
         legend.text = element_text(size = 9),
         plot.title = element_text(size = 14, face = "bold",margin = margin(b = -90)))+
   scale_fill_viridis_c()+
   coord_equal()+
   ylab(expression(bold("ENSO")))+xlab(expression(bold("Planting time")))+
   ggtitle("Standard Deviation")
 p1+p2+plot_layout(ncol = 2) 
 
 if(AOI==TRUE){
   ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_ONI_HeatMap_Variety.pdf"),dpi=300, width = 12, height=6, units=c("in"))
 }else{
   ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_ONI_HeatMap_Variety.pdf"),dpi=300, width = 12, height=6, units=c("in"))
 }
 
 ## 4.6. Maps ####
 
 # Read the relevant shape file from gdam to be used to crop the global data
 countryShp <- geodata::gadm(country, level = 1, path=paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName,"/",Crop,"/result/DSSAT/", sep=""))
 country_sf <- sf::st_as_sf(countryShp)
 
 countryShp0 <- geodata::gadm(country, level = 0, path=paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName,"/",Crop,"/result/DSSAT/", sep=""))
 country_sf0 <- sf::st_as_sf(countryShp0)
							 
#TODO: THIS PART BELOW NEEDS FIXING
 ### 4.6.1. Global Map ####
 #Organized by ENSO
 dssat_oni.g <- dssat_oni %>%
   Rmisc::summarySE(measurevar="HWAH", groupvars=c("Lat","Long", "ENSO"))
 
 # Scale limits
 min.mean <- min(dssat_oni.g$HWAH)
 max.mean <- max(dssat_oni.g$HWAH)
 
 min.sd <- min(dssat_oni.g$sd)
 max.sd <- max(dssat_oni.g$sd)
 dssat_oni.g$ENSO <- factor(dssat_oni.g$ENSO,levels =c("Niño","Neutral","Niña"))

 #Organized by ENSO and cultivars
 dssat_oni.gc <- dssat_oni %>%
   Rmisc::summarySE(measurevar="HWAH", groupvars=c("Lat","Long", "ENSO","Variety"))
 
 # Scale limits
 min.meanc <- min(dssat_oni.gc$HWAH)
 max.meanc <- max(dssat_oni.gc$HWAH)
 
 min.sdc <- min(dssat_oni.gc$sd)
 max.sdc <- max(dssat_oni.gc$sd)
 dssat_oni.gc$ENSO <- factor(dssat_oni.gc$ENSO,levels =c("Niño","Neutral","Niña"))

 
 mean.g <- oni_map(data = dssat_oni.g, x = Long, y = Lat, shp = country_sf,
                   shp0 = country_sf0, fill = HWAH, HWAH = TRUE, 
                   limits = c(min.mean, max.mean), varieties_grid = FALSE)
 sd.g <- oni_map(data= dssat_oni.g, x=Long, y=Lat,shp=country_sf,shp0=country_sf0, fill=sd, HWAH= FALSE, limits=c(min.sd, max.sd),varieties_grid=FALSE)
 
 ass <- plot_grid(mean.g, sd.g)
 ass
 

  if(AOI==TRUE){
    ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_ONI_Maps_Global.pdf"), dpi=300, width = 8, height=6.89, units=c("in"))
  }else{
    ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_ONI_Maps_Global.pdf"), dpi=300, width = 8, height=6.89, units=c("in"))
  }
  
  #Map including variety and ENSO
  mean.gc <-oni_map(data=dssat_oni.gc, x=Long, y=Lat,shp=country_sf, shp0=country_sf0, fill=HWAH, HWAH= TRUE,limits=c(min.meanc, max.meanc),varieties_grid=TRUE)
  mean.gc
  if(AOI==TRUE){
    ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_ONI_Maps_Global_mean.pdf"), dpi=300, width = 8, height=8, units=c("in"))
  }else{
    ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_ONI_Maps_Global_mean.pdf"), dpi=300, width = 8, height=8, units=c("in"))
  }
  
  sd.gc <-oni_map(data=dssat_oni.gc, x=Long, y=Lat,shp=country_sf,shp0=country_sf0, fill=sd, HWAH= FALSE, limits=c(min.sdc, max.sdc),varieties_grid=TRUE)
  sd.gc
  if(AOI==TRUE){
    ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_ONI_Maps_Global_sd.pdf"), dpi=300, width = 8, height=8, units=c("in"))
  }else{
    ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_ONI_Maps_Global_sd.pdf"), dpi=300, width = 8, height=8, units=c("in"))
  }
  
  ##################################################
  ### Find optimum planting dates and plot them ####
  ##################################################
  
  dssat_oni$year<-year(dssat_oni$PDAT)
  dssat_oni$date<-dssat_oni$PDAT
  dssat_oni$doy<-strftime(dssat_oni$PDAT,format="%j")
  dssat_oni$ydoy<-strftime(dssat_oni$PDAT,format="%y%j")
  dssat_oni<-as.data.frame(dssat_oni)
  
  gps <- readRDS(paste0("~/agwise-datacuration/dataops/datacuration/Data/useCase_", country, "_",useCaseName,"/", Crop, "/result/AOI_GPS.RDS"))
  
  
  pyd <- merge(gps, dssat_oni,by.x=c("lon","lat"), by.y=c("Long","Lat"))
  
  pyd$ONI<-pyd$mode_variable
  pyd$NAME_0<-pyd$country
  pyd$yield <-pyd$HWAH
  pyd$prov <-pyd$Loc
  
  pyd_select<-pyd[,c("NAME_0", "NAME_1","NAME_2","lon","lat","TRNO","TNAM","PDAT",
                     "yield","Variety","prov","ONI","ENSO","year","date","doy",
                     "ydoy")]
  
  
  summary_pyd<-pyd_select %>%
    dplyr::group_by(lon,lat,Variety,ENSO,TRNO,TNAM,doy) %>%
    dplyr::summarize(median = median(yield, na.rm = TRUE))
  
  
  
  #get only top 5 optimum dates per ENSO, variety, and location
  max_median_summary_poptions <- summary_pyd %>%  
    group_by(lon,lat,Variety,ENSO) %>% 
    slice_max(median,n=5) %>%
    select(TRNO,TNAM,median, doy) %>%
    arrange(ENSO,Variety, desc(median))%>%
    filter(as.logical(!is.na(ENSO)))
  
  # Save the top optimum 5 planting dates per ENSO per variety per location
  if(AOI ==TRUE){
    saveRDS(max_median_summary_poptions,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_optimum_planting_per_variety.RDS" ))
  }else{
    saveRDS(max_median_summary_poptions,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_optimum_planting_per_variety.RDS" ))
  }
  #get only one optimum date
  max_median_summary <- summary_pyd %>%  
    group_by(lon,lat,Variety,ENSO) %>% 
    slice_max(median) %>%
    select(TRNO,TNAM,median, doy) %>%
    arrange(desc(median))%>%
    filter(as.logical(!is.na(ENSO)))
  
  # Save the top optimum planting date per ENSO per variety per location
  if(AOI ==TRUE){
    saveRDS(max_median_summary,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_optimum_planting.RDS" ))
  }else{
    saveRDS(max_median_summary,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_optimum_planting.RDS" ))
  }
  
  year <- 2023
  max_median_summary$doyy <- as.Date(as.numeric(as.character(max_median_summary$doy))-1, origin = paste0(year, "-01-01"))
  max_median_summary$Opt_date <- format(max_median_summary$doyy, "%d-%b")
  
  max_median_summary$TRNO <-factor(max_median_summary$TRNO)
  
  # This produced a disordered legend
  # max_median_summary$Opt_date <- factor(max_median_summary$Opt_date, 
  #                                       levels = unique(max_median_summary$Opt_date[order(max_median_summary$TRNO)]))
  max_median_summary$Opt_date <- factor(
    max_median_summary$Opt_date,
    levels = unique(max_median_summary$Opt_date[order(max_median_summary$doyy)])
  )
  
  max_median_summary$ENSO <- factor(max_median_summary$ENSO,levels =c("Niño","Neutral","Niña"))
  max_median_summary <- na.omit(max_median_summary)
  d<-max_median_summary %>%
    ggplot() +
    geom_raster(aes(x = lon, y = lat, fill = Opt_date)) +
    labs(fill ="Opt. Date")+
    scale_fill_viridis_d()+
    facet_grid(Variety~ENSO)+
    theme_bw()+
    theme(legend.position = "right", aspect.ratio = 1, 
          axis.text.x = element_text(angle = 90, hjust = 1,size = 16, face ="bold"),
          axis.text.y = element_text(size = 16, face ="bold"),
          axis.title = element_text(size = 16, face = "bold"),
          strip.text = element_text(size = 16, face = "bold"),
          strip.background = element_blank(),
          legend.text = element_text(size = 16),
          legend.title = element_text(size = 16, face = "bold"),
          plot.title = element_text(hjust = 0.5, size = 14, face = "bold"))+ 
    geom_sf(data=country_sf, fill=NA, color="white", linewidth=0.5)+
    geom_sf(data=country_sf0, fill=NA, color="black", linewidth=0.5)+
    coord_sf(xlim=c(min(max_median_summary$lon), max(max_median_summary$lon)), 
             ylim=c(min(max_median_summary$lat), max(max_median_summary$lat)))+
    xlab("Longitude")+ ylab("Latitude")
  #d
  if(AOI ==TRUE){
    ggsave(plot=d,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_OptPlanting_ONI.png"), width = 12, height = 12)
    ggsave(plot=d,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_AOI_season_",season,"_OptPlanting_ONI.pdf"), width = 12, height = 12)
    }else{
    ggsave(plot=d,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_OptPlanting_ONI.png" ), width = 12, height = 12)
    ggsave(plot=d,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_fieldData_season_",season,"_OptPlanting_ONI.pdf" ), width = 12, height = 12)
    }

 
  }
}

# country="Kenya"
# useCaseName="KALRO"
# Crop = "Maize"
# Extent = "AOI"
# season = 1
# Plot = TRUE
# 
# 
# get_ONI(country, useCaseName, Crop, Extent, season, Plot)
# merge_DSSAT_output(country, useCaseName, Crop, Extent, season)
  # Meand and SEM plot

 

