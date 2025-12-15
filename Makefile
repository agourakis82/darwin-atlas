.PHONY: all setup demetrios julia test cross-validate pipeline reproduce clean help epistemic export-knowledge verify-knowledge

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
	@echo "  epistemic      Export + verify epistemic Knowledge layer"
	@echo "  reproduce      Clean + rebuild + verify checksums"
	@echo "  clean          Remove build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  make all                 # Full build"
	@echo "  make test                # Run tests only"
	@echo "  make pipeline MAX=50     # Run pipeline with 50 genomes"
	@echo "  make epistemic MAX=50    # Export + validate Knowledge layer"

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

# =============================================================================
# Epistemic Knowledge Layer (Demetrios L0 integration)
# =============================================================================

# Export Atlas tables to Knowledge JSONL
export-knowledge:
	@echo "Exporting epistemic Knowledge layer..."
	@mkdir -p data/epistemic
	PIPELINE_MAX=$(MAX) PIPELINE_SEED=$(SEED) $(JULIA) julia/scripts/export_knowledge.jl

# Verify Knowledge JSONL against Demetrios schema
verify-knowledge:
	@echo "Verifying epistemic Knowledge layer..."
	@if command -v dc >/dev/null 2>&1; then \
		dc run demetrios/src/verify_knowledge.d -- \
			data/epistemic/atlas_knowledge.jsonl \
			data/epistemic/atlas_knowledge_report.md; \
	else \
		echo "Demetrios compiler (dc) not found - using Julia fallback"; \
		$(JULIA) julia/scripts/verify_knowledge.jl; \
	fi

# Full epistemic pipeline: ensure tables exist, export, verify
epistemic: export-knowledge verify-knowledge
	@echo "Epistemic Knowledge layer complete"
	@echo "  JSONL: data/epistemic/atlas_knowledge.jsonl"
	@echo "  Report: data/epistemic/atlas_knowledge_report.md"

# Epistemic with pipeline (run full analysis first if tables missing)
epistemic-full:
	@if [ ! -f data/tables/atlas_replicons.csv ]; then \
		echo "Tables not found, running pipeline first..."; \
		$(MAKE) pipeline MAX=$(MAX) SEED=$(SEED); \
	fi
	$(MAKE) epistemic MAX=$(MAX) SEED=$(SEED)
