# Package Q (dev/design-quoting.md), T4: weft_str() end to end and what weft writes back as markup (C5,
# D5, D9), and the M1 construct error as the caller sees it. The Pandoc read-back of the written forms is
# in test-quoting-conformance.R. ASCII only; markup is in raw strings.

# weft_str(), an error shown as the result so that a refusal is a failed expectation, not an aborted test.
# weft_str() evaluates in its caller's environment, so the call is evaluated in the test's own.
ws <- function(x, envir = parent.frame()) {
  tryCatch(eval(bquote(weft::weft_str(.(x))), envir), error = function(e) paste("ERROR:", conditionMessage(e)))
}

test_that("T4, 1.2.3: an if with a string literal chooses the arm, in single-quoted, double-quoted and raw-string forms", {
  tier <- "sev"
  expect_identical(ws("[severe | mild]{if='tier == \"sev\"'}"), "severe")
  expect_identical(ws("[severe | mild]{if=\"tier == \\\"sev\\\"\"}"), "severe")
  expect_identical(ws(r"([severe | mild]{if='tier == "sev"'})"), "severe")
  expect_identical(ws(r"([severe | mild]{if="tier == 'sev'"})"), "severe")
  tier <- "x"
  expect_identical(ws("[severe | mild]{if='tier == \"sev\"'}"), "mild")
  expect_identical(ws("[severe | mild]{if=\"tier == \\\"sev\\\"\"}"), "mild")
  expect_identical(ws(r"([severe | mild]{if='tier == "sev"'})"), "mild")
})

test_that("T4, 1.2.2: a single-quoted and a bare n are read", {
  k <- 3
  expect_identical(ws("Found [a site | # sites]{n='k'}."), "Found 3 sites.")
  expect_identical(ws("Found [a site | # sites]{n=k}."), "Found 3 sites.")
})

test_that("T4, D5, D9: a pass-through value is written double-quoted with \\ , \" and | escaped", {
  expect_identical(ws(r"{`r 1.2`{.num custom-style='Key "figure"'}}"),
                   r"{[1.2]{custom-style="Key \"figure\""}}")
  expect_identical(ws(r"{`r 1.2`{.num title="a\|b"}}"), r"{[1.2]{title="a\|b"}}")
  expect_identical(ws(r"{`r 1.2`{.num title="it's"}}"), r"{[1.2]{title="it's"}}")
})

test_that("T4, D5: a literal span is written without its why, the other keys double-quoted and escaped", {
  expect_identical(ws(r"{[lit]{.weft-literal why='it\'s fine' title='say "hi"'}}"),
                   r"{[lit]{.weft-literal title="say \"hi\""}}")
})

test_that("T4, M1: a backslash that escapes nothing is a weft_construct_error whose message holds M1", {
  cond <- tryCatch(weft::weft_str(r"([a | b]{if="a\db"})"), error = function(e) e)
  expect_s3_class(cond, "weft_construct_error")
  expect_true(grepl("A `\\` in the value of `if` that does not escape `\"`, `'` or `|` (rule 1.2.3).",
                    conditionMessage(cond), fixed = TRUE))
})

test_that("T4, M3: a character reference in a quoted value is a weft_construct_error", {
  cond <- tryCatch(weft::weft_str(r"([a | b]{if="x &amp;&amp; y"})"), error = function(e) e)
  expect_s3_class(cond, "weft_construct_error")
  expect_true(grepl("A character reference, `&amp;`, in the value of `if` (rule 1.2.3)",
                    conditionMessage(cond), fixed = TRUE))
})
