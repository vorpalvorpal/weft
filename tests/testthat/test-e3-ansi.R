# Package E3 (dev/design-e3.md): the ANSI rendering, when styles are written, format(), print() and
# the target errors (C1 to C7, C12; T1 to T7). Non-ASCII is written as \u escapes: \u00b2 is
# superscript 2, \u2082 is subscript 2.

# design ambiguity: the design asks for these helpers in helper-0-common.R; the test-writer may not
# modify existing files, so they live here under e3_ names.
e3_ESC <- "\u001b"
e3_ansi_on <- function(env = parent.frame()) {
  withr::local_options(cli.num_colors = 256L, .local_envir = env)
}
e3_fmt <- function(m) unname(format(weft(m), target = "ansi"))

# ---- T1: run kinds (C1, C2) --------------------------------------------------------------------

e3_rows <- list(
  list("a *b* c", "a \u001b[3mb\u001b[23m c"),
  list("a _b_ c", "a \u001b[3mb\u001b[23m c"),
  list("**b**", "\u001b[1mb\u001b[22m"),
  list("__b__", "\u001b[1mb\u001b[22m"),
  list("***b***", "\u001b[1m\u001b[3mb\u001b[23m\u001b[22m"),
  list("*a **b** c*", "\u001b[3ma \u001b[1mb\u001b[22m c\u001b[23m"),
  list("*m^2^*", "\u001b[3mm\u00b2\u001b[23m"),
  list("10^*2*^", "10\u00b2"),
  list("x^*ab*^", "x^(\u001b[3mab\u001b[23m)"),
  list("CO~2~", "CO\u2082"),
  list("`code` here", "code here"),
  list("$x^2$ and $y$", "$x^2$ and $y$"),
  list("[3]{.smallcaps}", "3"),
  list("*1*<!-- -->*2*", "\u001b[3m1\u001b[23m\u001b[3m2\u001b[23m"),
  list("<<weft: failed claim, chunk fig-a>>",
       "\u001b[1m\u001b[31m<<weft: failed claim, chunk fig-a>>\u001b[39m\u001b[22m"),
  list("see <<weft: no value, line 4>> here",
       "see \u001b[1m\u001b[31m<<weft: no value, line 4>>\u001b[39m\u001b[22m here"),
  list("[x]{.em}", "\u001b[3mx\u001b[23m"),
  list("`r 2`{.num} m^2^", "2 m\u00b2"),
  list("plain words", "plain words")
)

test_that("T1 C1/C2: each run kind has the exact ANSI bytes of the design table", {
  e3_ansi_on()
  for (row in e3_rows) {
    expect_identical(e3_fmt(row[[1]]), row[[2]], label = row[[1]])
  }
})

test_that("T1 C2: the result is a bare character string, with no cli_ansi_string class", {
  e3_ansi_on()
  out <- format(weft("a *b*"), target = "ansi")
  expect_type(out, "character")
  expect_false(inherits(out, "cli_ansi_string"))
  expect_false(inherits(out, "weft"))
})

test_that("T1 C2: a full reset (ESC[0m) is never written", {
  e3_ansi_on()
  for (row in e3_rows) {
    expect_false(grepl("\u001b[0m", e3_fmt(row[[1]]), fixed = TRUE), label = row[[1]])
  }
})

test_that("T1 C2: a weft text inside a cli colour keeps the colour around it", {
  e3_ansi_on()
  out <- cli::col_blue(paste0("A ", e3_fmt("*b*"), " C"))
  # the colour is closed once, at the end, not by anything weft wrote
  expect_identical(sum(gregexpr("\u001b[39m", out, fixed = TRUE)[[1]] > 0), 1L)
})

# ---- T2: strip gives plain (C3) ----------------------------------------------------------------

# design ambiguity: E1's reader table lives in test-e1-plain.R and is not visible here; the inputs
# below repeat that table's rows (those weft() accepts as input) and add the T1 inputs.
e3_reader_inputs <- c(
  "A **plain** string, 5 < 6.", "*a*", "**a**", "***a***", "_a_", "__a__", "snake_case_name",
  "5 * 3 and 2 * 4", "a * b*", "2*3*4", r"---(\*a\*)---", r"---(C:\Users)---", "m^2^",
  "10^\u22124^", "10^-4^", "x^ab^", "x^a b^", "CO~2~", "NO~x~", "~~gone~~", "*m^2^*", "^*2*^",
  "1.2 &times; 10<sup>-4</sup>", "&infin;", "&#8722;3", "R&D", "*1*<!-- -->*2*",
  "[3]{.smallcaps}", "[1990]{.weft-literal why='a year'}", "as shown [@smith2020]", "[a](http://x)", "[1]",
  "`code`", "`` a`b ``", "$x^2$", "costs $5 and $10", "- a\n- b", "a\\\nb",
  "<<weft: failed claim, chunk fig-a>>"
)

test_that("T2 C3: ansi_strip() of the ANSI rendering is the plain rendering, names included", {
  e3_ansi_on()
  inputs <- unique(c(e3_reader_inputs, vapply(e3_rows, `[[`, "", 1)))
  for (m in inputs) {
    w <- weft(c(nm = m))
    ansi <- format(w, target = "ansi")
    expect_identical(unname(cli::ansi_strip(ansi)), unname(format(w)), label = m)  # ansi_strip() drops names
    expect_identical(names(ansi), "nm", label = m)
  }
})

test_that("T2 C3: the same holds for a vector with an NA element", {
  e3_ansi_on()
  w <- weft(c(a = "*x* m^2^", b = NA, c = "**y**"))
  ansi <- format(w, target = "ansi")
  expect_identical(unname(cli::ansi_strip(ansi)), unname(format(w)))  # ansi_strip() drops names
})

# ---- T3: when styles are written (C5) ----------------------------------------------------------

test_that("T3 C5: cli.num_colors = 1 gives the plain text", {
  w <- weft("a *b*")
  withr::local_options(cli.num_colors = 1L)
  expect_identical(format(w, target = "ansi"), format(w))
})

test_that("T3 C5: NO_COLOR gives the plain text, with no ESC", {
  w <- weft("a *b*")
  withr::local_options(cli.num_colors = NULL, crayon.enabled = NULL, knitr.in.progress = NULL)
  withr::local_envvar(NO_COLOR = "1", R_CLI_NUM_COLORS = NA)
  out <- format(w, target = "ansi")
  expect_identical(out, format(w))
  expect_false(grepl(e3_ESC, out, fixed = TRUE))
})

test_that("T3 C5: a knit in progress gives the plain text", {
  w <- weft("a *b*")
  withr::local_options(cli.num_colors = NULL, crayon.enabled = NULL, knitr.in.progress = TRUE)
  withr::local_envvar(NO_COLOR = NA, R_CLI_NUM_COLORS = NA)
  expect_identical(format(w, target = "ansi"), format(w))
})

test_that("T3 C5: R_CLI_NUM_COLORS = 256 turns styles on", {
  w <- weft("a *b*")
  withr::local_options(cli.num_colors = NULL, crayon.enabled = NULL, knitr.in.progress = NULL)
  withr::local_envvar(NO_COLOR = NA, R_CLI_NUM_COLORS = "256")
  expect_identical(unname(format(w, target = "ansi")), "a \u001b[3mb\u001b[23m")
})

test_that("T3 C5: crayon.enabled = FALSE gives the plain text", {
  w <- weft("a *b*")
  withr::local_options(cli.num_colors = NULL, crayon.enabled = FALSE, knitr.in.progress = NULL)
  withr::local_envvar(NO_COLOR = NA, R_CLI_NUM_COLORS = NA)
  expect_identical(format(w, target = "ansi"), format(w))
})

# ---- T4: format() and as.character() stay plain (C6) -------------------------------------------

test_that("T4 C6: format(), as.character() and format(target = 'plain') hold no ESC with styles on", {
  e3_ansi_on()
  w <- weft(c("a *b* **c**", "x^*ab*^"))
  expect_false(any(grepl(e3_ESC, format(w), fixed = TRUE)))
  expect_false(any(grepl(e3_ESC, as.character(w), fixed = TRUE)))
  expect_false(any(grepl(e3_ESC, format(w, target = "plain"), fixed = TRUE)))
})

test_that("T4 C6: format(target = 'ansi') keeps names and writes NA as 'NA'", {
  e3_ansi_on()
  w <- weft(c(p = "a *b*", q = NA))
  out <- format(w, target = "ansi")
  expect_identical(names(out), c("p", "q"))
  expect_identical(out[["p"]], "a \u001b[3mb\u001b[23m")
  expect_identical(out[["q"]], "NA")
})

# ---- T5: print() (C7) --------------------------------------------------------------------------

test_that("T5 C7: print() writes each element on its own line, styled when stdout() has colours", {
  e3_ansi_on()
  out <- capture.output(print(weft(c("a *b*", "c"))))
  expect_identical(out, c("a \u001b[3mb\u001b[23m", "c"))
  expect_output(print(weft(c("a *b*", "c"))), "a \u001b[3mb\u001b[23m\nc", fixed = TRUE)
})

test_that("T5 C7: with cli.num_colors = 1 the lines are plain", {
  withr::local_options(cli.num_colors = 1L)
  out <- capture.output(print(weft(c("a *b*", "c"))))
  expect_identical(out, c("a b", "c"))
})

test_that("T5 C7: print() shows no names", {
  e3_ansi_on()
  out <- capture.output(print(weft(c(x = "a"))))
  expect_identical(out, "a")
})

test_that("T5 C7: print() writes NA as NA", {
  e3_ansi_on()
  out <- capture.output(print(weft(c("a", NA))))
  expect_identical(out, c("a", "NA"))
})

test_that("T5 C7: a length-0 object prints <weft[0]>", {
  e3_ansi_on()
  expect_output(print(weft(character())), "<weft[0]>", fixed = TRUE)
  withr::local_options(cli.num_colors = 1L)
  expect_output(print(weft(character())), "<weft[0]>", fixed = TRUE)
})

test_that("T5 C7: print() returns its argument invisibly", {
  e3_ansi_on()
  w <- weft("a *b*")
  out <- NULL
  capture.output(out <- withVisible(print(w)))
  expect_false(out$visible)
  expect_identical(out$value, w)
})

# ---- T6: target errors (C6, C12) ---------------------------------------------------------------

test_that("T6 C6: an unknown target is a weft_construct_error with the new text", {
  w <- weft("a")
  e <- tryCatch(format(w, target = "rtf"), error = function(e) e)
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e),
    "`target` must be \"plain\", \"markdown\", \"ansi\", \"html\" or \"marquee\"; got \"rtf\".", fixed = TRUE)
  e <- tryCatch(format(w, target = 1), error = function(e) e)
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e),
    "`target` must be \"plain\", \"markdown\", \"ansi\", \"html\" or \"marquee\"; got something else.", fixed = TRUE)
})

test_that("T6 C12: fmt_em() does not take target = 'ansi' (E1's FT3 text, unchanged)", {
  e <- tryCatch(fmt_em("x", target = "ansi"), error = function(e) e)
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e),
    "`target` must be \"markdown\", \"tex\", \"plain\", \"html\" or \"marquee\"; got \"ansi\".", fixed = TRUE)
})

# ---- T7: joined and changed elements (C4) ------------------------------------------------------

test_that("T7 C4: an element joined in by c() is its plain text, unstyled", {
  e3_ansi_on()
  x <- c(weft("*a*"), "*b* m^2^")
  out <- format(x, target = "ansi")
  expect_identical(out[[2]], "*b* m^2^")
  expect_identical(out[[1]], "\u001b[3ma\u001b[23m")
})

test_that("T7 C4: an element set by [<- is its plain text, unstyled", {
  e3_ansi_on()
  y <- weft("*abc*")
  y[1] <- "*z*"
  expect_identical(unname(format(y, target = "ansi")), "*z*")
})

test_that("T7 C4: an element changed by a function that kept the attributes is plain, unstyled", {
  e3_ansi_on()
  z <- weft("*abc*")
  z <- substr(z, 1, 2)
  out <- unname(format(z, target = "ansi"))
  expect_identical(out, "ab")
  expect_false(grepl(e3_ESC, out, fixed = TRUE))
})

test_that("T7 C4: an NA element is 'NA', unstyled", {
  e3_ansi_on()
  expect_identical(format(weft(c("a", NA)), target = "ansi")[[2]], "NA")
})
