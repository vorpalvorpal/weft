# Self-formatting values (rule 3.12, dev/design-self-formatting.md, stage 1): a number with the
# class `weft_val` put before its own classes, a format (`weft_spec`: the classes and keys a
# formatter would be given) and the texts that format gives it (`weft_shown`: markdown, plain and
# TeX, element by element), made once when the value is made. The internals here are named
# `sv_*()`, so that none of them shares a name with a test helper.

#' Self-formatting values
#'
#' `val_num()`, `val_pct()`, `val_sci()` and `val_p()` return a
#' **self-formatting value** (rule 3.12): the number given, with the class
#' `weft_val` put before its own classes, and a format that prints it as the
#' function of the same name in [fmt_num()] and its siblings would. The value
#' stays a number: it compares, sorts and plots as one. Only the way it turns
#' into text changes, so one statement of the digits serves every sink: prose,
#' a [weft()] string, `paste()`, `glue::glue()`, a plot title, a table and the
#' console.
#'
#' The constructors take the arguments of the formatter of the same name,
#' except `target` and the collapse arguments, and refuse what it refuses with
#' the same error, naming the function called. `x` is a double, an integer, an `integer64`, a
#' [weft_year][weft_year], a `units` quantity (see [u()]) or a self-formatting
#' value, whose number is then given the new format; anything else is a
#' `weft_construct_error`. An element that is `NA`, `NaN`, `Inf` or `-Inf` is
#' kept and not formatted: its text is `NA`, `"NaN"`, `"Inf"` or `"-Inf"`.
#'
#' **The texts are made when the value is made**, under the configuration a
#' formatter would use there (the knit's, or the working directory's
#' `_weft.yml`): the markdown, the plain text read from it (rule 1.4.24) and
#' the TeX form. A value made in one project keeps its texts after `setwd()`.
#' A ladder of units (`unit = "m|km"`) picks one rung for the whole vector,
#' and `v[1]` keeps it. A value made with the default digits that prints a
#' number that is not zero as zero is warned about once, then: a warned check
#' of kind "printed as zero" in a knit, a `weft_zero_warning` outside one.
#' Printing it never warns again.
#'
#' **What it gives.** `as.character()`, `format()`, `paste()`, `toString()`,
#' `sprintf("%s", )`, `glue::glue()`, `message()`, `warning()`, `stop()`,
#' cli's `{v}` and `{.val {v}}`, a ggplot2 title or label, a printed data
#' frame and `knitr::kable()` give the plain text. `format(v, target = )`
#' takes `"plain"` (the default), `"markdown"`, `"tex"`, `"ansi"` (plain),
#' `"html"` or `"marquee"` (what the matching `fmt_*()` call gives); other arguments of `format()` are ignored. `knitr::knit_print()` gives the
#' markdown, joined by ", " inline and one element per line otherwise, so a
#' document with no weft hooks prints the value right in prose. `print()`
#' writes a header naming the format, then the plain texts. Three limits are
#' R's: `cat()` prints the number underneath (as it prints a `Date`),
#' `writeLines()` refuses the value, and a `for` loop reads the numbers; give
#' the first two `format(v)`. `sprintf("%.2f", v)` formats the number, as
#' asked.
#'
#' **Vectors.** `[`, `[[`, `rev()`, `rep()`, `head()`, `tail()`, `sort()`,
#' `unique()` and `as.list()` keep the format and the texts of the elements
#' they keep. `c()` and `[<-` make the texts again for the whole result, under
#' the configuration in force then; numbers given to them take the format.
#' Values whose formats differ, or a value and anything that is not a number,
#' do not combine: a `weft_construct_error`. `c(3, v)` is a plain number,
#' because R dispatches `c()` on its first argument. When vctrs is loaded,
#' `vctrs::vec_c()` and the dplyr verbs follow the same rules, and a value
#' combined with a plain number gives a plain number.
#'
#' **Arithmetic drops the format** (rule 3.12.7): `+`, `*`, `round()`,
#' `sum()` and the rest give the result for the number underneath: a double,
#' or what the class underneath gives (a `units` quantity, a `weft_year`).
#' `min()`, `max()`, `range()`, `mean()` and `median()`, whose result is on
#' the scale of their input, keep the format. A comparison gives a logical,
#' so [claim()] judges the number.
#'
#' **In weft's constructs** (rule 3.12.8) the format is put together with what
#' is written at the use: a key written there replaces the format's key of
#' that name (`digits` and `sigfig` replace each other); a number class
#' written there that differs from the format's replaces it, with all its
#' keys; otherwise the format's class and keys apply. `` `r v` `` in prose
#' prints the markdown, in math its TeX, and `` `v`{.val} `` prints its own
#' format. The ledger records the value only where weft resolves it: making
#' it, converting it to text and printing it record nothing. A self-formatting
#' value is never a named value for the filter: [weft_values_write()] refuses
#' it (E46). Phrase functions such as [ci()] use its number and ignore its
#' format.
#'
#' @param x A number, a quantity, or a self-formatting value.
#' @param digits,sigfig,unit,unit_form,plus,label As for [fmt_num()],
#'   [fmt_pct()], [fmt_sci()] and [fmt_p()].
#' @return A self-formatting value: the number, of class `weft_val` and its
#'   own classes.
#' @examples
#' v <- val_num(3.14159, digits = 2)
#' paste("Mean", v)
#' v > 3
#' format(val_sci(1.2e-4), target = "markdown")
#' @name val
NULL

#' @rdname val
#' @export
val_num <- function(x, digits = NULL, sigfig = NULL, unit = NULL, unit_form = NULL, plus = FALSE) {
  x <- sv_input("val_num", x)
  check_unit_form(unit_form, "val_num")
  check_flag(plus, "plus")
  sv_build(x, sv_spec(c(".num", if (plus) ".plus"), list(digits = digits, sigfig = sigfig, unit = unit),
                      unit_form))
}

#' @rdname val
#' @export
val_pct <- function(x, digits = NULL, sigfig = NULL, unit = NULL, plus = FALSE) {
  x <- sv_input("val_pct", x)
  check_flag(plus, "plus")
  sv_build(x, sv_spec(c(".pct", if (plus) ".plus"), list(digits = digits, sigfig = sigfig, unit = unit)))
}

#' @rdname val
#' @export
val_sci <- function(x, digits = NULL, sigfig = NULL, unit = NULL, unit_form = NULL) {
  x <- sv_input("val_sci", x)
  check_unit_form(unit_form, "val_sci")
  sv_build(x, sv_spec(".sci", list(digits = digits, sigfig = sigfig, unit = unit), unit_form))
}

#' @rdname val
#' @export
val_p <- function(x, digits = NULL, label = NULL) {
  x <- sv_input("val_p", x)
  sv_build(x, sv_spec(".p", list(digits = digits, label = label)))
}

# ---- making a value -------------------------------------------------------------------------------

# The number a constructor was given (3.12.2): a self-formatting value gives its number.
sv_input <- function(fn, x) {
  if (inherits(x, "weft_val")) return(sv_strip(x))
  ok <- inherits(x, c("units", "weft_year", "integer64")) || (is.numeric(x) && !is.object(x))
  if (!ok) {
    construct_error(sprintf("`%s()` takes a number or a quantity; got a %s. To print text, use `weft()`.",
                            fn, class(x)[1L]))
  }
  x
}

# A format: the classes and the keys a formatter is given, and the unit form. The keys that are
# NULL are left out, and a number key is stored as a double, so that two formats are equal when
# they print alike (3.12.6).
sv_spec <- function(classes, keys, unit_form = NULL) {
  keys <- keys[!vapply(keys, is.null, NA)]
  for (k in intersect(names(keys), c("digits", "sigfig"))) {
    if (is.numeric(keys[[k]]) && !inherits(keys[[k]], "integer64")) keys[[k]] <- as.double(keys[[k]])
  }
  list(classes = classes, keys = keys, unit_form = unit_form)
}

# The number underneath a value: its own classes, without the format.
sv_strip <- function(x) {
  if (!inherits(x, "weft_val")) return(x)
  attr(x, "weft_spec") <- NULL
  attr(x, "weft_shown") <- NULL
  cl <- setdiff(oldClass(x), "weft_val")
  class(x) <- if (length(cl)) cl else NULL
  x
}

# The elements that have a number to format: not NA, NaN, Inf or -Inf.
sv_ok <- function(number) {
  if (inherits(number, "integer64")) return(!is.na(number))
  is.finite(as.numeric(unclass(number)))
}

# A value of the number `number` with the format `spec` and the texts `shown`.
sv_restore <- function(number, spec, shown) {
  structure(number, class = c("weft_val", oldClass(number)), weft_spec = spec, weft_shown = shown)
}

# The texts of `shown` at the positions `pos` (NA where a position is out of range).
sv_shown_at <- function(shown, pos) {
  pos <- unname(pos)
  lapply(shown, function(s) if (is.null(s)) NULL else s[pos])
}

# Each element's position, named as the elements are: what `[`, `[[` and `rep()` select.
sv_positions <- function(x) stats::setNames(seq_along(x), names(x))

# The value of `number` formatted by `spec` (3.12.3): the formatter runs for markdown and for TeX,
# under one configuration, and the plain text is the markdown read by PL, as `target = "plain"`
# gives it. The zero check (2.6.11) runs once, on the markdown run. A missing element is not
# formatted; with none to format, the construct errors that need no value still come.
sv_build <- function(number, spec, config = current_config()) {
  force(config)
  bare <- if (inherits(number, "integer64")) rep(NA_real_, length(number)) else as.numeric(unclass(number))
  ok <- sv_ok(number)
  miss <- as.character(ifelse(is.nan(bare), "NaN", ifelse(is.na(bare), NA_character_,
                                                        ifelse(bare > 0, "Inf", "-Inf"))))
  md <- miss
  tex <- miss
  has_tex <- !any(spec$classes %in% names(TEX_NO_FORM))
  run <- function(target, on_zero) {
    r <- apply_formatters(number[ok], spec$classes, spec$keys, config, on_zero = on_zero,
                          unit_form = spec$unit_form, target = target)
    unname(as.character(unclass(r)))
  }
  if (any(ok)) {
    md[ok] <- run("markdown", note_zero)
    if (has_tex) tex[ok] <- run("tex", function(msg) invisible(NULL))
  } else {
    tryCatch(run("markdown", note_zero), weft_no_value = function(e) NULL)
  }
  sv_restore(number, spec, list(markdown = md, plain = plain_text(md), tex = if (has_tex) tex))
}

# ---- a value meeting weft's formatting (3.12.8) -------------------------------------------------

# The value, classes, keys and unit form a formatter works with when it is given a value: the use's
# own, put together with the value's format. `reg` is the configuration's `formatters`.
sv_merge <- function(value, classes, keys, unit_form, reg) {
  spec <- attr(value, "weft_spec")
  value <- sv_strip(value)
  use_num <- c(intersect(classes, NUMBER_CLASSES), intersect(classes, registered_classes(reg, "number")))
  own_num <- intersect(spec$classes, NUMBER_CLASSES)
  if (length(use_num) && !identical(use_num[1L], own_num[1L])) {
    # another number class: the format goes, with all its keys
    return(list(value = value, classes = classes, keys = keys, unit_form = unit_form))
  }
  given <- names(keys)
  # `digits` and `sigfig` are one choice: either written at the use replaces both
  if (any(c("digits", "sigfig") %in% given)) given <- union(given, c("digits", "sigfig"))
  keys <- c(keys, spec$keys[setdiff(names(spec$keys), given)])
  list(value = value, classes = union(spec$classes, classes), keys = keys,
       unit_form = unit_form %||% spec$unit_form)
}

# ---- texts ----------------------------------------------------------------------------------------

# The format as an attribute block writes it, without the braces: ".num digits=1".
sv_spec_text <- function(spec) {
  keys <- spec$keys
  kv <- vapply(names(keys), function(k) paste0(k, "=", paste(as.character(keys[[k]]), collapse = "|")), "")
  uf <- if (!is.null(spec$unit_form)) paste0("unit_form=", spec$unit_form)
  paste(c(spec$classes, kv, uf), collapse = " ")
}

# What a value is, for the error of c() and `[<-`.
sv_what <- function(x) {
  if (inherits(x, "weft_val")) sprintf("`%s`", sv_spec_text(attr(x, "weft_spec"))) else sprintf("a %s", class(x)[1L])
}

# c() and `[<-` (3.12.6): `x` joins a value of format `spec` when it is a value of the same format,
# a number or quantity, or NAs; anything else is a construct error.
sv_check_join <- function(spec, x, first) {
  if (is.null(x)) return(invisible())
  same <- if (inherits(x, "weft_val")) {
    identical(attr(x, "weft_spec"), spec)
  } else {
    (is.numeric(x) && !inherits(x, "weft_text")) || (is.logical(x) && all(is.na(x)))
  }
  if (!same) {
    construct_error(sprintf(paste0("Values with different formats cannot be combined: %s and %s. Give them ",
                                   "one format, or combine the numbers with as.numeric()."),
                            sv_what(first), sv_what(x)))
  }
  invisible()
}

# The texts of `x` for `target`, names kept; `na` replaces a missing text.
sv_texts <- function(x, target, na = NULL) {
  shown <- attr(x, "weft_shown")
  out <- switch(target,
                markdown = shown$markdown,
                tex = {
                  if (is.null(shown$tex)) tex_class_check(attr(x, "weft_spec")$classes)
                  shown$tex
                },
                html = ,
                marquee = rich_text(shown$markdown, target),
                shown$plain)
  if (!is.null(na)) out[is.na(out)] <- na
  names(out) <- names(x)
  out
}

# ---- methods: text --------------------------------------------------------------------------------

#' @rdname val
#' @param ... Passed on, or ignored where the text says so.
#' @export
as.character.weft_val <- function(x, ...) sv_texts(x, "plain")

#' @rdname val
#' @param target `"plain"` (the default), `"markdown"`, `"tex"`, `"ansi"` (which is plain),
#'   `"html"` or `"marquee"`. The last two give what the matching `fmt_*()` call gives for the same
#'   number and format; the html form has class `c("html", "character")` and the attribute
#'   `html = TRUE`.
#' @export
format.weft_val <- function(x, target = "plain", ...) {
  if (!is_string(target) || !target %in% c("plain", "markdown", "tex", "ansi", "html", "marquee")) {
    got <- if (is_string(target)) paste0("\"", target, "\"") else "something else"
    construct_error(sprintf(paste0("`target` must be \"plain\", \"markdown\", \"tex\", \"ansi\", ",
                                   "\"html\" or \"marquee\"; got %s."), got))
  }
  out <- sv_texts(x, if (identical(target, "ansi")) "plain" else target, na = "NA")
  if (identical(target, "html")) structure(out, class = c("html", "character"), html = TRUE) else out
}

#' @rdname val
#' @export
print.weft_val <- function(x, ...) {
  head <- paste0("<weft_val", if (!length(x)) "[0]", " ", sv_spec_text(attr(x, "weft_spec")), ">")
  cat(head, "\n", sep = "")
  if (length(x)) print(sv_texts(x, "plain"), quote = FALSE)
  invisible(x)
}

#' @rdname val
#' @param options Passed by knitr.
#' @param inline For `knit_print()`: `TRUE` for inline R.
#' @exportS3Method knitr::knit_print
knit_print.weft_val <- function(x, options = NULL, inline = FALSE, ...) {
  knitr::asis_output(paste(format(x, target = "markdown"), collapse = if (isTRUE(inline)) ", " else "\n"))
}

#' @rdname val
#' @param style Not used (for `cli_format()`).
#' @exportS3Method cli::cli_format
cli_format.weft_val <- function(x, style = NULL, ...) {
  out <- sv_texts(x, "plain", na = "NA")
  attributes(out) <- list(names = names(out))
  out
}

#' @rdname val
#' @param row.names,optional,nm As for `as.data.frame()`.
#' @export
as.data.frame.weft_val <- function(x, row.names = NULL, optional = FALSE, ..., nm = deparse1(substitute(x))) {
  as.data.frame.vector(x, row.names = row.names, optional = optional, ..., nm = nm)
}

# ---- methods: vectors -----------------------------------------------------------------------------

#' @rdname val
#' @export
`[.weft_val` <- function(x, ...) {
  pos <- sv_positions(x)[...]
  sv_restore(sv_strip(x)[...], attr(x, "weft_spec"), sv_shown_at(attr(x, "weft_shown"), pos))
}

#' @rdname val
#' @export
`[[.weft_val` <- function(x, ...) {
  pos <- sv_positions(x)[[...]]
  sv_restore(sv_strip(x)[[...]], attr(x, "weft_spec"), sv_shown_at(attr(x, "weft_shown"), pos))
}

#' @rdname val
#' @param value The new elements: numbers, or values of the same format.
#' @export
`[<-.weft_val` <- function(x, ..., value) {
  spec <- attr(x, "weft_spec")
  sv_check_join(spec, value, x)
  inner <- sv_strip(x)
  inner[...] <- sv_strip(value)
  sv_build(inner, spec)
}

#' @rdname val
#' @export
`[[<-.weft_val` <- function(x, ..., value) {
  spec <- attr(x, "weft_spec")
  sv_check_join(spec, value, x)
  inner <- sv_strip(x)
  inner[[...]] <- sv_strip(value)
  sv_build(inner, spec)
}

#' @rdname val
#' @export
c.weft_val <- function(...) {
  args <- list(...)
  args <- args[!vapply(args, is.null, NA)]
  first <- args[[1L]]
  spec <- attr(first, "weft_spec")
  for (a in args[-1L]) sv_check_join(spec, a, first)
  sv_build(do.call(c, lapply(args, sv_strip)), spec)
}

#' @rdname val
#' @export
rep.weft_val <- function(x, ...) {
  pos <- rep(sv_positions(x), ...)
  sv_restore(rep(sv_strip(x), ...), attr(x, "weft_spec"), sv_shown_at(attr(x, "weft_shown"), pos))
}

#' @rdname val
#' @param incomparables As for `unique()`.
#' @export
unique.weft_val <- function(x, incomparables = FALSE, ...) {
  x[!duplicated(sv_strip(x), incomparables = incomparables, ...)]
}

#' @rdname val
#' @export
xtfrm.weft_val <- function(x) xtfrm(sv_strip(x))

#' @rdname val
#' @export
as.list.weft_val <- function(x, ...) {
  out <- lapply(seq_along(x), function(i) x[[i]])
  names(out) <- names(x)
  out
}

# ---- methods: arithmetic (3.12.7) -----------------------------------------------------------------

#' @rdname val
#' @param e1,e2 Operands.
#' @export
Ops.weft_val <- function(e1, e2) {
  if (missing(e2)) return(get(.Generic)(sv_strip(e1)))
  get(.Generic)(sv_strip(e1), sv_strip(e2))
}

#' @rdname val
#' @param y,mx,my,cl,reverse As for `chooseOpsMethod()`.
#' @export
chooseOpsMethod.weft_val <- function(x, y, mx, my, cl, reverse) TRUE

#' @rdname val
#' @export
Math.weft_val <- function(x, ...) get(.Generic)(sv_strip(x), ...)

#' @rdname val
#' @param na.rm As for `Summary` and `median()`.
#' @export
Summary.weft_val <- function(..., na.rm = FALSE) {
  args <- list(...)
  r <- do.call(.Generic, c(lapply(args, sv_strip), list(na.rm = na.rm)))
  if (!.Generic %in% c("min", "max", "range")) return(r)
  first <- Filter(function(a) inherits(a, "weft_val"), args)[[1L]]
  sv_build(r, attr(first, "weft_spec"))
}

#' @rdname val
#' @export
mean.weft_val <- function(x, ...) sv_build(mean(sv_strip(x), ...), attr(x, "weft_spec"))

#' @rdname val
#' @exportS3Method stats::median
median.weft_val <- function(x, na.rm = FALSE, ...) {
  sv_build(stats::median(sv_strip(x), na.rm = na.rm, ...), attr(x, "weft_spec"))
}

#' @rdname val
#' @exportS3Method units::drop_units
drop_units.weft_val <- function(x) {
  spec <- attr(x, "weft_spec")
  spec$keys$unit <- NULL
  spec$unit_form <- NULL
  sv_build(units::drop_units(sv_strip(x)), spec)
}

# ---- vctrs (registered when vctrs is loaded; no dependency on it) ----------------------------------

# The proxy is a data frame of the bare number and the texts, so slices keep the texts that go with
# their numbers; the restore puts back the classes and attributes of the number underneath `to`.
sv_bare_data <- function(x) {
  d <- sv_strip(x)
  attributes(d) <- NULL
  d
}

vec_proxy_weft_val <- function(x, ...) {
  sh <- attr(x, "weft_shown")
  df <- data.frame(n = sv_bare_data(x), markdown = sh$markdown, plain = sh$plain, stringsAsFactors = FALSE)
  if (!is.null(sh$tex)) df$tex <- sh$tex
  df
}

vec_restore_weft_val <- function(x, to, ...) {
  d <- x$n
  inner <- attributes(sv_strip(to))
  inner$names <- NULL
  attributes(d) <- inner
  sv_restore(d, attr(to, "weft_spec"),
             list(markdown = x$markdown, plain = x$plain, tex = if ("tex" %in% names(x)) x$tex))
}

vec_proxy_equal_weft_val <- function(x, ...) {
  d <- sv_strip(x)
  if (inherits(d, "integer64")) return(as.double(d))
  attributes(d) <- NULL
  d
}

vec_ptype2_weft_val_val <- function(x, y, ...) {
  sv_check_join(attr(x, "weft_spec"), y, x)
  x[0L]
}
vec_ptype2_weft_val_dbl <- function(x, y, ...) double()
vec_cast_weft_val_val <- function(x, to, ...) {
  sv_check_join(attr(to, "weft_spec"), x, to)
  x
}
vec_cast_dbl_weft_val <- function(x, to, ...) as.double(sv_strip(x))

register_val_vctrs <- function() {
  s3_register("vctrs::vec_proxy", "weft_val", vec_proxy_weft_val)
  s3_register("vctrs::vec_restore", "weft_val", vec_restore_weft_val)
  s3_register("vctrs::vec_proxy_equal", "weft_val", vec_proxy_equal_weft_val)
  s3_register("vctrs::vec_ptype2", "weft_val.weft_val", vec_ptype2_weft_val_val)
  s3_register("vctrs::vec_ptype2", "weft_val.double", vec_ptype2_weft_val_dbl)
  s3_register("vctrs::vec_ptype2", "double.weft_val", vec_ptype2_weft_val_dbl)
  s3_register("vctrs::vec_ptype2", "weft_val.integer", vec_ptype2_weft_val_dbl)
  s3_register("vctrs::vec_ptype2", "integer.weft_val", vec_ptype2_weft_val_dbl)
  s3_register("vctrs::vec_cast", "weft_val.weft_val", vec_cast_weft_val_val)
  s3_register("vctrs::vec_cast", "double.weft_val", vec_cast_dbl_weft_val)
  invisible()
}
