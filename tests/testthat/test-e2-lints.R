# Package E2 (dev/design-e2.md), T11: the lints named-unpublished (ST5) and string-markup (ST6, rule 5.12.3), and the
# engine rule's unchanged answers (ST2). Static: no Pandoc, Python or Julia is needed.

NU_E2_BODY <- "The depth is `zz`{.num} metres."

nu_rmd <- function(chunks = character(), front = "title: t", name = "a.Rmd", ...) {
  w6d_find(w6d_doc(NU_E2_BODY, chunks, front), "named-unpublished", name = name, ...)
}

test_that("T11 ST5: a knitr .Rmd: the knitr message; a chunk that sets the name silences it", {
  x <- nu_rmd()
  expect_identical(nrow(x), 1L)
  expect_identical(x$message, W6D_E70("zz", knitr = TRUE))
  expect_identical(nrow(nu_rmd(w6d_r("zz <- 1"))), 0L)
})

test_that("T11 ST5: a jupyter .qmd gets the filter's message", {
  x <- w6d_find(w6d_doc(NU_E2_BODY), "named-unpublished")
  expect_identical(x$message, W6D_E70("zz"))
})

test_that("T11 ST5: names_from python in a knitr document gets the filter's message", {
  x <- nu_rmd(weft_yml = "names_from: python")
  expect_identical(x$message, W6D_E70("zz"))
})

test_that("T11 ST5: the hint has no gate sentence and names the language publishers", {
  x <- w6d_find(w6d_doc(NU_E2_BODY), "named-unpublished")
  expect_identical(x$hint, W6D_E70_HINT)
  expect_false(grepl("governor", x$hint, fixed = TRUE))
  expect_false(grepl("weft_put", x$hint, fixed = TRUE))
  expect_false(grepl("weft_put", nu_rmd()$hint, fixed = TRUE))
})

# ---- string-markup ----------------------------------------------------------------------------------

sm <- function(code, front = "title: t", name = "a.Rmd", opts = character(), engine = "r", ...) {
  chunk <- w6d_chunk(engine, code, opts)
  w6d_find(w6d_doc("Intro.", chunk, front), "string-markup", name = name, ...)
}

test_that("T11 ST6: lint_rules() lists string-markup, tier 2, rule 5.12.3, scope file", {
  r <- as.data.frame(unclass(lint_rules()), stringsAsFactors = FALSE)
  row <- r[apply(r, 1, function(z) "string-markup" %in% z), , drop = FALSE]
  expect_identical(nrow(row), 1L)
  expect_identical(as.integer(row$tier), 2L)
  expect_true("5.12.3" %in% unlist(row))
  expect_true("file" %in% unlist(row))
})

test_that("T11 ST6: a string holding a named value, given to cat(), is one tier-2 finding at the string", {
  code <- "cat(\"We sampled `n`{.num} sites.\\n\")"
  x <- sm(code)
  expect_identical(nrow(x), 1L)
  expect_identical(x$rule, "string-markup")
  expect_identical(x$tier, 2L)
  expect_identical(x$spec, "5.12.3")
  expect_identical(x$text, "`n`{.num}")
  expect_identical(x$context, "chunk")
  expect_identical(x$line, 8L)
  expect_identical(x$col, 5L)
  expect_identical(x$message,
                   paste0("This string holds weft markup (`n`{.num}) but is not given to weft(), so R does not read its ",
                          "names and the filter has no value for them (rule 5.12.3)."))
  expect_identical(x$hint,
                   paste0("Give the string to weft() and print the object (a chunk that prints a weft object writes its ",
                          "markdown), or cat(format(weft(\"...\"), target = \"markdown\"))."))
})

test_that("T11 ST6: a span with an n, if, sign or list key is a finding too", {
  expect_identical(nrow(sm("cat(\"[a | b]{if='flag'}\")")), 1L)
  expect_identical(nrow(sm("cat(\"[a | b]{n='k'}\")")), 1L)
})

test_that("T11 ST6: strings given to weft(), or without a construct with a name, are no finding", {
  for (code in c("cat(weft::weft(\"`n`{.num}\"))",
                 "cat(format(weft(\"`n`{.num}\"), target = \"markdown\"))",
                 "weft(x = \"`n`{.num}\")",
                 "cat(\"a `n` here\")",
                 "cat(\"[`n`{.num}]{.weft-literal why='x'}\")")) {
    expect_identical(nrow(sm(code)), 0L, label = code)
  }
})

test_that("T11 ST6: not read: a Python chunk, eval: false, names_from python, a jupyter .qmd", {
  expect_identical(nrow(sm("print(\"`n`{.num}\")", engine = "python")), 0L)
  expect_identical(nrow(sm("cat(\"`n`{.num}\")", opts = "eval: false")), 0L)
  expect_identical(nrow(sm("cat(\"`n`{.num}\")", weft_yml = "names_from: python")), 0L)
  expect_identical(nrow(sm("cat(\"`n`{.num}\")", front = "engine: jupyter", name = "a.qmd")), 0L)
})

# T11 ST2 (the engine rule and use_quarto()'s check keep today's answers for a .qmd with an {r} chunk, no engine key and only
# named values) is the control already pinned in test-lint-engine-named.R and test-use-quarto*.R; they are unchanged.
