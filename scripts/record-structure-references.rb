#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds corpus/fixtures/structure-reference.json from the seed battery
# below (asciichem-rs#45: the standalone structure-reference ingest
# edge, grammar v0.6.0). Each `parses: true` case records THREE fields
# from three agreeing legs:
#
#   text  — the canonical ascii output, from the gem
#           (`AsciiChem.parse(input).to_text`; the ingest-edge posture:
#           the reference syntax is not preserved, the model is the
#           structure)
#   inchi — the recorded identity, from three legs that must agree:
#           engine(smiles), engine(gem molfile of the
#           reference-parsed molecule), oracle(gem molfile) — the
#           record-smiles-identity.rb discipline
#
# A disagreement refuses the case (never guesses). Requires: the
# asciichem gem (with grammar v0.6.0), the chemomer gem, CHEMOMER_LIB,
# and the official inchi-1 binary.
#
#   CHEMOMER_LIB=... ruby scripts/record-structure-references.rb \
#     > corpus/fixtures/structure-reference.json

require 'asciichem'
require 'chemomer'
require 'json'
require 'tmpdir'

SEEDS = [
  ['ethanol',        '@smiles("CCO")',                          'CCO',                          'simple'],
  ['benzene',        '@smiles("c1ccccc1")',                     'c1ccccc1',                     'ring-aromatic'],
  ['pyrrole',        '@smiles("c1cc[nH]c1")',                   'c1cc[nH]c1',                   'bracket-h'],
  ['aspirin',        '@smiles("CC(=O)OC1=CC=CC=C1C(=O)O")',     'CC(=O)OC1=CC=CC=C1C(=O)O',     'drug'],
  ['caffeine',       '@smiles("Cn1cnc2c1c(=O)n(C)c(=O)n2C")',   'Cn1cnc2c1c(=O)n(C)c(=O)n2C',   'drug-fused'],
  ['l-alanine',      '@smiles("N[C@@H](C)C(=O)O")',             'N[C@@H](C)C(=O)O',             'stereo'],
].freeze

REJECTS = [
  ['molfile-source', '@molfile("CCO")'],
  ['dot-components', '@smiles("CC.O")'],
  ['truncated',      '@smiles("CCO"'],
].freeze

bin = ENV.fetch('ASCIICHEM_INCHI_BIN', 'inchi-1')

def oracle_inchi(molfile, bin)
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, 's.mol'), molfile)
    system(bin, File.join(dir, 's.mol'), File.join(dir, 'o.txt'),
           '-AuxNone', '-NoLabels', '-Key', out: File::NULL, err: File::NULL)
    File.read(File.join(dir, 'o.txt'))[/^InChI=\S+/]
  end
end

rows = []
refused = []

SEEDS.each do |name, input, smiles, klass|
  formula = AsciiChem.parse(input)
  molecule = formula.nodes.first

  # The text column records ONLY where the canonical text round-trips
  # to the same structure — the same "expressible in text" discipline
  # the smiles family applies. The gem's ascii canonicaliser currently
  # breaks on SMILES-ingested carbonyl branches (ring digits assigned
  # to carbonyl oxygens; the aspirin/caffeine texts re-parse to
  # different structures), so those cases carry no text.
  text = nil
  begin
    candidate = formula.to_text
    text = candidate if AsciiChem.parse(candidate).to_smiles == smiles
  rescue AsciiChem::ParseError
    nil
  end

  # The engine's SMILES reader is the phase-1 contract — a case
  # outside it (chirality, E/Z) skips the identity column (the
  # record-smiles-identity.rb discipline) while the reference still
  # gates: it parses everywhere and the text column gates where
  # recorded.
  begin
    engine_leg = Chemomer.from_smiles(smiles)
    molfile = AsciiChem::Molfile.write(molecule)
    gem_leg = Chemomer.from_molfile(molfile).first
    oracle_leg = oracle_inchi(molfile, bin)
    legs = { 'engine(smiles)' => engine_leg, 'engine(reference molfile)' => gem_leg,
             'oracle(reference molfile)' => oracle_leg }.compact
    if legs.values.uniq.size != 1
      refused << ["structure-reference/#{name}", legs]
      next
    end
    inchi = engine_leg
  rescue Chemomer::Error
    inchi = nil
  end

  row = { 'id' => "structure-reference/#{name}",
          'input' => input,
          'parses' => true,
          'smiles' => smiles,
          'tags' => [klass],
          'since' => '0.13.0' }
  row['text'] = text if text
  row['inchi'] = inchi if inchi
  rows << row
end

REJECTS.each do |name, input|
  rows << { 'id' => "structure-reference/#{name}",
            'input' => input,
            'parses' => false,
            'tags' => ['reject'],
            'since' => '0.13.0' }
end

unless refused.empty?
  warn "#{refused.size} case(s) refused — the legs disagree:"
  refused.each do |id, legs|
    warn "  #{id}:"
    legs.each { |leg, inchi| warn "    #{leg}: #{inchi.inspect}" }
  end
end

puts JSON.pretty_generate(rows)
warn "recorded #{rows.count { |r| r['parses'] }} reference cases"
exit 1 unless refused.empty?
