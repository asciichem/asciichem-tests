#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the recorded canonical-text column to the smiles-family
# fixtures (corpus/fixtures/smiles.json + perception.json): the
# branch-projection text (asciichem-ruby#208) — smiles-ingested
# molecules text as branch groups instead of carbonyl ring digits,
# byte-identical across the four runtimes.
#
# Every `parses: true` case records only when the text round-trip is
# identity-faithful — the re-parsed text's molfile derives the same
# oracle InChI as the original's:
#
#   1. text(smiles)  — the ruby reference's to_text (the gem's
#                      branch-projection linearizer);
#   2. oracle(smiles molfile) — the original's identifier;
#   3. oracle(text molfile)   — the re-parsed text's identifier.
#
# A disagreement is a recording finding: the script reports it and
# leaves that case's text absent, never guesses. A case whose text
# form is inexpressible (a re-parse failure) skips the same way.
#
#   ruby scripts/record-smiles-text.rb   (the released gem on the
#   load path; ASCIICHEM_INCHI_BIN for the oracle)

require 'asciichem'
require 'json'
require 'tmpdir'

bin = ENV.fetch('ASCIICHEM_INCHI_BIN', 'inchi-1')

def oracle_inchi(molfile, bin)
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, 's.mol'), molfile)
    system(bin, File.join(dir, 's.mol'), File.join(dir, 'o.txt'),
           '-AuxNone', '-NoLabels', '-Key', out: File::NULL, err: File::NULL)
    File.read(File.join(dir, 'o.txt'))[/^InChI=\S+/]
  end
end

families = %w[smiles perception]
recorded = 0
refused = []
skipped = []
families.each do |name|
  family_path = File.join(__dir__, '..', 'corpus', 'fixtures', "#{name}.json")
  family = JSON.parse(File.read(family_path))
  family.each do |row|
    next unless row['parses']

    smiles = row.fetch('smiles')
    id = row.fetch('id')

    begin
      mol = AsciiChem::Smiles.parse(smiles)
      text = mol.to_text
    rescue StandardError => e
      skipped << "#{id}: the read itself declined: #{e.message[0, 60]}"
      next
    end

    begin
      round = AsciiChem.parse(text)
    rescue StandardError => e
      skipped << "#{id}: the text form does not re-parse (#{e.message[0, 40]})"
      next
    end

    begin
      original_identity = oracle_inchi(mol.nodes.first.to_molfile, bin)
      text_identity = oracle_inchi(round.nodes.first.to_molfile, bin)
    rescue AsciiChem::ParseError => e
      skipped << "#{id}: the molfile transport declined (#{e.message[0, 50]})"
      next
    end
    if original_identity.nil? || text_identity.nil?
      skipped << "#{id}: the oracle declined a leg"
      next
    end
    if original_identity != text_identity
      refused << "#{id}: identity moved through the text: " \
                 "#{original_identity} vs #{text_identity}"
      next
    end

    row['text'] = text
    recorded += 1
  end
  File.write(family_path, "#{JSON.pretty_generate(family)}\n")
end

puts "recorded #{recorded} rows; #{skipped.length} skipped, #{refused.length} refused"
skipped.each { |line| puts "  skip  #{line}" }
refused.each { |line| puts "  REFUSE #{line}" }
exit(refused.empty? ? 0 : 1)
