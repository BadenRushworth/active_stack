# frozen_string_literal: true

require "stringio"

module GeneratorHelper
  # Minimal stand-in for what `rails plugin new demo --mountable` produces.
  ENGINE_FILES = {
    "lib/demo.rb" => %(require "demo/engine"\n\nmodule Demo\nend\n),
    "lib/demo/engine.rb" => <<~RUBY,
      module Demo
        class Engine < ::Rails::Engine
          isolate_namespace Demo
        end
      end
    RUBY
    "demo.gemspec" => <<~RUBY,
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.version = "0.1.0"
        spec.add_dependency "rails", ">= 7.1"
      end
    RUBY
    "config/routes.rb" => "Demo::Engine.routes.draw do\nend\n",
    "app/views/layouts/demo/application.html.erb" => <<~ERB,
      <!DOCTYPE html>
      <html>
        <head>
          <title>Demo</title>
          <%= stylesheet_link_tag "demo/application", media: "all" %>
        </head>
        <body><%= yield %></body>
      </html>
    ERB
    "app/assets/stylesheets/demo/application.css" => "/* scaffold */\n"
  }.freeze

  LAYOUT = "app/views/layouts/demo/application.html.erb"
  CSS    = "app/assets/stylesheets/demo/application.css"

  # Yields inside a temp engine directory. Pass `path => content` to override a
  # scaffold file, or `path => nil` to leave it out.
  def in_engine(files = {})
    Dir.mktmpdir("active_engine_spec") do |dir|
      ENGINE_FILES.merge(files).compact.each do |path, content|
        full = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content)
      end
      Dir.chdir(dir) { yield dir }
    end
  end

  # Runs a generator in the current directory and returns everything it printed.
  # Thor errors are raised (THOR_DEBUG) so specs can assert on them.
  def run_generator(klass, *args)
    captured   = StringIO.new
    stdout_was = $stdout
    debug_was  = ENV["THOR_DEBUG"]
    $stdout    = captured
    ENV["THOR_DEBUG"] = "1"
    klass.start(args, destination_root: Dir.pwd)
    captured.string
  ensure
    $stdout = stdout_was
    ENV["THOR_DEBUG"] = debug_was
  end

  # { "path" => "content" } for every file under the current directory.
  def snapshot
    Dir.glob("**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h { |path| [path, File.read(path)] }
  end

  def append(path, text) = File.write(path, File.read(path) + text)

  def ruby_syntax_ok?(path) = system("ruby", "-c", path, out: File::NULL, err: File::NULL)
end
