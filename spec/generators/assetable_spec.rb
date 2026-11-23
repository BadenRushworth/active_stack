# frozen_string_literal: true

require "yaml"

RSpec.describe ActiveEngine::Generators::AssetableGenerator do
  def generate(*args) = run_generator(described_class, *args)

  let(:index_js)  { "app/javascript/demo/controllers/index.js" }
  let(:helper_rb) { "app/helpers/demo/assets_helper.rb" }

  describe "isolated mode (defaults)" do
    it "creates the concern, registry, JavaScript, CSS, helper and demo" do
      in_engine do
        generate
        %w[
          lib/demo/concerns/assetable.rb
          lib/demo/assets.rb
          config/importmap.rb
          app/javascript/demo/application.js
          app/javascript/demo/controllers/application.js
          app/javascript/demo/controllers/index.js
          app/javascript/demo/controllers/demo_controller.js
          app/assets/stylesheets/demo/components/demo.css
          app/helpers/demo/assets_helper.rb
          app/controllers/demo/demo_controller.rb
          app/views/demo/demo/index.html.erb
          app/views/layouts/demo/demo.html.erb
        ].each { |path| expect(File).to exist(path), "missing #{path}" }
        expect(File.read("config/routes.rb")).to include('get "demo", to: "demo#index"')
      end
    end

    it "wires the engine, lib file and gemspec" do
      in_engine do
        generate

        engine = File.read("lib/demo/engine.rb")
        expect(engine).to include('require "demo/concerns/assetable"', "include Demo::Concerns::Assetable")
        expect(engine.index("isolate_namespace")).to be < engine.index("include Demo::Concerns::Assetable")
        expect(File.read("lib/demo.rb")).to include('require "importmap-rails"', 'require "turbo-rails"', 'require "stimulus-rails"')
        %w[propshaft importmap-rails turbo-rails stimulus-rails].each do |dep|
          expect(File.read("demo.gemspec")).to include(%(spec.add_dependency "#{dep}"))
        end
      end
    end

    it "generates syntactically valid Ruby" do
      in_engine do
        generate
        Dir.glob("{lib,app}/**/*.rb").each do |file|
          expect(ruby_syntax_ok?(file)).to be(true), "#{file} has a syntax error"
        end
      end
    end

    it "uses stimulus-loading with plain controller names" do
      in_engine do
        generate

        expect(File.read(index_js)).to include("eagerLoadControllersFrom", '"demo/controllers"')
        expect(File.read("config/importmap.rb")).to include("stimulus-loading")
        expect(File.read("app/views/demo/demo/index.html.erb")).to include('data-controller="demo"')
      end
    end

    it "uses the engine's own registry" do
      in_engine do
        generate

        expect(File.read("lib/demo/concerns/assetable.rb")).to include("registry = Demo.assets", 'NAMESPACE = "demo"')
        expect(File.read(helper_rb)).to include("def demo_importmap_tags", "def demo_stylesheet_tags", "Demo.assets.importmap")
      end
    end
  end

  describe "stimulus loader options" do
    it "--lazy uses lazy loading" do
      in_engine do
        generate("--lazy")

        expect(File.read(index_js)).to include("lazyLoadControllersFrom")
      end
    end

    it "--loader prefixed registers namespaced controllers without stimulus-loading" do
      in_engine do
        generate("--loader", "prefixed")

        expect(File.read(index_js)).to include('"demo--"').and(satisfy { |text| !text.include?("stimulus-loading") })
        expect(File.read("config/importmap.rb")).not_to include("stimulus-loading")
        expect(File.read("app/views/demo/demo/index.html.erb")).to include('data-controller="demo--demo"')
      end
    end

    it "rejects unknown loaders and modes" do
      in_engine do
        expect { generate("--loader", "nope") }.to raise_error(Thor::Error, /--loader/)
        expect { generate("--mode", "nope") }.to raise_error(Thor::Error, /--mode/)
      end
    end
  end

  describe "shared mode" do
    it "feeds the given registry, skips the registry file and defaults to prefixed controllers" do
      in_engine do
        generate("--mode", "shared", "--registry", "Core.assets")

        expect(File).not_to exist("lib/demo/assets.rb")
        expect(File.read("lib/demo/concerns/assetable.rb")).to include("registry = Core.assets")
        expect(File.read(helper_rb)).to include("Core.assets.importmap")
        expect(File.read(index_js)).to include('"demo--"')
      end
    end

    it "requires --registry" do
      in_engine do
        expect { generate("--mode", "shared") }.to raise_error(Thor::Error, /--registry/)
      end
    end
  end

  describe "namespace" do
    it "--namespace changes folders, helper names and the pin namespace" do
      in_engine do
        generate("--namespace", "admin")

        expect(File).to exist("app/javascript/admin/application.js")
        expect(File).to exist("app/assets/stylesheets/admin/components/demo.css")
        expect(File.read(helper_rb)).to include("def admin_importmap_tags")
        expect(File.read("lib/demo/concerns/assetable.rb")).to include('NAMESPACE = "admin"')
        expect(YAML.safe_load_file(".active_engine.yml")["namespace"]).to eq("admin")
      end
    end
  end

  describe "--no-demo" do
    it "skips the demo files and route but keeps the stylesheet comment" do
      in_engine do
        generate("--no-demo")

        expect(File).not_to exist("app/controllers/demo/demo_controller.rb")
        expect(File).not_to exist("app/assets/stylesheets/demo/components/demo.css")
        expect(File.read("config/routes.rb")).not_to include("demo#index")
        expect(File.read(CSS)).to include("demo_stylesheet_tags")
      end
    end
  end

  describe "layouts" do
    it "replaces the scaffold stylesheet line, adds the importmap tag and backs the layout up" do
      in_engine do
        generate

        layout = File.read(LAYOUT)
        expect(layout).to include('<%= demo_stylesheet_tags media: "all" %>', "<%= demo_importmap_tags %>")
        expect(layout).not_to include('stylesheet_link_tag "demo/application"')
        expect(File.read("#{LAYOUT}.backup")).to include('stylesheet_link_tag "demo/application"')
      end
    end

    it "leaves a layout that already uses the host's importmap alone, with a warning" do
      host_layout = "<html>\n  <head>\n    <%= javascript_importmap_tags %>\n  </head>\n</html>\n"
      in_engine(LAYOUT => host_layout) do
        out = generate

        expect(File.read(LAYOUT)).not_to include("demo_importmap_tags")
        expect(out).to include("left alone")
      end
    end
  end

  describe "stylesheets" do
    it "inserts the starter comment into an existing application.css and keeps the content" do
      in_engine(CSS => ".mine { color: red; }\n") do
        generate

        css = File.read(CSS)
        expect(css).to include("demo_stylesheet_tags", ".mine { color: red; }")
        expect(css.index("demo_stylesheet_tags")).to be < css.index(".mine")
        expect(File).not_to exist("#{CSS}.backup")
      end
    end
  end

  describe "re-running" do
    it "is idempotent: nothing changes and no backups appear" do
      in_engine do
        generate
        before = snapshot
        out = generate

        expect(out).to include("Already up to date")
        expect(snapshot).to eq(before)
        expect(Dir.glob("**/*.backup*").size).to eq(1) # only the scaffold layout backup from run one
      end
    end

    it "never overwrites starter files you edited" do
      in_engine do
        generate
        append(index_js, "// my custom load order\n")
        generate

        expect(File.read(index_js)).to include("// my custom load order")
      end
    end

    it "--force regenerates starter files and keeps a backup" do
      in_engine do
        generate
        append(index_js, "// my custom load order\n")
        generate("--force")

        expect(File.read(index_js)).not_to include("// my custom load order")
        expect(File.read("#{index_js}.backup")).to include("// my custom load order")
      end
    end

    it "backs up edited generated files before rewriting them, without overwriting older backups" do
      in_engine do
        generate
        original = File.read(helper_rb)

        append(helper_rb, "# first edit\n")
        generate
        expect(File.read(helper_rb)).to eq(original)
        expect(File.read("#{helper_rb}.backup")).to include("# first edit")

        append(helper_rb, "# second edit\n")
        generate
        expect(File.read("#{helper_rb}.backup.2")).to include("# second edit")
        expect(File.read("#{helper_rb}.backup")).to include("# first edit")
      end
    end
  end

  describe ".active_engine.yml" do
    it "remembers choices between runs" do
      in_engine do
        generate("--mode", "shared", "--registry", "Core.assets")
        before = snapshot
        out = generate

        expect(out).to include("Already up to date")
        expect(snapshot).to eq(before)
        expect(YAML.safe_load_file(".active_engine.yml")["assetable"]).to include("mode" => "shared", "registry" => "Core.assets", "loader" => "prefixed")
      end
    end

    it "lets command-line flags override saved values" do
      in_engine do
        generate("--no-demo")
        generate
        expect(File).not_to exist("app/controllers/demo/demo_controller.rb")

        generate("--demo")
        expect(File).to exist("app/controllers/demo/demo_controller.rb")
      end
    end
  end
end
