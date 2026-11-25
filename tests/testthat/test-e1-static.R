# Package E1 (dev/design-e1.md): the static side (T13; ST1 to ST4). The lints, arms(), the scanner
# and the gate find the literal strings given to weft() with context "weft"; weft_str() is no longer read.

e1s_doc <- function(code, opts = NULL, engine = "r") {
  c("Intro.", "", sprintf("```{%s}", engine), opts, code, "```")
}

e1s_numerals <- function(code, ...) {
  doc <- e1s_doc(code, ...)
  x <- lint_one(doc, rules = "numeral")
  list(x = x, doc = doc)
}

test_that("T13 ST1/ST3: a typed numeral in weft('...') is a numeral finding at its file position, context 'weft'", {
  code <- "x <- weft(\"We found 12 sites\")"
  r <- e1s_numerals(code)
  expect_identical(nrow(r$x), 1L)
  expect_identical(r$x$text, "12")
  expect_identical(r$x$context, "weft")
  pos <- f3_pos(r$doc, "12")
  expect_identical(r$x$line, as.integer(pos[["line"]]))
  expect_identical(r$x$col, as.integer(pos[["col"]]))
})

test_that("T13 ST1/ST2: the same through weft::weft(), weft(x = ), .envir before or after the string, and c() of strings", {
  codes <- c(
    "x <- weft::weft(\"We found 12 sites\")",
    "x <- weft(x = \"We found 12 sites\")",
    "x <- weft(\"We found 12 sites\", .envir = e)",
    "x <- weft(.envir = e, \"We found 12 sites\")"
  )
  for (code in codes) {
    r <- e1s_numerals(code)
    expect_identical(r$x$text, "12", label = code)
    expect_identical(r$x$context, "weft", label = code)
    pos <- f3_pos(r$doc, "12")
    expect_identical(r$x$col, as.integer(pos[["col"]]), label = code)
  }
  r <- e1s_numerals("x <- weft(c(\"We found 12 sites\", \"and 45 more\"))")
  expect_identical(r$x$text, c("12", "45"))
  expect_identical(r$x$context, c("weft", "weft"))
})

test_that("T13 ST1: weft_str() is no longer read", {
  r <- e1s_numerals("x <- weft_str(\"We found 12 sites\")")
  expect_identical(nrow(r$x), 0L)
})

test_that("T13 ST1: a weft() string in a chunk with eval: false, or another engine, is not read", {
  off <- e1s_numerals("x <- weft(\"We found 12 sites\")", opts = "#| eval: false")
  expect_identical(nrow(off$x), 0L)
  py <- e1s_numerals("x = weft(\"We found 12 sites\")", engine = "python")
  expect_identical(nrow(py$x), 0L)
})

test_that("T13 ST3: the scanner's rows carry context 'weft'", {
  doc <- e1s_doc("x <- weft(\"A `r 5`{.num} string\")")
  path <- tempfile("weft-e1s-", fileext = ".qmd")
  writeLines(doc, path)
  withr::defer(unlink(path))
  x <- weft:::scan_file(path)
  expect_true("weft" %in% x$context)
  expect_false("weft_str" %in% x$context)
  y <- x[x$context == "weft", ]
  expect_identical(y$line, 4L)
})

test_that("T13 ST2: the scanner reads the argument R matches to x, whatever the named arguments", {
  doc <- c("```{r}", "x <- weft(.envir = e, \"A `r 5`{.num} string\")", "y <- weft(x = \"B `r 6`{.num} string\", .envir = e)", "```")
  path <- tempfile("weft-e1s-", fileext = ".qmd")
  writeLines(doc, path)
  withr::defer(unlink(path))
  x <- weft:::scan_file(path)
  y <- x[x$context == "weft", ]
  expect_identical(sort(y$line), c(2L, 3L))
})

test_that("T13 ST3: arms() lists an n span of a weft() string with context 'weft'", {
  doc <- c("```{r}", "k <- 3", "x <- weft(\"Found [a site | # sites]{n='k'}\")", "```")
  path <- tempfile("weft-e1s-", fileext = ".Rmd")
  writeLines(doc, path)
  withr::defer(unlink(path))
  x <- arms(path)
  expect_true("weft" %in% x$context)
  expect_false("weft_str" %in% x$context)
  expect_identical(unique(x$key[x$context == "weft"]), "n")
})

test_that("T13 ST3: the gate counts the constructs of a weft() string, with the context renamed", {
  doc <- c("```{r fig-one}", "x <- weft(\"A `r five`{.num} string\")", "```")
  x <- weft:::count_constructs(read_src(doc, ext = "qmd"))
  expect_identical(nrow(x), 1L)
  expect_identical(x$line, 2L)
  # weft_str() strings are not counted
  y <- weft:::count_constructs(read_src(c("```{r fig-one}", "x <- weft_str(\"A `r five`{.num} string\")", "```"), ext = "qmd"))
  expect_identical(nrow(y), 0L)
})

test_that("T13 ST3: a construct finding inside a weft() string has context 'weft'", {
  doc <- c("Intro.", "", "```{r}", "x <- weft(\"over [1]{.weft-literal} years\")", "```")
  x <- lint_one(doc, rules = "construct")
  expect_identical(x$context, "weft")
})
