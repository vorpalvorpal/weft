# Write a values file

`weft_values_write()` writes the values it is given to a JSON file in
the form of a `weft-values` block (schema 1), for a document to read
with a `weft-values` block that names the file (rules 2.13.10, 3.8.5).
It works outside a knit, and in a `targets` pipeline. In a knitr
document R reads a named value itself, so a values file is for a
document that runs no R, or for a pipeline that computes the values
elsewhere.

## Usage

``` r
weft_values_write(path, ...)
```

## Arguments

- path:

  The file to write. A relative path is relative to the working
  directory.

- ...:

  Named values, or names of variables, as above. An argument may be a
  call of
  [`claim()`](https://vorpalvorpal.github.io/weft/reference/claim.md).

## Value

`path`, invisibly.

## Details

Each argument after `path` writes one name:
`weft_values_write(f, depth = mean(d$depth))`, or
`weft_values_write(f, depth, n_sites)` for variables of the same names.
A name is ASCII letters, digits, `_` and `.`, starting with a letter or
`_`, at most 64 characters. An argument that is a call of
[`claim()`](https://vorpalvorpal.github.io/weft/reference/claim.md) is
captured: its checks are run and recorded with the value, nothing is
stopped, and each check counts where the name is used.

A bool, a whole or decimal number, a string, a factor, a `Date`, an
`integer64` or an atomic vector of these (up to 10000 elements) is
written with its kind. `NA`, `NaN`, `Inf` and `NULL` are written as
missing. A value with units is refused, and any other object (a data
frame, a list, a `POSIXct`, a function) is written as an error that is
reported where the name is used.

The file is written atomically, as UTF-8 with `\\n` line ends. Nothing
is written when an argument is refused, and the old file stays.

## Examples

``` r
f <- tempfile(fileext = ".json")
weft_values_write(f, n = 12L, site = "north")
cat(readLines(f), sep = "\n")
#> {"weft":1,"lang":"r","run":null,"at":1795819957,"values":{"n":{"t":"int","v":"12"},"site":{"t":"string","v":"north"}}}
```
