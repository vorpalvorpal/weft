# Package E2 (dev/design-e2.md), T3, T4, T5, T9: what R leaves for the filter, what the hooks publish, text a chunk
# prints, and a binding from before the render (BN2, BN5, BN11, TR1, TR2, PS1, D7, D8, D15).

# ---- T3: left for the filter -----------------------------------------------------------------

test_that("T3 BN5 (a): above its value a name is left, published after the chunk, and the filter prints it", {
  lines <- c("In summary, `n`{.count} sites.", "", e2_chunk("calc", "n <- 12L"), "End.")
  res <- e2_render(lines)
  b6_expect_knitted(res)
  expect_true(any(grepl("In summary, `n`{.count} sites.", res$text, fixed = TRUE)))
  expect_length(res$blocks, 1L)
  b <- res$blocks[[1]]
  expect_identical(names(b$block$values), "n")
  expect_identical(b6_core(b$block$values$n), b6_e_int("12"))
  expect_true(b6_line(res$text, "In summary") < b$open)
  expect_true(b$close < b6_line(res$text, "End."))
  expect_true(startsWith(trimws(res$filtered$output), "In summary, 12 sites."))
})

test_that("T3 BN5, M6: a name never bound is left, publishes nothing, and the filter fails it with the new hint", {
  res <- e2_render(c("Uses `zz`{.num}.", "", "End."))
  b6_expect_knitted(res)
  expect_true(any(grepl("`zz`{.num}", res$text, fixed = TRUE)))
  expect_length(res$blocks, 0L)
  expect_identical(res$filtered$status, 1L)
  expect_true(grepl(fm_msg$E10("zz"), res$filtered$stderr, fixed = TRUE))
  expect_true(grepl(fm_msg$E10_hint("zz"), res$filtered$stderr, fixed = TRUE))
  expect_true(grepl("pass text an R chunk prints through weft()", res$filtered$stderr, fixed = TRUE))
  expect_false(grepl("weft_put", res$filtered$stderr, fixed = TRUE))
})

test_that("T3 BN2, D1: base R and packages are not read by name; `r pi` still is", {
  res <- b6_knit(c("A: `pi`{.num}", "", "B: `letters`{.and}", "", "C: `rivers`{.num}", "", "D: `r pi`{.num}"))
  b6_expect_knitted(res)
  expect_true("A: `pi`{.num}" %in% res$text)
  expect_true("B: `letters`{.and}" %in% res$text)
  expect_true("C: `rivers`{.num}" %in% res$text)
  expect_true("D: 3.1" %in% res$text)
  expect_length(res$blocks, 0L)
})

test_that("T3 BN2, D2: a function is not a value: it is left, and published as an error record the filter fails", {
  res <- e2_render(c(e2_chunk("calc", "f <- function() 1"), "Uses `f`{.num}.", "", "End."))
  b6_expect_knitted(res)
  expect_true(any(grepl("`f`{.num}", res$text, fixed = TRUE)))
  expect_length(res$blocks, 1L)
  rec <- res$blocks[[1]]$block$values$f
  expect_identical(rec$t, "error")
  expect_match(rec$why, "is an R function, which weft does not publish", fixed = TRUE)
  expect_identical(res$filtered$status, 1L)
  expect_true(grepl("`f`", res$filtered$stderr, fixed = TRUE))
})

test_that("T3 TR2, 1.12.7: a name used above and republished with a new value below fails in the filter with several values", {
  res <- e2_render(c("Uses `n`{.num}.", "", e2_chunk("a", "n <- 1L"), "Middle.", "", e2_chunk("b", "n <- 2L"), "End."))
  b6_expect_knitted(res)
  expect_length(res$blocks, 2L)
  expect_identical(b6_core(res$blocks[[1]]$block$values$n), b6_e_int("1"))
  expect_identical(b6_core(res$blocks[[2]]$block$values$n), b6_e_int("2"))
  expect_identical(res$filtered$status, 1L)
})

test_that("T3 BN1: nothing is published for a name R reads, however often it is used", {
  res <- b6_knit(c(e2_chunk("calc", "n <- 3L"), "One `n`{.num}.", "", "Two `n`{.num}."))
  b6_expect_knitted(res)
  expect_length(res$blocks, 0L)
})

# ---- T4: what R publishes ------------------------------------------------------------------------

test_that("T4 TR1, D7: the leak: a name only in a prose governor is not written into the block", {
  res <- e2_render(c(e2_chunk("calc", "secret <- 'hunter2'", "n <- 3L"),
                     "[shown]{if='nchar(secret) > 0'} and `n`{.num}.", "", "End."),
                   front = "subtitle: \"Count `n`{.num}\"", to = "html", args = "-s")
  b6_expect_knitted(res)
  expect_length(res$blocks, 1L)
  expect_identical(names(res$blocks[[1]]$block$values), "n")
  expect_false(any(grepl("hunter2", res$text, fixed = TRUE)))
  expect_true(grepl("Count 3", res$filtered$output, fixed = TRUE))
})

test_that("T4 TR1: a governor in prose is never published", {
  res <- b6_knit(c(e2_chunk("calc", "kq <- 3L", "unused_q <- 1"), "Found [one | many]{n='kq'} sites."))
  b6_expect_knitted(res)
  expect_length(res$blocks, 0L)
  expect_true("Found many sites." %in% res$text)
})

test_that("T4 BN6: a front-matter name is the filter's: in a block scalar, a plain scalar and an end metadata block", {
  chunk_n <- e2_chunk("calc", "n <- 3L")
  a <- e2_render(c(chunk_n, "Body."), front = c("abstract: |", "  Found `n`{.num} sites."),
                  to = "html", args = "-s")
  b6_expect_knitted(a)
  expect_true(any(grepl("`n`{.num}", a$text, fixed = TRUE)))
  expect_identical(e2_names(a), "n")
  expect_true(grepl("Found 3 sites", a$filtered$output, fixed = TRUE))
  t <- e2_render(c(chunk_n, "Body."), front = "title: \"Sites `n`{.num}\"",
                  to = "html", args = "-s", drop_default_title = TRUE)
  expect_identical(e2_names(t), "n")
  expect_true(grepl("Sites 3", t$filtered$output, fixed = TRUE))
  e <- e2_render(c(chunk_n, "Body.", "", "---", "abstract: \"Late `n`{.num}\"", "---"),
                  to = "html", args = "-s")
  expect_identical(e2_names(e), "n")
  expect_true(grepl("Late 3", e$filtered$output, fixed = TRUE))
})

test_that("T4 TR1, D6: a caption of a cached chunk is the filter's: no error, kept as written, name published", {
  cached <- c("```{r fig-a, cache=TRUE, fig.cap = 'Depth `depth`{.num} m', echo=FALSE}", "depth <- 2.5", "plot(1)", "```")
  res <- b6_knit(c(cached, "", "End."))
  expect_false(isTRUE(res$failed) && grepl("construct", res$message), label = res$message)
  expect_true(any(grepl("Depth `depth`{.num} m", res$text, fixed = TRUE)))
  expect_true("depth" %in% e2_names(res))
})

test_that("T4 TR1, D6: the same caption on a chunk that runs uncached is read by R, and not published", {
  plain <- c("```{r fig-a, fig.cap = 'Depth `depth`{.num} m', echo=FALSE}", "depth <- 2.5", "plot(1)", "```")
  res <- b6_knit(c(plain, "", "End."))
  b6_expect_knitted(res)
  expect_true(any(grepl("Depth 2.5 m", res$text, fixed = TRUE)))
  expect_false("depth" %in% e2_names(res))
})

test_that("T4 D8: there is no gate: a bare named value in a cached chunk's caption has its name published", {
  cached <- c("```{r fig-a, cache=TRUE, fig.cap = 'Flag `flag`{.num}', echo=FALSE}", "flag <- 3L", "plot(1)", "```")
  res <- b6_knit(c(cached, "", "End."))
  expect_true("flag" %in% e2_names(res))
})

test_that("T4 TR5, D8: a document with no named value and no span in a caption writes no block, byte for byte as before", {
  res <- b6_knit(c(
    e2_chunk("calc", "depth <- 3.14159"),
    "Depth was `r depth`{.num digits=\"2\"} m.", "",
    "A second paragraph, with `inline`.", "",
    "```{r shown}", "1 + 1", "```", "",
    "End."
  ))
  b6_expect_knitted(res)
  expect_length(res$blocks, 0L)
  got <- readLines(file.path(res$dir, "doc.md"), warn = FALSE)
  expect_identical(got, c("---", "title: \"t\"", "---", "", "", "", "", "",
                          "Depth was 3.14 m.", "",
                          "A second paragraph, with `inline`.", "", "",
                          "``` r", "1 + 1", "```", "", "```", "## [1] 2", "```", "", "End."))
})

test_that("T4 TR2: change detection: a front-matter name is republished only when its value changes", {
  res <- b6_knit(c(e2_chunk("a", "n <- 1L"), "P1.", "", e2_chunk("b", "n <- 1L"), "P2.", "",
                   e2_chunk("c", "n <- 2L"), "P3."), front = "subtitle: \"`n`{.num}\"")
  b6_expect_knitted(res)
  expect_length(res$blocks, 2L)
  expect_identical(b6_core(res$blocks[[1]]$block$values$n), b6_e_int("1"))
  expect_identical(b6_core(res$blocks[[2]]$block$values$n), b6_e_int("2"))
})

test_that("T4 TR5: a knitr document all of whose named values R reads writes no block", {
  res <- b6_knit(c(e2_chunk("calc", "n <- 3L"), "Uses `n`{.num}."))
  b6_expect_knitted(res)
  expect_length(res$blocks, 0L)
  expect_false(any(grepl("weft-values", res$text, fixed = TRUE)))
})

# ---- T5: text a chunk prints -----------------------------------------------------------------------

test_that("T5 PS1, D9: a named value in text cat() prints is not read, not published, and fails in the filter with M6", {
  res <- e2_render(c(e2_chunk("calc", "n <- 3L"),
                     "```{r, results='asis', echo=FALSE}", "cat(\"We sampled `n`{.num} sites.\\n\")", "```", ""))
  b6_expect_knitted(res)
  expect_true(any(grepl("We sampled `n`{.num} sites.", res$text, fixed = TRUE)))
  expect_false("n" %in% e2_names(res))
  expect_identical(res$filtered$status, 1L)
  expect_true(grepl(fm_msg$E10("n"), res$filtered$stderr, fixed = TRUE))
  expect_true(grepl("through weft()", res$filtered$stderr, fixed = TRUE))
})

test_that("T5 PS1, E1 WS2: the weft() route gives each line of a loop its own value, with no block", {
  res <- b6_knit(c("```{r, results='asis', echo=FALSE}",
                   "for (n in 2:4) cat(format(weft::weft(\"Site `n`{.num}.\"), target = \"markdown\"), \"\\n\")",
                   "```", ""))
  b6_expect_knitted(res)
  for (l in c("Site 2.", "Site 3.", "Site 4.")) expect_true(any(grepl(l, res$text, fixed = TRUE)), label = l)
  expect_length(res$blocks, 0L)
})

test_that("T5 BN9: a chunk whose value is a weft object reads the name in it", {
  res <- b6_knit(c("```{r, echo=FALSE}", "m <- 1.25", "weft::weft(\"Mean `m`{.num}\")", "```", ""))
  b6_expect_knitted(res)
  expect_true(any(grepl("Mean 1.3", res$text, fixed = TRUE)))
})

# ---- T9: a binding from before the render ---------------------------------------------------------

E2_STALE <- function(assign = TRUE) {
  c("Above: `n`{.count}.", "", if (assign) e2_chunk("calc", "n <- 12L"), "Below.")
}

test_that("T9 BN11, M3: a name read above the code that sets it, from a value the session held, fails the knit", {
  e <- new.env(parent = globalenv())
  e$n <- 1L
  res <- e2_knit_in(E2_STALE(), e)
  expect_true(res$failed)
  f <- res$knit$failures
  expect_identical(nrow(f), 1L)
  expect_identical(f$kind, "no value")
  expect_identical(f$line, res$offset + 1L)
  expect_match(e2_fail_text(res),
               "`n` was read above the code that sets it in this render, from a value the R session held before the render began (rule 1.12.12).",
               fixed = TRUE)
})

test_that("T9 BN11, D15: in draft mode the knit prints the held value there and lists the failure", {
  e <- new.env(parent = globalenv())
  e$n <- 1L
  res <- e2_knit_in(E2_STALE(), e, draft = TRUE)
  expect_false(res$failed)
  expect_true("Above: one." %in% res$text)
  expect_identical(nrow(res$knit$failures), 1L)
  expect_identical(res$knit$failures$kind, "no value")
})

test_that("T9 BN11: without a chunk that sets the name later, the held value is the document's: no failure", {
  e <- new.env(parent = globalenv())
  e$n <- 1L
  res <- e2_knit_in(E2_STALE(assign = FALSE), e)
  expect_false(res$failed)
  expect_true("Above: one." %in% res$text)
  expect_identical(nrow(res$knit$failures), 0L)
})

test_that("T9 BN11: inline R is not covered: `r n` above the assigning chunk is no failure", {
  e <- new.env(parent = globalenv())
  e$n <- 1L
  res <- e2_knit_in(c("Above: `r n`{.count}.", "", e2_chunk("calc", "n <- 12L"), "Below."), e)
  expect_false(res$failed)
  expect_true("Above: one." %in% res$text)
})

# rehearse() runs each case in its own R process: run this alone
test_that("T9 BN11: a rehearse() of the document runs in its own environment: no M3", {
  doc <- c("---", "title: \"t\"", "params:", "  k: 1", "---", "",
           "```{r setup, include=FALSE}", "weft::weft_setup()", "```", "",
           "Above: `n`{.count}.", "", "```{r}", "n <- params$k", "```", "", "Below.", "")
  path <- e1_write(doc, "stale.Rmd")
  r <- e1_with_libs(rehearse(path, list(ok = list(k = 2))))
  expect_false(grepl("was read above the code that sets it", paste(unlist(r$cases$ok$failures$detail), collapse = " ")))
})
