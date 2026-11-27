# What weft has installed in a project

Reports the state of each part of the set-up: `setup` (`_weft.yml` and
the version it records), `activation`, `quarto`, `dictionary`, `hooks`,
`ci`, `agent docs`, `draft`, `verify_skip` and `strict`, and `python`
(can `import weft` run) for a project with a jupyter-engine document. It
writes nothing, starts no R process and uses no network.

## Usage

``` r
status(path = ".")
```

## Arguments

- path:

  A directory in the project.

## Value

A `weft_status`: a data frame with `part`, `state` and `detail`, and the
attribute [`next`](https://rdrr.io/r/base/Control.html).

## Details

`state` is one of `ok`, `missing`, `outdated` (weft's file is from
another version, or the hook's recorded `Rscript` has gone), `edited` (a
file weft wrote has been changed by hand: it is left alone and never
makes a next step), `off` (draft mode on, or parts of
[`verify()`](https://vorpalvorpal.github.io/weft/reference/verify.md)
skipped) and `n/a`. The [`next`](https://rdrr.io/r/base/Control.html)
attribute is the first part, in the order of
[`use_weft()`](https://vorpalvorpal.github.io/weft/reference/use_weft.md),
that is `missing` or `outdated`, as a sentence; otherwise it says there
is nothing to install.

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
status(dir)
#> weft status: /tmp/RtmpBZdLtm/weft-example1a076362bcdd
#>   setup        ok        _weft.yml does not record a weft version (not recorded; installed: 0.1.0)
#>   activation   missing   no .Rprofile line and no front-matter route
#>   quarto       n/a       not a Quarto project
#>   dictionary   missing   no dict.yml
#>   hooks        n/a       not a git repository
#>   ci           n/a       not a git repository
#>   agent docs   missing   AGENTS.md block: missing; skill: missing
#>   draft        ok        draft mode is off
#>   verify_skip  ok        verify() skips nothing
#>   strict       ok        no rule is strict
#> Next: run weft::use_setup() to activate weft in the documents.
unlink(dir, recursive = TRUE)
```
