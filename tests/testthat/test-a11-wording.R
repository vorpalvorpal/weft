# A11: the class and key checks are made twice, by the scanner (R/scan.R, block_errors()) and by the
# formatter at render (R/format.R, apply_formatters()). The owner's ruling: the render-time text is the
# scanner's text. The inventory is dev/design-a11.md.
#
# Each case is one mistake that both sides detect. `src` is the construct as written; `want` is the adopted
# (scanner) text; `value`, `classes` and `keys` drive apply_formatters() the way a call does. Part (a) pins
# the scanner's text (it passes today); part (b) pins the render-time text and its condition class (the
# class passes today, the text fails where the two differ).

a11_scan_error <- function(src) {
  r <- weft:::scan_text(src)
  r$error[!is.na(r$error)]
}

a11_render_error <- function(value, classes, keys = list()) {
  tryCatch({
    suppressWarnings(weft:::apply_formatters(value, classes, keys))
    NULL
  }, error = function(e) e)
}

a11_m <- function() units::set_units(3, "m")

a11_cases <- list(
  list(rule = "1.4.2 number group", src = "`r x`{.num .pct}",
       want = "Two classes from one group in one block: .num .pct (rule 1.4.2).",
       value = 1, classes = c(".num", ".pct"), cls = "weft_construct_error"),
  list(rule = "1.4.2 wording group", src = "`r x`{.word .count}",
       want = "Two classes from one group in one block: .word .count (rule 1.4.2).",
       value = 3, classes = c(".word", ".count"), cls = "weft_construct_error"),
  list(rule = "1.4.2 collapse group", src = "`r x`{.and .or}",
       want = "Two classes from one group in one block: .and .or (rule 1.4.2).",
       value = c("a", "b"), classes = c(".and", ".or"), cls = "weft_construct_error"),
  list(rule = "1.4.2 unit group", src = "`r x`{.uname .usym}",
       want = "Two unit classes in one block: .uname .usym (rule 1.4.2).",
       value = a11_m(), classes = c(".uname", ".usym"), cls = "weft_construct_error"),
  list(rule = "1.4.7 digits with sigfig", src = "`r x`{.num digits=\"2\" sigfig=\"3\"}",
       want = "`digits` with `sigfig` is an error (rule 1.4.7).",
       value = 1, classes = ".num", keys = list(digits = "2", sigfig = "3"), cls = "weft_construct_error"),
  list(rule = "1.4.7 digits on .date", src = "`r x`{.date digits=\"2\"}",
       want = "`digits` and `sigfig` do not apply to `.date` (rule 1.4.7).",
       value = as.Date("2024-06-03"), classes = ".date", keys = list(digits = "2"),
       cls = "weft_construct_error"),
  list(rule = "1.4.7 sigfig on .date", src = "`r x`{.date sigfig=\"2\"}",
       want = "`digits` and `sigfig` do not apply to `.date` (rule 1.4.7).",
       value = as.Date("2024-06-03"), classes = ".date", keys = list(sigfig = "2"),
       cls = "weft_construct_error"),
  list(rule = "1.4.17 sigfig on .p", src = "`r x`{.p sigfig=\"2\"}",
       want = "`sigfig` does not apply to `.p`; use `digits` (rule 1.4.17).",
       value = 0.03, classes = ".p", keys = list(sigfig = "2"), cls = "weft_construct_error"),
  list(rule = "1.4.17 digits out of range on .p", src = "`r x`{.p digits=\"9\"}",
       want = "`digits` on `.p` must be a whole number from 1 to 6 (got `9`) (rule 1.4.17).",
       value = 0.03, classes = ".p", keys = list(digits = "9"), cls = "weft_construct_error"),
  list(rule = "1.4.17 label without .p", src = "`r x`{.num label=\"q\"}",
       want = "`label` applies to `.p` only (rule 1.4.17).",
       value = 1, classes = ".num", keys = list(label = "q"), cls = "weft_construct_error"),
  list(rule = "1.4.21 .plus with .sci", src = "`r x`{.plus .sci}",
       want = paste0("`.plus` cannot go with `.sci`: it signs a number that `.num` or `.pct` ",
                     "prints (rule 1.4.21)."),
       value = 1, classes = c(".plus", ".sci"), cls = "weft_construct_error"),
  list(rule = "1.4.19 .usym with a spelled number", src = "`r x`{.usym .word}",
       want = paste0("The unit class `.usym` with `.word` is an error: a spelled number takes the ",
                     "unit's name (rule 1.4.19)."),
       value = a11_m(), classes = c(".usym", ".word"), cls = "weft_construct_error"),
  list(rule = "1.4.14 none with .range", src = "`r c(1, 2)`{.range none=\"x\"}",
       want = "The key `none` does not apply to `.range`: a range has two ends (stage 1h).",
       value = c(1, 2), classes = ".range", keys = list(none = "x"), cls = "weft_construct_error"),
  list(rule = "1.4.14 none empty", src = "`r x`{.and none=\"\"}",
       want = "The key `none` is empty; give the text to print for an empty value (stage 1h).",
       value = c("a", "b"), classes = ".and", keys = list(none = ""), cls = "weft_construct_error"),
  list(rule = "4.4.23 ladder with a repeated rung", src = "`r x`{.num unit=\"m|m\"}",
       want = "`unit = m|m`: `m` is on the ladder twice (rule 4.4.23).",
       value = a11_m(), classes = ".num", keys = list(unit = "m|m"), cls = "weft_construct_error")
)

test_that("A11: the scanner's text for each mistake both sides detect is the adopted text (pin)", {
  for (cs in a11_cases) {
    expect_identical(a11_scan_error(cs$src), cs$want, label = cs$rule)
  }
})

test_that("A11: the render-time message for each of those mistakes is the scanner's text", {
  for (cs in a11_cases) {
    e <- a11_render_error(cs$value, cs$classes, cs$keys %||% list())
    expect_s3_class(e, cs$cls)
    expect_identical(conditionMessage(e), cs$want, label = cs$rule)
  }
})
