# The TeX target of the formatters (design 9, rules TX3 to TX8; spec rules 1.4.23, 3.4.11, 4.4.25).
# `target = "markdown"` is the default and today's output; `"tex"` writes the forms a formula holds.
# The markdown path pays one `identical()` for all of this; everything else is here.

TARGETS <- c("markdown", "tex", "plain")

# E100, FT3: `target` is "markdown", "tex" or "plain". Returns TRUE for "tex", FALSE for the other two.
# Anything else is a construct error.
tex_target <- function(target) {
  if (is_string(target)) {
    if (identical(target, "tex")) return(TRUE)
    if (identical(target, "markdown") || identical(target, "plain")) return(FALSE)
    got <- paste0("\"", target, "\"")
  } else {
    got <- "something else"
  }
  construct_error(sprintf("`target` must be \"markdown\", \"tex\" or \"plain\"; got %s.", got))
}

# E101: the classes with no TeX form, and why.
TEX_NO_FORM <- c(
  stats::setNames(rep("it prints words", 7L), c(".word", ".count", ".ord", ".no", ".date", ".a", ".cap")),
  stats::setNames(rep("it is markdown emphasis", 2L), c(".em", ".strong")),
  stats::setNames(rep("it joins items into a phrase or a list", 6L), c(".and", ".or", ".pairs", ".ul", ".ol", ".dl")))

tex_class_check <- function(classes) {
  bad <- classes[classes %in% names(TEX_NO_FORM)]
  if (length(bad)) {
    construct_error(sprintf("`%s` has no TeX form (target = \"tex\"): %s (rule 3.4.11).", bad[1L],
                            TEX_NO_FORM[[bad[1L]]]))
  }
  invisible(classes)
}

# FT4: a text made for TeX reaching a plain result.
tex_in_plain_error <- function() {
  value_error(paste0("This text was formatted for TeX (target = \"tex\") and would print here as plain text. ",
                     "Format the number again, with target = \"plain\" (rule 3.4.11)."))
}

# The result of a formatter under `plain` (FT1): its text, its unit and its unit suffixes read by PL.
plain_finish <- function(out) {
  a <- attributes(out)
  x <- plain_text(as.character(unclass(out)))
  attributes(x) <- a
  if (!is.null(a$unit)) attr(x, "unit") <- plain_text(a$unit)
  if (!is.null(a$unit_suffix)) attr(x, "unit_suffix") <- plain_text(a$unit_suffix)
  attr(x, "target") <- "plain"
  x
}

# E103: a text made for TeX reaching a markdown result.
tex_in_markdown_error <- function() {
  value_error(paste0("This text was formatted for TeX (target = \"tex\") and would print here as markdown. ",
                     "Format the number again, without `target` (rule 3.4.11)."))
}

# ---- TX6: text in math ---------------------------------------------------

TEX_SPECIAL <- c("\\" = "\\backslash", "{" = "\\{", "}" = "\\}", "$" = "\\$", "%" = "\\%", "&" = "\\&",
                 "#" = "\\#", "_" = "\\_", "^" = "\\hat{}", "~" = "\\sim", "<" = "<", ">" = ">", "|" = "|",
                 "\u00a0" = "\\,")

# Maximal runs of ordinary characters go in \text{}; each special character maps singly.
tex_text <- function(s) {
  if (!nzchar(s)) return("")
  ch <- strsplit(s, "")[[1L]]
  out <- character()
  run <- ""
  for (x in ch) {
    if (x %in% names(TEX_SPECIAL)) {
      if (nzchar(run)) out <- c(out, paste0("\\text{", run, "}"))
      run <- ""
      out <- c(out, TEX_SPECIAL[[x]])
    } else {
      run <- paste0(run, x)
    }
  }
  if (nzchar(run)) out <- c(out, paste0("\\text{", run, "}"))
  paste(out, collapse = "")
}

# ---- TX4: the marks ------------------------------------------------------

tex_mark <- function(mark) {
  if (!nzchar(mark)) return("")
  switch(mark,
         "," = "{,}",
         "." = ".",
         " " = , "\u00a0" = , "\u2009" = , "\u202f" = "\\,",
         "'" = , "\u2019" = "\\text{'}",
         "\u00b7" = "{\\cdot}",
         tex_text(mark))
}

# The setting `p_label` under TeX (D72): one ASCII letter, bare or inside one pair of `*` or `_`, is
# the letter; anything else is text.
tex_p_label <- function(label) {
  if (!nzchar(label)) return("")
  if (grepl("^[A-Za-z]$", label)) return(label)
  if (grepl("^([*_])[A-Za-z]\\1$", label)) return(substr(label, 2L, 2L))
  tex_text(label)
}

# The configuration a TeX formatter works from: the minus is `-`, the marks are TeX, `p_label` is TeX.
tex_cfg <- function(cfg) {
  big_raw <- cfg$big_mark %||% ","
  dec_raw <- cfg$decimal_mark %||% "."
  big <- tex_mark(big_raw)
  dec <- tex_mark(dec_raw)
  if (nzchar(dec) && identical(big, dec)) dec <- paste0("\\text{", dec_raw, "}")
  cfg$minus <- "-"
  cfg$big_mark <- big
  cfg$decimal_mark <- dec
  cfg$p_label <- tex_p_label(cfg$p_label %||% "p")
  cfg$tex <- TRUE
  cfg
}

# ---- TX7: units ----------------------------------------------------------

# The markdown a unit prints (a symbol or a name) as TeX. `un` is the unit, named in E102.
unit_md_to_tex <- function(md, un) {
  ch <- strsplit(md, "")[[1L]]
  n <- length(ch)
  # Pieces and the current text run go in preallocated buffers, so the walk is linear in the text:
  # growing a vector or a string a character at a time copied it every time.
  out <- character(2L * n + 1L)
  k <- 0L
  run <- character(n)
  m <- 0L
  # For each `^` or `~`, the position of the next one of its kind (NA when there is none), so finding the
  # closing mark is a lookup, not a scan of the rest of the text.
  next_mark <- rep(NA_integer_, n)
  for (mk in c("^", "~")) {
    pos <- which(ch == mk)
    next_mark[pos] <- c(pos[-1L], NA_integer_)
  }
  inner <- function(s) {
    s <- gsub("\u2212", "-", s, fixed = TRUE)
    x <- strsplit(s, "")[[1L]]
    hit <- match(x, names(TEX_SPECIAL))
    x[!is.na(hit)] <- unname(TEX_SPECIAL)[hit[!is.na(hit)]]
    paste(x, collapse = "")
  }
  i <- 1L
  while (i <= n) {
    c1 <- ch[i]
    lit <- FALSE
    if (c1 == "\\" && i < n) {
      i <- i + 1L
      c1 <- ch[i]
      lit <- TRUE
    }
    piece <- NULL
    if (!lit && c1 %in% c("^", "~")) {
      nxt <- next_mark[i]
      if (is.na(nxt)) {
        piece <- TEX_SPECIAL[[c1]]
      } else {
        piece <- paste0(if (c1 == "^") "^{" else "_{", inner(paste(ch[seq_len(nxt - i - 1L) + i], collapse = "")), "}")
        i <- nxt
      }
    } else if (!lit && c1 %in% c("*", "_", "`", "[", "]")) {
      value_error(sprintf(paste0(
        "The unit `%s` prints as \"%s\", which holds markdown with no TeX form (only ^...^, ~...~ and ",
        "backslash escapes have one). Give it a plain `symbol:` or `name:` under `units:` in _weft.yml ",
        "to use it in math (rule 4.4.25)."), as.character(un), md))
    } else if (!lit && c1 == "\u00b7") {
      piece <- "{\\cdot}"
    } else if (!lit && c1 %in% c("'", "\u2032")) {
      piece <- "{}^{\\prime}"
    } else if (!lit && c1 %in% c("\"", "\u2033")) {
      piece <- "{}^{\\prime\\prime}"
    } else if (c1 %in% names(TEX_SPECIAL)) {
      piece <- TEX_SPECIAL[[c1]]
    } else {
      m <- m + 1L
      run[m] <- c1
    }
    if (!is.null(piece)) {
      if (m > 0L) {
        k <- k + 1L
        out[k] <- paste0("\\text{", paste(run[seq_len(m)], collapse = ""), "}")
        m <- 0L
      }
      k <- k + 1L
      out[k] <- piece
    }
    i <- i + 1L
  }
  if (m > 0L) {
    k <- k + 1L
    out[k] <- paste0("\\text{", paste(run[seq_len(m)], collapse = ""), "}")
  }
  paste(out[seq_len(k)], collapse = "")
}

# What a unit adds to a number under TeX: `\,` or nothing before a symbol, `\ ` before a name; or, for a
# unit written first, the symbol or name and then the space.
unit_affix_tex <- function(un, form, plural, before, word, cfg, lang) {
  md <- if (form == "name") unit_name_text(un, plural, cfg, lang) else unit_symbol_text(un, plural, cfg, lang)
  txt <- unit_md_to_tex(md, un)
  if (before) {
    paste0(txt, if (form == "name") "\\ " else if (word || unit_space(un, cfg)) "\\," else "")
  } else if (form == "name") {
    paste0("\\ ", txt)
  } else {
    paste0(if (unit_space(un, cfg)) "\\," else "", txt)
  }
}
