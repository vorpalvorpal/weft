# Resolve markup in a string

`weft()` resolves weft's constructs in a character vector from R code,
for the text slots no chunk option reaches: a plot's title and labels, a
console or log message, a table's caption, text printed with
`results = "asis"` (rule 1.10.10). Each element of `x` is a block of
prose. Everything in it (values, bare values, governors, claims, guards)
is evaluated during the call, in `.envir`, so the result holds what they
printed: changing a variable afterwards changes nothing.

## Usage

``` r
weft(x, .envir = parent.frame())

# S3 method for class 'weft'
as.character(x, ...)

# S3 method for class 'weft'
format(x, target = "plain", ...)

# S3 method for class 'weft'
print(x, ...)

# S3 method for class 'weft'
x[...]

# S3 method for class 'weft'
x[[i, ...]]

# S3 method for class 'weft'
sort(x, decreasing = FALSE, ...)

# S3 method for class 'weft'
c(...)

# S3 method for class 'weft'
x[i] <- value

# S3 method for class 'weft'
knit_print(x, options = NULL, inline = FALSE, ...)
```

## Arguments

- x:

  A character vector of markup (a factor is read as its labels), or a
  `weft` object, which is returned as it is. An `NA` element stays `NA`.

- .envir:

  The environment the markup's code is evaluated in.

- ...:

  Not used.

- target:

  For [`format()`](https://rdrr.io/r/base/format.html): `"plain"` (the
  default) or `"markdown"`.

- i:

  An index.

- decreasing:

  Passed to [`sort()`](https://rdrr.io/r/base/sort.html).

- value:

  The new elements: `weft` objects or character vectors.

- options:

  Passed by knitr.

- inline:

  For `knit_print()`: `TRUE` for inline R.

## Value

A `weft` object of the same length and names as `x`.

## Details

The result is a `weft` object, a character vector with two forms of each
element. Its content is the **plain** text (Unicode, no markup: `m²`,
`1.2 × 10⁻⁴`, emphasis without its marks, rule 1.4.24), so anything that
reads a character vector ([`cat()`](https://rdrr.io/r/base/cat.html),
[`nchar()`](https://rdrr.io/r/base/nchar.html),
[`paste()`](https://rdrr.io/r/base/paste.html), a ggplot2 title) gets
readable text. The attribute `markdown` holds the **markdown** text.
[`as.character()`](https://rdrr.io/r/base/character.html) and
[`format()`](https://rdrr.io/r/base/format.html) give the plain text;
`format(x, target = "markdown")` gives the markdown; printing the object
in a knit, or as inline R, writes the markdown. `[`, `[[` and
[`rev()`](https://rdrr.io/r/base/rev.html) keep both forms;
[`c()`](https://rdrr.io/r/base/c.html) and `[<-` take `weft` objects
(both forms) and character vectors (text as it is: not markup, not
evaluated); [`rep()`](https://rdrr.io/r/base/rep.html),
[`unique()`](https://rdrr.io/r/base/unique.html) and
[`sort()`](https://rdrr.io/r/base/sort.html) give a plain character
vector. A `weft` object given as a value inside the markup of another,
or to an `fmt_*()`, contributes its markdown.

A caption option that R computes as a `weft` object
(`fig.cap = weft(...)`, `#| fig-cap: !expr weft(...)`) is given to knitr
as markdown (as plain text for `fig.alt`).
`knitr::kable(caption = weft(...))` gets the plain text.
[`cat()`](https://rdrr.io/r/base/cat.html) in a `results = "asis"` chunk
writes plain text; to write markdown, print the object or use
`cat(format(x, target = "markdown"))`.

During a knit with weft active a failed check, a missing value or a
value error is collected as it is in prose (rules 2.4.1, 3.6.3) and
marked in the text with the chunk that holds the call, or the line of
the inline R (rule 2.6.8). Outside a knit, and in a knit where
[`weft_setup()`](https://vorpalvorpal.github.io/weft/reference/weft_setup.md)
was not called, the first failure stops at once, with the class of the
failure (`weft_claim_failed`, `weft_no_value`, `weft_value_error`,
`weft_construct_error`); draft mode has no effect there. A warning is
signalled at the call and the object is returned.

Outside a knit, the configuration is that of the project root of the
working directory (the nearest folder upward that holds `_weft.yml`,
else `_quarto.yml`, else the working directory). It is read once and
kept for the session, and read again when `_weft.yml` appears,
disappears or changes size or modification time. A `_weft.yml` with an
error is a `weft_config_error`.

Block-only constructs do not apply; each element is read as inline
markup. Bare inline R in a string is evaluated as knitr evaluates it
(rule 1.1.8). The functions inline code calls by name
([`claim()`](https://vorpalvorpal.github.io/weft/reference/claim.md),
[`plural()`](https://vorpalvorpal.github.io/weft/reference/plural.md),
the `fmt_*()` functions) are visible to the markup even when weft is not
attached; a function of the same name that `.envir` can see wins.

## Examples

``` r
n_sites <- 3
w <- weft("Found [a site | # sites]{n=\"n_sites\"} of *Eucalyptus* on 5 m^2^.")
as.character(w)
#> [1] "Found 3 sites of Eucalyptus on 5 m²."
format(w, target = "markdown")
#> [1] "Found 3 sites of *Eucalyptus* on 5 m^2^."

# one title for each site, each keeping its own value
titles <- lapply(c(2, 5), function(k) weft("Depth at `r k`{.num} sites"))
vapply(titles, as.character, "")
#> [1] "Depth at 2 sites" "Depth at 5 sites"

if (requireNamespace("ggplot2", quietly = TRUE)) {
  ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) +
    ggplot2::geom_point() +
    ggplot2::labs(title = weft("Rate of 1.2 &times; 10^-4^ m^2^"))
}
```
