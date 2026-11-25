# Package E2 (dev/design-e2.md), T7: R and a guest in one knitr document (BN7, BN8, TR3, TR4, D4, D13). Skipped
# as the other knitr Python and Julia tests are (k5() skips without Python, k5j() without Julia).

e2_py <- function(lines, ...) {
  res <- k5(lines, ...)
  res$blocks <- b6_blocks(res$text)
  res$filtered <- filter_md(res$text, name = "doc.Rmd", to = "plain")
  res
}

e2_out <- function(res) trimws(res$filtered$output)

test_that("T7 BN7: R binds n, Python publishes n later: the guest's value is the latest and the name is left", {
  res <- e2_py(c(e2_chunk("r1", "n <- 3L"),
                 pychunk("p1", c("from weft import put", "put(n=5)"), "include=FALSE"),
                 "Uses `n`{.num}."))
  expect_false(res$failed, label = res$message)
  expect_true(any(grepl("`n`{.num}", res$text, fixed = TRUE)))
  expect_length(res$blocks, 1L)
  expect_identical(b6_core(res$blocks[[1]]$block$values$n), b6_e_int("5"))
  expect_true(res$blocks[[1]]$close < b6_line(res$text, "Uses `n`"))
  expect_true(grepl("Uses 5.", e2_out(res), fixed = TRUE))
})

test_that("T7 BN7: R assigns n after the guest published it: R's later binding is read", {
  res <- e2_py(c(e2_chunk("r1", "n <- 3L"),
                 pychunk("p1", c("from weft import put", "put(n=5)"), "include=FALSE"),
                 e2_chunk("r2", "n <- 7L"),
                 "Uses `n`{.num}."))
  expect_false(res$failed, label = res$message)
  expect_true("Uses 7." %in% res$text)
})

test_that("T7 BN7: the guest published first and R assigned after: R's value", {
  res <- e2_py(c(pychunk("p1", c("from weft import put", "put(n=5)"), "include=FALSE"),
                 e2_chunk("r1", "n <- 3L"),
                 "Uses `n`{.num}."))
  expect_false(res$failed, label = res$message)
  expect_true("Uses 3." %in% res$text)
})

# design ambiguity: D4's stated cost: an R chunk that reassigns the value R already had is not "later", so the
# guest's value stays the latest; the test reads the filter's output
test_that("T7 D4: R reassigns the same value it had: the guest's publication is still the latest", {
  res <- e2_py(c(e2_chunk("r1", "n <- 3L"),
                 pychunk("p1", c("from weft import put", "put(n=5)"), "include=FALSE"),
                 e2_chunk("r2", "n <- 3L"),
                 "Uses `n`{.num}."))
  expect_false(res$failed, label = res$message)
  expect_true(grepl("Uses 5.", e2_out(res), fixed = TRUE))
})

test_that("T7 TR3: put() in a results='asis' Python chunk prints its block itself and is recorded for later", {
  res <- e2_py(c(e2_chunk("r1", "n <- 3L"),
                 pychunk("p1", c("from weft import put", "put(n=5)", "print(\"Py `n`{.num}.\")"),
                         "echo=FALSE, results='asis'"),
                 "After `n`{.num}."))
  expect_false(res$failed, label = res$message)
  out <- e2_out(res)
  expect_true(grepl("Py 5.", out, fixed = TRUE))
  expect_true(grepl("After 5.", out, fixed = TRUE))
})

test_that("T7 TR4: auto() publishes a changed Python name at the end of its chunk; R's earlier m loses", {
  res <- e2_py(c(pychunk("a1", c("from weft import auto", "auto()"), "include=FALSE"),
                 e2_chunk("r1", "m <- 2L"),
                 pychunk("a2", "m = 9", "include=FALSE"),
                 "Uses `m`{.num}."))
  expect_false(res$failed, label = res$message)
  expect_true(grepl("Uses 9.", e2_out(res), fixed = TRUE))
})

test_that("T7 TR4: auto() asks for the names of named values and of governors in Python or Julia code, not a prose governor", {
  res <- e2_py(c(pychunk("a1", c("from weft import auto", "auto()"), "include=FALSE"),
                 pychunk("a2", c("secret = 'x'", "shown = 4"), "include=FALSE"),
                 "[a | b]{if=\"nchar(secret) > 0\"} and `shown`{.num}."))
  expect_false("secret" %in% e2_names(res))
  expect_true("shown" %in% e2_names(res))
})

test_that("T7 BN8, D13: a named value in Python's weft_str() is left for the filter, which prints Python's value", {
  res <- e2_py(c(pychunk("p1", c("from weft import put, weft_str", "put(n=5)", "print(weft_str(\"`n`{.num}\"))"),
                         "echo=FALSE, results='asis'"),
                 "End."))
  expect_false(res$failed, label = res$message)
  expect_true(any(grepl("`n`{.num}", res$text, fixed = TRUE)))
  expect_true(grepl("5", e2_out(res), fixed = TRUE))
})

test_that("T7 BN7: a Julia @put after R's n is the latest: the name is left and the filter prints the Julia value", {
  res <- k5j(c(e2_chunk("r1", "n <- 3L"),
               jc6k("j1", "n = 8", "@put n", opts = "echo=FALSE"),
               "Uses `n`{.num}."), jl = "using Weft")
  res$blocks <- b6_blocks(res$text)
  expect_false(res$failed, label = res$message)
  expect_true(any(grepl("`n`{.num}", res$text, fixed = TRUE)))
  expect_identical(b6_core(res$blocks[[1]]$block$values$n), b6_e_int("8"))
})
