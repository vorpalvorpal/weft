# Fix round for package E3 (dev/review-e3.md): H1, H2, H3, H5, H7. Escape written as \u001b only.

er_ESC <- "\u001b"
er_RED_OPEN <- "\u001b[1m\u001b[31m"
er_on <- function(env = parent.frame()) {
  withr::local_options(cli.num_colors = 256L, .local_envir = env)
}

test_that("H1: a forced default colour count (RStudio style) does not put escapes in a sink", {
  withr::local_options(cli.default_num_colors = 256L, cli.num_colors = NULL)
  withr::local_envvar(R_CLI_NUM_COLORS = NA, NO_COLOR = NA)
  out <- capture.output(print(weft("a *b*")))
  expect_false(any(grepl(er_ESC, out, fixed = TRUE)))
})

test_that("H1: cli.num_colors forces colour even into a sink", {
  withr::local_options(cli.num_colors = 256L)
  out <- capture.output(print(weft("a *b*")))
  expect_true(any(grepl("\u001b[3m", out, fixed = TRUE)))
})

test_that("H2: a weft text with a line break keeps its styles under {.val}", {
  er_on()
  w <- weft("a\n*b*")
  out <- cli::format_inline("{.val {w}}")
  expect_true(grepl("\u001b[3mb\u001b[23m", out, fixed = TRUE))
})

test_that("H3: a failure marker in joined text is still drawn bold red", {
  er_on()
  x <- c(weft("x"), "see <<weft: no value, line 4>>")
  out <- format(x[2], target = "ansi")
  expect_true(grepl(paste0(er_RED_OPEN, "<<weft: no value, line 4>>\u001b[39m\u001b[22m"),
                    out, fixed = TRUE))
})

test_that("H5: a failure marker inside math is styled, and the strip still equals the plain form", {
  er_on()
  w <- weft("$\\text{<<weft: no value, line 2>>}$")
  ansi <- format(w, target = "ansi")
  expect_true(grepl(er_RED_OPEN, ansi, fixed = TRUE))
  expect_identical(unname(cli::ansi_strip(ansi)), unname(format(w)))
})

test_that("H5: a failure marker broken over a line is styled", {
  er_on()
  # ambiguity: whether the break survives in the plain form (newline or space) is not fixed; only
  # the styling and the strip-equals-plain rule are tested.
  w <- weft("see <<weft: no value,\nline 4>> here")
  ansi <- format(w, target = "ansi")
  expect_true(grepl(er_RED_OPEN, ansi, fixed = TRUE))
  expect_identical(unname(cli::ansi_strip(ansi)), unname(format(w)))
})

test_that("H7: an empty emphasis writes no empty style pair", {
  er_on()
  out <- format(weft("*<!-- -->*"), target = "ansi")
  expect_false(grepl("\u001b[3m\u001b[23m", out, fixed = TRUE))
})
