# Implementation Plan: Scale Atlas to 50k Replicons for Publication

**Track ID**: scale_50k_20251223  
**Created**: 2025-12-23  
**Status**: New  
**Depends On**: ecoli_analysis_20251223

---

## Overview

This plan implements production-scale processing of ≥50,000 bacterial replicons for Scientific Data publication. The plan incorporates performance optimizations and lessons learned from the E. coli validation track.

**IMPORTANT**: This track should only begin after completing the E. coli analysis track.

---

## Phase 1: Performance Optimization

**Goal**: Implement optimizations to achieve <24 hour processing time for 50k replicons.

### Tasks

- [ ] Task: Analyze E. coli performance benchmarks
  - Read `docs/ecoli_performance_benchmarks.md` from previous track
  - Identify top 3 bottlenecks
  - Prioritize optimizations by impact
  - Document optimization plan in `docs/optimization_plan.md`

- [ ] Task: Write tests for parallel processing
  - Create `julia/test/test_parallel_processing.jl`
  - Test thread-safe metric computation
  - Test parallel FASTA parsing
  - Run tests and confirm they fail (Red phase)

- [ ] Task: Implement parallel replicon processing
  - Update `julia/scripts/run_pipeline.jl`
  - Add `Threads.@threads` for independent replicons
  - Ensure thread-safe data structures
  - Add progress reporting for parallel execution

- [ ] Task: Optimize I/O operations
  - Implement streaming FASTA parser (avoid loading full file)
  - Batch Parquet writes (write every 1000 rows)
  - Optimize DataFrame operations (pre-allocate, avoid copies)
  - Profile I/O improvements

- [ ] Task: Run parallel processing tests (Green phase)
  - Run `julia/test/test_parallel_processing.jl`
  - Confirm all tests pass
  - Verify thread safety
  - Benchmark speedup (compare to serial)

- [ ] Task: Benchmark optimized pipeline
  - Run on 1000 replicons with optimizations
  - Measure total time and per-replicon time
  - Compare to baseline (E. coli benchmarks)
  - Document speedup achieved

- [ ] Task: Conductor - User Manual Verification 'Phase 1: Performance Optimization' (Protocol in workflow.md)

---

## Phase 2: Incremental Processing and Checkpointing

**Goal**: Enable batch processing with checkpoint/resume for multi-day runs.

### Tasks

- [ ] Task: Write tests for checkpoint/resume
  - Create `julia/test/test_checkpoint_resume.jl`
  - Test checkpoint state saving
  - Test resume from checkpoint
  - Test handling of partial batches
  - Run tests and confirm they fail (Red phase)

- [ ] Task: Implement checkpoint mechanism
  - Create `julia/src/Checkpoint.jl` module
  - Define checkpoint state structure (processed IDs, current batch, timestamp)
  - Implement `save_checkpoint(state, path)` function
  - Implement `load_checkpoint(path)` function
  - Add checkpoint validation

- [ ] Task: Implement batch processing
  - Update `julia/scripts/run_pipeline.jl` for batch mode
  - Add `--batch-size` parameter (default: 1000)
  - Process replicons in batches
  - Save checkpoint after each batch
  - Add `--resume` flag to continue from checkpoint

- [ ] Task: Implement progress tracking
  - Add progress bar for batch processing
  - Report: current batch, total batches, ETA
  - Log processing statistics per batch
  - Save progress to `data/progress.log`

- [ ] Task: Run checkpoint/resume tests (Green phase)
  - Run `julia/test/test_checkpoint_resume.jl`
  - Confirm all tests pass
  - Test interruption and resume
  - Verify data integrity after resume

- [ ] Task: Test batch processing on 5000 replicons
  - Run pipeline with `--batch-size=500`
  - Verify all batches process correctly
  - Check checkpoint files created
  - Verify final output matches single-batch processing

- [ ] Task: Conductor - User Manual Verification 'Phase 2: Incremental Processing and Checkpointing' (Protocol in workflow.md)

---

## Phase 3: Large-Scale NCBI Download

**Goal**: Download ≥50,000 complete bacterial genomes from NCBI.

### Tasks

- [ ] Task: Write tests for robust download
  - Create `julia/test/test_robust_download.jl`
  - Test retry logic for failed downloads
  - Test rate limiting compliance
  - Test manifest generation
  - Run tests and confirm they fail (Red phase)

- [ ] Task: Implement robust download with retry
  - Update `julia/src/NCBIFetch.jl`
  - Add retry logic (max 3 attempts with exponential backoff)
  - Add rate limiting (max 3 requests/second)
  - Add timeout handling (30 seconds per request)
  - Log all download attempts and failures

- [ ] Task: Query NCBI for 50k complete bacterial genomes
  - Use NCBI Assembly API
  - Filter: `assembly_level="Complete Genome"`
  - Sort by: RefSeq category, then quality
  - Limit: 50,000-100,000 (to have buffer)
  - Save query results to `data/ncbi_query_50k.json`

- [ ] Task: Download genomes in batches
  - Run download with `--batch-size=500`
  - Download in batches of 500 genomes
  - Save checkpoint after each batch
  - Monitor download progress and failures
  - Estimate: 2-4 hours for 50k genomes

- [ ] Task: Verify downloaded dataset
  - Check ≥50,000 genomes downloaded
  - Verify all checksums
  - Check for corrupt files
  - Document any download failures
  - Generate dataset summary

- [ ] Task: Run download tests (Green phase)
  - Run `julia/test/test_robust_download.jl`
  - Confirm all tests pass
  - Verify retry logic works
  - Verify rate limiting compliance

- [ ] Task: Conductor - User Manual Verification 'Phase 3: Large-Scale NCBI Download' (Protocol in workflow.md)

---

## Phase 4: Production Pipeline Execution

**Goal**: Process 50k replicons with cross-validation on sample.

### Tasks

- [ ] Task: Write tests for production pipeline
  - Create `julia/test/test_production_pipeline.jl`
  - Test pipeline on 100 replicons
  - Test cross-validation sampling
  - Test output table generation
  - Run tests and confirm they pass

- [ ] Task: Run production pipeline
  - Execute: `make atlas SCALE=50000 SEED=42`
  - Enable batch processing (batch-size=1000)
  - Enable checkpointing
  - Monitor progress (estimated: 12-24 hours)
  - Log all processing statistics

- [ ] Task: Run cross-validation on sample
  - Randomly sample 1000 replicons from 50k
  - Run full cross-validation suite
  - Verify 100% agreement
  - Document any discrepancies
  - Save results to `data/cross_validation_50k_sample.json`

- [ ] Task: Verify output tables
  - Check all tables exist and are complete
  - Verify row counts (≥50,000 replicons)
  - Check schema compliance
  - Validate metric ranges
  - Run data validation suite

- [ ] Task: Generate epistemic knowledge layer
  - Run: `make epistemic SCALE=50000 SEED=42`
  - Export knowledge records
  - Verify knowledge layer completeness
  - Validate epistemic records

- [ ] Task: Conductor - User Manual Verification 'Phase 4: Production Pipeline Execution' (Protocol in workflow.md)

---

## Phase 5: Quality Assurance and Validation

**Goal**: Ensure data quality and reproducibility at production scale.

### Tasks

- [ ] Task: Run comprehensive data validation
  - Execute technical validation suite
  - Check for missing values
  - Verify foreign key integrity
  - Validate metric ranges (e.g., 0 ≤ d_min/L ≤ 1)
  - Document validation results

- [ ] Task: Test reproducibility
  - Re-run pipeline on 1000-replicon sample with same SEED
  - Verify bit-exact results
  - Document any non-determinism
  - Ensure reproducibility guarantee

- [ ] Task: Verify taxonomic diversity
  - Analyze taxonomic distribution of 50k dataset
  - Ensure major bacterial phyla represented
  - Document diversity statistics
  - Create taxonomic summary table

- [ ] Task: Generate quality report
  - Create `docs/atlas_50k_quality_report.md`
  - Include: dataset statistics, validation results, cross-validation summary
  - Document any issues or limitations
  - Provide quality metrics

- [ ] Task: Conductor - User Manual Verification 'Phase 5: Quality Assurance and Validation' (Protocol in workflow.md)

---

## Phase 6: Zenodo Release and Publication Preparation

**Goal**: Create DOI-versioned dataset release and prepare Scientific Data manuscript.

### Tasks

- [ ] Task: Create Zenodo snapshot
  - Run: `make snapshot SCALE=50000 SEED=42`
  - Package all tables (CSV + Parquet)
  - Include manifest and metadata
  - Generate README for dataset
  - Create archive (ZIP or tar.gz)

- [ ] Task: Upload to Zenodo and assign DOI
  - Create Zenodo deposition
  - Upload dataset archive
  - Add metadata from `.zenodo.json`
  - Publish and obtain DOI
  - Update `.zenodo.json` with assigned DOI

- [ ] Task: Write Data Descriptor Methods section
  - Create `paper/sections/methods.tex`
  - Describe computational pipeline
  - Document operator definitions
  - Explain symmetry metrics
  - Include cross-validation approach

- [ ] Task: Write Data Records section
  - Create `paper/sections/data_records.tex`
  - Document table schemas
  - Describe file formats
  - Explain data organization
  - Include Zenodo DOI and access information

- [ ] Task: Write Technical Validation section
  - Create `paper/sections/technical_validation.tex`
  - Document validation procedures
  - Present cross-validation results
  - Show biological validation (E. coli)
  - Include quality metrics

- [ ] Task: Generate publication figures
  - Create figure: Dataset composition (taxonomic diversity)
  - Create figure: Symmetry metric distributions
  - Create figure: Cross-validation results
  - Create figure: E. coli validation (ori-ter correlation)
  - Save to `paper/figures/`

- [ ] Task: Update README and documentation
  - Update `README.md` with 50k dataset information
  - Add Zenodo DOI badge
  - Update usage examples
  - Add citation information

- [ ] Task: Conductor - User Manual Verification 'Phase 6: Zenodo Release and Publication Preparation' (Protocol in workflow.md)

---

## Quality Gates

Before marking this track complete, verify:

- [ ] ≥50,000 replicons processed successfully
- [ ] Cross-validation passes on sample (≥1000 replicons)
- [ ] Processing time <24 hours
- [ ] All output tables complete and valid
- [ ] Zenodo snapshot created with DOI
- [ ] Data descriptor sections written
- [ ] All tests pass with >80% coverage
- [ ] Documentation complete and reviewed
- [ ] Reproducibility verified

---

## Success Metrics

### Scale Metrics
- ✅ ≥50,000 replicons processed
- ✅ Taxonomic diversity: ≥10 phyla
- ✅ Processing time: <24 hours
- ✅ Memory usage: <64 GB peak

### Quality Metrics
- ✅ Cross-validation: 100% on sample
- ✅ Data validation: All checks pass
- ✅ Reproducibility: Bit-exact with same SEED
- ✅ No missing values or errors

### Publication Metrics
- ✅ Zenodo DOI assigned
- ✅ Data descriptor complete
- ✅ Figures publication-quality
- ✅ Ready for Scientific Data submission

---

## Performance Targets

Based on E. coli benchmarking, target metrics:

- **Per-Replicon Time**: <1 second average
- **Total Time**: <14 hours for 50k (with parallelization)
- **Memory**: <32 GB peak (with batch processing)
- **Disk**: ~100 GB total (sequences + tables)

---

## Notes

- This track depends on E. coli track completion
- Performance optimizations are critical for success
- Incremental processing enables multi-day runs if needed
- Cross-validation on sample (not full 50k) balances thoroughness with practicality
- Zenodo release is the final deliverable for Scientific Data

---

**Plan Version**: 1.0  
**Last Updated**: 2025-12-23
