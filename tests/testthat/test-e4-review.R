# Fix round for package E4 (dev/review-e4.md, K1 to K21). Written before the fixes. No R under R/ was read.

K_M1 <- "The setting `scripts_skip` must be a list of folder or file names, or paths from the project root (rule 9.1.4)."
k_clean <- function(x) cli::ansi_strip(x)
k_num <- function(files, ..., rule = "numeral") {
  root <- lint_proj(files, weft_yml = "draft: false")
  lints(root, rules = rule, tier = 1:2, ...)
}
k_text <- function(line) k_num(list("R/a.R" = line))$text

# ---- K1: the line is the source line of the first character ------------------------------------------------

K1_LINE <- "weft(\"Total:\\nWe saw [a site | # sites]{n='k'}\")"
K1_PAD <- c("x <- 1", "y <- 2", "z <- 3", "w <- 4")

test_that("K1: arms() of a script gives the line of the literal after an escaped newline", {
  root <- lint_proj(list("R/a.R" = c(K1_PAD, K1_LINE)), weft_yml = "draft: false")
  x <- arms(file.path(root, "R/a.R"))
  expect_gte(nrow(x), 1L)
  expect_true(all(x$line == 5L))
})

test_that("K1: arms() of a document chunk gives the line of the literal after an escaped newline", {
  doc <- c("Intro.", "", "```{r}", "x <- 1", K1_LINE, "```")
  root <- lint_proj(list("doc.qmd" = doc), weft_yml = "draft: false")
  x <- arms(file.path(root, "doc.qmd"))
  expect_gte(nrow(x), 1L)
  expect_true(all(x$line == 5L))
})

test_that("K1: a construct finding in a script after an escaped newline is on the line of the call", {
  line <- "weft(\"Total:\\nWe saw [ok]{if='a >'}\")"
  f <- k_num(list("R/a.R" = c(K1_PAD, line)), rule = "construct")
  expect_identical(nrow(f), 1L)
  expect_identical(f$line, 5L)
})

test_that("K1: the gate lists a removed construct after an escaped newline at its source line", {
  val <- "weft(\"Total:\\nFound `r k`{.num} sites\")"
  d <- g_scenario(list("a.qmd" = c("Plain words here.", ""), "R/a.R" = c(K1_PAD, val)), list("R/a.R" = NULL))
  res <- g_gate(d)
  expect_identical(res$n_removed, 1L)
  expect_identical(res$removed$line, 5L)
})

# ---- K2: the function position must be the symbol weft -----------------------------------------------------

test_that("K2: obj$weft(), env$weft() and x@weft() are not weft calls", {
  for (code in c("obj$weft(\"Saw 12\")", "env$weft(\"Saw 12\")", "x@weft(\"Saw 12\")", "a$b$weft(\"Saw 12\")")) {
    expect_identical(k_text(code), character(), label = code)
  }
})

test_that("K2: weft::weft() is still a weft call", {
  expect_identical(k_text("weft::weft(\"Saw 12\")"), "12")
})

# ---- K3: pipes ---------------------------------------------------------------------------------------------

test_that("K3: a piped string with a positional argument after it is the first argument", {
  expect_identical(k_text("\"Saw 12\" |> weft(e)"), "12")
})

test_that("K3: a piped environment is not the string; a named x is", {
  expect_identical(k_text("env |> weft(\"Saw 12\")"), character())
  expect_identical(k_text("\"Saw 12\" |> weft(.envir = e)"), "12")
})

test_that("K3: the native placeholder x = _ and the magrittr dot put the string where they stand", {
  expect_identical(k_text("\"Saw 12\" |> weft(x = _)"), "12")
  expect_identical(k_text("\"Saw 12\" %>% weft(.)"), "12")
  expect_identical(k_text("\"Saw 12\" %>% weft(., e)"), "12")
})

test_that("K3: a magrittr pipe into weft without parentheses is read", {
  expect_identical(k_text("\"Saw 12\" %>% weft"), "12")
})

# ---- K4, K5, K11: scripts_skip -----------------------------------------------------------------------------

test_that("K4: a nested _weft.yml decides skipping for the scripts under it, relative to its folder", {
  root <- lint_proj(list("tests/a.R" = E4_LINE, "sub/tests/a.R" = E4_LINE, "sub/_weft.yml" = c("scripts_skip: []")),
                    weft_yml = "draft: false")
  f <- lints(root)
  expect_true("sub/tests/a.R" %in% f$file)
  expect_false("tests/a.R" %in% f$file)
})

test_that("K5: a null scripts_skip keeps the default, tests", {
  for (v in list("scripts_skip: ~", "scripts_skip:", "scripts_skip: null")) {
    root <- lint_proj(list("tests/a.R" = E4_LINE, "R/b.R" = E4_LINE), weft_yml = c("draft: false", v))
    f <- lints(root)
    expect_false("tests/a.R" %in% f$file, label = v)
    expect_true("R/b.R" %in% f$file, label = v)
  }
})

test_that("K11: scripts_skip entries with a wildcard, a leading slash or a backslash are M1", {
  for (v in c("\"*.R\"", "\"a?.R\"", "\"/R\"", "\"R\\\\x\"")) {
    root <- lint_proj(list("R/a.R" = E4_LINE), weft_yml = c("draft: false", paste0("scripts_skip: [", v, "]")))
    e <- f2_cond(lints(root))
    expect_true(inherits(e, "weft_config_error"), label = v)
    expect_true(grepl(K_M1, k_clean(conditionMessage(e)), fixed = TRUE), label = v)
  }
})

# ---- K6: a skipped script named gives a note ---------------------------------------------------------------

test_that("K6: lints() on a skipped script, by path or by files, notes scripts_skip and the name", {
  root <- lint_proj(list("tests/a.R" = E4_LINE, "R/b.R" = E4_LINE), weft_yml = "draft: false")
  for (f in list(lints(file.path(root, "tests/a.R")), lints(root, files = "tests/a.R"))) {
    expect_identical(nrow(f), 0L)
    notes <- k_clean(attr(f, "notes"))
    expect_true(any(grepl("tests/a.R", notes, fixed = TRUE) & grepl("scripts_skip", notes, fixed = TRUE)))
  }
})

test_that("K6: checks() on a skipped script named in files or path notes scripts_skip", {
  root <- lint_proj(list("tests/a.R" = "weft(\"[ok]{if='n_sites > 3'}\")"), weft_yml = "draft: false")
  # ambiguity: checks() is assumed to take path = a file, as lints() does
  x <- checks(file.path(root, "tests/a.R"))
  notes <- k_clean(attr(x, "notes"))
  expect_true(any(grepl("tests/a.R", notes, fixed = TRUE) & grepl("scripts_skip", notes, fixed = TRUE)))
})

# ---- K7: the pandoc reader ---------------------------------------------------------------------------------

test_that("K7: lints(reader = 'pandoc') still reports a script's numeral", {
  n3_skip_no_pandoc()
  root <- lint_proj(list("R/a.R" = E4_LINE), weft_yml = "draft: false")
  f <- lints(root, reader = "pandoc", rules = "numeral", tier = 1:2)
  expect_identical(f$file, "R/a.R")
  expect_identical(f$text, "12")
})

# ---- K8: n_files -------------------------------------------------------------------------------------------

test_that("K8: lints() and checks() count the same files; skipped scripts and scripts with no weft are not counted", {
  root <- lint_proj(list("a.qmd" = c("Plain words here.", ""), "R/b.R" = "weft(\"plain\")", "R/none.R" = "x <- 1",
                         "tests/c.R" = E4_LINE), weft_yml = "draft: false")
  l <- lints(root)
  ch <- checks(root)
  # lints() calls its count n_files; checks() calls it documents
  expect_identical(attr(l, "n_files"), attr(ch, "documents"))
  expect_identical(attr(l, "n_files"), 2L)
})

# ---- K9: checks() notes an unparsable script ---------------------------------------------------------------

test_that("K9: checks() notes a script that does not parse", {
  root <- lint_proj(list("R/a.R" = "weft(\"[ok]{if='n > 3'}\""), weft_yml = "draft: false")
  x <- checks(root)
  notes <- k_clean(attr(x, "notes"))
  expect_true(any(grepl("`R/a.R` does not parse as R", notes, fixed = TRUE)))
})

# ---- K13: the gate does not take skipped or weft-free scripts as documents ---------------------------------

test_that("K13: scripts with no weft, and scripts under tests/, add no gate cache entries", {
  # ambiguity: observed from outside as the number of cache files, which is assumed to grow with each gate document
  withr::local_options(weft.gate_cache = TRUE)
  base <- list("a.qmd" = G_PROSE)
  d1 <- g_scenario(base, list("a.qmd" = g_num_doc("45%")))
  g_gate(d1)
  n1 <- length(g_cache_files(d1))
  more <- c(base, list("R/none.R" = "x <- 1", "R/other.R" = "y <- 2", "tests/t.R" = "weft(\"We saw 12\")"))
  d2 <- g_scenario(more, list("a.qmd" = g_num_doc("45%")))
  g_gate(d2)
  expect_identical(length(g_cache_files(d2)), n1)
})

# ---- K17: verify(files = ) error text ----------------------------------------------------------------------

test_that("K17: verify(files = 'x.txt') gives M3's text, as checks() does", {
  v4_env()
  p <- v4_proj(list("a.qmd" = G_PROSE, "x.txt" = "hello"), git = TRUE)
  r <- v4_verify(p$root, static = TRUE, files = "x.txt")
  expect_false(is.null(r$err))
  msg <- k_clean(conditionMessage(r$err))
  expect_true(grepl("`files` must name existing .qmd, .Rmd or .R files under the project root; not so: ",
                    msg, fixed = TRUE))
  expect_true(grepl("x.txt", msg, fixed = TRUE))
  expect_true(grepl("(rule 5.1.1)", msg, fixed = TRUE))
})

# ---- K20: a block-quoted chunk ----------------------------------------------------------------------------

test_that("K20: a numeral in a weft() literal in a block-quoted chunk is found", {
  doc <- c("Intro.", "", "> ```{r}", "> weft(\"Saw 12\")", "> ```", "")
  x <- lint_one(doc, rules = "numeral")
  expect_true("12" %in% x$text)
  expect_true("weft" %in% x$context[x$text == "12"])
})
