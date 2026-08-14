#!/usr/bin/env julia

"""
Independent Base/stdlib-only U0 manifest and terminal-work validator.

Sounio validates the strict structural manifest but cannot hash files in the
pinned runtime.  This validator independently resolves each relative FASTA,
recomputes the exact file SHA-256, reparses its sole FASTA record, recomputes
the normalized full-sequence SHA-256/length/accession/alphabet, reconstructs
every deterministic terminal record, and requires byte-exact equality.
"""

using SHA

const SCALES = (16, 100, 500, 1000)
const IUPAC = Set("ACGTNRYSWKMBDHV")
const MANIFEST_HEADER = join(("u0_manifest_version", "work_unit_id",
    "assembly_accession_version", "sequence_accession_version", "replicon_class",
    "source_locator", "source_file_sha256", "sequence_sha256", "sequence_length",
    "declared_alphabet", "parameters_sha256", "scale", "stride", "k_min", "k_max",
    "null_model", "null_replicates"), '\t')
const OUTPUT_HEADER = join(("u0_manifest_version", "record_kind", "work_unit_id",
    "assembly_accession_version", "sequence_accession_version", "scale", "source_locator",
    "source_file_sha256", "sequence_sha256", "sequence_length", "parameters_sha256",
    "checkpoint_key", "source_verification_requirement", "reason_code"), '\t')
const SOURCE_REQUIREMENT = "RUNNER_MUST_VERIFY_FASTA_FILE_SHA256_SEQUENCE_SHA256_LENGTH_ACCESSION_AND_ALPHABET"

fail(message) = error("U0_MANIFEST_VALIDATION_FAIL: " * message)

function parse_nonnegative(raw::String, context::String)
    isempty(raw) && fail("empty integer at $context")
    all(isdigit, raw) || fail("non-decimal integer at $context")
    value = tryparse(Int, raw)
    isnothing(value) && fail("integer overflow at $context")
    value
end

function valid_id(id::String)
    !isempty(id) && ncodeunits(id) <= 128 &&
        all(c -> isascii(c) && (isletter(c) || isdigit(c) || c in ('-', '.', '_')), id)
end

function valid_locator(locator::String)
    !isempty(locator) && ncodeunits(locator) <= 512 && !startswith(locator, "/") &&
        endswith(locator, ".fa") && !occursin("..", locator) && !occursin("//", locator) &&
        all(c -> isascii(c) && (isletter(c) || isdigit(c) || c in ('-', '.', '_', '/')), locator)
end

sha_syntax(value::String) = occursin(r"^[0-9a-f]{64}$", value)

function resolve_source(manifest_path::String, locator::String)
    valid_locator(locator) || fail("unsafe source locator: $locator")
    root = realpath(dirname(abspath(manifest_path)))
    candidate = normpath(joinpath(root, locator))
    rel = relpath(candidate, root)
    (rel == ".." || startswith(rel, "..$(Base.Filesystem.path_separator)")) &&
        fail("source locator escapes manifest directory: $locator")
    isfile(candidate) || fail("source locator is not a file: $locator")
    source = realpath(candidate)
    resolved_rel = relpath(source, root)
    (resolved_rel == ".." || startswith(resolved_rel, "..$(Base.Filesystem.path_separator)")) &&
        fail("source locator symlink escapes manifest directory: $locator")
    source
end

function parse_single_fasta(path::String, accession::String)
    raw = read(path)
    isvalid(String, raw) || fail("FASTA is not valid UTF-8: $path")
    text = String(copy(raw))
    endswith(text, "\n") || fail("FASTA must end in LF: $path")
    occursin('\r', text) && fail("FASTA must use LF, not CRLF: $path")
    lines = split(text, '\n'; keepempty=true)
    pop!(lines) == "" || fail("FASTA terminal-line drift: $path")
    length(lines) >= 2 || fail("FASTA requires header and sequence: $path")
    startswith(lines[1], ">") || fail("FASTA header missing: $path")
    count(line -> startswith(line, ">"), lines) == 1 || fail("FASTA must contain exactly one record: $path")
    header = lines[1][2:end]
    isempty(header) && fail("empty FASTA header: $path")
    split(header)[1] == accession || fail("FASTA accession mismatch for $accession")
    sequence_lines = lines[2:end]
    any(isempty, sequence_lines) && fail("blank FASTA sequence line: $path")
    sequence = join(sequence_lines)
    isempty(sequence) && fail("empty FASTA sequence: $path")
    all(c -> c in IUPAC, sequence) || fail("non-IUPAC or lowercase FASTA sequence: $path")
    raw, sequence
end

function parse_manifest(path::String)
    lines = readlines(path; keep=true)
    !isempty(lines) || fail("manifest is empty")
    strip(lines[1], ['\r', '\n']) == MANIFEST_HEADER || fail("header mismatch")
    rows = NamedTuple[]
    seen_work = Set{String}()
    seen_coordinates = Set{Tuple{String,Int}}()
    active_accession = nothing
    expected_index = 1
    invariant = nothing
    for (line_number, raw_line) in zip(2:length(lines), lines[2:end])
        line = strip(raw_line, ['\r', '\n'])
        isempty(line) && fail("blank line $line_number")
        fields = String.(split(line, '\t'; keepempty=true))
        length(fields) == 17 || fail("field count at line $line_number")
        version, work_id, assembly, accession, replicon_class, locator, file_sha,
            sequence_sha, length_raw, alphabet, parameters_sha, scale_raw, stride_raw,
            kmin_raw, kmax_raw, null_model, draws_raw = fields
        version == "1.0.0" || fail("version at line $line_number")
        valid_id(assembly) || fail("assembly accession at line $line_number")
        valid_id(accession) || fail("sequence accession at line $line_number")
        replicon_class in ("chromosome", "plasmid") || fail("replicon class at line $line_number")
        valid_locator(locator) || fail("unsafe source locator at line $line_number")
        sha_syntax(file_sha) || fail("source file SHA-256 syntax at line $line_number")
        sha_syntax(sequence_sha) || fail("sequence SHA-256 syntax at line $line_number")
        sha_syntax(parameters_sha) || fail("parameters SHA-256 syntax at line $line_number")
        length_bp = parse_nonnegative(length_raw, "line $line_number sequence length")
        length_bp > 0 || fail("zero sequence length at line $line_number")
        alphabet in ("acgt", "non_acgt") || fail("declared alphabet at line $line_number")
        scale = parse_nonnegative(scale_raw, "line $line_number scale")
        stride = parse_nonnegative(stride_raw, "line $line_number stride")
        kmin = parse_nonnegative(kmin_raw, "line $line_number k_min")
        kmax = parse_nonnegative(kmax_raw, "line $line_number k_max")
        draws = parse_nonnegative(draws_raw, "line $line_number null_replicates")
        work_id == "$accession@$scale" || fail("work unit id mismatch at line $line_number")
        work_id in seen_work && fail("duplicate work unit: $work_id")
        push!(seen_work, work_id)
        coordinate = (accession, scale)
        coordinate in seen_coordinates && fail("duplicate replicon x scale coordinate: $coordinate")
        push!(seen_coordinates, coordinate)
        stride == scale || fail("stride must equal scale at line $line_number")
        kmin == 1 && kmax == 8 || fail("k range at line $line_number")
        null_model == "euler_wilson_fixed_endpoints_v1" || fail("null model at line $line_number")
        draws == 1000 || fail("null replicate count at line $line_number")
        if active_accession !== accession
            active_accession === nothing || expected_index == 5 ||
                fail("incomplete scale group before line $line_number")
            active_accession = accession
            expected_index = 1
            invariant = (assembly, accession, replicon_class, locator, file_sha,
                sequence_sha, length_bp, alphabet, parameters_sha)
        end
        scale == SCALES[expected_index] || fail("scale order at line $line_number")
        (assembly, accession, replicon_class, locator, file_sha, sequence_sha,
            length_bp, alphabet, parameters_sha) == invariant ||
            fail("replicon invariant at line $line_number")

        source = resolve_source(path, locator)
        source_bytes, sequence = parse_single_fasta(source, accession)
        bytes2hex(sha256(source_bytes)) == file_sha ||
            fail("source file SHA-256 mismatch at line $line_number")
        bytes2hex(sha256(codeunits(sequence))) == sequence_sha ||
            fail("sequence SHA-256 mismatch at line $line_number")
        ncodeunits(sequence) == length_bp || fail("sequence length mismatch at line $line_number")
        observed_alphabet = all(c -> c in "ACGT", sequence) ? "acgt" : "non_acgt"
        observed_alphabet == alphabet || fail("declared alphabet mismatch at line $line_number")

        push!(rows, (work_id=work_id, assembly=assembly, accession=accession,
            replicon_class=replicon_class, locator=locator, file_sha=file_sha,
            sequence_sha=sequence_sha, length=length_bp, alphabet=alphabet,
            parameters_sha=parameters_sha, scale=scale))
        expected_index += 1
    end
    !isempty(rows) || fail("manifest contains no work units")
    expected_index == 5 || fail("final replicon scale group incomplete")
    rows
end

function terminal_reason(row)
    if row.alphabet == "non_acgt"
        "null_unavailable", "DECLARED_NON_ACGT_NULL_UNAVAILABLE_REQUIRES_RUNNER_VERIFICATION"
    elseif row.scale > 16
        "capability_refused", "SCALE_EXCEEDS_PINNED_SOUNIO_WINDOW_CAPACITY_16"
    else
        "capability_refused", "U0_EULER_WILSON_N1000_EXECUTOR_NOT_BOUND"
    end
end

function expected_output(rows)
    output = String[OUTPUT_HEADER]
    for row in rows
        kind, reason = terminal_reason(row)
        push!(output, join(("1.0.0", kind, row.work_id, row.assembly, row.accession,
            string(row.scale), row.locator, row.file_sha, row.sequence_sha,
            string(row.length), row.parameters_sha, row.work_id, SOURCE_REQUIREMENT, reason), '\t'))
    end
    join(output, "\n") * "\n"
end

function resume_suffix(rows, checkpoint::String)
    index = findfirst(row -> row.work_id == checkpoint, rows)
    isnothing(index) && fail("resume checkpoint does not name exactly one manifest work unit")
    rows[(index + 1):end]
end

function expect_failure(label::String, needle::String, thunk)
    try
        thunk()
    catch error_value
        occursin(needle, sprint(showerror, error_value)) ||
            fail("$label failed for wrong reason: $(sprint(showerror, error_value))")
        return
    end
    fail("$label unexpectedly passed")
end

function self_test(fixture_directory::String)
    manifest = joinpath(fixture_directory, "u0_manifest.tsv")
    expected = joinpath(fixture_directory, "u0_expected_terminal.tsv")
    rows = parse_manifest(manifest)
    read(expected, String) == expected_output(rows) || fail("canonical terminal fixture mismatch")
    invalid = (
        ("scale_order", "scale order", "invalid_scale_order.tsv"),
        ("stride", "stride must equal scale", "invalid_stride.tsv"),
        ("sha", "source file SHA-256 mismatch", "invalid_sha.tsv"),
        ("path", "unsafe source locator", "invalid_path.tsv"),
        ("duplicate", "duplicate work unit", "invalid_duplicate_work_unit.tsv"),
    )
    for (label, needle, file) in invalid
        expect_failure(label, needle, () -> parse_manifest(joinpath(fixture_directory, file)))
    end
    expect_failure("resume", "resume checkpoint", () -> resume_suffix(rows, "NC_DOES_NOT_EXIST.1@16"))
    println("U0_MANIFEST_JULIA_SELF_TEST_PASS work_units=$(length(rows)) invalid_cases=$(length(invalid) + 1)")
end

if length(ARGS) == 2 && ARGS[1] == "--self-test"
    self_test(ARGS[2])
    exit(0)
end

if length(ARGS) != 2 && length(ARGS) != 3
    println(stderr, "usage: validate_u0_manifest.jl <u0-manifest.tsv> <sounio-output.tsv> [resume_work_unit_id]")
    println(stderr, "       validate_u0_manifest.jl --self-test <fixture-directory>")
    exit(2)
end

rows = parse_manifest(ARGS[1])
if length(ARGS) == 3
    rows = resume_suffix(rows, ARGS[3])
end
actual = read(ARGS[2], String)
expected = expected_output(rows)
actual == expected || fail("Sounio terminal work artifact differs from independent recomputation")
capability_refusals = count(row -> first(terminal_reason(row)) == "capability_refused", rows)
null_unavailable = count(row -> first(terminal_reason(row)) == "null_unavailable", rows)
println("U0_MANIFEST_JULIA_PASS work_units=$(length(rows)) capability_refusals=$capability_refusals null_unavailable=$null_unavailable")
