# The static lints

This article is for authors who want to find problems in a project’s
documents without rendering them: numbers typed into the prose,
constructs that will not parse, broken cross-references, figures without
alt text. After it you will be able to run the lints, read their
findings, fix or exempt each one, and tune the rules for a project.

``` r

library(weft)
```

## What a lint is

A **lint** is a rule with a stable id.
[`lints()`](https://vorpalvorpal.github.io/weft/reference/lints.md)
reads every `.qmd` and `.Rmd` in a project as text, runs nothing, and
returns the **findings**: one row for each place a rule matched, with
its file, line and column, the rule, a message that ends with the rule’s
number in the design, and a hint.

Every rule has a **tier**:

| Tier | What it is | What happens |
|----|----|----|
| 1 | a hard rule, decidable from the source | fails the commit, the render or [`verify()`](https://vorpalvorpal.github.io/weft/reference/verify.md) |
| 2 | a heuristic | listed for newly added lines by [`changes()`](https://vorpalvorpal.github.io/weft/reference/changes.md) and [`verify()`](https://vorpalvorpal.github.io/weft/reference/verify.md); blocks nothing |
| 3 | a human read | the ranked list of [`changes()`](https://vorpalvorpal.github.io/weft/reference/changes.md); never decided by weft |

[`lint_rules()`](https://vorpalvorpal.github.io/weft/reference/lint_rules.md)
lists every rule:

``` r

lint_rules()[, c("id", "tier", "scope", "what")]
#>                     id tier   scope
#> 1              numeral    1    file
#> 2            construct    1    file
#> 3                 read    1    file
#> 4          block-start    1    file
#> 5             lone-bar    2    file
#> 6              if-zero    2    file
#> 7                 name    2    file
#> 8          inert-check    1    file
#> 9           long-guard    2    file
#> 10            cite-key    1    file
#> 11           cite-bare    1    file
#> 12        citation-key    1    file
#> 13          claim-word    2    file
#> 14       literal-value    1    file
#> 15      value-constant    2    file
#> 16        value-format    2    file
#> 17                xref    1 project
#> 18        anchor-twice    1 project
#> 19           ref-label    1    file
#> 20       anchor-unused    2 project
#> 21           xref-code    2    file
#> 22      section-anchor    1    file
#> 23         chunk-label    1    file
#> 24            tar-name    1    file
#> 25         dict-assign    1    file
#> 26           file-link    1    file
#> 27         above-setup    1    file
#> 28            dict-key    1    file
#> 29           tar-cache    1    file
#> 30        config-place    1 project
#> 31              engine    1 project
#> 32 front-matter-quarto    1    file
#> 33              figure    1    file
#> 34       table-caption    1    file
#> 35        guest-inline    1    file
#> 36          guest-call    1    file
#> 37          guest-read    2    file
#> 38           ojs-value    2    file
#> 39   named-unpublished    2    file
#> 40      publish-hidden    1    file
#> 41       string-markup    2    file
#>                                                                   what
#> 1  A number typed in prose, a caption, front matter, a string or math.
#> 2                           An error the scanner finds in a construct.
#> 3                                            A file that is not UTF-8.
#> 4                            A line inside a span that starts a block.
#> 5                              A bracket with one `|` and no governor.
#> 6                              An `if` condition that compares with 0.
#> 7           A class or key that is not weft's, or is one edit from it.
#> 8                         A check or condition with no variable in it.
#> 9                               An `if` arm longer than `guard_words`.
#> 10                       A key of a cite span not in the bibliography.
#> 11             A bare cite key not written as a citation in its block.
#> 12                             A citation key not in the bibliography.
#> 13                                         A claim word in a sentence.
#> 14                                     A value made only of constants.
#> 15                                  A numeric constant inside a value.
#> 16                             A value that rounds or formats in code.
#> 17                                     A cross-reference to no anchor.
#> 18                                   An anchor defined more than once.
#> 19                  A span whose text is a reference-definition label.
#> 20                A figure, table or equation anchor nobody refers to.
#> 21                       A cross-reference written inside a code span.
#> 22                                          A heading with no `{#id}`.
#> 23                                    An executed chunk with no label.
#> 24                         A target read that the store does not hold.
#> 25                                            An assignment to `dict`.
#> 26                        A link or image to a file that is not there.
#> 27                A construct above the chunk that calls weft_setup().
#> 28                       A `dict$key` read of a key that is not there.
#> 29                             A chunk that reads a target and caches.
#> 30             A project setting in a place that is not the project's.
#> 31                     A document with constructs that is not knitr's.
#> 32     A `---` block Quarto reads as front matter and Pandoc does not.
#> 33                        A figure with no label, caption or alt text.
#> 34                                            A table with no caption.
#> 35          Inline code in another language, which knitr does not run.
#> 36                    A weft function called from Python through `r.`.
#> 37         A value read from Python or Julia that weft does not check.
#> 38               An Observable value computed in the reader's browser.
#> 39 A name used by a named value or filter span that nothing publishes.
#> 40          A chunk that publishes values where its output is dropped.
#> 41         Weft markup in an R string that does not go through weft().
```

A rule’s **scope** is `file` when it reads one document at a time, and
`project` when it reads them all, as cross-references do.

## Running the lints

This project has an empty `_weft.yml` and one document with several
problems:

``` r

writeLines("", "_weft.yml")
writeLines(c(
  "---",
  "title: \"Survey\"",
  "---",
  "",
  "## Results {#sec-results}",
  "",
  "```{r}",
  "#| label: data",
  "n_sites <- 12",
  "```",
  "",
  "We visited 14 sites in 2023, and Site 4 was dry.",
  "Of these, `r 3 + 4` were above the trigger.",
  "Turbidity [rose | fell]{if=\"slope > 0\" .num}.",
  "All sites were sampled at `r n_sites` locations.",
  "Samples were filtered through [0.45 µm]{.weft-literal why=\"pore size set by the laboratory method\"} membranes.",
  "Discharge [rose | fell]{iff=\"q > 0\"} after the storm.",
  "See Figure 2 for the map.",
  "",
  "## Methods",
  "",
  "```{r}",
  "plot(1:3)",
  "```"
), "survey.qmd")
lints()
```

    #> weft lints: 9 findings in 1 file (9 tier 1, 0 tier 2)
    #> 
    #> survey.qmd
    #>   1:1    engine          survey.qmd holds weft constructs but is not marked `engine: knitr` and no document includes it (rule 5.8.9).
    #>                          Add `engine: knitr` to its front matter. Or write each value as a name, `x`{.num}, and publish it in code: then no knitr is needed (rule 1.12.8).
    #>   12:12  numeral         "14" is a number typed in prose (rule 5.2.1).
    #>                          Write it as a value, put it in the dictionary, or mark it [14]{.weft-literal why="..."}.
    #>   12:24  numeral         "2023" is a number typed in prose (rule 5.2.1).
    #>                          Write it as a value, put it in the dictionary, or mark it [2023]{.weft-literal why="..."}.
    #>   12:39  numeral         "4" is a number typed in prose (rule 5.2.1).
    #>                          Write it as a value, put it in the dictionary, or mark it [4]{.weft-literal why="..."}.
    #>   13:14  literal-value   `3 + 4` is made only of constants, so it is a number typed in the source (rule 5.6.1).
    #>                          Compute it, put it in the dictionary, or write [3 + 4]{.weft-literal why="..."}.
    #>   14:11  construct       A formatter on an `if` span is an error (rule 1.5.7): .num.
    #>   18:12  numeral         "2" after "Figure" is a typed cross-reference number; use @fig-<label> (rule 5.2.4).
    #>                          Write @fig-<label> and give the target that label.
    #>   20:4   section-anchor  The heading `Methods` has no `{#id}` (rule 5.8.1).
    #>                          Give it an id, for example `{#sec-name}`.
    #>   22:1   chunk-label     The r chunk `plot(1:3)` has no label (rule 5.8.1).
    #>                          Give the chunk a label, as `#| label: name`.

By default
[`lints()`](https://vorpalvorpal.github.io/weft/reference/lints.md) runs
the tier-1 rules over the whole project. `lints(files = )` limits the
report to some documents, `rules =` names rules by id, and `tier = 2` or
`tier = 1:2` asks for the heuristics:

``` r

lints(tier = 2)
#> weft lints: 5 findings in 1 file (0 tier 1, 5 tier 2)
#> 
#> survey.qmd
#>   14:29  if-zero     The condition `slope > 0` compares with 0, which is a threshold typed in the source (rule 5.3.3).
#>                      A comparison with zero probably wants `sign`: write [a | b | c]{sign="..."} with an arm for each of positive, negative and zero (rule 5.3.3).
#>   15:1   claim-word  Claim word "all" in a sentence with a value; check that the value still bears it out, or guard the word with an `if` span (rule 5.5.1).
#>                      "All sites were sampled at `r n_sites` locations."
#>   17:12  claim-word  Claim words "rose", "fell" in a sentence with no value: if it states a result, compute it (rule 5.5.1).
#>                      "Discharge [rose | fell]{iff="q > 0"} after the storm."
#>   17:12  lone-bar    The bracket `[rose | fell]` holds one `|` and has no governor, so it is not read as arms (rule 5.3.3).
#>                      Add a governor (`n`, `if`, `sign`, `list`) or escape the bar as `\|`.
#>   17:25  name        `iff` is not a name weft knows; it is one edit from `if` (rule 5.3.3).
#>                      Check the spelling, or list the name under `expected_names` in _weft.yml.
```

## Typed numbers

The rule `numeral` is the centre of the lints. Every numeral in the
prose must be one of these:

- a computed value, `` `r n_sites` ``;
- a value from the dictionary, `` `r dict$trigger` ``;
- inside a `cite` span, because it is quoted from a source;
- inside a `.weft-literal` span or block, with a `why` that says why it
  is fixed.

A word whose first letter or digit is a digit is a numeral: “12”, “45%”,
“11-year”, “3rd”, “1990s”. A word that starts with a letter is a name:
“CO2”, “PM2.5”. The rule reads the body, captions, the front-matter
fields that take constructs,
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md)
strings, and inline math, where an exponent or a subscript is exempt. A
value in math is written as inline R with a class block, which writes
TeX there: see “Values in math and raw LaTeX” in
[`vignette("values")`](https://vorpalvorpal.github.io/weft/articles/values.md).

The `.weft-literal` span in the example above is why “0.45” is not a
finding. Its `why` is the record: nothing else lists it.

Two settings in `_weft.yml` exempt more:

- `label_words`: words after which a number is a name, not a quantity,
  such as “Site” in “Site 4”. The list starts empty.
  [`label_seed()`](https://vorpalvorpal.github.io/weft/reference/label_seed.md)
  proposes candidates from the prose.
- `numeral_years: true` exempts a four-digit year from 1000 to 2999, a
  year range such as 2016-17, a decade and a possessive year. It is off
  by default, because a year in prose is often a choice that belongs in
  the dictionary.

``` r

label_seed(min_count = 1)
#>   word n files                 where
#> 1 Site 1     1 survey.qmd:12: Site 4
writeLines(c("label_words: [Site]", "numeral_years: true"), "_weft.yml")
lints(rules = "numeral")
#> weft lints: 2 findings in 1 file (2 tier 1, 0 tier 2)
#> 
#> survey.qmd
#>   12:12  numeral  "14" is a number typed in prose (rule 5.2.1).
#>                   Write it as a value, put it in the dictionary, or mark it [14]{.weft-literal why="..."}.
#>   18:12  numeral  "2" after "Figure" is a typed cross-reference number; use @fig-<label> (rule 5.2.4).
#>                   Write @fig-<label> and give the target that label.
```

A number after a word Quarto can cross-reference (“Figure 2”, “Table 3”,
“Section 4”) is never exempt: write a cross-reference such as `@fig-map`
instead.

When weft is adopted, a project’s existing documents may hold hundreds
of typed numbers. The commit gate tolerates the ones already committed
and refuses only new ones, so adoption can be gradual. See
[`vignette("gate", package = "weft")`](https://vorpalvorpal.github.io/weft/articles/gate.md).

## Literal values

A value made only of constants, such as `` `r 3 + 4` `` or `{n="3"}`,
renders, but it is a number typed in the source. The rule
`literal-value` finds it. Compute the number, put it in the dictionary,
or write it as a `.weft-literal` with its `why`.

The tier-2 rules `value-constant` and `value-format` list a numeric
constant inside a computation (other than 0 and 1) and a value that
rounds in code with [`round()`](https://rdrr.io/r/base/Round.html),
[`format()`](https://rdrr.io/r/base/format.html) or
[`sprintf()`](https://rdrr.io/r/base/sprintf.html). Rounding in code
skips weft’s formatters, so the value has no printed record and
[`round()`](https://rdrr.io/r/base/Round.html) drops trailing zeros.
`value-format` also lists a bare
[`fmt_num()`](https://vorpalvorpal.github.io/weft/reference/fmt.md) or
another `fmt_*()` in math, which writes markdown there; a class block
writes TeX. It lists a bare `fmt_*()` in prose given a literal
`target = "html"` or `target = "marquee"` too: the document would show
the marks or drop the tags. Those targets are for a sink such as a plot,
where [`format()`](https://rdrr.io/r/base/format.html) gives them; in
prose write a class block.

## How fences and chunks are read

One reader finds the fences of a document for every rule, the scanner
and the front-matter readers alike, and the Quarto filter, Python and
Julia read front matter the same way. An executable chunk is found as
knitr finds it, before anything else: three or more backticks, then `{`
and an engine name, at any indent, behind `>` quote markers, and even
inside an HTML comment. An unclosed chunk runs to the last line. Every
other fence is read as Pandoc’s markdown reader, which Quarto uses,
reads it: a `~~~` fence is never a chunk; a fence opens only with an
info string of one word or an attribute block (```` ```text ```` or
```` ```{.text} ````, not ```` ```text a ```` or a word holding a
backtick); a fence that never closes is no fence, and its text is prose;
and in a list item, a fence indented four or more spaces needs a blank
line above it. A `---` line inside any fence opens no front matter.

## Notebooks

[`lints()`](https://vorpalvorpal.github.io/weft/reference/lints.md) also
reads Jupyter notebooks (`.ipynb`) as documents. A markdown cell is
prose, a raw cell is its text, and a code cell is a chunk in the
kernel’s language. A finding is placed in the JSON file: at the line of
the JSON string that holds the source line, and at the column of the
character in that line, with escapes counted as written. A finding about
something weft adds to a cell, such as a fence, is placed at the cell’s
`"source"` key.

Percent scripts are read the same way: a `.py` file with a
`# %% [markdown]` or `# %% [raw]` cell, which is how Quarto decides that
a `.py` is a document. Its markdown cells are prose with the `#` taken
off, its code cells Python chunks, and a finding is placed at its line
and column in the `.py` file. A `.py` with only code cells, or an
ordinary module, is code and is not read. Notebooks in
`.ipynb_checkpoints` or `_freeze` are not read either.

The other surfaces read the same documents. The commit gate judges a
staged notebook or percent script as it judges a `.qmd`,
[`checks()`](https://vorpalvorpal.github.io/weft/reference/checks.md)
lists its checks, and
[`verify()`](https://vorpalvorpal.github.io/weft/reference/verify.md)
lints and renders it, with every row at the line of the file (the JSON
line of a notebook).
[`verify()`](https://vorpalvorpal.github.io/weft/reference/verify.md)
renders a notebook as `quarto render` does, as stored and not executed
unless its front matter says `execute: enabled: true`, and executes a
percent script unless `execute: enabled: false` or `_freeze` says not.
[`status()`](https://vorpalvorpal.github.io/weft/reference/status.md)
shows its `python` row when the project holds either.

## Construct errors

A **construct error** is a mistake in weft syntax that the scanner finds
without running R: a formatter on an `if` span, as in the example, the
wrong number of arms, two classes from one group, a `"` inside an
attribute value, an id defined twice, a class with no TeX form (such as
`.word`) in math. The rule is `construct`. A render stops at the first
construct error, and the commit gate refuses a changed document that
holds one, whatever `HEAD` held.

The rule `block-start` finds a line inside a span that Pandoc would read
as the start of a new block, which cuts the span in two.

## Checks that cannot fail

The rule `inert-check` finds a
[`claim()`](https://vorpalvorpal.github.io/weft/reference/claim.md)
check, or an `if` condition, with no variable in it: `claim(x, TRUE)` or
`if="1 > 0"`. Such a check cannot fail, and such a condition always
chooses the same arm, so neither checks anything.

## Cross-references, citations and figures

| Rule | Finds |
|----|----|
| `xref` | a reference, such as `@fig-map` or a link to `#sec-x`, with no anchor anywhere in the project |
| `anchor-twice` | an anchor defined twice |
| `ref-label` | a span whose text is also a reference-link label in the document |
| `cite-key`, `citation-key` | a citation key that is not in the bibliography |
| `cite-bare` | a bare-form `cite` span whose key is not cited in the same block |
| `figure` | a figure with no label, caption or alt text |
| `table-caption` | a table with no caption |
| `section-anchor` | a heading with no `{#id}` |
| `chunk-label` | an executed chunk with no label |

A missing section anchor or chunk label matters because the ledger keys
each value on its section, and a stable anchor keeps that key stable
when the heading’s words change.

## Project hygiene

| Rule | Finds |
|----|----|
| `engine` | a `.qmd` with constructs but no `engine: knitr` in its own front matter |
| `above-setup` | a construct above the chunk that calls [`weft_setup()`](https://vorpalvorpal.github.io/weft/reference/weft_setup.md) |
| `dict-key` | `dict$key` for a key the dictionary does not hold |
| `dict-assign` | chunk code that assigns to `dict` |
| `tar-name` | [`tar_read()`](https://docs.ropensci.org/targets/reference/tar_read.html) of a target the store does not hold |
| `tar-cache` | a chunk that reads a target and has `cache: true` |
| `file-link` | a link or image to a file that is not there |
| `config-place` | a `weft:` key in `_quarto.yml`, or a project setting in a document |
| `front-matter-quarto` | a `---` block in a `.qmd` that Quarto reads as front matter and Pandoc does not: text directly above it, or inside a `~~~` fence |
| `read` | a file that is not UTF-8 |

## Python, Julia and Observable

A document that mixes languages reaches prose through R. These rules
find the ways a value from another language goes wrong on the way.

| Rule | Tier | Finds |
|----|----|----|
| `guest-inline` | 1 | inline code in another language, such as `` `{python} depth` ``, in a document knitr knits: knitr does not run it, so it prints as code |
| `guest-call` | 1 | `r.fmt_num(` and the like in a Python chunk, which pass arguments through reticulate and can turn a Python integer into a wrong number; `from weft import fmt_num` is safe |
| `guest-read` | 2 | `py$n` in R chunk code, and `py_eval()`, `py_call()`, `julia_eval()` and the like in a value, which weft does not check; [`py_value()`](https://vorpalvorpal.github.io/weft/reference/py_value.md) and [`jl_value()`](https://vorpalvorpal.github.io/weft/reference/jl_value.md) are the guarded reads |
| `ojs-value` | 2 | an inline `` `{ojs} total` `` or a `${total}` in an Observable `md` or `html` template, which the reader’s browser computes after weft’s checks have run |

The first two block a commit like any tier-1 finding. The `engine` rule
also says which engine Quarto would pick for a Python or Julia document
and what to write instead.

## Tier-2 heuristics

The tier-2 rules guess. Their findings are worth a look and never block
anything:

- `claim-word`: a quantifier, extreme or direction word (“all”, “only”,
  “largest”, “rose”) in a sentence with a value, which the value may no
  longer bear out, or in a new sentence with no value at all. The list
  holds 65 English words. A word inside an `if` or `sign` span is
  already guarded and is not listed. Neither is a word inside an idiom
  such as “at least”, “no longer” or “most likely” (the list has 26), a
  word with a hyphen next to it (“best-supported”), or a word with a
  capital that does not start its sentence (“Wentworth Falls”). A
  quantifier (“all”, “only”, “never”) is listed only in a sentence that
  holds a value or a typed digit; the setting `claim_quantifiers`
  changes that.
- `if-zero`: an `if` condition that compares with zero.
- `lone-bar`: a bracket with one `|` and no governor, which is probably
  a span with a misspelt key.
- `name`: a class or key that weft does not know, especially one that is
  one edit from a weft name, such as `iff`.
- `long-guard`: an `if` arm longer than `guard_words` (25 words).
- `anchor-unused`, `xref-code`: an anchor nobody refers to, and a
  cross-reference written inside a code span.

Over a whole project the tier-2 rules can list a great deal. They are
meant for new material:
[`changes()`](https://vorpalvorpal.github.io/weft/reference/changes.md)
and
[`verify()`](https://vorpalvorpal.github.io/weft/reference/verify.md)
run them over the lines added since a commit.

## Scripts

Plot titles and console text are written in scripts as often as in
chunks, so
[`lints()`](https://vorpalvorpal.github.io/weft/reference/lints.md) also
reads the `.R` and `.r` files of the project, but only for the literal
strings they pass to
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md). It
also reads
[`claim()`](https://vorpalvorpal.github.io/weft/reference/claim.md)
calls, but only for the `inert-check` rule: how the gate counts them,
and the `if (FALSE)` rule, are in “Claims in scripts” in
[`vignette("gate", package = "weft")`](https://vorpalvorpal.github.io/weft/articles/gate.md).
A call is `weft(...)`, `weft::weft(...)` or `weft:::weft(...)`, or the
right-hand side of a pipe; the argument read is the one R matches to
`x`: a string (a raw string too) or the literal elements of a
[`c()`](https://rdrr.io/r/base/c.html). A computed argument
([`paste0()`](https://rdrr.io/r/base/paste.html),
[`sprintf()`](https://rdrr.io/r/base/sprintf.html), a name) is skipped.
The code around the call is not read, nor are the phrases of
[`lookup()`](https://vorpalvorpal.github.io/weft/reference/lookup.md)
and [`brk()`](https://vorpalvorpal.github.io/weft/reference/lookup.md),
or strings given to other functions.

``` r

dir.create("R")
writeLines(c(
  "library(ggplot2)",
  "p <- labs(title = weft(\"We found 12 sites\"))"), "R/plots.R")
lints()
#> weft lints: 8 findings in 2 files (8 tier 1, 0 tier 2)
#> 
#> R/plots.R
#>   2:34  numeral  "12" is a number typed in prose (rule 5.2.1).
#>                  Write it as a value, put it in the dictionary, or mark it [12]{.weft-literal why="..."}.
#> 
#> survey.qmd
#>   1:1    engine          survey.qmd holds weft constructs but is not marked `engine: knitr` and no document includes it (rule 5.8.9).
#>                          Add `engine: knitr` to its front matter. Or write each value as a name, `x`{.num}, and publish it in code: then no knitr is needed (rule 1.12.8).
#>   12:12  numeral         "14" is a number typed in prose (rule 5.2.1).
#>                          Write it as a value, put it in the dictionary, or mark it [14]{.weft-literal why="..."}.
#>   13:14  literal-value   `3 + 4` is made only of constants, so it is a number typed in the source (rule 5.6.1).
#>                          Compute it, put it in the dictionary, or write [3 + 4]{.weft-literal why="..."}.
#>   14:11  construct       A formatter on an `if` span is an error (rule 1.5.7): .num.
#>   18:12  numeral         "2" after "Figure" is a typed cross-reference number; use @fig-<label> (rule 5.2.4).
#>                          Write @fig-<label> and give the target that label.
#>   20:4   section-anchor  The heading `Methods` has no `{#id}` (rule 5.8.1).
#>                          Give it an id, for example `{#sec-name}`.
#>   22:1   chunk-label     The r chunk `plot(1:3)` has no label (rule 5.8.1).
#>                          Give the chunk a label, as `#| label: name`.
unlink("R", recursive = TRUE)
```

The finding is placed at the character of the script that holds it,
through escapes and raw strings. The rules that read scripts are the
ones marked `scripts` in
[`lint_rules()`](https://vorpalvorpal.github.io/weft/reference/lint_rules.md):
`numeral`, `construct`, `read`, `block-start`, `lone-bar`, `if-zero`,
`name`, `inert-check`, `long-guard`, `claim-word`, `literal-value`,
`value-constant` and `value-format`. The rules that read across
documents (cross-references, citations, hygiene) read documents only.

A script is left out when it is in a folder that starts with `.` or `_`,
or in `renv`, `packrat`, `node_modules`, `_site`, `_book`, `_freeze` or
`_extensions`, or when its own file name starts with `.`. The setting
`scripts_skip` in `_weft.yml` names more: a name with no `/` is matched
against each folder and the file name, and an entry with a `/` is a path
from the folder that holds the `_weft.yml`. No wildcards: an entry with
`*` or `?`, a leading `/` or a backslash is an error. Each script is
judged by the `_weft.yml` nearest to it, so a nested project can read
its own `tests` folder with its own `scripts_skip: []`. The setting is
`[tests]` unless set, because test files hold typed numbers and broken
markup on purpose; a list that you give replaces it, so keep `tests` in
it, and `[]` reads every script. An empty or commented-out
`scripts_skip:` (a null value) keeps the default. A script whose bytes
hold neither `weft` nor a `claim(` call is never read, one that is not
valid UTF-8 gives the `read` finding, and one that does not parse as R
gives a note and no findings. Naming a script that is left out, in
`files` or as `path`, gives a note that says which rule left it out.
`lints(reader = "pandoc")` reads scripts with weft’s reader too, since
they need no Pandoc. The commit gate counts a script’s findings and
constructs as it counts a document’s.

## Settings

| Setting | Default | Governs |
|----|----|----|
| `label_words` | `[]` | words after which a number is exempt |
| `numeral_years` | `false` | whether a four-digit year is exempt |
| `claim_words` | `{add: [], drop: [], idioms: []}` | words added to or dropped from the claim-word list, and phrases added to its idioms |
| `claim_quantifiers` | `number` | when a quantifier is listed: `number` (only in a sentence with a value or a digit), `any` or `none` |
| `claim_cap` | `20` | claim-word sentences listed per file before a count replaces them |
| `guard_words` | `25` | the length of an `if` arm that `long-guard` lists |
| `expected_names` | `[]` | classes (`.foo`) and keys (`foo`) from other tools that `name` should accept |
| `strict` | `[]` | tier-1 rules whose every instance fails [`verify()`](https://vorpalvorpal.github.io/weft/reference/verify.md) |
| `scripts_skip` | `[tests]` | folders and files whose `.R` scripts are not read (project setting) |
| `anchor_calls` | `[]` | helper calls that define anchors, for `xref`, `anchor-twice` and `anchor-unused` |

`strict` is for the end of adoption. Once a project has removed every
typed number, `strict: [numeral]` makes
[`verify()`](https://vorpalvorpal.github.io/weft/reference/verify.md)
fail on any that remain, whether or not they were committed before.

## Anchors made by a helper

A project that makes its tables or figures with a helper, such as
`tbl(x, id = "depths")`, can tell the lints about it:

``` yaml
anchor_calls:
  - fun: tbl
    arg: id
    prefix: "tbl-"
```

A call of `tbl()` in an executed R chunk, bare or as `pkg::tbl()`, then
defines the anchor `tbl-depths`, at the call’s line, for `xref`,
`anchor-twice` and `anchor-unused`. `arg` is the name of the argument,
or its position when it is a whole number; `prefix` is optional. Only a
literal string counts: a computed id defines nothing, and no finding
says so. An entry without `fun` or `arg` is a configuration error.

## The two readers

By default the lints tell prose from code with weft’s own reader, which
runs no Pandoc and gives the same answer on every machine.
`lints(reader = "pandoc")` also parses each document with Pandoc 3.0 or
later, and counts a character as prose only when both readers agree. It
finds the Pandoc version from the option `weft.pandoc`, the variable
`WEFT_PANDOC`, Quarto, rmarkdown or the path.
