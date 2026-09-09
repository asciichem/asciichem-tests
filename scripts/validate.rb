# frozen_string_literal: true

# Corpus self-validation, dependency-free: every fixture file parses,
# every case has an id, ids are globally unique, and every case has
# the keys its kind requires. Exits non-zero with the offender named.

require "json"
require "set"

ROOT = File.expand_path("..", __dir__)
FIXTURES = Dir[File.join(ROOT, "corpus", "fixtures", "*.json")].sort

PARSER_KEYS = %w[id input parses].freeze
IDENTIFIER_KEYS = %w[id convention value valid].freeze
LINT_KEYS = %w[id input lint].freeze

failures = []
ids = Set.new

FIXTURES.each do |path|
  label = File.basename(path)
  begin
    data = JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    failures << "#{label}: invalid JSON (#{e.message})"
    next
  end

  data.each_with_index do |case_data, index|
    where = "#{label}[#{index}]"
    unless case_data.is_a?(Hash)
      failures << "#{where}: not an object"
      next
    end

    id = case_data["id"].to_s
    failures << "#{where}: missing id" if id.empty?
    failures << "#{where}: duplicate id #{id}" if ids.include?(id)
    ids << id unless id.empty?

    required = if case_data.key?("convention")
                 IDENTIFIER_KEYS
               elsif case_data.key?("lint")
                 LINT_KEYS
               else
                 PARSER_KEYS
               end
    required.each do |key|
      failures << "#{where}: missing required key #{key}" unless case_data.key?(key)
    end
  end
end

if failures.empty?
  puts "OK: #{FIXTURES.length} fixture files, #{ids.length} unique cases"
else
  failures.each { |f| warn f }
  exit 1
end
