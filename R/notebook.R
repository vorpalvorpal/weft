# Jupyter notebooks and percent scripts, read the way Quarto 1.11.9 reads them (rule P7 of 2.1.6; the
# findings J1 to J8, K3 and K4 of dev/quarto-project-metadata.md; quarto.js: markdownFromNotebookJSON,
# mdFromRawCell, markdownFromJupyterPercentScript, percentCellHeader). The twins are weftlib/config.lua,
# weft/_config.py and Weft/src/config.jl.
#
#   P7  an `.ipynb` has front matter in its cells: the text of every raw or markdown cell, in cell order,
#       each followed by a blank line, read by the block rules of 2.1.6 (F1 to F3), so a cell whose source
#       is a `---` block is a block, and the later block wins per top-level key. Code cells hold none.
#   P7  a percent `.py` (one with a `# %% [markdown]` or `# %% [raw]` cell) the same, from its markdown and
#       raw cells, each with the leading `#` and one white-space character taken off its lines (or the cell
#       is a `"""` string); the text above the first `# %%` line is no cell.
#   J8  either is a Jupyter document whatever its front matter says (rule P4).
#
# The lints read a notebook as a document of its own (notebook_view() with `code = TRUE`): a markdown cell
# is prose, a raw cell is what Quarto writes for it (its text, or raw output fenced as `{=format}` when it
# names a format and is not a block), and a code cell is an executable chunk in the kernel's language. A
# finding is then placed in the notebook's JSON file (nb_place_findings()): at the line of the JSON string
# that holds the source line, and at the column of the character in that JSON line (escapes counted as
# written), so an editor that opens the file as text goes to the character. A percent script is read the
# same way (percent_doc_view()): its markdown cells prose with the `# ` taken off, its code cells Python
# chunks, and a finding is placed at its line and column in the `.py` file.
#
# Which files are such documents is Quarto's rule (rule P7, 5.1.8): an `.ipynb` the project lists (none in
# a `.` folder or a `_` folder), and a `.py` whose text has a `# %% [markdown]` or `# %% [raw]` line
# (quarto.js, isJupyterPercentScript); a `.py` with only code cells, and an ordinary module, are code.
# lints(), checks(), verify() and the gate read them all (lint_doc_files(), and the gate's own reading of
# its sides); status() asks only whether one exists (project_has_jupyter_doc()).

is_notebook_path <- function(path) grepl("\\.ipynb$", path, ignore.case = TRUE)
is_percent_path <- function(path) grepl("\\.py$", path, ignore.case = TRUE)

# Is the file one Quarto runs on the Jupyter engine by its extension alone (rule P4): an `.ipynb`, a `.py`.
is_jupyter_path <- function(path) is_notebook_path(path) | is_percent_path(path)

# ---- notebooks --------------------------------------------------------------------------------------

# The cells of a notebook's JSON text: for each, its `type`, its source strings `strs` as nbformat holds
# them, and the raw `format` it names (`raw_mimetype` or `format` in its metadata; NA when none); `lang`
# is the kernel's language. NULL when the text is not a notebook.
notebook_cells <- function(text) {
  nb <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(nb) || !is.list(nb$cells)) return(NULL)
  one <- function(x) if (is.character(x) && length(x) == 1L && nzchar(x)) x else NULL
  md <- if (is.list(nb$metadata)) nb$metadata else list()
  lang <- one(md$kernelspec$language) %||% one(md$language_info$name) %||% "python"
  cells <- lapply(nb$cells, function(cl) {
    if (!is.list(cl)) cl <- list()
    src <- cl$source
    strs <- if (is.character(src)) src else as.character(unlist(Filter(is.character, as.list(src))))
    meta <- if (is.list(cl$metadata)) cl$metadata else list()
    list(type = one(cl$cell_type) %||% "", strs = enc2utf8(strs),
         format = nb_raw_format(one(meta$raw_mimetype) %||% one(meta$format)))
  })
  list(cells = cells, lang = tolower(lang))
}

# The `{=format}` a raw cell's mimetype or format names, as Quarto's mdRawOutput() writes it; NA for none.
nb_raw_format <- function(x) {
  if (is.null(x)) return(NA_character_)
  known <- c("text/html" = "html", "text/latex" = "latex", "text/restructuredtext" = "rst",
             "application/rtf" = "rtf", "application/javascript" = "html")
  if (x %in% names(known)) unname(known[x]) else if (grepl("/", x, fixed = TRUE)) NA_character_ else x
}

# The lines of a cell's source (the strings joined, then cut at each newline; a final newline ends the last
# line and opens none), with the string each line starts in (`str`) and the characters of that string
# before it (`off`).
nb_cell_lines <- function(strs) {
  full <- paste(strs, collapse = "")
  n <- nchar(full)
  if (!n) return(list(lines = character(), str = integer(), off = integer()))
  nl <- gregexpr("\n", full, fixed = TRUE)[[1L]]
  nl <- if (nl[1L] > 0L) as.integer(nl) else integer()
  starts <- c(1L, nl[nl < n] + 1L)
  nc <- nchar(strs)
  before <- c(0L, cumsum(nc))[seq_along(strs)]
  live <- which(nc > 0L)
  si <- live[findInterval(starts - 1L, before[live])]
  list(lines = strsplit(full, "\n", fixed = TRUE)[[1L]], str = si, off = as.integer(starts - 1L - before[si]))
}

# `lines` fenced with backticks one longer than any run that starts a line of them (three at least), the
# fence info `info` after the opening ticks. `at` is each line's line in `lines` (NA for a fence).
nb_fenced <- function(lines, info) {
  lead <- regmatches(lines, regexpr("^[ \t>]*`+", lines))
  ticks <- strrep("`", max(3L, max(c(0L, nchar(gsub("[^`]", "", lead)))) + 1L))
  list(lines = c(paste0(ticks, info), lines, ticks), at = c(NA_integer_, seq_along(lines), NA_integer_))
}

# A notebook as the markdown text Quarto reads from it, from its JSON `text`: each raw and markdown cell,
# then a blank line (markdownFromNotebookJSON, the text front matter is read from). With `code = TRUE` it is
# the document the lints read: each code cell is a chunk in the kernel's language too, and a raw cell that
# names a format and is not a block is fenced as that raw output (mdFromRawCell). The result has the
# `lines`, and for each the `cell` it comes from and its line in that cell (`at`; NA for a fence or a blank
# line weft adds). NULL `cells` when the text is not a notebook.
notebook_view <- function(text, code = FALSE) {
  nb <- notebook_cells(text)
  if (is.null(nb)) return(list(lines = character(), cell = integer(), at = integer(), cells = NULL))
  is_block <- function(ln) length(ln) > 1L && grepl("^---[ \t]*$", ln[1L])
  parts <- lapply(seq_along(nb$cells), function(i) {
    cl <- nb$cells[[i]]
    ln <- nb_cell_lines(cl$strs)$lines
    plain <- list(lines = ln, at = seq_along(ln))
    body <- switch(cl$type,
      markdown = plain,
      raw = if (code && !is.na(cl$format) && !is_block(ln)) nb_fenced(ln, paste0("{=", cl$format, "}")) else plain,
      code = if (code) nb_fenced(ln, paste0("{", nb$lang, "}")) else NULL,
      NULL)
    if (is.null(body)) return(NULL)
    list(lines = c(body$lines, ""), cell = rep(i, length(body$lines) + 1L), at = c(body$at, NA_integer_))
  })
  parts <- Filter(Negate(is.null), parts)
  list(lines = as.character(unlist(lapply(parts, `[[`, "lines"))),
       cell = as.integer(unlist(lapply(parts, `[[`, "cell"))),
       at = as.integer(unlist(lapply(parts, `[[`, "at"))),
       cells = nb$cells)
}

# ---- placing a finding in the notebook's JSON ----------------------------------------------------------

# A JSON token: a string, a structural character, or a run of anything else (a number, `true`, `null`).
# The string's pattern is unrolled and possessive, so a long string (an image in an output) is matched
# without backtracking.
NB_TOKEN_RX <- "\"[^\"\\\\]*+(?:\\\\.[^\"\\\\]*+)*+\"|[][{}:,]|[^][{}:,\"\\s]++"
# One character of a JSON string as written: a surrogate pair, an escape, or a character.
NB_UNIT_RX <- "\\\\u[dD][89abAB][0-9a-fA-F]{2}\\\\u[dD][c-fC-F][0-9a-fA-F]{2}|\\\\u[0-9a-fA-F]{4}|\\\\.|."

# Where each cell's source strings are written in a notebook's JSON `text`: for each cell of the `cells`
# array, in order, the `line` and `col` in the file where each string's text starts (after its quote), and
# the string as written (`raw`, its quotes off); `key_line` and `key_col` are those of its `"source"` key.
# NULL when the text cannot be read so.
nb_json_sources <- function(text) {
  m <- gregexpr(NB_TOKEN_RX, text, perl = TRUE)[[1L]]
  if (m[1L] < 0L) return(NULL)
  st <- as.integer(m)
  len <- attr(m, "match.length")
  ch <- substring(text, st, st)
  opn <- ch %in% c("{", "[")
  cls <- ch %in% c("}", "]")
  after <- cumsum(opn) - cumsum(cls)
  before <- after - opn + cls
  n <- length(st)
  tok <- function(i) substring(text, st[i], st[i] + len[i] - 1L)
  nxt <- c(ch[-1L], "")
  # the token that closes the one opened at `i` (depth `d` before it)
  close_of <- function(i, d) {
    j <- which(seq_len(n) > i & after == d & cls)
    if (length(j)) j[1L] else n
  }
  key <- which(ch == "\"" & before == 1L & nxt == ":")
  key <- key[vapply(key, tok, "") == "\"cells\""]
  if (length(key) != 1L || key + 2L > n || ch[key + 2L] != "[") return(NULL)
  a <- key + 2L
  b <- close_of(a, 1L)
  nls <- gregexpr("\n", text, fixed = TRUE)[[1L]]
  line_start <- c(1L, if (nls[1L] > 0L) as.integer(nls) + 1L)
  place <- function(pos) {
    l <- findInterval(pos, line_start)
    c(l, pos - line_start[l] + 1L)
  }
  opens <- which(seq_len(n) > a & seq_len(n) < b & ch == "{" & before == 2L)
  lapply(opens, function(o) {
    e <- close_of(o, 2L)
    ks <- which(seq_len(n) > o & seq_len(n) < e & ch == "\"" & before == 3L & nxt == ":")
    ks <- ks[vapply(ks, tok, "") == "\"source\""]
    if (!length(ks)) return(list(line = integer(), col = integer(), raw = character(), key_line = NA_integer_,
                                 key_col = NA_integer_))
    k <- ks[1L]
    v <- k + 2L
    strs <- if (ch[v] == "[") {
      w <- close_of(v, 3L)
      which(seq_len(n) > v & seq_len(n) < w & ch == "\"" & before == 4L)
    } else if (ch[v] == "\"") v else integer()
    pk <- place(st[k])
    ps <- vapply(strs, function(i) place(st[i] + 1L), integer(2))
    raw <- vapply(strs, function(i) substring(text, st[i] + 1L, st[i] + len[i] - 2L), "")
    list(line = as.integer(ps[1L, ]), col = as.integer(ps[2L, ]), raw = unname(raw),
         key_line = pk[1L], key_col = pk[2L])
  })
}

# For each line of a notebook's view (notebook_view() with `code = TRUE`), where it is written in the JSON
# `text`: the JSON `line`, the `col` its first character is at, and the string as written from that
# character on (`raw`; NA for a line weft added, which is placed at the cell's `"source"` key). NULL when
# the JSON cannot be read so.
notebook_places <- function(text, view) {
  js <- nb_json_sources(text)
  if (is.null(js) || length(js) != length(view$cells)) return(NULL)
  per <- lapply(seq_along(view$cells), function(i) {
    cl <- nb_cell_lines(view$cells[[i]]$strs)
    s <- js[[i]]
    if (length(s$raw) != length(view$cells[[i]]$strs)) return(NULL)
    units <- lapply(s$raw, function(r) regmatches(r, gregexpr(NB_UNIT_RX, r, perl = TRUE))[[1L]])
    # the string a line starts in, as written from the line's first character, and the characters of it
    # written before that one
    raw <- vapply(seq_along(cl$lines), function(j) {
      u <- units[[cl$str[j]]]
      paste(u[seq_along(u) > cl$off[j]], collapse = "")
    }, "")
    skip <- vapply(seq_along(cl$lines), function(j) sum(nchar(units[[cl$str[j]]][seq_len(cl$off[j])])), 0L)
    list(line = s$line[cl$str], col = s$col[cl$str] + as.integer(skip), raw = raw,
         key_line = s$key_line, key_col = s$key_col)
  })
  if (any(vapply(per, is.null, NA))) return(NULL)
  n <- length(view$lines)
  out <- data.frame(line = rep(NA_integer_, n), col = rep(NA_integer_, n), raw = rep(NA_character_, n),
                    stringsAsFactors = FALSE)
  for (k in seq_len(n)) {
    p <- per[[view$cell[k]]]
    j <- view$at[k]
    if (is.na(j)) {
      out$line[k] <- p$key_line
      out$col[k] <- p$key_col
    } else {
      out$line[k] <- p$line[j]
      out$col[k] <- p$col[j]
      out$raw[k] <- p$raw[j]
    }
  }
  out
}

# The JSON line and column of column `col` of line `line` of a notebook's view, by its places
# (notebook_places()).
nb_place <- function(places, line, col) {
  if (is.na(line) || line < 1L || line > nrow(places) || is.na(places$line[line])) return(c(line, col))
  raw <- places$raw[line]
  # a percent script's line is the file's own text from `col` on (percent_doc_view())
  if (isTRUE(places$plain[line])) return(c(places$line[line], places$col[line] + col - 1L))
  if (is.na(raw)) return(c(places$line[line], places$col[line]))
  u <- regmatches(raw, gregexpr(NB_UNIT_RX, raw, perl = TRUE))[[1L]]
  k <- max(0L, min(length(u), col - 1L))
  c(places$line[line], places$col[line] + sum(nchar(u[seq_len(k)])))
}

# The findings `x` with those of each notebook placed in its JSON file (nb_place()), and those of each
# percent script in its `.py` file, the source of each read through `ctx`. A finding about the whole file
# (context "project") stays where it is.
nb_place_findings <- function(x, ctx) {
  if (!nrow(x)) return(x)
  for (f in unique(x$file[is_jupyter_path(x$file)])) {
    src <- tryCatch(ctx$source(f), error = function(e) NULL)
    pl <- if (is.list(src)) src$nb_places else NULL
    if (is.null(pl)) next
    for (i in which(x$file == f & x$context != "project")) {
      at <- nb_place(pl, x$line[i], x$col[i])
      end <- nb_place(pl, x$end_line[i], 1L)
      x$line[i] <- as.integer(at[1L])
      x$col[i] <- as.integer(at[2L])
      x$end_line[i] <- as.integer(end[1L])
    }
  }
  x
}

# The rows `x` read from a source `src` (checks, constructs, decision pointers) with their `cols`, lines of
# the document weft reads, placed at the line of the file: a notebook's JSON line, a percent script's own
# line (nb_place()). Any other source's rows are returned as they are.
src_place_lines <- function(src, x, cols = "line") {
  pl <- if (is.list(src)) src$nb_places else NULL
  if (is.null(pl) || !NROW(x)) return(x)
  for (cn in intersect(cols, names(x))) {
    x[[cn]] <- vapply(x[[cn]], function(l) as.integer(nb_place(pl, l, 1L)[1L]), 1L, USE.NAMES = FALSE)
  }
  x
}

# ---- percent scripts --------------------------------------------------------------------------------

PERCENT_SCRIPT_RX <- "^\\s*#\\s*%%+\\s+\\[(markdown|raw)\\]"
PERCENT_HEADER_RX <- "^\\s*#\\s*%%+\\s*(?:\\[(markdown|raw)\\])?\\s*(.*)?$"
# The test on a whole text, as Quarto makes it (multiline, any line end).
PERCENT_SCRIPT_TEXT_RX <- paste0("(*ANYCRLF)(?m)", PERCENT_SCRIPT_RX)
# A raw cell whose `# %%` line names a format is raw output.
PERCENT_RAW_FORMAT_RX <- "(^|\\s)(format|raw_mimetype)="

# Is a `.py` file's text (`bytes`, a raw vector) one Quarto claims as a percent script (quarto.js,
# isJupyterPercentScript): a `# %% [markdown]` or `# %% [raw]` line anywhere. A file that is not text (a
# NUL byte) is not.
is_percent_bytes <- function(bytes) {
  if (!length(bytes) || any(bytes == as.raw(0L))) return(FALSE)
  grepl(PERCENT_SCRIPT_TEXT_RX, rawToChar(bytes), perl = TRUE, useBytes = TRUE)
}

# The same, of the file at `path`; FALSE when it cannot be read.
is_percent_file <- function(path) {
  b <- tryCatch(readBin(path, "raw", file.size(path)), error = function(e) raw(), warning = function(w) raw())
  is_percent_bytes(b)
}

# The percent scripts under `root` that `use` reads (doc_path_ok()), as sorted relative paths: the `.py`
# files Quarto claims. Each `.py` is read once in a walk (walk_memo()).
percent_script_paths <- function(root, use = c("lint", "anchors", "setup")) {
  use <- match.arg(use)
  walk_memo(paste0("percent_", use), root, function() {
    py <- project_doc_paths(root, use, "\\.[Pp][Yy]$")
    py[vapply(py, function(rel) is_percent_file(file.path(root, rel)), NA, USE.NAMES = FALSE)]
  })
}

# The documents of the project at `root` that lints(), checks(), verify() and the gate read (rule P7, 5.1.8):
# its `.qmd` and `.Rmd` files, its notebooks and its percent scripts, as sorted relative paths.
lint_doc_files <- function(root) {
  sort(c(lint_files_under(root, LINT_DOC_EXT_RE), percent_script_paths(root, "lint")), method = "radix")
}

# The cells of a percent script, from its `lines`: for each `# %%` line, the cell's `type` ("code",
# "markdown" or "raw"), its `hdr` (that line's number) and the rest of that line (`opts`), and its body: the
# lines up to the next `# %%` line, its empty lines at either end dropped, as their line numbers `at` and
# the text Quarto reads from them (`lines`). A markdown or raw cell's lines have the leading `#` and one
# white-space character off, `cut` the characters taken off each (or, when the cell is wrapped in `"""`
# lines, the lines between). The text above the first `# %%` line is no cell.
percent_cells <- function(lines) {
  hdr <- regmatches(lines, regexec(PERCENT_HEADER_RX, lines, perl = TRUE))
  is_hdr <- lengths(hdr) > 0L
  cell <- cumsum(is_hdr)
  keep <- which(is_hdr)
  lapply(seq_along(keep), function(i) {
    h <- hdr[[keep[i]]]
    type <- if (nzchar(h[2L])) h[2L] else "code"
    at <- which(cell == i & !is_hdr)
    nb <- which(nzchar(trim_ws(lines[at])))
    at <- if (length(nb)) at[min(nb):max(nb)] else integer()
    body <- lines[at]
    cut <- integer(length(at))
    if (type != "code") {
      tq <- "^\"{3,}\\s*$"
      if (length(body) > 2L && grepl(tq, body[1L]) && grepl(tq, body[length(body)])) {
        at <- at[-c(1L, length(at))]
        body <- body[-c(1L, length(body))]
        cut <- integer(length(at))
      } else {
        m <- regexpr("^#\\s?", body, perl = TRUE)
        cut <- ifelse(m > 0L, attr(m, "match.length"), 0L)
        body <- substring(body, cut + 1L)
      }
    }
    list(type = type, hdr = keep[i], opts = h[3L], at = at, lines = body, cut = as.integer(cut))
  })
}

# A percent script as the markdown text Quarto reads its front matter from, from its `text`: each markdown
# and raw cell (percent_cells()), then a blank line. A raw cell that names a format (`format=` or
# `raw_mimetype=` on its `# %%` line) is raw output, fenced. A code cell holds no front matter, and is left
# out. A `.py` with no markdown or raw cell is no Quarto document (J7): character().
percent_view <- function(text) {
  lines <- split_source_lines(trim_ws(text))
  if (!any(grepl(PERCENT_SCRIPT_RX, lines, perl = TRUE))) return(character())
  out <- lapply(percent_cells(lines), function(cl) {
    if (cl$type == "code") return(NULL)
    body <- cl$lines
    if (cl$type == "raw" && grepl(PERCENT_RAW_FORMAT_RX, cl$opts)) body <- nb_fenced(body, "{=raw}")$lines
    c(body, "")
  })
  as.character(unlist(out))
}

# A percent script as the document the lints read, from its `text`, as notebook_view() with `code = TRUE`
# reads a notebook: each markdown cell is prose, a raw cell its text (or raw output fenced as `{=raw}`, as
# percent_view() has it), a code cell a Python chunk, each followed by a blank line. The result has the
# `lines`, and `places` (for nb_place()): for each line the `line` of the file it comes from and the `col`
# its first character is at, `plain` (the text from there on is the file's own). A fence or a blank line
# weft adds is placed at the cell's `# %%` line. NULL when the text is no percent script.
percent_doc_view <- function(text) {
  lines <- split_source_lines(text)
  if (!any(grepl(PERCENT_SCRIPT_RX, lines, perl = TRUE))) return(NULL)
  parts <- lapply(percent_cells(lines), function(cl) {
    info <- if (cl$type == "code") "{python}" else if (cl$type == "raw" && grepl(PERCENT_RAW_FORMAT_RX, cl$opts)) "{=raw}"
    if (is.null(info)) {
      body <- list(lines = cl$lines, line = cl$at, col = cl$cut + 1L)
    } else {
      f <- nb_fenced(cl$lines, info)
      body <- list(lines = f$lines, line = c(cl$hdr, cl$at, cl$hdr), col = c(1L, cl$cut + 1L, 1L))
    }
    list(lines = c(body$lines, ""), line = c(body$line, cl$hdr), col = c(body$col, 1L))
  })
  ln <- as.integer(unlist(lapply(parts, `[[`, "line")))
  list(lines = as.character(unlist(lapply(parts, `[[`, "lines"))),
       places = data.frame(line = ln, col = as.integer(unlist(lapply(parts, `[[`, "col"))),
                           raw = rep(NA_character_, length(ln)), plain = rep(TRUE, length(ln)),
                           stringsAsFactors = FALSE))
}

# The lines a Jupyter document's front matter is read from (rule P7): a notebook's raw and markdown cells
# (notebook_view()), or a percent script's (percent_view()), from the file's `text`.
jupyter_front_lines <- function(path, text) {
  if (is_notebook_path(path)) notebook_view(text)$lines else percent_view(text)
}
