# Package Q (dev/design-quoting.md), T8: the lints read what the scanner reads (C4): the construct lint
# gives the new M1 text, named-unpublished reads names and `file=` in any quoting, and the cite-key
# fallback reads a cite value in any form of a broken block. The gate's E18 is in _gate/edits.R.
# ASCII only.

QL_M1_IF <- "A `\\` in the value of `if` that does not escape `\"`, `'` or `|` (rule 1.2.3). Bind the expression to a name in a chunk and use the name."

test_that("T8, M1: a .Rmd with a backslash that escapes nothing has one construct finding at its line with the M1 text", {
  x <- lint_one(c("Intro.", "", "More.", "", "[a | b]{if=\"a\\db\"}", "", "End."), rules = "construct", ext = "Rmd")
  expect_identical(nrow(x), 1L)
  expect_identical(x$rule, "construct")
  expect_identical(x$line, 5L)
  expect_identical(x$message, QL_M1_IF)
})

test_that("T8, C4: named-unpublished names the name in a single-quoted if, not the string literal inside it", {
  body <- c("The depth is `v0`{.num} metres.", "", r"{The level [a | b]{if='flag_x == "a"'} again.}")
  x <- w6d_find(w6d_doc(body, w6d_py("v0 = 12")), "named-unpublished")
  expect_identical(w6d_msgs(x), W6D_E70("flag_x"))
})

test_that("T8, C4: a weft-values block's file= in single quotes is read, so its names count as published", {
  body <- c("The `k`{.num} here.", "", "````{.weft-values file='vals.json'}", "````")
  has <- list("vals.json" = "{\"weft\":1,\"values\":{\"k\":{\"t\":\"float\",\"v\":\"1.5\"}}}")
  x <- w6d_find(w6d_doc(body), "named-unpublished", files = has)
  expect_identical(nrow(x), 0L)
  lacks <- list("vals.json" = "{\"weft\":1,\"values\":{\"w\":{\"t\":\"float\",\"v\":\"1.5\"}}}")
  y <- w6d_find(w6d_doc(body), "named-unpublished", files = lacks)
  expect_identical(nrow(y), 1L)
})

test_that("T8, C4: a bare file= value of a weft-values block is read", {
  body <- c("The `k`{.num} here.", "", "````{.weft-values file=vals.json}", "````")
  has <- list("vals.json" = "{\"weft\":1,\"values\":{\"k\":{\"t\":\"float\",\"v\":\"1.5\"}}}")
  expect_identical(nrow(w6d_find(w6d_doc(body), "named-unpublished", files = has)), 0L)
})

test_that("T8, C4: the cite-key fallback reads the cite value of a broken block", {
  bibs <- list("refs.bib" = F3D_BIBTEX, "refs.json" = F3D_CSLJSON, "refs.yaml" = F3D_CSLYAML)
  front <- "bibliography: [refs.bib, refs.json, refs.yaml]"
  body <- c("Prose.", "", r"{A [0.5 m]{cite=@nokey2020 title="a"b"} depth.}")
  files <- c(list("doc.qmd" = f3d_doc(body, front)), bibs)
  x <- f3d_run(files, "cite-key")
  expect_texts(x, "cite-key", "nokey2020")
})
