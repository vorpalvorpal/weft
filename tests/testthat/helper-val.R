# Helpers for the self-formatting value tests (test-val-*.R). Contract:
# dev/design-self-formatting.md, stage 1. ASCII only: non-ASCII is written as
# \u escapes.

VAL_NB <- "\u00a0"   # the no-break space between a number and its unit

# the plain text of a formatter's result: a character vector, no attributes
val_txt <- function(x) as.character(unclass(x))

# the plain, markdown and TeX texts the formatter `f` gives `x`
val_plain <- function(f, x, ...) unname(val_txt(f(x, ..., target = "plain")))
val_md    <- function(f, x, ...) unname(val_txt(f(x, ..., target = "markdown")))
val_tex   <- function(f, x, ...) unname(val_txt(f(x, ..., target = "tex")))

# `expr` with its warnings collected: list(value, warnings, zero), where zero
# holds the weft_zero_warning conditions
val_warnings <- function(expr) {
  st <- rlang::env(ws = list())
  value <- withCallingHandlers(expr, warning = function(w) {
    st$ws <- c(st$ws, list(w))
    invokeRestart("muffleWarning")
  })
  list(value = value, warnings = st$ws,
       zero = Filter(function(w) inherits(w, "weft_zero_warning"), st$ws))
}

# the error `expr` signals, or NULL
val_err <- function(expr) tryCatch({ expr; NULL }, error = function(e) e)

# every text label under a grob (a grob, gTree or gtable)
val_grob_labels <- function(g) {
  if (inherits(g, "text") && !is.null(g$label)) return(as.character(g$label))
  kids <- c(if (inherits(g, "gtable")) g$grobs, if (inherits(g, "gTree")) g$children)
  unlist(lapply(kids, val_grob_labels), use.names = FALSE)
}

# a project folder holding `_weft.yml` made of `lines`, as the working directory
# of the calling test; returns its path
val_project <- function(lines, env = parent.frame()) {
  dir <- normalizePath(withr::local_tempdir(.local_envir = env))
  writeLines(lines, file.path(dir, "_weft.yml"))
  withr::local_dir(dir, .local_envir = env)
  dir
}

# a chunk as lines
val_chunk <- function(label, ..., opts = "include=FALSE") {
  c(sprintf("```{r %s, %s}", label, opts), c(...), "```", "")
}
