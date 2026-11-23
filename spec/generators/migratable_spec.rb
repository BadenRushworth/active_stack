# frozen_string_literal: true

RSpec.describe ActiveEngine::Generators::MigratableGenerator do
  it "installs the concern and wires it into the engine after isolate_namespace" do
    in_engine do
      run_generator(described_class)

      expect(File).to exist("lib/demo/concerns/migratable.rb")
      engine = File.read("lib/demo/engine.rb")
      expect(engine).to include('require "demo/concerns/migratable"', "include Demo::Concerns::Migratable")
      expect(engine.index("isolate_namespace")).to be < engine.index("include Demo::Concerns::Migratable")
      expect(Dir).to exist("db/migrate")
      expect(ruby_syntax_ok?("lib/demo/concerns/migratable.rb")).to be(true)
    end
  end

  it "is idempotent" do
    in_engine do
      run_generator(described_class)
      before = snapshot
      out = run_generator(described_class)

      expect(out).to include("Already up to date")
      expect(snapshot).to eq(before)
      expect(File.read("lib/demo/engine.rb").scan("include Demo::Concerns::Migratable").size).to eq(1)
    end
  end

  it "records itself in .active_engine.yml" do
    in_engine do
      run_generator(described_class)

      expect(YAML.safe_load_file(".active_engine.yml")).to include("migratable" => { "installed" => true })
    end
  end

  it "fails clearly outside an engine" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        expect { run_generator(described_class) }.to raise_error(Thor::Error, /No Rails engine found/)
      end
    end
  end
end
