# frozen_string_literal: true

RSpec.describe "engines that already have their own setup" do
  let(:engine_rb) { "lib/demo/engine.rb" }
  let(:own_engine) do
    <<~RUBY
      module Demo
        class Engine < ::Rails::Engine
          isolate_namespace Demo
          include Demo::Migratable
          include ::Lifeguard::Concerns::Assetable
        end
      end
    RUBY
  end

  describe ActiveEngine::Generators::MigratableGenerator do
    it "keeps the engine's own include and generates no concern" do
      in_engine(engine_rb => own_engine) do
        out = run_generator(described_class)

        expect(File.read(engine_rb)).to eq(own_engine)
        expect(File).not_to exist("lib/demo/concerns/migratable.rb")
        expect(out).to include("already includes Demo::Migratable")
      end
    end
  end

  describe ActiveEngine::Generators::AssetableGenerator do
    it "refuses isolated mode, which would clash with the engine's own registry" do
      in_engine(engine_rb => own_engine) do
        expect { run_generator(described_class) }.to raise_error(Thor::Error, /--mode shared/)

        expect(File.read(engine_rb)).to eq(own_engine)
        expect(Dir).not_to exist("app/javascript")
      end
    end

    it "in shared mode adds only the helpers, JavaScript and CSS" do
      in_engine(engine_rb => own_engine) do
        out = run_generator(described_class, "--mode", "shared", "--registry", "Lifeguard.assets", "--no-demo")

        expect(File.read(engine_rb)).to eq(own_engine)
        expect(File).not_to exist("lib/demo/concerns/assetable.rb")
        expect(File).to exist("app/helpers/demo/assets_helper.rb")
        expect(File).to exist("app/javascript/demo/controllers/index.js")
        expect(out).to include("already includes Lifeguard::Concerns::Assetable")
      end
    end
  end
end
