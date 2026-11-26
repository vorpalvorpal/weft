# Bare names read R (dev/design-e2.md, rules 1.12.12 to 1.12.14): the lookup of a named value, its snapshot, and
# the printing of `.val` from a value's record. The resolver (R/resolve.R) reads a name with these; the
# publishers (R/values.R) compare snapshots.

# ---- the lookup (BN2) ----------------------------------------------------------------------------------

# TRUE for an environment on the search path other than the global environment.
named_on_search <- function(e) {
  for (i in seq_along(search())[-1L]) if (identical(as.environment(i), e)) return(TRUE)
  FALSE
}

# The binding of `name` from `env`, through its enclosing environments as far as the global environment and no
# further: the walk stops before a namespace, a package on the search path, the base environment and the empty
# environment (BN2, D1). A list with `kind`: "value" (and `value`), "function", "unbound", or "error" (and
# `error`: forcing the binding raised).
named_lookup <- function(name, env) {
  e <- env
  repeat {
    is_global <- identical(e, globalenv())
    if (!is_global && (identical(e, emptyenv()) || identical(e, baseenv()) || isNamespace(e) ||
                       named_on_search(e))) {
      return(list(kind = "unbound"))
    }
    if (exists(name, envir = e, inherits = FALSE)) {
      v <- tryCatch(get(name, envir = e, inherits = FALSE), error = function(err) err)
      if (inherits(v, "error")) return(list(kind = "error", error = v))
      if (is.function(v)) return(list(kind = "function"))
      return(list(kind = "value", value = v))
    }
    if (is_global) return(list(kind = "unbound"))
    e <- parent.env(e)
  }
}

# What a publication of a name compares with: the value, "a function", or "unbound" (BN7).
named_snapshot <- function(lk) {
  switch(lk$kind, value = list(kind = "value", value = lk$value), `function` = list(kind = "function"),
         list(kind = "unbound"))
}

# ---- `.val` in R (BN4, D14) -------------------------------------------------------------------------

# The words of an R class for M4: "a units quantity", or "an R data.frame".
named_val_what <- function(v) {
  if (inherits(v, "units")) "a units quantity" else sprintf("an R %s", class(v)[1L])
}

# The elements `.val` prints for the value `v`, as the filter prints its record (1.12.2): or a list with
# `fail` ("no value" or "value error") and `detail`. `name` is for the message of M4.
named_val_elements <- function(v, name) {
  rec <- values_record(v)
  if (!is.null(rec$code)) {
    return(list(fail = "value error",
                detail = sprintf(paste0("`.val` prints a value as it is, and `%s` is %s, which has no such form; ",
                                        "use a formatter class such as .num (rule 1.12.2)."),
                                 name, named_val_what(v))))
  }
  if (is.null(v) || (is.atomic(v) && anyNA(v)) ||
      (is.double(v) && any(!is.finite(v)))) {
    return(list(fail = "no value", detail = sprintf("`%s` has no value to print: it is missing (rule 1.12.2).", name)))
  }
  if (inherits(v, "integer64")) return(list(text = as.character(v)))
  if (is.factor(v)) return(list(text = as.character(v)))
  if (inherits(v, "Date")) return(list(text = format(v, "%Y-%m-%d")))
  if (is.logical(v)) return(list(text = ifelse(v, "true", "false")))
  if (is.integer(v)) return(list(text = sprintf("%d", v)))
  if (is.double(v)) return(list(text = float_text(unname(v))))
  list(text = as.character(v))
}

# ---- what the executed code assigns (BN11, G5) --------------------------------------------------------

# The names the parsed code `code` assigns: `<-`, `=`, `->`, `<<-`, `->>` (the parser turns the arrows into the
# first and third), `assign("name", ...)` and a `for` variable. The target of a complex assignment (`x$a <- 1`,
# `names(x) <- v`) is the name it changes. `all` is TRUE when the code may assign any name: code that does not
# parse, `assign()` with a name that is not a literal string, and calls such as `list2env()`, `eval()`,
# `source()` and `load()`. A list with `names` and `all`.
named_code_assigns <- function(code) {
  ex <- tryCatch(parse(text = paste(code, collapse = "\n"), keep.source = FALSE), error = function(e) NULL)
  if (is.null(ex)) return(list(names = character(), all = TRUE))
  out <- character()
  all <- FALSE
  target <- function(lhs) {
    while (is.call(lhs) && length(lhs) >= 2L) lhs <- lhs[[2L]]
    if (is.character(lhs) && length(lhs) == 1L) return(lhs)
    if (is.symbol(lhs)) as.character(lhs) else NULL
  }
  ALL_CALLS <- c("list2env", "eval", "evalq", "source", "sys.source", "load", "delayedAssign", "makeActiveBinding")
  walk <- function(e) {
    if (is.call(e)) {
      f <- e[[1L]]
      fn <- if (is.symbol(f)) as.character(f) else if (is.call(f) && length(f) == 3L &&
                                                       as.character(f[[1L]])[1L] %in% c("::", ":::")) {
        as.character(f[[3L]])
      } else ""
      if (fn %in% c("<-", "=", "<<-") && length(e) == 3L) {
        t <- target(e[[2L]])
        if (!is.null(t)) out <<- c(out, t) else all <<- TRUE
      } else if (identical(fn, "assign")) {
        a <- if (length(e) >= 2L) e[[2L]] else NULL
        nm <- names(e)
        if (!is.null(nm) && "x" %in% nm) a <- e[[which(nm == "x")[1L]]]
        if (is.character(a) && length(a) == 1L) out <<- c(out, a) else all <<- TRUE
      } else if (identical(fn, "for") && length(e) >= 2L && is.symbol(e[[2L]])) {
        out <<- c(out, as.character(e[[2L]]))
      } else if (fn %in% ALL_CALLS) {
        all <<- TRUE
      }
      for (i in seq_along(e)) if (!identical(e[[i]], quote(expr = ))) walk(e[[i]])
    } else if (is.pairlist(e) || is.expression(e)) {
      for (i in seq_along(e)) if (!identical(e[[i]], quote(expr = ))) walk(e[[i]])
    }
    invisible()
  }
  for (i in seq_along(ex)) walk(ex[[i]])
  list(names = unique(out), all = all)
}

# Record the code of a chunk that is about to run (the `evaluate` hook).
named_note_code <- function(s, code) {
  a <- named_code_assigns(code)
  if (a$all) s$assigns_all <- TRUE
  s$assigned <- union(s$assigned, a$names)
  invisible()
}

# Whether an executed R chunk above has assigned `nm`, or may have.
named_assigned_above <- function(s, nm) isTRUE(s$assigns_all) || nm %in% s$assigned
