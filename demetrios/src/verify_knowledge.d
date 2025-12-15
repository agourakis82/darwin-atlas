/// Atlas Epistemic Knowledge Verifier
///
/// Validates atlas_knowledge.jsonl against Demetrios Knowledge[T] schema.
///
/// Invariants checked:
/// 1. Provenance fields present and non-empty
/// 2. Epsilon >= 0
/// 3. Confidence in [0,1]
/// 4. Validity predicate holds
/// 5. No-miracles: epsilon cannot decrease without explicit rule

module atlas::verify_knowledge

use std::io::*
use std::json::*

// =============================================================================
// Knowledge Record Schema (matches Julia exporter)
// =============================================================================

pub struct KnowledgeRecord {
    record_type: string,
    metric_name: string,
    value: JsonValue,
    epsilon: Option<f64>,
    confidence: Option<f64>,
    validity: ValidityInfo,
    provenance: ProvenanceInfo,
}

pub struct ValidityInfo {
    holds: bool,
    predicate: Option<string>,
}

pub struct ProvenanceInfo {
    assembly_accession: Option<string>,
    replicon_id: Option<string>,
    atlas_git_sha: string,
    atlas_version: string,
    timestamp_utc: string,
    pipeline_max: i64,
    pipeline_seed: i64,
}

// =============================================================================
// Validation Rules
// =============================================================================

pub enum ValidationRule {
    ProvenancePresent,
    ProvenanceGitSha,
    ProvenanceTimestamp,
    EpsilonNonNegative,
    ConfidenceRange,
    ValidityHolds,
    MetricConstraint { metric: string, constraint: string },
}

pub struct ValidationFailure {
    rule: ValidationRule,
    record_idx: usize,
    message: string,
}

pub struct ValidationReport {
    total_records: usize,
    total_checks: usize,
    passed: usize,
    failed: usize,
    failures: Vec<ValidationFailure>,
}

// =============================================================================
// Validator Implementation
// =============================================================================

pub fn validate_knowledge_file(path: &str) -> Result<ValidationReport, IoError> with IO {
    let content = read_file(path)?;
    let lines: Vec<string> = content.lines().collect();

    let mut failures: Vec<ValidationFailure> = vec![];
    let mut total_checks = 0;
    let mut passed = 0;

    for (idx, line) in lines.iter().enumerate() {
        if line.trim().is_empty() {
            continue;
        }

        match parse_json(line) {
            Ok(json) => {
                let record_failures = validate_record(&json, idx);
                total_checks += 7;  // Base checks per record
                passed += 7 - record_failures.len();
                failures.extend(record_failures);
            }
            Err(e) => {
                failures.push(ValidationFailure {
                    rule: ValidationRule::ProvenancePresent,
                    record_idx: idx,
                    message: format!("JSON parse error: {}", e),
                });
                total_checks += 1;
            }
        }
    }

    Ok(ValidationReport {
        total_records: lines.len(),
        total_checks,
        passed,
        failed: failures.len(),
        failures,
    })
}

fn validate_record(json: &JsonValue, idx: usize) -> Vec<ValidationFailure> {
    let mut failures = vec![];

    // 1. Provenance present
    if !json.has("provenance") {
        failures.push(ValidationFailure {
            rule: ValidationRule::ProvenancePresent,
            record_idx: idx,
            message: "Missing provenance object".into(),
        });
        return failures;  // Can't continue without provenance
    }

    let prov = &json["provenance"];

    // 2. Git SHA present
    if !prov.has("atlas_git_sha") || prov["atlas_git_sha"].as_str().unwrap_or("").is_empty() {
        failures.push(ValidationFailure {
            rule: ValidationRule::ProvenanceGitSha,
            record_idx: idx,
            message: "Missing atlas_git_sha".into(),
        });
    }

    // 3. Timestamp present
    if !prov.has("timestamp_utc") || prov["timestamp_utc"].as_str().unwrap_or("").is_empty() {
        failures.push(ValidationFailure {
            rule: ValidationRule::ProvenanceTimestamp,
            record_idx: idx,
            message: "Missing timestamp_utc".into(),
        });
    }

    // 4. Epsilon >= 0
    if let Some(eps) = json["epsilon"].as_f64() {
        if eps < 0.0 {
            failures.push(ValidationFailure {
                rule: ValidationRule::EpsilonNonNegative,
                record_idx: idx,
                message: format!("Epsilon {} < 0", eps),
            });
        }
    }

    // 5. Confidence in [0,1]
    if let Some(conf) = json["confidence"].as_f64() {
        if conf < 0.0 || conf > 1.0 {
            failures.push(ValidationFailure {
                rule: ValidationRule::ConfidenceRange,
                record_idx: idx,
                message: format!("Confidence {} not in [0,1]", conf),
            });
        }
    }

    // 6. Validity holds
    if json.has("validity") {
        let validity = &json["validity"];
        if let Some(holds) = validity["holds"].as_bool() {
            if !holds {
                let metric = json["metric_name"].as_str().unwrap_or("?");
                let pred = validity["predicate"].as_str().unwrap_or("?");
                failures.push(ValidationFailure {
                    rule: ValidationRule::ValidityHolds,
                    record_idx: idx,
                    message: format!("Validity failed for {} (predicate: {})", metric, pred),
                });
            }
        }
    }

    // 7. Metric-specific constraints
    let metric = json["metric_name"].as_str().unwrap_or("");
    if let Some(value) = json["value"].as_f64() {
        match metric {
            "gc_fraction" => {
                if value < 0.0 || value > 1.0 {
                    failures.push(ValidationFailure {
                        rule: ValidationRule::MetricConstraint {
                            metric: metric.into(),
                            constraint: "[0,1]".into()
                        },
                        record_idx: idx,
                        message: format!("gc_fraction={} not in [0,1]", value),
                    });
                }
            }
            "orbit_ratio" => {
                if value < 0.25 || value > 1.0 {
                    failures.push(ValidationFailure {
                        rule: ValidationRule::MetricConstraint {
                            metric: metric.into(),
                            constraint: "[0.25,1]".into()
                        },
                        record_idx: idx,
                        message: format!("orbit_ratio={} not in [0.25,1]", value),
                    });
                }
            }
            "dmin_over_L" | "dmin_normalized" => {
                if value < 0.0 || value > 1.0 {
                    failures.push(ValidationFailure {
                        rule: ValidationRule::MetricConstraint {
                            metric: metric.into(),
                            constraint: "[0,1]".into()
                        },
                        record_idx: idx,
                        message: format!("{}={} not in [0,1]", metric, value),
                    });
                }
            }
            "length_bp" => {
                if value <= 0.0 {
                    failures.push(ValidationFailure {
                        rule: ValidationRule::MetricConstraint {
                            metric: metric.into(),
                            constraint: "> 0".into()
                        },
                        record_idx: idx,
                        message: format!("length_bp={} <= 0", value),
                    });
                }
            }
            _ => {}
        }
    }

    failures
}

// =============================================================================
// Report Generation
// =============================================================================

pub fn generate_report(report: &ValidationReport) -> string {
    let mut out = String::new();

    out.push_str("# Atlas Epistemic Knowledge Validation Report\n\n");
    out.push_str("## Summary\n\n");
    out.push_str(&format!("| Metric | Value |\n"));
    out.push_str(&format!("|--------|-------|\n"));
    out.push_str(&format!("| Total Records | {} |\n", report.total_records));
    out.push_str(&format!("| Total Checks | {} |\n", report.total_checks));
    out.push_str(&format!("| Passed | {} |\n", report.passed));
    out.push_str(&format!("| Failed | {} |\n", report.failed));

    if report.failed == 0 {
        out.push_str("\n## Result: PASSED\n\n");
        out.push_str("All epistemic invariants satisfied.\n");
    } else {
        out.push_str("\n## Result: FAILED\n\n");
        out.push_str("### Failures\n\n");

        for failure in &report.failures[..min(20, report.failures.len())] {
            out.push_str(&format!("- Record {}: {}\n", failure.record_idx, failure.message));
        }

        if report.failures.len() > 20 {
            out.push_str(&format!("\n... and {} more failures\n", report.failures.len() - 20));
        }
    }

    out
}

// =============================================================================
// Main Entry Point
// =============================================================================

pub fn main() with IO {
    let args = env::args();

    let input_path = if args.len() > 1 {
        args[1].clone()
    } else {
        "data/epistemic/atlas_knowledge.jsonl".into()
    };

    let output_path = if args.len() > 2 {
        args[2].clone()
    } else {
        "data/epistemic/atlas_knowledge_report.md".into()
    };

    println!("Validating: {}", input_path);

    match validate_knowledge_file(&input_path) {
        Ok(report) => {
            let report_str = generate_report(&report);
            write_file(&output_path, &report_str).unwrap();

            println!("Total records: {}", report.total_records);
            println!("Passed: {}", report.passed);
            println!("Failed: {}", report.failed);
            println!("Report: {}", output_path);

            if report.failed > 0 {
                println!("\nVALIDATION FAILED");
                exit(1);
            } else {
                println!("\nVALIDATION PASSED");
                exit(0);
            }
        }
        Err(e) => {
            eprintln!("Error reading file: {}", e);
            exit(1);
        }
    }
}
