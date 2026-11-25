# E4: the static side reads `weft()` strings, in documents and scripts (26 Nov)

Package E4 of `dev/plan-weft-everywhere.md`. It builds on E1
(`dev/design-e1.md`), whose static half (ST1 to ST5) already renames the
context `"weft_str"` to `"weft"`, reads `weft(...)` and `weft::weft(...)` in
the code of an evaluated R chunk, and matches the argument to `x` (named
`x`, else the first argument without a name). E1 ST5 leaves raw strings and
`.R` files to this package. E2 (`dev/design-e2.md`) gives a named value in a
`weft()` literal the resolver `hooks` (its ST1) and adds the
`string-markup` lint, which does not read `.R` files ("E4"; see C16). Neither
E1 nor E2 is built yet; this note is written against their notes. Line
numbers are at `4dd02de`.

This note is the contract for a test-writer who does not read `R/` and an
implementer who does not edit tests. Contract items are **C1** to **C18**,
messages **M1** to **M3**, decisions **D1** to **D17**, tests **T1** to
**T16**.

A **script** in this note is an `.R` or `.r` file of a project.

## Why

`weft()` is for plot titles, labels and console text, which are mostly
written in scripts: `R/plots.R`, `_targets.R`, helpers that chunks call. A
typed numeral in `weft("We found 12 sites")` is the defect the numeral rule
exists to catch, and today nothing reads a script. In documents too the
reader misses cases: a raw string, a string over the parser's display limit,
a pipe.

## What the code does today (checked)

| Where | What it does |
|---|---|
| `R/scan-contexts.R:650-724` (`scan_chunk_strings()`) | the scanner's rows for `weft_str()` literals in an R chunk: finds `SYMBOL_FUNCTION_CALL == "weft_str"` whatever its package; reads one `STR_CONST` or a `c()` whose arguments are *all* string constants; evaluates the token text to get the value; maps offsets only for a token that starts with `"` or `'` (`:701`), so a raw string's rows have no file offset |
| `R/lint-source.R:254-313` (`chunk_literals()`) | the lints' prose pieces for the same strings: the first `expr` after `(` whatever its name; keeps only tokens matching `^["'].*["']$` (`:306`), so a raw string is never prose and the numeral rule misses it; drops tokens shown as `[N chars quoted with '"']` (getParseData's display of a long string), so a long string is never prose either |
| `R/lint-source.R:1024` (`read_source()`) | drops `weft_str` rows in a chunk that is not R or not evaluated |
| `R/lint-source.R:1041-1046` | a row with no file offset is put at the start of its line, column 1 |
| `R/io.R:222-263` (`DOC_EXT_RE`, `DOC_VENDORED_DIRS`, `DOC_QUARTO_DIRS`, `doc_path_ok()`, `project_doc_paths()`) | the documents of a project: `.qmd`, `.Rmd`, `.rmd`; never in a dot-folder, `renv`, `packrat`, `node_modules`, `_site`, `_book`, `_freeze`, `_extensions`; `_` folders are read for anchors only |
| `R/lint.R:346` (`lint_files_under()`), `:431` (`lints()`), `:515` (`lint_run()`) | `lints()` lists documents only; `files` must end `.qmd`/`.Rmd`/`.rmd` (`:476`); every file-scope rule runs on every reported document; project-scope rules read `ctx$files` |
| `R/gate-git.R:9` (`GATE_CONTENT_RE`), `:120` (`is_doc_path()`) | the gate's content files and documents; an `.R` file is neither, so `gate_materialise()` (`R/gate.R:227`) writes it as an empty file |
| `R/gate.R:150-178` (`gate_side_keys()`) | a document's cache key: its blob, the config blobs, the blobs of the other content files, the paths |
| `R/constructs.R:71-120` (`construct_rows()`) | the gate's counts: the scanner rows (values, spans; `claim()` inside an expression) and `claim()` calls in the code of each evaluated chunk (`src$chunks`) |
| `R/constructs.R:20-47` (`claim_calls()`) | already checks the package of `claim()`: `weft::claim` or none |
| `R/arms.R:76-84` (`arms_one()`) | `scan_file()`, which reads any file as a document: `arms("x.R")` scans R code as markdown |
| `R/scan-contexts.R:498-560` (`scan_chunk_captions()`) | a caption option written `!expr ...` is a region of form `expr` and is scanned as markup; a construct there is the error "must be in a YAML block scalar" (`:635-637`), which the knit also reports (`R/position.R:194-198`) |
| `R/changes.R`, `R/lint-doc.R:1384` (`changes_tier2()`), `R/verify.R:64,294`, `R/checks.R:731` | list the project's documents through `lint_files_under()` |

The last row of the first table bears on E1: `#| fig-cap: !expr
weft::weft("Depth at [a site | # sites]{n='k'}")`, which E1 WS16 makes
legal and E1 T8 renders, is a construct error to the scanner today, and the
knit reports scanner errors in captions. E1's implementer will meet it in
T8's Quarto case; C10 is the fix, and may be pulled into E1.

R's parser counts a tab as reaching the next multiple of 8 in the columns
of `getParseData()` (`xxcolno` in `gram.y`). This is from memory of R's
source and was not run for this note (no R process was free); T5 pins the
behaviour either way.

## The contract

### Which scripts are read

**C1** The scripts of a project are the `.R` and `.r` files under its root
(the root `lints()` and the gate find, 5.1.8, 6.1.2), as sorted relative
paths with `/`, less:

- those the documents' rule leaves out: in a folder whose name starts with
  `.`; in `renv`, `packrat` or `node_modules`; in `_site`, `_book`,
  `_freeze` or `_extensions`; in any folder whose name starts with `_` (so
  `_targets/` is not read); a file whose name starts with `.`;
- those `scripts_skip` names (C2).

`_targets.R` and `R/_helpers.R` are read (a file starting with `_` is, as
for documents). Git's ignore rules are not consulted (D4).

**C2** The setting `scripts_skip` is a project setting (9.1.4: an error in a
document's front matter where `_weft.yml` exists, and the `config-place`
lint finds it). Its value is a list of strings; the default is
`[tests]`. An entry with no `/` is a name: a script is skipped when that
name is one of the folders on its path or its file name. An entry with a `/`
is a path from the folder of the script's own settings root (the nearest
`_weft.yml`, the project root when none lies below; K4), a leading `./` and
a trailing `/` dropped: the script at that path, or every script under that
folder. No globs: an entry with `*`, `?`, a leading `/` or a backslash is
M1 (K11). A null value (`scripts_skip:` with nothing after it, `~`) is the
default `[tests]` (K5). Giving the setting replaces the default: `scripts_skip: [scratch]`
reads `tests/`. `scripts_skip: []` reads every script. A value that is not a
list of non-empty strings (or one string, read as a list of one) is a
`weft_config_error`, M1.

**C3** A script whose bytes do not contain `weft` (ASCII, case as written)
gives nothing: no rows, no findings, no constructs, whatever its encoding.
A script that contains it is read as a source is read (`read_source_text()`:
UTF-8, a BOM dropped, CRLF and CR to LF). One that holds a NUL byte or is
not valid UTF-8 gives the `read` finding (5.1.3: "`R/x.R` is not valid
UTF-8; save the file as UTF-8 (rule 5.1.3).", line 1, column 1) and nothing
else.

**C4** A readable script is parsed as R (`parse(keep.source = TRUE)`). When
it does not parse it gives no rows and no findings, and `lints()` adds the
note M2. The gate adds no note (D12).

### How a call is found (scripts and R chunks alike)

**C5** A `weft()` call is a function call whose function is the symbol
`weft`, written alone or after `weft::` or `weft:::`. A call qualified by
another package (`other::weft(...)`) is not read. `weft` not in call
position (`lapply(x, weft)`, `f <- weft`) is not read. A call anywhere in
the code is read: inside a function body, an `if (FALSE)` block, a `local()`.
A comment is not code (`# weft("...")` is not read, nor a roxygen
`#' @examples` line).

**C6** The argument read is the one R matches to `x`: the argument named
exactly `x`; else the first argument without a name (E1 ST2). On the right
of `|>` or `%>%` the left-hand side is `x` unless an argument is named `x`
(K3): `"a" |> weft(e)` is `weft("a", e)`. The placeholder puts the
left-hand side where it stands: `x = _` of the native pipe, and `.` as an
argument of `%>%` (`weft(., e)`); an argument that is a placeholder and
not the one matched to `x` takes the left-hand side away from `x`. A
magrittr pipe into `weft` with no parentheses (`"a" %>% weft`) is read
too. The function position is exactly the symbol `weft` or `weft::weft` /
`weft:::weft` (K2): `obj$weft(...)` and `x@weft(...)` are not calls
(5.1.4: a pipe is read as the call it makes).

**C7** What is read in the argument:

- a string literal, in any form R accepts: `"..."`, `'...'`, and a raw
  string `r"(...)"`, `R"(...)"`, with `'` or `"`, with `(` `)`, `[` `]` or
  `{` `}`, and with any number of dashes (`r"---(...)---"`);
- a call to `c()` (alone or `base::c`) given directly as the argument: each
  of its arguments that is a string literal is read, named or not; any
  other argument of the `c()` is skipped and the literal ones are still
  read.

Anything else (a name, `paste0()`, `sprintf()`, `glue()`, a `c()` nested in
a `c()`, `NA_character_`) is skipped without a finding or a note (D5). Each
literal read is one element of `x`: one block of prose (E1 WS1).

**C8** A literal's value is the string R gives (escapes decoded as R
decodes them; a raw string as written). Its full token text is taken with
`utils::getParseText()`, so a literal longer than `getParseData()`'s display
limit (shown there as `[N chars quoted with '"']`) is read in full. The
value is scanned as a `weft()` string is today (E1 ST1): one block of prose,
with the project's settings, context `"weft"`, and for a named value the
resolver `hooks` (E2 ST1).

**C9** The scanner's rows and the lints' prose pieces come from one reader
of calls and literals, so a string the construct rule reads is a string the
numeral rule reads, and the reverse. In a document this reader replaces
today's two (`scan_chunk_strings()` and `chunk_literals(which =
"weft_str")`); it reads R chunks that run, as E1 ST1 says.

**C10** R code in a chunk option. A caption option (`fig-cap`, `fig-subcap`,
`fig-alt`, `tbl-cap`, and the rmarkdown spellings in a chunk header, as
2.3 lists them) whose value is R code (`#| fig-cap: !expr ...` written as a
plain YAML scalar or a block scalar, or a header option `fig.cap = ...` that
is not a string literal) is not scanned as markup. Its code is read by C5 to
C8 for `weft()` calls, the rows taking context `"weft"`, the chunk's label
and the option's name, at their positions on the option's line. A
`weft()` literal there is not a caption construct error (1.10.3, 1.10.4).
A `!expr` value written as a quoted YAML scalar (`!expr "weft('...')"`) is
not read (YAML's own unescaping stands between the text and the code). A
caption option that is a markup string is scanned as now.

### Positions

**C11** Every row and finding from a literal has the position of the source
character that holds the value's character: `line` and `col` (1-based,
`col` in characters, a tab one character, as every other finding),
`end_line` likewise. An escape (`\"`, `\n`, `²`) maps to its
backslash. A raw string maps directly. A literal over several lines maps
across them (its second line's characters have that line's numbers). A
character that cannot be mapped (none is expected) takes the position of
the literal's first character (its opening quote, or the `r` of a raw
string), never column 1 of the line.

In a document these are the document's lines (inside the chunk, or on the
option's line for C10). In a script they are the script's.

### Scripts in the lints

**C12** `lints()` reads scripts as well as documents. `path` may be a
script, or a folder; the scripts reported on are those under it (C1). The
argument `files` takes scripts as well as documents. Project-scope rules
(5.4.1, 5.4.3, 5.7.1, 5.7.2, 5.8.8, 5.8.9) read documents only, as now, and
never report a script. A script is read with its project's settings
(`_weft.yml` of the innermost project holding it; a script has no front
matter); `lang` is English.

**C13** The file-scope rules that run on a script are listed in a new
column of `lint_rules()`, `scripts` (logical): `TRUE` for `numeral`,
`construct`, `read`, `block-start`, `lone-bar`, `if-zero`, `name`,
`inert-check`, `long-guard`, `claim-word`, `literal-value`,
`value-constant` and `value-format`; `FALSE` for every other rule. They read
only the rows and prose of the script's `weft()` literals: the code around
them is not read by any rule (C16).

**C14** A finding in a script has `file` the script's path (relative to the
root, with `/`), `context` `"weft"`, and the position of C11. Its text,
message and hint are those the rule gives in a document's `weft()` string.

### arms(), checks(), changes(), verify()

**C15**

- `arms(file)` takes scripts: a file whose name ends `.R` or `.r` is read
  as a script (C3 to C11), with the settings of the project root found from
  it and English plural rules; its rows have context `"weft"`. A script that
  does not parse lists no spans and no errors. `arms()` does not apply
  `scripts_skip`: a file named is read.
- `checks()` reads the guards and the `claim()` calls inside values of the
  `weft()` literals of every script of C1, with the script as their file.
- `changes()` lists the tier-2 findings (5.1.5) over the lines added to
  scripts as to documents.
- `verify()` reads scripts through `lints()` and counts their tier-1
  findings as it counts a document's (8.1.1, 8.1.2); `verify(files = )`
  takes scripts as `lints()` does.
- `rehearse()` is unchanged: it takes documents. A span of a script that a
  rehearsal evaluates is not one of the document's arms and is not matched
  (D16).

### The gate

**C16** What is not read in a script: `claim()` calls in its code outside a
`weft()` literal (D13); the phrases of `lookup()` and `brk()` (5.1.6 stands:
"phrases ... in a package's R code are not read"); strings given to any
other function, so E2's `string-markup` rule does not read scripts; `weft()`
called from inline R in a document's prose (`` `r weft("...")` ``), in
documents as in scripts.

**C17** The gate (§6) treats a script as it treats a document:

- the files it reads are the documents, the scripts and the project files
  (6.1.2); a script is content, materialised with its staged bytes;
- a construct error (`construct`, `block-start`, `read`) in a changed
  script fails the commit (6.2.1, item 1);
- the tier-1 findings of scripts are counted with the project's by rule and
  text (6.2.2, 6.2.3), so a typed numeral added to a script's `weft()`
  string fails as one added to a document's;
- the constructs of a script's `weft()` literals are counted: values and
  spans, and `claim()` inside a value's or governor's expression (6.3.1);
  deleting a script, or skipping it with `scripts_skip`, removes them;
- the removal list (6.3.4) names a script as it names a document, with its
  lines in `HEAD`;
- a script in `scripts_skip` on a side gives no findings and no constructs
  on that side; which scripts are skipped is read from that side's
  `_weft.yml`;
- cache keys keep their form (6.1.6): a script is keyed as a document is,
  so a change to `_weft.yml` (and so to `scripts_skip`) is a new key.

**C18** The ledger (§7) is unchanged. A `weft()` call evaluated during a
knit records its constructs with the knitted document as `file`, the
section it is in, and context `"weft"` (E1 WS15), wherever the call is
written; no script path is recorded (D15).

### Messages

| Id | Text |
|---|---|
| M1 | `` The setting `scripts_skip` must be a list of folder or file names, or paths from the project root (rule 9.1.4). `` (`weft_config_error`) |
| M2 | `` `{path}` does not parse as R, so its weft() strings were not read. `` (a note of `lints()`) |
| M3 | `` `files` must name existing .qmd, .Rmd or .R files under the project root; not so: {list} (rule 5.1.1). `` (`weft_lint_error`, replacing today's text at `R/lint.R:476-480`; the first check, "`files` must be paths to .qmd or .Rmd documents.", becomes "`files` must be paths to .qmd, .Rmd or .R files.") |

## Decisions

**D1 A script is a second kind of source, not a pseudo-document.** A script
source has the script's text, lines and line starts, the rows of its
`weft()` literals, a prose mask that is the literals' pieces, and no chunks,
metadata or blocks. Rules opt in (D11). Alternatives:

- *Wrap the script as a document with one R chunk.* Rejected: every chunk
  and document rule (`chunk-label`, `above-setup`, `figure`, `tar-name`,
  `tar-cache`, `named-unpublished`, the code rules) would read the whole
  script and need an exemption each; and `construct_rows()` would count
  every `claim()` in it (D13).
- *Read a script's strings into each document that `source()`s it.*
  Rejected: finding `source()` statically is unreliable (paths built in
  code, `tar_source()`, `sys.source()`), a script may be sourced by many
  documents or none, and a finding belongs where the text is written.

**D2 Every script under the root, less fixed and configured exclusions.**
Alternatives: only `R/` and `_targets.R` (misses `scripts/`, `analysis/`);
only scripts a document sources (D1); an opt-in list (a project that forgets
it is silently unread). A byte search for `weft` makes the unread case cost
one read per file.

**D3 `tests` skipped by default, through the setting.** A test file holds
deliberate typed numerals and broken markup, and removing a test would cost
a `Weft-Removed` trailer. Alternatives: a fixed exclusion (a project that
wants its tests read could not); no exclusion. The setting replaces its
default, as `strict` and `verify_skip` replace theirs; the documentation
says to keep `tests` in a list that is given.

**D4 Git's ignore rules are not consulted.** `lints()` reads ignored
documents today (5.1.8), and the gate reads only what is staged, so an
ignored script never reaches it. Honouring `.gitignore` for scripts alone
would make `lints()` and the gate disagree in a new way and needs git in
`lints()`, which runs without it. `scripts_skip` is the project's own list.

**D5 A computed argument is skipped silently.** Alternatives: a tier-2 rule
(`weft-computed`) or a note per call. Refused: `weft(sprintf(tpl, site))`
and `weft(paste0("*", species, "*"))` are the vectorised use E1 WS1 is
for, and a typed numeral there is in the template literal, which a rule on
`sprintf()` would have to read (later, if a case appears). The numeral rule
judges text an author typed into the call.

**D6 The literal elements of a `c()` are read even beside other elements.**
Today all or none. Each element is its own block of prose (WS1), so `c(a =
"One 12", b)` holds author-typed prose in its first element whatever `b`
is. Alternative: keep all-or-none; it misses that prose for no reason.

**D7 A pipe's left-hand side is the argument.** Rule 5.1.4 already reads a
pipe as the call it makes; `"..." |> weft()` is a natural way to write a
title in a pipeline.

**D8 The package qualifier is checked.** `other::weft()` is another
package's function, and `claim_calls()` already checks its qualifier.
Today's readers take any `weft_str` call; with a short name like `weft` a
false reading is likelier.

**D9 Positions through escapes and raw strings; the fallback is the
literal, not the line.** `lit_offsets()` already maps escapes; raw strings
need only their opening length (`r`, quote, dashes, bracket). Today's
fallback, column 1 of the line, points at the wrong place on a line such as
`p <- labs(title = weft(...))`. Columns are characters with a tab as one, as
every finding is placed; `getParseData()`'s columns are converted.

**D10 The context in a script is `"weft"`.** A new context (`"script"`)
was considered: the file's extension already says where the string is, the
gate keys findings by rule and text only (6.2.3), and a new value would
ripple through `dl_ctx()`, `lint-prose.R`, `position.R` and `rehearse.R`
for nothing a reader needs.

**D11 Rules opt in to scripts by a column of the rule table.** Alternative:
run every file rule and let an empty structure give nothing. Rejected:
`above-setup` would judge every construct as above a `weft_setup()` chunk
that does not exist, `file-link` would resolve paths against a script's
folder, and the citation rules would judge keys against no bibliography (a
`[@key]` in a plot title prints as typed, D14 of E1). An explicit list is
auditable, and `lint_rules()` shows it. The list is the rules that read only
rows and prose.

**D12 A script that does not parse: a note, not a finding.** Alternatives:
a `construct` finding (it would fail the gate on any work-in-progress
script that mentions `weft`, about R syntax weft does not own); silence (the
author loses the checks without knowing). In the gate the constructs of such
a script are gone, so a change that breaks its syntax lists them as removed
(6.3.4), which names the file.

**D13 `claim()` in a script's code is not counted.** The plan scopes E4 to
`weft()` literals, and runtime claims in scripts are a later item ("a claim
collector for scripts outside a knit"). Counting them would make the gate
the only part of weft that knows them (`checks()`, `changes()` and the
ledger would not), and would charge a trailer for edits to helpers. A
`claim()` inside a `weft()` literal's value is counted, as in a document.
See "For the orchestrator", question 1.

**D14 Only scripts that mention `weft` are judged for encoding.** A
council script saved in Windows-1252 that never calls weft is not weft's
business; one that does cannot be read reliably, and the `read` finding says
so, as for a document.

**D15 The ledger keeps the document as `file`.** E1 D10 left source
references to E4. Kept out: `srcref` exists only with `keep.source`
(never under `Rscript` by default), so the key would change with how R was
started, and the ledger's bytes are committed and compared (7.1). The
static side places a script's constructs; the runtime places their
evaluation in the document that ran them.

**D16 `rehearse()` takes documents only.** A rehearsal knits; a script's
spans evaluated by it are reported by the knit's ledger rows under the
document, not matched to `arms()` of the script. Matching them would need
D15's source references.

**D17 Computed captions are read as code (C10).** E1 WS16 makes `!expr
weft(...)` a caption; without C10 the scanner reads that R code as markup,
calls its spans construct errors, and the knit fails. Reading it as code
gives the numeral rule the literal, as for a chunk. Quoted YAML scalars are
left out to avoid a second unescaping layer in the offset map.

## Tests

The test-writer works from this note, E1's ST items and the existing helpers
`lint_proj()` (`tests/testthat/helper-3.R:55`, a temporary project from a
named list of files), `f3_write()` (same file), `g_scenario()` and `g_gate()`
(`tests/testthat/helper-4a.R:95,142`, a git repository and the gate run on
it). R source written into fixtures is given as a character vector of lines;
mind R's own escaping when writing `\"` into a line.

A fixture used below, `R/plot.R`:

```r
library(ggplot2)
p <- labs(title = weft("We found 12 sites"))
```

Line 2, the `1` of `12` is column 34.

### New tests (`test-scripts.R`, `test-lint-weft-literals.R`, `test-gate-scripts.R`)

- **T1 a script is read** (C1, C12, C14): `root <- lint_proj(list("R/plot.R"
  = <fixture>), weft_yml = "draft: false")`; `f <- lints(root)` has one row
  with `file` `"R/plot.R"`, `line` 2, `col` 34, `rule` `"numeral"`,
  `context` `"weft"`, `text` `"12"`. `lints(file.path(root, "R/plot.R"))`
  gives the same row; `lints(root, files = "R/plot.R")` too.
- **T2 which scripts** (C1, C2), the same line `weft("We found 12 sites")`
  written in each of these, under a `_weft.yml` of `draft: false`:
  `analysis.R`, `x.r`, `_targets.R`, `R/_helpers.R`, `scripts/deep/a.R` are
  reported; `renv/a.R`, `packrat/a.R`, `node_modules/a.R`, `.hidden/a.R`,
  `_site/a.R`, `_freeze/a.R`, `_targets/a.R`, `_extensions/a.R`,
  `tests/testthat/test-a.R`, `tests/a.R` are not. Then with `scripts_skip:
  [scratch, R/old.R]` in `_weft.yml`: `tests/a.R` is reported,
  `scratch/a.R`, `R/scratch/b.R` and `R/old.R` are not, `old.R` (at the
  root) is; with `scripts_skip: []` every script of the first list that is
  outside the fixed exclusions is reported.
- **T3 the setting** (C2, M1): `scripts_skip: 3` and `scripts_skip: [""]`
  make `lints()` raise a `weft_config_error` whose message is M1; a
  document whose front matter sets `weft: {scripts_skip: [x]}` in a project
  with `_weft.yml` gives a `config-place` finding.
- **T4 calls found** (C5, C6, C7): each line below is the whole of
  `R/a.R`; the table says which numerals `lints()` reports (by `text`):

  | Line | Reported |
  |---|---|
  | `weft::weft("Saw 12")` | `12` |
  | `weft:::weft("Saw 12")` | `12` |
  | `other::weft("Saw 12")` | none |
  | `weft(x = "Saw 12")` | `12` |
  | `weft(.envir = e, x = "Saw 12")` | `12` |
  | `weft(.envir = e, "Saw 12")` | `12` |
  | `weft("Saw 12", .envir = e)` | `12` |
  | `"Saw 12" \|> weft()` | `12` (column 6) |
  | `"Saw 12" %>% weft()` | `12` |
  | `weft(c("One 12", "Two 13"))` | `12`, `13` |
  | `weft(c(a = "One 12", b, "Two 13"))` | `12` (column 17), `13` (column 30) |
  | `weft(c(c("One 12")))` | none |
  | `weft(paste0("Saw ", "12"))` | none |
  | `weft(title)` | none |
  | `lapply(c("Saw 12"), weft)` | none |
  | `f <- function() weft("Saw 12")` | `12` |
  | `if (FALSE) weft("Saw 12")` | `12` |
  | `# weft("Saw 12")` | none |
  | `weft_str("Saw 12")` | none |
  | `lookup(k, c(low = "below 12"))` | none (5.1.6) |

  None of these gives a note.
- **T5 positions** (C8, C11), each the whole of `R/a.R`, the numeral `12`
  expected at (line, col):

  | Lines | (line, col) |
  |---|---|
  | `p <- labs(title = weft("We found 12 sites"))` | (1, 34) |
  | a tab, then `w <- weft("n 12")` | (1, 15) |
  | `weft("a \"q\" 12")` (backslashes in the file) | (1, 15) |
  | `weft(r"(a "q" 12)")` | (1, 15) |
  | `weft(R"--[x 12]--")` | (1, 13) |
  | `weft(r'{x 12}')` | (1, 11) |
  | `t <- weft("first line` / `then 12 sites")` (two lines) | (2, 6) |
  | `x <- weft("` + 1200 × `a` + ` 12")` | (1, 1213) |
  | `weft("caf` + backslash + `u00e9 12")`: the six-character escape written in the file, not the letter | (1, 17) |
  | `weft("café 12")` with the letter itself (UTF-8) | (1, 12) |

  And a construct error's position: `weft("ok [x]{if='a >'}")` gives a
  `construct` finding at line 1, column 10 (the `[`).
- **T6 rules on scripts** (C13): `lint_rules()` has a logical column
  `scripts`, `TRUE` exactly for the thirteen ids of C13. A script with
  `weft("[x]{if='5 > 3'}")` gives an `inert-check` finding; one with
  `` weft("`r 12`{.num}") `` gives `literal-value` (`lints(root, tier =
  1)`); one with `weft("See @fig-missing and [@nokey]")` gives no `xref`,
  `cite-key` or `citation-key` finding; a script with a `weft()` literal and
  no `weft_setup()` anywhere gives no `above-setup` finding; a script with
  `claim(n, . > 10)` outside any literal gives no `inert-check` finding for
  it and nothing else.
- **T7 encodings and parse failures** (C3, C4, M2): a script written as
  Latin-1 bytes holding `weft("caf\xe9 12")` gives exactly one finding,
  `read`, with the message of C3; a Latin-1 script with no `weft` in it
  gives nothing; a script with a NUL byte and `weft` gives `read`; a CRLF
  script reports its numeral at the same line and column as the LF one; a
  script `weft("Saw 12"` (unclosed) gives no finding, and
  `attr(lints(root), "notes")` contains M2 with `{path}` `R/a.R`.
- **T8 files argument** (M3): `lints(root, files = "R/a.py")` (an existing
  file) and `lints(root, files = "R/missing.R")` are `weft_lint_error`s
  with M3's text; `lints(root, files = c("doc.qmd", "R/a.R"))` reports both.
- **T9 project rules ignore scripts** (C12): a project with `doc.qmd`
  holding a `@fig-a` cross-reference to nothing and `R/a.R` holding
  `weft("@fig-b")`: the `xref` findings name `doc.qmd` only.
- **T10 documents** (C7 to C9, C11), on `.qmd` fixtures with an R chunk:
  a raw string `weft(r"(We found 12 sites)")` in a chunk gives a `numeral`
  finding at its exact line and column (today none); a 1200-character
  literal likewise; `"Saw 12" |> weft()` likewise; `other::weft("Saw 12")`
  gives none; `weft(c(a = "One 12", b))` gives `12`; the scanner reads the
  same strings: `arms()` of a document whose chunk holds
  `weft(r"([one | # sites]{n='k'})")` lists the span with context
  `"weft"`.
- **T11 computed captions** (C10): a `.qmd` with an R chunk whose options
  are `#| label: fig-a` and `#| fig-cap: !expr weft('Depth at [a site | #
  sites]{n="k"}')` gives no `construct` finding; with `#| fig-cap: !expr
  weft('We saw 12 sites')` a `numeral` finding at that option's line, column
  32, context `"weft"`; an `.Rmd` whose chunk header is
  ```` ```{r fig-a, fig.cap = weft('We saw 12 sites')} ```` gives a
  `numeral` finding at the header's line, column 37; `#| fig-cap: !expr
  "weft('We saw 12 sites')"` gives none; a caption written as a markup string
  (`#| fig-cap: "Depth at [a site | # sites]{n='k'}"`) gives its 1.10.3
  error as now.
- **T12 arms()** (C15): `arms(file.path(root, "R/a.R"))` for a script with
  `weft("[one site | # sites]{n='k'}")` on line 3 has two rows, `context`
  `"weft"`, `line` 3, `key` `"n"`, `expr` `"k"`, roles `"one"` and
  `"other"`; for a script that does not parse it has no rows and no
  errors; `arms()` of `tests/a.R` (skipped by default for the lints) lists
  its spans.
- **T13 the gate** (C17), each with `g_scenario()` and `g_gate()`:
  - before `R/plot.R` holding `` weft("Found `r k`{.num} sites") ``, after
    `weft("Found 12 sites")`: the gate fails, listing a `numeral` finding
    added in `R/plot.R` and 1 construct removed, with the trailer
    `Weft-Removed: 1`; with that trailer it fails on the numeral only;
  - a new script `R/new.R` holding `weft("ok [x]{if='a >'}")`: the gate
    fails with a construct error naming `R/new.R` and its line;
  - before a script with two values, after the script deleted: 2 removed,
    the list naming `R/plot.R, as in HEAD` and both lines; the trailer
    `Weft-Removed: 2` passes;
  - a script under `tests/` with `weft("We saw 12")` added: passes;
  - `R/a.R` changes from `claim(n, . > 10)` to nothing: passes (D13);
  - before `R/plot.R` with one value and `_weft.yml` `draft: false`, after
    `_weft.yml` adding `scripts_skip: [R]`: 1 removed;
  - an `.R` file with no `weft` changed: passes, and the report adds no
    note;
  - a script whose staged version does not parse, where `HEAD`'s held one
    value: 1 removed, listing the line.
- **T14 checks() and changes()** (C15): `checks(root)` for a script with
  `weft("[ok]{if='n_sites > 3'}")` lists that guard with `file`
  `"R/a.R"`; in a git project, a line added to a script holding
  `weft("[a | b]")` is listed by `changes()` with the `lone-bar` rule (use
  the existing `changes()` test set-up).
- **T15 verify()** (C15): in a project whose only tier-1 finding is a
  numeral in `R/a.R`, `verify()`'s lint part counts it as it counts one in a
  document (follow the existing `verify()` tests for the column to check).
- **T16 ledger unchanged** (C18): in an rmarkdown knit (`render_rmd(...,
  format = "knit", in_process = TRUE)`) whose setup chunk `source()`s a
  script defining `f <- function() weft("[one | # sites]{n='k'}")` and whose
  chunk `fig-a` calls `f()`, the ledger row of that span has `file` the
  document and `context` `"weft"`.

### Existing tests that change

- Tests that pin `lint_rules()`'s columns gain `scripts`.
- Tests that pin `lints()`'s `files` error text take M3's.
- Tests of `chunk_literals()` or `scan_chunk_strings()` through internal
  calls (`weft:::`), if any, move to the one reader of C9; their expectations
  for one string and `c()` of strings stand; a `c()` mixing a literal and a
  name now reads the literal (D6).
- E1 T13's expectations stand (they are a subset of T4 and T10).

## Rule edits for `dev/PACKAGE-SCOPING.md`

Against the text E1 and E2 write.

**3.6.7** (E1's) replaced: "The lints read a literal string passed to
`weft()` as prose (5.1.3), in the code of an R chunk that runs, in R code in
a caption option (`!expr weft(...)`, `fig.cap = weft(...)`), and in the
scripts of the project (5.1.9). A call is `weft(...)`, `weft::weft(...)` or
`weft:::weft(...)`, and the right-hand side of a pipe. The argument read is
the one R matches to `x` (named `x`, else the first without a name, else a
pipe's left-hand side). It is a string literal in any form R writes,
`r\"(...)\"` included, or `c()` of strings, whose literal elements are read
whatever the others are. A computed argument (`paste0()`, `sprintf()`, a
name) is not read. The context of what is found there is `weft`."

**3.7.1**, second sentence: "It takes the spans from the scanner (2.10.2),
in prose, captions, front-matter fields and literal `weft()` strings; given
an `.R` file, from the `weft()` strings of that script (5.1.9). It runs no
R."

**5.1.1**: "`lint_rules()` lists the ids, rule numbers, tiers, scopes
(`file` or `project`) and whether a rule reads scripts (5.1.9)."

**5.1.3**: "The lints read the prose of each source file, the captions
written in chunk options, the literal strings passed to `weft()` in
documents and in scripts (3.6.7, 5.1.9), and the front-matter fields of
1.10.7 ... A file that is not UTF-8 gives one finding, `read` (tier 1), and
no other; a script is judged only when it mentions `weft`."

**5.1.4**, sentence added after the pipe sentence: "A literal argument of a
`weft()` call is read wherever the call is (3.6.7); the rest of a script's
code is not read."

**5.1.7**: "`files` limits the findings reported to those documents and
scripts."

**5.1.8**, appended: "The scripts of the project (5.1.9) are listed under
the same root, with the same folders left out."

**5.1.9** (new) A script is an `.R` or `.r` file under the root, outside the
folders 5.1.8 leaves out (a dot-folder, `renv`, `packrat`, `node_modules`,
`_site`, `_book`, `_freeze`, `_extensions`, a `_` folder) and outside
`scripts_skip` (9.1.4), which is `[tests]` unless set. A script whose bytes
do not hold `weft` is not read. In a script the lints read the literal
strings passed to `weft()`, as 3.6.7 says, and nothing else: not the code
around them, its `claim()` calls or its phrases (5.1.6). The rules that read
them are `numeral`, `construct`, `read`, `block-start`, `lone-bar`,
`if-zero`, `name`, `inert-check`, `long-guard`, `claim-word`,
`literal-value`, `value-constant` and `value-format`; the project rules read
documents only. A finding is placed at the character of the script that
holds it, through escapes and raw strings. A script that does not parse as R
is not read, and `lints()` says so in a note. A script has no front matter:
its settings are its project's, and its language English.

**5.2.1**: "...the fields of 1.10.7, the strings of `weft()` in documents and
scripts, and the phrases of 5.1.6..."

**6.1.2**: "The files weft reads are the documents, the scripts (5.1.9) and
the project files the lints read (5.4.4, §5.8)."

**6.2.1**, item 1: "...in a changed document or script (one whose staged
version differs from `HEAD`), whenever it is present"

**6.3.1**, appended: "In a script it counts the values and spans of its
`weft()` strings, and a `claim()` inside one of their expressions; a
`claim()` elsewhere in a script is not counted (5.1.9). A script that
`scripts_skip` leaves out counts for nothing, so skipping one is a removal."

**7.3.5** (`changes()` tier 2): "...over the lines added to documents and
scripts..." (where the rule names documents).

**8.1.2**: the count of remaining numerals includes scripts (one clause where
the rule names documents).

**9.1.2**, the table, a row: "`scripts_skip`: the scripts the lints and the
gate do not read (project only where `_weft.yml` exists) | 5.1.9, 9.1.4".

**9.1.4**: "`draft`, `verify_skip` and `scripts_skip` are project settings."

**9.1.5**, the block, a line after `verify_skip`:
`scripts_skip: [tests]   # 5.1.9: folders and files whose .R scripts are not read`;
and in the paragraph of errors: "`scripts_skip` takes a list of names (no
`/`, matched against each folder and the file name) and paths from the root;
given, it replaces `[tests]`."

Part 2:

**5.1.9** (new) Plot titles and console text are written in scripts as
often as in chunks, and a typed numeral in a title is the same defect in
either. A script is read only for its `weft()` strings because those are
prose the author typed; the rest of a script is code that no chunk option
marks as run, and judging it would make the lints a linter of R. Tests are
skipped by default because they hold typed numbers and broken markup on
purpose. The project rules stay with documents: a plot title cannot hold an
anchor, and a citation in one prints as typed.

**6.3.1**, appended: "A script's `claim()` calls are not counted because
nothing else in weft knows them yet; counting them only in the gate would
charge a trailer for a check no report shows."

## Documentation

- `R/lint.R`: roxygen of `lints()` (`path` and `files` take scripts; a
  paragraph on scripts and `scripts_skip`), `lint_rules()` (the `scripts`
  column). `R/arms.R`: `@param file` takes `.R` files, "literal `weft()`
  strings" in the description. `devtools::document()`.
- `R/config.R` and the settings reference (`?weft_config` or wherever 9.1.5's
  block is shown to users): `scripts_skip`.
- `vignettes/lints.Rmd`: a section "Scripts" (what is read, the default
  skip, the rule list, an example finding in `R/plots.R`).
- `NEWS.md`: "`lints()`, the commit gate, `arms()`, `checks()` and
  `changes()` read the `weft()` strings of the project's `.R` scripts;
  raw strings, pipes and long strings are read in chunks too; the setting
  `scripts_skip`."
- `inst/agent/references/syntax.md` and `skills/weft`: E5.

## Order of work

1. Test-writer: T1 to T16 and the changes to existing tests. Check that T1
   to T9 and T12 to T15 fail because scripts are not read, T10 because raw
   and long strings are not read, T11 because of the caption error.
2. Implementer, the suite run after each step:
   1. The one reader of calls and literals (C5 to C9, C11), used by the
      scanner and the lints in documents (T4's document cases, T5, T10).
   2. The script listing and `scripts_skip` (C1, C2; `R/io.R`,
      `R/config.R`, `project_only_settings()`), and the script source
      (C3, C4, D1) (T2, T3, T7).
   3. `lints()`: scripts, `files`, the `scripts` column, notes (T1, T6, T8,
      T9).
   4. `arms()`, `checks()`, `changes()`, `verify()` (T12, T14, T15).
   5. The gate: content and source paths, side listing with the side's
      `scripts_skip`, constructs (T13).
   6. Computed captions (C10, T11), unless E1 has already done it.
   7. Roxygen, `document()`, vignette, `NEWS.md`.
3. Whole suite (one R process), review, then the spec editor applies the
   rule edits.

## For the orchestrator

1. **Should a `claim()` in a script's code count for the gate?** (D13.)
   This note says no: E4 is scoped to `weft()` literals and no other part of
   weft knows script claims. But a `claim()` in `R/clean.R`, called from a
   chunk, is a real check, and deleting it is exactly what 6.3 guards
   against. Counting them is cheap (`claim_calls()` exists); the cost is a
   trailer for edits to helpers, and a gate that knows checks `checks()`
   does not list. A ruling either way is a small change to C16, C17 and
   T13.
2. **`scripts_skip` defaults to `[tests]` and a given list replaces it**
   (D3). The alternative is a fixed `tests` exclusion plus an additive
   setting. Replacement matches `strict` and `verify_skip`.
3. **E1 gap, for E1's implementer now:** a computed caption `#| fig-cap:
   !expr weft::weft(...)` holding a span is a construct error to today's
   scanner, and the knit reports it (`R/scan-contexts.R:635-637`,
   `R/position.R:194-198`), so E1's T8 Quarto case should fail on it. C10
   is the fix; it can move into E1.

## Rulings (orchestrator, 2026-11-26)

1. **A `claim()` in a script's code does not count for the gate** (D13
   and C16 stand). Counting it would make the gate guard checks that
   `checks()`, `changes()` and the ledger do not show, so a failed commit
   would name something no other tool lists. It belongs with the
   claim collector for scripts, which the plan defers ("Later, not in this
   plan"); that package should count them in the gate too.
2. **`scripts_skip` defaults to `[tests]` and a given list replaces it**
   (D3 stands), as `strict` and `verify_skip` do.
3. **C10 (computed captions read as code) moves into E1.** E1's T8 Quarto
   case needs it. E4 keeps T11 as a regression test.
