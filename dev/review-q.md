# Review of package Q (loosened quoting), 2026-11-26

Independent review (opus) of 57d62fa..fa47999 and 4dd02de against
`dev/design-quoting.md`. R not run by the reviewer; Pandoc 3.8.3 probes.
Rulings by the orchestrator (authority delegated by Robin) follow each
finding.

## Findings and rulings

**R1. Bug. The writer re-quotes a bare value holding a character
reference, and Pandoc then decodes it.** `attr_markup` (R/resolve.R:260):
`` `r 1.2`{.num title=R&amp;D} `` is written `[1.2]{title="R&amp;D"}`,
which Pandoc reads as `R&D`; C1 read it as `R&amp;D`.
*Ruling:* extend M3 (the character-reference error) to bare values. A
`&name;`, `&#n;` or `&#xh;` in any value is a construct error.
Alternatives: write bare values back bare (fails when the value needs
quoting for another reason); encode `&` as `&amp;` on write (makes the
written block differ from what the author typed and still diverges in
other writers). Refusing is symmetric with the quoted case and safe under
D1.

**R2. Bug. A quoted value that runs over a line break inside a block
quote or list item is read differently from Pandoc.** `read_quoted_value`
(R/scan.R:548-580) and `read_value` (inst/quarto/weftlib/lines.lua:144)
keep the `>` and the indent; Pandoc strips them. `> [a | b]{if="x >⏎> 1"}`
evaluates `x > > 1`.
*Ruling:* (a) a line break and the white space after it read as one
space, in every reader (Pandoc's reading in a paragraph and a list item);
(b) a quoted value in a block quote (the span's line starts, after
indentation, with `>`) may not cross a line break: construct error
"a quoted value in a block quote must fit on one line". Alternative:
strip block-quote markers by nesting depth; refused, because the scanner
works on raw lines without block structure, and an error never misreads
(D1). (b) also removes the `S$plim` difference for `>`-only lines.

**R3. Gap. A quoted value that starts with white space is accepted for
keys D12 does not cover; Pandoc turns the block into text.** Includes a
no-break space after the opening quote, where Pandoc falls back to a bare
value that keeps the quotes.
*Ruling:* a quoted value whose first character is any Unicode white space
(including U+00A0) is a construct error for every key, in documents and
strings alike, in every reader that reports construct errors. Alternative:
keep D12's governor-only, filter-only check; refused because it leaves
blocks that Pandoc prints as text accepted silently.

**R4. Nit. M4 names the wrong cause for the commonest apostrophe
mistake.** `{why='the sites' own rule'}` gives cause `other`.
*Ruling:* when a quoted value closes and the next token is neither a
`key=value`, `.class`, `#id` nor `}`, the cause is the quote cause of
that quote character, with D4's hint. A value that ends in `\"` or `\'`
followed by an unclosed value gets the hint "the closing quote is
escaped".

**R5. Nit (regression). `strip_quoted` in weft-check.lua swallows the
rest of the block at an unbalanced quote** (`title=it's digits=2` hides
`digits=`). *Ruling:* open a quote only directly after `=`, as
`block_end()` does.

**R6. Gap (pre-existing). The pre-render script's `span_bad` finds a
governor key inside another key's quoted value**
(inst/quarto/weft-pre-render.R:171): `[x]{.weft-literal why='n=3 sites'}`
stops a document without `engine: knitr`. *Ruling:* strip quoted values
(escape-aware) before matching governor keys.

**R7. Nit. C8's `read_value` departs from Pandoc on two escapes**
(lines.lua:154-160): a backslash before a non-ASCII letter, and before a
line break. *Ruling:* follow Pandoc: a backslash escapes only a
non-alphanumeric character (Unicode letters and digits keep the
backslash); a backslash before a line break stays a backslash and the
break reads as a space. Correct the wording of C8.

**R8. Test gaps.** Tests to add with the fixes: `span_bad` with single-
quoted, bare and `\|` governors and a governor key inside a quoted value;
`strip_quoted`; writer round trips for `&` and a leading space; block-
quote and list-item cases in T1, T3 and T7; the T3 Pandoc driver pins
Pandoc's reading of `"a\db"` (`a\db`) and `"R&amp;D"` (`R&D`), on which
M1 and M3 rely.

## Checked and consistent (reviewer)

Quoted and bare value extent against Pandoc (including `\}` bare); `""`
and `''` followed by more attributes; `\|` in pipe-table cells; the order
of errors and one message per kind; condition quote state in cond.lua,
its R mirror and the pre-render script; the left-to-right literal strip
in R and Python; the governor-value regexes in R and Python; escapes in
`attr_markup`, `attr_shown` and Lua's `shown_value`; the `find_attr`
cursor; `values_file_attr` and the cite fallback decode.
