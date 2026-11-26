# The lints for named values (rules 5.12.1, 5.12.2; N144, N145 of dev/design-6.md): a name used with no
# publisher in sight, and a chunk that publishes where its output is dropped. Both read the document's rows
# and chunk table, which the reader already holds: nothing is read or parsed twice.

# ---- named-unpublished (5.12.1) ----------------------------------------------------------------

# The NAME tokens of a condition (N9): string literals taken out, numbers and reserved words are not names.
cond_names <- function(x) {
  x <- gsub("'[^']*'|\"[^\"]*\"", " ", x)
  m <- gregexpr("(?<![A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_.]*", x, perl = TRUE)[[1L]]
  if (m[1L] < 0L) return(character())
  nm <- regmatches(x, list(m))[[1L]]
  nm[vapply(nm, is_weft_name, NA)]
}

# The names the filter's constructs use, one entry per row: a named value its NAME, a span its governor's
# names. Rows with an error are left to the `construct` lint.
named_uses <- function(rows) {
  # a named value is the filter's or R's to read, and the lint reads both (E2 ST5); a span's governor is read
  # only where the filter resolves the span
  i <- which((rows$kind == "named" | (rows$resolver %in% "filter" & rows$kind %in% c("n", "if", "sign", "list"))) &
               is.na(rows$error))
  nm <- lapply(i, function(k) {
    e <- trim_ws(rows$expr[k])
    switch(rows$kind[k],
           named = e,
           `if` = cond_names(e),
           if (is_weft_name(e)) e else character())
  })
  list(row = rep(i, lengths(nm)), name = unlist(nm, use.names = FALSE) %||% character())
}

# The `weft-values` blocks of a text (N20): the attribute text of the opening fence and the body.
values_blocks <- function(lines) {
  open <- grep("^[ \t]*(`{3,}|~{3,})[ \t]*\\{[^}]*\\.weft-values[^}]*\\}[ \t]*$", lines)
  lapply(open, function(k) {
    fence <- regmatches(lines[k], regexpr("`{3,}|~{3,}", lines[k]))
    close_re <- paste0("^[ \t]*", substr(fence, 1L, 1L), "{", nchar(fence), ",}[ \t]*$")
    rest <- if (k < length(lines)) lines[(k + 1L):length(lines)] else character()
    j <- which(grepl(close_re, rest))[1L]
    list(attrs = lines[k], body = if (is.na(j)) rest else rest[seq_len(j - 1L)])
  })
}

# The names a JSON text of schema 1 publishes, or `character()` when it does not read.
values_keys <- function(text) {
  x <- tryCatch(json_read_text(text), error = function(e) NULL)
  if (!is.list(x) || !is.list(x$values)) return(character())
  names(x$values) %||% character()
}

# TRUE when `p` lies inside `root`, by its text with `.` and `..` folded (the file need not exist).
path_inside <- function(p, root) {
  fold <- function(x) {
    parts <- strsplit(gsub("\\", "/", x, fixed = TRUE), "/", fixed = TRUE)[[1L]]
    out <- character()
    for (q in parts[nzchar(parts) & parts != "."]) {
      if (q == "..") out <- out[-length(out)] else out <- c(out, q)
    }
    out
  }
  r <- fold(root)
  f <- fold(p)
  length(f) > length(r) && identical(f[seq_along(r)], r)
}

# The `file=` of a values block's attributes, in any form of 1.2.2 and decoded (1.2.3), as c(match, value); or
# character().
values_file_attr <- function(attrs) attr_value(attrs, "file")

# `key=value` in an attribute string, the value quoted either way or bare, as c(match, value) with the
# value decoded (1.2.3: `\"`, `\'` and `\|` lose their backslash); or character() when there is no such key.
attr_value <- function(attrs, key) {
  m <- regmatches(attrs, regexec(paste0(key, "[ \t]*=[ \t]*(?:\"((?:[^\"\\\\]|\\\\.)*)\"|'((?:[^'\\\\]|\\\\.)*)'|",
                                        "((?:[^\\s}\"'\\\\]|\\\\\\|)+))"), attrs, perl = TRUE))[[1L]]
  if (!length(m)) return(character())
  v <- m[2:4][nzchar(m[2:4])][1L]
  if (is.na(v)) v <- ""
  c(m[1L], gsub("\\\\([\"'|])", "\\1", v))
}

# What a text publishes or runs, for the search of N144: the code of its executed chunks, the keys of its
# hand-written blocks and of the values files they read, and the same of the files it includes, as Quarto
# expands them (include_walk(): any depth, every path against the document's folder). `path` is the
# document's. A values file is read relative to the folder of the file that names it (`dir`).
named_sources <- function(lines, chunks, path, root) {
  out <- named_sources_one(lines, chunks, dirname(path), root)
  read <- function(p) tryCatch(read_source_lines(p), weft_encoding_error = function(e) NULL)
  for (f in include_walk(path, lines = lines, read = read)$files) {
    if (!length(f$lines)) next
    ich <- chunk_table(f$lines, chunk_code_regions(f$lines))
    sub <- named_sources_one(f$lines, ich, dirname(f$path), root)
    out$code <- c(out$code, sub$code)
    out$keys <- c(out$keys, sub$keys)
  }
  out
}

named_sources_one <- function(lines, chunks, dir, root) {
  out <- list(code = character(), keys = character())
  if (nrow(chunks)) {
    run <- chunks$eval %in% TRUE
    out$code <- unlist(chunks$code[run], use.names = FALSE) %||% character()
  }
  for (b in values_blocks(lines)) {
    f <- values_file_attr(b$attrs[1L])
    if (length(f)) {
      p <- if (startsWith(f[2L], "/")) file.path(root, substring(f[2L], 2L)) else file.path(dir, f[2L])
      # the filter refuses a values file outside the project root (E32): so does the lint
      txt <- if (path_inside(p, root) && utils::file_test("-f", p)) read_source_text_or_null(p)
      if (!is.null(txt)) out$keys <- c(out$keys, values_keys(txt))
    } else {
      out$keys <- c(out$keys, values_keys(paste(b$body, collapse = "\n")))
    }
  }
  out
}

lint_named_unpublished <- function(src, ctx) {
  r <- src$rows
  if (!nrow(r) || !any(r$kind == "named" | (r$resolver %in% "filter" & r$kind %in% c("n", "if", "sign", "list")))) {
    return(new_findings())
  }
  use <- named_uses(r)
  if (!length(use$name)) return(new_findings())
  first <- !duplicated(use$name)
  nm <- use$name[first]
  row <- use$row[first]
  found <- named_sources(src$lines, src$chunks, src$path, ctx$root)
  code <- paste(found$code, collapse = "\n")
  mentioned <- vapply(nm, function(x) {
    x %in% found$keys || (grepl(x, code, fixed = TRUE) &&
      grepl(paste0("(?<![A-Za-z0-9_.])", gsub(".", "\\.", x, fixed = TRUE), "(?![A-Za-z0-9_])"), code,
            perl = TRUE))
  }, NA)
  if (all(mentioned)) return(new_findings())
  nm <- nm[!mentioned]
  row <- row[!mentioned]
  # in a knitr document whose names are R's, an R chunk can set the name (E2 ST5)
  knitr_r <- dl_knitr_doc(src) && !(dl_names_from(src) %in% c("python", "julia"))
  finding_at(src, r$fstart[row], r$fend[row], "named-unpublished", nm,
             sprintf(if (knitr_r) {
               paste0("`%s` is used by name but no chunk of this document mentions it; set it in an R chunk, or ",
                      "publish it with put() or @put (rule 5.12.1).")
             } else {
               paste0("`%s` is used by name but no chunk of this document mentions it; publish it with put() or ",
                      "@put (rule 5.12.1).")
             }, nm),
             paste0("Set it in code in this document: an R chunk under knitr, put(name=...) in Python, ",
                    "@put name in Julia, or a values file."),
             context = r$context[row])
}

# The setting `names_from` of a source: the document's `weft:` key over the configuration (E2 NS1).
dl_names_from <- function(src) {
  fw <- src$front$weft
  v <- if (is.list(fw)) fw$names_from else NULL
  if (is.null(v)) v <- src$cfg$names_from
  if (is.character(v) && length(v) == 1L) v else NA_character_
}

# ---- string-markup (5.12.3) -------------------------------------------------------------------------

# The first construct of `val`, read as prose, that is a named value or a span with an n, if, sign or list
# key, and not inside a `.weft-literal`: its text as written, or NA.
markup_construct <- function(val, config) {
  r <- tryCatch(scan_rows(val, config = config), error = function(e) NULL)
  if (is.null(r) || !nrow(r)) return(NA_character_)
  lit <- function(k) {
    while (!is.na(k)) {
      if (r$kind[k] == "literal") return(TRUE)
      k <- r$parent[k]
    }
    FALSE
  }
  for (k in order(r$start)) {
    if (r$kind[k] %in% c("named", "n", "if", "sign", "list") && !lit(k)) return(substr(val, r$start[k], r$end[k]))
  }
  NA_character_
}

lint_string_markup <- function(src, ctx) {
  ch <- src$chunks
  if (!nrow(ch) || !dl_knitr_doc(src) || dl_names_from(src) %in% c("python", "julia")) return(new_findings())
  cr <- src$code_regions %||% chunk_code_regions(src$lines)
  out <- list()
  for (k in seq_len(nrow(ch))) {
    if (!identical(tolower(ch$engine[k]), "r") || !(ch$eval[k] %in% TRUE)) next
    code <- ch$code[[k]]
    if (!any(grepl("`{", code, fixed = TRUE) | grepl("[", code, fixed = TRUE))) next
    # the string constants of the chunk's code not inside the argument weft() reads, nor names
    lit <- chunk_literals(cr$body[[k]], "other")
    for (i in seq_len(nrow(lit))) {
      con <- markup_construct(lit$value[i], src$cfg)
      if (is.na(con)) next
      out[[length(out) + 1L]] <- finding_at(
        src, lit$start[i] - 1, lit$start[i] + nchar(lit$raw[i]), "string-markup", con,
        sprintf(paste0("This string holds weft markup (%s) but is not given to weft(), so R does not read its ",
                       "names and the filter has no value for them (rule 5.12.3)."), con),
        paste0("Give the string to weft() and print the object (a chunk that prints a weft object writes its ",
               "markdown), or cat(format(weft(\"...\"), target = \"markdown\"))."),
        context = "chunk")
    }
  }
  bind_findings(out)
}

# ---- publish-hidden (5.12.2) ---------------------------------------------------------------------

# The option that hides a chunk's output, as `include: false`, or NULL.
hidden_option <- function(opts) {
  for (nm in c("include", "output")) {
    v <- opts[[nm]]
    if (!is.null(v) && falsy(yaml_scalar_text(sub("^!expr[ \t]*", "", v)))) return(paste0(nm, ": false"))
  }
  NULL
}

# The lines of N59's kind that call `put` (and `auto`): a line whose first non-blank character is not `#`.
PUT_RE <- c(python = "(?<![A-Za-z0-9_.])(?:weft\\.)?put\\(",
            julia = "(?<![A-Za-z0-9_.])(?:Weft\\.)?(?:@put\\b|put\\()")
AUTO_RE <- "(?<![A-Za-z0-9_.])(?:weft\\.)?auto\\("

code_calls <- function(code, re) {
  code <- code[!grepl("^[ \t]*#", code)]
  any(grepl(re, code, perl = TRUE))
}

# The names of `names` that a Python cell assigns at the start of a line (`n = 1`, `n += 1`, `n: int = 1`).
assigned_names <- function(code, names) {
  code <- code[!grepl("^[ \t]*#", code)]
  if (!length(names) || !length(code)) return(character())
  hit <- vapply(names, function(x) {
    grepl(paste0("^[ \t]*", gsub(".", "\\.", x, fixed = TRUE),
                 "[ \t]*(?::[^=]*)?(?:\\*\\*|//|>>|<<|[-+*/%@&|^])?=(?!=)"), code, perl = TRUE)
  }, logical(length(code)))
  names[colSums(matrix(hit, nrow = length(code))) > 0L]
}

lint_publish_hidden <- function(src, ctx) {
  ch <- src$chunks
  if (!nrow(ch)) return(new_findings())
  eng <- tolower(ch$engine)
  cand <- which(eng %in% c("python", "julia") & ch$eval %in% TRUE)
  if (!length(cand) || dl_knitr_doc(src)) return(new_findings())
  out <- list()
  # a document that calls auto() in an executed Python chunk, and the names its prose uses (from the rows
  # the scanner already holds); both are looked up only when a hidden Python chunk is met
  auto_doc <- NULL
  used <- NULL
  for (k in cand) {
    opt <- hidden_option(ch$options[[k]])
    if (is.null(opt)) next
    code <- ch$code[[k]]
    s <- src$line_start[ch$open[k]]
    e <- s + nchar(src$lines[ch$open[k]]) - 1
    if (code_calls(code, PUT_RE[[eng[k]]])) {
      out[[length(out) + 1L]] <- finding_at(
        src, s, e, "publish-hidden", ch$label[k],
        sprintf(paste0("chunk `%s` has %s, so what it publishes never reaches the document; publish in a chunk ",
                       "that shows its output, with echo: false if the code should not show (rule 5.12.2)."),
                ch$label[k], opt),
        "Use echo: false to hide the code, not include: false or output: false.", context = "chunk")
    }
    if (identical(eng[k], "python") && !code_calls(code, PUT_RE[["python"]])) {
      if (is.null(auto_doc)) {
        py <- cand[eng[cand] == "python"]
        auto_doc <- any(vapply(py, function(j) code_calls(ch$code[[j]], AUTO_RE), NA))
        used <- if (auto_doc) unique(named_uses(src$rows)$name) else character()
      }
      hit <- if (auto_doc) assigned_names(code, used) else character()
      if (length(hit)) {
        out[[length(out) + 1L]] <- finding_at(
          src, s, e, "publish-hidden", ch$label[k],
          sprintf(paste0("chunk `%s` has %s and assigns `%s`, which the text uses; auto() publishes a name when it ",
                         "changes, but a hidden cell's output is dropped, so the text keeps the value from an ",
                         "earlier cell (rule 5.12.2)."), ch$label[k], opt, hit[1L]),
          "Assign the name in a chunk that shows its output, with echo: false if the code should not show.",
          context = "chunk")
      }
    }
    if (identical(eng[k], "python") && code_calls(code, AUTO_RE)) {
      out[[length(out) + 1L]] <- finding_at(
        src, s, e, "publish-hidden-auto", ch$label[k],
        sprintf(paste0("chunk `%s` calls auto() and has %s, so the names it sets are not published ",
                       "(rule 5.12.2)."), ch$label[k], opt),
        "Call auto() in a chunk that shows its output.", context = "chunk", spec = "5.12.2", tier = 2L)
    }
  }
  bind_findings(out)
}
