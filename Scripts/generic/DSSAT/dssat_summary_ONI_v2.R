# Aggregated DSSAT output and ONI classification of aggregated DSSAT output

# Introduction: 
# This script allows : 
# (1) to aggregate/merge DSSAT output
# (2) the classification of aggregated ouput from DSSAT simulation in terms of ONI type : Nina, Nino and Neutral year
# It provides also graphical ouputs of aggregated DSSAT output according to the ONI
# For more info regarding ONI : https://origin.cpc.ncep.noaa.gov/products/analysis_monitoring/ensostuff/ONI_v5.php
# Authors : P.Moreno, E.Bendito Garcia, L.Leroux
# Credentials : EiA, 2024

#### Getting started #######

# 1. Sourcing required packages -------------------------------------------
packages_required <- c("DSSAT","tidyverse","dplyr", "purrr", "ggridges","patchwork", "Rmisc", "terra", "cowplot")

installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
  if(packages_required[!installed_packages] =="DSSAT"){
    remotes::install_github("palderman/DSSAT", ref = "develop",force=T)
  } else {
    install.packages(packages_required[!installed_packages])
  }
}

lapply(packages_required, library, character.only = TRUE)

# load required packages
suppressWarnings(suppressPackageStartupMessages(invisible(lapply(packages_required, library, character.only = TRUE))))

# 2. Defining required functions -------------------------------------------
get_median_variable <- function(initial_date, final_date, variable, data) {
  filtered_data <- data %>%
    filter(date >= as.Date(initial_date) & date <= as.Date(final_date))
  
  med_variable <- median(filtered_data[[variable]], na.rm = TRUE)
  
  return(data.frame(initial_date = initial_date, final_date = final_date, med_variable = med_variable))
}

oni_map <- function(data, x,y, fill, HWAH, shp, limits){
  
  # Mean plot
  if (HWAH == TRUE){
    ggplot(data = data) +
      geom_raster(aes(x = {{x}}, y = {{y}}, fill = {{fill}})) +
      facet_grid(rows = vars(Wheather), switch=c('y'), labeller=as_labeller(c(`A`="Niño",`B`="Neutral", `C`="Niña")))+
      scale_fill_stepsn(n.breaks = 9, colours = viridis::viridis(9),name=" Yield"~(kg~ha^{-1}), limits = limits)+ theme_bw()+
      theme(legend.position = "right")+ 
      geom_sf(data=shp, fill=NA, color="white", linewidth=0.5)+
      coord_sf(expand = FALSE, xlim=c(min(data$Long), max(data$Long)), ylim=c(min(data$Lat), max(data$Lat)))+
      xlab("Longitude")+ ylab("Latitude") + ggtitle(label="Mean")
  } else {
    ggplot(data = data) +
      geom_raster(aes(x = {{x}}, y = {{y}}, fill = {{fill}})) +
      facet_grid(rows = vars(Wheather), switch=c('y'), labeller=as_labeller(c(`A`="Niño",`B`="Neutral", `C`="Niña")))+
      scale_fill_stepsn(n.breaks = 9, colours = viridis::magma(9),name=" Yield"~(kg~ha^{-1}), limits = limits)+ theme_bw()+
      theme(legend.position = "right")+ 
      geom_sf(data=shp, fill=NA, color="white", linewidth=0.5)+
      coord_sf(expand = FALSE, xlim=c(min(data$Long), max(data$Long)), ylim=c(min(data$Lat), max(data$Lat)))+
      xlab("Longitude")+ ylab("Latitude") + ggtitle(label="Standard Deviation")
  }
}

# 3. Aggregated DSSAT output  -------------------------------------------
merge_DSSAT_output <- function(country, useCaseName, Crop, Extent, Season){
  
  #' @description Function that will aggregate all the DSSAT output in one file
  #' @param country country name
  #' @param useCaseName use case name
  #' @param Crop targeted crop
  #' @param Extent spatial extent of the simulation, default = AOI
  #' @param Season integer, cropping season concerned, default = 1
  #' 
  #' @return A table with the aggregated DSSAT simulation  - Output table is written out in "~/agwise-fertilizer/Data/useCaseName/Crop/result/DSSAT/Extent/useCase_country_useCaseName_crop_Extent_season_X.RDS")
  #'
  #' @examples merge_DSSAT_output (country= "Kenya", useCaseName = "KALRO", Crop="Maize", Extent="AOI", Season=1)
  #' 
  #'
  ## 3.1. Creating a directory to store output table and graphics ####
  if (Extent == 'AOI'){
    pathOut <- paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName,"/",Crop,"/result/DSSAT/",Extent,"/", sep="")
  } else {
    pathOut <- paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName,"/",Crop,"/result/DSSAT/", sep="")
  }
  
  
  if (!dir.exists(pathOut)){
    dir.create(file.path(pathOut), recursive = TRUE)
  }
  
  ## 3.2. Define the working directory for the input data ####
  if (Extent=='AOI'){
    if(is.null(Season)){
      print("with AOI=TRUE, season can not be null, please refer to the documentation and provide season number")
      return(NULL)
    }
    path.to.extdata <- paste("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName, "/", Crop, "/transform/DSSAT/AOI",sep="")
    
  }else{
    path.to.extdata <- paste("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName, "/", Crop, "/transform/DSSAT", sep="")
  }
  setwd(path.to.extdata)
  
  ## 3.3. Read and aggregate the input data ####
  ## List all the files (exte and weather) in the working directory
  
  # Exte files
  list.exte <- list.files(recursive = TRUE, full.names = TRUE, pattern=glob2rx("*EXTE*OUT*"))
  # Weather files
  list.wh <- list.files(recursive = TRUE, full.names = TRUE, pattern=glob2rx("*WHTE*WTH*"))
  
  # Check if the length of list.exte and list.wh is the same (should be the same), if not (case crop failure), filter the lists accordingly
  ## Case list.exte shorter than list.wh ##
  if (length(list.exte) < length(list.wh)){
    
    # Create the list of WTH files that corresponds to the OUT files
    list.exte.gsub <- gsub(".OUT",".WTH", list.exte) # replace the extension
    list.wh.sub <- sub("(\\EXTE.*?)\\EXTE", "\\1WHTE", list.exte.gsub) # replace the seconde EXTE of the file name by WHTE
    list.wh <- list.wh.sub
  }
  
  ## Loop on all the files to aggregate the .OUT files
  f_all <- NULL
  
  for (i in 1:length(list.exte)){
    # Read the exte file
    base <- list.exte[i]
    base.r <- read_output(base)
    # Keep the usefull information
    base.sub <- base.r[,c("XLAT","LONG","TRNO","TNAM","PDAT", "HDAT","CWAM","HWAH","CNAM","GNAM","NDCH","TMAXA",
                "TMINA","SRADA","PRCP","ETCP","ESCP", "CRST")]
    base.df <- data.frame(base.sub)
    base.sub$XLAT <- base.df$V15
    base.sub$base <- base
    base.sub$WUE <- base.sub$HWAH / base.sub$PRCP
    
    # Get the lat and long
    wh <- readLines(list.wh[i], n=5)[5]
    wh.split <- strsplit(wh," ", fixed=T)
    base.sub$Lat <- ifelse(is.na(as.numeric(wh.split[[1]][6]))==TRUE, as.numeric(wh.split[[1]][7]),as.numeric(wh.split[[1]][6]))
    base.sub$Lon <- ifelse(is.na(as.numeric(wh.split[[1]][9]))==TRUE, as.numeric(wh.split[[1]][10]),as.numeric(wh.split[[1]][9]))
    
    # Get the variety
    base.sub$Variety <- strsplit(base, "/")[[1]][2]
    
    # Get the location
    base.sub$Loc <- strsplit(base, "/")[[1]][3]
    
    f_all <- rbind(f_all, base.sub)
  }
  
  ## Save the aggregated DSSAT output
  saveRDS(f_all,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_",Extent,"_season_",Season,".RDS" )) #to be changed
}

# 4. Get ONI Index  -------------------------------------------

get_ONI <- function(country, useCaseName, Crop, Extent, Season, Plot){
  
  #' @description Function that will classify each DSSAT simulation based on ONI index
  #' @param country country name
  #' @param useCaseName use case name
  #' @param Crop targeted crop
  #' @param Extent spatial extent of the simulation, default = AOI
  #' @param Season integer, cropping season concerned, default = 1 
  #' @param Plot, provide somes plots of the output, default = TRUE
  #'
  #' @return A table with the aggregated DSSAT simulation classified based on ONI index - Output table is written out in "~/agwise-fertilizer/Data/useCaseName/Crop/result/DSSAT/Extent/useCase_country_useCaseName_crop_Extent_season_X_ONI.RDS")
  #'
  #' @examples get_ONI(country= "Kenya", useCaseName = "KALRO", Crop="Maize", Extent="AOI", Season=1, Plot=TRUE)
  #' 
  #'
  
  ## 4.1. Creating a directory to store output table and graphics ####
  if (Extent == 'AOI'){
    pathOut <- paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName,"/",Crop,"/result/DSSAT/",Extent,"/", sep="")
  } else {
    pathOut <- paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName,"/",Crop,"/result/DSSAT/", sep="")
  }
  
  
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
  if (!file.exists("/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/ONI/oni.txt")){
    download.file(url, paste(destfile, file_name, sep = ""), mode="wb")
  } else {
  # Update the ONI version with the last version
    unlink("/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/ONI/oni.txt")
    download.file(url, paste(destfile, file_name, sep = ""), mode="wb")
  }
  
  # Open the ONI data
  oni <- read_table("/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/ONI/oni.txt")
  
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
  
  ### 4.2.2. Get the aggregated DSSAT output and reshape the data ####
  # Open the aggregated DSSAT output
  dssat_path <- paste("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName,"/",Crop,"/result/DSSAT/",Extent,"/useCase_", country, "_",useCaseName,"_",Crop,"_",Extent,"_season_",Season,".RDS", sep="")
  dssat <- readRDS(dssat_path)
  
  ## 4.3. Get the median ONI over the cropping season for aggregated DSSAT output ####
  # Ranges of date of analysis
  date_ranges <- data.frame (
    initial_date = dssat$PDAT, # Planting Date
    final_date = dssat$HDAT    # Harvesting Date
  )
  
  # Compute the median ONI over the cropping season
  med_oni <- pmap_dfr(date_ranges, get_median_variable, variable="ANOM", data=oni)

  # Update the aggregated DSSAT output
  dssat_oni <- bind_cols(dssat,med_oni)
  
  ## 4.4. Classify tbe ONI into three classes ####
  # med ONI > 0.5, Nino, med ONI < -0.5 Nina, -0.5 > ONI > 0.5 Neutral 
  dssat_oni$ENSO <- ifelse(dssat_oni$med_variable > 0.5,"Niño",
                             ifelse(dssat_oni$med_variable< -0.5,"Niña", "Neutral"))
  
  # Save the aggregated DSSAT output with ONI information
  saveRDS(dssat_oni,paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_",Extent,"_season_",Season,"_ONI.RDS" ))
  
  ## 4.5. Basic plots ####
  if (Plot == TRUE){
    ### 4.5.1. Global plot ####
    dssat_oni <- na.omit(dssat_oni)
    # Define a manual scale
    val <- c("Neutral" = "gold",
             "Niño" = "tomato1",
             "Niña" = "royalblue2")
  
    x_lab_o <- unique(dssat_oni$TNAM)
    #ggplot(aes(x = factor(TNAM, level= x_lab_o)
               
  # Meand and SEM plot
  pd <- position_dodge(0.2)
  dssat_oni %>%
    summarySE(measurevar="HWAH", groupvars=c("Variety","TNAM", "ENSO"))%>%
  ggplot(aes(x = factor(TNAM, level= x_lab_o), 
             y = HWAH, 
             group=ENSO, 
             color=ENSO)) +
    geom_point(position = pd, size = 3) +
    geom_line(position = pd,linewidth = 1) +
    geom_errorbar(aes(ymin = HWAH - se, ymax = HWAH + se), width = .1, position= pd)+
    theme_bw()+
    scale_color_manual(values=val)+ theme(axis.text.x =element_text(angle=45, hjust=1))+
    ylab(expression(bold('Yield'~(kg~ha^{-1})))) + xlab(expression(bold("Planting time")))
  ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_",Extent,"_season_",Season,"_ONI_DotPlot_Global.pdf"))

  # Heat map
  p1 <- dssat_oni %>%
    summarySE(measurevar="HWAH", groupvars=c("Variety","TNAM", "ENSO"))%>%
  ggplot(aes(x=factor(TNAM, level= x_lab_o), y=ENSO, fill=HWAH))+
     geom_tile(color="white", linewidth=0.1)+
     theme_bw()+
     theme(axis.text.x =element_text(angle=45, hjust=1))+
     scale_fill_viridis_c(name="Yield"~(kg~ha^{-1}))+
     coord_equal()+
    ylab(expression(bold("ENSO")))+xlab(expression(bold("Planting time")))+
    ggtitle("Mean yield")
  
 p2 <-  dssat_oni %>%
   summarySE(measurevar="HWAH", groupvars=c("Variety","TNAM", "ENSO"))%>%
    ggplot(aes(x=factor(TNAM, level= x_lab_o), y=ENSO, fill=sd))+
    geom_tile(color="white", linewidth=0.1)+
    theme_bw()+
    theme(axis.text.x =element_text(angle=45, hjust=1))+
    scale_fill_viridis_c(name="Yield"~(kg~ha^{-1}))+
    coord_equal()+
    ylab(expression(bold("ENSO")))+xlab(expression(bold("Planting time")))+
    ggtitle("Standard Deviation")
 p1+p2+plot_layout(ncol = 1) 
 ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_",Extent,"_season_",Season,"_ONI_HeatMap_Global.pdf"))
 
 ### 4.5.2. Plot by variety ####
 # Meand and SEM plot
 pd <- position_dodge(0.2)
 dssat_oni %>%
   summarySE(measurevar="HWAH", groupvars=c("Variety","TNAM", "ENSO"))%>%
   ggplot(aes(x = factor(TNAM, level= x_lab_o), 
              y = HWAH, 
              group=ENSO, 
              color=ENSO)) +
   facet_grid(rows = vars(Variety))+
   geom_point(position = pd, size = 3) +
   geom_line(position = pd,linewidth = 1) +
   geom_errorbar(aes(ymin = HWAH - se, ymax = HWAH + se), width = .1, position= pd)+
   theme_bw()+
   scale_color_manual(values=val)+ theme(axis.text.x =element_text(angle=45, hjust=1))+
   ylab(expression(bold('Yield'~(kg~ha^{-1})))) + xlab(expression(bold("Planting time")))
 ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_",Extent,"_season_",Season,"_ONI_DotPlot_Variety.pdf"))
 
 # Heat map
 p1 <- dssat_oni %>%
   summarySE(measurevar="HWAH", groupvars=c("Variety","TNAM", "ENSO"))%>%
   ggplot(aes(x=factor(TNAM, level= x_lab_o), y=ENSO, fill=HWAH))+
   facet_grid(rows = vars(Variety))+
   geom_tile(color="white", linewidth=0.1)+
   theme_bw()+
   theme(axis.text.x =element_text(angle=45, hjust=1))+
   scale_fill_viridis_c(name="Yield"~(kg~ha^{-1}))+
   coord_equal()+
   ylab(expression(bold("ENSO")))+xlab(expression(bold("Planting time")))+
   ggtitle("Mean yield")
 
 p2 <-  dssat_oni %>%
   summarySE(measurevar="HWAH", groupvars=c("Variety","TNAM", "ENSO"))%>%
   ggplot(aes(x=factor(TNAM, level= x_lab_o), y=ENSO, fill=sd))+
   facet_grid(rows = vars(Variety))+
   geom_tile(color="white", linewidth=0.1)+
   theme_bw()+
   theme(axis.text.x =element_text(angle=45, hjust=1))+
   scale_fill_viridis_c(name="Yield"~(kg~ha^{-1}))+
   coord_equal()+
   ylab(expression(bold("ENSO")))+xlab(expression(bold("Planting time")))+
   ggtitle("Standard Deviation")
 p1+p2+plot_layout(ncol = 2) 
 ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_",Extent,"_season_",Season,"_ONI_HeatMap_Variety.pdf"))
 
 ## 4.6. Maps ####
 
 # Read the relevant shape file from gdam to be used to crop the global data
 countryShp <- geodata::gadm(country, level = 1, path=paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName,"/",Crop,"/result/DSSAT/", sep=""))
 country_sf <- sf::st_as_sf(countryShp)
 
 ### 4.6.1. Global Map ####
 dssat_oni.g <- dssat_oni %>%
   summarySE(measurevar="HWAH", groupvars=c("Lat","Long", "ENSO"))
 
 # Scale limits
 min.mean <- min(dssat_oni.g$HWAH)
 max.mean <- max(dssat_oni.g$HWAH)
 
 min.sd <- min(dssat_oni.g$sd)
 max.sd <- max(dssat_oni.g$sd)
 
 ## Neutral
 dssat.neutral.g <- subset(dssat_oni.g, dssat_oni.g$ENSO %in% 'Neutral', select = -c(ENSO, N))
 dssat.neutral.g <- na.omit(dssat.neutral.g[,c(2,1,3,4,5,6)])
 
 ## Nino
 dssat.nino.g <- subset(dssat_oni.g, dssat_oni.g$ENSO %in% 'Niño', select = -c(ENSO, N))
 dssat.nino.g <- na.omit(dssat.nino.g[,c(2,1,3,4,5,6)])
 
 ## Nina
 dssat.nina.g <- subset(dssat_oni.g, dssat_oni.g$ENSO %in% 'Niña', select = -c(ENSO, N))
 dssat.nina.g <- na.omit(dssat.nina.g[,c(2,1,3,4,5,6)])
 
 ## Assembling
 dssat.g.mean <- dssat.neutral.g
 dssat.g.mean$Wheather <- "B"
 dssat.nino.g$Wheather <- 'A'
 dssat.nina.g$Wheather <- 'C'
 dssat.g.mean <- rbind(dssat.g.mean, dssat.nino.g)
 dssat.g.mean <- rbind(dssat.g.mean, dssat.nina.g)
 
 mean.g <-oni_map(data=dssat.g.mean, x=Long, y=Lat,shp=country_sf, fill=HWAH, HWAH= TRUE,limits=c(min.mean, max.mean))
 sd.g <-oni_map(data=dssat.g.mean, x=Long, y=Lat,shp=country_sf, fill=sd, HWAH= FALSE, limits=c(min.sd, max.sd))
 
 ass <- plot_grid(mean.g, sd.g)
 # Final Layout
 title <- ggdraw() + draw_label(
     "Water limited yield according to main weather patterns:",
     fontface = 'bold',
     x = 0,
     hjust = 0
   ) +
   draw_label(
     paste(country, "-", useCaseName, " use case", "-", Crop),
     fontface = 'bold',
     x = 0,
     y=0.15,
     hjust = 0
   )+
   theme(
     # add margin on the left of the drawing canvas,
     # so title is aligned with left edge of first plot
     plot.margin = margin(0, 0, 0, 7)
   )
 
plot_grid(
   title, ass,
   ncol = 1,
   # rel_heights values control vertical title margins
   rel_heights = c(0.1, 1)
 )
 
ggsave(paste0(pathOut,"useCase_", country, "_",useCaseName,"_",Crop,"_",Extent,"_season_",Season,"_ONI_Maps_Global.pdf"), dpi=300, width = 8, height=6.89, units=c("in"))

  }
}

# country="Kenya"
# useCaseName="KALRO"
# Crop = "Maize"
# Extent = "AOI"
# Season = 1
# Plot = TRUE
# 
# 
# get_ONI(country, useCaseName, Crop, Extent, Season, Plot)
# merge_DSSAT_output(country, useCaseName, Crop, Extent, Season)