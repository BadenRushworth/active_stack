# frozen_string_literal: true

RSpec.describe ActiveEngine::Generators::ActiveEngineGenerator do
  describe ".available" do
    subject(:available) { described_class.available }

    it "discovers every tool from generators/active_engine/*/*_generator.rb" do
      expect(available.keys).to include("assetable", "migratable")
    end

    it "uses each tool's desc as the menu text" do
      expect(available["assetable"]).to match(/importmap/i)
      expect(available["migratable"]).to include("db/migrate")
    end
  end

  it "runs the tools named with --only and records both in .active_engine.yml" do
    in_engine do
      run_generator(described_class, "--only", "assetable", "migratable", "--no-demo")

      expect(File).to exist("lib/demo/concerns/assetable.rb")
      expect(File).to exist("lib/demo/concerns/migratable.rb")
      expect(YAML.safe_load_file(".active_engine.yml").keys).to include("namespace", "assetable", "migratable", "generator_version")
    end
  end

  it "passes options through to the tools" do
    in_engine do
      run_generator(described_class, "--only", "assetable", "--mode", "shared", "--registry", "Core.assets", "--no-demo")

      expect(File.read("lib/demo/concerns/assetable.rb")).to include("registry = Core.assets")
    end
  end
end
