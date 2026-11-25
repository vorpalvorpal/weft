# The scanner over the places that are not prose (rules 1.10.1-1.10.4,
# 1.10.7-1.10.11, 2.3.5, 2.10.2, 2.10.6, 3.6.2): the caption options of a
# chunk, the front-matter fields of the first metadata block and of any later
# one, and the literal strings given to weft() in chunk code. Every row
# carries `context`, and for a caption `chunk` and `option`; `line` is the
# line in the file. Static errors (found from the source) go in `error`.

FM_FIELDS <- c("title", "subtitle", "abstract", "description")
# rmarkdown spells a caption option with a dot, Quarto with a hyphen; both are
# read, and `tab.cap` is the one that is not supported (1.10.4)
CAPTION_OPTIONS <- c("fig-cap", "fig.cap", "fig-alt", "fig.alt", "fig-scap",
                     "fig.scap", "fig-subcap", "fig.subcap", "tbl-cap", "tab.cap")

DIV_REMEDY <- paste0("write the caption in a figure or table div instead, ",
                     "`::: {#fig-name}` ... caption paragraph ... `:::` (rules 1.10.5, 2.3.5)")

# ---- metadata blocks ---------------------------------------------------------

# The metadata blocks of a document, as the line numbers of the delimiters.
# Like Pandoc, a block opens with a `---` line at the start or after a blank
# line, followed by a line that is not blank, and closes at the next `---` or
# `...` line. Fenced blocks are left alone.
metadata_blocks <- function(lines) {
  n <- length(lines)
  is_blank <- function(l) !nzchar(trim_ws(l))
  open <- integer()
  close <- integer()
  # only a fence line or a `---` line can matter: the rest are skipped, in one pass
  cand <- which(grepl("^[ \t>]*(`{3,}|~{3,})", lines) | grepl("^---[ \t\r]*$", lines))
  # the first line after `k` that closes the fence `fence`, or n + 1
  next_close <- function(fence, k) {
    if (k >= n) return(n + 1L)
    hit <- which(grepl(fence, lines[(k + 1L):n], perl = TRUE))
    if (length(hit)) k + hit[1L] else n + 1L
  }
  k <- 1L
  while (k <= n) {
    ci <- cand[cand >= k]
    if (!length(ci)) break
    k <- ci[1L]
    l <- lines[k]
    fm <- regmatches(l, regexec("^[ \t>]*(`{3,}|~{3,})", l))[[1]]
    if (length(fm)) {
      fence <- paste0("^[ \t>]*", substr(fm[2], 1, 1), "{", nchar(fm[2]), ",}[ \t\r]*$")
      k <- next_close(fence, k) + 1L
      next
    }
    if (grepl("^---[ \t\r]*$", l) && (k == 1L || is_blank(lines[k - 1L])) &&
        k < n && !is_blank(lines[k + 1L])) {
      j <- k + 1L
      while (j <= n && !grepl("^(---|\\.\\.\\.)[ \t\r]*$", lines[j])) j <- j + 1L
      if (j <= n && is_yaml_mapping(lines[(k + 1L):(j - 1L)])) {
        open <- c(open, k)
        close <- c(close, j)
        k <- j + 1L
        next
      }
    }
    k <- k + 1L
  }
  data.frame(open = open, close = close)
}

# The lines of the front block: the first metadata block, when it opens on the
# first line of the document, without its delimiters; character() when there is
# none. One reading for every caller that wants the document's own fields.
front_block <- function(lines) {
  mb <- metadata_blocks(lines)
  if (!nrow(mb) || mb$open[1L] != 1L) return(character())
  lines[seq_len(mb$close[1L] - 1L)[-1L]]
}

# Whether the lines of a candidate metadata block are a YAML mapping, as Pandoc
# requires: a `---` rule followed by text is a horizontal rule, not metadata
# (2.5.2). A block that is broken YAML but starts with `key:` is still metadata
# (Pandoc stops on it).
is_yaml_mapping <- function(x) {
  x <- x[nzchar(trim_ws(x)) & !grepl("^[ \t]*#", x)]
  if (!length(x)) return(FALSE)
  looks <- grepl("^[A-Za-z_\"'][^:]*:([ \t]|$)", x[1L])
  y <- tryCatch(list(v = yaml_read_text(x)),
                error = function(e) NULL)
  if (is.null(y)) return(looks)
  is.list(y$v) && !is.null(names(y$v))
}

# The top-level fields of each metadata block: the field name, the first and
# last line of its value, and the form of the scalar: `block` (`|` or `>`:
# the value starts on the line after the key) or `other` (the value starts on
# the key's line).
front_fields <- function(lines) {
  mb <- metadata_blocks(lines)
  out <- list()
  for (b in seq_len(nrow(mb))) {
    if (mb$close[b] - mb$open[b] < 2L) next
    idx <- (mb$open[b] + 1L):(mb$close[b] - 1L)
    keyed <- grepl("^[A-Za-z_][A-Za-z0-9_.-]*[ \t]*:([ \t]|$)", lines[idx])
    ks <- idx[keyed]
    for (i in seq_along(ks)) {
      key <- ks[i]
      last <- if (i < length(ks)) ks[i + 1L] - 1L else mb$close[b] - 1L
      name <- sub("[ \t]*:.*$", "", lines[key])
      rest <- trim_ws(sub("^[^:]*:", "", lines[key]))
      block <- grepl("^[|>][-+0-9]*[ \t]*(#.*)?$", rest)
      out[[length(out) + 1L]] <- data.frame(
        field = name, key = key, first = if (block) key + 1L else key,
        last = last, form = if (block) "block" else "other",
        block = b, stringsAsFactors = FALSE)
    }
  }
  if (!length(out)) {
    return(data.frame(field = character(), key = integer(), first = integer(),
                      last = integer(), form = character(), block = integer()))
  }
  do.call(rbind, out)
}

# `lines` with every line outside `keep` replaced by spaces (line breaks and
# columns stay where they were).
mask_lines <- function(lines, keep) {
  out <- gsub("[^\t]", " ", lines)
  out[keep] <- lines[keep]
  out
}

# The text with each metadata block blanked but for the value of a field of
# the four that is a block scalar: what the `text` hook resolves (1.10.7).
mask_front_matter <- function(text) {
  if (!nzchar(text)) return(text)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  mb <- metadata_blocks(lines)
  if (!nrow(mb)) return(text)
  ff <- front_fields(lines)
  keep <- rep(FALSE, length(lines))
  for (i in seq_len(nrow(ff))) {
    if (ff$field[i] %in% FM_FIELDS && ff$form[i] == "block" && ff$first[i] <= ff$last[i]) {
      keep[ff$first[i]:ff$last[i]] <- TRUE
    }
  }
  inyaml <- rep(FALSE, length(lines))
  for (b in seq_len(nrow(mb))) inyaml[mb$open[b]:mb$close[b]] <- TRUE
  lines[inyaml & !keep] <- gsub("[^\t]", " ", lines[inyaml & !keep])
  paste0(paste(lines, collapse = "\n"), if (endsWith(text, "\n")) "\n" else "")
}

# The type of the project a file is in (`project: type:` of the nearest
# `_quarto.yml`), or "".
project_type <- function(path) {
  if (is.null(path) || is.na(path)) return("")
  d <- normalizePath(path, mustWork = FALSE)
  if (!dir.exists(d)) d <- dirname(d)
  repeat {
    for (f in QUARTO_MARKERS) {
      p <- file.path(d, f)
      if (file.exists(p)) {
        y <- tryCatch(yaml_read_file(p), error = function(e) NULL)
        ty <- if (is.list(y)) y$project$type else NULL
        return(if (is.character(ty) && length(ty) == 1L) ty else "")
      }
    }
    up <- dirname(d)
    if (identical(up, d)) return("")
    d <- up
  }
}

# The chunk options the document sets for every chunk: `knitr: opts_chunk:`,
# then `execute:` over it (the first metadata block). Option names are as
# written; a dot and a hyphen are the same name.
doc_execute <- function(lines) {
  mb <- metadata_blocks(lines)
  if (!nrow(mb) || mb$open[1L] != 1L || mb$close[1L] - 2L < 1L) return(list())
  y <- tryCatch(yaml_read_text(lines[2L:(mb$close[1L] - 1L)]), error = function(e) NULL)
  if (!is.list(y)) return(list())
  oc <- if (is.list(y$knitr)) y$knitr$opts_chunk else NULL
  ex <- y$execute
  out <- if (is.list(oc)) oc else list()
  if (is.list(ex)) for (n in names(ex)) out[[n]] <- ex[[n]]
  out
}

# The value of a chunk option written as a constant, or NULL when it is not
# (an expression that has to be run to be known): `TRUE`, `T`, `FALSE`, a
# number, and under `!expr` the same written as R.
static_option_value <- function(text, expr = FALSE) {
  t <- trim_ws(sub("^!expr[ \t]*", "", sub("(^|[ \t])#.*$", "", text)))
  if (!nzchar(t)) return(NULL)
  if (!expr && !grepl("^!expr", trim_ws(text))) return(yaml_scalar_text(text))
  ex <- tryCatch(parse(text = t, keep.source = FALSE), error = function(e) NULL)
  if (is.null(ex) || length(ex) != 1L) return(NULL)
  e <- ex[[1L]]
  if (is.symbol(e) && as.character(e) %in% c("T", "F")) return(as.character(e) == "T")
  if (is.atomic(e) && length(e) == 1L) return(e)
  if (is.call(e) && identical(e[[1L]], as.name("-")) && length(e) == 2L && is.numeric(e[[2L]])) return(-e[[2L]])
  NULL
}

truthy <- function(x) {
  if (is.null(x) || !length(x)) return(FALSE)
  if (is.logical(x)) return(isTRUE(x[1L]))
  if (is.numeric(x)) return(isTRUE(x[1L] > 0))
  x <- tolower(trim_ws(as.character(x[1L])))
  x %in% c("true", "t", "yes", "1", "2", "3")
}
falsy <- function(x) {
  if (is.null(x) || !length(x)) return(FALSE)
  if (is.logical(x)) return(isFALSE(x[1L]))
  tolower(trim_ws(as.character(x[1L]))) %in% c("false", "f", "no", "0")
}

# ---- front matter rows -------------------------------------------------------

scan_front_matter_rows <- function(lines, file = NA_character_, config = NULL,
                                   project = "", filter_doc = FALSE, named_filter = FALSE) {
  ff <- front_fields(lines)
  if (!nrow(ff)) return(NULL)
  keep <- rep(FALSE, length(lines))
  txt <- lines
  for (i in seq_len(nrow(ff))) {
    if (ff$first[i] > ff$last[i]) next
    r <- ff$first[i]:ff$last[i]
    keep[r] <- TRUE
    if (ff$form[i] == "other") {
      # the key is not part of the value
      txt[ff$key[i]] <- sub("^[^:]*:", paste0(strrep(" ", nchar(sub(":.*$", "", lines[ff$key[i]])) + 1L)),
                            lines[ff$key[i]])
    }
  }
  rows <- scan_rows(paste(mask_lines(txt, keep), collapse = "\n"), file = file,
                    config = config, filter_doc = filter_doc, named_filter = named_filter)
  if (!nrow(rows)) return(NULL)
  # front matter is always the filter's to read (E2 BN6)
  rows$resolver[rows$kind == "named"] <- "filter"
  field <- character(nrow(rows))
  form <- character(nrow(rows))
  for (i in seq_len(nrow(ff))) {
    hit <- rows$line >= ff$first[i] & rows$line <= ff$last[i]
    field[hit] <- ff$field[i]
    form[hit] <- ff$form[i]
  }
  rows$context <- "front-matter"
  rows$fstart <- as.numeric(rows$start)
  rows$fend <- as.numeric(rows$end)
  rows$fblock <- as.numeric(rows$block_start)
  rows$chunk <- NA_character_
  rows$option <- field
  # the hooks' rules about where a construct may sit do not apply to what the filter resolves
  top <- is.na(rows$parent) & !(rows$kind %in% c("bare", "link")) & rows$resolver == "hooks"
  add <- function(i, msg) {
    rows$error[i] <<- if (is.na(rows$error[i])) msg else paste(rows$error[i], msg, sep = "\n")
  }
  for (i in which(top)) {
    f <- field[i]
    if (!f %in% FM_FIELDS) {
      add(i, sprintf(paste0("A `%s` construct in the front-matter field `%s`: constructs work in ",
                            "`title`, `subtitle`, `abstract` and `description` only (rule 1.10.7)."),
                     rows$kind[i], f))
      next
    }
    if (form[i] != "block") {
      add(i, sprintf(paste0("A `%s` construct in `%s` must be in a YAML block scalar, written ",
                            "`%s: |` or `%s: >` (rule 1.10.7)."), rows$kind[i], f, f, f))
    }
    if (f == "title" && project %in% c("book", "website")) {
      add(i, sprintf(paste0("A `%s` construct in `title` of a %s: `title` holds no construct in a ",
                            "book or a website (rule 1.10.11); write it in `abstract` or `description`, ",
                            "or in a heading."), rows$kind[i], project))
    }
  }
  rows
}

# ---- chunks ------------------------------------------------------------------

# The executed chunks of a document: header line, close line, engine, and the
# header's options as written.
find_chunks <- function(lines) {
  n <- length(lines)
  mb <- metadata_blocks(lines)
  inyaml <- rep(FALSE, n)
  for (b in seq_len(nrow(mb))) inyaml[mb$open[b]:mb$close[b]] <- TRUE
  begin <- "^[ \t>]*(`{3,})[ \t]*\\{[ \t]*([A-Za-z0-9_]+)(.*)\\}[ \t]*$"
  # a chunk header is a fence line: only those are looked at, in one pass
  cand <- which(!inyaml & grepl("^[ \t>]*(`{3,}|~{3,})", lines))
  out <- list()
  k <- 1L
  while (k <= n) {
    ci <- cand[cand >= k]
    if (!length(ci)) break
    k <- ci[1L]
    l <- lines[k]
    m <- regmatches(l, regexec(begin, l, perl = TRUE))[[1]]
    gen <- regmatches(l, regexec("^[ \t>]*(`{3,}|~{3,})", l))[[1]]
    if (length(m) || length(gen)) {
      fence <- if (length(m)) m[2] else gen[2]
      close_re <- paste0("^[ \t>]*", substr(fence, 1, 1), "{", nchar(fence), ",}[ \t\r]*$")
      j <- n + 1L
      if (k < n) {
        hit <- which(grepl(close_re, lines[(k + 1L):n], perl = TRUE))
        if (length(hit)) j <- k + hit[1L]
      }
      if (length(m)) {
        out[[length(out) + 1L]] <- list(open = k, close = min(j, n + 1L) - 0L,
                                        engine = m[3], header = m[4], closed = j <= n)
      }
      k <- j + 1L
      next
    }
    k <- k + 1L
  }
  out
}

# The engine Quarto runs a document on: "knitr", "jupyter", "julia" or
# "markdown". An `engine:` key decides (its mapping form, `engine:` then
# `  julia: ...`, names the first key); then a `jupyter:` key means jupyter;
# with neither, the executed chunks do: an {r} chunk is knitr, else {python}
# is jupyter, else {julia} is julia. Only lower-case languages are executable
# (Quarto's rule), and find_chunks() already leaves out fenced examples, so a
# chunk shown inside a longer fence does not count.
quarto_engine <- function(lines) {
  fm <- front_block(lines)
  k <- grep("^engine[ \t]*:", fm)
  if (length(k)) {
    v <- sub("(^|[ \t])#.*$", "", sub("^engine[ \t]*:", "", fm[k[1L]]))
    v <- tolower(gsub("^[ \t\"']+|[ \t\"']+$", "", v))
    if (!nzchar(v) && k[1L] < length(fm)) {
      nxt <- regmatches(fm[k[1L] + 1L], regexec("^[ \t]+([A-Za-z]+)[ \t]*:", fm[k[1L] + 1L]))[[1]]
      if (length(nxt)) v <- tolower(nxt[2L])
    }
    return(if (v %in% c("knitr", "jupyter", "julia")) v else "markdown")
  }
  if (any(grepl("^jupyter[ \t]*:", fm))) return("jupyter")
  langs <- vapply(find_chunks(lines), function(ch) ch$engine, "")
  if ("r" %in% langs) return("knitr")
  if ("python" %in% langs) return("jupyter")
  if ("julia" %in% langs) return("julia")
  "markdown"
}

# `lines` with the block-quote markers of a quoted chunk taken off its lines
# (knitr runs a chunk written `> ```{r}`; the scan reads it as written
# without the quote). Line numbers do not change.
dequote_chunks <- function(lines) {
  for (ch in find_chunks(lines)) {
    if (!grepl(">", sub("[^ \t>].*$", "", lines[ch$open]), fixed = TRUE)) next
    r <- ch$open:min(ch$close, length(lines))
    lines[r] <- sub("^[ \t>]*", "", lines[r])
  }
  lines
}

# The options in a chunk header, as written: the label, and for each named
# option the value when it is a literal string, else NULL, with its text.
parse_header <- function(header) {
  rest <- sub("^[ \t,]+", "", trim_ws(header))
  label <- NA_character_
  m <- regexpr("^[^,=[:space:]'\"()]+[ \t]*(,|$)", rest, perl = TRUE)
  if (m > 0L) {
    label <- trim_ws(sub(",$", "", substring(rest, 1L, attr(m, "match.length"))))
    rest <- substring(rest, attr(m, "match.length") + 1L)
  }
  rest <- sub("^[ \t,]+", "", rest)
  opts <- list()
  if (nzchar(trim_ws(rest))) {
    ex <- tryCatch(parse(text = paste0("alist(", rest, ")"), keep.source = FALSE),
                   error = function(e) NULL)
    if (!is.null(ex)) {
      args <- as.list(ex[[1L]])[-1L]
      nms <- names(args)
      if (is.null(nms)) nms <- rep("", length(args))
      for (i in seq_along(args)) {
        if (!nzchar(nms[i])) next
        a <- args[[i]]
        opts[[nms[i]]] <- list(
          literal = if (is.character(a) && length(a) == 1L) a else NULL,
          text = paste(deparse(a, width.cutoff = 500L), collapse = " "))
      }
      if (is.na(label) && !is.null(opts$label) && !is.null(opts$label$literal)) {
        label <- opts$label$literal
      }
    }
  }
  list(label = label, opts = opts)
}

# The `#|` option lines at the top of a chunk: their line numbers and text
# with the prefix taken off.
chunk_option_lines <- function(lines, open, close) {
  idx <- integer()
  j <- open + 1L
  while (j < close && grepl("^[ \t]*#\\|", lines[j])) {
    idx <- c(idx, j)
    j <- j + 1L
  }
  list(lines = idx, text = sub("^[ \t]*#\\|[ ]?", "", lines[idx]),
       code_first = j)
}

# The text of a one-line YAML scalar: no trailing comment, no quotes.
yaml_scalar_text <- function(x) {
  x <- trim_ws(sub("(^|[ \t])#.*$", "", x))
  gsub("^[\"']|[\"']$", "", x)
}

# The options of a `#|` block: for each top-level key, its name, the line of
# the key, the line range of its value, and the form of the value: `block`
# (`|`/`>`), `list` (a YAML sequence), `expr` (`!expr`) or `scalar`. List items
# are returned in `items`: line range and form of each.
parse_option_block <- function(idx, text) {
  if (!length(idx)) return(list())
  keyed <- grepl("^[A-Za-z0-9_.-]+[ \t]*:([ \t]|$)", text)
  ks <- which(keyed)
  out <- list()
  for (i in seq_along(ks)) {
    a <- ks[i]
    b <- if (i < length(ks)) ks[i + 1L] - 1L else length(text)
    name <- sub("[ \t]*:.*$", "", text[a])
    rest <- trim_ws(sub("^[^:]*:", "", text[a]))
    form <- if (grepl("^[|>][-+0-9]*[ \t]*(#.*)?$", rest)) "block" else
      if (grepl("^!expr", rest)) "expr" else
        if (!nzchar(rest) && b > a && any(grepl("^[ \t]*-", text[(a + 1L):b]))) "list" else "scalar"
    items <- NULL
    if (form == "list") {
      sub_idx <- (a + 1L):b
      starts <- sub_idx[grepl("^[ \t]*-([ \t]|$)", text[sub_idx])]
      items <- lapply(seq_along(starts), function(q) {
        s0 <- starts[q]
        e0 <- if (q < length(starts)) starts[q + 1L] - 1L else b
        r0 <- trim_ws(sub("^[ \t]*-", "", text[s0]))
        blk <- grepl("^[|>][-+0-9]*[ \t]*(#.*)?$", r0)
        list(start = idx[s0], first = if (blk) idx[s0] + 1L else idx[s0], last = idx[e0],
             form = if (blk) "block" else "scalar", dash = s0)
      })
    }
    out[[length(out) + 1L]] <- list(
      name = name, key = idx[a], first = if (form == "block") idx[a] + 1L else idx[a],
      last = idx[b], form = form, items = items, value = rest)
  }
  out
}

# ---- file offsets of a literal string ------------------------------------------

# The file offset of each character of the value of a string literal whose
# contents (as typed, escapes and all) begin at file offset `f0`: one entry per
# character of the value.
lit_offsets <- function(raw, f0) {
  if (!nzchar(raw)) return(numeric())
  if (!grepl("\\", raw, fixed = TRUE)) return(f0 + seq_len(nchar(raw)) - 1)
  m <- gregexpr(paste0("(?s)\\\\(?:u\\{[0-9A-Fa-f]+\\}|u[0-9A-Fa-f]{1,4}|U\\{[0-9A-Fa-f]+\\}|",
                       "U[0-9A-Fa-f]{1,8}|x[0-9A-Fa-f]{1,2}|[0-7]{1,3}|.)|[^\\\\]"), raw, perl = TRUE)[[1L]]
  f0 + as.numeric(m) - 1
}

# The file ranges of a string literal's contents that are prose: its characters less the escape sequences
# (`\n`, `\"`, `\u00e9`), which stand for one value character each and are not prose as typed. `start` is
# the file offset of the first character of `raw`, the contents as typed. A raw string has no escapes. The
# ranges, with `idx` the number of the literal each belongs to.
literal_ranges <- function(start, raw, is_raw = rep(FALSE, length(raw))) {
  out <- list()
  for (k in seq_along(raw)) {
    n <- nchar(raw[k])
    if (n == 0L) next
    if (is_raw[k] || !grepl("\\", raw[k], fixed = TRUE)) {
      out[[length(out) + 1L]] <- data.frame(start = start[k], end = start[k] + n - 1, idx = k)
      next
    }
    m <- gregexpr(paste0("(?s)\\\\(?:u\\{[0-9A-Fa-f]+\\}|u[0-9A-Fa-f]{1,4}|U\\{[0-9A-Fa-f]+\\}|",
                         "U[0-9A-Fa-f]{1,8}|x[0-9A-Fa-f]{1,2}|[0-7]{1,3}|.)"), raw[k], perl = TRUE)[[1L]]
    keep <- rep(TRUE, n)
    if (m[1L] > 0L) {
      for (j in seq_along(m)) keep[m[j]:(m[j] + attr(m, "match.length")[j] - 1L)] <- FALSE
    }
    if (!any(keep)) next
    r <- rle(keep)
    ends <- cumsum(r$lengths)
    begs <- ends - r$lengths + 1L
    out[[length(out) + 1L]] <- data.frame(start = start[k] + begs[r$values] - 1,
                                          end = start[k] + ends[r$values] - 1, idx = k)
  }
  if (!length(out)) return(data.frame(start = numeric(), end = numeric(), idx = integer()))
  do.call(rbind, out)
}

# Piece offsets `p` mapped through the table `off` (NA past its end).
map_offsets <- function(p, off) {
  out <- rep(NA_real_, length(p))
  ok <- !is.na(p) & p >= 1 & p <= length(off)
  out[ok] <- off[p[ok]]
  out
}

# Line starts of `lines` (file offsets, lines joined by one line feed).
line_starts <- function(lines) {
  if (!length(lines)) return(numeric())
  1 + c(0, cumsum(nchar(lines) + 1))[seq_along(lines)]
}

# ---- caption rows ------------------------------------------------------------

# The executed chunks of a document, each with its label (knitr's
# `unnamed-chunk-N` when it has none: N counts the chunks without a label),
# its header options and its `#|` options.
labelled_chunks <- function(lines) {
  chunks <- find_chunks(lines)
  counter <- 0L
  for (i in seq_along(chunks)) {
    ch <- chunks[[i]]
    hdr <- parse_header(ch$header)
    oi <- chunk_option_lines(lines, ch$open, ch$close)
    optblk <- parse_option_block(oi$lines, oi$text)
    lab <- hdr$label
    for (o in optblk) {
      if (o$name == "label") lab <- yaml_scalar_text(o$value)
    }
    if (is.na(lab) || !nzchar(lab)) {
      counter <- counter + 1L
      lab <- sprintf("unnamed-chunk-%d", counter)
    }
    chunks[[i]]$label <- lab
    chunks[[i]]$hdr <- hdr
    chunks[[i]]$oi <- oi
    chunks[[i]]$optblk <- optblk
  }
  chunks
}

# One chunk's caption rows, with their static errors.
scan_chunk_captions <- function(lines, ch, label, hdr, optblk, optinfo, doc_exec, file,
                                config, dq = NULL, filter_doc = FALSE, named_filter = FALSE) {
  rows <- list()
  rem <- integer(length(lines))   # characters taken off the front of a line
  ls <- line_starts(lines)
  keep <- rep(FALSE, length(lines))
  txt <- lines
  regions <- list()   # option, first, last, kind of region
  add_region <- function(option, first, last, form, item = FALSE) {
    if (first > last) return()
    keep[first:last] <<- TRUE
    regions[[length(regions) + 1L]] <<- list(option = option, first = first, last = last,
                                            form = form, item = item)
  }
  for (o in optblk) {
    if (!(o$name %in% CAPTION_OPTIONS)) next
    # R code that calls weft() is read as code, not as markup (C10)
    if (identical(o$form, "expr") && caption_is_code(o, lines)) next
    if (o$form == "list") {
      for (it in o$items) {
        add_region(o$name, it$first, it$last, it$form, item = TRUE)
        if (it$form == "scalar") {
          new <- sub("^[ \t]*#\\|[ ]?[ \t]*-", "", txt[it$first])
          rem[it$first] <- rem[it$first] + nchar(txt[it$first]) - nchar(new)
          txt[it$first] <- new
        }
      }
    } else {
      add_region(o$name, o$first, o$last, o$form)
      if (o$form != "block") {
        # the key is not part of the value
        new <- sub("^[ \t]*#\\|[ ]?[A-Za-z0-9_.-]+[ \t]*:", "", txt[o$first])
        rem[o$first] <- rem[o$first] + nchar(txt[o$first]) - nchar(new)
        txt[o$first] <- new
      }
    }
  }
  # the `#|` prefix is not part of a caption
  txt[keep] <- sub("^([ \t]*)#\\|", "\\1  ", txt[keep])
  # lines the prefix strip left unaligned are scanned as they are: only line
  # numbers matter
  if (length(regions)) {
    r <- scan_rows(paste(mask_lines(txt, keep), collapse = "\n"), file = file, config = config,
                   filter_doc = filter_doc, named_filter = named_filter)
    if (nrow(r)) {
      # file offsets: the text scanned is the lines less what `rem` took off
      tstart <- c(1, cumsum(nchar(lines) - rem + 1))
      shift <- cumsum(rem + (if (is.null(dq)) 0L else dq))
      at <- function(p) {
        L <- findInterval(p, tstart[seq_along(lines)])
        L[L < 1L] <- 1L
        ifelse(is.na(p), NA_real_, p + shift[L])
      }
      r$fstart <- at(r$start)
      r$fend <- at(r$end)
      r$fblock <- at(r$block_start)
      opt <- character(nrow(r))
      reg <- integer(nrow(r))
      for (i in seq_along(regions)) {
        hit <- r$line >= regions[[i]]$first & r$line <= regions[[i]]$last
        opt[hit] <- regions[[i]]$option
        reg[hit] <- i
      }
      r$option <- opt
      r$region <- reg
      rows[[length(rows) + 1L]] <- r
    }
  }
  # captions written in the header (rmarkdown): a literal string is scanned
  for (nm in names(hdr$opts)) {
    if (!(nm %in% CAPTION_OPTIONS)) next
    v <- hdr$opts[[nm]]$literal
    if (is.null(v)) next
    r <- scan_rows(v, file = file, first_line = ch$open, config = config, filter_doc = filter_doc,
                   named_filter = named_filter)
    if (!nrow(r)) next
    off <- rep(NA_real_, nchar(v))
    pat <- paste0("(?<![A-Za-z0-9_.])", gsub(".", "\\.", nm, fixed = TRUE),
                  "[ \t]*=[ \t]*(?:\"((?:[^\"\\\\]|\\\\.)*)\"|'((?:[^'\\\\]|\\\\.)*)')")
    mm <- regexpr(pat, lines[ch$open], perl = TRUE)
    if (mm > 0L) {
      cs <- attr(mm, "capture.start")
      cl <- attr(mm, "capture.length")
      g <- if (cs[1L] > 0L) 1L else 2L
      raw <- substr(lines[ch$open], cs[g], cs[g] + cl[g] - 1L)
      f0 <- ls[ch$open] + cs[g] - 1 + (if (is.null(dq)) 0 else dq[ch$open])
      o <- lit_offsets(raw, f0)
      if (length(o) == nchar(v)) off <- o
    }
    r$fstart <- map_offsets(r$start, off)
    r$fend <- map_offsets(r$end, off)
    r$fblock <- map_offsets(r$block_start, off)
    r$line <- rep(ch$open, nrow(r))
    r$option <- rep(nm, nrow(r))
    r$region <- rep(0L, nrow(r))
    rows[[length(rows) + 1L]] <- r
  }
  if (!length(rows)) return(NULL)
  rows <- bind_scan_rows(rows)
  rows$context <- "caption"
  rows$chunk <- label
  add <- function(i, msg) {
    rows$error[i] <<- if (is.na(rows$error[i])) msg else paste(rows$error[i], msg, sep = "\n")
  }
  # chunk-level reasons a caption is not resolved (2.3.5)
  cache <- truthy(doc_exec$cache)
  eval_off <- falsy(doc_exec$eval)
  # the option as the chunk writes it: its value when that is a constant,
  # `NA` when it has to be run to be known, NULL when the chunk does not set it
  co <- function(name) {
    for (o in optblk) {
      if (o$name == name) {
        v <- static_option_value(o$value, expr = o$form == "expr")
        return(if (is.null(v)) NA else v)
      }
    }
    h <- hdr$opts[[name]]
    if (!is.null(h)) {
      v <- static_option_value(h$text, expr = TRUE)
      return(if (is.null(v)) NA else v)
    }
    NULL
  }
  cv <- co("cache")
  if (!is.null(cv)) cache <- if (isTRUE(is.na(cv))) FALSE else truthy(cv) || (cache && !falsy(cv))
  ev <- co("eval")
  if (!is.null(ev)) eval_off <- !isTRUE(is.na(ev)) && falsy(ev)
  why <- not_resolved_why(cache, eval_off, ch$engine)
  # a named value in a caption the hooks do not resolve is the filter's (E2 ST1)
  if (length(why)) rows$resolver[rows$kind == "named"] <- "filter"
  top <- is.na(rows$parent) & !(rows$kind %in% c("bare", "link")) & rows$resolver == "hooks"
  for (i in which(top)) {
    o <- rows$option[i]
    if (o == "tab.cap") {
      add(i, sprintf(paste0("A `%s` construct in `tab.cap`: rmarkdown's `tab.cap` is not ",
                            "supported (rule 1.10.4); write the caption in `tbl-cap` or in a table div (rule 1.10.5)."),
                     rows$kind[i]))
    } else if (!is.na(rows$region[i]) && rows$region[i] > 0L) {
      rg <- regions[[rows$region[i]]]
      if (o %in% c("fig-subcap", "fig.subcap") && rg$form == "expr") {
        add(i, sprintf(paste0("A `%s` construct under `!expr` in `%s` (rule 1.10.4); write each ",
                              "caption as a YAML list item holding a block scalar."), rows$kind[i], o))
      } else if (rg$form %in% c("scalar", "expr")) {
        add(i, sprintf(paste0("A `%s` construct in `%s` must be in a YAML block scalar, written ",
                              "`%s: |` (rule 1.10.3)."), rows$kind[i], o, o))
      }
    }
    if (length(why)) {
      add(i, sprintf("A `%s` construct in a caption of chunk `%s`, which %s: %s.",
                     rows$kind[i], label, paste(why, collapse = " and "), DIV_REMEDY))
    }
  }
  rows
}

# ---- weft() strings ----------------------------------------------------------

# The calls to `weft()` in parse data, as `weft(...)` or `weft::weft(...)` (ST1): the id of each call's
# expression.
weft_calls <- function(pd) {
  fn <- pd[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == "weft", , drop = FALSE]
  out <- integer()
  for (id in fn$id) {
    fexpr <- pd$parent[pd$id == id]            # the expr that names the function
    sib <- pd[pd$parent == fexpr, , drop = FALSE]
    pk <- sib$text[sib$token == "SYMBOL_PACKAGE"]
    if (length(pk) && !identical(pk[1L], "weft")) next
    call_id <- pd$parent[pd$id == fexpr]       # the call
    if (!length(call_id) || call_id == 0L || !any(pd$parent == call_id & pd$token == "'('")) next
    out <- c(out, call_id)
  }
  out
}

# The expression a call passes as `x` (ST2, C6): the argument named `x`, else the first given without a
# name, else, for the right-hand side of `|>` or `%>%`, the left-hand side. NA when there is none.
weft_call_arg <- function(pd, call_id) {
  kids <- pd[pd$parent == call_id, , drop = FALSE]
  kids <- kids[order(kids$line1, kids$col1), , drop = FALSE]
  after <- kids[seq_len(nrow(kids)) > which(kids$token == "'('")[1L], , drop = FALSE]
  name <- NA_character_
  first <- NA_integer_
  for (k in seq_len(nrow(after))) {
    tk <- after$token[k]
    if (tk == "SYMBOL_SUB") {
      name <- after$text[k]
    } else if (tk == "expr") {
      if (identical(name, "x")) return(after$id[k])
      if (is.na(name) && is.na(first)) first <- after$id[k]
      name <- NA_character_
    } else if (tk == "','") {
      name <- NA_character_
    }
  }
  if (!is.na(first)) return(first)
  # no argument of the call is `x` and none is unnamed: a pipe supplies it
  pe <- pd$parent[pd$id == call_id]
  if (length(pe) && pe != 0L) {
    sib <- pd[pd$parent == pe, , drop = FALSE]
    sib <- sib[order(sib$line1, sib$col1), , drop = FALSE]
    at <- match(call_id, sib$id)
    if (!is.na(at) && at >= 3L && sib$token[at - 1L] %in% c("PIPE", "SPECIAL") &&
        sib$text[at - 1L] %in% c("|>", "%>%") && sib$token[at - 2L] == "expr") return(sib$id[at - 2L])
  }
  NA_integer_
}

# ---- (the strings given to weft()) ----

scan_chunk_strings <- function(lines, ch, first, label, file, config, dq = NULL) {
  if (!identical(tolower(ch$engine), "r") || first >= ch$close) return(NULL)
  scan_weft_code(lines[first:(ch$close - 1L)], first, label, file, config, dq, line_starts(lines))
}

# The `STR_CONST` tokens a `weft()` call reads (C7): the argument is one string literal, or a `c()` (or
# `base::c()`) whose literal arguments are each read. The ids of the tokens.
weft_arg_literals <- function(pd, argid) {
  one <- function(id) {
    k <- pd[pd$parent == id, , drop = FALSE]
    if (nrow(k) == 1L && k$token == "STR_CONST") k$id else integer()
  }
  top <- one(argid)
  if (length(top)) return(top)
  kids <- pd[pd$parent == argid, , drop = FALSE]
  kids <- kids[order(kids$line1, kids$col1), , drop = FALSE]
  op <- which(kids$token == "'('")
  if (!length(op) || op[1L] < 2L || kids$token[1L] != "expr") return(integer())
  fk <- pd[pd$parent == kids$id[1L], , drop = FALSE]
  fk <- fk[order(fk$line1, fk$col1), , drop = FALSE]
  is_c <- (nrow(fk) == 1L && fk$token == "SYMBOL_FUNCTION_CALL" && fk$text == "c") ||
    (nrow(fk) == 3L && identical(fk$token, c("SYMBOL_PACKAGE", "NS_GET", "SYMBOL_FUNCTION_CALL")) &&
       fk$text[1L] == "base" && fk$text[3L] == "c")
  if (!is_c) return(integer())
  out <- integer()
  for (id in kids$id[seq_len(nrow(kids)) > op[1L] & kids$token == "expr"]) out <- c(out, one(id))
  out
}

# Where a parser column falls in a line: R counts a tab as reaching the next multiple of 8.
parse_char_col <- function(line_text, col) {
  if (!grepl("\t", line_text, fixed = TRUE)) return(col)
  ch <- strsplit(line_text, "")[[1L]]
  pos <- 0L
  for (i in seq_along(ch)) {
    pos <- if (ch[i] == "\t") (pos %/% 8L + 1L) * 8L else pos + 1L
    if (pos >= col) return(i)
  }
  length(ch) + 1L
}

# The width of what opens and closes a string token: `"`, or `r"(`, `R'--[`. `open` and `close` in
# characters, and whether it is a raw string.
str_token_shape <- function(tok) {
  m <- regexec("^[rR]([\"'])(-*)([(\\[{])", tok)[[1L]]
  if (m[1L] > 0L) {
    ml <- attr(m, "match.length")
    return(list(open = ml[1L], close = 1L + ml[3L] + 1L, raw = TRUE))
  }
  list(open = 1L, close = 1L, raw = FALSE)
}

# The literal strings given to weft() in parse data `pd` (C5 to C8): one row each, in order: `line` and
# `col` (of the token's first character, within the code, a tab one character), `text` (the whole token),
# `value`, `raw` (the contents as typed), `open` (the characters before them). The one reader the scanner
# and the lints share (C9).
empty_literals <- function() {
  data.frame(line = integer(), col = integer(), text = character(), value = character(),
             raw = character(), open = integer(), stringsAsFactors = FALSE)
}

weft_literals_pd <- function(pd, code) {
  none <- empty_literals()
  ids <- integer()
  for (call_id in weft_calls(pd)) {
    argid <- weft_call_arg(pd, call_id)
    if (!is.na(argid)) ids <- c(ids, weft_arg_literals(pd, argid))
  }
  ids <- unique(ids)
  if (!length(ids)) return(none)
  rows <- lapply(ids, function(id) {
    d <- pd[pd$id == id, , drop = FALSE]
    tok <- paste(utils::getParseText(pd, id), collapse = "\n")
    val <- tryCatch(eval(parse(text = tok, keep.source = FALSE)[[1L]]), error = function(e) NULL)
    if (!is.character(val) || length(val) != 1L || is.na(val)) return(NULL)
    sh <- str_token_shape(tok)
    data.frame(line = d$line1, col = parse_char_col(code[d$line1], d$col1), text = tok, value = val,
               raw = substr(tok, sh$open + 1L, nchar(tok) - sh$close), open = sh$open,
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) return(none)
  out <- out[order(out$line, out$col), , drop = FALSE]
  rownames(out) <- NULL
  out
}

weft_literals <- function(code, pd = NULL) {
  if (is.null(pd)) {
    if (!length(code) || !any(grepl("weft", code, fixed = TRUE))) return(empty_literals())
    p <- tryCatch(parse(text = paste(code, collapse = "\n"), keep.source = TRUE), error = function(e) NULL)
    pd <- if (is.null(p)) NULL else utils::getParseData(p)
  }
  if (is.null(pd)) return(empty_literals())
  weft_literals_pd(pd, code)
}

# The scanner's rows for the literal strings given to weft() in `code`, whose first line is line `first` of
# the document (`ls`, the line starts of the document, `dq` what dequoting took off each line). `option`
# names the chunk option the code is the value of (C10), NA for a chunk's code. `lit` is the literals
# when the caller has them.
scan_weft_code <- function(code, first, label, file, config, dq = NULL, ls = NULL, option = NA_character_,
                           lit = NULL) {
  if (is.null(lit)) lit <- weft_literals(code)
  if (!nrow(lit)) return(NULL)
  rows <- list()
  for (q in seq_len(nrow(lit))) {
    val <- lit$value[q]
    line <- first + lit$line[q] - 1L
    r <- scan_rows(val, file = file, first_line = line, config = config)
    if (!nrow(r)) next
    tokstart <- ls[line] + lit$col[q] - 1 + (if (is.null(dq)) 0 else dq[line])
    off <- rep(NA_real_, nchar(val))
    o <- if (lit$open[q] > 1L) tokstart + lit$open[q] + seq_len(nchar(val)) - 1 else
      lit_offsets(lit$raw[q], tokstart + 1)
    if (length(o) == nchar(val)) off <- o
    r$fstart <- map_offsets(r$start, off)
    r$fend <- map_offsets(r$end, off)
    r$fblock <- map_offsets(r$block_start, off)
    # a character that cannot be placed takes the place of the literal's first character (C11)
    r$fstart[is.na(r$fstart)] <- tokstart
    r$fend[is.na(r$fend)] <- r$fstart[is.na(r$fend)]
    rows[[length(rows) + 1L]] <- r
  }
  if (!length(rows)) return(NULL)
  rows <- bind_scan_rows(rows)
  rows$context <- "weft"
  rows$chunk <- label
  rows$option <- option
  rows
}

# C10: the R code of a caption option. In a `#|` block, a `!expr` value (the code after the tag, and
# the lines that follow it); in an rmarkdown header, an option whose value is not a string. Each is
# given to scan_weft_code() on lines that keep the code where it is in the document, so positions
# are the document's.
caption_code_rows <- function(lines, ch, label, hdr, optblk, file, config, dq, filter_doc = FALSE) {
  ls <- line_starts(lines)
  parts <- list()
  scan <- function(code, first, option) {
    r <- scan_weft_code(code, first, label, file, config, dq, ls, option)
    if (!is.null(r)) parts[[length(parts) + 1L]] <<- r
  }
  for (o in optblk) {
    if (!(o$name %in% CAPTION_OPTIONS) || !identical(o$form, "expr") || !caption_is_code(o, lines)) next
    ec <- expr_option_code(lines, o)
    if (is.null(ec)) next
    scan(ec$code, o$first, o$name)
  }
  for (nm in names(hdr$opts)) {
    if (!(nm %in% CAPTION_OPTIONS) || !is.null(hdr$opts[[nm]]$literal)) next
    code <- header_option_code(lines[ch$open], nm, hdr$opts[[nm]]$text)
    if (!is.null(code)) scan(code, ch$open, nm)
  }
  if (!length(parts)) return(NULL)
  bind_scan_rows(parts)
}

# Does the `!expr` value of option `o` call weft()? Then it is R code to be read for the strings it
# holds, and not scanned as markup (C10). Any other `!expr` stays as it was: an expression that holds a
# string with a construct is the error of 1.10.3 and 1.10.4.
caption_is_code <- function(o, lines) {
  ec <- expr_option_code(lines, o)
  if (is.null(ec)) return(FALSE)
  ex <- tryCatch(parse(text = paste(ec$code, collapse = "\n"), keep.source = TRUE), error = function(e) NULL)
  if (is.null(ex)) return(FALSE)
  pd <- utils::getParseData(ex)
  !is.null(pd) && length(weft_calls(pd)) > 0L
}

# The R code of a `!expr` option of a `#|` block (one line, continuation lines, or a block scalar
# `!expr |` with the code on the lines that follow, F4), on lines that keep the code where it is in the
# document: the `#|` prefix, the key, the tag and a block scalar's indicator are blanked to spaces.
# list(code, first), or NULL when the first line is not a `!expr` line.
expr_option_code <- function(lines, o) {
  code <- lines[o$first:o$last]
  pre <- regexpr("^[ \t]*#\\|[ ]?[ \t]*[A-Za-z0-9_.-]+[ \t]*:[ \t]*!expr", code[1L], perl = TRUE)
  if (pre < 0L) return(NULL)
  plen <- attr(pre, "match.length")
  rest <- substring(code[1L], plen + 1L)
  code[1L] <- paste0(strrep(" ", plen), rest)
  if (length(code) > 1L) code[-1L] <- sub("^([ \t]*)#\\|", "\\1  ", code[-1L])
  if (grepl("^[ \t]*[|>][-+0-9]*[ \t]*(#.*)?$", rest)) code[1L] <- strrep(" ", nchar(code[1L]))
  list(code = code, first = o$first)
}

# The R code of the header option `nm` of a chunk header line (an rmarkdown `fig.cap = weft(...)`), padded
# so that it keeps its columns, or NULL. `text` is the option's deparsed value. Trailing white space after
# the closing brace is not part of the header (F12).
header_option_code <- function(hl, nm, text) {
  hl <- sub("[ \t\r]+$", "", hl)
  st <- regexpr(paste0("(?<![A-Za-z0-9_.])", gsub(".", "\\.", nm, fixed = TRUE), "[ \t]*=[ \t]*"), hl, perl = TRUE)
  if (st < 0L) return(NULL)
  from <- st + attr(st, "match.length")
  ends <- c(gregexpr(",", hl, fixed = TRUE)[[1L]], nchar(hl))
  ends <- ends[ends >= from]
  for (e in sort(unique(ends))) {
    ex <- tryCatch(parse(text = substr(hl, from, e - 1L), keep.source = FALSE), error = function(err) NULL)
    if (!is.null(ex) && length(ex) == 1L &&
        identical(paste(deparse(ex[[1L]], width.cutoff = 500L), collapse = " "), text)) {
      return(paste0(strrep(" ", from - 1L), substr(hl, from, e - 1L)))
    }
  }
  NULL
}

# ---- putting the rows together ----------------------------------------------

# rbind scan results, shifting each one's `parent` indices past the rows
# before it.
bind_scan_rows <- function(parts) {
  parts <- Filter(function(p) !is.null(p) && nrow(p), parts)
  if (!length(parts)) return(NULL)
  off <- 0L
  for (i in seq_along(parts)) {
    p <- parts[[i]]
    p$parent <- p$parent + off
    off <- off + nrow(p)
    parts[[i]] <- p
  }
  if (length(parts) == 1L) return(parts[[1L]])
  nm <- Reduce(union, lapply(parts, names))
  parts <- lapply(parts, function(p) {
    for (m in setdiff(nm, names(p))) {
      p[[m]] <- if (m %in% c("region")) rep(NA_integer_, nrow(p)) else rep(NA_character_, nrow(p))
    }
    p[nm]
  })
  do.call(rbind, parts)
}

# The rows of the places beside prose in a document's lines: front matter,
# captions and weft() strings.
scan_extra_rows <- function(lines, file = NA_character_, config = NULL, project = "", filter_doc = FALSE,
                            named_filter = NULL) {
  if (is.null(named_filter)) named_filter <- document_names_from(lines, file, config) %in% c("python", "julia")
  fm <- scan_front_matter_rows(lines, file, config, project, filter_doc, named_filter)
  caps <- list()
  strs <- list()
  doc_exec <- doc_execute(lines)
  orig <- lines
  lines <- dequote_chunks(lines)
  dq <- nchar(orig) - nchar(lines)
  for (ch in labelled_chunks(lines)) {
    caps[[length(caps) + 1L]] <- scan_chunk_captions(lines, ch, ch$label, ch$hdr, ch$optblk,
                                                    ch$oi, doc_exec, file, config, dq, filter_doc, named_filter)
    strs[[length(strs) + 1L]] <- scan_chunk_strings(lines, ch, ch$oi$code_first, ch$label,
                                                   file, config, dq)
    strs[[length(strs) + 1L]] <- caption_code_rows(lines, ch, ch$label, ch$hdr, ch$optblk, file, config, dq)
  }
  parts <- c(list(fm), caps, strs)
  bind_scan_rows(parts)
}

# The ids the captions of a document define (rows of scan_extra_rows()): a
# reference in prose to one is known (1.7.10).
caption_ids <- function(extra) {
  if (is.null(extra) || !nrow(extra)) return(character())
  unique(extra$id[extra$context == "caption" & !is.na(extra$id) & nzchar(extra$id)])
}

# A file that names a child document is not the whole document: a reference
# to an id it cannot see is the knit's to judge (1.7.10).
has_child_chunk <- function(lines) any(grepl("child[ \t]*[=:]", lines))

# Does the Lua filter resolve the spans of this document (N14): any document the knitr hooks do not knit.
# The hooks knit an `.Rmd`; a `.qmd` with `engine: knitr`, or with an executed {r} chunk and no `engine:` or
# `jupyter:` key. Read from the lines with no parse: the first metadata block's top-level keys, and the
# chunk headers.
filter_resolves <- function(lines, file = NA_character_) {
  if (!is.na(file) && grepl("\\.rmd$", file, ignore.case = TRUE)) return(FALSE)
  n <- length(lines)
  fm <- front_block(lines)
  eng <- grep("^engine[ \t]*:", fm, value = TRUE)
  if (length(eng)) {
    v <- trim_ws(sub("(^|[ \t])#.*$", "", sub("^engine[ \t]*:", "", eng[1L])))
    v <- tolower(gsub("^[\"']|[\"']$", "", v))
    return(!identical(v, "knitr"))
  }
  if (any(grepl("^jupyter[ \t]*:", fm))) return(TRUE)
  hdr <- grep("^[ \t>]*`{3,}[ \t]*\\{[ \t]*[rR][ \t,}]", lines)
  for (k in hdr) {
    if (grepl("[ ,{]eval[ \t]*=[ \t]*(FALSE|F)[ \t]*[,}]", lines[k])) next
    j <- k + 1L
    off <- FALSE
    while (j <= n && grepl("^[ \t>]*#\\|", lines[j])) {
      if (grepl("^[ \t>]*#\\|[ ]?eval[ \t]*:[ \t]*(false|no|FALSE)[ \t]*(#.*)?$", lines[j])) off <- TRUE
      j <- j + 1L
    }
    if (!off) return(FALSE)
  }
  TRUE
}

# All the rows of a document, in textual order, each with its context. Prose
# is judged as the knit judges it: an id a caption defines is known, and a
# file with children is lenient about the ids it cannot see.
scan_document <- function(lines, file = NA_character_, config = NULL, project = "") {
  text <- paste(lines, collapse = "\n")
  fd <- filter_resolves(lines, file)
  nf <- document_names_from(lines, file, config) %in% c("python", "julia")
  extra <- scan_extra_rows(lines, file, config, project, fd, nf)
  prose <- scan_text(blank_front_matter(text), file = file, config = config,
                     lenient = has_child_chunk(lines), known = caption_ids(extra), filter_doc = fd,
                     named_filter = nf)
  prose$context <- rep("prose", nrow(prose))
  prose$fstart <- as.numeric(prose$start)
  prose$fend <- as.numeric(prose$end)
  prose$fblock <- as.numeric(prose$block_start)
  prose$chunk <- rep(NA_character_, nrow(prose))
  prose$option <- rep(NA_character_, nrow(prose))
  all <- bind_scan_rows(list(prose, extra))
  if (is.null(all)) return(prose)
  ord <- order(all$line, seq_len(nrow(all)))
  all$parent <- match(all$parent, ord)
  all <- all[ord, , drop = FALSE]
  rownames(all) <- NULL
  all$region <- NULL
  all
}
