# frozen_string_literal: true

require "yaml"

module ActiveEngine
  # Reads and writes .active_engine.yml in the engine root (the current directory).
  # Precedence everywhere: command-line flag > this file > built-in default.
  #
  # Layout: generator_version, namespace, one section per installed tool, and `files`
  # (path => SHA256 of the content a generator last wrote there).
  class Config
    FILE = ".active_engine.yml"
    FILES_KEY = "files"
    HEADER = <<~TXT
      # .active_engine.yml - written by `rails g active_engine`.
      # Defaults for the ActiveEngine generators in this engine. Safe to commit and edit;
      # command-line flags override these values. Names, choices and checksums only, no secrets.
    TXT

    def initialize(path = FILE)
      @path = path
      @data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
    end

    def get(*keys, default: nil)
      value = @data.dig(*keys.map(&:to_s))
      value.nil? ? default : value
    rescue TypeError
      default
    end

    def set(*keys, value)
      *parents, last = keys.map(&:to_s)
      node = parents.reduce(@data) do |hash, key|
        hash[key] = {} unless hash[key].is_a?(Hash)
        hash[key]
      end
      node[last] = value
    end

    def delete(*keys)
      *parents, last = keys.map(&:to_s)
      node = parents.empty? ? @data : @data.dig(*parents)
      node.delete(last) if node.is_a?(Hash)
    end

    # Names of the installed tools: every section except the files map.
    def tools = @data.select { |key, value| value.is_a?(Hash) && key != FILES_KEY }.keys

    # Checksums of generated files: { "lib/x/concerns/assetable.rb" => "<sha256>" }
    def files
      value = @data[FILES_KEY]
      value.is_a?(Hash) ? value : {}
    end

    # Returns true only when the file content actually changed (or would change, with
    # dry_run: true, which writes nothing).
    def write(dry_run: false)
      @data = { "generator_version" => VERSION }.merge(@data.except("generator_version"))
      files = @data.delete(FILES_KEY)
      @data[FILES_KEY] = files.sort.to_h if files.is_a?(Hash) && files.any?
      text = HEADER + YAML.dump(@data).delete_prefix("---\n")
      return false if File.exist?(@path) && File.read(@path) == text

      File.write(@path, text) unless dry_run
      true
    end
  end
end
