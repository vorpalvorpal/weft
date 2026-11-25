# Package Q (dev/design-quoting.md): attribute quoting loosened everywhere. This file is T1 and T2: the
# scanner (weft:::scan_text) reads double-quoted, single-quoted and bare values, with \" \' \| escapes
# in a quoted value and \| in a bare one; the errors M1 to M5 have exact texts (C2); a broken block that
# holds why, decision or label is the 1.2.9 error (C3, D4). Written before the code: tests of the new
# reading fail today on the old single-quote and backslash errors. Controls that pin behaviour that
# already holds say so. ASCII only; markup is in raw strings.
#
# READINGS (the design leaves them open):
#  - the texts of the M4 causes space, novalue and marker are "today's" (C2), which this file cannot read
#    from the source: those three are pinned by the M4 prefix and the cause words of the table in C2;
#  - an M4 hint follows the cause on the same line after a space, as C2 says ("one line"), so the whole
#    first line is compared;
#  - the arm text of the span is not pinned; kind, expr and keys are.

qs <- function(x, ...) weft:::scan_text(x, ...)

# the construct errors found in a text, each message split into its lines
q_errs <- function(x) {
  r <- qs(x)
  e <- r$error[!is.na(r$error)]
  as.character(unlist(strsplit(as.character(e), "\n", fixed = TRUE), use.names = FALSE))
}
q_first <- function(x) q_errs(x)[1]

# a two-column pipe table, the construct in the first cell
q_tbl <- function(cell) paste("| name | n |", "|------|---|", paste0("| ", cell, " | 1 |"), sep = "\n")

# ---- the exact texts of C2 -----------------------------------------------------------------------------

M1 <- function(key) sprintf("A `\\` in the value of `%s` that does not escape `\"`, `'` or `|` (rule 1.2.3). Bind the expression to a name in a chunk and use the name.", key)
M2 <- function(key) sprintf("A `\"`, `'` or `\\` in the value of `%s`, which has no quotes around it (rule 1.2.3); only `\\|` may stand there. Put the value in quotes.", key)
M3 <- function(ref, key) sprintf("A character reference, `%s`, in the value of `%s` (rule 1.2.3): Pandoc reads it as the character it names. Write the character itself.", ref, key)
M4_HEAD <- "The attribute block does not parse: "
M4_TAIL <- " (rules 1.2.3, 1.2.9)."
M4 <- list(
  q2 = paste0(M4_HEAD, "a `\"` inside a value in double quotes ends it early", M4_TAIL,
              " Write it as `\\\"`, or put the value in single quotes."),
  q1 = paste0(M4_HEAD, "a `'` inside a value in single quotes ends it early", M4_TAIL,
              " Write it as `\\'`, or put the value in double quotes."),
  glued = paste0(M4_HEAD, "a closing quote must be followed by a space or `}`", M4_TAIL),
  open = paste0(M4_HEAD, "a quoted value is not closed in its paragraph", M4_TAIL,
                " A `\\` before a quote escapes it.")
)
M4_CAUSE <- c(space = "spaces around `=` are not allowed", novalue = "a key has no value",
              marker = "a `#` or `.` has nothing after it")
M5 <- function(key) sprintf("An unescaped `|` in the value of `%s` of a construct in a pipe-table cell (rule 1.5.13); write `\\|`.", key)

# ---- T1: accepted forms ----------------------------------------------------------------------------------

test_that("T1, 1.2.2, 1.2.3: if and n values are read in double, single and bare quoting (expr is the decoded value)", {
  cases <- list(
    list(r"{[a | b]{if='tier == "sev"'}}", "if", r"{tier == "sev"}"),
    list(r"{[a | b]{if="tier == \"sev\""}}", "if", r"{tier == "sev"}"),
    list(r"{[a | b]{if="tier == 'sev'"}}", "if", "tier == 'sev'"),
    list(r"{[a | b]{n='k'}}", "n", "k"),
    list(r"{[a | b]{n=k}}", "n", "k"),
    list(r"{[a | b]{if='s == "it\'s"'}}", "if", r"{s == "it's"}"),
    list(r"{[a | b]{if="s == \"it's\""}}", "if", r"{s == "it's"}"),
    list(r"{[a | b]{if="s == 'a\|b'"}}", "if", "s == 'a|b'"),
    list(r"{[a | b]{if="p \|\| q"}}", "if", "p || q")
  )
  for (cs in cases) {
    r <- qs(cs[[1]])
    expect_identical(nrow(r), 1L, label = cs[[1]])
    if (nrow(r) != 1L) next
    expect_true(is.na(r$error), label = paste("no error:", cs[[1]]))
    expect_identical(r$kind, cs[[2]], label = cs[[1]])
    expect_identical(r$expr, cs[[3]], label = cs[[1]])
  }
})

test_that("T1, 1.2.3: a value on inline code is read in any form; keys hold the decoded value", {
  key <- function(src, k) {
    r <- qs(src)
    expect_identical(nrow(r), 1L, label = src)
    if (nrow(r) != 1L) return(NA_character_)
    expect_true(is.na(r$error), label = paste("no error:", src))
    expect_identical(r$kind, "value", label = src)
    unname(r$keys[[1]][[k]])
  }
  expect_identical(key("`r x`{.num digits='2'}", "digits"), "2")
  expect_identical(key("`r x`{.num digits=2}", "digits"), "2")
  expect_identical(key(r"{`r x`{unit=mm\|m}}", "unit"), "mm|m")
  expect_identical(key(r"{`r x`{unit="mm\|m"}}", "unit"), "mm|m")
  expect_identical(key(r"{`r x`{unit='mm\|m'}}", "unit"), "mm|m")
  expect_identical(key("`r x`{.num title=''}", "title"), "")
  expect_identical(key("`r x`{.num title=\"\"}", "title"), "")
  expect_identical(key("`r x`{.num title=R&amp;D}", "title"), "R&amp;D")
  expect_identical(key(r"{`r x`{.num title="a}b"}}", "title"), "a}b")
})

test_that("T1, 1.2.3, 1.8.10: a .weft-literal span's why is read in any form, with the escapes, line breaks as one space", {
  why <- function(src) {
    r <- qs(src)
    expect_identical(nrow(r), 1L, label = src)
    if (nrow(r) != 1L) return(NA_character_)
    expect_true(is.na(r$error), label = paste("no error:", src))
    expect_identical(r$kind, "literal", label = src)
    unname(r$keys[[1]][["why"]])
  }
  expect_identical(why(r"{[lit]{.weft-literal why='it\'s "quoted"'}}"), r"{it's "quoted"}")
  expect_identical(why(r"{[lit]{.weft-literal why="said \"about 5\" in the source"}}"), r"{said "about 5" in the source}")
  expect_identical(why(r"{[lit]{.weft-literal why="it's fine"}}"), "it's fine")
  expect_identical(why(r"{[lit]{.weft-literal why="it\'s fine"}}"), "it's fine")
  # D6: a line break is one space; the characters after it are kept
  expect_identical(why("[lit]{.weft-literal why=\"line one\nline two\"}"), "line one line two")
  expect_identical(why("[lit]{.weft-literal why=\"line one\n   line two\"}"), "line one    line two")
  expect_identical(why("[lit]{.weft-literal why=\"line one\r\nline two\"}"), "line one line two")
})

test_that("T1, 1.2.3: braces that are not a construct are never an error and give no row", {
  expect_identical(nrow(qs(r"{[a]{foo="a\\b"}}")), 0L)
  expect_identical(nrow(qs("[a]{title='x'}")), 0L)
  expect_identical(q_errs(r"{[a]{foo="a\\b"}}"), character(0))
})

test_that("T1, 1.2.3: a quote of the other kind needs no escape and a closing quote followed by white space or } is fine", {
  expect_true(is.na(qs(r"{`r x`{.num title="a 'b' c" digits=1}}")$error))
  expect_true(is.na(qs(r"{`r x`{.num title='a "b" c' digits=1}}")$error))
  expect_true(is.na(qs("`r x`{.num title='a'\tdigits=1}")$error))
})

# ---- T1: errors, with the exact texts -------------------------------------------------------------------

test_that("T1, M1: a backslash that does not escape a quote or a bar is the M1 error naming the first such key", {
  expect_identical(q_first(r"{[a | b]{if="grepl('\\d', s)"}}"), M1("if"))
  expect_identical(q_first(r"{[a | b]{if='grepl("\d+", s)'}}"), M1("if"))
  expect_identical(q_first(r"{[a | b]{if="a\ b"}}"), M1("if"))
  expect_identical(q_first("[a | b]{if=\"a\\\nb\"}"), M1("if"))
  expect_identical(q_first(r"{`r x`{.num title="a\\b"}}"), M1("title"))
  expect_identical(q_first(r"{`r x`{.num title="a\}b"}}"), M1("title"))
  expect_identical(q_first(r"{`r x`{.num title="a\$b"}}"), M1("title"))
})

test_that("T1, M1: the key keeps its letter case, and is the first in the block with the mistake", {
  expect_identical(q_first(r"{`r x`{.num Title="a\db" digits="1\z"}}"), M1("Title"))
})

test_that("T1, M2: a quote or a backslash in a bare value is the M2 error", {
  expect_identical(q_first(r"{[a | b]{if=x"y}}"), M2("if"))
  expect_identical(q_first(r"{[a | b]{if=\"flag\"}}"), M2("if"))
  expect_identical(q_first(r"{[a | b]{if=a\ b}}"), M2("if"))
  expect_identical(q_first(r"{`r x`{.num title=a\}b}}"), M2("title"))
})

test_that("T1, M3 (D6): a character reference in a quoted value is the M3 error naming the reference as written", {
  expect_identical(q_first(r"{[a | b]{if="x &amp;&amp; y"}}"), M3("&amp;", "if"))
  expect_identical(q_first(r"{`r x`{.num title="R&#38;D"}}"), M3("&#38;", "title"))
  expect_identical(q_first(r"{`r x`{.num title='&#39;'}}"), M3("&#39;", "title"))
  expect_identical(q_first(r"{`r x`{.num title="&#x41;"}}"), M3("&#x41;", "title"))
})

test_that("T1, M3 (D6) control: an ampersand that does not begin a reference is read as itself", {
  r <- qs(r"{`r x`{.num title="R & D" digits=1}}")
  expect_true(is.na(r$error))
  expect_identical(unname(r$keys[[1]][["title"]]), "R & D")
})

test_that("T1, M4: a block that does not parse and holds a weft key is one error with its cause, in the order of C2", {
  expect_identical(q_first(r"{[a | b]{if="tier == "sev""}}"), M4$q2)
  expect_identical(q_first(r"{[a | b]{if='it's'}}"), M4$q1)
  expect_identical(q_first(r"{`r x`{unit="m\"}}"), M4$open)
  expect_identical(q_first(r"{[a | b]{n="k".word}}"), M4$glued)
})

test_that("T1, M4: space, novalue and marker keep their causes (the texts are today's; the cause words are pinned)", {
  one <- function(src, cause) {
    e <- q_errs(src)
    expect_gte(length(e), 1L, label = src)
    expect_true(startsWith(e[1], M4_HEAD), label = src)
    expect_true(grepl(cause, e[1], fixed = TRUE), label = src)
    expect_true(grepl("1.2.9", e[1], fixed = TRUE), label = src)
    expect_false(grepl("bind", e[1], ignore.case = TRUE), label = paste("no bind hint (D11):", src))
  }
  one(r"{[a | b]{n = "k"}}", M4_CAUSE[["space"]])
  one(r"{[a | b]{if=}}", M4_CAUSE[["novalue"]])
  one(r"{[a | b]{# if="y"}}", M4_CAUSE[["marker"]])
})

test_that("T1, M4 (D11): no M4 text carries the bind hint; the backslash error (M1) keeps it", {
  for (src in c(r"{[a | b]{if="tier == "sev""}}", r"{[a | b]{if='it's'}}", r"{`r x`{unit="m\"}}", r"{[a | b]{n="k".word}}")) {
    expect_false(grepl("bind", q_first(src), ignore.case = TRUE), label = src)
  }
  expect_true(grepl("Bind the expression to a name", q_first(r"{[a | b]{if="a\db"}}"), fixed = TRUE))
})

test_that("T1, C2: one message per kind per block; M4 stands alone when the block does not parse", {
  e <- q_errs(r"{[a | b]{if="a\db" n="k"}}")
  expect_true(any(e == M1("if")))
  expect_identical(sum(e == M1("if")), 1L)
  e <- q_errs(r"{`r x`{.num title="a\db" digits="1\z" if="x "y""}}")
  expect_identical(e[1], M4$q2)
  expect_false(any(grepl("does not escape", e, fixed = TRUE)))
})

# ---- T1: pipe-table cells (M5, D8) ----------------------------------------------------------------------

test_that("T1, M5, 1.5.13, D8: an unescaped | in any value of a construct in a pipe-table cell is the M5 error", {
  expect_identical(q_first(q_tbl(r"{[x \| y]{if="p || q"}}")), M5("if"))
  expect_identical(q_first(q_tbl("`r x`{.num title='a|b'}")), M5("title"))
  expect_identical(q_first(q_tbl("`r x`{unit=\"mm|m|km\"}")), M5("unit"))
})

test_that("T1, D8: an escaped bar in a table cell is no error and is read as a bar", {
  r <- qs(q_tbl(r"{[x \| y]{if="p \|\| q"}}"))
  expect_identical(nrow(r), 1L)
  expect_true(is.na(r$error))
  expect_identical(r$kind, "if")
  expect_identical(r$expr, "p || q")
  r <- qs(q_tbl(r"{`r x`{.num title='a\|b'}}"))
  expect_true(is.na(r$error))
  expect_identical(unname(r$keys[[1]][["title"]]), "a|b")
})

test_that("T1, D8 control: the same bars outside a pipe-table cell are not the M5 error", {
  expect_identical(q_errs("[a | b]{if=\"p || q\"}"), character(0))
  expect_identical(q_errs("`r x`{.num title='a|b'}"), character(0))
})

# ---- T1: a filter-resolved document (D12) ----------------------------------------------------------------

test_that("T1, D12, 1.12.6: in a document the filter resolves a leading space in a single-quoted if is the 1.12.6 error", {
  lines <- w6d_doc(c("Intro.", "", "A [one | many]{if=' ok'} B."))
  r <- w6d_scan(lines)
  r <- r[r$kind == "if", , drop = FALSE]
  expect_identical(nrow(r), 1L)
  expect_false(is.na(r$error))
  expect_true(grepl("1.12.6", r$error, fixed = TRUE))
  x <- w6d_find(lines, "construct")
  expect_identical(nrow(x), 1L)
})

test_that("T1, D12 control: in a document the hooks resolve a leading space stays accepted, single-quoted too", {
  rmd <- w6d_scan(c("Intro.", "", "A [one | many]{if=' ok'} B."), name = "a.Rmd")
  expect_true(all(is.na(rmd$error)))
})

# ---- T2: broken blocks that hold why, decision or label (C3, D4) -----------------------------------------

test_that("T2, C3: a broken block holding why, decision or label is one row with M4", {
  r <- qs(r"{[lit]{.weft-literal why="said "about 5""}}")
  expect_identical(nrow(r), 1L)
  expect_identical(r$kind, "literal")
  expect_identical(r$error, M4$q2)

  r <- qs(r"{[lit]{.weft-literal decision='it's'}}")
  expect_identical(nrow(r), 1L)
  expect_identical(r$kind, "literal")
  expect_identical(r$error, M4$q1)

  r <- qs(r"{`r p`{.p label="p "x""}}")
  expect_identical(nrow(r), 1L)
  expect_identical(r$kind, "value")
  expect_identical(r$error, M4$q2)

  r <- qs(r"{`p_val`{.p label="a "b""}}")
  expect_identical(nrow(r), 1L)
  expect_identical(r$kind, "named")
  expect_identical(r$error, M4$q2)
})

test_that("T2, C3: a fenced div's opening line with a broken why is a literal row on its line", {
  r <- qs(paste(c("::: {.weft-literal why='it's fine'}", "Text.", ":::"), collapse = "\n"))
  expect_identical(nrow(r), 1L)
  expect_identical(r$kind, "literal")
  expect_identical(r$line, 1L)
  expect_identical(r$error, M4$q1)
})

test_that("T2, C3, D4: the line of the row is the line of the bracket", {
  r <- qs("Intro.\n\nSome [lit]{.weft-literal why='it's fine'} text.")
  expect_identical(nrow(r), 1L)
  expect_identical(r$line, 3L)
})

test_that("T2, C3 controls: braces with no detection key are not a block and not an error", {
  expect_identical(nrow(qs(r"{[a]{foo="a "b""}}")), 0L)
  expect_identical(q_errs(r"{`r x`{foo="a "b""}}"), character(0))
  expect_identical(q_errs(r"{[a]{foo="a "b""}}"), character(0))
})
