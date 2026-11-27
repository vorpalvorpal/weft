# Lint and filter of the rich targets (stage H3 of dev/design-html-target.md: RS3 with E111, RS4).
# Helpers used: helper-3.R (lint_one, lf_by_rule), helper-3c.R (c3_para, c3_chunk), helper-filter.R (filter_md).
# ASCII only.

e111 <- function(fn, target, what) {
  sprintf(paste0("The value in prose is formatted with `%s(target = \"%s\")`, which writes %s; a document ",
                 "shows its marks or drops its tags (rule 5.6.4)."), fn, target, what)
}

test_that("RS3, E111: value-format finds fmt_sci(target = \"html\") in prose, once, tier 2", {
  for (ext in c("qmd", "Rmd")) {
    x <- lint_one(c3_para("The rate is `r fmt_sci(x, target = \"html\")`."), rules = "value-format", ext = ext)
    r <- lf_by_rule(x, "value-format")
    expect_identical(nrow(r), 1L, label = ext)
    expect_identical(r$tier, 2L)
    expect_identical(r$spec, "5.6.4")
    expect_identical(r$message, e111("fmt_sci", "html", "HTML"))
    expect_match(r$hint, "`r x`{.num}", fixed = TRUE)
  }
})

test_that("RS3, E111: the same for target = \"marquee\"", {
  x <- lint_one(c3_para("The rate is `r fmt_sci(x, target = \"marquee\")`."), rules = "value-format")
  r <- lf_by_rule(x, "value-format")
  expect_identical(nrow(r), 1L)
  expect_identical(r$message, e111("fmt_sci", "marquee", "marquee text"))
})

test_that("RS3: nothing is found for target = \"plain\" or \"markdown\", or for a call inside a chunk", {
  x <- lint_one(c3_para("The rate is `r fmt_sci(x, target = \"plain\")`."), rules = "value-format")
  expect_identical(nrow(lf_by_rule(x, "value-format")), 0L)
  x <- lint_one(c3_para("The rate is `r fmt_sci(x, target = \"markdown\")`."), rules = "value-format")
  expect_identical(nrow(lf_by_rule(x, "value-format")), 0L)
  x <- lint_one(c(c3_para("Intro."), c3_chunk("lab <- fmt_sci(x, target = \"html\")")), rules = "value-format")
  expect_identical(nrow(lf_by_rule(x, "value-format")), 0L)
})

test_that("RS3: a format() of a weft object with target = \"html\" in prose is already found by the format() case", {
  x <- lint_one(c3_para("The rate is `r format(w, target = \"html\")`."), rules = "value-format")
  expect_identical(nrow(lf_by_rule(x, "value-format")), 1L)
})

# ---- RS4: weft-check.lua reads raw HTML for markers -------------------------------------------------------------

rs4_doc <- function(cell) c("Before.", "", "```{=html}", cell, "```", "", "After.")

test_that("RS4, 2.5.3: a failure marker in a raw HTML block fails the filter, written escaped or not", {
  for (cell in c("<td>&lt;&lt;weft: no value, line 4&gt;&gt;</td>", "<td><<weft: no value, line 4>></td>")) {
    r <- filter_md(rs4_doc(cell), to = "html")
    expect_identical(r$status, 1L, label = cell)
  }
})

test_that("RS4: a raw HTML block with no marker reports nothing", {
  r <- filter_md(rs4_doc("<td>5</td>"), to = "html")
  expect_identical(r$status, 0L)
})

test_that("RS4: a raw inline HTML span with a marker fails too", {
  r <- filter_md(c("A `<b>&lt;&lt;weft: no value, line 4&gt;&gt;</b>`{=html} here."), to = "html")
  expect_identical(r$status, 1L)
})
