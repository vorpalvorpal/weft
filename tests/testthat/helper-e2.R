# Package E2 (dev/design-e2.md): helpers shared by test-e2-*.R.

# a knit with Python (k5() skips without it), its values blocks and the filter's plain output
e2_py <- function(lines, ...) {
  res <- k5(lines, ...)
  res$blocks <- b6_blocks(res$text)
  res$filtered <- filter_md(res$text, name = "doc.Rmd", to = "plain")
  res
}

e2_out <- function(res) trimws(res$filtered$output)

# T9 BN11: a name read above the code that sets it
E2_STALE <- function(assign = TRUE) {
  c("Above: `n`{.count}.", "", if (assign) e2_chunk("calc", "n <- 12L"), "Below.")
}
