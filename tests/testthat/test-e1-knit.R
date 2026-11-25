# Package E1 (dev/design-e1.md): weft() in knitr, captions and ggplot2 (T8, T9; WS7, WS16, WS17).
# Rmarkdown knits use render_rmd(..., format = "knit", in_process = TRUE).

e1k_head <- c("---", "title: \"t\"", "---", "")
e1k_setup <- c("```{r setup, include=FALSE}", "weft::weft_setup()", "k <- 3", "```", "")

e1k_knit <- function(body, ...) {
  render_rmd(c(e1k_head, e1k_setup, body), setup = FALSE, format = "knit", in_process = TRUE, ...)
}

# ---- T8: knitr ---------------------------------------------------------------------------------

# design ambiguity: the design's inline example nests backticks inside inline R (`r weft::weft('... `r 2`{.num} ...')`),
# which knitr's inline pattern cannot read; the construct here is an n span over the variable k instead.
test_that("T8 WS7: inline R in prose writes the markdown of the object", {
  res <- e1k_knit("Text `r weft::weft(\"*a* [one | # sites]{n='k'} m^2^\")` end.")
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "Text *a* 3 sites m^2^ end.", fixed = TRUE)
})

test_that("T8 WS7: a vector in inline R is joined by ', ' as stock knitr joins one", {
  res <- e1k_knit("Both `r weft::weft(c('*a*', 'b'))` here.")
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "Both *a*, b here.", fixed = TRUE)
})

test_that("T8 WS7: a chunk whose value is a weft object writes markdown, as asis (no ## output prefix)", {
  res <- e1k_knit(c("```{r a, echo=FALSE}", "weft::weft('*a* m^2^')", "```", ""))
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "*a* m^2^", fixed = TRUE)
  expect_false(grepl("##", res$md, fixed = TRUE))
})

test_that("T8 WS7: a chunk printing a vector writes its elements as paragraphs", {
  res <- e1k_knit(c("```{r a, echo=FALSE}", "weft::weft(c('*a*', 'b'))", "```", ""))
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "*a*\n\nb", fixed = TRUE)
})

test_that("T8 WS17: cat() of a weft object in a results='asis' chunk writes the plain text", {
  res <- e1k_knit(c("```{r a, results='asis', echo=FALSE}",
                    "cat('Got', weft::weft('*a* m^2^'), 'here.\\n')", "```", ""))
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "Got a m² here.", fixed = TRUE)
  expect_false(grepl("*a*", res$md, fixed = TRUE))
})

test_that("T8 WS17: to write markdown from cat(), format(target = 'markdown') is used", {
  res <- e1k_knit(c("```{r a, results='asis', echo=FALSE}",
                    "cat('Got', format(weft::weft('*a* m^2^'), target = 'markdown'), 'here.\\n')", "```", ""))
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "Got *a* m^2^ here.", fixed = TRUE)
})

test_that("T8 WS16: fig.cap = weft(...) in a chunk header gives a caption holding the markdown", {
  res <- e1k_knit(c("```{r fig-a, echo=FALSE, fig.cap = weft::weft(\"Depth at *[a site | # sites]{n='k'}*\")}",
                    "plot(1)", "```", ""))
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "Depth at *3 sites*", fixed = TRUE)
})

test_that("T8 WS16: fig.alt = weft(...) gets the plain text, fig.cap the markdown", {
  res <- e1k_knit(c(
    "```{r fig-b, echo=FALSE, fig.cap = weft::weft('Cap *x*'), fig.alt = weft::weft('Alt *y* m^2^')}",
    "plot(1)", "```", ""))
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "Cap *x*", fixed = TRUE)
  expect_match(res$md, "Alt y m²", fixed = TRUE)
  expect_false(grepl("Alt *y*", res$md, fixed = TRUE))
})

test_that("T8 WS16: a computed caption that is a plain character string is still resolved as markup (2.3)", {
  res <- e1k_knit(c("```{r fig-c, echo=FALSE, fig.cap = 'Depth at [a site | # sites]{n=\"k\"}'}",
                    "plot(1)", "```", ""))
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "Depth at 3 sites", fixed = TRUE)
})

test_that("T8 WS17: kable(caption = weft(...)) gets Table: and the plain text", {
  res <- e1k_knit(c("```{r tbl, echo=FALSE}",
    "knitr::kable(data.frame(x = 1), caption = weft::weft(\"Sites: *[a site | # sites]{n='k'}*\"))",
    "```", ""))
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "Table: Sites: 3 sites", fixed = TRUE)
  expect_false(grepl("*3 sites*", res$md, fixed = TRUE))
})

# design ambiguity: a `# ` inside a YAML plain scalar starts a comment, so the Quarto caption uses an if span, not an n span.
test_that("T8 WS16 (Quarto): #| fig-cap: !expr weft::weft(...) gives a caption with the emphasis", {
  skip_if_no_quarto()
  lines <- c("---", "title: \"t\"", "engine: knitr", "format: html", "---", "",
             "```{r setup, include=FALSE}", "weft::weft_setup()", "k <- 3", "```", "",
             "```{r fig-q, echo=FALSE}",
             "#| fig-cap: !expr weft::weft(\"Depth at *[one | many]{if='k > 5'}*\")",
             "plot(1)", "```", "")
  r <- qmd_html(lines)
  expect_false(r$failed, label = r$message)
  expect_match(r$html, "<em>many</em>", fixed = TRUE)
})

# ---- T9: ggplot2 -------------------------------------------------------------------------------

test_that("T9 WS17: a ggplot2 title that is a weft object draws its plain text", {
  skip_if_not_installed("ggplot2", "4.0.0")
  w <- weft("Rate *r* of 10^-4^ m^2^")
  p <- ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) +
    ggplot2::geom_point() + ggplot2::labs(title = w)
  g <- ggplot2::ggplotGrob(p)
  grob <- g$grobs[[which(g$layout$name == "title")]]
  lab <- NULL
  find_label <- function(x) {
    if (!is.null(x$label)) lab <<- x$label
    for (ch in x$children) find_label(ch)
    for (gr in x$grobs) find_label(gr)
  }
  find_label(grob)
  expect_identical(as.character(lab), as.character(w))
  expect_false(grepl("^", as.character(lab), fixed = TRUE))
  expect_false(grepl("*", as.character(lab), fixed = TRUE))
})

test_that("T9 FT: a scale whose labels are fmt_num(target = 'plain') builds without error", {
  skip_if_not_installed("ggplot2", "4.0.0")
  p <- ggplot2::ggplot(data.frame(x = c(1, 2), y = c(0.0001, 0.0002)), ggplot2::aes(x, y)) +
    ggplot2::geom_point() +
    ggplot2::scale_y_continuous(labels = function(b) fmt_num(b, target = "plain"))
  expect_no_error(ggplot2::ggplotGrob(p))
})
