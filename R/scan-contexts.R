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

# ---- the skeleton of a document, read once (E1) ----------------------------

# A document's skeleton (its metadata blocks, chunks and front-matter fields)
# is read by many callers from the same lines. `local_doc_memo()` opens a memo
# for the length of the calling function (one document read, one knit's file
# state), in which each is computed once per `lines`; with none open, every call
# computes. The memo ends with that call.
local_doc_memo <- function(envir = parent.frame()) {
  if (!is.null(weft_env$doc_memo)) return(invisible())
  weft_env$doc_memo <- new.env(parent = emptyenv())
  withr::defer(weft_env$doc_memo <- NULL, envir = envir)
  invisible()
}

# `compute(lines)`, kept under `kind` for lines identical to `lines` while a
# memo is open (the last eight of each kind). A call that fails keeps nothing.
doc_memo <- function(kind, lines, compute) {
  m <- weft_env$doc_memo
  if (is.null(m)) return(compute(lines))
  for (e in m[[kind]]) if (identical(e$lines, lines)) return(e$value)
  v <- compute(lines)
  m[[kind]] <- c(list(list(lines = lines, value = v)), utils::head(m[[kind]], 7L))
  v
}

# ---- metadata blocks ---------------------------------------------------------

# The metadata blocks of a document, as the line numbers of the delimiters: the
# one reading of a document's front matter (rule 2.1.6). Like Pandoc, a block
# opens with a line that is exactly `---` (trailing white space allowed, no
# indent) at the top of the file (only blank lines above) or after a blank line,
# followed by a line that is not blank, closes at the next `---` or `...` line,
# and holds a YAML mapping. A block inside a backtick or tilde fence, or inside
# an HTML comment that starts a line, is not one; an indented `---` is not one
# either.
metadata_blocks <- function(lines) doc_memo("metadata_blocks", lines, metadata_blocks_)

metadata_blocks_ <- function(lines) {
  n <- length(lines)
  is_blank <- function(l) !nzchar(trim_ws(l))
  open <- integer()
  close <- integer()
  # only a fence line, a line that opens an HTML comment or a `---` line can matter: the rest are skipped,
  # in one pass
  opens_comment <- grepl("^ {0,3}<!--", lines)
  cand <- which(grepl("^[ \t>]*(`{3,}|~{3,})", lines) | opens_comment | grepl("^---[ \t\r]*$", lines))
  ends_comment <- which(grepl("-->", lines, fixed = TRUE))
  # the first line after `k` that closes the fence `fence`, or n + 1: a closing line is a fence line, so
  # only the candidates are tried (E2)
  next_close <- function(fence, k) {
    after <- cand[cand > k]
    hit <- after[grepl(fence, lines[after], perl = TRUE)]
    if (length(hit)) hit[1L] else n + 1L
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
    if (opens_comment[k]) {
      # the comment ends at the first `-->` after its `<!--`; one that never ends hides nothing
      same <- grepl("-->", sub("^.*?<!--", "", l, perl = TRUE), fixed = TRUE)
      end <- if (same) k else ends_comment[ends_comment > k][1L]
      k <- if (is.na(end)) k + 1L else end + 1L
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

# The lines of the front block, without its delimiters: the first metadata block,
# when only blank lines stand above it; character() when there is none. It is
# for the keys Quarto reads from that block alone, `engine:`, `knitr:` and
# `jupyter:` (rule 2.1.6). The document's own fields are every block's, merged:
# doc_front_lines().
front_block <- function(lines) {
  mb <- metadata_blocks(lines)
  if (!nrow(mb)) return(character())
  above <- lines[seq_len(mb$open[1L] - 1L)]
  if (any(nzchar(trim_ws(above)))) return(character())
  lines[(mb$open[1L] + 1L):(mb$close[1L] - 1L)]
}

# The front block read as YAML (list() when there is none, or it does not parse): where weft reads the
# keys `engine:`, `knitr:` and `jupyter:`, which Quarto honours in that block only (rule 2.1.6).
front_block_yaml <- function(lines) {
  doc_memo("front_block_yaml", lines, function(l) {
    fm <- front_block(l)
    y <- if (length(fm)) yaml_text(fm) else NULL
    if (is.list(y)) y else list()
  })
}

# The front matter of a document from its lines (rule 2.1.6): the fields of every
# metadata block, merged in order, a later block's top-level key replacing the
# whole value of an earlier one's (merge_front()).
doc_front_lines <- function(lines) {
  doc_memo("doc_front", lines, function(l) merge_front(meta_blocks_yaml(l, metadata_blocks(l))))
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
front_fields <- function(lines) doc_memo("front_fields", lines, front_fields_)

front_fields_ <- function(lines) {
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
# `_quarto.yml`), or "". Read once per folder in a walk (walk_memo()).
project_type <- function(path) {
  if (is.null(path) || is.na(path)) return("")
  d <- normalizePath(path, mustWork = FALSE)
  if (!dir.exists(d)) d <- dirname(d)
  walk_memo("project_type", d, function() {
    r <- find_quarto_root(d)
    if (is.null(r)) return("")
    p <- file.path(r, QUARTO_MARKERS)
    y <- tryCatch(yaml_read_file(p[file.exists(p)][1L]), error = function(e) NULL)
    ty <- if (is.list(y)) y$project$type else NULL
    if (is.character(ty) && length(ty) == 1L) ty else ""
  })
}

# The chunk options set for every chunk of a document: `knitr: opts_chunk:` then `execute:` over it, first of
# the project files that apply to the document at `path` (Quarto's merged view, rules P1 and P2; none when
# `path` is NULL), then of the document, `knitr:` read from the front block alone as Quarto reads it and
# `execute:` from the front matter as a whole. Option names are as written; a dot and a hyphen are the same
# name.
doc_execute <- function(lines, path = NULL) {
  pv <- quarto_project_view(path)
  kn <- front_block_yaml(lines)$knitr
  ex <- doc_front_lines(lines)$execute
  opts_chunk <- function(k) if (is.list(k)) k$opts_chunk else NULL
  sets <- list(opts_chunk(pv[["knitr"]]), pv[["execute"]], opts_chunk(kn), ex)
  Reduce(function(out, o) {
    if (is.list(o) && !is.null(names(o))) out[names(o)] <- o
    out
  }, sets, list())
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
  errs <- new.env(parent = emptyenv())
  errs$v <- rows$error
  add <- function(i, msg) {
    errs$v[i] <- if (is.na(errs$v[i])) msg else paste(errs$v[i], msg, sep = "\n")
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
  rows$error <- errs$v
  rows
}

# ---- chunks ------------------------------------------------------------------

# The executed chunks of a document: header line, close line, engine, and the
# header's options as written.
find_chunks <- function(lines) doc_memo("find_chunks", lines, find_chunks_)

find_chunks_ <- function(lines) {
  n <- length(lines)
  mb <- metadata_blocks(lines)
  inyaml <- rep(FALSE, n)
  for (b in seq_len(nrow(mb))) inyaml[mb$open[b]:mb$close[b]] <- TRUE
  begin <- "^[ \t>]*(`{3,})[ \t]*\\{[ \t]*([A-Za-z0-9_]+)(.*)\\}[ \t]*$"
  # a chunk header is a fence line: only those are looked at, in one pass; a closing line is a fence line
  # too, metadata or not, so the close is looked for among those (E2)
  fl <- which(grepl("^[ \t>]*(`{3,}|~{3,})", lines))
  cand <- fl[!inyaml[fl]]
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
      after <- fl[fl > k]
      hit <- after[grepl(close_re, lines[after], perl = TRUE)]
      j <- if (length(hit)) hit[1L] else n + 1L
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

# The prefix of a `#|` line up to the dash of a list item, and up to the colon of a key (S5).
OPT_ITEM_RE <- "^[ \t]*#\\|[ ]?[ \t]*-"
OPT_KEY_RE <- "^[ \t]*#\\|[ ]?[A-Za-z0-9_.-]+[ \t]*:"

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

# One chunk's caption rows, with their static errors. `lines` are the dequoted lines of `cr`
# (chunk_code_regions()); `code_keys`, the key lines of the `!expr` caption options that are R code (C10).
scan_chunk_captions <- function(lines, ch, doc_exec, file, config, cr, code_keys = integer(),
                                filter_doc = FALSE, named_filter = FALSE) {
  label <- ch$label
  hdr <- ch$hdr
  optblk <- ch$optblk
  dq <- cr$dq
  rows <- list()
  rem <- integer(length(lines))   # characters taken off the front of a line
  keep <- rep(FALSE, length(lines))
  txt <- lines
  regions <- list()   # option, first, last, kind of region
  # `regions` with one more region, unless the region holds no line
  add_region <- function(regions, option, first, last, form, item = FALSE) {
    if (first > last) return(regions)
    c(regions, list(list(option = option, first = first, last = last, form = form, item = item)))
  }
  for (o in optblk) {
    if (!(o$name %in% CAPTION_OPTIONS)) next
    # R code that calls weft() is read as code, not as markup (C10)
    if (identical(o$form, "expr") && o$key %in% code_keys) next
    if (o$form == "list") {
      for (it in o$items) {
        regions <- add_region(regions, o$name, it$first, it$last, it$form, item = TRUE)
        if (it$form == "scalar") {
          new <- sub(OPT_ITEM_RE, "", txt[it$first])
          rem[it$first] <- rem[it$first] + nchar(txt[it$first]) - nchar(new)
          txt[it$first] <- new
        }
      }
    } else {
      regions <- add_region(regions, o$name, o$first, o$last, o$form)
      if (o$form != "block") {
        # the key is not part of the value
        new <- sub(OPT_KEY_RE, "", txt[o$first])
        rem[o$first] <- rem[o$first] + nchar(txt[o$first]) - nchar(new)
        txt[o$first] <- new
      }
    }
  }
  for (rg in regions) keep[rg$first:rg$last] <- TRUE
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
      shift <- cumsum(rem + dq)
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
    h <- header_literal_at(lines[ch$open], nm)
    if (!is.null(h)) {
      o <- lit_offsets(h$raw, cr$ls[ch$open] + h$start - 1)
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
  errs <- new.env(parent = emptyenv())
  errs$v <- rows$error
  add <- function(i, msg) {
    errs$v[i] <- if (is.na(errs$v[i])) msg else paste(errs$v[i], msg, sep = "\n")
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
  rows$error <- errs$v
  rows
}

# ---- parse data --------------------------------------------------------------

# The parse data of R code (lines, or one string), or NULL when it does not parse.
parse_data <- function(code) {
  p <- tryCatch(parse(text = paste(code, collapse = "\n"), keep.source = TRUE), error = function(e) NULL)
  if (is.null(p)) NULL else utils::getParseData(p)
}

# Parse data with its lookups built once (E4): `pos[id]`, the row of node `id`, and `kids[[id]]`, the rows of
# its children in source order.
pd_index <- function(pd) {
  n <- if (nrow(pd)) max(pd$id) else 0L
  pos <- integer(n)
  pos[pd$id] <- seq_len(nrow(pd))
  o <- order(pd$line1, pd$col1)
  g <- split(o, pd$parent[o])
  p <- as.integer(names(g))
  keep <- p >= 1L & p <= n
  kids <- vector("list", n)
  kids[p[keep]] <- g[keep]
  list(pd = pd, pos = pos, kids = kids)
}

# The rows of the children of node `id`, in source order.
pd_kids <- function(ix, id) {
  if (id < 1L || id > length(ix$kids)) return(integer())
  ix$kids[[id]] %||% integer()
}

# The children of node `id`, in source order.
pd_kid_rows <- function(ix, id) ix$pd[pd_kids(ix, id), , drop = FALSE]

# The parent of node `id`: integer() when `id` is not a node.
pd_parent <- function(ix, id) {
  r <- if (id >= 1L && id <= length(ix$pos)) ix$pos[id] else 0L
  if (r == 0L) integer() else ix$pd$parent[r]
}

# Is node `id` of the parse data `pd` dead code (rule 3.11.1, SC6): inside the body of an `if` whose
# condition, with parentheses that enclose the whole of it removed, is the constant `FALSE`? The `else` arm
# is live. It reads the `id`, `parent`, `token` and `text` columns and the start of each node, which both
# tree forms keep (`pd_index()` and `pd_tree()`), so the claim readers and `checks()` share it; a comment
# between `)` and the body is skipped by its token.
pd_dead_if <- function(pd, id) {
  if (!any(pd$token == "IF") || !any(pd$text == "FALSE")) return(FALSE)
  # the children of node `p`, comments left out, in source order
  kids <- function(p) {
    k <- which(pd$parent == p & pd$token != "COMMENT")
    k[order(pd$line1[k], pd$col1[k])]
  }
  # is row `r` the constant FALSE, within parentheses that enclose all of it?
  is_false <- function(r) {
    k <- kids(pd$id[r])
    if (length(k) == 3L && pd$token[k[1L]] == "'('" && pd$token[k[3L]] == "')'") return(is_false(k[2L]))
    length(k) == 1L && pd$token[k] == "NUM_CONST" && pd$text[k] == "FALSE"
  }
  cur <- id
  repeat {
    up <- pd$parent[match(cur, pd$id)]
    if (is.na(up) || up <= 0L) return(FALSE)
    k <- kids(up)
    if (length(k) >= 5L && pd$token[k[1L]] == "IF" && pd$token[k[4L]] == "')'" && pd$id[k[5L]] == cur &&
        is_false(k[3L])) {
      return(TRUE)
    }
    cur <- up
  }
}

# The value of a constant token as written (`"a"`, `1L`, `r"(x)"`), or NULL when it does not evaluate.
token_value <- function(tok) {
  tryCatch(eval(parse(text = tok, keep.source = FALSE)[[1L]]), error = function(e) NULL)
}

# The value of a string token when it is one string, else NULL.
str_token_value <- function(tok) {
  v <- token_value(tok)
  if (is_string(v)) v else NULL
}

# ---- weft() strings ----------------------------------------------------------

# The calls to `weft()` in indexed parse data `ix`, as `weft(...)` or `weft::weft(...)` (ST1), and `x %>% weft`
# with no parentheses (K3): the id of each call's expression (of the symbol's, for the last). The function
# position is exactly the symbol `weft` or `weft::weft` (K2): `obj$weft()` is not one.
weft_calls <- function(ix) {
  pd <- ix$pd
  out <- integer()
  for (id in pd$id[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == "weft"]) {
    fexpr <- pd_parent(ix, id)                 # the expr that names the function
    sib <- pd_kid_rows(ix, fexpr)
    if (nrow(sib) == 3L) {
      ok <- sib$token[1L] == "SYMBOL_PACKAGE" && sib$token[2L] %in% c("NS_GET", "NS_GET_INT") &&
        identical(sib$text[1L], "weft")
      if (!ok) next
    } else if (nrow(sib) != 1L) next
    call_id <- pd_parent(ix, fexpr)            # the call
    if (!length(call_id) || call_id == 0L) next
    kids <- pd_kid_rows(ix, call_id)
    if (!any(kids$token == "'('") || kids$id[1L] != fexpr) next
    out <- c(out, call_id)
  }
  # `x %>% weft`: the symbol is the right-hand side of a magrittr pipe
  for (id in pd$id[pd$token == "SYMBOL" & pd$text == "weft"]) {
    e <- pd_parent(ix, id)
    if (!length(e) || e == 0L || length(pd_kids(ix, e)) != 1L) next
    if (!is.na(weft_pipe_lhs(ix, e, "%>%"))) out <- c(out, e)
  }
  out
}

# The left-hand side of the pipe whose right-hand side is expression `id`, for the operators `ops`; NA
# when `id` is not one.
weft_pipe_lhs <- function(ix, id, ops = c("|>", "%>%")) {
  pe <- pd_parent(ix, id)
  if (!length(pe) || pe == 0L) return(NA_integer_)
  sib <- pd_kid_rows(ix, pe)
  at <- match(id, sib$id)
  if (!is.na(at) && at == 3L && nrow(sib) == 3L && sib$token[2L] %in% c("PIPE", "SPECIAL") &&
      sib$text[2L] %in% ops && sib$token[1L] == "expr") return(sib$id[1L])
  NA_integer_
}

# The expression a call passes as `x` (ST2, C6): the argument named `x`, else the first given without a
# name. On the right of a pipe the left-hand side is `x` unless an argument is named `x`; the placeholder
# (`_` of `|>`, `.` of `%>%`) as an argument puts it where it stands (K3). NA when there is none.
weft_call_arg <- function(ix, call_id) {
  kids <- pd_kid_rows(ix, call_id)
  op <- which(kids$token == "'('")[1L]
  lhs <- weft_pipe_lhs(ix, call_id)
  if (is.na(op)) return(lhs)                   # `x %>% weft`
  pipe_op <- ""
  if (!is.na(lhs)) pipe_op <- pd_kid_rows(ix, pd_parent(ix, call_id))$text[2L]
  after <- kids[seq_len(nrow(kids)) > op, , drop = FALSE]
  args <- list()
  name <- NA_character_
  for (k in seq_len(nrow(after))) {
    tk <- after$token[k]
    if (tk == "SYMBOL_SUB") {
      name <- after$text[k]
    } else if (tk == "expr") {
      ch <- pd_kid_rows(ix, after$id[k])
      mark <- nrow(ch) == 1L && ((pipe_op == "|>" && ch$token == "PLACEHOLDER") ||
                                   (pipe_op == "%>%" && ch$token == "SYMBOL" && ch$text == "."))
      args[[length(args) + 1L]] <- list(name = name, id = after$id[k], mark = mark)
      name <- NA_character_
    } else if (tk == "','") {
      name <- NA_character_
    }
  }
  nm <- vapply(args, function(a) a$name, "")
  pick <- which(nm == "x")[1L]
  if (is.na(pick)) pick <- which(is.na(nm))[1L]
  anymark <- any(vapply(args, function(a) a$mark, NA))
  if (is.na(lhs)) return(if (is.na(pick)) NA_integer_ else args[[pick]]$id)
  if (!anymark) return(if (!is.na(pick) && identical(nm[pick], "x")) args[[pick]]$id else lhs)
  if (is.na(pick)) return(NA_integer_)
  if (args[[pick]]$mark) lhs else args[[pick]]$id
}

# ---- (the strings given to weft()) ----

# The `STR_CONST` tokens a `weft()` call reads (C7): the argument is one string literal, or a `c()` (or
# `base::c()`) whose literal arguments are each read. The ids of the tokens.
weft_arg_literals <- function(ix, argid) {
  one <- function(id) {
    k <- pd_kid_rows(ix, id)
    if (nrow(k) == 1L && k$token == "STR_CONST") k$id else integer()
  }
  top <- one(argid)
  if (length(top)) return(top)
  kids <- pd_kid_rows(ix, argid)
  op <- which(kids$token == "'('")
  if (!length(op) || op[1L] < 2L || kids$token[1L] != "expr") return(integer())
  fk <- pd_kid_rows(ix, kids$id[1L])
  is_c <- (nrow(fk) == 1L && fk$token == "SYMBOL_FUNCTION_CALL" && fk$text == "c") ||
    (nrow(fk) == 3L && identical(fk$token, c("SYMBOL_PACKAGE", "NS_GET", "SYMBOL_FUNCTION_CALL")) &&
       fk$text[1L] == "base" && fk$text[3L] == "c")
  if (!is_c) return(integer())
  out <- integer()
  for (id in kids$id[seq_len(nrow(kids)) > op[1L] & kids$token == "expr"]) out <- c(out, one(id))
  out
}

# The string constants of indexed parse data `ix` that are (`inside = TRUE`) or are not (`FALSE`) within the
# nodes `root_ids`, less a string used as a name (`"a" = 1`), a raw string and one R shortens to
# `[N chars ...]`: their ids, in source order. The phrase strings (inside lookup() and brk() calls) and the
# strings not given to weft() (5.12.3) are both read this way.
pd_strings <- function(ix, root_ids, inside = TRUE) {
  pd <- ix$pd
  sc <- which(pd$token == "STR_CONST")
  under <- vapply(sc, function(r) {
    cur <- pd$parent[r]
    while (length(cur) && cur > 0L) {
      if (cur %in% root_ids) return(TRUE)
      cur <- pd_parent(ix, cur)
    }
    FALSE
  }, NA)
  sc <- sc[under == inside]
  # a string that is a name (`"a" = ...`): the next of its siblings is `=`
  named <- vapply(sc, function(r) {
    sib <- pd_kid_rows(ix, pd$parent[r])
    sib <- sib[sib$line1 > pd$line2[r] | (sib$line1 == pd$line2[r] & sib$col1 > pd$col2[r]), , drop = FALSE]
    nrow(sib) > 0L && sib$token[1L] %in% c("EQ_SUB", "EQ_ASSIGN")
  }, NA)
  sc <- sc[!named]
  sc <- sc[grepl("^[\"'].*[\"']$", pd$text[sc]) & !grepl("^\\[[0-9]+ chars", pd$text[sc])]
  sc <- sc[order(pd$line1[sc], pd$col1[sc])]
  pd$id[sc]
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

# Literal strings of R code, one row each, in order: `line` and `col` (of the token's first character,
# within the code, a tab one character), `text` (the whole token), `value`, `raw` (the contents as typed),
# `open` (the characters before them).
empty_literals <- function() {
  data.frame(line = integer(), col = integer(), text = character(), value = character(),
             raw = character(), open = integer(), stringsAsFactors = FALSE)
}

# The rows of the string tokens `ids` of indexed parse data `ix` of the lines `code`: a token whose value
# is not one string is left out. The one way a string token is placed (C9, K10).
str_token_rows <- function(ix, ids, code) {
  pd <- ix$pd
  rows <- lapply(unique(ids), function(id) {
    d <- pd[ix$pos[id], , drop = FALSE]
    tok <- paste(utils::getParseText(pd, id), collapse = "\n")
    val <- str_token_value(tok)
    if (is.null(val)) return(NULL)
    sh <- str_token_shape(tok)
    data.frame(line = d$line1, col = parse_char_col(code[d$line1], d$col1), text = tok, value = val,
               raw = substr(tok, sh$open + 1L, nchar(tok) - sh$close), open = sh$open,
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) return(empty_literals())
  out <- out[order(out$line, out$col), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# The literal strings given to weft() (C5 to C8) in indexed parse data `ix` of `code`: the one reader the
# scanner and the lints share (C9).
weft_literals_pd <- function(ix, code) {
  ids <- integer()
  for (call_id in weft_calls(ix)) {
    argid <- weft_call_arg(ix, call_id)
    if (!is.na(argid)) ids <- c(ids, weft_arg_literals(ix, argid))
  }
  str_token_rows(ix, ids, code)
}

weft_literals <- function(code, pd = NULL) {
  if (is.null(pd)) {
    if (!length(code) || !any(grepl("weft", code, fixed = TRUE))) return(empty_literals())
    pd <- parse_data(code)
  }
  if (is.null(pd)) return(empty_literals())
  weft_literals_pd(pd_index(pd), code)
}

# The scanner's rows for the literal strings given to weft() in `code`, whose first line is line `first` of
# the document and whose lines start at the file offsets `ls` (a column of the code plus its line's start is
# a file offset). `option` names the chunk option the code is the value of (C10), NA for a chunk's code.
# `lit` is the literals when the caller has them.
scan_weft_code <- function(code, first, label, file, config, ls, option = NA_character_, lit = NULL) {
  if (is.null(lit)) lit <- weft_literals(code)
  if (!nrow(lit)) return(NULL)
  rows <- list()
  for (q in seq_len(nrow(lit))) {
    val <- lit$value[q]
    r <- scan_rows(val, file = file, first_line = first + lit$line[q] - 1L, config = config)
    if (!nrow(r)) next
    tokstart <- ls[lit$line[q]] + lit$col[q] - 1
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
    # a row's line is the source line of its first character, read from its mapped offset, not a count of
    # the newlines the value holds (an escaped `\n` is not a source line) (K1)
    r$line <- as.integer(first + findInterval(r$fstart, ls) - 1L)
    rows[[length(rows) + 1L]] <- r
  }
  if (!length(rows)) return(NULL)
  rows <- bind_scan_rows(rows)
  rows$context <- "weft"
  rows$chunk <- label
  rows$option <- option
  rows
}

# ---- the R code of a document (A5) --------------------------------------------

# Every region of R code in a document's lines, from one reading of its chunks. `body` has one region per
# chunk (whatever its engine): the code after the `#|` block. `caption` has the code of the computed
# captions (C10, F4, F5): the `!expr` value of a `#|` caption option (`kind` "expr") and a header caption
# option whose value is not a string ("header"). The code of a block-quoted chunk is read without its `>`
# prefix (K20). A region has its `code` lines, `first` (the document line of the first), `ls` (the file
# offset each code line starts at, the prefix taken off included, so that a column of the code plus it is a
# file offset), `chunk` (the index of its chunk), `option` and `key` (the line of a `!expr` option's key),
# and a memo, so that its code is parsed once (E3). Also: the dequoted `lines`, what dequoting took off each
# line (`dq`), the line starts `ls` and the labelled chunks `chs`.
chunk_code_regions <- function(lines) {
  dl <- dequote_chunks(lines)
  dq <- nchar(lines) - nchar(dl)
  cls <- line_starts(lines) + dq
  chs <- labelled_chunks(dl)
  n <- length(lines)
  region <- function(kind, i, first, code, option = NA_character_, key = NA_integer_) {
    list(kind = kind, chunk = i, option = option, key = key, first = first, code = code,
         ls = cls[first + seq_along(code) - 1L], memo = new.env(parent = emptyenv()))
  }
  body <- list()
  caps <- list()
  for (i in seq_along(chs)) {
    ch <- chs[[i]]
    first <- ch$oi$code_first
    last <- min(ch$close, n + 1L) - 1L
    body[[i]] <- region("body", i, first, if (last >= first) dl[first:last] else character())
    for (o in ch$optblk) {
      if (!(o$name %in% CAPTION_OPTIONS) || !identical(o$form, "expr")) next
      ec <- expr_option_code(dl, o)
      if (!is.null(ec)) caps[[length(caps) + 1L]] <- region("expr", i, ec$first, ec$code, o$name, o$key)
    }
    for (nm in names(ch$hdr$opts)) {
      if (!(nm %in% CAPTION_OPTIONS) || !is.null(ch$hdr$opts[[nm]]$literal)) next
      code <- header_option_code(dl[ch$open], nm, ch$hdr$opts[[nm]]$text)
      if (!is.null(code)) caps[[length(caps) + 1L]] <- region("header", i, ch$open, code, nm)
    }
  }
  list(lines = dl, dq = dq, ls = cls, chs = chs, body = body, caption = caps)
}

# The caption code regions of chunk `i`.
chunk_caption_regions <- function(cr, i) Filter(function(rg) rg$chunk == i, cr$caption)

# A region's parse data, indexed: parsed on first use and kept (E3). NULL when the code does not parse.
region_ix <- function(rg) {
  m <- rg$memo
  if (!exists("ix", envir = m, inherits = FALSE)) {
    pd <- parse_data(rg$code)
    m$ix <- if (is.null(pd)) NULL else pd_index(pd)
  }
  m$ix
}

# Does a region's code call weft()? Then a `!expr` caption is R code to be read for the strings it holds,
# and not scanned as markup (C10). Any other `!expr` stays as it was: an expression that holds a string with
# a construct is the error of 1.10.3 and 1.10.4.
region_calls_weft <- function(rg) {
  if (!any(grepl("weft", rg$code, fixed = TRUE))) return(FALSE)
  ix <- region_ix(rg)
  !is.null(ix) && length(weft_calls(ix)) > 0L
}

# The literal strings of a region's code (rows as empty_literals()), read once each: `weft`, those given to
# weft() (C9); `phrase`, those inside lookup() and brk() calls; `other`, those outside the argument weft()
# reads (5.12.3). The last two leave out names, as pd_strings() does.
region_literals <- function(rg, which = c("weft", "phrase", "other")) {
  which <- match.arg(which)
  m <- rg$memo
  key <- paste0("lit_", which)
  if (!is.null(m[[key]])) return(m[[key]])
  code <- rg$code
  gate <- switch(which,
                 weft = any(grepl("weft", code, fixed = TRUE)),
                 phrase = any(grepl("lookup", code, fixed = TRUE) | grepl("brk", code, fixed = TRUE)),
                 other = any(grepl("[\"']", code)))
  ix <- if (length(code) && gate) region_ix(rg)
  out <- if (is.null(ix)) empty_literals() else switch(which,
    weft = weft_literals_pd(ix, code),
    phrase = str_token_rows(ix, pd_strings(ix, phrase_calls(ix), inside = TRUE), code),
    other = str_token_rows(ix, pd_strings(ix, weft_args(ix), inside = FALSE), code))
  m[[key]] <- out
  out
}

# The calls to lookup() and brk() in indexed parse data: the id of each call's expression.
phrase_calls <- function(ix) {
  pd <- ix$pd
  out <- integer()
  for (id in pd$id[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text %in% c("lookup", "brk")]) {
    call_id <- pd_parent(ix, pd_parent(ix, id))
    if (length(call_id) && call_id != 0L) out <- c(out, call_id)
  }
  out
}

# The expressions the weft() calls in indexed parse data read as `x`.
weft_args <- function(ix) {
  out <- integer()
  for (call_id in weft_calls(ix)) {
    ex <- weft_call_arg(ix, call_id)
    if (!is.na(ex)) out <- c(out, ex)
  }
  out
}

# A region's literal strings placed in the document: `start` (the file offset of the contents' first
# character), `raw` (the contents as typed), `token`, `value` and `line` (the document line of the string).
chunk_literals <- function(rg, which = c("weft", "phrase", "other")) {
  lit <- region_literals(rg, which)
  data.frame(start = rg$ls[lit$line] + lit$col - 1 + lit$open, raw = lit$raw, token = lit$text,
             value = lit$value, line = as.integer(rg$first + lit$line - 1L), stringsAsFactors = FALSE)
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

# The start of option `nm` in a chunk header line, up to its value: `nm = `.
header_opt_re <- function(nm) paste0("(?<![A-Za-z0-9_.])", gsub(".", "\\.", nm, fixed = TRUE), "[ \t]*=[ \t]*")

# Where the literal string given to header option `nm` sits in chunk header line `hl` (S5): `start`, the
# column of its contents' first character, and `raw`, the contents as typed; NULL when there is none. The
# scanner and the lint mask place a header caption with this.
header_literal_at <- function(hl, nm) {
  pat <- paste0(header_opt_re(nm), "(?:\"((?:[^\"\\\\]|\\\\.)*)\"|'((?:[^'\\\\]|\\\\.)*)')")
  mm <- regexpr(pat, hl, perl = TRUE)
  if (mm < 0L) return(NULL)
  cs <- attr(mm, "capture.start")
  cl <- attr(mm, "capture.length")
  g <- if (cs[1L] > 0L) 1L else 2L
  list(start = cs[g], raw = substr(hl, cs[g], cs[g] + cl[g] - 1L))
}

# The R code of the header option `nm` of a chunk header line (an rmarkdown `fig.cap = weft(...)`), padded
# so that it keeps its columns, or NULL. `text` is the option's deparsed value. Trailing white space after
# the closing brace is not part of the header (F12).
header_option_code <- function(hl, nm, text) {
  hl <- sub("[ \t\r]+$", "", hl)
  st <- regexpr(header_opt_re(nm), hl, perl = TRUE)
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
# captions and weft() strings. `cr` is the document's code regions (chunk_code_regions()) when the
# caller has them; `path` as for scan_document().
scan_extra_rows <- function(lines, file = NA_character_, config = NULL, project = "", filter_doc = FALSE,
                            named_filter = NULL, cr = NULL, path = NULL) {
  if (is.null(named_filter)) named_filter <- document_names_from(lines, file, config) %in% c("python", "julia")
  fm <- scan_front_matter_rows(lines, file, config, project, filter_doc, named_filter)
  caps <- list()
  strs <- list()
  doc_exec <- doc_execute(lines, path)
  if (is.null(cr)) cr <- chunk_code_regions(lines)
  scan <- function(rg, label) {
    scan_weft_code(rg$code, rg$first, label, file, config, rg$ls, rg$option, lit = region_literals(rg, "weft"))
  }
  for (i in seq_along(cr$chs)) {
    ch <- cr$chs[[i]]
    capr <- chunk_caption_regions(cr, i)
    code_keys <- vapply(Filter(function(rg) rg$kind == "expr" && region_calls_weft(rg), capr),
                        function(rg) as.integer(rg$key), 0L)
    caps[[length(caps) + 1L]] <- scan_chunk_captions(cr$lines, ch, doc_exec, file, config, cr, code_keys,
                                                    filter_doc, named_filter)
    body <- cr$body[[i]]
    if (identical(tolower(ch$engine), "r") && length(body$code)) strs[[length(strs) + 1L]] <- scan(body, ch$label)
    for (rg in capr) strs[[length(strs) + 1L]] <- scan(rg, ch$label)
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
# file with children is lenient about the ids it cannot see. `path` is the document's file, whose project
# files set chunk options too (doc_execute()); NULL: none are read.
scan_document <- function(lines, file = NA_character_, config = NULL, project = "", cr = NULL, path = NULL) {
  text <- paste(lines, collapse = "\n")
  fd <- filter_resolves(lines, file)
  nf <- document_names_from(lines, file, config) %in% c("python", "julia")
  extra <- scan_extra_rows(lines, file, config, project, fd, nf, cr, path)
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
