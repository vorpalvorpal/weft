# Self-formatting values, stage 1: in a knit, the ledger, the gate and named values.
# Contract: dev/design-self-formatting.md, sections 5, 6, 8.7, 8.9 (cases 61 to 72, 77, 78).
# Written before the code. Non-ASCII is written as \u escapes. Helpers: helper-val.R and the 2d
# helpers (d2_render(), d2_ledger()), which write into temporary folders only.

VAL_MK <- "v <- weft::val_num(3.14159, digits = 2)"

# one document knitted in this process with weft's hooks; `code` runs in the set-up chunk
val_knit <- function(lines, code = VAL_MK, ...) {
  res <- d2_render(lines, code = code, ...)
  res$entries <- d2_ledger(res)
  res$all <- paste(res$text, collapse = "\n")
  res
}

# ---- 8.7 In a knit -------------------------------------------------------------------------

test_that("val 61: `r v` in prose prints 3.14 and the ledger has a bare entry with text 3.14 and raw 3.14159", {
  res <- val_knit("Mean `r v` here.")
  expect_false(res$failed, label = res$message)
  expect_match(res$all, "Mean 3.14 here.", fixed = TRUE)
  e <- d2_one(res$entries, kind = "bare", expr = "v")
  expect_identical(e$text, "3.14")
  expect_equal(e$raw, 3.14159)
})

test_that("val 62: the same document without weft_setup() (plain knitr) prints 3.14", {
  res <- render_rmd("Mean `r v` here.", setup = FALSE, in_process = TRUE, format = "knit",
                    code = VAL_MK)
  expect_false(res$failed, label = res$message)
  expect_match(paste(res$text, collapse = "\n"), "Mean 3.14 here.", fixed = TRUE)
})

test_that("val 63: `r v`{.num digits=3} is a value entry with text 3.142", {
  res <- val_knit("Mean `r v`{.num digits=3} here.")
  expect_false(res$failed, label = res$message)
  expect_match(res$all, "Mean 3.142 here.", fixed = TRUE)
  e <- d2_one(res$entries, kind = "value", expr = "v")
  expect_identical(e$text, "3.142")
  expect_equal(e$raw, 3.14159)
})

test_that("val 64: in inline math `r v` writes the TeX form and the ledger entry has context math", {
  res <- val_knit("Math $x = `r v`$ here.", code = "v <- weft::val_num(-1234.5)")
  expect_false(res$failed, label = res$message)
  expect_match(res$all, "-1{,}234.5", fixed = TRUE)
  es <- d2_pick(res$entries, expr = "v")
  expect_length(es, 1L)
  expect_identical(es[[1]]$context, "math")
  expect_equal(es[[1]]$raw, -1234.5)
})

test_that("val 65: in a {=latex} raw block `r v` writes the TeX wrapped in \\ensuremath{}", {
  res <- val_knit(c("```{=latex}", "Value `r v` here.", "```"), code = "v <- weft::val_num(-1234.5)")
  expect_false(res$failed, label = res$message)
  expect_match(res$all, "\\ensuremath{-1{,}234.5}", fixed = TRUE)
})

test_that("val 66: val_sci(1e-4) bare in prose writes the markdown form, not the plain one", {
  res <- val_knit("Size `r v` here.", code = "v <- weft::val_sci(1e-4)")
  expect_false(res$failed, label = res$message)
  md <- val_md(fmt_sci, 1e-4)
  pl <- val_plain(fmt_sci, 1e-4)
  expect_false(identical(md, pl))                           # control: the forms differ
  expect_match(res$all, paste0("Size ", md, " here."), fixed = TRUE)
  expect_false(grepl(paste0("Size ", pl, " here."), res$all, fixed = TRUE))
})

test_that("val 67: pasting a value into cat() in a results='asis' chunk gives the chunk's table entry and no entry for v", {
  res <- val_knit(c(val_chunk("asis-text", "cat(paste('Mean', v), '\\n\\n')", opts = "echo=FALSE, results='asis'"),
                    "After."))
  expect_false(res$failed, label = res$message)
  expect_match(res$all, "Mean 3.14", fixed = TRUE)
  tab <- d2_pick(res$entries, kind = "table")
  expect_length(tab, 1L)
  expect_identical(tab[[1]]$expr, "asis-text")
  expect_length(d2_pick(res$entries, expr = "v"), 0L)
})

test_that("val 68: a plot titled with paste('Mean', v) leaves no ledger entry naming v", {
  res <- val_knit(val_chunk("mk-plot", "w <- weft::val_num(2.5, digits = 1)",
                            "plot(1, main = paste('Mean', w))", opts = "echo=FALSE"))
  expect_false(res$failed, label = res$message)
  expect_length(d2_pick(res$entries, expr = "w"), 0L)
  expect_false(any(vapply(res$entries, function(e) identical(e$sentence, "Mean 2.5"), NA)))
})

test_that("val 69: a weft() plot title gives one entry, context weft, sentence 'Mean 3.14'", {
  res <- val_knit(val_chunk("titled", "plot(1, main = weft::weft('Mean `r v`'))", opts = "echo=FALSE"))
  expect_false(res$failed, label = res$message)
  es <- d2_pick(res$entries, context = "weft")
  expect_length(es, 1L)
  expect_identical(es[[1]]$sentence, "Mean 3.14")
  expect_identical(es[[1]]$text, "3.14")
})

test_that("val 70: a cached chunk that makes v, rendered twice, gives the same ledger", {
  dir <- withr::local_tempdir()
  doc <- c(val_chunk("make-v", "v <- weft::val_num(3.14159, digits = 2)", opts = "cache=TRUE"),
           "Mean `r v` here.")
  r1 <- d2_render(doc, dir = dir)
  expect_false(r1$failed, label = r1$message)
  first <- d2_lines(d2_path(dir))
  r2 <- d2_render(doc, dir = dir)
  expect_false(r2$failed, label = r2$message)
  expect_identical(d2_lines(d2_path(dir)), first)
  expect_true(any(grepl("Mean 3.14 here.", r2$text, fixed = TRUE)))
})

test_that("val 71: a front-matter decimal_mark applies in prose, in a weft() string and through paste()", {
  res <- val_knit(
    c("Prose `r v`.", "",
      val_chunk("viaweft", "w <- weft::weft('Weft `r v`')", "cat(as.character(w), '\\n\\n')", opts = "echo=FALSE, results='asis'"),
      val_chunk("viapaste", "cat(paste('Paste', v), '\\n\\n')", opts = "echo=FALSE, results='asis'")),
    code = "v <- weft::val_num(1.5)",
    front = c("weft:", "  decimal_mark: \",\"", "  big_mark: \".\""))
  expect_false(res$failed, label = res$message)
  expect_match(res$all, "Prose 1,5.", fixed = TRUE)
  expect_match(res$all, "Weft 1,5", fixed = TRUE)
  expect_match(res$all, "Paste 1,5", fixed = TRUE)
})

test_that("val 72: the gate: deleting the chunk line needs no trailer; deleting the prose needs Weft-Removed: 1", {
  before <- list("ch1.qmd" = c(G_ENGINE, "```{r mk}", "v <- val_num(x)", "```", "", "Mean `r v` here."))
  d1 <- g_scenario(before,
                   list("ch1.qmd" = c(G_ENGINE, "```{r mk}", "```", "", "Mean `r v` here.")))
  res1 <- g_gate(d1)
  expect_true(res1$ok)
  expect_identical(max(0, res1$n_removed), 0)
  d2 <- g_scenario(before,
                   list("ch1.qmd" = c(G_ENGINE, "```{r mk}", "v <- val_num(x)", "```", "", "Mean here.")))
  res2 <- g_gate(d2)
  expect_false(res2$ok)
  expect_identical(res2$n_removed, 1L)
  d3 <- g_scenario(before,
                   list("ch1.qmd" = c(G_ENGINE, "```{r mk}", "v <- val_num(x)", "```", "", "Mean here.")))
  res3 <- g_gate(d3, msg = "Drop the mean.\n\nWeft-Removed: 1")
  expect_true(res3$ok)
})

# ---- 8.9 Named values ----------------------------------------------------------------------

test_that("val 77: weft_values_write() refuses a value with the E46 text", {
  dir <- withr::local_tempdir()
  p <- file.path(dir, "v.json")
  e <- val_err(weft::weft_values_write(p, d = val_num(1)))
  expect_s3_class(e, "weft_values_error")
  expect_match(conditionMessage(e), "d", fixed = TRUE)
  expect_match(conditionMessage(e),
               "is a self-formatting value; named values carry no format. Publish the number with as.numeric() and write its classes where it is used (rule 3.8.4).",
               fixed = TRUE)
  expect_false(file.exists(p))
})

test_that("val 77: values_block() refuses it too (control: a plain number is accepted)", {
  expect_error(weft:::values_block(d = val_num(1)), class = "weft_values_error")
  expect_no_error(weft:::values_block(d = 1))
})

test_that("val 78: automatic publishing of a value used above its binding reports E46 as an error record, and the knit goes on", {
  res <- b6_knit(c(
    val_chunk("calc", "depth <- weft::val_num(3.5)"),
    "Names listed in the subtitle."
  ), front = sprintf('subtitle: "%s"', "`depth`{.num}"))
  b6_expect_knitted(res)
  expect_length(res$blocks, 1L)
  rec <- res$blocks[[1]]$block$values$depth
  expect_identical(rec$t, "error")
  expect_match(rec$why, "is a self-formatting value; named values carry no format.", fixed = TRUE)
})
