# Self-formatting values under the html and marquee targets (3.12.5 after the 27 Nov ruling):
# format(v, target = "html" / "marquee") gives what the matching fmt_*() call gives with that target.
# ASCII only: non-ASCII is written as \u escapes.

vr_val <- list(
  num = list(v = function(...) val_num(1234.5, digits = 1, ...), f = function(...) fmt_num(1234.5, digits = 1, ...)),
  pct = list(v = function(...) val_pct(0.123, ...), f = function(...) fmt_pct(0.123, ...)),
  sci = list(v = function(...) val_sci(1.2e-4, digits = 1, ...), f = function(...) fmt_sci(1.2e-4, digits = 1, ...)),
  sci_pos = list(v = function(...) val_sci(1234567, ...), f = function(...) fmt_sci(1234567, ...)),
  p = list(v = function(...) val_p(0.0001, ...), f = function(...) fmt_p(0.0001, ...)),
  unit = list(v = function(...) val_num(u(5, m)), f = function(...) fmt_num(u(5, m), ...)),
  unit_sup = list(v = function(...) val_num(u(5, m^2)), f = function(...) fmt_num(u(5, m^2), ...))
)

vr_text <- function(x) as.character(unclass(x))

test_that("VR1: each constructor under target = html matches the fmt_* html form", {
  for (nm in names(vr_val)) {
    r <- vr_val[[nm]]
    got <- format(r$v(), target = "html")
    want <- r$f(target = "html")
    expect_identical(vr_text(got), vr_text(want), info = nm)
  }
})

test_that("VR2: each constructor under target = marquee matches the fmt_* marquee form", {
  for (nm in names(vr_val)) {
    r <- vr_val[[nm]]
    got <- format(r$v(), target = "marquee")
    want <- r$f(target = "marquee")
    expect_identical(vr_text(got), vr_text(want), info = nm)
  }
})

test_that("VR3: a negative exponent is a superscript in html and a span in marquee", {
  v <- val_sci(1.2e-4, digits = 1)
  expect_match(vr_text(format(v, target = "html")), "<sup>\u22124</sup>", fixed = TRUE)
  expect_match(vr_text(format(v, target = "marquee")), "{.sup \u22124}", fixed = TRUE)
})

test_that("VR4: a unit with a power is a superscript in html", {
  expect_match(vr_text(format(val_num(u(5, m^2)), target = "html")), "m<sup>2</sup>", fixed = TRUE)
  expect_match(vr_text(format(val_num(u(5, m^2)), target = "marquee")), "m{.sup 2}", fixed = TRUE)
})

test_that("VR5: the html form carries class c('html', 'character') and attr html = TRUE", {
  x <- format(val_sci(1.2e-4, digits = 1), target = "html")
  expect_identical(class(x), c("html", "character"))
  expect_true(attr(x, "html"))
  w <- format(weft("a"), target = "html")
  expect_identical(class(x), class(w))
  expect_identical(attr(x, "html"), attr(w, "html"))
})

test_that("VR6: names are kept and NA gives 'NA' under both targets", {
  for (tg in c("html", "marquee")) {
    x <- format(val_num(c(a = 1.5, b = NA), digits = 1), target = tg)
    expect_identical(names(x), c("a", "b"), info = tg)
    expect_identical(vr_text(x)[2], "NA", info = tg)
    expect_length(x, 2)
  }
})

test_that("VR7 (control): plain, markdown, tex and ansi forms are unchanged", {
  v <- val_sci(1.2e-4, digits = 1)
  expect_identical(format(v), as.character(v))
  expect_identical(format(v, target = "plain"), format(v))
  expect_identical(format(v, target = "ansi"), format(v))
  expect_identical(vr_text(format(v, target = "markdown")), vr_text(fmt_sci(1.2e-4, digits = 1, target = "markdown")))
  expect_identical(vr_text(format(v, target = "tex")), vr_text(fmt_sci(1.2e-4, digits = 1, target = "tex")))
})

test_that("VR8: a bad target names html and marquee after ansi, in the 3.12.5 order", {
  e <- tryCatch(format(val_sci(1.2e-4), target = "docx"), error = function(e) e)
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e),
    "\"plain\", \"markdown\", \"tex\", \"ansi\", \"html\" or \"marquee\"", fixed = TRUE)
  expect_match(conditionMessage(e), "docx", fixed = TRUE)
})

test_that("VR9: a ggtext label built from format(v, target = 'html') draws", {
  skip_on_cran()
  skip_if_not_installed("ggplot2", "4.0.0")
  skip_if_not_installed("ggtext")
  grDevices::pdf(NULL)
  withr::defer(grDevices::dev.off())
  lab <- format(val_sci(1.2e-4, digits = 1), target = "html")
  expect_identical(vr_text(lab), vr_text(fmt_sci(1.2e-4, digits = 1, target = "html")))
  expect_match(vr_text(lab), "10<sup>\u22124</sup>", fixed = TRUE)
  d <- data.frame(x = 1:3, y = c(1, 4, 9))
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point() +
    ggplot2::labs(title = lab) + ggplot2::theme(plot.title = ggtext::element_markdown())
  expect_no_error(ggplot2::ggplotGrob(p))
})
