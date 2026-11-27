# Self-formatting values

`val_num()`, `val_pct()`, `val_sci()` and `val_p()` return a
**self-formatting value** (rule 3.12): the number given, with the class
`weft_val` put before its own classes, and a format that prints it as
the function of the same name in
[`fmt_num()`](https://vorpalvorpal.github.io/weft/reference/fmt.md) and
its siblings would. The value stays a number: it compares, sorts and
plots as one. Only the way it turns into text changes, so one statement
of the digits serves every sink: prose, a
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md)
string, [`paste()`](https://rdrr.io/r/base/paste.html),
[`glue::glue()`](https://glue.tidyverse.org/reference/glue.html), a plot
title, a table and the console.

## Usage

``` r
val_num(
  x,
  digits = NULL,
  sigfig = NULL,
  unit = NULL,
  unit_form = NULL,
  plus = FALSE
)

val_pct(x, digits = NULL, sigfig = NULL, unit = NULL, plus = FALSE)

val_sci(x, digits = NULL, sigfig = NULL, unit = NULL, unit_form = NULL)

val_p(x, digits = NULL, label = NULL)

# S3 method for class 'weft_val'
as.character(x, ...)

# S3 method for class 'weft_val'
format(x, target = "plain", ...)

# S3 method for class 'weft_val'
print(x, ...)

# S3 method for class 'weft_val'
knit_print(x, options = NULL, inline = FALSE, ...)

# S3 method for class 'weft_val'
cli_format(x, style = NULL, ...)

# S3 method for class 'weft_val'
as.data.frame(
  x,
  row.names = NULL,
  optional = FALSE,
  ...,
  nm = deparse1(substitute(x))
)

# S3 method for class 'weft_val'
x[...]

# S3 method for class 'weft_val'
x[[...]]

# S3 method for class 'weft_val'
x[...] <- value

# S3 method for class 'weft_val'
x[[...]] <- value

# S3 method for class 'weft_val'
c(...)

# S3 method for class 'weft_val'
rep(x, ...)

# S3 method for class 'weft_val'
unique(x, incomparables = FALSE, ...)

# S3 method for class 'weft_val'
xtfrm(x)

# S3 method for class 'weft_val'
as.list(x, ...)

# S3 method for class 'weft_val'
Ops(e1, e2)

# S3 method for class 'weft_val'
chooseOpsMethod(x, y, mx, my, cl, reverse)

# S3 method for class 'weft_val'
Math(x, ...)

# S3 method for class 'weft_val'
Summary(..., na.rm = FALSE)

# S3 method for class 'weft_val'
mean(x, ...)

# S3 method for class 'weft_val'
median(x, na.rm = FALSE, ...)

# S3 method for class 'weft_val'
drop_units(x)
```

## Arguments

- x:

  A number, a quantity, or a self-formatting value.

- digits, sigfig, unit, unit_form, plus, label:

  As for
  [`fmt_num()`](https://vorpalvorpal.github.io/weft/reference/fmt.md),
  [`fmt_pct()`](https://vorpalvorpal.github.io/weft/reference/fmt.md),
  [`fmt_sci()`](https://vorpalvorpal.github.io/weft/reference/fmt.md)
  and [`fmt_p()`](https://vorpalvorpal.github.io/weft/reference/fmt.md).

- ...:

  Passed on, or ignored where the text says so.

- target:

  `"plain"` (the default), `"markdown"`, `"tex"`, `"ansi"` (which is
  plain), `"html"` or `"marquee"`. The last two give what the matching
  `fmt_*()` call gives for the same number and format; the html form has
  class `c("html", "character")` and the attribute `html = TRUE`.

- options:

  Passed by knitr.

- inline:

  For `knit_print()`: `TRUE` for inline R.

- style:

  Not used (for `cli_format()`).

- row.names, optional, nm:

  As for [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html).

- value:

  The new elements: numbers, or values of the same format.

- incomparables:

  As for [`unique()`](https://rdrr.io/r/base/unique.html).

- e1, e2:

  Operands.

- y, mx, my, cl, reverse:

  As for
  [`chooseOpsMethod()`](https://rdrr.io/r/base/chooseOpsMethod.html).

- na.rm:

  As for `Summary` and
  [`median()`](https://rdrr.io/r/stats/median.html).

## Value

A self-formatting value: the number, of class `weft_val` and its own
classes.

## Details

The constructors take the arguments of the formatter of the same name,
except `target` and the collapse arguments, and refuse what it refuses
with the same error, naming the function called. `x` is a double, an
integer, an `integer64`, a
[weft_year](https://vorpalvorpal.github.io/weft/reference/weft_year.md),
a `units` quantity (see
[`u()`](https://vorpalvorpal.github.io/weft/reference/u.md)) or a
self-formatting value, whose number is then given the new format;
anything else is a `weft_construct_error`. An element that is `NA`,
`NaN`, `Inf` or `-Inf` is kept and not formatted: its text is `NA`,
`"NaN"`, `"Inf"` or `"-Inf"`.

**The texts are made when the value is made**, under the configuration a
formatter would use there (the knit's, or the working directory's
`_weft.yml`): the markdown, the plain text read from it (rule 1.4.24)
and the TeX form. A value made in one project keeps its texts after
[`setwd()`](https://rdrr.io/r/base/getwd.html). A ladder of units
(`unit = "m|km"`) picks one rung for the whole vector, and `v[1]` keeps
it. A value made with the default digits that prints a number that is
not zero as zero is warned about once, then: a warned check of kind
"printed as zero" in a knit, a `weft_zero_warning` outside one. Printing
it never warns again.

**What it gives.**
[`as.character()`](https://rdrr.io/r/base/character.html),
[`format()`](https://rdrr.io/r/base/format.html),
[`paste()`](https://rdrr.io/r/base/paste.html),
[`toString()`](https://rdrr.io/r/base/toString.html), `sprintf("%s", )`,
[`glue::glue()`](https://glue.tidyverse.org/reference/glue.html),
[`message()`](https://rdrr.io/r/base/message.html),
[`warning()`](https://rdrr.io/r/base/warning.html),
[`stop()`](https://rdrr.io/r/base/stop.html), cli's `{v}` and
`{.val {v}}`, a ggplot2 title or label, a printed data frame and
[`knitr::kable()`](https://rdrr.io/pkg/knitr/man/kable.html) give the
plain text. `format(v, target = )` takes `"plain"` (the default),
`"markdown"`, `"tex"`, `"ansi"` (plain), `"html"` or `"marquee"` (what
the matching `fmt_*()` call gives); other arguments of
[`format()`](https://rdrr.io/r/base/format.html) are ignored.
[`knitr::knit_print()`](https://rdrr.io/pkg/knitr/man/knit_print.html)
gives the markdown, joined by ", " inline and one element per line
otherwise, so a document with no weft hooks prints the value right in
prose. [`print()`](https://rdrr.io/r/base/print.html) writes a header
naming the format, then the plain texts. Three limits are R's:
[`cat()`](https://rdrr.io/r/base/cat.html) prints the number underneath
(as it prints a `Date`),
[`writeLines()`](https://rdrr.io/r/base/writeLines.html) refuses the
value, and a `for` loop reads the numbers; give the first two
`format(v)`. `sprintf("%.2f", v)` formats the number, as asked.

**Vectors.** `[`, `[[`, [`rev()`](https://rdrr.io/r/base/rev.html),
[`rep()`](https://rdrr.io/r/base/rep.html),
[`head()`](https://rdrr.io/r/utils/head.html),
[`tail()`](https://rdrr.io/r/utils/head.html),
[`sort()`](https://rdrr.io/r/base/sort.html),
[`unique()`](https://rdrr.io/r/base/unique.html) and
[`as.list()`](https://rdrr.io/r/base/list.html) keep the format and the
texts of the elements they keep. [`c()`](https://rdrr.io/r/base/c.html)
and `[<-` make the texts again for the whole result, under the
configuration in force then; numbers given to them take the format.
Values whose formats differ, or a value and anything that is not a
number, do not combine: a `weft_construct_error`. `c(3, v)` is a plain
number, because R dispatches [`c()`](https://rdrr.io/r/base/c.html) on
its first argument. When vctrs is loaded,
[`vctrs::vec_c()`](https://vctrs.r-lib.org/reference/vec_c.html) and the
dplyr verbs follow the same rules, and a value combined with a plain
number gives a plain number.

**Arithmetic drops the format** (rule 3.12.7): `+`, `*`,
[`round()`](https://rdrr.io/r/base/Round.html),
[`sum()`](https://rdrr.io/r/base/sum.html) and the rest give the result
for the number underneath: a double, or what the class underneath gives
(a `units` quantity, a `weft_year`).
[`min()`](https://rdrr.io/r/base/Extremes.html),
[`max()`](https://rdrr.io/r/base/Extremes.html),
[`range()`](https://rdrr.io/r/base/range.html),
[`mean()`](https://rdrr.io/r/base/mean.html) and
[`median()`](https://rdrr.io/r/stats/median.html), whose result is on
the scale of their input, keep the format. A comparison gives a logical,
so [`claim()`](https://vorpalvorpal.github.io/weft/reference/claim.md)
judges the number.

**In weft's constructs** (rule 3.12.8) the format is put together with
what is written at the use: a key written there replaces the format's
key of that name (`digits` and `sigfig` replace each other); a number
class written there that differs from the format's replaces it, with all
its keys; otherwise the format's class and keys apply. `` `r v` `` in
prose prints the markdown, in math its TeX, and `` `v`{.val} `` prints
its own format. The ledger records the value only where weft resolves
it: making it, converting it to text and printing it record nothing. A
self-formatting value is never a named value for the filter:
[`weft_values_write()`](https://vorpalvorpal.github.io/weft/reference/weft_values_write.md)
refuses it (E46). Phrase functions such as
[`ci()`](https://vorpalvorpal.github.io/weft/reference/phrases.md) use
its number and ignore its format.

## Examples

``` r
v <- val_num(3.14159, digits = 2)
paste("Mean", v)
#> [1] "Mean 3.14"
v > 3
#> [1] TRUE
format(val_sci(1.2e-4), target = "markdown")
#> [1] "1.2 × 10^−4^"
```
