# Regression guards for three position fixes of the simplify pass, and one include ruling. Written
# from the commit messages, dev/ and the include rules; no R under R/ was read.
#   A1: a phrase literal of brk()/lookup() after a tab is placed with the tab as one character
#       (E4 review K10; dev/design-e4.md C11: `col` in characters, a tab one character).
#   A2: a phrase literal after an escaped \n (backslash-n in the source) keeps its own source line.
#   A3: a header-literal caption (`fig.cap="..."` in the chunk header) in a chunk below a block-quoted
#       chunk is placed at its real column, not early by the width of the quote markers.
#   B:  rule I4 (dev/decisions.md, "One include reader, following Quarto"): a `file=` values file
#       named in an included file is read against the MAIN document's folder in the lints too, as the
#       Lua filter reads it. Seen through named-unpublished (N144): a key of a values file the
#       document reads is a publication.
# Helpers: helper-3.R (lint_one, lint_fixture, f3_pos, lf_by_rule), helper-3b.R (expect_numerals),
# helper-6d.R (w6d_doc, W6D_E70). ASCII only; every project is a temporary folder.

sr_cons <- function(lines, ext = "qmd") lint_one(lines, rules = "construct", ext = ext)

# exactly one construct finding at the source position of `frag`, under .qmd and .Rmd
expect_construct_at <- function(lines, frag, ctx) {
  want <- f3_pos(lines, frag)
  for (e in c("qmd", "Rmd")) {
    x <- sr_cons(lines, ext = e)
    info <- sprintf("[%s] %s", e, paste(lines, collapse = " / "))
    expect_identical(nrow(x), 1L, info = info)
    if (nrow(x) != 1L) next
    expect_identical(x$context, ctx, info = info)
    expect_identical(x$line, as.integer(want[["line"]]), info = paste("line:", info))
    expect_identical(x$col, as.integer(want[["col"]]), info = paste("col:", info))
  }
}

# ---- A1: a tab before a phrase literal (K10) --------------------------------------------------------

test_that("A1: a brk() phrase construct after a tab is at its column, the tab one character", {
  for (code in c("p <-\tbrk(v, c(2, 5), c(\"few\", \"[1]{.weft-literal} some\", \"many\"))",
                 "\tp <- brk(v, c(2, 5), c(\"few\", \"[1]{.weft-literal} some\", \"many\"))",
                 "p <- brk(v, c(2, 5),\tc(\"few\",\t\"[1]{.weft-literal} some\", \"many\"))")) {
    expect_construct_at(c("Intro.", "", "```{r}", "x <- 1", code, "```"), "[1]{", "phrase")
  }
})

test_that("A1: a lookup() phrase construct after a tab is at its column", {
  doc <- c("```{r}", "z <-\tlookup(c(a = \"top [1]{.weft-literal}\"))", "```")
  expect_construct_at(doc, "[1]{", "phrase")
})

test_that("A1: a phrase numeral after a tab is at its column, the tab one character", {
  expect_numerals(c("```{r}", "y <-\tbrk(. > 5 ~ \"more than 2 sites\")", "```"), "2", ctx = "phrase")
  expect_numerals(c("```{r}", "\tz <- lookup(c(a = \"top 10\"))", "```"), "10", ctx = "phrase")
})

# ---- A2: an escaped newline before a phrase literal --------------------------------------------------

test_that("A2: a phrase construct after an escaped \\n in an earlier string of the call keeps its line", {
  doc <- c("Intro.", "", "```{r}",
           r"{p <- brk(v, c(2, 5), c("a\nb", "[1]{.weft-literal} some", "many"))}",
           "x <- 1", "```")
  expect_construct_at(doc, "[1]{", "phrase")
})

test_that("A2: a phrase construct after an escaped \\n in its own string keeps its line", {
  doc <- c("```{r}", r"{p <- brk(v, c(2, 5), c("few", "a\nb [1]{.weft-literal} some", "many"))}",
           "x <- 1", "```")
  expect_construct_at(doc, "[1]{", "phrase")
})

test_that("A2: a phrase numeral after an escaped \\n keeps its line and column", {
  expect_numerals(c("```{r}", r"{z <- lookup(c(a = "x\ny", b = "top 10"))}", "x <- 1", "```"),
                  "10", ctx = "phrase")
  expect_numerals(c("```{r}", r"{z <- lookup(c(a = "x\n\ny top 10"))}", "x <- 1", "```"),
                  "10", ctx = "phrase")
})

# ---- A3: a header-literal caption below a block-quoted chunk -----------------------------------------

sr_quoted_above <- function(...) {
  c("Intro.", "", "> ```{r}", "> x <- 1", "> y <- 2", "> ```", "", "Middle words.", "", ...)
}

test_that("A3: a construct in a chunk-header fig.cap below a block-quoted chunk is at its real column", {
  doc <- sr_quoted_above("```{r, fig.cap=\"Cap [1]{.weft-literal} here\"}", "plot(1)", "```")
  expect_construct_at(doc, "[1]{", "caption")
})

test_that("A3: a numeral in a chunk-header fig.cap below a block-quoted chunk is at its real column", {
  expect_numerals(sr_quoted_above("```{r, fig.cap=\"In 2019\"}", "plot(1)", "```"), "2019",
                  ctx = "caption")
  # two block-quoted chunks above: a drift would grow with them
  two <- c("> ```{r}", "> a <- 1", "> ```", "", sr_quoted_above("```{r, fig.alt=\"Dots for 12 sites\"}",
                                                                 "plot(1)", "```"))
  expect_numerals(two, "12", ctx = "caption")
})

test_that("A3: a `#|` caption below a block-quoted chunk is at its real column too", {
  doc <- sr_quoted_above("```{r}", "#| fig-cap: \"Depth at 3 sites\"", "plot(1)", "```")
  expect_numerals(doc, "3", ctx = "caption")
})

# ---- B: a values file named in an included file resolves against the main document's folder ----------

SR_BODY <- "The depth is `depth`{.num} and the width `width`{.num}."
SR_BLOCK <- c("````{.weft-values file=\"vals.json\"}", "````")
sr_vals <- function(name) sprintf("{\"weft\":1,\"values\":{\"%s\":{\"t\":\"float\",\"v\":\"1.5\"}}}", name)

# the names named-unpublished reports for main.qmd in a project holding `files`
sr_unpublished <- function(files, env = parent.frame()) {
  x <- lint_fixture(files, rules = NULL, tier = 1:2, env = env)
  x <- lf_by_rule(x, "named-unpublished")
  x <- x[x$file == "main.qmd", , drop = FALSE]
  c("depth", "width")[c(W6D_E70("depth"), W6D_E70("width")) %in% x$message]
}

test_that("B control: a values file named in an included file beside the main document is read", {
  files <- list("main.qmd" = w6d_doc(c(SR_BODY, "", "{{< include part.qmd >}}")),
                "part.qmd" = SR_BLOCK,
                "vals.json" = sr_vals("depth"))
  expect_identical(sr_unpublished(files), "width")
})

test_that("B, I4: a values file named in sub/part.qmd is read from the main document's folder, not sub/", {
  files <- list("main.qmd" = w6d_doc(c(SR_BODY, "", "{{< include sub/part.qmd >}}")),
                "sub/part.qmd" = SR_BLOCK,
                "vals.json" = sr_vals("depth"),      # the file Quarto's filter reads
                "sub/vals.json" = sr_vals("width"))  # the decoy beside the included file
  expect_identical(sr_unpublished(files), "width")
})

test_that("B, I4: at depth two (main -> sub/a.qmd -> sub/b.qmd), the values file is read from the main folder", {
  files <- list("main.qmd" = w6d_doc(c(SR_BODY, "", "{{< include sub/a.qmd >}}")),
                "sub/a.qmd" = c("Part a.", "", "{{< include sub/b.qmd >}}"),
                "sub/b.qmd" = SR_BLOCK,
                "vals.json" = sr_vals("depth"),
                "sub/vals.json" = sr_vals("width"))
  expect_identical(sr_unpublished(files), "width")
})
