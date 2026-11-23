# frozen_string_literal: true

require "bundler"
require "open3"

# Slow (builds a real engine, runs bundler). Opt in with:
#   INTEGRATION=1 bundle exec rspec --tag integration
RSpec.describe "a fresh mountable engine", :integration do
  gem_root = File.expand_path("../..", __dir__)
  gem_env  = { "BUNDLE_GEMFILE" => File.join(gem_root, "Gemfile") }

  # Same pins as the gem's Gemfile: Termux (Android) needs them in every engine too.
  termux_gems = ENV["PREFIX"].to_s.include?("com.termux") ? ['gem "tzinfo-data"', 'gem "nokogiri", "1.18.10"'] : []

  def sh(*command, chdir:, env: {})
    output, status = Bundler.with_unbundled_env { Open3.capture2e(env, *command, chdir: chdir) }
    raise "#{command.join(' ')} failed:\n#{output}" unless status.success?

    output
  end

  it "boots with the generated helpers and importmap" do
    Dir.mktmpdir("active_engine_int") do |dir|
      begin
        sh("bundle", "exec", "rails", "-v", chdir: dir, env: gem_env)
      rescue RuntimeError => e
        skip "Rails can't run in this environment:\n#{e.message.lines.first(6).join}"
      end

      sh("bundle", "exec", "rails", "plugin", "new", "demo_int", "--mountable", "--skip-git", "--skip-bundle",
         chdir: dir, env: gem_env)
      engine  = File.join(dir, "demo_int")
      gemfile = File.join(engine, "Gemfile")
      File.open(gemfile, "a") do |file|
        file.puts 'gem "propshaft"' unless File.read(gemfile).include?("propshaft")
        termux_gems.each { |line| file.puts line }
        file.puts %(gem "active_engine", path: "#{gem_root}", group: :development)
      end

      sh("bundle", "install", chdir: engine)
      sh("bin/rails", "g", "active_engine", "--only", "assetable", "migratable", chdir: engine)
      sh("bundle", "install", chdir: engine)

      methods = sh("bin/rails", "runner", "puts DemoInt::AssetsHelper.public_instance_methods(false).sort.inspect", chdir: engine)
      expect(methods).to include("demo_int_importmap_tags", "demo_int_stylesheet_tags")

      map = sh("bin/rails", "runner", "puts DemoInt.assets.importmap.to_json(resolver: ApplicationController.helpers)", chdir: engine)
      expect(map).to include("demo_int/application", "demo_int/controllers")
    end
  end
end
