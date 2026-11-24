# frozen_string_literal: true

require_relative "lib/active_engine/version"

Gem::Specification.new do |spec|
  spec.name        = "active_engine"
  spec.version     = ActiveEngine::VERSION
  spec.authors     = ["Your Name"]
  spec.summary     = "Toolkit and generators for Rails engines: Propshaft, importmap, Stimulus and migrations"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.files       = Dir["lib/**/*", "README.md"]
  spec.add_dependency "rails", ">= 7.1"
end
