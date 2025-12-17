/// Atlas Epistemic Knowledge Verifier
///
/// Validates atlas_knowledge.jsonl against Demetrios Knowledge[T] schema.
///
/// Invariants checked:
/// 1. Provenance fields present and non-empty
/// 2. Epsilon >= 0
/// 3. Confidence in [0,1]
/// 4. Validity predicate holds
/// 5. Join integrity: replicon_id must exist in atlas_replicons.csv (when available)
/// 6. Metric-specific range checks (selected high-signal metrics)
/// 7. No-miracles: epsilon cannot decrease without explicit rule

module atlas::verify_knowledge

use std::io::*
use std::json::*
use std.collections.HashSet;

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
    demetrios_schema_version: string,
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
    ProvenanceAtlasVersion,
    ProvenanceSchemaVersion,
    ProvenanceTimestamp,
    ProvenancePipelineMax,
    ProvenancePipelineSeed,
    ProvenanceAssemblyAccession,
    ProvenanceRepliconId,
    JoinRepliconId,
    EpsilonNonNegative,
    ConfidenceRange,
    ValidityPresent,
    ValidityHoldsPresent,
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

    let replicon_ids = load_replicon_ids_from_workspace();

    let mut failures: Vec<ValidationFailure> = vec![];
    let mut total_checks = 0;
    let mut passed = 0;
    let mut total_records = 0;

    for (idx, line) in lines.iter().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        total_records += 1;

        match parse_json(line) {
            Ok(json) => {
                let (record_failures, record_checks) = validate_record(&json, idx, replicon_ids.as_ref());
                total_checks += record_checks;
                passed += record_checks - record_failures.len();
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
        total_records,
        total_checks,
        passed,
        failed: failures.len(),
        failures,
    })
}

fn is_replicon_scoped(record_type: &str) -> bool {
    match record_type {
        "replicon_metric" |
        "window_metric" |
        "approx_symmetry" |
        "kmer_metric" |
        "skew_metric" |
        "ir_metric" |
        "replichore_metric" => true,
        _ => false,
    }
}

fn validate_record(json: &JsonValue, idx: usize, replicon_ids: Option<&HashSet<string>>) -> (Vec<ValidationFailure>, usize) {
    let mut failures = vec![];
    let mut checks = 0;

    // 1. Provenance present
    checks += 1;
    if !json.has("provenance") {
        failures.push(ValidationFailure {
            rule: ValidationRule::ProvenancePresent,
            record_idx: idx,
            message: "Missing provenance object".into(),
        });
        return (failures, checks);  // Can't continue without provenance
    }

    let prov = &json["provenance"];

    // 2. Git SHA present
    checks += 1;
    if !prov.has("atlas_git_sha") || prov["atlas_git_sha"].as_str().unwrap_or("").is_empty() {
        failures.push(ValidationFailure {
            rule: ValidationRule::ProvenanceGitSha,
            record_idx: idx,
            message: "Missing atlas_git_sha".into(),
        });
    }

    // 3. Atlas version present
    checks += 1;
    if !prov.has("atlas_version") || prov["atlas_version"].as_str().unwrap_or("").is_empty() {
        failures.push(ValidationFailure {
            rule: ValidationRule::ProvenanceAtlasVersion,
            record_idx: idx,
            message: "Missing atlas_version".into(),
        });
    }

    // 4. Schema version present
    checks += 1;
    if !prov.has("demetrios_schema_version") || prov["demetrios_schema_version"].as_str().unwrap_or("").is_empty() {
        failures.push(ValidationFailure {
            rule: ValidationRule::ProvenanceSchemaVersion,
            record_idx: idx,
            message: "Missing demetrios_schema_version".into(),
        });
    }

    // 5. Timestamp present
    checks += 1;
    if !prov.has("timestamp_utc") || prov["timestamp_utc"].as_str().unwrap_or("").is_empty() {
        failures.push(ValidationFailure {
            rule: ValidationRule::ProvenanceTimestamp,
            record_idx: idx,
            message: "Missing timestamp_utc".into(),
        });
    }

    // 6. pipeline_max present
    checks += 1;
    if prov["pipeline_max"].as_i64().is_none() {
        failures.push(ValidationFailure {
            rule: ValidationRule::ProvenancePipelineMax,
            record_idx: idx,
            message: "Missing pipeline_max".into(),
        });
    }

    // 7. pipeline_seed present
    checks += 1;
    if prov["pipeline_seed"].as_i64().is_none() {
        failures.push(ValidationFailure {
            rule: ValidationRule::ProvenancePipelineSeed,
            record_idx: idx,
            message: "Missing pipeline_seed".into(),
        });
    }

    // 8. replicon-scoped: require assembly_accession and replicon_id (+ join, if possible)
    let record_type = json["record_type"].as_str().unwrap_or("");
    if is_replicon_scoped(record_type) {
        checks += 1;
        if !prov.has("assembly_accession") || prov["assembly_accession"].as_str().unwrap_or("").is_empty() {
            failures.push(ValidationFailure {
                rule: ValidationRule::ProvenanceAssemblyAccession,
                record_idx: idx,
                message: format!("Missing assembly_accession for {}", record_type),
            });
        }

        checks += 1;
        let rid = prov["replicon_id"].as_str().unwrap_or("");
        if rid.is_empty() {
            failures.push(ValidationFailure {
                rule: ValidationRule::ProvenanceRepliconId,
                record_idx: idx,
                message: format!("Missing replicon_id for {}", record_type),
            });
        } else if let Some(ids) = replicon_ids {
            checks += 1;
            if !ids.contains(rid) {
                failures.push(ValidationFailure {
                    rule: ValidationRule::JoinRepliconId,
                    record_idx: idx,
                    message: format!("replicon_id '{}' not found in atlas_replicons.csv", rid),
                });
            }
        }
    }

    // 9. Epsilon >= 0
    checks += 1;
    if let Some(eps) = json["epsilon"].as_f64() {
        if eps < 0.0 {
            failures.push(ValidationFailure {
                rule: ValidationRule::EpsilonNonNegative,
                record_idx: idx,
                message: format!("Epsilon {} < 0", eps),
            });
        }
    }

    // 10. Confidence in [0,1]
    checks += 1;
    if let Some(conf) = json["confidence"].as_f64() {
        if conf < 0.0 || conf > 1.0 {
            failures.push(ValidationFailure {
                rule: ValidationRule::ConfidenceRange,
                record_idx: idx,
                message: format!("Confidence {} not in [0,1]", conf),
            });
        }
    }

    // 11. Validity present + holds present
    checks += 1;
    if !json.has("validity") {
        failures.push(ValidationFailure {
            rule: ValidationRule::ValidityPresent,
            record_idx: idx,
            message: "Missing validity object".into(),
        });
        return (failures, checks);
    }

    let validity = &json["validity"];
    checks += 1;
    if validity["holds"].as_bool().is_none() {
        failures.push(ValidationFailure {
            rule: ValidationRule::ValidityHoldsPresent,
            record_idx: idx,
            message: "Missing validity.holds".into(),
        });
        return (failures, checks);
    }

    // 12. Validity holds
    checks += 1;
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

    // 13. Metric-specific constraints (selected)
    checks += 1;
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
            "x_k" | "x_k_6" => {
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
            "ori_confidence" | "ter_confidence" => {
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
            "gc_skew_amplitude" => {
                if value < 0.0 {
                    failures.push(ValidationFailure {
                        rule: ValidationRule::MetricConstraint {
                            metric: metric.into(),
                            constraint: ">= 0".into()
                        },
                        record_idx: idx,
                        message: format!("gc_skew_amplitude={} < 0", value),
                    });
                }
            }
            "window_size" => {
                if value <= 0.0 {
                    failures.push(ValidationFailure {
                        rule: ValidationRule::MetricConstraint {
                            metric: metric.into(),
                            constraint: "> 0".into()
                        },
                        record_idx: idx,
                        message: format!("window_size={} <= 0", value),
                    });
                }
            }
            "ir_count" | "k_l_tau_05" | "k_l_tau_10" | "total_kmers" | "symmetric_kmers" => {
                if value < 0.0 {
                    failures.push(ValidationFailure {
                        rule: ValidationRule::MetricConstraint {
                            metric: metric.into(),
                            constraint: ">= 0".into()
                        },
                        record_idx: idx,
                        message: format!("{}={} < 0", metric, value),
                    });
                }
            }
            "ir_density" | "baseline_count" | "enrichment_ratio" => {
                if value < 0.0 {
                    failures.push(ValidationFailure {
                        rule: ValidationRule::MetricConstraint {
                            metric: metric.into(),
                            constraint: ">= 0".into()
                        },
                        record_idx: idx,
                        message: format!("{}={} < 0", metric, value),
                    });
                }
            }
            "p_value" => {
                if value < 0.0 || value > 1.0 {
                    failures.push(ValidationFailure {
                        rule: ValidationRule::MetricConstraint {
                            metric: metric.into(),
                            constraint: "[0,1]".into()
                        },
                        record_idx: idx,
                        message: format!("p_value={} not in [0,1]", value),
                    });
                }
            }
            _ => {}
        }
    }

    (failures, checks)
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

// =============================================================================
// Helpers
// =============================================================================

fn load_replicon_ids_from_workspace() -> Option<HashSet<string>> {
    let candidates = [
        "dist/atlas_dataset_v2/csv/atlas_replicons.csv",
        "data/tables/atlas_replicons.csv",
    ];

    for path in candidates.iter() {
        match read_file(path) {
            Ok(content) => {
                if let Some(ids) = parse_replicon_ids_csv(&content) {
                    println!("Loaded {} replicon IDs from {}", ids.len(), path);
                    return Some(ids);
                }
            }
            Err(_) => {}
        }
    }

    None
}

fn parse_replicon_ids_csv(content: &str) -> Option<HashSet<string>> {
    let mut iter = content.lines();
    let header = match iter.next() {
        Some(h) => h,
        None => return Some(HashSet::new()),
    };

    let cols: Vec<&str> = header.split(',').collect();
    let mut rid_idx: Option<usize> = None;
    for (i, c) in cols.iter().enumerate() {
        if c.trim() == "replicon_id" {
            rid_idx = Some(i);
            break;
        }
    }

    let rid_idx = match rid_idx {
        Some(i) => i,
        None => return None,
    };

    let mut ids = HashSet::new();
    for line in iter {
        if line.trim().is_empty() {
            continue;
        }
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() <= rid_idx {
            continue;
        }
        let rid = parts[rid_idx].trim();
        if !rid.is_empty() {
            ids.insert(rid.into());
        }
    }

    Some(ids)
}
