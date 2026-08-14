#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministically render the non-scientific scale fixture for the dedicated
# Sounio Euler/Wilson capacity probe.  This is deliberately not a U0 source
# manifest or a pilot parameter artifact: its opaque parameter hash is a
# fixture-domain separator used solely to exercise the prescribed seed chain.

require "digest"

abort "usage: generate_u0_dinucleotide_scale_cases.rb <parameters-domain.txt> <output.tsv>" unless ARGV.length == 2

parameters_path, output_path = ARGV
SCALES = [16, 100, 500, 1000].freeze
ALPHABET = %w[A C G T].freeze

def sequence_for(scale)
  # A portable unsigned 32-bit LCG; all rows contain all four bases and use
  # fixed endpoints so the fixture exercises parallel-edge Euler graphs.
  state = (0x9e37_79b9 ^ scale) & 0xffff_ffff
  chars = Array.new(scale) do
    state = (1_664_525 * state + 1_013_904_223) & 0xffff_ffff
    ALPHABET[(state >> 30) & 3]
  end
  chars[0] = "A"
  chars[-1] = "T"
  chars.join
end

parameters_sha = Digest::SHA256.file(parameters_path).hexdigest
rows = ["case_id\tparameters_sha256\taccession_version\twindow_start\tscale\tseed64\tbases\treplicates"]
SCALES.each_with_index do |scale, index|
  accession = format("U0_SCALE_FIXTURE_%04d.1", scale)
  window_start = index * 10_000
  seed64 = Digest::SHA256.hexdigest("#{parameters_sha}:#{accession}:#{window_start}")[0, 16]
  rows << ["scale_#{scale}", parameters_sha, accession, window_start, scale, seed64,
           sequence_for(scale), 1000].join("\t")
end

File.binwrite(output_path, rows.join("\n") + "\n")
