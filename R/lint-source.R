# The source reader for the static lints (design-3 L9-L12): one document as
# text, rows (the scanner's, with file offsets), a prose mask, regions,
# blocks, executed chunks and metadata. Nothing here runs document code.

# ---- offsets -------------------------------------------------------------------

# The 1-based line of each file offset (NA stays NA).
src_line_of <- function(src, pos) findInterval(pos, src$line_start)

# The 1-based column, in characters, of each file offset.
src_col_of <- function(src, pos) {
  l <- findInterval(pos, src$line_start)
  as.integer(pos - src$line_start[pmax(l, 1L)] + 1)
}

# Pieces of a text by character offset: `substring(text, start, stop)`. For a text with non-ASCII
# characters substring() walks the string from its start for every piece, so a document's worth of
# pieces is quadratic. The cutter splits such a text into characters once and cuts from those.
text_cutter <- function(text) {
  if (nchar(text, "bytes") == nchar(text)) return(function(start, stop) substring(text, start, stop))
  chars <- strsplit(text, "")[[1L]]
  function(start, stop) {
    if (!length(start) || !length(stop)) return(character())
    k <- max(length(start), length(stop))
    start <- pmax(rep_len(start, k), 1L)
    stop <- pmin(rep_len(stop, k), length(chars))
    vapply(seq_len(k), function(i) {
      if (is.na(start[i]) || is.na(stop[i])) NA_character_
      else if (start[i] > stop[i]) ""
      else paste(chars[start[i]:stop[i]], collapse = "")
    }, "")
  }
}

# The same for a source's own text; the cutter is kept on the source, so it goes with it.
src_substr <- function(src, start, stop) {
  if (is.null(src$cache)) return(substring(src$text, start, stop))
  if (is.null(src$cache$cut)) src$cache$cut <- text_cutter(src$text)
  src$cache$cut(start, stop)
}

# Logical vector of length n, TRUE inside any [starts[i], ends[i]].
mark_ranges <- function(n, starts, ends) {
  ok <- !is.na(starts) & !is.na(ends) & ends >= starts
  starts <- pmax(starts[ok], 1)
  ends <- pmin(ends[ok], n)
  if (!length(starts) || n == 0L) return(rep(FALSE, n))
  d <- tabulate(starts, n + 1L) - tabulate(ends + 1L, n + 1L)
  cumsum(d)[seq_len(n)] > 0
}

# The matches of `pat` in `x` as start, end and capture starts, in characters. On a text with
# multi-byte characters R turns every match's byte offset into a character offset from the start of
# the string, so a document's worth of matches is quadratic. Where the pattern's meaning does not
# depend on character units (see byte_pattern_ok()) and the text is valid UTF-8, the match runs on
# bytes and one map from byte to character, kept for the last text, turns the offsets back.
gmatch <- function(pat, x) {
  cmap <- if (nchar(x, "bytes") > nchar(x) && byte_pattern_ok(pat, x)) byte_char_map(x)
  m <- gregexpr(pat, x, perl = TRUE, useBytes = !is.null(cmap))[[1L]]
  if (m[1L] == -1L) return(list(s = integer(), e = integer(), cs = NULL))
  ml <- attr(m, "match.length")
  s <- as.integer(m)
  cs <- attr(m, "capture.start")
  if (is.null(cmap)) return(list(s = s, e = s + ml - 1L, cs = cs))
  # the end of a match is the character that holds its last byte; an empty match ends before its start
  e <- cmap[pmax(s + ml - 1L, 1L)]
  e[ml == 0L] <- cmap[s[ml == 0L]] - 1L
  if (!is.null(cs)) cs[cs > 0L] <- cmap[cs[cs > 0L]]
  list(s = cmap[s], e = as.integer(e), cs = cs)
}

# One map per text, the last one asked for: the character that holds each byte (1-based), with one
# more entry for the position after the last byte (an empty match there).
gmatch_cache <- new.env(parent = emptyenv())
gmatch_shapes <- new.env(parent = emptyenv())
byte_char_map <- function(x) {
  if (identical(gmatch_cache$text, x)) return(gmatch_cache$map)
  cp <- utf8ToInt(x)
  width <- 1L + (cp >= 0x80L) + (cp >= 0x800L) + (cp >= 0x10000L)
  gmatch_cache$map <- c(rep.int(seq_along(cp), width), length(cp) + 1L)
  gmatch_cache$text <- x
  gmatch_cache$map
}

# Whether `pat` can run on the bytes of `x` and give the offsets of a run on its characters.
# Audited by shape. It cannot when the pattern holds a non-ASCII character, `.`, `\p`, `\P`, `\X`,
# `\R`, `\N`, `\C`, `\h`, `\H`, `\v`, `\V`, `\x` or `\0` (a character is one unit there); and a
# caseless pattern needs a text without the two characters that fold to an ASCII letter (U+017F,
# U+212A). A negated class, a literal, `\s`, `\S`, `\b`, `[[:alnum:]]`, `[[:punct:]]` and a
# lookbehind of one ASCII character take the same bytes as characters, because every byte of a
# multi-byte character falls on the same side of them. The one `.` in P2_PATTERN is the `\S.*$` of
# the reference rule, where `.*` runs to the end of the line in either unit.
byte_pattern_ok <- function(pat, x) {
  ok <- gmatch_shapes[[pat]]
  if (is.null(ok)) {
    ok <- !grepl("[^\\x01-\\x7f]", pat, perl = TRUE, useBytes = TRUE) &&
      !grepl("\\\\[pPXRNChHvVx0]", pat, perl = TRUE)
    if (ok) {
      rest <- gsub("\\S.*$", "", pat, fixed = TRUE)
      rest <- gsub("\\\\.", "x", rest, perl = TRUE)              # an escape is one item
      rest <- gsub("\\[:[a-z]+:\\]", "x", rest, perl = TRUE)     # a POSIX class is one item
      rest <- gsub("\\[\\^?[^]]*\\]", "x", rest, perl = TRUE)    # a class is one item
      ok <- !grepl(".", rest, fixed = TRUE)
    }
    assign(pat, ok, envir = gmatch_shapes)
  }
  if (!ok) return(FALSE)
  if (grepl("(?i", pat, fixed = TRUE) && grepl("[\u017f\u212a]", x, perl = TRUE)) return(FALSE)
  validUTF8(x) && Encoding(x) %in% c("UTF-8", "unknown") && l10n_info()$`UTF-8`
}

# The first of `groups` that matched, for each match.
match_type <- function(g, groups) {
  if (!length(g$s)) return(character())
  hit <- g$cs[, groups, drop = FALSE] > 0
  vapply(seq_len(nrow(hit)), function(i) groups[which(hit[i, ])[1L]], "")
}

# ---- regions -------------------------------------------------------------------

new_regions <- function(type = character(), start = integer(), end = integer(),
                        row = NA_integer_, name = NA_character_) {
  n <- length(start)
  if (!n) type <- character()
  data.frame(type = rep_len(type, n), start = as.integer(start), end = as.integer(end),
             row = rep_len(as.integer(row), n), name = rep_len(as.character(name), n),
             inner_start = rep(NA_integer_, n), inner_end = rep(NA_integer_, n),
             attr_start = rep(NA_integer_, n), attr_end = rep(NA_integer_, n),
             stringsAsFactors = FALSE)
}

# Add the parsed classes, keys and id of the attribute text `a` as list columns.
with_attrs <- function(r, a) {
  n <- nrow(r)
  r$classes <- vector("list", n)
  r$keys <- vector("list", n)
  r$id <- vector("list", n)
  if (!n) return(r)
  a0 <- gsub("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", "\"\"", a, perl = TRUE)
  ex <- function(pat, grp = 0L) lapply(seq_len(n), function(i) {
    if (is.na(a0[i])) return(character())
    m <- gregexpr(pat, a0[i], perl = TRUE)[[1L]]
    if (m[1L] == -1L) return(character())
    st <- if (grp) attr(m, "capture.start")[, grp] else as.integer(m)
    ln <- if (grp) attr(m, "capture.length")[, grp] else attr(m, "match.length")
    substring(a0[i], st, st + ln - 1L)
  })
  r$classes <- ex("(?<![\\w-])\\.[A-Za-z][\\w.-]*")
  r$keys <- ex("(?<![\\w.#-])([A-Za-z][\\w:-]*)\\s*=", 1L)
  r$id <- ex("#([^\\s\"{}]+)", 1L)
  r
}

# ---- the file -------------------------------------------------------------------

lint_rel_path <- function(path, root) {
  p <- normalizePath(path, winslash = "/", mustWork = FALSE)
  r <- normalizePath(root, winslash = "/", mustWork = FALSE)
  enc2utf8(rel_to(p, r))
}

# All the fenced blocks: open and close lines, and the text after the fence.
fence_blocks <- function(lines, inmeta) {
  n <- length(lines)
  empty <- data.frame(open = integer(), close = integer(), info = character(),
                      stringsAsFactors = FALSE)
  cand <- which(!inmeta & grepl("^[ \t>]*(`{3,}|~{3,})", lines))
  if (!length(cand)) return(empty)
  m <- regmatches(lines[cand], regexec("^[ \t>]*(`{3,}|~{3,})(.*)$", lines[cand]))
  fch <- vapply(m, function(x) substr(x[2L], 1L, 1L), "")
  fln <- vapply(m, function(x) nchar(x[2L]), 1L)
  info <- trimws(vapply(m, function(x) x[3L], ""))
  closer <- grepl("^[ \t>]*(`{3,}|~{3,})[ \t\r]*$", lines[cand])
  open <- integer()
  close <- integer()
  inf <- character()
  last <- 0L
  for (i in seq_along(cand)) {
    k <- cand[i]
    if (k <= last) next
    if (fch[i] == "`" && grepl("`", info[i], fixed = TRUE) && !grepl("^\\{.*\\}$", info[i])) next
    j <- which(closer & cand > k & fch == fch[i] & fln >= fln[i])[1L]
    cl <- if (is.na(j)) n else cand[j]
    open <- c(open, k)
    close <- c(close, cl)
    inf <- c(inf, info[i])
    last <- cl
  }
  data.frame(open = open, close = close, info = inf, stringsAsFactors = FALSE)
}

# YAML read for the lints: `!expr` kept as text, nothing evaluated.
yaml_text <- function(x) {
  tryCatch(yaml_read_text(x), error = function(e) NULL)
}

# ---- chunks ---------------------------------------------------------------------

# One row per chunk of the code regions `cr` (chunk_code_regions()) of `lines`.
chunk_table <- function(lines, cr) {
  n <- length(lines)
  chs <- cr$chs
  cols <- function(f, type) vapply(chs, f, type)
  eval_of <- function(ch) {
    v <- NULL
    for (o in ch$optblk) if (o$name == "eval") v <- static_option_value(o$value, expr = o$form == "expr")
    h <- ch$hdr$opts$eval
    if (is.null(v) && !is.null(h)) v <- static_option_value(h$text, expr = TRUE)
    !(!is.null(v) && falsy(v))
  }
  cache_of <- function(ch) {
    v <- NULL
    for (o in ch$optblk) if (o$name == "cache") v <- static_option_value(o$value, expr = o$form == "expr")
    h <- ch$hdr$opts$cache
    if (is.null(v) && !is.null(h)) v <- static_option_value(h$text, expr = TRUE)
    if (is.null(v)) return(NA)
    if (falsy(v)) FALSE else if (is.logical(v) || is.character(v) && tolower(v) %in% c("true", "yes")) isTRUE(truthy(v)) || NA else NA
  }
  explicit_of <- function(ch) {
    (!is.na(ch$hdr$label) && nzchar(ch$hdr$label)) || any(vapply(ch$optblk, function(o) o$name == "label", NA))
  }
  options_of <- function(ch) {
    o <- lapply(ch$hdr$opts, function(x) x$text)
    for (b in ch$optblk) o[[b$name]] <- b$value
    o
  }
  # the code of a block-quoted chunk is read without its `>` prefix, as the scanner reads it (K20)
  codes <- lapply(cr$body, function(rg) rg$code)
  data.frame(
    open = cols(function(ch) as.integer(ch$open), 0L),
    close = cols(function(ch) as.integer(min(ch$close, n)), 0L),
    engine = cols(function(ch) ch$engine, ""),
    label = cols(function(ch) ch$label, ""),
    explicit = cols(explicit_of, NA),
    eval = cols(eval_of, NA),
    cache = cols(cache_of, NA),
    options = I(lapply(chs, options_of)),
    code = I(codes),
    code_first = vapply(codes, function(x) if (length(x)) x[1L] else NA_character_, ""),
    code_line = cols(function(ch) as.integer(ch$oi$code_first), 0L),
    stringsAsFactors = FALSE)[, c("open", "close", "engine", "label", "explicit", "eval",
                                  "cache", "options", "code", "code_first", "code_line")]
}

# ---- string constants in chunk code -----------------------------------------------

# Rows for the strings given to lookup() and brk() (context "phrase"): `lit` as chunk_literals() gives, `ls`
# the document's line starts.
phrase_rows <- function(lit, chunk_label, file, config, ls) {
  parts <- list()
  for (k in seq_len(nrow(lit))) {
    val <- lit$value[k]
    r <- scan_rows(val, file = file, first_line = lit$line[k], config = config)
    if (!nrow(r)) next
    off <- lit_offsets(lit$raw[k], lit$start[k])
    if (length(off) != nchar(val)) off <- rep(NA_real_, nchar(val))
    r$fstart <- map_offsets(r$start, off)
    r$fend <- map_offsets(r$end, off)
    r$fblock <- map_offsets(r$block_start, off)
    # a row's line is the source line of its first character, as for a weft() string (K1, K10)
    at <- !is.na(r$fstart)
    r$line[at] <- findInterval(r$fstart[at], ls)
    r$context <- "phrase"
    r$chunk <- chunk_label
    r$option <- NA_character_
    parts[[length(parts) + 1L]] <- r
  }
  bind_scan_rows(parts)
}

# ---- the pieces beside the body (L10) ------------------------------------------------

# Returns a data frame: kind (front, caption, weft, phrase), name, start, end
# (file offsets of the characters that are prose), form ("scalar"/"block").
source_pieces <- function(lines, ls, chunks, cr, front_ff) {
  le <- ls + nchar(lines) - 1
  # the pieces so far (`P`) and the last group id given (`gid`), written only by add() and add_weft()
  acc <- new.env(parent = emptyenv())
  acc$P <- list()
  acc$gid <- 0L
  add <- function(kind, name, start, end, by_row = FALSE, grp = NULL) {
    ok <- !is.na(start) & !is.na(end) & end >= start
    if (any(ok)) {
      k <- sum(ok)
      g <- if (by_row) acc$gid + seq_len(k) else if (!is.null(grp)) rep_len(grp, length(ok))[ok] else acc$gid + 1L
      if (is.null(grp)) acc$gid <- acc$gid + (if (by_row) k else 1L)
      acc$P[[length(acc$P) + 1L]] <- data.frame(kind = kind, name = name, start = start[ok],
                                                end = end[ok], grp = rep_len(g, k),
                                                stringsAsFactors = FALSE)
    }
  }
  # the prose of the literals given to weft(): each literal one block, its escapes not prose
  add_weft <- function(lit) {
    if (!nrow(lit)) return(invisible())
    ex <- literal_ranges(lit$start, lit$raw, grepl("^[rR]", lit$token))
    if (!nrow(ex)) return(invisible())
    g0 <- acc$gid
    add("weft", NA_character_, ex$start, ex$end, grp = g0 + ex$idx)
    acc$gid <- g0 + nrow(lit)
  }
  # strip wrapping quotes of a one-line scalar: returns the ranges to keep
  value_range <- function(l, from_col) {
    txt <- substring(lines[l], from_col)
    lead <- nchar(txt) - nchar(sub("^[ \t]+", "", txt))
    body <- sub("[ \t]+$", "", sub("^[ \t]+", "", txt))
    s <- ls[l] + from_col - 1 + lead
    e <- s + nchar(body) - 1
    if (nchar(body) >= 2L && grepl("^([\"']).*\\1$", body)) {
      s <- s + 1
      e <- e - 1
    }
    c(s, e)
  }
  # where the text of each of the lines `r` starts: the line's start, or after a `#|` prefix
  line_start <- function(r) ls[r]
  after_bar <- function(r) ls[r] + attr(regexpr("^[ \t]*#\\|", lines[r]), "match.length")
  # a block value: its lines `first` to `last`, the text of each from `from`
  add_block <- function(kind, name, first, last, from) {
    if (first <= last) {
      r <- first:last
      add(kind, name, from(r), le[r])
    }
  }
  # a scalar value: on line `l` from column `col`, without its quotes, then the lines to `last` that
  # continue it, the text of each from `from`, in its group
  add_scalar <- function(kind, name, l, col, last, from) {
    v <- value_range(l, col)
    g0 <- acc$gid + 1L
    add(kind, name, v[1L], v[2L])
    if (last > l) {
      r <- (l + 1L):last
      add(kind, name, from(r), le[r], grp = g0)
    }
  }
  # front matter
  ff <- front_ff
  for (i in seq_len(nrow(ff))) {
    if (!(ff$field[i] %in% FM_FIELDS)) next
    if (ff$form[i] == "block") {
      add_block("front", ff$field[i], ff$first[i], ff$last[i], line_start)
    } else {
      k <- ff$key[i]
      add_scalar("front", ff$field[i], k, regexpr(":", lines[k], fixed = TRUE) + 1L, ff$last[i], line_start)
    }
  }
  # captions, in executed R chunks
  for (i in seq_along(cr$chs)) {
    ch <- cr$chs[[i]]
    if (!identical(tolower(ch$engine), "r")) next
    for (o in ch$optblk) {
      if (!(o$name %in% setdiff(CAPTION_OPTIONS, "tab.cap")) || o$form == "expr") next
      if (o$form == "block") {
        add_block("caption", o$name, o$first, o$last, after_bar)
      } else if (o$form == "list") {
        for (it in o$items) {
          if (it$form == "block") {
            add_block("caption", o$name, it$first, it$last, after_bar)
          } else {
            col <- attr(regexpr(OPT_ITEM_RE, lines[it$start]), "match.length") + 1L
            add_scalar("caption", o$name, it$start, col, it$last, after_bar)
          }
        }
      } else {
        col <- attr(regexpr(OPT_KEY_RE, lines[o$key]), "match.length") + 1L
        add_scalar("caption", o$name, o$key, col, o$last, after_bar)
      }
    }
    # a weft() string in a computed caption: `!expr`, or a header option such as `fig.cap = weft(...)`
    # (F4, F5); read as the weft() strings of chunk code are, from the document's code regions (A5)
    for (rg in chunk_caption_regions(cr, i)) add_weft(chunk_literals(rg, "weft"))
    # header literals
    for (nm in names(ch$hdr$opts)) {
      if (!(nm %in% setdiff(CAPTION_OPTIONS, "tab.cap"))) next
      if (is.null(ch$hdr$opts[[nm]]$literal)) {
        ex <- tryCatch(parse(text = ch$hdr$opts[[nm]]$text, keep.source = FALSE)[[1L]],
                       error = function(e) NULL)
        okc <- is.call(ex) && identical(ex[[1L]], as.name("c")) && length(ex) > 1L &&
          all(vapply(as.list(ex)[-1L], is.character, NA))
        if (!isTRUE(okc)) next
      }
      qs <- "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'"
      hl <- sub("[ \t\r]+$", "", lines[ch$open])
      mm <- regexpr(paste0(header_opt_re(nm), "c[ \t]*\\("), hl, perl = TRUE)
      if (mm > 0L) {
        st <- mm + attr(mm, "match.length")
        rest <- substring(hl, st)
        sm <- gregexpr(qs, rest, perl = TRUE)[[1L]]
        # stop at the closing paren that is outside any string
        for (k in seq_along(sm)) {
          if (sm[k] < 0L) break
          pre <- substr(rest, 1L, sm[k] - 1L)
          if (grepl(")", gsub(qs, "", pre, perl = TRUE), fixed = TRUE)) break
          b <- st + sm[k] - 1L
          e <- b + attr(sm, "match.length")[k] - 1L
          if (e - b >= 2L) add("caption", nm, ls[ch$open] + b, ls[ch$open] + e - 2L)
        }
        next
      }
      h <- header_literal_at(hl, nm)
      if (!is.null(h)) add("caption", nm, ls[ch$open] + h$start - 1, ls[ch$open] + h$start + nchar(h$raw) - 2)
    }
  }
  # strings: the literals the scan read, from the same code regions (E3)
  for (k in seq_len(nrow(chunks))) {
    if (!identical(tolower(chunks$engine[k]), "r") || isFALSE(chunks$eval[k])) next
    rg <- cr$body[[k]]
    if (!length(rg$code)) next
    add_weft(chunk_literals(rg, "weft"))
    lit <- chunk_literals(rg, "phrase")
    if (nrow(lit)) add("phrase", NA_character_, lit$start, lit$start + nchar(lit$raw) - 1, by_row = TRUE)
  }
  if (!length(acc$P)) {
    return(data.frame(kind = character(), name = character(), start = numeric(), end = numeric(),
                      grp = integer(), stringsAsFactors = FALSE))
  }
  do.call(rbind, acc$P)
}

# ---- the prose mask ------------------------------------------------------------------

NB <- "(?:(?!\\n[ \\t]*\\n)[\\s\\S])"

P2_PATTERN <- paste0(
  "(?m)",
  "(?<com><!--[\\s\\S]*?-->)",
  "|(?<scr><(?:script|style)\\b[\\s\\S]*?</(?:script|style)>)",
  "|(?<cod>(?<![\\\\`])(?<tk>`+)(?!`)", NB, "+?(?<!`)\\k<tk>(?!`))",
  "|(?<me>\\\\begin\\{(?<men>", paste(TEX_MATH_ENVS, collapse = "|"), ")\\*?\\}[\\s\\S]*?\\\\end\\{\\k<men>\\*?\\})",
  "|(?<md>\\$\\$", NB, "+?\\$\\$)",
  "|(?<m1>(?<![\\\\$])\\$(?![\\s$])[^$\\n]+?(?<![\\s\\\\])\\$(?![0-9]))",
  "|(?<m3>\\\\\\(", NB, "*?\\\\\\))",
  "|(?<m4>\\\\\\[", NB, "*?\\\\\\])",
  "|(?<ref>^ {0,3}\\[(?!\\^)[^\\]\\n]+\\]:[ \\t]+\\S.*$)",
  "|(?<sc>\\{\\{<[\\s\\S]*?>\\}\\})",
  "|(?<ent>&(?:#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);)",
  "|(?<tag></?[A-Za-z][^<>]*>)",
  "|(?<url>(?<![A-Za-z0-9@])(?:https?://|ftp://|www\\.)[^\\s<>]*[^\\s<>.,;:!?)\\]'\"*_])",
  "|(?<doi>(?<![0-9A-Za-z.])10\\.[0-9]{4,9}/[^\\s<>]*[^\\s<>.,;:!?)\\]'\"])",
  "|(?<eml>[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,})")
P2_TYPES <- c("com", "scr", "cod", "me", "md", "m1", "m3", "m4", "ref", "sc", "ent", "tag", "url", "doi", "eml")

# a Quarto cross-reference type in any letter case: `@Fig-map` prints as a capitalised "Figure 1"
XREF_PREFIX <- "(?i:fig|tbl|lst|sec|eq|thm|lem|cor|prp|cnj|def|exm|exr|sol|rem)"
KEY_BODY <- "[[:alnum:]_:.#$%&+?<>~/-]*[[:alnum:]_]"

P3_PATTERN <- paste0(
  "(?<cb>\\[[^\\[\\]]*(?<![[:alnum:]])-?@[[:alnum:]_][^\\[\\]]*\\](?!\\{))",
  "|(?<xr2>\\\\@ref\\([^)\\n]*\\))",
  "|(?<xa>\\(\\\\#(?:fig|tab|eq):[^)\\n]*\\))",
  "|(?<cbr>(?<![[:alnum:]_])-?@\\{[^}\\n]*\\})",
  "|(?<xr>(?<![[:alnum:]_])-?@", XREF_PREFIX, "-", KEY_BODY, ")",
  "|(?<ct>(?<![[:alnum:]_])-?@[[:alnum:]_](?:", KEY_BODY, ")?(?:[ \\t]*\\[[^\\[\\]\\n]*\\](?![(\\[{]))?)")

LINK_PATTERN <- paste0(
  "(?<![\\\\])(?<img>!)?\\[(?:(?!\\n[ \\t]*\\n)[^\\[\\]]|\\[[^\\[\\]]*\\])*\\]",
  "(?:\\((?:[^()\\n]|\\([^()\\n]*\\))*\\)|\\[[^\\]\\n]*\\])")

SPAN_PATTERN <- paste0("(?<![\\\\])\\[(?:(?!\\n[ \\t]*\\n)[^\\[\\]]|\\[[^\\[\\]]*\\])*\\]\\{[^{}\\n]*\\}")

# The lines that are indented code (L11): indented four spaces or a tab, after
# a blank line or another such line, and outside a list. `blk` marks the lines
# that are blank or not body (they end a run), `nonbody` the lines of metadata
# and fences, which neither open nor close a list. `mask_prose()` also counts
# the continuation lines of an HTML comment as blank; `indented_code_lines()`
# in lint-code.R does not.
indented_code_flags <- function(wl, blk, nonbody) {
  nl <- length(wl)
  icode <- logical(nl)
  indent4 <- grepl("^( {4,}|\t)", wl) & !blk
  if (!any(indent4)) return(icode)
  marker <- grepl("^[ \t]*([-*+]|[0-9]{1,9}[.)])[ \t]+[^ \t]", wl) & !nonbody
  col0 <- grepl("^[^ \t]", wl) & !nonbody
  inlist <- FALSE
  prevblank <- TRUE
  for (i in seq_len(nl)) {
    if (blk[i]) { prevblank <- TRUE; next }
    if (col0[i] && prevblank) inlist <- FALSE
    if (marker[i]) inlist <- TRUE
    if (indent4[i] && prevblank && !inlist) icode[i] <- TRUE
    else if (indent4[i] && !prevblank && i > 1L && icode[i - 1L]) icode[i] <- TRUE
    prevblank <- FALSE
  }
  icode
}

# the prose mask and the regions that come with it
mask_prose <- function(S) {
  text <- S$text
  n <- nchar(text)
  nl <- length(S$lines)
  empty_regs <- new_regions()
  empty_regs <- with_attrs(empty_regs, character())
  if (n == 0L) return(list(prose = "", regions = empty_regs))
  msk <- new.env(parent = emptyenv())
  msk$chars <- strsplit(text, "")[[1L]]
  at <- text_cutter(text)
  ls <- S$line_start
  lc <- rep.int(seq_len(nl), nchar(S$lines) + 1L)[seq_len(n)]
  # which lines are not body
  nonbody <- S$inmeta | S$infence
  keepv <- !nonbody[lc]
  pc <- S$pieces
  if (nrow(pc)) keepv <- keepv | mark_ranges(n, pc$start, pc$end)
  msk$chars[!keepv & msk$chars != "\n"] <- " "
  msk$regs <- list()
  addreg <- function(type, s, e, name = NA_character_, row = NA_integer_) {
    if (length(s)) msk$regs[[length(msk$regs) + 1L]] <- new_regions(type, s, e, row, name)
  }
  blank <- function(s, e) {
    if (!length(s)) return(invisible())
    m <- mark_ranges(n, s, e) & msk$chars != "\n"
    msk$chars[m] <- " "
    invisible()
  }
  cur <- function() paste(msk$chars, collapse = "")
  line_texts <- function(w) cut_lines(w, nl)
  work <- cur()

  # divs (whole fence lines)
  wl <- line_texts(work)
  divl <- which(grepl("^[ \t]*:{3,}", wl) & !nonbody)
  if (length(divl)) {
    blank(ls[divl], ls[divl] + nchar(S$lines[divl]) - 1L)
    # regions: from the opening line to the matching close
    dd <- S$lines[divl]
    cnt <- nchar(sub("^[ \t]*(:+).*$", "\\1", dd))
    closes <- grepl("^[ \t]*:{3,}[ \t]*$", dd)
    stack <- integer()
    ds <- integer(); de <- integer(); dn <- character(); did <- character()
    for (i in seq_along(divl)) {
      if (!closes[i] || !length(stack)) {
        stack <- c(stack, i)
      } else {
        j <- stack[length(stack)]
        stack <- stack[-length(stack)]
        ds <- c(ds, divl[j]); de <- c(de, divl[i])
        did <- c(did, sub("^[^{]*", "", dd[j]))
      }
    }
    for (j in stack) {
      ds <- c(ds, divl[j]); de <- c(de, nl); did <- c(did, sub("^[^{]*", "", dd[j]))
    }
    if (length(ds)) {
      r <- new_regions("div", ls[ds], ls[de] + nchar(S$lines[de]) - 1L, name = did)
      msk$regs[[length(msk$regs) + 1L]] <- r
      S$divs <- data.frame(open = ds, close = de, id = did, stringsAsFactors = FALSE)
    }
    work <- cur()
  }

  # indented code
  wl <- S$lines
  blk <- !grepl("[^ \t]", wl) | nonbody
  # a line that continues an HTML comment is the comment's, whatever its indentation (review 3, S3)
  gc <- gmatch("<!--[\\s\\S]*?-->", work)
  if (length(gc$s)) {
    for (q in seq_along(gc$s)) {
      lc <- findInterval(c(gc$s[q], gc$e[q]), ls)
      if (lc[2L] > lc[1L]) blk[(lc[1L] + 1L):lc[2L]] <- TRUE
    }
  }
  il <- which(indented_code_flags(wl, blk, nonbody))
  if (length(il)) {
    blank(ls[il], ls[il] + nchar(S$lines[il]) - 1L)
    work <- cur()
  }

  # opaque inline constructs
  g <- gmatch(P2_PATTERN, work)
  if (length(g$s)) {
    ty <- match_type(g, P2_TYPES)
    cod <- ty == "cod"
    md <- ty %in% c("me", "md", "m1", "m3", "m4")
    s <- g$s; e <- g$e
    blank(s, e)
    code_attr <- list()
    if (any(cod | ty == "md")) {
      idx <- which(cod | ty == "md")
      sp <- if (any(ty[idx] == "md")) "^[ \t]*\\{[^{}\\n]*\\}" else "^\\{[^{}\\n]*\\}"
      for (kk in c("cod", "md")) {
        ii <- which(ty == kk)
        if (!length(ii)) next
        pat <- if (kk == "md") "^[ \t]*\\{[^{}\\n]*\\}" else "^\\{[^{}\\n]*\\}"
        sub_txt <- at(e[ii] + 1L, e[ii] + 300L)
        m <- regexpr(pat, sub_txt, perl = TRUE)
        has <- which(m > 0L)
        if (length(has)) {
          p1 <- regexpr("{", sub_txt[has], fixed = TRUE)
          as <- e[ii][has] + as.integer(p1)
          ae <- e[ii][has] + attr(m, "match.length")[has]
          blank(as, ae)
          if (kk == "cod") {
            r <- new_regions("code_attr", s[ii][has], ae)
            r$attr_start <- as; r$attr_end <- ae
            r <- with_attrs(r, at(as, ae))
            code_attr[[length(code_attr) + 1L]] <- r
          }
        }
      }
    }
    addreg("code", s[cod], e[cod])
    addreg("math", s[md], e[md])
    addreg("refdef", s[ty == "ref"], e[ty == "ref"])
    for (r in code_attr) msk$regs[[length(msk$regs) + 1L]] <- r
    work <- cur()
  }

  # spans, found where code and math are gone
  gs <- gmatch(SPAN_PATTERN, work)
  span_reg <- NULL
  if (length(gs$s)) {
    # the last "]{" opens the attribute block
    ap <- vapply(text_cutter(work)(gs$s, gs$e), function(x) {
      m <- gregexpr("]{", x, fixed = TRUE)[[1L]]
      as.integer(m[length(m)])
    }, 1L)
    as <- gs$s + ap
    r <- new_regions("span", gs$s, gs$e)
    r$inner_start <- gs$s
    r$inner_end <- as - 1L
    r$attr_start <- as
    r$attr_end <- gs$e
    r <- with_attrs(r, at(as, gs$e))
    span_reg <- r
  }

  # weft rows: code and attribute blocks
  rw <- S$rows
  if (nrow(rw)) {
    isv <- rw$kind %in% c("bare", "value", "named")
    blank(ifelse(isv, rw$fstart, rw$fblock), rw$fend)
  }

  # citations and cross-references
  g <- gmatch(P3_PATTERN, work)
  if (length(g$s)) {
    ty <- match_type(g, c("cb", "xr2", "xa", "cbr", "xr", "ct"))
    blank(g$s, g$e)
    isx <- ty %in% c("xr2", "xa", "xr")
    addreg("crossref", g$s[isx], g$e[isx], name = at(g$s, g$e)[isx])
    addreg("citation", g$s[!isx], g$e[!isx], name = at(g$s, g$e)[!isx])
    work <- cur()
  }

  # footnote markers and inline notes
  g <- gmatch("\\[\\^[^\\]\\s]+\\]:?", work)
  if (length(g$s)) {
    blank(g$s, g$e)
    addreg("footnote", g$s, g$e, name = at(g$s, g$e))
    work <- cur()
  }
  inl <- inline_footnotes(work)
  if (!is.null(inl)) {
    blank(c(inl$from, inl$from + 1L, inl$to), c(inl$from, inl$from + 1L, inl$to))
    addreg("footnote", inl$from, inl$to, name = "inline")
    S$inline_notes <- inl
    work <- cur()
  }

  # links and images (regions), then their targets
  gl <- gmatch(LINK_PATTERN, work)
  if (length(gl$s)) {
    isimg <- gl$cs[, "img"] > 0
    addreg("image", gl$s[isimg], gl$e[isimg])
    addreg("link", gl$s[!isimg], gl$e[!isimg])
  }
  # attribute blocks straight after a bracket
  g <- gmatch("(?<=\\])\\{[^{}\\n]*\\}", work)
  blank(g$s, g$e)
  work <- cur()
  g <- gmatch("(?<=\\])(?:\\((?:[^()\\n]|\\([^()\\n]*\\))*\\)|\\[[^\\]\\n]*\\])", work)
  if (length(g$s)) {
    blank(g$s, g$e)
    sub_txt <- at(g$e + 1L, g$e + 300L)
    m <- regexpr("^\\{[^{}\\n]*\\}", sub_txt, perl = TRUE)
    has <- which(m > 0L)
    if (length(has)) blank(g$e[has] + 1L, g$e[has] + attr(m, "match.length")[has])
    work <- cur()
  }
  g <- gmatch("\\{[ \\t]*[#.][^{}\\n]*\\}", work)
  blank(g$s, g$e)
  work <- cur()

  # raw TeX and escapes
  g <- gmatch("\\\\[A-Za-z]+\\*?(?:\\[[^\\]\\n]*\\]|\\{(?:[^{}\\n]|\\{[^{}\\n]*\\})*\\})*", work)
  blank(g$s, g$e)
  g <- gmatch("\\\\(?=[[:punct:]])", cur())
  blank(g$s, g$e)
  work <- cur()

  # line-start markers
  wl <- line_texts(work)
  wb <- !grepl("[^ \t]", wl)
  hit <- function(pat, x = wl) {
    m <- regexpr(pat, x, perl = TRUE)
    ok <- m > 0L
    list(l = which(ok), len = attr(m, "match.length")[ok], s = as.integer(m)[ok])
  }
  blank_hit <- function(h) {
    if (length(h$l)) blank(ls[h$l] + h$s - 1L, ls[h$l] + h$s + h$len - 2L)
  }
  whole <- function(idx) if (length(idx)) blank(ls[idx], ls[idx] + nchar(S$lines[idx]) - 1L)
  prev_nb <- c(FALSE, !wb[-nl])
  tdelim <- which(grepl("\\|", wl) & grepl("^[ \t]*\\|?[ \t]*:?-+:?[ \t]*(\\|[ \t]*:?-+:?[ \t]*)*\\|?[ \t]*$", wl))
  grid <- which(grepl("^[ \t]*\\+[-=:+]+\\+[ \t]*$", wl))
  rule <- which(grepl("^ {0,3}(?:(?:\\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$", wl, perl = TRUE))
  # a setext underline sits under a one-line paragraph; under two lines or more Pandoc reads the
  # dashes as the end of the paragraph (review 3, finding 11)
  under <- grepl("^ {0,3}(?:=+|-+)[ \t]*$", wl) & prev_nb
  prev2_nb <- c(FALSE, FALSE, !wb)[seq_len(nl)]
  setx <- which(under & !prev2_nb)
  rule <- setdiff(rule, which(under & prev2_nb))
  S$structural <- sort(unique(c(tdelim, grid, rule, setx)))
  S$tdelim <- tdelim
  S$setext <- setx
  whole(S$structural)
  work <- cur()
  wl <- line_texts(work)
  wb <- !grepl("[^ \t]", wl)
  blank_hit(hit("^(?:[ \t]{0,3}>[ \t]?)+"))
  wl <- line_texts(cur())
  h <- hit("^[ \t]{0,3}#{1,6}(?:[ \t]+|$)")
  blank_hit(h)
  atxl <- h$l
  S$atx <- atxl
  wl <- line_texts(cur())
  hh <- hit("[ \t]+#+[ \t]*$", wl[atxl])
  # (closing #s of a heading: the hits are relative to atxl)
  if (length(hh$l)) {
    ll <- atxl[hh$l]
    blank(ls[ll] + hh$s - 1L, ls[ll] + hh$s + hh$len - 2L)
  }
  wl <- line_texts(cur())
  bullet <- hit("^[ \t]*[-*+][ \t]+(?:\\[[ xX]\\][ \t]+)?")
  blank_hit(bullet)
  wl <- line_texts(cur())
  wb <- !grepl("[^ \t]", wl)
  numc <- hit("^[ \t]*(?:[0-9]{1,9}[.)]|\\((?:[0-9]{1,2}|@[A-Za-z0-9_-]*)\\))[ \t]+")
  acc <- integer()
  if (length(numc$l)) {
    isitem <- logical(nl)
    isitem[bullet$l] <- TRUE
    ishead <- logical(nl)
    ishead[atxl] <- TRUE
    ok <- logical(length(numc$l))
    for (i in seq_along(numc$l)) {
      l <- numc$l[i]
      ok[i] <- !ishead[l] && (l == 1L || wb[l - 1L] || isitem[l - 1L] || ishead[l - 1L] || nonbody[l - 1L])
      if (ok[i]) isitem[l] <- TRUE
    }
    acc <- numc$l[ok]
    blank_hit(list(l = numc$l[ok], s = numc$s[ok], len = numc$len[ok]))
  }
  S$num_items <- acc
  S$bullets <- bullet$l
  wl <- line_texts(cur())
  blank_hit(hit("^[ \t]{0,3}[:~](?=[ \t])"))

  prose <- cur()
  regions <- do.call(rbind, c(list(empty_regs), lapply(msk$regs, function(r) {
    if (!"classes" %in% names(r)) r <- with_attrs(r, rep(NA_character_, nrow(r)))
    r
  })))
  if (!is.null(span_reg)) regions <- rbind(regions, span_reg)
  list(prose = prose, regions = regions)
}

# ---- blocks ----------------------------------------------------------------------------

build_blocks <- function(S) {
  lines <- S$lines
  nl <- length(lines)
  ls <- S$line_start
  le <- ls + nchar(lines) - 1
  text <- S$text
  n <- nchar(text)
  nonbody <- S$inmeta | S$infence
  dl <- sub("^(?:[ \t]{0,3}>[ \t]?)+", "", lines, perl = TRUE)
  blank <- nonbody | !grepl("[^ \t]", lines)
  lt <- ifelse(blank, "blank", "text")
  prev_blank <- c(TRUE, blank[-nl])
  lt[which(!blank & grepl("^ {0,3}:[ \t]+\\S", dl) & prev_blank & !grepl("^[ \t]*:{3,}", dl))] <- "tcap"
  lt[which(!blank & grepl("^ {0,3}\\[\\^[^\\]\\s]+\\]:", dl, perl = TRUE))] <- "fndef"
  lt[c(S$bullets, S$num_items)] <- "item"
  lt[S$atx] <- "heading"
  # tables
  tbl <- list()
  cell_lines <- integer()
  for (d in S$tdelim) {
    if (d < 2L || blank[d - 1L]) next
    j <- d + 1L
    while (j <= nl && !blank[j]) j <- j + 1L
    rows <- c(d - 1L, if (j > d + 1L) (d + 1L):(j - 1L))
    cell_lines <- c(cell_lines, rows)
    tbl[[length(tbl) + 1L]] <- c(d - 1L, j - 1L)
  }
  gridb <- which(grepl("^[ \t]*\\+[-=:+]+\\+[ \t]*$", lines) & !nonbody)
  if (length(gridb)) {
    # a grid table runs from a border line to the first blank line after
    k <- 1L
    while (k <= length(gridb)) {
      a <- gridb[k]
      j <- a
      while (j <= nl && !blank[j]) j <- j + 1L
      cell_lines <- c(cell_lines, which(seq_len(nl) >= a & seq_len(nl) < j & grepl("^[ \t]*\\|", lines)))
      tbl[[length(tbl) + 1L]] <- c(a, j - 1L)
      k <- k + sum(gridb < j)
    }
  }
  lt[cell_lines] <- "cell"
  lt[S$structural] <- "struct"
  lt[which(!blank & grepl("^[ \t]*:{3,}", lines))] <- "div"
  prevlt <- c("blank", lt[-nl])
  newblk <- lt %in% c("heading", "item", "fndef", "tcap") |
    (lt == "text" & prevlt %in% c("blank", "heading", "struct", "div", "cell"))
  inblk <- lt %in% c("text", "heading", "item", "fndef", "tcap")
  id <- ifelse(inblk, cumsum(newblk), NA_integer_)
  B <- NULL
  if (any(inblk)) {
    first <- tapply(which(inblk), id[inblk], min)
    last <- tapply(which(inblk), id[inblk], max)
    ft <- lt[first]
    type <- c(text = "para", heading = "heading", item = "item", fndef = "footnote",
              tcap = "caption")[ft]
    B <- data.frame(type = unname(type), start = ls[first], end = le[last],
                    line = as.integer(first), end_line = as.integer(last),
                    stringsAsFactors = FALSE)
    for (u in S$setext) {
      k <- which(B$end_line == u - 1L & B$type == "para")
      if (length(k)) B$type[k] <- "heading"
    }
    if (!is.null(S$divs) && nrow(S$divs)) {
      for (i in seq_len(nrow(S$divs))) {
        if (!grepl("#(fig|tbl)-", S$divs$id[i])) next
        k <- which(B$type == "para" & B$line > S$divs$open[i] & B$end_line < S$divs$close[i])
        if (length(k)) B$type[k[length(k)]] <- "caption"
      }
    }
  }
  # cells
  C <- NULL
  if (length(cell_lines)) {
    rw <- S$rows
    protect <- mark_ranges(n, c(rw$fstart, S$regions$start[S$regions$type %in% c("code", "math", "span", "code_attr")]),
                           c(rw$fend, S$regions$end[S$regions$type %in% c("code", "math", "span", "code_attr")]))
    pm <- gregexpr("(?<!\\\\)\\|", text, perl = TRUE)[[1L]]
    pm <- as.integer(pm[pm > 0L])
    pm <- pm[!protect[pm]]
    cl <- sort(unique(cell_lines))
    segs <- list()
    for (l in cl) {
      ps <- pm[pm >= ls[l] & pm <= le[l]]
      a <- c(ls[l], ps + 1L)
      b <- c(ps - 1L, le[l])
      keep <- b >= a
      a <- a[keep]; b <- b[keep]
      if (!length(a)) next
      t <- substring(text, a, b)
      lead <- nchar(t) - nchar(sub("^[ \t]+", "", t))
      trail <- nchar(t) - nchar(sub("[ \t]+$", "", t))
      ok <- lead < nchar(t)
      segs[[length(segs) + 1L]] <- data.frame(type = "cell", start = (a + lead)[ok], end = (b - trail)[ok],
                                              line = l, end_line = l, stringsAsFactors = FALSE)
    }
    if (length(segs)) C <- do.call(rbind, segs)
  }
  # pieces
  Pb <- NULL
  pc <- S$pieces
  if (nrow(pc)) {
    pc$line <- findInterval(pc$start, ls)
    pc <- pc[order(pc$grp, pc$start), , drop = FALSE]
    seg <- cumsum(c(TRUE, pc$grp[-1L] != pc$grp[-nrow(pc)] | pc$line[-1L] - pc$line[-nrow(pc)] > 1L))
    Pb <- do.call(rbind, lapply(split(seq_len(nrow(pc)), seg), function(ix) {
      k <- pc$kind[ix[1L]]
      data.frame(type = c(front = "front-matter", caption = "caption", weft = "weft",
                          phrase = "phrase")[[k]],
                 start = min(pc$start[ix]), end = max(pc$end[ix]),
                 line = min(pc$line[ix]), end_line = findInterval(max(pc$end[ix]), ls),
                 stringsAsFactors = FALSE)
    }))
  }
  Fn <- NULL
  if (!is.null(S$inline_notes)) {
    inl <- S$inline_notes
    Fn <- data.frame(type = "footnote", start = inl$from + 2L, end = inl$to - 1L,
                     line = findInterval(inl$from, ls), end_line = findInterval(inl$to, ls),
                     stringsAsFactors = FALSE)
    Fn <- Fn[Fn$end >= Fn$start, , drop = FALSE]
  }
  all <- do.call(rbind, Filter(Negate(is.null), list(B, C, Pb, Fn)))
  if (is.null(all)) all <- data.frame(type = character(), start = numeric(), end = numeric(),
                                      line = integer(), end_line = integer(), stringsAsFactors = FALSE)
  all <- all[order(all$start, all$end), , drop = FALSE]
  all$start <- as.integer(all$start); all$end <- as.integer(all$end)
  all$line <- as.integer(all$line); all$end_line <- as.integer(all$end_line)
  rownames(all) <- NULL
  tb <- if (length(tbl)) do.call(rbind, tbl) else matrix(integer(), 0, 2)
  list(blocks = all, tables = tb)
}

# ---- reading a document ------------------------------------------------------------------------

# A document's source; `text` is its text when the caller has read it already (lint_open()), `bytes` a
# script's bytes. The document's skeleton is computed once for the read (local_doc_memo()).
read_source <- function(path, root, cfg, bytes = NULL, text = NULL) {
  if (is_script_path(path)) return(read_script_source(path, root, cfg, bytes))
  local_doc_memo()
  rel <- lint_rel_path(path, root)
  ext <- sub("^.*\\.", "", basename(path))
  if (is.null(text)) text <- read_source_text_or_null(path)
  if (is.null(text)) {
    return(structure(list(file = rel, path = path, ext = ext, invalid = TRUE, cfg = cfg, text = "",
                          lines = character(), line_start = numeric()), class = "weft_source"))
  }
  lines <- if (nzchar(text)) strsplit(text, "\n", fixed = TRUE)[[1L]] else character()
  nl <- length(lines)
  ls <- line_starts(lines)
  n <- nchar(text)
  mb <- metadata_blocks(lines)
  inmeta <- logical(nl)
  for (b in seq_len(nrow(mb))) inmeta[mb$open[b]:mb$close[b]] <- TRUE
  fb <- fence_blocks(lines, inmeta)
  infence <- logical(nl)
  for (b in seq_len(nrow(fb))) infence[fb$open[b]:fb$close[b]] <- TRUE
  # the R code of the document, each region parsed once for the scan, the phrases and the pieces (A5, E3)
  cr <- chunk_code_regions(lines)
  chunks <- chunk_table(lines, cr)
  ff <- front_fields(lines)
  # metadata: `meta` is the document's own blocks, at its own lines; the front matter and the front block are
  # read with its includes expanded (rules P4, P5)
  meta <- meta_blocks_yaml(lines, mb)
  xl <- front_source_lines(path, lines)
  front <- if (identical(xl, lines)) merge_front(meta) else doc_front_lines(xl)
  # `lang` as Quarto merges it: the document over the project files (rules P1, P2)
  lang <- quarto_doc_view(path, front)[["lang"]]
  if (!(is.character(lang) && length(lang) == 1L)) lang <- NA_character_
  # rows
  rows <- scan_document(lines, file = rel, config = cfg, project = project_type(path), cr = cr, path = path)
  if (nrow(rows)) {
    ci <- findInterval(rows$line, chunks$open)
    inchunk <- ci > 0L & rows$line <= chunks$close[pmax(ci, 1L)]
    eng_r <- ifelse(inchunk, tolower(chunks$engine[pmax(ci, 1L)]) == "r", TRUE)
    ev <- ifelse(inchunk, chunks$eval[pmax(ci, 1L)], TRUE)
    # a caption construct on another engine's chunk is kept when it carries its error (2.3.5, rule 5.11)
    # (a caption the filter resolves is read whatever the chunk's engine, N140)
    drop <- (rows$context == "weft" & (!eng_r | !ev)) |
      (rows$context == "caption" & !eng_r & is.na(rows$error) & rows$resolver != "filter")
    if (any(drop)) {
      newidx <- cumsum(!drop)
      rows <- rows[!drop, , drop = FALSE]
      rows$parent <- ifelse(is.na(rows$parent), NA_integer_, newidx[rows$parent])
    }
  }
  phr <- list()
  for (k in seq_len(nrow(chunks))) {
    if (!identical(tolower(chunks$engine[k]), "r") || isFALSE(chunks$eval[k])) next
    lit <- chunk_literals(cr$body[[k]], "phrase")
    if (nrow(lit)) phr[[length(phr) + 1L]] <- phrase_rows(lit, chunks$label[k], rel, cfg, ls)
  }
  if (length(phr)) {
    rows <- bind_scan_rows(c(list(rows), phr))
    ord <- order(rows$fstart, seq_len(nrow(rows)), na.last = TRUE)
    rows$parent <- match(rows$parent, ord)
    rows <- rows[ord, , drop = FALSE]
    rownames(rows) <- NULL
  }
  if (nrow(rows)) {
    bad <- is.na(rows$fstart)
    if (any(bad)) {
      rows$fstart[bad] <- ls[pmin(rows$line[bad], nl)]
      rows$fend[bad] <- rows$fstart[bad]
      rows$fblock[bad] <- NA_real_
    }
  }
  pieces <- source_pieces(lines, ls, chunks, cr, ff)
  # the regions are kept for the lints without their parses: a source is cached as it is
  for (rg in c(cr$body, cr$caption)) rm(list = names(rg$memo), envir = rg$memo)
  src <- source_assemble(rel, path, ext, cfg, text, lines, ls, inmeta, infence, pieces, rows, chunks, ff, meta,
                         front, lang)
  src$code_regions <- cr
  src$first_block <- front_block_yaml(xl)
  src
}

# The rest of reading a source, shared by documents and scripts (D1): the regions, the prose mask and the
# blocks over the pieces and rows.
source_assemble <- function(rel, path, ext, cfg, text, lines, ls, inmeta, infence, pieces, rows, chunks, ff,
                            meta, front, lang, script = FALSE) {
  nl <- length(lines)
  S <- new.env(parent = emptyenv())
  S$text <- text; S$lines <- lines; S$line_start <- ls
  S$inmeta <- inmeta; S$infence <- infence; S$pieces <- pieces; S$rows <- rows
  S$divs <- NULL; S$inline_notes <- NULL
  mp <- mask_prose(S)
  regions <- mp$regions
  # regions from the rows, chunks, fields and pieces; add(regions, r) is `regions` with `r` added
  add <- function(regions, r) if (nrow(r)) rbind(regions, with_attrs(r, rep(NA_character_, nrow(r)))) else regions
  if (nrow(rows)) {
    kmap <- c(value = "value", named = "value", bare = "bare", n = "n", `if` = "if", sign = "sign", list = "list",
              cite = "cite_span", literal = "literal", text = "text_span")
    ty <- unname(kmap[rows$kind])
    ok <- !is.na(ty)
    r <- new_regions(ty[ok], rows$fstart[ok], rows$fend[ok], row = which(ok), name = rows$expr[ok])
    regions <- add(regions, r)
    # a row's index on the span it sits in
    sp <- which(regions$type == "span")
    if (length(sp)) regions$row[sp] <- match(regions$start[sp], rows$fstart)
  }
  if (nrow(chunks)) {
    regions <- add(regions, new_regions("chunk", ls[chunks$open], ls[chunks$close] + nchar(lines[chunks$close]) - 1L,
                                        name = chunks$label))
  }
  if (nrow(pieces)) {
    for (k in c("front", "caption", "weft", "phrase")) {
      pk <- pieces[pieces$kind == k, , drop = FALSE]
      if (!nrow(pk)) next
      g <- split(seq_len(nrow(pk)), pk$grp)
      st <- vapply(g, function(ix) min(pk$start[ix]), 1)
      en <- vapply(g, function(ix) max(pk$end[ix]), 1)
      nm <- vapply(g, function(ix) pk$name[ix[1L]], "")
      rtype <- c(front = "yaml_field", caption = "caption", weft = "weft", phrase = "phrase")[[k]]
      regions <- add(regions, new_regions(rtype, st, en, name = nm))
    }
  }
  # text spans: a span with a formatter class and no weft row
  fmt <- c(shipped_classes(), names(cfg$formatters %||% list()))
  sp <- which(regions$type == "span")
  if (length(sp)) {
    isf <- vapply(sp, function(i) any(regions$classes[[i]] %in% fmt) && is.na(regions$row[i]), NA)
    has_text <- regions$start[regions$type == "text_span"]
    isf <- isf & !(regions$start[sp] %in% has_text)
    if (any(isf)) {
      r <- regions[sp[isf], , drop = FALSE]
      r$type <- "text_span"
      regions <- rbind(regions, r)
    }
  }
  S$prose <- mp$prose
  S$regions <- regions
  bb <- build_blocks(S)
  hd <- bb$blocks[bb$blocks$type == "heading", , drop = FALSE]
  if (nrow(hd)) regions <- rbind(regions, with_attrs(new_regions("heading", hd$start, hd$end), rep(NA_character_, nrow(hd))))
  if (nrow(bb$tables)) {
    regions <- rbind(regions, with_attrs(new_regions("table", ls[bb$tables[, 1L]], le_of(lines, ls, bb$tables[, 2L])),
                                         rep(NA_character_, nrow(bb$tables))))
  }
  regions <- regions[order(regions$start, regions$end), , drop = FALSE]
  rownames(regions) <- NULL
  structure(list(
    file = rel, path = path, ext = ext, invalid = FALSE, script = script, cfg = cfg, text = text, lines = lines,
    line_start = ls, lang = lang, rows = rows, prose = mp$prose, regions = regions,
    blocks = bb$blocks, chunks = chunks, meta = meta, front = front, divs = S$divs,
    cache = new.env(parent = emptyenv())), class = "weft_source")
}

# The first metadata block of a source, read as YAML (list() when there is none): where the lints read
# `engine:`, `knitr:` and `jupyter:`, which Quarto honours in that block alone (rule 2.1.6). It is the first
# block of the include-expanded text, so an include on line 1 can supply it (rule P4). Every other key
# comes from the front matter as a whole, `src$front`.
src_first_block <- function(src) src$first_block %||% front_block_yaml(src$lines)

le_of <- function(lines, ls, i) ls[i] + nchar(lines[i]) - 1

# ---- sentences (L12) -----------------------------------------------------------------------------

source_sentences <- function(src) {
  out <- list()
  b <- src$blocks
  lang <- if (is.na(src$lang)) "" else src$lang
  prose_at <- text_cutter(src$prose)
  for (i in seq_len(nrow(b))) {
    t <- src_substr(src, b$start[i], b$end[i])
    pr <- prose_at(b$start[i], b$end[i])
    if (!grepl("[^ \n]", pr)) next
    nc <- nchar(t)
    cuts <- sentence_cuts(t, NULL, lang)$cuts
    cuts <- sort(unique(cuts[cuts > 1L & cuts <= nc]))
    st <- c(1L, cuts)
    en <- c(cuts - 1L, nc)
    seg <- substring(t, st, en)
    # a cut sits after a block marker (`2.`, `(b)`), so the sentence before it would end with that
    # marker: a last line that is only a marker belongs to the next sentence, not this one (CW10)
    tl <- ifelse(grepl("\n", seg, fixed = TRUE), sub("(?s)^.*\n", "", seg, perl = TRUE), "")
    mm <- regexpr(sentence_marker_re, tl, perl = TRUE)
    tail_marker <- nzchar(tl) & mm == 1L & attr(mm, "match.length") == nchar(tl)
    en <- ifelse(tail_marker, en - nchar(tl) - 1L, en)
    seg <- substring(t, st, en)
    mm <- regexpr(sentence_marker_re, seg, perl = TRUE)
    only_marker <- mm == 1L & attr(mm, "match.length") == nchar(seg)
    lead <- nchar(seg) - nchar(sub("^[ \t\n]+", "", seg))
    trail <- nchar(seg) - nchar(sub("[ \t\n]+$", "", seg))
    st2 <- st + lead
    en2 <- en - trail
    pseg <- substring(pr, st2, en2)
    ok <- en2 >= st2 & grepl("[^ \n]", pseg) & !only_marker
    if (!any(ok)) next
    a <- b$start[i] + st2[ok] - 1L
    e <- b$start[i] + en2[ok] - 1L
    out[[length(out) + 1L]] <- data.frame(start = a, end = e, line = src_line_of(src, a),
                                          end_line = src_line_of(src, e), block = i)
  }
  if (!length(out)) {
    return(data.frame(start = integer(), end = integer(), line = integer(), end_line = integer(),
                      block = integer()))
  }
  r <- do.call(rbind, out)
  # in document order: a note's sentences are emitted after the paragraph's but start inside it
  r <- r[order(r$start, -r$end), , drop = FALSE]
  rownames(r) <- NULL
  r
}

# ---- reading a script (D1, C3, C4) -----------------------------------------------------------------

is_script_path <- function(path) grepl("\\.[rR]$", path)

# The bytes of a script as one string, a NUL byte read as a space so that it does not stop a search.
script_bytes_text <- function(bytes) {
  bytes[bytes == as.raw(0L)] <- as.raw(32L)
  rawToChar(bytes)
}

# Whether the bytes of a script hold the ASCII letters `weft` (C3): what decides whether a script that is not
# text is reported (rule 3.11.7).
bytes_mention_weft <- function(bytes) grepl("weft", script_bytes_text(bytes), fixed = TRUE, useBytes = TRUE)

# A `claim(` call in a script's bytes: `claim` after a character that is not a letter, digit, `_` or `.` (or
# at the start), then optional spaces or tabs, then `(` (rule 3.11.7).
SCRIPT_CLAIM_RE <- "(^|[^A-Za-z0-9_.])claim[ \t]*\\("

# Whether a script is opened (rule 3.11.7, SC1): its bytes hold `weft` or a `claim(` call.
script_may_hold_weft <- function(bytes) {
  txt <- script_bytes_text(bytes)
  grepl("weft", txt, fixed = TRUE, useBytes = TRUE) || grepl(SCRIPT_CLAIM_RE, txt, perl = TRUE, useBytes = TRUE)
}

# What reading a script's `weft()` literals and `claim()` calls gives (C3, C4, SC2, SC3): `status` is "invalid"
# (not text, and its bytes hold `weft`), "skip" (not opened by rule 3.11.7, not text without `weft` in its
# bytes, or neither a literal nor a counted claim call), "noparse", or "ok", with the text, lines, line starts,
# the literals, the scanner's rows (an empty table when none of them holds a construct) and the parse data
# `pd`, which the claim readers reuse.
script_scan <- function(path, rel, cfg, bytes = NULL) {
  none <- function(status) list(status = status, text = "", lines = character(), ls = numeric(), lit = NULL,
                                rows = NULL, pd = NULL)
  if (is.null(bytes)) bytes <- read_source_bytes(path)
  if (!script_may_hold_weft(bytes)) return(none("skip"))
  # the bytes already read are the text's: the file is read once (K14)
  text <- tryCatch(read_source_text(path, bytes = bytes), weft_encoding_error = function(e) NULL)
  # a file that is not text is weft's business only when it holds `weft` (D4)
  if (is.null(text)) return(none(if (bytes_mention_weft(bytes)) "invalid" else "skip"))
  lines <- split_source_lines(text)
  p <- tryCatch(parse(text = lines, keep.source = TRUE), error = function(e) NULL)
  if (is.null(p)) return(none("noparse"))
  pd <- utils::getParseData(p)
  if (is.null(pd)) return(none("skip"))
  ls <- line_starts(lines)
  lit <- weft_literals(lines, pd)
  if (!nrow(lit) && !nrow(claim_calls(lines, pd = pd))) return(none("skip"))
  rows <- if (nrow(lit)) scan_weft_code(lines, 1L, NA_character_, rel, cfg, ls, lit = lit)
  if (is.null(rows)) {
    rows <- scan_rows("", file = rel, first_line = 1L, config = cfg)
    rows$fstart <- rows$fend <- rows$fblock <- numeric()
    rows$context <- rows$chunk <- rows$option <- character()
  }
  list(status = "ok", text = text, lines = lines, ls = ls, lit = lit, rows = rows, pd = pd)
}

# A script is a second kind of source: its text, lines and line starts, the rows of its `weft()` literals, a
# prose mask that is their pieces, the parse data of its code (`code_pd`, for its claims), and no chunks,
# metadata or blocks of its own. One that is not opened, holds nothing to read, does not parse or is not text
# has no rows and a `status` of "skip", "noparse" or "invalid" (a source read in full has none, or "ok"), with
# the `note` a run gives for it (NULL when it gives none, M1).
script_stub <- function(rel, path, cfg, status) {
  note <- if (status == "noparse") {
    sprintf("`%s` does not parse as R, so its weft() strings and claim() calls were not read.", rel)
  }
  structure(list(file = rel, path = path, ext = sub("^.*\\.", "", basename(path)), script = TRUE, cfg = cfg,
                 text = "", lines = character(), line_start = numeric(), rows = NULL, chunks = NULL,
                 status = status, note = note, invalid = status == "invalid"),
            class = "weft_source")
}

# The status of a source: "ok" for a document or a script read in full (see `script_stub()`).
source_status <- function(src) src[["status"]] %||% "ok"

read_script_source <- function(path, root, cfg, bytes = NULL) {
  rel <- lint_rel_path(path, root)
  ext <- sub("^.*\\.", "", basename(path))
  sc <- script_scan(path, rel, cfg, bytes)
  if (sc$status != "ok") return(script_stub(rel, path, cfg, sc$status))
  lines <- sc$lines
  lit <- sc$lit
  nl <- length(lines)
  ex <- literal_ranges(sc$ls[lit$line] + lit$col - 1 + lit$open, lit$raw, lit$open > 1L)
  pieces <- data.frame(kind = rep("weft", nrow(ex)), name = rep(NA_character_, nrow(ex)), start = ex$start,
                       end = ex$end, grp = ex$idx, stringsAsFactors = FALSE)
  chunks <- chunk_table(lines, list())
  ff <- front_fields(character())
  src <- source_assemble(rel, path, ext, cfg, sc$text, lines, sc$ls, logical(nl), rep(TRUE, nl), pieces, sc$rows,
                         chunks, ff, list(), list(), "en", script = TRUE)
  # the parse the scan made, for the script's claims (SC2): claim_calls() and claim_decisions() do not parse again
  src$code_pd <- sc$pd
  src
}
