# List the arms of every governed span of a document

Reads one or more `.qmd`, `.Rmd` or `.R` files with the scanner and
lists, for every `n`, `if`, `sign` and `list` span, each of its arms:
the span's place, the key and its expression, the arm's role and the
text the author wrote. The spans are those in prose, in captions, in
front-matter fields and in literal
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md)
strings. No R is run: the file is parsed, never evaluated, so an
expression that stops, writes a file or names an unknown object does
nothing.

## Usage

``` r
arms(file)
```

## Arguments

- file:

  One path, or several, to documents or scripts.

## Value

A data frame of class `weft_arms`, one row per arm, with the columns
`file`, `line` (where the span starts), `context`, `span` (the span's
number in the result, in document order), `key` (`"n"`, `"if"`, `"sign"`
or `"list"`), `expr` (the key's value), `arm` (the arm's index in its
span), `role` (`"always"`, `"one"`, `"other"`, `"zero"`, `"two"`,
`"true"`, `"false"`, `"positive"` or `"negative"`), `text` (the arm as
written, trimmed), and `parent_span` and `parent_arm` (the span and arm
it is nested in, or `NA`).

## Details

A file with a construct error is still listed. The errors are in the
attribute `errors`, and the print method ends with them. A span whose
arm count is not one the key accepts is not listed; it is one of the
errors. So is an `n` span with more than one arm in a document whose
`lang` is not English, because weft ships no other plural rules (rules
1.6.4, 1.6.5).

A file whose name ends `.R` or `.r` is read as a script: its spans are
those of the literal strings it passes to
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md)
(`weft(...)`, `weft::weft(...)`, or the right-hand side of a pipe, where
the left-hand side is the `x` it passes unless an argument is named
`x`), with the settings of its project and English plural rules, and
context `"weft"`. The setting `scripts_skip` is not applied: a script
that is named is read. A script that does not parse, or is not valid
UTF-8, lists no spans and no errors.

Only the spans of the files given are listed; a document that a chunk
includes with `child=` is listed only when it is given too.

## See also

[`rehearse()`](https://vorpalvorpal.github.io/weft/reference/rehearse.md),
which knits a document under several sets of parameters and reports
which arms they chose.

## Examples

``` r
dir <- tempfile("weft-example")
dir.create(dir)
writeLines("", file.path(dir, "_weft.yml"))
writeLines(c(
  "---",
  "title: Survey",
  "---",
  "",
  "We visited 14 sites.",
  "",
  "```{r}",
  "n_high <- 3",
  "```",
  "",
  "[No site | One site | # sites]{n=n_high} read high."
), file.path(dir, "survey.Rmd"))
arms(file.path(dir, "survey.Rmd"))
#> survey.Rmd:11  n="n_high"
#>   1 (zero)  No site
#>   2 (one)  One site
#>   3 (other)  # sites
unlink(dir, recursive = TRUE)
```
