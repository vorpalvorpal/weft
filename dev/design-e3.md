# E3: console output and ANSI (26 Nov)

Package E3 of `dev/plan-weft-everywhere.md`. It builds on E1
(`dev/design-e1.md`): the `weft` object (WS6), its renderings (WS7), the
plain reader and its runs (PL1 to PL11, D1). E1 D1 already names this
package's job: "Package E3's ANSI target is a second renderer over the same
runs (emphasis to italic, strong to bold)." E2 (`dev/design-e2.md`) changes
nothing here, except that a `weft()` string no longer leaves a named value
for the filter (E2 D3), so a resolved string holds no attribute block.
Neither E1 nor E2 is built yet; this note is written against their notes.

This note is the contract for a test-writer who does not read `R/` and an
implementer who does not edit tests. Contract items are **C1** to **C12**,
decisions **D1** to **D10**, tests **T1** to **T11**.

## Why

E1 gives a `weft` object two forms: plain (its content) and markdown (an
attribute). In a terminal neither is right. Plain loses the emphasis the
author wrote (`*Eucalyptus*`), and markdown prints `*` and `^2^` as typed.
cli, which weft already imports, knows how to draw bold and italic, knows
when the terminal can (and when it cannot: `NO_COLOR`, a knit, a sink, a
dumb terminal), and has a hook, `cli_format()`, for objects interpolated
into its messages.

## What cli does (read from cli 3.6.5's source)

The installed versions are 3.6.4 to 3.6.6; the behaviour below has not
changed in 3.x. Read from `R/inline.R`, `R/format.R`, `R/themes.R`,
`R/ansi.R` and `R/num-ansi-colors.R` at tag `v3.6.5`.

| Fact | Where |
|---|---|
| A plain substitution `{x}` in a cli template evaluates `x`, stores the value, and puts a marker in the template; the value is styled and inserted after the template is parsed. A value is never read as a template, so braces in it are text. | `make_cmd_transformer()`, `glue_delay()`, `inline_transformer()` (plain branch) |
| A plain substitution is pasted with `paste0(before, x, after)`, which calls `as.character()` on an object, then collapsed (`a, b, and c`). | `inline_generic()`, `inline_collapse()` |
| `cli_format()` is called only by the `.val` style: `span.val = list(transform = function(x, ...) cli_format(x, ...), color = "blue")`. `cli_format.character()` quotes with `encodeString(quote = "\"")`. | `R/themes.R:238`, `R/format.R` |
| An R class can be mapped to a cli class only through the theme's `class-map` (the builtin maps `fs_path` and `cli-progress-bar`). | `R/themes.R:96`, `inline_transformer()` |
| `num_ansi_colors(stream = "auto")`: the option `cli.num_colors`, then `R_CLI_NUM_COLORS`, then `crayon.enabled`, then `NO_COLOR` (1), then `knitr.in.progress` (1), then an active sink (1, for `"auto"`), then the stream's terminal. `"auto"` means `stdout()` when interactive with no sink, else `stderr()`: the stream cli's own messages go to. | `R/num-ansi-colors.R:36-110` |
| `style_bold()`, `style_italic()`, `col_red()` write `ESC[1m`…`ESC[22m`, `ESC[3m`…`ESC[23m`, `ESC[31m`…`ESC[39m`, and nothing when `num_ansi_colors() <= 1`. An inner close code of the same style is replaced by the open code, so nesting keeps the outer style. | `create_ansi_style_fun()`, `ansi_builtin_styles` |
| `format_inline()` is `cli_inline()` captured as a string, with `cli.width = Inf`. | `R/cli.R:115` |

`ESC` is U+001B throughout this note.

## The contract

### The ANSI rendering

**C1** A third rendering of a `weft` element, **ANSI**, is made from the same
runs as the plain rendering (E1 PL1 to PL10, D1). It is the plain rendering
(PL11) with these styles added, and nothing else changed:

| Run | ANSI |
|---|---|
| text | as plain; inside it, each failure marker (2.6.8: from `<<weft: ` to the next `>>`) is bold red |
| code | as plain (its text, no backticks), unstyled |
| math | as plain (written with its delimiters), unstyled |
| an HTML comment | removed, as plain |
| emphasis (`*a*`, `_a_`) | italic around the ANSI rendering of the content |
| strong (`**a**`, `__a__`) | bold around the ANSI rendering of the content |
| strong emphasis (`***a***`) | bold around italic around the content |
| superscript, subscript | PL11's choice is made on the **plain** rendering of the content: when every character has a Unicode form, the Unicode characters, with no style from inside the run; otherwise `^(`, the ANSI rendering of the content, `)` (`_(` … `)` for a subscript) |
| span | the ANSI rendering of its content, attributes dropped, no style from its classes |

**C2** The styles are written exactly as cli's style functions write them,
composed over the runs from the inside out:

- italic(s) is `cli::style_italic(s)`, bold(s) is `cli::style_bold(s)`, and
  the marker style is `cli::style_bold(cli::col_red(marker))`;
- adjacent runs are joined with `paste0()`;
- the result is a bare character string (no `cli_ansi_string` class).

So, with styles on: `*a*` is `"\033[3ma\033[23m"`; `**a**` is `"\033[1ma\033[22m"`; `***a***` is
`"\033[1m\033[3ma\033[23m\033[22m"`. A full reset (`ESC[0m`) is never
written, so a weft text inside a cli colour keeps the colour around it.

**C3** For every element, `cli::ansi_strip()` of its ANSI rendering is its
plain rendering, byte for byte.

**C4** An element whose plain text is not the PL reading of its markdown
(a text joined by `c()` or `[<-`, E1 WS9, or changed by a function that kept
the attributes, WS10) is rendered in ANSI as its plain text, unstyled. An
`NA` element is `"NA"`, unstyled.

### When styles are written

**C5** Styles are written only where cli would write its own. The ANSI
rendering *with styles* is C1 and C2; the ANSI rendering *without styles* is
the plain rendering. Which one a sink gets:

| Sink | Styles when |
|---|---|
| `format(x, target = "ansi")` | `cli::num_ansi_colors() > 1` (stream `"auto"`, as cli's own styles) |
| `print(x)` | `cli::num_ansi_colors(stdout()) > 1` |
| `cli::cli_format(x)` (and so `{.val {x}}`) | `cli::num_ansi_colors() > 1` |

`NO_COLOR` set, a knit in progress, an active sink, a terminal without
colour, `options(cli.num_colors = 1)` and `crayon.enabled = FALSE` therefore
give plain text everywhere, and `options(cli.num_colors = 256)` (or
`R_CLI_NUM_COLORS`) turns styles on everywhere. weft reads no environment
variable or option of its own for this.

### `format()` and `print()`

**C6** `format(x, target = "ansi")` gives each element's ANSI rendering (C5),
names kept, `NA` as `"NA"`. `format(x)` and `as.character(x)` stay plain
whatever the console supports (E1 WS7 unchanged). The target error of WS7
becomes: "`target` must be \"plain\", \"markdown\" or \"ansi\"; got %s."
(`%s` as in rule 3.4.11: the value in double quotes, or `something else`).

**C7** `print(x)` writes each element on its own line: its ANSI rendering
with styles when `cli::num_ansi_colors(stdout()) > 1`, else its plain text
exactly as E1 WS7 says. Names are not shown; `NA` prints `NA`; a length-0
object prints `<weft[0]>`; the value is `x`, invisibly. (A styled print is
the line of C1 and C2 even when `cli::num_ansi_colors()`, on the `"auto"`
stream, would say no: the print goes to `stdout()`.)

**C8** Nothing else changes: `knitr::knit_print()` writes markdown, captions
get markdown and `fig.alt` plain (WS16), and `cat()`, `paste()`,
`message()`, `glue::glue()` and ggplot2 get plain text (WS8, WS17).

### cli

**C9** weft registers an S3 method `cli_format.weft(x, style = NULL, ...)`
for cli's generic (in `NAMESPACE`: `S3method(cli::cli_format, weft)`). It
returns a bare character vector of the same length: each element's ANSI
rendering when `cli::num_ansi_colors() > 1`, else its plain text; names
kept; no class, no `markdown` attribute; `NA` as `"NA"`. It does not quote
(a `weft` text is prose, not a string value) and ignores `style`. So
`{.val {w}}` in any cli template draws the text with its emphasis, in cli's
value colour, with no quotes; a vector is collapsed by cli (`a, b, and c`).

**C10** A plain substitution `{w}` gets plain text: cli pastes the value,
which calls `as.character()` (C8). This is cli's behaviour and weft does not
change it (D5).

**C11** Braces. A `weft` object given to cli as a value (`"{w}"`,
`"{.val {w}}"`, `c(i = "{w}")`) is never read as a cli template, so braces
in its text (a formula kept as TeX, PL3; braces the author typed) are text,
and nothing in it is evaluated. A `weft` object or its text given as the
template itself (`cli_inform(w)`, `cli_text(as.character(w))`,
`format_inline(format(w))`) is read by cli's glue: `{1}` in `$x_{1}$` is
evaluated and printed as `1`, and a name in braces is looked up in the
caller. weft writes no escaping into any form (D6); the documentation says
to pass the object as a value. Markup written directly in a cli template
(`cli_inform("Mean `r x`{.num}")`) is cli's to read, and fails there
(`{.num}` is a cli style name); the documentation says to build the text
with `weft()` first.

**C12** cli stays in `Imports` (it is there already, for `hash_md5()`,
`hash_raw_xxhash64()` and `ansi_strip()`). No new dependency. `fmt_*()` do
not take `target = "ansi"`: their target error is E1's FT3 text, unchanged.

## Decisions

**D1 ANSI is plain plus font styles.** Emphasis is italic, strong is bold,
the failure marker bold red; every other run renders as plain, so C3 holds
and a test can check the two forms against each other. Alternatives:

- *Code in cli's code style* (backticks, a grey background). Rejected: plain
  drops the backticks (PL11), so the two forms would differ in their
  characters, not only their styles; and a code span in a title or a log
  line is rare.
- *A class map for spans* (`.underline` to underline, `.smallcaps`,
  `.mark` to inverse). Rejected for now: weft passes these classes through
  for Pandoc (1.4.10), and no case needs them in a console. Easy to add
  later inside C1's table.
- *Links as OSC 8 hyperlinks* (`cli::style_hyperlink()`). Not possible
  without a change to the reader: PL9 keeps `[a](u)` as text. Later, with
  the HTML target.
- *No style for the marker.* Rejected: a marker is a failure that printed;
  in a console it is the one thing that must be seen. Markers only arise in
  a knit (E1 WS12), where colour is off, so this matters for an object made
  in a knit and printed later at the console.

**D2 cli decides when; weft never does.** Styles follow
`cli::num_ansi_colors()` (C5). Alternatives:

- *`format(target = "ansi")` always writes escapes*, and only `print()` and
  `cli_format()` check the console. Rejected: then
  `cli_inform("{format(w, target = 'ansi')}")` writes escapes under
  `NO_COLOR` and in a knit, and a script that writes the form to a log gets
  escapes in the file. One rule ("ANSI is what cli would draw") is easier to
  state and to keep. A user who wants escapes in a file sets
  `cli.num_colors`, as for any cli output.
- *weft's own test* (`isatty()`, `NO_COLOR`, `TERM`). Rejected: cli already
  handles RStudio, Emacs, sinks, knitr, Windows terminals and its options;
  a second test would disagree with cli's styling of the text around a weft
  value.

`print()` asks about `stdout()` and the others about `"auto"` because that is
where each writes: `print()` to standard output, cli's messages to the
stream `"auto"` names.

**D3 `format()` stays plain; only `print()` chooses.** `format()` and
`as.character()` feed `paste()`, ggplot2, files and tests, and must not
change with the terminal (E1 D3). `print()` is for a person at a console.
Alternative: `format()` picks ANSI when the console supports it, as
`tibble` does for its own printing; rejected, since `format()` of a `weft`
object is the plain text E1 promises everywhere.

**D4 The escapes are cli's.** The renderer calls `cli::style_italic()`,
`cli::style_bold()` and `cli::col_red()`. Those functions check
`num_ansi_colors()` themselves (on `"auto"`), so the renderer calls them with
`cli.num_colors` set locally to the count the sink decided (C5); for
`print()` that is the count for `stdout()`. Alternative: write the SGR codes
by hand. Rejected: cli's nesting rule (an inner close replaced by the outer
open) is already right, and the bytes then match whatever cli writes around
the value. Cost: a local option per rendering, negligible beside the
reader.

**D5 `cli_format.weft()` is the only hook; `{w}` stays plain.** cli calls
`cli_format()` only for `.val` (fact table). The other route to styling a
plain substitution, an entry in the theme's `class-map`, is the user's
theme: a package that sets `cli.user_theme` on load would override the
user's own. So `{w}` is plain, `{.val {w}}` is styled. Alternatives:

- *Quote, as `cli_format.character()` does.* Rejected: a `weft` text is a
  sentence, not a value to show the reader as a string; `"Found 3 sites"`
  in quotes reads as data.
- *Return the `weft` object.* Rejected: cli then pastes it, which calls
  `as.character()`, and the styles are lost (fact table).
- *Document a theme recipe for `{w}`.* Not now: it relies on how cli merges
  `class-map` into a span's style, which is internal; E5 can add it if it is
  tested against a released cli.

**D6 weft escapes nothing for cli.** A value substitution needs no escaping
(C11), and the template case is a misuse that escaping would hide only for
weft text, not for the rest of the template. A `target = "cli"` that doubles
braces was considered: it duplicates `"{w}"`, and plain text with `{{` would
be wrong in every other sink. The documentation shows `"{w}"`.

**D7 `fmt_*()` do not gain `"ansi"`.** A formatter's result goes into a
`weft()` string or a cli template; in the first case `weft()` renders it, in
the second `target = "plain"` (E1 FT1) is the form, since the only markup a
formatter writes that ANSI would show differently is `.em`, `.strong` and a
`p_label` with `*`. Alternative: accept it for symmetry; rejected, as it
adds a fourth target to every `fmt_*()` page, FT3's message and FT4's rule
for no case.

**D8 A superscript's style is decided on its plain content (C1).** A
mapped superscript (`10²`) is made of Unicode characters that cannot carry a
style from inside without splitting them; an unmapped one keeps its
content's styles inside `^( )`. Either way C3 holds.

**D9 Joined and changed elements are unstyled (C4).** Their markdown is not
markup (WS9) or no longer matches (WS10), so reading it for styles would
style text the author did not mark: `c(w, "m^2^")` would show `m²`.

**D10 cli stays in `Imports`.** It is there already; the method is
registered with `S3method(cli::cli_format, weft)`, which needs cli loaded
with weft, as `Imports` guarantees. Moving cli to `Suggests` would need a
delayed registration (`vctrs::s3_register()` style) and a fallback for
`print()`, for a package weft already loads.

## Tests

The test-writer works from this note and E1's. Helpers to add to
`tests/testthat/helper-0-common.R`:

```r
# styles on, whatever testthat set (testthat sets cli.num_colors = 1)
ansi_on <- function(env = parent.frame()) {
  withr::local_options(cli.num_colors = 256L, .local_envir = env)
}
ESC <- "\033"
```

Unicode in expectations is written in the test files with `\u` escapes, as
the suite does: ² is U+00B2, ₂ is U+2082. `\033` below is ESC.

### New tests (`test-weft-ansi.R`)

- **T1 run kinds** (C1, C2), with `ansi_on()`, `unname(format(weft(m),
  target = "ansi"))` is:

  | `m` | expected |
  |---|---|
  | `"a *b* c"` | `"a \033[3mb\033[23m c"` |
  | `"a _b_ c"` | `"a \033[3mb\033[23m c"` |
  | `"**b**"`, `"__b__"` | `"\033[1mb\033[22m"` |
  | `"***b***"` | `"\033[1m\033[3mb\033[23m\033[22m"` |
  | `"*a **b** c*"` | `"\033[3ma \033[1mb\033[22m c\033[23m"` |
  | `"*m^2^*"` | `"\033[3mm²\033[23m"` |
  | `"10^*2*^"` | `"10²"` (no escape) |
  | `"x^*ab*^"` | `"x^(\033[3mab\033[23m)"` |
  | `"CO~2~"` | `"CO₂"` |
  | `` "`code` here" `` | `"code here"` |
  | `"$x^2$ and $y$"` | `"$x^2$ and $y$"` |
  | `"[3]{.smallcaps}"` | `"3"` |
  | `"*1*<!-- -->*2*"` | `"\033[3m1\033[23m\033[3m2\033[23m"` |
  | `"<<weft: failed claim, chunk fig-a>>"` | `"\033[1m\033[31m<<weft: failed claim, chunk fig-a>>\033[39m\033[22m"` |
  | `"see <<weft: no value, line 4>> here"` | `"see \033[1m\033[31m<<weft: no value, line 4>>\033[39m\033[22m here"` |
  | `"[x]{.em}"` (a formatter's emphasis) | `"\033[3mx\033[23m"` |
  | `` "`r 2`{.num} m^2^" `` | `"2 m²"` |
  | `"plain words"` | `"plain words"` |

- **T2 strip gives plain** (C3): with `ansi_on()`, for every markdown of E1's
  reader table and per-class table that `weft()` accepts as input, and for
  the T1 inputs, `cli::ansi_strip(format(w, target = "ansi"))` is identical
  to `format(w)`, names included (give the vector names).
- **T3 when styles are written** (C5), `w <- weft("a *b*")`:
  - `withr::local_options(cli.num_colors = 1L)`: `format(w, target =
    "ansi")` is identical to `format(w)`;
  - `withr::local_options(cli.num_colors = NULL, crayon.enabled = NULL,
    knitr.in.progress = NULL)` and `withr::local_envvar(NO_COLOR = "1",
    R_CLI_NUM_COLORS = NA)`: identical to `format(w)`, and
    `grepl(ESC, ., fixed = TRUE)` is `FALSE`;
  - the same options unset, `NO_COLOR` unset, `knitr.in.progress = TRUE`:
    identical to `format(w)`;
  - `withr::local_envvar(R_CLI_NUM_COLORS = "256")` with the options unset:
    holds `"\033[3mb\033[23m"`.
- **T4 `format()` and `as.character()` stay plain** (C6): with `ansi_on()`,
  `format(w)` and `as.character(w)` hold no `ESC`; `format(w, target =
  "plain")` likewise.
- **T5 `print()`** (C7): with `ansi_on()`, `expect_output(print(weft(c("a
  *b*", "c"))), "a \033[3mb\033[23m\nc", fixed = TRUE)` (or compare
  `capture.output()` with `c("a \033[3mb\033[23m", "c")`); with
  `cli.num_colors = 1L` the lines are `c("a b", "c")`; `print(weft(c(x =
  "a")))` shows no name; `print(weft(c("a", NA)))` writes `a` and `NA`;
  `print(weft(character()))` writes `<weft[0]>`; `print()` returns its
  argument invisibly (`expect_invisible`).
- **T6 target errors** (C6, C12): `format(w, target = "html")` is a
  `weft_construct_error` with the message "`target` must be \"plain\",
  \"markdown\" or \"ansi\"; got \"html\"."; `format(w, target = 1)` ends
  "got something else."; `fmt_em("x", target = "ansi")` is E1's FT3 error
  ("`target` must be \"markdown\", \"tex\" or \"plain\"; got \"ansi\".").
- **T7 joined and changed elements** (C4): with `ansi_on()`, `x <-
  c(weft("*a*"), "*b* m^2^")`; `format(x, target = "ansi")[2]` is `"*b*
  m^2^"`; `y <- weft("*abc*"); y[1] <- "*z*"` gives `"*z*"`; `z <-
  weft("*abc*"); z <- substr(z, 1, 2)` (WS10) gives `"ab"` with no escape;
  `format(weft(c("a", NA)), target = "ansi")[2]` is `"NA"`.
- **T8 `cli_format()`** (C9): `w <- weft(c(p = "a *b*", q = "c"))`;
  - with `ansi_on()`: `out <- cli::cli_format(w)` is a bare character vector
    (`expect_identical(class(out), "character")`, `attributes(out)` is
    `list(names = c("p", "q"))`), and `out[["p"]]` is `"a \033[3mb\033[23m"`;
  - with `cli.num_colors = 1L`: `cli::cli_format(w)` is `c(p = "a b", q =
    "c")` (no quotes);
  - `cli::format_inline("Got {.val {weft('a *b*')}}.")` with `ansi_on()`
    holds `"\033[3mb\033[23m"`, and `cli::ansi_strip()` of it is `"Got a
    b."` (no quotes);
  - with `cli.num_colors = 1L`: `cli::format_inline("Got {.val {w}}.")` is
    `"Got a b and c."`;
  - the method is registered: `!is.null(utils::getS3method("cli_format",
    "weft", optional = TRUE))` after `library(weft)` (or under
    `load_all()`).
- **T9 plain substitution** (C10): with `ansi_on()`,
  `cli::format_inline("Got {w}.")` for `w <- weft("a *b*")` is `"Got a b."`
  with no `ESC`.
- **T10 braces** (C11): `w <- weft("Index $x_{no_such_object_e3}$ here")`
  (math keeps its TeX, PL3; no object of that name exists);
  `cli::format_inline("{w}")` is `"Index $x_{no_such_object_e3}$ here"`, and
  `cli::ansi_strip(cli::format_inline("{.val {w}}"))` is the same (nothing
  is evaluated); and, to pin the documented hazard,
  `expect_error(cli::format_inline(as.character(w)))` (cli evaluates the
  braces of a template).
- **T11 sinks unchanged** (C8): with `ansi_on()`, `paste0(w)`,
  `sprintf("%s", w)`, `capture.output(cat(w))` and `message(w)` (through
  `expect_message`) hold no `ESC`; `format(w, target = "markdown")` is E1's
  markdown.

### Existing tests that change

- E1's test of the `format()` target error (T7 of `dev/design-e1.md`,
  "`format(w, target = "tex")` gives the WS7 error") expects the new text of
  C6.
- E1's `print()` tests run under testthat's `cli.num_colors = 1`, so they
  stand.

## Rule edits for `dev/PACKAGE-SCOPING.md`

Against the text E1 writes (its §3.6).

**3.6.3**, the WS7 table, rows added and changed:

| Call | Gives |
|---|---|
| `format(x, target = "ansi")` | the console form (3.6.9); names kept; `NA` is `"NA"` |
| `format(x, target = other)` | `weft_construct_error`: "`target` must be \"plain\", \"markdown\" or \"ansi\"; got %s." |
| `print(x)` | each element on its own line, in the console form when the console draws styles (3.6.9), else plain; `NA` as `NA`; names not shown; a length-0 object prints `<weft[0]>`; returns `x` invisibly |

**3.6.9** (new) In a console, a `weft` text keeps its emphasis. The console
form of an element is its plain form (1.4.24) with emphasis in italic, strong
emphasis in bold, both for `***`, and each failure marker (2.6.8) in bold red;
nothing else differs, so with the styles removed it is the plain form. A
superscript or subscript that has Unicode characters takes no style from
inside. An element joined by `c()` or `[<-`, or changed by a function, is
plain. The styles are written only where cli writes its own
(`cli::num_ansi_colors()`): not under `NO_COLOR`, in a knit, into a sink or
a file, or on a terminal without colour. `print()` uses the console form for
standard output; `format(x)` and `as.character(x)` are always plain.

**3.6.10** (new) Inside cli's messages, `{.val {x}}` draws a `weft` text in
its console form, unquoted, in cli's value colour; `{x}` gives the plain
text. A `weft` text given to cli as a value is never read as a cli template,
so braces in it are text. Given as the template itself (`cli_inform(x)`), it
is read by cli, which evaluates what it finds in braces: pass it as `"{x}"`.
Markup is not written into a cli template: it is resolved by `weft()` first.

```r
w <- weft("Depth at *[one site | # sites]{n='k'}*: `r d`{.num unit='m'}")
cli::cli_inform("{.val {w}}")          # emphasis drawn, in the value colour
cli::cli_inform("Plotted {w}")         # plain text
msg <- cli::format_inline("{.val {w}}")
```

Part 2:

**3.6.9** (new) A console can draw emphasis, and a title typed with
`*Eucalyptus*` loses it in the plain form. The console form adds styles and
changes no character, so a log that strips escapes holds the plain text and
the two forms are checked against each other. When to draw them is cli's
decision, not weft's: cli already knows `NO_COLOR`, knitr, sinks and the
terminals, and a weft text inside a cli message must agree with the styling
cli draws around it. `format()` stays plain because it feeds plots, files
and `paste()`, which must not change with the terminal.

**3.6.10** (new) cli reads a template once and inserts values after, so a
value is safe and a template is not; weft escapes nothing, because escaping
would be needed in one sink and wrong in every other.

## Documentation

- `R/weft.R` (E1's file): roxygen for `format.weft()` names `"ansi"` under
  `target`; `print.weft()` says when it draws styles; a section "In the
  console and in cli" with C9 to C11 and the three-line example of 3.6.10.
  `@exportS3Method cli::cli_format` on `cli_format.weft()`, documented on the
  same page (`@rdname weft`). `devtools::document()` regenerates `NAMESPACE`
  and `man/weft.Rd`.
- `NEWS.md`: "`print()` of a `weft` object draws emphasis in a console that
  supports it; `format(x, target = "ansi")`; `{.val {x}}` in cli messages."
- Vignettes: none in E3. E5's strings article takes the console section
  (3.6.9, 3.6.10) and the cli example.
- `inst/agent/references/syntax.md` and `skills/weft`: E5.

## Order of work

1. Test-writer: the helper, T1 to T11, and the E1 test text change. Check
   that T1, T5, T8 fail because `"ansi"` is refused and no method is
   registered, and that T2 fails for the same reason, not for E1 behaviour.
2. Implementer:
   1. The ANSI renderer over E1's runs, beside the plain renderer in
      `R/plain.R` (T1, T2, T7).
   2. `format()` target `"ansi"` and the error text; `print()` (T3 to T6).
   3. `cli_format.weft()` and its registration (T8 to T10).
   4. Roxygen, `document()`, `NEWS.md`.
3. Whole suite (one R process), review, then the spec editor applies the
   rule edits.

## For the orchestrator

Nothing needs Robin. Two choices a reviewer may want to see confirmed:

1. **`format(x, target = "ansi")` gives plain text where cli draws no
   styles** (D2), so the form cannot be forced into a file without setting
   `cli.num_colors`. The alternative (always escapes) is one line to switch.
2. **The failure marker is bold red** (D1). It is the only colour weft
   adds; dropping it leaves only font styles.
