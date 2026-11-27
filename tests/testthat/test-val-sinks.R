# Self-formatting values, stage 1: the sinks and weft's own formatters.
# Contract: dev/design-self-formatting.md, sections 4.6, 4.7, 8.5, 8.6 (cases 38 to 49, 51 to 60).
# Written before the code. Non-ASCII is written as \u escapes. Helpers: helper-val.R.
# Case 50 is stage 2 and is not here.

VAL_X <- c(1.5, 2.5)
val_two <- function() val_num(VAL_X, digits = 2)          # plain texts "1.50", "2.50"
val_one <- function() val_num(3.14159, digits = 2)        # plain text "3.14"

# ---- 8.5 Sinks -----------------------------------------------------------------------------

test_that("val 38: paste(), paste0(), toString() and sprintf('%s') use the plain text", {
  v <- val_two()
  expect_identical(paste("a", v), c("a 1.50", "a 2.50"))
  expect_identical(paste0(v, "!"), c("1.50!", "2.50!"))
  expect_identical(toString(v), "1.50, 2.50")
  expect_identical(sprintf("%s", v), c("1.50", "2.50"))
})

test_that("val 39: sprintf('%.3f') prints the raw number", {
  expect_identical(sprintf("%.3f", val_num(3.14159, digits = 1)), "3.142")
})

test_that("val 40: glue() uses the plain text and recycles a vector value", {
  skip_if_not_installed("glue")
  v <- val_two()
  expect_identical(as.character(glue::glue("{v} m")), c("1.50 m", "2.50 m"))
})

test_that("val 41: message(), warning() and stop() hold the plain text", {
  v <- val_one()
  m <- tryCatch(message(v), message = identity)
  expect_identical(conditionMessage(m), "3.14\n")
  w <- tryCatch(warning(v), warning = identity)
  expect_identical(conditionMessage(w), "3.14")
  e <- tryCatch(stop(v), error = identity)
  expect_identical(conditionMessage(e), "3.14")
})

test_that("val 42: cat() prints the raw number (R's limit)", {
  expect_identical(capture.output(cat(val_num(3.14159, digits = 1))), "3.14159")
})

test_that("val 43: writeLines(v) errors; writeLines(format(v)) writes the plain text", {
  v <- val_one()
  expect_error(writeLines(v), "can only write character objects", fixed = TRUE)
  expect_identical(capture.output(writeLines(format(v))), "3.14")
})

test_that("val 44: as.graphicsAnnot() is the plain text, the route of every grid text", {
  v <- val_two()
  expect_identical(grDevices::as.graphicsAnnot(v), as.character(v))
  expect_identical(grDevices::as.graphicsAnnot(v), c("1.50", "2.50"))
})

test_that("val 45: a ggplot2 title and geom_text labels draw the plain text", {
  skip_if_not_installed("ggplot2")
  v <- val_num(3.14159, digits = 2)
  p <- ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) +
    ggplot2::geom_point() + ggplot2::labs(title = v)
  g <- ggplot2::ggplotGrob(p)
  labs <- val_grob_labels(g)
  expect_true("3.14" %in% labs)
  df <- data.frame(x = 1:2, y = 1:2)
  df$lab <- val_two()
  p2 <- ggplot2::ggplot(df, ggplot2::aes(x, y, label = lab)) + ggplot2::geom_text()
  lg <- ggplot2::layer_grob(p2, 1)[[1]]
  expect_identical(as.character(lg$label), c("1.50", "2.50"))
})

test_that("val 46: format() of a data frame and its print show the plain text", {
  df <- data.frame(x = val_two())
  expect_identical(as.character(format(df)$x), c("1.50", "2.50"))
  out <- capture.output(print(df))
  expect_true(any(grepl("1.50", out, fixed = TRUE)))
  expect_true(any(grepl("2.50", out, fixed = TRUE)))
})

test_that("val 47: kable() shows the plain texts right-aligned, and kable's digits does not change them", {
  df <- data.frame(x = val_num(c(1.5, 22.25), digits = 2))
  k <- knitr::kable(df, format = "pipe")
  expect_true(any(grepl("1.50", k, fixed = TRUE)))
  expect_true(any(grepl("22.25", k, fixed = TRUE)))
  expect_match(k[2], "-:", fixed = TRUE)
  k0 <- knitr::kable(df, format = "pipe", digits = 0)
  expect_identical(as.character(k0), as.character(k))
})

test_that("val 48: format(v, target = 'ansi') equals format(v)", {
  v <- val_two()
  expect_identical(format(v, target = "ansi"), format(v))
})

test_that("val 49: format(v, target = 'docx') is the construct error", {
  e <- val_err(format(val_two(), target = "docx"))
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e), "`target` must be \"plain\", \"markdown\", \"tex\", \"ansi\", \"html\" or \"marquee\"; got", fixed = TRUE)
  expect_match(conditionMessage(e), "docx", fixed = TRUE)
})

test_that("val 51: print() writes the header naming .num and digits=1, then the text with its name", {
  v <- val_num(c(a = 1.25), digits = 1)
  out <- capture.output(r <- print(v))
  expect_identical(out[1], "<weft_val .num digits=1>")
  want <- capture.output(print(c(a = val_plain(fmt_num, 1.25, digits = 1)), quote = FALSE))
  expect_identical(out[-1], want)
  expect_identical(r, v)
  # visible check: print() returns the value invisibly
  expect_false(withVisible(print(v))$visible)
})

test_that("val 52: cli::format_inline() holds the plain text, with and without .val", {
  skip_if_not_installed("cli")
  withr::local_options(cli.num_colors = 1)
  v <- val_one()
  expect_identical(cli::ansi_strip(cli::format_inline("{v}")), "3.14")
  expect_identical(cli::ansi_strip(cli::format_inline("{.val {v}}")), "3.14")
  expect_identical(as.character(cli::cli_format(v)), "3.14")
})

test_that("val 53: knit_print(v, inline = TRUE) is the markdown joined by ', '; val_sci(1e-4) gives the markdown form", {
  v <- val_two()
  expect_identical(as.character(knitr::knit_print(v, inline = TRUE)), "1.50, 2.50")
  s <- val_sci(1e-4)
  want_md <- val_md(fmt_sci, 1e-4)
  want_pl <- val_plain(fmt_sci, 1e-4)
  expect_false(identical(want_md, want_pl))          # control: the two forms differ for a power of ten
  expect_identical(as.character(knitr::knit_print(s, inline = TRUE)), want_md)
  expect_false(identical(as.character(knitr::knit_print(s, inline = TRUE)), want_pl))
  v2 <- val_num(c(1.5, 2.5, 3.5), digits = 1)
  expect_identical(paste(as.character(knitr::knit_print(v2)), collapse = "\n"), "1.5\n2.5\n3.5")
})

# ---- 8.6 Meeting weft's formatters --------------------------------------------------------

test_that("val 54: fmt_num() takes the spec's digits; a digits written replaces them; another class drops the spec", {
  v <- val_num(3.14159, digits = 2)
  expect_identical(val_txt(fmt_num(v)), "3.14")
  expect_identical(val_txt(fmt_num(v, digits = 0)), "3")
  expect_identical(val_txt(fmt_pct(val_num(0.5, digits = 3))), "50%")
})

test_that("val 55: fmt_word() and fmt_and() take the number underneath and the spec", {
  expect_identical(val_txt(fmt_word(val_num(3))), "three")
  expect_identical(val_txt(fmt_and(val_num(c(1.23, 4.56), digits = 1))), "1.2 and 4.6")
})

test_that("val 56: fmt_num() of a value whose digits were given signals no zero warning", {
  v <- val_num(0.04, digits = 1)
  r <- val_warnings(fmt_num(v))
  expect_length(r$zero, 0L)
  expect_identical(val_txt(r$value), "0.0")
})

test_that("val 57: weft() strings give the spec's text in both forms; a different class drops the spec", {
  v <- val_num(3.14159, digits = 2)
  for (src in c("`r v`", "`r v`{.num}", "`v`{.num}", "`v`{.val}")) {
    w <- weft(src)
    expect_identical(unname(as.character(w)), "3.14", info = src)
    expect_identical(unname(format(w, target = "markdown")), "3.14", info = src)
  }
  w <- weft("`r v`{.pct}")
  expect_identical(unname(as.character(w)), val_plain(fmt_pct, 3.14159))
  expect_identical(unname(format(w, target = "markdown")), val_md(fmt_pct, 3.14159))
})

test_that("val 58: an n governor follows the number as printed", {
  v <- val_num(1.04, digits = 2)
  expect_identical(unname(as.character(weft("[one site | # sites]{n=v}"))), "1.04 sites")
  # ruling 27 Nov: the default digits print 1.0, and a plain 1.04 gives "1.0 sites" too (design case 58 corrected)
  v <- val_num(1.04)
  expect_identical(unname(as.character(weft("[one site | # sites]{n=v}"))), "1.0 sites")
})

test_that("val 59: a claim in a weft() string judges the number and stops with weft_claim_failed", {
  v <- val_num(61)
  expect_error(weft("`r claim(v, . < 50)`"), class = "weft_claim_failed")
  v <- val_num(40)
  expect_no_error(weft("`r claim(v, . < 50)`"))
})

test_that("val 60: a phrase function uses the number underneath", {
  expect_identical(val_txt(ci(val_num(2.123), 1, 3)), val_txt(ci(2.123, 1, 3)))
})

# ---- Controls: behaviour the design says is unchanged or relies on, which already holds ------

test_that("val control: a formatter's text compares as a string, and loses to a number (the hazard the feature closes)", {
  expect_false(isTRUE(as.character(fmt_num(10)) > 9))
})

test_that("val control: fmt_num() and fmt_pct() of plain numbers, and a quantity, print as the design's tables say", {
  expect_identical(val_txt(fmt_pct(0.5)), "50%")
  expect_identical(val_txt(fmt_num(3.14159, digits = 2)), "3.14")
  expect_identical(val_txt(fmt_num(u(5, m), target = "plain")), paste0("5", VAL_NB, "m"))
  expect_identical(val_txt(fmt_sci(0)), "0")
})

test_that("val control: R's own limits that the design pins, shown on a Date (a classed double)", {
  d <- as.Date("2026-11-27")
  expect_false(identical(capture.output(cat(d)), format(d)))          # cat() prints the day count
  expect_error(writeLines(d), "can only write character objects", fixed = TRUE)
  expect_false(inherits(c(3, d), "Date"))                              # c() dispatches on the first argument
  expect_identical(class(c(d, 3)), "Date")
})

test_that("val control: an n governor with a plain 1.04 prints the number with its default digits", {
  v <- 1.04
  expect_identical(unname(as.character(weft("[one site | # sites]{n=v}"))), "1.0 sites")
})

test_that("val control: weft_values_write() refuses a units quantity (E44), the model for E46", {
  p <- file.path(withr::local_tempdir(), "v.json")
  e <- val_err(weft::weft_values_write(p, d = units::set_units(1, "m")))
  expect_s3_class(e, "weft_values_error")
  expect_match(conditionMessage(e), "is a units quantity; named values carry no units", fixed = TRUE)
})

test_that("val control: a weft_year plus an integer is a weft_year, and a plain claim passes and fails as the design assumes", {
  y <- read_dict(a2_fixture())$method_change
  expect_s3_class(y + 1L, "weft_year")
  expect_identical(claim(10, . > 9), 10)
  expect_error(claim(10, . < 9), class = "weft_claim_failed")
})
