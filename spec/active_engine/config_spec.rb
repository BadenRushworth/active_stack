# frozen_string_literal: true

RSpec.describe ActiveEngine::Config do
  around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

  it "returns the default for missing keys" do
    expect(described_class.new.get("assetable", "mode", default: "isolated")).to eq("isolated")
  end

  it "round-trips nested values through the file" do
    config = described_class.new
    config.set("assetable", "mode", "shared")
    config.write

    expect(described_class.new.get("assetable", "mode")).to eq("shared")
  end

  it "stamps the generator version" do
    config = described_class.new
    config.set("namespace", "demo")
    config.write

    expect(described_class.new.get("generator_version")).to eq(ActiveEngine::VERSION)
  end

  it "reports a change only when the file content actually changed" do
    config = described_class.new
    config.set("assetable", "mode", "isolated")

    expect(config.write).to be(true)
    expect(described_class.new.write).to be(false)
  end

  it "deletes keys" do
    config = described_class.new
    config.set("assetable", "registry", "Core.assets")
    config.delete("assetable", "registry")

    expect(config.get("assetable", "registry")).to be_nil
  end
end
