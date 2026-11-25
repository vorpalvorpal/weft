# Lint a project's documents and scripts without running them

Reads `.qmd` and `.Rmd` documents as text and returns the typed numbers,
construct errors and other problems the rules of
[`lint_rules()`](https://vorpalvorpal.github.io/weft/reference/lint_rules.md)
find. Nothing in a document is run.

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

The `.R` and `.r` files of the project (its scripts) are read too, but
only for the literal strings they pass to
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md): in a
script, `weft("We found 12 sites")` is prose like any other and its `12`
is a finding, placed at its line and column in the script. A call is
`weft(...)`, `weft::weft(...)` or `weft:::weft(...)`, or the right-hand
side of a pipe; the argument read is the one R matches to `x`, a string
literal (a raw string too) or the literal elements of a
[`c()`](https://rdrr.io/r/base/c.html). The code around the call is not
read, and neither are
[`claim()`](https://vorpalvorpal.github.io/weft/reference/claim.md)
calls, phrases or strings given to other functions. The rules that read
scripts are those with `scripts` `TRUE` in
[`lint_rules()`](https://vorpalvorpal.github.io/weft/reference/lint_rules.md);
the project rules read documents only. A script is left out when it is
in a folder whose name starts with `.` or `_`, or in `renv`, `packrat`,
`node_modules`, `_site`, `_book`, `_freeze` or `_extensions`, when its
file name starts with `.`, or when it matches the setting `scripts_skip`
of the `_weft.yml` nearest to it: a list of folder or file names, or
paths from that folder, with no wildcards. Its default is `[tests]`,
`[]` reads every script, and a list that is given replaces the default,
so keep `tests` in it. A skipped or excluded script named in `files` or
as `path` gives a note. A script whose bytes do not hold `weft` is not
read, one that is not valid UTF-8 gives the `read` finding, and one that
does not parse as R gives a note and no findings.
