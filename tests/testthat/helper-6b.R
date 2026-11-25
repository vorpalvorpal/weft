# Helpers for package 6b: the carrier, and publishing from R (dev/design-6.md
# N40 to N48, N130h steps 1 and 2). ASCII only.
#
# INTERFACE FIXED HERE (the note leaves these internal names open):
#   weft:::values_source_names(path)
#       N45: the names a source file names. `path` is the path of a document;
#       the function reads it (and the files its {{< include >}} shortcodes
#       name, relative to it, recursively). It returns a character vector of
#       unique NAMEs, in no fixed order (tests sort it). Reserved words of N6
#       are never in it.
#   Everything else is reached through weft:::values_block() (E2: weft_put() is gone)
#   (its returned text is parsed by b6_parse()), weft_values_write(), and
#   knits of small .Rmd documents with b6_knit().
#
# READINGS TAKEN where the note is open (each is one place to change):
#   * The text weft:::values_block() returns is the fenced block (N20, N44)
#     or the bare JSON; b6_parse() accepts both. Tests pin only that it is a
#     character string of class "weft_values" that parses as schema 1.
#   * Key order (N20's example): weft, lang, run, at come in that order, then
#     values; a record's t comes first and v (when written) second. Where
#     `cell` and `checks` sit is not pinned.
#   * values_block() raises weft_values_error for E40 to E44 (N2) and makes an
#     error record for E45 (N47: "anything else"). The record-level path (N43)
#     makes an error record for both E44 and E45.
#   * An error record's `why` holds `{S}` for the subject, the text of E44 or
#     E45 with its leading `{name}` replaced by `{S}` (N22, E16).
#   * Outside a knit "the document's folder" for N48 is the working
#     directory.

# ---- parsing --------------------------------------------------------------

# the JSON object text of a block text: strip fence lines when present
b6_json_text <- function(x) {
  x <- paste(as.character(x), collapse = "\n")
  lines <- strsplit(x, "\n", fixed = TRUE)[[1]]
  keep <- !grepl("^`{3,}", lines) & nzchar(trimws(lines))
  paste(lines[keep], collapse = "\n")
}

b6_read_json <- function(txt) {
  jsonlite::fromJSON(txt, simplifyVector = FALSE)
}

# the parsed block (a list with weft, lang, run, at, values, ...) of the text
# weft:::values_block() returns
b6_parse <- function(x) b6_read_json(b6_json_text(x))

# the raw JSON text of that
b6_text <- function(x) b6_json_text(x)

# the top-level key order of a JSON text
b6_keys <- function(txt) names(b6_read_json(txt))

# the record weft:::values_block() (E2 PB3, the internal block maker) makes of one R value
b6_rec <- function(x) b6_parse(weft:::values_block(v = x))$values$v

# only the members of a record the note pins (not `type`, not `checks`)
b6_core <- function(rec) {
  out <- list(t = rec$t)
  if (!is.null(rec$v)) {
    out$v <- if (identical(rec$t, "list")) lapply(rec$v, b6_core) else rec$v
  }
  if (!is.null(rec$of)) out$of <- rec$of
  if (identical(rec$t, "list")) {
    out$keys <- if (is.null(rec$keys)) NULL else unlist(rec$keys)
    if (is.null(out$v)) out$v <- list()
  }
  if (!is.null(rec$why)) out$why <- rec$why
  out
}

# ---- expected records ----------------------------------------------------

b6_e_bool  <- function(v) list(t = "bool", v = v)
b6_e_int   <- function(v) list(t = "int", v = v)
b6_e_float <- function(v) list(t = "float", v = v)
b6_e_str   <- function(v) list(t = "string", v = v)
b6_e_date  <- function(v) list(t = "date", v = v)
b6_e_miss  <- function(why) list(t = "missing", why = why)
b6_e_list  <- function(of, elems, keys = NULL) {
  out <- list(t = "list", v = elems, of = of)
  out$keys <- keys
  out
}

# expect the record of R value `x` to be `expected` (core members only)
b6_expect_rec <- function(x, expected, info = NULL) {
  got <- b6_core(b6_rec(x))
  testthat::expect_equal(got, expected, info = info)
}

# ---- blocks in knitted output ---------------------------------------------

b6_open_re <- "^`{4,}\\s*\\{[^}]*\\.weft-values[^}]*\\}\\s*$"

# All weft-values blocks of a character vector of lines: a list of
# list(open, close, nlines, text, block, fence). `block` is the parsed JSON.
b6_blocks <- function(lines) {
  out <- list()
  i <- 1L
  n <- length(lines)
  while (i <= n) {
    if (grepl(b6_open_re, lines[i])) {
      fence <- nchar(sub("^(`+).*$", "\\1", lines[i]))
      j <- i + 1L
      while (j <= n && !grepl(sprintf("^`{%d,}\\s*$", fence), lines[j])) j <- j + 1L
      body <- if (j > i + 1L) lines[(i + 1L):(j - 1L)] else character()
      txt <- paste(body, collapse = "\n")
      parsed <- tryCatch(b6_read_json(txt), error = function(e) NULL)
      out[[length(out) + 1L]] <- list(open = i, close = j, nlines = length(body),
                                      text = txt, block = parsed, fence = fence)
      i <- j + 1L
    } else {
      i <- i + 1L
    }
  }
  out
}

# the names each block publishes, as a list of character vectors
b6_block_names <- function(blocks) lapply(blocks, function(b) names(b$block$values))

# the first line number of `pattern` (fixed) in lines, or NA
b6_line <- function(lines, pattern) {
  w <- which(grepl(pattern, lines, fixed = TRUE))
  if (length(w)) w[1] else NA_integer_
}

# ---- knitting -------------------------------------------------------------

# Knit a small .Rmd in this process (raw knitr output, no Pandoc). `lines` is
# the body after the set-up chunk. Returns render_rmd()'s list plus `blocks`
# (the weft-values blocks of the output). The environment has no draft flag and
# no run id unless given; files go in the document's folder.
b6_knit <- function(lines, draft = FALSE, env = NULL, files = NULL, ...) {
  vars <- c(WEFT_DRAFT = if (draft) "1" else NA_character_,
            WEFT_RUN = NA_character_,
            WEFT_COLLECT = NA_character_)
  for (n in names(env)) vars[[n]] <- env[[n]]
  res <- render_rmd(lines, format = "knit", in_process = TRUE,
                    env = vars, files = files, ...)
  res$blocks <- b6_blocks(res$text)
  res
}

# Expect a knit to have finished (a fixture is legal; a failure is the
# package's)
b6_expect_knitted <- function(res) {
  testthat::expect_false(res$failed, label = paste("the knit finished:", res$message))
  !isTRUE(res$failed)
}

# the file a test document is, for N45 tests
b6_write_doc <- function(lines, name = "doc.Rmd", dir = NULL, extra = list()) {
  if (is.null(dir)) dir <- withr::local_tempdir(.local_envir = parent.frame())
  writeLines(lines, file.path(dir, name), useBytes = TRUE)
  for (f in names(extra)) writeLines(extra[[f]], file.path(dir, f), useBytes = TRUE)
  file.path(dir, name)
}

# ---- E2 (dev/design-e2.md): the knit, then the filter on its markdown --------------------------------

# the knit, then the filter on its markdown, as a knitr document (2.13.13)
e2_render <- function(lines, ..., to = "plain") {
  k <- b6_knit(lines, ...)
  k$filtered <- filter_md(k$text, name = "doc.Rmd", to = to)
  k
}

# an R chunk as lines (hidden by default), for the E2 tests
e2_chunk <- function(label, ..., opts = "include=FALSE") {
  c(sprintf("```{r %s, %s}", label, opts), c(...), "```", "")
}

# the lines of the blocks the hooks wrote, for the names each publishes, in order
e2_names <- function(res) unlist(b6_block_names(res$blocks))

# knitr::knit() of a small .Rmd in `envir` (T9): the knit's raw text, any error, and last_knit(). The set-up
# chunk calls weft::weft_setup(). Files go in a fresh temp folder.
e2_knit_in <- function(lines, envir, draft = FALSE, front = NULL, files = NULL, env = parent.frame()) {
  d <- write_doc(lines, TRUE, NULL, front, files, "doc", "rmd")
  withr::local_envvar(c(WEFT_DRAFT = if (draft) "1" else NA_character_, WEFT_RUN = NA_character_,
                        WEFT_COLLECT = NA_character_), .local_envir = env)
  withr::local_dir(d$dir, .local_envir = env)
  withr::defer(weft_restore_knitr(), envir = env)
  err <- tryCatch({
    knitr::knit(d$input, output = file.path(d$dir, "doc.md"), envir = envir, quiet = TRUE)
    NULL
  }, error = function(e) e)
  out <- file.path(d$dir, "doc.md")
  list(error = err, failed = !is.null(err), text = if (file.exists(out)) readLines(out, warn = FALSE, encoding = "UTF-8") else character(),
       knit = tryCatch(weft:::last_knit(), error = function(e) NULL), offset = d$offset, dir = d$dir)
}

# the text of the failures of a knit, as one string
e2_fail_text <- function(res) {
  f <- res$knit$failures
  if (is.null(f) || !nrow(f)) return("")
  paste(vapply(f$detail, function(x) paste(unlist(x), collapse = " "), ""), collapse = "\n")
}
