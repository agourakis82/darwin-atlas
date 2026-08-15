.PHONY: all help status contract setup-julia julia test test-julia \
	sounio sounio-fixture operator-differential-fixture compile-sounio-fixture \
	sounio-fasta-fixture fasta-differential-fixture \
	sounio-mini-pipeline mini-pipeline-differential-fixture \
	metamorphic-differential-fixture null-metamorphic-differential-fixture \
	null-quality-differential-fixture \
	cohort-smoke-differential \
	cohort-products \
	u250-smoke-contract u250-null-contract u250-dinucleotide-contract \
	u0-contract u0-schema-integration u0-cli-integration u0-julia-contract \
	u0-manifest-differential-fixture u0-dinucleotide-scale-fixture u0-gate \
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
	@echo "  sounio-mini-pipeline    Run frozen FASTA+metadata mini-pipeline in pinned Sounio"
	@echo "  mini-pipeline-differential-fixture  Sounio JSONL (including engineering nulls) + Base-only Julia check"
	@echo "  metamorphic-differential-fixture  Spec 12.1 metamorphic properties in Sounio + independent Julia oracle"
	@echo "  null-metamorphic-differential-fixture  Metamorphic relations MR1-MR4 around both null engines + Julia byte-exact check"
	@echo "  null-quality-differential-fixture  Null-generator quality: exact support + chi-square uniformity (alpha=1e-3) for both engines"
	@echo "  cohort-smoke-differential  Complete-replicon engineering smoke + Julia byte-exact check"
	@echo "  cohort-products         Engineering canonical products + Julia byte-exact checks"
	@echo "  u250-smoke-contract     Validate the engineering U250 hardware-smoke scaffold"
	@echo "  u250-null-contract      Validate Julia/HLS exact null-draw fixtures"
	@echo "  u250-dinucleotide-contract  Validate exact Euler/Wilson Sounio/Julia/HLS fixture"
	@echo "  u0-contract             Validate DOSA v3 U0 contracts and fixture-only fail-closed gates"
	@echo "  u0-schema-integration  Meta-validate v3 schemas (requires Python jsonschema)"
	@echo "  u0-cli-integration     Exercise DuckDB/Zstd package, query and verify integration"
	@echo "  u0-julia-contract      Run independent U0 manifest and secondary-gate validators"
	@echo "  u0-manifest-differential-fixture  Pinned Sounio manifest boundary + independent Julia"
	@echo "  u0-dinucleotide-scale-fixture  Euler/Wilson draws + nested v3 profiles (16..1000) + Julia"
	@echo "  u0-gate                Fail-closed U0 evaluator; real promotion remains explicitly locked"
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
	@echo "Canonical pipeline: BLOCKED (mini-pipeline fixture exists; full cohort/receipt integration absent)"

contract:
	@test -s docs/SCIENTIFIC_SPEC.md
	@test -s docs/NOVELTY_AUDIT.md
	@test -s docs/ADR-0001-sounio-primary-julia-validator.md
	@test -s docs/ADR-0002-pilot-parameter-decisions.md
	@test -s docs/ADR-0003-dinucleotide-null-engineering-contract.md
	@test -s schemas/run_receipt.schema.json
	@test -s schemas/u250_hardware_smoke_receipt.schema.json
	@test -s schemas/u250_null_draw_receipt.schema.json
	@test -s schemas/u250_dinucleotide_null_receipt.schema.json
	@test -s schemas/dinucleotide_null_parameters.schema.json
	@test -s schemas/novelty_claims.schema.json
	@test -s data/novelty/claims.json
	@test -s receipts/u250-smoke-659ab549-20260803T022116Z/u250_smoke_receipt.json
	@test -s fpga/u250-null-model/src/null_draws.cpp
	@test -s fpga/u250-null-model/generated_fixture.hpp
	@test -s fpga/u250-null-model/kubernetes/null-draw-pod.yaml
	@test -x fpga/u250-null-model/verify-fixture.sh
	@test -s sounio/src/dinucleotide_null_fixture.sio
	@test -x scripts/generate_dinucleotide_cases.rb
	@test -x scripts/run_dinucleotide_null_differential.sh
	@test -x julia/scripts/validate_dinucleotide_null.jl
	@test -x fpga/u250-dinucleotide-null/verify-fixture.sh
	@test -s fpga/u250-dinucleotide-null/src/host_throughput.cpp
	@test -s fpga/u250-dinucleotide-null/kubernetes/throughput-pod.yaml
	@test -s fpga/u250-dinucleotide-null/THROUGHPUT_PROBE.md
	@test -s data/fixtures/dinucleotide_null/SHA256SUMS
	@cd data/fixtures/dinucleotide_null && (sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS)
	@test -s sounio/src/null_quality_fixture.sio
	@test -x scripts/generate_null_quality_cases.rb
	@test -x scripts/run_null_quality_differential.sh
	@test -x julia/scripts/validate_null_quality.jl
	@rg -q 'NULL_QUALITY_DIFFERENTIAL_PASS' scripts/run_null_quality_differential.sh
	@test -s data/fixtures/null_quality/parameters.json
	@test -s data/fixtures/null_quality/case_templates.tsv
	@test -s data/fixtures/null_quality/cases.tsv
	@test -s data/fixtures/null_quality/README.md
	@test -s data/fixtures/null_quality/SHA256SUMS
	@cd data/fixtures/null_quality && (sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS)
	@tmp=$$(mktemp); trap 'rm -f "$$tmp"' EXIT; ruby scripts/generate_null_quality_cases.rb data/fixtures/null_quality/parameters.json data/fixtures/null_quality/case_templates.tsv "$$tmp"; cmp "$$tmp" data/fixtures/null_quality/cases.tsv
	@test -s toolchains/sounio.lock.json
	@test -s fpga/u250-smoke/src/vector_add.cpp
	@test -s fpga/u250-smoke/src/host.cpp
	@test -s fpga/u250-smoke/vector_add.cfg
	@test -x fpga/u250-smoke/build.sh
	@test -x fpga/u250-smoke/compile-host.sh
	@test -x fpga/u250-smoke/run-hardware.sh
	@test -s fpga/u250-smoke/kubernetes/smoke-pod.yaml
	@test -s sounio/src/operator_fixture.sio
	@test -s sounio/src/fasta_stream_fixture.sio
	@test -s julia/scripts/validate_operator_fixture.jl
	@test -s julia/scripts/validate_fasta_fixture.jl
	@test -s julia/scripts/validate_mini_pipeline.jl
	@test -s schemas/window_operator_profile.schema.json
	@test -x scripts/run_sounio_fasta_fixture.sh
	@test -x scripts/run_fasta_differential_fixture.sh
	@test -x scripts/run_sounio_mini_pipeline.sh
	@test -x scripts/run_mini_pipeline_differential.sh
	@test -s sounio/src/metamorphic_fixture.sio
	@test -x scripts/run_sounio_metamorphic_fixture.sh
	@test -x scripts/run_metamorphic_differential_fixture.sh
	@test -s julia/scripts/validate_metamorphic_fixture.jl
	@test -x scripts/run_sounio_null_metamorphic.sh
	@test -x scripts/run_null_metamorphic_differential.sh
	@test -s julia/scripts/validate_null_metamorphic.jl
	@test -s data/fixtures/null_metamorphic/README.md
	@test -s data/fixtures/null_metamorphic/SHA256SUMS
	@for f in nullmeta_fixture.fa nullmeta_metadata.tsv dinucleotide_seeds_nullmeta_k8.tsv; do test -s "data/fixtures/null_metamorphic/$$f"; done
	@for f in parameters_nullmeta_mono_k8 parameters_nullmeta_dinuc_k8; do test -s "data/fixtures/null_metamorphic/$$f.json"; done
	@cd data/fixtures/null_metamorphic && (sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS)
	@tmp=$$(mktemp); trap 'rm -f "$$tmp"' EXIT; ruby scripts/generate_dinucleotide_seed_sidecar.rb data/fixtures/null_metamorphic/parameters_nullmeta_dinuc_k8.json data/fixtures/null_metamorphic/nullmeta_fixture.fa data/fixtures/null_metamorphic/nullmeta_metadata.tsv "$$tmp"; cmp "$$tmp" data/fixtures/null_metamorphic/dinucleotide_seeds_nullmeta_k8.tsv
	@test -x scripts/generate_dinucleotide_seed_sidecar.rb
	@for f in valid_multi_record invalid_symbol sequence_before_header empty_header empty_sequence no_records; do test -s "data/fixtures/fasta/$$f.fa"; done
	@test "$$(wc -c < data/fixtures/fasta/valid_multi_record.fa)" -gt 17
	@test -s data/fixtures/mini_pipeline/pipeline_fixture.fa
	@test -s data/fixtures/mini_pipeline/pipeline_k8_fixture.fa
	@test -s data/fixtures/mini_pipeline/SHA256SUMS
	@for f in pipeline_metadata pipeline_k8_metadata metadata_invalid metadata_mismatch metadata_short; do test -s "data/fixtures/mini_pipeline/$$f.tsv"; done
	@for f in parameters_k4 parameters_k8 parameters_null_k4 parameters_null_k8 parameters_dinucleotide_k4 parameters_dinucleotide_k8; do test -s "data/fixtures/mini_pipeline/$$f.json"; done
	@for f in dinucleotide_seeds_k4 dinucleotide_seeds_k8; do test -s "data/fixtures/mini_pipeline/$$f.tsv"; done
	@for f in window_size_zero stride_zero stride_mismatch k_min_two k_max_nine k_max_above_window unknown_policy extra_field null_model_unknown null_replicates_mismatch; do test -s "data/fixtures/mini_pipeline/params_invalid/$$f.json"; done
	@test -s schemas/pipeline_parameters.schema.json
	@test -s data/cohort/mini/cohort_manifest.jsonl
	@test -s data/cohort/mini/replicons.tsv
	@test -s data/cohort/mini/SHA256SUMS
	@test -s data/cohort/mini/ncbi_md5sum.txt
	@test -s data/cohort/mini/topology_locus.txt
	@test -s data/cohort/mini/assemblies/GCF_000005845.2/GCF_000005845.2_ASM584v2_genomic.fna
	@test -s data/cohort/mini/assemblies/GCF_000008865.2/GCF_000008865.2_ASM886v2_genomic.fna
	@cd data/cohort/mini && (sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS)
	@ruby -rjson -e 'rows=File.readlines("data/cohort/mini/cohort_manifest.jsonl",chomp:true).map{|l|JSON.parse(l)}; abort "cohort must have exactly 2 assemblies" unless rows.size==2; rows.each{|r| %w[assembly_accession_version taxid organism_name refseq_category assembly_level retrieval_utc datasets_version package_md5 included].each{|k| abort "cohort manifest missing #{k}" unless r.key?(k)}; abort "cohort assembly not included" unless r["included"]==true; abort "datasets version drift" unless r["datasets_version"]=="18.34.0"}'
	@ruby -e 'rows=File.readlines("data/cohort/mini/replicons.tsv",chomp:true); abort "replicons.tsv must have header + 4 rows" unless rows.size==5; abort "all mini replicons must be declared circular" unless rows.drop(1).all?{|l| l.split("\t")[4]=="circular"}; abort "replicon scope must be ncbi_complete_replicon" unless rows.drop(1).all?{|l| l.split("\t")[5]=="ncbi_complete_replicon"}'
	@cd data/cohort/mini && ruby -rdigest -e 'md5s=File.readlines("ncbi_md5sum.txt",chomp:true).map{|l| l.split}; md5s.each{|md5,rel| p=rel.sub(%r{\Ancbi_dataset/data/},""); parts=p.split("/"); target = if parts[0].start_with?("GCF_") then (parts[1].end_with?(".fna") ? "assemblies/#{parts[0]}/#{parts[1]}" : "sequence_report.#{parts[0]}.jsonl") else parts[-1] end; actual=Digest::MD5.file(target).hexdigest; abort "NCBI md5 mismatch: #{target}" unless actual==md5 }'
	@cd data/fixtures/mini_pipeline && (sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS)
	@tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; ruby scripts/generate_dinucleotide_seed_sidecar.rb data/fixtures/mini_pipeline/parameters_dinucleotide_k4.json data/fixtures/mini_pipeline/pipeline_fixture.fa data/fixtures/mini_pipeline/pipeline_metadata.tsv "$$tmp/k4.tsv"; ruby scripts/generate_dinucleotide_seed_sidecar.rb data/fixtures/mini_pipeline/parameters_dinucleotide_k8.json data/fixtures/mini_pipeline/pipeline_k8_fixture.fa data/fixtures/mini_pipeline/pipeline_k8_metadata.tsv "$$tmp/k8.tsv"; cmp "$$tmp/k4.tsv" data/fixtures/mini_pipeline/dinucleotide_seeds_k4.tsv; cmp "$$tmp/k8.tsv" data/fixtures/mini_pipeline/dinucleotide_seeds_k8.tsv
	@test -s data/fixtures/cohort_smoke/nc_002127_1.fa
	@test -s data/fixtures/cohort_smoke/nc_002127_1_metadata.tsv
	@test -s data/fixtures/cohort_smoke/parameters_k8.json
	@cd data/fixtures/cohort_smoke && (sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS)
	@ruby -rjson -e 'p=JSON.parse(File.read("data/fixtures/cohort_smoke/parameters_k8.json")); abort "cohort smoke parameters drifted" unless p["window_size"]==16 && p["stride"]==16 && p["k_min"]==1 && p["k_max"]==8 && p["min_kmer_effective_count"]==1'
	@ruby -e 'rows=File.readlines("data/fixtures/cohort_smoke/nc_002127_1_metadata.tsv",chomp:true); abort "smoke metadata must have header + 1 row" unless rows.size==2; f=rows[1].split("\t"); abort "smoke metadata drifted" unless f==["1","NC_002127.1","GCF_000008865.2","plasmid","circular","ncbi_complete_replicon"]'
	@ruby -e 'fa=File.readlines("data/fixtures/cohort_smoke/nc_002127_1.fa",chomp:true); abort "smoke FASTA header drifted" unless fa[0].start_with?(">NC_002127.1 "); seq=fa.drop(1).join; abort "smoke FASTA length drifted" unless seq.length==3306; abort "smoke FASTA alphabet drifted" unless seq.match?(/\A[ACGT]+\z/)'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/pipeline_parameters.schema.json")); abort "parameters schema must forbid extras" unless s.fetch("additionalProperties")==false; %w[schema_version specification_version window_size stride k_min k_max min_kmer_effective_count positional_ambiguity_policy kmer_ambiguity_policy coordinate_system window_wraparound output_order].each { |k| abort "parameters schema missing required #{k}" unless s.fetch("required").include?(k) }'
	@ruby -rjson -e 'p=JSON.parse(File.read("data/fixtures/mini_pipeline/parameters_k4.json")); abort "k4 fixture drifted" unless p["window_size"]==4 && p["stride"]==4 && p["k_min"]==1 && p["k_max"]==4 && p["min_kmer_effective_count"]==1'
	@ruby -rjson -e 'p=JSON.parse(File.read("data/fixtures/mini_pipeline/parameters_k8.json")); abort "k8 fixture drifted" unless p["window_size"]==16 && p["stride"]==16 && p["k_min"]==1 && p["k_max"]==8 && p["min_kmer_effective_count"]==1'
	@ruby -rjson -e 'p=JSON.parse(File.read("data/fixtures/mini_pipeline/parameters_null_k8.json")); abort "null k8 fixture drifted" unless p["window_size"]==16 && p["k_max"]==8 && p["null_model"]=="mononucleotide_shuffle" && p["null_replicates"]==8'
	@ruby -rjson -e '%w[k4 k8].each{|k| p=JSON.parse(File.read("data/fixtures/mini_pipeline/parameters_dinucleotide_#{k}.json")); abort "dinucleotide #{k} fixture drifted" unless p["null_model"]=="dinucleotide_shuffle" && p["null_replicates"]==8}; s=JSON.parse(File.read("schemas/pipeline_parameters.schema.json")); abort "null_model must be an optional enum" unless s.dig("properties","null_model","enum")==["none","mononucleotide_shuffle","dinucleotide_shuffle"] && !s.fetch("required").include?("null_model"); abort "null_replicates ceiling drifted" unless s.dig("properties","null_replicates","maximum")==1000'
	@grep -q "^const NULL_MAX_REPLICATES = 1000$$" julia/scripts/window_pipeline_core.jl || (echo "Julia null_replicates ceiling drifted" && exit 1)
	@grep -q "^const NULL_MAX_REPLICATES: i64 = 1000$$" sounio/src/fasta_stream_fixture.sio || (echo "Sounio null_replicates ceiling drifted" && exit 1)
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/window_operator_profile.schema.json")); abort "schema must fix canonical_only" unless s.dig("properties","ambiguity_policy","const")=="canonical_only"; abort "schema must fix window fields" unless s.fetch("required").include?("delta_RC") && s.fetch("additionalProperties")==false'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/window_operator_profile.schema.json")); abort "schema_version must be 0.3.0" unless s.dig("properties","schema_version","const")=="0.3.0"; abort "kmer policy must be masked" unless s.dig("properties","kmer_ambiguity_policy","const")=="masked"; abort "kmer min effective count must be an integer >= 1" unless s.dig("properties","kmer_min_effective_count","type")=="integer" && s.dig("properties","kmer_min_effective_count","minimum")==1; abort "parameters_sha256 must be a lowercase hex sha256" unless s.dig("properties","parameters_sha256","pattern")=="^[0-9a-f]{64}$$"; abort "required must cover k=1..8 with reasons, null summaries and 183 fields" unless s.fetch("required").size==183 && s.fetch("required").include?("rc_kmer_imbalance_8") && s.fetch("required").include?("kmer_8_unavailable_reason") && s.fetch("required").include?("parameters_sha256") && s.fetch("required").include?("null_model") && s.fetch("required").include?("null_replicates") && s.fetch("required").include?("null_seed_derivation") && s.fetch("required").include?("delta_R_null_mean") && s.fetch("required").include?("rc_kmer_imbalance_8_null_q975"); abort "additionalProperties must stay false" unless s.fetch("additionalProperties")==false'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/window_operator_profile.schema.json")); abort "dinucleotide model missing from output schema" unless s.dig("properties","null_model","enum").include?("dinucleotide_shuffle"); abort "dinucleotide seed derivation missing from output schema" unless s.dig("properties","null_seed_derivation","enum").include?("sha256_parameters_accession_window_first64be_v1")'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/run_receipt.schema.json")); abort "producer must be Sounio" unless s.dig("properties","producer","properties","language","const")=="Sounio"; abort "validator must be Julia" unless s.dig("properties","validator","oneOf",1,"properties","language","const")=="Julia"'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/novelty_claims.schema.json")); r=JSON.parse(File.read("data/novelty/claims.json")); abort "novelty registry version drift" unless r["schema_version"]=="0.1.0" && s.dig("properties","schema_version","const")=="0.1.0"; abort "scientific novelty must remain unestablished" unless r["scientific_novelty_established"]==false; abort "language authority drift" unless r["canonical_producer"]=="Sounio" && r["independent_validator"]=="Julia"; claims=r.fetch("claims"); abort "claim ids must be unique" unless claims.map{|c|c["claim_id"]}.uniq.size==claims.size; abort "claim registry must contain exactly NC-01..NC-09" unless claims.map{|c|c["claim_id"]}==(1..9).map{|i|"NC-%02d"%i}; abort "five rejected prior-art claims required" unless claims.count{|c|c["status"]=="rejected_by_prior_art"}==5; abort "no novelty claim is release eligible" unless claims.none?{|c|c["release_eligible"]}; abort "scientific targets must remain unvalidated" unless claims.select{|c|c["claim_type"]=="scientific" && c["status"]!="rejected_by_prior_art"}.all?{|c|c["status"]=="target_unvalidated"}; abort "engineering validation cannot imply scientific novelty" unless claims.select{|c|c["status"]=="engineering_validated_scope_limited"}.all?{|c|c["claim_type"]=="engineering"}; required=%w[doi:10.1093/bioinformatics/18.8.1021 doi:10.1371/journal.pone.0007553 doi:10.1186/s12864-016-3012-8 doi:10.1186/s12859-016-0905-0 doi:10.1093/oxfordjournals.molbev.a040370 doi:10.1186/1471-2105-9-192 doi:10.1093/bib/bbaa041]; ids=claims.flat_map{|c|c["closest_prior_art"].map{|p|p["persistent_id"]}}; abort "prior-art closure incomplete" unless (required-ids).empty?'
	@rg -q '^Novelty is not established by the current engineering receipts\.' docs/NOVELTY_AUDIT.md
	@rg -q 'Sounio-producer/Julia-validator contract' docs/NOVELTY_AUDIT.md
	@$(MAKE) --no-print-directory u250-smoke-contract
	@$(MAKE) --no-print-directory u250-null-contract
	@$(MAKE) --no-print-directory u250-dinucleotide-contract
	@$(MAKE) --no-print-directory u0-contract
	@ruby -rjson -rdigest -e 'id="engineering-products-b3682abb-20260801T203932Z"; r=JSON.parse(File.read("receipts/#{id}/run_receipt.json")); abort "engineering receipt must be validated" unless r["state"]=="validated"; v=r["validator"]; abort "receipt validator drift" unless v["language"]=="Julia" && v["status"]=="pass" && v["absolute_tolerance"]==0; abort "receipt commit must be a 40-hex sha" unless r.dig("atlas_source","commit").to_s.match?(/\A[0-9a-f]{40}\z/); abort "receipt must come from a clean tree" unless r.dig("atlas_source","dirty")==false; r["artifacts"].each{|a| p=a["path"].to_s; next unless p.include?("receipts/#{id}/"); f="receipts/#{id}/#{File.basename(p)}"; abort "receipt artifact missing #{f}" unless File.file?(f); abort "receipt sha256 mismatch #{f}" unless Digest::SHA256.file(f).hexdigest==a["sha256"] }'
	@ruby -rjson -rdigest -e 'id="engineering-products-8bbe89fd-20260802T144440Z"; r=JSON.parse(File.read("receipts/#{id}/run_receipt.json")); abort "release-tree engineering receipt must be validated" unless r["state"]=="validated"; v=r["validator"]; abort "release-tree receipt validator drift" unless v["language"]=="Julia" && v["status"]=="pass" && v["absolute_tolerance"]==0; abort "release-tree receipt commit must be a 40-hex sha" unless r.dig("atlas_source","commit").to_s.match?(/\A[0-9a-f]{40}\z/); abort "release-tree receipt must come from a clean tree" unless r.dig("atlas_source","dirty")==false; r["artifacts"].each{|a| p=a["path"].to_s; next unless p.include?("receipts/#{id}/"); f="receipts/#{id}/#{File.basename(p)}"; abort "release-tree receipt artifact missing #{f}" unless File.file?(f); abort "release-tree receipt sha256 mismatch #{f}" unless Digest::SHA256.file(f).hexdigest==a["sha256"] }'
	@ruby -rjson -rdigest -e 'dir="release/darwin-atlas-0.1.0-engineering-b04fdefd"; r=JSON.parse(File.read("#{dir}/release_receipt.json")); abort "release kind drift" unless r["receipt_kind"]=="engineering_release"; abort "release must stay engineering scope" unless r["engineering_scope"]==true && r["release_eligible"]==false; abort "DOI must stay an explicit placeholder" unless r["doi"]=="pending"; abort "release commit must be a 40-hex sha" unless r["source_commit"].to_s.match?(/\A[0-9a-f]{40}\z/); abort "release must come from a clean tree" unless r["source_dirty"]==false; abort "battery marker drift" unless r.dig("battery","final_marker")=="BATTERY_ALL_GREEN"; abort "battery evidence hash drift" unless Digest::SHA256.file("#{dir}/battery_evidence.txt").hexdigest==r.dig("battery","evidence_sha256"); abort "tarball hash drift" unless Digest::SHA256.file("#{dir}/#{r.dig("bundle_files","tarball")}").hexdigest==r.dig("bundle_files","tarball_sha256"); abort "products receipt hash drift" unless Digest::SHA256.file("receipts/#{r.dig("products_receipt","run_id")}/run_receipt.json").hexdigest==r.dig("products_receipt","receipt_sha256"); abort "benchmark receipt hash drift" unless Digest::SHA256.file("receipts/#{r.dig("benchmark_receipt","run_id")}/benchmark_receipt.json").hexdigest==r.dig("benchmark_receipt","receipt_sha256")'
	@ruby -rjson -rdigest -e 'dir="receipts/chromosome-benchmark-53ccaccb-20260801T225452Z"; r=JSON.parse(File.read("#{dir}/benchmark_receipt.json")); abort "benchmark kind drift" unless r["receipt_kind"]=="chromosome_scale_benchmark"; v=r["validator"]; abort "benchmark validator drift" unless v["language"]=="Julia" && v["status"]=="pass" && v["tolerance"]==0; abort "benchmark commit must be a 40-hex sha" unless r.dig("atlas_source","commit").to_s.match?(/\A[0-9a-f]{40}\z/); abort "benchmark must come from a clean tree" unless r.dig("atlas_source","dirty")==false; exp={"NC_000913.3"=>[290104,"59ad5c34a1f0cf9dfa41c7fee9e94403419c38bf2fe86a8f0c40c99ee3148650","sample_chr_MG1655.txt"],"NC_002695.2"=>[343662,"6d119d223162bcf27f4f9d5a2ba7fb952f2b1746c93b8dd8db7eaae4933fb0e4","sample_chr_Sakai.txt"]}; abort "benchmark must have exactly 2 results" unless r["results"].size==2; r["results"].each{|x| e=exp[x["accession"]] or abort "benchmark accession drift"; abort "benchmark lines drift" unless x["lines"]==e[0] && x["expected_lines"]==e[0]; abort "benchmark sha256 drift" unless x["sha256"]==e[1]; abort "benchmark wall/RSS missing" unless x["wall_seconds"]>0 && x["peak_rss_kb"]>0; abort "benchmark sample must pass" unless x.dig("sample","status")=="pass" && x.dig("sample","tolerance")==0; abort "benchmark coordinates hash drift" unless Digest::SHA256.file("#{dir}/#{e[2]}").hexdigest==x.dig("sample","coordinates_sha256") }'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/cohort_assemblies.schema.json")); abort "cohort schema must forbid extras" unless s.fetch("additionalProperties")==false; %w[assembly_accession_version taxid organism_name refseq_category assembly_level retrieval_utc datasets_version package_md5 included].each { |k| abort "cohort schema missing 11.1 field #{k}" unless s.fetch("required").include?(k) }; abort "cohort schema must fix 16-field order" unless s.fetch("required").size==16'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/atlas_replicons.schema.json")); abort "replicons schema must forbid extras" unless s.fetch("additionalProperties")==false; %w[sequence_accession_version assembly_accession_version replicon_class declared_topology length_bp canonical_count ambiguous_count gc_fraction input_sha256 included exclusion_reason].each { |k| abort "replicons schema missing 11.2 field #{k}" unless s.fetch("required").include?(k) }; abort "replicons schema must fix 14-field order" unless s.fetch("required").size==14; abort "topology enum drift" unless s.dig("properties","declared_topology","enum")==["circular","linear","unknown"]'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/excluded_records.schema.json")); abort "exclusions schema must forbid extras" unless s.fetch("additionalProperties")==false; %w[exclusion_level sequence_accession_version assembly_accession_version window_start window_end metric reason_code].each { |k| abort "exclusions schema missing 11.5 field #{k}" unless s.fetch("required").include?(k) }; abort "exclusions schema must fix 10-field order" unless s.fetch("required").size==10; abort "reason code enum drift" unless s.dig("properties","reason_code","enum")==["AMBIGUOUS_WINDOW","K_OUT_OF_CONFIGURED_RANGE","INSUFFICIENT_EFFECTIVE_KMERS"]'
	@ruby -rjson -e 's=JSON.parse(File.read("toolchains/sounio.lock.json")); abort "wrong official remote" unless s.fetch("repository")=="https://github.com/sounio-lang/sounio.git"; abort "invalid Sounio commit" unless s.fetch("commit").match?(/\A[0-9a-f]{40}\z/)'
	@! rg -n "Running Julia-only validation instead" julia/scripts/cross_validation.jl
	@! rg -n "rm -rf julia/[M]anifest.toml" Makefile
	@echo "Contract checks passed"

u0-contract:
	@for f in \
		docs/ADR-0004-v3-u0-utility-first-fail-closed-gates.md \
		docs/DOSA_V3_PUBLIC_DATA_DICTIONARY.md \
		docs/V2_1_2_FORENSIC_PRESERVATION.md \
		data/v3/u0_parameters.json \
		data/v3/refseq_bacteria_complete_query.json \
		data/v3/public_field_use_rules.json \
		toolchains/ncbi-datasets.lock.json \
		toolchains/u0-python-requirements.txt \
		scripts/select_u0_pilot.py \
		scripts/review_u0_control_candidates.py \
		scripts/bind_u0_control_ledger.py \
		scripts/validate_u0_control_ledger.py \
		scripts/build_u0_source_manifest.py \
		scripts/evaluate_u0_gate.py \
		scripts/audit_v3_public_fields.py \
		scripts/project_u0_parquet_capacity.py \
		scripts/measure_u0_operational_utility.py \
		scripts/prepare_biostudies_queue.py \
		scripts/run_u0_manifest_differential.sh \
		scripts/generate_u0_dinucleotide_scale_cases.rb \
		scripts/run_u0_dinucleotide_scale_fixture.sh \
		scripts/validate_u0_window_profile_fixture.py \
		cli/bin/dosa \
		sounio/src/u0_manifest_fixture.sio \
		sounio/src/u0_dinucleotide_scale_fixture.sio \
		julia/scripts/validate_u0_manifest.jl \
		julia/scripts/validate_u0_dinucleotide_scale_fixture.jl \
		julia/scripts/validate_u0_window_profile_fixture.jl \
		julia/test/test_u0_window_profile_fixture.jl; do test -s "$$f"; done
	@test -s data/v3/U0_CONTROL_LEDGER.md
	@test -s data/fixtures/u0_control_ledger/control_candidates.tsv
	@test -s data/fixtures/u0_dinucleotide_scale/cases.tsv
	@test -s data/fixtures/u0_dinucleotide_scale/invalid_replicates.tsv
	@for f in dosa_v3_common dosa_v3_parameters dosa_v3_source_manifest dosa_v3_source_index dosa_v3_replicon dosa_v3_run dosa_v3_window_profile dosa_v3_summary dosa_v3_exclusion dosa_v3_payload_manifest dosa_v3_receipt; do test -s "schemas/$$f.schema.json"; done
	@bash -n scripts/freeze_u0_refseq_snapshot.sh scripts/run_u0_dinucleotide_scale_fixture.sh scripts/test_u0_selection.sh scripts/test_u0_control_review.sh scripts/test_u0_control_ledger.sh scripts/test_u0_source_manifest.sh scripts/test_u0_gate.sh scripts/test_u0_capacity.sh scripts/test_u0_operational.sh
	@ruby -c scripts/generate_u0_dinucleotide_scale_cases.rb >/dev/null
	@python3 -c 'p="scripts/validate_u0_window_profile_fixture.py"; compile(open(p,encoding="utf-8").read(),p,"exec")'
	@tmp="$$(mktemp "$${TMPDIR:-/tmp}/dosa-u0-scale-cases.XXXXXX")"; ruby scripts/generate_u0_dinucleotide_scale_cases.rb data/v3/u0_parameters.json "$$tmp"; cmp data/fixtures/u0_dinucleotide_scale/cases.tsv "$$tmp"; rm -f "$$tmp"
	@python3 -c 'import json,pathlib; files=list(pathlib.Path("schemas").glob("dosa_v3_*.schema.json"))+list(pathlib.Path("data/v3").glob("*.json"))+[pathlib.Path("toolchains/ncbi-datasets.lock.json")]; hook=lambda pairs: _pairs(pairs); ns={}; exec("def _pairs(pairs):\n d={}\n for k,v in pairs:\n  if k in d: raise ValueError(\"duplicate JSON key: \"+k)\n  d[k]=v\n return d",ns); [json.loads(p.read_text(),object_pairs_hook=ns["_pairs"]) for p in files]; print("DOSA_V3_JSON_NO_DUPLICATES_PASS files=%d"%len(files))'
	@python3 -c 'import json; p=json.load(open("data/v3/u0_parameters.json")); mutable={"u0_status","full_atlas_execution_state","hdd_purchase_state","release_policy"}; assert p["window_profiles"]==[{"window_size":16,"stride":16},{"window_size":100,"stride":100},{"window_size":500,"stride":500},{"window_size":1000,"stride":1000}] and p["k_min"]==1 and p["k_max"]==8 and p["null_model"]=="euler_wilson_fixed_endpoints_v1" and p["null_replicates"]==1000 and not mutable.intersection(p) and "p_values" not in p and "q_values" not in p; print("DOSA_V3_U0_PARAMETERS_PASS immutable_science_only=true")'
	@python3 scripts/audit_v3_public_fields.py --schema-dir schemas --rules data/v3/public_field_use_rules.json --evidence-scope fixture
	@python3 -m unittest discover -s cli/tests -p 'test_*.py'
	@scripts/test_u0_selection.sh
	@bash scripts/test_u0_control_review.sh
	@bash scripts/test_u0_control_ledger.sh
	@scripts/test_u0_source_manifest.sh
	@scripts/test_u0_gate.sh
	@scripts/test_u0_operational.sh
	@! rg -n 'reverse_kmer_imbalance_1|fixed_R|fixed_RC|orbit_ratio|orbit_size|dmin|p_value|q_value|parameters_sha256' schemas/dosa_v3_window_profile.schema.json
	@echo "DOSA_V3_U0_CONTRACT_PASS fixture_scope_only=true"

u0-schema-integration:
	@python3 -c 'import jsonschema' 2>/dev/null || (echo "BLOCKED: Python jsonschema is required for v3 schema integration" && exit 2)
	@python3 scripts/validate_v3_schemas.py

u0-cli-integration:
	@python3 -c 'import duckdb; assert duckdb.__version__ == "1.5.5", duckdb.__version__' 2>/dev/null || (echo "BLOCKED: duckdb==1.5.5 is required for the U0 CLI integration" && exit 2)
	@python3 -m unittest discover -s cli/tests -p 'test_*.py'
	@scripts/test_u0_capacity.sh

u0-julia-contract:
	@$(JULIA) --startup-file=no julia/scripts/validate_u0_manifest.jl --self-test data/fixtures/u0_manifest
	@$(JULIA) --startup-file=no julia/scripts/validate_u0_manifest.jl data/fixtures/u0_manifest/u0_manifest.tsv data/fixtures/u0_manifest/u0_expected_terminal.tsv
	@$(JULIA) --startup-file=no julia/test/test_u0_dinucleotide_scale_fixture.jl
	@$(JULIA) --startup-file=no julia/test/test_u0_window_profile_fixture.jl
	@$(JULIA) --startup-file=no julia/test/test_v3_scientific_gates.jl

u0-manifest-differential-fixture:
	@SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		JULIA_BIN="$$(printf '%s' "$(JULIA)" | awk '{print $$1}')" \
		bash scripts/run_u0_manifest_differential.sh

# Synthetic capacity/profile fixture only: it does not make U0 evidence or
# unlock the canonical U0 producer. Canonical v3 parameter bytes bind seeds.
u0-dinucleotide-scale-fixture:
	@SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		JULIA_BIN="$$(printf '%s' "$(JULIA)" | awk '{print $$1}')" \
		bash scripts/run_u0_dinucleotide_scale_fixture.sh

u0-gate:
	@for variable in U0_AGREEMENT_REPORT U0_QUERY_REPORT U0_SPEED_REPORT U0_CAPACITY_REPORT U0_FIELD_AUDIT_REPORT U0_ORIC_REPORT U0_MODEL_REPORT U0_ORIC_INPUT U0_MODEL_INPUT U0_PARAMETERS U0_SOURCE_MANIFEST U0_SOURCE_INTEGRITY U0_SOURCE_INDEX U0_PAYLOAD_MANIFEST U0_SOUNIO_ATTESTATION U0_SOUNIO_BUILD_RECEIPT U0_SOUNIO_EXECUTION_RECEIPT U0_SOUNIO_OUTPUT_MANIFEST U0_JULIA_RECEIPT U0_PILOT_PROVENANCE U0_SELECTION U0_CONTROL_CANDIDATES U0_CONTROL_LEDGER U0_CONTROL_BINDING_RECEIPT U0_CONTROL_VALIDATION_RECEIPT U0_SOURCE_FREEZE_RECEIPT U0_ASSEMBLY_REPORT U0_SEQUENCE_REPORT U0_FULL_REPLICON_INVENTORY U0_WORK_UNIT_MANIFEST U0_JULIA_BIN; do eval "value=\$$$$variable"; if [ -z "$$value" ] || [ ! -f "$$value" ]; then echo "BLOCKED: $$variable must name an immutable real U0 evidence artifact"; exit 2; fi; done
	@if [ -z "$$U0_EVIDENCE_ROOT" ] || [ ! -d "$$U0_EVIDENCE_ROOT" ]; then echo "BLOCKED: U0_EVIDENCE_ROOT must name the immutable real U0 evidence root"; exit 2; fi
	@python3 scripts/evaluate_u0_gate.py \
		--agreement "$$U0_AGREEMENT_REPORT" \
		--query "$$U0_QUERY_REPORT" \
		--speed "$$U0_SPEED_REPORT" \
		--capacity "$$U0_CAPACITY_REPORT" \
		--field-audit "$$U0_FIELD_AUDIT_REPORT" \
		--oric "$$U0_ORIC_REPORT" \
		--model "$$U0_MODEL_REPORT" \
		--oric-input "$$U0_ORIC_INPUT" \
		--model-input "$$U0_MODEL_INPUT" \
		--selection "$$U0_SELECTION" \
		--control-candidates "$$U0_CONTROL_CANDIDATES" \
		--control-ledger "$$U0_CONTROL_LEDGER" \
		--control-binding-receipt "$$U0_CONTROL_BINDING_RECEIPT" \
		--control-validation-receipt "$$U0_CONTROL_VALIDATION_RECEIPT" \
		--source-freeze-receipt "$$U0_SOURCE_FREEZE_RECEIPT" \
		--assembly-report "$$U0_ASSEMBLY_REPORT" \
		--sequence-report "$$U0_SEQUENCE_REPORT" \
		--full-replicon-inventory "$$U0_FULL_REPLICON_INVENTORY" \
		--work-unit-manifest "$$U0_WORK_UNIT_MANIFEST" \
		--julia-bin "$$U0_JULIA_BIN" \
		--parameters "$$U0_PARAMETERS" \
		--source-manifest "$$U0_SOURCE_MANIFEST" \
		--source-integrity "$$U0_SOURCE_INTEGRITY" \
		--source-index "$$U0_SOURCE_INDEX" \
		--payload-manifest "$$U0_PAYLOAD_MANIFEST" \
		--sounio-attestation "$$U0_SOUNIO_ATTESTATION" \
		--sounio-build-receipt "$$U0_SOUNIO_BUILD_RECEIPT" \
		--sounio-execution-receipt "$$U0_SOUNIO_EXECUTION_RECEIPT" \
		--sounio-output-manifest "$$U0_SOUNIO_OUTPUT_MANIFEST" \
		--julia-receipt "$$U0_JULIA_RECEIPT" \
		--evidence-root "$$U0_EVIDENCE_ROOT" \
		--pilot-provenance "$$U0_PILOT_PROVENANCE"

u250-smoke-contract:
	@bash -n fpga/u250-smoke/build.sh fpga/u250-smoke/compile-host.sh fpga/u250-smoke/run-hardware.sh
	@rg -q 'xilinx_u250_gen3x16_xdma_4_1_202210_1' fpga/u250-smoke/build.sh
	@rg -q 'sounio.dev/u250' fpga/u250-smoke/kubernetes/smoke-pod.yaml
	@rg -q 'kElementCount = 4096' fpga/u250-smoke/src/host.cpp
	@rg -q 'U250_VECTOR_ADD_PASS elements=' fpga/u250-smoke/src/host.cpp
	@rg -q 'U250_HARDWARE_SMOKE_PASS' fpga/u250-smoke/run-hardware.sh
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/u250_hardware_smoke_receipt.schema.json")); abort "U250 receipt must remain engineering-only" unless s.dig("properties","engineering_scope","const")==true && s.dig("properties","scientific_claim","const")==false; abort "U250 receipt must require a validated hardware marker" unless s.dig("properties","execution","properties","marker","const")=="U250_HARDWARE_SMOKE_PASS"'
	@ruby -rjson -rdigest -e 'dir="receipts/u250-smoke-659ab549-20260803T022116Z"; r=JSON.parse(File.read("#{dir}/u250_smoke_receipt.json")); abort "U250 receipt kind/state drift" unless r["receipt_kind"]=="u250_hardware_smoke" && r["state"]=="validated"; abort "U250 receipt scope drift" unless r["engineering_scope"]==true && r["scientific_claim"]==false; abort "U250 source receipt drift" unless r.dig("atlas_source","commit")=="659ab54985edc17efaabaad9e3320e0ab92b1275" && r.dig("atlas_source","dirty")==false; kinds=r["artifacts"].map{|a|a["kind"]}; expected=%w[kernel_source host_source connectivity xo xclbin host_binary]; abort "U250 artifact set drift" unless kinds.sort==expected.sort && kinds.uniq.size==6; r["artifacts"].first(3).each{|a| f=a["path"]; abort "U250 source artifact missing #{f}" unless File.file?(f); abort "U250 source artifact hash drift #{f}" unless Digest::SHA256.file(f).hexdigest==a["sha256"]; abort "U250 source artifact size drift #{f}" unless File.size(f)==a["size_bytes"]}; builder=File.read("#{dir}/builder-SHA256SUMS"); %w[xo xclbin].each{|kind| a=r["artifacts"].find{|x|x["kind"]==kind}; abort "U250 builder hash evidence missing #{kind}" unless builder.include?("#{a["sha256"]}  #{a["path"]}")}; env=File.read("#{dir}/builder-environment.txt"); abort "U250 builder environment drift" unless env.include?(r.dig("builder","host")) && env.include?("v++ v#{r.dig("builder","vitis_version")}") && env.include?("SW Build #{r.dig("builder","vitis_build")}"); %w[xpfm_sha256 xsa_sha256].each{|key| abort "U250 platform hash evidence missing #{key}" unless env.include?(r.dig("platform",key))}; runtime=File.read("#{dir}/runtime-artifacts.txt"); %w[xclbin host_binary].each{|kind| a=r["artifacts"].find{|x|x["kind"]==kind}; abort "U250 runtime hash evidence missing #{kind}" unless runtime.include?(a["sha256"])}; log="#{dir}/hardware-run.log"; abort "U250 hardware log hash drift" unless Digest::SHA256.file(log).hexdigest==r.dig("execution","log_sha256"); text=File.read(log); abort "U250 vector marker missing" unless text.include?("U250_VECTOR_ADD_PASS elements=4096"); abort "U250 wrapper marker missing" unless text.include?("U250_HARDWARE_SMOKE_PASS"); abort "U250 execution receipt drift" unless r.dig("execution","exit_code")==0 && r.dig("execution","elements")==4096'
	@cd receipts/u250-smoke-659ab549-20260803T022116Z && (sha256sum -c evidence-SHA256SUMS 2>/dev/null || shasum -a 256 -c evidence-SHA256SUMS)
	@echo "U250 smoke contract checks passed"

u250-null-contract:
	@bash -n fpga/u250-null-model/build.sh fpga/u250-null-model/compile-host.sh fpga/u250-null-model/run-hardware.sh fpga/u250-null-model/verify-fixture.sh
	@rg -q 'lcg31_sha8_fixture_v1' fpga/u250-null-model/README.md
	@rg -q 'U250_NULL_HARDWARE_PASS' fpga/u250-null-model/run-hardware.sh
	@rg -q 'null_draws_1.windows:DDR\[0\]' fpga/u250-null-model/null_draws.cfg
	@rg -q 'sounio.dev/u250' fpga/u250-null-model/kubernetes/null-draw-pod.yaml
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/u250_null_draw_receipt.schema.json")); abort "U250 null receipt scope drift" unless s.dig("properties","engineering_scope","const")==true && s.dig("properties","pilot_null_primary","const")==false && s.dig("properties","scientific_claim","const")==false && s.dig("properties","performance_claim","const")==false; abort "U250 null receipt marker drift" unless s.dig("properties","validation","properties","hardware_marker","const")=="U250_NULL_HARDWARE_PASS"; abort "U250 null fixture draw count drift" unless s.dig("properties","fixture","properties","draws","const")==1152'
	@fpga/u250-null-model/verify-fixture.sh
	@ruby -rjson -rdigest -e 'dir="receipts/null-draws-8a090b8-20260803T090705Z"; r=JSON.parse(File.read("#{dir}/null_draw_receipt.json")); abort "null receipt kind/state drift" unless r["receipt_kind"]=="u250_null_draw_hardware" && r["state"]=="validated"; abort "null receipt scope drift" unless r["engineering_scope"]==true && r["pilot_null_primary"]==false && r["scientific_claim"]==false && r["performance_claim"]==false; abort "null receipt adr drift" unless r["adr_0002_status"]=="proposed"; abort "null source receipt drift" unless r.dig("atlas_source","commit")=="8a090b86cb2df88bff7dc5534bd3ff0a8863d180" && r.dig("atlas_source","dirty")==false; abort "null fixture drift" unless r.dig("fixture","cases")==8 && r.dig("fixture","metrics")==18 && r.dig("fixture","replicates")==8 && r.dig("fixture","draws")==1152 && r.dig("fixture","tolerance")==0; kinds=r["artifacts"].map{|a|a["kind"]}; expected=%w[kernel_source xo xclbin host_binary]; abort "null artifact set drift" unless kinds.sort==expected.sort && kinds.uniq.size==4; r["artifacts"].each{|a| f=a["path"]; abort "null artifact missing #{f}" unless File.file?(f); abort "null artifact hash drift #{f}" unless Digest::SHA256.file(f).hexdigest==a["sha256"]; abort "null artifact size drift #{f}" unless File.size(f)==a["size_bytes"]}; builder=File.read("#{dir}/SHA256SUMS"); %w[xo xclbin].each{|kind| a=r["artifacts"].find{|x|x["kind"]==kind}; abort "null builder hash evidence missing #{kind}" unless builder.include?(a["sha256"])}; env=File.read("#{dir}/builder-environment.txt"); abort "null builder environment drift" unless env.include?(r.dig("builder","host")) && env.include?(r.dig("platform","xpfm_sha256")) && env.include?(r.dig("platform","xsa_sha256")); runtime=File.read("#{dir}/runtime-artifacts.txt"); %w[xclbin host_binary].each{|kind| a=r["artifacts"].find{|x|x["kind"]==kind}; abort "null runtime hash evidence missing #{kind}" unless runtime.include?(a["sha256"])}; log="#{dir}/hardware-run.log"; abort "null hardware log hash drift" unless Digest::SHA256.file(log).hexdigest==r.dig("validation","hardware_log_sha256"); text=File.read(log); abort "null hardware log missing draw marker" unless text.include?("U250_NULL_DRAW_PASS cases=8 metrics=18 replicates=8 draws=1152"); abort "null hardware log missing pass marker" unless text.include?("U250_NULL_HARDWARE_PASS")'
	@cd receipts/null-draws-8a090b8-20260803T090705Z && (sha256sum -c evidence-SHA256SUMS 2>/dev/null || shasum -a 256 -c evidence-SHA256SUMS)
	@echo "U250 null-model contract checks passed"

u250-dinucleotide-contract:
	@bash -n fpga/u250-dinucleotide-null/build.sh fpga/u250-dinucleotide-null/compile-host.sh fpga/u250-dinucleotide-null/run-hardware.sh fpga/u250-dinucleotide-null/verify-fixture.sh scripts/run_dinucleotide_null_differential.sh
	@rg -q 'euler_wilson_fixed_endpoints_v1' docs/ADR-0003-dinucleotide-null-engineering-contract.md fpga/u250-dinucleotide-null/README.md
	@rg -q 'DINUCLEOTIDE_NULL_DIFFERENTIAL_PASS' scripts/run_dinucleotide_null_differential.sh
	@rg -q 'U250_DINUCLEOTIDE_HARDWARE_PASS' fpga/u250-dinucleotide-null/run-hardware.sh
	@rg -q 'dinucleotide_draws_1.windows:DDR\[0\]' fpga/u250-dinucleotide-null/dinucleotide_draws.cfg
	@rg -q 'sounio.dev/u250' fpga/u250-dinucleotide-null/kubernetes/dinucleotide-pod.yaml
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/u250_dinucleotide_null_receipt.schema.json")); abort "dinucleotide receipt scope drift" unless s.dig("properties","engineering_scope","const")==true && s.dig("properties","pilot_primary_candidate","const")==true && s.dig("properties","pilot_null_primary","const")==false && s.dig("properties","scientific_claim","const")==false && s.dig("properties","performance_claim","const")==false; abort "dinucleotide receipt slot count drift" unless s.dig("properties","fixture","properties","base_slots","const")==1024; abort "dinucleotide hardware marker drift" unless s.dig("properties","validation","properties","hardware_marker","const")=="U250_DINUCLEOTIDE_HARDWARE_PASS"'
	@ruby -rjson -e 'p=JSON.parse(File.read("data/fixtures/dinucleotide_null/parameters.json")); s=JSON.parse(File.read("schemas/dinucleotide_null_parameters.schema.json")); abort "dinucleotide parameter keys drift" unless p.keys==s.fetch("required"); s.fetch("properties").each{|key,rule| abort "dinucleotide parameter #{key} drift" unless p[key]==rule["const"]}'
	@temp="$$(mktemp)"; scripts/generate_dinucleotide_cases.rb data/fixtures/dinucleotide_null/parameters.json data/fixtures/dinucleotide_null/case_templates.tsv "$$temp"; cmp data/fixtures/dinucleotide_null/cases.tsv "$$temp"; rm -f "$$temp"
	@fpga/u250-dinucleotide-null/verify-fixture.sh
	@ruby -rjson -rdigest -rtime -e 'dir="receipts/dinucleotide-null-556ac81-20260803T171300Z"; r=JSON.parse(File.read("#{dir}/dinucleotide_null_receipt.json")); abort "dinucleotide receipt kind/state drift" unless r["receipt_kind"]=="u250_dinucleotide_null_hardware" && r["state"]=="validated"; abort "dinucleotide receipt scope drift" unless r["engineering_scope"]==true && r["pilot_primary_candidate"]==true && r["pilot_null_primary"]==false && r["scientific_claim"]==false && r["performance_claim"]==false; abort "dinucleotide ADR drift" unless r["adr_0002_status"]=="proposed" && r["adr_0003_status"]=="accepted"; abort "dinucleotide source receipt drift" unless r.dig("atlas_source","commit")=="556ac81eedc58a3a2e1ae9c0a2497dd434a5a944" && r.dig("atlas_source","dirty")==false; abort "dinucleotide run id drift" unless r["run_id"]=="dinucleotide-null-556ac81-20260803T171300Z"; started=Time.iso8601(r["started_utc"]); finished=Time.iso8601(r["finished_utc"]); abort "dinucleotide run interval drift" unless started==Time.utc(2026,8,3,17,13,35) && finished==Time.utc(2026,8,3,19,29,51) && started<finished; abort "dinucleotide fixture drift" unless r.dig("fixture","cases")==8 && r.dig("fixture","replicates")==8 && r.dig("fixture","sequence_draws")==64 && r.dig("fixture","base_slots")==1024 && r.dig("fixture","tolerance")==0; sha=/\A[0-9a-f]{64}\z/; %w[launcher_sha256 source_sha256 executable_sha256 artifact_sha256].each{|key| abort "dinucleotide Sounio hash invalid #{key}" unless sha.match?(r.dig("sounio",key).to_s)}; abort "dinucleotide Sounio source hash drift" unless Digest::SHA256.file("sounio/src/dinucleotide_null_fixture.sio").hexdigest==r.dig("sounio","source_sha256"); artifact="#{dir}/dinucleotide-sounio.jsonl"; abort "dinucleotide Sounio artifact hash drift" unless Digest::SHA256.file(artifact).hexdigest==r.dig("sounio","artifact_sha256"); lines=File.readlines(artifact,chomp:true); abort "dinucleotide Sounio artifact line drift" unless lines.size==64; lines.each{|line| JSON.parse(line)}; differential=File.read("#{dir}/dinucleotide-differential.log"); %w[launcher_sha256 source_sha256 executable_sha256 artifact_sha256].each{|key| abort "dinucleotide differential hash evidence missing #{key}" unless differential.include?("#{key.sub(/_sha256\z/,"")}_sha256=#{r.dig("sounio",key)}")}; abort "dinucleotide differential marker missing" unless differential.include?("DINUCLEOTIDE_NULL_DIFFERENTIAL_PASS cases=8 replicates=8 draws=64 tolerance=0") && differential.include?("DINUCLEOTIDE_JULIA_DIFFERENTIAL_PASS cases=8 replicates=8 draws=64 distinct_case_draws=30 tolerance=0"); kinds=r["artifacts"].map{|a|a["kind"]}; expected=%w[kernel_source xo xclbin host_binary]; abort "dinucleotide artifact set drift" unless kinds.sort==expected.sort && kinds.uniq.size==4; r["artifacts"].each{|a| f=a["path"]; abort "dinucleotide artifact missing #{f}" unless File.file?(f); abort "dinucleotide artifact hash drift #{f}" unless Digest::SHA256.file(f).hexdigest==a["sha256"]; abort "dinucleotide artifact size drift #{f}" unless File.size(f)==a["size_bytes"]}; sums=File.read("#{dir}/SHA256SUMS"); %w[xo xclbin].each{|kind| a=r["artifacts"].find{|x|x["kind"]==kind}; abort "dinucleotide builder hash evidence missing #{kind}" unless sums.include?(a["sha256"])}; build=File.read("#{dir}/build-wrapper.log"); abort "dinucleotide build timing evidence missing" unless build.include?("Start of session at: Mon Aug  3 17:13:58 2026") && build.include?("Total elapsed time: 1h 44m 19s"); impl=File.read("#{dir}/impl_runme.log"); warnings=impl.scan(/^CRITICAL WARNING:/).size; abort "dinucleotide critical-warning count drift" unless warnings==r.dig("builder","critical_warnings") && warnings==2; %w[Constraints\ 18-952 Vivado\ 12-4430].each{|id| abort "dinucleotide critical-warning identity missing #{id}" unless impl.include?(id)}; %w[compile.log link.log impl_runme.log build-wrapper.log].each{|name| abort "dinucleotide builder error in #{name}" if File.read("#{dir}/#{name}").match?(/^ERROR:/)}; abort "dinucleotide builder error count drift" unless r.dig("builder","errors")==0; log="#{dir}/hardware-run.log"; abort "dinucleotide hardware log hash drift" unless Digest::SHA256.file(log).hexdigest==r.dig("validation","hardware_log_sha256"); text=File.read(log); abort "dinucleotide draw marker missing" unless text.include?("U250_DINUCLEOTIDE_DRAW_PASS cases=8 replicates=8 slots=1024 tolerance=0"); abort "dinucleotide hardware marker missing" unless text.include?("U250_DINUCLEOTIDE_HARDWARE_PASS"); abort "dinucleotide device evidence missing" unless text.include?("[0000:d8:00.1]") && text.include?("xilinx_u250_gen3x16_xdma_shell_4_1") && text.match?(/\|Yes\s*\|/)'
	@cd receipts/dinucleotide-null-556ac81-20260803T171300Z && (sha256sum -c evidence-SHA256SUMS 2>/dev/null || shasum -a 256 -c evidence-SHA256SUMS)
	@echo "U250 dinucleotide-null contract checks passed"

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

# Frozen FASTA + metadata -> positional windows -> delta_R/delta_RC -> masked
# k-mers + additive engineering nulls -> deterministic JSONL, produced by
# pinned official Sounio.
sounio-mini-pipeline:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_sounio_mini_pipeline.sh

# Sounio JSONL artifact + independent Base-only Julia byte-exact recomputation.
mini-pipeline-differential-fixture:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_mini_pipeline_differential.sh

# Spec section 12.1 metamorphic properties: executable Sounio fixture emitting
# one integer observation per property, plus an independent Base-only Julia
# oracle recomputing every pair at tolerance zero.
metamorphic-differential-fixture:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_metamorphic_differential_fixture.sh

# Spec 12.1 extension around both null engines (Fase M4): engineered
# homopolymer/alternating/branching synthetic controls run through both null
# engines as optimized/optimized/reference triples (required byte-identical),
# then an independent Base-only Julia validator recomputes every line byte for
# byte and asserts the metamorphic relations MR1-MR4 over the persisted
# producer output.
null-metamorphic-differential-fixture:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_null_metamorphic_differential.sh

# Fase N null-generator quality gate: both engines replicated exactly in a
# standalone Sounio fixture (284000 frozen draws, twice, byte-identical),
# then an independent standard-library-only Julia validator re-enumerates
# each exact null support, requires containment plus full coverage, and
# applies a chi-square uniformity test with pre-declared alpha=1e-3 per case.
null-quality-differential-fixture:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_null_quality_differential.sh

# Complete-replicon engineering smoke (NC_002127.1, 207 windows): optimized
# kernel twice for determinism + independent Julia byte-exact recomputation.
# Engineering smoke only; not the pilot and not a release receipt.
cohort-smoke-differential:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_cohort_smoke_differential.sh

# Engineering canonical products (Fase E): cohort_assemblies + atlas_replicons
# (all four replicons) + excluded_records (all four) + window products for the
# two plasmids, each recomputed byte-exact by independent Base-only Julia.
# Engineering scope; not the pilot dataset and not a release receipt.
cohort-products:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_cohort_products.sh

# Development-only FFI comparison. The publication gate will compare persisted
# Sounio artifacts after the canonical producer exists.
cross-validate: julia
	@echo "Running fail-closed Sounio/Julia comparison diagnostic..."
	$(JULIA) julia/scripts/cross_validation.jl

pipeline:
	@echo "BLOCKED: the mini-pipeline fixture is an executable specification only; the canonical cohort pipeline (run receipts, k-mer/null-model metrics, release artifacts) is not implemented."
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
