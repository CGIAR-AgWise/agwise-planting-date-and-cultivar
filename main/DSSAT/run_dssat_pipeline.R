#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)

cat("Initializing DSSAT Pipeline...\n")
source(paste0(project_root, '/main/DSSAT/common_helpers.R'))

# 1. Environment Setup
source("scripts/00_load_packages.R")

# 2. Sequential Execution of the Workflow Steps
cat("Step 1: Preparing geospatial data...\n")
source("scripts/01_prepare_geo.R")

cat("Step 2: Preparing DSSAT experimental files...\n")
source("scripts/02_prepare_exp.R")

cat("Step 3: Executing DSSAT crop model...\n")
source("scripts/03_run_dssat.R")

cat("Step 4: Merging DSSAT simulation outputs...\n")
source("scripts/04_merge_results.R")

cat("Step 5: Generating final workflow outputs...\n")
source("scripts/05_final_outputs.R")

cat("Pipeline completed successfully!\n")