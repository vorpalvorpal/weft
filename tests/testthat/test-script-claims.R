# Claims in scripts, stage S1 (dev/design-script-claims.md: SC1 to SC14, M1, M2, D1 to D12, T1 to T44).
# The gate counts a claim() call in a script's code (SC4, SC5); checks() lists it (SC7); inert-check reads it
# (SC8); verify() lists its removal (SC9) and checks its decision pointer (SC10). The `if (FALSE)` rule (SC6,
# S1b) is in test-script-claims-dead-if.R. Written before the code; no R under R/ was read.
# Tests marked "control" pass before the feature and must go on passing.

SC_DOC <- c("Plain words here.", "")
SC_FN <- c("count_up <- function(trend) {", "  claim(sum(trend$up), . >= 10)", "}")
SC_FN_OFF <- c("count_up <- function(trend) {", "  sum(trend$up)", "}")
SC_TRAILER <- c("Edit.", "", "Weft-Removed: 1")

# A scenario (baseline `before`, staged `after`) with a plain document added, and the gate run on it.
sc_run <- function(before, after = list(), msg = NULL, env = parent.frame()) {
  before <- c(list("a.qmd" = SC_DOC), before)
  d <- g_scenario(before, after, env = env)
  g_gate(d, msg = msg, env = env)
}

# `line` in a script, then replaced by `x <- 1`: the gate's n_removed
sc_n_removed <- function(line, env = parent.frame()) {
  sc_run(list("R/a.R" = c("x <- 1", line)), list("R/a.R" = c("x <- 1", "x <- 1")), env = env)$n_removed
}

sc_clean <- function(x) cli::ansi_strip(x)
sc_pr <- function(x) cli::ansi_strip(utils::capture.output(print(x)))
sc_lints <- function(files, ..., tier = 1:2, env = parent.frame()) {
  lints(lint_proj(files, weft_yml = "draft: false", env = env), tier = tier, ...)
}

# ---- the gate: T1 to T21 ----------------------------------------------------------------------------------

test_that("SC4 T1: removing a claim from R/functions.R fails, listing the script, line, kind and text", {
  res <- sc_run(list("R/functions.R" = SC_FN), list("R/functions.R" = SC_FN_OFF))
  expect_false(res$ok)
  expect_identical(res$n_removed, 1L)
  expect_identical(nrow(res$removed), 1L)
  expect_identical(res$removed$file, "R/functions.R")
  expect_identical(res$removed$line, 2L)
  expect_identical(res$removed$kind, "claim")
  expect_identical(res$removed$text, "claim(sum(trend$up), . >= 10)")
})

test_that("SC4 T1: with the trailer Weft-Removed: 1 the removal passes", {
  res <- sc_run(list("R/functions.R" = SC_FN), list("R/functions.R" = SC_FN_OFF), msg = SC_TRAILER)
  expect_identical(res$n_removed, 1L)
  expect_true(res$ok)
})

test_that("SC1 SC4 T2: a script that holds weft is counted the same, the claim now on line 3", {
  res <- sc_run(list("R/functions.R" = c("library(weft)", SC_FN)),
                list("R/functions.R" = c("library(weft)", SC_FN_OFF)))
  expect_identical(res$n_removed, 1L)
  expect_identical(res$removed$file, "R/functions.R")
  expect_identical(res$removed$line, 3L)
})

test_that("SC5 T3: moving a claim from an R chunk into a script in one commit removes nothing", {
  # labelled, so the chunk-label finding is not keyed by the chunk text (ruling 27 Nov)
  chunk <- function(code) c("```{r move}", code, "```", "")
  res <- sc_run(list("b.Rmd" = c("Words.", "", chunk("n <- claim(x, . > 1)")), "R/a.R" = "y <- 1"),
                list("b.Rmd" = c("Words.", "", chunk("n <- 1")), "R/a.R" = c("y <- 1", "n <- claim(x, . > 1)")))
  expect_identical(res$n_removed, 0L)
  expect_true(res$ok)
})

test_that("SC5 T4: moving count_up() to another script, or renaming the script, removes nothing", {
  res <- sc_run(list("R/functions.R" = SC_FN), list("R/functions.R" = NULL, "R/count.R" = SC_FN))
  expect_identical(res$n_removed, 0L)
  d <- g_scenario(list("a.qmd" = SC_DOC, "R/functions.R" = SC_FN))
  g_ok_git(d, "mv", "R/functions.R", "R/fns.R")
  expect_identical(g_gate(d)$n_removed, 0L)
})

test_that("SC4 T5: deleting a script with two claims removes two, listed under it as in HEAD", {
  two <- c("a <- claim(x, . > 1)", "b <- claim(y, . > 2)")
  res <- sc_run(list("R/two.R" = two), list("R/two.R" = NULL))
  expect_false(res$ok)
  expect_identical(res$n_removed, 2L)
  expect_identical(nrow(res$removed), 2L)
  expect_true(all(grepl("R/two\\.R$", res$removed$file)))
  expect_true("  R/two.R, as in HEAD" %in% g_report(res))
})

test_that("SC5 T6: adding a claim passes, and a claim deleted in one script and added in another nets out", {
  res <- sc_run(list("R/a.R" = "x <- 1"), list("R/a.R" = c("x <- 1", "claim(x, . > 1)")))
  expect_true(res$ok)
  res2 <- sc_run(list("R/a.R" = "claim(x, . > 1)", "R/b.R" = "y <- 1"),
                 list("R/a.R" = "x <- 1", "R/b.R" = c("y <- 1", "claim(y, . > 2)")))
  expect_identical(res2$n_removed, 0L)
  expect_true(res2$ok)
})

test_that("SC4 T7: a claim inside a tar_target() command in _targets.R is counted", {
  res <- sc_run(list("_targets.R" = "list(tar_target(n_up, claim(count(x), . > 0)))"),
                list("_targets.R" = "list(tar_target(n_up, count(x)))"))
  expect_false(res$ok)
  expect_identical(res$n_removed, 1L)
  expect_identical(res$removed$file, "_targets.R")
})

test_that("SC13 T8: a claim under tests/ is skipped by default; with scripts_skip: [] it is counted", {
  res <- sc_run(list("tests/testthat/test-a.R" = "claim(x, . > 1)"), list("tests/testthat/test-a.R" = "x <- 1"))
  expect_true(res$ok)
  expect_identical(res$n_removed, 0L)
  yml <- c("draft: false", "scripts_skip: []")
  res2 <- sc_run(list("tests/testthat/test-a.R" = "claim(x, . > 1)", "_weft.yml" = yml),
                 list("tests/testthat/test-a.R" = "x <- 1"))
  expect_false(res2$ok)
  expect_identical(res2$n_removed, 1L)
})

test_that("SC13 T9: adding scripts_skip: [R] while R/functions.R holds two claims removes two", {
  two <- c("a <- claim(x, . > 1)", "b <- claim(y, . > 2)")
  res <- sc_run(list("R/functions.R" = two), list("_weft.yml" = c("draft: false", "scripts_skip: [R]")))
  expect_identical(res$n_removed, 2L)
  expect_false(res$ok)
})

test_that("SC4 D8 T10: a staged script that stops parsing loses its claim: 1 removed, from that script", {
  res <- sc_run(list("R/functions.R" = SC_FN), list("R/functions.R" = SC_FN[1:2]))
  expect_identical(res$n_removed, 1L)
  expect_identical(res$removed$file, "R/functions.R")
})

test_that("M2 D8: the gate names the script that stopped parsing, once, in a note", {
  res <- sc_run(list("R/functions.R" = SC_FN), list("R/functions.R" = SC_FN[1:2]))
  rep <- g_report(res)
  want <- "commit-msg: note: R/functions.R does not parse as R, so its constructs and claims count as removed (rule 3.11.7)."
  expect_identical(sum(rep == want), 1L)
})

test_that("SC4 T11: a claim in a weft() literal counts once as a call, and its value once as a value", {
  lit <- "weft(\"`r claim(n, . > 1)` sites\")"
  both <- c(lit, "claim(m, . > 2)")
  res <- sc_run(list("R/a.R" = both), list("R/a.R" = lit))
  expect_identical(res$n_removed, 1L)
  expect_identical(res$removed$text, "claim(m, . > 2)")
  res2 <- sc_run(list("R/a.R" = both), list("R/a.R" = "claim(m, . > 2)"))
  expect_identical(res2$n_removed, 2L)
  expect_identical(sort(res2$removed$kind), c("claim", "value"))
  expect_identical(res2$removed$line, c(1L, 1L))
})

SC_NOT_COUNTED <- c("# claim(x, . > 1)", "#' claim(x, . > 1)", "s <- \"claim(x, . > 1)\"",
                    "s <- r\"(claim(x, . > 1))\"", "other::claim(x, . > 1)", "f <- claim",
                    "lapply(xs, claim)", "disclaimer(x)")

test_that("SC4 T12: comments, strings, other::claim, claim not called and disclaimer() are not counted (control)", {
  res <- sc_run(list("R/a.R" = SC_NOT_COUNTED), list("R/a.R" = rep("x <- 1", length(SC_NOT_COUNTED))))
  expect_identical(res$n_removed, 0L)
  expect_true(res$ok)
})

test_that("SC4 T12: with one real claim among them, exactly that one is counted", {
  res <- sc_run(list("R/a.R" = c("claim(x, . > 1)", SC_NOT_COUNTED)),
                list("R/a.R" = rep("x <- 1", length(SC_NOT_COUNTED) + 1L)))
  expect_identical(res$n_removed, 1L)
  expect_identical(res$removed$line, 1L)
})

test_that("SC4 T13: every spelling of a call is counted, removed alone", {
  forms <- c("weft::claim(x, . > 1)", "weft:::claim(x, . > 1)", "x |> claim(. > 1)", "x %>% claim(. > 1)",
             "f <- \\(v) claim(v, . > 0)", "claim(x, . > 1, level = \"warn\")", "claim (x, . > 1)",
             "for (i in 1:3) claim(i, . > 0)")
  for (f in forms) expect_identical(sc_n_removed(f), 1L, info = f)
})

test_that("SC4 T14: in a nested project the removed row names the script by its path from the top", {
  res <- sc_run(list("sub/_weft.yml" = "draft: false", "sub/R/a.R" = "claim(x, . > 1)"),
                list("sub/R/a.R" = "x <- 1"), env = environment())
  expect_identical(res$n_removed, 1L)
  expect_identical(res$removed$file, "sub/R/a.R")
})

test_that("SC3 D4 T15: a latin-1 script that holds claim( and not weft gives no error (control)", {
  bytes <- function(extra = "") c(charToRaw(paste0("# caf", extra)), as.raw(0xE9), charToRaw("\nclaim(x, . > 1)\ny <- 1\n"))
  d <- g_scenario(list("a.qmd" = SC_DOC, "R/a.R" = bytes()), list("R/a.R" = c(bytes(), charToRaw("z <- 2\n"))))
  res <- g_gate(d)
  expect_identical(nrow(res$errors), 0L)
  expect_false("read" %in% lints(d, tier = 1:2)$rule)
})

test_that("SC3 D4 T15: the same bytes with weft in a comment give a read error (control, D14 of E4)", {
  bytes <- function() c(charToRaw("# weft caf"), as.raw(0xE9), charToRaw("\nclaim(x, . > 1)\ny <- 1\n"))
  d <- g_scenario(list("a.qmd" = SC_DOC, "R/a.R" = bytes()), list("R/a.R" = c(bytes(), charToRaw("z <- 2\n"))))
  res <- g_gate(d)
  expect_true("read" %in% res$errors$rule)
})

test_that("SC1 T16: two hundred scripts with neither weft nor claim( add no read and no cache entry (control)", {
  withr::local_options(weft.gate_cache = TRUE)
  none <- stats::setNames(rep(list("x <- 1"), 200L), sprintf("R/s%03d.R", 1:200))
  doc2 <- c(SC_DOC, "More words.", "")
  one <- function(extra, env) {
    d <- g_scenario(c(list("a.qmd" = SC_DOC), extra), c(list("a.qmd" = doc2), if (length(extra)) list("R/s001.R" = c("x <- 1", "y <- 2"))), env = env)
    n <- g_count_reads(g_gate(d))
    list(reads = n, cache = length(g_cache_files(d)))
  }
  e <- environment()
  with <- one(none, e)
  without <- one(list(), e)
  expect_identical(with$reads, without$reads)
  expect_identical(with$cache, without$cache)
})

test_that("SC4 T19: editing a top-level bound of a claim passes with the 6.3.7 note, verdict looser", {
  res <- sc_run(list("analysis.R" = "n_down <- claim(shift$n_down, . >= 10)"),
                list("analysis.R" = "n_down <- claim(shift$n_down, . >= 5)"))
  expect_identical(res$n_removed, 0L)
  expect_true(res$ok)
  expect_true("commit-msg: note: analysis.R:1 in HEAD, `n_down >= 10`, is gone and nothing that remains covers it (rule 6.3.7)" %in% g_report(res))
  expect_identical(nrow(res$checks), 1L)
  expect_identical(res$checks$verdict, "looser")
})

test_that("SC4 T20: the same edit inside a function gives verdict unread and no note", {
  loose <- sub(">= 10", ">= 5", SC_FN, fixed = TRUE)
  res <- sc_run(list("R/functions.R" = SC_FN), list("R/functions.R" = loose))
  expect_true(res$ok)
  expect_false(any(grepl("is gone and nothing that remains covers it", g_report(res))))
  expect_identical(nrow(res$checks), 1L)
  expect_identical(res$checks$verdict, "unread")
})

test_that("SC8 T21: adding claim(x, TRUE) to a script fails with an inert-check finding", {
  res <- sc_run(list("R/a.R" = "x <- 1"), list("R/a.R" = c("x <- 1", "claim(x, TRUE)")))
  expect_false(res$ok)
  expect_true("inert-check" %in% res$added$rule)
  expect_identical(res$added$file[res$added$rule == "inert-check"], "R/a.R")
})

test_that("SC8 T21: a claim(x, TRUE) already in HEAD does not fail a commit that changes another line", {
  res <- sc_run(list("R/a.R" = c("claim(x, TRUE)", "y <- 1")), list("R/a.R" = c("claim(x, TRUE)", "y <- 2")))
  expect_true(res$ok)
  expect_identical(nrow(res$added), 0L)
})

# ---- checks(): T22 to T28 ---------------------------------------------------------------------------------

test_that("SC7 T22: a top-level claim is a readable check of role claim, with the script as file", {
  x <- checks(lint_proj(list("analysis.R" = "n_down <- claim(shift$n_down, . >= 10)"), weft_yml = "draft: false"))
  expect_identical(nrow(x), 1L)
  expect_identical(x$file, "analysis.R")
  expect_identical(x$line, 1L)
  expect_identical(x$role, "claim")
  expect_identical(x$level, "fail")
  expect_identical(x$cond, "n_down >= 10")
  expect_true(x$always)
})

test_that("SC7 T23: a claim inside a function is not readable, and print() lists it under not read", {
  x <- checks(lint_proj(list("R/functions.R" = SC_FN), weft_yml = "draft: false"))
  expect_identical(nrow(x), 1L)
  expect_true(is.na(x$cond))
  expect_identical(x$text, "claim(sum(trend$up), . >= 10)")
  out <- sc_pr(x)
  i <- match("R/functions.R", out)
  expect_false(is.na(i))
  expect_identical(out[i + 1L], "  not read")
  expect_match(out[i + 2L], "claim(sum(trend$up), . >= 10)", fixed = TRUE)
})

test_that("SC7 T24: a claim in a loop is not always, and level warn is kept", {
  x <- checks(lint_proj(list("R/a.R" = c("for (s in sites) claim(s, . > 0)",
                                         "claim(x, . > 0, level = \"warn\")")), weft_yml = "draft: false"))
  expect_identical(nrow(x), 2L)
  expect_false(x$always[x$line == 1L])
  expect_identical(x$level[x$line == 2L], "warn")
})

test_that("SC7 T25: a project of one script holding only a claim counts as one document", {
  x <- checks(lint_proj(list("analysis.R" = "n_down <- claim(shift$n_down, . >= 10)"), weft_yml = "draft: false"))
  expect_identical(sc_pr(x)[1], "weft checks: 1 check of 1 value in 1 document; 0 values flagged")
})

test_that("SC7 T26: a name assigned twice before a claim marks the claim rebound", {
  x <- checks(lint_proj(list("R/a.R" = c("x <- 1", "x <- 2", "claim(x, . > 0)")), weft_yml = "draft: false"))
  expect_identical(nrow(x), 1L)
  expect_true(x$rebound)
})

test_that("SC7 T27: a script with a weft() guard and a code claim gives two rows, guard and claim", {
  x <- checks(lint_proj(list("R/a.R" = c("weft(\"[a]{if='n > 1'}\")", "claim(m, . > 2)")), weft_yml = "draft: false"))
  expect_identical(nrow(x), 2L)
  expect_setequal(x$role, c("guard", "claim"))
})

test_that("SC7 T28: checks() now lists a claim in a script's code outside a literal (was D13 of E4)", {
  root <- lint_proj(list("R/a.R" = c("claim(n, . > 10)", "weft(\"plain\")")), weft_yml = "draft: false")
  expect_true("R/a.R" %in% checks(root)$file)
})

# ---- lints(): T30 to T35 ----------------------------------------------------------------------------------

test_that("SC8 T30: claim(x, TRUE) in a script is one inert-check finding at the check, context script", {
  x <- sc_lints(list("R/a.R" = "claim(x, TRUE)"))
  expect_identical(nrow(x), 1L)
  expect_identical(x$rule, "inert-check")
  expect_identical(x$file, "R/a.R")
  expect_identical(x$line, 1L)
  expect_identical(x$col, 10L)
  expect_identical(x$context, "script")
  expect_identical(sc_clean(x$message), "The check `TRUE` has no variable, so it can never fail (rule 3.1.6).")
})

test_that("SC8 T31: claim(x, 1 > 0) and claim(x, interactive()) are inert; claim(x, . > 0) and y > 0 are not", {
  # ruling 27 Nov: as in an R chunk today, a check that reads no variable is inert, a call included
  for (bad in c("claim(x, 1 > 0)", "claim(x, interactive())")) {
    expect_true("inert-check" %in% sc_lints(list("R/a.R" = bad))$rule, info = bad)
  }
  for (ok in c("claim(x, . > 0)", "claim(x, y > 0)")) {
    expect_false("inert-check" %in% sc_lints(list("R/a.R" = ok))$rule, info = ok)
  }
})

test_that("SC8 D10 T32: no rule but inert-check reads a script's code (tar-name, dict-assign, lookup phrases)", {
  x <- sc_lints(list("R/a.R" = c("claim(x, . > 0)", "y <- tar_read(fit)", "dict$k <- 3",
                                 "lookup(n, \"one\", \"two\")")))
  expect_identical(nrow(x), 0L)
})

test_that("SC2 T33: a script holding only a claim is read, so lints() counts it as a file", {
  x <- sc_lints(list("R/functions.R" = SC_FN, "a.qmd" = SC_DOC))
  expect_identical(attr(x, "n_files"), 2L)
})

test_that("M1 SC2 T34: a script holding claim( and no weft that does not parse is noted by lints() and checks()", {
  root <- lint_proj(list("R/a.R" = "claim(x, . > 1"), weft_yml = "draft: false")
  want <- "`R/a.R` does not parse as R, so its weft() strings and claim() calls were not read."
  expect_true(any(grepl(want, sc_clean(attr(lints(root, tier = 1:2), "notes")), fixed = TRUE)))
  expect_true(any(grepl(want, sc_clean(attr(checks(root), "notes")), fixed = TRUE)))
})

test_that("SC8 T35: a claim in a script's code that is not inert gives no finding", {
  x <- sc_lints(list("R/a.R" = c("claim(n, . > 10)", "weft(\"plain words\")")))
  expect_identical(nrow(x), 0L)
})

# ---- verify(): T36 to T39 ---------------------------------------------------------------------------------

sc_vproj <- function(files, env = parent.frame()) {
  v4_env(env = env)
  v4_proj(c(list("doc.qmd" = G_PROSE), files, DP_FILES), git = TRUE, weft_yml = DP_YML, env = env)
}

test_that("SC10 T36: a script claim's literal decision that does not resolve fails the decisions part; a computed one is not checked", {
  p <- sc_vproj(list("R/a.R" = c("n <- 1", "claim(n, . > 0, decision = 99)", "d <- 98", "claim(n, . > 0, decision = d)")))
  r <- v4_verify(p$root, static = TRUE)
  dp_expect_failed(r)
  expect_identical(v4_status(r$res, "decisions"), "failed")
  rows <- dp_rows(r$res, "a.R")
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$decision, "99")
  expect_identical(rows$line, 2L)
  expect_identical(rows$key, "claim()")
  expect_identical(rows$resolved, FALSE)
})

test_that("SC10 T36: a script claim's decision that resolves passes (control)", {
  p <- sc_vproj(list("R/a.R" = "claim(n, . > 0, decision = 12)"))
  r <- v4_verify(p$root, static = TRUE)
  dp_expect_passed(r)
  expect_identical(dp_rows(r$value, "a.R")$resolved, TRUE)
})

test_that("SC10 T37: with files = a script, only that script's pointers are checked", {
  p <- sc_vproj(list("R/a.R" = "claim(n, . > 0, decision = 12)", "R/b.R" = "claim(n, . > 0, decision = 99)"))
  r <- v4_verify(p$root, static = TRUE, files = "R/a.R")
  dp_expect_passed(r)
  expect_false(any(basename(r$value$decisions$file) == "b.R"))
  expect_identical(nrow(dp_rows(r$value, "a.R")), 1L)
})

test_that("SC9 T38: since a commit that removed a script claim, verify() lists the removal and fails nothing", {
  v4_env()
  p <- v4_proj(list("doc.qmd" = G_PROSE, "R/a.R" = c("x <- 1", "claim(x, . > 1)")), git = TRUE)
  base <- g_head(p$top)
  g_apply(p$top, list("R/a.R" = "x <- 1"))
  g_add(p$top)
  g_commit(p$top, "Drop the claim\n\nWeft-Removed: 1")
  r <- v4_verify(p$root, since = base, static = TRUE)
  expect_null(r$err, label = if (!is.null(r$err)) conditionMessage(r$err) else "no error")
  expect_identical(nrow(r$res$removed), 1L)
  expect_identical(r$res$removed$file, "R/a.R")
  expect_identical(r$res$removed$kind, "claim")
})

test_that("SC9 T39: a claim(x, TRUE) in the baseline is tolerated: verify() passes and reports the total", {
  v4_env()
  p <- v4_proj(list("doc.qmd" = G_PROSE, "R/a.R" = "claim(x, TRUE)"), git = TRUE)
  r <- v4_verify(p$root, static = TRUE)
  expect_null(r$err, label = if (!is.null(r$err)) conditionMessage(r$err) else "no error")
  expect_identical(r$value$tolerated$rule, "inert-check")
  expect_identical(r$value$tolerated$n, 1L)
})

# ---- runtime and the reports that do not change: T40 to T44 -----------------------------------------------

test_that("SC12 T40: source() of a script claim writes nothing, passing or failing (control)", {
  v4_env()
  root <- lint_proj(list("R/ok.R" = "weft::claim(5, . > 0)", "R/bad.R" = "weft::claim(5, . < 0)"),
                    weft_yml = "draft: false")
  withr::local_dir(root)
  snap <- function() sort(list.files(root, recursive = TRUE, all.files = TRUE, include.dirs = TRUE))
  before <- snap()
  source(file.path(root, "R/ok.R"), local = new.env())
  expect_identical(snap(), before)
  expect_error(source(file.path(root, "R/bad.R"), local = new.env()), class = "weft_claim_failed")
  expect_identical(snap(), before)
})

test_that("SC11 T41: changes() prints the same with a claim added to a script (nothing rendered)", {
  skip_if(Sys.which("git") == "")
  before <- list("a.qmd" = c("# A {#sec-a}", "", "Opening text here.", ""), "R/a.R" = "x <- 1")
  d0 <- f3d_scenario(before)
  d1 <- f3d_scenario(before, list("R/a.R" = c("x <- 1", "claim(x, . > 0)")))
  expect_identical(f3d_print(changes(path = d1)), f3d_print(changes(path = d0)))
})

test_that("SC11 T42: arms() of a script with only code claims lists no arms and no errors (control)", {
  root <- lint_proj(list("R/a.R" = "claim(x, . > 0)"), weft_yml = "draft: false")
  x <- arms(file.path(root, "R/a.R"))
  expect_identical(nrow(x), 0L)
})

test_that("SC4 T44: a warm gate on 50 scripts of 200 lines with five claims each reads none, and costs about what 5 scripts cost", {
  skip_on_cran()
  withr::local_options(weft.gate_cache = TRUE)
  script <- function(k) c(sprintf("v_%d_%d <- %d", k, 1:195, 1:195),
                          sprintf("claim(v_%d_1, . > %d)", k, 0:4))
  run <- function(n) {
    files <- stats::setNames(lapply(seq_len(n), script), sprintf("R/s%02d.R", seq_len(n)))
    d <- g_repo(c(list("a.qmd" = SC_DOC), files))
    edit <- function(txt) {
      g_write(d, "R/s01.R", c(files[[1]], txt))
      g_add(d)
    }
    edit("# first")
    g_gate(d)
    g_commit(d, "first")
    edit("# second")
    secs <- cpu_time(g_gate(d), children = TRUE)
    reads <- g_count_reads(g_gate(d))
    g_commit(d, "second")
    # the claims are really counted: dropping one of the five is one removal
    g_write(d, "R/s01.R", files[[1]][-length(files[[1]])])
    g_add(d)
    list(secs = secs, reads = reads, removed = g_gate(d)$n_removed)
  }
  small <- run(5L)
  large <- run(50L)
  expect_identical(small$removed, 1L)
  expect_identical(large$removed, 1L)
  expect_identical(large$reads, 0L)
  expect_lt(large$secs / max(small$secs, 0.05), 3)
})

# Ruling 27 Nov: `decision` is not a check (3.10.1, 3.1.12), so a literal pointer is not an inert check,
# in a script or in an R chunk.
test_that("3.10.1: a literal decision = 12 on a claim is not an inert check", {
  expect_false("inert-check" %in% sc_lints(list("R/a.R" = "claim(x, . > 0, decision = 12)"))$rule)
  expect_true("inert-check" %in% sc_lints(list("R/a.R" = "claim(x, 1 > 0, decision = 12)"))$rule)
})
