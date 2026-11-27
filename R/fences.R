# ---- the one fence finder (A18) ----------------------------------------------------------------------------

# Every reading of a document's fences, chunks and metadata blocks comes from here, so the lints, the scan
# and the front-matter reader see the same document. The fences are found in the order a knitr document is
# processed (the A18 ruling, amended 27 Nov):
#
# 1. the executable chunks, over the whole text, as knitr finds them (knitr_chunks()): knitr swaps each one
#    for its output before Pandoc reads anything, so a chunk is a chunk inside an HTML comment, inside a
#    plain fence, at any indent and behind any `>` markers;
# 2. in the text outside the chunks, the plain fences as CommonMark (and Pandoc) reads them, the HTML
#    comments that hide them and the metadata blocks (plain_blocks()).
#
# `doc_fences(lines)` gives both: `fences`, a data frame with a row per fence (chunks and plain ones, by
# their opening line): `open`, `close` (the closer, or the last line of an unclosed fence: line n, or the
# last line of the quote or list item an unclosed fence was opened in), `info` (the text after the fence
# characters), `chunk`, `closed`, and for a chunk its `engine` and `header` (the options after the engine);
# and `meta`, the metadata blocks' `open` and `close`. A chunk opened inside a plain fence is a row of its
# own inside that fence's rows.
doc_fences <- function(lines) doc_memo("doc_fences", lines, doc_fences_)

doc_fences_ <- function(lines) {
  n <- length(lines)
  ch <- knitr_chunks(lines)
  inchunk <- logical(n)
  if (nrow(ch)) inchunk[sequence(ch$close - ch$open + 1L, ch$open)] <- TRUE
  pb <- plain_blocks(lines, inchunk)
  f <- rbind(ch, pb$fences)
  f <- f[order(f$open), , drop = FALSE]
  rownames(f) <- NULL
  list(fences = f, meta = pb$meta)
}

fence_rows <- function(open = integer(), close = integer(), info = character(), chunk = logical(),
                       closed = logical(), engine = character(), header = character()) {
  data.frame(open = as.integer(open), close = as.integer(close), info = info, chunk = chunk,
             closed = closed, engine = engine, header = header, stringsAsFactors = FALSE)
}

# The text after a fence line's fence characters, trimmed: a fence's info string.
fence_info <- function(x) trimws(sub("^[ \t>]*(`{3,}|~{3,})", "", x))

# knitr's end pattern (`knitr::all_patterns$md`); the begin pattern is KNITR_CHUNK_BEGIN (scan.R).
KNITR_CHUNK_END <- "^[\\t >]*```+\\s*$"

# ---- pass 1: the chunks, as knitr finds them -------------------------------------------------------------

# The chunks of `lines` as knitr 1.51 divides a document (knitr:::group_indices()): a chunk opens at a line
# that matches its begin pattern and closes at the first line after it of its end pattern that repeats the
# opener's prefix exactly (the same indent, `>` markers and backticks). A line of the end pattern that does
# not repeat it is code when the exact closer comes later (knitr reads on to it); with no exact closer to
# come, knitr stops with an error, and the line is read as the closer, since it is knitr's end pattern. A
# chunk opened on line 1 has no prefix (knitr keeps none for it), so any line of the end pattern closes it.
# A begin line inside a chunk that repeats the prefix starts a new chunk, and the one before ends on the
# line above, unclosed. An unclosed chunk runs to line n. A `~~~` line is neither a begin nor an end.
knitr_chunks <- function(lines) {
  n <- length(lines)
  cand <- which(grepl("```", lines, fixed = TRUE))
  if (!length(cand)) return(fence_rows())
  x <- lines[cand]
  isb <- grepl(KNITR_CHUNK_BEGIN, x, perl = TRUE)
  if (!any(isb)) return(fence_rows())
  ise <- !isb & grepl(KNITR_CHUNK_END, x, perl = TRUE)
  keep <- isb | ise
  cand <- cand[keep]
  isb <- isb[keep]
  # the opener's prefix (knitr's `pattern.end` without its regex): what an exact closer repeats
  prefix <- function(l) sub("^([\t >]*`+).*$", "\\1", l)
  exact_end <- function(l, p) startsWith(l, p) & grepl("^\\s*$", substring(l, nchar(p) + 1L), perl = TRUE)
  # is the line `i` (of the end pattern, not exact) code, because knitr reads on to a later exact closer?
  reads_on <- function(t, p) {
    i <- cand[t]
    later <- cand[-seq_len(t)][!isb[-seq_len(t)]]
    e <- later[exact_end(lines[later], p)][1L]
    if (is.na(e)) return(FALSE)
    if (e == i + 1L) return(TRUE)
    btw <- lines[(i + 1L):(e - 1L)]
    !any(startsWith(btw, p) & grepl("^`*\\{", substring(btw, nchar(p) + 1L)))
  }
  open <- close <- integer()
  closed <- logical()
  cur <- NA_integer_
  p <- NA_character_
  for (t in seq_along(cand)) {
    i <- cand[t]
    l <- lines[i]
    if (is.na(cur)) {
      if (isb[t]) {
        cur <- i
        p <- if (i == 1L) NA_character_ else prefix(l)
      }
      next
    }
    if (isb[t]) {
      # a begin line that repeats the prefix starts a new chunk (on line 1 knitr has no prefix and stops)
      if (is.na(p) || startsWith(l, paste0(p, "{"))) {
        open <- c(open, cur)
        close <- c(close, i - 1L)
        closed <- c(closed, FALSE)
        cur <- i
      }
      next
    }
    if (!is.na(p) && !exact_end(l, p) && reads_on(t, p)) next
    open <- c(open, cur)
    close <- c(close, i)
    closed <- c(closed, TRUE)
    cur <- NA_integer_
  }
  if (!is.na(cur)) {
    open <- c(open, cur)
    close <- c(close, n)
    closed <- c(closed, FALSE)
  }
  m <- regmatches(lines[open], regexec(KNITR_CHUNK_BEGIN, lines[open], perl = TRUE))
  spec <- vapply(m, function(z) z[2L], "")
  engine <- sub("[ ,].*$", "", spec)
  fence_rows(open, close, fence_info(lines[open]), rep(TRUE, length(open)), closed, engine,
             substring(spec, nchar(engine) + 1L))
}

# ---- pass 2: plain fences, comments and metadata blocks, as CommonMark reads them --------------------------

# A fence line read as CommonMark reads it: `depth` (the number of block-quote markers), `indent` (the
# columns before the fence characters: inside the quote when it is quoted, a tab to the next stop of 4),
# `fch` and `flen` (the fence character and the length of the run), `info` and `ok` (the line is a fence
# line at all). NA rows where it is not.
FENCE_LINE_RE <- "^( {0,3})((?:> ?(?: {0,3}(?=>))?)*)( *)(`{3,}|~{3,})(.*)$"

parse_fence_lines <- function(x) {
  x <- expand_lead_tabs(x)
  m <- regmatches(x, regexec(FENCE_LINE_RE, x, perl = TRUE))
  ok <- lengths(m) == 6L
  g <- function(k) vapply(m, function(z) if (length(z) == 6L) z[k] else NA_character_, "")
  q <- g(3L)
  depth <- nchar(gsub("[^>]", "", q))
  indent <- ifelse(depth > 0L, nchar(g(4L)), nchar(g(2L)) + nchar(g(4L)))
  run <- g(5L)
  data.frame(ok = ok, depth = depth, indent = indent, fch = substr(run, 1L, 1L), flen = nchar(run),
             info = g(6L), stringsAsFactors = FALSE)
}

# `x` with the tabs in its leading white space and `>` markers expanded to the next stop of 4.
expand_lead_tabs <- function(x) {
  t <- which(grepl("^[ >]*\t", x))
  for (i in t) {
    lead <- regmatches(x[i], regexpr("^[ \t>]*", x[i]))
    out <- ""
    for (ch in strsplit(lead, "", fixed = TRUE)[[1L]]) {
      out <- paste0(out, if (ch == "\t") strrep(" ", 4L - nchar(out) %% 4L) else ch)
    }
    x[i] <- paste0(out, substring(x[i], nchar(lead) + 1L))
  }
  x
}

# The number of block-quote markers a line starts with, and its indent (a tab to the next stop of 4).
quote_depth <- function(l) {
  q <- regmatches(l, regexpr("^ {0,3}(?:> ?(?: {0,3}(?=>))?)*", l, perl = TRUE))
  nchar(gsub("[^>]", "", q))
}
lead_width <- function(l) nchar(regmatches(l, regexpr("^ *", expand_lead_tabs(l))))

# The content column of the list item a line `k` indented `ind` (4 or more) columns sits in, or NA: the
# nearest item above whose content starts at most 3 columns to the left of it, through blank lines and
# lines that may belong to the item. A top-level block above (a line at column 0 after a blank line) ends
# the search: then the line is indented code, or a paragraph's.
list_item_col <- function(lines, k, ind) {
  item_re <- "^( *)([-+*]|[0-9]{1,9}[.)])( {1,4})(?=\\S)"
  blank <- function(j) !nzchar(trim_ws(lines[j]))
  j <- k - 1L
  while (j >= 1L) {
    if (blank(j)) {
      j <- j - 1L
      next
    }
    l <- expand_lead_tabs(lines[j])
    m <- regmatches(l, regexec(item_re, l, perl = TRUE))[[1L]]
    if (length(m)) {
      c0 <- nchar(m[1L])
      if (ind >= c0 && ind <= c0 + 3L) return(c0)
      if (!nzchar(m[2L])) return(NA_integer_)
    } else if (lead_width(l) == 0L && (j == 1L || blank(j - 1L))) {
      return(NA_integer_)
    }
    j <- j - 1L
  }
  NA_integer_
}

# The plain fences, the HTML comments and the metadata blocks of `lines`, read in one pass over the lines
# outside the chunks (`inchunk`), by CommonMark's rules as Pandoc applies them:
# - a fence is 3 or more backticks or tildes, indented at most 3 spaces (inside its block quote, or inside
#   its list item); a backtick fence whose info string holds a backtick is not a fence;
# - it closes at a line of the same character, at least as long, with only spaces after it, in the same
#   container; a fence opened in a block quote ends with its quote, one in a list item with its item, and
#   a quoted line does not close a fence opened outside a quote; an unclosed fence runs to line n;
# - an HTML comment that starts a line (`<!--`, indented at most 3 spaces) runs to its `-->` and hides the
#   fences and the blocks in it; one that never ends hides nothing;
# - a metadata block opens with a line that is exactly `---` (trailing white space allowed, no indent) at
#   the top of the file (only blank lines above) or after a blank line, followed by a line that is not
#   blank, closes at the next `---` or `...` line, and holds a YAML mapping (rule 2.1.6).
# Fences and blocks inside a fence, a comment or a block are not read.
plain_blocks <- function(lines, inchunk) {
  n <- length(lines)
  fl <- grepl("^[ \t>]*(`{3,}|~{3,})", lines) & !inchunk
  co <- grepl("^ {0,3}<!--", lines) & !inchunk
  hr <- grepl("^---[ \t\r]*$", lines) & !inchunk
  cand <- which(fl | co | hr)
  ends_comment <- which(grepl("-->", lines, fixed = TRUE) & !inchunk)
  fi <- which(fl)
  pf <- parse_fence_lines(lines[fi])
  at <- integer(n)
  at[fi] <- seq_along(fi)
  is_blank <- function(l) !nzchar(trim_ws(l))
  # is fence line `j` a closer of the fence (`ch`, `len`) at quote depth `d` in the container at column `c0`?
  closes <- function(j, ch, len, d, c0) {
    r <- at[j]
    r > 0L && pf$ok[r] && pf$fch[r] == ch && pf$flen[r] >= len && pf$depth[r] == d &&
      grepl("^[ \t\r]*$", pf$info[r]) && pf$indent[r] >= c0 && pf$indent[r] <= c0 + 3L
  }
  # the close line of the fence opened on `k`, and whether a closer closed it
  fence_close <- function(k, r, c0) {
    ch <- pf$fch[r]
    len <- pf$flen[r]
    d <- pf$depth[r]
    if (d == 0L && c0 == 0L) {
      # the common case: only fence lines can close it
      for (s in seq_len(length(fi) - r) + r) {
        if (closes(fi[s], ch, len, 0L, 0L)) return(list(close = fi[s], closed = TRUE))
      }
      return(list(close = n, closed = FALSE))
    }
    j <- k + 1L
    while (j <= n) {
      if (!inchunk[j]) {
        l <- lines[j]
        # a quoted fence ends with its quote, a list item's with its item
        if (d > 0L && quote_depth(l) < d) return(list(close = j - 1L, closed = FALSE))
        if (c0 > 0L && !is_blank(l) && lead_width(l) < c0) return(list(close = j - 1L, closed = FALSE))
        if (fl[j] && closes(j, ch, len, d, c0)) return(list(close = j, closed = TRUE))
      }
      j <- j + 1L
    }
    list(close = n, closed = FALSE)
  }
  f_open <- f_close <- integer()
  f_info <- character()
  f_closed <- logical()
  m_open <- m_close <- integer()
  last <- 0L
  for (k in cand) {
    if (k <= last) next
    if (fl[k]) {
      r <- at[k]
      if (!pf$ok[r]) next
      if (pf$fch[r] == "`" && grepl("`", pf$info[r], fixed = TRUE)) next
      c0 <- 0L
      if (pf$indent[r] > 3L) {
        if (pf$depth[r] > 0L) next
        c0 <- list_item_col(lines, k, pf$indent[r])
        if (is.na(c0)) next
      }
      fc <- fence_close(k, r, c0)
      f_open <- c(f_open, k)
      f_close <- c(f_close, fc$close)
      f_info <- c(f_info, trimws(pf$info[r]))
      f_closed <- c(f_closed, fc$closed)
      last <- fc$close
      next
    }
    l <- lines[k]
    if (co[k]) {
      # the comment ends at the first `-->` after its `<!--`; one that never ends hides nothing
      same <- grepl("-->", sub("^.*?<!--", "", l, perl = TRUE), fixed = TRUE)
      end <- if (same) k else ends_comment[ends_comment > k][1L]
      if (!is.na(end)) last <- end
      next
    }
    if (hr[k] && (k == 1L || is_blank(lines[k - 1L])) && k < n && !is_blank(lines[k + 1L])) {
      j <- k + 1L
      while (j <= n && !grepl("^(---|\\.\\.\\.)[ \t\r]*$", lines[j])) j <- j + 1L
      if (j <= n && is_yaml_mapping(lines[(k + 1L):(j - 1L)])) {
        m_open <- c(m_open, k)
        m_close <- c(m_close, j)
        last <- j
      }
    }
  }
  nf <- length(f_open)
  list(fences = fence_rows(f_open, f_close, f_info, rep(FALSE, nf), f_closed, rep(NA_character_, nf),
                           rep(NA_character_, nf)),
       meta = data.frame(open = m_open, close = m_close))
}

# ---- the views the callers read ----------------------------------------------------------------------------

# All the fenced blocks, chunks and plain fences, whose opening line is not in a metadata block (`inmeta`):
# open and close lines, and the text after the fence.
fence_blocks <- function(lines, inmeta) {
  f <- doc_fences(lines)$fences
  f <- f[!inmeta[f$open], , drop = FALSE]
  data.frame(open = f$open, close = f$close, info = f$info, stringsAsFactors = FALSE)
}

# The last line of a chunk's code (find_chunks()): the line above its closer, or its last line when it has
# none.
chunk_code_end <- function(ch) if (isTRUE(ch$closed)) ch$close - 1L else ch$close
