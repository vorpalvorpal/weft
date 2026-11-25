# Package E2 (dev/design-e2.md), T1, T2, T10, T12: a named value in the prose of a knitr document is read by R, with
# every R formatter, exactly as `r NAME` with the same attribute block (BN1 to BN4, BN10, BN12). Knits are raw knitr
# output (b6_knit); a line of the output is compared with the line of `r x` beside it.

# the lines of a knit that begin with `prefix`, with the prefix removed
e2_lines_of <- function(res, prefix) {
  w <- grep(paste0("^", prefix), res$text)
  sub(paste0("^", prefix, " *"), "", res$text[w])
}

# ---- T1: prose reads R -----------------------------------------------------------------------

test_that("T1 BN1: prose reads a bound name: the value is printed, the name is gone, no block is written", {
  res <- b6_knit(c(e2_chunk("calc", "depth <- 3.14159"), "The depth is `depth`{.num} m."))
  b6_expect_knitted(res)
  expect_true("The depth is 3.1 m." %in% res$text)
  expect_false(any(grepl("`depth`{", res$text, fixed = TRUE)))
  expect_length(res$blocks, 0L)
})

test_that("T1 BN3: a named value prints what `r x` prints with the same attribute block, class by class", {
  cases <- list(
    list("depth", ".num digits='2'"), list("big", ".num"), list("frac", ".pct"), list("tiny", ".sci"),
    list("k", ".word"), list("cnt", ".count"), list("o", ".ord"), list("sv", ".and"), list("w", ".cap")
  )
  setup <- e2_chunk("calc", "depth <- 3.14159", "big <- 1234567.891", "frac <- 0.123", "tiny <- 0.000123",
                    "k <- 3L", "cnt <- 1234L", "o <- 3L", "sv <- c('a', 'b', 'c')", "w <- 'north'")
  body <- unlist(lapply(seq_along(cases), function(i) {
    nm <- cases[[i]][[1]]
    a <- cases[[i]][[2]]
    c(sprintf("N%d: `%s`{%s}", i, nm, a), "", sprintf("R%d: `r %s`{%s}", i, nm, a), "")
  }))
  res <- b6_knit(c(setup, body))
  b6_expect_knitted(res)
  for (i in seq_along(cases)) {
    n <- e2_lines_of(res, sprintf("N%d:", i))
    r <- e2_lines_of(res, sprintf("R%d:", i))
    expect_length(n, 1L)
    expect_identical(n, r, label = cases[[i]][[1]])
    expect_true(nzchar(n))
    expect_false(grepl("`", n, fixed = TRUE), label = cases[[i]][[1]])
  }
  expect_length(res$blocks, 0L)
})

test_that("T1 BN3: units: a units value prints as `r d` does, with the unit ladder and unit=", {
  res <- b6_knit(c(e2_chunk("calc", "d <- weft::u(5, m^2)"),
                   "N1: `d`{.num}", "", "R1: `r d`{.num}", "",
                   "N2: `d`{unit='cm^2'}", "", "R2: `r d`{unit='cm^2'}"))
  b6_expect_knitted(res)
  expect_identical(e2_lines_of(res, "N1:"), e2_lines_of(res, "R1:"))
  expect_identical(e2_lines_of(res, "N1:"), "5 m^2^")
  expect_identical(e2_lines_of(res, "N2:"), e2_lines_of(res, "R2:"))
  expect_false(identical(e2_lines_of(res, "N2:"), "5 m^2^"))
})

test_that("T1 BN3: a project formatter reaches a named value as it reaches `r x`", {
  assign("e2_my_fmt", function(x, ...) paste0("<<", format(unclass(x)), ">>"), envir = globalenv())
  withr::defer(rm("e2_my_fmt", envir = globalenv()))
  yml <- c("formatters:", "  .myclass:", "    function: e2_my_fmt", "    stage: number")
  res <- b6_knit(c(e2_chunk("calc", "x <- 41"), "N: `x`{.myclass}", "", "R: `r x`{.myclass}"),
                 files = list("_weft.yml" = yml))
  b6_expect_knitted(res)
  expect_identical(e2_lines_of(res, "N:"), "<<41>>")
  expect_identical(e2_lines_of(res, "N:"), e2_lines_of(res, "R:"))
})

test_that("T1 BN1: math in prose reads the name, giving the same TeX as `r x`", {
  res <- b6_knit(c(e2_chunk("calc", "depth <- 3.14159"),
                   "M1: $a = `depth`{.num}$", "", "M2: $a = `r depth`{.num}$"))
  b6_expect_knitted(res)
  expect_identical(e2_lines_of(res, "M1:"), e2_lines_of(res, "M2:"))
  expect_false(grepl("`", e2_lines_of(res, "M1:"), fixed = TRUE))
})

test_that("T1 BN1: a named value inside an arm of a span the hooks resolve is read by R", {
  res <- b6_knit(c(e2_chunk("calc", "depth <- 3.5"), "Arm: [`depth`{.num} m | none]{if='depth > 0'}."))
  b6_expect_knitted(res)
  expect_true("Arm: 3.5 m." %in% res$text)
})

test_that("T1 BN2: dotted and underscore names are looked up by their exact text", {
  res <- b6_knit(c(e2_chunk("calc", "n.sites <- 4L", "assign('_x', 2L)"),
                   "S: `n.sites`{.num}", "", "U: `_x`{.num}"))
  b6_expect_knitted(res)
  expect_identical(e2_lines_of(res, "S:"), "4")
  expect_identical(e2_lines_of(res, "U:"), "2")
})

test_that("T1 BN3: a value error fails the knit with the kind `r z`{.num} gives, shown as the named value; draft marks it", {
  chunk_z <- e2_chunk("calc", "z <- 1 + 2i")
  named <- b6_knit(c(chunk_z, "Uses `z`{.num}."))
  inline <- b6_knit(c(chunk_z, "Uses `r z`{.num}."))
  expect_true(named$failed)
  expect_true(inline$failed)
  expect_identical(named$knit$failures$kind, inline$knit$failures$kind)
  expect_match(named$message, "`z`{.num}", fixed = TRUE)
  expect_false(grepl("`r z`", named$message, fixed = TRUE))
  d <- b6_knit(c(chunk_z, "Uses `z`{.num}."), draft = TRUE)
  b6_expect_knitted(d)
  line <- d$offset + length(chunk_z) + 1L
  expect_true(any(grepl(sprintf("<<weft: %s, line %d>>", named$knit$failures$kind[[1]], line), d$text, fixed = TRUE)))
})

test_that("T1 BN12: the ledger entry of a named value R reads is a value entry with no writer, keyed as `r NAME` is", {
  mk <- function(txt) {
    res <- d2_render(c(e2_chunk("calc", "depth <- 3.14159"), txt))
    d2_ledger(res)
  }
  named <- mk("The depth is `depth`{.num} m.")
  inline <- mk("The depth is `r depth`{.num} m.")
  e <- d2_pick(named, kind = "value", expr = "depth")
  i <- d2_pick(inline, kind = "value", expr = "depth")
  expect_length(e, 1L)
  expect_length(i, 1L)
  expect_null(e[[1]]$writer)
  expect_identical(e[[1]]$occ, i[[1]]$occ)
  expect_identical(e[[1]]$text, i[[1]]$text)
})

test_that("T1 BN5, BN12: last_knit()$constructs keeps a row of kind named for it, evaluated", {
  res <- b6_knit(c(e2_chunk("calc", "depth <- 3.14159"), "The depth is `depth`{.num} m."))
  b6_expect_knitted(res)
  cs <- res$knit$constructs
  w <- cs[cs$kind == "named", , drop = FALSE]
  expect_identical(nrow(w), 1L)
  expect_true(all(w$evaluated))
})

# ---- T2: .val in R ----------------------------------------------------------------------------

E2_VAL_CASES <- list(
  list("n", "12L", "12", fr_int("12")),
  list("f", "0.1 + 0.2", "0.30000000000000004", fr_float("0.30000000000000004")),
  list("g", "1e23", "1e+23", fr_float("1e+23")),
  list("b", "TRUE", "true", fr_bool(TRUE)),
  list("dt", "as.Date('2026-11-25')", "2026-11-25", fr_date("2026-11-25")),
  list("s", "'a*b'", "a*b", fr_str("a*b")),
  list("v", "c(1L, 2L, 3L)", "1, 2, 3", fr_list_int(c("1", "2", "3"))),
  list("neg", "-2L", "-2", fr_int("-2")),
  list("fct", "factor('x')", "x", fr_str("x"))
)

test_that("T2 BN4: .val prints from the record: each kind prints the text the filter prints, and the text T2 gives", {
  setup <- e2_chunk("calc", vapply(E2_VAL_CASES, function(cs) sprintf("%s <- %s", cs[[1]], cs[[2]]), ""))
  body <- unlist(lapply(E2_VAL_CASES, function(cs) c(sprintf("V_%s: `%s`{.val}", cs[[1]], cs[[1]]), "")))
  res <- b6_knit(c(setup, body))
  b6_expect_knitted(res)
  expect_length(res$blocks, 0L)
  for (cs in E2_VAL_CASES) {
    got <- e2_lines_of(res, sprintf("V_%s:", cs[[1]]))
    expect_identical(got, cs[[3]], label = cs[[1]])
    # parity: the filter prints the same text for the same record in a block
    out <- filter_md(c(carrier(v = cs[[4]]), "", "`v`{.val}"), to = "plain")
    expect_identical(trimws(out$output), got, label = paste("filter parity:", cs[[1]]))
  }
})

test_that("T2 BN4: a vector under .val .and hands its elements to the class as text, never read as markdown", {
  res <- b6_knit(c(e2_chunk("calc", "sites <- c('a*b', 'c')"), "A: `sites`{.val .and}"))
  b6_expect_knitted(res)
  expect_identical(e2_lines_of(res, "A:"), "a*b and c")
})

test_that("T2 BN4: a missing value under .val is a no value failure", {
  res <- b6_knit(c(e2_chunk("calc", "m <- NA"), "Uses `m`{.val}."))
  expect_true(res$failed)
  expect_setequal(res$knit$failures$kind, "no value")
})

test_that("T2 BN4, M4: a units quantity or a data frame under .val is a value error with the M4 text", {
  q <- b6_knit(c(e2_chunk("calc", "q <- weft::u(5, m)"), "Uses `q`{.val}."))
  expect_true(q$failed)
  expect_setequal(q$knit$failures$kind, "value error")
  expect_match(e2_fail_text(q),
               "`.val` prints a value as it is, and `q` is a units quantity, which has no such form; use a formatter class such as .num (rule 1.12.2).",
               fixed = TRUE)
  df <- b6_knit(c(e2_chunk("calc", "df <- data.frame(a = 1)"), "Uses `df`{.val}."))
  expect_true(df$failed)
  expect_match(e2_fail_text(df),
               "`.val` prints a value as it is, and `df` is an R data.frame, which has no such form; use a formatter class such as .num (rule 1.12.2).",
               fixed = TRUE)
})

# ---- T10: ids ----------------------------------------------------------------------------------

test_that("T10 BN10: a hooks span may refer to the id of a named value R reads", {
  lines <- c("```{r}", "k <- 1L", "```", "", "`k`{#kk .num} then [site | sites]{n='#kk'}.")
  path <- withr::local_tempfile(fileext = ".Rmd")
  writeLines(lines, path)
  x <- weft:::scan_file(path)
  expect_true(all(is.na(x$error)))
  res <- b6_knit(c(e2_chunk("calc", "k <- 1L"), "`k`{#kk .num} then [site | sites]{n='#kk'}."))
  b6_expect_knitted(res)
  expect_true("1 then site." %in% res$text)
})

test_that("T10 BN10, M5: with the name unbound at that point the span fails with M5", {
  res <- b6_knit(c("`k`{#kk .num} then [site | sites]{n='#kk'}.", "", e2_chunk("calc", "k <- 1L"), "End."))
  expect_true(res$failed)
  expect_match(e2_fail_text(res),
               "`#kk` names an id on `k`, which R did not read here and left for the filter; the hooks cannot read it (rule 1.12.10).",
               fixed = TRUE)
})

# ---- T12: rehearse() ----------------------------------------------------------------------------

E2_REH <- c("---", "title: \"t\"", "params:", "  k: 1", "---", "",
            "```{r setup, include=FALSE}", "weft::weft_setup()", "n <- params$k", "```", "",
            "The count is `n`{.num}.", "")

# rehearse() runs each case in its own R process: run this alone (the machine allows one R at a time)
test_that("T12 ST4: rehearse() checks the named values R reads: a missing one fails the case at its line", {
  path <- e1_write(E2_REH, "reh.Rmd")
  r <- e1_with_libs(rehearse(path, list(ok = list(k = 2), gone = list(k = NA))))
  expect_true(r$cases$ok$ok)
  expect_identical(nrow(r$cases$ok$failures), 0L)
  expect_identical(nrow(r$cases$gone$failures), 1L)
  expect_identical(r$cases$gone$failures$kind, "no value")
  expect_identical(r$cases$gone$failures$line, e1_line(E2_REH, "The count is"))
})
