# Container for the AgWISE planting-date/cultivar R pipeline (this repo only).
# The separate agwise-data/data_sourcing Python package is NOT included here -
# that is a later, separate container per AZURE_CONTAINERIZATION_PLAN.md.
#
# Uses the already-built DSSAT-CSM v4.8.1.40 binary tree (copied in from
# dssat-bin/, see repo root README section on building this image) rather
# than compiling DSSAT-CSM from source - matches this repo's hardcoded
# binary path (main/DSSAT/dssat_exec.R:31) and avoids the unverified CMake
# install-layout risk called out in AZURE_CONTAINERIZATION_PLAN.md.

FROM rocker/geospatial:4.5.2

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Mirrors main/DSSAT/00_load_packages.R
RUN R -e "install.packages(c( \
      'yaml','future','future.apply','furrr','foreach','mgsub', \
      'countrycode','slider','sp','sf','chirps','rlang','scales', \
      'DSSAT','rgl','geodata','tidyverse','terra','tidyterra' \
    ), repos='https://cloud.r-project.org')"

# Mirrors the Python package list in README.md (ECMWF/CDS download workflow)
RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install --no-cache-dir \
      cdsapi xarray pandas numpy dask netCDF4 h5netcdf rioxarray requests \
      tqdm matplotlib cartopy

# DSSAT-CSM binary + support files (genotype .CUL/.ECO/.SPE, MODEL.ERR, Data/)
COPY dssat-bin/v4.8.1.40 /opt/DSSAT/v4.8.1.40

COPY . /workspace
WORKDIR /workspace

ENTRYPOINT ["Rscript", "usecases/run_usecase.R"]
CMD ["usecases/configs/KEN/maize_test.yml", "--dry-run"]
