#!/usr/bin/env julia

# Independent standard-library-only statistical validator for the Fase N
# null-generator quality artifact produced by
# sounio/src/null_quality_fixture.sio (pinned official Sounio).
#
# For each case the validator:
#   1. re-enumerates the exact null support from first principles:
#        mono  — all distinct multiset permutations. Fisher-Yates is uniform
#                over the len! position permutations and every distinct
#                sequence has the same fiber size prod_c n_c!, so the null is
#                exactly uniform over the distinct sequences.
#        dinuc — all Eulerian trails of the dinucleotide multigraph with
#                distinct parallel edges. The Wilson construction
#                (euler_wilson_fixed_endpoints_v1, ADR-0003) is uniform over
#                trails and every sequence has the same multiplicity
#                prod_(v,w) m_vw!, so the null is exactly uniform over the
#                distinct trail sequences.
#   2. verifies the metamorphic invariants of every draw (anagram for mono;
#      fixed endpoints plus all 16 dinucleotide counts for dinuc);
#   3. requires observed support == enumerated support (containment and full
#      coverage);
#   4. runs a chi-square uniformity test with pre-declared alpha = 1e-3 per
#      case; p-values come from the regularized upper incomplete gamma
#      function implemented here (Numerical Recipes series / continued
#      fraction), with built-in self-tests against closed forms.
#
# Exit 0 with NULL_QUALITY_JULIA_PASS only when every case passes every gate.

using Printf

const ALPHA = 1e-3
const BASES = ('A', 'C', 'G', 'T')
const CODE = Dict('A' => 1, 'C' => 2, 'G' => 3, 'T' => 4)

# --------------------------------------------------------- incomplete gamma

function gammln(x::Float64)
    cof = (76.18009172947146, -86.50532032941677, 24.01409824083091,
           -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5)
    y = x
    tmp = x + 5.5
    tmp -= (x + 0.5) * log(tmp)
    ser = 1.000000000190015
    for c in cof
        y += 1.0
        ser += c / y
    end
    -tmp + log(2.5066282746310005 * ser / x)
end

# Regularized lower incomplete gamma P(a,x) via series expansion.
function gamma_p_series(a::Float64, x::Float64)
    x == 0.0 && return 0.0
    gln = gammln(a)
    ap = a
    s = 1.0 / a
    del = s
    for _ in 1:1000
        ap += 1.0
        del *= x / ap
        s += del
        abs(del) < abs(s) * 1e-15 && break
    end
    s * exp(-x + a * log(x) - gln)
end

# Regularized upper incomplete gamma Q(a,x) via continued fraction.
function gamma_q_cfrac(a::Float64, x::Float64)
    gln = gammln(a)
    b = x + 1.0 - a
    c = 1.0 / 1e-300
    d = 1.0 / b
    h = d
    for i in 1:1000
        an = -Float64(i) * (Float64(i) - a)
        b += 2.0
        d = an * d + b
        abs(d) < 1e-300 && (d = 1e-300)
        c = b + an / c
        abs(c) < 1e-300 && (c = 1e-300)
        d = 1.0 / d
        del = d * c
        h *= del
        abs(del - 1.0) < 1e-15 && break
    end
    exp(-x + a * log(x) - gln) * h
end

gamma_q(a::Float64, x::Float64) =
    x < a + 1.0 ? 1.0 - gamma_p_series(a, x) : gamma_q_cfrac(a, x)

chi2_sf(x2::Float64, df::Int) = gamma_q(Float64(df) / 2.0, x2 / 2.0)

function selftest_gamma!()
    # Q(1,x) = exp(-x) exactly.
    for x in (0.5, 1.0, 3.7, 12.0)
        abs(gamma_q(1.0, x) - exp(-x)) < 1e-12 || error("gamma self-test failed at x=$x")
    end
    # chi-square df=1 survival at the 0.95 quantile is 0.05.
    abs(chi2_sf(3.841458820984124, 1) - 0.05) < 1e-6 ||
        error("chi-square df=1 self-test failed")
    # chi-square df=2 survival is exp(-x/2); the 0.975 quantile gives 0.025.
    abs(chi2_sf(7.3777589082278725, 2) - 0.025) < 1e-9 ||
        error("chi-square df=2 self-test failed")
    # chi-square df=69 sanity: survival far in the right tail is tiny.
    q = chi2_sf(140.0, 69)
    (q > 0.0 && q < 1e-6) || error("chi-square df=69 tail self-test failed")
    true
end

# ------------------------------------------------------- exact enumerations

# mono: distinct multiset permutations; multiplicity = fiber size prod n_c!.
function mono_enumeration(bases::AbstractString)
    counts = Dict{Char,Int}()
    for b in bases
        counts[b] = get(counts, b, 0) + 1
    end
    letters = sort!(collect(keys(counts)))
    fiber = prod(factorial, values(counts))
    support = Dict{String,Int}()
    cur = Vector{Char}(undef, length(bases))
    function rec(pos::Int)
        if pos > length(bases)
            support[String(cur)] = fiber
            return
        end
        for b in letters
            counts[b] > 0 || continue
            counts[b] -= 1
            cur[pos] = b
            rec(pos + 1)
            counts[b] += 1
        end
    end
    rec(1)
    support, factorial(length(bases))
end

# dinuc: Eulerian trails with distinct parallel edges; multiplicity per
# distinct base sequence.
function dinuc_enumeration(bases::AbstractString)
    edges = [(CODE[bases[i]], CODE[bases[i + 1]]) for i in 1:(length(bases) - 1)]
    out_adj = [Int[] for _ in 1:4]
    for (idx, (s, _)) in pairs(edges)
        push!(out_adj[s], idx)
    end
    n = length(edges)
    used = falses(n)
    support = Dict{String,Int}()
    seqbuf = Vector{Char}(undef, length(bases))
    seqbuf[1] = bases[1]
    function rec(v::Int, depth::Int)
        if depth > n
            key = String(copy(seqbuf))
            support[key] = get(support, key, 0) + 1
            return
        end
        for ei in out_adj[v]
            used[ei] && continue
            used[ei] = true
            seqbuf[depth + 1] = BASES[edges[ei][2]]
            rec(edges[ei][2], depth + 1)
            used[ei] = false
        end
    end
    rec(CODE[bases[1]], 1)
    support, n
end

# -------------------------------------------------------------- input checks

function parse_cases(path::String)
    rows = readlines(path)
    !isempty(rows) || error("empty cases file")
    rows[1] == "case_id\tengine\taccession_version\twindow_start\tseed_material\tbases\tdraws" ||
        error("cases header drift")
    cases = NamedTuple[]
    for row in rows[2:end]
        f = split(row, '\t'; keepempty = true)
        length(f) == 7 || error("case field-count drift: $row")
        engine = f[2]
        engine in ("mono", "dinuc") || error("unknown engine: $engine")
        bases = f[6]
        1 <= length(bases) <= 16 || error("bases length drift: $bases")
        all(c -> c in "ACGT", bases) || error("non-ACGT base in case: $bases")
        push!(cases, (case_id = f[1], engine = engine, accession = f[3],
                      window_start = parse(Int, f[4]), seed_material = f[5],
                      bases = bases, draws = parse(Int, f[7])))
    end
    !isempty(cases) || error("no cases")
    cases
end

function parse_blocks(path::String)
    blocks = Pair{String,Vector{String}}[]
    for line in eachline(path)
        if startswith(line, "#case=")
            push!(blocks, line => String[])
        else
            !isempty(blocks) || error("draw line before any block header")
            push!(blocks[end].second, line)
        end
    end
    blocks
end

function dinuc_counts(s::AbstractString)
    counts = zeros(Int, 4, 4)
    for i in 1:(length(s) - 1)
        counts[CODE[s[i]], CODE[s[i + 1]]] += 1
    end
    counts
end

# ------------------------------------------------------------------- driver

function main()
    length(ARGS) == 2 ||
        error("usage: validate_null_quality.jl <cases.tsv> <draws.txt>")
    cases_path, draws_path = ARGS
    selftest_gamma!()
    cases = parse_cases(cases_path)
    blocks = parse_blocks(draws_path)
    length(blocks) == length(cases) ||
        error("block count drift: expected $(length(cases)), got $(length(blocks))")

    failures = String[]
    total_draws = 0
    for (case, block) in zip(cases, blocks)
        header, draws_lines = block
        expected_header = "#case=$(case.case_id) engine=$(case.engine) " *
            "draws=$(case.draws) seed_material=$(case.seed_material) bases=$(case.bases)"
        header == expected_header ||
            error("block header drift for $(case.case_id): $header")
        length(draws_lines) == case.draws ||
            error("draw count drift for $(case.case_id): expected $(case.draws), got $(length(draws_lines))")

        if case.engine == "mono"
            support, trails_total = mono_enumeration(case.bases)
        else
            support, _ = dinuc_enumeration(case.bases)
            trails_total = sum(values(support))
            trails_total > 0 || error("empty dinuc enumeration")
        end
        S = length(support)
        S >= 2 || error("degenerate support for $(case.case_id)")

        observed = Dict{String,Int}()
        expected_sorted_bases = sort!(collect(case.bases))
        expected_dinuc = case.engine == "dinuc" ? dinuc_counts(case.bases) : nothing
        for d in draws_lines
            length(d) == length(case.bases) ||
                error("draw length drift in $(case.case_id): $d")
            all(c -> c in "ACGT", d) ||
                error("non-ACGT draw in $(case.case_id): $d")
            sort!(collect(d)) == expected_sorted_bases ||
                error("anagram invariant violated in $(case.case_id): $d")
            if case.engine == "dinuc"
                (d[1] == case.bases[1] && d[end] == case.bases[end]) ||
                    error("endpoint invariant violated in $(case.case_id): $d")
                dinuc_counts(d) == expected_dinuc ||
                    error("dinucleotide-count invariant violated in $(case.case_id): $d")
            end
            haskey(support, d) ||
                error("draw outside the exact null support in $(case.case_id): $d")
            observed[d] = get(observed, d, 0) + 1
        end

        length(observed) == S || push!(failures,
            "$(case.case_id): coverage $(length(observed))/$S")

        chi2 = 0.0
        min_ratio = Inf
        max_ratio = 0.0
        for (seq, mult) in support
            exp = case.draws * mult / trails_total
            obs = Float64(get(observed, seq, 0))
            chi2 += (obs - exp)^2 / exp
            r = obs / exp
            r < min_ratio && (min_ratio = r)
            r > max_ratio && (max_ratio = r)
        end
        df = S - 1
        p = chi2_sf(chi2, df)
        p >= ALPHA || push!(failures,
            "$(case.case_id): chi2=$(@sprintf("%.4f", chi2)) df=$df p=$(@sprintf("%.3g", p)) < alpha=$ALPHA")

        total_draws += case.draws
        @printf("NULL_QUALITY_CASE case=%s engine=%s draws=%d support=%d coverage=%d/%d chi2=%.4f df=%d p=%.6g alpha=%g min_ratio=%.4f max_ratio=%.4f\n",
            case.case_id, case.engine, case.draws, S, length(observed), S,
            chi2, df, p, ALPHA, min_ratio, max_ratio)
    end

    if !isempty(failures)
        for f in failures
            println(stderr, "NULL_QUALITY_FAIL $f")
        end
        exit(1)
    end
    println("NULL_QUALITY_JULIA_PASS cases=$(length(cases)) draws=$total_draws alpha=$ALPHA tolerance=exact-support")
end

main()
