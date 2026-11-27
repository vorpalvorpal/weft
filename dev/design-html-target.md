# Design: an HTML target and rich plot text (ggtext, marquee)

Written 27 Nov 2026, on Robin's ruling of 27 Nov that the three "Later" pieces
of `dev/plan-weft-everywhere.md` are to be built now. This note covers one of
them: "An HTML target and rich plot text (ggtext, marquee)". It follows the
shape of `dev/design-9.md` (the TeX target). It is the contract for a
test-writer who does not read `R/` and an implementer who does not edit tests.

**Conventions.** This file is ASCII. `\uXXXX` in a table or an example stands
for that one character: `\u2212` is the minus sign, `\u00d7` the multiply
sign, `\u00a0` the no-break space, `\u2009` the thin space, `\u2013` the en
dash, `\u00b7` the middle dot, `\u00b0` the degree sign. In the marquee
tables, `[NL]` stands for one newline character (U+000A). Everything else in
a code span is literal.

**Numbering.** Decisions continue from D85 (design 9): D86 to D104. Messages
continue from E106: E107 to E111. Rule ids local to this note: **HR** (the
HTML rendering), **MQ** (the marquee rendering), **RT** (targets, objects and
errors), **RS** (sinks and checks). Spec rules proposed: 1.4.25, 1.4.26,
3.6.11, with amendments to 1.4.8, 1.4.10, 2.5.3, 3.4.11, 3.6.3, 3.6.4 and
5.6.4.

## What I found and what I recommend

- **Today.** weft has three formatter targets: `"markdown"` (the default),
  `"tex"` (design 9) and `"plain"` (package E1). A `weft` object also formats
  as `"ansi"` (package E3). Plain ggplot2 text is served: a `weft` object or a
  `target = "plain"` formatter draws correct Unicode text. Rich plot text is
  not. ggtext reads weft's markdown only by accident, and gets negative
  exponents, spans, lists and spacing wrong; one list makes the plot fail to
  draw. marquee reads weft's subscripts as strikethrough and its
  superscripts as raw carets, and it silently drops HTML tags, so
  `10<sup>\u22124</sup>` draws as "10\u22124", a different number.
- **What to build.** Two new targets, both renderers over the runs the plain
  reader already makes (`R/plain.R`), as `"ansi"` is:
  - `"html"`: a small tag set (`<i> <b> <sup> <sub> <span> <br>`) and an
    escaping that survives the markdown pass ggtext makes first. One form
    serves ggtext, gt, reactable, htmltools and plotly.
  - `"marquee"`: marquee's own dialect, with `{.sup ...}`, `{.sub ...}`,
    `{.em ...}` and `{.str ...}` custom spans and CommonMark backslash escapes.
  - Both are values of `target` on every `fmt_*()` and on `format()` of a
    `weft` object. Every class has a form in both (D87).
- **`"plain"` is not widened.** An ASCII form and a plotmath form are sketched
  for later (D100).
- **Nothing changes in the ledger or the gate** (D99). The ledger records the
  markdown when `weft()` runs; the target is chosen later, at the sink.
- **The Lua filter needs no target.** `weft-check.lua` should read raw HTML for
  failure markers (a gap that exists today for gt tables). Python and Julia get
  a sketch only (D102).
- **One existing defect found.** `check_targets()` (`R/config.R:494`) tests
  `got %in% TARGETS`, and `TARGETS` holds `"plain"`, so `targets: [markdown,
  plain]` is accepted although rule 1.4.8 says `targets:` does not list plain.
  Adding `"html"` and `"marquee"` to `TARGETS` would widen the hole. Fixed in
  stage H1 (D104).
- **What I could not check.** I ran no R (another session holds the one R
  process). The behaviour of ggtext, marquee and plotly below comes from their
  source code, read on GitHub: gridtext 0.1.5 (`R/richtext-grob.R`,
  `R/process-tags.R`), markdown 1.13 and 2.0, litedown 0.7, marquee 1.0.0,
  1.2.0 and the development version 1.3.0.9000 (`src/marquee.cpp`,
  `R/classic_style.R`), plotly.js `src/lib/svg_text_utils.js`. marquee is not
  installed on this Mac. Stage H0 is a probe that confirms or corrects every
  sink claim before the tests are written.

---

## 1. The problem

### 1.1 What weft writes today (markdown target, default settings)

| Formatter, value | Markdown |
|---|---|
| `.num` -1234567.89 | `\u22121,234,567.9` |
| `.num` 1234567.89, `big_mark: "\u2009"` | `1\u2009234\u2009567.9` |
| `.pct` 0.123 | `12.3%` |
| `.sci` 1234567 | `1.2 \u00d7 10^6^` |
| `.sci` -0.000123 | `\u22121.2 \u00d7 10^\u22124^` |
| `.p` 0.0001 / 0.995 | `p < 0.001` / `p > 0.99` |
| `.p` 0.0001, `p_label: "*p*"` | `*p* < 0.001` |
| `.range` c(1.23, 3.45) / c(-1, 3) | `1.2\u20133.5` / `\u22121 to 3` |
| `u(5, mg/L)` | `5\u00a0mg/L` |
| `u(5, m^2)` / `u(5, s^-1)` | `5\u00a0m^2^` / `5\u00a0s^\u22121^` |
| `u(5, kg*m/s^2)` | `5\u00a0kg\u00b7m/s^2^` |
| `.em` / `.strong` | `*x*` / `**x**` |
| `.ul` c("a", "b") | `- a[NL]- b` |
| `.ol` c("a", "b") | `1. a[NL]2. b` |
| `.dl` c(a = "1", b = "2") | `a[NL]:   1[NL][NL]b[NL]:   2` |
| a class weft does not own | `[x]{.smallcaps}` |
| a subscript in a project symbol or the author's text | `H~2~O` |
| a failure marker | `<<weft: no value, line 3>>` |

### 1.2 Plain ggplot2 text (`element_text()`)

- A markdown string, as `fmt_*()` returns by default, shows its markup:
  `1.2 \u00d7 10^\u22124^`, `5 m^2^`, `*Eucalyptus*`, `[x]{.smallcaps}`.
- A `weft` object, or `target = "plain"`, is right today: `1.2 \u00d7
  10\u207b\u2074`, `5 m\u00b2`, `Eucalyptus` with no marks. Emphasis is lost:
  a species name cannot be italic. A superscript with letters falls back to
  `^(n)`. The default `pdf()` device cannot draw the minus sign or the
  superscripts (rule 3.6.4 already says so).
- So plain text needs nothing new. What is missing is emphasis, colour and real
  superscripts, which only a rich-text sink can draw.

### 1.3 ggtext (`element_markdown()`, `geom_richtext()`)

ggtext hands the label to `gridtext::richtext_grob()`, which runs
`markdown::markdownToHTML()` on it, parses the result with `xml2`, and draws
only the tags `b strong i em br p span sup sub img`. Any other tag stops the
draw with "gridtext has encountered a tag that isn't supported yet". Text runs
are split on white space (`stringr::str_squish()` and `[[:space:]]+`).

| weft markdown in ggtext | What draws |
|---|---|
| `1.2 \u00d7 10^6^` | right: the markdown package's own superscript extension takes `^6^` |
| `1.2 \u00d7 10^\u22124^` | wrong: the extension takes only `[[:alnum:]*()]` (markdown 1.13) or `[[:alnum:]*(),.]` (litedown 0.7), so the carets show |
| `5\u00a0s^\u22121^` | wrong, as above |
| `5\u00a0m^2^` | right |
| `H~2~O` | right with markdown's subscript extension; depends on its version |
| `1\u2009234\u2009567.9`, `5\u00a0mg/L` | the thin and no-break spaces draw as ordinary word spaces (gridtext splits on every white-space character) |
| `*x*`, `**x**` | right |
| `- a[NL]- b` (`.ul`), `.ol` | **the plot fails to draw**: markdown makes `<ul>`, which gridtext refuses |
| `[x]{.smallcaps}` | brackets and braces show |
| `$x^2$` (a formula kept in a string) | markdown's `latex_math` writes `\(x^2\)`, which shows as typed |
| a newline in a `weft()` string | drawn as a space |
| `p < 0.001`, the failure marker | right (commonmark escapes the `<`) |

A `weft` object (plain text) in ggtext mostly draws, but a literal `*`, `_` or
`<b>` in the plain text is read as markup, and newlines are lost. The result
also depends on which markdown package is installed: 1.13 runs smartypants
(`1/2` becomes a fraction, `(c)` a copyright sign), 2.0 does not.

### 1.4 marquee (`element_marquee()`, `geom_marquee()`)

marquee parses with md4c, with strikethrough and underline on, so `~x~` is
strikethrough and `_x_` is underline. It has no superscript syntax: its style
set has `sup` and `sub` styles reached only as custom spans (`H{.sub 2}O`),
since marquee 1.2.0. It reads `$...$` as math from 1.3.0. With its default
`ignore_html = TRUE`, it drops every HTML tag and keeps the text inside.

| Input to marquee | What draws |
|---|---|
| markdown `1.2 \u00d7 10^\u22124^`, `5 m^2^` | carets show |
| markdown `H~2~O` | "H2O" with the 2 struck through |
| the author's `_Eucalyptus_` kept in the markdown | underlined, not italic |
| markdown `[x]{.smallcaps}` | brackets show; the braces may open a custom span |
| markdown `.ul` | a real bulleted list block |
| **HTML** `1.2 \u00d7 10<sup>\u22124</sup>` | **"1.2 \u00d7 10\u22124": a wrong number, with no error** |
| HTML `<i>x</i>` | "x", not italic |
| a `weft` object (plain) | right for numbers and units; a literal `*`, `_`, `~` or `{` is read as markup |

### 1.5 HTML tables and widgets

- **gt.** `fmt_markdown()` uses commonmark with no superscript extension, so
  weft's markdown shows `10^\u22124^`. Plain text is right, with no emphasis.
  HTML through `fmt_markdown()` or `gt::html()` is right in HTML output. gt
  converts to Word or PDF with the tags dropped (to be confirmed in H0).
- **reactable** with `colDef(html = TRUE)`, **htmltools** with `HTML()`:
  HTML is right; markdown shows its marks.
- **plotly** text and hover text read a pseudo-HTML subset: `b i sup sub span
  br a s u` and `em`, which plotly draws bold italic. `strong` is not read.
  Entities: `&amp; &lt; &gt; &nbsp; &times; &plusmn; &deg; &mu;` and numeric
  ones.

### 1.6 What follows from this

- Rich sinks need weft's own HTML, not its markdown: the markdown pass in
  ggtext is version-dependent and does not cover negative exponents.
- marquee needs its own form. HTML there is the worst case: tags vanish and a
  number changes. Markdown there is wrong in four ways.
- Plain text is fine as it is.

---

## 2. Decisions

| # | Question | Options | Chosen | Why |
|---|---|---|---|---|
| D86 | Which targets | (a) `"html"` only; (b) `"html"` and `"marquee"`; (c) one CommonMark-subset target for both plot packages, superscripts as Unicode; (d) a `"ggtext"` target apart from `"html"`; (e) detect the sink | **(b)** | (a) leaves marquee with silent wrong numbers; (c) gives up real superscripts and spans, and gt still needs HTML; (d) is not needed, one HTML form survives ggtext's markdown pass (D88); (e) is impossible, ggtext and marquee call `as.character()` and weft never sees the sink |
| D87 | How the forms are made | (a) renderers over the plain reader's runs, as `"plain"` and `"ansi"`; (b) an emitter table in each formatter, as `"tex"` | **(a)** | every class gets a form for free; html, marquee and plain never disagree; one reader to keep right. Cost: a list is its markdown lines (D91) |
| D88 | One HTML for ggtext and for browsers | (a) plain HTML; (b) HTML whose text also survives a markdown pass | **(b)** | ggtext always runs markdown first, and so does gt's `fmt_markdown()`. The cost is numeric entities (`&#42;`) in the HTML, which every HTML reader decodes |
| D89 | Emphasis tags | `<i>`/`<b>`; `<em>`/`<strong>` | **`<i>`/`<b>`** (For Robin 1) | gridtext reads both; plotly draws `em` bold italic and ignores `strong` |
| D90 | Superscripts in HTML | `<sup>`/`<sub>`; Unicode when every character has one, else tags | **tags** (For Robin 2) | the sinks that want HTML draw tags well; Unicode-first makes the HTML of a number the same as its plain text, so there is little reason to ask for it |
| D91 | Lists | `<ul><li>`; lines joined by `<br>`, list markers as text | **lines** | gridtext refuses `<ul>` and stops the plot; plain keeps a list's lines too |
| D92 | Spans that weft passes through | content only; a `<span>` with the attributes as Pandoc writes them | **html: `<span>`; marquee: content only** | `[Depth]{style='color:#c00'}` then colours the word in ggtext, plotly, gt and the knit's own HTML alike. marquee has no attributes; mapping classes to custom spans is sketched (S3) |
| D93 | Raw HTML tags the author writes in a `weft()` string | text, escaped; passed through | **text** (For Robin 3) | the plain reading already treats any tag but `<sup>`/`<sub>` as text; a span with `style` does the same job and works in documents too |
| D94 | Code spans | html: `<code>`, text, a monospace span; marquee: a code span | **html: text; marquee: a code span** | gridtext refuses `<code>`; gridtext's span style does not promise a monospace family; marquee has a `code` style |
| D95 | A formula kept as written (PL3) | escape it; keep it | **html: text, escaped; marquee: kept as math** | ggtext would rewrite `$...$`; marquee 1.3.0 draws math, older versions show it as typed |
| D96 | Emphasis in marquee | `*x*`/`**x**`; `{.em x}`/`{.str x}` | **custom spans** | custom spans have no flanking rules, so escaped neighbours (`*\[a\]*b`) cannot undo them; they are marquee's own form for `sup` and `sub` too |
| D97 | Mixing targets | allow; refuse | **refuse**, as for TeX | an HTML or marquee text read again as markdown loses its tags or shows them. Put the target on the outermost call |
| D98 | What `format(x, target = "html")` returns | a character vector; one with class `c("html", "character")` | **class `html`** (For Robin 4) | that is the class `htmltools::HTML()` gives, so htmltools, Shiny and gt's HTML helpers take it unescaped. No dependency |
| D99 | Ledger and gate | record the target; unchanged | **unchanged** | the target is unknown when `weft()` records; the markdown is the source of every form |
| D100 | Widen `"plain"` | no; an `"ascii"` target; a plotmath target | **no** | plain already serves plain sinks. ASCII and plotmath are sketched (S1, S2) |
| D101 | Constructs inside `{=html}` raw blocks in a document | write HTML there now; later | **later** (For Robin 5) | it is a scanner change, the analogue of design 9's raw LaTeX; this package is about strings |
| D102 | Lua, Python, Julia | targets in each; none | **none; `weft-check.lua` reads raw HTML for markers** | the filter writes into documents, where Pandoc makes the HTML. Python's `weft_str(target =)` is sketched (S4) |
| D103 | An old marquee | ignore; check the installed version | **check** | marquee before 1.2.0 has no `sup` style and draws `10{.sup \u22124}` as "10\u22124" |
| D104 | `targets:` of a project formatter | add html and marquee; unchanged | **unchanged, and the check fixed** | html and marquee, like plain, are read from the formatter's markdown |

---

## 3. Specification

### RT: targets, objects and errors

**RT1 (values).** `TARGETS` becomes `c("markdown", "tex", "plain", "html",
"marquee")`. Every `fmt_*()` and `apply_formatters()` takes them. E100's text
becomes: "`target` must be \"markdown\", \"tex\", \"plain\", \"html\" or
\"marquee\"; got %s." `format()` of a `weft` object takes `"plain"`,
`"markdown"`, `"ansi"`, `"html"` and `"marquee"`; its message becomes
"`target` must be \"plain\", \"markdown\", \"ansi\", \"html\" or \"marquee\";
got %s." Both stay `weft_construct_error`.

**RT2 (how a form is made).** Under `"html"` or `"marquee"` a formatter runs
exactly as under `"markdown"` (so `f$target` is `"markdown"` inside, as for
plain), then its text is read by PL1 to PL10 (rule 1.4.24) and the runs are
rendered by HR or MQ. The `unit` and `unit_suffix` attributes are rendered the
same way. A project formatter is called as for markdown.

**RT3 (attribute).** The result carries `target = "html"` or `target =
"marquee"`, keeps its printed record (`number`, `decimals`, `relation`, `raw`),
and its `unit_form`, `units` and `unit_before` attributes.

**RT4 (`weft` objects).** `format(x, target = "html")` renders each element:

- an element whose plain text is the plain reading of its markdown: its
  markdown, read by PL and rendered by HR;
- an element joined as text by `c()` or `[<-`, or changed by a function that
  kept the attributes (the WS10 test that `weft_ansi()` uses): its plain text,
  escaped as HR text (HR2), newlines as HR5;
- `NA`: `"NA"`. Names are kept.
- The result has class `c("html", "character")` (D98, For Robin 4).
- `"marquee"` is the same with MQ, and returns a bare character vector.

**RT5 (mixing).**

- A `weft_text` whose `target` is `"html"` or `"marquee"`, given to any
  formatter, is a `weft_value_error` unless the formatter formats it again from
  its raw number (a number class is in force, as for E103), **E107**: "This
  text was formatted for %s (target = \"%s\"), and weft cannot format it again.
  Give the formatter the value itself, or a text made without `target`, and put
  `target` on the outer call: fmt_strong(fmt_num(x), target = \"%s\") (rule
  3.4.11)." The first `%s` is `HTML` or `marquee`.
- A text made under `"tex"` reaching an `"html"` or `"marquee"` result is
  **E108**, a `weft_value_error`: "This text was formatted for TeX (target =
  \"tex\") and would print here as %s. Format the number again, with target =
  \"%s\" (rule 3.4.11)." The first `%s` is `HTML` or `marquee text`.
- A text made under `"plain"` given to a formatter is read as markdown, as now.
- `c()` or `[<-` of a `weft` object with a `weft_text` whose `target` is
  `"tex"`, `"html"` or `"marquee"` is a `weft_construct_error`, **E109**: "A
  text formatted for %s (target = \"%s\") cannot join a weft text: its markup
  would be read as text. Join texts made without `target`, then format the
  result (rule 3.6.3)." `%s` is `TeX`, `HTML` or `marquee`.
- The messages for TeX (E103 and the "plain text" variant) keep their text.

**RT6 (`fmt_unit()`).** Takes the two new targets:
`fmt_unit(u(1, m^2), target = "html")` is `m<sup>2</sup>`; with
`"marquee"` it is `m{.sup 2}`.

### HR: the HTML rendering (rule 1.4.25)

**HR1 (tags).** weft writes only `<i>`, `<b>`, `<sup>`, `<sub>`, `<span>` and
`<br>`: the tags gridtext, plotly and every browser read.

**HR2 (text).** In a text run each character maps as below; every other
character is written as it is, in UTF-8 (the minus, the multiply sign, the
spaces, the en dash and the degree sign are characters, not entities).

| Character | HTML | Why |
|---|---|---|
| `&` | `&amp;` | HTML |
| `<` | `&lt;` | HTML |
| `>` | `&gt;` | HTML |
| `*` | `&#42;` | markdown pass |
| `_` | `&#95;` | markdown pass |
| `` ` `` | `&#96;` | markdown pass |
| `\` | `&#92;` | markdown pass |
| `[` | `&#91;` | markdown pass |
| `]` | `&#93;` | markdown pass |
| `^` | `&#94;` | markdown's superscript extension |
| `~` | `&#126;` | markdown's subscript and strikethrough |
| `$` | `&#36;` | markdown's `latex_math` |
| `{` | `&#123;` | attribute syntax in markdown and litedown |
| `}` | `&#125;` | as above |
| `/` between two digits | `&#47;` | smartypants fractions (markdown 1.x) |
| `(` before `c)`, `r)` or `tm)` | `&#40;` | smartypants symbols |

**HR3 (the start of the text).** The first character of the whole result, when
it is text (not a tag):

- `#`, `-`, `+`, `=` become `&#35;`, `&#45;`, `&#43;`, `&#61;`;
- a space or a tab becomes `&#32;` or `&#9;`;
- a run of digits followed by `.` or `)` and then a space or the end: the `.`
  or `)` becomes `&#46;` or `&#41;`.

These stop the markdown pass from reading a heading, a list, an indented code
block or a setext line. Only the start needs them: weft writes no newline
(HR5), so no other line starts.

**HR4 (runs).**

| Run | HTML |
|---|---|
| text | HR2 |
| code | its text, by HR2 (no tag: gridtext refuses `<code>`) |
| math | as written, delimiters included, by HR2 (`$x^2$` is `&#36;x&#94;2&#36;`) |
| em | `<i>` kids `</i>` |
| strong | `<b>` kids `</b>` |
| sup | `<sup>` kids `</sup>` |
| sub | `<sub>` kids `</sub>` |
| span | `<span` attributes `>` kids `</span>` (HR6); with no attributes, the kids alone |
| an empty em, strong, sup, sub or span | nothing |

Strong emphasis `***x***` is an em and a strong nested as the reader nests
them.

**HR5 (line breaks).** Each newline (`\n`, or `\r\n` as one) is `<br>`. Two
newlines are `<br><br>`.

**HR6 (span attributes).** The span's block is read by the scanner's attribute
parser (`parse_block_strict()`):

- an id: `id="..."`;
- classes: `class="a b"`, in the order written;
- the keys `style`, `title`, `lang` and `dir`: as themselves;
- any other key: `data-KEY="..."`, as Pandoc's HTML writer does;
- order: id, class, then keys in the order written;
- values escape `&`, `<`, `>` and `"` as `&amp; &lt; &gt; &quot;`, and the
  markdown-pass characters of HR2 as their numeric entities.

**HR7 (markers).** A failure marker is text: `&lt;&lt;weft: no value, line
3&gt;&gt;`.

**HR8 (what weft does not promise).** ggtext draws every white-space
character, the thin and no-break spaces included, as an ordinary word space;
in `element_textbox()` a line may break between a number and its unit.

### MQ: the marquee rendering (rule 1.4.26)

**MQ1 (text).** In a text run a backslash goes before each of
`` \ ` * _ ~ [ ] { } < > & $ ^ ``. Every other character is written as it is.
There is no smartypants in marquee, so `/` and `(` stay.

**MQ2 (the start of each line).** At the start of the result and after each
written line break (MQ4):

- `#`, `-`, `+`, `=` and `:` get a backslash before them;
- a run of digits followed by `.` or `)` and then a space or the end: a
  backslash before the `.` or `)`;
- each leading space or tab becomes U+00A0, so that four of them do not make
  an indented code block.

**MQ3 (runs).**

| Run | marquee |
|---|---|
| text | MQ1 |
| code | a code span: a run of backticks one longer than the longest run inside, the text, the same run; a space inside each end when the text starts or ends with a backtick |
| math | as written (D95) |
| em | `{.em ` kids `}` |
| strong | `{.str ` kids `}` |
| sup | `{.sup ` kids `}` |
| sub | `{.sub ` kids `}` |
| span | the kids alone (attributes dropped, as in plain) |
| an empty em, strong, sup, sub or span | nothing |

**MQ4 (line breaks).** One newline is a hard break: `\` then the newline. Two
or more newlines are one blank line (`[NL][NL]`), a paragraph break.

**MQ5 (markers).** Text: `\<\<weft: no value, line 3\>\>`.

**MQ6 (version, D103).** When the result holds a `{.sup` or `{.sub` span and
marquee is installed at a version below 1.2.0, the call is a
`weft_config_error`, **E110**: "marquee %s draws {.sup } and {.sub } as
ordinary text, so 10{.sup -4} would draw as 10-4. Install marquee 1.2.0 or
later (rule 3.6.11)." The version is read once per session without loading
the package (`utils::packageDescription("marquee", fields = "Version")`), so
the check costs nothing after the first call. With marquee not installed there
is no check: the text may be drawn elsewhere.

### The forms, side by side (default settings)

Every row is one test (section 6). `fmt_*()` calls and `format(weft(...),
target = )` give the same text for the same markdown.

**Numbers and classes**

| Input | `target = "html"` | `target = "marquee"` |
|---|---|---|
| `fmt_num(-1234567.89)` | `\u22121,234,567.9` | `\u22121,234,567.9` |
| `fmt_num(1234567.89)`, `big_mark: "\u2009"` | `1\u2009234\u2009567.9` | `1\u2009234\u2009567.9` |
| `fmt_num(3, plus = TRUE)` | `&#43;3` | `\+3` |
| `fmt_num(-3)`, `minus: "-"` | `&#45;3` | `\-3` |
| `fmt_pct(0.123)` | `12.3%` | `12.3%` |
| `fmt_sci(1234567)` | `1.2 \u00d7 10<sup>6</sup>` | `1.2 \u00d7 10{.sup 6}` |
| `fmt_sci(-0.000123)` | `\u22121.2 \u00d7 10<sup>\u22124</sup>` | `\u22121.2 \u00d7 10{.sup \u22124}` |
| `fmt_sci(0)` | `0` | `0` |
| `fmt_p(0.0001)` | `p &lt; 0.001` | `p \< 0.001` |
| `fmt_p(0.03)` | `p = 0.030` | `p = 0.030` |
| `fmt_p(0.995)` | `p &gt; 0.99` | `p \> 0.99` |
| `fmt_p(0.0001)`, `p_label: "*p*"` | `<i>p</i> &lt; 0.001` | `{.em p} \< 0.001` |
| `fmt_range(c(1.23, 3.45))` | `1.2\u20133.5` | `1.2\u20133.5` |
| `fmt_range(c(-1, 3))` | `\u22121 to 3` | `\u22121 to 3` |
| `fmt_range(c(1, 3), plus = TRUE)` | `&#43;1 to +3` | `\+1 to +3` |
| `fmt_word(3)` | `three` | `three` |
| `fmt_a(8)` | `an 8` | `an 8` |
| `fmt_date(as.Date("2024-03-05"))` | `5 March 2024` | `5 March 2024` |
| `fmt_and(c(1, 2, 3))` | `1, 2 and 3` | `1, 2 and 3` |
| `fmt_em("Eucalyptus")` | `<i>Eucalyptus</i>` | `{.em Eucalyptus}` |
| `fmt_strong("high")` | `<b>high</b>` | `{.str high}` |
| `fmt_ul(c("a", "b"))` | `&#45; a<br>- b` | `\- a\[NL]\- b` |
| `fmt_ol(c("a", "b"))` | `1&#46; a<br>2. b` | `1\. a\[NL]2\. b` |
| `fmt_dl(c(a = "1", b = "2"))` | `a<br>:   1<br><br>b<br>:   2` | `a\[NL]\:   1[NL][NL]b\[NL]\:   2` |

**Units**

| Input | `"html"` | `"marquee"` |
|---|---|---|
| `fmt_num(u(5, mg/L))` | `5\u00a0mg/L` | `5\u00a0mg/L` |
| `fmt_num(u(5, m^2))` | `5\u00a0m<sup>2</sup>` | `5\u00a0m{.sup 2}` |
| `fmt_num(u(5, s^-1))` | `5\u00a0s<sup>\u22121</sup>` | `5\u00a0s{.sup \u22121}` |
| `fmt_num(u(5, kg*m/s^2))` | `5\u00a0kg\u00b7m/s<sup>2</sup>` | `5\u00a0kg\u00b7m/s{.sup 2}` |
| `fmt_num(u(20, degC))` | `20\u00a0\u00b0C` | `20\u00a0\u00b0C` |
| `fmt_num(u(5, mg/L), unit_form = "name")` | `5\u00a0milligrams per litre` | `5\u00a0milligrams per litre` |
| `fmt_range(u(c(1.2, 3.4), m))` | `1.2\u20133.4\u00a0m` | `1.2\u20133.4\u00a0m` |
| `fmt_unit(u(1, m^2))` | `m<sup>2</sup>` | `m{.sup 2}` |

**Text an author writes in `weft()`**

| `weft(...)` | `"html"` | `"marquee"` |
|---|---|---|
| `"*Eucalyptus* sp."` | `<i>Eucalyptus</i> sp.` | `{.em Eucalyptus} sp.` |
| `"_Eucalyptus_ sp."` | `<i>Eucalyptus</i> sp.` | `{.em Eucalyptus} sp.` |
| `"H~2~O"` | `H<sub>2</sub>O` | `H{.sub 2}O` |
| `"10^n^"` | `10<sup>n</sup>` | `10{.sup n}` |
| `"m<sup>2</sup>"` | `m<sup>2</sup>` | `m{.sup 2}` |
| `"1.2 &times; 10"` | `1.2 \u00d7 10` | `1.2 \u00d7 10` |
| `"[Depth]{style='color:#c00'} at 4"` | `<span style="color:#c00">Depth</span> at 4` | `Depth at 4` |
| `"[x]{.smallcaps}"` | `<span class="smallcaps">x</span>` | `x` |
| `"[x]{#a .b custom-style='C'}"` | `<span id="a" class="b" data-custom-style="C">x</span>` | `x` |
| `"2 \\* 3"` (markdown `2 \* 3`) | `2 &#42; 3` | `2 \* 3` |
| `"a & b < c"` | `a &amp; b &lt; c` | `a \& b \< c` |
| `"snake_case_name"` | `snake&#95;case&#95;name` | `snake\_case\_name` |
| `"a {b}"` | `a &#123;b&#125;` | `a \{b\}` |
| `"$x^2$ is"` | `&#36;x&#94;2&#36; is` | `$x^2$ is` |
| ``"Run `f()` now"`` | `Run f() now` | ``Run `f()` now`` |
| `"1/2 of (c) sites"` | `1&#47;2 of &#40;c) sites` | `1/2 of (c) sites` |
| `"# 3 sites"` | `&#35; 3 sites` | `\# 3 sites` |
| `"Line one\nline two"` | `Line one<br>line two` | `Line one\[NL]line two` |
| `"<span style='x'>a</span>"` | `&lt;span style='x'&gt;a&lt;/span&gt;` (For Robin 3) | `\<span style='x'\>a\</span\>` |
| a failure marker | `&lt;&lt;weft: no value, line 3&gt;&gt;` | `\<\<weft: no value, line 3\>\>` |
| `c(weft("a"), "b*c*")[2]` (joined as text) | `b&#42;c&#42;` | `b\*c\*` |
| `NA` | `NA` | `NA` |

### RS: sinks and checks

**RS1 (which form goes where).** The documentation's sink table (3.6.4)
gains these rows:

| Sink | Form |
|---|---|
| `element_text()`, `geom_text()`, scale labels | plain (the `weft` object, or `target = "plain"`) |
| ggtext `element_markdown()`, `element_textbox()`, `geom_richtext()`, `geom_textbox()` | `format(x, target = "html")`; scale labels `fmt_*(target = "html")` |
| marquee `element_marquee()`, `geom_marquee()`, `guide_marquee()` | `format(x, target = "marquee")` |
| gt: HTML output only | `format(x, target = "html")` with `fmt_markdown()` or `gt::html()` |
| gt, flextable, kable in a document for Word or PDF | plain, or markdown where the table reads Pandoc markdown (kable) |
| reactable `colDef(html = TRUE)`, htmltools, Shiny, DT with `escape = FALSE`, leaflet popups | `"html"` |
| plotly `text` and hover text | `"html"` |

**RS2 (no automatic form).** A `weft` object given straight to ggtext or marquee
draws its plain text (both call `as.character()`). weft cannot see the sink,
so the author writes `format(x, target = )`.

**RS3 (lint, rule 5.6.4).** `value-format` (tier 2) adds: a bare value in prose
whose outermost call is a weft `fmt_*()` with `target = "html"` or
`target = "marquee"` given as a literal, **E111**: "The value in prose is
formatted with `%s(target = \"%s\")`, which writes %s; a document shows its
marks or drops its tags (rule 5.6.4)." The third `%s` is `HTML` or `marquee
text`. Hint: "Give it a class block, `` `r x`{.num} ``, which writes markdown."
A bare `format(w, target = "html")` is already found by the `format()` case.

**RS4 (the `weft-check` filter, rule 2.5.3).** `RawInline` and `RawBlock`
elements whose format is `html` are searched for `<<weft:` and for
`&lt;&lt;weft:`, as text is now. This covers a marker in a gt or reactable
cell, which today escapes the backstop.

### Ledger and gate (D99)

- `weft()` evaluates and records at the call (rule 3.6.2). The entry's context
  is `weft`, its text is the markdown, and its key is unchanged. `format()`
  records nothing, however often it runs, and whichever target it takes.
- So a plot title made with `weft()` and drawn by ggtext has the same entry as
  one drawn as plain text. Moving a title from `element_text()` to
  `element_markdown()` is not a change in `changes()`. That is right: the words
  did not change.
- A claim in a `weft()` string is checked each time `weft()` runs, as now. The
  gate counts the literal once (E4), wherever its text is drawn.
- `fmt_*(target = "html")` in chunk code (a scale's labels) records nothing,
  as any `fmt_*()` call in code does now.
- A table a chunk prints with HTML cells is a `table` entry as now (7.1). Its
  digest reads the visible text with the tags removed and the entities as
  written, so the escaping of HR2 is part of the digest. It is stable because
  HR2 is fixed.
- Alternative refused: recording the target at `format()` time. `format()` runs
  outside a knit, from `print()`, and many times per object; a second write per
  sink would make the ledger depend on drawing, not on what the report says.

### Project formatters (D104)

- `targets:` still lists `markdown` and, optionally, `tex`. E104's message is
  unchanged. Under `"html"` and `"marquee"`, as under `"plain"`, the function
  is called as for markdown (with `target = "markdown"` when it lists tex), and
  its markdown is read by PL and rendered.
- `check_targets()` tests against `c("markdown", "tex")`, not `TARGETS`, so
  `targets: [markdown, plain]`, `[markdown, html]` and `[markdown, marquee]`
  are E104. This fixes the defect noted at the top.
- Raw HTML a project function writes into its markdown (a `<span>`) is text
  under `"html"` (D93). If projects need their own HTML, sketch S5 applies.

### The Lua filter, Python and Julia (D102)

- **`weft.lua` and `num.lua`: nothing.** Named values are resolved into a
  document's markdown, and Pandoc writes the HTML. No named value reaches a
  plot.
- **`weft-check.lua`: RS4.** About 20 lines: a `RawInline`/`RawBlock` handler
  for `html`, beside the one for `tex`.
- **Python and Julia: nothing now.** Their `weft_str()` calls R's `weft()` and
  returns markdown. Sketch S4 adds `target`.

---

## 4. Rules for the spec

In the spec's numbered style. The rationale paragraphs go in Part 2, section 13,
under the same numbers.

**1.4.8 (amended, last sentences).** "Under the plain, html and marquee targets
(1.4.24 to 1.4.26) a project formatter is called as for markdown and its text
is read as 1.4.24 says; `targets:` lists only `markdown` and `tex`."

**1.4.10 (amended).** "...except inside math and raw LaTeX (1.4.23) and under
the plain (1.4.24), html (1.4.25) and marquee (1.4.26) targets."

**1.4.25** Under the target `html` a formatter writes HTML for a sink that
draws a small set of tags: ggtext, plotly, and HTML tables and widgets. The
HTML is the markdown text read by PL1 to PL10 (1.4.24) and written by these
rules, so it never disagrees with the plain text:

- **HR1** The tags are `<i>`, `<b>`, `<sup>`, `<sub>`, `<span>` and `<br>`,
  and no others.
- **HR2** Text writes `&`, `<` and `>` as `&amp;`, `&lt;` and `&gt;`, and each
  of `` * _ ` \ [ ] ^ ~ $ { } `` as its numeric entity, so that the markdown
  pass ggtext makes first leaves it as text. A `/` between two digits is
  `&#47;`, and `(` before `c)`, `r)` or `tm)` is `&#40;`. Every other
  character is written as it is.
- **HR3** At the start of the text, `#`, `-`, `+` and `=` are numeric
  entities, a leading space or tab is `&#32;` or `&#9;`, and in a leading run
  of digits followed by `.` or `)` and a space, that `.` or `)` is an entity.
- **HR4** Emphasis is `<i>`, strong emphasis `<b>`, a superscript `<sup>`, a
  subscript `<sub>`. A code span is its text. A formula is its text as written,
  escaped. A span is a `<span>` with its attributes (HR6), or its content
  when it has none. An empty run writes nothing.
- **HR5** A newline is `<br>`. A list keeps its lines.
- **HR6** A span's id is `id`, its classes `class`, its keys `style`, `title`,
  `lang` and `dir` themselves, and any other key `data-` and the key, in that
  order; values are escaped as HR2 and `"` as `&quot;`.
- **HR7** A marker (2.6.8) is text.

So `.sci` writes `1.2 \u00d7 10<sup>\u22124</sup>`, a unit `m<sup>2</sup>`, a list `- a<br>- b`
(with the first `-` an entity), and `[Depth]{style='color:#c00'}` a coloured
word in ggtext. Every class has an html form.

**1.4.26** Under the target `marquee` a formatter writes the markdown dialect of
the marquee package. It is the markdown text read by PL1 to PL10 and written by
these rules:

- **MQ1** Text puts a backslash before each of
  `` \ ` * _ ~ [ ] { } < > & $ ^ ``.
- **MQ2** At the start of the text and of each line, `#`, `-`, `+`, `=` and `:`
  get a backslash, as does the `.` or `)` after a leading run of digits that a
  space follows; a leading space or tab is a no-break space.
- **MQ3** Emphasis is `{.em ...}`, strong emphasis `{.str ...}`, a superscript
  `{.sup ...}`, a subscript `{.sub ...}`. A code span is a code span. A formula
  is kept as written. A span is its content.
- **MQ4** A newline is a hard break, `\` and the newline; two or more are one
  blank line.
- **MQ5** A marker is text.

So `.sci` writes `1.2 \u00d7 10{.sup \u22124}` and `H~2~O` writes `H{.sub 2}O`. Every
class has a marquee form.

**3.4.11 (amended).** The list of targets is `"markdown"`, `"tex"`, `"plain"`,
`"html"` and `"marquee"`; examples gain
`fmt_sci(0.000123, target = "html")  # 1.2 \u00d7 10<sup>\u22124</sup>` and
`fmt_sci(0.000123, target = "marquee")  # 1.2 \u00d7 10{.sup \u22124}`. New bullets: RT3,
RT5 (E107, E108), RT6.

**3.6.3 (amended).** The `format()` table gains `format(x, target = "html")`
(the html form of 1.4.25, class `html`; names kept; `NA` is `"NA"`) and
`format(x, target = "marquee")` (1.4.26). `c()` and `[<-` refuse a text made
for TeX, HTML or marquee (E109).

**3.6.4 (amended).** The sink sentences gain RS1 and RS2.

**3.6.11** Rich plot text. ggtext draws `format(x, target = "html")` and
marquee draws `format(x, target = "marquee")`; `fmt_*()` take the same targets
for a scale's labels. A `weft` object given to either as it is draws its plain
text. ggtext draws the thin and no-break spaces as word spaces (HR8). Before
1.2.0 marquee has no superscript style, and a marquee text holding a
superscript or subscript is then a configuration error (MQ6, E110). The ledger
records a `weft()` string's markdown when it is evaluated; the target is the
sink's choice and changes no entry (7.1).

```r
w <- weft("*Eucalyptus* cover at `r cover`{.pct}, 10^`r k`^ stems")
ggplot(d, aes(x, y)) + geom_point() +
  labs(title = format(w, target = "html")) +
  theme(plot.title = ggtext::element_markdown()) +
  scale_y_continuous(labels = \(b) fmt_sci(b, target = "html")) +
  theme(axis.text.y = ggtext::element_markdown())

ggplot(d, aes(x, y)) + geom_point() +
  labs(title = format(w, target = "marquee")) +
  theme(plot.title = marquee::element_marquee())
```

**2.5.3 (amended).** A new bullet: "a failure marker in raw HTML, written
`<<weft:` or `&lt;&lt;weft:`."

**5.6.4 (amended).** RS3.

**Rationale (Part 2, section 13).**

- **1.4.25.** ggtext runs a markdown pass before it reads HTML, and that pass
  depends on the markdown package's version: it superscripts `^6^` but not
  `^\u22124^`. Writing weft's own HTML, escaped so the pass leaves it alone, makes
  the result the same under every version. The tag set is what gridtext and
  plotly both read; gridtext stops a plot on any other tag. A list is lines
  because `<ul>` stops a ggtext plot.
- **1.4.26.** marquee reads `~x~` as strikethrough and `_x_` as underline, has
  no superscript syntax, and drops HTML tags silently, so neither weft's
  markdown nor its HTML is safe there. Custom spans are marquee's only route to
  its `sup` and `sub` styles, and they have no flanking rules.
- **3.6.11.** A sink calls `as.character()`, so weft cannot choose the form for
  it; the author names the target where the text meets the sink.

---

## 5. Sketches, not to be built now

- **S1 (ASCII plain).** `target = "ascii"`: `1.2 x 10^-4`, `-1,234,567.9`,
  `5 m^2`, `kg.m/s^2`, the no-break space as a space, the en dash as `-` or
  "to". For the default `pdf()` device, CSV headers and logs that must be
  ASCII. One more renderer over the runs.
- **S2 (plotmath).** `fmt_sci(x, target = "plotmath")` returning expressions
  (`1.2 %*% 10^-4`), for base graphics. It is not text, so it is not a target
  of the same kind; it would be its own function.
- **S3 (marquee classes).** A span's first class written as a marquee custom
  span, `[Depth]{.red}` as `{.red Depth}`, which marquee colours by name.
  Needs a rule for classes marquee does not know (they draw unstyled).
- **S4 (Python and Julia).** `weft_str(s, target = "markdown")` in both
  modules, passing `target` to R's `format()`. `"html"` serves great_tables
  (`html()`) and plotly from Python. No change to the filter.
- **S5 (project HTML).** `targets: [markdown, tex, html]`: the function writes
  its own HTML, which weft checks against HR1's tag set.
- **S6 (`{=html}` regions, For Robin 5).** A construct inside a `{=html}` fence
  or span in a document writes HTML, as one in `{=latex}` writes TeX (design 9,
  TX1 `"raw"`). A scanner change: a `tex` column value or a new `raw_html`
  flag, and E95-style errors for classes with no inline form.

---

## 6. Tests

A test-writer can write these from this note alone. Unless a test says
otherwise it runs with weft's default configuration outside a knit, in a
temporary folder with no `_weft.yml`, and compares strings exactly with
`expect_identical()`. Build expected strings with `\u` escapes.

### `tests/testthat/test-html-target.R` (stage H1)

1. **Every row** of the three tables in section 3, column `"html"`: the
   `fmt_*()` rows call the function with `target = "html"` and compare
   `as.character(result)`; the `weft()` rows compare
   `unclass(format(weft(x), target = "html"))` (attributes dropped). The
   `big_mark`, `minus` and `p_label` rows write a `_weft.yml` in the
   temporary folder first.
2. **Attribute.** `attr(fmt_num(5, target = "html"), "target")` is `"html"`;
   `attr(., "number")` is 5. `attr(fmt_num(u(5, m^2), target = "html"),
   "unit")` is `"m<sup>2</sup>"`.
3. **Markdown unchanged.** For every input of the tables, the result with
   `target = "markdown"` is identical to the result with no `target`, and has
   no `target` attribute.
4. **Plain agreement.** For each html row whose markdown holds no superscript,
   subscript, span or formula: parsing the HTML with
   `xml2::read_html(paste0("<body>", h, "</body>"))`, after replacing `<br>`
   by a newline, gives `xml2::xml_text()` equal to the plain form
   (`fmt_*(target = "plain")` or `as.character(weft(x))`).
5. **Survives the markdown pass** (skip without ggtext). For each html row:
   `markdown::markdownToHTML(text = h, options = c("use_xhtml",
   "fragment_only"))`, with a leading `<p>` and a trailing `</p>` and newline
   removed, parsed with `xml2`, has the same text (`xml_text()`) and the same
   sequence of element names (`xml_name()` of every descendant, in document
   order) as `h` parsed directly. In particular `fmt_ul(c("a", "b"), target =
   "html")` gives no `ul` or `li` element after the pass.
6. **`format()` class.** `class(format(weft("a"), target = "html"))` is
   `c("html", "character")` (if Robin rules D98 otherwise, a bare character
   vector). Names are kept: `format(weft(c(k = "a")), target = "html")` has
   name `k`.
7. **E100 and the `format()` message.** `fmt_num(1, target = "rtf")` is a
   `weft_construct_error` whose message is exactly "`target` must be
   \"markdown\", \"tex\", \"plain\", \"html\" or \"marquee\"; got \"rtf\"."
   `format(weft("a"), target = "rtf")` gives "`target` must be \"plain\",
   \"markdown\", \"ansi\", \"html\" or \"marquee\"; got \"rtf\"."
8. **E107.** `fmt_strong(fmt_num(5, target = "html"))` is a
   `weft_value_error` matching "formatted for HTML (target = \"html\"), and
   weft cannot format it again". So is `fmt_strong(fmt_num(5, target =
   "html"), target = "html")`. `fmt_num(fmt_num(5, target = "html"))` is not
   an error (it formats again from the number) and gives `"5"`.
   `fmt_strong(fmt_num(5), target = "html")` gives `"<b>5</b>"`.
9. **E108.** `fmt_strong(fmt_num(5, target = "tex"), target = "html")` is a
   `weft_value_error` matching "would print here as HTML".
10. **E109.** `c(weft("a"), fmt_num(5, target = "html"))` is a
    `weft_construct_error` matching "cannot join a weft text". So is
    `w <- weft(c("a", "b")); w[2] <- fmt_num(5, target = "tex")`.
    `c(weft("a"), fmt_num(5, target = "plain"))` is not an error.
11. **`fmt_unit()`.** `fmt_unit(u(1, m^2), target = "html")` is
    `"m<sup>2</sup>"` with attribute `target = "html"`.
12. **Project formatters.** With `_weft.yml` registering `.tidy` with
    `function: fmt_tidy` (a function in the test environment returning
    `paste0("*", x, "*")`), `weft("`r 3`{.tidy}")` formatted as html is
    `"<i>3</i>"`. With `targets: [markdown, tex]` and a function that records
    its `target` argument, the recorded value under `format(..., target =
    "html")`'s `weft()` call is `"markdown"`.
13. **E104 fixed.** `_weft.yml` with `targets: [markdown, plain]`, then with
    `[markdown, html]`, then `[markdown, marquee]`: each makes `weft("x")` a
    `weft_config_error` whose message is E104's present text.
14. **A collected failure.** In a knit (the existing helpers in
    `helper-e1*.R`) with draft mode on, a chunk that does `w <- weft("`r
    NA`{.num}")` and `cat(format(w, target = "html"))` with `results: asis`
    writes `&lt;&lt;weft: no value, line N&gt;&gt;` for the right N.
15. **Speed.** 200 calls of `format(weft("a *b* 10^2^"), target = "html")`
    take less than twice as long as 200 calls with `target = "plain"`.

### `tests/testthat/test-marquee-target.R` (stage H2)

1. **Every row** of the three tables, column `"marquee"`, as in H1 test 1
   (replace `[NL]` with `"\n"`).
2. **Attribute** `target = "marquee"`; `unit` of `u(5, m^2)` is `"m{.sup 2}"`.
3. **E107** with "for marquee (target = \"marquee\")"; **E108** with "would
   print here as marquee text"; **E109** with "formatted for marquee".
4. **Class.** `format(weft("a"), target = "marquee")` is a bare character
   vector (no class).
5. **E110.** With the internal version reader mocked
   (`testthat::local_mocked_bindings(marquee_version = function() "1.1.1")`):
   `fmt_sci(0.000123, target = "marquee")` is a `weft_config_error` whose
   message is exactly "marquee 1.1.1 draws {.sup } and {.sub } as ordinary
   text, so 10{.sup -4} would draw as 10-4. Install marquee 1.2.0 or later
   (rule 3.6.11)."; `fmt_num(5, target = "marquee")` is not an error (no
   superscript). Mocked to `"1.2.0"`: no error. Mocked to `NA` (not
   installed): no error. The mocked function is named `marquee_version` in the
   package; the implementer must use that name.
6. **Parse agreement** (skip without marquee 1.2.0). For each marquee row,
   `marquee::marquee_parse(m)` has text whose concatenation, with the
   paragraph and line-break structure ignored, equals the plain form with its
   Unicode superscripts and subscripts replaced by their digits. In the row
   `fmt_sci(-0.000123)`, the piece whose text is `"\u22124"` has the `sup`
   style (its `baseline` is above 0 and its `size` below the body's). In
   `fmt_em("Eucalyptus")`, the piece has `italic` TRUE. No piece of any row
   has `strikethrough` or `underline` TRUE.

### `tests/testthat/test-rich-plots.R` (stage H3; slow; skip on CRAN)

1. **ggtext draws** (skip without ggtext and ggplot2 >= 4.0.0; open
   `grDevices::pdf(NULL)` as T9 does). A plot with
   `labs(title = format(weft("Rate *r* of 10^-4^ m^2^"), target = "html"))`
   and `theme(plot.title = ggtext::element_markdown())` builds with
   `ggplot2::ggplotGrob()` without error. So does one whose title is
   `format(weft("`r c('a', 'b')`{.ul}"), target = "html")`.
2. **The failing case is real.** The same plot with
   `format(..., target = "markdown")` of the `.ul` string fails with an error
   matching "isn't supported yet". (This pins the problem; if a gridtext
   release ever reads `<ul>`, the test is changed, not the design.)
3. **ggtext scale labels.** `scale_y_continuous(labels = \(b) fmt_sci(b,
   target = "html"))` with `axis.text.y = ggtext::element_markdown()` builds.
4. **marquee draws** (skip without marquee 1.2.0): the same title through
   `format(..., target = "marquee")` and `marquee::element_marquee()` builds.
5. **marquee drops HTML** (skip without marquee): `marquee::marquee_parse("10<sup>4</sup>")`
   has the text `"104"`. This pins why HTML must not go to marquee.

### Lint and filter (stage H3)

1. **`value-format`** (in the existing lint test file): a `.qmd` with
   ``The rate is `r fmt_sci(x, target = "html")`.`` in prose gives one tier-2
   `value-format` finding with E111's text for `fmt_sci` and `html`; the same
   with `target = "marquee"`; none for `target = "plain"` written in a chunk.
2. **`weft-check.lua`** (needs Pandoc; in the existing filter tests): a
   markdown file holding a raw HTML block `` ```{=html} `` with
   `<td>&lt;&lt;weft: no value, line 4&gt;&gt;</td>` makes `weft-check`
   report a `marker` finding; one with `<td><<weft: no value, line 4>></td>`
   too; one with `<td>5</td>` reports nothing.

---

## 7. Implementation

### Stage H0: probe (one R process, about 30 minutes)

Before the tests. Run each sink claim of section 1 and each row of section 3
through the real packages, and correct this note where they differ:

- `markdown::markdownToHTML()` with markdown 1.13 and 2.0 (this Mac has 1.13
  in the system library and 2.0 in the user library), and gridtext's grob on
  each html row (no error; the text pieces);
- `marquee::marquee_parse()` with 1.2.x and 1.3.0 on each marquee row,
  including the no-break and thin spaces, `\:` and `{.em ...}`;
- gt `fmt_markdown()` on an html cell rendered to HTML and to docx (are the
  tags dropped?);
- plotly: a hover text with `<i>`, `<b>`, `<sup>` (by eye, once).

Install marquee into a temporary library for this; do not add it to the user
library without asking.

### Stage H1: the HTML target

- **New `R/rich.R`** (about 180 lines): `html_render(runs)`, `html_run()`,
  `html_text()` (HR2), `html_start()` (HR3), `html_attrs()` (HR6, using
  `parse_block_strict()` from `R/scan.R`), `html_finish(out)` (as
  `plain_finish()` in `R/tex.R`), `weft_html(x)` (RT4, following
  `weft_ansi()`'s C4 test in `R/plain.R`).
- **`R/tex.R`**: `TARGETS`; `tex_target()` becomes a function returning the
  target kind (`"tex"`, `"derived"` for plain, html and marquee, `"markdown"`);
  E100's text; E107, E108 messages. Keep the TeX messages byte for byte.
- **`R/format.R`**: `formatter_input()` (derived targets run as markdown;
  `in_target` from the input's attribute replaces `tex_in`), the `none` early
  return and `formatted_text()` (call the finisher by target), the E107/E108
  check beside the E103 one in `unit_forms()`.
- **`R/unit-names.R`**: `fmt_unit()` finishers.
- **`R/weft.R`**: `weft_target()`, `format.weft()`, E109 in `weft_parts()`.
- **`R/config.R`**: `check_targets()` against `c("markdown", "tex")`.
- Roxygen for `target` (`R/format.R:1619`) and `format.weft`.
- Risk: `plain_read()` keeps a span's block as written; HR6 needs it parsed.
  Use the scanner's parser so quoting rules match package Q.

### Stage H2: the marquee target

- **`R/rich.R`** (about 100 lines more): `marquee_render()`, `mq_text()`
  (MQ1), `mq_lines()` (MQ2, MQ4), `marquee_version()` (cached per session in
  the package environment), the E110 check.
- `R/tex.R` and `R/weft.R` as in H1, for the second value.

### Stage H3: sinks, lint, filter, documents

- **`R/lint-code.R`**: RS3.
- **`inst/quarto/weft-check.lua`**: RS4, about 20 lines beside the TeX handler
  (line 499).
- **`DESCRIPTION`**: `ggtext` and `marquee` in Suggests (`xml2` is there).
- **Documents**: `dev/PACKAGE-SCOPING.md` (section 4 of this note);
  `vignettes/strings.Rmd` (the sink table at line 62, a new section "Rich plot
  text" after "Plots", with the two examples of 3.6.11, not run); NEWS;
  `inst/agent/references/syntax.md` and its `skills/weft` copy (one paragraph);
  `dev/decisions.md` (D86 to D104 and Robin's rulings).
- H3's documents can be written while H2 is built; the tests of H3 need H2.

### Size

| Part | Lines, about |
|---|---|
| R code (`R/rich.R` 280, edits 120) | 400 |
| Lua | 20 |
| Tests (H1 250, H2 180, H3 120, lint and filter 40) | 590 |
| Spec, vignette, references, NEWS | 250 |

Medium: smaller than design 9's T1, because no scanner change and no Lua
formatting. Order: H0, then H1, then H2 with H3's documents, then H3's tests.

---

## For Robin

Each item is a choice of taste or of risk. The build can go ahead on the
recommendation.

1. **Emphasis tags in HTML: `<i>`/`<b>` or `<em>`/`<strong>`?** gridtext and
   browsers read both. plotly draws `<em>` bold italic and does not read
   `<strong>`. Pandoc writes `<em>`/`<strong>` in a document's HTML.
   **Recommended: `<i>` and `<b>`**, so one form is right in plotly too.
2. **Superscripts in HTML: tags always, or Unicode first?** Tags
   (`10<sup>\u22124</sup>`) are what the HTML sinks draw best. But a sink that
   strips tags (marquee, Word through gt) then shows "10\u22124", a wrong
   number. Unicode first (`10\u207b\u2074`, tags only for letters) survives
   stripping, needs the font to have the glyphs, and makes the HTML of a number
   the same as its plain text. **Recommended: tags**, with marquee given its own
   target and the docs saying which form goes where (RS1).
3. **Raw HTML an author writes in a `weft()` string** (`<span
   style='color:red'>`): text, or passed through under `"html"`? Passing it
   through is what a ggtext user expects, but the same string would then show
   tags as text in plain output and in marquee. **Recommended: text**, as the
   plain reading does; write `[word]{style='color:red'}`, which works in
   ggtext, plotly, gt and the knit's own HTML.
4. **Should `format(x, target = "html")` return class `c("html",
   "character")`?** That is `htmltools::HTML()`'s class, so htmltools, Shiny
   and gt helpers take it without escaping; it costs no dependency. It makes
   `format()` return a classed object. **Recommended: yes, for `format()` only**;
   `fmt_*()` results stay `weft_text`, and a user wraps them in
   `htmltools::HTML()` where needed.
5. **Constructs inside `{=html}` blocks in a document** (sketch S6): build
   with this package, or later? It is the HTML twin of design 9's raw LaTeX,
   and a scanner change. **Recommended: later.** No user has asked for it, and
   this package is about strings.

## Rulings (27 Nov 2026, orchestrator, under Robin's delegation of design decisions)

All five "For Robin" items are taken as recommended: `<i>`/`<b>` (plotly draws `em` as bold italic
and ignores `strong`); `<sup>`/`<sub>` tags, not Unicode first; raw HTML in a `weft()` string is
text (`[word]{style=...}` does that job everywhere); `format(x, target = "html")` alone returns
class `c("html", "character")`; values inside `{=html}` blocks later. Stage H0 (a probe of ggtext,
marquee, gt and plotly with R, once R is free) runs before the tests, and its results amend the
tables if a source reading was wrong. The `check_targets()` bug (accepts `targets: [markdown,
plain]`, which 1.4.8 forbids) is fixed in H1.
