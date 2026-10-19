SHELL := /bin/sh
-include .env
export

PYTHON ?= python
RSCRIPT ?= Rscript
PY_PATH ?= $(PYTHON)
LOCATION ?= Chokwe
CROP ?= Maize
COUNTRY_CODE ?=
SEASON_START ?= 2025-11-01
SEASON_END ?= 2026-02-28
SEASON_YEAR ?= 2025
SEASON_LENGTH_MONTHS ?= 4
LEAD_MONTHS ?= 1
USECASE_CONFIG ?= usecases/configs/MOZ/maize_chokwe.yml
DSSAT_SUMMARY ?= $(firstword $(wildcard data/usecases/useCase_Mozambique_*/Maize/result/DSSAT/AOI/Maize_2025_treatment_summary.csv))
LOCATION_SLUG = $(shell "$(PYTHON)" -c "import sys; print(sys.argv[1].lower())" "$(LOCATION)")
CROP_SLUG = $(shell "$(PYTHON)" -c "import sys; print(sys.argv[1].lower())" "$(CROP)")
ADVISORY_OUTPUT ?= integration/examples/$(LOCATION_SLUG)_$(CROP_SLUG)_advisory.json
ADVISORY_RAINFALL_SOURCE ?= $(if $(IWMI_PRCP_CSV),Synthetic IWMI rainfall override used by DSSAT,AgWise forecast PRCP used by DSSAT)
AGWISE_N_CORES ?= 2
IWMI_PRCP_CSV ?=
IWMI_RAINFALL_OUTPUT ?= integration/synthetic_rainfall/output/chokwe_2025_26_synthetic_rainfall.csv
IWMI_MONTHLY_MODE ?= target-year-fallback
SKIP_DOWNLOAD ?= 0
STATE_DIR ?= .agwise/state
FORCE ?= 0
CHECKPOINT ?= $(STATE_DIR)/forecast.json
ADVISORY_CHECKPOINT ?= $(STATE_DIR)/advisory.json

.PHONY: help setup dry-run iwmi-rainfall forecast advisory workflow status invalidate clean-python-cache

help:
	@echo "AgWise + IWMI workflow"
	@echo ""
	@echo "Required decisions: LOCATION, CROP, SEASON_START, SEASON_END"
	@echo ""
	@echo "Targets:"
	@echo "  make setup       Show environment setup commands"
	@echo "  make dry-run     Validate the AgWise use-case without running downloads"
	@echo "  make iwmi-rainfall Generate synthetic daily IWMI rainfall for the season"
	@echo "  make forecast    Run the configured AgWise/DSSAT use-case"
	@echo "  make advisory    Build terminal advisory from a DSSAT summary"
	@echo "  make workflow    Run forecast, then build the advisory"
	@echo "  make status      Show forecast and advisory checkpoints"
	@echo "  make invalidate  Explain how to force a refresh"
	@echo ""
	@echo "Overrides:"
	@echo "  LOCATION=Chokwe CROP=Maize SEASON_START=2025-11-01 SEASON_END=2026-02-28"
	@echo "  USECASE_CONFIG=usecases/configs/MOZ/maize_chokwe.yml"
	@echo "  DSSAT_SUMMARY=path/to/treatment_summary.csv"
	@echo "  IWMI_PRCP_CSV=path/to/daily_rainfall.csv  # opt-in PRCP replacement"
	@echo "  IWMI_RAINFALL_OUTPUT=path/to/generated_daily_rainfall.csv"
	@echo "  IWMI_MONTHLY_MODE=target-year-fallback|target-year|climatology"

setup:
	@echo "Create the Conda environment with: conda env create -f environment.yml"
	@echo "Activate it with: conda activate agwise-integration"
	@echo "Install climate4R packages with: $(RSCRIPT) install_pkgs.R"
	@echo "Then configure CDS credentials and DSSAT_CSM."

dry-run:
	$(RSCRIPT) usecases/run_usecase.R "$(USECASE_CONFIG)" \
		--dry-run --season-year "$(SEASON_YEAR)" \
		--n-cores "$(AGWISE_N_CORES)" --py-path "$(PY_PATH)"

iwmi-rainfall:
	$(PYTHON) integration/synthetic_rainfall/generate_daily_rainfall.py \
		--monthly-csv integration/raw_data/iwmi_chokwe_monthly_rainfall_2001_2026_09.csv \
		--season-start "$(SEASON_START)" \
		--season-end "$(SEASON_END)" \
		--monthly-mode "$(IWMI_MONTHLY_MODE)" \
		--output "$(IWMI_RAINFALL_OUTPUT)"

forecast:
	@if [ "$(FORCE)" = "1" ] || ! $(PYTHON) integration/workflow_state.py check \
		--state "$(CHECKPOINT)" \
		--inputs "$(USECASE_CONFIG)" "season-year=$(SEASON_YEAR)" "n-cores=$(AGWISE_N_CORES)" \
			"iwmi-prcp=$(IWMI_PRCP_CSV)" \
		--outputs "$(DSSAT_SUMMARY)"; then \
		if $(RSCRIPT) usecases/run_usecase.R "$(USECASE_CONFIG)" \
			--season-year "$(SEASON_YEAR)" --n-cores "$(AGWISE_N_CORES)" \
			--py-path "$(PY_PATH)" \
			$(if $(filter 1,$(SKIP_DOWNLOAD)),--skip-download,) \
			$(if $(IWMI_PRCP_CSV),--rainfall-override-csv "$(IWMI_PRCP_CSV)",); then \
			$(PYTHON) integration/workflow_state.py write \
				--state "$(CHECKPOINT)" \
				--inputs "$(USECASE_CONFIG)" "season-year=$(SEASON_YEAR)" "n-cores=$(AGWISE_N_CORES)" \
					"iwmi-prcp=$(IWMI_PRCP_CSV)" \
				--outputs "$(DSSAT_SUMMARY)"; \
		else \
			echo "Forecast failed; checkpoint was not written." >&2; \
			exit 1; \
		fi; \
	else \
		echo "Reusing completed AgWise/DSSAT checkpoint. Use FORCE=1 to rerun."; \
	fi

advisory:
	@if [ "$(FORCE)" = "1" ] || ! $(PYTHON) integration/workflow_state.py check \
		--state "$(ADVISORY_CHECKPOINT)" \
		--inputs "$(DSSAT_SUMMARY)" "location=$(LOCATION)" "crop=$(CROP)" \
			"season-start=$(SEASON_START)" "season-end=$(SEASON_END)" \
			"season-length=$(SEASON_LENGTH_MONTHS)" "lead-months=$(LEAD_MONTHS)" \
			"rainfall-source=$(ADVISORY_RAINFALL_SOURCE)" \
		--outputs "$(ADVISORY_OUTPUT)"; then \
		if $(PYTHON) integration/run_advisory.py \
			--dssat-summary "$(DSSAT_SUMMARY)" \
			--location "$(LOCATION)" \
			$(if $(COUNTRY_CODE),--country-code "$(COUNTRY_CODE)",) \
			--crop "$(CROP)" \
			--season-start "$(SEASON_START)" \
			--season-end "$(SEASON_END)" \
			--season-length-months "$(SEASON_LENGTH_MONTHS)" \
			--lead-months "$(LEAD_MONTHS)" \
			--rainfall-source "$(ADVISORY_RAINFALL_SOURCE)" \
			--sample-raster \
			--output "$(ADVISORY_OUTPUT)"; then \
			$(PYTHON) integration/workflow_state.py write \
				--state "$(ADVISORY_CHECKPOINT)" \
				--inputs "$(DSSAT_SUMMARY)" "location=$(LOCATION)" "crop=$(CROP)" \
					"season-start=$(SEASON_START)" "season-end=$(SEASON_END)" \
					"season-length=$(SEASON_LENGTH_MONTHS)" "lead-months=$(LEAD_MONTHS)" \
					"rainfall-source=$(ADVISORY_RAINFALL_SOURCE)" \
				--outputs "$(ADVISORY_OUTPUT)"; \
		else \
			echo "Advisory failed; checkpoint was not written." >&2; \
			exit 1; \
		fi; \
	else \
		echo "Reusing completed IWMI advisory checkpoint. Use FORCE=1 to refresh."; \
	fi

workflow:
	$(MAKE) forecast
	$(MAKE) advisory

status:
	@$(PYTHON) integration/workflow_state.py check \
		--state "$(CHECKPOINT)" \
		--inputs "$(USECASE_CONFIG)" "season-year=$(SEASON_YEAR)" "n-cores=$(AGWISE_N_CORES)" \
		--outputs "$(DSSAT_SUMMARY)" || exit 0
	@$(PYTHON) integration/workflow_state.py check \
		--state "$(ADVISORY_CHECKPOINT)" \
		--inputs "$(DSSAT_SUMMARY)" "location=$(LOCATION)" "crop=$(CROP)" \
			"season-start=$(SEASON_START)" "season-end=$(SEASON_END)" \
			"season-length=$(SEASON_LENGTH_MONTHS)" "lead-months=$(LEAD_MONTHS)" \
			"rainfall-source=$(ADVISORY_RAINFALL_SOURCE)" \
		--outputs "$(ADVISORY_OUTPUT)" || exit 0

invalidate:
	@echo "Use FORCE=1 with make forecast, make advisory, or make workflow to refresh outputs."

clean-python-cache:
	$(PYTHON) -c "import pathlib; [p.unlink() for p in pathlib.Path('.').rglob('*.pyc')]"
