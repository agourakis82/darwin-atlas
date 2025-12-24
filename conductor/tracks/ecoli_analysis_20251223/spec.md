# Track Specification: E. coli Symmetry Analysis and Validation

## Track ID
`ecoli_analysis_20251223`

## Type
Feature / Validation Study

## Status
New

## Priority
🟢 Medium (Validation before scaling)

---

## Problem Statement

### Current State

The Darwin Atlas has been tested with small datasets (MAX=200, ~445 replicons) across diverse bacterial species. Before scaling to 50,000 replicons, we need to:

1. **Validate biological relevance** of symmetry metrics on a well-studied organism
2. **Test system robustness** with a focused, homogeneous dataset
3. **Establish baseline** for comparative analysis across strains
4. **Identify optimization opportunities** before large-scale processing

### Why E. coli?

**Escherichia coli** is the ideal validation organism because:

1. **Well-Studied**: Most extensively characterized bacterial species
2. **Genomic Diversity**: Hundreds of sequenced strains with known biology
3. **Reference Quality**: High-quality complete genomes in RefSeq
4. **Biological Validation**: Known replication origins, genomic features for validation
5. **Literature Comparison**: Published symmetry and structural studies for comparison

### Opportunity

A focused E. coli analysis will:
- Validate that symmetry metrics correlate with known biological features
- Test cross-validation at moderate scale (~100-200 genomes)
- Identify performance bottlenecks before 50k scale
- Provide publication-ready results for Scientific Data manuscript
- Enable strain-level comparative analysis

---

## Goals and Objectives

### Primary Goal
Process and analyze ~100-200 complete E. coli genomes to validate symmetry metrics and prepare for large-scale atlas generation.

### Specific Objectives

1. **Dataset Curation**
   - Query NCBI for complete E. coli genomes (RefSeq quality)
   - Download ~100-200 representative strains
   - Include diverse pathotypes (K-12, O157:H7, etc.)
   - Document strain metadata (pathotype, isolation source, etc.)

2. **Symmetry Analysis**
   - Compute exact symmetry metrics (orbit size, palindromes, RC-fixed)
   - Compute approximate symmetry (d_min/L) with multiple window sizes
   - Run cross-validation between Julia and Demetrios implementations
   - Generate comprehensive output tables

3. **Biological Validation**
   - Compare symmetry patterns with known replication origins (DoriC database)
   - Analyze GC skew and ori-ter predictions
   - Correlate symmetry with genomic features
   - Validate against published E. coli structural studies

4. **Performance Benchmarking**
   - Measure processing time per replicon
   - Profile memory usage
   - Identify computational bottlenecks
   - Estimate resources needed for 50k scale

5. **Comparative Analysis**
   - Compare symmetry metrics across E. coli strains
   - Identify conserved vs. variable symmetry patterns
   - Analyze pathotype-specific signatures
   - Generate publication-quality visualizations

---

## Success Criteria

### Must Have (P0)

- [ ] **Dataset Complete**: ≥100 complete E. coli genomes downloaded and processed
- [ ] **Cross-Validation Passing**: 100% agreement between Julia and Demetrios
- [ ] **All Metrics Computed**: Exact symmetry, approximate symmetry, biology metrics
- [ ] **Output Tables Generated**: CSV and Parquet files with complete results
- [ ] **Performance Benchmarked**: Processing time and memory usage documented

### Should Have (P1)

- [ ] **Biological Validation**: Symmetry correlates with known ori-ter locations
- [ ] **Strain Comparison**: Comparative analysis across pathotypes
- [ ] **Visualizations**: Publication-quality figures and plots
- [ ] **Documentation**: Analysis report with findings and insights

### Nice to Have (P2)

- [ ] **Statistical Analysis**: Significance testing for strain differences
- [ ] **Literature Comparison**: Compare with published E. coli symmetry studies
- [ ] **Interactive Queries**: DuckDB queries for exploratory analysis

---

## Scope

### In Scope

1. **NCBI Data Acquisition**
   - Query NCBI Assembly for E. coli (taxid:562)
   - Filter for complete genomes (assembly_level="Complete Genome")
   - Download FASTA sequences
   - Generate manifest with metadata

2. **Symmetry Computation**
   - Run full pipeline with cross-validation enabled
   - Compute all metrics (exact, approximate, biology)
   - Generate atlas tables (replicons, windows, stats)
   - Export epistemic knowledge layer

3. **Validation and Analysis**
   - Compare with DoriC replication origins
   - Analyze GC skew patterns
   - Compute strain-level statistics
   - Generate summary visualizations

4. **Performance Analysis**
   - Profile pipeline execution
   - Measure per-replicon processing time
   - Monitor memory usage
   - Document bottlenecks

5. **Documentation**
   - Analysis report with findings
   - Performance benchmarks
   - Recommendations for scaling

### Out of Scope

1. **Performance Optimization**: Identify bottlenecks but don't optimize (separate track)
2. **Full 50k Scale**: This track focuses on E. coli only
3. **New Metrics**: Use existing metrics, no new features
4. **Web Interface**: Analysis only, no visualization dashboard

---

## Technical Approach

### Phase 1: Dataset Curation

**Goal**: Download and validate ~100-200 complete E. coli genomes

**Approach**:
1. Query NCBI Assembly API for E. coli (taxid:562)
2. Filter criteria:
   - `assembly_level="Complete Genome"`
   - `refseq_category="reference genome"` or `"representative genome"`
   - Exclude partial or scaffold assemblies
3. Download FASTA sequences via NCBI FTP
4. Generate manifest with:
   - Assembly accession
   - Strain name
   - Pathotype (if available)
   - Isolation source
   - RefSeq category
   - Download timestamp and checksum

**Output**: `data/ecoli/manifest.jsonl`, `data/ecoli/raw/*.fna.gz`

### Phase 2: Symmetry Analysis

**Goal**: Compute all symmetry metrics with cross-validation

**Approach**:
1. Run pipeline: `make atlas MAX=200 SEED=42` (filtered for E. coli)
2. Enable cross-validation for all metrics
3. Compute:
   - Exact symmetry (orbit size, palindromes, RC-fixed)
   - Approximate symmetry (d_min/L) with windows [1000, 5000, 10000] bp
   - Biology metrics (k-mer inversion, GC skew, inverted repeats)
4. Generate output tables in `data/ecoli/tables/`

**Output**: 
- `ecoli_replicons.csv`
- `ecoli_windows_exact.csv`
- `ecoli_approx_symmetry.csv`
- `ecoli_biology_metrics.csv`

### Phase 3: Biological Validation

**Goal**: Validate symmetry metrics against known E. coli biology

**Approach**:
1. Fetch DoriC replication origins for E. coli
2. Compare d_min/L minima with ori locations
3. Analyze GC skew patterns and ori-ter predictions
4. Correlate symmetry with:
   - Replication origin proximity
   - Genomic islands
   - Pathogenicity islands (for pathogenic strains)

**Output**: `docs/ecoli_validation_report.md`

### Phase 4: Comparative Analysis

**Goal**: Compare symmetry patterns across E. coli strains

**Approach**:
1. Group strains by pathotype (K-12, O157:H7, etc.)
2. Compute strain-level statistics:
   - Mean/median orbit size
   - Mean/median d_min/L
   - Palindrome density
3. Statistical testing for differences between groups
4. Generate visualizations (box plots, heatmaps, etc.)

**Output**: `docs/ecoli_comparative_analysis.md`, `data/ecoli/figures/`

### Phase 5: Performance Benchmarking

**Goal**: Measure performance and identify bottlenecks

**Approach**:
1. Profile pipeline execution with Julia `@profile`
2. Measure:
   - Total processing time
   - Per-replicon processing time
   - Memory usage (peak and average)
   - Disk I/O
3. Identify hotspots (parsing, computation, I/O)
4. Extrapolate to 50k scale

**Output**: `docs/ecoli_performance_benchmarks.md`

---

## Dependencies

### External Dependencies

- **NCBI Assembly Database**: E. coli genomes (taxid:562)
- **DoriC Database**: Replication origin annotations
- **Julia Packages**: Already installed (BioSequences, DataFrames, etc.)
- **Demetrios Library**: Already built and functional

### Internal Dependencies

- **Working FFI**: ✅ Verified in previous track
- **Cross-Validation**: ✅ Operational (100% passing)
- **Pipeline**: ✅ Functional (tested at MAX=200)

### Blocking Issues

- None (all prerequisites met)

### Blocked By This Track

- Large-scale atlas (50k replicons) - needs performance insights from this track

---

## Risks and Mitigation

### Risk 1: Insufficient E. coli Genomes in NCBI

**Probability**: Low  
**Impact**: Low  
**Mitigation**: 
- E. coli is extensively sequenced (>1000 complete genomes available)
- Can adjust target to available genomes
- Minimum viable: 50 genomes

### Risk 2: Performance Issues at 100-200 Scale

**Probability**: Medium  
**Impact**: Medium  
**Mitigation**:
- This is actually a goal (identify bottlenecks)
- Document issues for optimization track
- May need to reduce dataset size temporarily

### Risk 3: Biological Validation Fails

**Probability**: Low  
**Impact**: Medium  
**Mitigation**:
- Symmetry metrics are mathematically sound
- If no correlation with ori, document as finding
- May indicate need for metric refinement

### Risk 4: Cross-Validation Failures at Scale

**Probability**: Low  
**Impact**: High  
**Mitigation**:
- FFI already verified working
- Run cross-validation incrementally
- Debug any failures immediately

---

## Testing Strategy

### Unit Tests

**Already Covered**:
- FFI functions tested (previous track)
- Cross-validation suite passing

**New Tests**:
- E. coli-specific edge cases
- Strain metadata parsing
- DoriC integration

### Integration Tests

**Pipeline Testing**:
- Run full pipeline on 10 E. coli genomes
- Verify all output tables generated
- Check cross-validation passes
- Validate output schema

**End-to-End**:
- Download → Process → Validate → Analyze
- Verify reproducibility (same SEED produces same results)
- Test on different E. coli strains

### Validation Tests

**Biological Validation**:
- Symmetry minima near known ori locations
- GC skew patterns match literature
- Strain-specific features detected

**Data Quality**:
- No missing values in output tables
- All checksums valid
- Provenance complete

---

## Documentation Requirements

### Analysis Report

**File**: `docs/ecoli_analysis_report.md`

**Contents**:
1. Dataset description (strains, pathotypes, sources)
2. Symmetry metrics summary statistics
3. Biological validation results
4. Comparative analysis across strains
5. Key findings and insights

### Performance Report

**File**: `docs/ecoli_performance_benchmarks.md`

**Contents**:
1. Processing time breakdown
2. Memory usage analysis
3. Identified bottlenecks
4. Extrapolation to 50k scale
5. Optimization recommendations

### Visualization Gallery

**Directory**: `data/ecoli/figures/`

**Figures**:
1. Symmetry distribution across strains
2. d_min/L profiles with ori-ter annotations
3. GC skew patterns
4. Strain comparison heatmaps
5. Performance benchmarks

---

## Timeline Estimate

**Total Duration**: 1-2 weeks

### Week 1: Data Acquisition and Processing
- Days 1-2: Query NCBI, download E. coli genomes
- Days 3-4: Run pipeline with cross-validation
- Day 5: Verify outputs and data quality

### Week 2: Analysis and Documentation
- Days 1-2: Biological validation (DoriC, GC skew)
- Days 3: Comparative analysis across strains
- Days 4: Performance benchmarking
- Day 5: Documentation and visualization

---

## Acceptance Criteria

This track is complete when:

1. ✅ ≥100 E. coli genomes processed successfully
2. ✅ Cross-validation passes 100% for all genomes
3. ✅ All output tables generated (CSV + Parquet)
4. ✅ Biological validation shows correlation with known features
5. ✅ Comparative analysis across strains complete
6. ✅ Performance benchmarks documented
7. ✅ Analysis report written
8. ✅ Visualizations generated
9. ✅ Recommendations for 50k scale documented

---

## Success Metrics

### Dataset Metrics
- ✅ ≥100 complete E. coli genomes
- ✅ Diverse pathotypes represented
- ✅ High-quality RefSeq assemblies
- ✅ Complete metadata and provenance

### Computational Metrics
- ✅ Cross-validation: 100% passing
- ✅ Processing time: <1 hour for 100 genomes
- ✅ Memory usage: <16 GB peak
- ✅ No errors or warnings

### Scientific Metrics
- ✅ Symmetry correlates with replication origins
- ✅ GC skew patterns match literature
- ✅ Strain-specific signatures detected
- ✅ Results suitable for publication

---

## Follow-Up Tracks

After completing this track, create:

1. **Track: Scale to 10k Replicons**
   - Apply lessons learned from E. coli analysis
   - Implement performance optimizations
   - Test incremental processing

2. **Track: Scale to 50k Replicons (Full Atlas)**
   - Production-scale processing
   - Final dataset for Scientific Data publication
   - Zenodo DOI release

---

## References

- [ROADMAP.md](../../ROADMAP.md) - Phase 3: Escala (Mês 5-6)
- [EVOLUTION_PLAN.md](../../EVOLUTION_PLAN.md) - Scaling strategy
- [julia/src/NCBIFetch.jl](../../julia/src/NCBIFetch.jl) - NCBI download
- [julia/src/DoriC.jl](../../julia/src/DoriC.jl) - Replication origin data
- [julia/src/BiologyMetrics.jl](../../julia/src/BiologyMetrics.jl) - Biology metrics

---

**Created**: 2025-12-23  
**Last Updated**: 2025-12-23  
**Track ID**: ecoli_analysis_20251223
