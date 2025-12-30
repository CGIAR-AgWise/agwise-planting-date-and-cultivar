# Create Crop type map for the use case and targeted crop

# Introduction: 
# This script allows to derive crop type domain map based on crop coordinates of the targeted crop : 
# (1) - Read and prepare the relevante data
# (2) - Conduct a PCA analysis to reduce the RS data set size
# (3) - Create a targeted crop / other crops ground database based on an unsupervised learning approach
# (4) - Calibrate 5 classification algorithms and compare their performances
# (5) - Create the final crop type domain map based on the ensemble of the 3 top performing algorithms
# Authors : L.Leroux, A.Srivastava, P.Ghosh
# Credentials : EiA, 2024

#### Getting started #######

# 1. Reading the libraries  -------------------------------------------

packages_required <- c("plotly", "raster", "rgdal", "gridExtra", "sp", "ggplot2", "caret", "signal", "timeSeries", "zoo", 
                       "pracma", "rasterVis", "RColorBrewer", "dplyr", "terra", "randomForest", "sf", "factoextra", "mclust",
                       "tidyverse", "ggspatial", "cowplot", "tidyterra","lubridate")

# check and install packages that are not yet installed
installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
  install.packages(packages_required[!installed_packages])}

# load required packages
suppressWarnings(suppressPackageStartupMessages(invisible(lapply(packages_required, library, character.only = TRUE))))

# Set the environment to English 
Sys.setlocale("LC_ALL","English")

# 2. Crop type mapping from NDVI time series-------------------------------------------

CropType <- function (country, useCaseName, level, admin_unit_name, Planting_year, Harvesting_year, Planting_month, Harvesting_month, crop, coord, overwrite, CropMask=T){
  
  #' @description Function that allow to create a crop type domain map for the targeted crop. The input fill should be named as follow : "useCase_Country_useCaseName_Crop_Coordinates.csv"
  #' and should have at least 3 columns : lon, lat and Crop (ex Maize)
  #' @param country country name
  #' @param useCaseName use case name  name
  #' @param level the admin unit level, in integer, to be downloaded -  Starting with 0 for country, then 1 for the first level of subdivision (from 1 to 3). Default is zero
  #' @param admin_unit_name name of the administrative level to be download, default is NULL (when level=0) , else, to be specified as a vector (eg. c("Nandi"))
  #' @param overwrite default is FALSE 
  #' @param Planting_year the planting year in integer
  #' @param Harvesting_year the harvesting year in integer
  #' @param Planting_month the planting month in full name (eg.February)
  #' @param Harvesting_month the harvesting month in full name (eg. September)
  #' @param crop targeted crop with the first letter in uppercase. The input file should have one column named with the crop name
  #' @param coord names of the columns with the lon lat column (ex. c(lon, lat))
  #' @param CropMask default is TRUE. Does the cropland areas need to be masked?
  #'
  #' @return raster files of the targeted crop type domain at the Use Case level, the results will be written out in /agwise-planting-date-and-cultivar/Data/useCase/Crop/results/RS/CropType
  #'
  #' @examples CropType (country="Rwanda", useCaseName="RAB", Planting_year=2021, Harvesting_year=2022, Planting_month='September', Harvesting_month='March', crop='Maize', coord=c('lon','lat'), CropMask = T, overwrite=TRUE)
  
  #' 
  #'
  
  
  ## 2.1. Creating a directory to store the crop type data ####
  pathOut <- paste("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/", crop,"/result/RS/CropType", sep="")
  
  if (!dir.exists(pathOut)){
    dir.create(file.path(pathOut), recursive = TRUE)
  }
  
  ## 2.2. Read the relevant data ####
  
  ## Read the pre-processed NDVI time series ##
  pathIn <- paste("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/", "RS/transform/NDVI", sep="")
  fileIn_name <- paste0(country,'_', useCaseName, '_*_NDVI_', Planting_year,'_', Harvesting_year, '_SG.tif')
  listRaster_SG <- list.files(path=pathIn, pattern=glob2rx(fileIn_name), full.names = T)
  stacked_SG <- terra::rast(listRaster_SG) #stack
  
  ## Read the ground data ##
  pathInG <- paste("/home/jovyanagwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/", crop, "/raw/RS/", sep="")
  listGroundData <- list.files(path=pathInG, pattern = "data4RS.RDS", full.names = T)
  
  # Check which type of separator before to open the data
  #L <- readLines(listGroundData, n=1)
  #groundData <- if (grepl(";", L)) read.csv2(listGroundData) else read.csv(listGroundData)
  
  groundData <- readRDS(listGroundData)
  
  ## Read the administrative boundary data ##
  # Read the relevant shape file from gdam to be used to crop the global data
  countryShp <- geodata::gadm(country, level, path=pathOut)
  
  # Case admin_unit_name == NULL
  if (is.null(admin_unit_name)){
    countryShp <-countryShp
  }
  
  # Case admin_unit_name is not null 
  if (!is.null(admin_unit_name)) {
    if (level == 0) {
      print("admin_unit_name is not null, level can't be eq. to 0 and should be set between 1 and 3")
    }
    if (level == 1){
      countryShp <- subset(countryShp, countryShp$NAME_1 %in% admin_unit_name)
    } 
    if (level == 2){
      countryShp <- subset(countryShp, countryShp$NAME_2 %in% admin_unit_name)
    }
    if (level == 3){
      countryShp <- subset(countryShp, countryShp$NAME_3 %in% admin_unit_name)
    }
  }
  
  ## 2.3. Preprocess the relevant data ####
  ### 2.3.1 Subset the cropping season +/- 15 days for raster ####
  # Start of the season
  start <- paste0("01-",Planting_month,"-", Planting_year)
  start <- as.Date(as.character(start), format ="%d-%B-%Y")
  startj <- as.POSIXlt(start)$yday # conversion in julian day
  
  # Test the number of days in a month
  if (Harvesting_month %in% c('January','March','May','July','August','October','December')){
    nday = "31-"
  }
  
  if (Harvesting_month %in% c('April','June','September','November')){
    nday = "30-"
  }
  if (Harvesting_month %in% c('February')){
    nday = "28-"
  }
  
  # End of the season
  end <- paste0(nday,Harvesting_month,"-", Planting_year)
  end <- as.Date(as.character(end), format ="%d-%B-%Y")
  endj <- as.POSIXlt(end)$yday # conversion in julian day
  
  # Create a sequence between start and end of the season +/- 15 days
  # Case Planting Year = Harvesting Year
  if (Planting_year == Harvesting_year){
    seq<- seq(startj-15, endj+15,by=1)
    seq= paste0(Planting_year,"_", formatC(seq, width=3, flag="0"))
  }
  
  # Case Planting Year < Harvesting Year
  if (Planting_year < Harvesting_year){
    seq1<- seq(startj-15, 365,by=1)
    seq1 <- paste0(Planting_year, "_", formatC(seq1, width=3, flag="0"))
    seq2 <- seq(1, endj+15,by=1)
    seq2 <- paste0(Harvesting_year, "_", formatC(seq2, width=3, flag="0"))
    seq= c(seq1, seq2)
  }
  
  # Case Planting Year > Harvesting Year
  if (Planting_year > Harvesting_year){
    stop( "Planting_year can't be > to Harvesting_year")
  }
  
  # Subset the data between planting and harvesting date
  stacked_SG_s <- stacked_SG[[grep(paste(seq, collapse = "|"), names(stacked_SG))]]
  rm(stacked_SG)
  
  ### 2.3.2 Masking out of the cropped area ####
  if (CropMask == TRUE){
    
    ## Get the cropland mask and resample to NDVI
    cropmask <- list.files(paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/","RS/raw/CropMask"), pattern=".tif$", full.names=T)
    cropmask <- terra::rast(cropmask)
    cropmask <- terra::mask(cropmask, countryShp)
    ## reclassification 1 = crop, na = non crop
    m1 <- cbind(c(40), 1)
    cropmask <- terra::classify(cropmask, m1, others=NA)
    cropmask <- terra::resample(cropmask, stacked_SG_s)
    
    stacked_SG_s <- stacked_SG_s*cropmask
  }
  
  ### 2.3.4 Shape the ground data base ####
  # Subset the data between planting year and harvesting year
  groundData.s <- subset(groundData, year(groundData$planting_date)== Planting_year & year(groundData$harvest_date) == Harvesting_year)
  groundData.s <- groundData.s[, c(coord, 'crop')]
  groundData.s$ID <- seq(1,nrow(groundData.s)) #For subsequent sub-setting
  groundData.s <- na.omit(groundData.s)
  #groundData.s <- subset(groundData.s, groundData.s$maize %in% 1) #### TEMPORARY TO BE REMOVED
  
  ## Check if the data fall within the crop domain
  # Convert data frame to sf object
  my.sf.point <- st_as_sf(x = groundData.s, 
                          coords = coord,
                          crs = "+proj=longlat +datum=WGS84 +ellps=WGS84 +towgs84=0,0,0")
  # Check for intersection between raster and crop points
  groundData.s.extract <- terra::extract(stacked_SG_s, my.sf.point)
  groundData.s.extract <- na.omit(groundData.s.extract)
  groundData.s <- subset(groundData.s, groundData.s$ID %in% groundData.s.extract$ID)
  # Convert data frame to sf object
  my.sf.point <- st_as_sf(x = groundData.s, 
                          coords = coord,
                          crs = "+proj=longlat +datum=WGS84 +ellps=WGS84 +towgs84=0,0,0")
  
  ## 2.4. PCA Analysis ####
  # sample 5000 random grid cells
  set.seed(123)
  sr <- terra::spatSample(stacked_SG_s, 5000, na.rm=TRUE, method="random") 
  pca <- prcomp(sr, scale=TRUE, retx=FALSE) 
  # Eigenvalues
  eig.val <- get_eigenvalue(pca)
  # Count the number of dimension allowing to explain 80% of the total variance
  var80 <- nrow(subset(eig.val, eig.val$cumulative.variance.percent <= 80))
  
  #predict new raster based on PCA and subset the number of dimension allowing to explain 80% of the total variance
  stacked_SG_pca <- predict(stacked_SG_s, pca) # create new rasters based on PCA predictions
  stacked_SG_pca <- terra::subset(stacked_SG_pca, 1:var80)
  
  ## 2.5. Crop type classification ####
  ### 2.5.1. Unsupervised learning to generate targeted crop / other crops ground truth ####
  ## 1 - Model-based clustering to create unsupervised clusters on the PCA
  # https://www.datanovia.com/en/lessons/model-based-clustering-essentials/
  # use of SR for unsupervised clustering
  set.seed(123)
  # Check the number of observation in the initial ground truth data and considered a final MC database of x2 the initial one
  n <- nrow(my.sf.point)
  sr.pca <- terra::spatSample(stacked_SG_pca, n*2, na.rm=TRUE, method="random", xy=TRUE) 
  mc <- Mclust(sr.pca[,-c(1,2)], G=2:5) # to not account for x y ; Default number of clusters from 2 to 5
  
  ## 2- Applied the model-based clustering to the targeted crop ground data
  groundData.pca <- terra::extract(stacked_SG_pca,my.sf.point, xy=TRUE)
  mc.predict <- predict(mc, subset(groundData.pca, select= -c(ID,x,y)))
  
  ## 3 - Check in which cluster the targeted crop ground data fall in majority
  # Percent of targeted crop by cluster
  prop <- prop.table(table(mc.predict$classification))
  ind <- as.vector(which(prop>=0.25, arr.ind = T )) # consider that if at least 25% of the ground truth fall in that cluster, cluster is classified as the targeted crop
  
  ## 4 - Reclassify the model-based clustering data base into targeted crop(1) / other crop (0)
  sr.pca$Cluster <- mc$classification
  for (i in length(ind)){
    sr.pca$Crop <- ifelse(sr.pca$Cluster==ind[i],1,0)
  }
  
  ## 5 - Merge the Model-based clustering DB (Crop = 0), with the targeted crop ground truth
  sr.pca.nc <- subset(sr.pca, sr.pca$Crop == 0) # non targeted crop
  sr.pca.nc <- subset(sr.pca.nc, select = -c(Cluster))
  
  groundData.pca$Crop <- 1 # Targeted crop
  groundData.pca.c <- subset(groundData.pca, select = -c(ID))
  
  groundTruth.fin <- rbind(sr.pca.nc, groundData.pca.c)
  groundTruth.fin$Crop <- as.factor(groundTruth.fin$Crop) #Conversion into factor
  
  ### 2.5.2. spliting data ####
  # set random number
  set.seed(123)
  train_index <- createDataPartition(groundTruth.fin$Crop, times = 1, p = 0.7, list = FALSE)
  train_data <- groundTruth.fin[train_index, ] %>% glimpse
  test_data <- groundTruth.fin[-train_index, ] %>% glimpse()
  
  ### 2.5.3. Develop models (tuning and calibrating) ####
  # https://setscholars.net/wp-content/uploads/2019/11/Binary-Classification-with-CARET-in-R.html
  # https://andiyudha.medium.com/classification-model-in-r-with-caret-package-373f20e31dd
  #https://f0nzie.github.io/machine_learning_compilation/comparison-of-six-linear-regression-algorithms.html
  ## prepare simple test suite
  # 5-fold cross validation with 3 repeats
  control <- trainControl(method="repeatedcv", number=5, repeats=3, verboseIter = TRUE)
  metric <- "Accuracy"
  seed <- 7
  
  # --------------------------------------
  # Linear Models
  # --------------------------------------
  # Logistic Regression
  set.seed(seed)
  fit.glm <- train(Crop~., data=subset(train_data, select = -c(x,y)), method="glm", metric=metric, trControl=control)
  
  # --------------------------------------
  # Non-Linear Models
  # --------------------------------------
  # Multi-Layer Perceptron
  set.seed(seed)
  fit.mlp <- train(Crop~., data=subset(train_data, select = -c(x,y)), method="mlp", metric=metric, trControl=control)
  
  # --------------------------------------
  # Trees
  # --------------------------------------
  
  # CART
  set.seed(seed)
  tunegrid <- expand.grid(.cp=seq(0,0.1,by=0.01))
  fit.cart <- train(Crop~., data=subset(train_data, select = -c(x,y)), method="rpart", metric=metric, tuneGrid=tunegrid, trControl=control)
  
  # --------------------------------------
  # Boosting Ensemble Algorithms
  # --------------------------------------
  
  # Stochastic Gradient Boosting
  set.seed(seed)
  tunegrid <- expand.grid(.n.trees=c(5, 100, 500), .interaction.depth=c(1, 3, 5, 7, 9), .shrinkage=c(0, 1e-1, 1e-2, 1e-3, 1e-4), .n.minobsinnode=c(5, 10))
  fit.gbm <- train(Crop~., data=subset(train_data, select = -c(x,y)), method="gbm", metric=metric, tuneGrid=tunegrid, trControl=control, verbose=FALSE)
  
  # --------------------------------------
  # Bagged Ensemble Algorithms
  # --------------------------------------
  
  # Random Forest
  set.seed(seed)
  fit.ranger <- train(Crop~., data=subset(train_data, select = -c(x,y)), method="ranger", metric=metric, trControl=control)
  
  ### 2.5.4. Compare algorithms ####
  # Compare algorithms
  results <- resamples(list(GLM    = fit.glm, 
                            MLP = fit.mlp, 
                            RF    = fit.ranger, 
                            CART   = fit.cart, 
                            GBM    = fit.gbm))
  
  # Save all algorithms results
  summary(results)
  acc <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_Accuracy_CAL_All_Algo.pdf")
  pdf(acc, height = 5, width = 15)       # Export PDF
  grid.table(summary(results)$statistics$Accuracy)
  dev.off()
  
  kap <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_Kappa_CAL_All_Algo.pdf")
  pdf(kap, height = 5, width = 15)       # Export PDF
  grid.table(summary(results)$statistics$Kappa)
  dev.off()
  
  pl <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_Metrics_CAL_All_Algo.pdf")
  pdf(pl, height = 6, width = 9)       # Export PDF
  dotplot(results)
  dev.off()
  
  # Save models for the three best algorithms
  dfAcc <- as.data.frame(summary(results)$statistics$Accuracy)
  dfAcc <- dfAcc[order(dfAcc$Median,decreasing = TRUE),]
  dfAcc <-  row.names(dfAcc[1:3,])
  
  if ("GBM" %in% dfAcc){
    gbm <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_finalModel_GBM.rds")
    saveRDS(fit.gbm,gbm)
  }
  
  if ("RF" %in% dfAcc){
    rf <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_finalModel_RF.rds")
    saveRDS(fit.ranger,rf)
  }
  
  if ("MLP" %in% dfAcc){
    mlp <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_finalModel_MLP.rds")
    saveRDS(fit.mlp,mlp)
  }
  
  if ("CART" %in% dfAcc){
    cart <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_finalModel_CART.rds")
    saveRDS(fit.cart,cart)
  }
  
  if ("GLM" %in% dfAcc){
    glm <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_finalModel_GLM.rds")
    saveRDS(fit.glm,glm)
  }
  
  ### 2.5.5. Models validation ####
  val <- data.frame(matrix(nrow=7, ncol=0))
  if ("GBM" %in% dfAcc){
    predict.gbm <- predict(fit.gbm, subset(test_data, select = -c(x,y)))
    summary(predict.gbm)
    # Confusion Matrix
    cf.gbm <- confusionMatrix(predict.gbm, test_data$Crop)
    cf.gbm
    val <- cbind(val, as.data.frame(cf.gbm$overall))
  }
  
  if ("RF" %in% dfAcc){
    predict.ranger <- predict(fit.ranger, subset(test_data, select = -c(x,y)))
    summary(predict.ranger)
    # Confusion Matrix
    cf.ranger <- confusionMatrix(predict.ranger, test_data$Crop)
    cf.ranger
    val <- cbind(val,as.data.frame(cf.ranger$overall))
  }
  
  if ("MLP" %in% dfAcc){
    predict.mlp <- predict(fit.mlp, subset(test_data, select = -c(x,y)))
    summary(predict.mlp)
    # Confusion Matrix
    cf.mlp <- confusionMatrix(predict.mlp, test_data$Crop)
    cf.mlp
    val <- cbind(val,as.data.frame(cf.mlp$overall))
  }
  
  if ("CART" %in% dfAcc){
    predict.cart <- predict(fit.cart, subset(test_data, select = -c(x,y)))
    summary(predict.cart)
    # Confusion Matrix
    cf.cart <- confusionMatrix(predict.cart, test_data$Crop)
    cf.cart
    val <- cbind(val,as.data.frame(cf.cart$overall))
  }
  
  if ("GLM" %in% dfAcc){
    predict.glm <- predict(fit.glm, subset(test_data, select = -c(x,y)))
    summary(predict.glm)
    # Confusion Matrix
    cf.glm <- confusionMatrix(predict.glm, test_data$Crop)
    cf.glm
    val <- cbind(val,as.data.frame(cf.glm$overall))
  }
  
  ## Save models validation
  vali <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_Accuracy_VAL_3_Algo.pdf")
  pdf(vali, height = 5, width = 15)       # Export PDF
  grid.table(val)
  dev.off()
  
  ### 2.5.6. Prediction of best models on raster ####
  if ("GBM" %in% dfAcc){
    predict.gbm.r <- terra::predict(stacked_SG_pca, fit.gbm, na.rm=TRUE)
    plot(predict.gbm.r)
    gbmout <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_GBM_Prediction.tiff")
    terra::writeRaster(predict.gbm.r, gbmout, overwrite=overwrite)
  }
  
  if ("RF" %in% dfAcc){
    predict.ranger.r <- terra::predict(stacked_SG_pca, fit.ranger, na.rm=TRUE)
    plot(predict.ranger.r)
    rangerout <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_RF_Prediction.tiff")
    terra::writeRaster(predict.ranger.r, rangerout, overwrite=overwrite)
  }
  
  if ("MLP" %in% dfAcc){
    predict.mlp.r <- terra::predict(stacked_SG_pca, fit.mlp, na.rm=TRUE)
    plot(predict.mlp.r)
    mlpout <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_MLP_Prediction.tiff")
    terra::writeRaster(predict.mlp.r, mlpout, overwrite=overwrite)
  }
  
  if ("CART" %in% dfAcc){
    predict.cart.r <- terra::predict(stacked_SG_pca, fit.cart, na.rm=TRUE)
    plot(predict.cart.r)
    cartout <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_CART_Prediction.tiff")
    terra::writeRaster(predict.cart.r, cartout, overwrite=overwrite)
  }
  
  if ("GLM" %in% dfAcc){
    predict.glm.r <- terra::predict(stacked_SG_pca, fit.glm, na.rm=TRUE)
    plot(predict.glm.r)
    glmout <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_GLM_Prediction.tiff")
    terra::writeRaster(predict.glm.r, glmout, overwrite=overwrite)
  }
 
  ### 2.5.7. Ensembling the best models prediction and validation #### 
  
  ## Open the prediction
  # List the files
  fileIn_pred <- paste0("useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_*_Prediction.tiff")
  listRaster_Pred <- list.files(path=pathOut, pattern=glob2rx(fileIn_pred), full.names = T)
  # Open the files
  crop_Predict <- terra::rast(listRaster_Pred)
  
  ## Ensembling
  ensemble <- terra::app(crop_Predict, fun=modal)
  ensemble[ensemble==1] <- 0
  ensemble[ensemble > 1 ] <- 1
  levels(ensemble) <- c("Other Crops", stringr::str_to_title(crop))
  ensembleout <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_Ensemble_Prediction.tiff")
  terra::writeRaster(ensemble, ensembleout, overwrite=overwrite)

  ## Validation prediction ensemble
 
  
  ## 2.6. Mapping of the final results ####
  country_sf <- sf::st_as_sf(countryShp)
 ensemble.p <-  ggplot() +
    geom_spatraster(data = ensemble, aes(fill=lyr.1), na.rm=TRUE) +
    theme_bw()+ scale_fill_manual(values=c("azure3", "springgreen4"), name="", na.translate=FALSE)+
    theme(legend.position = "right")+ 
    geom_sf(data=country_sf, fill=NA, color="black", linewidth=0.5)+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop)," domain"))
 
  ensemblemap <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,'_', crop, "_Ensemble_Map.pdf")
  pdf(ensemblemap, height = 8, width = 6)       # Export PDF
  print(ensemble.p)
  dev.off()
  
  ## 2.7. Aggregation of the results at administrative levels ####
  # For the moment by default at admin level 2
  countryShp2 <- geodata::gadm(country, level=2, path=pathOut)
  
  ## Compute the crop area per administrative unit
  ensemble.area <- terra::zonal(ensemble, countryShp2, fun='sum', na.rm=TRUE, as.raster=TRUE) # get the number of cropped pixels
  # convert into surfaces (ha)
  ensemble.areaha <- ensemble.area*62500*0.0001 # (250 * 250) * 0.0001 (conversion from m² to ha)
  
  # Map
  country_sf2 <- sf::st_as_sf(countryShp2)
  area.p <- ggplot() +
    geom_spatraster(data = ensemble.areaha, aes(fill = lyr.1)) +
    scale_fill_stepsn(n.breaks = 9, colours = viridis::viridis(9),name="Crop surface (in ha)", na.value = "transparent")+ theme_bw()+
    theme(legend.position = "right")+ 
    geom_sf(data=country_sf2, fill=NA, color="white", linewidth=0.5)+
    coord_sf(expand = FALSE, xlim=c(terra::ext(ensemble.area)[1], terra::ext(ensemble.area)[2]), ylim=c(terra::ext(ensemble.area)[3], terra::ext(ensemble.area)[4]))+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(crop, " surfaces in ha"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  ## Compute the crop % per administrative unit
  total <- ensemble.area
  total[] <- 1 # to get the total number of pixels, classified as 1 and then sum them
  total <- terra::zonal(total, countryShp2, fun='sum', na.rm=FALSE, as.raster=TRUE)
  total <- round(((ensemble.area*100)/total),2)
  
  # Map
  pct.p <- ggplot() +
    geom_spatraster(data = total, aes(fill = lyr.1)) +
    scale_fill_stepsn(n.breaks = 9, colours = viridis::magma(9),name="Crop cover (in %)", na.value = "transparent")+ theme_bw()+
    theme(legend.position = "right")+ 
    geom_sf(data=country_sf2, fill=NA, color="white", linewidth=0.5)+
    coord_sf(expand = FALSE, xlim=c(terra::ext(ensemble.area)[1], terra::ext(ensemble.area)[2]), ylim=c(terra::ext(ensemble.area)[3], terra::ext(ensemble.area)[4]))+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(crop, " cover in %"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  # Assemble maps
  ass <- plot_grid(area.p, pct.p, nrow=2)
  
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,"_",Harvesting_year,"_Aggregated_Admin_Level2.pdf"), plot=ass, dpi=300, width = 8, height=6.89, units=c("in"))
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,"_",Harvesting_year,"_Aggregated_Admin_Level2.png"), plot=ass, dpi=300, width = 8, height=6.89, units=c("in"))
  
  ## Delete the GDAM folder
  unlink(paste0(pathOut, '/gadm'), force=TRUE, recursive = TRUE)
}

# country = "Rwanda"
# useCaseName = "RAB"
# level = 1
# admin_unit_name = NULL
# Planting_year = 2021
# Harvesting_year = 2022
# Planting_month = "September"
# Harvesting_month = "March"
# overwrite = TRUE
# crop = c("Maize")
# coord = c("lon", "lat")
# CropMask = T