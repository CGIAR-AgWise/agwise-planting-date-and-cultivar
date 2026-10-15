# Container for the AgWISE planting-date/cultivar R pipeline (this repo) +
# the sibling agwise-data CLI (../data_sourcing), chained in via a
# multi-stage FROM instead of vendoring that repo's source directly. Each
# repo keeps its own Dockerfile/release, and the R side still talks to the
# CLI exactly the way it does outside a container: a subprocess call to a
# binary on PATH (see main/DSSAT/run_datasourcing_export.R,
# data_sourcing's r/agwise_data.R), not a network call.
#
# Uses the already-built DSSAT-CSM v4.8.1.40 binary tree (copied in from
# dssat-bin/) rather than compiling DSSAT-CSM from source - matches this
# repo's hardcoded binary path (main/DSSAT/dssat_exec.R:31) and avoids the
# unverified CMake install-layout risk called out in
# AZURE_CONTAINERIZATION_PLAN.md.
#
# Build order (local):
#   1. cd ../data_sourcing && docker build -t agwise-data:latest .
#   2. Extract the DSSAT-CSM v4.8.1.40 binary tree into ./dssat-bin/v4.8.1.40
#      (from e.g. dssat-binary-for-laptop/dssat-v4.8.1.40.tar.gz) - NOT
#      committed to git, see .gitignore.
#   3. docker build -t agwise-planting-date-and-cultivar .
#
# For an Azure build (az acr build) later, replace `agwise-data:latest`
# below with the ACR-hosted tag of the image built by step 1 (e.g.
# <registry>.azurecr.io/agwise-data:latest), pushed there first.

# --- Stage 1: the agwise-data CLI, built by ../data_sourcing/Dockerfile ---
FROM agwise-data:latest AS datasourcing

# --- Stage 2: this repo's R pipeline ---------------------------------------
FROM rocker/geospatial:4.5.2

# Mirrors main/DSSAT/00_load_packages.R. Deliberately no repos= override -
# rocker/geospatial pins getOption("repos") to a p3m.dev binary snapshot
# (Ubuntu noble) so this installs prebuilt Linux binaries, not source: much
# faster, and avoids CRAN-source-only pitfalls (sf/terra/rgl need build-time
# system headers this image doesn't have outside the base image's own
# already-matched build; source-compiling under this build's amd64
# emulation independently hit a `gcc: internal compiler error` on one
# package - a QEMU artifact, not a real code issue, but one more reason to
# not compile from source here at all).
RUN R -e "install.packages(c( \
      'yaml','future','future.apply','furrr','foreach','mgsub', \
      'countrycode','slider','sp','sf','chirps','rlang','scales', \
      'DSSAT','rgl','geodata','tidyverse','terra','tidyterra', \
      'rmarkdown','knitr','plotly','crosstalk','leaflet','DT' \
    ))"

# agwise-data CLI, from the sibling repo's image (stage 1) - its whole
# self-contained /usr/local (interpreter, libpython*.so, stdlib,
# site-packages, the `agwise-data` console script), merged into this
# image's own /usr/local (where rocker/geospatial's R already lives, at
# distinctly-named paths - lib/R, bin/R - so nothing collides). Copying
# just a venv isn't enough: its python binary is dynamically linked
# against libpython*.so, which lives outside the venv directory.
COPY --from=datasourcing /usr/local /usr/local
COPY --from=datasourcing /opt/agwise-data-src/r/agwise_data.R /opt/agwise-data/r/agwise_data.R

ENV AGWISE_DATA_BIN=/usr/local/bin/agwise-data \
    AGWISE_DATA_REPO_DIR=/opt/agwise-data \
    AGWISE_DATA_PRODUCTS_DIR=/data/agwise_data/products \
    AGWISE_RAINFALL_SOURCE=chirps_v3 \
    AGWISE_TMPDIR=/tmp/agwise
# AGWISE_RAINFALL_SOURCE: on CGLabs this defaults to chirps_v3 automatically
# because AGWISE_LOCAL_ROOT points at a Landing tree containing
# Rainfall/chirps_v3 (see config.py's Config.__init__). This container never
# mounts that raw Landing tree (deliberately - see AZURE_CONTAINERIZATION_
# PLAN.md's "don't blob-mount the hot path" + the pre-staged harmonized-cache
# approach), so that auto-detection never fires and PRCP silently falls back
# to plain "chirps" (v2.0) - a source nothing pre-stages - triggering a live
# fetch instead of the intended chirps_v3 cache hit. Confirmed live: without
# this, a Rwanda bias-correction PRCP request that should hit an
# already-staged cache in under a minute instead took ~13 minutes chasing a
# live v2.0 fetch. Forcing the source here makes it deterministic regardless
# of what's mounted.

# DSSAT-CSM binary + support files (genotype .CUL/.ECO/.SPE, MODEL.ERR, Data/)
COPY dssat-bin/v4.8.1.40 /opt/DSSAT/v4.8.1.40

# blobfuse2: mounts the shared Azure Blob cache (agwise-cache container,
# Processed/ and Landing/ prefixes - see docker-entrypoint.sh) as real local
# paths for AGWISE_DATA_ROOT/AGWISE_LOCAL_ROOT, so agwise_data's existing
# path-based code (config.py) needs zero changes to read it. Requires FUSE
# container privileges at `docker run` time - confirmed sufficient locally:
# --cap-add SYS_ADMIN --security-opt apparmor:unconfined --device /dev/fuse
# (no need for full --privileged).
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl gnupg fuse3 \
    && curl -sSL -O https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update && apt-get install -y --no-install-recommends blobfuse2 \
    && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Only the pipeline code and its genotype/landing files - not the whole repo
# folder, so local data, logs and secrets.env can never end up in the image
# (dssat-bin/ is already copied to /opt/DSSAT above).
COPY main /workspace/main
COPY usecases /workspace/usecases
COPY Landing /workspace/Landing
WORKDIR /workspace

# Append project-specific cultivar/ecotype/species entries from Landing/DSSAT/
# to the installed DSSAT genotype files. DSSATPRO.L48 (CRD key) points DSSAT's
# cultivar lookup at /opt/DSSAT/v4.8.1.40/Genotype/ - copying Landing files to
# the EXTE working directory is not sufficient because dscsm048 reads from CRD,
# not from the current working directory. This appends after the standard
# entries so standard cultivar IDs retain their defaults while custom IDs
# (890xxx Rwanda, 999xxx Kenya/min/max, 900xxx Zambia/Ghana, 234xxx Nigeria)
# are found on the first and only occurrence.
RUN for f in Landing/DSSAT/*.CUL Landing/DSSAT/*.ECO Landing/DSSAT/*.SPE; do \
      base=$(basename "$f"); \
      target="/opt/DSSAT/v4.8.1.40/Genotype/${base}"; \
      [ -f "$target" ] && grep -v '^[!*@]' "$f" | grep -v '^[[:space:]]*$' >> "$target"; \
    done

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["usecases/configs/RWA/maize_demo.yml"]
