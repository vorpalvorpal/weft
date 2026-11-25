# Package E1 (dev/design-e1.md): the plain reading (PL1 to PL11), the per-class table (FT) and
# fmt_*(target = "plain") (T4, T5). Non-ASCII is written as \u escapes: \u00a0 no-break space,
# \u2212 minus, \u00d7 times, \u207b superscript minus, \u00b2 \u00b3 \u2074 \u2076 superscripts,
# \u2082 subscript 2, \u221e infinity.

e1p_plain <- function(x, .envir = parent.frame()) as.character(weft(x, .envir = .envir))
e1p_md <- function(x, .envir = parent.frame()) unname(format(weft(x, .envir = .envir), target = "markdown"))

# ---- T4: the reader table (PL) ----------------------------------------------------------------

# the input is the markdown of an element; weft() of a string with no construct has exactly this
# as its markdown (design table)
e1p_rows <- list(
  list("A **plain** string, 5 < 6.", "A plain string, 5 < 6."),
  list("*a*", "a"), list("**a**", "a"), list("***a***", "a"), list("_a_", "a"), list("__a__", "a"),
  list("snake_case_name", "snake_case_name"),
  list("5 * 3 and 2 * 4", "5 * 3 and 2 * 4"),
  list("a * b*", "a * b*"),
  list("2*3*4", "234"),
  list(r"---(\*a\*)---", "*a*"),
  list(r"---(C:\Users)---", r"---(C:\Users)---"),
  list("m^2^", "m\u00b2"),
  list("10^\u22124^", "10\u207b\u2074"),
  list("10^-4^", "10\u207b\u2074"),
  list("x^ab^", "x^(ab)"),
  list("x^a b^", "x^a b^"),
  list("CO~2~", "CO\u2082"),
  list("NO~x~", "NO_(x)"),
  list("~~gone~~", "~~gone~~"),
  list("*m^2^*", "m\u00b2"),
  list("^*2*^", "\u00b2"),
  list("1.2 &times; 10<sup>-4</sup>", "1.2 \u00d7 10\u207b\u2074"),
  list("&infin;", "\u221e"),
  list("&#8722;3", "\u22123"),
  list("R&D", "R&D"),
  list("*1*<!-- -->*2*", "12"),
  list("[3]{.smallcaps}", "3"),
  list("[1990]{.weft-literal why='a year'}", "1990"),
  list("as shown [@smith2020]", "as shown [@smith2020]"),
  list("[a](http://x)", "[a](http://x)"),
  list("[1]", "[1]"),
  list("`code`", "code"),
  list("`` a`b ``", "a`b"),
  list("$x^2$", "$x^2$"),
  list("costs $5 and $10", "costs $5 and $10"),
  list("- a\n- b", "- a\n- b"),
  list("a\\\nb", "a\nb"),
  list("<<weft: failed claim, chunk fig-a>>", "<<weft: failed claim, chunk fig-a>>")
)

test_that("T4 PL: every row of the reader table reads to its plain column (as.character and format)", {
  for (r in e1p_rows) {
    w <- weft(r[[1]])
    expect_identical(unname(as.character(w)), r[[2]], label = paste("as.character:", r[[1]]))
    expect_identical(unname(format(w, target = "plain")), r[[2]], label = paste("format plain:", r[[1]]))
  }
})

test_that("T4 PL: the markdown form of a string with no construct is the string as written", {
  for (r in e1p_rows) {
    # a .weft-literal span needs a why (1.8.10), which weft does not write back
    want <- sub(" why='a year'", "", r[[1]], fixed = TRUE)
    expect_identical(e1p_md(r[[1]]), want, label = paste("markdown:", r[[1]]))
  }
})

test_that("T4 PL: several rows at once keep their own readings (vector input)", {
  x <- vapply(e1p_rows, `[[`, "", 1L)
  y <- vapply(e1p_rows, `[[`, "", 2L)
  expect_identical(unname(as.character(weft(x))), y)
})

test_that("T4 PL1/PL2: an escape hides the delimiter from every other rule; code is verbatim", {
  expect_identical(e1p_plain(r"---(\_not emphasis\_ and `*raw*`)---"), "_not emphasis_ and *raw*")
  expect_identical(e1p_plain("`m^2^`"), "m^2^")
})

# ---- T4: the per-class table, through weft() (FT) ----------------------------------------------

test_that("T4 FT: classes with no markup read the same in both forms", {
  w <- weft(c("`r 12.5`{.num} m", "`r 0.123`{.pct}", "`r 3`{.word} sites", "`r 3`{.count}"))
  expect_identical(unname(as.character(w)), unname(e1p_md(c("`r 12.5`{.num} m", "`r 0.123`{.pct}",
                                                         "`r 3`{.word} sites", "`r 3`{.count}"))))
  expect_identical(unname(as.character(w))[1:3], c("12.5 m", "12.3%", "three sites"))
})

test_that("T4 FT: .sci reads 1.2 \u00d7 10\u207b\u2074 and 1.2 \u00d7 10\u2076", {
  expect_identical(e1p_plain("`r 0.000123`{.sci}"), "1.2 \u00d7 10\u207b\u2074")
  expect_identical(e1p_plain("`r 1200000`{.sci}"), "1.2 \u00d7 10\u2076")
  expect_match(e1p_md("`r 0.000123`{.sci}"), "10^\u22124^", fixed = TRUE)
})

test_that("T4 FT: unit symbols read as Unicode superscripts, with the no-break space kept", {
  expect_identical(e1p_plain("`r u(5, m^2)`{.num}"), "5\u00a0m\u00b2")
  expect_identical(e1p_plain("`r u(2, 1/s)`{.num}"), "2\u00a0s\u207b\u00b9")
  expect_identical(e1p_plain("`r u(3, m^3/s)`{.num}"), "3\u00a0m\u00b3/s")
  expect_identical(e1p_plain("`r u(4, kg*m)`{.num}"), "4\u00a0kg\u00b7m")
  expect_identical(e1p_plain("`r u(5, mg/L)`{.num}"), "5\u00a0mg/L")
  expect_identical(e1p_md("`r u(5, m^2)`{.num}"), "5\u00a0m^2^")
})

test_that("T4 FT: a symbol with an escape in units: reads without the backslash", {
  root <- withr::local_tempdir()
  writeLines(c("units:", "  zze1ugc:", "    symbol: \"\u00b5g\\\\_C\""), file.path(root, "_weft.yml"))
  withr::local_dir(root)
  weft:::string_config_reset()
  expect_identical(e1p_plain("`r u(3, zze1ugc)`{.num}"), "3\u00a0\u00b5g_C")
  expect_identical(e1p_md("`r u(3, zze1ugc)`{.num}"), "3\u00a0\u00b5g\\_C")
})

test_that("T4 FT: .em and .strong lose their markup, markdown keeps it", {
  expect_identical(e1p_plain("`r 'x'`{.em}"), "x")
  expect_identical(e1p_plain("`r 'x'`{.strong}"), "x")
  expect_identical(e1p_md("`r 'x'`{.em}"), "*x*")
  expect_identical(e1p_md("`r 'x'`{.strong}"), "**x**")
})

test_that("T4 FT: .p reads p = 0.046; a markdown p_label reads without markup", {
  expect_identical(e1p_plain("`r 0.046`{.p}"), "p = 0.046")
  root <- withr::local_tempdir()
  writeLines("p_label: \"*p*\"", file.path(root, "_weft.yml"))
  withr::local_dir(root)
  weft:::string_config_reset()
  expect_identical(e1p_md("`r 0.046`{.p}"), "*p* = 0.046")
  expect_identical(e1p_plain("`r 0.046`{.p}"), "p = 0.046")
})

test_that("T4 FT: two emphasis constructs side by side read 12; markdown keeps the comment", {
  expect_identical(e1p_md("`r 1`{.em}`r 2`{.em}"), "*1*<!-- -->*2*")
  expect_identical(e1p_plain("`r 1`{.em}`r 2`{.em}"), "12")
})

test_that("T4 FT: lists keep their lines in plain (D12)", {
  for (cls in c(".ul", ".ol")) {
    src <- sprintf("`r c('a', 'b')`{%s}", cls)
    expect_identical(e1p_plain(src), e1p_md(src), label = cls)
  }
  src <- "`r c(a = 'x', b = 'y')`{.dl}"
  expect_identical(e1p_plain(src), e1p_md(src), label = ".dl")
  expect_match(e1p_plain("`r c('a', 'b')`{.ul}"), "- a\n- b", fixed = TRUE)
})

test_that("T4 FT: n, if and nested spans choose an arm that is read by PL, with emphasis and a unit", {
  k <- 9
  src <- "[a | *b* `r u(5, m^2)`{.num}]{if='k < 5'}"  # the first arm is the true one
  expect_identical(e1p_md(src), "*b* 5\u00a0m^2^")
  expect_identical(e1p_plain(src), "b 5\u00a0m\u00b2")
  k <- 3
  nested <- "[a site | [few | *many*]{if='k < 5'} sites]{n='k'} sampled"
  expect_identical(e1p_plain(nested), "few sites sampled")
  k <- 9
  expect_identical(e1p_md(nested), "*many* sites sampled")
  expect_identical(e1p_plain(nested), "many sites sampled")
  k <- 3
  src2 <- "[a site | *# sites*]{n='k'}"
  expect_identical(e1p_md(src2), "*3 sites*")
  expect_identical(e1p_plain(src2), "3 sites")
})

# E2 BN1, BN9, D3: weft() reads a named value from .envir; an unbound name is a failure, not left as written
test_that("T4 FT (E2): a named value is read from .envir, in both forms; an unbound one stops with weft_no_value (WS4)", {
  x <- 12.5
  expect_identical(e1p_plain("see `x`{.num} here"), "see 12.5 here")
  expect_identical(e1p_md("see `x`{.num} here"), "see 12.5 here")
  expect_error(e1p_plain("see `unbound_zz`{.num} here"), class = "weft_no_value")
})

test_that("T4 FT: the minus sign, no-break and thin spaces are kept", {
  expect_identical(e1p_plain("a\u2212b\u00a0c\u2009d"), "a\u2212b\u00a0c\u2009d")
})

test_that("T4 WS5: bare inline R reads as knitr writes it, then by PL", {
  expect_identical(e1p_plain("Sum `r 1 + 1` here"), "Sum 2 here")
  expect_identical(e1p_plain("`r 'm^2^'`"), "m\u00b2")
})

# ---- T5: formatter plain (FT1 to FT5) ----------------------------------------------------------

test_that("T5 FT1: fmt_sci() under plain is 1.2 \u00d7 10\u207b\u2074", {
  expect_identical(as.character(unclass(fmt_sci(0.000123, target = "plain"))), "1.2 \u00d7 10\u207b\u2074")
})

test_that("T5 FT1: fmt_num() of a unit under plain: text, unit attribute and the record of the markdown call", {
  p <- fmt_num(u(5, m^2), target = "plain")
  m <- fmt_num(u(5, m^2))
  expect_identical(as.character(unclass(p)), "5\u00a0m\u00b2")
  expect_identical(attr(p, "unit"), "m\u00b2")
  for (a in c("number", "decimals", "relation", "raw", "units", "unit_form", "unit_before", "is_symbol")) {
    expect_identical(attr(p, a), attr(m, a), label = a)
  }
  expect_identical(attr(p, "target"), "plain")
  expect_s3_class(p, "weft_text")
})

test_that("T5 FT1: fmt_unit() under plain", {
  expect_identical(as.character(unclass(fmt_unit(u(1, 1/s), target = "plain"))), "s\u207b\u00b9")
  expect_identical(as.character(unclass(fmt_unit(u(1, m^2), target = "plain"))), "m\u00b2")
})

test_that("T5 FT1/FT2: fmt_em() and fmt_strong() accept plain (no TeX refusal) and return the text without markup", {
  x <- fmt_em("x", target = "plain")
  expect_identical(as.character(unclass(x)), "x")
  expect_identical(attr(x, "target"), "plain")
  expect_identical(as.character(unclass(fmt_strong("x", target = "plain"))), "x")
})

test_that("T5 FT1: lists under plain read the same as markdown", {
  for (f in list(fmt_ul, fmt_ol, fmt_dl)) {
    v <- if (identical(f, fmt_dl)) c(a = "x", b = "y") else c("a", "b")
    expect_identical(as.character(unclass(f(v, target = "plain"))), as.character(unclass(f(v))))
  }
})

test_that("T5 FT1: apply_formatters() takes target = 'plain'", {
  x <- weft:::apply_formatters(0.000123, ".sci", target = "plain")
  expect_identical(as.character(unclass(x)), "1.2 \u00d7 10\u207b\u2074")
})

test_that("T5 FT1: a plain result carries the attribute target = 'plain'; markdown carries none", {
  expect_identical(attr(fmt_num(2, target = "plain"), "target"), "plain")
  expect_null(attr(fmt_num(2), "target"))
  expect_null(attr(fmt_num(2, target = "markdown"), "target"))
})

test_that("T5 FT3: a target that is not markdown, tex or plain is a weft_construct_error", {
  e <- tryCatch(fmt_num(1, target = "html"), error = function(e) e)
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e), "`target` must be \"markdown\", \"tex\" or \"plain\"; got \"html\".", fixed = TRUE)
  e2 <- tryCatch(fmt_num(1, target = 1), error = function(e) e)
  expect_s3_class(e2, "weft_construct_error")
  expect_match(conditionMessage(e2), "got something else.", fixed = TRUE)
})

test_that("T5 FT4: a TeX text given to a formatter under plain is a weft_value_error with the stated text", {
  e <- tryCatch(fmt_cap(fmt_num(2, target = "tex"), target = "plain"), error = function(e) e)
  expect_s3_class(e, "weft_value_error")
  expect_match(conditionMessage(e), paste0(
    "This text was formatted for TeX (target = \"tex\") and would print here as plain text. ",
    "Format the number again, with target = \"plain\" (rule 3.4.11)."), fixed = TRUE)
})

test_that("T5 FT4: a plain text given to a formatter under markdown works, and is treated as markdown", {
  p <- fmt_num(c(1, 2), target = "plain")
  x <- fmt_and(p)
  expect_identical(as.character(unclass(x)), "1 and 2")
})

test_that("T5 FT1: every markdown result is identical to a call without target", {
  calls <- list(
    function(...) fmt_num(1234.567, ...), function(...) fmt_pct(0.123, ...),
    function(...) fmt_sci(0.000123, ...), function(...) fmt_num(u(5, m^2), ...),
    function(...) fmt_em("x", ...), function(...) fmt_p(0.03, ...))
  for (f in calls) expect_identical(f(target = "markdown"), f())
})

test_that("T5 FT1: plain keeps the minus sign and names", {
  x <- fmt_num(c(a = -1.5, b = 2), target = "plain")
  expect_identical(names(x), c("a", "b"))
  expect_identical(unname(as.character(unclass(x)))[1], "\u22121.5")
})
