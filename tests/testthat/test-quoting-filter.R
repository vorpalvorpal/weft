# Package Q (dev/design-quoting.md), T6 (the filter half) and T7: the Lua filter reads a condition with
# string literals in either quote (C6, D2), finds a span's line by its governor key and the value as
# Pandoc read it (C8), and shows a construct double-quoted with \ and " escaped (D13). The tables of T6
# are in _conformance/grammar.tsv (rows of kind cond) and run in test-conformance-grammar.R. Through plain
# Pandoc, helper-filter.R. ASCII only; markup is in raw strings.
#
# READINGS: in T7 each case is one paragraph and the marker of an unpublished name is the "no value"
# marker of test-filter-lines.R (draft mode). The entry of the report is found by its line, as
# test-filter-report.R does.

CEQ <- "<<weft: construct error, line {L}>>"
NVQ <- "<<weft: no value, line {L}>>"

q_carrier <- function() carrier(tier = fr_str("sev"), s = fr_str("north"), a = fr_bool(TRUE), f = fr_bool(FALSE))

# ---- T6: through the filter -------------------------------------------------------------------------------

test_that("T6, C6, D2: a condition with a double-quoted string literal chooses the arm, in every spelling of the attribute", {
  cases <- c(
    sq = r"{A [severe | mild]{if='tier == "sev"'} z.}",
    dq_esc = r"{A [severe | mild]{if="tier == \"sev\""} z.}",
    dq_sq = r"{A [severe | mild]{if="tier == 'sev'"} z.}",
    other = r"{A [severe | mild]{if='tier == "other"'} z.}",
    comma = r"{A [yes | no]{if='tier != "a,b"'} z.}",
    comma_two = r"{A [yes | no]{if='tier == "sev", s == "north"'} z.}",
    apostrophe = r"{A [yes | no]{if="tier != \"it's\""} z.}",
    flipped = r"{A [yes | no]{if='"sev" == tier'} z.}"
  )
  res <- filter_cases(cases, list(q_carrier()))
  expect_identical(res$status, 0L)
  expect_cases(res, c(
    sq = "A severe z.", dq_esc = "A severe z.", dq_sq = "A severe z.", other = "A mild z.",
    comma = "A yes z.", comma_two = "A yes z.", apostrophe = "A yes z.", flipped = "A yes z."))
  expect_false(grepl("weft", res$stderr, fixed = TRUE))
})

test_that("T6, E4: two double-quoted literals compared is a construct error", {
  cases <- c(dq = r"{A [yes | no]{if='"a" == "a"'} z.}")
  res <- filter_cases(cases, list(q_carrier()), draft = TRUE)
  expect_cases(res, c(dq = paste0("A ", CEQ, " z.")))
  expect_true(grepl(fm_msg$E4("\"a\" == \"a\""), res$stderr, fixed = TRUE))
})

test_that("T6, E3: an unclosed double-quoted literal is a construct error", {
  cases <- c(open = r"{A [yes | no]{if='tier == "a'} z.}")
  res <- filter_cases(cases, list(q_carrier()), draft = TRUE)
  expect_cases(res, c(open = paste0("A ", CEQ, " z.")))
  expect_true(grepl(fm_msg$E3("tier == \"a"), res$stderr, fixed = TRUE))
})

# ---- T7: lines --------------------------------------------------------------------------------------------

test_that("T7, C8: one decoded value in three spellings is found in order, each marker names its own line", {
  cases <- c(
    A = r"{A [x | y]{if='nothere == "a"'}.}",
    B = r"{B [x | y]{if="nothere == \"a\""}.}",
    C = r"{C [x | y]{if='nothere == "a"'}.}"
  )
  res <- filter_cases(cases, list(q_carrier()), draft = TRUE)
  expect_cases(res, c(A = paste0("A ", NVQ, "."), B = paste0("B ", NVQ, "."), C = paste0("C ", NVQ, ".")))
  expect_true(all(diff(res$line) > 0))
})

test_that("T7, C8: a bare n value, and a value with an escaped bar, have their line", {
  cases <- c(
    D = r"{D [x | y]{n=nothere}.}",
    E = r"{E [x | y]{if="nothere == 'a\|b'"}.}"
  )
  res <- filter_cases(cases, list(q_carrier()), draft = TRUE)
  expect_cases(res, c(D = paste0("D ", NVQ, "."), E = paste0("E ", NVQ, ".")))
})

test_that("T7, C8: a span found nowhere does not move the search on for the others (the cursor is per key and value)", {
  cases <- c(
    one = "One [x | y]{if=\"nothere > 1\"}.",
    two = "Two [x | y]{if='nothere > 1'}.",
    three = "Three [x | y]{if=nothere>1}."
  )
  res <- filter_cases(cases, list(q_carrier()), draft = TRUE)
  expect_cases(res, c(one = paste0("One ", NVQ, "."), two = paste0("Two ", NVQ, "."),
                      three = paste0("Three ", NVQ, ".")))
})

test_that("T7, D13: the report shows a span and a named value double-quoted with the quote escaped", {
  cases <- c(
    A = r"{A [x | y]{if='nothere == "a"'}.}",
    N = r"{N `nothere`{.num title='say "hi"'}.}"
  )
  res <- filter_cases(cases, list(q_carrier()), draft = TRUE)
  L <- res$line
  e <- fm_entry(res$stderr, sprintf("^  doc\\.md:%d  ", L[["A"]]))
  expect_true(e$found)
  expect_true(grepl(r"{[x | y]{if="nothere == \"a\""}}", e$head, fixed = TRUE), label = e$head)
  e <- fm_entry(res$stderr, sprintf("^  doc\\.md:%d  ", L[["N"]]))
  expect_true(e$found)
  expect_true(grepl(r"{`nothere`{.num title="say \"hi\""}}", e$head, fixed = TRUE), label = e$head)
})

test_that("T7, C8: a blank decision written decision='' on a .weft-literal span is reported with its line (single quotes)", {
  # READING: the design's example is decision=' ', but Pandoc reads no span for a value with a leading
  # space ({k=' x'} is text, 1.12.6 and 18), so the filter never sees it; an empty value is the blank one
  # Pandoc reads in single quotes.
  cases <- c(span = r"{Z [0.45]{.weft-literal why="w" decision=''} z.}")
  res <- filter_cases(cases, list(q_carrier()), draft = TRUE)
  expect_cases(res, c(span = paste0("Z ", CEQ, " z.")))
  expect_true(grepl(dp_msg$E50, res$stderr, fixed = TRUE))
})
