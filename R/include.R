# Quarto's `{{< include >}}`, read the way Quarto 1.11.9 expands it (the include rules I1 to I6, from
# quarto.js: isBlockShortcode, parseShortcodeCapture, breakQuartoMd, processMarkdownIncludes,
# standaloneInclude and resolvePath). The one R reader of includes: the knit's line map (2.7.4), the
# names a source names (N45) and the hooks' lists (TR1, TR4), the named-unpublished lint (N144), the
# engine lint (5.8.9), a report's reads (4.6.5) and the readers of front matter (2.1.6 P4, P5) all take
# their includes from here. The Lua filter (weftlib/lines.lua), the Python package (weft._include_lines)
# and the Julia package (Weft/src/include.jl) are its twins.
#
#   I1  a line is an include only when the whole line is the shortcode: optional white space, `{{< `,
#       the name, the parameters, ` >}}`, optional white space; exactly one space inside each bracket;
#       the escaped `{{</* include x */>}}` is not one
#   I2  the name is `include`, lowercase, in the main document; any case in an included file
#   I3  the path is the first positional parameter: "...", '...' or a run with no white space or quote
#   I4  every path, at any depth, is resolved against the MAIN document's folder; a leading `/` against
#       the Quarto project root (the folder of `_quarto.yml`), else the main document's folder
#   I5  fences, executable cells and HTML comments do not hide an include; in the main document a cell
#       whose text holds ```` ```{shortcodes=false} ```` does (Quarto checks no cell in an included file)
#   I6  no depth limit; a file already reached is not read again, so a cycle ends

INCLUDE_LINE_RX <- "^\\s*\\{\\{< (?!/\\*)(.+?)(?<!\\*/) >\\}\\}\\s*$"

# The shortcode on a line that is one (I1): its name and its positional parameters, or NULL. A capture
# Quarto cannot parse (no name, an unclosed quote) is NULL: Quarto stops the render there.
block_shortcode <- function(line) {
  m <- regmatches(line, regexec(INCLUDE_LINE_RX, line, perl = TRUE))[[1L]]
  if (length(m) != 2L) return(NULL)
  cap <- m[2L]
  name <- regmatches(cap, regexpr("^/?[A-Za-z0-9_]+", cap))
  if (!length(name)) return(NULL)
  rest <- trimws(substring(cap, nchar(name) + 1L))
  params <- character()
  # the start of `rest` that `rx` matches, or NULL
  lead <- function(rx) {
    hit <- regmatches(rest, regexpr(rx, rest, perl = TRUE))
    if (length(hit)) hit else NULL
  }
  while (nzchar(rest)) {
    # a named parameter (key="v", key='v', key=v) is not a positional one
    named <- lead("^[A-Za-z0-9_-]+=\"[^\"]*\"") %||% lead("^[A-Za-z0-9_-]+='[^']*'") %||%
      lead("^[A-Za-z0-9_-]+=[^\"'\\s]+")
    if (!is.null(named)) {
      rest <- trimws(substring(rest, nchar(named) + 1L))
      next
    }
    p <- lead("^[^\"'\\s]+")
    quoted <- is.null(p)
    if (quoted) p <- lead("^\"[^\"]*\"|^'[^']*'")
    if (is.null(p)) return(NULL)
    rest <- trimws(substring(rest, nchar(p) + 1L))
    if (quoted) p <- substr(p, 2L, nchar(p) - 1L)
    params <- c(params, p)
  }
  list(name = name, params = params)
}

# The lines of the main document that sit in a cell Quarto does not expand includes in (I5): the cells
# are breakQuartoMd's (front matter, a block shortcode line, an executable cell ```` ```{lang} ````, and
# the markdown between), and a cell whose text holds ```` ```{shortcodes=false} ```` is skipped.
include_skipped_lines <- function(lines) {
  n <- length(lines)
  skip <- logical(n)
  if (!n || !any(grepl("shortcodes", lines, fixed = TRUE))) return(skip)
  cell_rx <- "^\\s*(```+)\\s*\\{([=A-Za-z][=A-Za-z0-9._]*)( *[ ,].*)?\\}\\s*$"
  end_rx <- "^\\s*(```+)\\s*$"
  buf <- integer()
  # `skip` with the lines `buf` of one cell marked when the cell's text holds ```` ```{shortcodes=false} ````
  flush <- function(skip, buf) {
    if (length(buf)) {
      txt <- paste(lines[buf], collapse = "\n")
      if (grepl("\\s*```\\s*\\{\\s*shortcodes\\s*=\\s*false\\s*\\}", txt, perl = TRUE)) skip[buf] <- TRUE
    }
    skip
  }
  blank <- function(k) k >= 1L && k <= n && !nzchar(trimws(lines[k]))
  yaml_delim <- function(k, skip_hr) {
    if (!grepl("^---\\s*$", lines[k], perl = TRUE)) return(FALSE)
    !(skip_hr && k > 1L && blank(k - 1L) && k < n && blank(k + 1L))
  }
  ticks <- function(x) regmatches(x, regexec(end_rx, x, perl = TRUE))[[1L]][2L]
  # a block shortcode line holds `{{< `: the others are not read one by one
  maybe <- grepl("{{< ", lines, fixed = TRUE)
  in_yaml <- FALSE
  in_cell <- FALSE
  in_code <- 0L
  for (k in seq_len(n)) {
    line <- lines[k]
    plain <- !in_cell && in_code == 0L && !in_yaml
    if (in_code == 0L && !in_cell && yaml_delim(k, !in_yaml)) {
      if (in_yaml) {
        skip <- flush(skip, c(buf, k))
        buf <- integer()
        in_yaml <- FALSE
      } else {
        skip <- flush(skip, buf)
        buf <- k
        in_yaml <- TRUE
      }
    } else if (plain && maybe[k] && !is.null(tryCatch(block_shortcode(line), error = function(e) NULL))) {
      skip <- flush(skip, buf)
      skip <- flush(skip, k)
      buf <- integer()
    } else if (plain && grepl(cell_rx, line, perl = TRUE)) {
      skip <- flush(skip, buf)
      in_cell <- TRUE
      in_code <- nchar(sub(cell_rx, "\\1", line, perl = TRUE))
      buf <- k
    } else if (in_code > 0L && grepl(end_rx, line, perl = TRUE) && nchar(ticks(line)) == in_code) {
      buf <- c(buf, k)
      if (in_cell) {
        in_cell <- FALSE
        skip <- flush(skip, buf)
        buf <- integer()
      }
      in_code <- 0L
    } else if (in_code == 0L && startsWith(line, "```")) {
      first <- strsplit(line, " ", fixed = TRUE)[[1L]][1L]
      in_code <- lengths(regmatches(first, gregexpr("`", first, fixed = TRUE)))
      buf <- c(buf, k)
    } else {
      buf <- c(buf, k)
    }
  }
  flush(skip, buf)
}

# The Quarto project root a leading `/` resolves against (I4): the folder of `_quarto.yml` above the main
# document's folder, else that folder.
include_root <- function(main_dir) {
  main_dir <- norm_path(main_dir)
  find_quarto_root(main_dir) %||% main_dir
}

# The includes of one file's lines (I1 to I5): a data frame of each include's line and the path it
# resolves to (absolute, normalised; the file may not exist). `main_dir` is the MAIN document's folder,
# `root` the project root (include_root()), `in_included` whether these lines are an included file's.
include_targets <- function(lines, main_dir, root = include_root(main_dir), in_included = FALSE) {
  none <- data.frame(line = integer(), path = character(), stringsAsFactors = FALSE)
  cand <- which(grepl("{{< ", lines, fixed = TRUE))
  if (!length(cand)) return(none)
  if (!in_included) {
    skip <- include_skipped_lines(lines)
    cand <- cand[!skip[cand]]
  }
  at <- integer()
  path <- character()
  for (k in cand) {
    sc <- tryCatch(block_shortcode(lines[k]), error = function(e) NULL)
    if (is.null(sc) || !length(sc$params)) next
    ok <- if (in_included) identical(tolower(sc$name), "include") else identical(sc$name, "include")
    if (!ok) next
    p <- sc$params[1L]
    p <- if (startsWith(p, "/")) paste0(sub("/+$", "", root), p) else
      if (grepl("^[A-Za-z]:[/\\\\]", p)) p else file.path(main_dir, p)
    at <- c(at, k)
    path <- c(path, norm_path(include_tidy(p)))
  }
  if (!length(at)) return(none)
  data.frame(line = at, path = path, stringsAsFactors = FALSE)
}

# A path with `.` and `..` taken out, as Node's resolve() does, before any folder of it need exist.
include_tidy <- function(p) {
  p <- gsub("\\\\", "/", p)
  lead <- regmatches(p, regexpr("^(/|[A-Za-z]:/)", p))
  parts <- strsplit(substring(p, nchar(lead) + 1L), "/", fixed = TRUE)[[1L]]
  out <- character()
  for (q in parts) {
    if (!nzchar(q) || q == ".") next
    if (q == "..") out <- out[-length(out)] else out <- c(out, q)
  }
  paste0(lead, paste(out, collapse = "/"))
}

# Every file a document includes, at any depth (I6), each read once: `files`, a list of `path` (absolute)
# and `lines`, in the order Quarto expands them, and `missing`, the paths an include names that are not
# a file. `lines` are the main document's own, when the caller has read them; `read(path)` gives a
# file's lines, or NULL for one that cannot be read (it then includes nothing). The main document is
# not in `files`. What a site does with a missing file is its own (I6).
include_walk <- function(path, lines = NULL, root = NULL,
                         read = function(p) tryCatch(read_source_lines(p), error = function(e) NULL)) {
  main <- norm_path(path)
  main_dir <- dirname(main)
  if (is.null(root)) root <- include_root(main_dir)
  # `acc` (the files found so far, the paths that are not a file, and every path reached) with the
  # includes of the lines `ln` added, depth first
  walk <- function(ln, in_included, acc) {
    tg <- include_targets(ln, main_dir, root, in_included)
    for (p in tg$path) {
      if (p %in% acc$seen) next
      if (!utils::file_test("-f", p)) {
        acc$missing <- c(acc$missing, p)
        next
      }
      acc$seen <- c(acc$seen, p)
      il <- read(p)
      acc$files[[length(acc$files) + 1L]] <- list(path = p, lines = il %||% character())
      if (length(il)) acc <- walk(il, TRUE, acc)
    }
    acc
  }
  acc <- list(files = list(), missing = character(), seen = main)
  if (is.null(lines)) lines <- read(main)
  if (length(lines)) acc <- walk(lines, FALSE, acc)
  list(files = acc$files, missing = unique(acc$missing))
}

# The text Quarto reads after it expands every include (I1 to I6): `lines` (the main document's own when
# `nested` is FALSE) with each include line replaced by the included file's expanded lines and a blank line,
# two when the include sits in an included file, as Quarto splices them. A file is expanded wherever it is
# included, but not inside itself, so a cycle ends; an include whose file is missing, or cannot be read
# (`read(path)` gives NULL), stays the line it is. The result is a list of `lines`, and for each the `file`
# (absolute) and `line` it came from (an added blank line is the include's own), and `at`, the line of
# `lines` it stands for (the include's line, for an included file's lines). `main_dir` is the MAIN
# document's folder, against which every path resolves (I4). `read` may also stop, and the call then stops.
include_expand <- function(path, lines = NULL, main_dir = dirname(norm_path(path)), root = include_root(main_dir),
                           read = function(p) {
                             txt <- tryCatch(read_source_text_or_null(p), error = function(e) NULL)
                             if (is.null(txt)) NULL else split_source_lines(txt)
                           },
                           seen = character(), nested = FALSE) {
  here <- norm_path(path)
  if (is.null(lines)) lines <- read(here) %||% character()
  n <- length(lines)
  out <- list(lines = as.list(lines), file = as.list(rep(here, n)), line = as.list(seq_len(n)), at = as.list(seq_len(n)))
  tg <- include_targets(lines, main_dir, root, in_included = nested)
  for (j in seq_len(nrow(tg))) {
    k <- tg$line[j]
    p <- tg$path[j]
    if (!utils::file_test("-f", p) || p %in% c(seen, here)) next
    il <- read(p)
    if (is.null(il)) next
    sub <- include_expand(p, il, main_dir, root, read, c(seen, here), nested = TRUE)
    pad <- if (nested) 2L else 1L
    out$lines[[k]] <- c(sub$lines, rep("", pad))
    out$file[[k]] <- c(sub$file, rep(here, pad))
    out$line[[k]] <- c(sub$line, rep(k, pad))
    out$at[[k]] <- rep(k, length(sub$lines) + pad)
  }
  list(lines = as.character(unlist(out$lines, use.names = FALSE)),
       file = as.character(unlist(out$file, use.names = FALSE)),
       line = as.integer(unlist(out$line, use.names = FALSE)),
       at = as.integer(unlist(out$at, use.names = FALSE)))
}

# The lines a document's front matter is read from (rules P4 and P5 of 2.1.6): its own `lines` with every
# include expanded (include_expand()), so an included file's blocks sit where its include sits and an
# include on line 1 can supply the front block. The document at `path`; NULL, or lines with no include, give
# `lines` as they are, as does a walk that fails. A notebook's or a percent script's cells are read as they
# are: Quarto reads their front matter with no include expanded (rule P7).
front_source_lines <- function(path, lines) {
  if (is.null(path) || !length(lines) || !any(grepl("{{< ", lines, fixed = TRUE))) return(lines)
  if (is_jupyter_path(path)) return(lines)
  doc_memo("front_source", c(path, lines), function(x) {
    tryCatch(include_expand(path, lines)$lines, error = function(e) lines)
  })
}
