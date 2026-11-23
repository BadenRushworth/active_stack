# frozen_string_literal: true

module ActiveEngine
  # Coloured console output shared by every generator.
  # (The trailing `true` forces a newline: Thor drops it when text ends in a space.)
  module UI
    private

    def ui_banner(title)
      bar = "═" * (title.length + 4)
      say "\n╔#{bar}╗", :cyan, true
      say "║  #{title}  ║", %i[bold cyan], true
      say "╚#{bar}╝", :cyan, true
    end

    def ui_heading(text) = say("\n── #{text}", %i[bold blue], true)
    def ui_step(text)    = say("\n▸ #{text}", %i[bold cyan], true)
    def ui_ok(text)      = say("  ✓ #{text}", :green, true)
    def ui_info(text)    = say("  • #{text}", :cyan, true)
    def ui_warn(text)    = say("  ! #{text}", :yellow, true)
    def ui_fail(text)    = say("  ✗ #{text}", :red, true)
    def ui_cmd(text)     = say("      $ #{text}", :magenta, true)
  end
end
