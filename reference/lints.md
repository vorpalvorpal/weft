# Lint a project's documents and scripts without running them

Reads `.qmd` and `.Rmd` documents as text and returns the typed numbers,
construct errors and other problems the rules of
[`lint_rules()`](https://vorpalvorpal.github.io/weft/reference/lint_rules.md)
find. Nothing in a document is run. A Jupyter notebook (`.ipynb`) is
read as the document its cells make, its markdown cells prose and its
code cells chunks, and a finding in it is placed at its line and column
in the JSON file.

## Usage

``` r
# S3 method for class 'weft_findings'
print(x, max = 200, ...)

lints(
  path = ".",
  files = NULL,
  rules = NULL,
  tier = 1,
  reader = c("weft", "pandoc")
)
```

## Arguments

- x:

  A `weft_findings`.

- max:

  The most findings printed.

- ...:

  Not used.

- path:

  One existing file or folder. The project root is found from it.

- files:

  `NULL`, or documents and scripts (relative to the root or absolute
  under it) to report on. File-scope rules run on these only;
  project-scope rules still read every document.

- rules:

  `NULL` (every rule of the tiers asked for), or ids from
  [`lint_rules()`](https://vorpalvorpal.github.io/weft/reference/lint_rules.md).

- tier:

  A subset of `1:2`. The default is tier 1.

- reader:

  `"weft"` (the default) or `"pandoc"`.

## Value

A `weft_findings` data frame sorted by file, line, column and rule, with
columns `file`, `line`, `col`, `end_line`, `rule`, `tier`, `spec`,
`context`, `text`, `message`, `hint` and `sentence`, and the attribute
`notes`.

## Details

The `.R` and `.r` files of the project (its scripts) are read too, for
the literal strings they pass to
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) and
for their
[`claim()`](https://vorpalvorpal.github.io/weft/reference/claim.md)
calls: in a script, `weft("We found 12 sites")` is prose like any other
and its `12` is a finding, placed at its line and column in the script.
A call is `weft(...)`, `weft::weft(...)` or `weft:::weft(...)`, or the
right-hand side of a pipe; the argument read is the one R matches to
`x`, a string literal (a raw string too) or the literal elements of a
[`c()`](https://rdrr.io/r/base/c.html). Of the rest of a script's code
only its
[`claim()`](https://vorpalvorpal.github.io/weft/reference/claim.md)
calls are read, by `inert-check` alone; phrases and strings given to
other functions are not. The rules that read scripts are those with
`scripts` `TRUE` in
[`lint_rules()`](https://vorpalvorpal.github.io/weft/reference/lint_rules.md);
the project rules read documents only. A script is left out when it is
in a folder whose name starts with `.` or `_`, or in `renv`, `packrat`,
`node_modules`, `_site`, `_book`, `_freeze` or `_extensions`, when its
file name starts with `.`, or when it matches the setting `scripts_skip`
of the `_weft.yml` nearest to it: a list of folder or file names, or
paths from that folder, with no wildcards. Its default is `[tests]`,
`[]` reads every script, and a list that is given replaces the default,
so keep `tests` in it. A skipped or excluded script named in `files` or
as `path` gives a note. A script whose bytes hold neither `weft` nor a
`claim(` call is not read; one that is not valid UTF-8 gives the `read`
finding when its bytes hold `weft` and is otherwise not read; one that
does not parse as R gives a note and no findings.

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
lints(dir)
#> weft lints: 2 findings in 1 file (2 tier 1, 0 tier 2)
#> 
#> survey.Rmd
#>   5:12  numeral      "14" is a number typed in prose (rule 5.2.1).
#>                      Write it as a value, put it in the dictionary, or mark it [14]{.weft-literal why="..."}.
#>   7:1   chunk-label  The r chunk `n_high <- 3` has no label (rule 5.8.1).
#>                      Give the chunk a label, as `#| label: name`.
lints(dir, rules = "numeral", tier = 1:2)
#> weft lints: 1 finding in 1 file (1 tier 1, 0 tier 2)
#> 
#> survey.Rmd
#>   5:12  numeral  "14" is a number typed in prose (rule 5.2.1).
#>                  Write it as a value, put it in the dictionary, or mark it [14]{.weft-literal why="..."}.
unlink(dir, recursive = TRUE)
```
