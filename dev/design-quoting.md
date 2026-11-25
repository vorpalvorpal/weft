# Package Q: attribute quoting loosened everywhere (25 Nov)

Contract for the test-writer and the implementer. The adversarial review this
answers is in the scratchpad (`review/report.md`, verdict "do it, with these
changes"); its findings are cited as F1 to F10. Pandoc facts marked [ran] were
run with Pandoc 3.8.3 (`/opt/homebrew/bin/pandoc`) for this note or by the
review. Line numbers are at `94f1cf2`.

## Why

Rule 1.2.3 allows a value only in double quotes, or bare with nothing to
unescape. An R string inside a value must then take single quotes, an
apostrophe in a `why` cannot be written, and markup inside an R string has no
quote left to wrap it (`dev/field-notes.md` lines 141 and 438;
`dev/current-state.md`, "Quoting"). Pandoc reads double, single and bare
values, and its writer, so the visual editor, rewrites every value to double
quotes with `\"` (§18). weft now reads all three forms, in documents and in
strings alike, as a strict subset of Pandoc's reading.

## Decisions

Taken by the author (not reopened here):

- **D1. weft's reading is a strict subset of Pandoc's.** Every block weft
  accepts means the same to Pandoc. Accepted: double-quoted, single-quoted and
  bare values. In a quoted value `\"`, `\'` and `\|` stand for `"`, `'` and
  `|`, in every key. Any other `\` in a value stays a construct error with the
  hint to bind the expression to a name. A quote or `\` in a bare value stays
  an error (F4). *Why:* the hooks, the lints and `weft_str()` read source text
  before Pandoc does, and the filter reads Pandoc's tree; a block read two ways
  would mean two things in one project. Pandoc's reading is wider (F3): a `\`
  escapes any character that is not a letter or digit, character references
  are decoded, and a bare value may hold quotes. None of that is needed to
  write an expression or a reason, and a refusal is loud where a misreading is
  silent.
- **D2. The filter's condition grammar (1.12.4) takes double-quoted string
  literals as well as single-quoted ones**, in `cond.lua`, its R mirror and
  the pre-render script. *Why:* without it `{if='tier == "sev"'}` resolves
  under the hooks and is a construct error under the filter (F6); one sentence
  must work on both resolvers.
- **D3. No canonical-form fixer and no normalising lint.** An editor's
  requote is a spelling change only. *Why:* the decoded value is the same,
  and the ledger and `changes()` key on it (`expr_key()` gives one key for
  `tier == 'sev'` and `tier == "sev"`, [ran]).
- **D4. `why`, `decision` and `label` join the 1.2.9 broken-block
  detection.** *Why:* `why='it's fine'` is not a span to Pandoc (F5), and
  today it prints as text with no error. Rule 1.2.5 already lists all three as
  weft's; the scanner's list (`WEFT_KEYS`, `R/scan.R:10`) left them out.
- **D5. weft escapes what it writes.** Every attribute value weft writes back
  as markup (pass-through spans, literal spans and divs) is double-quoted with
  `\` written `\\` and `"` written `\"` (F2). See D9 for `|`.

Taken here, under delegation:

- **D6. Character references are refused, line breaks are decoded.** In a
  quoted value, `&` that begins a character reference (`&name;`, `&#digits;`,
  `&#xhex;`) is a construct error; a line break reads as one space, as Pandoc
  reads it [ran]. *Alternative:* decode references as Pandoc does. Refused:
  every reader (R scanner, R and Python name extractors, the pre-render
  script, the Lua line search) would need Pandoc's HTML entity table, and no
  expression or reason needs one. Refusing is safe under D1 (a refused block
  means nothing). *Cost:* a block that holds `&quot;` or `&amp;` in a quoted
  value is valid today and becomes an error; §18 records `&quot;` as the old
  workaround for a `"` in a cite prefix, which `\"` or single quotes now
  replace. No vignette, test or field note uses one. A bare value is not
  decoded by Pandoc [ran], so `&amp;` in a bare value is read literally by
  both and accepted. *Line breaks:* refusing them was the alternative; refused
  because an editor's hard re-wrap can put one inside a long `why`, and the
  decoded reading is exactly Pandoc's.
- **D7. `\|` is read in a bare value too** (`{unit=mm\|m}`). D1 says "a quote
  or backslash inside an unquoted value stays an error"; today a bare
  `unit=mm\|m` is accepted (`R/scan.R:524-528` unescapes it), and Pandoc reads
  `\|` as `|` in a bare value [ran]. F4's hazard (YAML's `\"`) does not arise:
  `\|` is not a YAML escape, so a YAML double-quoted scalar holding it fails
  in YAML itself. *Alternative:* make it an error; refused, since it breaks a
  block valid today for no safety gain.
- **D8. An unescaped `|` in any value of a construct in a pipe-table cell is
  the 1.5.13 error**, not only in `unit`. *Why:* Pandoc's pipe-table reader
  splits the row at a `|` inside an attribute block (rationale 1.5.13), and
  now that `\|` reads as `|` in every value there is a way to write one.
  *Cost:* `| [a \| b]{if="p || q"} |` resolved under the hooks today (it was
  already broken for the visual editor and Pandoc-read lints) and is now an
  error. *Alternative:* keep the check on `unit` only.
- **D9. weft also writes `|` as `\|` in a value it writes as markup.** *Why:*
  a pass-through value decoded from `title="a\|b"` in a table cell would
  otherwise be written back with a bare `|` and split the cell. Pandoc reads
  `\|` as `|` in any quoted value, so it is harmless elsewhere. Reports and
  listings (D13) do not escape `|`.
- **D10. A closing quote glued to what follows stays an error.** Pandoc reads
  `{n="k".word}` and `{n="k"#id}` [ran]; weft keeps requiring a space or `}`
  after a closing quote (today's behaviour). Safe under D1.
- **D11. Broken-block messages give the fix, not the bind hint.** A quote that
  ends a value early is now fixed by `\"` or the other quote, so that message
  says so. The bind hint stays on the backslash error (D1).
- **D12. The 1.12.6 leading-space check runs on single-quoted values.** It was
  skipped when the single-quote error was present (`R/scan.R:1703-1704`); that
  error is gone. `{if=' ok'}` is not a span to Pandoc [ran], so in a document
  the filter resolves it is the 1.12.6 error, as `{if=" ok"}` is. In a
  document the hooks resolve both stay accepted (review-6 #2, unchanged).
- **D13. Listings show a value double-quoted with `\` and `"` escaped**: the
  arm tree (`R/arms.R:178`), `print.weft_rehearsal` (`R/rehearse.R:318`), the
  decisions listing (`R/constructs.R:196`), the unknown-key failure
  (`R/resolve.R:1183`), and the Lua report's `shown_attrs()` and
  `shown_span()`. A shown value can then be pasted back.
- **D14. The gate's raw-text keys are not normalised (F8).** The removed
  listing (`R/gate.R:490`) and the finding text of `construct`,
  `above-setup` and `block-start` are cut from the source, so a requote of a
  construct that is already in error re-keys its finding. Counts of
  constructs do not change with a requote. Normalising would need a canonical
  writer, which D3 refuses; the same already happens for `{n=k}` to `{n="k"}`.
- **D15. A filter condition's ledger key keeps its literals' quotes.** The
  filter keys a span by its decoded condition with spaces collapsed
  (`expr_key(unparsed = TRUE)`), so an editor's requote of the *attribute*
  changes nothing, while an author who changes `'sev'` to `"sev"` *inside*
  the condition changes the key. That is an author's edit and shows as one.
- **D16. Link blocks and stray `]` are left as they are.** The link check
  (`R/scan.R:1630`) already flags any block that does not parse and holds a
  detection key, so a broken `why` after a link is now flagged with the link
  message; `handle_stray_close()` (`R/scan.R:1353-1356`) still counts only
  `WEFT_KEYS`. Neither is pinned by a new test.

## The contract

### C1. A value as weft reads it

A value follows `KEY=` with no space on either side of `=`. Three forms:

- **Double-quoted:** from `"` to the next `"` that is not escaped.
- **Single-quoted:** the same with `'`.
- **Bare:** one or more characters up to white space or `}`.

For the *extent* (where the value and the block end), a `\` and the character
after it are taken as a pair in all three forms, as Pandoc takes them: `\"`
does not close a double-quoted value, `\}` does not end a bare value. A
quoted value may run across a line break but not a blank line (the
paragraph's end); with no closing quote before it the block does not parse.
After a closing quote comes white space or `}`, else the block does not parse
(D10).

The *reading* of a quoted value: `\"` is `"`, `\'` is `'`, `\|` is `|`; a
line break (LF, or CR LF) is one space and the characters after it are kept;
every other character is itself. A quote of the other kind needs no escape.
Any other `\` (before a letter, a digit, a space, a line break, another `\`,
`$`, `}` or anything else), and a character reference, are errors (C2).

The reading of a bare value: `\|` is `|`; every other character is itself,
character references included. A `"`, a `'`, or any other `\` is an error.

Written as the source holds it, then the value read, or the verdict (`⏎` is
a line break):

```
{if="tier == 'sev'"}            tier == 'sev'        accepted (today's form)
{if='tier == "sev"'}            tier == "sev"        accepted
{if="tier == \"sev\""}          tier == "sev"        accepted (the editor's form)
{why='it\'s fine'}              it's fine            accepted
{why="it\'s fine"}              it's fine            accepted
{why="it's fine"}               it's fine            accepted
{title='a\"b'}                  a"b                  accepted
{n=k}  {digits=2}               k  2                 accepted
{unit="mm\|m"}                  mm|m                 accepted
{unit='mm\|m'}                  mm|m                 accepted
{unit=mm\|m}                    mm|m                 accepted (D7)
{if="p \|\| q"}                 p || q               accepted
{if=""}  {if=''}                (empty)              accepted as read; an empty governor is its own error, as today
{why="line one⏎   line two"}    line one    line two accepted (D6): the break is one space, the three after it stay
{title=R&amp;D}                 R&amp;D              accepted: bare, decoded by neither
{title="a}b"}                   a}b                  accepted
{if="grepl('\\d', s)"}                               M1 (\\)
{if='grepl("\d+", s)'}                               M1 (\d)
{if="a\ b"}  {if="a\⏎b"}  {title="a\}b"}             M1
{if=x"y}  {if=\"flag\"}  {if=a\ b}  {title=a\}b}     M2
{if="x &amp;&amp; y"}  {title='&#39;'}  {title="&#x41;"}   M3 (D6)
{if="tier == "sev""}                                 M4, cause q2
{why='it's fine'}                                    M4, cause q1
{unit="m\"}                                          M4, cause open
{n="k".word}                                         M4, cause glued (D10)
{n = "k"}  {if=}  {# if="y"}                         M4, causes space, novalue, marker (unchanged)
```

The errors apply in the block of a weft construct,
to every value in it, pass-through keys included, as 1.2.3 does today. A
block that is not a weft construct is parsed by the same rules for its extent
and is never an error.

### C2. Errors and their exact texts

One text per mistake, in `R/scan.R`. These are scanner-only messages, as
`dev/design-a11.md` ("Messages with no twin") already lists them: the render
side reports the scanner's text (`weft_str()`, the hooks through `R$error`),
the `construct` lint gives one finding per line of it (5.3.1), and the Lua
filter has no twin because Pandoc has decoded the value before the filter
sees it. Each is one line. `%s` is a key as written (its letter case kept),
the first in the block with that mistake; one message per kind per block.

**M1**, a `\` that is not an escape (1.2.3):

```
A `\` in the value of `%s` that does not escape `"`, `'` or `|` (rule 1.2.3). Bind the expression to a name in a chunk and use the name.
```

**M2**, a quote or `\` in a bare value (1.2.3):

```
A `"`, `'` or `\` in the value of `%s`, which has no quotes around it (rule 1.2.3); only `\|` may stand there. Put the value in quotes.
```

**M3**, a character reference in a quoted value (1.2.3); the first `%s` is
the reference as written, such as `&amp;`:

```
A character reference, `%s`, in the value of `%s` (rule 1.2.3): Pandoc reads it as the character it names. Write the character itself.
```

**M4**, a block that does not parse and holds a detection key (1.2.9):

```
The attribute block does not parse: CAUSE (rules 1.2.3, 1.2.9).
```

followed, where a hint is given below, by a space and the hint. The cause is
the first failure met reading the block left to right:

- **q2**: a closing `"` is followed by something other than white space or
  `}`, and another `"` follows later in the block.
- **q1**: the same for `'`.
- **glued**: a closing quote is followed by something other than white space
  or `}`, and no quote of its kind follows later in the block.
- **open**: a quoted value has no closing quote before the paragraph ends.
- **space**: white space before or after `=`.
- **novalue**: `=` followed by white space or `}`, with no value after.
- **marker**: a `#` or `.` with nothing after it.
- **other**: anything else.

CAUSE and, on the line below it where there is one, the hint (the labels
`cause:` and `hint:` are not part of the text):

```
q2       cause: a `"` inside a value in double quotes ends it early
         hint:  Write it as `\"`, or put the value in single quotes.
q1       cause: a `'` inside a value in single quotes ends it early
         hint:  Write it as `\'`, or put the value in double quotes.
glued    cause: a closing quote must be followed by a space or `}`
open     cause: a quoted value is not closed in its paragraph
         hint:  A `\` before a quote escapes it.
space    cause: spaces around `=` are not allowed
novalue  cause: a key has no value
marker   cause: a `#` or `.` has nothing after it
other    cause: it is not Pandoc's attribute syntax
```

So q2 reads in full: ``The attribute block does not parse: a `"` inside a
value in double quotes ends it early (rules 1.2.3, 1.2.9). Write it as `\"`,
or put the value in single quotes.`` The texts of space, novalue and marker are today's. No M4 text carries the
bind hint any more (D11). The quote causes say "ends it early"; the others do
not (review A #21 pins that).

**M5**, an unescaped `|` in a value in a pipe-table cell (1.5.13, D8);
replaces today's `unit`-only text:

```
An unescaped `|` in the value of `%s` of a construct in a pipe-table cell (rule 1.5.13); write `\|`.
```

Removed: "A single-quoted value in an attribute block (rule 1.2.3). ..." and
"A `\` inside a value (rule 1.2.3). ...". Unchanged: the arm-separator text
of 1.5.13, the ladder problems of 4.4.23, and every other message.

Order inside `block_errors()`: M4 alone when the block does not parse (as
today); else M2, M1, M3, then the ladder problems, M5, and the rest as today.

### C3. The broken-block detection (1.2.9, D4)

A block that does not parse comes back as broken when its raw text holds one
of the detection keys followed by `=` (any letter case, after the start, white
space, `{`, `,` or `;`, as today). The detection keys are `WEFT_KEYS` plus
`label`, `why` and `decision`; `WEFT_KEYS` itself does not change. Where the
broken block becomes a row:

- after a bracket: kind is the governor if the key is one (governor keys are
  searched first, as today), `literal` if it is `why` or `decision`, else
  `text`;
- after inline R: a `value` row (as today), for any detection key;
- after a code span that is not inline R: a `named` row when the key is one
  of `NAMED_KEYS` or `label`;
- on a fenced div's opening line (`handle_div()`): a `literal` row when the
  raw block holds `.weft-literal`, `why=` or `decision=` (today: no row);
- after a link or a stray `]`: as D16.

Each row carries M4. Braces with no detection key are not a block and not an
error, as today (`[a]{foo="a "b""}`).

### C4. What each reader does

| Reader | Where | Today | Change |
|---|---|---|---|
| Scanner, block parse | `R/scan.R` `parse_block_strict()` 547-604 | a quoted value runs to the next same quote; no escapes; a bare value with a quote is not a block | C1: escape-aware extent; per value its quote, its decoded value and its problems (bad escape, bare quote or `\`, reference, a bar not written as an escaped bar in the raw text); on failure, the cause of C2 |
| Scanner, block wrapper | `parse_block()` 517-545 | unescapes the escaped bar in `unit` only; detection by `WEFT_KEYS` | unescaping moves into the parse, for every value; detection by C3's list; the cause is passed on |
| Scanner, errors | `block_errors()` 884-910 | guesses the cause from the raw text; single-quote error; `\` error | M1 to M5 from what the parse recorded |
| Scanner, rows | `handle_bracket()` 1640-1657, `handle_named()` 1440-1449, `handle_div()` 1309-1335 | | C3 |
| Filter governor check | `R/scan.R` 1700-1704 | leading-space check skipped when the single-quote error is present | always run (D12) |
| Condition grammar, R mirror | `cond_parts()` 1175-1190, `COND_OPERAND` 1192, `cond_part_error()` 1196-1211 | `'...'` literals only | C6 |
| Names of a source (2.13.11) | `R/values.R` `values_text_names()` 434-447 | only `key="..."`, no escapes | C7 |
| Name tokens | `values_governor_names()` `R/values.R:425`, `cond_names()` `R/lint-named.R:8` | strip `'...'` | strip both kinds in one left-to-right pass (see below the table) |
| Python names | `inst/python/weft/__init__.py` `_GOV_RE` 187, the strip at 212 | as R today | as C7 and the line above |
| Pre-render script | `inst/quarto/weft-pre-render.R` `span_bad()` 163-178, `operand`/`cond_ok`/`cond_parts` 122-153 | values without escapes; `'...'` literals only | values read as C7 (escape-aware, unescaped); C6 |
| `cond.lua` | `M.split` 45-59, `operand()` 63-72, `find_op()` 75-89, `has_compare_char()` 91-99 | `'...'` only | C6 |
| Filter line search | `weft.lua` `tag()` 2503-2537, `tag_all()` Div 2541-2545; `weftlib/lines.lua` `M:find` 126-138 | needle `KEY="VALUE"` (and its escaped-bar twin) | C8 |
| Filter report | `weft.lua` `shown_attrs()` 515-523, `shown_span()` 534-538 | `k="v"` raw | D13 |
| TeX: math with a named value | `weft.lua` `block_end()` 1467-1481, `tex_candidates()` (via `pandoc.read`) | already escape-aware; Pandoc reads the block | none |
| `weft-check.lua` `carries_weft()` | about line 219 | strips `"[^"]*"` and `'[^']*'` without escapes | strip quoted values escape-aware (low; a `\"` in a value could expose `KEY=` text) |
| Cite fallback | `R/lint-doc.R` 463-467 (`doc_cite_rows()`) | `cite="..."` or `cite='...'`, no escapes | the C7 value pattern for `cite`, then unescape |
| `file=` of a values block | `R/lint-named.R:75` | `file="..."` only | any form of C1, decoded |
| Pass-through and literal writing | `R/resolve.R` `passthrough()` 260-265, `render_literal()` 1137-1151 | `k="v"`, nothing escaped | C5 |
| Listings | D13 | raw | D13 |

The name-token strip is one regular expression with two alternatives, a
single-quoted literal or a double-quoted one (`'[^']*'` or `"[^"]*"`),
applied left to right. Two passes, one per quote, would mis-strip
`"it's" == x`. The decoded value holds no `\` (C1), so no escape handling is
needed there.

Nothing else reads an attribute block from source: `parse_block()` has no
caller outside `R/scan.R`; `R/lint-pandoc.R` masks constructs before Pandoc
reads the text; `weft-post-render.R:147` only detects a governor key.

### C5. Writing

One R helper writes a value as markup: double quotes, with `\` as `\\`, `"`
as `\"` and `|` as `\|` (D5, D9). `passthrough()` and `render_literal()` use
it for every key. A second, for listings (D13), escapes `\` and `"` only. The
Lua report escapes `\` and `"` likewise. Pandoc reads a value written this way back
as the value it came from, and so does C1 unless the value holds a `\` (no
value that came through C1 does, since every other `\` is M1; the writer's
`\\` is for values from elsewhere).

### C6. String literals in a filter condition (1.12.4, D2)

An operand may be `'...'` or `"..."`. A literal holds no `\` and not its own
quote; it may hold the other (`"it's"`, `'say "hi"'`). Every scan of a
condition (the comma split, the operator search, the second-operator check)
tracks one state: outside a literal, either quote opens a literal of its kind;
inside, only the same kind closes it. A comma or an operator character inside
either kind is text. The literal test for "two literals compared" counts both
kinds (`^['"0-9-]`). Evaluation is unchanged: a literal is a string. The E3
and E4 texts are unchanged (E3's "names, numbers and 'strings'" stays).

### C7. Governor values read from raw text

`values_text_names()`, Python's `_source_names()` and the pre-render script
match a governor key (`n`, `if`, `sign`, `list`, any letter case, not after a
name character or `-`) followed by `=` and a value in any C1 form:
`"(?:[^"\\]|\\.)*"`, `'(?:[^'\\]|\\.)*'`, or bare `(?:[^\s}"'\\]|\\\|)+`.
The quotes are removed and `\"`, `\'` and `\|` unescaped; then string
literals of both kinds are stripped (C4) and the name tokens taken. A value
with a mistake of C2 may yield names; that is harmless (publishing an extra
bound name costs nothing, and the construct error stops the render). The
`grepl("=\"", ...)` prefilter in `values_text_names()` widens to any `=`.

### C8. The filter's line search

A span is found by its governor key as written (`get_key()`) and its value
as Pandoc read it; a `.weft-literal` span or div by `decision` likewise.
`lines.lua` gains a search that walks the occurrences of `KEY=` that follow
`{`, a space, a tab or a line break, reads the value written after `=`, and
counts the occurrence when that reading equals the tree's value. The reading
here is Pandoc's, not weft's subset, so that a document weft would refuse
still gets its lines: in a quoted value `\` before a character that is not a
letter or digit (Unicode ones included) is that character (a whole UTF-8
character), `\` before a letter or digit stays, as does `\` before a line
break, and a line break is a space (in a list item the item's indent after
it is dropped; a value that crosses a line break in a block quote has no
line); in a bare value (up to white space or `}`) `\` before a
non-alphanumeric is that character.
Character references are not decoded: such a span has no line (a limit; it
is a construct error to the lints). The cursor of 2.13.6 is kept per key and
value (the next occurrence after the previous one *with the same key and
value*), not per `KEY=`, so a span that is found nowhere does not move the
search on for others. The escaped-bar twin in `M:find` is no longer needed
for spans; it stays for other needles. Named values keep their needle
`` `NAME`{ ``.

## Test plan

The test-writer does not read `R/`. Observe the scanner with
`weft:::scan_text(x)` (a data frame: `kind`, `line`, `expr`, `keys` (a list
of named character vectors), `error` (`NA` or the messages joined by a line
break), and others), names with `weft:::values_source_names(path)`, output
with `weft::weft_str()`, the filter with `filter_cases()`, `filter_md()`,
`carrier()`, `fr_*()`, `fm_entry()` and `marker()` (helper-filter.R), lints
with `weft::lints(path)`. Write markup in raw strings (`r"(...)"`,
`r"---(...)---"`) to avoid R escaping mistakes. Exact message texts are C2;
compare with `fixed = TRUE`.

### T1. The scanner reads every form (`scan_text`)

Accepted (no error; check `kind`, `expr` or the key in `keys`). Input as the
source holds it, then what to expect:

```
[a | b]{if='tier == "sev"'}                     kind if, expr: tier == "sev"
[a | b]{if="tier == \"sev\""}                   the same expr
[a | b]{if="tier == 'sev'"}                     expr: tier == 'sev'   (control)
[a | b]{n='k'}    and    [a | b]{n=k}           kind n, expr: k
`r x`{.num digits='2'}                          kind value, keys digits = 2
[a | b]{if='s == "it\'s"'}                      expr: s == "it's"
[a | b]{if="s == \"it's\""}                     expr: s == "it's"
[a | b]{if="s == 'a\|b'"}                       expr: s == 'a|b'
[a | b]{if="p \|\| q"}   (not in a table)       expr: p || q
`r x`{unit=mm\|m}                               keys unit = mm|m
[lit]{.weft-literal why='it\'s "quoted"'}       kind literal, keys why = it's "quoted"
[lit]{.weft-literal why="said \"about 5\" in the source"}   why = said "about 5" in the source
[lit]{.weft-literal why="line one⏎line two"}    why = line one line two
`r x`{.num title=''}                            keys title = (empty)
`r x`{.num title=R&amp;D}                       keys title = R&amp;D
[a]{foo="a\\b"}    and    [a]{title='x'}        no row (not constructs)
```

Errors, the first error line exactly as C2 (key `if` unless said):
M1 for `[a | b]{if="grepl('\\d', s)"}`, `[a | b]{if='grepl("\d+", s)'}`,
`[a | b]{if="a\ b"}`, a `\` then a line break inside a quoted `if`, and
`` `r x`{.num title="a\\b"} `` (key `title`); M2 for `[a | b]{if=x"y}`,
`[a | b]{if=\"flag\"}`, `[a | b]{if=a\ b}`; M3 for
`[a | b]{if="x &amp;&amp; y"}` (reference `&amp;`) and
`` `r x`{.num title="R&#38;D"} `` (`&#38;`, key `title`); M4 with cause q2
for `[a | b]{if="tier == "sev""}`, q1 for `[a | b]{if='it's'}`, open for
`` `r x`{unit="m\"} ``, glued for `[a | b]{n="k".word}`; space, novalue
and marker as today.

Pipe-table cells (a two-column table, the construct in the first cell): M5
with key `if` for `[x \| y]{if="p || q"}`; no error and expr `p || q` for
`[x \| y]{if="p \|\| q"}`; M5 with key `title` for `` `r x`{.num title='a|b'} ``;
today's `unit` cases still give M5 with key `unit` (and the existing
`unit` tests keep passing, since they match "unescaped `|`", "unit",
"rule 1.5.13" and `\|`).

In a document the filter resolves (the helpers of test-review6-r.R):
`A [one | many]{if=' ok'} B.` is one construct error with the 1.12.6
leading-space text.

### T2. Broken blocks holding `why`, `decision`, `label` (C3)

Each gives one row with M4 and the cause shown: `[lit]{.weft-literal why="said "about 5""}`
(`literal`, q2); `[lit]{.weft-literal decision='it's'}` (`literal`, q1);
`` `r p`{.p label="p "x""} `` (`value`, q2); `` `p_val`{.p label="a "b""} ``
(`named`, q2); the three lines `::: {.weft-literal why='it's fine'}`, `Text.`,
`:::` (a `literal` row on line 1, q1). Controls with no row:
`[a]{foo="a "b""}`, `` `r x`{foo="a "b""} ``.

### T3. A shared table: weft's reading against Pandoc's (D1)

New `tests/testthat/_conformance/quoting.tsv`, read with `f6_read()` and
percent-unescaped as `gr_unesc()` does (`%20`, `%25`, `%0A`, `%09`):
columns `written` (a value as written, quotes included), `verdict` (`ok`,
`M1`, `M2`, `M3`, `M4`), `value` (the decoded value for `ok`). Two drivers:

1. **Scanner.** For each row scan `` `r 1`{.num digits="1" title=WRITTEN} ``
   (`digits` makes a broken block detectable). `ok`: no error and keys
   `title` equals `value`. Otherwise the error starts with the verdict's
   text up to its first `%s` (for M4, "The attribute block does not parse:").
2. **Pandoc.** One document, one paragraph `[x]{title=WRITTEN}` per `ok` row,
   through the Pandoc of `lua_pandoc()` (`skip_if_no_lua_pandoc()`) to JSON;
   each span's `title` equals `value`. This pins the subset rule.

Rows, at least: `"a b"`, `'a b'`, `ab`, `""`, `''`, `'say "hi"'`,
`"say \"hi\""`, `"it's"`, `'it\'s'`, `"it\'s"`, `'a\"b'`, `"a\|b"`,
`'a\|b'`, `a\|b`, `"a|b"`, `"line one%0Aline two"`, `"a%0A%20%20%20b"`
(value `a    b`), `R&amp;D` (bare, value `R&amp;D`), `"a}b"`, `'{x}'`
(all `ok`); `"a\\b"`, `"a\db"`, `'a\ b'`, `"a\%0Ab"`, `"a\}b"` (M1);
`a"b`, `a'b`, `\"a\"`, `a\}b` (M2); `"R&amp;D"`, `'&#39;'`, `"&#x41;"`
(M3); `"a"b"`, `'it's'`, `"m\"`, `"k".c` (M4).

### T4. `weft_str()` end to end, and what weft writes

- `tier <- "sev"`: `weft_str("[severe | mild]{if='tier == \"sev\"'}")`,
  the same with `{if="tier == \"sev\""}`, and
  `weft_str(r"([severe | mild]{if='tier == "sev"'})")` each give `"severe"`;
  with `tier <- "x"`, `"mild"`.
- `k <- 3`: `weft_str("Found [a site | # sites]{n='k'}.")` gives
  `"Found 3 sites."`.
- Pass-through (D5, D9), exact output:
  `` `r 1.2`{.num custom-style='Key "figure"'} `` gives
  `[1.2]{custom-style="Key \"figure\""}`; `` `r 1.2`{.num title="a\|b"} ``
  gives `[1.2]{title="a\|b"}`; `` `r 1.2`{.num title="it's"} `` gives
  `[1.2]{title="it's"}`.
- Literal: `[lit]{.weft-literal why='it\'s fine' title='say "hi"'}` gives
  `[lit]{.weft-literal title="say \"hi\""}`.
- Each output above, read by Pandoc (as in T3), has the attribute value the
  source decoded to.
- `weft_str(r"([a | b]{if="a\db"})")` is an error of class
  `weft_construct_error` whose message holds M1.

### T5. Names a source names (2.13.11), R and Python

A document `doc.qmd` with the lines `` We saw `v0`{.num}. ``,
`[a | b]{n='n_sq'}`, `[a | b]{n=n_bare}`, `[a | b]{if='lvl == "str_dq"'}`,
`[a | b]{if="lvl2 == \"str_esc\""}`, `[a | b]{if="lvl3 == 'str_sq'"}`,
`[a | b]{sign='d_sq'}`, `[a | b]{list=l_bare}`, `[a | b]{n = "spaced"}`:

- `weft:::values_source_names(path)` holds `n_sq`, `n_bare`, `lvl`, `lvl2`,
  `lvl3`, `d_sq`, `l_bare`, and none of `str_dq`, `str_esc`, `str_sq`,
  `spaced`.
- Python, `py_exe6k()` with `PYTHONPATH` = `py_lib6k()` (as the Python
  driver of test-conformance-grammar.R): `weft._source_names(path)` returns
  the same set.
- A knit (the `b6_knit()` pattern of test-values-knit.R:150) with
  `[one | many]{n='kq'}` in the prose and `kq` bound in a chunk publishes `kq`.

### T6. The filter's condition grammar (D2)

`_conformance/grammar.tsv`, new `cond` rows (verdict): `s == "north"` ok,
`"north" == s` ok, `s == "a,b"` ok, `s == "it's"` ok, `s == 'say "hi"'` ok,
`s == ""` ok, `d >= "2026-01-01"` ok, `s == "north", !ok` ok,
`"a" == "a"` E4, `"a" == 'a'` E4, `s == "a` E3, `s == "a"b"` E3,
`s == "a" "b"` E3, `!"x"` E3, `s == "a,b", 3 > 2` E4 (message on `3 > 2`).
No row holds a `\`. The pre-render driver (test-conformance-grammar.R:264)
embeds the condition in `{if="..."}`, so it must write `"` as `\"` there.

Through the filter (`filter_cases()` with `carrier(tier = fr_str("sev"))`):
`A [severe | mild]{if='tier == "sev"'} z.`, `A [severe | mild]{if="tier == \"sev\""} z.`
and `A [severe | mild]{if="tier == 'sev'"} z.` all give `A severe z.`;
`A [severe | mild]{if='tier == "other"'} z.` gives `A mild z.`;
`A [yes | no]{if='tier != "a,b"'} z.` gives `A yes z.`; `{if='"a" == "a"'}`
is the E4 construct error (mirror test-filter-if.R).

### T7. The filter's lines and report (C8, D13)

Draft mode, unpublished names, the `NV` marker of test-filter-lines.R, one
case per paragraph:

- `A [x | y]{if='nothere == "a"'}.`, `B [x | y]{if="nothere == \"a\""}.`,
  `C [x | y]{if='nothere == "a"'}.`: each marker names its own line (one
  decoded value, three spellings, found in order).
- `D [x | y]{n=nothere}.` and `E [x | y]{if="nothere == 'a\|b'"}.`: each has
  its line (D has none today).
- The report entry for case A shows `[x | y]{if="nothere == \"a\""}`; a named
  value `` `nothere`{.num title='say "hi"'} `` shows
  `` `nothere`{.num title="say \"hi\""} ``.
- A blank `decision` written `decision=' '` on a `.weft-literal` span is
  reported with its line (mirror test-filter-decision.R).

### T8. Lints and the gate

- A `.Rmd` with `[a | b]{if="a\db"}` on line 5: `lints()` has one
  `construct` finding at line 5 whose text is M1.
- A `.qmd` the filter resolves, with `` `v0`{.num} `` published and
  `[a | b]{if='flag_x == "a"'}` unpublished: `named-unpublished` names
  `flag_x` and not `a`.
- A ```` ```{.weft-values file='vals.json'} ```` block whose file publishes
  `k`, and `` `k`{.num} `` in the prose: no `named-unpublished` finding for
  `k`.
- `[0.5 m]{cite=@nokey2020 title="a"b"}` (a broken block): a `cite-key`
  finding for `nokey2020` (none today).
- `_gate/edits.R` E18: add a requote of `n="n_sites"` to `n='n_sites'` in the
  paragraph that holds it, and replace the `sem` note; its EXPECT row does
  not change (D3).

### Existing tests that change

| Test | Change |
|---|---|
| test-scan.R:525-536 | invert: the three single-quoted inputs parse with no error; check their expr or key |
| test-scan.R:538-544, 546-554, 556-559 | unchanged (still errors, or still no row) |
| test-sign.R:68-70 | the bad block becomes `{sign="d\e"}` on the same span; add `{sign='d'}` as a second good form |
| test-cite.R:197-199 | bad becomes `[x]{cite="@smith\2020"}`; `cite='@smith2020'` is good |
| test-syntax-fixtures.R:281, 282, 284 | move to the OK rows, with the output of the same block written with double quotes; 283 stays bad; add OK rows for `{if='flag == "x"'}`-style blocks |
| test-trial-bugs.R:102-113 | the input is valid now: it resolves (assert no error, expr `x == "a"`); the "spaces around" control stays |
| test-review-a.R:111, 230 | unchanged |
| test-review6-r.R:61 | passes as is (now the 1.12.6 error); rename to say so |
| test-unit-ladder-source.R:127-133 | `m\\` (that is `unit="m\"`) is now M4, cause open: match "1.2.9" for that case |
| test-unit-ladder-source.R:135-141 | rewrite: an escaped bar in another key is read as a bar (see below the table); drop the error expectation |
| test-unit-ladder-source.R:74-82, 143-146 | unchanged |
| test-values-record.R:326-336 | `single` and `bare` are read now; `spaced` still is not |
| test-conformance-grammar.R:264 | escape `"` when writing the condition (T6) |
| _gate/edits.R:51 | T8 |
| test-review6-filter.R:54 | unchanged (Pandoc still loses `' ok'`) |
| test-front-matter.R:116 | unchanged (the 1.10.7 error) |

For test-unit-ladder-source.R:135-141: the block `{if="x\|y"}` on a span gives
expr `x|y`, and `{n="x\|y"}` likewise; `digits` and `sigfig` with an
escaped bar are no longer the 1.2.3 error (keep them only as reads of the
key's value).

A test whose expected `expr` holds a line break inside a quoted value would
change to a space (D6); none was found, and the implementer reports any.

## Spec edits (PACKAGE-SCOPING.md)

Part 1, replacement text.

**1.2.2** A value is written in double quotes, in single quotes, or bare.
`{if="tier == 'sev'"}`, `{if='tier == "sev"'}` and `{if="tier == \"sev\""}`
are the same block. A bare value holds no white space, no `}`, no quote and
no `\` but `\|`: `{n=k}`, `{digits=2}`.

**1.2.3** weft reads a value as Pandoc reads it, and accepts only part of
what Pandoc accepts, so that a block weft reads means the same to Pandoc.
In a quoted value `\"`, `\'` and `\|` stand for `"`, `'` and `|`, a quote of
the other kind needs no escape, and a line break reads as one space. In a
bare value `\|` stands for `|`. In the block of a weft construct these are
construct errors (§5.3): any other `\` in a value; a `"`, `'` or `\` in a
bare value, but for `\|`; a character reference (`&amp;`, `&#39;`) in a
quoted value. The message for a `\` says to bind the expression to a name in
a chunk.

**1.2.9** An unescaped quote of a value's own kind ends the value early, and
what is left is no longer an attribute block. So braces that directly follow
a bracket or inline code, do not parse as an attribute block, and contain a
key of 1.2.5 (`label`, `why` and `decision` included) in any letter case
followed by `=`, are a construct error that names the cause. The same holds
on the opening line of a fenced div that holds `.weft-literal`, `why` or
`decision`.

**1.5.13** Inside a pipe-table cell the arm separator must be written `\|`.
An unescaped one is a construct error. So must a `|` in any attribute value
of a construct in the cell, such as the ladder of `unit` (4.4.23):
`` `r x`{unit="mm\|m\|km"} ``, `[a \| b]{if="p \|\| q"}`.

**1.8.8** A citation that a value cannot hold, a prefix or locator that needs
a `\` (1.2.3), is written as an ordinary Pandoc citation after a bare-form
span.

**1.12.4**, replace "each side a name, a number literal or a single-quoted
string, at least one a name" with "each side a name, a number literal or a
string literal in single or double quotes (`'sev'`, `"sev"`), at least one a
name", and "A string literal holds no `'` and no `\`." with "A string literal
holds no `\` and not the quote that delimits it: `"it's"` and `'say "hi"'`
are literals."

**2.12.15**, replace "In an attribute value the argument takes single
quotes: `{if="jl_value('ok')"}`." with "In an attribute value the argument
takes the quote the value does not use: `{if="jl_value('ok')"}` or
`{if='jl_value("ok")'}`."

**2.13.6**, replace "A span whose attribute value holds an escaped bar
(`\|`, as a pipe-table cell needs) is searched for in the form the tree
holds." with "A span is found by its governor key as written and its value,
and a `.weft-literal` by its `decision`: an occurrence is `KEY=` after a `{`
or white space whose value, read as Pandoc reads it, is the tree's value,
in any quotes and with any escapes (1.2.3). For a span, the same text is the
same key and value."

**2.13.11**, replace "every name in the value of an `n`, `if`, `sign` or
`list` key" with "every name in the value of an `n`, `if`, `sign` or `list`
key, written in any form of 1.2.2 and read by 1.2.3, outside string literals
in either quote".

**4.4.23**, the pipe-table bullet becomes: "In a pipe-table cell the
separator is written `\|` (1.5.13): `` `r x`{unit="mm\|m\|km"} ``. weft reads
`\|` as `|` in every value (1.2.3). An unescaped `|` in a value in a
pipe-table cell is a construct error (1.5.13). The `|` of a ladder does not
change a span's arm count."

**5.3.1** list: replace "a single-quoted value, or a `"` or `\` inside a
value (1.2.3, 1.2.9), but for `\|` in `unit`" with two items: "in a value, a
`\` that does not escape `"`, `'` or `|`; a `"`, `'` or `\` in a bare value,
but for `\|`; a character reference in a quoted value (1.2.3)" and "braces
after a bracket, inline code or a `.weft-literal` div's colons that do not
parse and hold a key of 1.2.5 (1.2.9)". Replace "an empty or repeated rung
in `unit`; an unescaped `|` in `unit` in a pipe-table cell (1.5.13, 4.4.23)"
with "an empty or repeated rung in `unit` (4.4.23); an unescaped `|` in any
value of a construct in a pipe-table cell (1.5.13)".

§18: in "The stand-in is not the rules", replace "it accepts single-quoted
values (rule 1.2.3 makes them an error)" with "it reads a quoted value
without escapes (rule 1.2.3 reads `\"`, `\'` and `\|`)". Replace the row
"Not writable under the quoting rule: ..." with "Not writable as a value: a
prefix or locator needing a backslash (1.2.3). Pandoc decodes `&quot;` in a
quoted value; weft refuses a character reference (1.2.3)". Add a row, run
under "check, 2026-11-25": "Pandoc 3.8.3 reads `\` before any character that
is not a letter or digit as that character, in quoted and bare values, and
keeps a `\` before a letter or digit; decodes character references in a
quoted value only; reads a line break in a quoted value as a space; reads
`{k=x"y}`, `{k="x".c}` and `{k="m\"}` (as the bare value `"m"`) as spans and
`{k=' x'}` as text; its writer writes `\` as `\\`, `"` as `\"` and `\|` as
`|`".

§19: "the single-quote and escape errors (1.2.3)" becomes "the quoting and
escape rules (1.2.3)".

§21, "Attribute forms": replace "With its values single-quoted it must give
the construct error of 1.2.3." with "With its values single-quoted, and as
Pandoc's writer writes them (double quotes, `\"`), it must render the same
text (1.2.3)."

Part 2, replacement text.

**1.2.2, 1.2.3, 1.2.9** Markup is written in documents and inside strings:
R string literals, raw strings (`r"( ... )"`), plot labels built in code. A
rule of double quotes only makes every R string inside a value take single
quotes, leaves no way to write an apostrophe in a single-quoted `why`, and
leaves no quote to wrap the whole string with. Pandoc reads double, single
and bare values, and its writer, so the visual editor, rewrites every value
to double quotes with `\"` (`{if='tier == "sev"'}` comes back as
`{if="tier == \"sev\""}`, §18). weft reads each of these forms and unescapes
as Pandoc does, so a save in the editor changes the spelling and never the
meaning: the ledger and `changes()` key on the value read, which is the same.
weft accepts only part of what Pandoc reads because weft reads the source
before Pandoc does (the hooks, the lints, `weft_str()`) and the filter reads
Pandoc's tree; a block read two ways would mean two things in one project.
Pandoc also takes a `\` before any character that is not a letter or digit,
decodes character references in quoted values, and reads quotes in a bare
value. weft refuses these: none is needed to write an expression or a
reason, a refusal is loud where a misreading is silent, and decoding
references would put Pandoc's entity table in every reader. A bare value
with an escape is a trap besides: a construct in a YAML double-quoted string
reaches the scanner with YAML's `\"` still in it (`{if=\"flag\"}`), and a
bare value read with escapes would test the string `"flag"` statically while
the render evaluates `flag`. A line break reads as a space because an
editor's re-wrap may put one inside a long value. `commonmark_x` reads
neither single quotes nor `\"`, but weft's lints mask constructs before
Pandoc reads the text, so this does not reach them. The broken-block error
covers `label`, `why` and `decision` because an apostrophe in a single-quoted
`why` ends it, and the span would then print as text with no error.

**1.5.13**, add at the end: "Now that `\|` reads as `|` in every value
(1.2.3), the same holds for a `|` in any value of a construct in a cell, not
only a ladder's."

**1.12.4** (new entry, before 1.12.7): "A string literal takes either quote so
that one sentence means the same under the filter and under the hooks, where
R reads both: `{if='tier == "sev"'}` is the natural form inside a
single-quoted value. A literal holds no `\` and not its own quote, so the
condition has no escapes of its own on top of the attribute's."

## Doc edits

- `vignettes/wording.Rmd:26`: "The key's value is an R expression, in double
  quotes." becomes "The key's value is an R expression, in double or single
  quotes; one name needs none (`{n=n_sites}`)." Add after "Writing `|` and
  `#` in an arm" (line 270) a section "Quoting a value": a value goes in
  double quotes, single quotes, or none when it is one word; an R string
  inside a value takes the other quote, so `{if="tier == 'sev'"}` and
  `{if='tier == "sev"'}` are the same block; inside quotes `\"`, `\'` and
  `\|` stand for the character, which is how the visual editor writes a value
  when it saves; any other backslash is an error, and the fix is to bind the
  expression to a name in a chunk. Show the raw-string form in a
  `{verbatim, lang = "r"}` block, `weft_str(r"([severe | mild]{if='tier == "sev"'})")`,
  with the note that a raw string ends at `)"`, so a value that ends in `)`
  takes single quotes (`{if='isTRUE(x)'}`); then a run chunk:
  `tier <- "sev"` and `weft_str("[severe | mild]{if='tier == \"sev\"'}")`.
  The run chunk avoids a raw string because the package declares no minimum
  R version.
- `vignettes/values.Rmd:273-274`: "with the value in double quotes" becomes
  "with the value in double or single quotes, or none when it is one word
  (`digits=2`)".
- `vignettes/languages.Rmd:537-539`: replace with "Inside an attribute value,
  write the name in the quote the value does not use:
  `{if="jl_value('rising')"}` or `{if='jl_value("rising")'}`."
- `vignettes/named-values.Rmd:374`: "a single-quoted string such as
  `'north'`" becomes "a string in quotes such as `'north'` or `"north"`".
- `inst/agent/references/syntax.md`: after "Spans that choose wording", a
  section "Quoting a value": "A value goes in double quotes, single quotes, or
  none when it is one word: `{if="tier == 'sev'"}`, `{if='tier == "sev"'}`,
  `{n=n_sites}`. Inside quotes, `\"`, `\'` and `\|` stand for the character;
  any other `\` is an error. In R code a raw string needs no escapes:
  `weft_str(r"([severe | mild]{if='tier == "sev"'})")`." Then regenerate
  `skills/weft/` with `agent_repo_skill(".")` (a test compares the copies).
- `R/guest-julia.R:286` (roxygen) as 2.12.15; then `devtools::document()`.
- `dev/current-state.md` ("Quoting", about line 496) and `dev/decisions.md`
  (an entry for D6 to D16 beside the 25 Nov "Weft everywhere" one): by the
  orchestrator.

## Order of work

1. One test-writer: T1 to T8 and the changes to existing tests, including
   both conformance tables. Check that the new tests fail for the right
   reason: the accepted forms on the old single-quote and `\` errors, the
   filter cases on E3, the names on missing names, the lines on "no line".
2. In parallel, in two worktrees:
   - **R implementer:** `R/scan.R` (C1 to C3, D12, C6 mirror), the name
     extractors and Python (C4, C7), `R/lint-doc.R`, `R/lint-named.R`,
     `R/resolve.R` writing (C5), the listings (D13), the pre-render script.
   - **Lua implementer:** `cond.lua` (C6), `lines.lua` and `weft.lua`
     (C8, D13), `weft-check.lua` (`carries_weft()`).
   They share no file. Neither edits tests.
3. The whole suite (offloaded), then an independent review that reproduces
   findings, with T3's Pandoc driver as the check on D1.
4. Spec editor (the edits above), docs, `skills/weft/`, decisions entry.

## Not in this package

- The cite span's ledger key uses the raw bracket text (`R/resolve.R:1220`,
  F9); Pandoc's pipe-table writer writes `\|` in a value back as `|` (F9).
- A value that starts with a space is accepted in a document the hooks
  resolve though Pandoc reads no block there (review-6 #2, unchanged).
- Pandoc versions before 3.1 were not run (F10); the hooks consume the block
  before Pandoc sees it, and the filter needs 3.1.

## For the author

Nothing blocks the work. Two of the decisions above make blocks that are
valid today into errors, and can be reversed on their own: D6 (a character
reference in a quoted value, such as the old `&quot;` workaround) and D8
(a bare `|` in any value of a construct in a pipe-table cell, such as
`{if="p || q"}`).
