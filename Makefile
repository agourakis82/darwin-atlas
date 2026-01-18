.PHONY: all setup sounio julia test cross-validate pipeline reproduce clean help epistemic export-knowledge verify-knowledge

JULIA := julia --project=julia
SOUNIO := souc

# Default target
all: setup sounio julia test

help:
	@echo "Darwin Operator Symmetry Atlas - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  setup          Install dependencies"
	@echo "  sounio         Build Sounio kernels"
	@echo "  julia          Build Julia package"
	@echo "  test           Run all tests"
	@echo "  cross-validate Run Sounio vs Julia validation"
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
setup: setup-julia setup-sounio

setup-julia:
	@echo "Installing Julia dependencies..."
	$(JULIA) -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

setup-sounio:
	@echo "Setting up Sounio..."
	@if command -v $(SOUNIO) >/dev/null 2>&1; then \
		cd sounio && $(SOUNIO) check src/operators.sio && \
		$(SOUNIO) check src/exact_symmetry.sio && \
		$(SOUNIO) check src/approx_metric.sio && \
		echo "Sounio setup complete"; \
	else \
		echo "Sounio compiler (souc) not found - skipping"; \
	fi

# Build targets
sounio:
	@echo "Checking Sounio kernels..."
	@if command -v $(SOUNIO) >/dev/null 2>&1; then \
		cd sounio && $(SOUNIO) check src/operators.sio && \
		$(SOUNIO) check src/exact_symmetry.sio && \
		$(SOUNIO) check src/approx_metric.sio && \
		echo "Sounio kernels verified"; \
	else \
		echo "Sounio compiler (souc) not found - skipping"; \
	fi

julia:
	@echo "Building Julia package..."
	$(JULIA) -e 'using Pkg; Pkg.build()'

# Test targets
test: test-julia test-sounio

test-julia:
	@echo "Running Julia tests..."
	$(JULIA) -e 'using Pkg; Pkg.test()'

test-sounio:
	@echo "Running Sounio tests..."
	@if command -v $(SOUNIO) >/dev/null 2>&1; then \
		cd sounio && $(SOUNIO) run src/test_simple.sio && \
		$(SOUNIO) run src/test_operators_only.sio && \
		echo "Sounio tests passed"; \
	else \
		echo "Sounio compiler not found - skipping"; \
	fi

# Cross-validation
cross-validate: sounio julia
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
	rm -rf sounio/target
	rm -rf julia/Manifest.toml

cleanall: clean
	@echo "Cleaning all data..."
	rm -rf data/raw/*

# =============================================================================
# Epistemic Knowledge Layer (Sounio L0 integration)
# =============================================================================

# Export Atlas tables to Knowledge JSONL
export-knowledge:
	@echo "Exporting epistemic Knowledge layer..."
	@mkdir -p data/epistemic
	PIPELINE_MAX=$(MAX) PIPELINE_SEED=$(SEED) $(JULIA) julia/scripts/export_knowledge.jl

# Verify Knowledge JSONL against Sounio schema
verify-knowledge:
	@echo "Verifying epistemic Knowledge layer..."
	@if command -v $(SOUNIO) >/dev/null 2>&1; then \
		$(SOUNIO) run sounio/src/verify_knowledge.sio -- \
			data/epistemic/atlas_knowledge.jsonl \
			data/epistemic/atlas_knowledge_report.md; \
	else \
		echo "Sounio compiler not found - using Julia fallback"; \
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
