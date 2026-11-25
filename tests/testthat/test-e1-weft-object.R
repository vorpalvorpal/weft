# Package E1 (dev/design-e1.md): weft() and its object. T1 (the function), T2 (evaluated at the
# call), T3 (environment), T6 (vector semantics), T7 (sinks). Rules WS1 to WS11.
# Non-ASCII is written as \u escapes. Failing tests are meant to fail because weft() does not
# exist yet, not because of the test itself.

e1_plain <- function(x) as.character(x)
e1_md <- function(x) unname(format(x, target = "markdown"))

# ---- T1: the function (WS1) ------------------------------------------------------------------

test_that("T1 WS1: weft is exported and weft_str is not", {
  expect_true("weft" %in% getNamespaceExports("weft"))
  expect_false("weft_str" %in% getNamespaceExports("weft"))
})

test_that("T1 WS6: the result has class c('weft', 'character')", {
  w <- weft("A *plain* string")
  expect_identical(class(w), c("weft", "character"))
  expect_true(is.character(w))
})

test_that("T1 WS1: length and names follow x, NA stays NA", {
  w <- weft(c(a = "one", b = "two *2*", c = "three"))
  expect_length(w, 3L)
  expect_identical(names(w), c("a", "b", "c"))
  w2 <- weft(c("x", NA, "z"))
  expect_length(w2, 3L)
  expect_identical(is.na(w2), c(FALSE, TRUE, FALSE))
  expect_identical(e1_plain(w2), c("x", NA, "z"))
  # NA is never a failure, and is NA in the markdown form too
  expect_identical(is.na(attr(w2, "markdown")), c(FALSE, TRUE, FALSE))
})

test_that("T1 WS1: a factor is read as its labels; a zero-length vector gives a zero-length object", {
  f <- factor(c("alpha *a*", "beta"))
  w <- weft(f)
  expect_s3_class(w, "weft")
  expect_identical(e1_plain(w), c("alpha a", "beta"))
  z <- weft(character())
  expect_s3_class(z, "weft")
  expect_length(z, 0L)
})

test_that("T1 WS1: anything but a character vector is a weft_construct_error with the stated text", {
  msg <- "`weft()` takes a character vector of markup."
  for (bad in list(1, 2L, list("a"), NULL, TRUE)) {
    e <- tryCatch(weft(bad), error = function(e) e)
    expect_s3_class(e, "weft_construct_error")
    expect_match(conditionMessage(e), msg, fixed = TRUE)
  }
})

test_that("T1 WS1: .envir that is not an environment is a weft_construct_error with the stated text", {
  e <- tryCatch(weft("a", .envir = 1), error = function(e) e)
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e), "`.envir` must be an environment.", fixed = TRUE)
})

test_that("T1 WS1: a weft object given as x is returned unchanged", {
  w <- weft("a *b*")
  expect_identical(weft(w), w)
  expect_identical(weft(weft("a *b*")), weft("a *b*"))
})

test_that("T1 WS6: the content is the plain text and the attribute markdown holds the markdown", {
  w <- weft(c("a *b* m^2^", "plain"))
  expect_identical(unclass(w)[1:2], c("a b m²", "plain"))
  expect_identical(attr(w, "markdown"), c("a *b* m^2^", "plain"))
})

# ---- T2: evaluated at the call (WS2) ---------------------------------------------------------

test_that("T2 WS2: titles made in a loop each keep their own iteration's values", {
  titles <- lapply(c(2, 5, 9), function(k) weft("Sites: `r k`{.num}"))
  expect_identical(vapply(titles, e1_plain, ""), c("Sites: 2", "Sites: 5", "Sites: 9"))
  expect_identical(vapply(titles, e1_md, ""), c("Sites: 2", "Sites: 5", "Sites: 9"))
  # the same through a for loop sharing one variable
  out <- list()
  for (v in c(3, 4)) out[[length(out) + 1L]] <- weft("N is `r v`{.num}")
  expect_identical(vapply(out, e1_plain, ""), c("N is 3", "N is 4"))
})

test_that("T2 WS2: changing a variable after the call changes nothing", {
  v <- 1
  w <- weft("Value `r v`{.num}")
  v <- 2
  expect_identical(e1_plain(w), "Value 1")
  expect_identical(e1_md(w), "Value 1")
  k <- 3
  w2 <- weft("[a site | # sites]{n='k'}")
  k <- 1
  expect_identical(e1_plain(w2), "3 sites")
})

# ---- T3: environment (WS3) -------------------------------------------------------------------

test_that("T3 WS2: a value local to a calling function is read", {
  f <- function() {
    only_here_e1 <- 4
    weft("[a site | # sites]{n='only_here_e1'}")
  }
  expect_identical(e1_plain(f()), "4 sites")
  expect_error(weft("[a site | # sites]{n='only_here_e1'}"), class = "weft_no_value")   # control
})

test_that("T3 WS1: an explicit .envir is read", {
  e <- list2env(list(e1_depth = 12.5))
  expect_identical(e1_plain(weft("Depth `r e1_depth`{.num} m", .envir = e)), "Depth 12.5 m")
  expect_error(weft("Depth `r e1_depth`{.num} m"), class = "weft_no_value")   # control
})

test_that("T3 WS3: the inline functions are found without weft attached", {
  env <- list2env(list(k = 2), parent = baseenv())
  w <- local(weft::weft("[one | # sites]{n='k'}"), envir = env)
  expect_identical(e1_plain(w), "2 sites")
  w2 <- local(weft::weft("`r claim(k, . > 0)`{.num}"), envir = env)
  expect_identical(e1_plain(w2), "2")
  # an fmt_*() is found too
  w3 <- local(weft::weft("`r fmt_num(k)`"), envir = env)
  expect_identical(e1_plain(w3), "2")
})

test_that("T3 WS3: a function of the same name that .envir sees wins", {
  env <- list2env(list(plural = function(...) "MINE"), parent = baseenv())
  expect_identical(e1_plain(weft("Is `r plural(1, 'x')`", .envir = env)), "Is MINE")
})

# ---- T6: vector semantics (WS8 to WS10) ------------------------------------------------------

test_that("T6 WS8: [, [[ and rev() keep both forms", {
  w <- weft(c("a *b*", "c m^2^", "d"))
  for (x in list(w[2], w[[2]])) {
    expect_s3_class(x, "weft")
    expect_identical(e1_plain(x), "c m²")
    expect_identical(e1_md(x), "c m^2^")
  }
  r <- rev(w)
  expect_s3_class(r, "weft")
  expect_identical(e1_plain(r), c("d", "c m²", "a b"))
  expect_identical(e1_md(r), c("d", "c m^2^", "a *b*"))
})

test_that("T6 WS8: rep(), unique() and sort() give a bare character vector", {
  w <- weft(c("a *b*", "a *b*"))
  for (x in list(rep(w, 2), unique(w), sort(w))) {
    expect_false(inherits(x, "weft"))
    expect_type(x, "character")
  }
})

test_that("T6 WS8: unclass() is the plain text with the attribute markdown", {
  w <- weft("a *b*")
  u <- unclass(w)
  expect_identical(as.vector(u), "a b")
  expect_identical(attr(u, "markdown"), "a *b*")
})

test_that("T6 WS9: c() of weft objects keeps both forms", {
  w1 <- weft("a *b*")
  w2 <- weft("c m^2^")
  x <- c(w1, w2)
  expect_s3_class(x, "weft")
  expect_identical(e1_plain(x), c("a b", "c m²"))
  expect_identical(e1_md(x), c("a *b*", "c m^2^"))
})

test_that("T6 WS9: a character element joins as text as it is: plain and markdown are both the string", {
  w <- weft("a *b*")
  x <- c(w, "m^2^")
  expect_s3_class(x, "weft")
  expect_identical(e1_plain(x), c("a b", "m^2^"))
  expect_identical(e1_md(x), c("a *b*", "m^2^"))
  # NULL is allowed
  expect_identical(e1_plain(c(w, NULL)), "a b")
})

test_that("T6 WS9: c() with anything else is a weft_construct_error naming the class", {
  w <- weft("a")
  e <- tryCatch(c(w, 1), error = function(e) e)
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e),
    "A weft text can be combined only with weft texts and character vectors; got a numeric.", fixed = TRUE)
})

test_that("T6 WS9: [<- with a weft value sets both forms; beyond the length fills with NA in both", {
  w <- weft(c("a", "b"))
  w[2] <- weft("*b*")
  expect_identical(e1_plain(w), c("a", "b"))
  expect_identical(e1_md(w), c("a", "*b*"))
  w[4] <- "x"
  expect_length(w, 4L)
  expect_identical(is.na(w), c(FALSE, FALSE, TRUE, FALSE))
  expect_identical(is.na(attr(w, "markdown")), c(FALSE, FALSE, TRUE, FALSE))
  e <- tryCatch({ w[1] <- 1; NULL }, error = function(e) e)
  expect_s3_class(e, "weft_construct_error")
})

test_that("T6 WS10: substr() of an element with emphasis gives the substring in the markdown form", {
  w <- weft("a *b* c")
  s <- substr(w, 1, 1)
  expect_identical(e1_plain(s), "a")
  expect_identical(e1_md(s), "a")
})

test_that("T6 WS8: nchar() counts plain characters", {
  expect_identical(as.integer(nchar(weft("**abc** m^2^"))), 6L)
})

# ---- T7: sinks (WS7, WS8) --------------------------------------------------------------------

test_that("T7 WS8: paste0(), sprintf(), toString() and message() give plain text", {
  w <- weft("*a* m^2^")
  expect_identical(paste0("T: ", w), "T: a m²")
  expect_identical(paste("T:", w), "T: a m²")
  expect_identical(sprintf("%s", w), "a m²")
  expect_identical(toString(w), "a m²")
  expect_message(message(w), "a m²", fixed = TRUE)
})

test_that("T7 WS8: glue::glue() gives plain text", {
  skip_if_not_installed("glue")
  w <- weft("*a* m^2^")
  expect_identical(as.character(glue::glue("{w}")), "a m²")
})

test_that("T7 WS7/WS8: cat() and print() write plain lines", {
  w <- weft(c("*a* m^2^", "second"))
  expect_output(cat(w), "a m² second", fixed = TRUE)
  expect_output(print(w), "a m²", fixed = TRUE)
  out <- capture.output(r <- print(w))
  expect_identical(out, c("a m²", "second"))
  expect_identical(r, w)
  expect_false(any(grepl("*", out, fixed = TRUE)))
})

test_that("T7 WS7: print() writes NA as NA, does not show names, and prints <weft[0]> for length 0", {
  out <- capture.output(print(weft(c(a = "x", b = NA))))
  expect_identical(out, c("x", "NA"))
  expect_output(print(weft(character())), "<weft[0]>", fixed = TRUE)
})

test_that("T7 WS7: as.character() is plain with names and NA kept; format() writes NA as 'NA'", {
  w <- weft(c(a = "x *y*", b = NA))
  ch <- as.character(w)
  expect_false(inherits(ch, "weft"))
  expect_identical(names(ch), c("a", "b"))
  expect_identical(unname(ch), c("x y", NA))
  f <- format(w)
  expect_identical(names(f), c("a", "b"))
  expect_identical(unname(f), c("x y", "NA"))
  expect_identical(unname(format(w, target = "plain")), c("x y", "NA"))
  expect_identical(unname(format(w, target = "markdown")), c("x *y*", "NA"))
  expect_identical(names(format(w, target = "markdown")), c("a", "b"))
})

test_that("T7 WS7: a target other than plain, markdown or ansi is a weft_construct_error", {
  w <- weft("a")
  e <- tryCatch(format(w, target = "tex"), error = function(e) e)
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e), "`target` must be \"plain\", \"markdown\" or \"ansi\"; got \"tex\".", fixed = TRUE)
  e <- tryCatch(format(w, target = 1), error = function(e) e)
  expect_s3_class(e, "weft_construct_error")
  expect_match(conditionMessage(e), "got something else.", fixed = TRUE)
})

test_that("T7 WS7: knit_print() gives the markdown, joined by ', ' inline and by a blank line in a chunk", {
  w <- weft(c("*a* m^2^", "b"))
  inl <- knitr::knit_print(w, inline = TRUE)
  expect_s3_class(inl, "knit_asis")
  expect_identical(as.character(inl), "*a* m^2^, b")
  blk <- knitr::knit_print(w)
  expect_s3_class(blk, "knit_asis")
  expect_identical(as.character(blk), "*a* m^2^\n\nb")
})

test_that("T7 WS8: the base functions that read the content see plain text", {
  w <- weft(c("*a*", "b"))
  expect_identical(w == "a", c(TRUE, FALSE))
  expect_identical(grepl("*", w, fixed = TRUE), c(FALSE, FALSE))
  expect_output(writeLines(w), "a")
})

# ---- WS11: a weft object used as a value contributes its markdown -----------------------------

test_that("WS11: a weft object used as a value inside weft() markup contributes its markdown text", {
  inner <- weft("*b* m^2^")
  w <- weft("Is `r inner`")
  expect_identical(e1_md(w), "Is *b* m^2^")
  expect_identical(e1_plain(w), "Is b m²")
})

test_that("WS11: a weft object passed to a fmt_*() contributes its markdown text", {
  inner <- weft("*b*")
  x <- fmt_and(inner)
  expect_identical(as.character(unclass(x)), "*b*")
})
