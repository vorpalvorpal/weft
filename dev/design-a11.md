# A11: one wording for the class and key checks

Ruling (owner): the mistakes in a construct's attribute block that the scanner
(`R/scan.R`, `block_errors()`) and the formatter at render (`R/format.R`,
`apply_formatters()` and what it calls) both detect get one text, and it is the
scanner's. Only the render-time texts change. What is an error, when, its
condition class and where it is reported do not change. Messages only one side
can produce stay as they are. The scanner's text is adopted for every pair
below except the one marked NEEDS RULING.

Tests: `tests/testthat/test-a11-wording.R` (table-driven, one case per row
marked "yes" under Tested). The knit path (`R/resolve.R`) already reports the
scanner's text, since it returns `R$error` (`resolve.R:1280`); the render-time
texts are reached through `apply_formatters()` and the `fmt_*()` functions
called directly. `resolve.R` writes no class or key check of its own that the
scanner also makes (its `lang_check()`, 1.6.8, has no scanner twin).

## Pairs

"Differ" is the state before the change. Line numbers are at the commit this
file was written on.

| # | Rule | Scanner text (`scan.R`) | Render text (`format.R`) | Differ | Lua (`weft.lua`) | Existing tests pinning the render text | Tested |
|---|------|-------------------------|--------------------------|--------|------------------|----------------------------------------|--------|
| 1 | 1.4.2 two classes of one group (number, wording, collapse, project stage) | `Two classes from one group in one block: %s (rule 1.4.2).` (:974) | `Two classes from one group (%s) in one construct: %s (rule 1.4.2).` (:783; `%s` the group name, then the classes) | yes | same as the scanner (`weft.lua:734`) | none by text; `test-filter-classes.R:86,138`, `test-collapse.R:131`, `test-collected.R:182-183` pin the class only | yes (3 cases) |
| 2 | 1.4.2 two unit classes | `Two unit classes in one block: %s (rule 1.4.2).` (:972) | the row 1 text with group `unit` (:783) | yes | row 1 text (`weft.lua:734`) | none | yes |
| 3 | 1.4.7 `digits` with `sigfig` | `` `digits` with `sigfig` is an error (rule 1.4.7). `` (:993) | `` `digits` and `sigfig` together are an error (rule 1.4.7). `` (:789) | yes | the render text (`weft.lua:761`); no test ties it | none by text; `test-lint-named.R:124` pins the scanner's; `test-filter-values.R:135` the class only | yes |
| 4 | 1.4.7 `digits` or `sigfig` on `.date` | `` `digits` and `sigfig` do not apply to `.date` (rule 1.4.7). `` (:1009) | `` `digits` and `sigfig` do not apply to `.date`. `` (:802; no rule) | yes (the rule citation) | the render text (`weft.lua:764`) | `test-p-digits.R:243` (exact); `test-lua-p.R:145` ties the Lua text to the same string | yes (digits and sigfig) |
| 5 | 1.4.17 `sigfig` on `.p` | `` `sigfig` does not apply to `.p`; use `digits` (rule 1.4.17). `` (:1012) | same (:806) | no | not checked | none by text | yes (a pin) |
| 6 | 1.4.17 `digits` of `.p` out of 1 to 6 | `p_digits_value()` (:1015) | `p_digits_value()` (:808; text at :454) | no, one function | not checked | `test-p-digits.R` (the function) | yes (a pin) |
| 7 | 1.4.17 `label` without `.p` | `` `label` applies to `.p` only (rule 1.4.17). `` (:1020) | same (:811) | no | not checked | none by text | yes (a pin) |
| 8 | 1.4.21 `.plus` with a class that prints a number itself | `` `.plus` cannot go with `%s`: it signs a number that `.num` or `.pct` prints (rule 1.4.21). `` (:1026) | same (:816) | no | same, written `.%s` (`weft.lua:710`) | none by text | yes (a pin) |
| 9 | 1.4.19 `.usym` with a class that spells a number | `` The unit class `.usym` with `%s` is an error: a spelled number takes the unit's name (rule 1.4.19). `` (:984) | `` `.usym` with `%s` is an error: a spelled number takes the unit's name, and "five m" is not written (rule 1.4.19). `` (:825) | yes | none | none by text | yes |
| 10 | 1.4.14 `none` with `.range` | `` The key `none` does not apply to `.range`: a range has two ends (stage 1h). `` (:1051) | `` `none` does not apply to `.range`: a range has two ends (rule 1.4.14). `` (:757) | yes | the render text (`weft.lua:791`) | `test-review-f.R:212` (class only) | yes |
| 11 | 1.4.14 `none` empty | `` The key `none` is empty; give the text to print for an empty value (stage 1h). `` (:1053) | `` `none` must be one string that is not empty or only spaces (rule 1.4.14). `` (:753-755) | yes | the render text (`weft.lua:794`) | `test-filter-classes.R:171` (class only) | yes (empty string) |
| 12 | 4.4.23 a ladder in `unit` with a problem (empty or repeated rung) | `ladder_split(uv)$problem` (:891) | `ladder_split()$problem` through `construct_error()` (`units.R:293`) | no, one function | not in Lua | `test-unit-ladder.R` | yes (repeated rung, a pin) |
| 13 | 1.4.22 a project class's key or option | `project_key_errors()` (:919) | `project_key_errors()` (:796, first message only) and `project_args()` (:1319-1336) | no, one function | none | `test-formatter-options.R:75-76,405-420` (M8, M9) | no: identical by construction, pinned by M8 and M9 |
| 14 | 5.2.6 / 3.4.11 a class with no TeX form | in math or raw LaTeX: `` `%s` cannot be used inside %s: it prints words, and a formula holds numbers. Move the value out of the %s, or use a number class such as `.num` (rule 5.2.6). `` and the emphasis and list variants (`tex_block_errors()`, :336-348) | `` `%s` has no TeX form (target = "tex"): %s (rule 3.4.11). `` (`tex.R:34`, `tex_class_check()`, called at `format.R:673`) | yes | the scanner's texts (`test-filter-math.R:567`, `fm_e95` to `fm_e97`, ties Lua to the scanner) | `test-tex-target.R:37,146` (exact) | NEEDS RULING, not tested |

Rows 6, 12 and 13 are one function on both sides: nothing to change.

## Adopted text, row by row

For every row but 14 the render side builds the scanner's text, filled from
what it holds at render: the classes and keys, in the order the scanner uses
(`unique(classes)`, then the first of the clashing ones). Notes for the
implementer:

* Rows 1 and 2: the render side loses the group name. The `unit` group takes
  the row 2 text ("Two unit classes in one block: ..."); every other group
  takes the row 1 text. The classes are joined with a space.
* Row 3: the scanner's text is for `digits` and `sigfig` together; the render
  check is the same condition.
* Row 4: one text for `digits` or `sigfig`; add the rule citation. The render
  check runs after row 3's, so `digits` with `sigfig` on `.date` reports row 3.
* Row 9: the "five m" clause goes.
* Rows 10 and 11: the citation becomes "(stage 1h)", as the scanner writes it,
  and "The key" begins the text. At render one branch catches both an empty
  string and a `none` that is not one string (a number, a vector, `NA`). The
  scanner can only see a written value, so it never reports the second kind;
  that message stays as it is ("must be one string ...") and only the
  empty-string case takes the scanner's text. The code branch must be split.
* Row 11: the render side tests `trimws(nn)`; the scanner `trim_ws()`. Both
  reject a value of spaces only.

## NEEDS RULING: row 14, a class with no TeX form

The scanner's text names a place ("math" or "raw LaTeX") and tells the author
to move the value out of it. The render side is `target = "tex"` and does not
know whether it was called for a formula or for raw LaTeX, nor that there is a
construct to move (`fmt_word(x, target = "tex")` is a function call). The
scanner's text cannot be used verbatim.

Closest text, per class kind, with the place written as "a formula":

* words: `` `%s` cannot be used inside a formula: it prints words, and a formula holds numbers. Move the value out of the formula, or use a number class such as `.num` (rule 5.2.6). ``
* emphasis: `` `%s` cannot be used inside a formula: it is markdown emphasis, and a formula is TeX. Put \mathbf{} or \mathit{} around the value in the formula (rule 5.2.6). ``
* lists: `` `%s` cannot be used inside a formula: it joins items into a phrase or a list. Use `.range` for two ends, or move the value out of the formula (rule 5.2.6). ``

Alternative: leave the render text as it is (it is a different mistake, "a
function was asked for a TeX form it has not got", and the place is not the
source's). The Lua text follows the scanner's, so Lua parity favours the first.
`test-tex-target.R:37,146` pins today's text.

## Messages with no twin

Scanner only: the parse errors of the block (1.2.3, 1.2.9), single quote and
`\` in a value (1.2.3), a bare `|` in a table cell (1.5.13), a key written
twice (1.2.10), the `claim` and `level` keys on a named value or a span the
filter resolves (5.3.3; Lua writes the same text, `check_key_error`), a
governor key on a value or a named value (1.3.3; Lua `E9`), two governors
(1.1.5), two ids (1.7.5), a text class or `trunc` with a block class (1.4.6),
`level` on `n`, `sign` or `list` and on a guard, a block class on a `list`
span (1.5.19), an `#id` on a text, cite or `list` span, `.val` with a wording
class (1.12.2; Lua `E2`), a unit class on `if` and `cite` spans (1.4.19), a
formatter or renderer key on an `if` or `cite` span (1.5.7, 1.8.7), `.plus`
with a governor (1.4.21; Lua writes it), `sign="."` and `list="."`, `none`
anywhere but on a value with a collapse class (stage 1h; Lua checks the
collapse class at `weft.lua:788`), `decision` and `why` (1.8.10, 1.8.12), cite
values (1.8.4, 1.8.5), the TeX placement errors of math (5.2.6), the filter's
condition and governor grammar (1.12.4, 1.12.6).

Render only: `.pct` or `.sci` with a wording class (1.4.1), `trunc` below 1,
`.sci` with a ladder, the `lang` checks (1.6.8), the unit-form checks (4.4.15,
4.4.19, 4.4.22), a phrase result given a format (1.4.1, 1.4.12), the value
errors on the data, `target` not markdown or tex (E100).

Lua: row 14's Lua twin, and every Lua text in the table that is not the
scanner's (rows 3, 4, 10 and 11 are the render text today), move in the later
Lua parity step. Of these, only row 4 is tied to an R text by an existing test
(`test-lua-p.R:145`, against the text `test-p-digits.R:243` pins); changing
row 4's R text breaks `test-lua-p.R:145` until Lua follows.
