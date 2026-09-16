SHELL := /bin/sh
-include .env
export

PYTHON ?= python
RSCRIPT ?= Rscript
LOCATION ?= Chokwe
CROP ?= Maize
COUNTRY_CODE ?=
SEASON_START ?= 2025-11-01
SEASON_END ?= 2026-02-28
SEASON_YEAR ?= 2025
SEASON_LENGTH_MONTHS ?= 4
LEAD_MONTHS ?= 1
USECASE_CONFIG ?= usecases/configs/MOZ/maize_chokwe.yml
DSSAT_SUMMARY ?= data/usecases/useCase_Mozambique_chokwe/Maize/result/DSSAT/AOI/Maize_2025_treatment_summary.csv
ADVISORY_OUTPUT ?= integration/examples/$(shell echo "$(LOCATION)" | tr '[:upper:]' '[:lower:]')_$(shell echo "$(CROP)" | tr '[:upper:]' '[:lower:]')_advisory.json

.PHONY: help setup dry-run forecast advisory workflow clean-python-cache

help:
	@echo "AgWise + IWMI workflow"
	@echo ""
	@echo "Required decisions: LOCATION, CROP, SEASON_START, SEASON_END"
	@echo ""
	@echo "Targets:"
	@echo "  make setup       Show environment setup commands"
	@echo "  make dry-run     Validate the AgWise use-case without running downloads"
	@echo "  make forecast    Run the configured AgWise/DSSAT use-case"
	@echo "  make advisory    Build terminal advisory from a DSSAT summary"
	@echo "  make workflow    Run forecast, then build the advisory"
	@echo ""
	@echo "Overrides:"
	@echo "  LOCATION=Chokwe CROP=Maize SEASON_START=2025-11-01 SEASON_END=2026-02-28"
	@echo "  USECASE_CONFIG=usecases/configs/MOZ/maize_chokwe.yml"
	@echo "  DSSAT_SUMMARY=path/to/treatment_summary.csv"

setup:
	@echo "Create the Conda environment with: conda env create -f environment.yml"
	@echo "Then activate it and configure CDS credentials and DSSAT_CSM."
	@echo "Install R GitHub packages with: $(RSCRIPT) install_pkgs.R"

dry-run:
	$(RSCRIPT) usecases/run_usecase.R $(USECASE_CONFIG) --dry-run

forecast:
	$(RSCRIPT) usecases/run_usecase.R $(USECASE_CONFIG) --season-year "$(SEASON_YEAR)"

advisory:
	$(PYTHON) integration/run_advisory.py \
		--dssat-summary "$(DSSAT_SUMMARY)" \
		--location "$(LOCATION)" \
		$(if $(COUNTRY_CODE),--country-code "$(COUNTRY_CODE)",) \
		--crop "$(CROP)" \
		--season-start "$(SEASON_START)" \
		--season-end "$(SEASON_END)" \
		--season-length-months "$(SEASON_LENGTH_MONTHS)" \
		--lead-months "$(LEAD_MONTHS)" \
		--sample-raster \
		--output "$(ADVISORY_OUTPUT)"

workflow:
	$(MAKE) forecast
	$(MAKE) advisory

clean-python-cache:
	$(PYTHON) -c "import pathlib; [p.unlink() for p in pathlib.Path('.').rglob('*.pyc')]"
