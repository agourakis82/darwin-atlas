#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministic case generator for the Fase N null-generator quality fixture.
#
# Seed policy (quality_parameters_sha256_v1):
#   mono  seed_material = first 16 hex digits of parameters_sha256. The fixture
#         consumes only the first 8 as seed_base, exactly mirroring
#         null_seed_base_from_sha in sounio/src/fasta_stream_fixture.sio
#         (lcg31_sha8_fixture_v1), with window_start from the case and the
#         documented fixed record_index=1 / metric_index=0.
#   dinuc seed_material = first64be(SHA-256(parameters_sha256 || ":" ||
#         accession_version || ":" || window_start)), exactly the ADR-0003
#         derivation sha256_parameters_accession_window_first64be_v1.

require "digest"

abort "usage: generate_null_quality_cases.rb <parameters.json> <templates.tsv> <output.tsv>" unless ARGV.length == 3

parameters_path, templates_path, output_path = ARGV
parameters_sha = Digest::SHA256.file(parameters_path).hexdigest
rows = File.readlines(templates_path, chomp: true)
expected_header = "case_id\tengine\taccession_version\twindow_start\tbases\tdraws"
abort "template header drift" unless rows.shift == expected_header
abort "empty template fixture" if rows.empty?

output = ["case_id\tengine\taccession_version\twindow_start\tseed_material\tbases\tdraws"]
rows.each do |row|
  fields = row.split("\t", -1)
  abort "template field-count drift" unless fields.length == 6
  case_id, engine, accession, window_start, bases, draws = fields
  abort "invalid case id" unless case_id.match?(/\A[A-Za-z0-9_]+\z/)
  abort "invalid engine" unless %w[mono dinuc].include?(engine)
  abort "invalid accession" unless accession.match?(/\A[A-Za-z0-9._-]+\z/)
  abort "invalid window start" unless window_start.match?(/\A(?:0|[1-9][0-9]*)\z/)
  abort "invalid canonical fixture sequence" unless bases.match?(/\A[ACGT]{1,16}\z/)
  abort "invalid draw count" unless draws.match?(/\A[1-9][0-9]*\z/) && draws.to_i <= 1_000_000
  seed_material =
    if engine == "mono"
      parameters_sha[0, 16]
    else
      Digest::SHA256.hexdigest("#{parameters_sha}:#{accession}:#{window_start}")[0, 16]
    end
  output << [case_id, engine, accession, window_start, seed_material, bases, draws].join("\t")
end

File.write(output_path, output.join("\n") + "\n")
