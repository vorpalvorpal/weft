# Package E4 (dev/design-e4.md): how a weft() call is found (C5 to C9), where its literal sits (C11), and R code in a
# caption option (C10, T11, a regression test: C10 itself moved into E1). T4, T5, T10, T11.
# Written before the code. No R under R/ was read.

e4l_nums <- function(lines, rule = "numeral", file = "R/a.R") {
  root <- lint_proj(stats::setNames(list(lines), file), weft_yml = "draft: false")
  list(x = lints(root, rules = rule, tier = 1:2), root = root)
}

# ---- T4: calls found --------------------------------------------------------------------------------------

E4_CALLS <- list(
  list("weft::weft(\"Saw 12\")", "12"),
  list("weft:::weft(\"Saw 12\")", "12"),
  list("other::weft(\"Saw 12\")", character()),
  list("weft(x = \"Saw 12\")", "12"),
  list("weft(.envir = e, x = \"Saw 12\")", "12"),
  list("weft(.envir = e, \"Saw 12\")", "12"),
  list("weft(\"Saw 12\", .envir = e)", "12"),
  list("\"Saw 12\" |> weft()", "12", 6L),
  list("\"Saw 12\" %>% weft()", "12"),
  list("weft(c(\"One 12\", \"Two 13\"))", c("12", "13")),
  list("weft(c(a = \"One 12\", b, \"Two 13\"))", c("12", "13"), c(17L, 30L)),
  list("weft(c(c(\"One 12\")))", character()),
  list("weft(paste0(\"Saw \", \"12\"))", character()),
  list("weft(title)", character()),
  list("lapply(c(\"Saw 12\"), weft)", character()),
  list("f <- function() weft(\"Saw 12\")", "12"),
  list("if (FALSE) weft(\"Saw 12\")", "12"),
  list("# weft(\"Saw 12\")", character()),
  list("weft_str(\"Saw 12\")", character()),
  list("lookup(k, c(low = \"below 12\"))", character())
)

test_that("T4 C5 to C7: the calls of a script that are read, and the numerals reported", {
  for (cs in E4_CALLS) {
    r <- e4l_nums(cs[[1]])
    expect_identical(r$x$text, cs[[2]], label = cs[[1]])
    if (length(cs) >= 3L) expect_identical(r$x$col, cs[[3]], label = paste(cs[[1]], "col"))
    if (length(cs[[2]])) expect_true(all(r$x$context == "weft"), label = paste(cs[[1]], "context"))
    # none of these gives a note
    expect_identical(length(attr(r$x, "notes")), 0L, label = paste(cs[[1]], "notes"))
  }
})

test_that("T4 C5: a roxygen example line is a comment, not code", {
  r <- e4l_nums(c("#' @examples", "#' weft(\"Saw 12\")", "f <- function() 1"))
  expect_identical(nrow(r$x), 0L)
})

test_that("T4 C5: a call inside local() or a function body is read", {
  r <- e4l_nums(c("local({", "  weft(\"Saw 12\")", "})"))
  expect_identical(r$x$text, "12")
  expect_identical(r$x$line, 2L)
})

test_that("T4 C7/D6: the literal elements of a c() are read beside other elements, a computed one is skipped", {
  r <- e4l_nums("weft(c(a = \"One 12\", paste0(\"x\", 5), \"Two 13\"))")
  expect_identical(r$x$text, c("12", "13"))
})

test_that("T4 C7: a named element of c() is read as an element of x", {
  r <- e4l_nums("weft(c(first = \"One 12\"))")
  expect_identical(r$x$text, "12")
})

# ---- T5: positions ----------------------------------------------------------------------------------------

test_that("T5 C8/C11: the numeral 12 is found at the character of the script that holds it", {
  cases <- list(
    list("p <- labs(title = weft(\"We found 12 sites\"))", 1L, 34L),
    list("\tw <- weft(\"n 12\")", 1L, 15L),
    list("weft(\"a \\\"q\\\" 12\")", 1L, 15L),
    list("weft(r\"(a \"q\" 12)\")", 1L, 15L),
    list("weft(R\"--[x 12]--\")", 1L, 13L),
    list("weft(r'{x 12}')", 1L, 11L),
    list(c("t <- weft(\"first line", "then 12 sites\")"), 2L, 6L),
    list(paste0("x <- weft(\"", strrep("a", 1200), " 12\")"), 1L, 1213L),
    list("weft(\"caf\\u00e9 12\")", 1L, 17L),
    list("weft(\"café 12\")", 1L, 12L)
  )
  for (cs in cases) {
    r <- e4l_nums(cs[[1]])
    lab <- paste(substr(cs[[1]], 1L, 40L), collapse = " / ")
    expect_identical(nrow(r$x), 1L, label = lab)
    expect_identical(r$x$text, "12", label = lab)
    expect_identical(r$x$line, cs[[2]], label = paste(lab, "line"))
    expect_identical(r$x$col, cs[[3]], label = paste(lab, "col"))
  }
})

test_that("T5 C11: a construct error is placed at the bracket of the span", {
  r <- e4l_nums("weft(\"ok [x]{if='a >'}\")", rule = "construct")
  expect_identical(nrow(r$x), 1L)
  expect_identical(r$x$line, 1L)
  expect_identical(r$x$col, 10L)
})

test_that("T5 C11: the fixture for a long string reads the whole literal (the 1200 characters)", {
  r <- e4l_nums(paste0("x <- weft(\"", strrep("a", 1200), " 12\")"))
  expect_identical(r$x$end_line, 1L)
})

# ---- T10: documents ---------------------------------------------------------------------------------------

e4l_doc <- function(code, ext = "qmd") {
  c("Intro.", "", "```{r}", code, "```")
}
e4l_docnums <- function(code, ext = "qmd", rule = "numeral") {
  doc <- e4l_doc(code)
  list(x = lint_one(doc, rules = rule, ext = ext), doc = doc)
}

test_that("T10 C7/C9: a raw string in a chunk is read, at its exact line and column", {
  r <- e4l_docnums("w <- weft(r\"(We found 12 sites)\")")
  expect_identical(nrow(r$x), 1L)
  expect_identical(r$x$text, "12")
  pos <- f3_pos(r$doc, "12")
  expect_identical(r$x$line, as.integer(pos[["line"]]))
  expect_identical(r$x$col, as.integer(pos[["col"]]))
  expect_identical(r$x$context, "weft")
})

test_that("T10 C8/C9: a literal over the display limit is read in full, at its position", {
  r <- e4l_docnums(paste0("w <- weft(\"", strrep("a", 1200), " 12\")"))
  expect_identical(nrow(r$x), 1L)
  expect_identical(r$x$text, "12")
  expect_identical(r$x$line, 4L)
  expect_identical(r$x$col, 1213L)
})

test_that("T10 C6/C9: a pipe's left-hand side is the argument in a chunk", {
  r <- e4l_docnums("\"Saw 12\" |> weft()")
  expect_identical(r$x$text, "12")
  expect_identical(r$x$line, 4L)
  expect_identical(r$x$col, 6L)
})

test_that("T10 C5/D8: other::weft() is not read in a chunk", {
  r <- e4l_docnums("other::weft(\"Saw 12\")")
  expect_identical(nrow(r$x), 0L)
})

test_that("T10 D6: a c() mixing a literal and a name reads the literal", {
  r <- e4l_docnums("weft(c(a = \"One 12\", b))")
  expect_identical(r$x$text, "12")
})

test_that("T10 C16: weft() in inline R of the prose is not read", {
  x <- lint_one(c("We have `r weft(\"Saw 12\")` here.", ""), rules = "numeral")
  expect_identical(nrow(x), 0L)
})

test_that("T10 C9: the scanner reads the same strings: a raw string's span is listed, context weft", {
  doc <- e4l_doc("weft(r\"([one | # sites]{n='k'})\")")
  path <- withr::local_tempfile(fileext = ".qmd")
  writeLines(doc, path)
  x <- arms(path)
  expect_gt(nrow(x), 0L)
  expect_true(all(x$context == "weft"))
  expect_identical(unique(x$key), "n")
  expect_true(all(x$line == 4L))
})

test_that("T10 C9: the rule that counts constructs and the one that judges numerals read the same strings", {
  # a raw string with a construct error is a construct finding (the construct rule reads it)
  r <- e4l_docnums("weft(r\"(ok [x]{if='a >'})\")", rule = "construct")
  expect_identical(nrow(r$x), 1L)
  expect_identical(r$x$context, "weft")
  expect_identical(r$x$line, 4L)
  expect_identical(r$x$col, 11L)
})

# ---- T11: computed captions (regression; C10 is E1's) -----------------------------------------------------

test_that("T11 C10: a !expr weft() caption holding a span is not a construct error", {
  doc <- c("Intro.", "", "```{r}", "#| label: fig-a",
           "#| fig-cap: !expr weft('Depth at [a site | # sites]{n=\"k\"}')", "plot(1)", "```")
  x <- lint_one(doc, rules = "construct")
  expect_identical(nrow(x), 0L)
})

test_that("T11 C10: a !expr weft() caption with a typed numeral is a numeral finding on the option's line", {
  doc <- c("Intro.", "", "```{r}", "#| label: fig-a", "#| fig-cap: !expr weft('We saw 12 sites')", "plot(1)", "```")
  x <- lint_one(doc, rules = "numeral")
  expect_identical(nrow(x), 1L)
  expect_identical(x$text, "12")
  expect_identical(x$line, 5L)
  expect_identical(x$col, 32L)
  expect_identical(x$context, "weft")
})

test_that("T11 C10: an .Rmd header option fig.cap = weft(...) is read at the header's column", {
  doc <- c("Intro.", "", "```{r fig-a, fig.cap = weft('We saw 12 sites')}", "plot(1)", "```")
  x <- lint_one(doc, rules = "numeral", ext = "Rmd")
  expect_identical(nrow(x), 1L)
  expect_identical(x$text, "12")
  expect_identical(x$line, 3L)
  expect_identical(x$col, 37L)
})

test_that("T11 C10: an !expr written as a quoted YAML scalar is not read", {
  doc <- c("Intro.", "", "```{r}", "#| label: fig-a", "#| fig-cap: !expr \"weft('We saw 12 sites')\"", "plot(1)", "```")
  x <- lint_one(doc, rules = "numeral")
  expect_identical(nrow(x), 0L)
})

test_that("T11 C10: a caption written as a markup string still gives its 1.10.3 error", {
  doc <- c("Intro.", "", "```{r}", "#| label: fig-a", "#| fig-cap: \"Depth at [a site | # sites]{n='k'}\"", "plot(1)", "```")
  x <- lint_one(doc, rules = "construct")
  expect_gte(nrow(x), 1L)
  expect_identical(x$line[[1]], 5L)
})
