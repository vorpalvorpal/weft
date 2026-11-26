# Front-matter rules F1-F6 (orchestrator ruling of 2026-11-27, from the Quarto 1.11.9 / Pandoc 3.10
# experiments). Every reader of a document's front matter follows one rule:
#   F1  the front matter is every metadata block, merged in order;
#   F2  a block opens with a line that is exactly `---` (trailing white space allowed, no indent), at
#       the top (only blank lines above) or after a blank line, the next line not blank, closed at the
#       next `---` or `...` line, its content a YAML mapping; never inside a backtick or tilde fence,
#       an HTML comment or indented code;
#   F3  on a clash the later block wins per top-level key, the whole value replaced (no deep merge,
#       not even inside `weft:`);
#   F4  the same for .Rmd;
#   F5  the document lints report `front-matter-quarto` for the two blocks Quarto reads and Pandoc
#       does not: text directly above the `---`, and a block inside a `~~~` fence;
#   F6  `engine:`, `knitr:`, `jupyter:` stay first-block-only.
# Readers: the knit (weft settings under `weft:`, `lang`, `dict_local`), the lints, verify(),
# checks(), status() (activation). Knits run in this process through plain knitr::knit()
# (run_rmd_file(), helper-render.R), so .qmd documents carry `engine: knitr` in the first block.
#
# Observations: `digits` (decimal places of `.num`; default 1, so pi prints 3.1), `count_threshold`
# (`.count` prints a word below it; default 10, so 7 prints "seven"), `lang` (an n span with arms is a
# construct error under a lang that is not shipped: a draft marker under lang de), `dict_local`
# (last_knit()$dict_local), `claim_words` and `lang` for the claim-word lint, `verify_skip` for
# verify(). ASCII only.

# ---- writing and knitting whole documents --------------------------------------------------------

# a first block: a title, `engine: knitr` for a .qmd, then `extra` lines
fr_head <- function(..., ext = "Rmd") {
  c("---", "title: \"t\"", if (ext == "qmd") "engine: knitr", c(...), "---", "")
}
FR_SETUP <- c("```{r setup, include=FALSE}", "weft::weft_setup()", "```", "")
FR_PI <- "Pi is `r pi`{.num}."
FR_SEVEN <- "Seven is `r 7`{.count}."
FR_ARMS <- "Zed [one | other]{n=\"2\"} end."

# a block (no blank line added on either side)
fr_block <- function(...) c("---", c(...), "---")
fr_digits4 <- function() fr_block("weft:", "  digits: 4")

# Knit `lines` (whole file) as doc.<ext> with knitr::knit() in this process, in a temporary project
# (an _weft.yml holding only a comment). Returns run_rmd_file()'s list plus md (the output, YAML kept),
# failed, message and dir.
fr_knit <- function(lines, ext = "Rmd", draft = FALSE, env = parent.frame()) {
  dir <- normalizePath(withr::local_tempdir(.local_envir = env), winslash = "/")
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir(.local_envir = env), .local_envir = env)
  writeLines("# front-rules test project", file.path(dir, "_weft.yml"))
  input <- file.path(dir, paste0("doc.", ext))
  writeLines(lines, input, useBytes = TRUE)
  out <- file.path(dir, "doc.md")
  vars <- c(WEFT_DRAFT = if (draft) "1" else NA_character_)
  res <- run_rmd_file(input, out, "knit", TRUE, vars)
  res$md <- paste(tidy_output(out, keep_yaml = TRUE), collapse = "\n")
  res$failed <- isTRUE(res$failed)
  res$message <- if (is.null(res$error)) "" else res$error$message
  res$dir <- dir
  res
}

# expect a knit to have run and to hold `text` (fixed); `not` must not appear
fr_expect <- function(res, text, not = NULL, label = "") {
  testthat::expect_false(res$failed, label = paste(label, "knit failed:", substr(res$message, 1, 300)))
  testthat::expect_match(unesc(res$md), text, fixed = TRUE, label = paste(label, "output"))
  for (n in not) testthat::expect_no_match(unesc(res$md), n, fixed = TRUE, label = paste(label, "output"))
}

# ---- F1 / F3 / F4: the knit merges every block ------------------------------------------------------

test_that("F1 control: a weft: setting in the first block takes effect in the knit (both formats)", {
  for (ext in c("Rmd", "qmd")) {
    res <- fr_knit(c(fr_head("weft:", "  digits: 4", ext = ext), FR_SETUP, FR_PI), ext)
    fr_expect(res, "Pi is 3.1416.", label = ext)
    res <- fr_knit(c(fr_head(ext = ext), FR_SETUP, FR_PI), ext)
    fr_expect(res, "Pi is 3.1.", not = "3.1416", label = paste(ext, "(no setting)"))
  }
})

test_that("F1 + F4: a weft: setting only in a second block, mid-document after a blank line, takes effect in the knit", {
  for (ext in c("Rmd", "qmd")) {
    doc <- c(fr_head(ext = ext), FR_SETUP, "Intro.", "", fr_digits4(), "", FR_PI)
    fr_expect(fr_knit(doc, ext), "Pi is 3.1416.", label = ext)
  }
})

test_that("F1: a second block at the end of the document applies to the values above it", {
  for (ext in c("Rmd", "qmd")) {
    doc <- c(fr_head(ext = ext), FR_SETUP, FR_PI, "", fr_digits4())
    fr_expect(fr_knit(doc, ext), "Pi is 3.1416.", label = ext)
  }
})

test_that("F1: a second block closed with `...` counts", {
  doc <- c(fr_head(ext = "qmd"), FR_SETUP, "Intro.", "", "---", "weft:", "  digits: 4", "...", "", FR_PI)
  fr_expect(fr_knit(doc, "qmd"), "Pi is 3.1416.")
})

test_that("F1: a second block whose opening line has trailing white space counts", {
  doc <- c(fr_head(ext = "qmd"), FR_SETUP, "Intro.", "", "---  ", "weft:", "  digits: 4", "---", "", FR_PI)
  fr_expect(fr_knit(doc, "qmd"), "Pi is 3.1416.")
})

test_that("F1 control: lang de in the first block makes an n span with arms a construct error (draft marker)", {
  res <- fr_knit(c(fr_head("lang: de", ext = "qmd"), FR_SETUP, FR_ARMS), "qmd", draft = TRUE)
  fr_expect(res, "construct error")
  res <- fr_knit(c(fr_head(ext = "qmd"), FR_SETUP, FR_ARMS), "qmd", draft = TRUE)
  fr_expect(res, "Zed other end.", not = "construct error", label = "no lang")
})

test_that("F1 + F4: lang only in a second block takes effect in the knit", {
  for (ext in c("Rmd", "qmd")) {
    doc <- c(fr_head(ext = ext), FR_SETUP, FR_ARMS, "", fr_block("lang: de"))
    fr_expect(fr_knit(doc, ext, draft = TRUE), "construct error", not = "Zed other end.", label = ext)
  }
})

test_that("F3: on a clash the later block wins, for lang", {
  for (ext in c("Rmd", "qmd")) {
    doc <- c(fr_head("lang: de", ext = ext), FR_SETUP, FR_ARMS, "", fr_block("lang: en"))
    fr_expect(fr_knit(doc, ext, draft = TRUE), "Zed other end.", not = "construct error", label = ext)
  }
})

test_that("F3: on a clash the later block wins, for a weft: setting; three blocks, the last wins", {
  doc <- c(fr_head("weft:", "  digits: 4", ext = "qmd"), FR_SETUP, FR_PI, "",
           fr_block("weft:", "  digits: 2"))
  fr_expect(fr_knit(doc, "qmd"), "Pi is 3.14.", not = "3.1416")
  doc <- c(fr_head("weft:", "  digits: 4", ext = "qmd"), FR_SETUP, FR_PI, "",
           fr_block("weft:", "  digits: 2"), "", "Middle.", "", fr_block("weft:", "  digits: 3"))
  fr_expect(fr_knit(doc, "qmd"), "Pi is 3.142.", not = "3.1416")
})

test_that("F3 + F4: a later weft: replaces the whole weft: value; a setting only in the first is no longer in force", {
  for (ext in c("Rmd", "qmd")) {
    # control: the first block alone sets both effects it names
    one <- c(fr_head("weft:", "  digits: 4", ext = ext), FR_SETUP, FR_PI, "", FR_SEVEN)
    fr_expect(fr_knit(one, ext), "Pi is 3.1416.", label = paste(ext, "control"))
    fr_expect(fr_knit(one, ext), "Seven is seven.", label = paste(ext, "control"))
    doc <- c(fr_head("weft:", "  digits: 4", ext = ext), FR_SETUP, FR_PI, "", FR_SEVEN, "",
             fr_block("weft:", "  count_threshold: 5"))
    res <- fr_knit(doc, ext)
    fr_expect(res, "Seven is 7.", label = paste(ext, "the later weft: applies"))
    fr_expect(res, "Pi is 3.1.", not = "3.1416", label = paste(ext, "digits from the first weft: is gone"))
  }
})

test_that("F3: a top-level key the later block does not name is kept from the earlier one", {
  doc <- c(fr_head("lang: de", ext = "qmd"), FR_SETUP, FR_ARMS, "", FR_PI, "",
           fr_block("weft:", "  digits: 4"))
  res <- fr_knit(doc, "qmd", draft = TRUE)
  fr_expect(res, "Pi is 3.1416.")
  fr_expect(res, "construct error", not = "Zed other end.")
})

test_that("F1: dict_local under weft: only in a second block is the knit's local dictionary", {
  local <- c("weft:", "  dict_local:", "    site_class:", "      value: {yes: Allowed, no: Barred}",
             "      type: labels", "      definition: \"Local site classes.\"", "      why: \"This chapter.\"")
  for (ext in c("Rmd", "qmd")) {
    # control: the same entry in the first block
    one <- c(fr_head(local, ext = ext), FR_SETUP, "Class `r dict_local$site_class('yes')`.")
    fr_expect(fr_knit(one, ext), "Class Allowed.", label = paste(ext, "control"))
    doc <- c(fr_head(ext = ext), FR_SETUP, "Intro.", "", fr_block(local), "",
             "Class `r dict_local$site_class('yes')`.")
    res <- fr_knit(doc, ext)
    fr_expect(res, "Class Allowed.", label = ext)
    expect_identical(names(res$knit$dict_local), "site_class", label = ext)
  }
})

# ---- F2: what is not front matter, in the knit ------------------------------------------------------

# each: a document whose only digits: 4 is in a candidate that is not a block
FR_NOT_BLOCKS <- list(
  list(id = "--- then a blank line at the top", ext = "Rmd",
       doc = c("---", "", "weft:", "  digits: 4", "---", "", FR_SETUP, FR_PI)),
  list(id = "--- with trailing spaces then a blank line at the top", ext = "Rmd",
       doc = c("---  ", "", "title: t", "weft:", "  digits: 4", "---", "", FR_SETUP, FR_PI)),
  list(id = "' ---' indented, at the top", ext = "Rmd",
       doc = c(" ---", "weft:", "  digits: 4", " ---", "", FR_SETUP, FR_PI)),
  list(id = "' ---' indented, mid-document", ext = "qmd",
       doc = c(fr_head(ext = "qmd"), FR_SETUP, "Intro.", "", " ---", "weft:", "  digits: 4", " ---", "", FR_PI)),
  list(id = "four-space indented code", ext = "qmd",
       doc = c(fr_head(ext = "qmd"), FR_SETUP, "Intro.", "", "    ---", "    weft:", "      digits: 4", "    ---",
               "", FR_PI)),
  list(id = "inside a backtick fence", ext = "qmd",
       doc = c(fr_head(ext = "qmd"), FR_SETUP, "Intro.", "", "```", fr_digits4(), "```", "", FR_PI)),
  list(id = "inside a backtick yaml fence", ext = "Rmd",
       doc = c(fr_head(ext = "Rmd"), FR_SETUP, "Intro.", "", "```yaml", fr_digits4(), "```", "", FR_PI)),
  list(id = "inside a ~~~ fence", ext = "qmd",
       doc = c(fr_head(ext = "qmd"), FR_SETUP, "Intro.", "", "~~~", fr_digits4(), "~~~", "", FR_PI)),
  list(id = "inside a ~~~ fence (.Rmd)", ext = "Rmd",
       doc = c(fr_head(ext = "Rmd"), FR_SETUP, "Intro.", "", "~~~", fr_digits4(), "~~~", "", FR_PI)),
  list(id = "inside an HTML comment, mid-document", ext = "qmd",
       doc = c(fr_head(ext = "qmd"), FR_SETUP, "Intro.", "", "<!--", fr_digits4(), "-->", "", FR_PI)),
  list(id = "inside an HTML comment at the top", ext = "Rmd",
       doc = c("<!--", fr_digits4(), "-->", "", FR_SETUP, FR_PI)),
  list(id = "text directly above (no blank line)", ext = "qmd",
       doc = c(fr_head(ext = "qmd"), FR_SETUP, "Intro words.", fr_digits4(), "", FR_PI)),
  list(id = "text directly above (no blank line, .Rmd)", ext = "Rmd",
       doc = c(fr_head(ext = "Rmd"), FR_SETUP, "Intro words.", fr_digits4(), "", FR_PI))
)

test_that("F2: a setting in something that is not a metadata block does not take effect in the knit", {
  for (cs in FR_NOT_BLOCKS) {
    res <- fr_knit(cs$doc, cs$ext)
    fr_expect(res, "Pi is 3.1.", not = "Pi is 3.1416.", label = cs$id)
  }
})

test_that("F2: a later block of plain text (not a YAML mapping) is not front matter; the first block still applies", {
  doc <- c(fr_head("weft:", "  digits: 4", ext = "qmd"), FR_SETUP, FR_PI, "", fr_block("Just some words here."))
  fr_expect(fr_knit(doc, "qmd"), "Pi is 3.1416.")
})

test_that("F2: front matter preceded only by blank lines still counts in the knit", {
  for (ext in c("Rmd", "qmd")) {
    doc <- c("", "", fr_head("weft:", "  digits: 4", ext = ext), FR_SETUP, FR_PI)
    fr_expect(fr_knit(doc, ext), "Pi is 3.1416.", label = ext)
  }
})

# ---- F1 / F3 / F4 for the lints, checks() and verify() (they already merge: guards) ----------------

cwf <- function(lines, ext = "qmd", env = parent.frame()) {
  lint_one(lines, rules = "claim-word", ext = ext, env = env)
}
FR_RATIO <- "The ratio was clear."
FR_ROSE <- "All 3 sites rose."
fr_cw_add <- function() c("weft:", "  claim_words:", "    add: [ratio]")

test_that("F1 + F4 (lints): claim_words in a second block is honoured by the claim-word lint", {
  for (ext in c("qmd", "Rmd")) {
    expect_identical(nrow(cwf(c("---", "title: T", "---", "", FR_RATIO), ext)), 0L, label = paste(ext, "control"))
    x <- cwf(c("---", "title: T", "---", "", "Intro.", "", fr_block(fr_cw_add()), "", FR_RATIO), ext)
    expect_identical(x$text, "ratio", label = ext)
  }
})

test_that("F1 + F3 (lints): lang in a second block is honoured, and on a clash the later block wins", {
  for (ext in c("qmd", "Rmd")) {
    x <- cwf(c("---", "title: T", "---", "", FR_ROSE, "", fr_block("lang: de")), ext)
    expect_identical(nrow(x), 0L, label = paste(ext, "lang de in block 2"))
    x <- cwf(c("---", "title: T", "lang: de", "---", "", FR_ROSE, "", fr_block("lang: en")), ext)
    expect_identical(x$text, "all, rose", label = paste(ext, "lang en in block 2 wins"))
  }
})

test_that("F3 (lints): a later weft: replaces the whole weft: value", {
  for (ext in c("qmd", "Rmd")) {
    x <- cwf(c("---", "title: T", fr_cw_add(), "---", "", FR_RATIO), ext)
    expect_identical(x$text, "ratio", label = paste(ext, "control"))
    x <- cwf(c("---", "title: T", fr_cw_add(), "---", "", FR_RATIO, "", fr_block("weft:", "  claim_cap: 5")), ext)
    expect_identical(nrow(x), 0L, label = paste(ext, "claim_words from the first weft: is gone"))
  }
})

test_that("F2 (lints): front matter preceded only by blank lines counts", {
  x <- cwf(c("", "", "---", "title: T", "lang: de", "---", "", FR_ROSE))
  expect_identical(nrow(x), 0L)
})

test_that("F2 (lints): lang in something that is not a block is not honoured", {
  cases <- list(
    "--- then a blank line at the top" = c("---", "", "lang: de", "---", "", FR_ROSE),
    "' ---' indented at the top" = c(" ---", "lang: de", " ---", "", FR_ROSE),
    "inside a backtick fence" = c("---", "title: T", "---", "", "```", fr_block("lang: de"), "```", "", FR_ROSE),
    "inside a ~~~ fence" = c("---", "title: T", "---", "", "~~~", fr_block("lang: de"), "~~~", "", FR_ROSE),
    "inside an HTML comment" = c("---", "title: T", "---", "", "<!--", fr_block("lang: de"), "-->", "", FR_ROSE),
    "inside an HTML comment at the top" = c("<!--", fr_block("lang: de"), "-->", "", FR_ROSE),
    "text directly above" = c("---", "title: T", "---", "", "Intro words.", fr_block("lang: de"), "", FR_ROSE)
  )
  for (id in names(cases)) {
    x <- cwf(cases[[id]])
    expect_identical(x$text, "all, rose", label = id)
  }
})

test_that("F1 (checks): dict_local in a second block makes a dictionary read of that key unreadable", {
  local <- fr_block("weft:", "  dict_local:", "    k:", "      value: 1", "      why: local")
  chunk <- j7_chunk("claim(v, dict$k > 3)", "claim(v, dict$j > 3)")
  r <- j7_read(c("---", "title: T", "---", "", chunk))
  expect_identical(r$cond, c("dict$k > 3", "dict$j > 3"), label = "control")
  r <- j7_read(c("---", "title: T", "---", "", chunk, "", local))
  expect_identical(nrow(r), 2L)
  expect_true(is.na(r$cond[[1]]))
  expect_identical(r$cond[[2]], "dict$j > 3")
})

test_that("F1 (verify): verify_skip in a second block of a lone document skips the lints", {
  v4_env()
  doc <- c("---", "title: T", "---", "", "A", F3_BAD_TWO, "here.", "", fr_block("weft:", "  verify_skip: [lints]"))
  p <- v4_proj(list("a.qmd" = doc), weft_yml = NULL)
  r <- v4_verify(p$root, static = TRUE)
  expect_null(r$err, label = if (!is.null(r$err)) conditionMessage(r$err) else "")
  expect_identical(v4_status(r$value, "lints"), "skipped")
})

test_that("F3 (verify): a later weft: without verify_skip replaces the first block's, so the lints run", {
  v4_env()
  doc <- c("---", "title: T", "weft:", "  verify_skip: [lints]", "---", "", "A", F3_BAD_TWO, "here.", "",
           fr_block("weft:", "  claim_cap: 5"))
  p <- v4_proj(list("a.qmd" = doc), weft_yml = NULL)
  r <- v4_verify(p$root, static = TRUE)
  expect_false(identical(v4_status(r$res, "lints"), "skipped"))
})

# ---- F5: the lint front-matter-quarto ---------------------------------------------------------------

fq <- function(lines, ext = "qmd", env = parent.frame()) {
  lf_by_rule(lint_one(lines, ext = ext, env = env), "front-matter-quarto")
}
FR_QUARTO_MSG <- "Quarto reads this block as front matter but Pandoc does not"

test_that("F5: a --- block with text directly above it is a front-matter-quarto finding", {
  doc <- c("---", "title: T", "---", "", "Body one.", "---", "lang: fr", "---", "", "More text.")
  x <- fq(doc)
  expect_identical(nrow(x), 1L)
  expect_identical(x$line, 6L)
  expect_match(x$message, FR_QUARTO_MSG, fixed = TRUE)
  expect_match(x$message, "blank line", fixed = TRUE)
})

test_that("F5: a --- metadata block inside a ~~~ fence is a front-matter-quarto finding", {
  doc <- c("---", "title: T", "---", "", "Intro.", "", "~~~", "---", "lang: fr", "---", "~~~", "", "More text.")
  x <- fq(doc)
  expect_identical(nrow(x), 1L)
  expect_true(x$line %in% c(7L, 8L), label = "the finding is at the fence or the block's opening line")
  expect_match(x$message, FR_QUARTO_MSG, fixed = TRUE)
  expect_match(x$message, "fence", fixed = TRUE)
})

test_that("F5: no front-matter-quarto finding for a normal block, a backtick fence, an HTML comment or a setext heading", {
  cases <- list(
    "first block only" = c("---", "title: T", "lang: fr", "---", "", "Text."),
    "a normal second block" = c("---", "title: T", "---", "", "Body one.", "", "---", "lang: fr", "---", "", "More."),
    "in a backtick fence" = c("---", "title: T", "---", "", "```", "---", "lang: fr", "---", "```", "", "More."),
    "in a backtick yaml fence" = c("---", "title: T", "---", "", "```yaml", "---", "lang: fr", "---", "```", "", "More."),
    "in an HTML comment" = c("---", "title: T", "---", "", "<!--", "---", "lang: fr", "---", "-->", "", "More."),
    "a setext heading" = c("---", "title: T", "---", "", "A heading", "---", "", "Paragraph text.")
  )
  for (id in names(cases)) expect_identical(nrow(fq(cases[[id]])), 0L, label = id)
})

# ---- status(): the activation route (F2, and F6: knitr: is first-block-only) -----------------------

fr_status_doc <- function(lines, env = parent.frame()) {
  dir <- h4_repo(list(`index.qmd` = lines), weft = character(), env = env)
  h4_state(h4_status(dir), "activation")
}
FR_BODY <- c("```{r}", "x <- 1", "```", "", "Text.")

test_that("F2 (status) control: the front-matter route in the first block is activation ok", {
  expect_identical(fr_status_doc(c("---", "title: \"t\"", "engine: knitr", U4_OPTS_KNIT, "---", "", FR_BODY)), "ok")
})

test_that("F2 (status): the route in a first block preceded only by blank lines is activation ok", {
  expect_identical(fr_status_doc(c("", "", "---", "title: \"t\"", "engine: knitr", U4_OPTS_KNIT, "---", "",
                                   FR_BODY)), "ok")
})

test_that("F2 (status): the route after --- and a blank line at the top is not front matter: activation missing", {
  expect_identical(fr_status_doc(c("---", "", "engine: knitr", U4_OPTS_KNIT, "---", "", FR_BODY)), "missing")
})

test_that("F6 (status): the route (a knitr: key) only in a second block is not activation", {
  expect_identical(fr_status_doc(c("---", "title: \"t\"", "engine: knitr", "---", "", FR_BODY, "",
                                   fr_block(U4_OPTS_KNIT))), "missing")
})
