# Package Q (dev/design-quoting.md), T3: ONE table of attribute values as written, run against weft's
# reading and against Pandoc's, so that weft's reading stays a strict subset of Pandoc's (D1).
# The table is _conformance/quoting.tsv, read with f6_read() (helper-6f.R); its columns:
#   written  a value as written, quotes included, percent-escaped (%20 space, %25 percent, %0A line break,
#            %09 tab), unescaped with gr_unesc() of test-conformance-grammar.R's convention
#   verdict  ok, M1, M2, M3 or M4 (C2 of the design)
#   value    the decoded value, for ok rows
# Two drivers: the scanner (a value on `r 1`{.num digits="1" title=WRITTEN}), and Pandoc (a paragraph
# [x]{title=WRITTEN} per ok row, to JSON). ASCII only.

# the percent-unescape of the conformance tables of this package
q_unesc <- function(x) {
  x <- gsub("%0A", "\n", x, fixed = TRUE)
  x <- gsub("%09", "\t", x, fixed = TRUE)
  f6_unesc(x)
}

q_table <- function() {
  d <- f6_read("quoting")
  d$written <- q_unesc(d$written)
  d$value <- q_unesc(d$value)
  d
}

# what each verdict's error starts with, up to its first %s
Q_PREFIX <- c(
  M1 = "A `\\` in the value of `",
  M2 = "A `\"`, `'` or `\\` in the value of `",
  M3 = "A character reference, `",
  M4 = "The attribute block does not parse:"
)

# the first Span's attribute `key` of each paragraph of `md` through Pandoc (NA when a paragraph holds no
# span or the attribute)
q_pandoc_attr <- function(md, key = "title") {
  skip_if_no_lua_pandoc()
  p <- lua_pandoc()
  dir <- withr::local_tempdir()
  f <- file.path(dir, "doc.md")
  writeLines(md, f, useBytes = TRUE)
  out <- suppressWarnings(system2(p$cmd, c(p$pre, "-f", "markdown", "-t", "json", shQuote(f)),
                                  stdout = TRUE, stderr = FALSE))
  j <- jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
  vapply(j$blocks, function(b) {
    if (!identical(b$t, "Para")) return(NA_character_)
    for (i in b$c) {
      if (identical(i$t, "Span")) {
        for (kv in i$c[[1]][[3]]) if (identical(kv[[1]], key)) return(as.character(kv[[2]]))
        return(NA_character_)
      }
    }
    NA_character_
  }, "")
}

test_that("T3: quoting.tsv has every verdict, the rows the design names, and no row twice", {
  d <- q_table()
  expect_setequal(unique(d$verdict), c("ok", "M1", "M2", "M3", "M4"))
  expect_identical(anyDuplicated(d$written), 0L)
  expect_true(all(c("\"a b\"", "'a b'", "ab", "\"\"", "''", "'say \"hi\"'", "\"it's\"", "a\\|b", "\"a}b\"",
                    "'{x}'", "R&amp;D", "\"a\\\\b\"", "a\"b", "\"R&amp;D\"", "\"k\".c") %in% d$written))
  expect_true("a    b" %in% d$value)
  expect_true("line one line two" %in% d$value)
  expect_true(all(d$value[d$verdict != "ok"] == ""))
})

test_that("T3, scanner: every row of quoting.tsv gives its verdict (ok: no error and the value; else the error text)", {
  d <- q_table()
  bad <- character()
  for (i in seq_len(nrow(d))) {
    src <- paste0("`r 1`{.num digits=\"1\" title=", d$written[i], "}")
    r <- weft:::scan_text(src)
    err <- as.character(r$error[!is.na(r$error)])
    got <- tryCatch(unname(r$keys[[1]][["title"]]), error = function(e) NA_character_)
    if (d$verdict[i] == "ok") {
      if (length(err) || is.null(got) || is.na(got) || !identical(got, d$value[i]))
        bad <- c(bad, sprintf("row %d [%s]: want ok with value '%s', got '%s' and error '%s'", i,
                              encodeString(d$written[i]), d$value[i], paste(got, collapse = "/"),
                              paste(substr(err, 1, 60), collapse = " ; ")))
    } else {
      want <- Q_PREFIX[[d$verdict[i]]]
      if (!length(err) || !startsWith(err[1], want))
        bad <- c(bad, sprintf("row %d [%s]: want %s, got '%s'", i, encodeString(d$written[i]), d$verdict[i],
                              substr(paste(err, collapse = " ; "), 1, 80)))
      else if (d$verdict[i] %in% c("M1", "M2", "M3") && !grepl("`title`", err[1], fixed = TRUE))
        bad <- c(bad, sprintf("row %d [%s]: the message does not name `title`", i, encodeString(d$written[i])))
    }
  }
  expect_identical(bad, character())
})

test_that("T3, Pandoc: every ok row, written as [x]{title=WRITTEN}, is read by Pandoc as the row's value (D1: the subset rule)", {
  d <- q_table()
  d <- d[d$verdict == "ok", , drop = FALSE]
  expect_gt(nrow(d), 15L)
  md <- unlist(lapply(d$written, function(w) c(paste0("[x]{title=", w, "}"), "")))
  got <- q_pandoc_attr(md)
  expect_length(got, nrow(d))
  bad <- sprintf("row %d [%s]: want '%s', Pandoc read '%s'", seq_len(nrow(d)), encodeString(d$written),
                 d$value, got)[is.na(got) | got != d$value]
  expect_identical(bad, character())
})

# ---- T4: what weft writes, read back by Pandoc (D5, D9) --------------------------------------------------

test_that("T4, D5, D9: the pass-through spans and literals weft writes carry the value the source decoded to, read by Pandoc", {
  src <- c(
    r"{`r 1.2`{.num custom-style='Key "figure"'}}",
    r"{`r 1.2`{.num title="a\|b"}}",
    r"{`r 1.2`{.num title="it's"}}"
  )
  want <- c(r"{Key "figure"}", "a|b", "it's")
  ws <- function(x) tryCatch(weft_md(x), error = function(e) paste("ERROR:", conditionMessage(e)))
  out <- vapply(src, ws, "", USE.NAMES = FALSE)
  keys <- c("custom-style", "title", "title")
  for (i in seq_along(src)) {
    got <- q_pandoc_attr(c(out[i], ""), keys[i])
    expect_identical(got, want[i], label = paste("Pandoc's reading of", out[i]))
  }
  lit <- ws(r"{[lit]{.weft-literal why='it\'s fine' title='say "hi"'}}")
  expect_identical(q_pandoc_attr(c(lit, ""), "title"), r"{say "hi"}")
})
