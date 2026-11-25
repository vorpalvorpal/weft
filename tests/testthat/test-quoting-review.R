# Review of package Q (dev/review-q.md): tests for the fix round, written from the rulings R1 to R8 and
# the contract of dev/design-quoting.md, before the fixes. ASCII only (non-ASCII characters are built
# with \u escapes); markup is in raw strings. Controls that already hold say so.
#
# READINGS (the rulings leave them open):
#  - R1: a character reference in a BARE value is the M3 error with the same text as in a quoted one.
#    quoting.tsv still lists `R&amp;D` as ok and test-quoting-scan.R still expects the bare value
#    `R&amp;D` to read; both contradict R1 and must change with the fix (this file does not touch them).
#  - R2(a): inside a list item Pandoc strips the item's content indent before the break, so the scanner
#    must read `one` + break + the indent as `one two`. In a plain paragraph Pandoc keeps the indent after
#    the break (`a    b`), so the existing paragraph tests stay as they are and are not repeated here.
#  - R2(b): the message is pinned by its fragment "must fit on one line" and the kind; the ruling quotes
#    the full text, which is asserted as a fixed substring.
#  - R3: the ruling gives no message, so only "an error is reported" (and the construct error class for
#    weft_md()) is asserted.
#  - R4: the ruling's second hint ("the closing quote is escaped") is pinned by that fragment on
#    `unit="m\" title="b}`, where the first value ends in a backslash-quote and the next value is unclosed.
#  - R5: strip_quoted of weft-check.lua is reached only for text that Pandoc leaves as text, and there the
#    check reads the first key of the block; no black-box input shows the swallowing. The test below is a
#    control that pins the intended reading; it does not fail now (see the report).
#  - R7: the Lua escapes are observed through the line the filter finds for a span (draft mode marker with
#    a line); the marker's kind is not pinned, only that it names the case's own line.

qr_scan <- function(x, ...) weft:::scan_text(x, ...)
qr_errs <- function(x) {
  r <- qr_scan(x)
  e <- r$error[!is.na(r$error)]
  as.character(unlist(strsplit(as.character(e), "\n", fixed = TRUE), use.names = FALSE))
}
qr_first <- function(x) qr_errs(x)[1]
qr_cond <- function(x) tryCatch(weft_md(x), error = function(e) e)
qr_nbsp <- "\u00a0"
qr_eacute <- "\u00e9"

QR_M3 <- function(ref, key) sprintf("A character reference, `%s`, in the value of `%s` (rule 1.2.3): Pandoc reads it as the character it names. Write the character itself.", ref, key)
QR_M4_HEAD <- "The attribute block does not parse: "
QR_M4_TAIL <- " (rules 1.2.3, 1.2.9)."
QR_M4_Q2 <- paste0(QR_M4_HEAD, "a `\"` inside a value in double quotes ends it early", QR_M4_TAIL,
                   " Write it as `\\\"`, or put the value in single quotes.")
QR_M4_Q1 <- paste0(QR_M4_HEAD, "a `'` inside a value in single quotes ends it early", QR_M4_TAIL,
                   " Write it as `\\'`, or put the value in double quotes.")
QR_BQ <- "a quoted value in a block quote must fit on one line"

# every Span of the document, found at any depth: a list of its attribute lists (key -> value), per
# top-level block, the first Span of each block (NULL when none)
qr_pandoc_first_span <- function(md, key = "title") {
  skip_if_no_lua_pandoc()
  p <- lua_pandoc()
  dir <- withr::local_tempdir()
  f <- file.path(dir, "doc.md")
  writeLines(md, f, useBytes = TRUE)
  out <- suppressWarnings(system2(p$cmd, c(p$pre, "-f", "markdown", "-t", "json", shQuote(f)),
                                  stdout = TRUE, stderr = FALSE))
  j <- jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
  find <- function(x) {
    if (is.list(x)) {
      if (identical(x$t, "Span")) {
        for (kv in x$c[[1]][[3]]) if (identical(kv[[1]], key)) return(as.character(kv[[2]]))
        return(NA_character_)
      }
      for (el in x) {
        r <- find(el)
        if (!is.null(r)) return(r)
      }
    }
    NULL
  }
  vapply(j$blocks, function(b) { r <- find(b); if (is.null(r)) NA_character_ else r }, "")
}

# ---- R1: a character reference in a bare value is the M3 error ---------------------------------------------

test_that("R1, M3: a character reference in a bare value is the M3 error, as in a quoted value", {
  expect_identical(qr_first(r"{`r x`{.num title=R&amp;D}}"), QR_M3("&amp;", "title"))
  expect_identical(qr_first(r"{`r x`{.num title=R&#38;D}}"), QR_M3("&#38;", "title"))
  expect_identical(qr_first(r"{`r x`{.num title=&#x41;}}"), QR_M3("&#x41;", "title"))
  expect_identical(qr_first(r"{[a | b]{if=x&amp;y}}"), QR_M3("&amp;", "if"))
  expect_identical(qr_first(r"{[lit]{.weft-literal why=a&quot;b}}"), QR_M3("&quot;", "why"))
})

test_that("R1 control: an ampersand that does not begin a reference stays readable in a bare value", {
  r <- qr_scan(r"{`r x`{.num title=R&D digits=1}}")
  expect_true(is.na(r$error))
  expect_identical(unname(r$keys[[1]][["title"]]), "R&D")
})

test_that("R1, weft_md(): a bare value with a character reference is a construct error, not a written block", {
  cond <- qr_cond(r"{`r 1.2`{.num title=R&amp;D}}")
  expect_s3_class(cond, "weft_construct_error")
  expect_true(grepl("A character reference, `&amp;`, in the value of `title`", conditionMessage(cond), fixed = TRUE))
})

test_that("R1, M3 rows (the table of the ruling): bare and quoted references are refused in every form", {
  rows <- c(r"{R&amp;D}", r"{"R&amp;D"}", r"{'R&amp;D'}", r"{&#39;}", r"{"&#x41;"}")
  for (w in rows) {
    e <- qr_first(paste0("`r 1`{.num digits=\"1\" title=", w, "}"))
    expect_true(startsWith(e, "A character reference, `"), label = w)
  }
})

# ---- R2: line breaks inside list items and block quotes ----------------------------------------------------

test_that("R2(a), T1: a quoted value over a line break inside a list item reads as one space (Pandoc strips the item's indent)", {
  why <- function(src) {
    r <- qr_scan(src)
    expect_identical(nrow(r), 1L, label = src)
    if (nrow(r) != 1L) return(NA_character_)
    expect_true(is.na(r$error), label = paste("no error:", src))
    unname(r$keys[[1]][["why"]])
  }
  expect_identical(why("- [lit]{.weft-literal why=\"one\n  two\"}"), "one two")
  expect_identical(why("1. [lit]{.weft-literal why=\"one\n   two\"}"), "one two")
  expect_identical(why("- [lit]{.weft-literal why='one\r\n  two'}"), "one two")
})

test_that("R2(a), T3: Pandoc reads the same list-item values the scanner now reads (the subset rule)", {
  md <- c("- [x]{title=\"one", "  two\"}", "", "1. [x]{title=\"one", "   two\"}", "",
          "> - [x]{title=\"one", ">   two\"}", "")
  got <- qr_pandoc_first_span(md)
  expect_identical(got, c("one two", "one two", "one two"))
})

test_that("R2(b), T1: a quoted value that crosses a line break inside a block quote is a construct error", {
  cases <- c(
    "> [a | b]{if=\"x >\n> 1\"}",
    "> [lit]{.weft-literal why=\"one\n> two\"}",
    "> [lit]{.weft-literal why='one\n> two'}",
    "  > [a | b]{if=\"x\n> y\"}",
    "> `r x`{.num title=\"one\n> two\"}",
    "> [lit]{.weft-literal why=\"one\ntwo\"}",
    "> > [a | b]{if=\"x\n> > y\"}",
    "> - [lit]{.weft-literal why=\"one\n>   two\"}"
  )
  for (src in cases) {
    e <- qr_errs(src)
    expect_gte(length(e), 1L, label = src)
    expect_true(any(grepl(QR_BQ, e, fixed = TRUE)), label = src)
  }
})

test_that("R2(b), T1: the block-quote error is the only error of such a block, once", {
  e <- qr_errs("> [a | b]{if=\"x >\n> 1\"}")
  expect_identical(sum(grepl(QR_BQ, e, fixed = TRUE)), 1L)
})

test_that("R2(b) controls: a quoted value on one line in a block quote, and a crossing one outside a block quote, are accepted", {
  r <- qr_scan("> [a | b]{if=\"x > 1\"}")
  expect_identical(nrow(r), 1L)
  expect_true(is.na(r$error))
  expect_identical(r$expr, "x > 1")
  r <- qr_scan("> `r x`{.num title=\"a'b\" digits=1}")
  expect_true(is.na(r$error))
  r <- qr_scan("[lit]{.weft-literal why=\"one\ntwo\"}")
  expect_true(is.na(r$error))
  expect_identical(unname(r$keys[[1]][["why"]]), "one two")
})

test_that("R2(b), weft_md(): a block-quote span with a value over a line break is a construct error", {
  cond <- qr_cond("> [a | b]{if=\"x >\n> 1\"}")
  expect_s3_class(cond, "weft_construct_error")
  expect_true(grepl(QR_BQ, conditionMessage(cond), fixed = TRUE))
})

test_that("R2(a), T7: the filter finds the line of a span whose quoted value crosses a line break in a list item", {
  cases <- c(
    li = "- A [x | y]{if=\"nothere\n  == 1\"} z.",
    ol = "1. A [x | y]{if='nothere\n   == 1'} z."
  )
  res <- filter_cases(cases, list(carrier(a = fr_bool(TRUE))), draft = TRUE)
  for (nm in names(cases)) {
    L <- res$line[[nm]]
    expect_true(grepl(sprintf("<<weft: [a-z ]+, line %d>>", L), res$got[[nm]]), label = paste(nm, res$got[[nm]]))
  }
})

test_that("R2(b), T7: the filter finds the line of a block-quote span whose value is on one line", {
  cases <- c(bq = "> A [x | y]{if=\"nothere == 1\"} z.")
  res <- filter_cases(cases, list(carrier(a = fr_bool(TRUE))), draft = TRUE)
  L <- res$line[["bq"]]
  expect_true(grepl(sprintf("<<weft: [a-z ]+, line %d>>", L), res$got[["bq"]]), label = res$got[["bq"]])
})

# ---- R3: a quoted value that starts with white space is a construct error for every key ----------------------

test_that("R3, T1: a quoted value whose first character is white space is an error for every key, both quotes", {
  cases <- c(
    "`r x`{.num title=\" a\"}", "`r x`{.num title=' a'}",
    "[lit]{.weft-literal why=\" a\"}", "[lit]{.weft-literal why=' a'}",
    "[lit]{.weft-literal why=\"w\" decision=\" a\"}",
    "[a | b]{if=\" ok\"}", "[a | b]{if=' ok'}", "[a | b]{n=\" k\"}",
    "`r x`{.num title=\" \"}",
    paste0("`r x`{.num title=\"", qr_nbsp, "a\"}"),
    paste0("[lit]{.weft-literal why='", qr_nbsp, "a'}"),
    paste0("[a | b]{if=\"", qr_nbsp, "ok\"}")
  )
  for (src in cases) {
    r <- qr_scan(src)
    expect_identical(nrow(r), 1L, label = src)
    expect_true(any(!is.na(r$error)), label = paste("error for", src))
  }
})

test_that("R3 controls: white space inside or at the end of a quoted value, and an empty value, are fine", {
  expect_true(is.na(qr_scan("`r x`{.num title=\"a b \" digits=1}")$error))
  expect_true(is.na(qr_scan("`r x`{.num title='a  b' digits=1}")$error))
  expect_true(is.na(qr_scan("`r x`{.num title=\"\" digits=1}")$error))
  expect_true(is.na(qr_scan(paste0("`r x`{.num title=\"a", qr_nbsp, "b\" digits=1}"))$error))
})

test_that("R3, hooks documents: the error also holds in a document the hooks resolve (.Rmd), where D12 had accepted it", {
  for (v in c("' ok'", "\" ok\"")) {
    r <- w6d_scan(c("Intro.", "", sprintf("A [one | many]{if=%s} B.", v)), name = "a.Rmd")
    r <- r[r$kind == "if", , drop = FALSE]
    expect_identical(nrow(r), 1L, label = v)
    expect_false(is.na(r$error), label = v)
  }
  r <- w6d_scan(c("Intro.", "", "A `r x`{.num title=' a'} B."), name = "a.Rmd")
  expect_true(any(!is.na(r$error)))
})

test_that("R3, weft_md(): a leading space in a quoted value is a construct error in a string, for pass-through keys too", {
  expect_s3_class(qr_cond("[a | b]{if=' ok'}"), "weft_construct_error")
  expect_s3_class(qr_cond(r"{`r 1.2`{.num title=" x"}}"), "weft_construct_error")
  expect_s3_class(qr_cond(paste0("`r 1.2`{.num title='", qr_nbsp, "x'}")), "weft_construct_error")
})

test_that("R3, Pandoc pin: a leading space makes the block text, a no-break space falls back to a bare value keeping the quotes", {
  got <- qr_pandoc_first_span(c("[x]{title=\" a\"}", "", paste0("[x]{title=\"", qr_nbsp, "a\"}"), ""))
  expect_true(is.na(got[1]))
  expect_identical(got[2], paste0("\"", qr_nbsp, "a\""))
})

# ---- R3a: a leading space is written `\ ` (backslash, space) ------------------------------------------------

test_that("R3a, T1: a backslash-space is an escape for a space in a quoted value, so a value may start with a space", {
  r <- qr_scan(r"{`r s`{.and last="\ plus "}}")
  expect_identical(nrow(r), 1L)
  expect_true(is.na(r$error))
  expect_identical(unname(r$keys[[1]][["last"]]), " plus ")
  r <- qr_scan(r"{`r s`{.or last='\ or else '}}")
  expect_true(is.na(r$error))
  expect_identical(unname(r$keys[[1]][["last"]]), " or else ")
  r <- qr_scan(r"{[lit]{.weft-literal why="a\ b"}}")
  expect_true(is.na(r$error))
  expect_identical(unname(r$keys[[1]][["why"]]), "a b")
})

test_that("R3a, M7: the leading-space error names the backslash-space escape", {
  e <- qr_first(r"{`r s`{.and last=" plus "}}")
  expect_match(e, "starts with white space", fixed = TRUE)
  expect_match(e, "\\ ", fixed = TRUE)
})

test_that("R3a, Pandoc pin: Pandoc reads a leading backslash-space as a space", {
  got <- qr_pandoc_first_span(c(r"{[x]{title="\ plus "}}", "", r"{[x]{title='\ a'}}", ""))
  expect_identical(got, c(" plus ", " a"))
})

test_that("R3a, T4: the writer writes a leading space as a backslash-space, and Pandoc reads it back", {
  out <- weft_md(r"{`r 1.2`{.num title="\ lead"}}")
  expect_identical(out, r"{[1.2]{title="\ lead"}}")
  expect_identical(qr_pandoc_first_span(c(out, "")), " lead")
})

# ---- R4: M4 names the quote cause for an apostrophe in a value ---------------------------------------------

test_that("R4, M4: a quoted value that closes and is followed by a token that is not an attribute gives the quote cause and its hint", {
  expect_identical(qr_first(r"{[lit]{.weft-literal why='the sites' own rule'}}"), QR_M4_Q1)
  expect_identical(qr_first(r"{[lit]{.weft-literal why="x" decision='the sites' own rule'}}"), QR_M4_Q1)
  expect_identical(qr_first(r"{[a | b]{if='x' y'}}"), QR_M4_Q1)
  expect_identical(qr_first(r"{[lit]{.weft-literal why="say "hi" now"}}"), QR_M4_Q2)
})

test_that("R4, M4: a value ending in a backslash-quote followed by an unclosed value gets the escaped-closing-quote hint", {
  e <- qr_first(r"{`r x`{unit="m\" title="b}}")
  expect_true(startsWith(e, QR_M4_HEAD))
  expect_true(grepl("closing quote is escaped", e, fixed = TRUE), label = e)
})

test_that("R4 controls: the other M4 causes keep their texts (after a closed value, a key=value, a class, an id or } follows)", {
  expect_true(is.na(qr_scan(r"{[lit]{.weft-literal why='it\'s fine' #id .c}}")$error))
  expect_true(is.na(qr_scan(r"{`r x`{.num title='a' digits=1}}")$error))
})

# ---- R5: strip_quoted in weft-check.lua --------------------------------------------------------------------

test_that("R5, control: weft-check.lua still reports a key after an unbalanced apostrophe in a code span's block", {
  # READING: see the header; the code-span key path and the text path both report today
  for (txt in c("`x`{title=it's digits=2}", "`x`{title=it's n=k}", "12.5{n=k title=it's}", "12.5{n=k} it's here")) {
    res <- filter_md(txt, filters = "weft-check.lua", to = "plain")
    expect_identical(res$status, 1L, label = txt)
    expect_true(grepl("weft-check", res$stderr, fixed = TRUE), label = txt)
  }
})

# ---- R6: the pre-render script's span_bad reads values as C7 -------------------------------------------------

qr_pre_run <- function(docs, env = parent.frame()) {
  script <- system.file("quarto", "weft-pre-render.R", package = "weft")
  expect_true(nzchar(script) && file.exists(script), label = "the package ships its pre-render script")
  files <- c(list("_quarto.yml" = c("project:", "  type: default", "format: html")),
             lapply(docs, function(line) c("---", "title: t", "---", "", line)))
  names(files)[-1] <- paste0(names(docs), ".qmd")
  root <- lint_proj(files, env = env)
  withr::local_envvar(c(QUARTO_PROJECT_INPUT_FILES = NA, WEFT_RUN = NA), .local_envir = env)
  out <- suppressWarnings(withr::with_dir(root, system2(file.path(R.home("bin"), "Rscript"), shQuote(script),
                                                         stdout = TRUE, stderr = TRUE)))
  stopped <- sub("^  ([A-Za-z0-9_]+)\\.qmd: holds a weft construct.*$", "\\1",
                 grep("^  [A-Za-z0-9_]+\\.qmd: holds a weft construct", out, value = TRUE))
  list(stopped = stopped, log = paste(out, collapse = "\n"))
}

test_that("R6, span_bad: a governor key inside another key's quoted value does not stop a document without engine: knitr", {
  docs <- c(
    lit_sq = r"{A [x]{.weft-literal why='n=3 sites'} b.}",
    lit_dq = r"{A [x]{.weft-literal why="if=3 sites"} b.}",
    lit_esc = r"{A [x]{.weft-literal why="said \"n=3\" here"} b.}",
    lit_sign = r"{A [x]{.weft-literal why='sign=x and list=y'} b.}",
    lit_two = r"{A [x]{.weft-literal why='n=3' decision='if=a && b'} b.}"
  )
  res <- qr_pre_run(as.list(docs))
  expect_identical(res$stopped, character(), info = res$log)
})

test_that("R6, span_bad: single-quoted, bare and escaped-bar governors that do not fit still stop the document", {
  docs <- c(
    sq_n = r"{A [a site | # sites]{n='3'} b.}",
    sq_if = r"{A [rose | fell]{if='a && b'} b.}",
    bare_n = r"{A [a site | # sites]{n=3} b.}",
    bare_sign = r"{A [rose | fell]{sign=3} b.}",
    bar_if = r"{A [rose | fell]{if="a \|\| b"} b.}",
    bar_sq = r"{A [rose | fell]{if='a \|\| b'} b.}",
    after_quoted = r"{A [rose | fell]{title='n=3 sites' if='a && b'} b.}",
    after_quoted_dq = r"{A [rose | fell]{title="x" n="3"} b.}"
  )
  res <- qr_pre_run(as.list(docs))
  expect_setequal(res$stopped, names(docs))
})

test_that("R6 control: fitting governors in single quotes, bare, and with a string literal do not stop the document", {
  docs <- c(
    sq_ok = r"{A [a site | # sites]{n='k'} b.}",
    bare_ok = r"{A [a site | # sites]{n=k} b.}",
    lit_ok = r"{A [severe | mild]{if='tier == "sev"'} b.}",
    esc_ok = r"{A [severe | mild]{if="tier == \"sev\""} b.}"
  )
  res <- qr_pre_run(as.list(docs))
  expect_identical(res$stopped, character(), info = res$log)
})

# ---- R7: the two Lua escapes in read_value (observed through the line the filter finds) -----------------------

test_that("R7, C8: a backslash before a non-ASCII letter keeps the backslash, so the span still has its line", {
  cases <- c(
    sq = paste0("A [x | y]{if='nothere == \"a\\", qr_eacute, "b\"'} z."),
    dq = paste0("B [x | y]{if=\"nothere == 'a\\", qr_eacute, "b'\"} z.")
  )
  res <- filter_cases(cases, list(carrier(a = fr_bool(TRUE))), draft = TRUE)
  for (nm in names(cases)) {
    L <- res$line[[nm]]
    expect_true(grepl(sprintf("<<weft: [a-z ]+, line %d>>", L), res$got[[nm]]), label = paste(nm, res$got[[nm]]))
  }
})

test_that("R7, C8: a backslash before a line break stays a backslash and the break reads as a space", {
  cases <- c(
    sq = "A [x | y]{if='nothere >\\\n1'} z.",
    dq = "B [x | y]{if=\"nothere >\\\n1\"} z."
  )
  res <- filter_cases(cases, list(carrier(a = fr_bool(TRUE))), draft = TRUE)
  for (nm in names(cases)) {
    L <- res$line[[nm]]
    expect_true(grepl(sprintf("<<weft: [a-z ]+, line %d>>", L), res$got[[nm]]), label = paste(nm, res$got[[nm]]))
  }
})

# ---- R8: Pandoc pins, writer round trips -------------------------------------------------------------------------

test_that("R8, T3, Pandoc pin: \"a\\db\" reads a\\db, \"R&amp;D\" reads R&D, and the escapes R7 follows", {
  md <- c(
    r"{[x]{title="a\db"}}", "",
    r"{[x]{title="R&amp;D"}}", "",
    paste0("[x]{title=\"a\\", qr_eacute, "b\"}"), "",
    "[x]{title=\"a\\\nb\"}", "",
    r"{[x]{title=R&amp;D}}", ""
  )
  got <- qr_pandoc_first_span(md)
  expect_identical(got, c(r"{a\db}", "R&D", paste0("a\\", qr_eacute, "b"), "a\\ b", "R&amp;D"))
})

test_that("R8, T4: a value with an ampersand that is no reference is written and read back unchanged", {
  src <- c(r"{`r 1.2`{.num title="R & D"}}", r"{`r 1.2`{.num title="a&b"}}", r"{`r 1.2`{.num title='Q&A '}}")
  want <- c("R & D", "a&b", "Q&A ")
  out <- vapply(src, function(x) { r <- qr_cond(x); if (inherits(r, "error")) conditionMessage(r) else r }, "",
                USE.NAMES = FALSE)
  expect_identical(out, c(r"{[1.2]{title="R & D"}}", r"{[1.2]{title="a&b"}}", r"{[1.2]{title="Q&A "}}"))
  got <- qr_pandoc_first_span(unlist(lapply(out, function(o) c(o, ""))))
  expect_identical(got, want)
})

test_that("R8, T4: values that Pandoc would decode or drop are refused before they are written (character reference, leading space)", {
  for (src in c(r"{`r 1.2`{.num title="R&amp;D"}}", r"{`r 1.2`{.num title=R&amp;D}}",
                r"{`r 1.2`{.num title='&#39;'}}", r"{`r 1.2`{.num title=" lead"}}",
                r"{[lit]{.weft-literal why="w" title=" lead"}}")) {
    expect_s3_class(qr_cond(src), "weft_construct_error")
  }
})

test_that("R8, T1: span_bad's cousins in the scanner: a governor key inside a quoted value is not read as that key", {
  r <- qr_scan(r"{[lit]{.weft-literal why='n=3 sites'}}")
  expect_identical(nrow(r), 1L)
  expect_identical(r$kind, "literal")
  expect_true(is.na(r$error))
  expect_identical(unname(r$keys[[1]][["why"]]), "n=3 sites")
})
