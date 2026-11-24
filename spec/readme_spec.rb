# frozen_string_literal: true

RSpec.describe "README" do
  readme = File.read(File.expand_path("../README.md", __dir__))

  ActiveEngine::Generators::ActiveEngineGenerator.available.each_key do |tool|
    it "documents the #{tool} tool" do
      expect(readme).to match(/^### #{Regexp.escape(tool)}\s*$/)
    end
  end
end
