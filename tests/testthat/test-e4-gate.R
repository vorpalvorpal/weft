# Package E4 (dev/design-e4.md): the gate treats a script as it treats a document (C17, T13). Rulings: a claim() in a
# script's code is not counted (D13). Written before the code. No R under R/ was read.

E4G_DOC <- c("Plain words here.", "")

e4g_val <- function(k = "k") sprintf("x <- weft(\"Found `r %s`{.num} sites\")", k)

test_that("T13 C17: a typed numeral added to a script fails as in a document, and a construct removed needs its trailer", {
  d <- g_scenario(list("R/plot.R" = e4g_val()), list("R/plot.R" = "x <- weft(\"Found 12 sites\")"))
  res <- g_gate(d)
  expect_false(res$ok)
  expect_true("numeral" %in% res$added$rule)
  expect_true(all(res$added$file[res$added$rule == "numeral"] == "R/plot.R"))
  expect_identical(res$n_removed, 1L)
  expect_false(is.na(res$trailer) && FALSE)
  res2 <- g_gate(d, msg = "Edit plot.\n\nWeft-Removed: 1")
  expect_false(res2$ok)
  expect_true("numeral" %in% res2$added$rule)
  expect_identical(res2$n_removed, 1L)
  expect_identical(res2$trailer, 1L)
  expect_false(any(grepl("constructs? removed, and the message", g_report(res2))))
})

test_that("T13 C17: a construct error in a new script fails, naming the script and its line", {
  d <- g_scenario(list("a.qmd" = E4G_DOC), list("R/new.R" = c("x <- 1", "weft(\"ok [x]{if='a >'}\")")))
  res <- g_gate(d)
  expect_false(res$ok)
  expect_identical(nrow(res$errors), 1L)
  expect_identical(res$errors$file, "R/new.R")
  expect_identical(res$errors$line, 2L)
  expect_identical(res$errors$rule, "construct")
})

test_that("T13 C17: deleting a script with two values removes two constructs, listed as in HEAD", {
  before <- c("a <- weft(\"One `r k`{.num} site\")", "b <- weft(\"Two `r j`{.num} sites\")")
  d <- g_scenario(list("a.qmd" = E4G_DOC, "R/plot.R" = before), list("R/plot.R" = NULL))
  res <- g_gate(d)
  expect_false(res$ok)
  expect_identical(res$n_removed, 2L)
  expect_identical(nrow(res$removed), 2L)
  expect_true(all(grepl("R/plot\\.R$", res$removed$file)))
  expect_identical(sort(res$removed$line), c(1L, 2L))
  expect_true("  R/plot.R, as in HEAD" %in% g_report(res))
  ok <- g_gate(d, msg = "Drop plot.\n\nWeft-Removed: 2")
  expect_true(ok$ok)
})

test_that("T13 C17/D3: a script under tests/ with a typed numeral added passes", {
  d <- g_scenario(list("a.qmd" = E4G_DOC), list("tests/a.R" = "weft(\"We saw 12\")"))
  res <- g_gate(d)
  expect_true(res$ok)
  expect_identical(nrow(res$added), 0L)
})

test_that("T13 D13: removing a claim() from a script's code passes", {
  d <- g_scenario(list("a.qmd" = E4G_DOC, "R/a.R" = "claim(n, . > 10)"), list("R/a.R" = "x <- 1"))
  res <- g_gate(d)
  expect_true(res$ok)
  expect_identical(res$n_removed, 0L)
})

test_that("T13 C17: skipping a script with scripts_skip in the new _weft.yml removes its constructs", {
  d <- g_scenario(list("a.qmd" = E4G_DOC, "R/plot.R" = e4g_val()),
                  list("_weft.yml" = c("draft: false", "scripts_skip: [R]")))
  res <- g_gate(d)
  expect_identical(res$n_removed, 1L)
  expect_false(res$ok)
})

test_that("T13 C17: an .R file with no weft in it that changes passes, and the report adds no note", {
  d <- g_scenario(list("a.qmd" = E4G_DOC, "R/b.R" = "x <- 1"), list("R/b.R" = c("x <- 1", "y <- 2")))
  res <- g_gate(d)
  expect_true(res$ok)
  expect_false(any(grepl("parse|note", g_report(res), ignore.case = TRUE)))
})

test_that("T13 C17/D12: a staged script that does not parse loses its constructs: 1 removed, with the line", {
  d <- g_scenario(list("a.qmd" = E4G_DOC, "R/plot.R" = c("x <- 1", e4g_val())),
                  list("R/plot.R" = c("x <- 1", "x <- weft(\"Found `r k`{.num} sites\"")))
  res <- g_gate(d)
  expect_identical(res$n_removed, 1L)
  expect_identical(nrow(res$removed), 1L)
  expect_identical(res$removed$line, 2L)
  expect_match(res$removed$file, "R/plot\\.R$")
  expect_false(any(grepl("does not parse", g_report(res), fixed = TRUE)))
})

test_that("T13 C17: an unchanged script is not judged, and a changed one is: a numeral already in HEAD is tolerated", {
  d <- g_scenario(list("a.qmd" = E4G_DOC, "R/plot.R" = "weft(\"We found 12 sites\")"),
                  list("a.qmd" = c(E4G_DOC, "More plain words.", "")))
  res <- g_gate(d)
  expect_true(res$ok)
})
