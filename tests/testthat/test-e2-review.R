# Package E2, fix round (dev/review-e2.md, G1 to G6): tests written from the rulings, not from the code.

e2_py_plain <- function(res) trimws(res$filtered$output)

# ---- G1: auto() is fetched under names_from python ---------------------------------------------------

test_that("G1: names_from python in _weft.yml: a name auto() publishes reaches the filter", {
  res <- k5(c(pychunk("p1", c("from weft import auto", "auto()", "n = 3"), "include=FALSE"),
              "Uses `n`{.num}."),
            weft_yml = "names_from: python")
  expect_false(res$failed, label = res$message)
  out <- filter_md(res$text, name = "doc.Rmd", to = "plain")
  expect_identical(out$status, 0L)
  expect_true(grepl("Uses 3.", out$output, fixed = TRUE))
})

# ---- G2: front matter in block form is left for the filter -------------------------------------------

test_that("G2: an abstract in block form holding a named value is the filter's, not R's global read", {
  withr::defer(if (exists("n", envir = globalenv(), inherits = FALSE)) rm("n", envir = globalenv()))
  assign("n", 2, envir = globalenv())
  res <- e2_knit_in(c(e2_chunk("calc", "n <- 3L"), "End."), globalenv(),
                    front = c("abstract: |", "  Found `n`{.num} sites."))
  expect_false(res$failed, label = if (res$failed) conditionMessage(res$error) else "")
  expect_true("n" %in% unlist(b6_block_names(b6_blocks(res$text))))
  out <- filter_md(res$text, name = "doc.Rmd", to = "html", args = "-s")
  expect_true(grepl("Found 3 sites", out$output, fixed = TRUE))
})

# ---- G3: a governor in an unresolved caption publishes no names ------------------------------------

test_that("G3: draft mode, cached chunk, caption with a governor: the secret is in no values block", {
  res <- b6_knit(c(e2_chunk("s", "secret <- \"hunter2\""),
                   "```{r fig-c, cache=TRUE, echo=FALSE, fig.cap='[Shown]{if=\"nchar(secret) > 0\"}'}",
                   "plot(1)", "```", "", "End."),
                 draft = TRUE)
  b6_expect_knitted(res)
  expect_false("secret" %in% e2_names(res))
  expect_false(any(grepl("hunter2", res$text, fixed = TRUE)))
  # ambiguity: "the caption is marked" is read as the governor span still being in the caption as written
  expect_true(any(grepl("[Shown]{if=", res$text, fixed = TRUE)))
})

# ---- G4: caching set at run time -------------------------------------------------------------------

test_that("G4: knitr::opts_chunk$set(cache = TRUE): a named value in the caption has its name published", {
  lines <- c(e2_chunk("opts", "knitr::opts_chunk$set(cache = TRUE)"),
             e2_chunk("dd", "d <- 4L"),
             "```{r fig-d, echo=FALSE, fig.cap='Depth `d`{.num}'}", "plot(1)", "```", "", "End.")
  res <- e2_render(lines)
  b6_expect_knitted(res)
  expect_true("d" %in% e2_names(res))
  expect_true(any(grepl("Depth `d`{.num}", res$text, fixed = TRUE)))
  expect_true(grepl("Depth 4", res$filtered$output, fixed = TRUE))
})

# ---- G5: the stale-session check ---------------------------------------------------------------------

test_that("G5: the document set the name above the read, to the value the session held: no failure", {
  e <- new.env(parent = globalenv())
  e$ok <- TRUE
  res <- e2_knit_in(c(e2_chunk("a", "ok <- TRUE"), "Read: `ok`{.val}.", "", e2_chunk("b", "ok <- FALSE"), "End."), e)
  expect_false(res$failed, label = if (res$failed) conditionMessage(res$error) else "")
  expect_identical(nrow(res$knit$failures), 0L)
})

test_that("G5 control: a name not set above the read, held from before the render, is still noted and fails", {
  e <- new.env(parent = globalenv())
  e$n <- 1L
  res <- e2_knit_in(E2_STALE(), e)
  expect_true(res$failed)
  expect_identical(res$knit$failures$kind, "no value")
  expect_match(e2_fail_text(res), "was read above the code that sets it in this render", fixed = TRUE)
})

# ---- G6: R does not publish a function --------------------------------------------------------------

test_that("G6: an R function f and a guest's put(f=3) below the read: no 'different values', the filter prints 3", {
  res <- e2_py(c(e2_chunk("r1", "f <- function() 1"),
                 "Uses `f`{.num}.", "",
                 pychunk("p1", c("from weft import put", "put(f=3)"), "include=FALSE")))
  expect_false(res$failed, label = res$message)
  expect_false("f" %in% e2_names(res)[seq_len(max(0L, length(e2_names(res)) - 1L))])
  expect_identical(res$filtered$status, 0L)
  expect_false(grepl("different values", res$filtered$stderr, fixed = TRUE))
  expect_true(grepl("Uses 3.", e2_out(res), fixed = TRUE))
})

test_that("G6: an R function f and no guest: the filter fails 'no value' and R publishes no record for f", {
  res <- e2_render(c(e2_chunk("r1", "f <- function() 1"), "Uses `f`{.num}.", "", "End."))
  b6_expect_knitted(res)
  expect_false("f" %in% e2_names(res))
  expect_identical(res$filtered$status, 1L)
  expect_true(grepl(fm_msg$E10("f"), res$filtered$stderr, fixed = TRUE))
})
