# Track Specification: Scale Atlas to 50k Replicons for Publication

## Track ID
`scale_50k_20251223`

## Type
Feature / Production Scale

## Status
New

## Priority
🟡 High (Publication requirement)

---

## Problem Statement

### Current State

The Darwin Atlas has been validated with:
- Small-scale testing (MAX=200, ~445 replicons)
- E. coli focused analysis (~100-200 genomes)
- Functional cross-validation (100% passing)

However, the **Scientific Data publication requires a comprehensive dataset** covering:
- ≥50,000 complete bacterial replicons
- Diverse taxonomic representation
- Complete provenance and validation
- DOI-versioned release via Zenodo

### Challenge

Scaling from 200 to 50,000 replicons requires:

1. **Performance Optimization**: Current pipeline may be too slow
2. **Incremental Processing**: Cannot process 50k in single run
3. **Memory Management**: Must handle large datasets efficiently
4. **Fault Tolerance**: Resume capability for multi-day runs
5. **Quality Assurance**: Maintain cross-validation at scale

### Opportunity

A 50k-replicon atlas will:
- Meet Scientific Data publication requirements
- Provide comprehensive bacterial symmetry database
- Enable large-scale comparative genomics
- Showcase Demetrios at production scale
- Establish DOSA as reference dataset in the field

---

## Goals and Objectives

### Primary Goal
Process ≥50,000 complete bacterial replicons to create a production-ready, DOI-versioned atlas for Scientific Data publication.

### Specific Objectives

1. **Performance Optimization**
   - Implement optimizations identified in E. coli benchmarking
   - Parallelize independent computations
   - Optimize I/O operations (Parquet writes, FASTA parsing)
   - Target: <24 hours total processing time

2. **Incremental Processing**
   - Implement batch processing (process in chunks of 1000-5000)
   - Add checkpoint/resume capability
   - Enable partial dataset updates
   - Maintain provenance across batches

3. **Robust Pipeline**
   - Handle download failures gracefully
   - Retry failed downloads automatically
   - Skip invalid sequences with logging
   - Comprehensive error reporting

4. **Quality Assurance**
   - Run cross-validation on representative sample (1000 replicons)
   - Validate all output tables
   - Verify data integrity (checksums, schema)
   - Ensure reproducibility (deterministic with SEED)

5. **Publication Preparation**
   - Generate final atlas tables (CSV + Parquet)
   - Create Zenodo snapshot with metadata
   - Assign DOI
   - Prepare data descriptor for Scientific Data

---

## Success Criteria

### Must Have (P0)

- [ ] **Dataset Scale**: ≥50,000 complete bacterial replicons processed
- [ ] **Taxonomic Diversity**: Represent major bacterial phyla
- [ ] **Cross-Validation**: 100% passing on representative sample (≥1000 replicons)
- [ ] **Processing Time**: Complete in <24 hours on standard hardware
- [ ] **Data Quality**: All validation checks pass
- [ ] **Zenodo Release**: Dataset uploaded with DOI assigned

### Should Have (P1)

- [ ] **Performance**: ≥10x faster than baseline (via optimization)
- [ ] **Incremental Processing**: Checkpoint/resume functional
- [ ] **Fault Tolerance**: Automatic retry for transient failures
- [ ] **Documentation**: Complete data descriptor for Scientific Data
- [ ] **Reproducibility**: Bit-exact results with same SEED

### Nice to Have (P2)

- [ ] **Parallel Processing**: Multi-threaded computation
- [ ] **Progress Monitoring**: Real-time progress dashboard
- [ ] **Quality Metrics**: Per-batch quality reports
- [ ] **Taxonomic Analysis**: Symmetry patterns by phylum

---

## Scope

### In Scope

1. **Performance Optimization**
   - Profile current pipeline
   - Implement identified optimizations
   - Parallelize independent operations
   - Optimize I/O (FASTA parsing, Parquet writes)

2. **Incremental Processing**
   - Batch processing implementation
   - Checkpoint/resume mechanism
   - Progress tracking and reporting
   - Partial dataset updates

3. **Large-Scale Download**
   - Query NCBI for ≥50k complete bacterial genomes
   - Implement robust download with retry logic
   - Handle rate limiting and timeouts
   - Generate comprehensive manifest

4. **Quality Assurance**
   - Cross-validation on sample
   - Data validation suite
   - Schema verification
   - Provenance tracking

5. **Publication Preparation**
   - Generate final atlas tables
   - Create Zenodo snapshot
   - Write data descriptor
   - Assign DOI

### Out of Scope

1. **New Metrics**: Use existing metrics only
2. **Taxonomic Analysis**: Basic diversity only, no deep phylogenetic analysis
3. **Visualization Dashboard**: Static figures only, no interactive interface
4. **API Development**: Dataset release only, no API service

---

## Technical Approach

### Phase 1: Performance Optimization

**Based on E. coli benchmarking**, implement optimizations:

1. **Parallel Processing**
   - Use Julia `Threads.@threads` for independent replicons
   - Parallelize FASTA parsing
   - Parallelize metric computation

2. **I/O Optimization**
   - Batch Parquet writes
   - Stream FASTA parsing (avoid loading entire file)
   - Optimize DataFrame operations

3. **Memory Management**
   - Process in batches to limit memory
   - Clear intermediate results
   - Use memory-efficient data structures

### Phase 2: Incremental Processing

**Implement checkpoint/resume**:

1. **Batch Processing**
   - Process in chunks of 1000-5000 replicons
   - Save intermediate results after each batch
   - Track progress in state file

2. **Checkpoint Mechanism**
   - Save state: `data/checkpoint.json`
   - Record: processed replicons, current batch, timestamp
   - Resume: Skip already-processed replicons

3. **Fault Tolerance**
   - Retry failed downloads (max 3 attempts)
   - Skip invalid sequences with logging
   - Continue processing on non-fatal errors

### Phase 3: Large-Scale Download

**Download 50k+ genomes**:

1. **NCBI Query**
   - Query for complete bacterial genomes
   - Filter: `assembly_level="Complete Genome"`
   - Sort by quality (RefSeq > GenBank)
   - Limit to target count (50k-100k)

2. **Download Strategy**
   - Batch downloads (100-500 at a time)
   - Respect NCBI rate limits (3 req/sec)
   - Retry on timeout or network error
   - Verify checksums after download

3. **Manifest Generation**
   - Record all metadata (accession, taxonomy, quality)
   - Generate SHA-256 checksums
   - Track download timestamps
   - Save to `data/manifest/manifest_50k.jsonl`

### Phase 4: Quality Assurance

**Ensure data quality at scale**:

1. **Cross-Validation Sample**
   - Randomly sample 1000 replicons
   - Run full cross-validation
   - Verify 100% agreement
   - Document any discrepancies

2. **Data Validation**
   - Check schema compliance
   - Verify no missing values
   - Validate metric ranges
   - Check foreign key integrity

3. **Reproducibility Test**
   - Re-run pipeline with same SEED
   - Verify bit-exact results
   - Document any non-determinism

### Phase 5: Publication Preparation

**Prepare for Scientific Data**:

1. **Final Atlas Tables**
   - Generate CSV (human-readable)
   - Generate Parquet (efficient queries)
   - Create DuckDB database
   - Verify schema and documentation

2. **Zenodo Snapshot**
   - Package dataset with metadata
   - Upload to Zenodo
   - Assign DOI
   - Update `.zenodo.json`

3. **Data Descriptor**
   - Write Methods section
   - Write Data Records section
   - Write Technical Validation section
   - Prepare figures and tables

---

## Dependencies

### External Dependencies

- **NCBI Assembly Database**: Source of 50k genomes
- **Zenodo**: DOI assignment and archival
- **Computational Resources**: Multi-core CPU, ≥32 GB RAM, ≥200 GB disk

### Internal Dependencies

- **E. coli Track**: Performance insights and validation approach
- **Working FFI**: Cross-validation capability
- **Optimized Pipeline**: Performance improvements

### Blocking Issues

- Must complete E. coli track first (performance insights needed)

### Blocked By This Track

- Scientific Data manuscript submission
- Atlas v3.0 development
- Community release and adoption

---

## Risks and Mitigation

### Risk 1: Processing Time Exceeds 24 Hours

**Probability**: Medium  
**Impact**: High  
**Mitigation**:
- Implement performance optimizations from E. coli track
- Use parallel processing
- Consider cloud computing if needed
- May reduce target to 30k-40k if necessary

### Risk 2: NCBI Download Failures

**Probability**: High (at 50k scale)  
**Impact**: Medium  
**Mitigation**:
- Implement robust retry logic
- Save progress frequently
- Resume capability for interrupted downloads
- Alternative: Use pre-downloaded datasets if available

### Risk 3: Memory Exhaustion

**Probability**: Medium  
**Impact**: High  
**Mitigation**:
- Batch processing with memory limits
- Stream processing where possible
- Monitor memory usage
- Use swap if needed (slower but functional)

### Risk 4: Cross-Validation Failures at Scale

**Probability**: Low  
**Impact**: High  
**Mitigation**:
- Cross-validate sample (1000) not full dataset
- Debug any failures immediately
- May indicate edge cases not covered in testing

### Risk 5: Disk Space Exhaustion

**Probability**: Medium  
**Impact**: High  
**Mitigation**:
- Estimate: ~50 GB for sequences, ~10 GB for tables
- Monitor disk usage
- Clean up intermediate files
- Compress raw sequences

---

## Testing Strategy

### Unit Tests

**Performance Optimizations**:
- Test parallel processing functions
- Test batch processing logic
- Test checkpoint/resume mechanism

**Download Robustness**:
- Test retry logic
- Test error handling
- Test manifest generation

### Integration Tests

**End-to-End**:
- Test full pipeline on 100 replicons
- Verify checkpoint/resume works
- Test cross-validation on sample

**Incremental Processing**:
- Process 1000 replicons in batches of 100
- Verify results are identical to single-batch processing
- Test resume after interruption

### Stress Tests

**Large Scale**:
- Test with 5000 replicons
- Test with 10000 replicons
- Monitor memory and disk usage
- Verify no resource leaks

---

## Documentation Requirements

### Technical Documentation

1. **Performance Optimization Report**
   - Optimizations implemented
   - Benchmark results (before/after)
   - Speedup achieved

2. **Scaling Guide**
   - How to run 50k pipeline
   - Resource requirements
   - Troubleshooting common issues

3. **Checkpoint/Resume Guide**
   - How to resume interrupted runs
   - State file format
   - Recovery procedures

### Scientific Documentation

1. **Data Descriptor (Scientific Data)**
   - Background and summary
   - Methods (computational pipeline)
   - Data records (table schemas)
   - Technical validation
   - Usage notes

2. **Dataset README**
   - Dataset description
   - File formats and schemas
   - Citation information
   - License and usage terms

---

## Timeline Estimate

**Total Duration**: 2-3 weeks

### Week 1: Optimization and Incremental Processing
- Days 1-2: Implement performance optimizations
- Days 3-4: Implement batch processing and checkpointing
- Day 5: Test on 1000-5000 replicons

### Week 2: Large-Scale Processing
- Days 1-2: Download 50k genomes from NCBI
- Days 3-5: Run full pipeline with cross-validation sample

### Week 3: Quality Assurance and Publication
- Days 1-2: Validate outputs and run quality checks
- Days 3-4: Create Zenodo snapshot and assign DOI
- Day 5: Write data descriptor sections

---

## Acceptance Criteria

This track is complete when:

1. ✅ ≥50,000 replicons processed successfully
2. ✅ Cross-validation passes on sample (≥1000 replicons)
3. ✅ Processing time <24 hours
4. ✅ All output tables complete (CSV + Parquet)
5. ✅ Zenodo snapshot created with DOI
6. ✅ Data descriptor written
7. ✅ All validation checks pass
8. ✅ Reproducibility verified
9. ✅ Documentation complete

---

## References

- [ROADMAP.md](../../ROADMAP.md) - Phase 3: Escala
- [EVOLUTION_PLAN.md](../../EVOLUTION_PLAN.md) - Scaling strategy
- [E. coli Track](../ecoli_analysis_20251223/) - Performance insights
- [julia/scripts/run_pipeline.jl](../../julia/scripts/run_pipeline.jl) - Current pipeline

---

**Created**: 2025-12-23  
**Last Updated**: 2025-12-23  
**Track ID**: scale_50k_20251223  
**Depends On**: ecoli_analysis_20251223
