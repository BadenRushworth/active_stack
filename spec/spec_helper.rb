# frozen_string_literal: true

# Termux keeps temp files in ~/tmp, not /tmp.
ENV["TMPDIR"] ||= File.expand_path("~/tmp")

require "fileutils"
require "tmpdir"
FileUtils.mkdir_p(ENV["TMPDIR"])

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "active_engine"
require "active_engine/config"
require "active_engine/assetable/assetable_generator"
require "active_engine/migratable/migratable_generator"
require "generators/active_engine/active_engine_generator"

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.include GeneratorHelper
  config.filter_run_excluding :integration unless ENV["INTEGRATION"]
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
end
