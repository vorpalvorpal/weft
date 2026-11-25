# Package E2 (dev/design-e2.md), T8: the setting names_from (NS1 to NS3, ST1, M9).

e2_yml_python <- c("names_from: python")

test_that("T8 NS2: names_from python in _weft.yml: R reads no name, publishes nothing, the filter fails it", {
  res <- e2_render(c(e2_chunk("calc", "n <- 3L"), "Uses `n`{.num}."), files = list("_weft.yml" = e2_yml_python))
  b6_expect_knitted(res)
  expect_true("Uses `n`{.num}." %in% res$text)
  expect_length(res$blocks, 0L)
  expect_identical(res$filtered$status, 1L)
  expect_true(grepl(fm_msg$E10("n"), res$filtered$stderr, fixed = TRUE))
})

test_that("T8 NS2: names_from julia behaves as python in R", {
  res <- b6_knit(c(e2_chunk("calc", "n <- 3L"), "Uses `n`{.num}."), files = list("_weft.yml" = "names_from: julia"))
  b6_expect_knitted(res)
  expect_true("Uses `n`{.num}." %in% res$text)
  expect_length(res$blocks, 0L)
})

test_that("T8 NS1: the document's weft: key wins over _weft.yml", {
  res <- b6_knit(c(e2_chunk("calc", "n <- 3L"), "Uses `n`{.num}."), files = list("_weft.yml" = e2_yml_python),
                 front = c("weft:", "  names_from: r"))
  b6_expect_knitted(res)
  expect_true("Uses 3." %in% res$text)
})

test_that("T8 NS1: absent means r in a knitr document", {
  res <- b6_knit(c(e2_chunk("calc", "n <- 3L"), "Uses `n`{.num}."))
  b6_expect_knitted(res)
  expect_true("Uses 3." %in% res$text)
})

test_that("T8 NS2: with names_from python, governors in prose stay R expressions", {
  res <- b6_knit(c(e2_chunk("calc", "flag <- TRUE"), "[yes | no]{if='flag'}."), files = list("_weft.yml" = e2_yml_python))
  b6_expect_knitted(res)
  expect_true("yes." %in% res$text)
  expect_length(res$blocks, 0L)
})

test_that("T8 NS2: weft() always reads .envir, whatever names_from says", {
  res <- b6_knit(c(e2_chunk("calc", "n <- 3L"),
                   "```{r, results='asis', echo=FALSE}", "cat(as.character(weft::weft(\"Got `n`{.num}.\")), \"\\n\")", "```", ""),
                 front = c("weft:", "  names_from: python"))
  b6_expect_knitted(res)
  expect_true(any(grepl("Got 3.", res$text, fixed = TRUE)))
})

test_that("T8 NS3: python with a Python put() above: the filter prints Python's value", {
  res <- k5(c(pychunk("p1", c("from weft import put", "put(n=5)"), "include=FALSE"), "Uses `n`{.num}."),
            weft_yml = e2_yml_python)
  expect_false(res$failed, label = res$message)
  out <- filter_md(res$text, name = "doc.Rmd", to = "plain")
  expect_true(grepl("Uses 5.", out$output, fixed = TRUE))
})

M9 <- "The setting `names_from` must be r, python or julia."

test_that("T8 M9: names_from: ruby stops the knit with a weft_config_error", {
  res <- b6_knit(c("Plain words."), files = list("_weft.yml" = "names_from: ruby"))
  expect_true(res$failed)
  expect_true("weft_config_error" %in% res$error$class)
  expect_match(res$message, M9, fixed = TRUE)
})

test_that("T8 M9: read_config() raises the same error, from _weft.yml and from the front matter", {
  dir <- withr::local_tempdir()
  writeLines("names_from: ruby", file.path(dir, "_weft.yml"))
  withr::local_envvar(WEFT_DRAFT = NA)
  e <- tryCatch({ weft:::read_config(dir, front = list()); NULL }, condition = function(e) e)
  expect_s3_class(e, "weft_config_error")
  expect_match(conditionMessage(e), M9, fixed = TRUE)
  dir2 <- withr::local_tempdir()
  e2 <- tryCatch({ weft:::read_config(dir2, front = list(names_from = "ruby")); NULL }, condition = function(e) e)
  expect_s3_class(e2, "weft_config_error")
  # the three allowed values read
  for (v in c("r", "python", "julia")) {
    expect_identical(weft:::read_config(dir2, front = list(names_from = v))$names_from, v)
  }
})

# ---- ST1: the scanner's resolver column ---------------------------------------------------------

e2_named <- function(x) x[x$kind == "named", , drop = FALSE]

E2_SCAN_RMD <- c("---", "title: \"Depth `depth`{.num}\"", "---", "", "Prose `depth`{.num}.")

test_that("T8 ST1: in an .Rmd a prose named row has resolver hooks and a front-matter one filter", {
  x <- e2_named(w6d_scan(E2_SCAN_RMD, name = "a.Rmd"))
  expect_identical(nrow(x), 2L)
  expect_identical(x$resolver[x$context == "prose"], "hooks")
  expect_identical(x$resolver[x$context == "front-matter"], "filter")
})

test_that("T8 ST1: with names_from python (in _weft.yml or the document) both rows are filter", {
  x <- e2_named(w6d_scan(E2_SCAN_RMD, name = "a.Rmd", files = list("_weft.yml" = e2_yml_python)))
  expect_true(all(x$resolver == "filter"))
  y <- e2_named(w6d_scan(c("---", "title: \"Depth `depth`{.num}\"", "weft:", "  names_from: python", "---", "",
                           "Prose `depth`{.num}."), name = "a.Rmd"))
  expect_identical(nrow(y), 2L)
  expect_true(all(y$resolver == "filter"))
})

test_that("T8 ST1: in a .qmd with engine: jupyter every named row is filter, whatever the setting", {
  lines <- w6d_doc("Prose `depth`{.num}.", front = c("engine: jupyter", "weft:", "  names_from: r"))
  expect_true(all(e2_named(w6d_scan(lines))$resolver == "filter"))
})

test_that("T8 ST1: a named value in a weft() literal is a hooks row; in a cached chunk's caption it is filter", {
  lines <- c("```{r}", "x <- weft::weft(\"A `depth`{.num} string\")", "```", "",
             "```{r fig-c, cache=TRUE, fig.cap='B `depth`{.num}'}", "plot(1)", "```")
  x <- e2_named(w6d_scan(lines, name = "a.Rmd"))
  expect_identical(x$resolver[x$context == "weft"], "hooks")
  expect_identical(x$resolver[x$context == "caption"], "filter")
})
