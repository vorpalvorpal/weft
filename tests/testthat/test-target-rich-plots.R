# Rich plot text (stage H3 of dev/design-html-target.md): ggtext and marquee draw what the targets write.
# Slow; skipped on CRAN. ggtext needs ggplot2 4.0.0 or later. marquee is not in the main library, so the
# marquee tests skip when it is missing. ASCII only.

rp_plot <- function(title, theme_arg) {
  d <- data.frame(x = 1:3, y = c(1, 4, 9))
  ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point() + ggplot2::labs(title = title) +
    ggplot2::theme(plot.title = theme_arg)
}
rp_build <- function(p) ggplot2::ggplotGrob(p)
rp_device <- function(env = parent.frame()) {
  grDevices::pdf(NULL)
  withr::defer(grDevices::dev.off(), envir = env)
}
rp_need_ggtext <- function() {
  skip_on_cran()
  skip_if_not_installed("ggplot2", "4.0.0")
  skip_if_not_installed("ggtext")
}

test_that("RS1, 3.6.11: ggtext draws the html form of a title with a negative exponent and a unit", {
  rp_need_ggtext()
  rp_device()
  g2_cfg(NULL)
  t <- format(weft("Rate *r* of 10^-4^ m^2^"), target = "html")
  expect_no_error(rp_build(rp_plot(t, ggtext::element_markdown())))
})

test_that("RS1, D91: ggtext draws the html form of a list", {
  rp_need_ggtext()
  rp_device()
  g2_cfg(NULL)
  t <- format(weft("`r c('a', 'b')`{.ul}"), target = "html")
  expect_no_error(rp_build(rp_plot(t, ggtext::element_markdown())))
})

test_that("D91: the markdown form of the same list stops ggtext (this pins the problem)", {
  rp_need_ggtext()
  rp_device()
  g2_cfg(NULL)
  t <- format(weft("`r c('a', 'b')`{.ul}"), target = "markdown")
  expect_error(rp_build(rp_plot(t, ggtext::element_markdown())), "isn't supported yet")
})

test_that("RS1: ggtext scale labels from fmt_sci(target = \"html\") build", {
  rp_need_ggtext()
  rp_device()
  g2_cfg(NULL)
  d <- data.frame(x = 1:3, y = c(1e-4, 2e-4, 3e-4))
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point() +
    ggplot2::scale_y_continuous(labels = function(b) fmt_sci(b, target = "html")) +
    ggplot2::theme(axis.text.y = ggtext::element_markdown())
  expect_no_error(rp_build(p))
})

test_that("RS1, 3.6.11: marquee draws the marquee form of a title", {
  skip_on_cran()
  skip_if_not_installed("ggplot2", "4.0.0")
  skip_if_not_installed("marquee")
  # marquee 1.3.0 builds element_marquee() as an S7 subclass of ggplot2's element_text, and with S7 1.0.0
  # (ggplot2 4.0.4) it errors "`_parent` must be an instance of <ggplot2::element_text>, not <S7_object>".
  # That is in marquee and S7, before any weft code runs, so the test waits for a fixed marquee.
  skip_if(utils::packageVersion("S7") >= "1.0.0" && utils::packageVersion("marquee") <= "1.3.0" &&
            inherits(try(marquee::element_marquee(), silent = TRUE), "try-error"),
          "marquee <= 1.3.0 cannot build element_marquee() with S7 >= 1.0.0 (CI: ggplot2 4.0.4, marquee 1.3.0, S7 1.0.0)")
  rp_device()
  g2_cfg(NULL)
  t <- format(weft("Rate *r* of 10^-4^ m^2^"), target = "marquee")
  expect_no_error(rp_build(rp_plot(t, marquee::element_marquee())))
})

test_that("D86: marquee drops HTML tags, so the html form must not go to it (this pins the problem)", {
  skip_if_not_installed("marquee")
  p <- marquee::marquee_parse("10<sup>4</sup>")
  expect_identical(paste(p$text, collapse = ""), "104")
})
