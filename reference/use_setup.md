# Activate weft in a project's documents

Sets up the activation of weft (rule 9.2): the project `.Rprofile` that
calls
[`weft_setup()`](https://vorpalvorpal.github.io/weft/reference/weft_setup.md)
in every knit, or the same call in each document's front matter,
together with the `_weft.yml` that records the weft version. It says
what it will write before it writes anything, and running it again
changes nothing.
[`suppressMessages()`](https://rdrr.io/r/base/message.html) silences it.

## Usage

``` r
use_setup(path = ".", route = c("auto", "rprofile", "front-matter"))
```

## Arguments

- path:

  A folder or one document. Default: the current folder.

- route:

  `"auto"`, `"rprofile"` or `"front-matter"`.

## Value

The paths written, relative to the root, invisibly
([`character()`](https://rdrr.io/r/base/character.html) when nothing
changed).

## Details

`path` is a folder or one `.qmd`, `.Rmd` or `.rmd` file. A folder in a
Quarto project (a `_quarto.yml` here or above it) is set up at the
project root. The `route` is `"rprofile"` in a Quarto project and
`"front-matter"` otherwise, unless you choose.

It writes:

- `_weft.yml`, when there is none (a comment and `weft_version:`), or
  the `weft_version:` line appended to one that lacks it. An existing
  line is left as it is.

- route `"rprofile"`: the `.Rprofile` at the project root. A new file
  sources `~/.Rprofile` first, because R reads one profile only; an
  existing file gains a comment and the activation line after its last
  line (after `source("renv/activate.R")`, so weft is found in renv's
  library). A file that already calls
  [`weft::weft_setup()`](https://vorpalvorpal.github.io/weft/reference/weft_setup.md)
  is kept.

- route `"front-matter"`:
  `knitr: opts_knit: weft: !expr weft::weft_setup()` in each document's
  front matter.

- `engine: knitr` in each `.qmd` that has no `engine:` or `jupyter:` key
  and is not another engine's alone, except files and folders whose
  names start with `_` or `.` (includes). A page of another engine's
  chunks alone gains the line only when it holds an R construct: an R
  value (`` `r x`{.num} ``) or a span whose governor is outside the
  grammar of the filter. A page of named values (`` `depth`{.num} ``)
  and spans of that grammar, or with no construct, stays as it is.

- for an `.Rmd` outside a Quarto project, `weft.lua`, `weft-check.lua`,
  `weft-output.lua` and the folder `weftlib/` beside the document
  (weft's own files: kept when identical, replaced when they differ)
  and, under each format of `output:`,
  `pandoc_args: ["--lua-filter", "weft.lua", "--lua-filter", "weft-check.lua", "--lua-filter", "weft-output.lua"]`.
  A document set up before named values, which names only
  `weft-check.lua`, gets `weft.lua` named before it; one set up before
  the rendered-output check gets `weft-output.lua` named last.

Front matter is edited as text and checked by parsing it again. When an
edit cannot be made safely (flow-style `knitr:` or `pandoc_args`, a YAML
anchor, another `weft:` value under `opts_knit`), or a file's place
holds a folder or a symbolic link, nothing is written, and the error
prints the lines to add by hand.

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
use_setup(dir)
#> weft will write, under /tmp/RtmpJkcgEX/weft-example1a167a0eba7d:
#>   _weft.yml  (edit: adds the weft_version line)
#>   survey.Rmd  (edit: adds the weft setup line and names the weft-check filter)
#>   weft-check.lua  (new: the weft-check filter for rmarkdown)
#>   weft-output.lua  (new: the rendered-output check for rmarkdown)
#>   weft.lua  (new: the weft filter for rmarkdown)
#>   weftlib/cond.lua  (new: the weft filter for rmarkdown)
#>   weftlib/config.lua  (new: the weft filter for rmarkdown)
#>   weftlib/ledger.lua  (new: the weft filter for rmarkdown)
#>   weftlib/lines.lua  (new: the weft filter for rmarkdown)
#>   weftlib/num.lua  (new: the weft filter for rmarkdown)
#>   weftlib/report.lua  (new: the weft filter for rmarkdown)
#>   weftlib/stamp.lua  (new: the weft filter for rmarkdown)
#>   weftlib/words.lua  (new: the weft filter for rmarkdown)
#> Wrote: _weft.yml, survey.Rmd, weft-check.lua, weft-output.lua, weft.lua, weftlib/cond.lua, weftlib/config.lua, weftlib/ledger.lua, weftlib/lines.lua, weftlib/num.lua, weftlib/report.lua, weftlib/stamp.lua, weftlib/words.lua
list.files(dir, all.files = TRUE)
#> [1] "."               ".."              "_weft.yml"       "survey.Rmd"     
#> [5] "weft-check.lua"  "weft-output.lua" "weft.lua"        "weftlib"        
unlink(dir, recursive = TRUE)
```
