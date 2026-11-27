# Claims in scripts, stage S1b (dev/design-script-claims.md SC6, D6, rule 3.11.1 in brackets, T17, T18, T29, T36):
# a claim in the body of an `if` whose condition is the literal FALSE (whole-enclosing parentheses removed) is
# not counted, not listed by checks() and its decision is not collected, in scripts and in R chunks alike. The
# `else` arm is live. Written before the code; no R under R/ was read.
# Controls (tests that pass before the feature) say so.

DI_DOC <- c("Plain words here.", "")
DI_FN_DEAD <- c("count_up <- function(trend) {", "  if (FALSE) {", "    claim(sum(trend$up), . >= 10)", "  }", "}")
DI_FN <- c("count_up <- function(trend) {", "  claim(sum(trend$up), . >= 10)", "}")
DI_TRAILER <- c("Edit.", "", "Weft-Removed: 1")

di_run <- function(before, after = list(), msg = NULL, env = parent.frame()) {
  d <- g_scenario(c(list("a.qmd" = DI_DOC), before), after, env = env)
  g_gate(d, msg = msg, env = env)
}
di_chunk <- function(...) c("Words.", "", "```{r}", c(...), "```", "")

# a script holding `claim_line` (line 2), replaced by `x <- 1`: n_removed
di_n_removed <- function(claim_line, env = parent.frame()) {
  di_run(list("R/a.R" = c("x <- 1", claim_line)), list("R/a.R" = c("x <- 1", "x <- 1")), env = env)$n_removed
}

# ---- T17: wrapping a claim in if (FALSE) is a removal ---------------------------------------------------------

test_that("SC6 T17: wrapping the claim of R/functions.R in if (FALSE) is a removal, passed by the trailer", {
  res <- di_run(list("R/functions.R" = DI_FN), list("R/functions.R" = DI_FN_DEAD))
  expect_false(res$ok)
  expect_identical(res$n_removed, 1L)
  expect_identical(res$removed$file, "R/functions.R")
  expect_identical(res$removed$kind, "claim")
  expect_true(di_run(list("R/functions.R" = DI_FN), list("R/functions.R" = DI_FN_DEAD), msg = DI_TRAILER)$ok)
})

test_that("SC6 T17: wrapping a claim in an R chunk of a document in if (FALSE) is a removal", {
  res <- di_run(list("b.Rmd" = di_chunk("n <- claim(x, . > 1)")),
                list("b.Rmd" = di_chunk("if (FALSE) {", "  n <- claim(x, . > 1)", "}")))
  expect_identical(res$n_removed, 1L)
  expect_false(res$ok)
  expect_identical(res$removed$file, "b.Rmd")
})

test_that("SC6 T17: changing if (TRUE) to if (FALSE) around a claim is a removal, in a script and in a chunk", {
  res <- di_run(list("R/a.R" = "if (TRUE) claim(x, . > 1)"), list("R/a.R" = "if (FALSE) claim(x, . > 1)"))
  expect_identical(res$n_removed, 1L)
  res2 <- di_run(list("b.Rmd" = di_chunk("if (TRUE) claim(x, . > 1)")),
                 list("b.Rmd" = di_chunk("if (FALSE) claim(x, . > 1)")))
  expect_identical(res2$n_removed, 1L)
})

test_that("SC6 D6 T17: a claim already under if (FALSE) in HEAD is in neither total; an unrelated edit passes (control)", {
  res <- di_run(list("R/functions.R" = c(DI_FN_DEAD, "y <- 1")), list("R/functions.R" = c(DI_FN_DEAD, "y <- 2")))
  expect_true(res$ok)
  expect_identical(res$n_removed, 0L)
  res2 <- di_run(list("b.Rmd" = di_chunk("if (FALSE) claim(x, . > 1)")),
                 list("b.Rmd" = di_chunk("if (FALSE) claim(x, . > 1)", "y <- 2")))
  expect_identical(res2$n_removed, 0L)
})

test_that("SC6 T17: taking a claim out of if (FALSE) into live code, and deleting a dead claim, cost nothing", {
  res <- di_run(list("R/a.R" = c("x <- 1", "if (FALSE) claim(x, . > 1)")),
                list("R/a.R" = c("x <- 1", "claim(x, . > 1)")))
  expect_true(res$ok)
  res2 <- di_run(list("R/a.R" = c("x <- 1", "if (FALSE) claim(x, . > 1)")), list("R/a.R" = "x <- 1"))
  expect_identical(res2$n_removed, 0L)
})

# ---- T18: which conditions are dead ------------------------------------------------------------------------

test_that("SC6 D6 T18: counted (removing the line removes one): else arm, F, 0, FALSE && y, a variable condition", {
  counted <- c("if (FALSE) 1 else claim(x, . > 1)", "if (F) claim(x, . > 1)", "if (0) claim(x, . > 1)",
               "if (FALSE && y) claim(x, . > 1)", "if (x) claim(x, . > 1)")
  for (l in counted) expect_identical(di_n_removed(l), 1L, info = l)
})

test_that("SC6 D6 T18: not counted (removing the line removes nothing): if ((FALSE)) and FALSE with a comment before the body", {
  expect_identical(di_n_removed("if ((FALSE)) claim(x, . > 1)"), 0L)
  res <- di_run(list("R/a.R" = c("if (FALSE) # off", "{ claim(x, . > 1) }")),
                list("R/a.R" = c("if (FALSE) # off", "{ }")))
  expect_identical(res$n_removed, 0L)
})

test_that("SC6 D6 T18: a claim nested inside a dead if is dead, and a dead if inside a function is read", {
  expect_identical(di_n_removed("if (FALSE) { if (x) claim(x, . > 1) }"), 0L)
  expect_identical(di_n_removed("f <- function() if (FALSE) claim(x, . > 1)"), 0L)
})

test_that("SC6 T18: the same rule in an R chunk: else arm counted, F counted, FALSE body not", {
  chunk_n <- function(line) di_run(list("b.Rmd" = di_chunk(line)), list("b.Rmd" = di_chunk("x <- 1")))$n_removed
  expect_identical(chunk_n("if (FALSE) 1 else claim(x, . > 1)"), 1L)
  expect_identical(chunk_n("if (F) claim(x, . > 1)"), 1L)
  expect_identical(chunk_n("if (FALSE) claim(x, . > 1)"), 0L)
  expect_identical(chunk_n("if ((FALSE)) claim(x, . > 1)"), 0L)
})

# ---- T29: checks() -----------------------------------------------------------------------------------------

test_that("SC6 T29: checks() lists no row for a claim under if (FALSE), in a script and in an R chunk", {
  s <- checks(lint_proj(list("R/a.R" = c("if (FALSE) claim(x, . > 0)", "claim(y, . > 1)")), weft_yml = "draft: false"))
  expect_identical(nrow(s), 1L)
  expect_identical(s$line, 2L)
  d <- checks(lint_proj(list("b.Rmd" = di_chunk("if (FALSE) claim(x, . > 0)", "claim(y, . > 1)")),
                        weft_yml = "draft: false"))
  expect_identical(nrow(d), 1L)
  expect_identical(d$line, 5L)
})

test_that("SC6 T29: the else arm of if (FALSE) is listed", {
  s <- checks(lint_proj(list("R/a.R" = "if (FALSE) 1 else claim(y, . > 1)"), weft_yml = "draft: false"))
  expect_identical(nrow(s), 1L)
})

# ---- T36 (bracket): decisions ------------------------------------------------------------------------------

di_verify <- function(files, env = parent.frame()) {
  v4_env(env = env)
  p <- v4_proj(c(list("doc.qmd" = G_PROSE), files, DP_FILES), git = TRUE, weft_yml = DP_YML, env = env)
  v4_verify(p$root, static = TRUE)
}

test_that("SC6 T36: a decision pointer on a claim under if (FALSE) is not collected, in a script and in a chunk", {
  r <- di_verify(list("R/a.R" = "if (FALSE) claim(n, . > 0, decision = 99)",
                      "b.Rmd" = di_chunk("if (FALSE) claim(n, . > 0, decision = 98)")))
  dp_expect_passed(r)
  expect_false(any(c("99", "98") %in% r$value$decisions$decision))
})

test_that("SC6 T36: the same pointers outside if (FALSE) are collected and fail (control)", {
  dp_expect_failed(di_verify(list("b.Rmd" = di_chunk("claim(n, . > 0, decision = 98)"))))
})
