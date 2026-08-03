#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"

abort "usage: generate_dinucleotide_cases.rb <parameters.json> <templates.tsv> <output.tsv>" unless ARGV.length == 3

parameters_path, templates_path, output_path = ARGV
parameters_sha = Digest::SHA256.file(parameters_path).hexdigest
rows = File.readlines(templates_path, chomp: true)
expected_header = "case_id\taccession_version\twindow_start\tbases"
abort "template header drift" unless rows.shift == expected_header
abort "empty template fixture" if rows.empty?

output = ["case_id\tparameters_sha256\taccession_version\twindow_start\tseed64\tbases"]
rows.each do |row|
  fields = row.split("\t", -1)
  abort "template field-count drift" unless fields.length == 4
  case_id, accession, window_start, bases = fields
  abort "invalid case id" unless case_id.match?(/\A[A-Za-z0-9_]+\z/)
  abort "invalid accession" unless accession.match?(/\A[A-Za-z0-9._-]+\z/)
  abort "invalid window start" unless window_start.match?(/\A(?:0|[1-9][0-9]*)\z/)
  abort "invalid canonical fixture sequence" unless bases.match?(/\A[ACGT]{1,16}\z/)
  material = "#{parameters_sha}:#{accession}:#{window_start}"
  seed64 = Digest::SHA256.hexdigest(material)[0, 16]
  output << [case_id, parameters_sha, accession, window_start, seed64, bases].join("\t")
end

File.write(output_path, output.join("\n") + "\n")
