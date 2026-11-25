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
  amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = " ", times = "×",
  minus = "−", infin = "∞", plusmn = "±", deg = "°", middot = "·",
  ndash = "–", mdash = "—", hellip = "…", micro = "µ")

PLAIN_SUP <- c("0" = "⁰", "1" = "¹", "2" = "²", "3" = "³", "4" = "⁴",
               "5" = "⁵", "6" = "⁶", "7" = "⁷", "8" = "⁸", "9" = "⁹",
               "+" = "⁺", "-" = "⁻", "−" = "⁻", "=" = "⁼",
               "(" = "⁽", ")" = "⁾", "n" = "ⁿ", "i" = "ⁱ")
PLAIN_SUB <- c("0" = "₀", "1" = "₁", "2" = "₂", "3" = "₃", "4" = "₄",
               "5" = "₅", "6" = "₆", "7" = "₇", "8" = "₈", "9" = "₉",
               "+" = "₊", "-" = "₋", "−" = "₋", "=" = "₌",
               "(" = "₍", ")" = "₎")

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
  is_ws <- function(c) !is.na(c) && c %in% c(" ", "\t", "\n", "\r", " ", " ")
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
      if (nchar(content) >= 2L && startsWith(content, " ") && endsWith(content, " ") &&
          nzchar(trimws(content, whitespace = " "))) {
        content <- substr(content, 2L, nchar(content) - 1L)
      }
      add(plain_run("code", text = content))
      i <- end + 1L
      next
    }
    # PL3 math
    if (c == "$") {
      if (at(i + 1L) %in% "$") {
        j <- plain_find_str(ch, i + 2L, "$$")
        if (!is.na(j)) {
          add(plain_run("math", text = paste(ch[i:(j + 1L)], collapse = "")))
          i <- j + 2L
          next
        }
      } else if (!is.na(at(i + 1L)) && !is_ws(at(i + 1L))) {
        j <- i + 1L
        while (j <= n && ch[j] != "$") j <- j + if (ch[j] == "\\") 2L else 1L
        if (j <= n && !is_ws(at(j - 1L)) && !grepl("[0-9]", at(j + 1L) %||% "")) {
          add(plain_run("math", text = paste(ch[i:j], collapse = "")))
          i <- j + 1L
          next
        }
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
        if (ch[j] == c) {
          ok <- TRUE
          break
        }
        j <- j + 1L
      }
      if (ok && j > i + 1L) {
        add(plain_run(if (c == "^") "sup" else "sub", kids = plain_read_chars(ch[(i + 1L):(j - 1L)])))
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
        j <- i + k
        close <- NA_integer_
        while (j <= n) {
          d <- ch[j]
          if (d == "\\" && j < n) {
            j <- j + 2L
            next
          }
          if (d == c) {
            m <- plain_run_len(ch, j, c)
            if (m == k && j > i + k && !is_ws(at(j - 1L)) &&
                (c == "*" || !is_alnum(at(j + m)))) {
              close <- j
              break
            }
            j <- j + m
            next
          }
          j <- j + 1L
        }
        if (!is.na(close)) {
          kids <- plain_read_chars(ch[(i + k):(close - 1L)])
          add(plain_run(if (k == 2L) "strong" else "em", kids = kids))
          i <- close + k
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
