# E2: bare names read R (25 Nov)

Package E2 of `dev/plan-weft-everywhere.md`. Rulings 3 to 6 there, and the
entry "Weft everywhere" in `dev/decisions.md`, are not reopened: a bare name
reads R wherever R runs, with every R formatter; a name not bound where it
stands is left to the filter and published for it; `weft_put()` leaves R's
API and `weft_values_write()` stays; Python `put()`/`auto()` and Julia
`@put` stay; later replaces; automatic publishing publishes only what the
filter will resolve; a setting names the namespace a document's bare names
read. Package Q (`dev/design-quoting.md`) and package E1
(`dev/design-e1.md`, `weft()`) land first: examples use single-quoted
attribute values, and "a `weft()` string" is E1's.

"Bare name" in this note is the plan's word for a named value
(`` `x`{.num} ``, rule 1.12.1). It is not a *bare value* (`` `r x` `` with
no attribute block, rule 1.1.8); the spec keeps saying "named value".

This note is the contract for a test-writer who does not read `R/` and an
implementer who does not edit tests. Rule ids: **BN** (who reads a name and
how), **TR** (what the hooks publish), **NS** (the namespace setting),
**PS** (text a chunk prints), **PB** (the publishers), **ST** (the static
side). Messages are **M1** to **M9**. Decisions are **D1** to **D18**.
Design-6 numbers (N, E) are cited where E2 revises them.

## Why

In a knitr document `` `depth`{.num} `` today is not read by R. The hooks
leave it as written, publish `depth` in a `weft-values` block, and the Lua
filter prints it from the block. So the same name in the same document
prints with R's formatters in `` `r depth`{.num} `` and with the filter's in
`` `depth`{.num} ``: units, the dictionary and project formatters work in one
and are refused in the other (2.13.3). And the publisher publishes too much:
with one named value in a document, every token of every governor is a name
to publish, so `[shown]{if="nchar(secret) > 0"}` wrote
`"secret":"hunter2"` into the values block, which persists in `_freeze`,
keep-md output and `.ipynb` files.

## What the code does today (checked at 5bf21f4)

| Where | What it does |
|---|---|
| `R/resolve.R:1278-1279` (`render_item0()`) | a row of kind `named` returns its source text unchanged: the hooks never read a name, in prose, captions or `weft_str()` strings |
| `R/resolve.R:370` | `env0` is `ctx$envir` for a string, else `knitr::knit_global()`; `render_value()` (`:776-803`) evaluates the parked expression of `` `r x` `` there |
| `R/resolve.R:486-497` (`forward_hint()`) | `` `r n` `` that fails with "object 'n' not found" gets the hint "write it as a named value, `n`{.num}, which takes its value from below (rule 1.12.7)" |
| `R/weft-str.R:113-114` (`resolve_string()`) | fast path: a string with no parked code and no `[` is returned as it is, so a string whose only construct is a named value is never scanned |
| `R/weft-str.R:119-120` (`inline_function_names()`) | the names visible to markup include `weft_put` |
| `R/values.R:367-382` (`weft_put()`) | exported; outside a knit returns the block text (class `weft_values`); in a knit hands records to `values_wait()` |
| `R/values.R:283-321` (`values_collect()`) | the arguments of `weft_put()` and `weft_values_write()`: names or symbols; E40 (`:295`) and E43 (`:304`) name `weft_put()`; a `claim()` argument is captured (`:248-279`, `:311-315`) and its checks ride on the record |
| `R/values.R:410-421` (`weft_values_write()`) | writes a values file with the same arguments; stays |
| `R/values.R:434-447` (`values_text_names()`) | the names a source names: every `` `NAME`{ `` and every NAME token of an `n`, `if`, `sign` or `list` value (`:441-444`, `values_governor_names()` `:425-430`), over the whole file text: prose, front matter, chunk options and chunk code alike; `nchar(secret) > 0` gives `nchar` and `secret` |
| `R/values.R:491-503` (`values_names()`) | the gate: those names count only when the source holds a named value (`sc$named`) |
| `R/values.R:511-525` (`values_wait_json()`) | in a `results: asis` chunk the block is written into the chunk output at once; otherwise the names wait |
| `R/values.R:527-540` (`values_note_put()`) | a name a publisher published is recorded with its current R binding, so the hooks do not publish it again until the binding changes |
| `R/values.R:542-571` (`values_pending()`) | at each prose block: every listed name bound in `knit_global()` (no inheritance) whose record changed is published; Python `auto()` changes are fetched here (`guest_auto_changes()`, `:562`); a name a publisher put wins over the automatic value in the same block |
| `R/hooks.R:179-188`, `:193-203` | the `text` hook writes the pending block before the prose; the `document` hook appends the last one |
| `R/hooks.R:481-482` (`finish_document()`) | the end-of-document check (2.5.2) leaves out `named` rows |
| `R/guest.R:419-428` (`guest_knitr_put()`) | Python `put()` under knitr: records go to the waiting names; in an asis chunk it returns `FALSE` and Python prints the block itself, so R never sees that publication |
| `R/guest.R:434-443` (`guest_auto_changes()`) | asks Python's `_knitr_changes(names)` with R's list of names |
| `R/guest.R:288` (`guest_chunk_end()`), called from `R/captions.R:34-44` | runs at the end of every Python and Julia chunk (drains claims, Julia puts) |
| `R/captions.R:82-100`, `:136-147` | a caption with a construct becomes a call evaluated after the chunk, in the chunk's environment; `caption_not_resolved()` (`:58-65`) gives the 2.3.5 reasons (cache, `eval: false`, another engine) |
| `R/scan.R:1766-1769` | the scanner's `resolver` column: a `named` row is `filter` always |
| `R/scan.R:1825-1830` (`check_ids()`) | a hooks span may not refer to an id on a named value (1.12.10) |
| `R/scan-contexts.R:246`, `:596` | the front-matter (1.10.7) and caption (2.3.5) placement errors apply to top rows whose `resolver` is `hooks` |
| `R/lint-doc.R:889-891` (`lint_engine()`), `R/setup.R:302-303` (`lines_hold_construct()`) | a row is "the filter's form, needs no R" when its `resolver` is `filter` |
| `R/lint-named.R:18-29` (`named_uses()`), `:101-140` | `named-unpublished` reads rows whose resolver is `filter`; its message and hint name `weft_put()` and the gate |
| `inst/quarto/weft.lua:332-336` | the filter's "no value is published" hint names `weft_put()` |
| `R/rehearse.R:262`, `:292` | a rehearsal knits only (no Pandoc) in `new.env(parent = globalenv())`: named values are never checked by `rehearse()` today |

Two findings beyond the brief:

- `tests/testthat/test-quoting-names.R:66-75` (package Q, uncommitted)
  expects `kq` in `[one | many]{n='kq'}` to be published by a knit whose
  source holds no named value. Under today's gate it is not, so that test
  should fail even before E2; E2 inverts it in any case (TR1: a prose
  governor is never published). Tell Q's implementer.
- The publisher's list is read over chunk code too, so a governor inside a
  `weft()` literal that fits the grammar (`if='tier == "gold"'`) is a name to
  publish, though `weft()` resolves it at the call. TR1 removes chunk code
  from R's list.

## The contract

### BN. Who reads a name

**BN1 Where R reads a name.** Under `names_from: r` (NS1, the default in a
knitr document), R reads a named value, with every R formatter, in:

- the prose of a knitr document (2.13.13), including math and raw LaTeX in
  prose (target `tex`, as `` `r x` `` there), the arms of spans the hooks
  resolve, knitr children and included text;
- a caption the hooks resolve: a caption option of an R chunk that runs and
  is not served from the cache (2.3.1, 2.3.5), after the chunk, in its
  environment;
- a `weft()` string, in `.envir`, whatever `names_from` says.

It is never read by R in: front matter (BN6), a caption the hooks do not
resolve, text a chunk prints (PS), a Python `weft_str()` string (BN8), and
any document the filter resolves.

**BN2 The lookup.** The name is looked up from the start environment
(`knitr::knit_global()` for prose, the chunk's environment for a caption,
`.envir` for `weft()`), through its enclosing environments, by its exact
text (so `n.sites` and `_x` are found as bound). The walk reads the global
environment and stops before the first environment that is a namespace, a
package environment on the search path, the base environment or the empty
environment (D1). The first binding found decides:

- a binding that is not a function: the name is **bound** to that value;
- a function (a closure, a builtin or a special): the name is **a function**
  (D2);
- none: the name is **unbound**.

Forcing a promise (a lazy-loaded object from knitr's cache) that raises is a
"no value" failure, `error evaluating `x`{.num}: <message>`, as for
`` `r x` ``.

So `pi`, `T`, `letters`, `rivers` (datasets) and anything a package exports
are never read by name; `` `r pi` `` still reads base R's `pi`.

**BN3 How it prints.** A bound name prints exactly as `` `r NAME` `` with the
same attribute block prints in the same place: the same formatters (units,
unit ladders and `unit=`, the dictionary, project formatters, text and
collapse classes), the same `lang` checks, the same failures and markers
(2.6.8), warnings (printed-as-zero, unit warnings), the same TeX in math,
the same ids (BN10). Differences: the failure's construct is shown as the
named value as written (`` `depth`{.num} ``), not as `` `r depth` ``; a bare
missing value check (1.3.5) does not arise, since a named value always has
an attribute block. A `claim` or `level` key stays a construct error
(1.12.9), wherever the name is read.

**BN4 `.val` in R.** R prints `.val` from the value's record (3.8.4), as the
filter prints that record (1.12.2): an integer its digits, a double the
record's shortest text (`0.1 + 0.2` gives `0.30000000000000004`, `1e23`
gives `1e+23`), a string as it is, a factor its level, a `Date` its ISO
text, `TRUE` as `true`, a vector its elements so printed and joined by
", ", the minus `-`. A missing record (`NA`, `NaN`, `Inf`, `NULL`) is a "no
value" failure (1.12.2). With a text or collapse class, `.val` hands the
printed elements to that class as text pieces that are never read as
markdown (`` `sites`{.val .and} `` with `c("a*b", "c")` prints `a*b and c`).
A value 3.8.4 refuses or records as an error (a `units` quantity, a data
frame, a list, a function) under `.val` is a value error, M4. `digits` on
`.val` is ignored, as in the filter. (`.val` on `` `r x` `` is unchanged by
E2.)

**BN5 Left for the filter (knitr).** Under `names_from: r`, the hooks leave a
named value in prose or in a caption they resolve, as written, for the
filter, when:

- (a) the name is unbound (BN2); or
- (b) the name is a function (BN2); or
- (c) a guest published the name later than R's binding last changed (BN7).

Under `names_from: python` or `julia` the hooks leave every named value. A
left named value is recorded in the knit's constructs (`last_knit()`) as
evaluated, with no text and no failure, and is published for the filter when
R has a value for it (TR1). It is not a failure in the knit: the filter
resolves it, from a block above, or by the look-ahead of 1.12.7, or fails it
"no value".

**BN6 Front matter is always the filter's.** A named value in any
front-matter field of a knitr document, in either metadata block, is left
for the filter and takes the name's last published value (decision 71).
The hooks never read R for it: the top block is resolved before any chunk
runs (1.10.8), where R's binding is absent or left over from before the
render (D5).

**BN7 Later replaces, between R and a guest.** Each publication of a name by
a guest under knitr (Python `put()` or `auto()`, Julia `put` or `@put`) is
recorded with a **snapshot**: the result of BN2 from `knit_global()` at that
moment (the value, "a function", or "unbound"). Where the hooks meet the
name (prose, a resolved caption), let G be the latest guest publication of
it in this knit:

- no G: R's binding is read when bound (BN1), else BN5 (a) or (b);
- a G whose snapshot equals BN2 now (compared with `identical()`; "unbound"
  equals "unbound"): the guest's value is the latest, BN5 (c);
- a G whose snapshot differs from BN2 now: R's binding changed after the
  guest published, so R's binding is read when bound, else BN5 (a) or (b).

R's binding "changed" means its value changed: an R chunk that assigns a
name the value it already had does not count as a later assignment (D4). A
hand-written `weft-values` block and a values file are not guests: in a
knitr document they give a name its value only where R does not bind it.

**BN8 Python's `weft_str()`.** A named value in a string given to the
Python module's `weft_str()` (E1 PY1) is left for the filter, as today: in a
Python chunk a name is Python's, published by `put()` or `auto()`. The
expressions of inline R in that string are R, as before. R's `weft()` takes
an internal option for this (E1's PY1 caller passes it); it is not
exported and not documented in `?weft`.

**BN9 `weft()` and an unbound name.** In a `weft()` string a name that is
unbound in `.envir` (BN2) is a "no value" failure, M1; a function is a "no
value" failure, M2. Nothing is left for the filter (D3). In a knit with the
hooks the failure is collected and marked (E1 WS12); elsewhere it stops with
class `weft_no_value` (E1 WS13), the message beginning as WS13 says. The
fast path of `resolve_string()` (`R/weft-str.R:113`) must not skip a string
whose only construct is a named value.

**BN10 Ids.** A named value R reads defines its id for the hooks: a span the
hooks resolve may refer to it (`` `k`{#kk .num} `` then `[site | sites]{n="#kk"}`).
A named value left for the filter defines its id for the filter only; a
hooks span that refers to it is a "no value" failure, M5. A span the filter
resolves (in text a chunk printed) still cannot refer to an id on a value R
read (1.12.10).

**BN11 A binding from before the render.** At the start of a knit, for each
name of a named value in the source (TR4's list A), the hooks record BN2's
result from `knit_global()` when it is a value ("held before the render").
When the hooks read a name in prose or a caption and the value they read is
`identical()` to the one held before the render, they note the read. At the
end of the document, a noted name whose BN2 result is no longer identical to
the value held before the render (the document assigned it a new value
during the knit) is a "no value" failure, M3, located at the construct's
line, with no marker (the text is written). A name the document never
reassigns is not a failure: the value held before the render is the one the
document has. Inline R is not covered (1.12.7). In a `weft()` string there
is no such check.

**BN12 Ledger and records.** A named value R reads makes the ledger entry a
value makes (7.1): kind `value`, expression the name (whose key equals that
of `` `r NAME` ``, since `expr_key()` of a symbol is its text), the context
of where it stands (`prose`, `caption`, `math`, `tex`, `weft`), the printed
text, raw value and unit, and no `writer` field (an R entry). A named value
left for the filter makes no R entry; the filter's entry has `writer`
`"filter"` as now. `last_knit()$constructs` keeps kind `named` for these
rows.

### TR. What the hooks publish (knitr)

**TR1 R's list.** Under `names_from: r`, R publishes only names the filter
will resolve. A name is on R's list when:

- it is the name of a named value in a front-matter field (BN6), in either
  metadata block; or
- it is the name of a named value, or a NAME in a governor value (`n`, `if`,
  `sign`, `list`) that fits 1.12.4 to 1.12.6, in a caption option of a chunk
  whose captions the hooks do not resolve (2.3.5: `cache: true`,
  `eval: false`, or an engine other than R); or
- the hooks left a named value of it for the filter, for reason (a) or (b) of
  BN5, earlier in this knit (it joins the list from that point).

Never on R's list: a NAME in the governor of a span in prose (the hooks
resolve it, with R); a name of a named value that the hooks read; anything
found only in the code of a chunk, of any engine (PS). Under
`names_from: python` or `julia`, R's list is empty.

**TR2 When and what.** At the start of each block of prose and at the end of
the document, R publishes each name on its list for which BN2 from
`knit_global()` gives a value or a function, and that result is not
`identical()` to the snapshot of the name's latest publication in this knit
by anyone (R or a guest), or the name was never published. A value becomes
its record by 3.8.4; a function becomes the error record E45 ("is an R
function, which weft does not publish"), so the filter's failure names the
cause. A name bound only outside `knit_global()`'s walk (BN2) is not
published. Each R publication records its snapshot. The block is one fenced
block per point, `lang` `"r"`, `run` and `at` as now (2.13.8); with a
guest's waiting records in it, `cell` is that chunk's label, as now.

**TR3 Guests under knitr.** Python `put()` and Julia `put`/`@put` publish
as now (waiting names, written at the start of the next block of prose;
Python in a `results: asis` chunk prints its block itself). In addition R
records each such publication with its snapshot (BN7), including a Python
`put()` in an asis chunk, which `guest_knitr_put()` records before returning
`FALSE`. Where a guest's waiting record and R's own record of one name fall
in one block, the one with the later snapshot wins: R's when BN2 now differs
from the guest's snapshot, else the guest's (this replaces "a name
`weft_put()` published wins").

**TR4 Python's `auto()` under knitr.** Its changes are fetched at the end of
each Python chunk (`guest_chunk_end()`), not at the next block of prose, so
each carries its chunk's snapshot. R asks for these names (list A ∪ B):

- A: the name of every named value in the source and its includes, wherever
  it stands (prose, captions, front matter, chunk code);
- B: every NAME in a governor value that fits 1.12.4 to 1.12.6, of a span in
  the code of a Python or Julia chunk or in any chunk's options.

A NAME in the governor of a span in prose or in an R chunk's code is not in
the list. There is no gate: with no named value and no such span the list is
empty and nothing is published. On the jupyter engine `auto()` is unchanged
(its own source scan and its gate, 3.8.7).

**TR5 Nothing else changes in transport.** The block format, schema 1,
records (3.8.4), the run id (2.13.8), the filter's reading (2.13.2) and
freshness are as now. A knitr document all of whose named values R reads
writes no block; its stamp's `fresh` is then `null` (no block), and its
`named` count is 0.

### NS. The namespace setting

**NS1 `names_from`.** A setting in `_weft.yml` and in a document's `weft:`
key (9.1.1, the document's value wins). Values: `r`, `python`, `julia`, or
absent. Absent means the engine's language: `r` in a document the hooks
resolve. Any other value is a `weft_config_error` when the configuration is
read: M9.

**NS2 Effect.** Only in a document the hooks resolve (2.13.13):

- `r`: BN1 to BN7 and TR1 to TR4.
- `python` or `julia`: the hooks read no R binding for a named value in
  prose or a caption; every named value there is left for the filter; R
  publishes nothing itself (TR1); guests publish as TR3 and TR4 say. The two
  values behave the same in R; they differ in the lints' messages (ST5),
  which name that language's publisher.

`weft()` always reads `.envir`. Governors are not names: a span's `if`, `n`,
`sign` and `list` values in prose stay R expressions under every value
(read a Python value there as `py$flag`). In a document the filter resolves
the setting has no effect: its names are whatever its engine publishes. The
filter does not read the setting.

**NS3 A name bound in neither.** Under `r`: unbound in R and never published
by a guest above the sentence, the named value is left; the filter takes the
value the document publishes below when there is one value (1.12.7), else it
fails "no value" with the new hint (M6). Under `python` or `julia`: the
same, without R.

### PS. Text a chunk prints

**PS1** A named value or a span in text that R code prints (`cat()`,
`print()`, `knitr::kable()` cells and captions, any string that reaches the
output without going through `weft()`) is not read by R, and no name in it
is on R's list (TR1). It reaches Pandoc as markup. The filter then resolves
it only when the name is published another way (a guest, a values file, a
hand-written block, or the same name on R's list for another reason);
otherwise it fails "no value" with M6, whose hint says to pass the text
through `weft()`. In a loop `weft()` gives each line its own value (E1 WS2).

**PS2** Text a Python or Julia chunk prints keeps the guest route: `put()`
before the print in a `results: asis` chunk (the block is printed at once),
or `weft_str()` (BN8) with `put()`.

**PS3** The `string-markup` lint (ST6) finds the literal case before the
render.

### PB. The publishers

**PB1 `weft_put()` is removed** from the exports, the `NAMESPACE`, the
inline function names (`inline_function_names()`, so also from E1's WS3
list and `weft_setup()`'s search-path environment), `man/`, `_pkgdown.yml`.
Calling it is R's "could not find function". No deprecation.

**PB2 `weft_values_write(path, ...)` stays**, with its claim capture (the
old 3.8.2) and every refusal. Its messages no longer name `weft_put()`:

- E40 becomes M7: "weft_values_write() takes named arguments or names after
  the path: weft_values_write(path, n = nrow(d)) or weft_values_write(path,
  n) (rule 3.8.5)."
- E43 becomes M8: "`%s` is given twice in one weft_values_write() call."

**PB3 An internal block maker for tests**: `weft:::values_block(...)` takes
`weft_values_write()`'s value arguments (names or symbols, `claim()`
captured, the same refusals and messages M7, M8, E41, E42, E44), and
returns the fenced block text (class `weft_values`, which prints as the
text), in or out of a knit, storing nothing. `run` is read as 2.13.8 says
from the working directory; `at` is now. It is not exported. The transport
(TR) does not use it.

**PB4 Use-site checks.** In R, a check that should count where the value is
used is written where it is used: `` `r claim(worst, . < 50)`{.num} `` in
prose (2.4.1), a guard span `[`worst`{.num}]{if="worst < 50"}`, or `claim()`
inside a `weft()` string. A check carried on a record (2.13.4) comes only
from a values file written by `weft_values_write()` with `claim()` (or a
hand-written block); the filter honours it as now.

### ST. The static side

**ST1 The `resolver` column of a named row** (2.13.14, N140): `hooks` in a
document the hooks resolve with `names_from` `r` (or absent), when the row is
in prose, in a `weft()` literal, or in a caption of an R chunk whose
captions the hooks resolve; `filter` in front matter, in a caption of a chunk
whose captions they do not resolve (2.3.5), in a document with `names_from`
`python` or `julia`, and in every document the filter resolves. The
scanner reads `names_from` from the configuration it is given (the merged
`_weft.yml` and `weft:`). Every other row is as now.

**ST2 Consumers of the column.** The front-matter (1.10.7) and caption
(2.3.5) placement errors keep applying to rows whose resolver is `hooks`
(so a named value in front matter keeps its freedom of scalar form, and one
in a cached chunk's caption is no error). `check_ids()` applies 1.12.10 by
the column, which gives BN10's static half. `lint_engine()` and
`lines_hold_construct()` treat every `named` row as the filter's form
(needs no R) whatever its column, so the `engine` rule and `use_quarto()`'s
check give the same answers as today.

**ST3 The gate (6.3.1)** counts a named value as a value, as now, whoever
resolves it. Turning `` `r x`{.num} `` into `` `x`{.num} `` keeps the ledger
key (BN12) and the gate's counts.

**ST4 `arms()`, `checks()`, `changes()`** are unchanged: `arms()` lists
spans; a named value is text in an arm. `rehearse()` now checks the named
values R reads in each case (they fail, print and choose arms as values do);
a named value left for the filter is not checked by a rehearsal, which runs
no Pandoc (3.7.4). `verify()`, stamps and freshness are as now (TR5).

**ST5 `named-unpublished` (5.12.1).** It reads every `named` row whatever its
column, and the governor names of spans whose column is `filter`, as now.
Its message by document:

- a document the filter resolves, or `names_from` `python`/`julia`:
  "`{name}` is used by name but no chunk of this document mentions it;
  publish it with put() or @put (rule 5.12.1)."
- a knitr document with `names_from` `r`: "`{name}` is used by name but no
  chunk of this document mentions it; set it in an R chunk, or publish it
  with put() or @put (rule 5.12.1)."

Hint, in both: "Set it in code in this document: an R chunk under knitr,
put(name=...) in Python, @put name in Julia, or a values file." The
sentence about the gate is removed. Tier 2, one finding per name, as now.

**ST6 New lint `string-markup`** (rule 5.12.3, tier 2, scope file). In a
document the hooks resolve with `names_from` `r`, in the code of an executed
R chunk: a string constant (R's parse data, `STR_CONST`) that is not inside
the `x` argument of a call to `weft()` or `weft::weft()` (the argument E1's
ST2 reads) and whose content, read by the scanner as prose, holds a named
value or a span with an `n`, `if`, `sign` or `list` key. One finding per
string, at the string's line and column, context `chunk`, text the first
such construct as written. Message: "This string holds weft markup
(`{construct}`) but is not given to weft(), so R does not read its names
and the filter has no value for them (rule 5.12.3)." Hint: "Give the string
to weft() and print the object (a chunk that prints a weft object writes its
markdown), or cat(format(weft(\"...\"), target = \"markdown\"))." Not read:
chunks with `eval: false`, other engines, `.R` files (E4), documents the
filter resolves.

**ST7 `publish-hidden`** (5.12.2) is unchanged: it reads documents knitr does
not knit.

### Messages

| Id | Text |
|---|---|
| M1 | `` `{name}` is not bound where weft() was called, so it has no value (rule 1.12.12). `` Hint: `` Bind it before the call, or read a Python value with py_value("{name}"). `` |
| M2 | `` `{name}` is a function in R, not a value (rule 1.12.12). `` |
| M3 | `` `{name}` was read above the code that sets it in this render, from a value the R session held before the render began (rule 1.12.12). `` Hint: `` Render in a fresh R session, as quarto render and the Knit button do, or move the sentence below the code that sets it. `` |
| M4 | `` `.val` prints a value as it is, and `{name}` is {what}, which has no such form; use a formatter class such as .num (rule 1.12.2). `` (`{what}`: `a units quantity`, or `an R {class}` with the first class) |
| M5 | `` `#{id}` names an id on `{name}`, which R did not read here and left for the filter; the hooks cannot read it (rule 1.12.10). `` |
| M6 | filter, replacing the hint of "no value is published under the name" (E10, `weft.lua:332-336`, 1.12.7): `` Publish it in code in this document: put({name}=...) in Python, @put {name} in Julia, or a values file; under knitr, set it in an R chunk, and pass text an R chunk prints through weft(). A cell with include: false or output: false publishes nothing on the jupyter and julia engines. `` The detail text is unchanged. |
| M7 | `weft_values_write() takes named arguments or names after the path: weft_values_write(path, n = nrow(d)) or weft_values_write(path, n) (rule 3.8.5).` |
| M8 | `` `{name}` is given twice in one weft_values_write() call. `` |
| M9 | `` The setting `names_from` must be r, python or julia. `` (`weft_config_error`) |

M1 to M5 are details of collected failures (kind `no value` for M1, M2, M3,
M5; `value error` for M4), shown under 2.6.2 with the construct as written.

## Decisions

**D1 The lookup stops at the global environment.** BN2 reads the
environments the document owns (the knit environment, a calling function's
frames and closures, the global environment), never base R, a namespace or
an attached package. Alternatives: (i) full inheritance, exactly as
`` `r x` ``; refused, because a named value is the document's value with a
filter behind it: `` `pi`{.num} ``, `` `T`{.val} `` or `` `rivers`{.count} ``
used above the code that sets them would print base R's or a dataset's value
instead of the value from below, and `` `F`{.num} `` would never reach a
Python F statistic; (ii) `knit_global()` without inheritance, as the
publisher reads; refused, because a `weft()` string in a function must see
the function's locals, and `rehearse()` knits in a child of the global
environment. Cost: `` `r pi` `` and `` `pi`{.num} `` differ, and a value an
attached data package exports must be bound in a chunk (`n <- pkg::n`).
This is the one place where `` `x` `` and `` `r x` `` do not agree, and it
is for R's own objects only.

**D2 A function is not a value.** In prose it is left (BN5 b) and published
as an error record (TR2); in `weft()` it is M2. Alternatives: a value error
from the formatter, as `` `r f`{.num} `` gives (refused: Python's `max` or
`sum`, or a name used above its value that happens to shadow a user
function, would fail instead of taking the published value); skip the
function and keep walking (refused: two bindings of one name is a trap
either way, and the first is what R would read).

**D3 An unbound name in `weft()` fails; it is not left.** A `weft()` object
goes to plots, the console and logs, where no filter runs, and its plain
form would print the markup (E1 PL2). Alternative: leave it in a knit
(refused: the same string would print a value in a knit and markup in a
plot).

**D4 R against a guest: by snapshot, compared by value.** BN7 orders an R
binding and a guest publication by whether R's binding changed since the
guest published. Alternatives: R always wins (refused: an R scratch `n` set
early silently shadows the Python `n` published later, the case ruling 5
exists for); the guest always wins (refused: the mirror image); timestamps
per chunk from a hook after every R chunk (refused: more state for the same
answer, and still blind inside a chunk); `identical()` on addresses (refused:
R has no supported address identity; `identical()` by value is what
`values_pending()` uses now). Cost: an R chunk that reassigns the value R
already had does not count as later; written in Limits.

**D5 Front matter is always the filter's.** Alternatives: R reads it where
the field stands (refused: the top block is resolved before any chunk, so R
has either no binding or one left from before the render, and decision 71
already gives front matter the document's last value); R reads it only in
the end block of 1.10.9 (refused: two rules for one field). Cost: units and
project formatters do not reach a named value in a title; `` `r x` `` in an
end block (1.10.9) still does.

**D6 Captions follow who resolves them.** A caption the hooks resolve runs
after its chunk, so R's binding there is the chunk's value; reading it gives
units and project formatters in figure captions and agrees with
`` `r x` `` in the same caption. A caption they do not resolve keeps the last
published value. Alternative: all captions take the last value (decision
71); refused for resolved captions, where R's value at the chunk is already
the value the caption describes, and "last" would differ from it only when
the document changes the name later, which the caption cannot mean.

**D7 R's list is places the filter reads, not the whole source.** TR1
publishes front-matter names, names in captions the hooks leave, and names
the hooks left at run time. Alternatives: today's whole-source list
(refused: it leaks every token of every R governor, the review's finding);
the whole source minus prose governors (refused: still lists names in
chunk code, including governors in `weft()` literals, which `weft()`
resolves at the call); parsing chunk code to drop `weft()` literals
(refused: PS makes chunk code a non-place for R altogether, so nothing needs
parsing).

**D8 No gate under knitr.** Design-6 N43 published nothing unless the source
held a named value, so that a document with only R governors knit as before.
Under TR1 such a document has an empty list and writes no block anyway; the
gate would now only stop publishing a name the filter will resolve (a
grammar span in a cached chunk's caption), turning a working document into a
"no value" failure. Alternative: keep it (refused for that reason). Python's
`auto()` on the jupyter engine keeps its gate: it is unchanged by ruling.

**D9 Text an R chunk prints: not published, loud, linted at tier 2.**
Alternatives: (i) keep publishing names found in chunk code (refused: the
filter then prints the last published value, which in a loop is the same
for every line and after a later change is stale, silently); (ii) a tier-1
lint (refused: a string built in a variable and given to `weft()` later,
`x <- "..."; weft(x)`, is a false positive that would block commits; the
render already fails loudly, D26's reasoning for `named-unpublished`);
(iii) scan each R chunk's output at knit time (refused: echoed source,
Quarto's cell divs and kable's HTML all have to be told apart from printed
markdown, for a case the filter already fails). Cost: a document that relied
on a printed name with a value that never changes now fails until the text
goes through `weft()`.

**D10 `weft_put()` goes; tests get `weft:::values_block()`.** Alternatives:
keep `weft_put()` unexported for tests (refused: its knit behaviour, the
waiting names and the asis write, is what E2 removes, and tests would keep
pinning it); build every test record through `weft_values_write()` and a
temporary file (workable, but dozens of tests read a record in one line
today). `values_block()` is the outside-a-knit half of the old function,
which costs nothing to keep.

**D11 `weft_values_write()` keeps `claim()` capture.** A values file feeds
documents that may run no R (engine-free chapters, 2.13.10); a check carried
on the record is then the only use-site check the pipeline can give.
Alternative: drop it with `weft_put()` (refused for that reason; 2.13.4
keeps reading such checks).

**D12 The setting is `names_from: r | python | julia`.** Alternatives for the
name: `names` (too broad), `bare_names` ("bare" means 1.1.8's bare value),
`name_language`. For the values: `r | published` would say exactly what R
does, but the ruling names a namespace, and `python` reads as what the
author means; `python` and `julia` behave alike in R and differ only in the
lint messages. Governors stay R under every value: making grammar spans in
prose the filter's under `python` would move a construct between resolvers
by a setting, which N14 and 2.13.13 decide from the source alone. The filter
does not read the setting, because what reaches it is already decided.

**D13 Python's `weft_str()` leaves names.** Alternatives: read R's
`.envir` (refused: in a Python chunk `n` means Python's `n`, and R's `n`
would print silently instead); read Python's `__main__` through reticulate
(refused for now: a second lookup path and type reader in E2; possible
later, and the plan keeps `put()` as the route for Python's printed loops).

**D14 `.val` in R prints from the record.** So `` `x`{.val} `` prints the same
text whether R or the filter resolves it, which is the point of `.val`.
Alternatives: R's stock print (refused: `TRUE` and `true`, `1e+23` and
`1e23` would differ by resolver); refuse `.val` in R (refused: a knitr
document would have a class that works only above its value).

**D15 A binding from before the render is a failure, not a warning.** BN11.
1.12.7 promises that a name used above its value takes the value from
below; a stale session value breaks that silently, the defect weft exists to
stop (1.12.7's own reason for refusing a warning). The check is narrow: it
fires only when the document itself assigns the name a new value later in
the knit. Alternatives: document the trap only, as today (refused: E2 makes
R the reader, so weft can see it); a warned check (refused, as above); also
cover `` `r x` `` (refused: inline R is evaluated where it stands, by
1.12.7, and stock knitr behaves so). Cost: a script that sets `n`, renders,
and whose document both reads `n` above and reassigns it below fails; it
should use two names.

**D16 The `resolver` column describes the first reader.** For a named row in
a knitr document it is `hooks` where the hooks try first, though the filter
may still resolve it at run time (BN5). The two consumers that ask "does
this document need R?" read the kind instead (ST2). Alternative: a third
value `both` (refused: every consumer would need a case for it, for no
answer they use).

**D17 Ids follow the reader.** BN10. Alternative: keep 1.12.10's static ban
on hooks spans referring to named values (refused: it would forbid
`` `k`{#kk .num} `` then `n="#kk"` in a knitr document, where both are R's).

**D18 Rule 1.12.8 is restated, not kept.** "A named value means the same in
every document and on every engine" is false once R reads names: a `units`
value prints in R and is refused by the filter (3.8.4, 2.13.3). The new text
(rule edits) says what holds: one name and one record print one text; R
carries more kinds of value than the filter.

## Tests

The test-writer works from this note. Existing helpers: `b6_knit(lines)` in
`helper-6b.R` (an in-process knit of an `.Rmd`, raw knitr output in
`$text`, its blocks in `$blocks`, `$failed`), `b6_blocks()`,
`b6_block_names()`, `b6_core()`, `b6_e_*()`; `filter_md(md, name =, to =)`
in `helper-filter.R` (plain Pandoc with `weft.lua` on markdown text);
`fm_msg` for filter texts; the Python skips of `test-py-put.R`. Add to
`helper-6b.R`:

```r
# the knit, then the filter on its markdown, as a knitr document (2.13.13)
e2_render <- function(lines, ..., to = "plain") {
  k <- b6_knit(lines, ...)
  k$filtered <- filter_md(k$text, name = "doc.Rmd", to = to)
  k
}
```

and change `b6_rec` to `weft:::values_block(v = x)` (PB3).

Each test below names its input and the observable output. "md" is
`b6_knit()`'s `$text`; "out" is `filter_md()`'s `$output`.

### New tests (`test-names-read.R`, `test-names-transport.R`, `test-names-from.R`, `test-lint-string-markup.R`)

**T1 Prose reads R** (BN1, BN3, BN12):

- `depth <- 3.14159` in a chunk; prose `The depth is `depth`{.num} m.` → md
  holds `The depth is 3.1 m.`, no `` `depth`{ `` anywhere, and no block.
- In one knit, `` `depth`{.num digits='2'} `` and
  `` `r depth`{.num digits='2'} `` on two lines print the same text; the same
  for `x <- 1234567.891` with `.num`, `.pct` (`x <- 0.123`), `.sci`
  (`x <- 0.000123`), `.word` (`k <- 3L`), `.count`, `.ord`, `.and`
  (`s <- c("a", "b", "c")`), `.cap` (`w <- "north"`).
- Units: `d <- weft::u(5, m^2)`: `` `d`{.num} `` and `` `r d`{.num} `` print
  the same (`5 m^2^` with a no-break space); `` `d`{unit='cm^2'} `` and
  `` `r d`{unit='cm^2'} `` the same.
- A project formatter (a `_weft.yml` with a formatter class, as the existing
  project-formatter tests write one): `` `x`{.myclass} `` and
  `` `r x`{.myclass} `` print the same.
- Math: `$a = `depth`{.num}$` and `$a = `r depth`{.num}$` give the same TeX
  in md.
- In an arm: `depth <- 3.5`; `[`depth`{.num} m | none]{if="depth > 0"}` →
  `3.5 m`.
- Dotted and underscore names: `n.sites <- 4L` → `` `n.sites`{.num} `` is
  `4`; `` assign("_x", 2L) `` → `` `_x`{.num} `` is `2`.
- A value error: `z <- 1 + 2i`; `` `z`{.num} `` fails the knit with the same
  kind as `` `r z`{.num} `` (`last_knit()$failures$kind`), the construct shown
  as `` `z`{.num} ``; in draft mode md holds a marker `<<weft: KIND, line N>>`
  with N the prose line.
- Ledger, in a set-up project (`use_setup()` as the ledger tests do): the
  entry for `` `depth`{.num} `` has kind `value`, expression `depth`, no
  `writer` member, and the same key as the entry of `` `r depth`{.num} `` in
  a second render of the document with that text instead.
- `last_knit()$constructs` has a row of kind `named` for it, evaluated.

**T2 `.val` in R** (BN4): in prose, `n <- 12L` → `12`; `f <- 0.1 + 0.2` →
`0.30000000000000004`; `g <- 1e23` → `1e+23`; `b <- TRUE` → `true`;
`dt <- as.Date("2026-11-25")` → `2026-11-25`; `s <- "a*b"` → `a*b` (no
emphasis in md: the `*` stays as typed); `v <- c(1L, 2L, 3L)` → `1, 2, 3`;
`neg <- -2L` → `-2` (ASCII hyphen); `sites <- c("a*b", "c")` with
`{.val .and}` → `a*b and c`; `fct <- factor("x")` → `x`. `m <- NA` →
a "no value" failure. `q <- weft::u(5, m)` → a value error whose detail is
M4 with `a units quantity`; `df <- data.frame(a = 1)` → M4 with
`an R data.frame`. Each of the non-failing rows prints in md exactly what
`filter_md()` prints for the same record in a block (one parity check per
kind, with `fr_int()`, `fr_float()`, `fr_bool()`, `fr_date()`,
`fr_str()`, `fr_list_int()`).

**T3 Left for the filter** (BN2, BN5, TR1, TR2):

- Above its value: prose `In summary, `n`{.count} sites.`, then a chunk
  `n <- 12L`, then prose `End.` → md line 1 still holds `` `n`{.count} ``;
  exactly one block, after the chunk and before `End.`, naming `n` with
  `b6_e_int("12")`; `e2_render()` out starts `In summary, 12 sites.`.
- Never bound: `` `zz`{.num} `` → md keeps it, no block; out fails with
  `fm_msg$E10("zz")` and the new hint M6 (update `fm_msg$E10_hint`).
- Base and packages are not read: `` `pi`{.num} ``, `` `letters`{.and} ``,
  `` `rivers`{.num} `` → md keeps each; no block; `` `r pi`{.num} `` on the
  same page prints `3.1` (control).
- A function: `f <- function() 1` in a chunk; `` `f`{.num} `` → md keeps it;
  a block names `f` with an error record whose `why` holds E45's text with
  `function`; out fails with a value error naming it.
- Twice republished below a use above: prose `` `n`{.num} ``, chunk
  `n <- 1L`, prose, chunk `n <- 2L`, prose → md has two blocks naming `n`
  (1 then 2); out fails with 1.12.7's several-values text (as today).
- Nothing is published for a name R reads: `n <- 3L`, prose
  `` `n`{.num} `` twice → no block.

**T4 What R publishes** (TR1, TR2, D7, D8):

- The leak: chunk `secret <- "hunter2"; n <- 3L`; front matter
  `title: "Count `n`{.num}"`; prose `[shown]{if="nchar(secret) > 0"}` and
  `` `n`{.num} `` → md holds exactly one block (at the first prose block),
  whose names are exactly `n`; `hunter2` occurs nowhere in md; out's title
  is `Count 3`.
- A prose governor is never published: chunk `kq <- 3L; unused_q <- 1`;
  prose `Found [one | many]{n='kq'} sites.` → no block (replaces Q's T5 knit
  test, `test-quoting-names.R:66-75`, whose expectation inverts).
- A front-matter name in a block scalar: `abstract: |` with
  `` `n`{.num} ``; chunk `n <- 3L` → md keeps the abstract's
  `` `n`{.num} `` and a block names `n`; out's abstract reads `3`. The same
  with `title: "... `n`{.num}"` (plain scalar) and in an end metadata block
  (1.10.9).
- A cached chunk's caption: chunk with `cache=TRUE` and
  `fig.cap = "Depth `depth`{.num} m"`, `depth <- 2.5` inside, `plot(1)` →
  no construct error; the caption in md keeps `` `depth`{.num} ``; a block
  names `depth`. The same caption on an R chunk with no cache → md's caption
  reads `Depth 2.5 m` and no block names `depth`.
- No gate: no named value anywhere; a cached chunk whose `fig.cap` holds
  `[a | b]{if='flag'}`, with `flag <- TRUE` → a block names `flag`.
- A document with no named value and no span in a caption knits
  byte-identical to the same knit with weft's publishing stubbed out (keep
  today's "N43: a document with no named value knits byte-identical" test,
  with that fixture).
- Change detection: front-matter name `n`; chunks `n <- 1L`, prose,
  `n <- 1L`, prose, `n <- 2L`, prose → blocks name `n` twice (1, then 2).

**T5 Text a chunk prints** (PS1, D9):

- Chunk `n <- 3L` then a `results='asis'` chunk
  `cat("We sampled `n`{.num} sites.\n")` → md holds the line with
  `` `n`{.num} ``; no block names `n`; out fails "no value" with M6.
- The `weft()` route: an asis chunk
  `for (n in 2:4) cat(format(weft::weft("Site `n`{.num}."), target = "markdown"), "\n")`
  → md holds `Site 2.`, `Site 3.`, `Site 4.`, and no block.
- A chunk whose value is `weft::weft("Mean `m`{.num}")` with `m <- 1.25` →
  md holds `Mean 1.2` (E1 knit_print; BN9 reads `m`).

**T6 `weft()`** (BN1, BN9, D3), outside a knit unless said:

- `n <- 3L; as.character(weft::weft("`n`{.num} sites"))` is `"3 sites"`;
  `format(, target = "markdown")` the same.
- `f <- function() { k <- 2L; weft::weft("`k`{.num}") }`;
  `as.character(f())` is `"2"`.
- `vapply(2:4, function(n) as.character(weft::weft("`n`{.num}")), "")` is
  `c("2", "3", "4")`.
- `weft::weft("`zz`{.num}")` (no `zz`) stops with class `weft_no_value`,
  the message containing M1 for `zz`; `weft::weft("`pi`{.num}")` the same
  for `pi`; with `g <- function() 1` in the caller, `` `g`{.num} `` stops
  with M2.
- `.envir = list2env(list(a = 5L))` reads `a`.
- `weft::weft("`b`{.val}")` with `b <- TRUE` is `"true"`; with
  `u5 <- weft::u(5, m^2)`, `weft::weft("`u5`{.num}")` is `"5 m²"`.
- In a knit with the hooks, a chunk `x <- weft::weft("`zz`{.num}")` in draft
  mode: `as.character(x)` holds `<<weft: no value, chunk LABEL>>`; out of
  draft the render fails naming the chunk.
- A `weft()` call is unaffected by `names_from: python` in the front matter:
  it reads R's `n`.

**T7 Guests** (BN7, TR3, TR4, NS2), skipped as the existing knitr Python
and Julia tests skip:

- R chunk `n <- 3L`; Python chunk `from weft import put; put(n=5)`; prose
  `` `n`{.num} `` → md keeps the named value, a block above it names `n` with
  5; out prints `5`.
- R `n <- 3L`; Python `put(n=5)`; R `n <- 7L`; prose → md prints `7`; no
  block for `n` after the R chunk is needed (the Python block may stand).
- Python `put(n=5)`; R `n <- 3L`; prose → `3`.
- R `n <- 3L`; Python `put(n=5)`; R `n <- 3L` again; prose → out prints `5`
  (D4's stated cost).
- Python in a `results='asis'` chunk: `put(n=5)` then
  `print("Py `n`{.num}.")` with R's `n <- 3L` set before → out prints
  `Py 5.`; prose after it with `` `n`{.num} `` → out `5` (the asis put is
  recorded, TR3).
- `auto()`: Python chunk `from weft import auto; auto()`; R `m <- 2L`;
  Python `m = 9`; prose `` `m`{.num} `` → out `9`. A Python chunk that binds
  `secret = "x"`, with prose `[a | b]{if="nchar(secret) > 0"}` and a named
  value elsewhere → no block names `secret` (TR4's list).
- `print(weft_str("`n`{.num}"))` in an asis Python chunk after `put(n=5)` →
  md keeps `` `n`{.num} `` in the printed line (BN8); out prints `5`.
- A Julia `@put n` after R's `n <- 3L`, prose → `` `n`{.num} `` left, out
  the Julia value (one test, skipped without Julia).

**T8 The setting** (NS1 to NS3):

- `_weft.yml` `names_from: python`, R `n <- 3L`, prose `` `n`{.num} `` → md
  keeps it; no block (R publishes nothing); out fails "no value".
- The same with Python `put(n=5)` above → out `5`; front matter
  `weft: {names_from: r}` over the project file → md prints `3`.
- `names_from: ruby` → the knit stops with `weft_config_error` and M9;
  `weft:::read_config()` of such a project raises the same.
- `names_from: julia` behaves as `python` in R (one case).
- The scanner (ST1): in an `.Rmd`, a prose named row has resolver `hooks`
  and a front-matter one `filter`; with `names_from: python` both are
  `filter`; in a `.qmd` with `engine: jupyter` every named row is `filter`
  whatever the setting.

**T9 A binding from before the render** (BN11, D15): knit the document with
`knitr::knit(input, envir = e)` where `e <- new.env(parent = globalenv())`
holds `n <- 1L` (the document's setup chunk calls `weft::weft_setup()`):

- prose `` `n`{.count} ``, then chunk `n <- 12L`, then prose → the knit
  fails; `last_knit()$failures` has one row of kind `no value` whose detail
  is M3 for `n`, at the prose line; in draft mode md prints `1` there and the
  failure is listed.
- the same without the assigning chunk → no failure, md prints `1`.
- `` `r n` `` in place of the named value → no failure (inline R is not
  covered).
- a `rehearse()` of the first document (its own environment) → no M3.

**T10 Ids** (BN10): `k <- 1L`; `` `k`{#kk .num} `` then
`[site | sites]{n="#kk"}` in an `.Rmd` → no construct error from the scanner
(`weft:::scan_file()` row errors are `NA`), md `1 site`. With `k` unbound at
that point (set below) → the span fails with M5.

**T11 Lints** (ST5, ST6):

- `named-unpublished`, knitr `.Rmd`: prose `` `zz`{.num} `` and no chunk
  mentions `zz` → one finding with ST5's knitr message; a chunk
  `zz <- 1` → none. In a jupyter `.qmd` → the filter message. The hint has
  no gate sentence.
- `string-markup`: an R chunk `cat("We sampled `n`{.num} sites.\n")` →
  one finding, rule `string-markup`, tier 2, spec `5.12.3`, at the string's
  line, text `` `n`{.num} ``, with the message and hint of ST6;
  `cat("[a | b]{if='flag'}")` → one finding. None for:
  `cat(weft::weft("`n`{.num}"))`, `cat(format(weft("`n`{.num}"), target = "markdown"))`,
  `weft(x = "...")`, a string with `` `n` `` and no attribute block, a
  string holding only a `.weft-literal` span, a Python chunk's
  `print("`n`{.num}")`, an R chunk with `eval: false`, a document with
  `names_from: python`, a jupyter `.qmd`.
  `lint_rules()` lists `string-markup`, tier 2, rule `5.12.3`, scope `file`.
- The `engine` rule and `use_quarto()`'s construct check give today's
  answers for a `.qmd` with an `{r}` chunk, no `engine:` key and only named
  values (keep `test-lint-engine-named.R`'s control).

**T12 `rehearse()`** (ST4): a document with
`n <- params$k` and prose `` `n`{.num} ``; cases `ok = list(k = 2)` and
`gone = list(k = NA)` → `ok` has no failures; `gone` has one failure of kind
`no value` at the prose line.

**T13 `weft_put()` is gone** (PB1 to PB3):
`"weft_put" %in% getNamespaceExports("weft")` is `FALSE`;
`"weft_values_write" %in% ...` is `TRUE`; `"values_block"` is not exported;
`weft:::values_block(depth = 3.14159)` has class `weft_values` and parses as
schema 1 (today's N44 expectations); `weft_values_write(f, 1 + 1)` raises
`weft_values_error` with M7; `weft_values_write(f, a = 1, a = 2)` with M8;
`weft_values_write(f, lim = claim(50, . > 10))` writes a record whose
`checks` hold the check (today's N41 expectations, through the file).

### Existing tests that change

- `helper-6b.R`: `b6_rec()` uses `weft:::values_block()`; the header comment
  names it. `b6_parse()` is unchanged.
- `test-weft-put.R` becomes `test-values-block.R`: every
  `weft::weft_put(...)` outside a knit becomes `weft:::values_block(...)`,
  expectations unchanged; "N1" is inverted (T13); the E40 and E43 tests
  expect M7 and M8 (also for `weft_values_write()` in the same file and in
  `test-values-write.R`, if it pins them).
- `test-values-record.R` (13 uses), `test-review6-r.R` #14, #15, #17:
  `weft::weft_put(` becomes `weft:::values_block(`. "#15: in a knit, a
  complex the prose names is an error record at the name" becomes: the knit
  fails with the kind `` `r z`{.num} `` gives (T1).
- `test-values-knit.R`: the N43 tests whose prose names a bound name now
  expect the value printed in md and no block; "a name bound after the prose
  that mentions it" keeps its block (T3's first case); the N42 tests
  (`weft_put()` in a knit, waiting names, asis write, `weft_put` wins, `cell`
  label from a put, a claim put in a knit) are deleted: the behaviour is
  gone (PB4 says where use-site checks went). N26, N48 and N21 tests force a
  block with a front-matter named value (`title: "`a`{.num}"`) instead of a
  prose one. "the end-of-document check does not fail on named constructs"
  and "R-expression constructs resolve as today, named ones stay" become:
  named ones print too.
- `test-coexist-knitr.R`: `CK_QMD` loses `weft::weft_put(lim = ...)` for
  `lim <- 20L` (and `30L`); `depth`, `lim`, `pb` are now hooks entries with
  no `writer`; to keep a filter construct in the document, its title gains
  `` `lim`{.num} ``; `CK_KEYS`, the stamp's `named` and `writers`, and the
  ledger expectations follow (the filter's entry is the title's). N131h
  becomes T1's `` `x` ``/`` `r x` `` parity. The N92 cases are unchanged.
- `test-scan-named.R:135-153`: in a knitr document named rows in prose and in
  an arm of a hooks span have resolver `hooks`; `:169-185` (python chunk,
  cached or `eval: false` R chunk captions) stay `filter`; `:158-165` (plain
  `title:`) stay `filter`.
- `test-quoting-names.R:66-75` inverts (T4's second case).
- `test-lint-named.R`: fixtures `weft_put(depth = 12)` become
  `depth <- 12`; the E70 text and hint follow ST5 (`helper-6d.R:84`); the
  gate-hint tests are deleted.
- `helper-filter.R:256` `E10_hint` becomes M6; `test-filter-carrier.R:52`,
  `test-filter-forward.R:120`, `test-jupyter-render.R:171`,
  `test-julia-render.R:195` follow through `fm_msg`.
- `test-gate-named.R:133-134`, `test-verify-named.R:197`:
  `weft_put(depth = ...)` becomes `depth <- ...`; where the test needs the
  filter to resolve `depth`, the named value moves to the title.
- `test-checks-read.R:384` (`weft_put('x', 2)` is not a rebinding) stays: it
  is an unknown call to the reader.
- E1's `test-weft.R` cases that expect a named value left in a `weft()`
  string (E1 WS4, the PL table row "named value (E1)") expect the value read
  (T6), except through Python's `weft_str()` (BN8).
- Python's knitr `auto()` tests (`test-review6-py.R`, the knitr half of
  `test-py-auto.R` if any) take TR4's list: a name only in a prose governor
  is not published.

## Rule edits for `dev/PACKAGE-SCOPING.md`

Replacement text. Part 3 (evidence) keeps `weft_put()` as a record of what
was run. E1's edits are assumed applied; where E2 edits E1's text, it says so.

### Part 1

**1.10.1**, last sentence: "A named value works in any caption, on any
chunk: in a caption the hooks resolve, R reads it after the chunk (1.12.12);
in any other caption the filter gives it the name's last published value
(1.12.7)."

**1.10.7**, last sentence: "A named value works in any of the four fields,
in any form of scalar, and in either metadata block: the filter resolves it
after the body with the name's last published value (1.12.7); R does not
read it there (1.12.12)."

**1.10.10** (E1's text), add: "A named value or a span in text that R code
prints without `weft()` is not read by R, and R publishes nothing for it
(1.12.14)."

**§1.12 intro**: "A named value is a value written by its name. Where R runs
(the prose of a knitr document, a caption the hooks resolve, a `weft()`
string) R reads the name, as `` `r x` `` reads an expression (1.12.12).
Elsewhere the filter of 2.13 resolves it from what code publishes. These
rules hold for every language and every engine."

**1.12.1**, the sentence "Code publishes the name (2.13, 3.8)." becomes
"Where R runs, R reads the name (1.12.12); elsewhere code publishes it
(2.13, 3.8)."

**1.12.2**, add at the end: "R prints `.val` from the value's record (3.8.4),
so it prints what the filter prints for that record; a value whose record is
refused or an error (a `units` quantity, a data frame, a list, a function)
is a value error under `.val`."

**1.12.7**, the knitr paragraph ("This holds in every document the filter
resolves, knitr documents included: the hooks publish each name the source
uses when it is bound, at each prose block and at the end of the document
(2.13.11), so the value is in the closing block.") becomes: "This holds in
every document the filter resolves. In a knitr document a named value the
hooks leave because R does not bind it where it stands (1.12.12) is
published by the hooks once R binds it (2.13.11), so its value is in a block
below." The hint of "no value is published under the name" becomes: "Publish
it in code in this document: put(%s=...) in Python, @put %s in Julia, or a
values file; under knitr, set it in an R chunk, and pass text an R chunk
prints through weft(). A cell with include: false or output: false publishes
nothing on the jupyter and julia engines."

**1.12.8** replaced: "A named value prints its value as the resolver where it
stands formats it: R in a knitr document's prose and resolved captions and in
a `weft()` string (1.12.12), the filter elsewhere. One name with one record
prints one text in every document and on every engine, for the classes the
filter implements (1.12.11, 2.13.3): `.val` and every number class print the
same from R and from the filter. R carries more than the filter: a `units`
quantity, a unit ladder, a dictionary entry and a project formatter print
only where R reads the name; where the filter resolves it they are a value
error. In a knitr document write names or R expressions as you prefer:
`` `x`{.num} `` and `` `r x`{.num} `` print the same, except for objects of R
itself (1.12.12). On the jupyter and julia engines and in plain markdown,
write names: no R evaluates an expression there."

**1.12.9**, the sentence "`unit` is a renderer key (1.12.1), and the filter
has no units, so a named value with it, or an `n`, `sign` or `list` span
with it, is a value error (2.13.3)." becomes "`unit` is a renderer key
(1.12.1). Where R reads the name it works as on an R value (4.4.23); the
filter has no units, so where the filter resolves a named value with it, or
an `n`, `sign` or `list` span with it, it is a value error (2.13.3)." The
sentence on `claim` and `level` keys adds: "whoever reads the name".

**1.12.10**, the last sentence becomes: "In a knitr document a span the hooks
resolve may refer to an id on a named value R read; a reference to an id on a
named value the hooks left for the filter is a "no value" failure that says
so. A span the filter resolves cannot refer to an id on an R value or on a
named value R read; that is a construct error found from the source."

**1.12.12** (new) **Where R runs, R reads the name.** In the prose of a
document the hooks resolve (2.13.13), including math, raw LaTeX, arms and
included text, in a caption the hooks resolve (2.3), and in a `weft()`
string (3.6), R reads a named value as `` `r NAME` `` with the same attribute
block would print: every formatter, units, the dictionary, project
formatters, the same failures, markers and ledger entry (kind `value`,
expression the name). The name is looked up from the knit's environment (the
chunk's for a caption, `.envir` for `weft()`), through its enclosing
environments as far as the global environment, never in base R, a namespace
or an attached package: so `pi`, `T`, `letters` and a dataset are not read
by name. A binding that is a function is not a value.

- In a `weft()` string a name that is not bound, or is a function, is a "no
  value" failure: "`%s` is not bound where weft() was called, so it has no
  value (rule 1.12.12)." or "`%s` is a function in R, not a value (rule
  1.12.12)."
- In a knitr document a name that is not bound where it stands, or is a
  function, is left as written for the filter (1.12.7), and the hooks
  publish it once R binds it (2.13.11). So is a name a guest published later
  than R last changed it (1.12.13).
- R never reads a named value in front matter, in a caption the hooks do not
  resolve (2.3.5), in text a chunk prints (1.12.14), or in a string given to
  Python's `weft_str()`, whose names are Python's: all of these are the
  filter's.
- When R reads a name above the code that sets it and finds a value the
  session held before the render began, and the document later assigns the
  name a new value, the use is a "no value" failure at the end of the knit:
  "`%s` was read above the code that sets it in this render, from a value
  the R session held before the render began (rule 1.12.12)." Its hint:
  "Render in a fresh R session, as quarto render and the Knit button do, or
  move the sentence below the code that sets it."

**1.12.13** (new) **R and another language.** In a knitr document, when
Python or Julia publishes a name (3.8.6 to 3.8.8) and R also binds it, the
later wins where the sentence stands: R's binding when its value changed
after the guest published, else the published value. A hand-written block
and a values file give a name its value only where R does not bind it. The
setting `names_from` (9.1.5) names where a knitr document's named values
come from: `r` (the default, the engine's language) as above; `python` or
`julia`, R reads no named value in prose or captions, and every one is
left for the filter, filled by what the guest publishes. `weft()` always
reads R. Governors (`if`, `n`, `sign`, `list`) are R expressions in a knitr
document under every value; read a Python value there with `py$`. In a
document that is not knit the setting has no effect.

**1.12.14** (new) **Text a chunk prints.** A named value or a span in text
that R code prints without `weft()` (`cat()`, a table cell, a `kable()`
caption) reaches Pandoc as markup. R does not read it and publishes nothing
for it, so the filter fails it "no value" unless the name is published
another way. Pass such text through `weft()`, which reads each name where
the call runs, once per line in a loop. Text a Python or Julia chunk prints
uses `put()` before it, in a chunk with `results: asis` (3.8.6).

**2.3.5**, last sentence: "A named value in such a caption is not an error:
the filter resolves it with the name's last published value (1.12.7), and R
does not read it (1.12.12)."

**2.13.2**, first sentence: "The filter resolves the named values the hooks
leave (1.12.12), every construct in a document that is not knit, and a span
that reaches Pandoc in a knit document still carrying a governor in the
grammar of 1.12.4."

**2.13.3**, "That covers units (...)" sentence, add before it: "R reads the
names of a knitr document's prose and resolved captions (1.12.12), so this
paragraph is about the names the filter resolves."

**2.13.11** replaced: "In a knit, the hooks publish what the filter will
resolve and nothing else. Under `names_from: r` their list is: the name of
each named value in front matter; the name of each named value, and each
name in a governor value of 1.12.4 to 1.12.6, in a caption the hooks do not
resolve (2.3.5); and each name the hooks left for the filter because R did
not bind it where it stood or bound a function (1.12.12), from that point
on. A name in the governor of a span in prose, a named value R read, and
anything written only in a chunk's code are never on it. At the start of
each block of prose and at the end of the document, the hooks publish each
listed name that R binds in the knit's environment (1.12.12's walk) and
whose binding changed since the name's last publication by anyone, or that
was never published; a function is published as an error record. Python's
`put()` and `auto()` and Julia's `put` and `@put` publish under knitr as
3.8.7 and 3.8.8 say; the hooks note each such publication with R's binding
at that moment, which decides 1.12.13. Under `names_from: python` or
`julia` the hooks publish nothing themselves. There is no gate under knitr:
a document with no named value and no span in an unresolved caption writes
no block. A value that cannot be published is published as an error record,
so the failure shows where the name is used."

**2.13.14**, second sentence: "R values always have the resolver `hooks`, and
so does a named value in prose, in a resolved caption and in a `weft()`
string of a knitr document under `names_from: r`; a named value in front
matter, in an unresolved caption or under `names_from: python` or `julia`
has `filter`."

**3.6.2** (E1's, joining WS2 to WS4): the WS4 part becomes "A named value is
read from `.envir` (1.12.12); a name not bound there, or bound to a
function, is a "no value" failure."

**3.6.8** (E1's), add: "A named value in its markup is left for the filter:
in a Python chunk a name is Python's, published by `put()` or `auto()`."

**§3.8** replaced (numbers kept, since other rules cite 3.8.4 to 3.8.9):

> **3.8.1** In R a named value is read where R runs (1.12.12): R has no
> function that publishes into a knit. The hooks publish what the filter
> needs by themselves (2.13.11). A pipeline writes a values file with
> `weft_values_write()` (3.8.5).
>
> **3.8.2** An argument of `weft_values_write()` that is a call of
> `claim()` is captured before evaluation: its first argument is the value,
> its checks are run as `claim()` runs them, the value's record carries a
> check object for each, and nothing is stopped. The check counts where the
> name is used (2.13.4). In a knitr document a check that should count
> where a value is used is written there: `` `r claim(x, . < 50)`{.num} ``,
> or a guard span.
>
> **3.8.3** In a knit, what the hooks publish (2.13.11), and what Python and
> Julia publish there, is written as one block, at the start of the next
> block of prose or at the end of the document. A Python `put()` in a chunk
> with `results = "asis"` prints its block into the chunk's output at once.
>
> **3.8.4** [unchanged: an R value becomes a record]
>
> **3.8.5** `weft_values_write(path, ...)` writes a values file (2.13.10).
> Each argument after `path` writes one name: `n = nrow(d)`, or a variable,
> `n`, under its own name. Any other unnamed argument, a name that is not a
> name (1.12.1), and a name given twice are errors: "weft_values_write()
> takes named arguments or names after the path: weft_values_write(path, n =
> nrow(d)) or weft_values_write(path, n) (rule 3.8.5)." and "`%s` is given
> twice in one weft_values_write() call." `lang` is `r`, `run` is read as
> 2.13.8 says, `at` is now. The file is UTF-8 with `\n` line ends, written
> atomically; nothing is written when an argument is refused. It returns
> `path` invisibly, and works outside a knit and in a `targets` pipeline.
>
> **3.8.6** [unchanged]
>
> **3.8.7** [unchanged, except the knitr sentences]: "Under a knit, `put()`
> and `auto()` in a Python chunk hand their records to the hooks (3.8.3), and
> nothing is printed in the chunk except by `put()` with `results = "asis"`;
> `auto()` there publishes, at the end of each Python chunk, the names R
> gives it that are bound in Python's `__main__` and changed: the name of
> every named value in the source, and each name in a governor value of
> 1.12.4 to 1.12.6 in a Python or Julia chunk's code or in a chunk's
> options. The gate of the jupyter engine does not apply under a knit."
>
> **3.8.8** [unchanged]
>
> **3.8.9** Known gaps. Julia has no `auto()`. On the jupyter engine,
> `auto()` cannot tell that a hidden cell's output was dropped (2.13.12).
> There is no `checked()` that makes a claim from Python or Julia count where
> the name is used (3.9). In a knitr document R's binding counts as later
> than a guest's publication only when its value changed (1.12.13). R does
> not read a named value in a Python `weft_str()` string.

**3.10.8** and **3.10.16**: drop `weft_put()` from "Not counted" and from the
list of misses ("a value published only by `weft_put()`").

**5.1.1**, the list of contexts is E1's; no change.

**5.12**: the table gains a row `| 3 | string-markup | markup in an R string
that does not go through weft() | 2 |`. Rule 1's message becomes the two
texts of ST5, and its sentence "Its hint also says that a governor name in a
document with no named value is not published automatically (2.13.11)" is
removed; "It reads every named value, whoever reads it at render, and the
names in the governor of a span the filter resolves." New bullet:

> - Rule 3: in a document the hooks resolve with `names_from: r`, a string
>   constant in the code of an executed R chunk, not inside the `x` argument
>   of `weft()` or `weft::weft()`, whose content holds a named value or a
>   span with an `n`, `if`, `sign` or `list` key. One finding per string, at
>   the string. Message: "This string holds weft markup (`{construct}`) but
>   is not given to weft(), so R does not read its names and the filter has
>   no value for them (rule 5.12.3)." Hint: "Give the string to weft() and
>   print the object (a chunk that prints a weft object writes its
>   markdown), or cat(format(weft(\"...\"), target = \"markdown\"))." It is
>   tier 2 because a string kept in a variable and given to `weft()` later
>   is read as one that is not; the render fails anyway (1.12.14).

The last bullet's sentence "named rows are `filter` always" becomes "named
rows are `hooks` or `filter` as 2.13.14 says; the `engine` rule reads a
named value as needing no R whatever its column."

**9.1.2**, table row added: "| `names_from`: where a knitr document's named
values come from | 1.12.13 |".

**9.1.5**, YAML line added after `chunk_claims`:
`names_from: null       # 1.12.13: r, python or julia; null is the engine's language (r under knitr)`,
and to the paragraph of `weft_config_error`s: "The setting `names_from`
must be r, python or julia." The filter does not read it.

### Part 2 (rationale)

**1.12.8** A named value is R's where R runs because the same text must not
print one way in a sentence and another in `` `r ` `` beside it, and an R
author should not lose units by writing a name. The rule says what still
holds across resolvers, one record one text, instead of a sameness that a
`units` value breaks.

**1.12.12** The walk stops at the global environment because a named value is
the document's: base R's `pi` or a dataset's `rivers` would otherwise
answer for a name the document sets further down. A function is not a value,
so Python's `max` or a name used above its value is not shadowed by an R
function of the same name. `weft()` fails on an unbound name, not leaves it,
because its text goes to plots and consoles where no filter runs. Front
matter is the filter's because it is read before any chunk runs, where R's
binding is missing or left from an earlier session; decision 71 already gave
it the document's last value. A session value read above the code that
replaces it is a failure, as 1.12.7 makes several values one, because it
prints a value the sentence does not mean.

**1.12.13** "Later replaces" across languages is decided by R's binding at the
guest's publication, so that a scratch name reused in R and Python takes the
value written last, without an error that such reuse would raise often.
Governors stay R under every setting, because the scanner decides from the
source alone which resolver owns a span.

**1.12.14** Text a chunk prints never passes the hooks, and a value published
for it is published once for a loop that prints many lines; `weft()` reads
the value at each call. Publishing nothing makes the mistake fail loudly
rather than print one value for every line.

**2.13.11** The hooks publish only names the filter will resolve, because a
block persists in `_freeze`, keep-md output and notebooks: with the old list,
`if="nchar(secret) > 0"` wrote the secret into it. The gate is gone because
the narrower list already keeps a document without named values from writing
a block.

**3.8.1, 3.8.2** `weft_put()` went because R now reads names itself and its
remaining use, text a chunk prints, is `weft()`'s. `weft_values_write()`
keeps `claim()` capture because a values file feeds documents that run no R,
where a check carried on the value is the only use-site check.

**5.12.3** Tier 2, as `named-unpublished`, because a token search cannot
follow a string through a variable, and the render fails loudly anyway.

## Documentation

- **`vignettes/named-values.Rmd`**:
  - Opening paragraph: the article is also for knitr authors: "In a knitr
    document a name reads R, as `` `r x` `` does; elsewhere code publishes
    it."
  - "When to write a name" (`:67-78`) rewritten: knitr, names or R
    expressions as you like (1.12.8), names for a value used above its code
    and in front matter; the other engines, names always.
  - "Publishing from R" (`:80-153`) replaced by "Names in a knitr document":
    R reads them (one example, the same as today's with no publishing
    talk); the walk stops at the global environment (`pi`, datasets);
    a function is not a value; front matter and unresolved captions take the
    last published value; the hooks publish what the filter needs, never a
    prose governor; `weft_values_write()` for pipelines; the named-vector
    example moves to the values-file section.
  - "Text a chunk prints" (`:155-194`): `weft()` for R (the loop example of
    T5); `put()` then print for Python; a printed name in R without
    `weft()` fails "no value" and the `string-markup` lint finds it.
  - "Checks" (`:502-553`): drop `weft_put(x = claim(...))`; R's use-site
    checks are `` `r claim(x, . < 50)`{.num} `` or a guard;
    `weft_values_write()` with `claim()` for a values file.
  - "A name used above its value" (`:459-500`): the mechanism is now "R
    does not bind it there, so the filter takes it from below"; the trap
    paragraph (`:495-500`) becomes: "If you render with
    `rmarkdown::render()` in a session that still holds an old `n_sites`, R
    reads that old value above the chunk. When the document sets
    `n_sites` again below, weft fails the render and says so; render in a
    fresh session."
  - "The traps" (`:588-616`): the hint text M6.
  - "Captions and front matter" (`:654-664`): resolved captions read R;
    other captions and all front matter take the last published value.
  - A short section "R and Python in one knitr document": later replaces
    (1.12.13), `names_from`, governors stay R.
  - "The lints" (`:712-739`): `named-unpublished` row "set it in an R chunk,
    or publish it with `put()` or `@put`"; new row `string-markup`.
  - "Limits" (`:741-768`): "Units, the dictionary and project formatters stay
    in R" becomes "...work only where R reads the name"; add D4's cost and
    BN8.
- **`vignettes/languages.Rmd`**: the Python `weft_str()` section
  (`:322-345`): one sentence that a named value in its markup is Python's,
  published by `put()`; the module paragraph (`:313-322`) unchanged; a
  pointer to the new named-values section for mixed documents.
- **`README.md:104-109`**: "Values by name. In a knitr document a name such
  as `` `depth`{.num} `` reads R, as `` `r depth` `` does. A document that is
  not knit, such as a Quarto `.qmd` on the Jupyter or Julia engine, has no R:
  publish the value from Python (`put()`), Julia (`@put`) or a pipeline's
  values file (`weft_values_write()`), and a Pandoc filter fills it in. ..."
- **`inst/agent/references/syntax.md:79-92`** and
  **`skills/weft/references/syntax.md`** (the same text without the
  `weft-file` line): "## Named values" becomes: "In a knitr document a name
  in the inline block reads R: `` `worst`{.num} `` prints what
  `` `r worst`{.num} `` prints. In a document that is not knit, code
  publishes it: `put()` in Python, `@put` in Julia. Text an R chunk prints
  goes through `weft()`." with the one markdown example kept and the
  `weft_put()` block removed.
- **R docs**: `weft_values_write()`'s roxygen describes its arguments itself
  (no "as for `weft_put()`"), `@seealso` drops `weft_put()`; `weft()`'s
  roxygen (E1) says a named value is read from `.envir`; `man/weft_put.Rd`
  goes; `NAMESPACE` by roxygen; `_pkgdown.yml` drops `weft_put`.
- **`NEWS.md`**: named values read R in knitr prose, captions and `weft()`;
  `weft_put()` removed; the publisher lists only what the filter resolves;
  `names_from`; the `string-markup` lint.
- **`inst/quarto/weft.lua:332-336`**: the hint M6.

## Order of work

1. Test-writer: `e2_render()` and `b6_rec()` in `helper-6b.R`, T1 to T13,
   the migrations above. Check the new tests fail for the right reason (a
   named value left in md; `values_block` not found; `names_from` not
   validated; no `string-markup` rule) and that the migrated ones fail only
   where E2 changes behaviour.
2. Implementer, the suite run after each step:
   1. `names_from` in `read_config()` (M9) and in the scanner's resolver
      column (ST1, ST2).
   2. The lookup (BN2) and a `named` branch in `render_item0()` that reads
      the value and formats it as `render_value()` does (BN3), with `.val`
      from the record (BN4), ids (BN10), ledger (BN12), the fast path of
      `resolve_string()`, `weft()`'s failures (BN9) and Python's leave
      option (BN8).
   3. Captions (BN1, D6) and front matter (BN6).
   4. The state's per-name publication record and snapshots; guest notes in
      `guest_knitr_put()` (asis too), `julia_take_puts()` and `auto()`
      fetched in `guest_chunk_end()` (BN7, TR3, TR4).
   5. R's list and publishing (TR1, TR2); the gate removed from
      `values_names()`; the left set.
   6. The binding-from-before check (BN11).
   7. `weft_put()` removed, `values_block()`, M7 and M8, the inline
      function names, the filter's hint (M6).
   8. Lints: `named-unpublished` (ST5) and `string-markup` (ST6).
   9. Roxygen, `devtools::document()`, the documentation above.
3. Whole suite (one R process), opus review, fixes, then the spec editor
   applies the rule edits.

## For Robin

1. **`pi`, `T`, `letters` and datasets are not read by name** (D1). The rest
   of R agrees with `` `r x` ``, but a name never reaches past the global
   environment, so `` `pi`{.num} `` with nothing published fails where
   `` `r pi`{.num} `` prints 3.1. The alternative, reading everything R
   reads, lets base R and datasets answer for a name the document sets
   further down.
2. **A name in text an R chunk prints, outside `weft()`, now fails** (D9):
   R publishes nothing for it, so a printed sentence that worked because
   its value never changed now needs `weft()`. A tier-2 lint finds it.
3. **A session value read above the code that resets it fails the render**
   (D15), where today it prints the old value with only an article warning.

## Rulings by the orchestrator on "For Robin" (25 Nov)

Robin delegated these. All three stand as the note proposes.

1. **Base R names are not read by name** (`pi`, `T`, `letters`,
   datasets). Lookup stops at the global environment. Alternative: follow
   R's full search path, so `` `x` `` and `` `r x` `` agree everywhere;
   refused, because a prose name that happens to match a base object
   (`T`, `c`, `df`) would print it silently instead of failing as
   unbound. Write `` `r pi` `` for those.
2. **A named value in text an R chunk prints without `weft()` fails with
   "no value".** Alternative: keep publishing it for the filter; refused,
   since that is the loop case that printed an earlier value silently. The
   failure's hint names `weft()`.
3. **The stale-session case is a render failure.** Alternative: a warning;
   refused for the reason of 1.12.7's rationale: a warning would print a
   value the sentence may not mean.
