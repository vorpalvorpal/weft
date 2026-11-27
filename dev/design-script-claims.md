# Script claims: the static side reads `claim()` in scripts (27 Nov)

The last "Later" item of `dev/plan-weft-everywhere.md`: "A claim collector
for scripts outside a knit". Robin asked for it on 27 Nov
(`dev/decisions.md`, "Robin's rulings (2026-11-27)"). It builds on E4
(`dev/design-e4.md`), which taught the lints, `checks()` and the gate to read
the `weft()` strings of a script and, by ruling D13, nothing else. This note
lifts D13.

This note is the contract for a test-writer who does not read `R/` and an
implementer who does not edit tests. Contract items are **SC1** to **SC14**,
messages **M1** and **M2**, decisions **D1** to **D12**, tests **T1** to
**T44**. Line numbers drift, so code is named by file and function.

A **script** in this note is what rule 5.1.9 calls one: an `.R` or `.r` file
under the project root, outside the folders 5.1.8 leaves out and outside
`scripts_skip`. A **code claim** is a `claim()` call in a script's code, as
opposed to one inside the expression of a `weft()` literal, which E4 already
reads.

## 1. The problem

### A project

```
project/
  _weft.yml           draft: false
  _targets.R          library(targets); tar_option_set(packages = "weft")
                      tar_source()
                      list(tar_target(raw, read_raw("data/raw.csv")),
                           tar_target(trend, fit_trend(raw)),
                           tar_target(n_up, count_up(trend)))
  R/functions.R       count_up <- function(trend) {
                        claim(sum(trend$up), . >= 10)
                      }
                      fit_trend <- function(raw) { ... }
  analysis.R          source("R/functions.R")
                      shift <- summarise_shift(read.csv("data/shift.csv"))
                      n_down <- claim(shift$n_down, . >= 10)
  report.qmd          n_up <- tar_read(n_up)
                      "Of the sites, `r n_up` rose ..."
```

`R/functions.R` does not hold the letters `weft`: the package is attached by
`tar_option_set()` in `_targets.R`. That is the usual targets layout.

### What the author loses today

What still works is the check itself. A failed claim in a target stops the
target, and the target's error is in `tar_meta()`, which the condition log of
every chapter that reads it already records (7.4.1). A failed claim in
`analysis.R` stops the script (2.4.2). Everything weft does from the source
is lost:

1. **Deleting a claim is silent.** Removing `claim(sum(trend$up), . >= 10)`
   from `R/functions.R`, or `claim(shift$n_down, . >= 10)` from
   `analysis.R`, passes the gate with no trailer. The test
   `test-e4-gate.R` "T13 D13: removing a claim() from a script's code
   passes" pins this.
2. **The advice of 3.1.13 punishes the author.** "Check a value once, where
   it is made." In a targets project a value is made in `R/`. Moving a
   claim out of a `report.qmd` chunk into `count_up()` is the refactor
   targets itself recommends, and today it costs `Weft-Removed: 1`. After
   it the claim is gone from every weft report, so the gate reads the move
   as a deletion, and is right about what it can see.
3. **`checks()` does not list them.** A claim in `R/functions.R` is in no
   report, so an author cannot see where a value is checked.
4. **A loosened bound gives no note.** Editing `. >= 10` to `. >= 5` in
   `analysis.R` prints nothing; the same edit in a chunk prints the 6.3.7
   note.
5. **`inert-check` misses `claim(x, TRUE)`** in a script.
6. **`verify()` does not check a script claim's `decision` pointer**
   (4.5.5 reads documents only).
7. **Most `R/` files are not even opened.** A script whose bytes do not hold
   `weft` is skipped (5.1.9), so `R/functions.R` above is invisible even to
   the E4 readers.

### Why it waited

The E4 ruling (`dev/design-e4.md`, "Rulings", 1) kept D13 because counting
script claims "would make the gate guard checks that `checks()`, `changes()`
and the ledger do not show, so a failed commit would name something no other
tool lists". The bar this note has to clear is that every tool that knows
document claims knows script claims too. Note that chunk claims are not in
`changes()` or the ledger either: a claim prints nothing, so neither holds
it. The tools that know chunk claims are the gate (6.3.1), `checks()`
(3.10.1), `inert-check` (3.1.6) and `verify()`'s decisions part (4.5.5).
Those four are the bar.

## 2. How claims get collected

### The alternatives

**A. Static.** Parse each script and count every `claim()` call, as the
gate already counts chunk claims (`claim_calls()`) and as the lints already
read a script's `weft()` literals (`script_scan()`).

- Costs: small (section 8). One parse per script read, cached by blob in the
  gate (6.1.6). The byte filter that decides whether a script is opened has
  to widen from `weft` to `weft` or a `claim(` call, so more files are
  parsed.
- Limits: it cannot tell whether a claim runs (a function no target calls, a
  file nothing sources). It counts a `claim()` of the project's own, as the
  document side already does. It sees only files under the root.
- Fit: the gate runs static checks only and runs no code (6.1.4). Whatever
  the gate counts must come from the source, so the gate can use only this
  option.

**B. Dynamic.** When `claim()` runs outside a knit, it appends a record (file,
line, check, outcome, time) to a file such as `_weft/claims/<script>.jsonl`.

- The gate cannot use it (6.1.4). A record is evidence that an earlier
  version of the code ran. Counting from it would let a deleted claim count
  until the next run, and a new claim not count until one.
- File and line need a `srcref`. `Rscript` runs with `keep.source = FALSE`,
  and `source()` follows that option, so most runs give only the deparsed
  check (3.1.4), which matches a static call only by text.
- `claim()` would write into the project from inside a library function, on
  every call. A claim in a loop over 100,000 rows needs buffering and a flush
  at exit, which plain R gives no reliable hook for. Parallel workers
  (`crew`, `future`, `mirai`, `callr`) race on one file. A line run at the
  console writes a record too.
- Committed, the file churns on every run (outcomes and times), and a merge
  conflict in it has no "render again" fix, unlike the ledger (7.1.5).
  Uncommitted, there is nothing to compare across commits.
- What it buys: knowing which claims ran. That is real, but it is not what
  the gate is for.

**C. Targets-aware.** Two forms.

- **C1, dynamic per target.** Under `targets::tar_active()`, `claim()` writes
  the claims a target ran to one file per target
  (`_weft/claims/<store>/<target>.json`). One file per target removes the
  race, and since targets skips a target that is up to date, the files are
  the last build's. Costs: B's `srcref` problem; files targets does not track
  (`tar_delete()`, `tar_destroy()` and a renamed target leave orphans); a
  cloud or `crew` worker may run elsewhere and write nowhere the project
  sees. What it buys: "target `n_up` ran 1 claim, passed" in `verify()`.
- **C2, static per target.** Map each static claim to the targets that call
  its function, from `targets::tar_network(targets_only = FALSE)`, which has
  the functions of the pipeline's environment and their edges.
  `upstream_targets()` (`R/targets.R`) already runs `tar_network()` and keeps
  its edges in `.weft/targets/network.rds`. `verify()` could then note a
  claim whose function no target reaches. Costs: it runs the pipeline script,
  so it belongs in `verify()`, never the gate; it knows functions, not
  branches. What it buys: the "function that never runs" case below, for
  targets projects only.

**D. A mix.** A for everything the gate and the static reports need; C2
later, as a `verify()` note; B and C1 not at all.

**E. Not this: collecting failures at run time.** `chunk_claims: collect`
outside a knit, so that `Rscript analysis.R` reports every failed claim at
the end. Refused: 2.4.2 says a claim outside a knit stops, a target must
never store a value that failed its claim, and plain R has no end-of-run
hook. It would need a wrapper (`weft::run_script()`), which is a different
feature.

### Recommendation

**A now; C2 later and optional; B, C1 and E refused** (D1). The gate is the
reason for the feature, and only A can feed it. A also meets the bar of
section 1 exactly: the four tools that know chunk claims are all static
readers, so a static reader of scripts gives each of them script claims with
no new kind of record. `R/claim.R` does not change: `claim()` gains no I/O
and no state.

### What counts as a script

Nothing changes in which files are scripts (5.1.9, D2). In the project
above:

| File | Read | Why |
|---|---|---|
| `R/functions.R` | yes | an `.R` file under the root |
| `_targets.R` | yes | 5.1.9 leaves out `_` folders and dot-files, not `_` file names |
| `analysis.R` | yes | |
| a file `source()`d by a document or script | yes, when it is under the root and a script | nothing is followed: a script is read because it is in the listing, not because something sources it |
| `../shared/helpers.R` | no | outside the root |
| `tests/testthat/test-x.R` | no | `scripts_skip` is `[tests]` unless set |
| `renv/`, `.Rprofile`, `_targets/` (the store) | no | 5.1.8 and 5.1.9 leave them out |
| `scripts/clean.py`, `src/fit.jl` | no | later (section 5) |

Two consequences are worth stating. A script that a chunk `source()`s is
counted once, in the script; the chunk holds only `source(...)`. And the
ledger already lists such a script among the files a chapter reads (7.2.2),
so editing it makes the chapter "not re-rendered" (7.2.1): the two features
meet without being joined.

**The byte filter** (SC1, D3). Today a script is opened only when its bytes
hold `weft`. It becomes: the bytes hold `weft`, or they match
`(^|[^A-Za-z0-9_.])claim[ \t]*\(` (a `claim(` call, so `disclaimer(`,
`claims` and `claim_id` do not open a file). `weft::claim(` already holds
`weft`. The encoding rule of D14 (E4) stays tied to `weft`: a file that is
not valid UTF-8 gives the `read` finding only when its bytes hold `weft`;
one that matches only the `claim(` pattern is skipped quietly (D4). The
reason: `read` fails every commit that changes the file (6.2.1), and a
Windows-1252 council script about insurance claims is not weft's business.

### Configuration

No new key (D5). `scripts_skip` already says which scripts are read, per
settings root, and skipping a script that holds claims is already a removal
(6.3.1). `chunk_claims` does not apply: outside a knit a claim stops
(2.4.2), and a script sourced from a chunk is chunk code, where the setting
already applies (2.4.4).

Alternatives: a key `script_claims: count | ignore` (refused: `scripts_skip`
does it per file; a switch that turns counting off would itself be a removal
when flipped, so it buys nothing); an opt-in key for adoption (refused:
adoption costs nothing, because the gate reads `HEAD` with the same code, so
both sides gain the same claims and no total falls).

## 3. What the gate and the reports do with script claims

### Counting (SC4, SC5)

- Every `claim()` or `weft::claim()` (or `weft:::claim()`) call in a script's
  code counts once, at any depth: in a function body, a `tar_target()`
  command, a lambda, a pipe, a loop. That is 6.3.1's rule for chunk code,
  applied to the whole script.
- The calls are found as `claim_calls()` finds them in chunk code today:
  the symbol in call position, bare or qualified by `weft`. Not counted: a
  comment (roxygen included), a string, a raw string, `other::claim()`,
  `claim` not in call position (`f <- claim`, `lapply(x, claim)`).
- A claim inside a `weft()` literal's expression is counted as E4 counts it,
  once. The script's code parse sees the literal as a string, so it is not
  counted twice.
- The project's claims total (6.3.2) holds document claims and script
  claims together. So a claim moved from a chunk to `R/functions.R`, or
  between scripts, or with a renamed script, changes no total.
- A `level = "warn"` claim counts, as in chunk code.

### What a removal means

A removal is a fall in the project's claims total, as now (6.3.2). For
scripts that gives:

- deleting a code claim, or the script that holds it: a removal, listed with
  the script and its line in `HEAD` (6.3.4);
- adding the script, or a folder that holds it, to `scripts_skip`: a removal
  (already 6.3.1);
- a staged script that stops parsing: its claims are gone, as its `weft()`
  constructs are by E4's D12 (D8). The failure lists them under the file;
- commenting a claim out: a removal (a comment is not code).

The accepted limits of 6.3.6 hold: a removal and an unrelated addition in one
project net out.

### `eval: false`, `if (FALSE)`, and functions that never run

**There is no `eval: false` in a script.** A script is code; it has no
chunk options. A script that knitr's `spin()` or Quarto renders as a
document (`#+ eval = FALSE`, `#| eval: false` comment lines) is still read as
a script, and those lines are comments (D9). Weft does not treat a `.R` file
as a document (5.1.8).

**A claim under `if (FALSE)`.** `if (FALSE) { ... }` is the script spelling
of `eval: false`: the usual way to switch code off without deleting it. Two
choices:

- Count it, as chunk code is counted today, and as E4's C5 reads a `weft()`
  call inside `if (FALSE)`. Then wrapping a claim in `if (FALSE)` switches it
  off with no trailer, the one thing 6.3 exists to stop.
- Do not count a claim in the body of an `if` whose condition is the literal
  `FALSE` (parentheses around the whole condition removed; not `F`, not `0`,
  not `FALSE && x`), in scripts and in R chunk code alike. Then wrapping is a
  removal, as turning `eval` off is. It is not a check for `checks()`
  either, and its `decision` is not collected, as in an `eval: false` chunk.
  The `else` arm of `if (FALSE)` is live and counts.

The second is recommended (D6, "For Robin" 2). It is not at odds with E4's
C5: both err towards telling the author. A lint that reads dead code finds
more; a count that skips dead code charges for switching a check off. The
change touches documents, but no commit fails because of it: both sides are
read with the new code, so a claim already under `if (FALSE)` leaves both
totals.

**A claim in a function that never runs** counts. The gate cannot know that
`count_up()` is never called, and the same is true of a function defined in
a chunk today. `checks()` lists the claim. C2 (later) can note it for a
targets project. Accepted limit (D7).

### `checks()` (SC7)

- A code claim is a check of role `claim` (3.10.1), with `file` the script
  and `line` the call's first line.
- It is read by 3.10.2 to 3.10.7. A claim at a script's top level
  (`n_down <- claim(shift$n_down, . >= 10)`) is readable: `n_down >= 10`. A
  claim anywhere inside a function definition is not readable, as 3.10.6
  already says ("its names are the function's"), and is listed under
  "not read" by its text. Most claims in `R/` are of this kind; they are
  listed and counted, and compared only by text.
- `always` follows 3.10.9: false under an R `if`, `for`, `while` or
  `repeat`. A function body is not a condition, as in chunk code.
- Rebinding (3.10.8) counts the script's top-level assignments as executed R
  code. Each script is its own file for groups, flags and `repeated`.
- A script that holds code claims and no `weft()` literal is now read, so it
  appears in the report and in the heading's count of files.

### The gate's notes on checks gone (6.3.7)

Scripts take part as documents do. A check's key is gone when the project
holds fewer of it, so a claim moved between files is not gone. A gone row in
a script gets a verdict judged within that script. Editing `. >= 10` to
`. >= 5` at the top level of `analysis.R` gives `looser` and, on a passing
run, the 6.3.7 note. The same edit inside `count_up()` gives `unread`, which
prints nothing on a pass.

### `verify()` (SC9, SC10)

- `lints`: script claims join the constructs removed since `since`, listed
  and failing nothing (8.2.2). An `inert-check` finding on a script claim is
  a tier-1 finding, judged against the comparison commit like any other, and
  counted in the tolerated totals (8.1.2).
- `decisions`: the literal `decision` pointers of code claims in the scripts
  verified are checked as a document's are (4.5.5): `file` the script, `key`
  `claim()`. A computed pointer is not checked. With `files` given, only the
  scripts named.
- `render` and `ledger`: unchanged. `verify()` runs no script and no
  pipeline.

### `inert-check` (SC8)

It reads code claims, with the finding at the check (`TRUE` in
`claim(x, TRUE)`) and `context` `"script"`. Findings in a script's `weft()`
literals keep the context `"weft"`. No other rule reads a script's code: the
rules that read chunk code (`tar-name`, `dict-assign`, `above-setup` and the
rest) are not script rules (5.1.9), and `inert-check` is the only script rule
that reads code pieces of every kind. This is a change to 5.1.9's "and
nothing else" (D10, "For Robin" 6).

### The ledger and `changes()` (SC11)

- **No ledger rows.** The ledger records what a knit prints (7.1.1). A claim
  prints nothing, in a chunk or a script, and nothing in a script is knit.
  There is no context `script` in the ledger, and no new ledger kind.
- **Findings** gain the context value `"script"` (above). Construct rows and
  `checks()` rows have no context column and gain none.
- **`changes()` is unchanged.** It reports printed values and conditions; it
  does not list chunk claims either. Two things already reach it: a target
  that fails its claim is an error in `tar_meta()`, which is a new condition
  in the log of each chapter that reads the target (7.4.1, 7.4.4); and a
  tier-2 finding on lines added to a script (7.3.5). The alternative, a
  "checks gone" section in `changes()` built from `gate_judge_checks()`, is
  "For Robin" 4.

## 4. How this fits the existing static readers

No new walker. Each piece below reuses a reader that already exists; the
names are the functions to change.

| Where | Today | Change |
|---|---|---|
| `R/lint-source.R` `bytes_mention_weft()` | `weft` in the bytes | becomes `script_may_hold_weft(bytes)`: `weft`, or the `claim(` pattern of section 2 (SC1). Used by `lint_open()` (`R/lint.R`) and `gate_script_read()` (`R/gate.R`), the two callers today |
| `R/lint-source.R` `script_scan()` | status `skip` when the parse holds no `weft()` literal | `ok` when it holds a literal or a `claim` call that `claim_calls()` would count; returns the parse data it made, so the claim reader does not parse again (SC2). A text that is not UTF-8 is `invalid` only when the bytes hold `weft`, else `skip` (SC3) |
| `R/lint-source.R` `script_stub()` | the `noparse` note names `weft()` strings | the note names both (M1) |
| `R/lint-source.R` `read_script_source()` | no code region | keeps `sc$pd` on the source (`src$code_pd`) for `construct_rows()` |
| `R/constructs.R` `claim_calls()` | finds calls in code | takes an optional `pd`; drops a call under `if (FALSE)` (SC6, if ruled) |
| `R/constructs.R` `construct_rows()` | rows, then chunks | a script branch: `claim_calls(src$lines, pd = src$code_pd)` gives `claim` rows, `bad = FALSE` (SC4) |
| `R/constructs.R` `decision_pointer_rows()` | rows, then R chunks | a script branch with `claim_decisions(src$lines)` (SC10) |
| `R/lint-code.R` `code_pieces()` | value, span and chunk pieces | for a script read in full, one more piece: kind `"script"`, context `"script"`, the whole text, offset 1 (SC7) |
| `R/checks.R` `checks_read()` | `chunk` pieces feed `assigned` and have no row | the same for `script` pieces; the `if (FALSE)` rule as for `claim_calls()` |
| `R/lint-code.R` `lint_inert_check()` | reads every piece | unchanged: the script piece reaches it (SC8) |
| `R/verify.R` `verify()` | `verify_document_pointers(root, docs)` | `c(docs, scripts)` (SC10) |

Notes on the table:

- **`chunk_code_regions()` is not used for scripts.** It finds chunks in a
  document's lines. A script is one region, which `code_pieces()` already
  builds the way it builds a chunk piece (`mk()` with the line offsets), so
  no region code is needed. The script piece is a new kind, not a fake chunk,
  so that the chunk-reading lints (`lc_pieces(src, "chunk")`) and
  `lint_tar_cache()` never see script code. A fake chunk row in
  `src$chunks` was considered and refused (D11): every chunk reader would
  start reading scripts, which 5.1.9 refuses.
- **The `if (FALSE)` test is one function over parse data**,
  `pd_dead_if(pd, id)`: true when an ancestor of node `id` is an `if` whose
  condition, with whole-enclosing parentheses removed, is the constant
  `FALSE`, and `id` is inside the expression after the condition's `)`, not
  the one after `else`. It reads only the `id`, `parent`, `token` and `text`
  columns, which both tree forms keep (`pd_index()` in
  `R/scan-contexts.R` and `pd_tree()` in `R/lint-code.R`), so
  `claim_calls()` and `checks_read()` call the same function. It sits beside
  `pd_parent()`. Comments between `)` and the body are skipped by token, not
  by position, because `pd_tree()` drops them.
- **Parses.** A script read in full is parsed twice: once in
  `script_scan()` (kept, and reused by `claim_calls()`), once by `pd_tree()`
  in `code_pieces()`, whose form differs. That matches a chunk today. In the
  gate both are cached by blob (6.1.6).
- **The gate's cache** needs no new key: every key carries the identity of
  the installed weft code, so the first run after the upgrade is cold and
  both sides are read with the new rules.

## 5. Python and Julia scripts: later

Later (D12, "For Robin" 3). The reasons:

- **No tool reads a `.py` or `.jl` file today.** E4 made `.R` files a kind
  of source; these would be a third and fourth, with their own listing,
  `scripts_skip` matching, cache entries and `files` validation
  (`resolve_files()` accepts `.qmd`, `.Rmd` and `.R` only).
- **Python environments are not dot-folders.** `venv/`, `env/` and conda
  prefixes inside a project are common. weft's own Python module, installed
  into `venv/lib/.../site-packages/weft/`, holds `claim(` and `weft`, so the
  byte filter would open it and count its docstrings. The listing would need
  a skip list for environments first.
- **The reader is a pattern.** `guest_claim_calls()` (N59) knows no
  function, string or `if False`, so a claim in a docstring counts.
- **Robin's projects are R first.** No Python or Julia script project is
  waiting on this.

Sketch, for when it is built:

- A guest script is a `.py` file whose bytes hold `weft`, or a `.jl` file
  whose bytes hold `Weft`, under the root, outside 5.1.8's folders, a new
  fixed list (`venv`, `env`, `site-packages`, `__pycache__`, `.pixi`,
  `.tox`) and `scripts_skip`.
- Its claims are found by `guest_claim_calls(code, engine)`, as in a guest
  chunk, and counted in the project's claims total.
- In `checks()` they are claims of level `unknown`, never readable, by text
  (as guest chunk claims are, 3.10.1).
- No lint reads them, and their `weft_str()` literals are not read.
- A parse would replace the pattern only if a pure-R tokenizer for Python
  strings and comments proves cheap; a Python subprocess in the gate is not
  acceptable (6.1.4, and the gate needs no Python).

## 6. Rules

New section **3.11**, and edits to 3.10.1, 4.5.5, 5.1.9 and 6.3.1. The
bracketed rule depends on "For Robin" 2.

### 3.11 Claims in scripts

**3.11.1** A `claim()` in a script (5.1.9) is read from the source. Every
call of `claim`, `weft::claim` or `weft:::claim` in the script's code is a
*script claim*, wherever it sits: in a function body, a target's command, a
lambda, a pipe or a loop. Not script claims: a call in a comment or a string;
`claim` qualified by another package; `claim` not in call position; a claim
inside the expression of a `weft()` literal, which is read as 3.6.7 says.
[A claim in the body of an `if` whose condition is the constant `FALSE`,
parentheses that enclose the whole condition removed, is not a script claim
and not a check; the `else` arm is read. The same holds in R chunk code
(6.3.1).]

**3.11.2** Nothing changes when a script claim runs. Outside a knit it stops,
or warns at level `warn`; in a running target it stops; in a script that a
chunk `source()`s it is chunk code, and `chunk_claims` applies (2.4.2,
2.4.4). A claim that runs records nothing and writes nothing.

**3.11.3** The gate counts each script claim as a `claim()` call of the
project that holds the script, in the same total as the claims of its
documents (6.3.1, 6.3.2). So moving a claim between a chunk and a script, or
between scripts, removes nothing.

**3.11.4** `checks()` lists each script claim as a check of role `claim`
(3.10.1), read by 3.10.2 to 3.10.9 with the script as the file. A claim inside
a function definition is not readable (3.10.6).

**3.11.5** `inert-check` (3.1.6) reads script claims. A finding's context is
`script`. No other rule reads a script's code (5.1.9).

**3.11.6** `verify()` checks the literal `decision` pointer of a script claim
as it checks a document's (4.5.5).

**3.11.7** A script is opened when its bytes hold `weft` or a `claim(` call:
the letters `claim`, after a character that is not a letter, digit, `_` or
`.` (or at the start), then optional spaces or tabs, then `(`. A script that
is not valid UTF-8 gives the `read` finding only when its bytes hold `weft`;
otherwise it is not read and nothing is said. A script that does not parse
is not read: its claims are gone, as its `weft()` strings are, and
`lints()` and `checks()` say so in a note (M1).

**3.11.8** Not read: claims in Python and Julia files; claims in files
outside the project root or left out by `scripts_skip`; chunk options
written in a script's comments (`#+`, `#|`); whether a claim's function is
ever called. Script claims have no ledger entries (7.1.1), and `changes()`
does not list them.

### Edits to existing rules

**3.10.1**, the second bullet, last sentence becomes: "Claims are found where
the gate counts them (6.3.1): in executed R chunks, inline values, governor
expressions and scripts (3.11)."

**4.5.5**, after "except in a chunk that is statically not evaluated
(1.8.12)": "and every script claim (3.11.1) of the scripts verified, with
`file` the script."

**5.1.9**, two sentences change. "A script whose bytes do not hold `weft` is
not read, whatever its encoding" becomes "A script is opened as 3.11.7
says". "In a script the lints read the literal strings passed to `weft()`, as
3.6.7 says, and nothing else: not the code around them, its `claim()` calls
or its phrases (5.1.6)" becomes "In a script the lints read the literal
strings passed to `weft()`, as 3.6.7 says, and `inert-check` reads its
claims (3.11.5); nothing else is read: not the rest of its code, or its
phrases (5.1.6)."

**6.3.1**, "a `claim()` elsewhere in a script is not counted (5.1.9)"
becomes "and every script claim (3.11.1)". [Add after "(`eval: false`, in R
as in a guest engine)": "and except in the body of an R `if (FALSE)`
(3.11.1)".]

### Rationale (section 13, Functions)

**3.11** A claim is a check wherever it is written, and a targets project
writes its checks in `R/`, where 3.1.13 tells the author to put them. Until
weft read scripts, that advice cost a trailer and hid the check. The claims
are read from the source because the gate can use nothing else (6.1.4): a
record of claims that ran is evidence of an earlier version of the code, and
would make `claim()` write files from inside the author's loops and workers.
[A claim under `if (FALSE)` is not counted because wrapping code in
`if (FALSE)` is how a script switches it off; counted, it would be a way to
drop a check with no trailer.]

## 7. Tests

For a test-writer who does not read `R/`. The helpers exist in
`tests/testthat/`: `g_scenario()`, `g_gate()`, `g_report()` and
`g_count_reads()` in `helper-4a.R`; `lint_proj()` and `lint_fixture()` in
`helper-3.R`; `e4_one()` in `helper-e4.R`; `v4_proj()` and `v4_verify()` in
`helper-4c.R`. The gate result has `ok`, `n_removed`, `removed` (`file`,
`line`, `kind`, `text`), `added`, `errors`, `trailer` and `checks`. New tests
go in `tests/testthat/test-script-claims.R`. Tests marked [FALSE] wait on
"For Robin" 2; write them, and skip them with a reason naming this note
until the ruling.

Fixture used below, `FN`, a file `R/functions.R` that does not hold the
letters `weft`:

```r
count_up <- function(trend) {
  claim(sum(trend$up), . >= 10)
}
```

### The gate

- **T1** Removing the claim from `FN` (the function body becomes
  `sum(trend$up)`) fails: `n_removed` 1; one `removed` row, file
  `R/functions.R`, line 2, kind `claim`, text `claim(sum(trend$up), . >= 10)`.
  With the message "Edit.\n\nWeft-Removed: 1" it passes.
- **T2** As T1 with `library(weft)` added on line 1 of `FN`: the same,
  line 3. (The file is read whether or not it holds `weft`.)
- **T3** Moving the claim from an R chunk of `report.qmd` (`n <- claim(x, .
  > 1)`) into `R/a.R` (the same line) in one commit passes, `n_removed` 0.
- **T4** Moving `count_up()` from `R/functions.R` to `R/count.R` passes;
  `git mv R/functions.R R/fns.R` passes; both `n_removed` 0.
- **T5** Deleting a script with two claims: `n_removed` 2, two rows listed
  under that file, and the report holds "  R/two.R, as in HEAD".
- **T6** Adding a claim to a script passes. Deleting one claim in
  `R/a.R` and adding a different one in `R/b.R` in one commit passes,
  `n_removed` 0 (6.3.6).
- **T7** In `_targets.R`, `list(tar_target(n_up, claim(count(x), . > 0)))`;
  removing the `claim()` wrapper fails with `n_removed` 1 and file
  `_targets.R`.
- **T8** A claim in `tests/testthat/test-a.R` removed: passes, 0. With
  `scripts_skip: []` in `_weft.yml` on both sides: fails, 1.
- **T9** Adding `scripts_skip: [R]` to `_weft.yml` while `R/functions.R`
  holds two claims: `n_removed` 2.
- **T10** A staged `FN` that stops parsing (a `}` deleted): `n_removed` 1,
  the row from `R/functions.R`.
- **T11** A script with `weft("`r claim(n, . > 1)` sites")` on line 1 and
  `claim(m, . > 2)` on line 2. Removing line 2: `n_removed` 1, text
  `claim(m, . > 2)`. Removing line 1 instead: `n_removed` 2, since the
  value counts once as a value and its claim once as a call (6.3.1); the
  `removed` rows are one of kind `value` and one of kind `claim`, both on
  line 1.
- **T12** Not counted. A script holding each of these, one per line, changed
  to `x <- 1`, passes with `n_removed` 0: `# claim(x, . > 1)`;
  `#' claim(x, . > 1)`; `s <- "claim(x, . > 1)"`; `s <- r"(claim(x, . > 1))"`;
  `other::claim(x, . > 1)`; `f <- claim`; `lapply(xs, claim)`;
  `disclaimer(x)`.
- **T13** Counted. Each of these in a script, removed alone, gives
  `n_removed` 1: `weft::claim(x, . > 1)`; `weft:::claim(x, . > 1)`;
  `x |> claim(. > 1)`; `x %>% claim(. > 1)`; `f <- \(v) claim(v, . > 0)`;
  `claim(x, . > 1, level = "warn")`; `claim (x, . > 1)` (a space before the
  parenthesis); `for (i in 1:3) claim(i, . > 0)`.
- **T14** Nested projects: `sub/_weft.yml` and `sub/R/a.R` with a claim;
  removing it gives a `removed` row whose file is `sub/R/a.R`, `n_removed` 1.
- **T15** A script whose bytes are latin-1 (a `0xE9` byte in a comment),
  holding `claim(x, . > 1)` and not `weft`, changed: the gate passes with no
  `errors` row and no `read` finding. The same bytes with `weft` added in a
  comment: an `errors` row of rule `read` (regression of D14).
- **T16** Two hundred scripts holding neither `weft` nor `claim(`, one of
  them changed: `g_count_reads()` around `g_gate()` counts no read of any of
  them (only the documents, as today).
- **T17** [FALSE] Wrapping the claim of `FN` in `if (FALSE) { ... }`:
  `n_removed` 1. Wrapping a claim in an R chunk of a `.qmd` the same way:
  `n_removed` 1. Changing `if (TRUE)` to `if (FALSE)` around a claim: 1.
- **T18** [FALSE] Counted: `if (FALSE) 1 else claim(x, . > 1)`;
  `if (F) claim(x, . > 1)`; `if (0) claim(x, . > 1)`;
  `if (FALSE && y) claim(x, . > 1)`; `if (x) claim(x, . > 1)`. Not counted:
  `if ((FALSE)) claim(x, . > 1)`; `if (FALSE) # off` then `{ claim(x, . > 1) }`
  on the next line. Assert each by removing the line.
- **T19** `analysis.R` holds `n_down <- claim(shift$n_down, . >= 10)` at top
  level; edit the bound to `. >= 5`. The gate passes (`n_removed` 0) and the
  report holds "commit-msg: note: analysis.R:1 in HEAD, `n_down >= 10`, is
  gone and nothing that remains covers it (rule 6.3.7)". `res$checks` has one
  row, verdict `looser`.
- **T20** The same edit to the claim inside `count_up()` of `FN`: passes, no
  such note, `res$checks` row verdict `unread`.
- **T21** Adding `claim(x, TRUE)` to `R/a.R` fails: an `added` row of rule
  `inert-check`, file `R/a.R`. A commit that changes another line of a
  script whose `claim(x, TRUE)` is already in `HEAD` passes.

### `checks()`

- **T22** `analysis.R` as in T19: one row, `file` `analysis.R`, `line` 1,
  `role` `claim`, `level` `fail`, `cond` `n_down >= 10`, `always` TRUE.
- **T23** `FN`: one row, `cond` NA, `text` `claim(sum(trend$up), . >= 10)`;
  `print()` shows it under `  not read` for `R/functions.R`.
- **T24** `for (s in sites) claim(s, . > 0)` at top level: `always` FALSE.
  `claim(x, . > 0, level = "warn")`: `level` `warn`.
- **T25** A project whose only file is `analysis.R` as in T19 (it does not
  hold `weft`): the printed heading is "weft checks: 1 check of 1 value in 1
  document; 0 values flagged" (3.10.15 counts a script as a document, as it
  does today for a script with `weft()` literals).
- **T26** `x <- 1`, `x <- 2`, `claim(x, . > 0)` in a script: `rebound` TRUE.
- **T27** A script with a `weft()` literal whose value holds
  `[a]{if="n > 1"}` and a code `claim(m, . > 2)`: two rows, roles `guard` and
  `claim`.
- **T28** The E4 test "T14 C15/D13: a claim() in a script's code outside a
  literal is not listed by checks()" now fails; rewrite it: `R/a.R` is in
  `x$file`.
- **T29** [FALSE] `if (FALSE) claim(x, . > 0)` in a script and in an R chunk:
  no row.

### `lints()`

- **T30** `R/a.R` holding only `claim(x, TRUE)`: one finding, rule
  `inert-check`, file `R/a.R`, line 1, column of `TRUE` (10), context
  `script`, message "The check `TRUE` has no variable, so it can never fail
  (rule 3.1.6)."
- **T31** `claim(x, 1 > 0)`: an `inert-check` finding. `claim(x, . > 0)`,
  `claim(x, interactive())`, `claim(x, y > 0)`: none.
- **T32** A script holding `claim(x, . > 0)`, `y <- tar_read(fit)`,
  `dict$k <- 3` and `lookup(n, "one", "two")` at tier 1:2 gives no finding of
  any rule (no rule but `inert-check` reads script code).
- **T33** `lints()` on a project with `FN` and one document counts 2 files
  read.
- **T34** A script holding `claim(` and not `weft` that does not parse:
  `lints()` and `checks()` give the note M1 ("`R/a.R` does not parse as R,
  so its weft() strings and claim() calls were not read."). Update the two
  E4 tests that match the old text (`test-e4-scripts.R` "does not parse",
  `test-e4-review.R` "does not parse"): the first matches the full text.
- **T35** The E4 test "T6 C16: a claim() in a script's code, outside a
  literal, is read by no rule" still passes (`claim(n, . > 10)` is not
  inert). Rename it "a claim() in a script's code that is not inert gives no
  finding".

### `verify()`

- **T36** `verify(static = TRUE)`, with a decision resolver set up as the
  existing 4.5.5 tests set one up: a script claim with `decision = "99"`
  that does not resolve fails the `decisions` part, naming the script and
  line, key `claim()`. `decision = d` (computed): not checked.
  [FALSE] under `if (FALSE)`: not checked.
- **T37** `verify(static = TRUE, files = "R/a.R")` checks the pointers of
  `R/a.R` only; a bad pointer in `R/b.R` is not reported.
- **T38** `verify(static = TRUE, since = <the previous commit>)` after a
  commit that removed a script claim (with its trailer): the result lists
  the removal and the `lints` part does not fail on it.
- **T39** A script with `claim(x, TRUE)` in the baseline: `verify()` passes
  its `lints` part and reports the tolerated `inert-check` total.

### Runtime and the reports that do not change

- **T40** `source()` of a script with a passing claim leaves the project's
  file listing (recursive, hidden files included) as it was: no `_weft/` and
  no `.weft/` appears. A failing claim stops with class `weft_claim_failed`,
  and the listing is again unchanged.
- **T41** `changes()` in a repository whose working tree adds a claim to
  `R/a.R` (nothing rendered): the printed result is the same as with the
  line not added. (A tier-2 finding on an added line is still listed when
  there is one; use a line with none.)
- **T42** `arms("R/a.R")` on a script with only code claims lists no arms
  and no errors (regression).
- **T43** Every existing chunk-claim test of the gate (`test-gate-constructs.R`,
  `test-gate-guest-claim.R`) passes unchanged.
- **T44** Performance: `g_gate()` on a project with 50 scripts of 200 lines,
  each holding 5 code claims, one changed, finishes within the bound
  `test-gate-perf.R` uses for documents of that size, and a second run reads
  no script (`g_count_reads()` gives 0 for scripts: the cache serves them).
  Skipped where `test-gate-perf.R` skips.

### Existing tests that change

- `test-e4-gate.R` "T13 D13: removing a claim() from a script's code passes":
  now fails with `n_removed` 1 (T1 covers it; delete or rewrite).
- `test-e4-scripts.R` "T14 C15/D13 ... is not listed by checks()": T28.
- `test-e4-scripts.R` and `test-e4-review.R`, the "does not parse" notes:
  T34.
- `test-e4-scripts.R` "T6 C16 ... read by no rule": rename only (T35).

## 8. Size, files and stages

### Size

About 120 to 160 lines of R, no new exported function, no new setting, no
change to `claim()`. About 44 tests, 450 to 550 lines. About 70 lines of spec.
One working day of build, one review.

### Files touched

- `R/lint-source.R`: `script_may_hold_weft()` (renamed from
  `bytes_mention_weft()`), `script_scan()`, `script_stub()`,
  `read_script_source()`.
- `R/lint.R`: `lint_open()` calls the renamed filter.
- `R/gate.R`: `gate_script_read()` calls the renamed filter.
- `R/constructs.R`: `claim_calls()` (`pd` argument, `if (FALSE)`),
  `construct_rows()` and `decision_pointer_rows()` (script branches).
- `R/scan-contexts.R`: `pd_dead_if()` beside `pd_parent()`.
- `R/lint-code.R`: `code_pieces()` (the script piece).
- `R/checks.R`: `checks_read()` (script pieces; `if (FALSE)`).
- `R/verify.R`: `verify()` passes scripts to `verify_document_pointers()`.
- Roxygen: `checks()`, `gate()`, `lints()` (scripts' claims); `man/`
  regenerated.
- Tests: `tests/testthat/test-script-claims.R` (new); the four E4 tests above.
- Spec: `dev/PACKAGE-SCOPING.md` 3.10.1, 3.11 (new), 4.5.5, 5.1.9, 6.3.1,
  section 13.
- Docs: `vignettes/gate.Rmd` (what is counted; a short "Scripts" paragraph),
  `vignettes/targets.Rmd` (claims in `R/` count, and are checked once where
  the value is made), `vignettes/lints.Rmd` (`inert-check` in scripts),
  `inst/agent/references/reports.md` if it lists what the gate counts,
  `NEWS.md`.
- `dev/decisions.md`: the rulings, under a new dated heading.
- `dev/plan-weft-everywhere.md`: the "Later" item marked built.

### Stages

1. **S1, this package.** SC1 to SC5 and SC7 to SC14: the filter, the
   reader, the count, `checks()`, `inert-check`, decision pointers. The cycle
   of `dev/current-state.md`: test-writer (T1 to T16, T19 to T28, T30 to
   T44), implementer, whole suite, review, spec and docs. One R process at a
   time.
2. **S1b, with S1 if Robin agrees to "For Robin" 2.** SC6, the `if (FALSE)`
   rule, in its own commit because it touches documents: T17, T18, T29 and
   the bracketed parts of T36 and section 6.
3. **Later, optional: C2.** A `verify()` note for a script claim whose
   function no target reaches, from `tar_network(targets_only = FALSE)`, with
   the function edges kept beside the target edges in
   `.weft/targets/network.rds`. A spike first: confirm that the network holds
   function-to-function edges for functions loaded by `tar_source()`.
4. **Later: Python and Julia scripts** (section 5).
5. **Later, small: a target's name as the claim's value.** In
   `tar_target(n_up, claim(count(x), . > 0))`, bind `.` to `n_up` (as 3.10.6
   binds an assigned name), so `checks()` reads `n_up > 0`. Not now: the
   gain is display only, since coverage is within one file.

## Contract summary

- **SC1** The byte filter of 3.11.7, in `lint_open()` and the gate.
- **SC2** `script_scan()`: `ok` for a literal or a counted claim call.
- **SC3** Encoding: `read` only with `weft` in the bytes.
- **SC4** The gate counts script claims (6.3.1, 3.11.3).
- **SC5** One claims total per project, documents and scripts.
- **SC6** [FALSE] `if (FALSE)` bodies are not counted, read or collected.
- **SC7** `checks()` lists script claims (3.11.4).
- **SC8** `inert-check` reads them, context `script`.
- **SC9** `verify()`'s `lints` part lists their removal and fails nothing.
- **SC10** `verify()`'s `decisions` part checks their literal pointers.
- **SC11** No ledger entries; `changes()` unchanged.
- **SC12** `claim()` unchanged; nothing is written at run time.
- **SC13** No new setting; `scripts_skip` decides.
- **SC14** No `.py` or `.jl` file is read.

## Messages

- **M1** `lints()` and `checks()` note for a script that does not parse:
  "`%s` does not parse as R, so its weft() strings and claim() calls were
  not read." (was "... so its weft() strings were not read.")
- **M2** Only if "For Robin" 5 is accepted: a gate note, once per file,
  printed with the failure when a staged script does not parse and its
  constructs count as removed: "commit-msg: note: %s does not parse as R, so
  its constructs and claims count as removed (rule 3.11.7)."

## Decisions

- **D1 Static only, now.** Alternatives: dynamic run records (B), per-target
  records (C1), a static target map (C2), runtime collection (E). Only a
  static reader can feed the gate (6.1.4); B and C1 put I/O and races into
  `claim()` and give records the gate cannot trust; C2 is useful and later.
- **D2 The script set is 5.1.9's.** Alternatives: follow `source()` calls
  from documents (would need the walker of 7.2.2 in the gate, and misses
  `tar_source()`); add `R/` only (arbitrary). The listing already holds every
  `.R` file worth reading.
- **D3 Open on `weft` or a `claim(` call.** Alternatives: `weft` only (misses
  the usual `R/` file); `claim` anywhere (opens every file about insurance
  claims); parse every `.R` file (cost on large projects, and more
  `noparse` notes). The pattern is the cheapest filter that loses no call.
- **D4 `read` stays tied to `weft`.** Alternative: any opened file. A file
  that is not UTF-8 and only matches `claim(` is most likely not weft's, and
  `read` fails every commit that touches it.
- **D5 No new setting.** See section 2, "Configuration".
- **D6 `if (FALSE)` bodies are not counted** (pending "For Robin" 2).
  Alternatives: count them (today's chunk rule; a silent off switch); treat
  any constant-false condition (`F`, `0`, `FALSE && x`) as dead (`F` can be
  rebound, and the rest is not an idiom).
- **D7 A claim in a function that never runs counts.** Alternative: count
  only claims a static call graph reaches (no such graph in the gate; C2 is
  the later, `verify()`-only form).
- **D8 A script that does not parse loses its claims**, as E4's D12 loses its
  `weft()` constructs. Alternative: count its claims by `claim_calls()`'s
  pattern fallback, as an unparsable chunk's are. Refused: one file would
  then follow two rules, and the failure that lists the file's claims is a
  useful alarm. See "For Robin" 5 for naming the cause.
- **D9 Spin and Quarto script options are comments.** Alternative: read
  `#+ eval = FALSE` and `#| eval: false`. Refused: weft does not treat `.R`
  files as documents, and reading options for one rule would make it half
  of one.
- **D10 `inert-check` reads script claims.** Alternative: keep 5.1.9's
  "nothing else" and read no script code in the lints. Refused: the defect
  is the same in a script, and the rule is about weft's own function, not a
  general R lint, which was 5.1.9's reason.
- **D11 The script is a new piece kind, not a fake chunk.** Alternative: one
  row in `src$chunks` covering the script (fewer edits). Refused: every
  chunk reader would then read scripts.
- **D12 Python and Julia later.** See section 5.

## For Robin

1. **Static reading only, now; no records of claims that ran.** The gate can
   use nothing else (6.1.4), and the static reader is what gives
   `checks()`, `inert-check` and `verify()` the same claims. Run records
   (dynamic, or per target) would put file writes and races into `claim()`,
   and still could not decide a commit. *Recommendation:* static now; a
   `verify()` note for claims no target reaches (C2) as a later, optional
   package; no run records.
2. **A claim under `if (FALSE)` is not counted**, in scripts and in R chunk
   code alike, so that wrapping a claim in `if (FALSE)` is a removal, as
   turning `eval` off is. This changes how documents are counted, but no
   commit fails because of it. *Recommendation:* yes, as S1b.
3. **Python and Julia scripts later.** Environments inside a project are not
   dot-folders, so weft's own installed Python module would be counted; no
   tool reads `.py` or `.jl` files yet. *Recommendation:* later, as its own
   small package, with the sketch of section 5.
4. **`changes()` stays as it is.** It does not list chunk claims either; the
   gate and `verify(since = )` list claims removed, and a target that fails
   its claim already shows as a new condition. The alternative is a "checks
   gone" section in `changes()`, built from the gate's comparison.
   *Recommendation:* unchanged.
5. **A script that stops parsing loses its claims** (D8, as E4's D12). Now
   that most `R/` files are read, a commit with a syntax error in
   `R/functions.R` will fail, listing its claims as removed. Should the gate
   say why (M2)? E4's D12 says the gate adds no note. *Recommendation:* keep
   D8, and add M2: one line naming the file that does not parse saves the
   author a puzzle.
6. **`inert-check` reads script claims** (D10), which amends 5.1.9's "and
   nothing else". *Recommendation:* yes.

## Rulings (27 Nov 2026, orchestrator, under Robin's delegation of design decisions)

All six "For Robin" items are taken as recommended:

1. Static reading only (route A); C2 (a `verify()` note for claims in functions no target
   calls) stays optional and later; B, C1 and E are refused. Reason: the gate runs no code
   (6.1.4), and every tool that knows chunk claims is a static reader.
2. A claim in the body of `if (FALSE)` (the literal, parentheses removed) does not count, in
   scripts and in R chunks alike, as a separate commit (S1b). Reason: otherwise wrapping a claim
   in `if (FALSE)` switches it off with no trailer, which 6.3 exists to stop; no commit fails
   because both sides are read with the new code.
3. Python and Julia scripts later, as sketched in section 5.
4. `changes()` unchanged.
5. A script that stops parsing loses its claims, with the new gate note M2 naming the file
   (amends E4's D12 "the gate adds no note").
6. `inert-check` reads script claims (amends 5.1.9's "and nothing else").
