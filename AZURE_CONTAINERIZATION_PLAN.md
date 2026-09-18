# Containerizing this pipeline for Azure

Plan for running the DSSAT planting-date/cultivar pipeline (this repo,
R) plus its data layer (`agwise-data`/`data_sourcing`, Python) in a
container on Azure, reading/writing from Azure Blob Storage instead of
local disk. Written as a starting point to adapt, not a drop-in recipe —
several choices below (base image, orchestration service) depend on
things only you know (budget, existing Azure subscription setup, how
often this runs).

## What actually needs to move

Two codebases, two languages, one working-directory-heavy R pipeline:

- **This repo** (`main/DSSAT/*.R`): R, uses `future`/`future.apply` for
  per-zone and per-site parallelism (`plan_multisession()`, cgroup-aware),
  reads/writes DSSAT's own file formats (`SOIL.SOL`, `.WTH`, `.MZX`,
  `.OUT`) via `setwd()` into one `EXTE####` folder per site, and shells
  out to the DSSAT-CSM Fortran binary (`/opt/DSSAT/v4.8.1.40/dscsm048`
  on this machine).
- **`agwise-data`** (sibling Python package, `~/agwise-datasourcing/code/data_sourcing`):
  fetches/caches CDS (SEAS5 seasonal forecast), CHIRPS, AgERA5, SoilGrids
  data under a configurable root (`AGWISE_DATA_ROOT` env var) plus a
  read-only pre-staged local tree (`AGWISE_LOCAL_ROOT`, `CGLABS_LANDING`
  on this server).
- **R package list** (`main/DSSAT/00_load_packages.R`): `sf`, `terra`,
  `sp`, `rgl`, `tidyterra`, `geodata`, `chirps`, `DSSAT`, `tidyverse`,
  `future`/`future.apply`/`furrr` — several of these need system GDAL/GEOS/
  PROJ libraries, not just R itself.
- No `renv.lock`/`DESCRIPTION`/`requirements.txt` exists in either repo
  today — the package lists above are the closest thing to a manifest;
  pin exact versions when you write the Dockerfile rather than trusting
  "whatever CRAN has today."

## The one architectural decision that matters most: don't blob-mount the hot path

This session spent a long time making the per-site DSSAT loop fast
precisely because it's I/O-heavy: thousands of `EXTE####` folders, each
`setwd()`'d into and read/written many times (weather file, soil file,
genetic files copied in, batch file, `.OUT` file). Blob-backed filesystem
mounts (blobfuse2, NFS-on-blob) have per-file-open latency far higher
than local disk — pointing the live `transform/DSSAT/AOI/.../EXTE####/`
tree at a blob mount would silently reintroduce a severe slowdown, the
same class of problem already fixed once this session (see
`data_sourcing_bugs.txt`).

**Recommended split:**

| Data | Access pattern | Where it lives |
|---|---|---|
| Usecase configs (`usecases/configs/**/*.yml`) | read once per run | Blob, fetched at container start |
| CDS/CHIRPS/AgERA5/soil cache (`AGWISE_DATA_ROOT`, `AGWISE_LOCAL_ROOT`) | read a handful of times per run, large files | Blob, either blobfuse2-mounted or synced in — moderate I/O volume, blob is fine here |
| `EXTE####` working tree (`transform/DSSAT/AOI/**`) during Step 2/3 | thousands of small file opens per zone | **Local/attached disk only** (container-local SSD, or Azure Files Premium if it must survive a container restart) — sync to blob only before/after, not during |
| DSSAT templates (`Landing/DSSAT/*`) | read-heavy, small, static | Bake into the container image (rarely changes) rather than fetch at all |
| Final merged results/dashboard exports | written once per run | Blob, uploaded at the end of Step 4 |

## Dockerfile sketch

```dockerfile
# --- Stage 1: DSSAT-CSM (build once, reuse) -------------------------------
FROM ubuntu:22.04 AS dssat-build
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake gfortran git ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch v4.8.1.40 \
    https://github.com/DSSAT/dssat-csm-os.git /src/dssat-csm-os
RUN cmake -S /src/dssat-csm-os -B /src/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /src/build -j"$(nproc)"
# Adjust the install path below to match wherever CMake actually puts the
# binary + support files (MODEL.ERR, Data/, genotype .CUL/.ECO/.SPE) for
# your checked-out version - verify against a local build first.

# --- Stage 2: runtime -------------------------------------------------------
FROM rocker/geospatial:4.4   # ships GDAL/GEOS/PROJ already built for sf/terra

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv blobfuse2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=dssat-build /opt/DSSAT /opt/DSSAT

# R deps - pin versions once you've confirmed a known-good set; this
# mirrors main/DSSAT/00_load_packages.R
RUN R -e "install.packages(c( \
      'yaml','future','future.apply','furrr','foreach','mgsub', \
      'countrycode','slider','sp','sf','chirps','rlang','scales', \
      'DSSAT','rgl','geodata','tidyverse','terra','tidyterra' \
    ), repos='https://cloud.r-project.org')"

# Python side (agwise-data)
COPY data_sourcing/pyproject.toml /opt/agwise-data/pyproject.toml
COPY data_sourcing/src /opt/agwise-data/src
RUN pip3 install --no-cache-dir "/opt/agwise-data[cds,geo]"

# Landing/DSSAT templates baked in (small, static, avoids a blob round trip
# on every one of thousands of per-site reads)
COPY Landing/DSSAT /opt/dssat-templates

COPY . /workspace
WORKDIR /workspace

ENV AGWISE_DATA_ROOT=/mnt/blobdata/agwise_data_root \
    AGWISE_LOCAL_ROOT=/mnt/blobdata/landing \
    DSSAT_WORKDIR=/scratch/dssat

ENTRYPOINT ["Rscript", "usecases/run_usecase.R"]
```

Notes:
- `rocker/geospatial` is a real, maintained image with `sf`/`terra`'s
  system deps already compiled — worth using instead of plain
  `rocker/r-ver` + hand-installing GDAL, unless you need a specific base
  OS for other reasons.
- The DSSAT-CSM build stage is unverified against this exact tag — build
  it once locally, diff the resulting binary/support-file layout against
  `/opt/DSSAT/v4.8.1.40/` on this machine, and adjust `COPY --from=` paths
  before trusting it in CI. The faster path for a first container is
  often to just `COPY` the already-built `/opt/DSSAT/v4.8.1.40/` tree
  from this server directly into the image instead of rebuilding from
  source — reproducible-from-source is nicer long-term, not required
  for a first working container.

## Reading/writing Azure Blob Storage

Two mechanisms below: explicit SDK calls (for config-in/results-out, a
few large transfers per run — auditable, simple) and a blobfuse2 mount
(for the CDS/observation cache, moderate-volume reads — matches this
repo's existing path-based code with zero changes). Do **not** blobfuse2-mount
the `EXTE####` working tree (see table above).

### R — explicit blob I/O (`AzureStor`)

```r
library(AzureStor)

# Managed Identity (no secret in the image/env) - the container's Azure
# identity must be granted Storage Blob Data Contributor on the account.
library(AzureAuth)
token <- get_managed_token("https://storage.azure.com/")
endpoint <- storage_endpoint(
  "https://<account>.blob.core.windows.net", token = token)

# Local dev / outside Azure fallback: a storage key or SAS token instead
# endpoint <- storage_endpoint(
#   "https://<account>.blob.core.windows.net",
#   key = Sys.getenv("AZURE_STORAGE_KEY"))

configs_cont <- storage_container(endpoint, "usecase-configs")
results_cont <- storage_container(endpoint, "dssat-results")

# Fetch a usecase config before run_dssat_pipeline() reads it
storage_download(
  configs_cont, src = "MOZ/maize_develop.yml",
  dest = "usecases/configs/MOZ/maize_develop.yml", overwrite = TRUE)

# ... run_dssat_pipeline(usecase, repo_root) as usual, writing to
# local/scratch paths ...

# Push the final merged results + dashboard store back to blob
storage_upload(
  results_cont,
  src = "data/usecases/useCase_Mozambique_develop/Maize/result/dssat_results.rds",
  dest = "Mozambique/develop/dssat_results.rds")

storage_multiupload(
  results_cont,
  src = "data/usecases/useCase_Mozambique_develop/Maize/dashboard_store/*",
  dest = "Mozambique/develop/dashboard_store/")
```

### Python — explicit blob I/O (`azure-storage-blob` + `azure-identity`)

Relevant to `agwise-data`'s own I/O boundary (`config.py`'s
`AGWISE_DATA_ROOT`) if you'd rather fetch specific files than mount the
whole cache:

```python
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

# DefaultAzureCredential finds the container's Managed Identity on Azure,
# falls back to `az login` locally - no secret in code or image.
credential = DefaultAzureCredential()
blob_service = BlobServiceClient(
    account_url="https://<account>.blob.core.windows.net",
    credential=credential,
)
cache_container = blob_service.get_container_client("agwise-data-cache")

def fetch_cached(blob_path: str, local_path: str) -> None:
    local_path = Path(local_path)
    local_path.parent.mkdir(parents=True, exist_ok=True)
    with open(local_path, "wb") as f:
        f.write(cache_container.download_blob(blob_path).readall())

def push_cached(local_path: str, blob_path: str) -> None:
    with open(local_path, "rb") as f:
        cache_container.upload_blob(name=blob_path, data=f, overwrite=True)

# Example: pull a harmonized SEAS5 file before get_seasonal() needs it
fetch_cached(
    "harmonized/seas5/rg_29_m28_42_m9/Seasonal_PRCP_i08_1993_2016.nc",
    f"{os.environ['AGWISE_DATA_ROOT']}/harmonized/seas5/rg_29_m28_42_m9/Seasonal_PRCP_i08_1993_2016.nc",
)
```

### blobfuse2 mount (for the CDS/observation cache, not the hot path)

```yaml
# /etc/blobfuse2/config.yaml
allow-other: true
components: [libfuse, file_cache, attr_cache, azstorage]
file_cache:
  path: /mnt/blobfuse_tmp
  timeout-sec: 120
azstorage:
  type: block
  account-name: <account>
  container: agwise-data-cache
  mode: msi     # managed identity - no key in this file
```

```bash
mkdir -p /mnt/blobdata /mnt/blobfuse_tmp
blobfuse2 mount /mnt/blobdata --config-file=/etc/blobfuse2/config.yaml
export AGWISE_DATA_ROOT=/mnt/blobdata/agwise_data_root
export AGWISE_LOCAL_ROOT=/mnt/blobdata/landing
```
With this mounted, `agwise-data`'s existing `AGWISE_DATA_ROOT`/
`AGWISE_LOCAL_ROOT`-based code runs completely unmodified — the whole
point of choosing env-var-configurable roots.

## Compute / orchestration on Azure

This pipeline's natural unit of work is one `(country, zone, varietyid)`
combination — already how `run_dssat_pipeline.R` loops, and how
`plan_multisession()` sizes its worker pool per container. That maps well
onto batch-style orchestration rather than a long-lived service:

| Service | Fit |
|---|---|
| **Azure Batch** (recommended for the actual DSSAT run) | Built for exactly this shape: an embarrassingly-parallel scientific batch job, one task per zone/usecase, auto-scaling pools, task retry built in. Task-level retry is a nice complement to this session's per-site `tryCatch` work — a whole-task failure (e.g. transient blob-fetch error) gets retried by Batch without you writing that logic yourself. |
| **Azure Container Apps Jobs** | Simpler to set up than Batch; fine for smaller usecases or scheduled (cron-triggered) monthly runs where you don't need Batch's pool-management features. |
| **Azure Container Instances (ACI)** | Simplest possible "run one container," good for dev/prototyping only — no retry, no pool scaling, not recommended once you're running real countries. |
| **AKS** | Overkill unless this becomes one service among several on a shared platform. Skip for a first pass. |

**Secrets/identity**: use a **Managed Identity** on whichever compute
service you pick, granted `Storage Blob Data Contributor` on the storage
account — avoids any storage key/SAS token living in the image or an env
var. Put the CDS API credential (this pipeline's `~/.cdsapirc`
equivalent) and (if you do the Claude Code supervision below) the
`ANTHROPIC_API_KEY` in **Azure Key Vault**, referenced by the compute
service rather than baked into the image.

**Sizing**: `plan_multisession()` (`main/DSSAT/common_helpers.R`) already
reads the cgroup CPU quota via `parallelly::availableCores()`, so it
auto-adapts to whatever vCPU limit you set on the container/task — no
code change needed there, just pick a real vCPU/memory allocation per
task (this session observed ~380-440 MB RSS per FILEX-generation worker,
and separately confirmed multi-GB peaks during the bias-correction work
for large countries — size generously and confirm against a real run
rather than guessing).

## Phased rollout

1. **Parity check**: containerize with everything still pointed at local
   disk (no blob at all) — confirm a known-good usecase (e.g. Rwanda
   develop) produces identical output inside the container vs. bare
   metal here. Catches missing system deps / R package version drift
   before blob storage adds a second variable.
2. **Config in / results out**: add the explicit blob calls (R
   `AzureStor` examples above) for usecase configs and final results
   only — smallest, lowest-risk blob surface, easy to verify by hand.
3. **Cache via blobfuse2**: point `AGWISE_DATA_ROOT`/`AGWISE_LOCAL_ROOT`
   at a blobfuse2 mount; re-run the same usecase, compare timing against
   step 1's local-disk baseline (expect it to be slower — CDS/observation
   fetches are already a minority of total runtime per this session's
   Rwanda/Mozambique timing work, so some slowdown here is an acceptable
   tradeoff; a *large* slowdown means something's touching this mount too
   often and needs to move to explicit sync-in instead).
4. **Local scratch for the hot path**: confirm the `EXTE####` working
   tree lives on container-local disk (or Azure Files Premium if the job
   needs to survive a restart), synced to blob only at zone boundaries —
   this is the step that protects the I/O performance work already done
   this session.
5. **Move orchestration to Azure Batch**: one task per zone/usecase,
   matching the existing loop structure; lean on Batch's task retry as a
   second layer on top of this session's `tryCatch` containment, not a
   replacement for it.

## Running with Claude Code supervision

A supervisory Claude Code instance watching this pipeline's logs (e.g.
this session's new per-zone completeness summaries in `dssat.exec.log`)
and flagging anomalies is a reasonable pattern, with some caveats:

- **Non-interactive invocation**: Claude Code supports a headless/print
  mode for scripted use (`claude -p "<prompt>"` or similar — check
  `claude --help` in your installed version for the exact current flags,
  since this surface evolves). This is what a cron job or an Azure
  Container Apps Job would call, not the interactive terminal UI.
- **Scope its permissions down**: an unattended supervisor should not run
  with blanket destructive permissions. Give it read access to logs/
  outputs (mount the synced-out results/logs, or a read-only blob SAS)
  and a narrow, explicit allowlist (see this repo's own
  `.claude/settings.json` pattern, or the `fewer-permission-prompts`
  skill) rather than `--dangerously-skip-permissions`. If you want it to
  *act* (e.g. re-trigger a failed Batch task), that's a deliberate,
  reviewed integration (a specific tool/MCP server), not blanket shell
  access.
- **Trigger pattern**: simplest is a small wrapper script the
  orchestrator (cron, Batch job-completion hook, Container Apps Job)
  calls after each run: feed it the zone-completeness summary lines,
  ask for a pass/fail judgment and a one-paragraph report, post that to
  wherever you already get alerts (email, Teams/Slack webhook).

## Containerizing Claude Code itself

Claude Code is an npm package (`@anthropic-ai/claude-code`), so
containerizing it is small:

```dockerfile
FROM node:20-slim
RUN npm install -g @anthropic-ai/claude-code
WORKDIR /workspace
ENTRYPOINT ["claude"]
```

Run it with:
```bash
docker run --rm \
  -e ANTHROPIC_API_KEY=<from Key Vault, not baked into the image> \
  -v /path/to/synced/logs:/workspace/logs:ro \
  claude-code-supervisor \
  -p "Read logs/dssat.exec.log, summarize any zone with >5% skipped sites, flag if any zone is missing entirely."
```

Notes:
- Mount whatever the supervisor needs read access to (synced-out logs/
  results from blob) as a read-only volume — don't give it write access
  to the pipeline's own working tree.
- If it needs to inspect Azure resources directly (e.g. check a Batch
  job's status), add the Azure CLI (`apt-get install azure-cli` or the
  `mcr.microsoft.com/azure-cli` base image) and a Managed Identity/
  service-principal login, scoped read-only where possible.
- If your organization routes Claude through Bedrock or Vertex instead
  of the Anthropic API directly, the same container works — swap the
  auth env vars per Claude Code's Bedrock/Vertex configuration instead
  of `ANTHROPIC_API_KEY`.

## Open questions to settle before building this for real

- Which Azure region(s) — affects both storage/compute placement and
  network latency to the Copernicus CDS API (outbound only, no special
  networking needed, but worth confirming egress isn't blocked by
  whatever NSG/firewall policy applies).
- Expected run cadence (monthly per the forecast cycle? on-demand?) —
  decides whether Container Apps Jobs' simplicity beats Azure Batch's
  extra setup cost.
- Who owns the Azure subscription / Key Vault / Managed Identity setup —
  not something to guess at from this repo alone.
- Whether `data_sourcing`/`agwise-data` gets containerized as a separate
  service (called over a small API) or vendored into the same image as
  this repo, as sketched above — the sketch above assumes the latter for
  simplicity; a separate service makes sense if other AgWise modules
  besides this one also need it.
