# frozen_string_literal: true

require "digest"
require "fileutils"
require "stringio"
require "tmpdir"
require "active_engine/version"
require "active_engine/config"
require "generators/active_engine/active_engine_generator"
require "generators/active_engine/migratable/migratable_generator"

RSpec.describe ActiveEngine::Config do
  let(:dir)  { Dir.mktmpdir("ae-config") }
  let(:path) { File.join(dir, ".active_engine.yml") }

  after { FileUtils.remove_entry(dir) }

  it "lists tools but not the files map" do
    config = described_class.new(path)
    config.set("namespace", "demo")
    config.set("assetable", "mode", "isolated")
    config.set("files", "lib/a.rb", "abc")

    expect(config.tools).to eq(["assetable"])
    expect(config.files).to eq("lib/a.rb" => "abc")
  end

  it "writes the files map last and sorted" do
    config = described_class.new(path)
    config.set("files", "z.rb", "1")
    config.set("files", "a.rb", "2")
    config.set("migratable", "installed", true)
    config.write

    text = File.read(path)
    expect(text.index("migratable:")).to be < text.index("files:")
    expect(text.index("a.rb")).to be < text.index("z.rb")
  end

  it "reports a change on a dry run without writing" do
    config = described_class.new(path)
    config.set("migratable", "installed", true)

    expect(config.write(dry_run: true)).to be(true)
    expect(File.exist?(path)).to be(false)
    expect(config.write).to be(true)
    expect(config.write).to be(false)
  end
end

RSpec.describe "doctor, upgrade and dry run" do
  let(:dir) { Dir.mktmpdir("ae-upgrade") }
  let(:yml) { File.join(dir, ActiveEngine::Config::FILE) }
  let(:concern)  { File.join(dir, "lib/demo/concerns/assetable.rb") }
  let(:registry) { File.join(dir, "lib/demo/assets.rb") }

  before { build_engine }
  after  { FileUtils.remove_entry(dir) }

  def build_engine
    FileUtils.mkdir_p(File.join(dir, "lib/demo"))
    FileUtils.mkdir_p(File.join(dir, "app/views/layouts/demo"))
    File.write(File.join(dir, "lib/demo/engine.rb"), <<~RUBY)
      module Demo
        class Engine < ::Rails::Engine
          isolate_namespace Demo
        end
      end
    RUBY
    File.write(File.join(dir, "lib/demo.rb"), %(require "demo/engine"\n))
    File.write(File.join(dir, "demo.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.version = "0.0.1"
        spec.summary = "demo"
      end
    RUBY
    File.write(File.join(dir, "app/views/layouts/demo/application.html.erb"),
               "<html>\n  <head>\n  </head>\n  <body><%= yield %></body>\n</html>\n")
  end

  def run_generator(klass, args)
    captured = StringIO.new
    original = [$stdout, $stderr]
    $stdout = $stderr = captured
    Dir.chdir(dir) { klass.start(args, debug: true) }
    captured.string
  ensure
    $stdout, $stderr = original
  end

  def run_hub(*args) = run_generator(ActiveEngine::Generators::ActiveEngineGenerator, args)
  def install!      = run_hub("--only", "assetable", "migratable")
  def saved_config  = ActiveEngine::Config.new(yml)
  def backups       = Dir.glob("**/*.backup*", base: dir)

  def snapshot
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir)
       .select { |f| File.file?(File.join(dir, f)) }
       .to_h { |f| [f, Digest::SHA256.file(File.join(dir, f)).hexdigest] }
  end

  def set_saved_version(version)
    File.write(yml, File.read(yml).sub(/generator_version: .*/, "generator_version: #{version}"))
  end

  describe "--dry-run" do
    it "writes nothing when given to the hub" do
      before_state = snapshot
      out = run_hub("--only", "assetable", "migratable", "--dry-run")

      expect(snapshot).to eq(before_state)
      expect(out).to include("Dry run")
    end

    it "works on a single generator too" do
      out = run_generator(ActiveEngine::Generators::MigratableGenerator, %w[--dry-run])

      expect(File.exist?(File.join(dir, "lib/demo/concerns/migratable.rb"))).to be(false)
      expect(Dir.exist?(File.join(dir, "db"))).to be(false)
      expect(File.exist?(yml)).to be(false)
      expect(out).to include("Dry run")
    end
  end

  describe "checksums" do
    it "records one for every generated file" do
      install!

      expect(saved_config.files["lib/demo/concerns/assetable.rb"]).to eq(Digest::SHA256.file(concern).hexdigest)
      expect(saved_config.files).to include("lib/demo/assets.rb", "lib/demo/concerns/migratable.rb")
    end
  end

  describe "--upgrade" do
    before { install! }

    it "is a no-op when nothing changed" do
      before_state = snapshot
      out = run_hub("--upgrade")

      expect(snapshot).to eq(before_state)
      expect(out).to include("Already up to date")
      expect(backups).to be_empty
    end

    it "backs up a file you edited and restores the generated version" do
      generated = File.read(concern)
      File.write(concern, "# my edit\n#{generated}")

      run_hub("--upgrade")

      expect(File.read(concern)).to eq(generated)
      expect(File.read("#{concern}.backup")).to start_with("# my edit")
    end

    it "overwrites without a backup when the file is exactly what an older version generated" do
      generated = File.read(registry)
      old = "# generated by an older version\n#{generated}"
      File.write(registry, old)
      config = saved_config
      config.set("files", "lib/demo/assets.rb", Digest::SHA256.hexdigest(old))
      config.write

      run_hub("--upgrade")

      expect(File.read(registry)).to eq(generated)
      expect(backups).to be_empty
    end

    it "treats a file with no recorded checksum as edited when it differs, and records checksums" do
      File.write(concern, "# my edit\n#{File.read(concern)}")
      config = saved_config
      config.delete("files")
      config.write

      run_hub("--upgrade")

      expect(backups).to eq(["lib/demo/concerns/assetable.rb.backup"])
      expect(saved_config.files).not_to be_empty
    end

    it "previews everything with --dry-run and changes nothing" do
      File.write(concern, "# my edit\n#{File.read(concern)}")
      before_state = snapshot

      out = run_hub("--upgrade", "--dry-run")

      expect(snapshot).to eq(before_state)
      expect(out).to include("Dry run")
      expect(out).to match(%r{backup\s+lib/demo/concerns/assetable\.rb\.backup})
    end

    it "limits the upgrade with --only" do
      File.write(concern, "# my edit\n")

      run_hub("--upgrade", "--only", "migratable")

      expect(File.read(concern)).to eq("# my edit\n")
    end

    it "stamps the installed version" do
      set_saved_version("0.0.0")

      run_hub("--upgrade")

      expect(saved_config.get("generator_version")).to eq(ActiveEngine::VERSION)
    end
  end

  it "refuses to upgrade when no tools are recorded" do
    expect { run_hub("--upgrade") }.to raise_error(Thor::Error, /No installed tools/)
  end

  describe "--doctor" do
    it "refuses to run without .active_engine.yml" do
      expect { run_hub("--doctor") }.to raise_error(Thor::Error, /not found/)
    end

    context "after an install" do
      before { install! }

      it "is clean on a fresh install and writes nothing" do
        before_state = snapshot
        out = run_hub("--doctor")

        expect(out).to include("0 warning(s), 0 problem(s)")
        expect(snapshot).to eq(before_state)
      end

      it "warns about an edited file without failing" do
        File.write(concern, "# my edit\n")

        out = run_hub("--doctor")

        expect(out).to match(/assetable\.rb: edited since generated/)
        expect(out).to include("1 warning(s), 0 problem(s)")
      end

      it "warns when the yml was written by an older version" do
        set_saved_version("0.0.0")

        expect(run_hub("--doctor")).to include("Generated with v0.0.0")
      end

      it "fails when a generated file is missing" do
        FileUtils.rm(registry)

        expect { run_hub("--doctor") }.to raise_error(Thor::Error, /1 problem/)
      end
    end
  end
end
