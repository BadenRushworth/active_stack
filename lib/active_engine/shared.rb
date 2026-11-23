# frozen_string_literal: true

require "erb"
require "rails/generators"
require "active_engine/ui"
require "active_engine/config"

module ActiveEngine
  module Generators
    # Plumbing shared by every ActiveEngine generator: finds the engine in the current
    # directory, exposes its names to generators and templates, reads .active_engine.yml,
    # and writes files quietly (only changes are reported).
    module Shared
      include UI

      def self.included(base)
        base.class_option :engine,      type: :string,  desc: "Engine name (default: auto-detected in lib/**/engine.rb)"
        base.class_option :namespace,   type: :string,  desc: "Namespace for JS, CSS and pins (default: engine name)"
        base.class_option :interactive, type: :boolean, default: false, aliases: "-i",
                                        desc: "Prompt for choices instead of using saved/default values"
      end

      private

      # -- engine discovery ---------------------------------------------------

      def load_engine!
        return true if @engine_file

        found = Dir.glob("lib/**/engine.rb").select { |f| File.read(f).match?(/<\s*(::)?Rails::Engine/) }
        found.select! { |f| engine_path_for(f).tr("/", "_") == options[:engine] } if options[:engine]
        raise Thor::Error, "No Rails engine found - run this from an engine's root directory." if found.empty?

        @engine_file = found.one? ? found.first : pick_engine(found)
        @engine_path = engine_path_for(@engine_file)
        @engine_name = @engine_path.tr("/", "_")
        @mod = File.read(@engine_file)[/isolate_namespace\s+([\w:]+)/, 1] ||
               @engine_path.split("/").map(&:camelize).join("::")
        true
      end

      def engine_file = load_engine! && @engine_file
      def engine_path = load_engine! && @engine_path   # "lifeguard/admin" or "my_engine"
      def engine_name = load_engine! && @engine_name   # "lifeguard_admin" or "my_engine"
      def mod         = load_engine! && @mod           # "Lifeguard::Admin" or "MyEngine"

      def engine_path_for(file) = file.delete_prefix("lib/").delete_suffix("/engine.rb")

      def pick_engine(files)
        ui_heading "Engines found"
        files.each_with_index { |f, i| say "  #{i + 1}. #{engine_path_for(f)}" }
        choices = files.each_index.map { |i| (i + 1).to_s }
        files[ask("Which engine?", :yellow, limited_to: choices, default: "1").to_i - 1]
      end

      # -- settings -----------------------------------------------------------

      def engine_config = (@engine_config ||= Config.new)

      # CLI flag > .active_engine.yml > default
      def setting(name, section: nil, default: nil)
        cli = options[name]
        return cli unless cli.nil?

        engine_config.get(*[section, name].compact, default: default)
      end

      # Namespace for JS dir, CSS dir, importmap pins and helper names.
      def ns
        @ns ||= begin
          saved = engine_config.get("namespace").presence || engine_name
          options[:namespace].presence ||
            (options[:interactive] ? ask("Namespace for JS/CSS/pins?", :yellow, default: saved) : saved)
        end
      end

      # Stimulus identifier prefix: data-controller="<ns-dashed>--name"
      def identifier_prefix = ns.dasherize

      # Stores this run's choices in .active_engine.yml (a change only if the file changed).
      def remember(section, **values)
        values.each { |key, value| engine_config.set(section, key, value) }
        engine_config.write ? touched! : unchanged!
      end

      # -- quiet file writing -------------------------------------------------

      def render_tt(source)
        path = find_in_source_paths(source)
        ERB.new(File.binread(path), trim_mode: "-", eoutvar: "@output_buffer").result(instance_eval("binding"))
      end

      # Renders a template and writes it only if it differs from what is on disk.
      def put(source, destination)
        content = render_tt(source)
        if File.exist?(destination) && File.binread(destination) == content
          unchanged!
        else
          create_file destination, content
          touched!
        end
      end

      def touched!   = (@touched = @touched.to_i + 1)
      def unchanged! = (@unchanged = @unchanged.to_i + 1)
      def changed?   = @touched.to_i.positive?

      def ui_summary
        if changed?
          ui_ok "#{@touched} changed, #{@unchanged.to_i} already up to date"
        else
          ui_ok "Already up to date (#{@unchanged.to_i} checked)"
        end
      end

      # Adds `require` + `include <Mod>::Concerns::<Name>` right after isolate_namespace
      # (the concerns build initializer names from engine_name, so order matters).
      def wire_concern(name)
        content = File.read(engine_file)
        return unchanged! if content.include?("Concerns::#{name}")

        unless content.match?(/^\s*isolate_namespace /)
          raise Thor::Error, "#{engine_file} has no isolate_namespace line - add it first, then re-run."
        end

        inject_into_file engine_file, <<~RUBY.indent(4), after: /^\s*isolate_namespace .*\n/
          require "#{engine_path}/concerns/#{name.underscore}"
          include #{mod}::Concerns::#{name}
        RUBY
        touched!
      end
    end
  end
end
