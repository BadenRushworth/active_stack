# frozen_string_literal: true

require "active_engine/shared"

module ActiveEngine
  module Generators
    class AssetableGenerator < Rails::Generators::Base
      include Shared

      source_root File.expand_path("templates", __dir__)

      desc "Adds Propshaft, importmap, Stimulus and CSS helpers to an engine (isolated or shared importmap)"

      LOADERS = %w[stimulus-loading prefixed].freeze

      # No defaults here on purpose: CLI flag > .active_engine.yml > built-in default.
      class_option :mode,     type: :string,  desc: "isolated (own importmap, default) or shared (feeds an existing registry)"
      class_option :registry, type: :string,  desc: "--mode shared: Ruby expression of the shared registry, e.g. Lifeguard.assets"
      class_option :loader,   type: :string,  desc: "stimulus-loading (default for isolated) or prefixed (default for shared)"
      class_option :lazy,     type: :boolean, desc: "stimulus-loading: lazy-load controllers when first used (default: eager)"
      class_option :demo,     type: :boolean, desc: "Install demo controller, view, layout and assets (default: yes; --no-demo to skip)"

      def welcome
        ui_step "Assetable - #{mod}  (#{mode}, #{loader} loader, namespace #{ns})"
      end

      def copy_concern_and_registry
        put "assetable.rb.tt", "lib/#{engine_path}/concerns/assetable.rb"
        put "assets.rb.tt",    "lib/#{engine_path}/assets.rb" if isolated?
        wire_concern("Assetable")
      end

      def scan_dependencies
        lib_file = "lib/#{engine_path}.rb"
        if !File.exist?(lib_file)
          ui_warn "#{lib_file} not found - add requires for importmap-rails, turbo-rails, stimulus-rails"
        elsif File.read(lib_file).include?("importmap-rails")
          unchanged!
        else
          inject_into_file lib_file,
                           %(require "importmap-rails"\nrequire "turbo-rails"\nrequire "stimulus-rails"\n),
                           before: /^require "#{Regexp.escape(engine_path)}\/engine"/
          touched!
          @needs_bundle = true
        end

        gemspec = Dir.glob("*.gemspec").first
        return ui_warn("No gemspec found - add propshaft, importmap-rails, turbo-rails, stimulus-rails yourself.") unless gemspec

        missing = %w[propshaft importmap-rails turbo-rails stimulus-rails].reject { |dep| File.read(gemspec).include?(%("#{dep}")) }
        return unchanged! if missing.empty?

        missing.each { |dep| insert_into_file gemspec, %(  spec.add_dependency "#{dep}"\n), before: /^end\s*\z/ }
        ui_ok "#{gemspec}: added #{missing.join(', ')}"
        touched!
        @needs_bundle = true
      end

      def copy_javascript
        seed "importmap.rb.tt", "config/importmap.rb"
        seed "application.js.tt", "app/javascript/#{ns}/application.js"
        seed "controllers/application.js.tt", "app/javascript/#{ns}/controllers/application.js"
        seed "controllers/index.#{prefixed? ? 'prefixed' : 'stimulus_loading'}.js.tt", "app/javascript/#{ns}/controllers/index.js"
        put "controllers/demo_controller.js.tt", "app/javascript/#{ns}/controllers/demo_controller.js" if demo?
      end

      def copy_stylesheets
        seed_comment "css/application.css.tt", "app/assets/stylesheets/#{ns}/application.css", marker: "#{helper_prefix}_stylesheet_tags"
        put "css/demo.css.tt", "app/assets/stylesheets/#{ns}/components/demo.css" if demo?
      end

      def copy_helper
        put "assets_helper.rb.tt", "app/helpers/#{engine_path}/assets_helper.rb"
      end

      def wire_layouts
        layouts = Dir.glob("app/views/layouts/**/*.erb").reject { |f| f.end_with?("/demo.html.erb") }
        layouts.each { |file| wire_layout(file) }
      end

      def copy_demo
        return unless demo?

        put "demo/controller.rb.tt",   "app/controllers/#{engine_path}/demo_controller.rb"
        put "demo/index.html.erb.tt",  "app/views/#{engine_path}/demo/index.html.erb"
        put "demo/layout.html.erb.tt", "app/views/layouts/#{engine_path}/demo.html.erb"

        routes = "config/routes.rb"
        if !File.exist?(routes)
          ui_warn "No #{routes}; add: get \"demo\", to: \"demo#index\""
        elsif File.read(routes).include?("demo#index")
          unchanged!
        else
          inject_into_file routes, %(  get "demo", to: "demo#index"\n), after: /\.routes\.draw do\n/
          touched!
        end
      end

      def save_settings
        engine_config.set("namespace", ns)
        engine_config.delete("assetable", "registry") if isolated?
        values = { mode: mode, loader: loader, lazy: lazy?, demo: demo? }
        values[:registry] = registry_expr unless isolated?
        remember "assetable", **values
      end

      def finish
        ui_summary
        return unless changed?

        ui_cmd "bundle install" if @needs_bundle
        ui_cmd "bin/rails s    # then open <mount path>/demo" if demo?
        unless @layouts_wired
          ui_info "No engine layout found. Add to your layout's <head>:"
          ui_cmd "<%= #{helper_prefix}_stylesheet_tags media: \"all\" %>"
          ui_cmd "<%= #{helper_prefix}_importmap_tags %>"
        end
        ui_info "Stimulus: data-controller=\"#{prefixed? ? "#{identifier_prefix}--name" : 'name'}\" " \
                "for app/javascript/#{ns}/controllers/name_controller.js"
      end

      private

      def wire_layout(file)
        content = File.read(file)
        return ui_warn("#{file}: no </head>, skipped") unless content.include?("</head>")

        @layouts_wired = true
        css = "#{helper_prefix}_stylesheet_tags"
        js  = "#{helper_prefix}_importmap_tags"
        scaffold_css = /^[ \t]*<%=\s*stylesheet_link_tag\s+["']#{Regexp.escape(ns)}\/application["'][^\n]*%>[ \t]*\n/
        css_line     = "    <%= #{css} media: \"all\" %>\n"

        if content.include?(css)
          unchanged!
        elsif content.match?(scaffold_css)
          backup_file(file)
          gsub_file file, scaffold_css, css_line
          touched!
        else
          inject_into_file file, css_line, before: /^[ \t]*<\/head>/
          touched!
        end

        if content.include?(js)
          unchanged!
        elsif content.include?("javascript_importmap_tags")
          ui_warn "#{file}: uses the host's javascript_importmap_tags - left alone (two import maps break a page). " \
                  "Switch to #{js} if this layout is standalone."
        else
          inject_into_file file, "    <%= #{js} %>\n", before: /^[ \t]*<\/head>/
          touched!
        end
      end

      def mode
        @mode ||= begin
          saved  = engine_config.get("assetable", "mode") || "isolated"
          chosen = options[:mode].presence ||
                   (options[:interactive] ? ask("Importmap mode?", :yellow, limited_to: %w[isolated shared], default: saved) : saved)
          raise Thor::Error, "--mode must be isolated or shared" unless %w[isolated shared].include?(chosen)

          chosen
        end
      end

      def loader
        @loader ||= begin
          same_mode = engine_config.get("assetable", "mode") == mode
          saved     = (same_mode && engine_config.get("assetable", "loader")) || (isolated? ? "stimulus-loading" : "prefixed")
          chosen    = options[:loader].presence ||
                      (options[:interactive] ? ask("Stimulus loader?", :yellow, limited_to: LOADERS, default: saved) : saved)
          raise Thor::Error, "--loader must be one of: #{LOADERS.join(', ')}" unless LOADERS.include?(chosen)

          chosen
        end
      end

      def isolated? = mode == "isolated"
      def prefixed? = loader == "prefixed"
      def lazy?     = setting(:lazy, section: "assetable", default: false)
      def demo?     = setting(:demo, section: "assetable", default: true)

      # Identifier of the demo Stimulus controller in the views.
      def demo_identifier = prefixed? ? "#{identifier_prefix}--demo" : "demo"

      # Ruby expression (evaluated inside the engine) that returns the registry.
      def registry_expr
        @registry_expr ||=
          if isolated?
            "#{mod}.assets"
          else
            saved = engine_config.get("assetable", "registry").to_s
            options[:registry].presence ||
              (options[:interactive] ? ask("Shared registry expression (e.g. Lifeguard.assets)?", :yellow, default: saved).strip.presence : saved.presence) ||
              raise(Thor::Error, "--mode shared needs --registry 'Some.assets'")
          end
      end

      def helper_prefix = ns.tr("-/", "__")
      def js_global     = "#{helper_prefix.camelize}Stimulus"
    end
  end
end
