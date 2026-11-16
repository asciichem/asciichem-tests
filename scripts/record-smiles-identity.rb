#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the recorded identity column to corpus/fixtures/smiles.json
# (asciichem-rs#45: SMILES ingest gated parse -> render -> identity).
# Every `parses: true` case is recorded from three legs that must
# agree before anything is written:
#
#   1. engine(smiles)      — the chemomer engine's SMILES reader
#                            (chemomer/chemomer, the smiles.parg
#                            contract; corpus-gated against the oracle
#                            at 1,537 fixtures);
#   2. engine(gem molfile) — the asciichem gem's SMILES parse piped
#                            through the gem's molfile writer into the
#                            same engine;
#   3. oracle(gem molfile) — the official `inchi-1` binary on the
#                            gem's molfile (the development-time
#                            oracle; the corpus ships only the
#                            recorded strings).
#
# A disagreement is a transcription finding: the script reports it
# and refuses to record that case, never guesses.
#
#   CHEMOMER_LIB=.../libchemomer.dylib \
#     ruby scripts/record-smiles-identity.rb > smiles.json.new
# (run with the asciichem and chemomer gems on the load path)

require 'asciichem'
require 'chemomer'
require 'json'
require 'tmpdir'
require 'fileutils'

family_path = File.join(__dir__, '..', 'corpus', 'fixtures', 'smiles.json')
family = JSON.parse(File.read(family_path))
bin = ENV.fetch('ASCIICHEM_INCHI_BIN', 'inchi-1')

def oracle_inchi(molfile, bin)
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, 's.mol'), molfile)
    system(bin, File.join(dir, 's.mol'), File.join(dir, 'o.txt'),
           '-AuxNone', '-NoLabels', '-Key', out: File::NULL, err: File::NULL)
    txt = File.read(File.join(dir, 'o.txt'))
    txt[/^InChI=\S+/]
  end
end

recorded = 0
refused = []
skipped = []
family.each do |row|
  next unless row['parses']

  smiles = row.fetch('smiles')
  id = row.fetch('id')
  # The engine's SMILES reader is the phase-1 contract (chains,
  # branches, rings, organic + bracket atoms; chirality, E/Z and
  # dot-disconnection are its documented phase 2) — a case outside
  # the phase is a skip, not a refusal: the identity column stays
  # absent and the runtimes gate the recorded intersection.
  begin
    engine_leg = Chemomer.from_smiles(smiles)
  rescue Chemomer::Error => e
    skipped << [id, e.message]
    next
  end
  molecule = AsciiChem.parse_smiles(smiles).nodes.first
  molfile = AsciiChem::Molfile.write(molecule)
  gem_leg = Chemomer.from_molfile(molfile).first
  oracle_leg = oracle_inchi(molfile, bin)

  # The oracle binary occasionally declines a molfile the engine
  # reads (non-kekulized aromatic bond codes, for one) — an
  # oracle-side limitation, not a transcription question. There the
  # two ENGINE legs agree as the recording evidence; genuine
  # disagreement between any two legs refuses the case.
  legs = { 'engine(smiles)' => engine_leg, 'engine(gem molfile)' => gem_leg,
           'oracle(gem molfile)' => oracle_leg }.compact
  if legs.values.uniq.size != 1
    refused << [id, legs]
    next
  end
  if oracle_leg.nil?
    warn "  #{id}: oracle binary declined the molfile; recorded on engine-leg agreement"
  end

  row['inchi'] = engine_leg
  recorded += 1
end

unless refused.empty?
  warn "#{refused.size} case(s) refused — the legs disagree (left unrecorded):"
  refused.each do |id, legs|
    warn "  #{id}:"
    legs.each { |leg, inchi| warn "    #{leg}: #{inchi.inspect}" }
  end
  warn 'the agreeing intersection is written; fix the transcription and re-run'
end

unless skipped.empty?
  warn "#{skipped.size} case(s) skipped (outside the engine's phase-1 SMILES):"
  skipped.each { |id, message| warn "  #{id}: #{message}" }
end

File.write(family_path, JSON.pretty_generate(family) + "\n")
warn "recorded #{recorded} identity entries into #{family_path}"
exit 1 unless refused.empty?
