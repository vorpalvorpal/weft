# Package E1 (dev/design-e1.md): failures, location, conditions and the ledger (T10; WS12 to WS15).

e1f_head <- c("---", "title: \"t\"", "---", "")
e1f_setup <- c("```{r setup, include=FALSE}", "weft::weft_setup()", "k <- 3", "```", "")

# ---- outside a knit (WS13) ---------------------------------------------------------------------

test_that("T10 WS13: outside a knit each failure class stops at once, message beginning 'weft: a weft() string: '", {
  k <- 3
  cases <- list(
    weft_claim_failed = "Mean `r claim(k, . > 100)`{.num} m",
    weft_no_value = "Mean `r NA_real_`{.num} m",
    weft_value_error = "`r 1.5`{.word} sites",
    weft_construct_error = "[a | b | c | d | e]{if='TRUE'}")
  for (cls in names(cases)) {
    e <- tryCatch(weft(cases[[cls]]), error = function(e) e)
    expect_s3_class(e, cls)
    expect_match(conditionMessage(e), "^weft: a weft\\(\\) string: ", label = cls)
  }
})

test_that("T10 WS13: the first failure of a vector stops at once", {
  expect_error(weft(c("fine", "Mean `r claim(1, . > 100)`")), class = "weft_claim_failed")
})

test_that("T10 WS13: a passing check, and the legal neighbours of each failure, return the object", {
  k <- 3
  expect_s3_class(weft("Mean `r claim(k, . > 0)`{.num} m"), "weft")
  expect_s3_class(weft("`r 1.5`{.num}"), "weft")
})

test_that("T10 WS13: draft mode has no effect outside a knit: a construct error still stops", {
  withr::local_envvar(WEFT_DRAFT = "1")
  expect_error(weft("[a | b | c | d | e]{if='TRUE'}"), class = "weft_construct_error")
  expect_error(weft("Mean `r claim(1, . > 100)`"), class = "weft_claim_failed")
})

test_that("T10 WS13: a warning is signalled at the call and the object is returned", {
  w <- NULL
  expect_warning(w <- weft("Dose `r 0.04`{.num} mg"), class = "weft_zero_warning")
  expect_s3_class(w, "weft")
})

# ---- in a knit with weft_setup() (WS12) --------------------------------------------------------

test_that("T10 WS12: in a knit a failed claim in a chunk is collected with the chunk label and the render fails naming it", {
  lines <- c(e1f_head, e1f_setup,
    "```{r fig-depth, results='asis', echo=FALSE}",
    "w <- weft::weft('Mean `r claim(k, . > 100)`{.num} m')",
    "cat('PLAIN:', as.character(w), '\\n')",
    "```", "")
  res <- render_rmd(lines, setup = FALSE, in_process = TRUE)
  expect_true(res$failed)
  expect_true("weft_failures" %in% res$error$class)
  expect_match(res$message, "fig-depth", fixed = TRUE)
  expect_equal(res$knit$failures$chunk, "fig-depth")
  expect_setequal(res$knit$failures$kind, "failed claim")
})

test_that("T10 WS12: the object holds the marker in both forms (draft mode, so the render finishes)", {
  lines <- c(e1f_head, e1f_setup,
    "```{r fig-depth, results='asis', echo=FALSE}",
    "w <- weft::weft('Mean `r claim(k, . > 100)`{.num} m')",
    "cat('PLAIN:', as.character(w), '\\n')",
    "cat('MD:', format(w, target = 'markdown'), '\\n')",
    "```", "")
  d <- render_rmd(lines, setup = FALSE, format = "knit", in_process = TRUE, env = c(WEFT_DRAFT = "1"))
  expect_false(d$failed, label = d$message)
  expect_match(unesc(d$md), "PLAIN: Mean 3<<weft: failed claim, chunk fig-depth>> m", fixed = TRUE)
  expect_match(unesc(d$md), "MD: Mean 3<<weft: failed claim, chunk fig-depth>> m", fixed = TRUE)
})

test_that("T10 WS12: draft mode turns a construct error into a marker in a knit", {
  lines <- c(e1f_head, e1f_setup,
    "```{r cs, results='asis', echo=FALSE}",
    "cat(as.character(weft::weft('[a | b | c | d | e]{if=\"TRUE\"}')), '\\n')",
    "```", "")
  res <- render_rmd(lines, setup = FALSE, in_process = TRUE)
  expect_true(res$failed)
  expect_true("weft_construct_error" %in% res$error$class)
  expect_match(res$message, "cs", fixed = TRUE)
  d <- render_rmd(lines, setup = FALSE, format = "knit", in_process = TRUE, env = c(WEFT_DRAFT = "1"))
  expect_false(d$failed, label = d$message)
  expect_match(unesc(d$md), "<<weft: construct error", fixed = TRUE)
})

test_that("T10 WS12/WS14: a failed claim in weft() called from inline R in prose is a marker naming the line (draft), or a failure located by its line", {
  body <- c("Inline fail: `r weft::weft(s9)`.", "", "Control `r claim(k, . > 0)`{.num}.", "")
  code <- c("k <- 3", "s9 <- 'IF `r claim(k, . > 9)`{.num}'")
  d <- render_rmd(body, code = code, format = "knit", in_process = TRUE, env = c(WEFT_DRAFT = "1"))
  expect_false(d$failed, label = d$message)
  expect_match(unesc(d$md), "<<weft: failed claim, line [0-9]+>>")
  res <- render_rmd(body, code = code, in_process = TRUE)
  expect_true(res$failed)
  expect_match(res$message, at_line(res, 1))
  expect_no_match(res$message, "unnamed-chunk-[0-9]+")
})

test_that("T10 WS13: in a knit where the hooks were never installed the first failure stops, 'weft: chunk LABEL: '", {
  lines <- c(e1f_head,
    "```{r a, results='asis', echo=FALSE}",
    "k <- 3",
    "cat(as.character(weft::weft('`r claim(k, . > 100)`')))",
    "```", "")
  res <- render_rmd(lines, setup = FALSE, in_process = FALSE)
  expect_true(res$failed)
  expect_match(res$message, "weft: chunk a: ", fixed = TRUE)
  expect_match(res$message, ". > 100", fixed = TRUE)
})

test_that("T10 WS12: a warned check in a knit is recorded as a warning, not a failure", {
  lines <- c(e1f_head, e1f_setup,
    "```{r w, results='asis', echo=FALSE}",
    "cat(as.character(weft::weft('Str `r claim(k, . > 703, level = \"warn\")`{.num} done.')), '\\n')",
    "```", "")
  res <- render_rmd(lines, setup = FALSE, format = "knit", in_process = TRUE)
  expect_false(res$failed, label = res$message)
  expect_equal(nrow(res$knit$failures), 0L)
  expect_gt(nrow(res$knit$warnings), 0L)
})

# ---- the ledger (WS15) -------------------------------------------------------------------------

test_that("T10 WS15: the ledger rows of a weft() string have context 'weft', never 'weft_str'", {
  lines <- c("```{r strs, results='asis'}",
             "cat(as.character(weft::weft('Weight `r wsv`{.num} kg here.')), '\\n')",
             "```", "")
  res <- d2_render(lines, code = "wsv <- 7")
  entries <- d2_ledger(res)
  ctx <- vapply(entries, function(z) as.character(z$context %||% NA_character_), "")
  expect_true("weft" %in% ctx)
  expect_false("weft_str" %in% ctx)
  e <- d2_one(entries, kind = "value", expr = "wsv")
  expect_identical(e$context, "weft")
  expect_identical(e$sentence, "Weight 7 kg here.")
})

test_that("T10 WS15: last_knit() sees the context 'weft'", {
  lines <- c("```{r strs, results='asis'}",
             "cat(as.character(weft::weft('Weight `r wsv`{.num} kg here.')), '\\n')",
             "```", "")
  res <- d2_render(lines, code = "wsv <- 7")
  expect_true("weft" %in% res$knit$ledger$context)
  expect_false("weft_str" %in% res$knit$ledger$context)
})
