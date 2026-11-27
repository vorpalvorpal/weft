# The marquee target of the formatters and of format() (stage H2 of dev/design-html-target.md: rules RT1 to
# RT6, MQ1 to MQ5, messages E100, E107 to E109). The H0 results amend the design: E110, MQ6, D103 and
# marquee_version() are removed; math is escaped as text (`\$x\^2\$`). Rows come from helper-target-rich.R.
# marquee is not in the main library: the tests that need it skip. ASCII only.

# ---- MQ1 to MQ5: the rows of section 3 ---------------------------------------------------------------------

test_that("MQ1, MQ3, RT2: every fmt_*() row of the numbers and classes table under target = \"marquee\"", {
  rich_expect_fmt_rows(RICH_FMT_ROWS, "mq", "marquee")
})

test_that("MQ3, RT6: every unit row under target = \"marquee\"", {
  rich_expect_fmt_rows(RICH_UNIT_ROWS, "mq", "marquee")
})

test_that("MQ1 to MQ5, RT4: every row of text an author writes in weft()", {
  rich_expect_text_rows(RICH_TEXT_ROWS, "mq", "marquee")
})

test_that("MQ1 (H0): quotes, dashes and dots stay as typed (marquee has no smartypants)", {
  rich_expect_text_rows(RICH_H0_ROWS, "mq", "marquee")
})

test_that("MQ2: the start of the text", {
  rich_expect_text_rows(RICH_START_ROWS, "mq", "marquee")
})

test_that("MQ1: a backslash goes before each of \\ ` * _ ~ [ ] { } < > & $ ^ and before nothing else", {
  g2_cfg(NULL)
  # the author's text is markdown; each character is made literal there with a backslash
  for (ch in c("\\", "`", "*", "_", "~", "[", "]", "{", "}", "<", ">", "&", "$", "^")) {
    w <- weft(paste0("a \\", ch, " b"))
    expect_identical(rich_fmt_text(w, "marquee"), paste0("a \\", ch, " b"), label = ch)
  }
  for (ch in c("/", "(", ")", "|", "@", "%", "!", "?", ",", ";")) {
    w <- weft(paste0("a ", ch, " b"))
    expect_identical(rich_fmt_text(w, "marquee"), paste0("a ", ch, " b"), label = ch)
  }
})

test_that("MQ3: nested strong emphasis; an empty run writes nothing; a span is its content", {
  g2_cfg(NULL)
  expect_match(rich_fmt_text(weft("***x***"), "marquee"),
               "^(\\{\\.em \\{\\.str x\\}\\}|\\{\\.str \\{\\.em x\\}\\})$")
  expect_identical(rich_fmt_text(weft("a[]{.x}b"), "marquee"), "ab")
  expect_identical(rich_fmt_text(weft("[x]{}"), "marquee"), "x")
})

test_that("MQ3: a code span uses a run of backticks one longer than the longest inside, and pads a backtick end", {
  g2_cfg(NULL)
  expect_identical(rich_fmt_text(weft("``a`b``"), "marquee"), "``a`b``")
  expect_identical(rich_fmt_text(weft("`` `a ``"), "marquee"), "`` `a ``")
})

test_that("MQ4: one newline is a hard break (backslash, newline); two or more are one blank line", {
  g2_cfg(NULL)
  expect_identical(rich_fmt_text(weft("a\nb"), "marquee"), "a\\\nb")
  expect_identical(rich_fmt_text(weft("a\r\nb"), "marquee"), "a\\\nb")
  expect_identical(rich_fmt_text(weft("a\n\nb"), "marquee"), "a\n\nb")
  expect_identical(rich_fmt_text(weft("a\n\n\nb"), "marquee"), "a\n\nb")
})

test_that("MQ2, MQ4: a list keeps its lines, each line start escaped", {
  g2_cfg(NULL)
  expect_identical(f2_tx(fmt_ul(c("a", "b"), target = "marquee")), "\\- a\\\n\\- b")
  expect_identical(f2_tx(fmt_ol(c("a", "b"), target = "marquee")), "1\\. a\\\n2\\. b")
})

# ---- RT3: the attribute ---------------------------------------------------------------------------------------

test_that("RT3: the result carries target = \"marquee\", the printed record and the unit attribute", {
  g2_cfg(NULL)
  x <- fmt_num(5, target = "marquee")
  expect_s3_class(x, "weft_text")
  expect_identical(attr(x, "target"), "marquee")
  expect_equal(attr(x, "number"), 5)
  y <- fmt_num(u(5, m^2), target = "marquee")
  expect_identical(attr(y, "unit"), "m{.sup 2}")
  expect_identical(attr(y, "target"), "marquee")
})

test_that("RT1: every fmt_*() takes target = \"marquee\" and returns a weft_text with that target", {
  g2_cfg(NULL)
  for (nm in names(RICH_CALLS)) {
    x <- RICH_CALLS[[nm]](target = "marquee")
    expect_s3_class(x, "weft_text")
    expect_identical(attr(x, "target"), "marquee", label = nm)
  }
})

test_that("RT4: format(x, target = \"marquee\") is a bare character vector, with names kept", {
  x <- format(weft(c(k = "a *b*", m = "c")), target = "marquee")
  expect_identical(class(x), "character")
  expect_null(attr(x, "html"))
  expect_identical(names(x), c("k", "m"))
  expect_identical(unname(x), c("a {.em b}", "c"))
})

test_that("RT4: an element joined as text is escaped as text; NA is \"NA\"", {
  x <- c(weft("a"), "b*c*", "d_e_")
  expect_identical(unname(as.character(format(x, target = "marquee"))), c("a", "b\\*c\\*", "d\\_e\\_"))
  expect_identical(unname(format(weft(NA_character_), target = "marquee")), "NA")
})

# ---- RT5: mixing ------------------------------------------------------------------------------------------------

test_that("RT5, E107: a marquee text cannot be formatted again, except from its number", {
  g2_cfg(NULL)
  m <- fmt_num(5, target = "marquee")
  rich_expect_error(f2_cond(fmt_strong(m)), "weft_value_error", RICH_E107("marquee", "marquee"))
  rich_expect_error(f2_cond(fmt_strong(m, target = "marquee")), "weft_value_error", RICH_E107("marquee", "marquee"))
  expect_identical(f2_tx(fmt_num(m)), "5")
  expect_identical(f2_tx(fmt_strong(fmt_num(5), target = "marquee")), "{.str 5}")
})

test_that("RT5, E107: an html text cannot go to a marquee formatter either", {
  g2_cfg(NULL)
  h <- fmt_num(5, target = "html")
  rich_expect_error(f2_cond(fmt_strong(h, target = "marquee")), "weft_value_error", RICH_E107("HTML", "html"))
})

test_that("RT5, E108: a TeX text reaching a marquee result", {
  g2_cfg(NULL)
  e <- f2_cond(fmt_strong(fmt_num(5, target = "tex"), target = "marquee"))
  rich_expect_error(e, "weft_value_error", RICH_E108("marquee text", "marquee"))
})

test_that("RT5, E109: a marquee text cannot join a weft object; a plain one can", {
  g2_cfg(NULL)
  rich_expect_error(f2_cond(c(weft("a"), fmt_num(5, target = "marquee"))), "weft_construct_error",
                    RICH_E109("marquee", "marquee"))
  w <- weft(c("a", "b"))
  e <- f2_cond(w[2] <- fmt_num(5, target = "marquee"))
  rich_expect_error(e, "weft_construct_error", RICH_E109("marquee", "marquee"))
  expect_null(f2_cond(c(weft("a"), fmt_num(5, target = "plain"))))
})

test_that("RT6: fmt_unit() takes target = \"marquee\"", {
  g2_cfg(NULL)
  x <- fmt_unit(u(1, m^2), target = "marquee")
  expect_identical(f2_tx(x), "m{.sup 2}")
  expect_identical(attr(x, "target"), "marquee")
})

# ---- D104 --------------------------------------------------------------------------------------------------------

test_that("D104, RT2: a project formatter's markdown is read and rendered under marquee", {
  rich_install("fmt_tidy", function(x, ...) paste0("*", x, "*"))
  withr::local_dir(f2_proj(rich_reg(".tidy", "fmt_tidy")))
  expect_identical(rich_fmt_text(weft("`r 3`{.tidy}"), "marquee"), "{.em 3}")
})

test_that("D104, RT2: a formatter that lists tex is called with target = \"markdown\" under marquee", {
  store <- new.env()
  store$seen <- character()
  rich_install("fmt_seen", function(x, target = "markdown", ...) {
    store$seen <- c(store$seen, target)
    paste0("[", x, "]")
  })
  withr::local_dir(f2_proj(rich_reg(".seen", "fmt_seen", extra = "    targets: [markdown, tex]")))
  out <- rich_fmt_text(weft("`r 3`{.seen}"), "marquee")
  expect_true(length(store$seen) >= 1L)
  expect_true(all(store$seen == "markdown"))
  expect_identical(out, "\\[3\\]")
})

# ---- H0: no version check ------------------------------------------------------------------------------------------

test_that("MQ6 (removed by H0): there is no marquee_version() and no E110; a superscript never raises", {
  expect_false(exists("marquee_version", envir = asNamespace("weft"), inherits = FALSE))
  g2_cfg(NULL)
  expect_identical(f2_tx(fmt_sci(0.000123, target = "marquee")), "1.2 \u00d7 10{.sup \u22124}")
})

# ---- parse agreement (needs marquee) -------------------------------------------------------------------------------

mq_digits <- c("\u2070" = "0", "\u00b9" = "1", "\u00b2" = "2", "\u00b3" = "3", "\u2074" = "4", "\u2075" = "5",
               "\u2076" = "6", "\u2077" = "7", "\u2078" = "8", "\u2079" = "9", "\u207b" = "\u2212",
               "\u2080" = "0", "\u2081" = "1", "\u2082" = "2", "\u2083" = "3", "\u2084" = "4", "\u2085" = "5",
               "\u2086" = "6", "\u2087" = "7", "\u2088" = "8", "\u2089" = "9")
mq_unscript <- function(x) {
  for (k in names(mq_digits)) x <- gsub(k, mq_digits[[k]], x, fixed = TRUE)
  x
}
mq_flat <- function(x) gsub("\n", "", x, fixed = TRUE)

test_that("MQ3: marquee reads each row as the plain text, with no strikethrough or underline anywhere", {
  skip_if_not_installed("marquee")
  skip_if_not_installed("marquee", "1.2.0")
  for (r in c(RICH_FMT_ROWS, RICH_UNIT_ROWS)) {
    g2_restore()
    withr::local_dir(f2_proj(r$yml))
    p <- marquee::marquee_parse(f2_tx(r$f(target = "marquee")))
    plain <- gsub("^\n+|\n+$", "", f2_tx(r$f(target = "plain")))
    expect_identical(mq_flat(paste(p$text, collapse = "")), mq_flat(mq_unscript(plain)), label = paste("row", r$id))
    expect_false(any(p$strikethrough), label = paste("strikethrough, row", r$id))
    expect_false(any(p$underline), label = paste("underline, row", r$id))
  }
  g2_cfg(NULL)
  for (r in Filter(function(r) r$plain, c(RICH_TEXT_ROWS, RICH_H0_ROWS))) {
    w <- rich_weft(r$x)
    p <- marquee::marquee_parse(rich_fmt_text(w, "marquee"))
    expect_identical(mq_flat(paste(p$text, collapse = "")), mq_flat(unname(as.character(w))), label = paste("row", r$id))
    expect_false(any(p$strikethrough), label = paste("strikethrough, row", r$id))
    expect_false(any(p$underline), label = paste("underline, row", r$id))
  }
})

test_that("MQ3: the superscript of a negative exponent has the sup style; emphasis is italic", {
  skip_if_not_installed("marquee")
  g2_cfg(NULL)
  p <- marquee::marquee_parse(f2_tx(fmt_sci(-0.000123, target = "marquee")))
  piece <- p[p$text == "\u22124", , drop = FALSE]
  expect_identical(nrow(piece), 1L)
  body <- p[p$type == "p", , drop = FALSE]
  expect_gt(piece$baseline, 0)
  expect_lt(piece$size, max(body$size))
  q <- marquee::marquee_parse(f2_tx(fmt_em("Eucalyptus", target = "marquee")))
  expect_true(q$italic[q$text == "Eucalyptus"])
})

test_that("MQ2, MQ3: a no-break space and a thin space survive the parse", {
  skip_if_not_installed("marquee")
  g2_cfg(NULL)
  p <- marquee::marquee_parse(f2_tx(fmt_num(u(5, mg/L), target = "marquee")))
  expect_true(grepl("5\u00a0mg/L", paste(p$text, collapse = ""), fixed = TRUE))
})
