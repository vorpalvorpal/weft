# Package E1 fix round (dev/review-e1.md, findings F1 to F13): tests written from the review's
# rulings and dev/design-e1.md, before the fixes. Non-ASCII is written as \u escapes:
#   no-break space.
#
# Not tested: F9 (documentation only: `pdf()` and superscripts).

e1r_plain <- function(x) as.character(weft(x))
e1r_md <- function(x) unname(format(weft(x), target = "markdown"))

e1r_unit_yml <- c("units:", "  zze1rv:", "    is: 201.168 m", "    symbol: FF")

# a project root in a temporary directory with the working directory moved into it
e1r_root <- function(yml = NULL, env = parent.frame()) {
  root <- normalizePath(withr::local_tempdir(.local_envir = env))
  if (!is.null(yml)) writeLines(yml, file.path(root, "_weft.yml"))
  root
}

# ---- F1: a root with no _weft.yml never sees another project's units ---------------------------

test_that("F1: project A's units: are not in force in project B, which has no _weft.yml", {
  weft:::string_config_reset()
  a <- e1r_root(e1r_unit_yml)
  b <- e1r_root(NULL)
  withr::local_dir(a)
  expect_identical(as.character(weft("`r u(3, zze1rv)`{.num}")), "3\u00a0FF")
  setwd(b)
  # B has the default units: the unit is unknown there
  expect_error(weft("`r u(3, zze1rv)`{.num}"))
  # and A's file applies again on going back
  setwd(a)
  expect_identical(as.character(weft("`r u(3, zze1rv)`{.num}")), "3\u00a0FF")
})

test_that("F1: fmt_*() outside a knit in B do not use A's units either", {
  weft:::string_config_reset()
  a <- e1r_root(e1r_unit_yml)
  b <- e1r_root(NULL)
  withr::local_dir(a)
  expect_no_error(fmt_num(u(3, zze1rv), target = "plain"))
  setwd(b)
  expect_error(fmt_num(u(3, zze1rv), target = "plain"))
})

test_that("F1: a knit's front-matter units are not left in force for a root with no _weft.yml", {
  weft:::string_config_reset()
  lines <- c("```{r a, results='asis', echo=FALSE}",
             "cat('KNIT:', as.character(weft::weft('`r u(3, zze1rv)`{.num}')), '\\n')", "```", "")
  res <- render_rmd(lines, front = c("weft:", "  units:", "    zze1rv:", "      is: 201.168 m",
                                     "      symbol: FF"),
                    format = "knit", in_process = TRUE)
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "KNIT: 3\u00a0FF", fixed = TRUE)
  b <- e1r_root(NULL)
  withr::local_dir(b)
  expect_error(weft("`r u(3, zze1rv)`{.num}"))
})

# ---- F2: Python's weft_str() evaluates in a fresh environment ----------------------------------

test_that("F2: Python's weft_str() sees the knit's x (and a missing result is None)", {
  res <- k5(c("```{r setx, include=FALSE}", "x <- 3", "na1 <- NA_character_", "```", "",
              pychunk("pyx", c("from weft import weft_str",
                               "print(weft_str('[a site | # sites]{n=\"x\"}'))"),
                      "results='asis'"),
              pychunk("pyna", c("from weft import weft_str",
                                "print(weft_str(None) is None)"),
                      "results='asis'")))
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "3 sites", fixed = TRUE)
  # reticulate hands an R NA_character_ to Python as the string "NA", so the missing case is
  # Python's None itself: it goes in as NA and comes back as None, not the string "NA"
  expect_match(res$md, "True", fixed = TRUE)
})

# ---- F3: R/plain.R is ASCII --------------------------------------------------------------------

test_that("F3: R/plain.R holds only ASCII characters", {
  p <- test_path("../../R/plain.R")
  skip_if_not(file.exists(p), "the package source is not available")
  bytes <- readBin(p, "raw", file.size(p))
  expect_false(any(as.integer(bytes) > 127L))
})

# ---- F4, F5, F12: the lints read computed captions and header options --------------------------

e1r_five <- function(doc, ext = "qmd") {
  x <- lint_one(doc, rules = "numeral", ext = ext)
  expect_true("5" %in% x$text, label = "a numeral finding for 5")
  r <- x[x$text == "5", ]
  expect_identical(nrow(r), 1L)
  pos <- f3_pos(doc, "5")
  expect_identical(r$line, as.integer(pos[["line"]]))
  expect_identical(r$col, as.integer(pos[["col"]]))
  invisible(r)
}

test_that("F4: a `fig-cap: !expr |` block scalar is read as code, and its weft() literal is linted", {
  doc <- c("Intro.", "", "```{r}", "#| fig-cap: !expr |", "#|   weft(\"Depth at 5 sites\")",
           "x <- 1", "```")
  e1r_five(doc)
})

test_that("F5: a weft() literal in a one-line `!expr` caption is linted with its position", {
  doc <- c("Intro.", "", "```{r}", "#| fig-cap: !expr weft(\"Depth at 5 sites\")", "x <- 1", "```")
  e1r_five(doc)
})

test_that("F5: a header option fig.cap = weft(...) in an .Rmd is linted with its position", {
  doc <- c("Intro.", "", "```{r, fig.cap = weft(\"Depth at 5 sites\")}", "x <- 1", "```")
  e1r_five(doc, ext = "Rmd")
})

test_that("F12: blanks after the closing brace of a chunk header do not stop the lint reading it", {
  doc <- c("Intro.", "", "```{r, fig.cap = weft(\"Depth at 5 sites\")}   ", "x <- 1", "```")
  e1r_five(doc, ext = "Rmd")
  doc2 <- c("Intro.", "", "```{r, fig.cap = weft(\"Depth at 5 sites\")}\t ", "x <- 1", "```")
  e1r_five(doc2, ext = "Rmd")
})

# ---- F6: emphasis closing inside a longer run (follow Pandoc) ----------------------------------

test_that("F6: a closing run of three closes an inner and an outer emphasis together", {
  rows <- list(
    list("**Total for *E. coli***", "Total for E. coli"),
    list("***Eucalyptus* sp.**", "Eucalyptus sp."),
    list("*a **b***", "a b"),
    list("**a *b* c**", "a b c"),
    list("***a** b*", "a b"))
  for (r in rows) {
    expect_identical(e1r_plain(r[[1]]), r[[2]], label = r[[1]])
    expect_identical(e1r_md(r[[1]]), r[[1]], label = r[[1]])
  }
})

# ---- F7: code spans and math are opaque to the closer search -----------------------------------

test_that("F7: an emphasis closer inside a code span or math is not a closer", {
  expect_identical(e1r_plain("*see `x*y`*"), "see x*y")
  expect_identical(e1r_plain("*a $x*y$ b*"), "a $x*y$ b")
  expect_identical(e1r_plain("*a $x*y$*"), "a $x*y$")
})

# ---- F8: [[<-, is.na<- and [[ behave as for a character vector ---------------------------------

test_that("F8: [[<- past the end extends the markdown with the new text", {
  w <- weft(c("*a*", "b"))
  w[[3]] <- "c"
  expect_identical(unname(format(w, target = "markdown")), c("*a*", "b", "c"))
  expect_identical(length(w), 3L)
  expect_identical(as.character(w)[3], "c")
})

test_that("F8: is.na<- sets the element to NA", {
  w <- weft(c("*a*", "b"))
  is.na(w) <- 1
  expect_identical(is.na(w), c(TRUE, FALSE))
})

test_that("F8: w[[5]] past the end is base's subscript-out-of-bounds error", {
  w <- weft(c("*a*", "b"))
  expect_error(w[[5]], "subscript out of bounds")
})

# ---- F10: the conformance tables use the defaults only -----------------------------------------

test_that("F10: conformance_write() gives the same tables with a _weft.yml in the working directory", {
  weft:::string_config_reset()
  clean <- file.path(withr::local_tempdir(), "clean")
  weft:::conformance_write(clean)
  proj <- e1r_root(c("digits: 5", e1r_unit_yml))
  withr::local_dir(proj)
  weft:::string_config_reset()
  dirty <- file.path(withr::local_tempdir(), "dirty")
  weft:::conformance_write(dirty)
  expect_setequal(list.files(dirty), list.files(clean))
  for (f in list.files(clean)) {
    expect_identical(readBin(file.path(dirty, f), "raw", 1e8),
                     readBin(file.path(clean, f), "raw", 1e8), label = f)
  }
  # ambiguity: weft:::conf_with_config()'s signature is not in the review; tested through
  # conformance_write(), which builds on it
})

# ---- F11: a caption !expr of several expressions uses the last value ---------------------------

test_that("F11 (Quarto): a `!expr` caption of two expressions gives the weft caption's text", {
  skip_if_no_quarto()
  lines <- c("---", "title: \"t\"", "engine: knitr", "format: html", "---", "",
             "```{r setup, include=FALSE}", "weft::weft_setup()", "```", "",
             "```{r fig-q, echo=FALSE}",
             "#| fig-cap: !expr a <- 1; weft::weft(\"Depth at *many* sites\")",
             "plot(1)", "```", "")
  r <- qmd_html(lines)
  expect_false(r$failed, label = r$message)
  expect_match(r$html, "<em>many</em>", fixed = TRUE)
})

# ---- F13: two readings follow Pandoc -----------------------------------------------------------

test_that("F13: a backslash-space in a superscript is a no-break space", {
  # ambiguity: the plain form has no Unicode superscript for `a` or U+00A0, so it is ^(...)
  expect_identical(e1r_plain("x^a\\ b^"), "x^(a b)")
})

test_that("F13: a code span's surrounding spaces are all trimmed", {
  expect_identical(e1r_plain("` a `"), "a")
  expect_identical(e1r_plain("`  a  `"), "a")
  expect_identical(e1r_plain("x `  a b  ` y"), "x a b y")
})
