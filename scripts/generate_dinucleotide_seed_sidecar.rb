#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"

abort "usage: generate_dinucleotide_seed_sidecar.rb <parameters.json> <input.fa> <metadata.tsv> <output.tsv>" unless ARGV.length == 4

parameters_path, fasta_path, metadata_path, output_path = ARGV
parameter_bytes = File.binread(parameters_path)
parameters = JSON.parse(parameter_bytes)
window_size = Integer(parameters.fetch("window_size"))
abort "window_size must be positive" unless window_size.positive?
abort "sidecar is only valid for dinucleotide_shuffle" unless parameters.fetch("null_model") == "dinucleotide_shuffle"
parameter_sha = Digest::SHA256.hexdigest(parameter_bytes)

metadata_lines = File.readlines(metadata_path, chomp: true).reject(&:empty?)
expected_header = "record_index\tsequence_accession_version\tassembly_accession_version\treplicon_class\tdeclared_topology\tsource_scope"
abort "metadata header mismatch" unless metadata_lines.shift == expected_header
accessions = metadata_lines.map.with_index(1) do |line, expected_index|
  fields = line.split("\t", -1)
  abort "metadata field-count mismatch" unless fields.length == 6
  abort "metadata record-index mismatch" unless Integer(fields[0]) == expected_index
  fields[1]
end

records = []
current_id = nil
current_sequence = +""
File.foreach(fasta_path, chomp: true) do |line|
  if line.start_with?(">")
    records << [current_id, current_sequence] unless current_id.nil?
    current_id = line.delete_prefix(">").split(/[ \t]/, 2).first
    current_sequence = +""
  else
    abort "sequence before FASTA header" if current_id.nil?
    current_sequence << line.strip
  end
end
records << [current_id, current_sequence] unless current_id.nil?
abort "FASTA/metadata record-count mismatch" unless records.length == accessions.length

rows = ["sequence_accession_version\twindow_start\tseed64"]
records.each_with_index do |(header_id, sequence), index|
  accession = accessions[index]
  abort "FASTA/metadata accession mismatch" unless header_id == accession
  start = 0
  while start < sequence.length
    material = "#{parameter_sha}:#{accession}:#{start}"
    rows << "#{accession}\t#{start}\t#{Digest::SHA256.hexdigest(material)[0, 16]}"
    start += window_size
  end
end

File.binwrite(output_path, rows.join("\n") + "\n")
