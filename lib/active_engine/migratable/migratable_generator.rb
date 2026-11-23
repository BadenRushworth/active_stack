# frozen_string_literal: true

require "active_engine/shared"

module ActiveEngine
  module Generators
    class MigratableGenerator < Rails::Generators::Base
      include Shared

      source_root File.expand_path("templates", __dir__)

      desc "Appends the engine's db/migrate to the host app (no install:migrations needed)"

      def welcome
        ui_step "Migratable - #{mod}"
      end

      def copy_concern
        put "migratable.rb.tt", "lib/#{engine_path}/concerns/migratable.rb"
      end

      def include_concern
        wire_concern("Migratable")
      end

      def ensure_migrate_dir
        return unchanged! if Dir.exist?("db/migrate")

        empty_directory "db/migrate"
        create_file "db/migrate/.keep", ""
        touched!
      end

      def save_settings
        remember "migratable", installed: true
      end

      def finish
        ui_summary
        ui_info "Host apps now run this engine's migrations with plain `rails db:migrate`." if changed?
      end
    end
  end
end
