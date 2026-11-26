# E1: `weft()` and the plain target (25 Nov)

Package E1 of `dev/plan-weft-everywhere.md`. The rulings there and in
`dev/decisions.md` ("Weft everywhere") are not reopened: `weft()` evaluates
at the call and returns an object each sink renders; `weft_str()` goes.
Package Q (loosened quoting, `dev/design-quoting.md`) lands first, so the
examples use single-quoted attribute values.

This note is the contract for a test-writer who does not read `R/` and an
implementer who does not edit tests. Rule ids: **WS** (the function and its
object), **PL** (the plain reading), **FT** (formatter targets), **CF** (the
configuration cache), **ST** (the static side). Decisions are **D1** to
**D14**, with their alternatives.

## Why

`weft_str()` returns markdown. In a plot title `1.2 × 10^−4^`, `m^2^` and
`**x**` print literally (tested on 19 Nov with ggplot2 4.0.3). A call costs
about 10 ms outside a knit (200 calls took 2.1 s; 200 `fmt_num()` calls
0.04 s) because each call builds a state and reads `_weft.yml` again
(`string_state()`, `R/weft-str.R:66`). Too slow for labels made in a loop.

## What the code does today (checked)

The places the plan names, read at `2f06dc9`:

| Where | What it writes | Checked |
|---|---|---|
| `R/format.R:845-846` (`text_stage()` in `apply_formatters()`) | `.em` and `.strong` wrap in `*` and `**` | yes |
| `R/format.R:377` (`sci_one()`) | `.sci` as `1.2 × 10^−4^` (`cfg$minus` in the exponent) | yes |
| `R/unit-names.R:21` (`md_escape()`), `:497-500` (`unit_symbol_text()`) | a unit's symbol: escapes, `m^2^`, `^−1^`, `·` for `*` | yes |
| `R/format.R:640` (`collapse_list()`) | `.ul`, `.ol`, `.dl` as markdown lists | yes |
| `R/resolve.R:260` (`passthrough()`) | `[text]{.cls key="v"}` for classes weft does not own | yes |
| `R/resolve.R:670` | `<!-- -->` between two emphasis constructs side by side | yes |
| `R/state.R:115` (`marker()`) | `<<weft: KIND, WHERE>>`: plain ASCII, no markdown | yes; needs no change |
| `R/resolve.R:800` | target per row from the scanner's `tex` column; there is no `ctx$target` | yes |
| `R/tex.R:93` (`tex_cfg()`), `:110` (`unit_md_to_tex()`) | the TeX target converts the unit's markdown after the fact | yes |

Two corrections to the brief. `weft_env$config` is assigned: by
`init_knit()` (`R/hooks.R:404`, cleared at `:434`), by `conf_with_config()`
(`R/conformance.R:258`) and by `R/dict-tools.R:252`. `string_state()` uses
it when set; only outside those is `_weft.yml` read on every call, and then
from `getwd()`, not from a project root. And `inst/agent/references/syntax.md`
(and its `skills/weft` copy) never mention `weft_str()`; nothing there to edit.

ggplot2 4.0.0, read from its source: `labs()` keeps its arguments as given
(`R/labels.R:193-206`); `setup_plot_labels()` passes a label that is not a
function through unchanged (`:101-107`); `element_grob()` for
`element_text` hands it to `titleGrob()` (`R/theme-elements.R:502`), which
calls `grid::textGrob(label, ...)` (`R/margins.R:109`); and grid's
`validDetails.text()` sets `x$label <- as.character(x$label)` when the label
is not a language object (`src/library/grid/R/primitives.R:1380-1382`). So a
classed label is drawn as its `as.character()`. Scale labels: major breaks
are not censored, and a label function's result is checked only for length
(`R/scale-.R:1170-1190`).

## The contract

### The function

**WS1** `weft(x, .envir = parent.frame())`, exported. `x` is a character
vector of markup; a factor is read as its labels. Each element is resolved
as a block of prose, as `weft_str()` resolved it. The result is a `weft`
object (WS6) of the same length, with the names of `x`. An `NA` element stays
`NA` and is never a failure. A `weft` object given as `x` is returned
unchanged (it is already resolved). Errors, both `weft_construct_error`:

- `x` of any other type (a number, a list, `NULL`):
  "`weft()` takes a character vector of markup."
- `.envir` not an environment: "`.envir` must be an environment."

**WS2** Every value, bare value, governor, claim and guard in the markup is
evaluated during the call, in `.envir`. The object holds what they printed,
so changing a variable after the call changes nothing, and objects made in a
loop each keep their own iteration's values.

**WS3** The functions inline code calls by name (today's
`inline_function_names()`: `claim`, `weft_put`, `plural`, `glue_vec`, `u`,
`dict_glossary`, `py_value`, `jl_value` and every exported `fmt_*`) are
visible to the markup even when weft is not attached, in and out of a knit.
A function of the same name that `.envir` can see wins. (Today this is done
only outside a knit; D9.)

**WS4** A named value (`` `x`{.num} ``, rule 1.12) is left in the markdown as
written, for the filter, as `weft_str()` left it. Package E2 changes this to
read `x` from `.envir`; only the resolver changes then (D2).

**WS5** Bare inline R is evaluated as knitr evaluates it (rule 1.1.8), as
today. In a knit its markdown is what knitr's inline hook writes (for a
number in scientific form that hook writes `1.2 &times; 10<sup>-4</sup>`);
its plain form is that markdown read by PL (so `1.2 × 10⁻⁴`).

### The object

**WS6** A `weft` object is a character vector of class `c("weft",
"character")`. Its content is the **plain** text of each element; the
attribute `markdown` holds the **markdown** text, the same length. The plain
text of an element is always its markdown read by PL1 to PL11, except for an
element joined in as plain text by `c()` or `[<-` (WS9). A function that
reads a character vector without dispatching therefore sees plain text.

**WS7** Renderings:

| Call | Gives |
|---|---|
| `as.character(x)` | plain; a bare character vector, names kept, `NA` kept |
| `format(x)`, `format(x, target = "plain")` | plain; names kept; an `NA` element is `"NA"`, as `format()` writes it |
| `format(x, target = "markdown")` | markdown; names kept; `NA` is `"NA"` |
| `format(x, target = other)` | `weft_construct_error`: "`target` must be \"plain\" or \"markdown\"; got %s." (`%s` as in rule 3.4.11: the value in double quotes, or `something else`) |
| `print(x)` | writes each element's plain text on its own line (`NA` as `NA`), names not shown; a length-0 object prints `<weft[0]>`; returns `x` invisibly |
| `knitr::knit_print(x, inline = TRUE)` | `knitr::asis_output()` of the markdown elements joined by `", "` (as stock knitr joins an inline vector) |
| `knitr::knit_print(x)` (a chunk prints the object) | `knitr::asis_output()` of the markdown elements joined by `"\n\n"` |

A `"tex"` target for a whole string is not offered (D5).

**WS8** Base functions, by what they do:

| Function | Result |
|---|---|
| `length()`, `names()`, `is.na()`, `nchar()`, `==`, `grepl()`, `cat()`, `writeLines()` | act on the plain text (the content) |
| `paste()`, `paste0()`, `sprintf("%s", )`, `toString()`, `message()`, `stop()`, `warning()`, `glue::glue()` | call `as.character()`: plain text |
| `x[i]`, `x[[i]]`, `rev(x)` | a `weft` object holding those elements, both forms |
| `rep()`, `unique()`, `sort()` | a plain character vector (base drops the class) |
| `unclass(x)` | the plain text with the attribute `markdown` |

**WS9** `c()` and `[<-`. Arguments to `c()` whose first is a `weft` object,
and the value of `x[i] <- value`, may be `weft` objects, character vectors
and `NULL`. A `weft` element brings both forms. A character element is text
as it is: not markup, not evaluated, not read; its plain and markdown forms
are both the string. Anything else is a `weft_construct_error`: "A weft text
can be combined only with weft texts and character vectors; got a %s."
(`%s` is `class(value)[1]`.) `[<-` beyond the length fills with `NA` in both
forms, as base does.

**WS10** An element whose plain text is no longer its markdown read by PL,
and is not a WS9 text, was changed by a function that kept the attributes
(`substr()`, `toupper()`, `[[<-`). Its markdown form is then its plain text.
`format(target = "markdown")` and `knit_print()` check each element.

**WS11** A `weft` object used as a value inside `weft()` markup (bare or
with classes), or passed to a `fmt_*()`, contributes its markdown text, as a
`weft_text` contributes its text today.

### Failures, location, conditions

**WS12** During a knit with weft's hooks installed (the `text` hook is
weft's and there is an active state: today's `string_state()` test), a
failed check, a missing value, a value error or an unknown citation key is
collected as in a paragraph (2.4.1), and the object holds its marker in both
forms: `<<weft: failed claim, chunk fig-depth>>`, or `line N` when the call
is inline R in prose (today's `in_prose` test). A construct error stops the
render, naming the chunk, except in draft mode, where it is a marker. A
warned check is recorded as a warning (2.6.10).

**WS13** Elsewhere (outside a knit, or in a knit where the hooks were never
installed) the first failure stops at once with its class:
`weft_claim_failed`, `weft_no_value`, `weft_value_error`,
`weft_construct_error` (with `weft_located` where it has it today). The
message begins `weft: a weft() string: ` outside a knit and
`weft: chunk LABEL: ` in a knit (today's `str_where()`, with `weft_str()`
renamed). Draft mode has no effect here. Warnings (`weft_zero_warning`,
`weft_unit_warning`, `weft_bare_missing_warning`) are signalled at the call
and the object is returned.

**WS14** A failure is located by its chunk label, or by the line of the
inline R that called `weft()`, as now. Not by the call's source reference
(D10).

**WS15** The ledger records each construct of a `weft()` string as it
records one of a `weft_str()` string now, with `context` `"weft"` (was
`"weft_str"`) and `text` the markdown. `last_knit()`, `changes()`,
`rehearse()` and the chunk-cache replay (2.9.1) see `"weft"`.

### Knitr

**WS16** A caption option whose value R computes (`#| fig-cap: !expr
weft(...)` under Quarto, `fig.cap = weft(...)` in an rmarkdown chunk
header) and that evaluates to a `weft` object is given to knitr as its
markdown for `fig.cap`, `fig.scap`, `fig.subcap` and `tbl-cap`, and as its
plain text for `fig.alt`. `caption_option_hook()` wraps such an option, which
knitr holds unevaluated because it is in `eval.after`, so that the value is
converted after it is evaluated; a `weft` object already evaluated is
converted at once. A caption written as a markup string is resolved by the
caption resolver as now (2.3), with the same engine.

**WS17** Everything else follows from WS6 to WS8, and is documented rather
than special-cased: `cat(weft(...))` in a `results: asis` chunk writes plain
text (no emphasis; units and `.sci` in Unicode, which is valid markdown); to
write markdown, print the object or `cat(format(x, target = "markdown"))`.
`knitr::kable(caption = weft(...))` gets the plain text (kable pastes it). A
ggplot2 title or axis label keeps the object and draws its plain text.

### The plain reading (PL)

The plain form is the markdown read by these rules, applied left to right;
at each position the first rule that matches applies. The reader returns
**runs** (D1); PL11 renders them as plain text. Only these inline forms are
read: block syntax (list markers, `:   ` of a definition list, headings) is
text.

**PL1** Escape: `\` followed by an ASCII punctuation character
(`` !"#$%&'()*+,-./:;<=>?@[\]^_`{|}~ ``) is that character, as text, and no
other rule sees it. `\` followed by a newline is a newline, and `\` followed by a space is a
no-break space U+00A0 (Pandoc; review-e1 F13). Any other `\` is
text.

**PL2** Code span: a run of n backticks, then text, then the next run of
exactly n backticks. A code run of its content, verbatim (no rule applies
inside); when the content is not all spaces, the spaces at both ends are removed (Pandoc). A code span directly followed
by `{`, up to the `}` that closes an attribute block (PL9), is kept as written,
block included (a named value left for the filter, WS4). A backtick run with
no closing run is text.

**PL3** Math: `$$...$$`, or `$...$` where the opening `$` is not followed by
white space and the closing `$` is not preceded by white space nor followed
by a digit. Kept as written, delimiters included; no rule applies inside.

**PL4** An HTML comment `<!--...-->` is removed.

**PL5** `<sup>...</sup>` and `<sub>...</sub>` (lower case, no attributes): a
superscript or subscript run of the content, which is read by these rules.
Any other tag is text.

**PL6** An entity: `&amp;` `&lt;` `&gt;` `&quot;` `&apos;` `&nbsp;` (U+00A0)
`&times;` `&minus;` `&infin;` `&plusmn;` `&deg;` `&middot;` `&ndash;`
`&mdash;` `&hellip;` `&micro;`, and `&#N;` or `&#xH;` for a code point, are
that character. Any other `&` is text.

**PL7** Superscript `^...^` and subscript `~...~` (a `~~` is text): the
content is not empty and holds no unescaped space, tab or newline and no
unescaped closing delimiter (Pandoc's rule); a backslash and a space in it is a no-break space (U+00A0, Pandoc's rule). A code span or math in it is opaque to the search for the closing delimiter. A superscript or subscript run
of the content, read by these rules.

**PL8** Emphasis: `***...***` (strong emphasis), `**...**` and `__...__`
(strong), `*...*` and `_..._` (emphasis). An opening run is not followed by
white space; its closing run is the first run of the same character after it that is not preceded by white space and is not used up closing an emphasis opened inside, as Pandoc reads it: a run longer than the opening run closes an inner and an outer emphasis together (`**Total for *E. coli***`), and an opening run of three may be closed in two steps (`***Eucalyptus* sp.**`). A code span or math between them is opaque to the search. For `_`, the opening run
is not preceded by a letter or digit and the closing run is not followed by
one (so `snake_case_name` is text). The content is not empty and is read by
these rules. A run with no closing run is text (`5 * 3 and 2 * 4` is text;
`2*3*4` is emphasis, as Pandoc reads it).

**PL9** Span: `[`, text, `]` directly followed by an attribute block `{...}`
(the block as the scanner reads it, so a quoted value may hold `}`). A span
run of the content, read by these rules, with the attributes. Brackets not
directly followed by `{` are text: links (`[a](u)`), citations
(`[@smith2020]`), `[1]`.

**PL10** Everything else is text as written: the minus sign U+2212, the
no-break space U+00A0, thin spaces, `·`, `×`, newlines, list markers and the
markers of 2.6.8.

**PL11** Plain rendering of runs: text and code as their text; math as
written; emphasis, strong and span as their content (attributes dropped);
a superscript as Unicode superscripts when every character of its rendered
content has one, else `^(content)`; a subscript likewise, else
`_(content)`. Superscripts: `0`-`9` (⁰¹²³⁴⁵⁶⁷⁸⁹), `+` (⁺), `-` and U+2212
(⁻), `=` (⁼), `(` `)` (⁽⁾), `n` (ⁿ), `i` (ⁱ). Subscripts: `0`-`9`
(₀-₉), `+` (₊), `-` and U+2212 (₋), `=` (₌), `(` `)` (₍₎).

Reader examples (input is the markdown of an element; `weft()` of a string
with no construct has exactly this as its markdown):

| Markdown | Plain |
|---|---|
| `A **plain** string, 5 < 6.` | `A plain string, 5 < 6.` |
| `*a*`, `**a**`, `***a***`, `_a_`, `__a__` | `a` |
| `snake_case_name`, `5 * 3 and 2 * 4`, `a * b*` | unchanged |
| `2*3*4` | `234` |
| `\*a\*` | `*a*` |
| `C:\Users` | unchanged |
| `m^2^`, `10^−4^`, `10^-4^` | `m²`, `10⁻⁴`, `10⁻⁴` |
| `x^ab^` | `x^(ab)` |
| `x^a b^` | unchanged |
| `CO~2~`, `NO~x~` | `CO₂`, `NO_(x)` |
| `~~gone~~` | unchanged |
| `*m^2^*`, `^*2*^` | `m²`, `²` |
| `1.2 &times; 10<sup>-4</sup>` | `1.2 × 10⁻⁴` |
| `&infin;`, `&#8722;3`, `R&D` | `∞`, `−3`, `R&D` |
| `*1*<!-- -->*2*` | `12` |
| `[3]{.smallcaps}`, `[1990]{.weft-literal}` | `3`, `1990` |
| `as shown [@smith2020]`, `[a](http://x)`, `[1]` | unchanged |
| `` `code` ``, ``` `` a`b `` ``` | `code`, ``a`b`` |
| `` `x`{.num} `` | unchanged |
| `$x^2$`, `costs $5 and $10` | unchanged |
| `- a` newline `- b` | unchanged |
| `a\` newline `b` | `a` newline `b` |
| `<<weft: failed claim, chunk fig-a>>` | unchanged |

### Formatter targets (FT)

**FT1** Every `fmt_*()` and `fmt_unit()` accepts `target = "plain"`. The
result is the markdown result (every rule as now) with its text read by PL,
and so are its attributes `unit` and `unit_suffix` (each element of the
latter). It keeps the printed record (`number`, `decimals`, `relation`,
`raw`), `units`, `unit_form`, `unit_before`, `text_classes`, `is_symbol` and
names, and carries the attribute `target = "plain"`. `apply_formatters()`
takes `target = "plain"` the same way. Under `"markdown"` nothing changes,
byte for byte, and no attribute is added (3.4.11).

**FT2** Every class has a plain form. The TeX refusals (`TEX_NO_FORM`,
`R/tex.R:25`) apply under `"tex"` only.

**FT3** A `target` that is not one of the three is a `weft_construct_error`:
"`target` must be \"markdown\", \"tex\" or \"plain\"; got %s." (was E100's
"markdown\" or \"tex\"" text; `%s` as before).

**FT4** A `weft_text` made under `"tex"` given to a formatter under
`"plain"` (a pass-through, a text class, a collapse) is a
`weft_value_error`: "This text was formatted for TeX (target = \"tex\") and
would print here as plain text. Format the number again, with target =
\"plain\" (rule 3.4.11)." A `weft_text` made under `"plain"` given to a
formatter under any target is treated as one made under `"markdown"` (its
text is markdown with no markup).

**FT5** A project formatter is called as now (for markdown, and with
`target = "markdown"` when its `targets:` lists more), and its text is read
by PL. `targets:` does not take `plain` (D6).

Per class, markdown (today) and plain (default settings; `␣` is U+00A0):

| Class or case | Markdown | Plain |
|---|---|---|
| `.num`, `.pct`, `.word`, `.count`, `.ord`, `.no`, `.a`, `.cap`, `.date`, `.plus`, `.and`, `.or`, `.pairs` | no markup | the same text |
| `.range` | `3–5`, `−2 to 4` | the same |
| `.sci` | `1.2 × 10^−4^`, `1.2 × 10^6^` | `1.2 × 10⁻⁴`, `1.2 × 10⁶` |
| unit symbol, `.usym` | `5␣m^2^`, `2␣s^−1^`, `3␣m^3^/s`, `4␣kg·m`, `5␣mg/L` | `5␣m²`, `2␣s⁻¹`, `3␣m³/s`, `4␣kg·m`, `5␣mg/L` |
| a symbol with an escape (`µg_C` in `units:`) | `µg\_C` | `µg_C` |
| `.uname`, `.nounit` | no markup | the same |
| `.em`, `.strong` | `*x*`, `**x**` | `x` |
| `.p` | `p = 0.046` | the same |
| `.p`, `p_label: "*p*"` or `label='*P*'` | `*p* = 0.046`, `*P* = 0.046` | `p = 0.046`, `P = 0.046` |
| `.ul`, `.ol` | newline `- a` newline `- b` newline (`1. ` for `.ol`) | the same |
| `.dl` | newline `a` newline `:   x` blank line `b` newline `:   y` newline | the same |
| two emphasis constructs side by side | `*1*<!-- -->*2*` | `12` |
| pass-through class or key | `[3]{.smallcaps}` | `3` |
| `.weft-literal` span | `[1990]{.weft-literal}` | `1990` |
| `cite` span | `the method [@smith2020]` | the same |
| `n`, `if`, `sign`, `list` spans | the chosen arm | the arm read by PL |
| failure marker | `<<weft: no value, chunk fig-a>>` | the same |
| construct in math or raw LaTeX | TeX, as now | the same (PL3, or text) |
| named value (E1) | `` `x`{.num} `` | the same |
| bare inline R, in a knit | knitr's inline markdown | read by PL |
| the minus sign, no-break and thin spaces | U+2212, U+00A0, U+2009 | kept |

### The configuration cache (CF)

**CF1** The configuration a `weft()` call resolves against, in order:

1. a knit with weft's hooks installed and an active state: the knit's state
   and configuration (failures collected, WS12);
2. otherwise, when `weft_env$config` is set (a knit being initialised,
   `conf_with_config()`, the dictionary tools): that configuration;
3. otherwise the cached configuration of the project root of the working
   directory (CF2).

In cases 2 and 3 a fresh light state is made per call (`new_state()`, D8)
with that configuration; `lang` is `""` (English), and draft mode does not
apply (WS13).

**CF2** The project root is found on every call from `getwd()` by
`find_project_root()` (`R/io.R:204`: the nearest folder upward holding
`_weft.yml`, else one holding `_quarto.yml` or `_quarto.yaml`, else the
working directory itself). The cache holds one entry per root for the
session, never on disk. An entry records whether `<root>/_weft.yml` exists
and, when it does, its size and modification time (`file.info()`, to the
sub-second where the file system keeps it). An entry is used when all three
still match; otherwise the configuration is read again with
`read_config(root, list())` and the entry replaced.

**CF3** A read that fails (a `weft_config_error` or `weft_encoding_error`)
raises it from `weft()` and leaves no entry, so every later call reads the
file again and fails again until it is fixed (3.6.3: a string never prints
with half a configuration).

**CF4** Before resolving with a cached entry, the root's `units:` table is
brought into force if another project's is (as `project_units(root)` does:
a no-op when it already is). A string resolved from the cache prints units
exactly as a fresh read would, even after another project's configuration was
read in between. A root with no `_weft.yml` has the default units plus any
the session registered through the API, never another root's file or a
knit's front matter: when the units in force came from such a source
(tracked as `ud_state$src`), the defaults are put back before `weft()` and
before an `fmt_*()` outside a knit (review F1).

**CF5** `weft:::string_config_reset()` (internal, for tests) empties the
cache.

**CF6** Speed. With the cache warm, a call reads no file but the `file.info()`
of CF2 and the stat calls of `find_project_root()`. The names of WS3 are
computed once per session, not per call. Aim, measured once on the Mac and
written in the build log: a call of `weft("Mean `r x`{.num} m")` takes at
most 2 ms (median of 200, warm). The test (T12) guards a looser bound.

### The static side (ST)

**ST1** The scanner (`scan_chunk_strings()`, `R/scan-contexts.R:653`) and
the lints (`chunk_literals()`, `R/lint-source.R:254`) find the literal
strings given to `weft()` exactly as they find those given to `weft_str()`
today: in the code of an R chunk that is evaluated, as `weft(...)` or
`weft::weft(...)`, one string or `c()` of strings. `weft_str(...)` is no
longer read.

**ST2** The argument read is the one R matches to `x`: the argument named
`x`, else the first argument given without a name. So `weft("...", .envir =
e)` and `weft(.envir = e, "...")` are both read. (Today
`scan_chunk_strings()` gives up when any argument is named and none is `x`,
and `chunk_literals()` takes the first argument whatever its name; both are
wrong once `.envir` exists.)

**ST3** Their rows, regions and findings carry the context `"weft"` where
they carried `"weft_str"`: the scanner's rows, the lint regions
(`lint-pandoc.R:223`, `lint-code.R:588`, `lint-source.R:949,1024,1077-1084`),
`dl_ctx()` (`lint-doc.R:41`), `lint-prose.R:34,362`, `position.R:187`,
`rehearse.R:213`, `arms()` rows, the gate's counts, the ledger (WS15).

**ST4** Python keeps a module function named `weft_str` (D7). The lint
lists that name Python's module (`GUEST_PY_MODULE_NAMES`, `lint-doc.R:1029`)
keep `weft_str`, and rule 5.11's sentence about a `weft_str('...')` call in a
Python chunk stands.

**ST5** Reading `.R` files and raw strings is package E4, not here.

### Python

**PY1** The module's `weft_str(markup)` calls R's `weft()` with `.envir` a
new environment whose parent is the knit's global environment (or the global
environment outside a knit), and returns the **markdown** form: a `str`, or
a `list` of `str` for several. It does not use the vector's content (that
is plain; `guest_form()` must take the `markdown` form explicitly). Failures,
location and rule 2.12.9 are as now.

## Decisions

**D1 Representation: resolved markdown, read into runs.** The resolver
writes markdown as it does today, with one evaluation. The plain form is that
markdown read by one reader (PL) into runs (text, code, math, emphasis,
strong, superscript, subscript, span with attributes), which a renderer
turns into plain text. Package E3's ANSI target is a second renderer over the
same runs (emphasis to italic, strong to bold). The target switch lives in
one place: the reader and its renderers (a new `R/plain.R`), called by
`weft()` and at the end of `apply_formatters()` and `fmt_unit()` under
`"plain"`. The markdown emitters listed above stay as they are, and
`resolve_markup()` keeps choosing markdown or TeX per row from the scanner.

Alternatives:

- *Target-aware emitters* (the plan's sketch): each emitter writes per
  target, and the resolver carries a target or two texts through its
  templates, `join_pieces()` and the arm hashes. Rejected: the author's own
  text in a `weft()` string is markdown too (`*Eucalyptus*` in a title), so
  a markdown reader is needed in any case; given one, a second set of
  emitters only duplicates it. It also puts the markdown path, which every
  knit runs, at risk of changing a byte.
- *Semantic runs from the formatters*, with markdown rendered from them.
  Rejected for the same reason, and because unit symbols come from
  `_weft.yml` as markdown (`raw:` symbols), so they would need reading anyway.
- *Resolve once per target*, replaying cached evaluations. Rejected: twice
  the resolver's cost, and every side effect (failures, ledger, ids,
  warnings) must be suppressed on the second pass.
- *Typed tokens in the resolver's strings* (private-use delimiters carrying
  a markdown and a plain half). Rejected: text classes, `.cap`, `.a`, the
  unit-suffix search, the emphasis guard and project formatters (user code)
  all inspect the text and would meet the tokens.

Cost of the choice: the reader must agree with Pandoc on the inline forms
weft writes. Data text is not escaped in markdown either (1.4.10), so a `*`
in a site name is read the same way in both targets.

**D2 `weft_text` and `weft` are different things.** A `weft_text` is one
formatter result for one target, with its printed record; a `weft` object is
resolved prose with two forms and no record. Records stay where they are (the
ledger holds each construct's number, relation and raw value). Alternative:
keep a run per number with its record in the object; no consumer needs it,
and self-formatting values are "later" in the plan. E2 slots in through the
resolver: a bare name is evaluated instead of left as markup (WS4), and the
reader's PL2 exception still covers a name left for the filter.

**D3 The content is the plain text, the markdown an attribute.**
Alternatives: content markdown (then `cat()`, `nchar()` and anything that
does not dispatch would show `m^2^` and `**`), or a list-based object as in
the 19 Nov prototype (`cat()` fails on a list, and `is.character()` is
false). Plain content degrades to the right thing in every sink that does
not know the class.

**D4 `as.character()` is plain in a knit too; markdown only through
`knit_print()`, `format(target = "markdown")` and computed captions.**
Alternative: markdown during a knit. Rejected: a plot drawn in a chunk would
get markdown, and plots are the main use. Cost: `cat()` in an asis chunk
loses emphasis (WS17).

**D5 No `"tex"` target for a `weft` object.** A string is prose: its words,
emphasis and lists have no TeX form, and turning prose into LaTeX is
Pandoc's job. Numbers for a formula come from `fmt_*(target = "tex")`.

**D6 `fmt_*(target = "plain")` reads the markdown result (FT1); `targets:`
does not gain `plain`.** A project formatter that writes markdown gets a
correct plain form with no change to its function. Alternative: let a
project formatter write plain itself; no case needs it, and it could
disagree with its markdown.

**D7 Python keeps the name `weft_str`.** It returns a `str`, which is what
the name says, and Python has no object to render later. `weft` is the
module's own name: `from weft import weft` and `weft.weft(...)` read badly.
Alternative: rename to `weft` for symmetry with R; rejected for those
reasons.

**D8 A fresh light state per call; the configuration is what is cached.**
`new_state()` is about forty assignments; the 10 ms was the configuration
read. A fresh state keeps ids, parked code and constructs from leaking
between calls, as now. Alternative: one state per session, cleared per call;
it saves microseconds and risks a leak.

**D9 The inline functions are made visible in a knit too (WS3).** A
document that calls `weft::weft()` without attaching weft should find
`claim()` in its markup, in a knit as outside one. Cost: about thirty
`exists()` lookups per call; the name list is computed once.

**D10 No source references.** `sys.call()` carries a `srcref` only when
source is kept: never under `Rscript` by default, and in knitr's evaluation
the lines are relative to the chunk. The chunk label (or the prose line)
already locates a failure in a knit, and outside a knit the error stops at
the call, with R's traceback. E4, which reads `.R` files, can revisit it.

**D11 The root is found on every call, not cached.** A dozen `file.exists()`
calls cost far less than the budget, and the answer follows `setwd()` and a
new `_weft.yml` at once. Validation is by existence, size and modification
time, not a hash (a hash reads the file each call). An edit that keeps the
size within the file system's time resolution is missed; APFS, ext4 and NTFS
keep sub-second times.

**D12 Lists have a plain form (their markdown lines), not an error.**
Rendering happens at the sink, after the call; an error there would surface
in ggplot2's drawing, far from the cause. The scoping note's suggestion (a
construct error, as under TeX) fits `fmt_*()` but not `weft()`, so neither
gets it. `- a` is readable plain text.

**D13 Math in a `weft()` string keeps its TeX in plain** (PL3). weft does
not render TeX; showing the source is honest, and a plot that needs a formula
uses plotmath. The note in §3.6 tells the author.

**D14 A citation stays `[@key]` in plain.** There is no citeproc outside
Pandoc. Dropping it would silently lose the attribution; keeping it is
visible and can be fixed by the author.

## Tests

The test-writer works from this note. Helpers in
`tests/testthat/helper-0-common.R`:

```r
# weft_str()'s old result: the markdown, unnamed, NA kept
weft_md <- function(x, .envir = parent.frame()) {
  w <- weft::weft(x, .envir = .envir)
  out <- unname(format(w, target = "markdown"))
  out[is.na(w)] <- NA_character_
  out
}
```

### New tests (`test-weft.R`, `test-plain.R`, `test-weft-config.R`)

- **T1 the function** (WS1): `weft` is exported and `weft_str` is not; class
  `c("weft", "character")`; length and names follow `x`; `NA` stays `NA`;
  a factor is read; `weft(character())` has length 0; a number, a list and
  `NULL` give the WS1 error text; `.envir = 1` gives its error text;
  `weft(weft("a *b*"))` is identical to `weft("a *b*")`.
- **T2 evaluated at the call** (WS2): titles made in a loop over three
  values keep three different texts; a variable changed after the call does
  not change `as.character()` or `format(target = "markdown")`.
- **T3 environment** (WS3): a value local to a calling function is read; an
  explicit `.envir` is read; `local(weft::weft("[one | # sites]{n='k'}"),
  envir = list2env(list(k = 2), parent = baseenv()))` works (`plural`,
  `claim` found without attaching weft); a `.envir` that defines its own
  `plural` uses it.
- **T4 the two forms**: every expectation of today's `test-weft-str.R` holds
  for `weft_md()` (markdown identical to `weft_str()`); and for each row of
  the per-class table and the reader table, `format(w, target = "plain")`
  and `as.character(w)` give the plain column. Include an `n`, an `if` and a
  nested span whose arm holds `.em` and a unit.
- **T5 formatter plain** (FT1 to FT5): `fmt_sci(0.000123, target =
  "plain")` is `"1.2 × 10⁻⁴"`; `fmt_num(u(5, m^2), target = "plain")` is
  `"5\u00a0m²"`, with `attr(, "unit")` `"m²"` and the record of the markdown
  call; `fmt_unit(u(1, 1/s), target = "plain")` is `"s⁻¹"`; `fmt_em("x",
  target = "plain")` is `"x"` (no error); `attr(, "target")` is `"plain"`;
  `target = "html"` gives the FT3 text; `fmt_cap(fmt_num(2, target =
  "tex"), target = "plain")` gives the FT4 error; a plain `weft_text` given
  to `fmt_and()` under markdown works; every markdown result is identical to
  a call without `target`.
- **T6 vector semantics** (WS8 to WS10): `[`, `[[`, `rev()` keep both forms;
  `rep()` and `unique()` give a bare character vector; `c(w1, w2)` keeps both
  forms; `c(w, "m^2^")` has plain and markdown `"m^2^"` for the new element;
  `c(w, 1)` gives the WS9 error with `numeric`; `w[2] <- weft("*b*")` sets
  both forms; `substr()` of an element with emphasis then `format(target =
  "markdown")` gives the substring (WS10); `nchar()` counts plain characters.
- **T7 sinks**: `paste0("T: ", w)`, `sprintf("%s", w)`, `toString(w)`,
  `message(w)` (via `expect_message`), `glue::glue("{w}")`
  (`skip_if_not_installed("glue")`) give plain; `cat(w)` and `print(w)`
  output plain lines (`expect_output`); `print(weft(character()))` writes
  `<weft[0]>`; `format(w)` writes `"NA"` for an `NA` element while
  `as.character()` keeps `NA`; `format(w, target = "tex")` gives the WS7
  error.
- **T8 knitr** (WS7, WS16, WS17), rmarkdown knits with the existing
  `render_rmd(..., format = "knit", in_process = TRUE)`: inline `` `r
  weft::weft('*a* `r 2`{.num} m^2^')` `` writes the markdown into the `.md`;
  a chunk whose value is a `weft` object writes markdown (asis, no `##`);
  `cat()` of one in a `results='asis'` chunk writes the plain text;
  a chunk header `fig.cap = weft::weft("Depth at *[a site | # sites]{n='k'}*")`
  (no inline R in a header) gives a caption holding `*3 sites*`; `kable(caption = weft::weft(...))` gives `Table: ` and the plain
  text; one Quarto case with `#| fig-cap: !expr weft::weft(...)`
  (skip without Quarto).
- **T9 ggplot2** (`skip_if_not_installed("ggplot2", "4.0.0")`): a plot with
  `labs(title = w)`; `g <- ggplot2::ggplotGrob(p)`; the grob in
  `g$grobs[[which(g$layout$name == "title")]]` holds a text grob whose
  `label` is identical to `as.character(w)` (plain, no `^`, no `*`). A
  scale with `labels = function(b) fmt_num(b, target = "plain")` builds
  without error.
- **T10 failures** (WS12 to WS14): outside a knit each class stops at once
  (today's cases), and the message starts `weft: a weft() string: `; in a
  knit with `weft_setup()`, a failed claim in a plot title is collected with
  `chunk` the label, the render fails at the end naming it, and
  `as.character()` of the object holds `<<weft: failed claim, chunk
  fig-depth>>`; draft mode turns a construct error into a marker in a knit
  and does not outside one; a knit without `weft_setup()` stops at the first
  failure; `` `r weft::weft(...)` `` in prose with a failed claim gives a
  marker naming the line. The ledger rows of a `weft()` string have context
  `"weft"`.
- **T11 configuration** (CF1 to CF5), each in a temporary directory with
  `withr::local_dir()` and `weft:::string_config_reset()` first:
  - `_weft.yml` with `digits: 3` at the root and the working directory two
    folders below it: `as.character(weft("`r pi`{.num}"))` is `"3.142"`.
  - a folder with only `_quarto.yml` and no `_weft.yml`: the defaults.
  - the cache key: write `digits: 3`, call; overwrite the file with text of
    the same byte length that is not valid YAML and put back the old
    modification time with `Sys.setFileTime()`; a call still gives
    `"3.142"` (served from the cache); then change the modification time and
    the call is a `weft_config_error`; a second call is the same error
    (nothing cached); fix the file to `digits: 2` and the call gives
    `"3.14"`.
  - deleting `_weft.yml` gives the defaults on the next call.
  - two projects A and B whose `units:` give one unit different symbols:
    calls alternating between them (by `setwd()`) print each project's
    symbol (CF4).
  - in a knit with `weft_setup()`, a document's `weft: {digits: 2}` front
    matter wins over the project file for a `weft()` call in a chunk.
- **T12 speed** (`skip_on_cran()`), in a temporary project with a
  `_weft.yml`, using `cpu_time_min()` from `helper-perf.R`: after one warm
  call, the least CPU time of 200 `weft("Mean `r x`{.num} m")` calls is at
  most 20 times that of 200 `fmt_num(x)` calls (today about 50).
- **T13 static side** (ST1 to ST4), on `.qmd` fixtures, through `lint()`,
  `arms()` and the scanner as today's tests reach them: a typed numeral in
  `weft("We found 12 sites")` is a `numeral` finding at its file position
  with context `"weft"`; the same in `weft::weft(...)`, `weft(x = ...)`,
  `weft("...", .envir = e)`, `weft(.envir = e, "...")` and `weft(c("...",
  "..."))`; none in `weft_str("We found 12 sites")`; a `weft()` string in a
  chunk with `eval: false` or another engine is not read; `arms()` lists an
  `n` span of a `weft()` string with context `"weft"`; the gate counts it.
- **T14 Python** (skip as the existing guest tests do): `from weft import
  weft_str`; `weft_str('*a* [one | # sites]{n="k"}')` returns the markdown
  `str`; a list for several strings.

### Existing tests that change

`grep -l weft_str tests/testthat` gives 50 files (270 uses). The rule:

- `weft::weft_str(X)` or `weft_str(X)` called in a test to get text becomes
  `weft_md(X)`. Expected values do not change: the markdown is identical.
- Inside knitted fixtures (`.Rmd`/`.qmd` lines built in tests), a
  `weft_str(...)` call becomes `weft(...)`: in `cat()` in an asis chunk
  where the expectation is markdown with emphasis, use
  `cat(format(weft(...), target = "markdown"))`; where it holds no markup
  (`Found 3 sites`) `cat(weft(...))` is enough.
- Literal `weft_str('...')` strings in fixtures read by the lints, `arms()`,
  the gate and the scanner become `weft('...')`; expected context
  `"weft_str"` becomes `"weft"` (16 files, among them `test-arms.R`,
  `test-lint-construct.R`, `test-lint-source.R`, `test-lint-pandoc.R`,
  `test-lint-claims.R`, `test-review-c.R`, `test-doc-findings.R`,
  `helper-1e.R`).
- Message texts `a weft_str() string` become `a weft() string`.
- `test-weft-str.R` is renamed `test-weft.R` and its test of
  `"weft_str" %in% getNamespaceExports("weft")` is inverted.
- Python and its module lists (`helper-5c.R:56`, `test-guest-forms.R`,
  `test-lint-guest.R`, `GUEST_PY_MODULE_NAMES` expectations) keep
  `weft_str`.
- `test-conformance-*.R` call `conf_row_text()`, which used `weft_str()`
  internally; their expectations do not change.
- `test-tex-target.R` pins the E100 text; it becomes the FT3 text.

## Rule edits for `dev/PACKAGE-SCOPING.md`

Replacement text. Part 3 (evidence) is a record of what was run and keeps
`weft_str()`.

**1.4.8**, the paragraph after the YAML block, last sentence added: "Under
the plain target (1.4.24) a project formatter is called as for markdown and
its text is read as 1.4.24 says; `targets:` does not list `plain`."

**1.4.10**, first sentence: "Formatter output is markdown, as stock knitr's
inline output is, except inside math and raw LaTeX (1.4.23) and under the
plain target (1.4.24)."

**1.4.23**, the ledger bullet: "...a caption, front matter or a `weft()`
string keeps its own context."

**1.4.24** (new) Under the target `plain` a formatter writes Unicode text
with no markup, for places that print none: a plot's labels, the console, a
log. The plain text is the markdown text read as follows, so the two never
disagree:

- [PL1 to PL11 of `dev/design-e1.md`, verbatim, as a list]

So `.sci` prints `1.2 × 10⁻⁴`, a unit `m²` or `s⁻¹`; emphasis and the
attributes of a span go; a list keeps its lines; the minus sign, the
no-break space and the markers of 2.6.8 stay; a formula keeps its TeX as
written. Every class has a plain form. The plain form of a `weft()` string
is read the same way, the author's text included: a literal `*`, `_`, `^` or
`~` is kept with a backslash.

**1.5.20**, second bullet: "At the start of a block, or of a `weft()`
string, a caption or a front-matter field, ..."

**1.10.10** `weft()` resolves markup in R code (§3.6). Text that a chunk
prints with `results: asis` is not prose the hooks see; it goes through
`weft()`: the chunk prints the object, and knitr writes its markdown. A
caption option that R computes as a `weft` object is written in its markdown
form.

**2.4.1**: "...in prose, in a caption, or in a string given to `weft()`."

**2.4.6**: "In a knit, in prose, a caption, a `weft()` string or chunk
code, ..."

**2.6.2**, last sentence: "...or in a `weft()` string (2.6.8)."

**2.6.8**, the paragraph after the table: "A string given to `weft()` has no
line, and its marker names the chunk: `<<weft: failed claim, chunk
fig-depth>>`; called from inline R in prose it names the line. The marker is
the same in draft mode and in every target of the string. Every marker can be
found by searching for `<<weft:`."

**2.6.11**: "`weft()` outside a knit signals the same warning and returns
its object."

**2.9.1**: "...so what is replayed is the chunk's `weft()` strings."

**2.10.2**: "...its captions in chunk options and the literal strings passed
to `weft()`."

**2.12.2**: "(a value, a bare value, a governor, a caption construct on an R
chunk, a `weft()` string)".

**2.12.8**: unchanged list; add after "...one string as a `str` and several
as a `list` of `str`.": "`weft_str` calls R's `weft()` (3.6) and returns its
markdown."

**2.12.9**: "`weft_str()` from the module resolves it, as 3.6.5 says, ..."

**3.2.3**: "...a `sign` span is written as markup in a `weft()` string."

**3.4.11** Every `fmt_*()` takes `target` as its last argument, `"markdown"`
by default. `"markdown"` is every output before 1.4.23, byte for byte, and the
result carries no new attribute. `target = "tex"` writes the forms of 1.4.23
and 4.4.25, for text that goes into math or raw LaTeX from code: a chunk that
builds a table of formulas. `target = "plain"` writes the forms of 1.4.24, for
a sink that prints no markdown: a ggplot2 scale's labels, a console message.

```r
fmt_num(-1234567.89, target = "tex")      # -1{,}234{,}567.9
fmt_pct(0.123, target = "tex")            # 12.3\%
fmt_num(u(5, mg/L), target = "tex")       # 5\,\text{mg/L}
fmt_sci(0.000123, target = "plain")       # 1.2 × 10⁻⁴
fmt_num(u(5, m^2), target = "plain")      # 5 m² (a no-break space)
scale_y_continuous(labels = \(b) fmt_num(b, target = "plain"))
```

- A `target` that is not `"markdown"`, `"tex"` or `"plain"` is a
  `weft_construct_error`: "`target` must be \"markdown\", \"tex\" or
  \"plain\"; got %s." Here `%s` is the value in double quotes, or `something
  else` when it is not one string.
- [the TeX-form bullet, unchanged]
- A result made under `"tex"` has the attribute `target = "tex"`. If it
  reaches a markdown result without being formatted again from its raw value
  (a pass-through, a text class, a collapse), it is a `weft_value_error`:
  [today's text]. Reaching a plain result, the error says: "This text was
  formatted for TeX (target = \"tex\") and would print here as plain text.
  Format the number again, with target = \"plain\" (rule 3.4.11)."
- A result made under `"plain"` has the attribute `target = "plain"`, keeps
  its printed record, and its `unit` attribute holds the plain symbol or name.
  Given to another formatter it is treated as a markdown text.
- `fmt_unit()` takes `target` too: `fmt_unit(u(5, mg/L), target = "tex")` is
  `\text{mg/L}`; `fmt_unit(u(1, m^2), target = "plain")` is `m²`.
- [the last bullet, unchanged]

**§3.6** replaced:

> ### 3.6 `weft()`
>
> **3.6.1** `weft(x, .envir = parent.frame())` resolves weft markup in R
> code, for the text slots no chunk option reaches: a plot's title and
> labels, a console or log message, a table's caption, text printed with
> `results: asis`. Each element of `x` is a block of prose. [WS1, from "The
> result is" to the two error texts.]
>
> **3.6.2** [WS2, WS3 and WS4, joined; WS4 without the mention of E2.]
>
> **3.6.3** A `weft` object is a character vector whose content is the
> plain text of each element (1.4.24) and whose attribute `markdown` holds
> the markdown. [WS7's table.] [WS8's table.] [WS9, WS10, WS11.]
>
> **3.6.4** In a knit, `knitr::knit_print()` writes the markdown [WS7's two
> rows]. [WS16.] [WS17.] A formula in the markup keeps its TeX in the plain
> form (1.4.24): a plot that needs one uses plotmath.
>
> **3.6.5** A string given to `weft()` is prose wherever it is called from.
> [WS12, WS13, WS14.] It reads the configuration as a knit does: a
> configuration error is raised, and it never prints with half a
> configuration.
>
> **3.6.6** Outside a knit with weft's hooks, `weft()` reads the
> configuration of the project root of the working directory (the nearest
> folder upward that holds `_weft.yml`, else `_quarto.yml` or
> `_quarto.yaml`, else the working directory). It is read once and kept for
> the session, and read again when `_weft.yml` there appears, disappears or
> changes size or modification time. A read that fails keeps nothing, so
> every call fails until the file is fixed. The language is English and draft
> mode is off.
>
> **3.6.7** The lints read a literal string passed to `weft()` as prose
> (5.1.3): the argument R matches to `x` (named `x`, else the first argument
> without a name), one string or `c()` of strings, in the code of an R chunk
> that runs, as `weft(...)` or `weft::weft(...)`. The context of what is
> found there is `weft`.
>
> **3.6.8** From a Python chunk, `weft_str()` is in the module (2.12.8). It
> calls `weft()` and returns the markdown as a `str`. The expressions in its
> markup are R.

**3.7.1**: "...in prose, captions, front-matter fields and literal `weft()`
strings, ..."

**5.1.1**: "(prose, caption, front matter, `weft()` string, phrase, chunk or
project)".

**5.1.3**: "...the literal strings passed to `weft()` (3.6.7), ..."

**5.2.1**: "...the strings of `weft()` and the phrases of 5.1.6..."

**5.5.1**: "It reads prose, captions, front matter and `weft()` strings,
..."

Part 2:

**1.4.24** (new) A plot, a console and a log print no markdown, and in them
`10^−4^` and `**` show as typed (tested on 19 Nov). The plain form is read
from the markdown, not written by a second set of formatters, because the
author's text in a `weft()` string is markdown too and needs reading anyway;
one reader keeps the markdown exactly as it was and the two forms from ever
disagreeing about a value. The reader follows Pandoc on the forms weft writes,
so data text, which is not escaped (1.4.10), reads the same in both. Lists
keep their lines instead of being refused, as under TeX, because a string is
rendered at its sink, long after the call that made it.

**3.4.11**, appended: "`plain` is on the same argument so that a formatter
can label a ggplot2 scale."

**3.6** (replaces the entry "3.6.1, 3.6.3") A plot title, a table footnote
and a `kable()` caption are prose that no chunk option reaches. `weft()`
evaluates at the call because a template evaluated at the sink reads each
variable when the plot is drawn: three titles built in a loop all showed the
last site (tested, 19 Nov). It returns an object, not text, because only the
sink knows its target: a plot wants plain text, a knit markdown. The object's
content is the plain text so that a function that does not know the class
(`cat()`, `nchar()`) still gets readable text. The configuration is kept per
project because reading it was most of the 10 ms a call cost. A string is
prose whoever calls the function, so a caption built in R fails the same way
as one written in a chunk option.

## Documentation

- `R/weft-str.R` becomes `R/weft.R`: roxygen for `weft()` (examples: a
  title in a loop, `format(target = "markdown")`, a ggplot2 title inside
  `if (requireNamespace("ggplot2", quietly = TRUE))`), the S3 methods, and
  `@param target` on `fmt_*()` (in `R/format.R:1439`) naming `"plain"`.
  `man/weft_str.Rd` goes; `man/weft.Rd`, `arms.Rd`, `rehearse.Rd` and the
  `fmt_*` pages regenerate. `NAMESPACE` by roxygen: `export(weft)`,
  `S3method()` for `as.character`, `format`, `print`, `[`, `[[`, `[<-`, `c`,
  and `S3method(knitr::knit_print, weft)`.
- `_pkgdown.yml:45`: `weft_str` becomes `weft`.
- `NEWS.md`: `weft()` replaces `weft_str()` (an object, plain and markdown
  forms, evaluated at the call, cached configuration); `target = "plain"`.
- Vignettes, each `weft_str()` in R becomes `weft()`:
  `adopting.Rmd:135`; `languages.Rmd:129` (R), `:317-335` and `:491` keep
  Python's `weft_str`, with one sentence that it calls R's `weft()`;
  `named-values.Rmd:162-193` (the `cat()` example prints the object
  instead); `lints.Rmd:110`; `weft.Rmd:61,189-194`; `values.Rmd:306-310`
  (it shows the markdown weft writes, so it prints
  `format(weft(...), target = "markdown")`) and `:382-388`;
  `wording.Rmd:115,236,277,298,583`.
- `inst/agent/references/syntax.md` and `skills/weft`: no mention of
  `weft_str()` today; nothing to change in E1 (E5 adds the strings section).

## Order of work

1. Test-writer: `helper-0-common.R` (`weft_md()`), T1 to T14, the migration
   of the 50 files. Check that the new tests fail for the right reason
   (`weft` not found, `target = "plain"` refused) and the migrated ones only
   because `weft()` does not exist yet.
2. Implementer, in this order, the suite run after each step:
   1. `R/plain.R`: the reader (runs) and the plain renderer; pure functions
      (T4's reader table).
   2. `target = "plain"` in `apply_formatters()`, `fmt_unit()`,
      `tex_target()`/`check_target()` (FT3), the FT4 check (T5).
   3. The configuration cache and the CF1 order (T11, T12).
   4. `weft()` and its methods, replacing `weft_str()`; WS11 in
      `apply_formatters()` and the resolver; `str_where()` text; the inline
      function names cached (T1 to T10).
   5. The caption hook for computed captions (WS16).
   6. The static side and the context rename (T13).
   7. Python's `guest_form("weft_str")` (T14); `conformance.R` and
      `dict-tools.R` callers moved to `weft()`.
   8. Roxygen, `devtools::document()`, vignettes, `_pkgdown.yml`, `NEWS.md`.
3. Whole suite (one R process), the T12 aim measured and logged, opus
   review, fixes, then the spec editor applies the rule edits above.

## For Robin

1. The plain form reads the author's own markdown too (D1, 1.4.24): a title
   typed `*Eucalyptus* cover` draws as "Eucalyptus cover", and a literal `*`
   needs `\*`. This departs from the plan's wording ("the formatters'
   markdown emitters become target-aware"): one reader replaces those
   emitters. Say if author text should stay verbatim instead.
2. Outside a knit, `fmt_*()` still use the default settings while `weft()`
   reads `_weft.yml` (as `weft_str()` did), so a script's tick labels and its
   title can differ in digits. Making `current_config()` use the same cache
   is a small follow-up, outside E1 unless you want it in.

## Amendment by the orchestrator (25 Nov)

**A1 `fmt_*()` read the same configuration as `weft()` outside a knit.**
Today `fmt_*()` called outside a knit use the default settings while
`weft()` reads `_weft.yml` through the cache (CF), so a script's tick labels
(`labels = \(x) fmt_pct(x, target = "plain")`) and its title (`weft(...)`)
could print different digits. In E1, outside a knit, `fmt_*()` and the
phrase functions take their configuration from the same cache as `weft()`
(the project's `_weft.yml`, else the defaults); inside a knit they keep
reading the knit's configuration. A configuration error is a
`weft_config_error`, as for `weft()`. Alternative: leave it as a follow-up;
refused, because one script printing one value two ways is the defect weft
exists to stop. Tests: a temp project with `digits: 3` in `_weft.yml`;
`fmt_num(pi)` and `as.character(weft("`r pi`{.num}"))` print the same
`3.142` with the working directory there, and `3.1` from a directory with
no project.

**A2 D1 accepted with its stated cost.** Plain text is read back from the
resolved markdown. Data text stays unescaped (1.4.10), so a `*` in a value
reads the same in markdown and in plain; escaping data text is a separate
question for both targets, not E1's.
