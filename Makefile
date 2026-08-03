.PHONY: all help status contract setup-julia julia test test-julia \
	sounio sounio-fixture operator-differential-fixture compile-sounio-fixture \
	sounio-fasta-fixture fasta-differential-fixture \
	sounio-mini-pipeline mini-pipeline-differential-fixture \
	cohort-smoke-differential \
	cohort-products \
	u250-smoke-contract u250-null-contract \
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
	@echo "  mini-pipeline-differential-fixture  Sounio JSONL + independent Base-only Julia check"
	@echo "  cohort-smoke-differential  Complete-replicon engineering smoke + Julia byte-exact check"
	@echo "  cohort-products         Engineering canonical products + Julia byte-exact checks"
	@echo "  u250-smoke-contract     Validate the engineering U250 hardware-smoke scaffold"
	@echo "  u250-null-contract      Validate Julia/HLS exact null-draw fixtures"
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
	@test -s docs/ADR-0001-sounio-primary-julia-validator.md
	@test -s docs/ADR-0002-pilot-parameter-decisions.md
	@test -s schemas/run_receipt.schema.json
	@test -s schemas/u250_hardware_smoke_receipt.schema.json
	@test -s receipts/u250-smoke-659ab549-20260803T022116Z/u250_smoke_receipt.json
	@test -s fpga/u250-null-model/src/null_draws.cpp
	@test -s fpga/u250-null-model/generated_fixture.hpp
	@test -x fpga/u250-null-model/verify-fixture.sh
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
	@for f in valid_multi_record invalid_symbol sequence_before_header empty_header empty_sequence no_records; do test -s "data/fixtures/fasta/$$f.fa"; done
	@test "$$(wc -c < data/fixtures/fasta/valid_multi_record.fa)" -gt 17
	@test -s data/fixtures/mini_pipeline/pipeline_fixture.fa
	@test -s data/fixtures/mini_pipeline/pipeline_k8_fixture.fa
	@test -s data/fixtures/mini_pipeline/SHA256SUMS
	@for f in pipeline_metadata pipeline_k8_metadata metadata_invalid metadata_mismatch metadata_short; do test -s "data/fixtures/mini_pipeline/$$f.tsv"; done
	@test -s data/fixtures/mini_pipeline/parameters_k4.json
	@test -s data/fixtures/mini_pipeline/parameters_k8.json
	@for f in window_size_zero stride_zero stride_mismatch k_min_two k_max_nine k_max_above_window unknown_policy extra_field; do test -s "data/fixtures/mini_pipeline/params_invalid/$$f.json"; done
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
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/pipeline_parameters.schema.json")); abort "null_model must be an optional enum" unless s.dig("properties","null_model","enum")==["none","mononucleotide_shuffle"] && !s.fetch("required").include?("null_model"); abort "null_replicates ceiling drifted" unless s.dig("properties","null_replicates","maximum")==64'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/window_operator_profile.schema.json")); abort "schema must fix canonical_only" unless s.dig("properties","ambiguity_policy","const")=="canonical_only"; abort "schema must fix window fields" unless s.fetch("required").include?("delta_RC") && s.fetch("additionalProperties")==false'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/window_operator_profile.schema.json")); abort "schema_version must be 0.3.0" unless s.dig("properties","schema_version","const")=="0.3.0"; abort "kmer policy must be masked" unless s.dig("properties","kmer_ambiguity_policy","const")=="masked"; abort "kmer min effective count must be an integer >= 1" unless s.dig("properties","kmer_min_effective_count","type")=="integer" && s.dig("properties","kmer_min_effective_count","minimum")==1; abort "parameters_sha256 must be a lowercase hex sha256" unless s.dig("properties","parameters_sha256","pattern")=="^[0-9a-f]{64}$$"; abort "required must cover k=1..8 with reasons, null summaries and 183 fields" unless s.fetch("required").size==183 && s.fetch("required").include?("rc_kmer_imbalance_8") && s.fetch("required").include?("kmer_8_unavailable_reason") && s.fetch("required").include?("parameters_sha256") && s.fetch("required").include?("null_model") && s.fetch("required").include?("null_replicates") && s.fetch("required").include?("null_seed_derivation") && s.fetch("required").include?("delta_R_null_mean") && s.fetch("required").include?("rc_kmer_imbalance_8_null_q975"); abort "additionalProperties must stay false" unless s.fetch("additionalProperties")==false'
	@ruby -rjson -e 's=JSON.parse(File.read("schemas/run_receipt.schema.json")); abort "producer must be Sounio" unless s.dig("properties","producer","properties","language","const")=="Sounio"; abort "validator must be Julia" unless s.dig("properties","validator","oneOf",1,"properties","language","const")=="Julia"'
	@$(MAKE) --no-print-directory u250-smoke-contract
	@$(MAKE) --no-print-directory u250-null-contract
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
	@fpga/u250-null-model/verify-fixture.sh
	@echo "U250 null-model contract checks passed"

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

# Frozen FASTA + metadata -> positional windows -> delta_R/delta_RC -> explicit
# exclusions -> deterministic JSONL, produced by pinned official Sounio.
sounio-mini-pipeline:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_sounio_mini_pipeline.sh

# Sounio JSONL artifact + independent Base-only Julia byte-exact recomputation.
mini-pipeline-differential-fixture:
	SOUNIO_REPO="$(SOUNIO_REPO)" SOUNIO_LIMA_INSTANCE="$(SOUNIO_LIMA_INSTANCE)" \
		bash scripts/run_mini_pipeline_differential.sh

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
