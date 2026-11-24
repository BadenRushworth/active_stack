# frozen_string_literal: true

RSpec.describe ActiveEngine::Generators::AssetableGenerator do
  def generate(*args) = run_generator(described_class, *args)

  describe "a slash in --namespace" do
    it "nests folders but uses dashes for Stimulus identifiers and CSS classes" do
      in_engine do
        generate("--namespace", "lifeguard/admin", "--loader", "prefixed")

        css = "app/assets/stylesheets/lifeguard/admin/components/demo.css"
        expect(File).to exist("app/javascript/lifeguard/admin/application.js")
        expect(File).to exist(css)
        expect(File.read("app/javascript/lifeguard/admin/controllers/index.js"))
          .to include('"lifeguard-admin--"', '"lifeguard/admin/controllers/"')
        expect(File.read("app/views/demo/demo/index.html.erb"))
          .to include('data-controller="lifeguard-admin--demo"', "lifeguard-admin-demo")
        expect(File.read(css)).to include(".lifeguard-admin-demo")
        expect(File.read("app/helpers/demo/assets_helper.rb"))
          .to include("def lifeguard_admin_importmap_tags", 'Dir.glob(["lifeguard/admin*.css", "lifeguard/admin*/**/*.css"]')
        expect(File.read("lib/demo/concerns/assetable.rb")).to include('NAMESPACE = "lifeguard/admin"')
      end
    end
  end

  describe "an engine in a nested module (lib/lifeguard/admin)" do
    let(:files) do
      {
        "lib/demo.rb" => nil,
        "lib/demo/engine.rb" => nil,
        "demo.gemspec" => nil,
        "app/views/layouts/demo/application.html.erb" => nil,
        "app/assets/stylesheets/demo/application.css" => nil,
        "lib/lifeguard/admin.rb" => %(require "lifeguard/admin/engine"\n\nmodule Lifeguard\n  module Admin\n  end\nend\n),
        "lib/lifeguard/admin/engine.rb" => <<~RUBY,
          module Lifeguard
            module Admin
              class Engine < ::Rails::Engine
                isolate_namespace Lifeguard::Admin
              end
            end
          end
        RUBY
        "lifeguard_admin.gemspec" => %(Gem::Specification.new do |spec|\n  spec.name = "lifeguard_admin"\nend\n),
        "config/routes.rb" => "Lifeguard::Admin::Engine.routes.draw do\nend\n"
      }
    end

    it "places files in nested folders and names things after the full path" do
      in_engine(files) do
        generate("--no-demo")

        expect(File).to exist("lib/lifeguard/admin/concerns/assetable.rb")
        expect(File).to exist("lib/lifeguard/admin/assets.rb")
        expect(File).to exist("app/helpers/lifeguard/admin/assets_helper.rb")
        expect(File).to exist("app/javascript/lifeguard_admin/application.js")
        expect(File.read("lib/lifeguard/admin/engine.rb"))
          .to include('require "lifeguard/admin/concerns/assetable"', "include Lifeguard::Admin::Concerns::Assetable")
        expect(File.read("lib/lifeguard/admin.rb")).to include('require "importmap-rails"')
        expect(File.read("app/helpers/lifeguard/admin/assets_helper.rb"))
          .to include("module Lifeguard::Admin", "def lifeguard_admin_importmap_tags")
        Dir.glob("{lib,app}/**/*.rb").each do |file|
          expect(ruby_syntax_ok?(file)).to be(true), "#{file} has a syntax error"
        end
      end
    end
  end
end
