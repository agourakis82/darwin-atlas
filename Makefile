.PHONY: all setup demetrios julia test cross-validate pipeline reproduce clean help

JULIA := julia --project=julia
DEMETRIOS := dc

# Default target
all: setup demetrios julia test

help:
	@echo "Darwin Operator Symmetry Atlas - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  setup          Install dependencies"
	@echo "  demetrios      Build Demetrios kernels"
	@echo "  julia          Build Julia package"
	@echo "  test           Run all tests"
	@echo "  cross-validate Run Demetrios vs Julia validation"
	@echo "  pipeline       Run full analysis pipeline"
	@echo "  reproduce      Clean + rebuild + verify checksums"
	@echo "  clean          Remove build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  make all                 # Full build"
	@echo "  make test                # Run tests only"
	@echo "  make pipeline MAX=50     # Run pipeline with 50 genomes"

# Setup
setup: setup-julia setup-demetrios

setup-julia:
	@echo "Installing Julia dependencies..."
	$(JULIA) -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

setup-demetrios:
	@echo "Setting up Demetrios..."
	@if command -v dc >/dev/null 2>&1; then \
		cd demetrios && dc build; \
	else \
		echo "Demetrios compiler (dc) not found - skipping"; \
	fi

# Build targets
demetrios:
	@echo "Building Demetrios kernels..."
	@if command -v dc >/dev/null 2>&1; then \
		cd demetrios && dc build --release --target=cdylib; \
	else \
		echo "Demetrios compiler (dc) not found - skipping"; \
	fi

julia:
	@echo "Building Julia package..."
	$(JULIA) -e 'using Pkg; Pkg.build()'

# Test targets
test: test-julia test-demetrios

test-julia:
	@echo "Running Julia tests..."
	$(JULIA) -e 'using Pkg; Pkg.test()'

test-demetrios:
	@echo "Running Demetrios tests..."
	@if command -v dc >/dev/null 2>&1; then \
		cd demetrios && dc test; \
	else \
		echo "Demetrios compiler (dc) not found - skipping"; \
	fi

# Cross-validation
cross-validate: demetrios julia
	@echo "Running cross-validation..."
	$(JULIA) julia/scripts/cross_validation.jl

# Pipeline
MAX ?= 200
SEED ?= 42

pipeline: setup
	@echo "Running analysis pipeline..."
	$(JULIA) julia/scripts/run_pipeline.jl --max-genomes $(MAX) --seed $(SEED)

# Validation only
validate:
	$(JULIA) julia/scripts/run_pipeline.jl --validate-only

# Reproducibility check
reproduce: clean all pipeline
	@echo "Verifying checksums..."
	cd data/manifest && sha256sum -c checksums.sha256

# Clean
clean:
	@echo "Cleaning build artifacts..."
	rm -rf data/tables/*.csv
	rm -rf data/manifest/*.jsonl
	rm -rf demetrios/target
	rm -rf julia/Manifest.toml

cleanall: clean
	@echo "Cleaning all data..."
	rm -rf data/raw/*
