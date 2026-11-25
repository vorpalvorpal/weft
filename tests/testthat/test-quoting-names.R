# Package Q (dev/design-quoting.md), T5 (C4, C7): the names a source names (rule 2.13.11), read from raw
# text in any form of 1.2.2 and with the escapes of 1.2.3, outside string literals in either quote. The R
# extractor (weft:::values_source_names), the Python one (weft._source_names), and a knit. ASCII only.
#
# READINGS: the Python function is called as weft._source_names(path) and its result is taken as a
# collection of strings (a set or a list); the test sorts it. The R and Python results are compared as
# sets, the document being the same.

NAMES_DOC <- c(
  "We saw `v0`{.num}.",
  "[a | b]{n='n_sq'}",
  "[a | b]{n=n_bare}",
  "[a | b]{if='lvl == \"str_dq\"'}",
  "[a | b]{if=\"lvl2 == \\\"str_esc\\\"\"}",
  "[a | b]{if=\"lvl3 == 'str_sq'\"}",
  "[a | b]{sign='d_sq'}",
  "[a | b]{list=l_bare}",
  "[a | b]{n = \"spaced\"}"
)
NAMES_WANT <- c("n_sq", "n_bare", "lvl", "lvl2", "lvl3", "d_sq", "l_bare")
NAMES_NOT <- c("str_dq", "str_esc", "str_sq", "spaced")

test_that("T5, C7, R: names are read from single-quoted, double-quoted and bare values, and string literals of both kinds are dropped", {
  p <- b6_write_doc(NAMES_DOC, name = "doc.qmd")
  got <- weft:::values_source_names(p)
  expect_true(all(NAMES_WANT %in% got), label = paste("got:", paste(sort(got), collapse = ", ")))
  expect_false(any(NAMES_NOT %in% got))
  expect_true("v0" %in% got)
})

test_that("T5, C7, R: a string literal holding the other quote does not leak a name; the strip is one left-to-right pass", {
  p <- b6_write_doc(c(
    r"{[a | b]{if='s1 == "it\'s"'}}",
    r"{[a | b]{if="s2 == \"x\", s3 == 'y'"}}",
    r"{[a | b]{if='"it\'s" == s4'}}"
  ), name = "doc.qmd")
  got <- weft:::values_source_names(p)
  expect_true(all(c("s1", "s2", "s3", "s4") %in% got))
  expect_false(any(c("it", "x", "y", "s") %in% got))
})

test_that("T5, C7, R: an escaped bar and other escapes are read before the names are taken", {
  p <- b6_write_doc(c("[a | b]{if=\"nm_a \\|\\| nm_b\"}", "[a | b]{n=\"nm_c\"}"), name = "doc.qmd")
  got <- weft:::values_source_names(p)
  expect_true(all(c("nm_a", "nm_b", "nm_c") %in% got))
})

test_that("T5, C7, Python: weft._source_names gives the same set as the R extractor", {
  py <- py_exe6k()
  p <- b6_write_doc(NAMES_DOC, name = "doc.qmd")
  dir <- withr::local_tempdir()
  script <- file.path(dir, "run.py")
  writeLines(c(
    "import sys, json",
    "import weft",
    "print(json.dumps(sorted(weft._source_names(sys.argv[1]))))"), script)
  out <- suppressWarnings(system2(py, c(shQuote(script), shQuote(p)),
                                  env = paste0("PYTHONPATH=", py_lib6k()), stdout = TRUE, stderr = FALSE))
  expect_gte(length(out), 1L)
  got <- jsonlite::fromJSON(out[length(out)])
  expect_true(all(NAMES_WANT %in% got), label = paste("got:", paste(sort(got), collapse = ", ")))
  expect_false(any(NAMES_NOT %in% got))
  expect_setequal(got, weft:::values_source_names(p))
})

test_that("T5, C7, knit: a name governed by a single-quoted n is published when the chunk binds it", {
  res <- b6_knit(c(
    "```{r calc, include=FALSE}", "kq <- 3L", "other_q <- 2L", "unused_q <- 1", "```", "",
    "Found [one | many]{n='kq'} sites, of `other_q`{.num}."
  ))
  b6_expect_knitted(res)
  published <- unlist(b6_block_names(res$blocks))
  expect_true("kq" %in% published)
  expect_false("unused_q" %in% published)
})
