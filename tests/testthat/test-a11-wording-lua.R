# A11, Lua side: for every mistake that the scanner (R/scan.R, block_errors()) and the filter
# (inst/quarto/weft.lua, check_construct()) both detect on a NAMED value, the filter writes the scanner's
# text. `want` is taken from scan_text() at run time, so the two cannot drift; `pin` is the literal, so that
# a change to both is noticed. The inventory is dev/design-a11.md. ASCII only.

a11l_block <- function() {
  carrier(
    i3 = fr_int("3"), f1 = fr_float("3.14159"), p5 = fr_float("0.05"), dt = fr_date("2024-06-03"),
    lab = fr_list_str(c("a", "b"))
  )
}

a11l_cases <- list(
  two_number = list(src = "`i3`{.num .pct}",
    pin = "Two classes from one group in one block: .num .pct (rule 1.4.2)."),
  two_wording = list(src = "`i3`{.word .count}",
    pin = "Two classes from one group in one block: .word .count (rule 1.4.2)."),
  two_collapse = list(src = "`lab`{.and .or}",
    pin = "Two classes from one group in one block: .and .or (rule 1.4.2)."),
  two_unit = list(src = "`i3`{.uname .usym}",
    pin = "Two unit classes in one block: .uname .usym (rule 1.4.2)."),
  digits_sigfig = list(src = "`f1`{.num digits=\"2\" sigfig=\"3\"}",
    pin = "`digits` with `sigfig` is an error (rule 1.4.7)."),
  date_digits = list(src = "`dt`{.date digits=\"2\"}",
    pin = "`digits` and `sigfig` do not apply to `.date` (rule 1.4.7)."),
  date_sigfig = list(src = "`dt`{.date sigfig=\"2\"}",
    pin = "`digits` and `sigfig` do not apply to `.date` (rule 1.4.7)."),
  p_sigfig = list(src = "`p5`{.p sigfig=\"2\"}",
    pin = "`sigfig` does not apply to `.p`; use `digits` (rule 1.4.17)."),
  p_digits = list(src = "`p5`{.p digits=\"9\"}",
    pin = "`digits` on `.p` must be a whole number from 1 to 6 (got `9`) (rule 1.4.17).",
    want = function() conditionMessage(tryCatch(weft:::p_digits_value("9"), error = identity))),
  label_no_p = list(src = "`f1`{.num label=\"q\"}",
    pin = "`label` applies to `.p` only (rule 1.4.17)."),
  plus_sci = list(src = "`f1`{.plus .sci}",
    pin = "`.plus` cannot go with `.sci`: it signs a number that `.num` or `.pct` prints (rule 1.4.21)."),
  none_range = list(src = "`lab`{.range none=\"x\"}",
    pin = "The key `none` does not apply to `.range`: a range has two ends (rule 1.4.14)."),
  none_empty = list(src = "`lab`{.and none=\"\"}",
    pin = "The key `none` is empty; give the text to print for an empty value (rule 1.4.14)."),
  none_no_collapse = list(src = "`i3`{.num none=\"x\"}",
    pin = paste0("The key `none` needs a collapse class (`.and`, `.or`, `.pairs`, `.ul`, `.ol`, `.dl`) ",
                 "on the value (rule 1.4.14)."))
)

a11l_want <- function(x) {
  if (is.function(x$want)) return(x$want())
  r <- weft:::scan_text(paste0("A ", x$src, " z."))
  e <- r$error[!is.na(r$error)]
  expect_length(e, 1L)
  e[[1L]]
}

test_that("A11: the filter writes the scanner's text for each mistake on a named value", {
  skip_if_no_lua_pandoc()
  cases <- vapply(a11l_cases, function(x) paste0("A ", x$src, " z."), "")
  res <- filter_cases(cases, list(a11l_block()), draft = TRUE)
  err <- fm_lines(res$stderr)
  for (nm in names(a11l_cases)) {
    want <- a11l_want(a11l_cases[[nm]])
    expect_identical(want, a11l_cases[[nm]]$pin, label = paste("R text of", nm))
    hit <- grep(paste0("^  doc.md:", res$line[[nm]], " "), err)
    expect_true(length(hit) > 0L, label = paste("stderr names the line of", nm))
    body <- paste(err[hit[1L]:min(length(err), hit[1L] + 1L)], collapse = "\n")
    expect_true(grepl(want, body, fixed = TRUE), label = paste("filter text of", nm, ":", body))
  }
})
