# Package E3 (dev/design-e3.md): cli (C8 to C11; T8 to T11).

e3c_ESC <- "\033"
e3c_ansi_on <- function(env = parent.frame()) {
  withr::local_options(cli.num_colors = 256L, .local_envir = env)
}

# ---- T8: cli_format() (C9) ---------------------------------------------------------------------

test_that("T8 C9: the method is registered", {
  expect_false(is.null(utils::getS3method("cli_format", "weft", optional = TRUE)))
})

test_that("T8 C9: cli_format() with styles on is a bare character vector of the ANSI renderings", {
  e3c_ansi_on()
  w <- weft(c(p = "a *b*", q = "c"))
  out <- cli::cli_format(w)
  expect_identical(class(out), "character")
  expect_identical(attributes(out), list(names = c("p", "q")))
  expect_identical(out[["p"]], "a \033[3mb\033[23m")
  expect_identical(out[["q"]], "c")
})

test_that("T8 C9: cli_format() with cli.num_colors = 1 is the plain text, unquoted", {
  withr::local_options(cli.num_colors = 1L)
  w <- weft(c(p = "a *b*", q = "c"))
  expect_identical(cli::cli_format(w), c(p = "a b", q = "c"))
})

test_that("T8 C9: cli_format() writes NA as 'NA' and ignores style", {
  e3c_ansi_on()
  out <- cli::cli_format(weft(c("a", NA)), style = list(color = "red"))
  expect_identical(unname(out), c("a", "NA"))
})

test_that("T8 C9: {.val {w}} draws the emphasis, unquoted", {
  e3c_ansi_on()
  out <- cli::format_inline("Got {.val {weft('a *b*')}}.")
  expect_true(grepl("\033[3mb\033[23m", out, fixed = TRUE))
  expect_identical(cli::ansi_strip(out), "Got a b.")
})

test_that("T8 C9: {.val {w}} with colours off collapses a vector as cli does", {
  withr::local_options(cli.num_colors = 1L)
  w <- weft(c(p = "a *b*", q = "c"))
  expect_identical(cli::format_inline("Got {.val {w}}."), "Got a b and c.")
})

# ---- T9: a plain substitution (C10) ------------------------------------------------------------

test_that("T9 C10: {w} gives plain text, with no ESC from weft", {
  e3c_ansi_on()
  w <- weft("a *b*")
  out <- cli::format_inline("Got {w}.")
  expect_identical(cli::ansi_strip(out), "Got a b.")
  expect_false(grepl("\033[3m", out, fixed = TRUE))
})

# ---- T10: braces (C11) -------------------------------------------------------------------------

test_that("T10 C11: braces in a weft value are text, never evaluated", {
  w <- weft("Index $x_{no_such_object_e3}$ here")
  expect_identical(cli::format_inline("{w}"), "Index $x_{no_such_object_e3}$ here")
  expect_identical(cli::ansi_strip(cli::format_inline("{.val {w}}")),
    "Index $x_{no_such_object_e3}$ here")
})

test_that("T10 C11: the text given as the template itself is read by cli's glue (documented hazard)", {
  w <- weft("Index $x_{no_such_object_e3}$ here")
  expect_error(cli::format_inline(as.character(w)))
})

# ---- T11: sinks unchanged (C8) -----------------------------------------------------------------

test_that("T11 C8: paste0(), sprintf(), cat() and message() give plain text with styles on", {
  e3c_ansi_on()
  w <- weft("a *b* m^2^")
  expect_false(grepl(e3c_ESC, paste0(w), fixed = TRUE))
  expect_false(grepl(e3c_ESC, sprintf("%s", w), fixed = TRUE))
  expect_false(any(grepl(e3c_ESC, capture.output(cat(w)), fixed = TRUE)))
  cnd <- tryCatch(message(w), message = function(m) m)
  expect_false(grepl(e3c_ESC, conditionMessage(cnd), fixed = TRUE))
  expect_identical(paste0(w), "a b m\u00b2")
})

test_that("T11 C8: format(target = 'markdown') is E1's markdown with styles on", {
  e3c_ansi_on()
  w <- weft("a *b* m^2^")
  expect_identical(unname(format(w, target = "markdown")), "a *b* m^2^")
})
