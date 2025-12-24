# Implementation Plan: E. coli Symmetry Analysis and Validation

**Track ID**: ecoli_analysis_20251223  
**Created**: 2025-12-23  
**Status**: New

---

## Overview

This plan implements a focused analysis of E. coli genomes to validate symmetry metrics, test system robustness, and prepare for large-scale atlas generation. The plan follows Test-Driven Development (TDD) principles as specified in the workflow.

---

## Phase 1: Dataset Curation and Download

**Goal**: Download and validate ~100-200 complete E. coli genomes from NCBI.

### Tasks

- [ ] Task: Create E. coli dataset download script
  - Create `julia/scripts/download_ecoli.jl`
  - Implement NCBI query for E. coli (taxid:562)
  - Filter for complete genomes (assembly_level="Complete Genome")
  - Include strain metadata (name, pathotype, isolation source)
  - Add command-line arguments for MAX and SEED

- [ ] Task: Write tests for E. coli download functionality
  - Create `julia/test/test_ecoli_download.jl`
  - Test NCBI query construction
  - Test metadata parsing
  - Test download with MAX=5 (small test)
  - Run tests and confirm they pass

- [ ] Task: Download E. coli dataset
  - Run `julia --project=julia julia/scripts/download_ecoli.jl --max=150 --seed=42`
  - Verify downloads complete successfully
  - Check manifest file created
  - Verify checksums for all downloaded files

- [ ] Task: Validate downloaded dataset
  - Verify ≥100 genomes downloaded
  - Check all FASTA files are valid
  - Confirm diverse strains (K-12, O157:H7, etc.)
  - Document dataset composition in `data/ecoli/dataset_summary.md`

- [ ] Task: Conductor - User Manual Verification 'Phase 1: Dataset Curation and Download' (Protocol in workflow.md)

---

## Phase 2: Symmetry Analysis with Cross-Validation

**Goal**: Process E. coli genomes and compute all symmetry metrics with full cross-validation.

### Tasks

- [ ] Task: Write tests for E. coli pipeline execution
  - Create `julia/test/test_ecoli_pipeline.jl`
  - Test pipeline runs on small E. coli subset (5 genomes)
  - Test all output tables are generated
  - Test cross-validation is enabled
  - Run tests and confirm they fail initially (Red phase)

- [ ] Task: Create E. coli-specific pipeline script
  - Create `julia/scripts/run_ecoli_pipeline.jl`
  - Configure for E. coli dataset
  - Enable cross-validation for all metrics
  - Set window sizes: [1000, 5000, 10000] bp
  - Add progress reporting

- [ ] Task: Run E. coli pipeline with cross-validation
  - Execute `julia --project=julia julia/scripts/run_ecoli_pipeline.jl`
  - Monitor progress and cross-validation results
  - Verify no errors or cross-validation failures
  - Check all output tables generated

- [ ] Task: Verify pipeline outputs
  - Check `data/ecoli/tables/ecoli_replicons.csv` exists and is complete
  - Check `data/ecoli/tables/ecoli_windows_exact.csv` exists
  - Check `data/ecoli/tables/ecoli_approx_symmetry.csv` exists
  - Check `data/ecoli/tables/ecoli_biology_metrics.csv` exists
  - Verify row counts match expected values

- [ ] Task: Run tests and verify pipeline works (Green phase)
  - Run `julia/test/test_ecoli_pipeline.jl`
  - Confirm all tests pass
  - Verify cross-validation passed 100%
  - Document any issues or warnings

- [ ] Task: Conductor - User Manual Verification 'Phase 2: Symmetry Analysis with Cross-Validation' (Protocol in workflow.md)

---

## Phase 3: Biological Validation

**Goal**: Validate that symmetry metrics correlate with known E. coli biological features.

### Tasks

- [ ] Task: Write tests for biological validation
  - Create `julia/test/test_ecoli_validation.jl`
  - Test DoriC data fetching for E. coli
  - Test ori-ter correlation analysis
  - Test GC skew pattern validation
  - Run tests and confirm they fail (Red phase)

- [ ] Task: Implement DoriC integration for E. coli
  - Update `julia/src/DoriC.jl` if needed for E. coli-specific queries
  - Fetch replication origin coordinates for E. coli strains
  - Map DoriC origins to NCBI assembly accessions
  - Store in `data/ecoli/doric_origins.csv`

- [ ] Task: Analyze symmetry vs. replication origins
  - Create `julia/scripts/analyze_ecoli_ori.jl`
  - For each replicon, find d_min/L minimum position
  - Compare with DoriC ori location
  - Compute distance between predicted and known ori
  - Calculate correlation statistics

- [ ] Task: Analyze GC skew patterns
  - Use existing `julia/src/GCSkew.jl` module
  - Compute GC skew for all E. coli replicons
  - Estimate ori-ter from GC skew
  - Compare with symmetry-based predictions
  - Generate GC skew plots for representative strains

- [ ] Task: Run validation tests (Green phase)
  - Run `julia/test/test_ecoli_validation.jl`
  - Confirm all tests pass
  - Verify biological correlations are significant
  - Document validation results

- [ ] Task: Conductor - User Manual Verification 'Phase 3: Biological Validation' (Protocol in workflow.md)

---

## Phase 4: Comparative Analysis Across Strains

**Goal**: Compare symmetry patterns across E. coli strains and pathotypes.

### Tasks

- [ ] Task: Write tests for comparative analysis
  - Create `julia/test/test_ecoli_comparative.jl`
  - Test strain grouping by pathotype
  - Test statistical comparison functions
  - Run tests and confirm they fail (Red phase)

- [ ] Task: Implement strain classification
  - Create `julia/scripts/classify_ecoli_strains.jl`
  - Parse strain names to identify pathotypes
  - Group strains: K-12, O157:H7, UPEC, ETEC, etc.
  - Add pathotype column to replicons table

- [ ] Task: Compute strain-level statistics
  - Create `julia/scripts/ecoli_strain_stats.jl`
  - For each pathotype group, compute:
    - Mean/median/std orbit size
    - Mean/median/std d_min/L
    - Palindrome density
    - RC-fixed sequence count
  - Generate summary table: `data/ecoli/tables/strain_statistics.csv`

- [ ] Task: Statistical testing for strain differences
  - Implement Kruskal-Wallis test for group differences
  - Compute pairwise comparisons (Mann-Whitney U)
  - Apply multiple testing correction (FDR)
  - Document significant differences

- [ ] Task: Generate comparative visualizations
  - Create box plots for symmetry metrics by pathotype
  - Create heatmap of strain-level statistics
  - Create scatter plots (orbit size vs. d_min/L)
  - Save figures to `data/ecoli/figures/`

- [ ] Task: Run comparative tests (Green phase)
  - Run `julia/test/test_ecoli_comparative.jl`
  - Confirm all tests pass
  - Verify statistical tests are correct
  - Document comparative findings

- [ ] Task: Conductor - User Manual Verification 'Phase 4: Comparative Analysis Across Strains' (Protocol in workflow.md)

---

## Phase 5: Performance Benchmarking and Documentation

**Goal**: Measure performance, identify bottlenecks, and document findings.

### Tasks

- [ ] Task: Write tests for performance benchmarking
  - Create `julia/test/test_ecoli_performance.jl`
  - Test profiling functions
  - Test benchmark measurement
  - Run tests and confirm they pass

- [ ] Task: Profile E. coli pipeline execution
  - Create `julia/scripts/profile_ecoli_pipeline.jl`
  - Use `@profile` macro for detailed profiling
  - Identify top 10 hotspots (functions consuming most time)
  - Measure per-replicon processing time
  - Document in `docs/ecoli_performance_benchmarks.md`

- [ ] Task: Benchmark memory usage
  - Monitor memory during pipeline execution
  - Record peak memory usage
  - Identify memory-intensive operations
  - Estimate memory needs for 50k scale

- [ ] Task: Benchmark disk I/O
  - Measure time spent in file reading/writing
  - Measure Parquet write performance
  - Identify I/O bottlenecks
  - Document findings

- [ ] Task: Extrapolate to 50k scale
  - Based on E. coli benchmarks, estimate:
    - Total processing time for 50k replicons
    - Memory requirements
    - Disk space requirements
  - Identify critical optimizations needed
  - Document in performance report

- [ ] Task: Write comprehensive analysis report
  - Create `docs/ecoli_analysis_report.md`
  - Include:
    - Dataset description
    - Symmetry metrics summary
    - Biological validation results
    - Comparative analysis findings
    - Performance benchmarks
    - Recommendations for scaling

- [ ] Task: Create visualization summary
  - Compile all figures into organized gallery
  - Add captions and descriptions
  - Create README for figures directory
  - Ensure publication quality

- [ ] Task: Document recommendations for 50k scale
  - Based on all findings, document:
    - Required optimizations
    - Estimated resources (time, memory, disk)
    - Potential issues to address
    - Suggested approach for incremental processing
  - Add to analysis report

- [ ] Task: Conductor - User Manual Verification 'Phase 5: Performance Benchmarking and Documentation' (Protocol in workflow.md)

---

## Quality Gates

Before marking this track complete, verify:

- [ ] ≥100 E. coli genomes processed successfully
- [ ] Cross-validation passed 100% for all genomes
- [ ] All output tables complete and valid
- [ ] Biological validation shows significant correlations
- [ ] Comparative analysis reveals strain patterns
- [ ] Performance benchmarks documented
- [ ] Analysis report complete and reviewed
- [ ] Visualizations publication-quality
- [ ] Recommendations for 50k scale documented
- [ ] All tests pass with >80% coverage

---

## Success Metrics

### Dataset Metrics
- ✅ ≥100 E. coli genomes processed
- ✅ Diverse pathotypes (≥3 groups)
- ✅ Complete metadata and provenance
- ✅ All checksums valid

### Computational Metrics
- ✅ Cross-validation: 100% passing
- ✅ Processing time: <2 hours for 150 genomes
- ✅ Memory usage: <16 GB peak
- ✅ No errors or warnings

### Scientific Metrics
- ✅ Symmetry correlates with ori (p < 0.05)
- ✅ GC skew patterns validated
- ✅ Strain differences detected
- ✅ Results publication-ready

### Performance Metrics
- ✅ Bottlenecks identified
- ✅ 50k scale extrapolation complete
- ✅ Optimization priorities documented

---

## Dependencies

### External
- NCBI Assembly Database (E. coli genomes)
- DoriC Database (replication origins)
- Julia packages (already installed)

### Internal
- Working FFI (✅ verified)
- Cross-validation (✅ operational)
- Pipeline (✅ functional)

---

## Timeline

**Total Duration**: 1-2 weeks

- **Phase 1**: 2-3 days (Dataset curation)
- **Phase 2**: 2-3 days (Symmetry analysis)
- **Phase 3**: 2-3 days (Biological validation)
- **Phase 4**: 2-3 days (Comparative analysis)
- **Phase 5**: 2-3 days (Performance and documentation)

---

## Notes

- This track validates the system before large-scale processing
- E. coli provides biological ground truth for validation
- Performance insights will guide optimization for 50k scale
- Results will strengthen Scientific Data manuscript
- Follows TDD principles with comprehensive testing

---

**Plan Version**: 1.0  
**Last Updated**: 2025-12-23
