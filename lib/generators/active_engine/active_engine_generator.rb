# frozen_string_literal: true

require "active_engine/version"
require "active_engine/shared"

module ActiveEngine
  module Generators
    class ActiveEngineGenerator < Rails::Generators::Base
      include Shared

      desc "Interactive menu: choose which ActiveEngine tools to install on an engine"

      class_option :only,     type: :array,   desc: "Skip the menu, e.g. --only assetable migratable"
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

        names = options[:only].presence || ask_for_generators
        return ui_warn("Nothing selected.") if names.empty?

        passthrough = options.to_h.except("only").merge("engine" => engine_name)
        names.each { |name| invoke "active_engine:#{name}", [], passthrough }
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
    end
  end
end
