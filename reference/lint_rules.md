# The static lints

`lint_rules()` lists every rule
[`lints()`](https://vorpalvorpal.github.io/weft/reference/lints.md)
knows, in order: its `id`, the `spec` rule number, its `tier` (1 blocks,
2 is listed over added material), its `scope` (`"file"` or `"project"`)
and what it finds.

## Usage

``` r
lint_rules()
```

## Value

A data frame with `id`, `spec`, `tier`, `scope` and `what`.

## Examples

``` r
head(lint_rules()[, c("id", "tier", "scope")])
#>            id tier scope
#> 1     numeral    1  file
#> 2   construct    1  file
#> 3        read    1  file
#> 4 block-start    1  file
#> 5    lone-bar    2  file
#> 6     if-zero    2  file
```
