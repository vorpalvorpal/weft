# Package E4 (dev/design-e4.md): scripts in lints(), arms(), checks(), changes(), verify(); the ledger is unchanged.
# T1 to T3, T6 to T9, T12, T14 to T16. Written before the code. No R under R/ was read.

E4_LINE <- "weft(\"We found 12 sites\")"
E4_PLOT <- c("library(ggplot2)", "p <- labs(title = weft(\"We found 12 sites\"))")

e4_clean <- function(x) cli::ansi_strip(x)
e4_files <- function(paths, line = E4_LINE) stats::setNames(rep(list(line), length(paths)), paths)

# ---- T1: a script is read ----------------------------------------------------------------------------------

test_that("T1 C1/C12/C14: a script is read and its numeral is reported at its position", {
  root <- lint_proj(list("R/plot.R" = E4_PLOT), weft_yml = "draft: false")
  f <- lints(root)
  expect_identical(nrow(f), 1L)
  expect_identical(f$file, "R/plot.R")
  expect_identical(f$line, 2L)
  expect_identical(f$col, 34L)
  expect_identical(f$rule, "numeral")
  expect_identical(f$context, "weft")
  expect_identical(f$text, "12")
  g <- lints(file.path(root, "R/plot.R"))
  expect_identical(g$file, f$file)
  expect_identical(g$line, f$line)
  expect_identical(g$col, f$col)
  expect_identical(g$rule, f$rule)
  h <- lints(root, files = "R/plot.R")
  expect_identical(h$file, f$file)
  expect_identical(h$line, f$line)
  expect_identical(h$col, f$col)
})

test_that("T1 C12: path may be a folder; the scripts reported are those under it", {
  root <- lint_proj(list("R/plot.R" = E4_PLOT, "other/b.R" = E4_LINE), weft_yml = "draft: false")
  f <- lints(file.path(root, "R"))
  expect_identical(unique(f$file), "R/plot.R")
})

# ---- T2: which scripts -------------------------------------------------------------------------------------

E4_READ <- c("analysis.R", "x.r", "_targets.R", "R/_helpers.R", "scripts/deep/a.R")
E4_FIXED <- c("renv/a.R", "packrat/a.R", "node_modules/a.R", ".hidden/a.R", "_site/a.R", "_freeze/a.R",
              "_targets/a.R", "_extensions/a.R")
E4_TESTS <- c("tests/testthat/test-a.R", "tests/a.R")

test_that("T2 C1/C2: the scripts read by default, and those left out", {
  root <- lint_proj(e4_files(c(E4_READ, E4_FIXED, E4_TESTS)), weft_yml = "draft: false")
  f <- lints(root)
  expect_setequal(unique(f$file), E4_READ)
})

test_that("T2 C2: a given scripts_skip replaces the default, by name and by path", {
  paths <- c("tests/a.R", "scratch/a.R", "R/scratch/b.R", "R/old.R", "old.R")
  root <- lint_proj(e4_files(paths), weft_yml = c("draft: false", "scripts_skip: [scratch, R/old.R]"))
  f <- lints(root)
  expect_setequal(unique(f$file), c("tests/a.R", "old.R"))
})

test_that("T2 C2: scripts_skip: [] reads every script outside the fixed exclusions", {
  root <- lint_proj(e4_files(c(E4_READ, E4_FIXED, E4_TESTS)), weft_yml = c("draft: false", "scripts_skip: []"))
  f <- lints(root)
  expect_setequal(unique(f$file), c(E4_READ, E4_TESTS))
})

test_that("T2 C2: a path entry skips every script under that folder, a leading ./ and trailing / are dropped", {
  root <- lint_proj(e4_files(c("R/a.R", "R/deep/b.R", "keep/c.R")),
                    weft_yml = c("draft: false", "scripts_skip: ['./R/']"))
  expect_setequal(unique(lints(root)$file), "keep/c.R")
})

test_that("T2 C2: a name entry matches a file name as well as a folder", {
  root <- lint_proj(e4_files(c("R/old.R", "R/new.R")), weft_yml = c("draft: false", "scripts_skip: [old.R]"))
  expect_setequal(unique(lints(root)$file), "R/new.R")
})

test_that("T2 C2: one string is read as a list of one", {
  root <- lint_proj(e4_files(c("scratch/a.R", "R/b.R")), weft_yml = c("draft: false", "scripts_skip: scratch"))
  expect_setequal(unique(lints(root)$file), "R/b.R")
})

# ---- T3: the setting ---------------------------------------------------------------------------------------

test_that("T3 C2/M1: scripts_skip that is not a list of non-empty strings is a weft_config_error with M1", {
  m1 <- "The setting `scripts_skip` must be a list of folder or file names, or paths from the project root (rule 9.1.4)."
  for (v in c("scripts_skip: 3", "scripts_skip: [\"\"]")) {
    root <- lint_proj(list("R/a.R" = E4_LINE), weft_yml = c("draft: false", v))
    e <- f2_cond(lints(root))
    expect_false(is.null(e), label = v)
    expect_true(inherits(e, "weft_config_error"), label = v)
    expect_true(grepl(m1, e4_clean(conditionMessage(e)), fixed = TRUE), label = v)
  }
})

test_that("T3 C2: scripts_skip in a document's front matter, where _weft.yml exists, is a config-place finding", {
  doc <- c("---", "title: t", "weft:", "  scripts_skip: [x]", "---", "", "Words here.")
  x <- lint_fixture(list("doc.qmd" = doc), rules = "config-place", weft_yml = "draft: false")
  expect_gte(nrow(x), 1L)
  expect_true(all(x$rule == "config-place"))
  expect_identical(x$file[[1]], "doc.qmd")
})

# ---- T6: rules on scripts ----------------------------------------------------------------------------------

E4_SCRIPT_RULES <- c("numeral", "construct", "read", "block-start", "lone-bar", "if-zero", "name",
                     "inert-check", "long-guard", "claim-word", "literal-value", "value-constant", "value-format")

test_that("T6 C13: lint_rules() has a logical column scripts, TRUE exactly for the thirteen ids", {
  r <- as.data.frame(unclass(lint_rules()), stringsAsFactors = FALSE)
  expect_true("scripts" %in% names(r))
  expect_type(r$scripts, "logical")
  expect_setequal(r$id[r$scripts], E4_SCRIPT_RULES)
  expect_false(anyNA(r$scripts))
})

e4_one <- function(line, ...) {
  root <- lint_proj(list("R/a.R" = line), weft_yml = "draft: false")
  lints(root, ...)
}

test_that("T6 C13: inert-check and literal-value rules run on a script's weft() literals", {
  x <- e4_one("weft(\"[x]{if='5 > 3'}\")", tier = 1:2)
  expect_true("inert-check" %in% x$rule)
  expect_true(all(x$file == "R/a.R"))
  y <- e4_one("weft(\"`r 12`{.num}\")", tier = 1)
  expect_true("literal-value" %in% y$rule)
})

test_that("T6 C13/D11: document-only rules give nothing on a script", {
  x <- e4_one("weft(\"See @fig-missing and [@nokey]\")", tier = 1:2)
  expect_false(any(x$rule %in% c("xref", "cite-key", "citation-key")))
  expect_false("above-setup" %in% x$rule)
  y <- e4_one(c("weft(\"plain words\")", "x <- 1"), tier = 1:2)
  expect_false("above-setup" %in% y$rule)
})

test_that("T6 C16: a claim() in a script's code, outside a literal, is read by no rule", {
  x <- e4_one(c("claim(n, . > 10)", "weft(\"plain words\")"), tier = 1:2)
  expect_identical(nrow(x), 0L)
})

test_that("T6 C16: the phrases of lookup() and brk() in a script are not read", {
  x <- e4_one(c("weft(\"plain words\")", "lookup(k, c(low = \"below 12\"))", "brk(c(a = \"over 12\"))"), tier = 1:2)
  expect_identical(nrow(x), 0L)
})

test_that("T6 C16: a string given to another function is not read", {
  x <- e4_one(c("weft(\"plain words\")", "title <- paste(\"We found 12 sites [x]{if='a >'}\")"), tier = 1:2)
  expect_identical(nrow(x), 0L)
})

# ---- T7: encodings and parse failures ----------------------------------------------------------------------

E4_READ_MSG <- "`R/a.R` is not valid UTF-8; save the file as UTF-8 (rule 5.1.3)."

test_that("T7 C3: a Latin-1 script that holds weft gives exactly one read finding", {
  bytes <- c(charToRaw("weft(\"caf"), as.raw(0xe9), charToRaw(" 12\")\n"))
  root <- lint_proj(list("R/a.R" = bytes), weft_yml = "draft: false")
  f <- lints(root, tier = 1:2)
  expect_identical(nrow(f), 1L)
  expect_identical(f$rule, "read")
  expect_identical(f$file, "R/a.R")
  expect_identical(f$line, 1L)
  expect_identical(f$col, 1L)
  expect_identical(e4_clean(f$message), E4_READ_MSG)
})

test_that("T7 C3: a Latin-1 script with no weft in it gives nothing", {
  bytes <- c(charToRaw("x <- \"caf"), as.raw(0xe9), charToRaw("\"\n"))
  root <- lint_proj(list("R/a.R" = bytes), weft_yml = "draft: false")
  expect_identical(nrow(lints(root, tier = 1:2)), 0L)
})

test_that("T7 C3: a script with a NUL byte and weft gives read", {
  bytes <- c(charToRaw("weft(\"a\")"), as.raw(0L), charToRaw("\n"))
  root <- lint_proj(list("R/a.R" = bytes), weft_yml = "draft: false")
  f <- lints(root, tier = 1:2)
  expect_identical(f$rule, "read")
})

test_that("T7 C3: a CRLF script reports a numeral at the same line and column as the LF one", {
  lines <- c("x <- 1", "p <- labs(title = weft(\"We found 12 sites\"))")
  lf <- lints(lint_proj(list("R/a.R" = lines), weft_yml = "draft: false"))
  crlf <- lints(lint_proj(list("R/a.R" = list(lines = lines, eol = "\r\n")), weft_yml = "draft: false"))
  expect_identical(nrow(lf), 1L)
  expect_identical(crlf$line, lf$line)
  expect_identical(crlf$col, lf$col)
})

test_that("T7 C3: a UTF-8 byte-order mark is dropped and does not shift columns", {
  lines <- "weft(\"We found 12 sites\")"
  x <- lints(lint_proj(list("R/a.R" = list(lines = lines, bom = TRUE)), weft_yml = "draft: false"))
  expect_identical(x$col, 17L)
})

test_that("T7 C4/M2: a script that does not parse gives no finding, and lints() notes it", {
  root <- lint_proj(list("R/a.R" = "weft(\"Saw 12\""), weft_yml = "draft: false")
  f <- lints(root, tier = 1:2)
  expect_identical(nrow(f), 0L)
  notes <- e4_clean(attr(f, "notes"))
  expect_true(any(grepl("`R/a.R` does not parse as R, so its weft() strings were not read.", notes, fixed = TRUE)))
})

# ---- T8: the files argument --------------------------------------------------------------------------------

test_that("T8 M3: files naming a non-script file or a missing one is a weft_lint_error with M3's text", {
  root <- lint_proj(list("R/a.py" = "print(1)", "R/a.R" = E4_LINE), weft_yml = "draft: false")
  for (bad in c("R/a.py", "R/missing.R")) {
    e <- f2_cond(lints(root, files = bad))
    expect_true(inherits(e, "weft_lint_error"), label = bad)
    msg <- e4_clean(conditionMessage(e))
    expect_true(grepl("`files` must name existing .qmd, .Rmd or .R files under the project root; not so: ",
                      msg, fixed = TRUE), label = bad)
    expect_true(grepl(bad, msg, fixed = TRUE), label = bad)
    expect_true(grepl("(rule 5.1.1)", msg, fixed = TRUE), label = bad)
  }
})

test_that("T8 C12: files may name a document and a script together, and both are reported", {
  root <- lint_proj(list("doc.qmd" = c("We found 12 sites in the survey.", ""), "R/a.R" = E4_LINE),
                    weft_yml = "draft: false")
  f <- lints(root, files = c("doc.qmd", "R/a.R"), rules = "numeral")
  expect_setequal(unique(f$file), c("doc.qmd", "R/a.R"))
})

# ---- T9: project rules ignore scripts ----------------------------------------------------------------------

test_that("T9 C12: project-scope rules never report a script", {
  root <- lint_proj(list("doc.qmd" = c("See @fig-a for it.", ""), "R/a.R" = "weft(\"@fig-b\")"),
                    weft_yml = "draft: false")
  f <- lints(root, tier = 1:2)
  x <- f[f$rule == "xref", ]
  expect_gte(nrow(x), 1L)
  expect_true(all(x$file == "doc.qmd"))
  expect_false(any(f$file[f$rule %in% c("xref", "cite-key", "citation-key")] == "R/a.R"))
})

# ---- T12: arms() -------------------------------------------------------------------------------------------

test_that("T12 C15: arms() of a script lists the spans of its weft() literals with context weft", {
  root <- lint_proj(list("R/a.R" = c("k <- 3", "", "weft(\"[one site | # sites]{n='k'}\")")), weft_yml = "draft: false")
  x <- arms(file.path(root, "R/a.R"))
  expect_identical(nrow(x), 2L)
  expect_true(all(x$context == "weft"))
  expect_true(all(x$line == 3L))
  expect_true(all(x$key == "n"))
  expect_true(all(x$expr == "k"))
  expect_setequal(x$role, c("one", "other"))
})

test_that("T12 C15: arms() of a script that does not parse lists nothing and raises nothing", {
  root <- lint_proj(list("R/a.R" = "weft(\"[one site | # sites]{n='k'}\""), weft_yml = "draft: false")
  x <- arms(file.path(root, "R/a.R"))
  expect_identical(nrow(x), 0L)
})

test_that("T12 C15: arms() does not apply scripts_skip: a script under tests/ is read when named", {
  root <- lint_proj(list("tests/a.R" = "weft(\"[one site | # sites]{n='k'}\")"), weft_yml = "draft: false")
  x <- arms(file.path(root, "tests/a.R"))
  expect_identical(nrow(x), 2L)
})

test_that("T12 C15: a file named .r is read as a script too", {
  root <- lint_proj(list("a.r" = "weft(\"[one site | # sites]{n='k'}\")"), weft_yml = "draft: false")
  expect_identical(nrow(arms(file.path(root, "a.r"))), 2L)
})

# ---- T14: checks() and changes() ---------------------------------------------------------------------------

test_that("T14 C15: checks() lists a guard inside a weft() literal of a script, with the script as file", {
  root <- lint_proj(list("R/a.R" = "weft(\"[ok]{if='n_sites > 3'}\")"), weft_yml = "draft: false")
  x <- checks(root)
  expect_gte(nrow(x), 1L)
  expect_true("R/a.R" %in% x$file)
})

test_that("T14 C15/D13: a claim() in a script's code outside a literal is not listed by checks()", {
  root <- lint_proj(list("R/a.R" = c("claim(n, . > 10)", "weft(\"plain\")")), weft_yml = "draft: false")
  x <- checks(root)
  expect_false("R/a.R" %in% x$file)
})

test_that("T14 C15: changes() lists a tier-2 finding on a line added to a script", {
  skip_if(Sys.which("git") == "")
  before <- list("a.qmd" = c("# A {#sec-a}", "", "Opening text here.", ""))
  # design ambiguity: the script is a new, untracked file, as f3d_scenario() makes new files for documents
  after <- list("R/a.R" = c("x <- 1", "weft(\"[a | b]\")"))
  dir <- f3d_scenario(before, after)
  f <- changes(path = dir)$findings
  expect_true("lone-bar" %in% f$rule)
  r <- f[f$rule == "lone-bar", ]
  expect_identical(r$file[[1]], "R/a.R")
  expect_identical(r$line[[1]], 2L)
})

# ---- T15: verify() -----------------------------------------------------------------------------------------

test_that("T15 C15: verify() counts a script's numeral as it counts a document's", {
  v4_env()
  ps <- v4_proj(list("a.qmd" = G_PROSE, "R/a.R" = "weft(\"We found 12 sites\")"), git = TRUE)
  rs <- v4_verify(ps$root, static = TRUE)
  pd <- v4_proj(list("a.qmd" = g_num_doc("45%")), git = TRUE)
  rd <- v4_verify(pd$root, static = TRUE)
  # control: a document's numeral in HEAD is tolerated
  expect_identical(nrow(rd$res$tolerated), 1L)
  expect_identical(nrow(rs$res$tolerated), 1L)
  expect_identical(rs$res$tolerated$rule, "numeral")
  expect_identical(rs$res$tolerated$file, "R/a.R")
})

test_that("T15 C15: verify(files = ) takes a script", {
  v4_env()
  p <- v4_proj(list("a.qmd" = G_PROSE, "R/a.R" = "weft(\"We found 12 sites\")"), git = TRUE)
  r <- v4_verify(p$root, static = TRUE, files = "R/a.R")
  expect_null(r$err, label = if (!is.null(r$err)) conditionMessage(r$err) else "no error")
})

# ---- T16: the ledger is unchanged --------------------------------------------------------------------------

test_that("T16 C18/D15: a weft() call in a sourced script records the knitted document as file, context weft", {
  body <- c("```{r fig-a}", "f()", "```")
  res <- d2_render(body, code = c("k <- 3", "source('R/f.R')"),
                   files = list("R/f.R" = "f <- function() weft(\"[one | # sites]{n='k'}\")"))
  entries <- d2_ledger(res)
  w <- Filter(function(e) identical(e$context, "weft"), entries)
  expect_gte(length(w), 1L)
  for (e in w) expect_identical(e$file, "doc.Rmd")
  expect_false(any(vapply(entries, function(e) grepl("f\\.R$", as.character(e$file)[[1]]), NA)))
})
