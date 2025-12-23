# Product Guidelines

## Communication Style and Tone

### Scientific and Formal

DOSA documentation, code comments, and outputs adopt a **scientific and formal** tone appropriate for peer-reviewed publication in Scientific Data (Nature Portfolio). All communication should:

- Use precise, unambiguous terminology from established scientific literature
- Maintain academic rigor suitable for journal reviewers and scientific audiences
- Employ formal grammar and complete sentences in documentation
- Cite relevant literature and mathematical foundations where applicable
- Avoid colloquialisms, informal language, and subjective statements

### Writing Principles

1. **Precision**: Every technical term must be defined on first use
2. **Objectivity**: Present facts and results without subjective interpretation
3. **Clarity**: Complex concepts should be explained systematically, building from fundamentals
4. **Completeness**: Provide sufficient detail for independent reproduction

### Example Comparisons

**Preferred (Scientific/Formal)**:
> "The dihedral group D_n acts on DNA sequences of length n through four operators: shift (S), reverse (R), complement (K), and reverse-complement (RC). The orbit size under this action quantifies the degree of rotational and reflectional symmetry."

**Avoid (Informal)**:
> "We use some group theory stuff to check how symmetric DNA sequences are by flipping and rotating them."

---

## Documentation Standards

### 1. Reproducibility-First

Every claim, result, and metric in DOSA must be independently verifiable:

#### Requirements

- **Exact Versions**: Document Julia version, Demetrios compiler version, and all dependency versions (via committed Manifest.toml)
- **Deterministic Seeds**: All random sampling must use documented seeds (default: SEED=42)
- **Parameter Transparency**: Every pipeline run must log MAX, SEED, window sizes, and other configuration parameters
- **Provenance Tracking**: Manifest files must include NCBI accession numbers, download timestamps, and SHA-256 checksums
- **Validation Scripts**: Include automated validation that verifies data integrity and computational correctness

#### Implementation Guidelines

- Commit `julia/Manifest.toml` to version control (never gitignore)
- Log all parameters to `data/manifest/run_metadata.jsonl`
- Include `make reproduce` target that regenerates published datasets bit-exactly
- Document system requirements (OS, RAM, disk space) in README

### 2. Mathematical Rigor

All algorithms and metrics must be formally defined with proper mathematical notation:

#### Requirements

- **Operator Definitions**: Formally define S, R, K, RC operators with domain and codomain
- **Group Theory**: Specify the dihedral group D_n structure, generators, and relations
- **Metric Definitions**: Provide precise mathematical definitions for d_min, orbit size, and other metrics
- **Algorithmic Complexity**: Document time and space complexity using Big-O notation
- **Proofs**: Include correctness proofs or citations for non-trivial algorithms

#### Notation Standards

- Use standard mathematical notation (e.g., ∈ for membership, ∀ for universal quantification)
- Define all symbols in a glossary or on first use
- Use LaTeX formatting in documentation where appropriate
- Maintain consistency with published literature on dihedral groups and sequence analysis

#### Example

```
Definition (Reverse-Complement Operator):
Let Σ = {A, C, G, T} be the DNA alphabet with complement map K: Σ → Σ
defined by K(A)=T, K(T)=A, K(C)=G, K(G)=C.

For a sequence s = s₁s₂...sₙ ∈ Σⁿ, the reverse-complement operator RC: Σⁿ → Σⁿ
is defined as:
  RC(s) = K(sₙ)K(sₙ₋₁)...K(s₁)

The operator RC has order 2 (RC² = identity) and generates a cyclic subgroup
of the dihedral group Dₙ.
```

### 3. FAIR Principles

DOSA must adhere to FAIR (Findable, Accessible, Interoperable, Reusable) data principles:

#### Findable

- **DOI Assignment**: Every dataset release receives a Zenodo DOI
- **Rich Metadata**: `.zenodo.json` includes title, authors, description, keywords, license
- **Searchable**: Metadata includes taxonomic terms, method keywords, and data types

#### Accessible

- **Open Access**: All data and code released under permissive licenses (Code: MIT, Data: CC-BY 4.0)
- **Multiple Formats**: Provide CSV (human-readable), Parquet (efficient), and JSONL (metadata)
- **Clear Documentation**: README with quick start, installation, and usage examples

#### Interoperable

- **Standard Formats**: Use widely-supported formats (CSV, Parquet, JSONL, not proprietary)
- **Typed Schema**: Document column types, units, and foreign key relationships
- **SQL Interface**: DuckDB integration for standard query language access
- **API Potential**: Design schema to support future REST API development

#### Reusable

- **Clear Licensing**: Explicit MIT (code) and CC-BY 4.0 (data) licenses in all files
- **Provenance**: Complete lineage from NCBI accessions to computed metrics
- **Validation**: Automated tests verify data integrity and correctness
- **Examples**: Include example queries and analysis scripts

---

## Code and Naming Conventions

### 1. Domain-Specific Terminology

Use established terms from bioinformatics, molecular biology, and mathematics consistently:

#### Preferred Terms

| Concept | Correct Term | Avoid |
|---------|--------------|-------|
| Circular bacterial chromosome | Replicon | Genome, chromosome, sequence |
| NCBI Assembly accession | Assembly accession | ID, accession, genome ID |
| Reverse-complement | RC, reverse-complement | rev-comp, rc, flip |
| Dihedral group | D_n, dihedral group | symmetry group, rotation group |
| Orbit size | Orbit size | equivalence class size, symmetry count |
| Window length | Window length (bp) | window size, chunk size |

#### Terminology Sources

- **Bioinformatics**: Follow NCBI and RefSeq terminology conventions
- **Group Theory**: Use standard notation from abstract algebra textbooks
- **Genomics**: Align with terms from Genome Biology, Nucleic Acids Research

### 2. Explicit Over Implicit

Prioritize clarity and self-documentation over brevity:

#### Naming Guidelines

**Functions/Methods**:
- Use verb phrases: `compute_orbit_size()`, `validate_sequence()`, `download_replicon()`
- Avoid abbreviations: `calculate_approximate_symmetry()` not `calc_approx_sym()`
- Be specific: `compute_dmin_normalized()` not `compute_metric()`

**Variables**:
- Use full words: `replicon_length_bp` not `rep_len` or `n`
- Include units: `window_length_bp`, `gc_fraction` (not `gc_percent`)
- Descriptive names: `assembly_accession` not `acc` or `id`

**Constants**:
- ALL_CAPS with underscores: `DEFAULT_WINDOW_LENGTH_BP`, `MAX_SEQUENCE_LENGTH_BP`
- Include context: `NCBI_BASE_URL` not `BASE_URL`

#### Examples

**Preferred**:
```julia
function compute_orbit_size(sequence::LongDNA, operators::Vector{Operator})
    unique_sequences = Set{LongDNA}()
    for operator in operators
        transformed = apply_operator(sequence, operator)
        push!(unique_sequences, transformed)
    end
    return length(unique_sequences)
end
```

**Avoid**:
```julia
function orb_sz(s, ops)
    u = Set()
    for o in ops
        push!(u, apply(s, o))
    end
    return length(u)
end
```

### 3. Cross-Language Consistency

Maintain identical naming between Julia and Demetrios implementations:

#### Consistency Requirements

- **Function Names**: `compute_orbit_size()` in both Julia and Demetrios
- **Variable Names**: `replicon_length_bp`, `window_length_bp` in both languages
- **Type Names**: `Replicon`, `SymmetryMetrics` in both languages
- **Constants**: `DEFAULT_WINDOW_LENGTH_BP` in both languages

#### Language-Specific Adaptations

While maintaining semantic consistency, respect language idioms:

**Julia**:
- Use snake_case for functions: `compute_orbit_size()`
- Use CamelCase for types: `RepliconMetadata`
- Use lowercase for modules: `DarwinAtlas`

**Demetrios**:
- Follow Demetrios style guide (assumed similar to Rust/D)
- Use appropriate type annotations and units of measure
- Maintain same semantic names even if syntax differs

#### Cross-Validation Transparency

Identical naming enables direct comparison in cross-validation:

```julia
# Julia
julia_result = DarwinAtlas.compute_orbit_size(sequence)

# Demetrios (via FFI)
demetrios_result = DemetriosFFI.compute_orbit_size(sequence)

# Comparison
@assert julia_result == demetrios_result "Cross-validation failed"
```

---

## Error Handling and Validation Philosophy

### 1. Fail-Fast with Context

Detect errors early and provide actionable diagnostic information:

#### Requirements

- **Early Detection**: Validate inputs before expensive computation
- **Informative Messages**: Include replicon ID, sequence position, expected vs. actual values
- **Actionable Guidance**: Suggest fixes or point to documentation
- **Structured Logging**: Use consistent log format with timestamps and severity levels

#### Examples

**Preferred**:
```julia
if length(sequence) < window_length_bp
    error("Replicon $(replicon_id): Sequence length $(length(sequence)) bp " *
          "is shorter than window length $(window_length_bp) bp. " *
          "Skipping window analysis for this replicon.")
end
```

**Avoid**:
```julia
if length(sequence) < window_length_bp
    error("Sequence too short")
end
```

### 2. Defensive Programming

Validate all inputs and check invariants throughout computation:

#### Validation Checklist

**Input Validation**:
- [ ] Sequence contains only valid nucleotides (A, C, G, T, N)
- [ ] Sequence length > 0
- [ ] Window length ≤ sequence length
- [ ] Parameters within valid ranges (e.g., 0 ≤ GC fraction ≤ 1)

**Preconditions**:
- [ ] Assert expected types and value ranges at function entry
- [ ] Check file existence before reading
- [ ] Verify network connectivity before NCBI downloads

**Postconditions**:
- [ ] Verify computed metrics are within valid ranges
- [ ] Check output file integrity (non-empty, valid format)
- [ ] Confirm cross-validation agreement within tolerance

**Invariants**:
- [ ] Orbit size ≤ 2n (dihedral group D_n has order 2n)
- [ ] 0 ≤ d_min/L ≤ 1 (normalized distance)
- [ ] Palindrome count ≤ sequence length

#### Implementation

```julia
function compute_dmin_normalized(sequence::LongDNA, window_length_bp::Int)
    # Preconditions
    @assert length(sequence) > 0 "Sequence must be non-empty"
    @assert window_length_bp > 0 "Window length must be positive"
    @assert window_length_bp ≤ length(sequence) "Window exceeds sequence length"
    
    # Computation
    dmin = compute_minimum_dihedral_distance(sequence, window_length_bp)
    dmin_normalized = dmin / window_length_bp
    
    # Postconditions
    @assert 0 ≤ dmin_normalized ≤ 1 "Normalized distance out of range: $(dmin_normalized)"
    
    return dmin_normalized
end
```

### 3. Epistemic Transparency

Use type systems to encode constraints and make assumptions explicit:

#### Demetrios Refinement Types

Leverage Demetrios refinement types to enforce constraints at compile time:

```demetrios
// Normalized distance must be in [0, 1]
type NormalizedDistance = f64 where x => 0.0 <= x && x <= 1.0;

// Sequence length must be positive
type SequenceLength = i64 where n => n > 0;

// Window length must not exceed sequence length
fn compute_dmin(seq_len: SequenceLength, window_len: SequenceLength where w => w <= seq_len) 
    -> NormalizedDistance {
    // Implementation guaranteed to satisfy constraints
}
```

#### Julia Type Annotations

Use Julia's type system for documentation and dispatch:

```julia
# Explicit types document expectations
function compute_orbit_size(
    sequence::LongDNA{4},  # 4-bit encoding (A, C, G, T)
    operators::Vector{Operator}
)::Int64  # Orbit size is always a positive integer
    # Implementation
end
```

#### Explicit Assumptions

Document assumptions in code comments and assertions:

```julia
# ASSUMPTION: Replicons are circular (no telomeres)
# This affects how we handle sequence boundaries in window analysis
function sliding_window_analysis(replicon::Replicon, window_length_bp::Int)
    # Wrap around to beginning for circular topology
    # ...
end
```

---

## Version Control and Change Management

### 1. Semantic Versioning

Follow semver (MAJOR.MINOR.PATCH) for all releases:

#### Version Bump Rules

- **MAJOR**: Breaking changes to data schema, API, or published results
  - Example: Changing orbit size definition, altering CSV column names
  - Requires new Zenodo DOI for dataset
  
- **MINOR**: Backward-compatible new features
  - Example: Adding new metrics, supporting additional output formats
  - Can update existing Zenodo DOI with new version
  
- **PATCH**: Bug fixes that don't change results
  - Example: Fixing typos, improving error messages, optimizing performance
  - Update Zenodo DOI metadata only

#### Version Documentation

- Update `version` in `julia/Project.toml`
- Update `version` in `.zenodo.json`
- Tag releases in Git: `git tag v2.1.0`
- Document changes in `CHANGELOG.md`

### 2. Atomic Commits

Each commit should represent a single logical change:

#### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding or updating tests
- `refactor`: Code restructuring without behavior change
- `perf`: Performance improvements
- `chore`: Build system, dependencies, tooling

**Scopes**:
- `julia`: Julia implementation (Layer 0-1)
- `demetrios`: Demetrios implementation (Layer 2)
- `pipeline`: Data processing pipeline
- `validation`: Validation and testing
- `docs`: Documentation
- `build`: Build system (Makefile, CI)

#### Examples

**Good Commits**:
```
feat(julia): Add quaternion lift verification for Dic_n → D_n

Implements quaternion-based verification that dicyclic group Dic_n
is a double cover of dihedral group D_n. Adds QuaternionLift module
with unit tests.

Closes #42
```

```
fix(demetrios): Correct orbit size calculation for palindromes

Previous implementation double-counted palindromic sequences in orbit.
Now correctly identifies RC-fixed points and adjusts orbit size.

Fixes #58
```

**Avoid**:
```
Update stuff
```

```
WIP
```

```
Fixed bug, added feature, updated docs, refactored code
```

### 3. Reproducibility Lock

Never break reproducibility of published datasets:

#### Immutability Guarantees

- **Published Datasets**: Once a dataset is published with a DOI, its generation must remain reproducible forever
- **Committed Dependencies**: `julia/Manifest.toml` must be committed and never force-updated
- **Versioned Demetrios**: Document exact Demetrios compiler version used for each release
- **Archived Releases**: Tag and archive all releases on GitHub and Zenodo

#### Reproducibility Checklist

- [ ] `julia/Manifest.toml` is committed to version control
- [ ] `.zenodo.json` documents Julia and Demetrios versions
- [ ] `README.md` includes installation instructions for exact versions
- [ ] `make reproduce` target regenerates published data bit-exactly
- [ ] CI tests verify reproducibility on clean environment

#### Breaking Changes Protocol

If a breaking change is necessary:

1. **Increment MAJOR version** (e.g., 2.0.0 → 3.0.0)
2. **Create new Zenodo DOI** for new dataset version
3. **Maintain old version** in separate Git branch (e.g., `v2.x-maintenance`)
4. **Document migration** in `CHANGELOG.md` and `MIGRATION.md`
5. **Preserve old data** on Zenodo (never delete published datasets)

#### Example Workflow

```bash
# Release v2.0.0 with DOI 10.5281/zenodo.1234567
git tag v2.0.0
make snapshot  # Creates Zenodo upload
# Upload to Zenodo, get DOI

# Later: Need breaking change for v3.0.0
git checkout -b v2.x-maintenance  # Preserve v2.x
git checkout main
# Implement breaking changes
git tag v3.0.0
make snapshot  # Creates NEW Zenodo upload with NEW DOI
# Upload to Zenodo, get NEW DOI

# Both v2.0.0 and v3.0.0 remain reproducible forever
```

---

## Summary

These guidelines ensure DOSA maintains:

1. **Scientific Rigor**: Formal, precise communication suitable for peer review
2. **Reproducibility**: Every result can be independently verified
3. **Clarity**: Explicit naming and comprehensive documentation
4. **Correctness**: Defensive programming and epistemic transparency
5. **Sustainability**: Semantic versioning and reproducibility locks

All contributors must adhere to these guidelines to maintain DOSA's quality and scientific integrity.
