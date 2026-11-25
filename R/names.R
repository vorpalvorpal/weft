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
  if (is.null(v) || (is.atomic(v) && anyNA(v) && !is.character(v)) || (is.character(v) && anyNA(v)) ||
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
