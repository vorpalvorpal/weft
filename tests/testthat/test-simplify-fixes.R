# Four behaviour fixes found by the simplify review (Batch 0, B1 to B4). Written from the rulings
# before the fixes; no R under R/ was read. Non-ASCII is written as \u escapes: \u00a0 is a
# no-break space.
#   B1: the gate obeys the project's scripts_skip (dev/review-e4.md K4, K13; rule 5.1.9).
#   B2: `\ ` in weft() prose is a no-break space in the plain form (dev/review-e1.md F13, PL1).
#   B3: a weft() string in a !expr caption is masked the same inside a block quote (K20, C9).
#   B4: dict_glossary() does not pin the units for the session (F1; decisions "units have an origin").

# ---- B1: the gate obeys scripts_skip ----------------------------------------------------------------

sf_val <- "x <- weft(\"Found `r k`{.num} sites\")"
sf_doc <- c("Plain words here.", "")

test_that("B1: with scripts_skip: [build], a construct removed from build/x.R is not counted", {
  d <- g_scenario(list("a.qmd" = sf_doc, "build/x.R" = sf_val), list("build/x.R" = "x <- 1"),
                  weft_yml = c("draft: false", "scripts_skip: [build]"))
  res <- g_gate(d)
  expect_identical(res$n_removed, 0L)
  expect_identical(nrow(res$removed), 0L)
  expect_true(res$ok)
})

test_that("B1 (control): with the default scripts_skip, the same removal in build/x.R is counted", {
  d <- g_scenario(list("a.qmd" = sf_doc, "build/x.R" = sf_val), list("build/x.R" = "x <- 1"),
                  weft_yml = "draft: false")
  res <- g_gate(d)
  expect_identical(res$n_removed, 1L)
  expect_false(res$ok)
})

test_that("B1: with scripts_skip: [build], a typed numeral added in build/x.R is not judged", {
  d <- g_scenario(list("a.qmd" = sf_doc, "build/x.R" = sf_val),
                  list("build/x.R" = "x <- weft(\"Found 12 sites\")"),
                  weft_yml = c("draft: false", "scripts_skip: [build]"))
  res <- g_gate(d)
  expect_identical(nrow(res$added), 0L)
  expect_identical(res$n_removed, 0L)
  expect_true(res$ok)
})

test_that("B1: with scripts_skip: [build], the default is replaced, so a construct removed from tests/t.R counts", {
  d <- g_scenario(list("a.qmd" = sf_doc, "tests/t.R" = sf_val), list("tests/t.R" = "x <- 1"),
                  weft_yml = c("draft: false", "scripts_skip: [build]"))
  res <- g_gate(d)
  expect_identical(res$n_removed, 1L)
  expect_false(res$ok)
})

test_that("B1: with scripts_skip: [], a construct removed from tests/t.R counts, as lints() reads it", {
  d <- g_scenario(list("a.qmd" = sf_doc, "tests/t.R" = sf_val), list("tests/t.R" = "x <- 1"),
                  weft_yml = c("draft: false", "scripts_skip: []"))
  res <- g_gate(d)
  expect_identical(res$n_removed, 1L)
  expect_true(any(grepl("tests/t\\.R$", res$removed$file)))
  expect_false(res$ok)
})

test_that("B1: with scripts_skip: [], a typed numeral added in tests/t.R fails the gate", {
  d <- g_scenario(list("a.qmd" = sf_doc), list("tests/t.R" = "weft(\"We saw 12\")"),
                  weft_yml = c("draft: false", "scripts_skip: []"))
  res <- g_gate(d)
  expect_false(res$ok)
  expect_true("numeral" %in% res$added$rule)
  expect_true(all(res$added$file[res$added$rule == "numeral"] == "tests/t.R"))
})

# ---- B2: a backslash-space is a no-break space ---------------------------------------------------

test_that("B2: `\\ ` in weft() prose is a no-break space in the plain form", {
  expect_identical(unname(format(weft("a\\ b"))), "a\u00a0b")
  expect_identical(as.character(weft("a\\ b")), "a\u00a0b")
  expect_identical(unname(format(weft("*a\\ b*"))), "a\u00a0b")
})

test_that("B2: the ANSI form, stripped, is the plain form with the no-break space", {
  withr::local_options(cli.num_colors = 256L)
  w <- weft("a\\ b")
  ansi <- format(w, target = "ansi")
  expect_identical(unname(cli::ansi_strip(ansi)), unname(format(w)))
  expect_identical(unname(cli::ansi_strip(ansi)), "a\u00a0b")
  expect_identical(unname(format(weft("*a\\ b*"), target = "ansi")), "\u001b[3ma\u00a0b\u001b[23m")
})

test_that("B2: inside a superscript, an escaped backslash and a code span, the readings stay", {
  expect_identical(unname(format(weft("x^a\\ b^"))), "x^(a\u00a0b)")
  # `\\` is a backslash, so the space after it is an ordinary space
  expect_identical(unname(format(weft("a\\\\ b"))), "a\\ b")
  # no rule applies inside a code span
  expect_identical(unname(format(weft("`a\\ b`"))), "a\\ b")
})

# ---- B3: a !expr caption's weft() string in a block-quoted chunk --------------------------------

# the findings of a document as comparable rows; `shift` is taken off the columns of lines that a
# block quote prefixes with "> "
sf_rows <- function(x, quoted_lines = integer(), shift = 0L) {
  df <- as.data.frame(unclass(x), stringsAsFactors = FALSE)
  keep <- intersect(c("rule", "line", "col", "text", "context"), names(df))
  df <- df[, keep, drop = FALSE]
  if (nrow(df) && "col" %in% keep) {
    q <- df$line %in% quoted_lines
    df$col[q] <- df$col[q] - shift
  }
  df <- df[do.call(order, unname(as.list(df))), , drop = FALSE]
  rownames(df) <- NULL
  df
}

sf_chunk <- function(cap) {
  c("```{r}", "#| label: fig-a", paste0("#| fig-cap: !expr ", cap), "plot(1)", "```")
}
sf_plain_doc  <- function(cap) c("Intro.", "", sf_chunk(cap), "")
sf_quoted_doc <- function(cap) c("Intro.", "", paste0("> ", sf_chunk(cap)), "")

B3_CAPS <- c(
  numeral = "weft(\"We saw 12 sites\")",
  span    = "weft(\"Depth at [a site | # sites]{n='k'}\")",
  mixed   = "weft(\"Depth *at* many, e.g. here -- and 1990s\")"
)
B3_CAP_LINE <- 5L

# Only the caption's line is compared: the label option's findings (figure, anchor-unused) are
# placed differently in a block quote today, which is outside this fix.
for (nm in names(B3_CAPS)) {
  test_that(paste0("B3 (", nm, "): a block-quoted chunk's !expr weft() caption gives the same findings as unquoted"), {
    cap <- B3_CAPS[[nm]]
    plain <- sf_rows(lint_one(sf_plain_doc(cap)))
    quoted <- sf_rows(lint_one(sf_quoted_doc(cap)), quoted_lines = 3:7, shift = 2L)
    plain <- plain[plain$line == B3_CAP_LINE, , drop = FALSE]
    quoted <- quoted[quoted$line == B3_CAP_LINE, , drop = FALSE]
    rownames(plain) <- rownames(quoted) <- NULL
    expect_identical(quoted, plain)
    # in particular, nothing in the caption string is read as prose
    expect_false(any(quoted$context == "prose"))
  })
}

test_that("B3: the quoted caption's typed numeral is one finding, read as a weft() string, not as prose", {
  x <- lint_one(sf_quoted_doc(B3_CAPS[["numeral"]]), rules = "numeral")
  expect_identical(sum(x$text == "12"), 1L)
  expect_identical(x$context[x$text == "12"], "weft")
  expect_identical(x$line[x$text == "12"], B3_CAP_LINE)
})

test_that("B3: the quoted caption's span is not a construct error", {
  x <- lint_one(sf_quoted_doc(B3_CAPS[["span"]]), rules = "construct")
  expect_identical(nrow(x), 0L)
})

# ---- B4: dict_glossary() does not pin the units ------------------------------------------------

sf_unit_yml <- c("units:", "  zze1rv:", "    is: 201.168 m", "    symbol: FF")

sf_root <- function(files = list(), env = parent.frame()) {
  root <- normalizePath(withr::local_tempdir(.local_envir = env))
  for (f in names(files)) writeLines(files[[f]], file.path(root, f), useBytes = TRUE)
  root
}

# dict_glossary() is the first call in A in each test: a weft() or fmt_*() call made in A before it
# reads the configuration first and hides the pin.

test_that("B4: after dict_glossary() in project A, weft() in B (no _weft.yml) has the default units", {
  weft:::string_config_reset()
  a <- sf_root(list("_weft.yml" = sf_unit_yml, dict.yml = c2_fixture_lines()))
  b <- sf_root()
  withr::local_dir(a)
  dict_glossary()
  setwd(b)
  # B has the default units: the unit is unknown there
  expect_error(weft("`r u(3, zze1rv)`{.num}"), "not a unit")
  # and A's file applies on going back
  setwd(a)
  expect_identical(as.character(weft("`r u(3, zze1rv)`{.num}")), "3\u00a0FF")
})

test_that("B4: after dict_glossary() in A, fmt_*() in B do not use A's units", {
  weft:::string_config_reset()
  a <- sf_root(list("_weft.yml" = sf_unit_yml, dict.yml = c2_fixture_lines()))
  b <- sf_root()
  withr::local_dir(a)
  dict_glossary()
  setwd(b)
  expect_error(fmt_num(u(3, zze1rv), target = "plain"), "not a unit")
  setwd(a)
  expect_no_error(fmt_num(u(3, zze1rv), target = "plain"))
})

test_that("B4: a dictionary given as an argument does not pin the units either", {
  weft:::string_config_reset()
  d <- read_dict(c2_fixture())
  a <- sf_root(list("_weft.yml" = sf_unit_yml))
  b <- sf_root()
  withr::local_dir(a)
  dict_glossary(d)
  setwd(b)
  expect_error(fmt_num(u(3, zze1rv), target = "plain"), "not a unit")
})
