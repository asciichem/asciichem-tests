# frozen_string_literal: true

# Corpus self-validation, mirroring the iso-8601-test-suite pattern:
# every artifact is guarded by a YAML Schema.
#
# Pass 1 (dependency-free fast checks): every fixture file parses,
# every case has an id, ids are globally unique, parseable molfile
# cases carry atom/bond counts.
# Pass 2 (schema): every fixture file validates against its
# filename-matched schema in corpus/schemas/fixtures/ (JSON Schema,
# YAML-encoded), and suite.yaml validates against the manifest
# schema. additionalProperties: false catches typo'd keys (e.g.
# "roundtrip" vs "roundTrip") before they reach an implementation.

require "json"
require "set"
require "yaml"

ROOT = File.expand_path("..", __dir__)
FIXTURES = Dir[File.join(ROOT, "corpus", "fixtures", "*.json")].sort
SCHEMA_DIR = File.join(ROOT, "corpus", "schemas", "fixtures")

begin
  require "json_schemer"
rescue LoadError
  warn "json_schemer is required for schema validation — run: bundle install"
  exit 1
end

failures = []
ids = Set.new

FIXTURES.each do |path|
  label = File.basename(path)
  data = begin
    JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    failures << "#{label}: invalid JSON (#{e.message})"
    next
  end

  # Pass 1: fast structural checks.
  data.each_with_index do |case_data, index|
    where = "#{label}[#{index}]"
    next unless case_data.is_a?(Hash)

    id = case_data["id"].to_s
    failures << "#{where}: missing id" if id.empty?
    failures << "#{where}: duplicate id #{id}" if ids.include?(id)
    ids << id unless id.empty?
    if case_data.key?("molfile") && case_data["parses"] &&
       !(case_data.key?("atoms") && case_data.key?("bonds"))
      failures << "#{where}: parseable molfile case needs atoms + bonds"
    end
  end

  # Pass 2: schema guarding (fixture parser-acceptance.json is guarded
  # by corpus/schemas/fixtures/parser-acceptance.yaml).
  schema_name = label.sub(/\.json\z/, ".yaml")
  schema_path = File.join(SCHEMA_DIR, schema_name)
  schema = begin
    JSONSchemer.schema(YAML.safe_load(File.read(schema_path)))
  rescue Errno::ENOENT
    failures << "#{label}: no schema at corpus/schemas/fixtures/#{schema_name}"
    next
  end
  data.each_with_index do |case_data, index|
    schema.validate(case_data).each do |error|
      failures << "#{label}[#{index}]: #{error['data_pointer']} #{error['type']}"
    end
  end
end

# Suite manifest must itself be schema-valid YAML.
manifest_schema_path = File.join(SCHEMA_DIR, "suite-manifest.yaml")
if File.file?(manifest_schema_path)
  manifest = YAML.safe_load(File.read(File.join(ROOT, "suite.yaml")))
  JSONSchemer.schema(YAML.safe_load(File.read(manifest_schema_path)))
              .validate(manifest).each do |error|
    failures << "suite.yaml: #{error['data_pointer']} #{error['type']}"
  end
end

if failures.empty?
  puts "OK: #{FIXTURES.length} fixture files, #{ids.length} unique cases, all schema-valid"
else
  failures.each { |f| warn f }
  exit 1
end
