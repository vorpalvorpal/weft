# Values by name: the carrier, and what the hooks publish (dev/design-6.md, section 2B and 2C; dev/design-e2.md).
#
# R reads a named value in a knitr document itself (R/resolve.R, R/names.R). The hooks publish only what the
# filter will resolve: the names of front matter, of captions the hooks do not resolve, and the names the hooks
# left for the filter because R does not bind them where they stand (TR1). A guest's records (Python `put()`
# and `auto()`, Julia `put` and `@put`) wait in the knit's state (`s$waiting`) and are written with them, as one
# block before the next block of prose; the `document` hook writes whatever is left at the end.
# `weft_values_write()` writes a values file; `values_block()` is the internal block maker the tests use. The
# record of an R value is the record of rule 1.11 seen from the R side: the kinds are R/guest.R's (`t` is one of
# bool, int, float, decimal, string, date, list, missing, error; a list holds scalar records, `of` is the kind of
# its elements, `keys` its names). The writer here makes the JSON text of a record directly, so the key order is
# fixed: `t`, then `v`, then `of`, `keys`, `why`, `checks`.

# ---- names (N6) ---------------------------------------------------------------------------------------

VALUES_RESERVED <- c("TRUE", "FALSE", "True", "False", "true", "false", "NA", "NULL",
                     "None", "nothing", "missing", "Inf", "NaN")

# TRUE for each element of `x` that is a NAME (N6).
values_name_ok <- function(x) {
  x <- as.character(x)
  ok <- !is.na(x) & grepl("^[A-Za-z_][A-Za-z0-9_.]{0,63}\\z", x, perl = TRUE) &
    !endsWith(x, ".") & !(x %in% VALUES_RESERVED)
  ok
}

values_abort <- function(msg) weft_abort(msg, "weft_values_error")

# ---- the JSON text -------------------------------------------------------------------------------------------

# JSON string literals (with their quotes) for a character vector.
values_str <- function(x) {
  x <- enc2utf8(as.character(x))
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  if (any(grepl("[\\x01-\\x1f]", x, perl = TRUE))) {
    for (code in setdiff(1:31, c(9L, 10L, 13L))) {
      x <- gsub(rawToChar(as.raw(code)), sprintf("\\u%04x", code), x, fixed = TRUE)
    }
  }
  paste0("\"", x, "\"")
}

# The shortest text, of %.15g, %.16g and %.17g, that reads back as the same
# double (N47). `x` is finite.
float_text <- function(x) {
  out <- sprintf("%.15g", x)
  # a subnormal has fewer digits than a normal double: take the first digit count that reads back
  # (5e-324, not 4.94...e-324)
  sub <- which(abs(x) < 2.2250738585072014e-308 & x != 0)
  for (i in sub) {
    for (d in seq_len(17L)) {
      t <- sprintf(paste0("%.", d, "g"), x[i])
      if (as.numeric(t) == x[i]) break
    }
    out[i] <- t
  }
  for (d in c(16L, 17L)) {
    redo <- !(as.numeric(out) == x)
    if (!any(redo)) break
    out[redo] <- sprintf(paste0("%.", d, "g"), x[redo])
  }
  out
}

# ---- the record of an R value (N47) ---------------------------------------------------------------

E44_TAIL <- paste0("is a units quantity; named values carry no units. Publish the number in ",
                   "the unit you mean (rule 2.13.3).")

E46_TAIL <- paste0("is a self-formatting value; named values carry no format. Publish the number with ",
                   "as.numeric() and write its classes where it is used (rule 3.8.4).")

# A refused value: the text after the subject, and the kind of refusal.
values_refusal <- function(code, tail) {
  list(code = code, tail = tail,
       json = paste0("{\"t\":\"error\",\"why\":", values_str(paste("{S}", tail)), "}"))
}

# The JSON of each element of an atomic vector `x` as a scalar record, and its
# kind. `x` is a logical, integer, double, character, factor, Date or integer64
# vector without names.
values_scalars <- function(x) {
  n <- length(x)
  miss <- function(why) paste0("{\"t\":\"missing\",\"why\":", values_str(why), "}")
  js <- character(n)
  kind <- rep(NA_character_, n)
  # the missing elements, read once: a double (a Date's too) is missing when it is not finite, and
  # says which; any other is missing when it is NA
  u <- if (inherits(x, "integer64") || is.factor(x)) as.character(x) else x
  if (inherits(x, "Date")) {
    u <- unclass(x)
    attributes(u) <- NULL
  }
  dbl <- is.double(u)
  bad <- if (dbl) !is.finite(u) else is.na(u)
  why <- if (dbl) ifelse(is.nan(u), "NaN", ifelse(is.na(u), "NA", ifelse(u > 0, "Inf", "-Inf"))) else "NA"
  js[bad] <- miss(if (dbl) why[bad] else why)
  kind[bad] <- "missing"
  ok <- !bad
  # the kind and the JSON of the elements that are not missing
  rec <- if (inherits(x, "integer64")) {
    list("int", paste0("{\"t\":\"int\",\"v\":", values_str(u[ok]), "}"))
  } else if (is.factor(x)) {
    list("string", paste0("{\"t\":\"string\",\"v\":", values_str(u[ok]), "}"))
  } else if (inherits(x, "Date")) {
    list("date", paste0("{\"t\":\"date\",\"v\":", values_str(format(x[ok], "%Y-%m-%d")), "}"))
  } else if (is.logical(x)) {
    list("bool", ifelse(x[ok], "{\"t\":\"bool\",\"v\":true}", "{\"t\":\"bool\",\"v\":false}"))
  } else if (is.integer(x)) {
    list("int", paste0("{\"t\":\"int\",\"v\":\"", sprintf("%d", x[ok]), "\"}"))
  } else if (is.double(x)) {
    list("float", paste0("{\"t\":\"float\",\"v\":\"", float_text(x[ok]), "\"}"))
  } else {
    list("string", paste0("{\"t\":\"string\",\"v\":", values_str(x[ok]), "}"))
  }
  js[ok] <- rec[[2L]]
  kind[ok] <- rec[[1L]]
  list(json = js, kind = kind)
}

# The record of an R value, as list(json, code, tail). `code` is NULL for a
# record, and "E42", "E44", "E45" or "E46" for a refused value (its `json` is then an
# error record, and `tail` the message after the subject).
values_record <- function(x) {
  if (is.null(x)) {
    return(list(json = "{\"t\":\"missing\",\"why\":\"NULL\"}", code = NULL))
  }
  if (inherits(x, "weft_val")) return(values_refusal("E46", E46_TAIL))
  if (inherits(x, "units")) return(values_refusal("E44", E44_TAIL))
  plain <- inherits(x, c("integer64", "factor", "Date")) ||
    (!is.object(x) && (is.logical(x) || is.integer(x) || is.double(x) || is.character(x)) &&
       is.null(dim(x)))
  if (!plain) {
    return(values_refusal("E45", sprintf(paste0(
      "is an R %s, which weft does not publish. Publish a bool, number, string, ",
      "Date, or a vector of one of these (rule 1.11.1)."), class(x)[1L])))
  }
  n <- length(x)
  if (n > 10000L) {
    return(values_refusal("E42", sprintf(
      "is a list of %d elements; weft publishes at most 10000 (rule 2.13.1).", n)))
  }
  nm <- names(x)
  if (!inherits(x, "integer64")) names(x) <- NULL
  sc <- values_scalars(x)
  # a named vector of length 1 is a list of one with its key; an unnamed one is a scalar
  if (n == 1L && is.null(nm)) return(list(json = sc$json, code = NULL))
  kinds <- unique(sc$kind[sc$kind != "missing"])
  of <- if (length(kinds)) kinds[1L] else if (n == 0L) values_empty_kind(x) else "missing"
  keys <- if (is.null(nm)) "null" else
    paste0("[", paste(values_str(ifelse(is.na(nm), "NA", nm)), collapse = ","), "]")
  list(json = paste0("{\"t\":\"list\",\"v\":[", paste(sc$json, collapse = ","),
                     "],\"of\":", values_str(of), ",\"keys\":", keys, "}"),
       code = NULL)
}

# The element kind of a vector of length zero, from its type.
values_empty_kind <- function(x) {
  if (inherits(x, "integer64") || is.integer(x)) "int"
  else if (inherits(x, "Date")) "date"
  else if (is.factor(x) || is.character(x)) "string"
  else if (is.double(x)) "float"
  else "bool"
}

# A check object (N23) for each check of a captured `claim()`.
values_check_json <- function(text, run, level) {
  why <- ifelse(!is.na(run$errs), values_str(run$errs),
                ifelse(!is.na(run$lens), values_str(sprintf("returned %d values, not a single TRUE", run$lens)),
                       "null"))
  paste0("{\"text\":", values_str(text), ",\"ok\":", ifelse(run$ok, "true", "false"),
         ",\"level\":", values_str(level), ",\"why\":", why, "}")
}

# `rec` with a `checks` member added.
values_with_checks <- function(rec, checks) {
  if (!length(checks)) return(rec)
  rec$json <- paste0(substr(rec$json, 1L, nchar(rec$json) - 1L), ",\"checks\":[",
                     paste(checks, collapse = ","), "]}")
  rec
}

# ---- run and time (N48) ---------------------------------------------------------------------------------

# The run id: the first line of `.weft/run`, found walking up from `dir` (at
# most 8 levels above it), else WEFT_RUN when set and not empty, else NULL.
# Read at each publish, never kept.
values_run <- function(dir = values_dir()) {
  d <- normalizePath(dir, winslash = "/", mustWork = FALSE)
  for (i in 0:8) {
    f <- file.path(d, ".weft", "run")
    if (file.exists(f) && !dir.exists(f)) {
      line <- tryCatch(readLines(f, n = 1L, warn = FALSE, encoding = "UTF-8"),
                       error = function(e) character())
      line <- sub("\r$", "", line)
      if (length(line) && nzchar(trimws(line))) return(enc2utf8(line))
    }
    up <- dirname(d)
    if (identical(up, d)) break
    d <- up
  }
  e <- Sys.getenv("WEFT_RUN", "")
  if (nzchar(e)) enc2utf8(e) else NULL
}

# The document's folder: the knit's input, else the working directory.
values_dir <- function() {
  p <- if (knit_in_progress()) knit_input_path() else NULL
  if (is.null(p)) getwd() else dirname(p)
}

values_now <- function() sprintf("%.0f", floor(as.numeric(Sys.time())))

# ---- the block (N20, N21) --------------------------------------------------------------------------------

# The JSON object text of a block. `records` is a named list of record JSON texts.
values_json <- function(records, cell = NULL, run = values_run()) {
  vals <- if (length(records)) {
    paste0(values_str(names(records)), ":", unlist(records, use.names = FALSE), collapse = ",")
  } else ""
  paste0("{\"weft\":1,\"lang\":\"r\",\"run\":", if (is.null(run)) "null" else values_str(run),
         ",\"at\":", values_now(), ",\"values\":{", vals, "}",
         if (!is.null(cell) && nzchar(cell)) paste0(",\"cell\":", values_str(cell)), "}")
}

# The fenced block: four backticks, so that a backtick fence inside a string
# cannot close it, and the JSON on one line.
values_fenced <- function(json) paste0("````{.weft-values}\n", json, "\n````\n")

# ---- what a call publishes (N40, N41) -------------------------------------------------------------

# TRUE for an expression that is a call of claim() or weft::claim().
is_claim_call <- function(e) {
  is.call(e) && (identical(e[[1L]], quote(claim)) || identical(e[[1L]], quote(weft::claim)))
}

# The parts of a `claim()` call that `weft_values_write()` captures, or NULL when the
# call is to be evaluated as it stands (so that claim() itself refuses it).
values_claim_parts <- function(e, env) {
  mc <- tryCatch(match.call(claim, e, expand.dots = FALSE), error = function(err) NULL)
  if (is.null(mc) || is.null(mc$x)) return(NULL)
  checks <- as.list(mc[["..."]])
  empty <- vapply(checks, function(ck) identical(ck, quote(expr = )), NA)
  checks <- checks[!empty]
  if (!length(checks)) return(NULL)
  bare <- vapply(checks, function(ck) is.character(ck) && length(ck) == 1L &&
                   ck %in% c("warn", "fail"), NA)
  if (any(bare)) return(NULL)
  # a bad decision is claim()'s own error (E52), raised before any check runs (N103)
  if (!is.null(mc$decision)) {
    ok <- tryCatch({ claim_decision(eval(mc$decision, env)); TRUE }, error = function(err) FALSE)
    if (!ok) return(NULL)
  }
  level <- "fail"
  if (!is.null(mc$level)) {
    lv <- tryCatch(eval(mc$level, env), error = function(err) NULL)
    if (!(is_string(lv) && lv %in% c("fail", "warn"))) return(NULL)
    level <- lv
  }
  list(x = mc$x, checks = checks, level = level)
}

# The records a call publishes: a named list of list(json, code, tail). `exprs`
# are the arguments as written, `get(i)` the value of the i-th (forced only
# when it is not a claim), `env` the caller's frame. Raises weft_values_error
# for E40, E41, E43 and for a value that is refused with E42, E44 or E46; E45 is a
# record.
values_collect <- function(exprs, get, env, frames) {
  n <- length(exprs)
  if (!n) return(list())
  given <- names(exprs)
  if (is.null(given)) given <- rep("", n)
  nm <- character(n)
  for (i in seq_len(n)) {
    if (nzchar(given[i])) {
      nm[i] <- given[i]
    } else if (is.symbol(exprs[[i]])) {
      nm[i] <- as.character(exprs[[i]])
    } else {
      values_abort(paste0("weft_values_write() takes named arguments or names after the path: ",
                          "weft_values_write(path, n = nrow(d)) or weft_values_write(path, n) (rule 3.8.5)."))
    }
    if (!values_name_ok(nm[i])) {
      values_abort(sprintf(paste0("`%s` is not a name weft can publish: ASCII letters, digits, _ and ., ",
                                  "starting with a letter or _ (rule 1.12.1)."), nm[i]))
    }
  }
  dup <- nm[duplicated(nm)]
  if (length(dup)) {
    values_abort(sprintf("`%s` is given twice in one weft_values_write() call.", dup[1L]))
  }
  out <- vector("list", n)
  names(out) <- nm
  for (i in seq_len(n)) {
    parts <- if (is_claim_call(exprs[[i]])) values_claim_parts(exprs[[i]], env) else NULL
    if (is.null(parts)) {
      rec <- values_record(get(i))
    } else {
      value <- eval(parts$x, env)
      run <- claim_run_checks(parts$checks, value, env)
      text <- written_checks(frames, parts$checks, weft_env$inline$expr)
      rec <- values_with_checks(values_record(value), values_check_json(text, run, parts$level))
    }
    if (!is.null(rec$code) && rec$code %in% c("E42", "E44", "E46")) {
      values_abort(sprintf("`%s` %s", nm[i], rec$tail))
    }
    out[[i]] <- rec
  }
  out
}

# ---- exports --------------------------------------------------------------------------------------------------

# The block of the values it is given, as the text weft_values_write() would put in a file: an internal block
# maker for tests (E2 PB3). It takes `weft_values_write()`'s value arguments, in or out of a knit, and stores
# nothing.
values_block <- function(...) {
  frames <- sys.calls()
  env <- parent.frame()
  self <- environment()
  exprs <- as.list(substitute(list(...)))[-1L]
  get <- function(i) eval(call("...elt", i), self)
  recs <- values_collect(exprs, get, env, frames)
  block <- values_json(lapply(recs, `[[`, "json"))
  structure(values_fenced(block), class = "weft_values")
}

#' @export
print.weft_values <- function(x, ...) {
  cat(unclass(x), sep = "")
  invisible(x)
}

#' Write a values file
#'
#' `weft_values_write()` writes the values it is given to a JSON file in the
#' form of a `weft-values` block (schema 1), for a document to read with a
#' `weft-values` block that names the file (rules 2.13.10, 3.8.5). It works
#' outside a knit, and in a `targets` pipeline. In a knitr document R reads a
#' named value itself, so a values file is for a document that runs no R, or
#' for a pipeline that computes the values elsewhere.
#'
#' Each argument after `path` writes one name: `weft_values_write(f, depth =
#' mean(d$depth))`, or `weft_values_write(f, depth, n_sites)` for variables of
#' the same names. A name is ASCII letters, digits, `_` and `.`, starting with a
#' letter or `_`, at most 64 characters. An argument that is a call of
#' [claim()] is captured: its checks are run and recorded with the value,
#' nothing is stopped, and each check counts where the name is used.
#'
#' A bool, a whole or decimal number, a string, a factor, a `Date`, an
#' `integer64` or an atomic vector of these (up to 10000 elements) is written
#' with its kind. `NA`, `NaN`, `Inf` and `NULL` are written as missing. A value
#' with units is refused, and any other object (a data frame, a list, a
#' `POSIXct`, a function) is written as an error that is reported where the
#' name is used.
#'
#' The file is written atomically, as UTF-8 with `\\n` line ends. Nothing is
#' written when an argument is refused, and the old file stays.
#'
#' @param path The file to write. A relative path is relative to the working
#'   directory.
#' @param ... Named values, or names of variables, as above. An argument may be
#'   a call of [claim()].
#' @return `path`, invisibly.
#' @examples
#' f <- tempfile(fileext = ".json")
#' weft_values_write(f, n = 12L, site = "north")
#' cat(readLines(f), sep = "\n")
#' @export
weft_values_write <- function(path, ...) {
  frames <- sys.calls()
  env <- parent.frame()
  self <- environment()
  exprs <- as.list(substitute(list(...)))[-1L]
  get <- function(i) eval(call("...elt", i), self)
  recs <- values_collect(exprs, get, env, frames)
  json <- values_json(lapply(recs, `[[`, "json"), run = values_run(getwd()))
  write_lines_atomic(json, path)
  invisible(path)
}

# ---- the names a source names (N45) ---------------------------------------------------------------

# Every name token of a governor value: string literals, in either quote, are removed first in one
# left-to-right pass (two passes would mis-strip `"it's" == x`).
values_governor_names <- function(x) {
  x <- gsub("'[^']*'|\"[^\"]*\"", " ", x)
  unlist(regmatches(x, gregexpr("(?<![A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_.]*", x, perl = TRUE)),
         use.names = FALSE)
}

# The names the text of one file names, not those of its includes: those of rule 1
# (`code`: the code spans of a named value) and those of rule 2 (`gov`: the
# governor values).
values_text_names <- function(txt) {
  code <- character()
  gov <- character()
  if (grepl("`{", txt, fixed = TRUE)) {
    m <- regmatches(txt, gregexpr("`[A-Za-z_][A-Za-z0-9_.]{0,63}`\\{", txt, perl = TRUE))[[1L]]
    code <- substr(m, 2L, nchar(m) - 2L)
  }
  if (grepl("=", txt, fixed = TRUE)) {
    # a value in any form of 1.2.2, read as 1.2.3: the quotes off, `\"`, `\'` and `\|` unescaped (C7)
    m <- regmatches(txt, gregexpr(paste0("(?s)(?<![A-Za-z0-9_.-])(?i:n|if|sign|list)=",
                                         "(?:\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|(?:[^\\s}\"'\\\\]|\\\\\\|)+)"),
                                  txt, perl = TRUE))[[1L]]
    if (length(m)) {
      v <- sub("^[A-Za-z]+=", "", m)
      quoted <- grepl("^[\"']", v)
      v[quoted] <- substr(v[quoted], 2L, nchar(v[quoted]) - 1L)
      v <- gsub("\\\\([\"'|])", "\\1", v)
      gov <- values_governor_names(v)
    }
  }
  list(code = code, gov = gov)
}

# What a document names (N45): `path` and every file its `{{< include >}}`
# shortcodes reach, as Quarto expands them (include_walk(): any depth, every
# path against the document's folder). A file that cannot be read, or is not
# there, names nothing. Returns the names (no repeats, no reserved word, nothing
# that is not a NAME) and `named`: whether any code span of rule 1 names one,
# that is, whether the document holds a named value.
values_source_scan <- function(path) {
  read <- function(p) {
    txt <- read_source_text_or_null(p)
    if (is.null(txt)) NULL else split_source_lines(txt)
  }
  if (!utils::file_test("-f", path)) return(list(names = character(), named = FALSE))
  main <- read(path)
  texts <- c(list(main), lapply(include_walk(path, lines = main %||% character(), read = read)$files,
                                `[[`, "lines"))
  found <- lapply(texts, function(ln) values_text_names(paste(ln, collapse = "\n")))
  code <- unique(unlist(lapply(found, `[[`, "code")))
  code <- code[values_name_ok(code)]
  nm <- unique(c(code, unlist(lapply(found, `[[`, "gov"))))
  list(names = nm[values_name_ok(nm)], named = length(code) > 0L)
}

# The names a source names (N45), without repeats.
values_source_names <- function(path) values_source_scan(path)$names

# ---- publishing in a knit (E2 TR1 to TR4) ------------------------------------------------------------

# The lists a source gives the hooks (TR1, TR4), for one file and the files it includes: `front` (the names of
# the named values in front matter), `cap` (the names a caption the hooks do not resolve holds: named values,
# and governor names of spans there), `auto` (the names Python's auto() is asked for: every named value of the
# source, wherever it stands, and each governor name of a span in the code of a Python or Julia chunk or in
# a chunk's options). `F` is the file's state (new_file_state()) when the knit has it: its lines and its scan
# are the ones read here (E7).
values_scan_lists <- function(path, cfg, F = NULL) {
  local_doc_memo()
  out <- list(front = character(), cap = character(), auto = character())
  lines <- if (!is.null(F)) F$lines else tryCatch(read_view_lines(path), error = function(e) character())
  if (!length(lines)) return(out)
  extra <- if (!is.null(F)) {
    F$extra
  } else {
    tryCatch(scan_extra_rows(lines, file = NA_character_, config = cfg, project = project_type(path)),
             error = function(e) NULL)
  }
  if (!is.null(extra) && nrow(extra)) {
    named <- extra$kind == "named" & is.na(extra$error)
    out$front <- extra$expr[named & extra$context == "front-matter"]
    out$cap <- extra$expr[named & extra$context == "caption" & extra$resolver == "filter"]
  }
  # the names of one file's text that go to `auto`
  one <- function(ln) {
    auto <- values_text_names(paste(ln, collapse = "\n"))$code
    cr <- tryCatch(chunk_code_regions(ln), error = function(e) NULL)
    if (length(cr$chs)) {
      tb <- chunk_table(ln, cr)
      for (i in seq_len(nrow(tb))) {
        opt <- if (tb$code_line[i] > tb$open[i]) ln[tb$open[i]:(tb$code_line[i] - 1L)] else ln[tb$open[i]]
        code <- if (tolower(tb$engine[i]) %in% c("python", "julia")) tb$code[[i]] else character()
        auto <- c(auto, values_text_names(paste(c(opt, code), collapse = "\n"))$gov)
      }
    }
    auto
  }
  out$auto <- c(out$auto, one(lines))
  for (f in include_walk(path, lines = lines)$files) if (length(f$lines)) out$auto <- c(out$auto, one(f$lines))
  ok <- function(x) { x <- unique(x); x[values_name_ok(x)] }
  lapply(out, ok)
}

# The lists of the file knitr is reading (a child has its own), added to the knit's once.
values_lists <- function(s) {
  path <- if (is_child_knit()) knit_input_path() else if (is.na(s$input_path)) NULL else s$input_path
  if (is.null(path) || path %in% s$list_paths) return(s$lists)
  s$list_paths <- c(s$list_paths, path)
  new <- values_scan_lists(path, s$config, s$files[[path]])
  for (k in c("front", "cap", "auto")) s$lists[[k]] <- union(s$lists[[k]], new[[k]])
  s$lists
}

# Whether the hooks publish by themselves: only where R reads the names (NS2).
values_r_names <- function(s) identical(s$config$names_from %||% "r", "r")

# R's list (TR1): front matter, unresolved captions, and what the hooks left for the filter.
values_listed <- function(s) {
  if (!values_r_names(s)) return(character())
  L <- values_lists(s)
  unique(c(L$front, L$cap, s$left))
}

# The values the R session holds for the names of the source before the render (BN11), taken when the knit
# starts.
values_hold <- function(s) {
  if (!values_r_names(s)) return(invisible())
  env <- tryCatch(knitr::knit_global(), error = function(e) NULL)
  if (is.null(env)) return(invisible())
  for (nm in values_lists(s)$auto) {
    lk <- named_lookup(nm, env)
    if (identical(lk$kind, "value")) s$held[nm] <- list(lk$value)
  }
  invisible()
}

# A guest published these names (Python put() or auto(), Julia put or @put): the snapshot of R's binding at
# this moment decides, where the sentence stands, which of R and the guest is the later (BN7, TR3).
values_note_guest <- function(s, nms) {
  env <- tryCatch(knitr::knit_global(), error = function(e) NULL)
  if (is.null(env)) return(invisible())
  for (nm in nms) {
    snap <- named_snapshot(named_lookup(nm, env))
    s$guest_pub[[nm]] <- list(snap = snap)
    s$pub[[nm]] <- list(snap = snap)
  }
  invisible()
}

# Python's auto() changes, fetched at the end of a Python chunk, each with that chunk's snapshot (TR4).
values_take_auto <- function(s) {
  nms <- values_lists(s)$auto
  if (!length(nms)) return(invisible())
  py <- guest_auto_changes(nms)
  if (!length(py)) return(invisible())
  for (nm in names(py)) s$waiting[[nm]] <- py[[nm]]
  values_note_guest(s, names(py))
  invisible()
}

# The records already written as JSON texts (a named list of strings) that Python's put() and Julia's put hand
# over wait for the next block of prose (N70, TR3); in a chunk with `results = "asis"` Julia's are written at
# once.
values_wait_json <- function(s, jsons) {
  label <- tryCatch(knitr::opts_current$get("label"), error = function(e) NULL)
  cell <- if (is.character(label) && length(label) == 1L) label else NULL
  values_note_guest(s, names(jsons))
  if (identical(tryCatch(knitr::opts_current$get("results"), error = function(e) NULL), "asis")) {
    cat("\n", values_fenced(values_json(jsons, cell = cell, run = values_run())), "\n", sep = "")
    return(invisible())
  }
  for (nm in names(jsons)) s$waiting[[nm]] <- jsons[[nm]]
  s$waiting_cell <- cell %||% s$waiting_cell
  invisible()
}

# The text of the block to write now (TR2): each name on R's list that R binds, or binds to a function, and that
# is not what its latest publication by anyone saw; and the guests' waiting records, where R's own record is
# not the later. NULL when there is none.
values_pending <- function(s) {
  nms <- values_listed(s)
  if (!length(nms) && !length(s$waiting)) return(NULL)
  env <- knitr::knit_global()
  fresh <- list()
  for (nm in nms) {
    lk <- named_lookup(nm, env)
    # R does not publish a function: the name is the filter's (G6)
    if (!identical(lk$kind, "value")) next
    snap <- named_snapshot(lk)
    last <- s$pub[[nm]]
    if (!is.null(last) && identical(last$snap, snap)) next
    s$pub[[nm]] <- list(snap = snap)
    fresh[[nm]] <- values_record(lk$value)$json
  }
  put <- s$waiting
  if (!length(fresh) && !length(put)) return(NULL)
  # R's record differs from the guest's snapshot, so it is the later (TR3)
  recs <- c(fresh, put[setdiff(names(put), names(fresh))])
  cell <- if (length(put)) s$waiting_cell else NULL
  s$waiting <- list()
  s$waiting_cell <- NULL
  values_fenced(values_json(recs, cell = cell))
}

# The `text` hook's block for the prose `x`, or NULL. Pieces of white space are not
# prose, so they wait.
values_pending_for <- function(s, x) {
  if (!nzchar(trimws(paste(as.character(x), collapse = "")))) return(NULL)
  values_pending(s)
}

# The `document` hook: what is left, at the end.
values_append <- function(s, x) {
  blk <- values_pending(s)
  if (is.null(blk) || !length(x)) return(x)
  n <- length(x)
  last <- x[n]
  x[n] <- paste0(last, if (nzchar(last) && !endsWith(last, "\n")) "\n", "\n", blk)
  x
}

# The end of the document (BN11, M3): a name R read above the code that sets it, from a value the session held
# before the render, which the document later assigned a new value, is a "no value" failure at the construct.
values_stale <- function(s) {
  if (!length(s$noted)) return(invisible())
  env <- tryCatch(knitr::knit_global(), error = function(e) NULL)
  if (is.null(env)) return(invisible())
  for (nm in names(s$noted)) {
    lk <- named_lookup(nm, env)
    if (identical(lk$kind, "value") && identical(lk$value, s$held[[nm]])) next
    n <- s$noted[[nm]]
    add_failure(s, "no value", file = n$file, line = n$line, chunk = n$chunk, expr = n$expr,
                detail = sprintf(paste0("`%s` was read above the code that sets it in this render, from a value the R ",
                                        "session held before the render began (rule 1.12.12)."), nm),
                hint = paste0("Render in a fresh R session, as quarto render and the Knit button do, or move the ",
                              "sentence below the code that sets it."))
  }
  s$noted <- list()
  invisible()
}
