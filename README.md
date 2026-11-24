# ActiveEngine

Toolkit for Rails engines: generators that wire **Propshaft**, **importmap**, **Stimulus** and
**migrations** into an engine, with helpers, a demo page and sensible defaults.

The generators *copy* their runtime code into your engine, so engines have no runtime dependency
on this gem. It is a development tool only.

## Install

~~~ruby
# the engine's Gemfile
gem "active_engine", path: "../active_engine", group: :development
~~~

Run everything from the engine's root. The engine needs `lib/<name>/engine.rb` with an
`isolate_namespace` line (the generated concerns build initializer names from `engine_name`).

## Usage

~~~zsh
bin/rails g active_engine                      # interactive menu of all tools
bin/rails g active_engine --only assetable migratable
bin/rails g active_engine:assetable --mode shared --registry "Lifeguard.assets"
bin/rails g active_engine:migratable
bin/rails g active_engine --help               # every option
~~~

Options every tool understands:

| Option | Meaning |
|---|---|
| `--engine NAME` | Pick an engine when `lib/` has several (default: auto-detected) |
| `--namespace NS` | Namespace for JS, CSS, pins and helper names (default: engine name) |
| `-i`, `--interactive` | Prompt for choices instead of using saved/default values |
| `--force`, `-f` | Regenerate starter files too (a backup is made first) |
| `--skip` | Never overwrite a changed generated file |
| `--only a b` | (hub only) skip the menu and run these tools |

Precedence everywhere: **command-line flag > `.active_engine.yml` > built-in default**.

## How files are written

Nothing prompts. Every file falls into one of three kinds:

| Kind | Examples | Behaviour |
|---|---|---|
| Starter files you own | `application.js`, `controllers/index.js`, `config/importmap.rb` | Created once, then never touched. `--force` regenerates them (with a backup). |
| Existing stylesheet | `application.css` | Missing: created. Existing: the starter comment is inserted at the top and your CSS is kept. |
| Generated code | concerns, registry, helpers, demo files | Written when new or changed. A changed existing file is copied to `<file>.backup` first (`.backup.2`, `.backup.3` ... if one exists). |

Layouts are wired too: the scaffold's `stylesheet_link_tag "<ns>/application"` line is replaced
with the helper (the layout is backed up first), and the importmap tag is added before `</head>`.
A layout that already uses the host's `javascript_importmap_tags` is left alone with a warning,
because two import maps on one page break it.

Add `*.backup*` to your `.gitignore`: Propshaft treats every file in an asset folder as an asset.
Re-running a tool is safe: if nothing changed it prints `Already up to date`.

## .active_engine.yml

Written to the engine root after each run. Safe to commit and edit; contains names and choices only.

~~~yaml
generator_version: 0.1.0
namespace: demo
assetable:
  mode: shared
  loader: prefixed
  lazy: false
  demo: true
  registry: Lifeguard.assets
migratable:
  installed: true
~~~

`generator_version` records which gem version last ran, for a future upgrade check.

## Engines that already have their own setup

- An existing `include ...::Migratable` or `...::Assetable` in `engine.rb` is detected and kept.
  No concern is generated and `engine.rb` is not touched.
- `assetable` in isolated mode refuses to run in such an engine (a second registry would clash with
  yours). Use `--mode shared --registry 'Your.registry'` to add only the helpers, JavaScript and CSS.
- Nested engines (`lib/lifeguard/admin`, `Lifeguard::Admin`) get nested folders and names
  (`lifeguard_admin_importmap_tags`).
- A slash in `--namespace` (`lifeguard/admin`) nests folders; Stimulus identifiers and CSS
  classes use dashes (`lifeguard-admin--demo`).

## Development

~~~zsh
bundle install
bundle exec rspec                                   # fast generator specs
INTEGRATION=1 bundle exec rspec --tag integration   # builds a real engine (slow)
~~~

Specs build a throwaway engine in `TMPDIR` and run the real generators against it.

### Adding a tool

1. `lib/active_engine/<tool>/<tool>_generator.rb`: `include Shared`, add `source_root` and a
   one-line `desc "..."` (it becomes the hub's menu text).
2. A thin stub so `rails g` can find it:
   `lib/generators/active_engine/<tool>/<tool>_generator.rb` containing
   `require "active_engine/<tool>/<tool>_generator"`. The hub discovers tools from any gem on the
   load path that ships `generators/active_engine/*/*_generator.rb`.
3. Templates in `lib/active_engine/<tool>/templates/` (`.tt`, ERB with `-` trim).
4. Use the `Shared` helpers: `put` (generated code), `seed` (starter files), `seed_comment`
   (existing stylesheet), `wire_concern`, `remember` (writes `.active_engine.yml`), `ui_step`,
   `ui_summary`.
5. Add specs in `spec/generators/`.
6. Append a `### <tool>` section at the end of this README (a spec enforces it).

# Tools

Each tool below is added with `bin/rails g active_engine:<tool>`.

### assetable

Propshaft + importmap + Stimulus for an engine, with helpers and an optional demo page.

~~~zsh
bin/rails g active_engine:assetable                      # isolated: the engine owns its importmap
bin/rails g active_engine:assetable --mode shared --registry "Lifeguard.assets"
~~~

| Option | Meaning |
|---|---|
| `--mode isolated\|shared` | `isolated` (default) creates `<Mod>.assets`, the engine's own importmap. `shared` feeds an existing registry (needs `--registry`). |
| `--registry EXPR` | Ruby expression returning the shared registry, e.g. `Lifeguard.assets`. It must respond to `pin`, `draw`, `watch` and `importmap`. |
| `--loader stimulus-loading\|prefixed` | `stimulus-loading` (default for isolated) registers controllers by file name. `prefixed` (default for shared) registers `<ns>--name`, so several engines can share a page. |
| `--lazy` | stimulus-loading: lazy-load controllers instead of eager. |
| `--demo` / `--no-demo` | Install the demo controller, view, layout and assets (default: yes). |

Creates (`<ns>` is the namespace, `<engine>` the engine's lib path):

~~~
lib/<engine>/concerns/assetable.rb       initializer: asset paths, pins, helper registration
lib/<engine>/assets.rb                   the engine's importmap registry (isolated mode only)
app/helpers/<engine>/assets_helper.rb    <ns>_importmap_tags, <ns>_stylesheet_tags
config/importmap.rb                      vendor pins (turbo, stimulus, stimulus-loading)
app/javascript/<ns>/application.js       entry point
app/javascript/<ns>/controllers/         application.js (own Stimulus instance), index.js (loader)
app/assets/stylesheets/<ns>/             application.css, components/demo.css
app/controllers, app/views, config/routes.rb    demo page at <mount path>/demo
~~~

It also adds `propshaft`, `importmap-rails`, `turbo-rails` and `stimulus-rails` to the gemspec,
and their `require`s to `lib/<engine>.rb`. Run `bundle install` afterwards.

In your layout (existing layouts are wired for you):

~~~erb
<%= <ns>_stylesheet_tags media: "all" %>
<%= <ns>_importmap_tags %>
~~~

`<ns>_stylesheet_tags` lists every `.css` under `app/assets/stylesheets/<ns>*`, recursively, with
`application.css` first. Propshaft has no manifests, so adding a CSS file is all it takes.

Stimulus: put `name_controller.js` in `app/javascript/<ns>/controllers/`. Each engine has its own
Stimulus instance. With `stimulus-loading` use `data-controller="name"`; with `prefixed` use
`data-controller="<ns-dashed>--name"`. For a specific load order, edit `controllers/index.js`
(the comments in it explain how). Switching loaders later: `--loader prefixed --force`.

### migratable

Appends the engine's `db/migrate` to the host app's migration paths, so `rails db:migrate` runs
engine migrations directly. No `<engine>:install:migrations` copies to drift out of sync.

~~~zsh
bin/rails g active_engine:migratable
~~~

No options. Creates `lib/<engine>/concerns/migratable.rb`, adds `include` after `isolate_namespace`
in `engine.rb`, and makes sure `db/migrate` exists.

<!-- Add new tools below: append a "### <tool>" section (the README spec checks every tool has one). -->
