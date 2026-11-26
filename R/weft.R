# weft() (rules 1.10.10, 3.6, 2.4.1, 2.6.8) and the strings it shares its machinery with: a
# caption is resolved by the same function (2.3). Design: dev/design-e1.md.

#' Resolve markup in a string
#'
#' `weft()` resolves weft's constructs in a character vector from R code, for
#' the text slots no chunk option reaches: a plot's title and labels, a console
#' or log message, a table's caption, text printed with `results = "asis"`
#' (rule 1.10.10). Each element of `x` is a block of prose. Everything in it
#' (values, bare values, governors, claims, guards) is evaluated during the
#' call, in `.envir`, so the result holds what they printed: changing a
#' variable afterwards changes nothing.
#'
#' The result is a `weft` object, a character vector with two forms of each
#' element. Its content is the **plain** text (Unicode, no markup: `m^2`,
#' `1.2 x 10^-4`, emphasis without its marks, rule 1.4.24), so
#' anything that reads a character vector (`cat()`, `nchar()`, `paste()`, a
#' ggplot2 title) gets readable text. The attribute `markdown` holds the
#' **markdown** text. `as.character()` and `format()` give the plain text;
#' `format(x, target = "markdown")` gives the markdown; printing the object in a
#' knit, or as inline R, writes the markdown. `[`, `[[` and `rev()` keep both
#' forms; `c()` and `[<-` take `weft` objects (both forms) and character
#' vectors (text as it is: not markup, not evaluated); `rep()`, `unique()` and
#' `sort()` give a plain character vector. A `weft` object given as a value
#' inside the markup of another, or to an `fmt_*()`, contributes its markdown.
#'
#' A caption option that R computes as a `weft` object (`fig.cap = weft(...)`,
#' `#| fig-cap: !expr weft(...)`) is given to knitr as markdown (as plain text
#' for `fig.alt`). `knitr::kable(caption = weft(...))` gets the plain text.
#'
#' The plain text of a `weft` object uses Unicode superscripts and the minus
#' sign, which the `pdf()` device cannot draw: for a plot with weft text that
#' is saved as PDF, use `cairo_pdf()` or a ragg device.
#'
#' `cat()` in a `results = "asis"` chunk writes plain text; to write markdown,
#' leave the object as a top-level value in a chunk (knitr then calls `knit_print()`)
#' or use `cat(format(x, target = "markdown"))`; an explicit `print()` writes plain text.
#'
#' @section In the console and in cli:
#' The console form of a `weft` text is its plain text with emphasis in italic,
#' strong emphasis in bold (both for `***`) and each failure marker in bold
#' red; with the styles removed it is the plain text. A superscript or subscript
#' with Unicode characters takes no style, and an element joined by `c()` or
#' `[<-`, or changed by a function, is plain. `format(x, target = "ansi")` gives
#' it, and `print()` writes it, but only where cli would write its own styles
#' (`cli::num_ansi_colors()`; `print()` asks about `stdout()`, and about cli's
#' own count as well under a sink): not under
#' `NO_COLOR`, in a knit, into a sink or on a terminal without colour. `format(x)`
#' and `as.character(x)` are always plain.
#'
#' In a cli message, `{.val {x}}` draws the console form, unquoted, in cli's value
#' colour (`cli_format()`, which returns a bare character vector), and `{x}` gives
#' the plain text. A `weft` object given to cli as a value is never read as a
#' template, so braces in it are text; given as the template itself
#' (`cli_inform(x)`) it is read by cli, which evaluates what is in braces, so pass
#' it as `"{x}"`. Use `{.val {x}}` alone: `{.val text {x}}` pastes the value
#' and quotes it. Markup is not written into a cli template: resolve it with
#' `weft()` first.
#'
#' ```r
#' w <- weft("Depth at *[one site | # sites]{n='k'}*: `r d`{.num unit='m'}")
#' cli::cli_inform("{.val {w}}")   # emphasis drawn, in the value colour
#' cli::cli_inform("Plotted {w}")  # plain text
#' msg <- cli::format_inline("{.val {w}}")
#' ```
#'
#' During a knit with weft active a failed check, a missing value or a value
#' error is collected as it is in prose (rules 2.4.1, 3.6.3) and marked in the
#' text with the chunk that holds the call, or the line of the inline R (rule
#' 2.6.8). Outside a knit, and in a knit where `weft_setup()` was not called, the
#' first failure stops at once, with the class of the failure
#' (`weft_claim_failed`, `weft_no_value`, `weft_value_error`,
#' `weft_construct_error`); draft mode has no effect there. A warning is
#' signalled at the call and the object is returned.
#'
#' Outside a knit, the configuration is that of the project root of the working
#' directory (the nearest folder upward that holds `_weft.yml`, else
#' `_quarto.yml` or `_quarto.yaml`, else the working directory). It is read once and kept for the
#' session, and read again when `_weft.yml` appears, disappears or changes size
#' or modification time. A `_weft.yml` with an error is a `weft_config_error`.
#'
#' A named value in the markup, `` `depth`{.num} ``, is read from `.envir`
#' (rule 1.12.12): the call looks the name up in `.envir` and its enclosing
#' environments as far as the global environment, never in base R, a
#' namespace or an attached package, and prints it as `` `r depth`{.num} ``
#' would. A name that is not bound there, or is bound to a function, is a "no
#' value" failure; nothing is left for a filter, because the text goes to
#' plots and consoles where none runs. In a loop, each call reads the names as
#' they stand.
#'
#' Block-only constructs do not apply; each element is read as inline markup.
#' Bare inline R in a string is evaluated as knitr evaluates it (rule 1.1.8).
#' The functions inline code calls by name (`claim()`, `plural()`, the
#' `fmt_*()` functions) are visible to the markup even when weft is not
#' attached; a function of the same name that `.envir` can see wins.
#'
#' @param x A character vector of markup (a factor is read as its labels), or
#'   a `weft` object, which is returned as it is. An `NA` element stays `NA`.
#' @param .envir The environment the markup's code is evaluated in.
#' @param ... Not used.
#' @param target For `format()`: `"plain"` (the default), `"markdown"` or
#'   `"ansi"` (the console form, see "In the console and in cli").
#' @param style Not used (for `cli_format()`).
#' @param inline For `knit_print()`: `TRUE` for inline R.
#' @return A `weft` object of the same length and names as `x`.
#' @examples
#' n_sites <- 3
#' w <- weft("Found [a site | # sites]{n=\"n_sites\"} of *Eucalyptus* on 5 m^2^.")
#' as.character(w)
#' format(w, target = "markdown")
#'
#' # one title for each site, each keeping its own value
#' titles <- lapply(c(2, 5), function(k) weft("Depth at `r k`{.num} sites"))
#' vapply(titles, as.character, "")
#'
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) +
#'     ggplot2::geom_point() +
#'     ggplot2::labs(title = weft("Rate of 1.2 &times; 10 per m^2^"))
#' }
#' @export
weft <- function(x, .envir = parent.frame()) {
  force(.envir)
  weft_impl(x, .envir, read_names = TRUE)
}

# weft() with the internal option of E2 BN8: Python's `weft_str()` leaves a named value in its markup for the
# filter (`read_names = FALSE`): in a Python chunk a name is Python's.
weft_impl <- function(x, .envir, read_names = TRUE) {
  if (inherits(x, "weft")) return(x)
  if (is.factor(x)) x <- as.character(x)
  if (!is.character(x)) {
    weft_abort("`weft()` takes a character vector of markup.", "weft_construct_error")
  }
  if (!is.environment(.envir)) {
    weft_abort("`.envir` must be an environment.", "weft_construct_error")
  }
  s <- string_state()
  strict <- !isTRUE(s$live)
  # called from inline R in prose, the string is prose where it is called
  # from: it is located by that line, not by the chunk knitr last ran (3.6.3)
  inl <- weft_env$inline
  in_prose <- !strict && !is.null(inl) && !is.na(inl$line %||% NA_integer_) &&
    is.na(inl$chunk %||% NA_character_)
  chunk <- if (in_prose) NA_character_ else current_chunk_label()
  where <- if (in_prose) list(file = inl$file, line = inl$line) else list()
  # the functions inline code calls are made visible to the strings, and to nothing else (WS3)
  env <- with_weft_functions(.envir)
  ctx <- list(chunk = chunk, option = NA_character_, envir = env, strict = strict,
              context = "weft", file = where$file, line = where$line,
              named_env = .envir, read_names = read_names)
  md <- vapply(unname(x), function(el) {
    if (is.na(el)) return(NA_character_)
    resolve_string(s, el, ctx)
  }, "", USE.NAMES = FALSE)
  new_weft(plain_text(md), md, names(x))
}

# A `weft` object from the two forms of each element.
new_weft <- function(plain, md, names = NULL) {
  plain <- as.character(plain)
  md <- as.character(md)
  attributes(plain) <- NULL
  structure(plain, markdown = md, names = names, class = c("weft", "character"))
}

current_chunk_label <- function() {
  if (!knit_in_progress()) return(NA_character_)
  lab <- tryCatch(knitr::opts_current$get("label"), error = function(e) NULL)
  if (is.character(lab) && length(lab) == 1L && !is.na(lab)) lab else NA_character_
}

# The state a string is resolved against (CF1): the knit's, when weft's hooks are installed and a
# state is active; else a light one holding the configuration `weft_env$config` names, else the
# cached configuration of the working directory's project.
string_state <- function() {
  s <- if (knit_in_progress() && is_weft_hook(knitr::knit_hooks$get("text", default = FALSE))) {
    active_state()
  }
  if (!is.null(s)) {
    s$live <- TRUE
    return(s)
  }
  s <- new_state(config = weft_env$config %||% string_config())
  s$live <- FALSE
  s
}

# ---- the configuration cache (CF1 to CF5) ------------------------------------------------------

string_cache <- new.env(parent = emptyenv())

# For tests: forget every cached configuration.
string_config_reset <- function() {
  rm(list = ls(string_cache, all.names = TRUE), envir = string_cache)
  invisible()
}

# What tells a cached entry from a changed file: whether `_weft.yml` exists, its size, its time.
yml_signature <- function(root) {
  info <- file.info(file.path(root, "_weft.yml"), extra_cols = FALSE)
  list(exists = !is.na(info$size), size = info$size, mtime = info$mtime)
}

# The configuration of the project root of the working directory, read once per session and again
# when `_weft.yml` appears, disappears or changes. A failed read raises and keeps nothing (CF3).
string_config <- function() {
  root <- find_project_root(getwd())
  sig <- yml_signature(root)
  e <- string_cache[[root]]
  if (!is.null(e) && identical(e$sig, sig)) {
    # another project's `units:` table may have been read in between (CF4); a root with no file
    # has the default units, whatever another root's file or a knit left in force (F1)
    if (sig$exists) project_units(root) else units_drop_stale()
    return(e$config)
  }
  string_cache[[root]] <- NULL
  weft_env$reading <- TRUE
  on.exit(weft_env$reading <- NULL)
  cfg <- read_config(root, list(), explicit = FALSE)
  string_cache[[root]] <- list(sig = sig, config = cfg)
  cfg
}

# Park the inline code of a string exactly as the `evaluate.inline` hook parks
# the code of a block of prose, so one resolver reads both. Returns the text
# with a placeholder for each piece of code.
park_string <- function(s, x, envir, bare = TRUE) {
  pat <- knitr::all_patterns$md$inline.code
  m <- gregexpr(pat, x, perl = TRUE)[[1L]]
  if (m[1L] < 0L) return(x)
  if (!bare) {
    len <- attr(m, "match.length")
    after <- substring(x, m + len, m + len)
    keep <- after == "{"
    if (!any(keep)) return(x)
    m <- structure(m[keep], match.length = len[keep])
  }
  hits <- regmatches(x, list(m))[[1L]]
  codes <- sub(pat, "\\3", hits, perl = TRUE)
  ph <- character(length(codes))
  for (i in seq_along(codes)) {
    idx <- length(s$parked) + 1L
    s$parked[[idx]] <- list(code = codes[i], envir = envir)
    ph[i] <- paste0("\ue000", idx, "\ue002")
  }
  regmatches(x, list(m)) <- list(ph)
  x
}

# Resolve one string. `ctx`: chunk, option, envir, strict, context.
resolve_string <- function(s, x, ctx) {
  x <- enc2utf8(x)
  # bare inline R in a caption stays literal text, as stock leaves it (1.1.8);
  # inline code that carries an attribute block is a construct and is run
  x <- park_string(s, x, ctx$envir, bare = !identical(ctx$context, "caption"))
  if (!grepl("\ue000", x, fixed = TRUE) && !grepl("[", x, fixed = TRUE) &&
      !grepl("]{", x, fixed = TRUE) && !grepl("`{", x, fixed = TRUE)) return(x)
  resolve_markup(s, x, block = NULL, ctx = ctx)
}

# The functions inline code calls by name (`claim()`, `plural()`, `fmt_*()`), computed once per session.
inline_function_names <- function() {
  if (is.null(weft_env$inline_names)) {
    weft_env$inline_names <- c("claim", "plural", "glue_vec", "u", "dict_glossary", "py_value",
                               "jl_value", grep("^fmt_", getNamespaceExports(asNamespace("weft")), value = TRUE))
  }
  weft_env$inline_names
}

# `envir`, or a child of it that holds the inline functions `envir` cannot see.
with_weft_functions <- function(envir) {
  nms <- inline_function_names()
  miss <- nms[!vapply(nms, exists, NA, envir = envir, mode = "function", inherits = TRUE)]
  if (!length(miss)) return(envir)
  e <- new.env(parent = envir)
  ns <- asNamespace("weft")
  for (m in miss) assign(m, get(m, envir = ns), envir = e)
  e
}

# ---- the weft object (WS6 to WS11) -------------------------------------------------------------

# The plain text of each element, names kept.
weft_plain <- function(x) {
  p <- unclass(x)
  attr(p, "markdown") <- NULL
  p
}

# The markdown attribute of `x`, or, when it has none of the length of its plain text `p`, that text
# (unnamed).
weft_md_attr <- function(x, p = weft_plain(x)) {
  md <- attr(x, "markdown")
  if (is.null(md) || length(md) != length(p)) unname(p) else md
}

# The markdown of each element, names kept. An element whose plain text is no longer its markdown
# read by PL, and is not text joined as it is, was changed by a function that kept the attributes
# (WS10): its markdown is then its plain text.
weft_markdown <- function(x) {
  p <- weft_plain(x)
  md <- attr(x, "markdown")
  if (is.null(md) || length(md) != length(p)) return(p)
  names(md) <- names(p)
  chg <- !is.na(p) & !is.na(md) & p != md & p != plain_text(md)
  chg <- chg | (is.na(p) != is.na(md))
  md[chg] <- p[chg]
  md
}

weft_target <- function(target) {
  if (is.character(target) && length(target) == 1L && !is.na(target)) {
    if (target %in% c("plain", "markdown", "ansi")) return(target)
    got <- paste0("\"", target, "\"")
  } else {
    got <- "something else"
  }
  weft_abort(sprintf("`target` must be \"plain\", \"markdown\" or \"ansi\"; got %s.", got),
             "weft_construct_error")
}

#' @rdname weft
#' @export
as.character.weft <- function(x, ...) weft_plain(x)

#' @rdname weft
#' @export
format.weft <- function(x, target = "plain", ...) {
  target <- weft_target(target)
  if (identical(target, "ansi")) return(weft_ansi(x, cli::num_ansi_colors()))
  out <- if (identical(target, "markdown")) weft_markdown(x) else weft_plain(x)
  out[is.na(out)] <- "NA"
  out
}

#' @rdname weft
#' @export
print.weft <- function(x, ...) {
  if (!length(x)) {
    cat("<weft[0]>\n")
  } else {
    p <- unname(weft_ansi(x, print_colors()))
    cat(p, sep = "\n")
  }
  invisible(x)
}

# The colour count for `print()`: that of `stdout()`, which does not see a sink; under a sink, the
# smaller of that and the "auto" count, which does (H1).
print_colors <- function() {
  n <- cli::num_ansi_colors(stdout())
  if (sink.number() > 0L) n <- min(n, cli::num_ansi_colors())
  n
}

#' @rdname weft
#' @exportS3Method cli::cli_format
#' @importFrom cli cli_format
cli_format.weft <- function(x, style = NULL, ...) {
  out <- weft_ansi(x, cli::num_ansi_colors(), breaks = TRUE)
  attributes(out) <- list(names = names(out))
  out
}

# A `weft` object of the elements `...` of both forms.
weft_pick <- function(x, ...) {
  p <- weft_plain(x)
  md <- weft_md_attr(x, p)
  names(md) <- names(p)
  new_weft(p[...], unname(md[...]), names(p[...]))
}

#' @rdname weft
#' @export
`[.weft` <- function(x, ...) weft_pick(x, ...)

#' @rdname weft
#' @param i An index.
#' @export
`[[.weft` <- function(x, i, ...) {
  if (length(i) != 1L) stop("subscript out of bounds", call. = FALSE)
  # base's own errors for an index out of bounds
  weft_plain(x)[[i]]
  weft_pick(x, i)
}

#' @rdname weft
#' @param decreasing Passed to `sort()`.
#' @export
sort.weft <- function(x, decreasing = FALSE, ...) sort(weft_plain(x), decreasing = decreasing, ...)

# The two forms of what `c()` and `[<-` take (WS9).
weft_parts <- function(v) {
  if (is.null(v)) return(list(plain = character(), md = character()))
  if (inherits(v, "weft")) return(list(plain = weft_plain(v), md = weft_markdown(v)))
  if (is.character(v) && !is.factor(v)) {
    v <- as.vector(v)
    return(list(plain = v, md = v))
  }
  weft_abort(sprintf(paste0("A weft text can be combined only with weft texts and character vectors; ",
                            "got a %s."), class(v)[1L]), "weft_construct_error")
}

#' @rdname weft
#' @export
c.weft <- function(...) {
  parts <- lapply(list(...), weft_parts)
  p <- unlist(lapply(parts, `[[`, "plain"), use.names = TRUE)
  md <- unlist(lapply(parts, `[[`, "md"), use.names = FALSE)
  new_weft(p %||% character(), md %||% character(), names(p))
}

#' @rdname weft
#' @param value The new elements: `weft` objects or character vectors.
#' @export
`[<-.weft` <- function(x, i, value) {
  v <- weft_parts(value)
  p <- weft_plain(x)
  md <- weft_markdown(x)
  p[i] <- v$plain
  md[i] <- v$md
  new_weft(p, md, names(p))
}

#' @rdname weft
#' @export
`[[<-.weft` <- function(x, i, value) {
  if (length(value) != 1L) {
    stop("more elements supplied than there are to replace", call. = FALSE)
  }
  `[<-.weft`(x, i, value)
}

#' @rdname weft
#' @export
`is.na<-.weft` <- function(x, value) {
  x[value] <- NA_character_
  x
}

#' @rdname weft
#' @param options Passed by knitr.
#' @exportS3Method knitr::knit_print
knit_print.weft <- function(x, options = NULL, inline = FALSE, ...) {
  md <- format(x, target = "markdown")
  knitr::asis_output(paste(md, collapse = if (isTRUE(inline)) ", " else "\n\n"))
}
