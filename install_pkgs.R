if (!requireNamespace("remotes", quietly = TRUE)) {
  stop("The Conda environment must provide the 'remotes' R package.")
}

remotes::install_github(c(
  "SantanderMetGroup/loadeR.java",
  "SantanderMetGroup/climate4R.UDG",
  "SantanderMetGroup/loadeR",
  "SantanderMetGroup/transformeR",
  "SantanderMetGroup/visualizeR",
  "SantanderMetGroup/downscaleR"
))
