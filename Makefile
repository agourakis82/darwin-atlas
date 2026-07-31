.PHONY: all help status contract setup-julia julia test test-julia \
	sounio sounio-fixture operator-differential-fixture compile-sounio-fixture \
	sounio-fasta-fixture fasta-differential-fixture \
	cross-validate pipeline release-gate \
	legacy-julia-pipeline legacy-export-knowledge legacy-verify-knowledge clean

JULIA ?= julia --project=julia
SOUNIO_REPO ?=
SOUNIO_LIMA_INSTANCE ?=
MAX ?= 200
SEED ?= 42

# Development checks only. Publication eligibility is controlled by release-gate.
all: contract test-julia

help:
	@echo "Darwin Operator Symmetry Atlas"
	@echo ""
	@echo "Sounio is the canonical producer; Julia is an independent validator."
	@echo ""
	@echo "Targets:"
	@echo "  status                  Show toolchain and migration status"
	@echo "  contract                Check normative docs and JSON contracts"
	@echo "  test-julia              Run validator-development tests"
	@echo "  sounio-fixture          Check, compile, and execute the pinned official Sounio fixture"
	@echo "  operator-differential-fixture  Sounio artifact + independent Base-only Julia check"
	@echo "  sounio-fasta-fixture    Execute streaming/IUPAC FASTA fixtures in pinned Sounio"
	@echo "  fasta-differential-fixture  Sounio FASTA artifact + independent Base-only Julia check"
	@echo "  cross-validate          Fail-closed Sounio/Julia diagnostic comparison"
	@echo "  pipeline                Canonical Sounio pipeline (blocked until implemented)"
	@echo "  release-gate            Full publication gate (red until pipeline is ready)"
	@echo "  legacy-julia-pipeline   Run noncanonical historical Julia pipeline"
	@echo "  clean                   Remove generated build/table artifacts; preserve manifests"

status:
	@echo "Specification: 0.1.0 (normative draft)"
	@echo "Canonical producer: Sounio"
	@echo "Independent validator: Julia"
	@if [ -n "$(SOUNIO_REPO)" ] && [ -x "$(SOUNIO_REPO)/bin/souc" ]; then \
		echo "Sounio repository: $(SOUNIO_REPO)"; \
		echo "Sounio commit: $$(git -C "$(SOUNIO_REPO)" rev-parse HEAD)"; \
	else \
		echo "Sounio repository: NOT CONFIGURED (set SOUNIO_REPO)"; \
	fi
	@if command -v julia >/dev/null 2>&1; then julia --version; else echo "Julia: MISSING"; fi
	@if command -v datasets >/dev/null 2>&1; then datasets --version; else echo "NCBI Datasets CLI: MISSING"; fi
	@echo "Canonical pipeline: BLOCKED (FASTA fixture exists; operator/writer integration absent)"

contract:
	@test -s docs/SCIENTIFIC_SPEC.md
	@test -s docs/ADR-0001-sounio-primary-julia-validator.md
	@test -s schemas/run_receipt.schema.json
	@test -s toolchains/sounio.lock.json
	@test -s sounio/src/operator_fixture.sio
	@test -s sounio/src/fasta_stream_fixture.sio
	@test -s julia/scripts/validate_operator_fixture.jl
	@test -s julia/scripts/validate_fasta_fixture.jl
	@test -x scripts/run_sounio_fasta_fixture.sh
	@test -x scripts/run_fasta_differential_fixture.sh
	@for f in valid_multi_record invalid_symbol sequence_before_header empty_header empty_sequence no_records; do test -s "data/fixtures/fasta/$$f.fa"; done
	@test "$$(wc -c < data/fixtures/fasta/valid_multi_record.fa)" -gt 17
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/run_receipt.schema.json")); abort "producer must be Sounio" unless s.dig("properties","producer","properties","language","const")=="Sounio"; abort "validator must be Julia" unless s.dig("properties","validator","oneOf",1,"properties","language","const")=="Julia"'
	@ruby -rjson -e 's=JSON.parse(File.read("toolchains/sounio.lock.json")); abort "wrong official remote" unless s.fetch("repository")=="https://github.com/sounio-lang/sounio.git"; abort "invalid Sounio commit" unless s.fetch("commit").match?(/\A[0-9a-f]{40}\z/)'
	@! rg -n "Running Julia-only validation instead" julia/scripts/cross_validation.jl
	@! rg -n "rm -rf julia/[M]anifest.toml" Makefile
	@echo "Contract checks passed"

setup-julia:
	$(JULIA) -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

julia:
	$(JULIA) -e 'using Pkg; Pkg.build()'

test: contract test-julia

test-julia:
	@echo "Running Julia validator-development tests (not a production receipt)..."
	$(JULIA) -e 'using Pkg; Pkg.test()'

# Uses only the exact official repository/commit in toolchains/sounio.lock.json.
# On Apple Silicon, pass SOUNIO_LIMA_INSTANCE=souc-linux for Linux x86-64 Madaros.
sounio-fixture:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_sounio_fixture.sh

sounio: sounio-fixture sounio-fasta-fixture
compile-sounio-fixture: sounio-fixture

operator-differential-fixture:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_operator_differential_fixture.sh

sounio-fasta-fixture:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_sounio_fasta_fixture.sh

fasta-differential-fixture:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_fasta_differential_fixture.sh

# Development-only FFI comparison. The publication gate will compare persisted
# Sounio artifacts after the canonical producer exists.
cross-validate: julia
	@echo "Running fail-closed Sounio/Julia comparison diagnostic..."
	$(JULIA) julia/scripts/cross_validation.jl

pipeline:
	@echo "BLOCKED: the streaming FASTA fixture is not yet integrated with operators and a deterministic artifact writer."
	@echo "See docs/SCIENTIFIC_SPEC.md sections 3, 11, and 13."
	@exit 2

release-gate: contract pipeline cross-validate
	@echo "Release gate passed"

# Explicit legacy target retained for migration diagnostics. Its artifacts are
# noncanonical and MUST NOT be used in a release receipt.
legacy-julia-pipeline: setup-julia
	@echo "WARNING: running NONCANONICAL historical Julia pipeline"
	$(JULIA) julia/scripts/run_pipeline.jl --max-genomes $(MAX) --seed $(SEED)

legacy-export-knowledge:
	@echo "WARNING: exporting legacy, noncanonical Julia-derived Knowledge records"
	@mkdir -p data/epistemic
	PIPELINE_MAX=$(MAX) PIPELINE_SEED=$(SEED) $(JULIA) julia/scripts/export_knowledge.jl

legacy-verify-knowledge:
	@echo "WARNING: validating legacy schema with Julia; this is not Sounio cross-validation"
	$(JULIA) julia/scripts/verify_knowledge.jl

clean:
	@echo "Removing generated build and table artifacts; preserving manifests and julia/Manifest.toml..."
	rm -f data/tables/*.csv
	rm -rf demetrios/target
