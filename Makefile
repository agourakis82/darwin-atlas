.PHONY: all setup sounio julia test cross-validate pipeline reproduce clean help epistemic export-knowledge verify-knowledge snapshot snapshot-full snapshot-zip atlas query

JULIA := julia --project=julia
SOUNIO ?= souc

# Default target
all: setup sounio julia test

help:
	@echo "DSLG Atlas - Sounio Operator Symmetry Atlas - Build System v2.0"
	@echo ""
	@echo "Primary Targets:"
	@echo "  atlas          Run unified Atlas pipeline (Parquet + CSV)"
	@echo "  query          Query Atlas dataset with SQL"
	@echo "  epistemic      Export + verify epistemic Knowledge layer"
	@echo "  snapshot       Build dataset snapshot for Zenodo/DOI"
	@echo ""
	@echo "Build Targets:"
	@echo "  setup          Install dependencies"
	@echo "  test           Run all tests"
	@echo "  pipeline       Legacy pipeline (CSV only)"
	@echo "  clean          Remove build artifacts"
	@echo ""
	@echo "Parameters:"
	@echo "  MAX=N          Maximum genomes (default: 200)"
	@echo "  SCALE=N        Scale target (overrides MAX)"
	@echo "  SEED=N         Random seed (default: 42)"
	@echo "  QUERY=\"SQL\"    SQL query for query target"
	@echo ""
	@echo "Examples:"
	@echo "  make atlas MAX=50 SEED=42           # Fast gate (50 replicons)"
	@echo "  make atlas MAX=200 SEED=42          # Medium gate"
	@echo "  make atlas SCALE=10000 SEED=42      # Scale run"
	@echo "  make query QUERY=\"SELECT * FROM atlas_replicons LIMIT 10\""
	@echo "  make epistemic MAX=50 SEED=42       # Export Knowledge layer"
	@echo "  make snapshot MAX=200 SEED=42       # Build Zenodo snapshot"

# Setup
setup: setup-julia setup-sounio

setup-julia:
	@echo "Installing Julia dependencies..."
	$(JULIA) -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

setup-sounio:
	@echo "Setting up Sounio..."
	@if command -v $(SOUNIO) >/dev/null 2>&1; then \
		echo "Sounio compiler found: $$($(SOUNIO) --version)"; \
		cd sounio && $(SOUNIO) build --release --target=cdylib || echo "Build failed, will retry during sounio target"; \
	else \
		echo "Sounio compiler not found (expected 'souc') - skipping"; \
		echo "Install from: https://github.com/sounio-lang/sounio"; \
		echo "After installation, add to PATH: export PATH=\"/path/to/sounio/compiler/target/release:\$$PATH\""; \
	fi

# Build targets
sounio:
	@echo "Building Sounio kernels..."
	@if command -v $(SOUNIO) >/dev/null 2>&1; then \
		echo "Using Sounio compiler: $$($(SOUNIO) --version)"; \
		cd sounio && \
		mkdir -p target/release && \
		if $(SOUNIO) build --cdylib src/lib.sio -O 3 -o target/release/libdarwin_kernels.so 2>&1; then \
			echo "✅ Sounio kernels built successfully"; \
			ls -lh target/release/libdarwin_kernels.* 2>/dev/null || echo "⚠️  Library file not found"; \
		else \
			echo "⚠️  Build failed - LLVM backend may not be enabled"; \
			echo "   To fix: cd /home/maria/sounio/compiler && cargo build --release --features llvm"; \
			echo "   Then retry: make sounio"; \
			echo "   Note: Darwin Atlas works without Sounio (Julia-only mode)"; \
		fi; \
	else \
		echo "⚠️  Sounio compiler not found (expected 'souc') - skipping"; \
		echo "   Install from: https://github.com/sounio-lang/sounio"; \
		echo "   After installation, add to PATH or set SOUNIO=/path/to/souc"; \
		echo "   Note: Darwin Atlas works without Sounio (Julia-only mode)"; \
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
		cd sounio && $(SOUNIO) test; \
	else \
		echo "Sounio compiler not found (expected 'souc') - skipping"; \
		echo "Install from: https://github.com/sounio-lang/sounio"; \
	fi

# Cross-validation
cross-validate: sounio julia
	@echo "Running cross-validation..."
	$(JULIA) julia/scripts/cross_validation.jl

# =============================================================================
# Pipeline Parameters
# =============================================================================

MAX ?= 200
SEED ?= 42
SCALE ?= 0
QUERY ?= SELECT * FROM atlas_replicons LIMIT 10
PIPELINE_MAX_VALUE := $(if $(filter 0,$(SCALE)),$(MAX),$(SCALE))

# =============================================================================
# Atlas Pipeline v2 (Parquet + CSV + DuckDB)
# =============================================================================

# Unified Atlas command - produces Parquet partitions + CSV views
atlas: setup
	@echo "Running DSLG Atlas pipeline v2..."
	@if [ "$(SCALE)" -gt 0 ]; then \
		$(JULIA) julia/scripts/run_atlas.jl --scale $(SCALE) --seed $(SEED); \
	else \
		$(JULIA) julia/scripts/run_atlas.jl --max $(MAX) --seed $(SEED); \
	fi
	@$(MAKE) epistemic MAX=$(MAX) SCALE=$(SCALE) SEED=$(SEED)

# Query Atlas dataset with DuckDB SQL
query:
	@echo "Querying Atlas dataset..."
	$(JULIA) julia/scripts/query_atlas.jl "$(QUERY)"

# Query with example
query-example:
	$(JULIA) julia/scripts/query_atlas.jl --example $(EXAMPLE)

# List available example queries
query-examples:
	$(JULIA) julia/scripts/query_atlas.jl --list-examples

# Show schema
query-schema:
	$(JULIA) julia/scripts/query_atlas.jl --schema

# =============================================================================
# Legacy Pipeline (CSV only)
# =============================================================================

pipeline: setup
	@echo "Running legacy pipeline (CSV only)..."
	$(JULIA) julia/scripts/run_pipeline.jl --max-genomes $(MAX) --seed $(SEED)

# Validation only
validate:
	$(JULIA) julia/scripts/run_pipeline.jl --validate-only

# Reproducibility check
reproduce: clean all pipeline
	@echo "Verifying checksums..."
	cd data/manifest && sha256sum -c checksums.sha256

# =============================================================================
# Epistemic Knowledge Layer (Sounio L0 integration)
# =============================================================================

# Export Atlas tables to Knowledge JSONL
export-knowledge:
	@echo "Exporting epistemic Knowledge layer..."
	@mkdir -p data/epistemic
	PIPELINE_MAX=$(PIPELINE_MAX_VALUE) PIPELINE_SEED=$(SEED) $(JULIA) julia/scripts/export_knowledge.jl

# Verify Knowledge JSONL against Sounio schema
verify-knowledge:
	@echo "Verifying epistemic Knowledge layer..."
	@if command -v $(SOUNIO) >/dev/null 2>&1; then \
		$(SOUNIO) run sounio/src/verify_knowledge.sio -- \
			data/epistemic/atlas_knowledge.jsonl \
			data/epistemic/atlas_knowledge_report.md; \
		if [ -f dist/atlas_dataset_v2/epistemic/atlas_knowledge.jsonl ]; then \
			$(SOUNIO) run sounio/src/verify_knowledge.sio -- \
				dist/atlas_dataset_v2/epistemic/atlas_knowledge.jsonl \
				dist/atlas_dataset_v2/epistemic/atlas_knowledge_report.md; \
		fi; \
	else \
		echo "Sounio compiler not found (expected 'souc') - using Julia fallback"; \
		$(JULIA) julia/scripts/verify_knowledge.jl; \
	fi

# Full epistemic pipeline: ensure tables exist, export, verify
epistemic: export-knowledge verify-knowledge
	@echo "Epistemic Knowledge layer complete"
	@echo "  JSONL: data/epistemic/atlas_knowledge.jsonl"
	@echo "  Report: data/epistemic/atlas_knowledge_report.md"
	@if [ -f dist/atlas_dataset_v2/epistemic/atlas_knowledge.jsonl ]; then \
		echo "  JSONL: dist/atlas_dataset_v2/epistemic/atlas_knowledge.jsonl"; \
		echo "  Report: dist/atlas_dataset_v2/epistemic/atlas_knowledge_report.md"; \
	fi

# Epistemic with pipeline (run full analysis first if tables missing)
epistemic-full:
	@if [ ! -f dist/atlas_dataset_v2/csv/atlas_replicons.csv ] && [ ! -f data/tables/atlas_replicons.csv ]; then \
		echo "Tables not found, running atlas first..."; \
		$(MAKE) atlas MAX=$(MAX) SCALE=$(SCALE) SEED=$(SEED); \
	else \
		$(MAKE) epistemic MAX=$(MAX) SCALE=$(SCALE) SEED=$(SEED); \
	fi

# =============================================================================
# Snapshot Builder (for Zenodo/DOI)
# =============================================================================

# Build deterministic dataset snapshot v2
# Usage: make snapshot MAX=50 SEED=42
snapshot:
	@echo "Building dataset snapshot v2..."
	@./scripts/make_snapshot.sh $(MAX) $(SEED)

# Build snapshot with full pipeline (if tables missing)
snapshot-full:
	@if [ ! -f dist/atlas_dataset_v2/csv/atlas_replicons.csv ]; then \
		echo "Dataset not found, running atlas first..."; \
		$(MAKE) atlas MAX=$(MAX) SCALE=$(SCALE) SEED=$(SEED); \
	fi
	$(MAKE) snapshot MAX=$(MAX) SEED=$(SEED)

# Create zip archive for Zenodo upload
snapshot-zip: snapshot
	@echo "Creating zip archive..."
	@cd dist && zip -r atlas_snapshot_v2.zip atlas_snapshot_v2/
	@echo "Archive created: dist/atlas_snapshot_v2.zip"

# =============================================================================
# Clean
# =============================================================================

clean:
	@echo "Cleaning build artifacts..."
	rm -rf data/tables/*.csv
	rm -rf data/manifest/*.jsonl
	rm -rf sounio/target
	rm -rf julia/Manifest.toml

cleanall: clean
	@echo "Cleaning all data..."
	rm -rf data/raw/*
	rm -rf dist/atlas_dataset_v2

cleandist:
	@echo "Cleaning dist directory..."
	rm -rf dist/*
