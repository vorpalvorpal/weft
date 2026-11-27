# Quarto project, folder, include and Jupyter metadata (27 Nov 2026)

How Quarto merges document metadata from project files, folder files, included files and
notebooks, found by experiment; how weft reads it today; and the rules P1 to P9 weft follows.
Companion to the in-document block rules F1 to F6 (spec 2.1.6; `dev/decisions.md`).

Quarto 1.11.9, bundled Pandoc 3.10, macOS. Line numbers are of `/Applications/quarto/bin/quarto.js`.
Each case was run with `quarto inspect` (Quarto's merged view, the one it acts on and hands the knit
through `QUARTO_EXECUTE_INFO`) and `quarto render --lua-filter dump.lua` (Pandoc's `doc.meta`). R never
ran: `QUARTO_R` pointed at a stand-in that only logs, and no case wrote the log. The case folders and
scripts were in the session scratchpad (`quarto-project-front/`) and are not kept.

## Source of truth (code)

- `resolveFormats` (125124-125200): three layers, `projMetadata` (`_quarto.yml` with profiles and the
  local file merged in), `directoryMetadata`, `inputMetadata` (the document: `readYamlFromMarkdown` of
  the include-expanded text, all blocks, per top-level key). Each is resolved per format, then
  `mergeFormatMetadata(proj, dir, input)` (29839): the later layer wins.
- `mergeConfigs` (28825, 29872) is lodash `mergeWith`, a deep merge of maps, with
  `mergeArrayCustomizer` (28835): arrays concatenated, duplicates dropped, a scalar on one side wrapped
  into a list. Exceptions: `tbl-colwidths` replaced, `variant` merged as a Pandoc variant,
  `code-links`/`other-links` can be disabled with `false`.
- `directoryMetadataForInputFile` (83875-83909) walks `relative(projectDir, inputDir).split("/")`,
  joining each part before reading, so the project root's `_metadata.yml` is read only for a document
  in the root. In each folder the first of `_metadata.yml`, `_metadata.yaml` is read, never both. Deeper
  folder wins.
- Profiles (`initializeProfileConfig` 35995, `mergeProfiles` 36063-36093): from `QUARTO_PROFILE` (set by
  `--profile`), else `.env`, else `profile: default` in `_quarto.yml.local`, else in `_quarto.yml`.
  `_quarto-<name>.yml|.yaml` merged in reverse order, so the first named wins; then
  `_quarto.yml.local` over all of them.
- `metadata-files` (29687-29716): deep-merged over the config that names them.
- Engine (`fileExecutionEngine` 84444-84477, `markdownExecutionEngine` 84340-84382): `.ipynb` and
  percent `.py` are Jupyter by extension. For `.qmd`/`.md` only the first block of the include-expanded
  text is consulted (with `-M`): `jupyter:`, `knitr:`, `markdown:`, `execute: engine:` or `engine:`. No
  project or folder metadata. After that, the languages of the chunks.

## Findings

| # | Case | What Quarto does |
|---|---|---|
| A1 | keys set in doc / `sub/_metadata.yml` / root `_metadata.yml` / `_quarto.yml`; doc in `sub/` | doc wins, then `sub/_metadata.yml`, then `_quarto.yml`. The root `_metadata.yml` is NOT read for a document in a subfolder. |
| A2 | doc in the root, root `_metadata.yml` | read, over `_quarto.yml` |
| A3 | doc in `s1/s2/s3/`, `_metadata` in `s1` and `s1/s2/s3` (`.yaml`) | every folder below the root down to the doc's is read, nearest wins; `.yaml` works |
| A4 | `_metadata.yml` beside a lone `.qmd`, no `_quarto.yml` | read: the document's folder is the project dir |
| A5 | `_metadata.yml` above the project | not read |
| A6 | `-M a:CLI` | highest |
| B1 | nested map and list in `weft:` and a top-level list, in project, folder and doc | deep merge across files; lists concatenated project, folder, doc, duplicates dropped |
| B2 | project `weft {a:1}`; doc block 1 `weft {c:3}`, block 2 `weft {e:5}` | views disagree: inspect `{a:1, e:5}` (blocks per top-level key, then deep over project); `doc.meta` `{e:5}` |
| B3 | doc `weft: ~`, a scalar over a project map; doc scalar over project list | `~` and a scalar replace a map; a scalar against a list is wrapped and concatenated |
| B4 | doc `weft: false`; doc `l: []` over project `l: [q]` | `false` replaces; an empty list cannot clear an inherited list |
| B5, B6 | `format: html: {weft:..., a:...}` in project or doc | format-scoped keys merge deeply with top-level keys; the layer order still holds |
| F1, F2 | one file sets `a: TOP` and `format: html: a: FMT` | within one file the format-scoped value wins |
| C1, C2 | `metadata-files:` in project or doc | merged deeply over the naming file; for a doc, inspect and `doc.meta` disagree |
| D1-D4, D7 | profiles by flag, env and `profile: default`; two profiles | profile over `_quarto.yml`, under `_metadata.yml`; the first named wins |
| D5 | `_quarto.yml.local` (and the wrong name `_quarto.local.yml`) | `.yml.local` merges over all; the other is ignored |
| D6 | `_metadata-p1.yml` | ignored |
| E1-E6 | `engine:`, `knitr:`, `execute: engine:` in `_quarto.yml` or `_metadata.yml`, with a `{python}` chunk | never picks the engine |
| E7, E9 | `engine:` in the doc; project `engines:` | the doc's first block picks; `engines:` only registers and orders |
| E8 | `execute: echo: false` in `_metadata.yml` | applied: only the engine choice ignores project files |
| I1 | doc includes a file with front matter | merged as a later block where the include sits, per top-level key |
| I2 | include above the includer's own front matter | the includer's block wins |
| I3 | nested includes | order of appearance after expansion |
| I4 | included file beside its own `_metadata.yml` | the included front matter applies; its folder's `_metadata.yml` does not |
| I5 | project, doc and include all set `weft:` | as B2 |
| I6 | line 1 is an include of a file that is front matter with `engine: markdown` | the included block is the first block and picks the engine |
| I7 | the same include mid-document | not the first block; engine unchanged |
| K1, K2, I8 | Jupyter-engine `.qmd`, a later block written or included | Quarto bug: inspect applies it, `doc.meta` keeps the first block's value, and the block's text is printed in the body (the notebook round trip puts a blank line after the `---`) |
| J1, J2 | `.ipynb`, front matter in the first raw or markdown cell | read, merged with the project layers |
| J3, J4 | `.ipynb`, a later raw cell with a block; a raw block that is not the first cell | all blocks count, a later one replaces per top-level key |
| J8 | `.ipynb` with `engine: markdown` | ignored: a notebook is always Jupyter |
| J5, J6 | percent `.py`, `# %% [markdown]` or `[raw]` cell of `# `-prefixed `---` YAML | read, merged, executed |
| K3, K4, J7 | `.py`: markdown cell without front matter; front-matter cell after code; only code cells | K3 valid; K4 read; J7 "is not a valid Quarto input document" |

**rmarkdown** (source read at rstudio/rmarkdown fab4515, not run): `output_format_from_yaml_front_matter`
reads `_site.yml`'s `output:` and the first of `output_yaml`, `_output.yml`, `_output.yaml`, all in the
document's folder, merged recursively, the document's `output:` last. Only output-format options: no
other key reaches `rmarkdown::metadata`, Pandoc or knitr. No folder walk, no profiles, no includes.

**Unknown, not tested:** project-level `knitr: opts_chunk:` reaching knitr (needs R); whether the knit
already sees included blocks through `knitr::current_input()` (the include-expanded `.rmarkdown`);
`--metadata-file` under rmarkdown, `_bookdown.yml`, knitr `child=` documents with blocks; book and
website project types; `_metadata.yml` and `.yaml` together (code says `.yml` only).

## weft today (27 Nov, from reading the code)

R:
- `read_front_matter` (`R/lint.R`) reads all blocks and merges per top-level key: right within a
  document. `.py` and `.ipynb` yield no blocks.
- Engine keys from the first block only (`front_block`, `R/scan-contexts.R`): right, except I6.
- `weft:` settings: defaults < `_weft.yml` < document `weft:` (`R/config.R`), for the knit and the lints.
  Nothing reads `weft:` from Quarto's project files. Rule 5.8.8's `lint_config_place`
  (`R/lint-doc.R`) reports `weft:` in `_quarto`/`_metadata` but misses profiles, `.local`,
  `metadata-files` targets and `format: <fmt>: weft:`.
- `project_meta_files` (`R/lint-doc.R`) reads the root `_metadata.yml` for subfolder documents (Quarto
  does not), reads both spellings, and knows no profiles or `.local`.
- `file_cache` takes the nearest non-NA value (right, but for the root rule); `doc_bib` takes the union
  of every block and file (right across files, over-collects within a document).
- `lang`: the lints take the document, else the root `_quarto.yml` (`R/lint-source.R`); the knit takes
  Quarto's merged metadata (`R/hooks.R`, `R/cite.R`). They disagree on a `lang` in `_metadata.yml` or a
  profile, and both put top-level `lang` over `format: html: lang`.
- `doc_execute` (`R/scan-contexts.R`) reads the document only.
- Included front matter is not read by the lints; the knit probably sees it.

Lua: `weft:` from the source text (`config.load`, `weftlib/config.lua`), defaults < `_weft.yml` < the
last block with `weft:`; the source is `quarto.doc.input_file`, not include-expanded, so included front
matter and `.ipynb`/`.py` front matter are missed. Prose keys (`lang`, `title`, ...) come from
`doc.meta`. Engine from the first block, with the I6 gap.

Python and Julia: one setting, `chunk_claims`, from the document's last `weft:` block over the nearest
`_weft.yml`; the document's front matter is read only for `.qmd`/`.md`.

## Rules (ruled 27 Nov 2026)

Two kinds of key. Quarto's own keys that weft reads (`lang`, `execute:`, `bibliography`, the engine
keys) mean what Quarto makes of them, so weft follows Quarto. `weft:` is weft's own key, with its own
project file, `_weft.yml`, which works the same under Quarto, rmarkdown, knitr, Python and Julia.

- **P1. Quarto's layers, for Quarto's keys.** Lowest to highest: `_quarto.yml`; the active
  `_quarto-<name>.yml` profiles (the first named wins); `_quarto.yml.local`; the `_metadata.yml` of each
  folder from the first folder below the root down to the document's (nearest wins; the root's own
  counts only for a document in the root); the document (all blocks, F1 to F3, includes in place, P5).
  One spelling per folder, `.yml` before `.yaml`. With no `_quarto.yml`, the document's own folder's
  `_metadata.yml` counts. Within one file, `format: html: <key>` beats `<key>` (the lints read the html
  format). Not followed: `metadata-files` (rare, and Quarto's own views disagree) and `-M` (a lint
  cannot know it).
- **P2. Across files the merge is deep; within a document it is not.** Maps merge at every depth;
  lists concatenate, project first, duplicates dropped; a scalar against a list joins it; a scalar,
  `null` or `false` replaces a map; an empty list does not clear an inherited list. A document's blocks
  combine per top-level key first (F3), then merge deeply over the files. weft models Quarto's view
  (inspect, `QUARTO_EXECUTE_INFO`) where it and `doc.meta` differ, because Quarto acts on it and the
  knit already gets it.
- **P3. `weft:` comes from `_weft.yml` and the document only.** Not from `_quarto.yml`,
  `_metadata.yml`, profiles, `.local`, `metadata-files` targets or `format: <fmt>: weft:`. Rule 5.8.8's
  lint widens to all of those, front matter included (`format: html: weft:` in a document).
- **P4. Engine keys come from the first block of the include-expanded text, never from project
  files.** An include on line 1 supplies that block (I6); one further down never does. `.ipynb` and
  `.py` are always Jupyter. Other `execute:` options come through P1's layers.
- **P5. An included file's front matter is part of the document**, its blocks at the include's position
  after full expansion (include rules I1 to I7), the later block winning per top-level key. The included
  file's folder `_metadata.yml` does not apply. Every reader (the R lints and `read_front_matter`, Lua
  `config.load`, Python and Julia) expands includes before reading blocks.
- **P6. A later block in a Jupyter-engine `.qmd`** (written or included) follows P5, which is Quarto's
  view, and the `front-matter-quarto` lint (F5) flags it: under the Jupyter engine Quarto applies the
  block but also prints its text.
- **P7. Notebooks and scripts have front matter.** In `.ipynb`, every raw or markdown cell whose source
  is a `---` block is a block, in cell order. In a percent `.py`, the same for `# %% [markdown]` and
  `# %% [raw]` cells, with the leading `# ` stripped. All readers read them.
- **P8. Under rmarkdown or plain knitr there are no layers**: weft reads `_weft.yml` and the document
  only. At knit time the renderer is known (`QUARTO_EXECUTE_INFO`). For the lints, `.qmd`, `.ipynb` and
  `.py` are Quarto's; an `.Rmd` is Quarto's when a `_quarto.yml` is found above it, else rmarkdown's.
- **P9. Profiles in the lints** are active as Quarto makes them: `QUARTO_PROFILE`, else
  `profile: default` in `_quarto.yml.local` or `_quarto.yml`.

### Reasons and alternatives

- P3, refused: read `weft:` from Quarto's merged metadata under Quarto. It would work for the knit and
  the filter, but not for lints run alone, nor for Python and Julia, and one document would get
  different settings under rmarkdown and Quarto. Because Quarto does merge these keys into `doc.meta`, a
  misplaced `weft:` would otherwise be half-applied in silence; hence the wider lint.
- P2, refused: model `doc.meta`. weft's knit already reads Quarto's view, and Quarto's options (`lang`,
  `execute`) act on that view.
- P4, alternative: a lint "the engine is chosen by an included file". Refused because P5 expands
  includes in every reader anyway, so following Quarto costs nothing more.
- P8, the `.Rmd` in a Quarto project: it can be rendered either way. Chose Quarto's layers when a
  `_quarto.yml` is above it, as `quarto render` of the project is the usual route there; the cost is a
  lint that may read a `lang` from `_metadata.yml` that the Knit button would not apply.
- P1, `metadata-files` left out: rare, and Quarto's inspect and `doc.meta` disagree on it, so there is
  no one answer to model.
