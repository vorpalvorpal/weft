# Self-formatting values, stage 1: vector behaviour, arithmetic, vctrs and dplyr.
# Contract: dev/design-self-formatting.md, sections 4.4, 4.5, 8.3, 8.4, 8.8 (cases 21 to 37, 73 to 75).
# Written before the code. Non-ASCII is written as \u escapes. Helpers: helper-val.R.

val_spec <- function(x) attr(x, "weft_spec")

# ---- 8.3 Vector behaviour -----------------------------------------------------------------

test_that("val 21: [, [[, rev, rep, head, sort and unique keep the class and the spec, with the right texts", {
  v <- val_num(c(2.5, 1.5, 2.5, 0.5), digits = 1)
  txt <- as.character(v)
  num <- as.numeric(v)
  cases <- list(
    list("v[2]",       v[2],           txt[2]),
    list("v[[2]]",     v[[2]],         txt[2]),
    list("rev(v)",     rev(v),         rev(txt)),
    list("rep(v, 2)",  rep(v, 2),      rep(txt, 2)),
    list("head(v, 1)", head(v, 1),     txt[1]),
    list("sort(v)",    sort(v),        txt[order(num)]),
    list("unique(v)",  unique(v),      txt[!duplicated(num)])
  )
  for (cs in cases) {
    expect_identical(class(cs[[2]])[1], "weft_val", info = cs[[1]])
    expect_identical(val_spec(cs[[2]]), val_spec(v), info = cs[[1]])
    expect_identical(as.character(cs[[2]]), cs[[3]], info = cs[[1]])
  }
  expect_identical(as.character(tail(v, 1)), txt[4])
  expect_identical(class(tail(v, 1))[1], "weft_val")
})

test_that("val 22: c() of two values with the same spec is a weft_val; with different digits it is the construct error naming both formats", {
  v <- val_num(c(1.5, 2.5), digits = 1)
  w <- val_num(3.5, digits = 1)
  cw <- c(v, w)
  expect_identical(class(cw)[1], "weft_val")
  expect_identical(as.numeric(cw), c(1.5, 2.5, 3.5))
  expect_identical(as.character(cw), c(as.character(v), as.character(w)))
  e <- val_err(c(v, val_num(3.5, digits = 2)))
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e), "Values with different formats cannot be combined:", fixed = TRUE)
  expect_match(conditionMessage(e), "digits=1", fixed = TRUE)
  expect_match(conditionMessage(e), "digits=2", fixed = TRUE)
  expect_match(conditionMessage(e), "Give them one format, or combine the numbers with as.numeric().", fixed = TRUE)
})

test_that("val 23: c(v, 3) is a weft_val and the last text is the spec's print of 3", {
  v <- val_num(c(1.5, 2.5), digits = 2)
  r <- c(v, 3)
  expect_identical(class(r)[1], "weft_val")
  expect_identical(as.character(r)[3], "3.00")
  expect_identical(as.character(r)[1:2], as.character(v))
})

test_that("val 24: c(3, v) is a plain double (R dispatches c() on the first argument)", {
  v <- val_num(c(1.5, 2.5), digits = 2)
  r <- c(3, v)
  expect_false(inherits(r, "weft_val"))
  expect_true(is.double(r))
  expect_identical(r, c(3, 1.5, 2.5))
})

test_that("val 25: c(v, 'a') is the construct error", {
  v <- val_num(c(1.5, 2.5))
  e <- val_err(c(v, "a"))
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e), "Values with different formats cannot be combined:", fixed = TRUE)
})

test_that("val 26: v[2] <- 7.25 keeps the class and the new text follows the spec; v[2] <- 'x' is the construct error", {
  v <- val_num(c(1.5, 2.5, 3.5), digits = 2)
  v[2] <- 7.25
  expect_identical(class(v)[1], "weft_val")
  expect_identical(as.numeric(v), c(1.5, 7.25, 3.5))
  expect_identical(as.character(v), c("1.50", "7.25", "3.50"))
  w <- val_num(c(1.5, 2.5, 3.5), digits = 2)
  e <- val_err(w[2] <- "x")
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e), "Values with different formats cannot be combined:", fixed = TRUE)
})

test_that("val 26: v[i] <- w with another spec is the error of c()", {
  v <- val_num(c(1.5, 2.5), digits = 2)
  e <- val_err(v[1] <- val_num(9, digits = 1))
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e), "Values with different formats cannot be combined:", fixed = TRUE)
})

test_that("val 27: as.list() is a list of weft_vals, and lapply(v, as.character) gives their texts", {
  v <- val_num(c(1.5, 2.5, 3.5), digits = 1)
  l <- as.list(v)
  expect_type(l, "list")
  expect_length(l, 3L)
  expect_true(all(vapply(l, function(el) identical(class(el)[1], "weft_val"), NA)))
  expect_identical(unlist(lapply(v, as.character), use.names = FALSE), as.character(v))
})

test_that("val 28: a for loop over a value reads bare numbers", {
  v <- val_num(c(1.5, 2.5), digits = 1)
  cls <- NULL
  for (el in v) cls <- class(el)
  expect_identical(cls, "numeric")
})

test_that("val 29: is.numeric(), length(), names() and is.na() act on the numbers", {
  v <- val_num(c(a = 1.5, b = NA, c = 3))
  expect_true(is.numeric(v))
  expect_identical(length(v), 3L)
  expect_identical(names(v), c("a", "b", "c"))
  expect_identical(unname(is.na(v)), c(FALSE, TRUE, FALSE))
})

# ---- 8.4 Arithmetic ------------------------------------------------------------------------

val_plain_double <- function(x) is.double(x) && !inherits(x, "weft_val") && is.null(attr(x, "weft_spec"))

test_that("val 30: + - * / ^ and unary minus give plain doubles with no weft_spec", {
  v <- val_num(c(1.5, 2.5), digits = 1)
  expect_true(val_plain_double(v + 1))
  expect_true(val_plain_double(v * 2))
  expect_true(val_plain_double(-v))
  expect_true(val_plain_double(v / v))
  expect_true(val_plain_double(v^2))
  expect_true(val_plain_double(v %% 2))
  expect_true(val_plain_double(v %/% 2))
  expect_equal(as.numeric(v + 1), c(2.5, 3.5))
  expect_equal(as.numeric(v^2), c(2.25, 6.25))
})

test_that("val 31: comparisons give logical vectors", {
  v <- val_num(c(1.5, 2.5), digits = 1)
  expect_identical(v > 2, c(FALSE, TRUE))
  expect_identical(v == v, c(TRUE, TRUE))
  expect_identical(v != 1.5, c(FALSE, TRUE))
  expect_true(is.logical(v <= 2))
})

test_that("val 32: round(), abs() and log() give plain results", {
  v <- val_num(c(1.5, 2.5), digits = 1)
  expect_true(val_plain_double(round(v)))
  expect_true(val_plain_double(abs(v)))
  expect_true(val_plain_double(log(v)))
})

test_that("val 33: max, min, range, mean and median keep the spec; sum and prod are plain", {
  v <- val_num(c(1.5, 2.5, 4), digits = 1)
  keep <- list(max = max(v), min = min(v), range = range(v), mean = mean(v), median = median(v))
  for (nm in names(keep)) {
    expect_identical(class(keep[[nm]])[1], "weft_val", info = nm)
    expect_identical(val_spec(keep[[nm]]), val_spec(v), info = nm)
  }
  expect_identical(as.character(keep$max), "4.0")
  expect_identical(as.character(keep$min), "1.5")
  expect_identical(as.numeric(keep$range), c(1.5, 4))
  expect_length(keep$range, 2L)
  expect_identical(as.numeric(keep$mean), mean(c(1.5, 2.5, 4)))
  expect_identical(as.character(keep$mean), val_plain(fmt_num, mean(c(1.5, 2.5, 4)), digits = 1))
  expect_identical(as.character(keep$median), "2.5")
  expect_true(val_plain_double(sum(v)))
  expect_true(val_plain_double(prod(v)))
  expect_equal(sum(v), 8)
})

test_that("val 34: a quantity value plus a quantity, either way round, is a units quantity of 6 m and warns not", {
  v <- val_num(u(5, m))
  r1 <- val_warnings(v + u(1, m))
  r2 <- val_warnings(u(1, m) + v)
  for (r in list(r1, r2)) {
    expect_length(r$warnings, 0L)
    expect_s3_class(r$value, "units")
    expect_false(inherits(r$value, "weft_val"))
    expect_equal(as.numeric(r$value), 6)
    expect_identical(units::deparse_unit(r$value), "m")
  }
})

test_that("val 35: a quantity value times 2 is a units quantity of 10 m", {
  r <- val_num(u(5, m)) * 2
  expect_s3_class(r, "units")
  expect_false(inherits(r, "weft_val"))
  expect_equal(as.numeric(r), 10)
  expect_identical(units::deparse_unit(r), "m")
})

test_that("val 36: a weft_year inside stays a weft_year under arithmetic", {
  y <- read_dict(a2_fixture())$method_change
  expect_s3_class(y, "weft_year")
  v <- val_num(y)
  expect_identical(as.character(v), "2014")   # control of the input: no thousands mark
  r <- v + 1L
  expect_s3_class(r, "weft_year")
  expect_false(inherits(r, "weft_val"))
  expect_identical(as.integer(r), 2015L)
})

test_that("val 37: claim() judges the number; a failure shows the number, not the text or the structure", {
  v <- val_num(10)
  expect_no_error(r <- claim(v, . > 9))
  expect_identical(r, v)
  e <- val_err(claim(val_num(10), . < 9))
  expect_s3_class(e, "weft_claim_failed")
  msg <- conditionMessage(e)
  expect_match(msg, "10", fixed = TRUE)
  expect_false(grepl("\"10\"", msg, fixed = TRUE))
  expect_false(grepl("structure(", msg, fixed = TRUE))
  # control: the text of a formatter compares as a string
  expect_false(isTRUE(as.character(fmt_num(10)) > 9))
})

# ---- 8.8 vctrs and dplyr -------------------------------------------------------------------

test_that("val 73: vec_c() of same-spec values is a weft_val; with a plain double it is a double; with different specs it errors", {
  skip_if_not_installed("vctrs")
  v <- val_num(c(1.5, 2.5), digits = 1)
  r <- vctrs::vec_c(v, v)
  expect_identical(class(r)[1], "weft_val")
  expect_identical(as.numeric(r), c(1.5, 2.5, 1.5, 2.5))
  d <- vctrs::vec_c(v, 1)
  expect_false(inherits(d, "weft_val"))
  expect_true(is.double(d))
  expect_error(vctrs::vec_c(v, val_num(1, digits = 2)))
})

test_that("val 74: mutate(), filter() and arrange() keep the class and the texts follow the rows", {
  skip_if_not_installed("dplyr")
  df <- data.frame(x = c(3.14159, 1.5, 2.25, 0.5))
  m <- dplyr::mutate(df, y = val_num(x, digits = 1))
  expect_identical(class(m$y)[1], "weft_val")
  txt <- as.character(m$y)
  f <- dplyr::filter(m, x > 1)
  expect_identical(class(f$y)[1], "weft_val")
  expect_identical(as.character(f$y), txt[df$x > 1])
  a <- dplyr::arrange(m, x)
  expect_identical(class(a$y)[1], "weft_val")
  expect_identical(as.character(a$y), txt[order(df$x)])
})

test_that("val 75: bind_rows() of same-spec columns keeps the class; with different specs it errors", {
  skip_if_not_installed("dplyr")
  a <- data.frame(y = val_num(c(1.5, 2.5), digits = 1))
  b <- data.frame(y = val_num(3.5, digits = 1))
  r <- dplyr::bind_rows(a, b)
  expect_identical(class(r$y)[1], "weft_val")
  expect_identical(as.numeric(r$y), c(1.5, 2.5, 3.5))
  bad <- data.frame(y = val_num(3.5, digits = 2))
  expect_error(dplyr::bind_rows(a, bad))
})
