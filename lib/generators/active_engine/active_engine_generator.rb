# frozen_string_literal: true

require "digest"
require "active_engine/version"
require "active_engine/shared"

module ActiveEngine
  module Generators
    class ActiveEngineGenerator < Rails::Generators::Base
      include Shared

      desc "Interactive menu: choose which ActiveEngine tools to install on an engine"

      class_option :only,     type: :array,   desc: "Skip the menu, e.g. --only assetable migratable"
      class_option :doctor,   type: :boolean, default: false, desc: "Check the engine against .active_engine.yml (writes nothing)"
      class_option :upgrade,  type: :boolean, default: false, desc: "Re-run every installed tool from .active_engine.yml (preview with --dry-run)"
      class_option :mode,     type: :string,  desc: "assetable: isolated | shared"
      class_option :registry, type: :string,  desc: "assetable --mode shared: Ruby expression for the shared registry"
      class_option :loader,   type: :string,  desc: "assetable: stimulus-loading | prefixed"
      class_option :lazy,     type: :boolean, desc: "assetable: lazy-load Stimulus controllers"
      class_option :demo,     type: :boolean, desc: "assetable: install the demo (--no-demo to skip)"

      # Any gem on the load path can add a tool by shipping
      # generators/active_engine/<name>/<name>_generator.rb. Its `desc "..."` is the menu text.
      def self.available
        stubs = $LOAD_PATH.flat_map do |dir|
          Dir.glob(File.join(dir.to_s, "generators", "active_engine", "*", "*_generator.rb"))
        end
        stubs.uniq { |file| File.basename(File.dirname(file)) }
             .sort_by { |file| File.basename(File.dirname(file)) }
             .to_h { |file| [File.basename(File.dirname(file)), describe(File.basename(File.dirname(file)), file)] }
      end

      # Stubs only require the real generator (lib/active_engine/<name>/<name>_generator.rb).
      def self.describe(name, stub)
        real = $LOAD_PATH.map { |dir| File.join(dir.to_s, "active_engine", name, "#{name}_generator.rb") }
                         .find { |file| File.exist?(file) }
        File.read(real || stub)[/^\s*desc\s+"([^"]+)"/, 1].to_s
      end

      def run_selected
        ui_banner "ActiveEngine v#{ActiveEngine::VERSION}"
        ui_info "Engine: #{mod} (lib/#{engine_path})"
        ui_warn "Dry run - nothing will be written." if dry_run?

        return run_doctor if options[:doctor]

        names = options[:upgrade] ? upgrade_names : (options[:only].presence || ask_for_generators)
        return ui_warn("Nothing selected.") if names.empty?

        previous = engine_config.get("generator_version")
        passthrough = options.to_h.except("only", "doctor", "upgrade").merge("engine" => engine_name)
        names.each { |name| invoke "active_engine:#{name}", [], passthrough }
        report_upgrade(previous) if options[:upgrade]
      end

      private

      def ask_for_generators
        available = self.class.available
        raise Thor::Error, "No generators found." if available.empty?

        all = available.size + 1
        ui_heading "Available tools"
        available.each_with_index do |(name, text), i|
          say "  #{set_color((i + 1).to_s, :green)}. #{set_color(name.ljust(12), :bold)} #{text}"
        end
        say "  #{set_color(all.to_s, :green)}. #{set_color("all".ljust(12), :bold)} Run everything above\n\n"

        picks = ask("Run which? (e.g. 1,2)", :yellow, default: all.to_s).split(/[,\s]+/).map(&:to_i)
        return available.keys if picks.include?(all)

        available.keys.values_at(*picks.select { |n| n.between?(1, available.size) }.map { |n| n - 1 })
      end

      # -- upgrade ------------------------------------------------------------

      # Tools recorded in .active_engine.yml that still have a generator, optionally
      # narrowed with --only. Each tool reads its own settings from the yml.
      def upgrade_names
        known = self.class.available.keys
        recorded = engine_config.tools
        (recorded - known).each do |tool|
          ui_warn "#{tool}: recorded in #{Config::FILE} but no such generator is available - skipped"
        end

        names = known & recorded
        raise Thor::Error, "No installed tools found in #{Config::FILE} - run `rails g active_engine` first." if names.empty?

        options[:only].presence ? names & options[:only] : names
      end

      def report_upgrade(previous)
        if dry_run?
          ui_info "Dry run only. Run again without --dry-run to apply."
        else
          ui_ok "Upgraded #{previous ? "v#{previous}" : 'an unversioned setup'} -> v#{ActiveEngine::VERSION}"
        end
      end

      # -- doctor -------------------------------------------------------------

      # Read-only health check. Warnings (edited files, older version) never fail the run;
      # problems (missing files, unknown tools) raise so scripts and CI can notice.
      def run_doctor
        raise Thor::Error, "#{Config::FILE} not found - run `rails g active_engine` first." unless File.exist?(Config::FILE)

        problems = 0
        warnings = 0
        ui_heading "Doctor"

        saved = engine_config.get("generator_version")
        if saved.nil?
          ui_warn "#{Config::FILE} has no generator_version"
          warnings += 1
        elsif outdated?(saved)
          ui_warn "Generated with v#{saved}, installed gem is v#{ActiveEngine::VERSION}. " \
                  "Preview: bin/rails g active_engine --upgrade --dry-run"
          warnings += 1
        else
          ui_ok "Generator version #{saved}"
        end

        known = self.class.available.keys
        tools = engine_config.tools
        if tools.empty?
          ui_warn "No tools recorded in #{Config::FILE}"
          warnings += 1
        end
        tools.each do |tool|
          if known.include?(tool)
            ui_ok "Tool #{tool}"
          else
            ui_fail "#{tool}: recorded in #{Config::FILE} but no such generator is available"
            problems += 1
          end
        end

        files = engine_config.files
        ui_info "No checksums recorded yet - run --upgrade once to record them." if files.empty? && tools.any?

        unchanged = 0
        files.sort.each do |path, checksum|
          if !File.exist?(path)
            ui_fail "#{path}: missing - --upgrade recreates it"
            problems += 1
          elsif Digest::SHA256.file(path).hexdigest != checksum
            ui_warn "#{path}: edited since generated - --upgrade keeps a .backup of your version"
            warnings += 1
          else
            unchanged += 1
          end
        end
        ui_ok "#{unchanged} generated file(s) unchanged" if unchanged.positive?

        ui_info "#{warnings} warning(s), #{problems} problem(s)"
        raise Thor::Error, "Doctor found #{problems} problem(s)." if problems.positive?
      end

      def outdated?(saved)
        Gem::Version.new(saved.to_s) < Gem::Version.new(ActiveEngine::VERSION)
      rescue ArgumentError
        true
      end
    end
  end
end
