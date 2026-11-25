# Plan: weft everywhere

**Date:** 2026-11-25. **Status:** approved by Robin; package Q in design.

weft markup works in the prose of a knit document. This plan makes it work
in any string R produces: plot titles and labels, console and CLI messages,
logs, table text. The scoping is in the vault note
`54.06 weft/2026-11-19 weft-everywhere scoping.md`; the adversarial review
of the two syntax changes is summarised under "Rulings" below.

## Rulings (Robin, 2026-11-25)

1. **Quoting is loosened everywhere** (documents and strings alike). A value
   is read as a strict subset of Pandoc's reading: double-quoted,
   single-quoted or unquoted; `\"`, `\'` and `\|` are escapes in a quoted
   value; any other backslash, and a quote or backslash in an unquoted
   value, stays a construct error. The filter's condition grammar accepts
   `"..."` strings too. No normalising fixer or lint.
2. **The entry point is `weft()`**, which evaluates at the call, in the
   caller's environment, and returns an object that each sink renders.
   `weft_str()` goes: weft has no users and no compatibility obligations.
   Named arguments that publish for one string were considered and
   refused (they trade `r ` for `, age = x` and leave the quotes where
   they were).
3. **`` `x` `` reads R wherever R runs.** In `weft()` strings and in the
   prose of a knitr document, a bare name is R's `x`, with every R
   formatter (units, dictionary, project formatters), so `` `x` `` and
   `` `r x` `` agree. The filter keeps documents that are not knit, and a
   name used above its value.
4. **`weft_put()` leaves R's API.** `put()` (Python) and `@put` (Julia)
   stay: they are the only correct route for text a cell prints in a loop,
   Julia has no post-cell hook, and a hidden Jupyter cell needs a put in a
   shown cell.
5. **Later replaces.** When two sources give a name different values, the
   last one above the sentence wins, as rule 1.12.7 says now.
6. **Automatic publishing publishes only what the filter will resolve**
   (decided by the orchestrator, from the review): with one named value in
   a document, every token in an R governor was published, so
   `{if="nchar(secret) > 0"}` wrote the secret into the values block, which
   persists in `_freeze`, keep-md and `.ipynb` outputs.

## Packages

Each package runs the cycle in `dev/current-state.md`: design note (opus),
failing tests (a test-writer that never reads `R/`), code (a different
implementer that never edits tests), the whole suite, an independent
review, fixes, then spec and docs. One R process at a time, so packages run
in sequence; the next design note may be written while a package is built.

### Q. Loosened quoting

Design: `dev/design-quoting.md`. Scanner (`parse_block_strict`,
`block_errors`), every reader that bypasses it (name extractors in R and
Python, the filter's line search and `shown_attrs`, `cond.lua` and its R
mirror, two lints), escaping of the attributes weft writes, the 1.2.9
detection gaining `why`, `decision` and `label`. Rules 1.2.2, 1.2.3,
1.2.9, 1.8.8, 1.5.13, 4.4.23, 1.12.4, 1.12.6 and their rationale.

### E1. `weft()` and the plain target

- `weft(x, .envir = parent.frame())`, vectorised over a character vector.
  Every inline R value, governor, claim and bare name is evaluated at the
  call. The result is an object of class `weft` holding the resolved
  pieces, not text.
- Rendering per target: `markdown` and `tex` (today's), and a new `plain`
  (Unicode text: `1.2 × 10⁻⁴`, `m³`, no emphasis markers). The formatters'
  markdown emitters (emphasis, `.sci`, unit exponents, lists, pass-through
  spans, the failure marker) become target-aware; `fmt_*()` accept
  `target = "plain"`, so they can serve as scale labels.
- Methods: `as.character()` and `format()` give plain text, `print()`
  prints it, `knitr::knit_print()` gives markdown in a knit, and captions
  and `results: asis` text resolve through the same engine. ggplot2 keeps
  the object as a label and draws its plain text.
- Failures: in a knit with weft active, collected and marked as in prose;
  elsewhere the first stops, with today's classes.
- Speed: the configuration is cached per project root, found upward from
  the working directory, and re-read when `_weft.yml` changes; no state is
  rebuilt per call.
- Python's `weft_str()` stays in the Python module, calling `weft()` and
  returning markdown.

### E2. Bare names read R

- In the prose of a knitr document the hooks resolve `` `x`{.num} `` from
  R's environment, as `` `r x`{.num} ``; in `weft()` strings the caller's
  environment.
- A name not bound where it stands (used above its value, or a Python
  value under knitr) is left to the filter, as now, and published at the
  end for it. Automatic publishing becomes internal transport, limited by
  ruling 6.
- `weft_put()` is removed from R's API; `weft_values_write()` stays for
  pipelines. A setting names the namespace a document's bare names read
  (default: the engine's language).
- Rules 1.12.x, 2.13.x and 3.8.x, the named-values article.

### E3. Console and ANSI

- An `ansi` target (emphasis as bold and italic through cli), used by
  `print()` when the console supports it.
- A `cli_format()` method, so a `weft` object prints inside `cli_*()`
  calls, and documented use of `format_inline()`.

### E4. The static side

- The lints, the gate and `arms()` read the literal strings passed to
  `weft()` as they read `weft_str()` strings today, including raw strings.
- `.R` files in the project are scanned for `weft()` literals: the numeral
  rule, construct errors and the gate's counts reach them.

### E5. Documentation

- An article on strings (plots, console, tables), the syntax reference in
  `inst/agent/references/syntax.md` and its `skills/weft` copy, the
  README, and the spec's §3.6.

## Later, not in this plan

- Self-formatting values (`num(x, digits = 1)` that print correctly
  through `paste()`, `glue()` and any sink).
- An HTML target and rich plot text (ggtext, marquee).
- A claim collector for scripts outside a knit.
