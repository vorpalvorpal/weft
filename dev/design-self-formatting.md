# Design: self-formatting values

**Date:** 2026-11-27. **Status:** design for Robin's review; nothing built.
**Source of the request:** `dev/plan-weft-everywhere.md`, "Later, not in this
plan": "Self-formatting values (`num(x, digits = 1)` that print correctly
through `paste()`, `glue()` and any sink)". Robin asked for it on 27 Nov
(`dev/decisions.md`, "Robin's rulings (2026-11-27)").

Nothing here was run. R was not started (one R process at a time on this
machine). Every claim about how R, knitr, glue, grid and vctrs behave was read
from their sources or their installed help, and the place is named. The test
plan (section 8) turns each such claim into a test, so a wrong reading is
caught before code depends on it.

In this note `x` and `-` in a quoted output such as `1.2 x 10^-4^` stand for
the Unicode times sign and minus sign that weft really prints. The file is
ASCII.

---

## 1. The problem

An author computes a number in a chunk and puts it in text that R builds: a
plot title, a log line, a table cell, a sentence written by `cat()` in a
`results: asis` chunk. Today there are three ways to do it, and each has a
hole.

**A bare number.** `m <- mean(x)`.

- `paste("Mean", m)` gives `"Mean 3.14159265358979"`: `as.character()` of a
  double writes 15 significant digits.
- `` `r m` `` in prose gives `3.141593`: knitr's inline hook rounds to
  `getOption("digits")` (knitr `R/hooks.R`, `.inline.hook`, and
  `round_digits()` in `R/utils.R`).
- `` `r m`{.num} `` gives `3.1`.

One value prints three ways. No ledger entry is made for the first; the
second and third are recorded.

**A formatter's text.** `fmt_num(m)` returns a `weft_text`, a character
vector with the printed record in attributes (rule 3.4.2). Its content is
markdown.

- In a plot, markdown shows as typed. `paste("Area", fmt_sci(a), "m^2")`
  draws `Area 1.2 x 10^-4^ m^2`, carets and all. The author must remember
  `target = "plain"` at every call that feeds a plot (3.4.11).
- In math, the same text is wrong again: it needs `target = "tex"` (the lint
  `value-format`, 5.6.4, lists the bare case).
- It is text, not a number. `fmt_num(10) > 9` compares the strings `"10"`
  and `"9"` and is `FALSE`. `claim(fmt_num(n), . > 9)` fails for `n = 10`.
  `sort()` sorts it as text. A `weft_text` loses its attributes through
  `ifelse()`, `unlist()`, `vapply()` and most data-frame code, and then it is
  a bare string with all of these problems.
- The digits are chosen at each call. A value used in a title, a caption
  and a table can print three precisions unless every call repeats them.

**A `weft()` string.** `weft("Mean `m`{.num digits=1}")` is right for plots,
consoles and markdown (3.6), and in a knit it records ledger entries. But it
is prose: the author writes a sentence of markup around every number, and
the result is text again, with no number underneath.

**What happens to the checks.** None of the three paths through code reaches
the ledger, except where weft already sees the text:

| Route | Formatting | Ledger | Gate | Claims |
|---|---|---|---|---|
| `paste()`/`glue()`/`sprintf()` into a plot title | as the author wrote it; markdown if from `fmt_*()` | none | not counted | a `claim()` in the chunk still runs (2.4.4) |
| the same into `cat()` in a `results: asis` chunk | the same | one `table` entry: a digest of the printed text (7.1.1) | not counted | as above |
| `knitr::kable()` of a data frame | kable's own (`round()` and `format()`) | one `table` entry, a digest | not counted | as above |
| `` `r m` `` in prose | knitr's | a `bare` entry (7.1.2) | counted (6.3.1) | as above |
| `` `r m`{.num} `` in prose | weft's | a `value` entry | counted | as above |
| `weft()` string in a knit | weft's | `value` entries, context `weft`, at the call | the literal is counted in scripts (6.3.1) | in the markup |

So the gap the feature closes is not the ledger. It is that a number going
into text through code is either formatted by hand, or formatted by weft as
text that has stopped being a number and is in the wrong form for half the
sinks.

**What the author wants.** Say once how a number prints, keep it a number,
and have every route print it the same: prose, a `weft()` string, `paste()`,
`glue()`, a plot, a table, the console.

---

## 2. What R lets a value control

A value can only control its text where the sink asks it. This was read from
R's sources (`src/main/paste.c`, `src/main/sprintf.c`, `src/main/builtin.c`,
`src/library/base/R/message.R`, `connections.R`, `grDevices/R/zzz.R`), from
glue (`R/glue.R`), knitr (`R/block.R`, `R/hooks.R`, `R/table.R`,
`R/utils.R`) and vctrs (`R/type-vctr.R`, `R/arith.R`, `R/numeric.R`), and
from R 4.4.3's installed help for `paste`, `sprintf`, `cat`, `Ops` and
`chooseOpsMethod`.

| Sink | How it turns a value into text | A character vector with a class | A double with a class |
|---|---|---|---|
| `paste()`, `paste0()` | C code: an argument that is not a string and is an object gets `as.character()` dispatched; a string is used as stored (`paste.c`, "method dispatch") | its content; **no method is called** | its `as.character()` method |
| `toString()` | `paste()` | content | method |
| `sprintf("%s")` | C code: an argument whose type is not character gets `as.character()` dispatched (`sprintf.c`, case `'s'`) | content; no method | method |
| `sprintf("%.1f")` and other number formats | a double is used as it is; other types get `as.double()` | an error ("use format %s for character objects") | the raw double |
| `glue::glue()` | R code: `as.character()` of each result (`glue.R`) | method if it has one, else content | method |
| `message()`, `warning()`, `stop()` | `.makeMessage()`: `lapply(list(...), as.character)` then `paste()` | method if any | method |
| `format()`, `print()` | S3 generics | method | method |
| `cat()` | C code: a string as stored; a number as `print()` writes it; **no dispatch** (`builtin.c`; help: "That includes factors, which are output as integer vectors") | content | **the raw number**, seven significant digits |
| `writeLines()` | `if (!is.character(text)) stop("can only write character objects")` | content | an error |
| a grid text grob: ggplot2 titles, labels, `geom_text()` | `as.graphicsAnnot()`: `if (is.language(x) \|\| !is.object(x)) x else as.character(x)` | method if any | method |
| knitr inline R | `knit_print(value, inline = TRUE)` (generic), then `as.character()` in the inline hook (`block.R`, `hooks.R`) | `knit_print` method | `knit_print` method |
| `knitr::kable()` | numeric columns (`is.numeric()`): `format()` of the columns through `format.data.frame()`, after `round()` only for columns whose first class is `numeric`, `integer`, `difftime` or `complex` (`table.R`, `utils.R`); other columns as stored | content | the `format()` method; not rounded by kable |
| a data frame printed | `format.data.frame()`, `format()` per column | method | method |
| arithmetic, comparison | `Ops` group generic | needs an `Ops` method or compares strings | numbers, unless an `Ops` method says otherwise |

Three facts decide the design.

1. **No sink tells the value what it is for.** `as.character()` is called
   the same way by `paste()` for a plot title and by `paste()` for a line of
   markdown. A value cannot print markdown for one and plain text for the
   other. Only `knit_print()`, `format(target = )` and weft's own resolver
   know the sink.
2. **A character vector cannot run code in `paste()` or `sprintf()`.** Its
   stored content is what they use. So a character-based value must choose
   its one text when it is made. (The `weft` object relies on exactly this:
   its content is its plain text, so `paste()` gets plain text without a
   method being called. Rule 3.6.3 says `paste()` and `sprintf("%s", )`
   "call `as.character()`"; for a `weft` object they do not, and the result
   is the same only because the content is plain. The wording should be
   fixed; see 7.2.)
3. **A double-based value is right everywhere except `cat()` and
   `writeLines()`.** `cat()` prints the raw number, as it prints a `Date` as
   its day count and a `units` quantity without its unit. `writeLines()`
   stops with an error, which is loud.

---

## 3. Alternatives

### A. A double with a class and methods (recommended)

The value is the number. A class and one attribute say how it prints.
Methods for `as.character()`, `format()`, `print()`, `knit_print()` and
`cli_format()` give its text; methods for `[`, `c()` and the rest keep the
class through vector work; `Ops`, `Math` and `Summary` say what arithmetic
does.

- Works: `paste()`, `paste0()`, `toString()`, `sprintf("%s")`, `glue()`,
  `message()` and friends, `format()`, data-frame printing, `kable()` cells,
  ggplot2 titles and labels, knitr inline R, weft's constructs, `claim()`,
  comparisons, sorting, plotting by value.
- Cannot work: `cat()` prints the raw number. `writeLines()` is an error.
  `sprintf("%.2f")` prints the raw number, which is what the author asked
  for. A `for` loop over the value gives bare numbers (R's `for` reads the
  vector without dispatch, as it does for a `Date`).
- Costs: a class to maintain (about 25 small methods); vctrs methods so that
  dplyr and tidyr keep it; a choice about arithmetic (4.5).

### B. A character vector carrying attributes

This is `weft_text` today, with a number underneath kept in an attribute.

- Works: every sink in section 2, `cat()` and `writeLines()` included,
  because the text is the content.
- Cannot work: the text is fixed when the value is made, so it is one form
  for every sink (plain or markdown, not both). It is not a number:
  comparisons are string comparisons unless an `Ops` method intervenes, and
  every function that drops attributes (`ifelse()`, `unlist()`, `vapply()`,
  `as.vector()`, `merge()`) turns it into a bare string, after which `"10" >
  "9"` is `FALSE` with no error. Arithmetic is an error ("non-numeric
  argument"), which is loud, but a comparison is silent.
- Costs: low to build (the class exists); high in the failures it hides.

### C. The `weft` object widened

Give the `weft` object a number and a TeX form, and let a constructor make
one from a number.

- Works: it already has two forms, plain content and a markdown attribute,
  and its methods for `c()`, `[`, `print()`, `knit_print()` and cli are
  designed and tested.
- Cannot work: the same as B, because it is a character vector. It is also
  the wrong kind of thing: a `weft` object is resolved prose, and its rules
  (3.6.3: "`substr()` keeps the attributes, so its markdown becomes its
  plain text"; `c()` with character vectors as text) are rules for text.
  Adding a number to it would give one class two meanings.
- Costs: low to build, and a muddier `weft` object.

### D. Documentation only

Tell authors: `fmt_*(x, target = "plain")` for plots, `weft()` for sentences
in code, `format(w, target = "markdown")` for markdown sinks, never compare a
formatter's text.

- Works: nothing new to build or maintain.
- Leaves: the string comparison hazard, the digits repeated at every call,
  and three prints of one value.

### E. A formatter function factory

`f <- fmt_with(digits = 1)`, then `f(m)` anywhere, as `scales::label_number()`
does.

- Works: one statement of the digits.
- Leaves: the result is still a `weft_text` (B's problems), and the spec
  travels with a function, not with the value, so a value passed to another
  chunk or a table loses it.

### Prior art looked at

- `units` and `Date`: doubles with a class. `cat()` prints their numbers; R
  users meet this already.
- `pillar::num()`, re-exported as `tibble::num()`: a vctrs double that
  formats itself in tibbles and keeps its options through arithmetic.
- `formattable`: a numeric with a format attribute and an `as.character()`
  method.

### Recommendation

**A.** It is the only shape in which the value stays a number, which is the
failure B and C hide silently. Its one silent gap, `cat()`, prints a correct
number with too many digits: visible, not false. The cost of `writeLines()`
is an error message.

---

## 4. The design

### 4.1 Class and storage

- The class is `weft_val`. Its data is the number the author gave: a
  double, an integer, an `integer64`, a `weft_year`, or a `units` quantity.
  `weft_val` is put in front of the existing classes, so a quantity is
  `c("weft_val", "units")` and stays a `units` object underneath.
- Two attributes: `weft_spec`, the classes and keys (a list, as an
  attribute block would give them), and `weft_shown`, the texts (4.3).
- The name `weft_val` follows `.val` ("a value as itself") and keeps clear
  of the error class `weft_value_error`.

### 4.2 Constructors

One function per number class, mirroring `fmt_*()` without the arguments
that choose a target or collapse a vector:

```r
val_num(x, digits = NULL, sigfig = NULL, unit = NULL, unit_form = NULL, plus = FALSE)
val_pct(x, digits = NULL, sigfig = NULL, unit = NULL, plus = FALSE)
val_sci(x, digits = NULL, sigfig = NULL, unit = NULL, unit_form = NULL)
val_p(x, digits = NULL, label = NULL)
```

Stage 2 adds `val_word()`, `val_count()`, `val_ord()`, `val_no()` (each
`unit_form = NULL`) and `val_date()`.

- A collapse class (`.and`, `.range`, the lists) cannot be a spec: it would
  make `as.character()` of a length-3 value return length 1, and `paste()`
  would recycle wrongly. A text class (`.a`, `.cap`, `.em`, `.strong`) is
  about the sentence the value sits in, not the value. Both are applied at
  the use, as now.
- A project formatter of the number stage is allowed as a spec through
  stage 2's general form, `val_as(x, ".compact", digits = 2)`. Not in
  stage 1.
- `x` given as a `weft_val` takes the new spec in place of the old one: the
  number underneath is formatted again.
- `x` that is character, logical, a factor, a list, a `weft_text` or a
  `weft` object is a `weft_construct_error`: "`val_num()` takes a number or
  a quantity; got a %s. To print text, use `weft()`." A `Date` is refused by
  every constructor but `val_date()`.

### 4.3 The texts are made when the value is made

The constructor calls `apply_formatters()` three times, for the targets
`markdown`, `plain` and `tex`, under `current_config()` (the knit's, or the
working directory's project, as `fmt_*()` uses), and stores the three
character vectors in `weft_shown`, element by element. A class with no TeX
form (3.4.11) stores none, and asking for it is that rule's error.

Why at construction and not at printing:

- **One text, wherever it goes.** The configuration outside a knit is that of
  the working directory (3.6.6). A plot drawn after `setwd()`, or in another
  process, would otherwise read another project's `_weft.yml`. `weft()`
  evaluates at the call for the same kind of reason (ruling 2).
- **The ladder picks once.** A unit ladder picks one rung for the whole
  vector (4.4.23). Made at construction, `v[1]` keeps the rung the column
  picked, so a table column has one unit.
- **The zero check runs once** (4.3.1). Run at printing, it would fire every
  time `as.character()` is called, and ggplot2 or a data-frame print calls it
  more than once.
- **It is cheap to read.** `as.character()` is a subset of a stored vector.

A missing element (`NA`, `NaN`, `Inf`, `-Inf`) is allowed, unlike in
`fmt_*()`, because a data column has them. Its texts are `NA` and it is not
formatted: its text is what R writes for it (`NA`, `"NaN"`, `"Inf"`,
`"-Inf"`), never a formatted number. Where a construct or a formatter meets
it, it is a "no value" failure, as now (1.3.4).

`c()` and `[<-` format the whole result again under the configuration in
force at that call, because a new element can change the ladder's rung or
the vector rule. `[`, `[[`, `rev()`, `rep()`, `sort()`, `unique()` keep the
texts they have.

#### 4.3.1 The printed-as-zero check

`val_num(0.04)` with the default digits prints "0.0". The warned check of
2.6.11 is raised by the constructor, once: in a knit with weft's hooks it is
recorded as a warned check, elsewhere it is a `weft_zero_warning`. `digits`
or `sigfig` given to the constructor silences it, as on `fmt_num()`.
Printing never raises it again. `[<-` and `c()`, which format again, raise
it for the result.

### 4.4 Vector behaviour

| Call | Gives |
|---|---|
| `v[i]`, `v[[i]]`, `rev(v)`, `rep(v, ...)`, `head(v)`, `tail(v)` | a `weft_val` with the same spec and the texts of those elements |
| `sort(v)`, `unique(v)` | a `weft_val`, sorted or deduplicated by number |
| `c(v, w)`, both `weft_val` with the same spec | a `weft_val`, formatted again (4.3) |
| `c(v, 3)`, a `weft_val` then numbers | a `weft_val`; the numbers take its spec |
| `c(3, v)` | a plain number: `c()` dispatches on its first argument only (R's rule); documented |
| `c(v, w)` with different specs, or with a string | `weft_construct_error`: "Values with different formats cannot be combined: %s and %s. Give them one format, or combine the numbers with as.numeric()." |
| `v[i] <- 5` | a `weft_val`, formatted again |
| `v[i] <- w` with another spec, or a string | the error of `c()` |
| `as.numeric(v)`, `as.double(v)`, `as.integer(v)` | the bare number, no attributes |
| `as.list(v)` | a list of length-one `weft_val`s, so `lapply()` keeps them |
| `for (el in v)` | bare numbers (R reads the vector directly); documented |
| `names(v)`, `length(v)`, `is.na(v)`, `is.numeric(v)` | as for the number underneath |

The vctrs methods (`vec_ptype2`, `vec_cast`, `vec_proxy`, `vec_restore`) are
registered when vctrs is loaded, with no dependency on it, as `weft_year`
does (`R/year.R`, decision 43). With them dplyr's `mutate()`, `filter()`,
`arrange()` and `bind_rows()` keep the class. Two `weft_val`s with the same
spec combine to a `weft_val`; with different specs, the error above;
`weft_val` with a plain double gives a plain double.

### 4.5 Arithmetic drops the format

| Operation | Gives |
|---|---|
| `+ - * / ^ %% %/%`, unary minus | the number underneath, operated on: a plain double, or a `units` quantity, or a `weft_year` where that class says so |
| `== != < > <= >=` | logical, on the numbers |
| `Math` (`round()`, `abs()`, `log()` ...) | the plain result |
| `min()`, `max()`, `range()` | a `weft_val` with the same spec |
| `mean()`, `median()` | a `weft_val` with the same spec |
| `sum()`, `prod()`, `any()`, `all()`, `quantile()` | the plain result |

Why: a format is a decision about one quantity. `val_pct(p) * 100` keeping
`.pct` would print "1200%"; `val_num(d, digits = 1) * 1000` (metres to
millimetres) would print a precision nobody chose. A dropped format prints
too many digits, which is visible and not false. The functions that keep it
return a number on the same scale as their input. This is `weft_year`'s
rule widened (decision 43).

`Ops` strips the `weft_val` layer from each side and calls the operator
again, so `units` and `weft_year` arithmetic happen as they would without
weft. When the other side has an `Ops` method of its own (a `units`
quantity, a `Date`), R calls `chooseOpsMethod()` to pick one (R 4.3.0 and
later); `chooseOpsMethod.weft_val()` returns `TRUE`, so weft's method runs
and hands the work to the class underneath. Before R 4.3.0 R warns about
incompatible methods and uses the internal operator, which would drop a
unit silently, so weft needs `Depends: R (>= 4.3.0)` (D16).

### 4.6 A value meeting weft's own formatting

Where weft formats (a construct, an `n` or `sign` governor, `fmt_*()`, a
named value), a `weft_val` gives its number and its spec, and the spec is
put together with what is written at the use:

1. A key written at the use replaces the spec's key of the same name.
2. A number-stage class written at the use that differs from the spec's
   replaces it, and the spec's keys go with it (`digits`, `sigfig`, `unit`,
   `label`, `plus`).
3. Otherwise the spec's class and keys apply, then the stages ii to iv
   written at the use.

| Use | Value | Prints |
|---|---|---|
| `` `r v` `` | `val_num(3.14159, digits = 2)` | 3.14 |
| `` `r v`{.num} `` | the same | 3.14 (same class: the spec's digits) |
| `` `r v`{.num digits=0} `` | the same | 3 |
| `` `r v`{.pct} `` | the same | 314.2% (another class: spec dropped) |
| `` `r k`{.word} `` | `val_num(3)` | three |
| `` `r v`{.and} `` | `val_num(c(1.23, 4.56), digits = 1)` | 1.2 and 4.6 |
| `fmt_num(v)` | `val_num(3.14159, digits = 2)` | 3.14 |
| `[one site \| # sites]{n=v}` | `val_num(1.04, digits = 2)` | "1.04 sites": the arm follows the number as printed |

Digits that come from a spec count as given for the zero rule (1.4.13): the
author chose them when the value was made.

The unwrapping is done in one place, at the top of `formatter_input()`, so
every route takes it. `value_finish()` treats a `weft_val` as formatted
even with no class written (its `has_fmt` test).

### 4.7 What the sinks give

| Sink | Gives |
|---|---|
| `as.character(v)` | plain, names kept, `NA` kept |
| `format(v)`, `format(v, target = "plain")` | plain; `NA` is `"NA"`; base arguments such as `trim`, `justify`, `digits` are accepted and ignored |
| `format(v, target = "markdown")` | markdown |
| `format(v, target = "tex")` | TeX, or 3.4.11's error for a class with no TeX form |
| `format(v, target = "ansi")` | plain (a number has no emphasis) |
| `print(v)` | a header `<weft_val .num digits=1>` then the plain texts, unquoted, names shown |
| `paste()`, `toString()`, `sprintf("%s")`, `glue()`, `message()`, `stop()` | plain |
| `sprintf("%.2f", v)` | the raw number, as asked |
| `cat(v)` | the raw number: R's limit, documented |
| `writeLines(v)` | R's error; documented: write `format(v)` |
| ggplot2 `labs()`, `geom_text(aes(label = ))` | plain |
| a data frame printed, a tibble printed | plain |
| `knitr::kable()` | plain, right-aligned, not rounded by kable |
| `knitr::knit_print(v, inline = TRUE)` | markdown, joined by ", " |
| `knitr::knit_print(v)` | markdown, one element per line |
| `{.val {v}}` in cli, `cli_format(v)` | plain |

Plain is the default everywhere, as for the `weft` object (3.6.3), and for
the same reason: plain text read as markdown is nearly always right, while
markdown in a plot shows its marks. The one case where plain is wrong in a
document is a PDF built with pdflatex, whose input encoding has no Unicode
superscript minus: `1.2 x 10^-4` in plain text stops it, as it does for a
`weft` object. The answer is the same as there: give a markdown sink
`format(v, target = "markdown")`.

---

## 5. Ledger, gate and claims

### 5.1 The ledger records a value only where weft resolves it

| Where the value prints | Ledger |
|---|---|
| inline R in prose, `` `r v` `` | a `bare` entry, as any bare value (7.1.2) |
| a construct, `` `r v`{.num} `` | a `value` entry |
| a named value read by R, `` `v`{.num} `` | a `value` entry, keyed as `` `r v` `` (BN12) |
| a `weft()` string in a knit, `` `v`{.val} `` or `` `r v` `` | entries with context `weft`, at the call, as now |
| a caption the hooks resolve | entries with context `caption` |
| `cat()` of pasted text in a `results: asis` chunk | the chunk's `table` entry, a digest of the text (7.1.1) |
| `knitr::kable()`, gt, flextable | the chunk's `table` entry |
| `paste()` or `glue()` into a plot, a message, a log | none |
| `val_num()` called in a chunk | none |

When a `weft_val` is recorded, its entry is a value's entry: the key is the
expression, the raw value is the number underneath (`ledger_raw()` reads it
through the class), the unit is the quantity's, the text is what weft wrote
there (markdown, or TeX in math), and the sentence is the sentence of the
prose or string around it. Nothing new is invented for the sentence: where
weft has no sentence, it records nothing.

**Rejected: recording when the value is turned into text.** In a knit,
`as.character.weft_val()` could add an entry each time it runs. It would
record the wrong thing in five ways:

1. Values that never reach the document: a check, a `nchar()`, a message to
   the console, a plot built and not printed.
2. Duplicates: ggplot2 and data-frame printing call `as.character()` or
   `format()` more than once.
3. No key: the method sees a value, not the expression that made it, and a
   key by order of calls changes with the plotting code.
4. No sentence: the text around the value is in `paste()`'s other
   arguments, which the method never sees.
5. Caching: a cached chunk does not run the method again, so its entries
   would vanish, and `changes()` would report removals that are not.

**Rejected: recording when the value is made.** Most values are
intermediate; a column of 10,000 is not 10,000 statements in the document;
there is no sentence.

**What the author does instead.** To have a plot title in the ledger, write
it with `weft()`: `labs(title = weft("Mean depth `d`{.val} m"))`. The value's
spec prints it; weft records it with the title as its sentence. The ledger
then holds what the document says, as it does now.

### 5.2 The gate

No change. The gate counts constructs, values and `claim()` calls (6.3.1).
A `val_*()` call in chunk code is code: removing one removes no printed
value (the prose that prints it still holds its inline R, which is counted).
`` `r val_num(x, digits = 1)` `` in prose is a bare value and is counted as
one.

One hole is closed in stage 2: `` `r val_num(3.2)` `` is a number typed in
the source, but the rule `literal-value` (5.6.1) does not see it, because a
call is not a constant (`lit_node()` in `R/lint-code.R`). The same hole
exists for `` `r fmt_num(3.2)` `` today. The rule should look through the
first argument of `val_*()` and `fmt_*()`, as `value-format` (5.6.4) looks
through `claim()`.

### 5.3 Claims

`claim(v, . > 9)` compares numbers, because `Ops` gives numbers: it passes
for `val_num(10)`, where `claim(fmt_num(10), . > 9)` fails. `claim()` returns
its value unchanged, so `` `r claim(v, . < 50)` `` prints with the spec. The
failure message shows the number underneath (`claim_value_text()` gains
`weft_val` beside `units`), because the check judged the number, not the
text.

### 5.4 Named values and the filter

A `weft_val` is never published to the filter. `weft_values_write()` and
automatic publishing refuse it with a new refusal, E46: "is a self-formatting
value; named values carry no format. Publish the number with as.numeric() and
write its classes where it is used (rule 3.8.4)." This follows `units`
(E44). Publishing the number alone would let the filter print it with other
digits than R would, silently; publishing the spec would need the filter, the
values-file format and the Python and Julia readers to learn it.

Under knitr a name reads R (ruling 3), so `` `v`{.num} `` and
`` `v`{.val} `` never need publishing unless the name is used above its
value.

---

## 6. Interactions

**`target = "tex"` and math.** A construct holding a `weft_val` in math
writes TeX, as any construct (1.4.23). A bare `` `r v` `` in math or raw
LaTeX writes the stored TeX form, wrapped in `\ensuremath{...}` in raw
LaTeX, because its own format is a weft format and its markdown is wrong
there. This is a new exception to "a bare value prints as stock prints it"
(1.4.23); it applies only to a `weft_val`. Outside weft's hooks (a plain
knit), `knit_print()` cannot see math and writes markdown.

**Units.** `val_num(u(1500, m), unit = "km")` prints "1.5 km" (with a
no-break space). The quantity stays a quantity underneath: `v + u(1, km)`
is a `units` quantity. `units::drop_units(v)` removes the unit and leaves the
spec, so the value prints without a unit; this is the units package's
method, documented. A ladder picks once at construction (4.3).

**The number classes.** Section 4.6. `.plus` is a spec key (`plus = TRUE`).
`.val` on a `weft_val` prints its own format (D13, for Robin), instead of
the value error a refused record gives under 1.12.2.

**Inline R in knitr.** `knit_print.weft_val()` writes the markdown, so a
document without weft's hooks prints the value right in prose. Under weft's
hooks the resolver formats it itself, which is how it can write TeX in math.

**Quarto's named values.** Section 5.4.

**The `weft` object.** Inside `weft()` markup a `weft_val` prints as in
prose: markdown for the object's markdown form, read by PL for its plain
form, which is the value's plain text. `c(w, v)` of a `weft` object and a
`weft_val` takes the value's two forms as text (stage 2; today it would be
the construct error of 3.6.3).

**Phrase functions.** `ci()`, `pm()`, `clamp()`, `about()` and `of_n()` use
the number underneath and print with their own arguments; the spec does not
apply (D12).

**Lints.** `value-format` (5.6.4) needs no change: `val_*()` is not in its
list, and a bare `val_*()` in math now writes TeX. `literal-value`, 5.2.

**Python and Julia.** Not in this package. A twin is possible and small.

- Python: `class Val(float)` with `__str__` and `__format__` returning the
  plain text, and `__repr__` showing the spec. f-strings call
  `__format__(spec)`: with an empty spec it gives the plain text, with a
  spec (`f"{v:.2f}"`) it formats the float, as `sprintf("%.2f")` does in R.
  `str()`, `print()` and `"%s" %` call `__str__`. Arithmetic on a `float`
  subclass returns a `float`, so the format drops as in 4.5 with no code.
  The text comes from weft's formatters, which the Python module reaches
  only under a weft knit, so the class is useful only there. `put()` must
  test for `Val` before `float` and refuse it, as E46.
- Julia: `struct Val{T<:Real} <: Real; x::T; spec; shown; end` with
  `Base.print(io, v)` and `Base.show(io, v)` giving the plain text, so
  `"$(v)"` uses it; `Base.promote_rule` and `Base.convert` to `T`, so
  arithmetic returns a plain `T`. `@put` refuses it.
- Ledger and gate semantics are the same: recorded only where the markup
  holds the value.

Recommendation: build the R class first; a Python twin when a Python
document needs it; Julia not planned.

---

## 7. Rules for the spec

### 7.1 A new section, 3.11 Self-formatting values

**3.11.1** `val_num()`, `val_pct()`, `val_sci()` and `val_p()` return a
**self-formatting value**: the number given, with the class `weft_val` put
before its classes and a format that prints it as the function of the same
name in `fmt_*()` would. They take the arguments of that function except
`target` and the collapse arguments: `val_num(x, digits = NULL, sigfig =
NULL, unit = NULL, unit_form = NULL, plus = FALSE)`, `val_pct(x, digits =
NULL, sigfig = NULL, unit = NULL, plus = FALSE)`, `val_sci(x, digits = NULL,
sigfig = NULL, unit = NULL, unit_form = NULL)`, `val_p(x, digits = NULL,
label = NULL)`. They are exported and attached (2.1.8), and visible to
`weft()` markup (3.6.2). An argument that `fmt_*()` refuses is refused with
the same error.

**3.11.2** `x` is a double, an integer, an `integer64`, a `weft_year`, a
`units` quantity, or a self-formatting value, whose number is then given the
new format. Anything else is a `weft_construct_error`: "`%s()` takes a number
or a quantity; got a %s. To print text, use `weft()`." An element that is
`NA`, `NaN`, `Inf` or `-Inf` is kept and is not formatted: its text is
`NA`, `"NaN"`, `"Inf"` or `"-Inf"`.

**3.11.3** The texts are made when the value is made, under the
configuration `fmt_*()` would use there (3.6.6): the markdown and plain
forms, and the TeX form for a class that has one (3.4.11). `[`, `[[`,
`rev()`, `rep()`, `sort()`, `unique()`, `head()` and `tail()` keep them. `c()`
and `[<-` make them again for the whole result, under the configuration in
force at that call. A ladder (4.4.23) picks one rung for the vector the
texts are made for.

**3.11.4** The check of 2.6.11 runs when the texts are made, never when they
are printed: a value made with the default digits that prints a number that
is not zero as zero records one warned check, or outside a knit signals one
`weft_zero_warning`. `digits` or `sigfig` given to the constructor silences
it.

**3.11.5** What a self-formatting value gives:

| Call | Gives |
|---|---|
| `as.character(v)` | plain (1.4.24); names kept; `NA` for an `NA` element |
| `format(v)`, `format(v, target = "plain")` | plain; `NA` is `"NA"`; other arguments are ignored |
| `format(v, target = "markdown")`, `"tex"`, `"ansi"` | markdown; TeX (3.4.11's error for a class with none); plain |
| `format(v, target = other)` | `weft_construct_error`: "`target` must be \"plain\", \"markdown\", \"tex\" or \"ansi\"; got %s." |
| `print(v)` | one line `<weft_val CLASS KEY=VALUE ...>`, then the plain texts unquoted, with names; returns `v` invisibly; a length-0 value prints `<weft_val[0] CLASS ...>` |
| `knitr::knit_print(v, inline = TRUE)` | the markdown elements joined by ", " |
| `knitr::knit_print(v)` | the markdown elements, one per line |
| `cli_format(v)` | plain |

`paste()`, `toString()`, `sprintf("%s", )`, `glue::glue()`, `message()`,
`warning()`, `stop()`, a ggplot2 label, a printed data frame and
`knitr::kable()` give the plain text. `cat()` prints the number underneath,
as it prints a `Date`, and `writeLines()` refuses the value: give them
`format(v)`. A `for` loop over the value reads the numbers.

**3.11.6** Vector operations are those of the table in
`dev/design-self-formatting.md` section 4.4. `c()` and `[<-` of values whose
formats differ, or with anything that is not a number, are a
`weft_construct_error`: "Values with different formats cannot be combined:
%s and %s. Give them one format, or combine the numbers with as.numeric()."
Two formats are the same when their class and their keys, defaults filled
in, are equal. When vctrs is loaded, `vec_c()` and the dplyr verbs follow the
same rules, and a value combined with a plain number gives a plain number.

**3.11.7** Arithmetic, `Math` and every `Summary` function except `min()`,
`max()` and `range()` give the result for the number underneath, without the
format: a double, or what the class underneath gives (`units`, `weft_year`).
`min()`, `max()`, `range()`, `mean()` and `median()` keep the format. A
comparison gives a logical. With another classed operand R's
`chooseOpsMethod()` chooses weft's method, which hands the operation to the
classes underneath.

**3.11.8** Where weft formats a self-formatting value (a construct, a
governor, a named value R reads, a `fmt_*()` call) its format is put
together with what is written there. A key written there replaces the
format's key of that name. A number-stage class written there that differs
from the format's replaces it, with the format's keys. Otherwise the
format's class and keys apply, and the stages ii to iv written there act on
its text. Digits that come from the format count as given for 1.4.13. A bare
value that holds a self-formatting value prints its markdown, and in math or
raw LaTeX its TeX, which in raw LaTeX is wrapped in `\ensuremath{...}`. `.val`
on it prints its own format.

**3.11.9** The ledger records a self-formatting value where it records any
value: inline R, a construct, a named value R reads, a caption, a `weft()`
string (7.1.1, 7.1.2). Its raw value is the number underneath and its unit
the quantity's. Making it, converting it to text and printing it record
nothing, and text built from it outside weft's constructs reaches the ledger
only as the chunk's `table` entry (7.1.1).

**3.11.10** A self-formatting value is not a named value's record: it is
refused (3.8.4, E46). A phrase function uses its number and ignores its
format. A `claim()` judges its number, and a failure shows the number.

**3.11.11** Stage 2: `val_word()`, `val_count()`, `val_ord()`, `val_no()`,
`val_date()` and `val_as(x, class, ...)` for a project formatter of the
number stage. A collapse class or a text class is never a format.

### 7.2 Amendments elsewhere

- **1.4.23**, the bullet on bare values: add "except a self-formatting value
  (3.11.8)".
- **1.12.2**: add "A self-formatting value prints its own format under `.val`
  where R reads the name (3.11.8)" (D13).
- **3.6.3**, the sentence on `paste()`: "`paste()` and `sprintf("%s", )` use
  the plain text, which is the object's content; `toString()`, `message()` and
  `glue::glue()` call `as.character()`, which gives the same."
- **3.8.4**, the table: a row "a self-formatting value | refused: named values
  carry no format".
- **5.6.1**: "A value whose outermost call is a `val_*()` or `fmt_*()` of weft
  is read by its first argument" (stage 2).
- **7.1.1**: a sentence pointing to 3.11.9.
- **Part 2, section 13, Functions**: the reasons of D1, D3, D4, D5 and D8, in
  two or three sentences each.

---

## 8. Test plan

For a test-writer who reads this note, the spec and the exported help, and
not `R/`. Every test runs outside a knit unless it says "in a knit". Knit
tests use the existing render helpers. Expected strings are written with
`\u2212` for the minus sign and `\u00a0` for the no-break space, as the
existing tests write them.

### 8.1 Construction

1. `val_num(3.14159)`: `class(v)[1]` is `"weft_val"`, `is.double(v)` is
   `TRUE`, and `as.numeric(v)` is `3.14159` exactly, with no attributes.
2. `val_num(3.14159, digits = 2)`: `as.character()` is `"3.14"`.
3. `val_num(1234567.89)`: `as.character()` equals
   `as.character(fmt_num(1234567.89, target = "plain"))`.
4. For each of `val_num`, `val_pct`, `val_sci`, `val_p` and a set of inputs
   (0.123, -0.5, 1e-4, 2^53, 0, a vector), `format(v, target = "markdown")`
   equals `as.character(fmt_X(x, ...))`, `format(v)` equals the plain call, and
   `format(v, target = "tex")` equals the TeX call.
5. `val_num(c(a = 1.5, b = 2.25))` keeps names in `as.character()` and
   `format()`.
6. `val_num(numeric())` has length 0; `as.character()` is `character(0)`;
   `print()` writes `<weft_val[0] .num>`.
7. `val_num(c(1.5, NA, Inf, NaN))` does not error; `as.character()` is
   `c("1.5", NA, "Inf", "NaN")`; `format()` is `c("1.5", "NA", "Inf", "NaN")`.
8. `val_num(5L)` (integer), `val_num(bit64::as.integer64("9007199254740993"))`
   (skip without bit64) print every digit.
9. `val_num(u(5, m))` prints `"5\u00a0m"` plain and keeps
   `inherits(v, "units")`.
10. `val_num(u(1500, m), unit = "km")` prints `"1.5\u00a0km"`.
11. `val_num(u(c(5, 5000), m), unit = "m|km")`: the rung is picked once for
    the vector; `v[1]` prints in that same rung.
12. Errors, class `weft_construct_error`: `val_num("3")`, `val_num(TRUE)`,
    `val_num(factor("a"))`, `val_num(list(1))`, `val_num(fmt_num(3))`,
    `val_num(weft("x"))`, `val_num(Sys.Date())`; the message names the
    function and the class given.
13. `val_num(1, digits = 1, sigfig = 2)` gives the error `fmt_num()` gives
    for the same arguments; so do `plus = NA` and a bad `unit_form`.
14. `val_num(val_pct(0.5))` is a `.num` value whose number is 0.5.
15. Configuration: in a temporary project whose `_weft.yml` sets
    `decimal_mark: ","` (and `big_mark: "."`), a value made there prints
    `"1,5"`; after `setwd()` to a folder with no `_weft.yml` the same object
    still prints `"1,5"`.

### 8.2 The zero check

16. `val_num(0.04)` signals one `weft_zero_warning` and prints `"0.0"`.
17. `val_num(0.04, digits = 1)` and `val_num(0.04, sigfig = 1)` signal none.
18. `as.character()`, `format()`, `paste()` and `print()` of the value from
    test 16 signal no warning.
19. `c(val_num(1), 0.04)` signals one warning.
20. In a knit with weft's hooks, a chunk with `v <- val_num(0.04)` records one
    warned check of kind "printed as zero" and the render succeeds.

### 8.3 Vector behaviour

21. `v[2]`, `v[[2]]`, `rev(v)`, `rep(v, 2)`, `head(v, 1)`, `sort(v)`,
    `unique(v)` are `weft_val` with the same spec, and their texts are the
    right subset or order.
22. `c(v, w)` with the same spec is a `weft_val`; with different digits it is
    the construct error of 3.11.6, naming both formats.
23. `c(v, 3)` is a `weft_val` whose last text is the spec's print of 3.
24. `c(3, v)` is a plain double (pins R's dispatch on the first argument).
25. `c(v, "a")` is the construct error.
26. `v[2] <- 7.25` keeps the class and the new text follows the spec;
    `v[2] <- "x"` is the construct error.
27. `as.list(v)` is a list of `weft_val`; `lapply(v, as.character)` gives
    their texts.
28. `for (el in v) cls <- class(el)` leaves `cls == "numeric"` (pins the
    documented limit).
29. `is.numeric(v)` is `TRUE`; `length()`, `names()`, `is.na()` act on the
    numbers.

### 8.4 Arithmetic

30. `v + 1`, `v * 2`, `-v`, `v / v`, `v^2` are plain doubles with no
    `weft_spec` attribute.
31. `v > 2`, `v == v` are logical vectors.
32. `round(v)`, `abs(v)`, `log(v)` are plain.
33. `max(v)`, `min(v)`, `range(v)`, `mean(v)`, `median(v)` are `weft_val`
    with the spec; `sum(v)` and `prod(v)` are plain.
34. `val_num(u(5, m)) + u(1, m)` and `u(1, m) + val_num(u(5, m))` are
    `units` quantities of 6 m, not `weft_val`, and signal no warning.
35. `val_num(u(5, m)) * 2` is a `units` quantity of 10 m.
36. A `weft_year` inside: with `y` a `year` entry read from a dictionary
    (`read_dict()` of a small YAML file), `val_num(y) + 1L` is a `weft_year`.
37. `claim(val_num(10), . > 9)` returns the value and does not fail;
    `claim(val_num(10), . < 9)` fails with `weft_claim_failed` and the
    message holds `10`, not `"10"` and not `structure(`.

### 8.5 Sinks

38. `paste("a", v)`, `paste0(v, "!")`, `toString(v)`, `sprintf("%s", v)` use
    the plain text.
39. `sprintf("%.3f", val_num(3.14159, digits = 1))` is `"3.142"`.
40. `glue::glue("{v} m")` uses the plain text, and recycles a vector value.
41. `conditionMessage(tryCatch(message(v), message = identity))` and the same
    for `warning()` and `stop()` hold the plain text.
42. `capture.output(cat(val_num(3.14159, digits = 1)))` is `"3.14159"` (pins
    the limit).
43. `writeLines(v)` errors with "can only write character objects" (pins the
    limit); `writeLines(format(v))` writes the plain text.
44. `grDevices::as.graphicsAnnot(v)` is the plain text (the route of every
    grid text).
45. With ggplot2 (skip without), a plot with `labs(title = v)` built by
    `ggplot2::ggplotGrob()` holds a title grob whose label is the plain text;
    `geom_text(aes(label = lab))` with `lab` a `weft_val` column draws the
    plain texts (inspect `layer_grob()`).
46. `format(data.frame(x = v))$x` is the plain text; `print()` of the data
    frame shows it.
47. `knitr::kable(data.frame(x = v), format = "pipe")` shows the plain texts,
    right-aligned, and kable's `digits` does not change them.
48. `format(v, target = "ansi")` equals `format(v)`.
49. `format(v, target = "html")` is the construct error of 3.11.5.
50. `format(val_word(3), target = "tex")` (stage 2) is 3.4.11's error.
51. `print(val_num(c(a = 1.25), digits = 1))` writes the header line naming
    `.num` and `digits=1`, then the text with its name.
52. `cli::format_inline("{v}")` and `cli::format_inline("{.val {v}}")` hold
    the plain text.
53. `knitr::knit_print(v, inline = TRUE)` is markdown joined by ", "; with
    `val_sci(1e-4)` it is the markdown form, not the plain one.

### 8.6 Meeting weft's formatters

54. `fmt_num(val_num(3.14159, digits = 2))` is `"3.14"`; `fmt_num(...,
    digits = 0)` is `"3"`; `fmt_pct(val_num(0.5, digits = 3))` is `"50%"`.
55. `fmt_word(val_num(3))` is `"three"`; `fmt_and(val_num(c(1.23, 4.56),
    digits = 1))` is `"1.2 and 4.6"`.
56. `fmt_num(val_num(0.04, digits = 1))` signals no zero warning.
57. `weft("`r v`")`, `weft("`r v`{.num}")`, `weft("`v`{.num}")` and
    `weft("`v`{.val}")` give the spec's text in both forms; `weft("`r v`{.pct}")`
    gives `.pct` with the default digits. (The `.val` case depends on D13.)
58. `weft("[one site | # sites]{n=v}")` with `v = val_num(1.04, digits = 2)`
    gives `"1.04 sites"`; with `val_num(1.04)` it gives `"1.0 sites"`, as a plain 1.04 does
    (corrected 27 Nov: the default digits print 1.0).
59. `weft("`r claim(v, . < 50)`")` with `v = val_num(61)` stops with
    `weft_claim_failed`.
60. `ci(val_num(2.123), 1, 3)` equals `ci(2.123, 1, 3)`.

### 8.7 In a knit

61. A document with `` `r v` `` in prose, `v <- val_num(3.14159, digits = 2)`
    in a chunk: the output holds `3.14`; the ledger has a `bare` entry with
    text `3.14` and raw `3.14159`.
62. The same document without `weft_setup()` (plain knitr) prints `3.14`.
63. `` `r v`{.num digits=3} ``: a `value` entry with text `3.142`.
64. `$x = `r v`$` with `v = val_num(-1234.5)`: the output holds
    `-1{,}234.5`; the ledger entry has context `math`.
65. A `{=latex}` raw block holding `` `r v` ``: the output holds
    `\ensuremath{...}` around the TeX.
66. `val_sci(1e-4)` bare in prose writes the markdown form (superscript
    markers), not the plain one.
67. A chunk that pastes `v` into `cat()` with `results: asis`: the ledger
    has that chunk's `table` entry and no value entry for `v`.
68. A chunk that calls `val_num()` and draws a plot titled with
    `paste("Mean", v)`: no ledger entry names `v`.
69. A chunk whose plot title is ``weft("Mean `r v`")``: one entry, context
    `weft`, sentence `Mean 3.14`.
70. A cached chunk (`cache: true`) that makes `v`, rendered twice: the second
    ledger equals the first.
71. A document whose front matter sets `decimal_mark: ","`: a value made in a
    chunk prints with the comma in prose, in a `weft()` string and through
    `paste()`.
72. Gate: a commit that deletes a chunk line `v <- val_num(x)` and leaves the
    prose `` `r v` `` needs no trailer; one that deletes the prose
    `` `r v` `` needs `Weft-Removed: 1`.

### 8.8 vctrs and dplyr (skip without them)

73. `vctrs::vec_c(v, v)` is a `weft_val`; `vctrs::vec_c(v, 1)` is a double;
    `vctrs::vec_c(v, w)` with different specs errors.
74. `dplyr::mutate(df, y = val_num(x, digits = 1))` then `filter()` and
    `arrange()` keep the class and the texts follow the rows.
75. `dplyr::bind_rows()` of two frames with same-spec columns keeps the
    class; with different specs, an error.
76. `tibble::tibble(x = v)` prints the plain texts (stage 2, with the pillar
    method).

### 8.9 Named values

77. `weft_values_write(path, d = val_num(1))` writes an error record whose
    message names E46's text; using `` `d`{.num} `` under the filter reports
    it.
78. Automatic publishing of a `weft_val` used above its value reports E46 at
    the use.

### 8.10 Static side

79. `lints()` on a document with `` `r val_num(3.2)` `` reports
    `literal-value` (stage 2), and with `` `r val_num(x)` `` does not.
80. `lints()` on `` `r fmt_num(3.2)` `` reports `literal-value` (stage 2).

### 8.11 Edge cases to keep in view

- A value whose texts were made under one `_weft.yml`, combined by `c()` after
  the file changed, prints the whole result under the new file (3.11.3).
- `units::drop_units(v)`: the unit goes, the spec stays, the value prints
  without a unit.
- `val_num(v)` where `v` is a `weft_val`: the new spec only, no trace of the
  old.
- A length-one value with a name: `print()` shows the name.
- `NA` in a governor (`{n=v}` with `v = val_num(NA)`): a "no value" failure.
- Very long vectors: `val_num(runif(1e5))` should take well under a second
  (soft; record the time, do not assert a bound).

---

## 9. Size and stages

| File | Change | Lines (rough) |
|---|---|---|
| `R/val.R` (new) | constructors, the class methods, `chooseOpsMethod`, vctrs registration | 350 |
| `R/format.R` | unwrap and merge in `formatter_input()`; `has_fmt` in `value_finish()` is in `R/resolve.R` | 40 |
| `R/resolve.R` | the bare value of a `weft_val` (markdown or TeX by position); `.val` | 30 |
| `R/ledger.R` | `ledger_raw()`, `ledger_unit()` through the class | 10 |
| `R/claim.R` | `claim_value_text()` | 5 |
| `R/values.R` | E46 | 10 |
| `R/weft.R` | `inline_function_names()` gains `^val_` | 3 |
| `R/year.R` | `.onLoad` registers the new vctrs methods | 3 |
| `DESCRIPTION` | `Depends: R (>= 4.3.0)` | 1 |
| `NAMESPACE`, `man/` | roxygen | generated |
| tests | about 80 cases above, in three or four files | 800 |
| spec | section 3.11 and the amendments, rationale | 150 |
| `vignettes/strings.Rmd` | a section "Values that format themselves"; the sink table gains a column | 80 |
| `NEWS.md`, `inst/agent/references/syntax.md` and its `skills/weft` copy | a paragraph each | 30 |

About 450 lines of R and 800 of tests.

**Split it in two stages.**

- **Stage 1**: `val_num()`, `val_pct()`, `val_sci()`, `val_p()`; the class and
  every method of 4.3 to 4.7; vctrs registration; the merge rule; bare values
  in prose and math; ledger, claim and E46; the spec section and the article.
  Tests 1 to 75 and 77, 78.
- **Stage 2**: `val_word()`, `val_count()`, `val_ord()`, `val_no()`,
  `val_date()`, `val_as()`; the pillar method for tibbles and a ggplot2
  `scale_type()` method (so a `weft_val` aesthetic picks a continuous scale
  without a message); `c()` of a `weft` object and a `weft_val`; the
  `literal-value` look-through for `val_*()` and `fmt_*()`. Tests 50, 76, 79,
  80.
- **Later, only if asked**: the Python twin; a Julia twin.

Stage 1 is one cycle of `dev/current-state.md`: tests, implementation,
review. It touches the formatter core (`formatter_input()`), so the whole
suite must run after it.

---

## 10. Decisions made here

Each with the alternatives and the reason. Those marked **(Robin)** are
repeated in section 11.

- **D1. Storage: the number, with a class.** Alternatives: a character
  vector with attributes (B); the `weft` object widened (C). Reason: only the
  number stays right when attributes are lost; a lost character class turns
  comparisons into silent string comparisons. Cost: `cat()` prints the raw
  number.
- **D2. Base S3 with vctrs methods registered on load.** Alternative:
  `vctrs::new_vctr()` with vctrs in Imports. Reason: the `weft_year`
  precedent (decision 43); vctrs stays in Suggests; `new_vctr()` would make
  arithmetic an error by default and `as.character()` a `vec_cast()`, both of
  which must be overridden anyway.
- **D3. Texts made at construction.** Alternative: format at printing.
  Reason: section 4.3 (one text wherever it goes, one ladder pick, one zero
  check). Cost: three formatter runs per construction, and `c()` formats
  again.
- **D4. Plain is the default text everywhere. (Robin)** Alternatives:
  markdown inside a knit and plain outside; markdown always. Reason: a value
  cannot see its sink (section 2); a text that changes with whether a knit
  is running would print differently in the console and the document;
  plain read as markdown is nearly always right, markdown in a plot is
  visibly wrong. Cost: a pdflatex PDF cannot take a plain Unicode exponent
  in a `kable()` cell or `cat()` text; the author writes
  `format(v, target = "markdown")`.
- **D5. Arithmetic drops the format. (Robin)** Alternatives: keep it
  (`pillar::num()`, `units`); make arithmetic an error (vctrs' default).
  Reason: a kept format prints a precision or a class nobody chose for the
  new number (`val_pct(p) * 100`); an error would block ordinary code. Kept
  by `min()`, `max()`, `range()`, `mean()`, `median()`, which stay on the
  input's scale.
- **D6. Different formats do not combine.** Alternatives: drop to plain
  numbers; take the first value's format. Reason: dropping silently loses a
  decision; taking the first prints the second value with digits chosen for
  another. The error names both.
- **D7. The merge rule of 4.6.** Alternatives: the use always wins
  (`` `r v`{.num} `` would ignore the spec's digits); the spec always wins
  (a written key would be ignored). Reason: what is written at the use is the
  later and nearer decision; a written class that matches the spec's says
  nothing about digits.
- **D8. The ledger records only where weft resolves.** Alternatives: at
  conversion to text; at construction. Reason: section 5.1, five ways each
  would record what the document does not say.
- **D9. A bare `weft_val` in math writes TeX.** Alternative: keep 1.4.23's
  "a bare value prints as stock" and write markdown. Reason: the format is
  weft's, and weft knows the position; markdown in math is a known error the
  lint `value-format` exists to catch.
- **D10. Named values refuse it (E46).** Alternatives: publish the number;
  publish number and format. Reason: section 5.4.
- **D11. Missing elements are kept.** Alternative: `fmt_*()`'s "no value"
  error at construction. Reason: data columns have `NA`; the failure comes
  where weft prints the element in prose, as now.
- **D12. Phrase functions use the number.** Alternative: a value error.
  Reason: they have their own `digits` and print several numbers together;
  ignoring the spec prints a consistent phrase, not a false one.
- **D13. `.val` prints the value's own format. (Robin)** Alternative: the
  value error that 1.12.2 gives a refused record. Reason: `.val` means "as
  itself", and this value's self is its format; the parity with the filter
  that 1.12.2 protects cannot be broken, because the filter never receives
  the value (D10).
- **D14. A collapse or text class is never a format.** Reason: 4.2.
- **D15. The constructor names. (Robin)** See 11.
- **D16. `Depends: R (>= 4.3.0)`.** Alternative: no `chooseOpsMethod()`,
  accepting that `u(1, m) + val_num(u(5, m))` warns and loses the unit on
  older R. Reason: R 4.3.0 is from April 2023; this machine has 4.4 and 4.5;
  the package has no users.

---

## 11. For Robin

1. **Build it, or document instead?** Recommended: build stage 1. The string
   comparison of a formatter's text (`fmt_num(10) > 9` is `FALSE`) and the
   three prints of one number are real, and documentation cannot fix the
   first.
2. **The names.** The plan wrote `num()`. `tibble::num()` (from pillar)
   already exists, and weft attaches its functions last on the search path
   (decision 11), so with the tidyverse loaded `num()` in a document would be
   tibble's. Options: `val_num()` and siblings (recommended: parallel to
   `fmt_num()`, and `val` matches `.val`); one constructor
   `val(x, ".num", digits = 1)` (fewer names; the class as a string is easy to
   mistype and no editor completes it); `num()` with the clash documented.
3. **Plain text by default (D4).** Recommended: plain, as for `weft()`
   objects. The alternative, markdown inside a knit, makes one line of code
   print differently in the console and in the document.
4. **Arithmetic drops the format (D5).** Recommended: drop, keeping it only
   for `min()`, `max()`, `range()`, `mean()` and `median()`. `pillar::num()`
   keeps it through all arithmetic; that is the main alternative.
5. **`.val` on a self-formatting value (D13).** Recommended: its own format.
   It bends rule 1.12.2, which says R prints `.val` from the value's record.
6. **`Depends: R (>= 4.3.0)` (D16).** Recommended: yes. Small, but visible in
   `DESCRIPTION`.
7. **Twins.** Recommended: no Python or Julia twin now; a Python `Val(float)`
   when a Python document asks for it.

## Rulings (27 Nov 2026)

- Robin: the constructors are the `val_*()` family (`val_num()`, `val_pct()`, `val_sci()`,
  `val_p()`; more in stage 2). Alternatives refused: `num_val()` and kin; `fmt_*(keep = TRUE)`,
  one function returning two types.
- Robin: DESCRIPTION gains `Depends: R (>= 4.3.0)`, for `chooseOpsMethod()`. Alternative refused:
  warn on older R.
- Orchestrator, under Robin's delegation: build stage 1 now; plain text by default at every sink
  (as `weft()` objects); arithmetic drops the format, except `min()`, `max()`, `range()`, `mean()`
  and `median()`; `.val` on such a value prints its own format (the bend to 1.12.2 is stated in
  the rule); no Python or Julia twin for now.
