# Self-formatting values, stage 1: construction and the zero check.
# Contract: dev/design-self-formatting.md, sections 4.1 to 4.3 and 8.1, 8.2 (cases 1 to 20).
# Written before the code. Non-ASCII is written as \u escapes. Helpers: helper-val.R.

# ---- 8.1 Construction ----------------------------------------------------------------------

test_that("val 1: val_num() is a double with class weft_val first, and as.numeric() gives the bare number", {
  v <- val_num(3.14159)
  expect_identical(class(v)[1], "weft_val")
  expect_true(is.double(v))
  n <- as.numeric(v)
  expect_identical(n, 3.14159)
  expect_null(attributes(n))
})

test_that("val 2: digits is the spec's digits for as.character()", {
  expect_identical(as.character(val_num(3.14159, digits = 2)), "3.14")
})

test_that("val 3: the default spec prints as fmt_num() prints, plain", {
  expect_identical(as.character(val_num(1234567.89)),
                   as.character(fmt_num(1234567.89, target = "plain")))
})

test_that("val 4: markdown, plain and tex texts equal the formatter's three targets, for each constructor", {
  num_x <- list(0.123, -0.5, 1e-4, 2^53, 0, c(0.1, 12.345, 1234.5))
  p_x   <- list(0.123, 1e-4, 0, 0.5, c(0.01, 0.5, 0.9))
  cases <- list(
    list("val_num", val_num, fmt_num, num_x),
    list("val_pct", val_pct, fmt_pct, num_x),
    list("val_sci", val_sci, fmt_sci, num_x),
    list("val_p",   val_p,   fmt_p,   p_x)
  )
  for (cs in cases) for (x in cs[[4]]) {
    info <- paste(cs[[1]], paste(x, collapse = ","))
    v <- suppressWarnings(cs[[2]](x))
    f <- cs[[3]]
    want_md <- suppressWarnings(val_md(f, x))
    want_pl <- suppressWarnings(val_plain(f, x))
    want_tx <- suppressWarnings(val_tex(f, x))
    expect_identical(unname(format(v, target = "markdown")), want_md, info = info)
    expect_identical(unname(format(v)), want_pl, info = info)
    expect_identical(unname(format(v, target = "plain")), want_pl, info = info)
    expect_identical(unname(format(v, target = "tex")), want_tx, info = info)
  }
})

test_that("val 5: names are kept by as.character() and format()", {
  v <- val_num(c(a = 1.5, b = 2.25))
  want <- val_plain(fmt_num, c(1.5, 2.25))
  expect_identical(names(as.character(v)), c("a", "b"))
  expect_identical(unname(as.character(v)), want)
  expect_identical(names(format(v)), c("a", "b"))
  expect_identical(unname(format(v)), want)
})

test_that("val 6: a length-0 value has length 0, as.character() is character(0) and print() writes the empty header", {
  v <- val_num(numeric())
  expect_identical(length(v), 0L)
  expect_identical(as.character(v), character(0))
  out <- capture.output(print(v))
  expect_identical(out[1], "<weft_val[0] .num>")
})

test_that("val 7: NA, Inf and NaN are kept and not formatted", {
  v <- NULL
  expect_no_error(v <- val_num(c(1.5, NA, Inf, NaN)))
  expect_identical(as.character(v), c("1.5", NA, "Inf", "NaN"))
  expect_identical(format(v), c("1.5", "NA", "Inf", "NaN"))
})

test_that("val 8: an integer and an integer64 print every digit", {
  expect_identical(as.character(val_num(5L)), "5")
  skip_if_not_installed("bit64")
  big <- bit64::as.integer64("9007199254740993")
  v <- val_num(big)
  expect_identical(gsub("[^0-9]", "", as.character(v)), "9007199254740993")
  expect_identical(as.character(v), val_plain(fmt_num, big))
})

test_that("val 9: a quantity prints with its unit and stays a units object", {
  v <- val_num(u(5, m))
  expect_identical(as.character(v), paste0("5", VAL_NB, "m"))
  expect_true(inherits(v, "units"))
  expect_identical(class(v)[1:2], c("weft_val", "units"))
})

test_that("val 10: a unit given converts, 1500 m with unit km prints 1.5 km", {
  v <- val_num(u(1500, m), unit = "km")
  expect_identical(as.character(v), paste0("1.5", VAL_NB, "km"))
})

test_that("val 11: a unit ladder picks one rung for the vector, and v[1] keeps it", {
  x <- u(c(5, 5000), m)
  want <- val_plain(fmt_num, x, unit = "m|km")
  v <- val_num(x, unit = "m|km")
  expect_identical(as.character(v), want)
  expect_identical(as.character(v[1]), want[1])
  unit_of <- function(s) sub("^.*\u00a0", "", s)
  expect_identical(length(unique(unit_of(as.character(v)))), 1L)
})

test_that("val 12: text, logical, factor, list, weft_text, weft and Date are weft_construct_errors naming the function and class", {
  bad <- list(character = "3", logical = TRUE, factor = factor("a"), list = list(1),
              weft_text = fmt_num(3), weft = weft("x"), Date = Sys.Date())
  for (nm in names(bad)) {
    e <- val_err(val_num(bad[[nm]]))
    expect_s3_class(e, "weft_construct_error")
    expect_match(conditionMessage(e), "`val_num()` takes a number or a quantity; got a", fixed = TRUE, info = nm)
    expect_match(conditionMessage(e), nm, fixed = TRUE, info = nm)
    expect_match(conditionMessage(e), "To print text, use `weft()`.", fixed = TRUE, info = nm)
  }
})

test_that("val 12: the other constructors name themselves in the error", {
  for (nm in c("val_pct", "val_sci", "val_p")) {
    e <- val_err(get(nm)("3"))
    expect_s3_class(e, "weft_construct_error")
    expect_match(conditionMessage(e), sprintf("`%s()` takes a number or a quantity; got a", nm), fixed = TRUE)
  }
})

test_that("val 13: arguments fmt_num() refuses are refused with the same error", {
  pairs <- list(
    list(function() fmt_num(1, digits = 1, sigfig = 2), function() val_num(1, digits = 1, sigfig = 2)),
    list(function() fmt_num(1, plus = NA),              function() val_num(1, plus = NA)),
    list(function() fmt_num(u(1, m), unit_form = "bogus"), function() val_num(u(1, m), unit_form = "bogus"))
  )
  for (p in pairs) {
    want <- val_err(p[[1]]())
    got <- val_err(p[[2]]())
    expect_false(is.null(want))
    expect_false(is.null(got))
    expect_identical(class(got), class(want))
    # ruling 27 Nov: the same error, but naming the function the author called
    expect_identical(sub("val_", "fmt_", conditionMessage(got), fixed = TRUE), conditionMessage(want))
  }
})

test_that("val 14: val_num() of a val_pct() takes the new spec only; the number underneath is formatted again", {
  p <- val_pct(0.5)
  v <- val_num(p)
  expect_identical(class(v)[1], "weft_val")
  expect_identical(as.numeric(v), 0.5)
  expect_identical(as.character(v), val_plain(fmt_num, 0.5))
  expect_false(grepl("%", as.character(v), fixed = TRUE))
})

test_that("val 15: a value made under a project _weft.yml keeps that project's marks after setwd()", {
  val_project(c("decimal_mark: \",\"", "big_mark: \".\""))
  v <- val_num(1.5)
  expect_identical(as.character(v), "1,5")
  other <- normalizePath(withr::local_tempdir())
  withr::local_dir(other)
  expect_identical(as.character(v), "1,5")
  expect_identical(as.character(val_num(1.5)), "1.5")   # control: a value made here uses the defaults
})

# ---- 8.2 The zero check --------------------------------------------------------------------

test_that("val 16: val_num(0.04) signals one weft_zero_warning and prints 0.0", {
  r <- val_warnings(val_num(0.04))
  expect_length(r$zero, 1L)
  expect_identical(as.character(r$value), "0.0")
})

test_that("val 17: digits or sigfig given to the constructor silences the zero check", {
  expect_length(val_warnings(val_num(0.04, digits = 1))$zero, 0L)
  expect_length(val_warnings(val_num(0.04, sigfig = 1))$zero, 0L)
})

test_that("val 18: printing, converting and pasting a value made earlier signal no warning", {
  v <- suppressWarnings(val_num(0.04))
  r <- val_warnings({
    as.character(v); format(v); paste(v); capture.output(print(v))
    format(v, target = "markdown")
  })
  expect_length(r$warnings, 0L)
})

test_that("val 19: c(val_num(1), 0.04) signals one zero warning", {
  r <- val_warnings(c(val_num(1), 0.04))
  expect_length(r$zero, 1L)
})

test_that("val 20: in a knit with weft's hooks, a chunk with val_num(0.04) records one warned check 'printed as zero' and the render succeeds", {
  res <- d2_render(c(val_chunk("mk", "v <- val_num(0.04)"), "Text `r 1`."))
  expect_false(res$failed, label = res$message)
  w <- res$knit$warnings
  expect_equal(nrow(w), 1L)
  expect_true(all(w$kind == "printed as zero"))
})
