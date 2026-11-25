# Package E2 (dev/design-e2.md), T6: weft() reads a named value from .envir (BN1, BN2, BN9, D3). Outside a knit unless
# said. The test environment's parents include the weft namespace, so the walk's stop (BN2) is exercised here.

test_that("T6 BN1: weft() reads a named value from the caller, in both forms", {
  n <- 3L
  expect_identical(as.character(weft::weft("`n`{.num} sites")), "3 sites")
  expect_identical(unname(format(weft::weft("`n`{.num} sites"), target = "markdown")), "3 sites")
})

test_that("T6 BN2: the lookup sees a calling function's locals and a closure's argument", {
  f <- function() {
    k <- 2L
    weft::weft("`k`{.num}")
  }
  expect_identical(as.character(f()), "2")
  expect_identical(vapply(2:4, function(n) as.character(weft::weft("`n`{.num}")), ""), c("2", "3", "4"))
})

test_that("T6 BN9, M1: an unbound name stops with weft_no_value and the M1 text", {
  e <- tryCatch(weft::weft("`zz`{.num}"), error = function(e) e)
  expect_s3_class(e, "weft_no_value")
  expect_match(conditionMessage(e), "`zz` is not bound where weft() was called, so it has no value (rule 1.12.12).",
               fixed = TRUE)
})

test_that("T6 BN2, D1: pi is not read by name (the walk stops before a namespace or package)", {
  e <- tryCatch(weft::weft("`pi`{.num}"), error = function(e) e)
  expect_s3_class(e, "weft_no_value")
  expect_match(conditionMessage(e), "`pi` is not bound where weft() was called", fixed = TRUE)
})

test_that("T6 BN2, D2, M2: a function is a no value failure with the M2 text", {
  g <- function() 1
  e <- tryCatch(weft::weft("`g`{.num}"), error = function(e) e)
  expect_s3_class(e, "weft_no_value")
  expect_match(conditionMessage(e), "`g` is a function in R, not a value (rule 1.12.12).", fixed = TRUE)
})

test_that("T6 BN1: .envir is where the name is read", {
  expect_identical(as.character(weft::weft("`a`{.num}", .envir = list2env(list(a = 5L)))), "5")
})

test_that("T6 BN3, BN4: .val prints from the record, and a units value prints as `r x` does", {
  b <- TRUE
  expect_identical(as.character(weft::weft("`b`{.val}")), "true")
  u5 <- weft::u(5, m^2)
  expect_identical(as.character(weft::weft("`u5`{.num}")), "5 m²")
})

test_that("T6 BN9, E1 WS12: in a knit with the hooks, the failure is collected: a marker in draft, a failed render otherwise", {
  chunk <- c("```{r wz, results='asis', echo=FALSE}",
             "x <- weft::weft(\"`zz`{.num}\")", "cat('GOT:', as.character(x), '\\n')", "```", "")
  d <- b6_knit(chunk, draft = TRUE)
  b6_expect_knitted(d)
  expect_true(any(grepl("<<weft: no value, chunk wz>>", d$text, fixed = TRUE)))
  r <- b6_knit(chunk)
  expect_true(r$failed)
  expect_match(r$message, "wz", fixed = TRUE)
})

test_that("T6 NS2: weft() is unaffected by names_from in the front matter: it reads R's n", {
  res <- b6_knit(c(e2_chunk("calc", "n <- 3L"),
                   "```{r, results='asis', echo=FALSE}", "cat(as.character(weft::weft('Got `n`{.num}.')), '\\n')", "```", ""),
                 front = c("weft:", "  names_from: python"))
  b6_expect_knitted(res)
  expect_true(any(grepl("Got 3.", res$text, fixed = TRUE)))
})
