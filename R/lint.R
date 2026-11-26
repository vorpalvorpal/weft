# The static lints (design-3): the entry point, the rule table, the findings
# structure and its printing, the lint configuration and the claim-word
# lexicon, and the `construct` lint.
#
# A rule is one row of `lint_rule_table()` (its id, spec, tier and scope) and one entry of
# `lint_rule_funs()` (its function: `(src, ctx)` for a file-scope rule, `(ctx)` for a
# project-scope one). Nothing is found by name; add both to add a rule.

lint_abort <- function(message) weft_abort(message, "weft_lint_error")

# ---- the rule table ------------------------------------------------------------------

# built once per session: findings are made by the thousand, each asking for the table
lint_rule_table <- function() {
  hit <- weft_env$lint_rule_table
  if (is.null(hit)) {
    hit <- lint_rule_table_build()
    weft_env$lint_rule_table <- hit
  }
  hit
}

# The file-scope rules that run on a script (C13): the ones that read only the rows and prose of its
# `weft()` literals.
LINT_SCRIPT_RULES <- c("numeral", "construct", "read", "block-start", "lone-bar", "if-zero", "name",
                       "inert-check", "long-guard", "claim-word", "literal-value", "value-constant",
                       "value-format")

lint_rule_table_build <- function() {
  r <- function(id, spec, tier, scope, what) {
    data.frame(id = id, spec = spec, tier = as.integer(tier), scope = scope, what = what,
               scripts = id %in% LINT_SCRIPT_RULES, stringsAsFactors = FALSE)
  }
  do.call(rbind, list(
    r("numeral", "5.2.1", 1, "file", "A number typed in prose, a caption, front matter, a string or math."),
    r("construct", "5.3.1", 1, "file", "An error the scanner finds in a construct."),
    r("read", "5.1.3", 1, "file", "A file that is not UTF-8."),
    r("block-start", "2.10.5", 1, "file", "A line inside a span that starts a block."),
    r("lone-bar", "5.3.3", 2, "file", "A bracket with one `|` and no governor."),
    r("if-zero", "5.3.3", 2, "file", "An `if` condition that compares with 0."),
    r("name", "5.3.3", 2, "file", "A class or key that is not weft's, or is one edit from it."),
    r("inert-check", "3.1.6", 1, "file", "A check or condition with no variable in it."),
    r("long-guard", "3.1.9", 2, "file", "An `if` arm longer than `guard_words`."),
    r("cite-key", "5.4.1", 1, "file", "A key of a cite span not in the bibliography."),
    r("cite-bare", "5.4.2", 1, "file", "A bare cite key not written as a citation in its block."),
    r("citation-key", "5.4.3", 1, "file", "A citation key not in the bibliography."),
    r("claim-word", "5.5.1", 2, "file", "A claim word in a sentence."),
    r("literal-value", "5.6.1", 1, "file", "A value made only of constants."),
    r("value-constant", "5.6.2", 2, "file", "A numeric constant inside a value."),
    r("value-format", "5.6.4", 2, "file", "A value that rounds or formats in code."),
    r("xref", "5.7.1", 1, "project", "A cross-reference to no anchor."),
    r("anchor-twice", "5.7.1", 1, "project", "An anchor defined more than once."),
    r("ref-label", "5.7.1", 1, "file", "A span whose text is a reference-definition label."),
    r("anchor-unused", "5.7.2", 2, "project", "A figure, table or equation anchor nobody refers to."),
    r("xref-code", "5.7.2", 2, "file", "A cross-reference written inside a code span."),
    r("section-anchor", "5.8.1", 1, "file", "A heading with no `{#id}`."),
    r("chunk-label", "5.8.1", 1, "file", "An executed chunk with no label."),
    r("tar-name", "5.8.2", 1, "file", "A target read that the store does not hold."),
    r("dict-assign", "5.8.3", 1, "file", "An assignment to `dict`."),
    r("file-link", "5.8.4", 1, "file", "A link or image to a file that is not there."),
    r("above-setup", "5.8.5", 1, "file", "A construct above the chunk that calls weft_setup()."),
    r("dict-key", "5.8.6", 1, "file", "A `dict$key` read of a key that is not there."),
    r("tar-cache", "5.8.7", 1, "file", "A chunk that reads a target and caches."),
    r("config-place", "5.8.8", 1, "project", "A project setting in a place that is not the project's."),
    r("engine", "5.8.9", 1, "project", "A document with constructs that is not knitr's."),
    r("front-matter-quarto", "5.8.10", 1, "file", "A `---` block Quarto reads as front matter and Pandoc does not."),
    r("figure", "5.9.1", 1, "file", "A figure with no label, caption or alt text."),
    r("table-caption", "5.9.1", 1, "file", "A table with no caption."),
    r("guest-inline", "5.11.1", 1, "file", "Inline code in another language, which knitr does not run."),
    r("guest-call", "5.11.2", 1, "file", "A weft function called from Python through `r.`."),
    r("guest-read", "5.11.3", 2, "file", "A value read from Python or Julia that weft does not check."),
    r("ojs-value", "5.11.4", 2, "file", "An Observable value computed in the reader's browser."),
    r("named-unpublished", "5.12.1", 2, "file", "A name used by a named value or filter span that nothing publishes."),
    r("publish-hidden", "5.12.2", 1, "file", "A chunk that publishes values where its output is dropped."),
    r("string-markup", "5.12.3", 2, "file", "Weft markup in an R string that does not go through weft().")))
}

#' The static lints
#'
#' `lint_rules()` lists every rule `lints()` knows, in order: its `id`, the
#' `spec` rule number, its `tier` (1 blocks, 2 is listed over added material),
#' its `scope` (`"file"` or `"project"`) and what it finds.
#'
#' @return A data frame with `id`, `spec`, `tier`, `scope` and `what`.
#' @export
lint_rules <- function() {
  r <- lint_rule_table()
  rownames(r) <- NULL
  r
}

# The function of each rule, in one explicit table: nothing is found by name. File-scope rules take
# (src, ctx), project-scope rules (ctx). `read` has none: the reader reports a file that is not UTF-8.
lint_rule_funs <- function() {
  list(
    `numeral` = lint_numeral,
    `construct` = lint_construct,
    read = NULL,
    `block-start` = lint_block_start,
    `lone-bar` = lint_lone_bar,
    `if-zero` = lint_if_zero,
    `name` = lint_name,
    `inert-check` = lint_inert_check,
    `long-guard` = lint_long_guard,
    `cite-key` = lint_cite_key,
    `cite-bare` = lint_cite_bare,
    `citation-key` = lint_citation_key,
    `claim-word` = lint_claim_word,
    `literal-value` = lint_literal_value,
    `value-constant` = lint_value_constant,
    `value-format` = lint_value_format,
    `xref` = lint_xref,
    `anchor-twice` = lint_anchor_twice,
    `ref-label` = lint_ref_label,
    `anchor-unused` = lint_anchor_unused,
    `xref-code` = lint_xref_code,
    `section-anchor` = lint_section_anchor,
    `chunk-label` = lint_chunk_label,
    `tar-name` = lint_tar_name,
    `dict-assign` = lint_dict_assign,
    `file-link` = lint_file_link,
    `above-setup` = lint_above_setup,
    `dict-key` = lint_dict_key,
    `tar-cache` = lint_tar_cache,
    `config-place` = lint_config_place,
    `engine` = lint_engine,
    `front-matter-quarto` = lint_front_matter_quarto,
    `figure` = lint_figure,
    `table-caption` = lint_table_caption,
    `guest-inline` = lint_guest_inline,
    `guest-call` = lint_guest_call,
    `guest-read` = lint_guest_read,
    `ojs-value` = lint_ojs_value,
    `named-unpublished` = lint_named_unpublished,
    `publish-hidden` = lint_publish_hidden,
    `string-markup` = lint_string_markup
  )
}

lint_rule_fun <- function(id) lint_rule_funs()[[id]]

# ---- findings --------------------------------------------------------------------------

# The columns of a weft_findings, in order (L5).
FINDING_COLS <- c("file", "line", "col", "end_line", "rule", "tier", "spec", "context", "text",
                  "message", "hint", "sentence")

# Build a weft_findings. `tier` and `spec` default to the rule table's. Every
# argument is recycled to the longest.
new_findings <- function(file = character(), line = integer(), col = 1L, end_line = line,
                         rule = character(), tier = NULL, spec = NULL, context = "prose",
                         text = "", message = "", hint = NA_character_,
                         sentence = NA_character_, notes = character()) {
  n <- max(length(file), length(line), length(rule), length(text), length(message))
  if (!length(file) || n == 0L) {
    n <- 0L
  }
  rec <- function(x, f) if (n == 0L) f(NULL) else rep_len(x, n)
  tab <- lint_rule_table()
  rl <- rec(rule, as.character)
  m <- match(rl, tab$id)
  out <- data.frame(
    file = rec(file, as.character), line = rec(as.integer(line), as.integer),
    col = rec(as.integer(col), as.integer), end_line = rec(as.integer(end_line), as.integer),
    rule = rl,
    tier = if (is.null(tier)) as.integer(tab$tier[m]) else rec(as.integer(tier), as.integer),
    spec = if (is.null(spec)) tab$spec[m] else rec(as.character(spec), as.character),
    context = rec(context, as.character), text = rec(text, as.character),
    message = rec(message, as.character), hint = rec(hint, as.character),
    sentence = rec(sentence, as.character), stringsAsFactors = FALSE)
  structure(out, class = c("weft_findings", "data.frame"), notes = as.character(notes))
}

# Findings for the offsets [start, end] of a source (the helper a rule uses).
finding_at <- function(src, start, end = start, rule, text, message, hint = NA_character_,
                       context = "prose", spec = NULL, tier = NULL, sentence = NA_character_) {
  new_findings(file = src$file, line = src_line_of(src, start), col = src_col_of(src, start),
               end_line = src_line_of(src, end), rule = rule, tier = tier, spec = spec,
               context = context, text = text, message = message, hint = hint,
               sentence = sentence)
}

bind_findings <- function(parts, notes = character()) {
  parts <- Filter(function(p) !is.null(p) && nrow(p) > 0L, parts)
  if (!length(parts)) return(new_findings(notes = notes))
  # column by column: `rbind` of thousands of small frames is the slow part
  cols <- lapply(FINDING_COLS, function(cn) unlist(lapply(parts, function(p) unclass(p)[[cn]]), use.names = FALSE))
  names(cols) <- FINDING_COLS
  out <- as.data.frame(cols, stringsAsFactors = FALSE, optional = TRUE)
  structure(out, class = c("weft_findings", "data.frame"), notes = as.character(notes))
}

# Findings (or the plain frame of them) by file, line, column and rule, with the row names reset.
sort_findings <- function(x) {
  x <- x[order(enc2utf8(x$file), x$line, x$col, x$rule, method = "radix"), , drop = FALSE]
  rownames(x) <- NULL
  x
}

finish_findings <- function(x, notes, n_files) {
  if (nrow(x)) {
    x <- as.data.frame(unclass(x), stringsAsFactors = FALSE)
    x <- x[!duplicated(x[, c("file", "line", "col", "rule", "text", "message")]), , drop = FALSE]
    x <- sort_findings(x)
    x <- structure(x, class = c("weft_findings", "data.frame"))
  }
  attr(x, "notes") <- unique(as.character(notes))
  attr(x, "n_files") <- as.integer(n_files)
  x
}

ascii_escape <- function(x) {
  vapply(x, function(s) {
    if (is.na(s) || !grepl("[^\\x01-\\x7F]", s, perl = TRUE)) return(s)
    ch <- strsplit(s, "")[[1L]]
    cp <- utf8ToInt(s)
    bad <- cp > 127L
    ch[bad] <- ifelse(cp[bad] > 65535L, sprintf("\\U%08x", cp[bad]), sprintf("\\u%04x", cp[bad]))
    paste(ch, collapse = "")
  }, "", USE.NAMES = FALSE)
}

#' @param x A `weft_findings`.
#' @param max The most findings printed.
#' @param ... Not used.
#' @rdname lints
#' @export
print.weft_findings <- function(x, max = 200, ...) {
  n <- nrow(x)
  nf <- attr(x, "n_files")
  plural <- function(k, w) paste0(k, " ", w, if (k == 1L) "" else "s")
  if (n == 0L) {
    if (is.null(nf)) nf <- 0L
    cat(sprintf("weft lints: no findings in %s.\n", plural(nf, "file")))
  } else {
    files <- unique(x$file)
    cat(sprintf("weft lints: %s in %s (%d tier 1, %d tier 2)\n", plural(n, "finding"),
                plural(length(files), "file"), sum(x$tier == 1L), sum(x$tier == 2L)))
    shown <- utils::head(seq_len(n), max)
    f <- as.data.frame(unclass(x), stringsAsFactors = FALSE)[shown, , drop = FALSE]
    for (file in unique(f$file)) {
      d <- f[f$file == file, , drop = FALSE]
      pos <- paste0(d$line, ":", d$col)
      wp <- max(nchar(pos))
      wr <- max(nchar(d$rule))
      cat("\n", ascii_escape(file), "\n", sep = "")
      pad <- strrep(" ", 2L + wp + 2L + wr + 2L)
      for (i in seq_len(nrow(d))) {
        msg <- d$message[i]
        more <- NULL
        mm <- regmatches(msg, regexec("^(.*\\(rule [0-9.]+\\))[;.,][ ]+(.+)$", msg))[[1L]]
        if (length(mm)) {
          msg <- paste0(mm[2L], ".")
          more <- mm[3L]
        }
        cat(ascii_escape(sprintf("  %-*s  %-*s  %s", wp, pos[i], wr, d$rule[i], msg)), "\n", sep = "")
        if (!is.null(more)) cat(pad, ascii_escape(more), "\n", sep = "")
        if (!is.null(d$hint) && !is.na(d$hint[i])) cat(pad, ascii_escape(d$hint[i]), "\n", sep = "")
        if (!is.null(d$sentence) && !is.na(d$sentence[i])) cat(pad, ascii_escape(paste0("\"", d$sentence[i], "\"")), "\n", sep = "")
      }
    }
    if (n > length(shown)) {
      cat(sprintf("... and %d more finding%s.\n", n - length(shown), if (n - length(shown) == 1L) "" else "s"))
    }
  }
  notes <- attr(x, "notes")
  if (length(notes)) {
    cat("\nNotes:\n")
    for (m in notes) cat("  ", ascii_escape(m), "\n", sep = "")
  }
  invisible(x)
}

# ---- configuration (L4, L8a) ---------------------------------------------------------------

# The settings of one document: `_weft.yml` under the front matter's `weft:`,
# read as YAML only (no units are installed). In a walk the file is read once per
# settings root (walk_memo()); it is checked, and merged with `front`, every time.
lint_config <- function(root, front = list()) {
  file <- file.path(root, "_weft.yml")
  proj <- list()
  raw <- NULL
  if (file.exists(file)) {
    ws <- walk_memo("weft_yml", file, function() read_weft_yml(file))
    proj <- ws$proj
    raw <- ws$raw
    check_raw_scalars(raw)
  }
  w <- if (is.list(front)) front$weft else NULL
  if (!is.list(w)) w <- list()
  for (nm in c("units", "dict_local")) {
    proj[[nm]] <- NULL
    w[[nm]] <- NULL
  }
  check_front_mapping(w)
  cfg <- merged_settings(proj, w)
  validate_lint_config(cfg, raw)
  cfg
}

lexicon_cache <- new.env(parent = emptyenv())

# The shipped lexicon file, read once: the words by class, and the idioms (rule 5.5.1).
claim_lexicon_file <- function() {
  if (is.null(lexicon_cache$file)) {
    y <- yaml_read_file(system.file("weft-claim-words.yml", package = "weft"))
    low <- function(v) tolower(as.character(unlist(v, use.names = FALSE)))
    lexicon_cache$file <- list(quantifier = low(y$quantifier),
                               other = low(c(y$extremum, y$direction)),
                               idioms = low(y$idioms))
  }
  lexicon_cache$file
}

is_english_lang <- function(lang) {
  is.null(lang) || length(lang) != 1L || is.na(lang) || !nzchar(lang) ||
    grepl("^(en|eng)([-_]|$)", lang, ignore.case = TRUE)
}

# The claim words for a document language (L8a): the shipped words, plus the project's `add`,
# minus its `drop`.
claim_lexicon <- function(cfg = default_config(), lang = NA_character_) {
  shipped <- character()
  if (is_english_lang(lang)) {
    f <- claim_lexicon_file()
    shipped <- c(f$quantifier, f$other)
  }
  cw <- cfg$claim_words
  add <- tolower(as.character(unlist(cw$add)))
  drop <- tolower(as.character(unlist(cw$drop)))
  setdiff(unique(c(shipped, add)), drop)
}

# The words of the lexicon that are quantifiers (rule 5.5.5): a shipped quantifier that the project
# has not also put in `add`; a word from `add` counts as not a quantifier.
claim_quantifier_words <- function(cfg = default_config(), lang = NA_character_) {
  if (!is_english_lang(lang)) return(character())
  setdiff(claim_lexicon_file()$quantifier, tolower(as.character(unlist(cfg$claim_words$add))))
}

# The idioms of a document: the shipped phrases (English only) and the project's own, lower case.
claim_idioms <- function(cfg = default_config(), lang = NA_character_) {
  shipped <- if (is_english_lang(lang)) claim_lexicon_file()$idioms else character()
  own <- tolower(trimws(as.character(unlist(cfg$claim_words$idioms))))
  unique(c(shipped, own[nzchar(own)]))
}

# ---- the project's documents --------------------------------------------------------------------

# The documents the lints read: `underscore = TRUE` gives only the documents in
# `_` folders (includes, partials), which are read for anchors but not linted.
lint_files_under <- function(root, ext = DOC_EXT_RE, underscore = FALSE) {
  project_doc_paths(root, if (underscore) "anchors" else "lint", ext)
}

# The folder whose `_weft.yml` governs a document: the innermost one from the
# document's folder up to `root`, as in the gate (review 4, #7); `root` when
# none lies below it.
settings_root <- function(root, rel) {
  s <- script_settings_root(root, rel)
  if (nzchar(s)) file.path(root, s) else root
}

# The front matter of a document file (rule 2.1.6), for every reader of its own fields: the knit (its
# `weft:` settings, `lang` and `dict_local`), the lints, verify(), checks() and arms(). The file is read as
# source text, not through `rmarkdown::metadata`, which holds the first block only; its fields are those of
# doc_front_lines(). `text` is the file's text when the caller has read it already (NULL: read it here).
# A script, no path, and a file that is not text have none.
read_front_matter <- function(path, text = NULL) {
  if (is.null(path) || is_script_path(path)) return(list())
  if (is.null(text)) text <- read_source_text_or_null(path)
  if (is.null(text)) return(list())
  doc_front_lines(split_source_lines(text))
}

# The metadata blocks `mb` of `lines`, each with its `open` and `close` lines and its `yaml` (list() when it
# is empty or not YAML).
meta_blocks_yaml <- function(lines, mb) {
  lapply(seq_len(nrow(mb)), function(b) {
    y <- if (mb$close[b] - mb$open[b] >= 2L) yaml_text(paste(lines[(mb$open[b] + 1L):(mb$close[b] - 1L)], collapse = "\n")) else list()
    list(open = mb$open[b], close = mb$close[b], yaml = if (is.list(y)) y else list())
  })
}

# The front matter of a document from its metadata blocks (meta_blocks_yaml()): the fields of each mapping, a
# later block's over an earlier one's.
merge_front <- function(meta) {
  front <- list()
  for (m in meta) if (length(m$yaml) && !is.null(names(m$yaml))) front[names(m$yaml)] <- m$yaml
  front
}

# Each file's source comes through here, so a cache can stand in (stage 4's
# `weft_env$lint_reader`). `bytes` are a script's bytes, and `text` a document's
# text, when the caller has read them already.
lint_read <- function(path, root, cfg, bytes = NULL, text = NULL) {
  (weft_env$lint_reader %||% read_source)(path, root, cfg, bytes, text)
}

# One document, read with its own settings.
lint_open <- function(root, rel) {
  path <- file.path(root, rel)
  bytes <- NULL
  text <- NULL
  if (is_script_path(rel)) {
    # a script whose bytes do not hold `weft` is judged before any settings are read (K14), and is read once
    bytes <- read_source_bytes(path)
    if (!bytes_mention_weft(bytes)) return(script_stub(rel, path, NULL, "skip"))
  } else {
    # the text the settings are read from is the text the document is read from (E6); it is read when the
    # settings first need it, after `_weft.yml`, as before
    delayedAssign("text", read_source_text_or_null(path))
  }
  cfg <- lint_config(settings_root(root, rel), read_front_matter(path, text))
  lint_read(path, root, cfg, bytes, text)
}

# A reader (for `weft_env$lint_reader`) that reads each file once for as long as it is in place, through
# `inner` (the reader in place before it; read_source() when none): verify() reads a document for its lints,
# its removed constructs, its decision pointers and its constructs (E5). A file read again with other
# settings is read again.
memo_reader <- function(inner = NULL) {
  seen <- new.env(parent = emptyenv())
  function(path, root, cfg, bytes = NULL, text = NULL) {
    key <- paste(root, path, sep = "\n")
    hit <- seen[[key]]
    if (!is.null(hit) && identical(hit$cfg, cfg)) return(hit$src)
    src <- (inner %||% read_source)(path, root, cfg, bytes, text)
    seen[[key]] <- list(cfg = cfg, src = src)
    src
  }
}

new_lint_ctx <- function(root, files, md_files, report, tier, rules, reader) {
  ctx <- new.env(parent = emptyenv())
  ctx$root <- root
  ctx$files <- files
  ctx$md_files <- md_files
  ctx$report <- report
  ctx$tier <- tier
  ctx$rules <- rules
  ctx$reader <- reader
  ctx$notes <- character()
  ctx$include_files <- lint_files_under(root, underscore = TRUE)
  cache <- new.env(parent = emptyenv())
  ctx$source <- function(rel) {
    if (is.null(cache[[rel]])) cache[[rel]] <- lint_open(root, rel)
    cache[[rel]]
  }
  ctx$note <- function(msg) ctx$notes <- c(ctx$notes, msg)
  ctx$path <- function(rel) file.path(root, rel)
  class(ctx) <- "weft_lint_ctx"
  ctx
}

#' Lint a project's documents and scripts without running them
#'
#' Reads `.qmd` and `.Rmd` documents as text and returns the typed numbers,
#' construct errors and other problems the rules of [lint_rules()] find.
#' Nothing in a document is run.
#'
#' The `.R` and `.r` files of the project (its scripts) are read too, but only
#' for the literal strings they pass to `weft()`: in a script, `weft("We found
#' 12 sites")` is prose like any other and its `12` is a finding, placed at its
#' line and column in the script. A call is `weft(...)`, `weft::weft(...)` or
#' `weft:::weft(...)`, or the right-hand side of a pipe; the argument read is the
#' one R matches to `x`, a string literal (a raw string too) or the literal
#' elements of a `c()`. The code around the call is not read, and neither are
#' `claim()` calls, phrases or strings given to other functions. The rules that
#' read scripts are those with `scripts` `TRUE` in [lint_rules()]; the project
#' rules read documents only. A script is left out when it is in a folder
#' whose name starts with `.` or `_`, or in `renv`, `packrat`, `node_modules`,
#' `_site`, `_book`, `_freeze` or `_extensions`, when its file name starts with
#' `.`, or when it matches the setting `scripts_skip` of the `_weft.yml` nearest
#' to it: a list of folder or file names, or paths from that folder, with no
#' wildcards. Its default is `[tests]`, `[]` reads every script, and a list that
#' is given replaces the default, so keep `tests` in it. A skipped or excluded
#' script named in `files` or as `path` gives a note. A script whose bytes do not hold `weft`
#' is not read, one that is not valid UTF-8 gives the `read` finding, and one
#' that does not parse as R gives a note and no findings.
#'
#' @param path One existing file or folder. The project root is found from it.
#' @param files `NULL`, or documents and scripts (relative to the root or
#'   absolute under it) to report on. File-scope rules run on these only;
#'   project-scope rules still read every document.
#' @param rules `NULL` (every rule of the tiers asked for), or ids from
#'   [lint_rules()].
#' @param tier A subset of `1:2`. The default is tier 1.
#' @param reader `"weft"` (the default) or `"pandoc"`.
#' @return A `weft_findings` data frame sorted by file, line, column and rule,
#'   with columns `file`, `line`, `col`, `end_line`, `rule`, `tier`, `spec`,
#'   `context`, `text`, `message`, `hint` and `sentence`, and the attribute
#'   `notes`.
#' @export
lints <- function(path = ".", files = NULL, rules = NULL, tier = 1, reader = c("weft", "pandoc")) {
  tier_given <- !missing(tier)
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path) || !file.exists(path)) {
    lint_abort("`path` must be one existing file or folder (rule 5.1.1).")
  }
  if (identical(reader, c("weft", "pandoc"))) reader <- "weft"
  if (!is.character(reader) || length(reader) != 1L || !reader %in% c("weft", "pandoc")) {
    lint_abort("`reader` must be \"weft\" or \"pandoc\" (rule 2.10.3).")
  }
  if (!is.numeric(tier) || !length(tier) || anyNA(tier) || !all(tier %in% 1:2)) {
    lint_abort("`tier` must be 1, 2 or both (rule 5.1.2).")
  }
  tab <- lint_rule_table()
  if (!is.null(rules)) {
    if (!is.character(rules) || anyNA(rules)) lint_abort("`rules` must be rule ids from `lint_rules()$id`.")
    bad <- setdiff(rules, tab$id)
    if (length(bad)) {
      lint_abort(paste0("Unknown rule", if (length(bad) > 1L) "s" else "", ": ",
                        paste0("`", bad, "`", vapply(bad, function(b) {
                          d <- did_you_mean(b, tab$id)
                          if (nzchar(d)) paste0(";", d) else ""
                        }, ""), collapse = "; "),
                        " (rule 5.1.1)."))
    }
  }
  # a rule named in `rules` runs whatever its tier when `tier` is not given (review 3, finding 9)
  skipped <- character()
  if (!is.null(rules)) {
    if (!tier_given) {
      tier <- sort(unique(tab$tier[tab$id %in% rules]))
    } else {
      skipped <- rules[!rules %in% tab$id[tab$tier %in% tier]]
    }
  }
  if (reader == "pandoc") {
    pp <- pandoc_path()
    if (!nzchar(pp)) {
      lint_abort(paste0("lints(reader = \"pandoc\") needs Pandoc; none was found. ",
                        "Set the option `weft.pandoc` to its path (rule 2.10.3)."))
    }
  }
  full <- normalizePath(path, winslash = "/", mustWork = TRUE)
  root <- normalizePath(find_project_root(full), winslash = "/", mustWork = FALSE)
  local_walk_memo()
  all_files <- lint_files_under(root)
  # the scripts, less those `scripts_skip` leaves out (C1, C2, K4), whatever the reader (K7); the settings are
  # read here, so a bad one stops the run whatever the project holds
  all_scripts <- project_script_paths(root)
  # files to report on
  files_rel <- if (!is.null(files)) resolve_files(files, root, lint_abort)
  report <- lint_report_under(all_files, full, root)
  scripts <- lint_report_under(all_scripts, full, root)
  if (!is.null(files_rel)) {
    report <- intersect(report, files_rel)
    scripts <- intersect(scripts, files_rel)
  }
  sel <- tab[tab$tier %in% tier & (is.null(rules) | tab$id %in% rules), , drop = FALSE]
  notes <- if (length(skipped)) {
    sprintf("Not run, because its tier is not in `tier`: %s (rule 5.1.2).",
            paste0("`", skipped, "`", collapse = ", "))
  } else {
    character()
  }
  # a file named in `files`, or as `path`, that is not read gets a note saying why (K6)
  notes <- c(notes, named_notes(root, full, files_rel, c(all_files, all_scripts)))
  pre <- paste0(rel_to(full, root), "/")
  keep_project <- function(f) {
    f %in% report | (is.null(files_rel) & dir.exists(full) & (identical(full, root) | startsWith(f, pre)))
  }
  lint_run(root, all_files, report, sel, tier, rules, reader, notes = notes, keep_project = keep_project,
           scripts = scripts)
}

# The notes for the files named by the caller (`files`, or a file given as `path`) that are not read: a script
# `scripts_skip` leaves out, or a file the document rules leave out (K6).
left_out_notes <- function(root, named, read) {
  named <- setdiff(unique(named), read)
  skip_of <- scripts_skip_getter(root)
  vapply(named, function(rel) {
    skip <- if (is_script_path(rel)) {
      tryCatch(script_skipped_in(root, rel, skip_of), error = function(e) FALSE)
    } else FALSE
    if (skip) sprintf("`%s` is left out by `scripts_skip` (rule 5.1.9).", rel)
    else sprintf("`%s` is left out by the document rules (rule 5.1.8).", rel)
  }, "", USE.NAMES = FALSE)
}

# The notes for what the caller named (`files`, else a file given as `path`) that is not among `read`.
named_notes <- function(root, full, files_rel, read) {
  named <- if (!is.null(files_rel)) files_rel else if (!dir.exists(full)) rel_to(full, root) else character()
  left_out_notes(root, named, read)
}

# The documents of `all_files` that `path` (a folder or a file, normalised, inside `root`) covers.
lint_report_under <- function(all_files, full, root) {
  if (!length(all_files)) return(all_files)
  if (!dir.exists(full)) return(intersect(all_files, rel_to(full, root)))
  if (identical(full, root)) return(all_files)
  pre <- paste0(rel_to(full, root), "/")
  all_files[startsWith(all_files, pre)]
}

# Run the rules of `sel` (rows of the rule table) over a project: each file-scope rule on the documents of
# `file_report`, each project-scope rule once, keeping the findings whose file `keep_project` accepts (all of
# them when it is NULL). Every document of `report` is opened. The `scripts` (relative paths) are read too,
# and the rules that read scripts run on them (C12, C13). Returns the findings, with the notes.
lint_run <- function(root, all_files, report, sel, tier, rules, reader, notes = character(),
                     file_report = report, keep_project = NULL, scripts = character()) {
  local_walk_memo()
  md_files <- lint_files_under(root, "\\.md$")
  ctx <- new_lint_ctx(root, all_files, md_files, report, tier, rules, reader)
  for (m in notes) ctx$note(m)
  parts <- list()
  for (rel in report) {
    src <- ctx$source(rel)
    if (!rel %in% file_report) next
    if (isTRUE(src$invalid)) {
      if ("read" %in% sel$id) {
        parts[[length(parts) + 1L]] <- new_findings(
          file = rel, line = 1L, col = 1L, rule = "read", context = "project", text = rel,
          message = sprintf("`%s` is not valid UTF-8; save the file as UTF-8 (rule 5.1.3).", rel),
          hint = "Save the file as UTF-8.")
      }
      next
    }
    for (i in which(sel$scope == "file")) {
      fn <- lint_rule_fun(sel$id[i])
      if (is.null(fn)) next
      parts[[length(parts) + 1L]] <- fn(src, ctx)
    }
  }
  ssel <- sel[sel$scope == "file" & sel$scripts, , drop = FALSE]
  n_scripts <- 0L
  for (rel in scripts) {
    src <- ctx$source(rel)
    # a script that holds no weft() literal, or does not parse, is not counted among the files read (K8)
    status <- source_status(src)
    if (!status %in% c("skip", "noparse")) n_scripts <- n_scripts + 1L
    if (status == "invalid") {
      if ("read" %in% sel$id) {
        parts[[length(parts) + 1L]] <- new_findings(
          file = rel, line = 1L, col = 1L, rule = "read", context = "weft", text = rel,
          message = sprintf("`%s` is not valid UTF-8; save the file as UTF-8 (rule 5.1.3).", rel),
          hint = "Save the file as UTF-8.")
      }
      next
    }
    if (status == "noparse") ctx$note(src$note)
    if (status != "ok") next
    for (i in seq_len(nrow(ssel))) {
      fn <- lint_rule_fun(ssel$id[i])
      if (is.null(fn)) next
      parts[[length(parts) + 1L]] <- fn(src, ctx)
    }
  }
  for (i in which(sel$scope == "project")) {
    fn <- lint_rule_fun(sel$id[i])
    if (is.null(fn)) next
    res <- fn(ctx)
    if (!is.null(res) && nrow(res)) {
      if (!is.null(keep_project)) res <- res[keep_project(res$file), , drop = FALSE]
      parts[[length(parts) + 1L]] <- res
    }
  }
  out <- bind_findings(parts)
  if (nrow(out)) out <- out[out$tier %in% tier, , drop = FALSE]
  finish_findings(out, ctx$notes, length(report) + n_scripts)
}

# ---- construct (L17) --------------------------------------------------------------------------------

lint_construct <- function(src, ctx) {
  r <- src$rows
  e <- which(!is.na(r$error))
  if (!length(e)) return(new_findings())
  parts <- lapply(e, function(i) {
    msgs <- strsplit(r$error[i], "\n", fixed = TRUE)[[1L]]
    msgs <- msgs[nzchar(msgs)]
    spec <- vapply(msgs, function(m) {
      mm <- regmatches(m, regexpr("rules? [0-9]+(\\.[0-9]+)+", m))
      if (length(mm)) sub("^rules? ", "", mm) else "5.3.1"
    }, "", USE.NAMES = FALSE)
    s <- r$fstart[i]
    en <- r$fend[i]
    txt <- src_substr(src, s, en)
    if (nchar(txt) > 80L) txt <- substr(txt, 1L, 80L)
    new_findings(file = src$file, line = src_line_of(src, s), col = src_col_of(src, s),
                 end_line = src_line_of(src, en), rule = "construct", spec = spec,
                 context = r$context[i], text = txt, message = msgs)
  })
  bind_findings(parts)
}
