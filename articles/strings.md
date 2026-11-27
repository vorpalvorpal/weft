# weft in strings

This article is for authors whose numbers end up in text that R builds:
plot titles and axis labels, console and log messages, the cells and
captions of a table. It assumes you know
[`vignette("values", package = "weft")`](https://vorpalvorpal.github.io/weft/articles/values.md)
and
[`vignette("wording", package = "weft")`](https://vorpalvorpal.github.io/weft/articles/wording.md).
After it you will be able to put weft markup in an R string, send the
result to a plot, the console, cli or a table, quote attribute values
inside R strings, and say what happens when a check in a string fails.

The chunks that draw a plot are not run when this article is built. The
others are run, and their output is shown as R gave it.

``` r

library(weft)
```

## One call, several sinks

[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) takes
a character vector of markup and resolves it. Every value, governor,
name and check in it is evaluated during the call, in the environment
that called it. The result holds what they printed, so changing a
variable afterwards changes nothing.

``` r

k <- 3
area <- 0.00012
w <- weft("*Eucalyptus* at `r k`{.word} sites, `r area`{.sci} m^2^ each")
```

The object is a character vector with two forms of each element. Its
content is the **plain** text: Unicode, with no markup. Superscripts are
Unicode characters, emphasis loses its marks, and an entity such as
`&times;` is its character. The **markdown** text is kept in an
attribute.

``` r

as.character(w)
#> [1] "Eucalyptus at three sites, 1.2 × 10⁻⁴ m² each"
format(w, target = "markdown")
#> [1] "*Eucalyptus* at three sites, 1.2 × 10^−4^ m^2^ each"
```

Printed by a chunk, the object writes its markdown, which the page then
renders:

``` r

w
```

*Eucalyptus* at three sites, 1.2 × 10⁻⁴ m² each

Each place a string can go takes the form it can show:

| Sink | Gets |
|----|----|
| a ggplot2 title, subtitle, caption or axis label | plain text |
| ggtext `element_markdown()`, `geom_richtext()` | `format(w, target = "html")` |
| marquee `element_marquee()`, `geom_marquee()` | `format(w, target = "marquee")` |
| gt in HTML output, reactable `colDef(html = TRUE)`, htmltools, Shiny, plotly text | `format(w, target = "html")` |
| [`cat()`](https://rdrr.io/r/base/cat.html), [`paste()`](https://rdrr.io/r/base/paste.html), `sprintf("%s", )`, [`message()`](https://rdrr.io/r/base/message.html), [`stop()`](https://rdrr.io/r/base/stop.html), [`glue::glue()`](https://glue.tidyverse.org/reference/glue.html) | plain text |
| [`print()`](https://rdrr.io/r/base/print.html) in a console | the console form: plain text with emphasis in italic and bold, where the console draws styles |
| `{.val {w}}` in a cli message | the console form; `{w}` gets plain text |
| a chunk that prints the object, inline R | markdown |
| a caption option R computes, `fig.cap = weft(...)` | markdown (`fig.alt` gets plain text) |
| `knitr::kable(caption = weft(...))` | plain text |

`format(w)` and `as.character(w)` are always plain, whatever the console
can draw. `format(w, target = "markdown")` gives the markdown and
`format(w, target = "ansi")` the console form.
`format(w, target = "html")` and `format(w, target = "marquee")` give
the forms for rich plot text (see “Rich plot text”).

In the prose of a document you do not need
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md): write
the markup directly.
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) is for
text that no chunk option reaches.

## Plots

A ggplot2 label keeps the `weft` object and draws its plain text. Write
the title as you would write the sentence in prose:

``` r

library(ggplot2)
creek <- data.frame(
  site = c("Upper", "Middle", "Lower"),
  flow = c(0.0021, 0.0094, 0.0310),
  ntu = c(4.2, 7.9, 12.6)
)
n_high <- sum(creek$ntu > 10)

ggplot(creek, aes(flow, ntu)) +
  geom_point() +
  scale_x_continuous(labels = function(b) fmt_sci(b, target = "plain")) +
  scale_y_continuous(labels = function(b) fmt_num(b, target = "plain")) +
  labs(
    title = weft("Turbidity at `r nrow(creek)`{.word} sites"),
    subtitle = weft("[No site | One site | # sites]{n=n_high} read above the trigger"),
    x = weft("Flow (m^3^ s^-1^)"),
    y = "Turbidity (NTU)"
  )
```

The axis title draws as “Flow (m³ s⁻¹)”, and the subtitle as “One site
read above the trigger”. A plot draws no emphasis: `*Eucalyptus*` draws
as “Eucalyptus” in the plot’s font. A formula in the markup keeps its
TeX in the plain text; for a formula in a plot, use plotmath.

**Scale labels.** A scale’s `labels` argument takes a function of the
breaks. Every `fmt_*()` takes `target = "plain"`, so the tick labels
print with the same digits, minus sign and grouping as the numbers in
the prose. Outside a knit, `fmt_*()` and
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) read
the same `_weft.yml`, so a script’s tick labels and its title agree.

``` r

fmt_num(c(-1.5, 0, 2500), target = "plain")
#> <weft_text>
#> [1] "−1.5"  "0"     "2,500"
fmt_sci(c(0.0021, 0.031), target = "plain")
#> <weft_text>
#> [1] "2.1 × 10⁻³" "3.1 × 10⁻²"
```

**Captions.** In a knit with weft on, a caption written as a string is
resolved like prose. When R computes the caption, give it as a
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) call.
knitr gets the markdown for `fig-cap` and `tbl-cap`, and the plain text
for `fig-alt`:

```` markdown
```{r}
#| label: fig-flow
#| fig-cap: !expr weft("Turbidity against flow at `r nrow(creek)`{.word} sites.")
#| fig-alt: !expr weft("Scatter plot of turbidity against flow at `r nrow(creek)`{.word} sites.")
ggplot(creek, aes(flow, ntu)) + geom_point()
```
````

In an R Markdown chunk header the same is `fig.cap = weft("...")`.

**PDF output.** The plain text uses Unicode superscripts and the minus
sign (U+2212). R’s [`pdf()`](https://rdrr.io/r/grDevices/pdf.html)
device cannot draw the minus sign or most of the superscripts. For a
plot with weft text that is saved as PDF, use
[`cairo_pdf()`](https://rdrr.io/r/grDevices/cairo.html) or a ragg
device:

``` r

ggsave("flow.pdf", device = cairo_pdf)
ggsave("flow.png", device = ragg::agg_png)
```

In a knit, set the device for every chunk in the setup chunk, with
`knitr::opts_chunk$set(dev = "cairo_pdf")` for PDF output or
`dev = "ragg_png"` for HTML.

## Rich plot text

ggtext and marquee draw emphasis, colour and real superscripts in a
plot, but neither reads weft’s markdown correctly: ggtext shows the
carets of `10^−4^` and stops the plot on a list, and marquee reads `_x_`
as underline and drops HTML tags without a word, so `10<sup>−4</sup>`
would draw as “10−4”. Each gets its own form, which you ask for where
the text meets the sink:

``` r

w <- weft("*Eucalyptus* cover at `r cover`{.pct}, 10^`r k`^ stems")

ggplot(d, aes(x, y)) + geom_point() +
  labs(title = format(w, target = "html")) +
  theme(plot.title = ggtext::element_markdown()) +
  scale_y_continuous(labels = \(b) fmt_sci(b, target = "html")) +
  theme(axis.text.y = ggtext::element_markdown())

ggplot(d, aes(x, y)) + geom_point() +
  labs(title = format(w, target = "marquee")) +
  theme(plot.title = marquee::element_marquee())
```

`target = "html"` writes only `<i>`, `<b>`, `<sup>`, `<sub>`, `<span>`
and `<br>`, with every character that ggtext’s own markdown pass would
read written as an entity, so the result does not depend on the version
of the markdown package. A span keeps its attributes, so
`[Depth]{style='color:#c00'}` draws a red word. A list is its lines. The
same form serves gt’s `fmt_markdown()` in HTML output, reactable with
`colDef(html = TRUE)`, htmltools, Shiny and plotly’s text;
[`format()`](https://rdrr.io/r/base/format.html) gives it the class
htmltools uses, so they take it unescaped. In a table converted to Word
the tags are dropped and a superscript is lost, so give such a table the
plain text.

`target = "marquee"` writes marquee’s own spans: `10{.sup −4}`,
`{.em x}` and `{.str x}`, with marquee’s backslash escapes. A formula is
drawn as typed.

A `weft` object given to ggtext or marquee as it is draws its plain
text: both call
[`as.character()`](https://rdrr.io/r/base/character.html), so weft
cannot see which sink it is in. ggtext draws the thin and no-break
spaces as word spaces.

## The console and cli

[`print()`](https://rdrr.io/r/base/print.html) writes each element on
its own line. Where the console draws styles, emphasis is italic, strong
emphasis bold, and a failure marker bold red. Nothing else differs, so
with the styles removed the line is the plain text. weft draws styles
only where cli would draw its own: not under `NO_COLOR`, not in a knit,
not into a sink, and not on a terminal without colour. This article is
knit, so it shows the plain text:

``` r

print(w)
#> Eucalyptus at three sites, 1.2 × 10⁻⁴ m² each
```

To see the styles as escape codes, force colour:

``` r

a <- withr::with_options(list(cli.num_colors = 256), format(w, target = "ansi"))
a
#> [1] "\033[3mEucalyptus\033[23m at three sites, 1.2 × 10⁻⁴ m² each"
cli::ansi_strip(a)
#> [1] "Eucalyptus at three sites, 1.2 × 10⁻⁴ m² each"
```

In a cli message, `{.val {w}}` draws the console form, in cli’s value
colour and without quotes. A plain `{w}` gets the plain text.

``` r

cli::format_inline("Mapped {.val {w}}")
#> [1] "Mapped \033[3m\033[34mEucalyptus\033[23m at three sites, 1.2 × 10⁻⁴ m² each\033[39m"
```

``` r

cli::cli_inform("{.val {w}}")      # emphasis drawn, in the value colour
cli::cli_inform("Plotted {w}")     # plain text
cli::cli_alert_success("Saved {.val {w}}")
```

Three things to know:

- Write `{.val {w}}` with nothing else inside the braces.
  `{.val text {w}}` pastes the value into the text and quotes the whole.
- Give the object to cli as a value, never as the template. A value is
  never read as a template, so braces in it (a TeX formula, say) stay
  text. As the template, `cli_inform(w)`, cli evaluates whatever it
  finds in braces. Write `cli_inform("{w}")`.
- Do not write weft markup into a cli template. cli reads `{.num}` as
  one of its own styles. Resolve the text with
  [`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md)
  first and pass the object.

## Tables

A column built with
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) holds
plain text, so a data frame prints readable cells. Build one element per
row in a function, so each row reads its own values:

``` r

readings <- data.frame(
  site = c("Upper", "Middle", "Lower"),
  ntu = c(4.2, 7.9, 12.6),
  n = c(1, 3, 2)
)
note <- function(ntu, n) {
  weft("`ntu`{.num} NTU, [**high** | normal]{if='ntu > 10'}, from [one sample | # samples]{n=n}")
}
readings$note <- do.call(c, Map(note, readings$ntu, readings$n))
readings
#>     site  ntu n                             note
#> 1  Upper  4.2 1 4.2 NTU, normal, from one sample
#> 2 Middle  7.9 3  7.9 NTU, normal, from 3 samples
#> 3  Lower 12.6 2   12.6 NTU, high, from 2 samples
```

[`c()`](https://rdrr.io/r/base/c.html) of `weft` objects keeps both
forms. For a table rendered as markdown, give `kable()` the markdown of
the column, so the emphasis is drawn. A
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md)
caption reaches `kable()` as plain text:

``` r

shown <- readings[c("site", "note")]
shown$note <- format(readings$note, target = "markdown")
knitr::kable(shown, caption = weft("Turbidity at `r nrow(readings)`{.word} sites"))
```

| site   | note                               |
|:-------|:-----------------------------------|
| Upper  | 4.2 NTU, normal, from one sample   |
| Middle | 7.9 NTU, normal, from 3 samples    |
| Lower  | 12.6 NTU, **high**, from 2 samples |

Turbidity at three sites {.table}

## Messages and logs

[`message()`](https://rdrr.io/r/base/message.html),
[`warning()`](https://rdrr.io/r/base/warning.html) and
[`stop()`](https://rdrr.io/r/base/stop.html) paste their arguments, so
they get the plain text:

``` r

n_files <- 4
message(weft("Read `n_files`{.word} files."))
#> Read four files.
```

A helper that wraps
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) must
pass its caller’s environment on, or the markup reads the helper’s own
variables:

``` r

log_line <- function(text) message(weft(text, .envir = parent.frame()))
n_rows <- 1250
log_line("Kept `n_rows`{.num} rows.")
#> Kept 1,250 rows.
```

To write a log file, write the plain text, with
`writeLines(format(w), con)` or
[`cat()`](https://rdrr.io/r/base/cat.html). Do not write
`format(w, target = "ansi")` to a file: its form depends on the console
that wrote it.

In a chunk with `results = "asis"`,
[`cat()`](https://rdrr.io/r/base/cat.html) writes the plain text, and so
does an explicit [`print()`](https://rdrr.io/r/base/print.html). To
write markdown from a loop, write
`cat(format(w, target = "markdown"), "\n\n")`. Only an object the chunk
prints at its top level is written as markdown by knitr.

## Quoting inside R strings

An attribute value goes in double quotes, in single quotes, or in none
when it is one word, as in prose. In R code the choice matters, because
the markup sits inside an R string. Give the values the quote the R
string does not use:

``` r

tier <- "sev"
as.character(weft("[severe | mild]{if='tier == \"sev\"'}"))
#> [1] "severe"
as.character(weft('[severe | mild]{if="tier == \'sev\'"}'))
#> [1] "severe"
```

Both calls give weft the same block. In the first, the R string is in
double quotes, the value in single quotes, and the R string inside the
value in escaped double quotes, which R reads as plain `"` before weft
sees the text.

A value of one word, such as a name, needs no quotes: `{n=n_high}`,
`{digits=2}`.

Inside a quoted value weft reads four escapes: `\"`, `\'`, `\|` and `\`
(backslash, space). The last is how a value starts with a space, as the
`last` of `.and` may need. Any other backslash in a value is an error.
In an ordinary R string a backslash is itself written `\\`, so weft’s
`\` is `\\` in the R source:

``` r

sites <- c("Upper", "Middle", "Lower")
as.character(weft("`sites`{.and last='\\ plus '}"))
#> [1] "Upper, Middle plus Lower"
```

A raw string (R 4.0 and later) holds the text as written: quotes of both
kinds need no R escape, and weft’s backslash is written once:

``` r

weft(r"([severe | mild]{if='tier == "sev"'})")
weft(r"(`sites`{.and last="\ plus "})")
```

A raw string `r"(...)"` ends at the first `)"`. A value that ends in `)`
then takes single quotes (`{if='isTRUE(x)'}`), or the raw string takes
other brackets or dashes: `r"[...]"`, `r"---(...)---"`.

## Bare names read R

A name in a code span with a class, `` `ntu`{.num} ``, reads R where the
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) call
runs: it prints what `` `r ntu`{.num} `` would print, with every
formatter, units and the dictionary included. Names in a governor, such
as `{n=n}`, are R code in the same place.

The name is looked up in `.envir` (by default the caller) and its
enclosing environments, as far as the global environment, and no
further. A name is never read from base R, a package or a dataset. In a
loop, each call reads the names as they stand at that call:

``` r

depth <- c(Upper = 0.42, Lower = 1.37)
titles <- lapply(names(depth), function(site) {
  d <- depth[[site]]
  weft("Depth at `site`{.val}: `d`{.num digits=2} m")
})
print(do.call(c, titles))
#> Depth at Upper: 0.42 m
#> Depth at Lower: 1.37 m
```

A name that is not bound there, or that is bound to a function, is a “no
value” failure. Nothing is left for a Pandoc filter, because the text
goes to plots and consoles where none runs:

``` r

weft("A circle's area is `pi`{.num} r^2^.")
#> Error:
#> ! weft: chunk pi-name: `pi` is not bound where weft() was called, so it has no value (rule 1.12.12).
```

`` `r pi`{.num} `` reads base R’s `pi`. To use a name from a package,
bind it first: `n <- pkg::n`.

From a Python chunk in a knitr document, `weft_str()` in the weft Python
module calls
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) and
returns the markdown. There a named value is Python’s, published with
`put()`; see
[`vignette("languages", package = "weft")`](https://vorpalvorpal.github.io/weft/articles/languages.md).

## When something fails

**Outside a knit**, in a script or at the console, the first failure
stops at once. Its class says what failed: `weft_claim_failed`,
`weft_no_value`, `weft_value_error` or `weft_construct_error`. The
message begins `weft: a weft() string:`. Draft mode has no effect. A
warning, such as a value printed as zero, is signalled and the object is
returned.

The same holds in a knit where
[`weft_setup()`](https://vorpalvorpal.github.io/weft/reference/weft_setup.md)
was not called, as in this article. There the message names the chunk:

``` r

peak <- 61
weft("The peak was `r claim(peak, . < 50)`{.num} NTU.")
#> Error:
#> ! weft: chunk peak: 1 failed claim
#>   check `. < 50` failed (value: 61)
```

A script can catch a failure by its class:

``` r

title <- tryCatch(
  weft("The peak was `r claim(peak, . < 50)`{.num} NTU."),
  weft_claim_failed = function(e) {
    message("Check the peak: ", conditionMessage(e))
    weft("The peak was above the limit.")
  }
)
#> Check the peak: weft: chunk catch-class: 1 failed claim
#>   check `. < 50` failed (value: 61)
```

**In a knit with weft on**, a failure in a
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) string
is collected as one in a paragraph is. The knit goes on, and the render
fails at the end with every failure listed, each located by the chunk
that holds the call (or the line, for inline R). A construct error stops
the render at once, except in draft mode. In draft mode the render
finishes and the text carries a marker where the value would be, in a
plot title as in prose:

``` text
The peak was 61<<weft: failed claim, chunk fig-peak>> NTU.
```

Outside a knit,
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) reads
the `_weft.yml` of the project the working directory is in: the nearest
folder upward that holds `_weft.yml`, else `_quarto.yml`, else the
working directory itself. It reads the file once per session, and again
when it changes, so a call in a loop costs little. A `_weft.yml` with an
error is a `weft_config_error`.

## Scripts are linted

The lints, the commit gate,
[`arms()`](https://vorpalvorpal.github.io/weft/reference/arms.md) and
[`checks()`](https://vorpalvorpal.github.io/weft/reference/checks.md)
read the literal strings given to
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md), in
the R chunks of a document and in the project’s `.R` files. A typed
number in `weft("We found 12 sites")` in `R/plots.R` is a `numeral`
finding, as it would be in prose, and a construct error there fails a
commit. Write the number as a value:
`` weft("We found `n_sites`{.word} sites") ``.

Only a literal is read: a string, a raw string, or the literal elements
of a [`c()`](https://rdrr.io/r/base/c.html). A computed argument, such
as `weft(paste0(...))` or `weft(txt)`, is skipped. Keep the markup
literal and let the names inside it carry the data. Files under `tests/`
are not read unless `scripts_skip` says otherwise. The details are in
the “Scripts” section of
[`vignette("lints", package = "weft")`](https://vorpalvorpal.github.io/weft/articles/lints.md).

Markup in an R string that never reaches
[`weft()`](https://vorpalvorpal.github.io/weft/reference/weft.md) prints
as typed. In a document’s chunks the `string-markup` lint finds such a
string.
