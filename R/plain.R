# The plain reading (rules 1.4.24, PL1 to PL11 of dev/design-e1.md): markdown text read by one
# reader into runs, and a renderer that turns runs into plain text. Package E3's ANSI target is a
# second renderer over the same runs.
#
# A run is a list with `type` and, by type:
#   text, code, math  `text`
#   em, strong, span  `kids` (span also `attrs`, the block as written)
#   sup, sub          `kids`

PLAIN_SPECIAL <- c("\\", "`", "$", "<", "&", "^", "~", "*", "_", "[")
PLAIN_SPECIAL_RE <- "[\\\\`$<&^~*_\\[]"

PLAIN_PUNCT <- strsplit("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~", "")[[1L]]

PLAIN_ENTITIES <- c(
  amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = "\u00A0", times = "\u00D7",
  minus = "\u2212", infin = "\u221E", plusmn = "\u00B1", deg = "\u00B0", middot = "\u00B7",
  ndash = "\u2013", mdash = "\u2014", hellip = "\u2026", micro = "\u00B5")

PLAIN_SUP <- c("0" = "\u2070", "1" = "\u00B9", "2" = "\u00B2", "3" = "\u00B3", "4" = "\u2074",
               "5" = "\u2075", "6" = "\u2076", "7" = "\u2077", "8" = "\u2078", "9" = "\u2079",
               "+" = "\u207A", "-" = "\u207B", "\u2212" = "\u207B", "=" = "\u207C",
               "(" = "\u207D", ")" = "\u207E", "n" = "\u207F", "i" = "\u2071")
PLAIN_SUB <- c("0" = "\u2080", "1" = "\u2081", "2" = "\u2082", "3" = "\u2083", "4" = "\u2084",
               "5" = "\u2085", "6" = "\u2086", "7" = "\u2087", "8" = "\u2088", "9" = "\u2089",
               "+" = "\u208A", "-" = "\u208B", "\u2212" = "\u208B", "=" = "\u208C",
               "(" = "\u208D", ")" = "\u208E")

# The plain text of markdown `x`, element by element (an NA stays NA). A string with none of the
# characters any rule starts on is returned as it is.
plain_text <- function(x) {
  if (!length(x)) return(x)
  x <- as.character(x)
  hit <- !is.na(x) & grepl(PLAIN_SPECIAL_RE, x, perl = TRUE)
  for (i in which(hit)) x[i] <- plain_render(plain_read(x[i]))
  x
}

# ---- the reader --------------------------------------------------------------------------------

plain_run <- function(type, ...) c(list(type = type), list(...))

# The runs of one markdown string.
plain_read <- function(s) {
  ch <- strsplit(s, "", fixed = TRUE)[[1L]]
  plain_read_chars(ch)
}

plain_read_chars <- function(ch) {
  n <- length(ch)
  out <- list()
  buf <- character()
  flush <- function() {
    if (length(buf)) {
      out[[length(out) + 1L]] <<- plain_run("text", text = paste(buf, collapse = ""))
      buf <<- character()
    }
  }
  add <- function(run) {
    flush()
    out[[length(out) + 1L]] <<- run
  }
  text <- function(x) buf <<- c(buf, x)
  is_ws <- function(c) !is.na(c) && c %in% c(" ", "\t", "\n", "\r", "\u00A0", "\u2009")
  is_alnum <- function(c) !is.na(c) && grepl("[[:alnum:]]", c)
  at <- function(j) if (j >= 1L && j <= n) ch[j] else NA_character_
  sp <- ch %in% PLAIN_SPECIAL
  i <- 1L
  while (i <= n) {
    if (!sp[i]) {
      nxt <- which(sp[i:n])[1L]
      j <- if (is.na(nxt)) n + 1L else i + nxt - 1L
      text(ch[i:(j - 1L)])
      i <- j
      next
    }
    c <- ch[i]
    # PL1 escape
    if (c == "\\") {
      d <- at(i + 1L)
      if (!is.na(d) && d %in% PLAIN_PUNCT) {
        text(d)
        i <- i + 2L
      } else if (!is.na(d) && d == "\n") {
        text("\n")
        i <- i + 2L
      } else {
        text("\\")
        i <- i + 1L
      }
      next
    }
    # PL2 code span
    if (c == "`") {
      k <- plain_run_len(ch, i, "`")
      j <- plain_find_run(ch, i + k, "`", k)
      if (is.na(j)) {
        text(rep("`", k))
        i <- i + k
        next
      }
      content <- if (j > i + k) paste(ch[(i + k):(j - 1L)], collapse = "") else ""
      end <- j + k - 1L
      if (at(end + 1L) %in% "{") {
        e <- plain_block_end(ch, end + 1L)
        if (!is.na(e)) {
          text(ch[i:e])
          i <- e + 1L
          next
        }
      }
      if (nzchar(trimws(content, whitespace = " "))) {
        content <- trimws(content, whitespace = " ")
      }
      add(plain_run("code", text = content))
      i <- end + 1L
      next
    }
    # PL3 math
    if (c == "$") {
      e <- plain_math_end(ch, i)
      if (!is.na(e)) {
        add(plain_run("math", text = paste(ch[i:e], collapse = "")))
        i <- e + 1L
        next
      }
      text("$")
      i <- i + 1L
      next
    }
    if (c == "<") {
      # PL4 comment
      if (plain_starts(ch, i, "<!--")) {
        j <- plain_find_str(ch, i + 4L, "-->")
        if (!is.na(j)) {
          i <- j + 3L
          next
        }
      }
      # PL5 sup and sub
      done <- FALSE
      for (tag in c("sup", "sub")) {
        open <- paste0("<", tag, ">")
        if (plain_starts(ch, i, open)) {
          close <- paste0("</", tag, ">")
          j <- plain_find_str(ch, i + nchar(open), close)
          if (!is.na(j)) {
            inner <- if (j > i + nchar(open)) ch[(i + nchar(open)):(j - 1L)] else character()
            add(plain_run(tag, kids = plain_read_chars(inner)))
            i <- j + nchar(close)
            done <- TRUE
            break
          }
        }
      }
      if (done) next
      text("<")
      i <- i + 1L
      next
    }
    # PL6 entity
    if (c == "&") {
      j <- i + 1L
      while (j <= n && j - i <= 12L && ch[j] != ";" && grepl("[#[:alnum:]]", ch[j])) j <- j + 1L
      if (j <= n && ch[j] == ";" && j > i + 1L) {
        body <- paste(ch[(i + 1L):(j - 1L)], collapse = "")
        r <- NA_character_
        if (grepl("^#[0-9]+$", body)) {
          r <- plain_codepoint(as.integer(substring(body, 2L)))
        } else if (grepl("^#[xX][0-9a-fA-F]+$", body)) {
          r <- plain_codepoint(strtoi(substring(body, 3L), 16L))
        } else if (body %in% names(PLAIN_ENTITIES)) {
          r <- PLAIN_ENTITIES[[body]]
        }
        if (!is.na(r)) {
          text(r)
          i <- j + 1L
          next
        }
      }
      text("&")
      i <- i + 1L
      next
    }
    # PL7 superscript and subscript
    if (c == "^" || c == "~") {
      if (c == "~" && at(i + 1L) %in% "~") {
        k <- plain_run_len(ch, i, "~")
        text(rep("~", k))
        i <- i + k
        next
      }
      j <- i + 1L
      ok <- FALSE
      while (j <= n) {
        if (ch[j] == "\\" && j < n) {
          j <- j + 2L
          next
        }
        if (ch[j] %in% c(" ", "\t", "\n")) break
        if (ch[j] == "`") {
          j <- plain_skip_code(ch, j)
          next
        }
        if (ch[j] == "$") {
          e <- plain_math_end(ch, j)
          if (!is.na(e)) {
            j <- e + 1L
            next
          }
        }
        if (ch[j] == c) {
          ok <- TRUE
          break
        }
        j <- j + 1L
      }
      if (ok && j > i + 1L) {
        # Pandoc: a backslash-space in a script is a no-break space
        inner <- ch[(i + 1L):(j - 1L)]
        w <- which(inner[-length(inner)] == "\\" & inner[-1L] == " ")
        if (length(w)) {
          inner[w] <- "\u00A0"
          inner <- inner[-(w + 1L)]
        }
        add(plain_run(if (c == "^") "sup" else "sub", kids = plain_read_chars(inner)))
        i <- j + 1L
      } else {
        text(c)
        i <- i + 1L
      }
      next
    }
    # PL8 emphasis
    if (c == "*" || c == "_") {
      k <- plain_run_len(ch, i, c)
      after <- at(i + k)
      before <- at(i - 1L)
      opens <- k <= 3L && !is.na(after) && !is_ws(after) &&
        (c == "*" || !is_alnum(before))
      if (opens) {
        ev <- plain_emph_close(ch, i, k, c)
        if (length(ev)) {
          if (length(ev) == 1L) {
            kids <- plain_read_chars(ch[(i + k):(ev[[1L]][1L] - 1L)])
            run <- if (k == 1L) {
              plain_run("em", kids = kids)
            } else if (k == 2L) {
              plain_run("strong", kids = kids)
            } else {
              plain_run("strong", kids = list(plain_run("em", kids = kids)))
            }
            end <- ev[[1L]][1L] + ev[[1L]][2L] - 1L
          } else {
            # a run of three closed in two steps: the inner emphasis first
            inner_kids <- plain_read_chars(ch[(i + k):(ev[[1L]][1L] - 1L)])
            inner <- plain_run(if (ev[[1L]][2L] == 1L) "em" else "strong", kids = inner_kids)
            rest_from <- ev[[1L]][1L] + ev[[1L]][2L]
            rest <- if (ev[[2L]][1L] > rest_from) {
              plain_read_chars(ch[rest_from:(ev[[2L]][1L] - 1L)])
            } else {
              list()
            }
            run <- plain_run(if (ev[[2L]][2L] == 1L) "em" else "strong",
                             kids = c(list(inner), rest))
            end <- ev[[2L]][1L] + ev[[2L]][2L] - 1L
          }
          add(run)
          i <- end + 1L
          next
        }
      }
      text(rep(c, k))
      i <- i + k
      next
    }
    # PL9 span
    if (c == "[") {
      j <- plain_bracket_end(ch, i)
      if (!is.na(j) && at(j + 1L) %in% "{") {
        e <- plain_block_end(ch, j + 1L)
        if (!is.na(e)) {
          inner <- if (j > i + 1L) ch[(i + 1L):(j - 1L)] else character()
          add(plain_run("span", kids = plain_read_chars(inner), attrs = paste(ch[(j + 1L):e], collapse = "")))
          i <- e + 1L
          next
        }
      }
      text("[")
      i <- i + 1L
      next
    }
    text(c)
    i <- i + 1L
  }
  flush()
  out
}

# The index just past a code span opening at `j` (or past the backticks when it has no closer).
plain_skip_code <- function(ch, j) {
  k <- plain_run_len(ch, j, "`")
  e <- plain_find_run(ch, j + k, "`", k)
  if (is.na(e)) j + k else e + k
}

# The index of the `$` that ends the math opening at `i`, or NA (PL3).
plain_math_end <- function(ch, i) {
  n <- length(ch)
  is_ws <- function(c) !is.na(c) && c %in% c(" ", "\t", "\n", "\r", "\u00A0", "\u2009")
  nx <- if (i < n) ch[i + 1L] else NA_character_
  if (!is.na(nx) && nx == "$") {
    j <- plain_find_str(ch, i + 2L, "$$")
    return(if (is.na(j)) NA_integer_ else j + 1L)
  }
  if (is.na(nx) || is_ws(nx)) return(NA_integer_)
  j <- i + 1L
  while (j <= n && ch[j] != "$") j <- j + if (ch[j] == "\\") 2L else 1L
  if (j <= n && !is_ws(ch[j - 1L]) && !(j < n && grepl("[0-9]", ch[j + 1L]))) j else NA_integer_
}

# The closing run(s) of the emphasis opened by the run of `k` copies of `c` at `i`, as a list of
# c(start, length): one entry, or two when a run of three closes as an inner and an outer emphasis.
# Follows Pandoc: a closing run first closes any emphasis opened inside, and a run longer than what
# is needed closes an inner and an outer emphasis together. Code spans and math are opaque.
# Returns an empty list when there is no closer.
plain_emph_close <- function(ch, i, k, c) {
  n <- length(ch)
  is_ws <- function(x) !is.na(x) && x %in% c(" ", "\t", "\n", "\r", "\u00A0", "\u2009")
  is_alnum <- function(x) !is.na(x) && grepl("[[:alnum:]]", x)
  at <- function(j) if (j >= 1L && j <= n) ch[j] else NA_character_
  need <- k
  stack <- integer()
  events <- list()
  j <- i + k
  while (j <= n) {
    d <- ch[j]
    if (d == "\\" && j < n) {
      j <- j + 2L
      next
    }
    if (d == "`") {
      j <- plain_skip_code(ch, j)
      next
    }
    if (d == "$") {
      e <- plain_math_end(ch, j)
      j <- if (is.na(e)) j + 1L else e + 1L
      next
    }
    if (d != c) {
      j <- j + 1L
      next
    }
    m <- plain_run_len(ch, j, c)
    before <- at(j - 1L)
    after <- at(j + m)
    can_close <- !is_ws(before) && (c == "*" || !is_alnum(after))
    can_open <- !is.na(after) && !is_ws(after) && (c == "*" || !is_alnum(before))
    rem <- m
    if (can_close) {
      while (rem > 0L && length(stack)) {
        take <- min(rem, stack[length(stack)])
        stack[length(stack)] <- stack[length(stack)] - take
        rem <- rem - take
        if (stack[length(stack)] == 0L) stack <- stack[-length(stack)]
      }
      if (rem > 0L) {
        t <- min(rem, need)
        if (t == need || (k == 3L && need == 3L && t < 3L)) {
          events[[length(events) + 1L]] <- c(j + m - rem, t)
          need <- need - t
          if (need == 0L) return(events)
          j <- j + m
          next
        }
      }
    } else if (can_open) {
      stack <- c(stack, m)
    }
    j <- j + m
  }
  list()
}

plain_codepoint <- function(cp) {
  if (is.na(cp) || cp < 1L || cp > 0x10FFFFL || (cp >= 0xD800L && cp <= 0xDFFFL)) return(NA_character_)
  intToUtf8(cp)
}

plain_starts <- function(ch, i, str) {
  w <- strsplit(str, "", fixed = TRUE)[[1L]]
  i + length(w) - 1L <= length(ch) && identical(ch[i:(i + length(w) - 1L)], w)
}

# The index of the first character of `str` at or after `from`, or NA.
plain_find_str <- function(ch, from, str) {
  w <- strsplit(str, "", fixed = TRUE)[[1L]]
  n <- length(ch)
  m <- length(w)
  j <- from
  while (j + m - 1L <= n) {
    if (identical(ch[j:(j + m - 1L)], w)) return(j)
    j <- j + 1L
  }
  NA_integer_
}

plain_run_len <- function(ch, i, c) {
  k <- 0L
  while (i + k <= length(ch) && ch[i + k] == c) k <- k + 1L
  k
}

# The start of the next run of exactly `k` copies of `c`, from `from`, or NA.
plain_find_run <- function(ch, from, c, k) {
  n <- length(ch)
  j <- from
  while (j <= n) {
    if (ch[j] == c) {
      m <- plain_run_len(ch, j, c)
      if (m == k) return(j)
      j <- j + m
    } else {
      j <- j + 1L
    }
  }
  NA_integer_
}

# The `}` that closes the attribute block opening at `i`, or NA. A quoted value may hold `}`.
plain_block_end <- function(ch, i) {
  n <- length(ch)
  j <- i + 1L
  while (j <= n) {
    d <- ch[j]
    if (d == "}") return(j)
    if (d == "=" && j < n && ch[j + 1L] %in% c("\"", "'")) {
      q <- ch[j + 1L]
      j <- j + 2L
      while (j <= n && ch[j] != q) j <- j + if (ch[j] == "\\") 2L else 1L
      if (j > n) return(NA_integer_)
    }
    j <- j + 1L
  }
  NA_integer_
}

# The `]` that closes the `[` at `i`, skipping escapes, code spans and nested brackets, or NA.
plain_bracket_end <- function(ch, i) {
  n <- length(ch)
  depth <- 0L
  j <- i
  while (j <= n) {
    d <- ch[j]
    if (d == "\\") {
      j <- j + 2L
      next
    }
    if (d == "`") {
      k <- plain_run_len(ch, j, "`")
      e <- plain_find_run(ch, j + k, "`", k)
      j <- if (is.na(e)) j + k else e + k
      next
    }
    if (d == "[") depth <- depth + 1L
    if (d == "]") {
      depth <- depth - 1L
      if (depth == 0L) return(j)
    }
    j <- j + 1L
  }
  NA_integer_
}

# ---- the renderer ------------------------------------------------------------------------------

plain_render <- function(runs) {
  paste(vapply(runs, plain_render_run, ""), collapse = "")
}

plain_render_run <- function(r) {
  switch(
    r$type,
    text = , code = , math = r$text,
    em = , strong = , span = plain_render(r$kids),
    sup = plain_script(plain_render(r$kids), PLAIN_SUP, "^"),
    sub = plain_script(plain_render(r$kids), PLAIN_SUB, "_"))
}

plain_script <- function(x, map, open) {
  ch <- strsplit(x, "", fixed = TRUE)[[1L]]
  if (length(ch) && all(ch %in% names(map))) return(paste(map[ch], collapse = ""))
  paste0(open, "(", x, ")")
}

# ---- the ANSI renderer (E3, C1 and C2) -----------------------------------------------------------

# The ANSI rendering of runs: the plain rendering with font styles added. The style functions are
# cli's, so the caller sets `cli.num_colors` to the count its sink decided (D4).
ansi_render <- function(runs) {
  paste(vapply(runs, ansi_render_run, ""), collapse = "")
}

ansi_marker <- function(s) {
  m <- gregexpr("(?s)<<weft: .*?>>", s, perl = TRUE)[[1L]]
  if (m[[1L]] == -1L) return(s)
  len <- attr(m, "match.length")
  out <- character()
  pos <- 1L
  for (k in seq_along(m)) {
    if (m[[k]] > pos) out <- c(out, substr(s, pos, m[[k]] - 1L))
    out <- c(out, as.character(cli::style_bold(cli::col_red(substr(s, m[[k]], m[[k]] + len[[k]] - 1L)))))
    pos <- m[[k]] + len[[k]]
  }
  if (pos <= nchar(s)) out <- c(out, substr(s, pos, nchar(s)))
  paste(out, collapse = "")
}

ansi_render_run <- function(r) {
  switch(
    r$type,
    text = ansi_marker(r$text),
    code = r$text,
    math = ansi_marker(r$text),
    em = ansi_styled(cli::style_italic, r$kids),
    strong = ansi_styled(cli::style_bold, r$kids),
    span = ansi_render(r$kids),
    sup = ansi_script(r, PLAIN_SUP, "^"),
    sub = ansi_script(r, PLAIN_SUB, "_"))
}

# An empty styled run writes nothing.
ansi_styled <- function(style, kids) {
  inner <- ansi_render(kids)
  if (!nzchar(inner)) return("")
  as.character(style(inner))
}

# D8: the choice between Unicode characters and `^( )` is made on the plain content.
ansi_script <- function(r, map, open) {
  p <- plain_render(r$kids)
  ch <- strsplit(p, "", fixed = TRUE)[[1L]]
  if (length(ch) && all(ch %in% names(map))) return(paste(map[ch], collapse = ""))
  paste0(open, "(", ansi_render(r$kids), ")")
}

# The ANSI rendering of a `weft` object with `colors` colours (names kept, NA as "NA"). With one
# colour, or for an element that is not the plain reading of its markdown (C4), the plain text.
# With `breaks`, a line break in the markdown's reading may stand as a space in the element (cli
# makes that change before `cli_format()`), and the rendering has the space.
weft_ansi <- function(x, colors, breaks = FALSE) {
  p <- weft_plain(x)
  na <- is.na(p)
  p[na] <- "NA"
  if (!length(p) || colors <= 1L) return(p)
  md <- attr(x, "markdown")
  if (is.null(md) || length(md) != length(p)) md <- unname(p)
  old <- options(cli.num_colors = colors)
  on.exit(options(old), add = TRUE)
  nl <- function(s) if (breaks) gsub("\n", " ", s, fixed = TRUE) else s
  read <- function(s) {
    if (grepl(PLAIN_SPECIAL_RE, s, perl = TRUE)) plain_read(s) else list(plain_run("text", text = s))
  }
  for (i in seq_along(p)) {
    if (na[[i]] || is.na(md[[i]])) next
    m <- md[[i]]
    runs <- read(m)
    if (!identical(nl(p[[i]]), nl(plain_render(runs)))) {
      # changed by a function that kept the attributes (WS10): its markdown is its plain text
      if (identical(p[[i]], m)) next
      runs <- read(p[[i]])
      if (!identical(p[[i]], plain_render(runs))) next
    }
    p[[i]] <- nl(ansi_render(runs))
  }
  p
}
