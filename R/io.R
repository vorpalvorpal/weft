# The shared foundations of weft's reading and writing: one reader of source
# text, one reader of YAML, one runner of git, one finder of the project root,
# one lister of a project's documents and one atomic writer. Nothing else in
# `R/` reads a file as text, parses YAML, runs git, walks up to a root, lists a
# project's documents or writes a file into a project or cache by its own
# means (dev/review-code-{a,b,c}.md, the rulings on items a7, b1, b5, b11,
# b12, c3, c7, c9).

# ---- source text ----------------------------------------------------------------------------------

# The bytes of a file, without a leading byte-order mark.
read_source_bytes <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  bytes <- readBin(con, "raw", max(file.size(path), 0, na.rm = TRUE))
  if (length(bytes) >= 3L && identical(bytes[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))) bytes <- bytes[-(1:3)]
  bytes
}

# The text of a file as one string: UTF-8, no byte-order mark, and "\n" for
# every line end (CRLF and a lone CR alike). A NUL byte or text that is not
# UTF-8 is a `weft_encoding_error` naming the file. A missing final newline is
# kept as it is (it is only a missing "\n"). `class` is put before
# `weft_encoding_error` on that error, for a caller whose own condition class
# the reader of that file has always had (`weft_dict_error`, `weft_config_error`).
read_source_text <- function(path, class = NULL, bytes = NULL) {
  if (is.null(bytes)) bytes <- read_source_bytes(path)
  if (any(bytes == as.raw(0L))) {
    weft_abort(sprintf("%s holds a NUL byte, so it is not text; save the file as UTF-8.", path),
               c(class, "weft_encoding_error"))
  }
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  if (!validUTF8(text)) {
    weft_abort(sprintf("%s is not valid UTF-8; save the file as UTF-8.", path),
               c(class, "weft_encoding_error"))
  }
  text <- gsub("\r\n", "\n", text, fixed = TRUE)
  gsub("\r", "\n", text, fixed = TRUE)
}

# The lines of a file, as `read_source_text()` reads it; `character()` for an
# empty file.
read_source_lines <- function(path, class = NULL) split_source_lines(read_source_text(path, class))

# The same text, or NULL for a file that is not text (a NUL byte, or not UTF-8):
# for the lints, which judge such a file invalid and go on.
read_source_text_or_null <- function(path) {
  tryCatch(read_source_text(path), weft_encoding_error = function(e) NULL)
}

split_source_lines <- function(text) {
  if (!nzchar(text)) return(character())
  strsplit(text, "\n", fixed = TRUE)[[1L]]
}

# ---- YAML -----------------------------------------------------------------------------------------

# The one YAML reading of weft. Only `true` and `false` (in any letter case)
# are booleans: `yes`, `no`, `on`, `off`, `y` and `n` stay text, as they are in
# YAML 1.2 and in Quarto; as a mapping key `N` is the text `N`. `!expr` is never
# evaluated, whatever `yaml.eval.expr` says. `handlers` replace the defaults of
# the same name. A parse failure is a `weft_yaml_error` naming `file`.
YAML_HANDLERS <- list(
  "bool#yes" = function(x) if (tolower(x) == "true") TRUE else x,
  "bool#no" = function(x) if (tolower(x) == "false") FALSE else x)

yaml_read_text <- function(text, file = NULL, handlers = NULL) {
  text <- paste(text, collapse = "\n")
  h <- YAML_HANDLERS
  h[names(handlers)] <- handlers
  tryCatch(yaml::yaml.load(text, handlers = h, eval.expr = FALSE),
           error = function(e) {
             msg <- conditionMessage(e)
             weft_abort(if (is.null(file)) msg else sprintf("%s: %s", file, msg), "weft_yaml_error")
           })
}

# The YAML of a file; the file is read as source text (`read_source_text()`).
yaml_read_file <- function(path, handlers = NULL) {
  yaml_read_text(read_source_text(path), file = path, handlers = handlers)
}

# JSON, as plain lists (objects named, arrays unnamed). Not yaml: libyaml refuses the surrogate pair
# json_string() writes for a character outside the BMP.
json_read_text <- function(text, file = NULL) {
  text <- paste(text, collapse = "\n")
  tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE),
           error = function(e) {
             msg <- conditionMessage(e)
             weft_abort(if (is.null(file)) msg else sprintf("%s: %s", file, msg), "weft_json_error")
           })
}

# The JSON of a file; the file is read as source text (`read_source_text()`).
json_read_file <- function(path) json_read_text(read_source_text(path), file = path)

# A literal string as a regular expression (the metacharacters backslash-escaped).
regex_escape <- function(x) gsub("([\\\\.+*?()|\\[\\]{}^$])", "\\\\\\1", x, perl = TRUE)

# ---- git ------------------------------------------------------------------------------------------

# where git is: "" when it is not on the PATH
git_path <- function() unname(Sys.which("git"))

# Run git in `dir`; every argument is quoted, so no shell reads any of them.
# Always `--no-optional-locks` (git's own option, for it works where system2()'s `env =` does not, on
# Windows) and `-c core.quotepath=false`. Returns
# `list(status, out (raw), err (character))`. When git is not on the PATH it is a
# `weft_git_error` (also a `weft_gate_error`).
git_raw <- function(dir, args, input = NULL) {
  git <- git_path()
  if (!nzchar(git)) {
    weft_abort("git was not found on the PATH, so weft cannot read the repository (rule 6.1.1).",
               c("weft_git_error", "weft_gate_error"))
  }
  out <- tempfile("weft-git-out-")
  err <- tempfile("weft-git-err-")
  on.exit(unlink(c(out, err)), add = TRUE)
  full <- c("--no-optional-locks", "-C", dir, "-c", "core.quotepath=false", args)
  st <- suppressWarnings(system2(git, shQuote(full), stdout = out, stderr = err, input = input))
  st <- if (is.null(st)) 0L else as.integer(st)
  list(status = st,
       out = readBin(out, "raw", max(file.size(out), 0, na.rm = TRUE)),
       err = suppressWarnings(readLines(err, warn = FALSE)))
}

# git must succeed, else a `weft_git_error` (also a `weft_gate_error`) naming the command
git_ok <- function(dir, args, input = NULL) {
  r <- git_raw(dir, args, input)
  if (!identical(r$status, 0L)) {
    weft_abort(paste0("git ", paste(args[seq_len(min(2L, length(args)))], collapse = " "), " failed",
                      if (length(r$err)) paste0(": ", paste(r$err, collapse = " ")) else "", "."),
               c("weft_git_error", "weft_gate_error"))
  }
  r
}

# The lines git printed, or NULL: no git, or git failed.
git_lines <- function(dir, args) {
  r <- tryCatch(git_raw(dir, args), weft_git_error = function(e) NULL)
  if (is.null(r) || !identical(r$status, 0L)) return(NULL)
  raw_lines(r$out)
}

# The NUL-terminated records of a command that lists paths (give it `-z`), or
# NULL: no git, or git failed.
git_records <- function(dir, args) {
  r <- tryCatch(git_raw(dir, args), weft_git_error = function(e) NULL)
  if (is.null(r) || !identical(r$status, 0L)) return(NULL)
  raw_records(r$out)
}

# the lines of git's raw output as UTF-8 text (a CRLF counts as a line end)
raw_lines <- function(x) {
  s <- rawToChar(x)
  Encoding(s) <- "UTF-8"
  if (!nzchar(s)) return(character())
  s <- gsub("\r\n", "\n", s, fixed = TRUE)
  strsplit(sub("\n$", "", s), "\n", fixed = TRUE)[[1L]]
}

# NUL-terminated records of a raw vector, as UTF-8 strings
raw_records <- function(x) {
  if (!length(x)) return(character())
  z <- which(x == as.raw(0L))
  st <- c(1L, z + 1L)
  en <- c(z - 1L, length(x))
  keep <- st <= length(x) & en >= st
  vapply(which(keep), function(i) {
    s <- rawToChar(x[st[i]:en[i]])
    Encoding(s) <- "UTF-8"
    s
  }, "")
}

# ---- the project root -----------------------------------------------------------------------------

# The nearest folder, from `start` upward, that holds any of `markers`, or NA.
find_up <- function(start, markers) {
  d <- start
  repeat {
    if (any(file.exists(file.path(d, markers)))) return(d)
    up <- dirname(d)
    if (identical(up, d)) return(NA_character_)
    d <- up
  }
}

QUARTO_MARKERS <- c("_quarto.yml", "_quarto.yaml")
METADATA_MARKERS <- c("_metadata.yml", "_metadata.yaml")

# `path` relative to `root`: the text after `root/`, or `path` unchanged when it
# is not inside `root`. Both are read as they are written (normalise them first
# if they may differ in spelling); the separator is `/`. A root that already
# ends in a separator (`/`, `C:/`) is not given a second one.
rel_to <- function(path, root) {
  prefix <- if (endsWith(root, "/")) root else paste0(root, "/")
  inside <- startsWith(path, prefix) %in% TRUE
  path[inside] <- substring(path[inside], nchar(prefix) + 1L)
  path
}

# The nearest folder, from the file (or folder) upward, that holds `_weft.yml`;
# failing that one that holds `_quarto.yml` or `_quarto.yaml`; failing that the
# folder itself.
find_project_root <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  start <- if (dir.exists(path)) path else dirname(path)
  for (markers in list("_weft.yml", QUARTO_MARKERS)) {
    r <- find_up(start, markers)
    if (!is.na(r)) return(r)
  }
  start
}

# The Quarto project root at or above `start` (a folder), or NULL.
find_quarto_root <- function(start) {
  r <- find_up(start, QUARTO_MARKERS)
  if (is.na(r)) NULL else r
}

# ---- a memo for one walk over a project ----------------------------------------------------------

# A walk over a project (lints(), checks(), verify(), a gate side) reads the same project files for every
# document: the `_weft.yml` of a settings root, the `_quarto.yml` above a folder. `local_walk_memo()` opens a
# memo for the length of the calling function, in which each is read once (E6). It ends with that call, so the
# next call reads a changed file fresh. A memo already open is used (a walk inside a walk), unless `fresh` (a
# gate side, whose project is a temporary copy).
local_walk_memo <- function(fresh = FALSE, envir = parent.frame()) {
  old <- weft_env$walk_memo
  if (!is.null(old) && !fresh) return(invisible())
  weft_env$walk_memo <- new.env(parent = emptyenv())
  withr::defer(weft_env$walk_memo <- old, envir = envir)
  invisible()
}

# `compute()`, kept under `key` of `kind` while a walk memo is open, and called every time when none is. Only
# a value is kept: a call that fails is made again.
walk_memo <- function(kind, key, compute) {
  m <- weft_env$walk_memo
  if (is.null(m) || length(key) != 1L || is.na(key) || !nzchar(key)) return(compute())
  tab <- m[[kind]]
  if (is.null(tab)) {
    tab <- new.env(parent = emptyenv())
    m[[kind]] <- tab
  }
  hit <- tab[[key]]
  if (!is.null(hit)) return(hit[[1L]])
  v <- compute()
  tab[[key]] <- list(v)
  v
}

# ---- a project's documents ------------------------------------------------------------------------

DOC_EXT_RE <- "\\.(qmd|Rmd|rmd)$"

# Folders that are never a project's own documents, by name: the libraries
# a project vendors, and the folders Quarto writes to or reads from.
DOC_VENDORED_DIRS <- c("renv", "packrat", "node_modules")
DOC_QUARTO_DIRS <- c("_site", "_book", "_freeze", "_extensions")

# Which relative paths (under the project root, with "/") are documents of a
# project for `use`:
#   "lint"    the documents that are read and judged: not in a dot-folder, a
#             vendored folder, a folder Quarto writes to, or a `_` folder
#             (includes, partials); a `_x.qmd` file is one (it is an include,
#             and a rule that cares skips it itself)
#   "anchors" the documents in `_` folders only, which are read for anchors
#   "setup"   the documents that set-up and status act on: as "lint", but no
#             `_` file either
# A file whose name starts with "." is never one.
doc_path_ok <- function(rel, use = c("lint", "anchors", "setup")) {
  use <- match.arg(use)
  parts <- strsplit(rel, "/", fixed = TRUE)
  vapply(parts, function(p) {
    f <- p[length(p)]
    d <- p[-length(p)]
    if (startsWith(f, ".")) return(FALSE)
    hid <- any(startsWith(d, ".") | d %in% DOC_VENDORED_DIRS | d %in% DOC_QUARTO_DIRS)
    us <- any(startsWith(d, "_"))
    switch(use,
           lint = !hid && !us,
           anchors = !hid && us,
           setup = !hid && !us && !startsWith(f, "_"))
  }, NA)
}

# The documents of the project at `root`, as sorted relative paths with "/"
# (`pattern` picks the extension; `.qmd`, `.Rmd` and `.rmd` by default).
project_doc_paths <- function(root, use = c("lint", "anchors", "setup"), pattern = DOC_EXT_RE) {
  use <- match.arg(use)
  sort(enc2utf8(project_files_under(root, pattern, use)), method = "radix")
}

# The files under `root` whose names match `pattern` and that `use` reads (doc_path_ok()), as relative paths
# with "/", in the order of the walk. The folders that hold none (a dot-folder, a vendored folder, a folder
# Quarto writes to, and but for "anchors" a `_` folder) are pruned as the walk goes, so renv's library is not
# walked and a symbolic link by one of those names is not followed (K15). Dot-files are never listed.
project_files_under <- function(root, pattern, use = c("lint", "anchors", "setup")) {
  use <- match.arg(use)
  out <- character()
  walk <- function(rel) {
    dir <- if (nzchar(rel)) file.path(root, rel) else root
    ents <- list.files(dir, all.files = FALSE, no.. = TRUE)
    if (!length(ents)) return(invisible())
    isd <- dir.exists(file.path(dir, ents))
    for (e in ents[isd]) {
      if (e %in% DOC_VENDORED_DIRS || e %in% DOC_QUARTO_DIRS || (use != "anchors" && startsWith(e, "_"))) next
      walk(if (nzchar(rel)) paste0(rel, "/", e) else e)
    }
    f <- ents[!isd & grepl(pattern, ents)]
    if (length(f)) out <<- c(out, if (nzchar(rel)) paste0(rel, "/", f) else f)
  }
  walk("")
  if (!length(out)) return(character())
  out[doc_path_ok(out, use)]
}

# The scripts of the project at `root` (C1, C2, K4): `.R` and `.r` files, as sorted relative paths with "/",
# less the folders and files the documents' rule leaves out and those `scripts_skip` names. Each script is
# judged by the `scripts_skip` of its own settings root (the nearest `_weft.yml`, `root`'s when none lies
# below it), with its path relative to that folder. An entry of `scripts_skip` with no "/" is a name: a folder
# on the script's path or its file name. One with a "/" is a path from that folder (a leading "./" and a
# trailing "/" dropped): that script, or every script under that folder. No globs. The settings of `root` are
# read whatever it holds, so a bad one stops the run.
SCRIPT_EXT_RE <- "\\.[rR]$"

project_script_paths <- function(root) {
  skip_of <- scripts_skip_getter(root)
  skip_of("")
  f <- project_files_under(root, SCRIPT_EXT_RE)
  if (!length(f)) return(character())
  f <- enc2utf8(f)
  keep <- vapply(f, function(rel) !script_skipped_in(root, rel, skip_of), NA, USE.NAMES = FALSE)
  sort(f[keep], method = "radix")
}

# The `files` argument of `lints()`, `checks()` and `verify()`: paths to documents and scripts under `root`
# (relative to it, or absolute), as normalised paths relative to `root`. `abort` is the caller's condition
# raiser; `strict` also refuses a folder and drops repeats (`verify()`).
resolve_files <- function(files, root, abort, strict = FALSE) {
  if (!is.character(files) || anyNA(files)) abort("`files` must be paths to .qmd, .Rmd or .R files.")
  absf <- ifelse(is_abs_path(files), files, file.path(root, files))
  nf <- normalizePath(absf, winslash = "/", mustWork = FALSE)
  prob <- !file.exists(absf) | !startsWith(nf, paste0(root, "/")) | !grepl("\\.(qmd|Rmd|rmd|R|r)$", files)
  if (strict) prob <- prob | dir.exists(absf)
  if (any(prob)) {
    abort(paste0("`files` must name existing .qmd, .Rmd or .R files under the project root; not so: ",
                 paste0("`", files[prob], "`", collapse = ", "), " (rule 5.1.1)."))
  }
  rel <- rel_to(nf, root)
  if (strict) unique(rel) else rel
}

# The nearest folder above `rel` (a path from the root, "" for the root) for which `has_yml(folder)` holds.
nearest_settings_dir <- function(rel, has_yml) {
  d <- dirname(rel)
  while (!identical(d, ".") && nzchar(d)) {
    if (has_yml(d)) return(d)
    d <- dirname(d)
  }
  ""
}

# The settings root of a script, as a path from `root` ("" for `root`).
script_settings_root <- function(root, rel) {
  nearest_settings_dir(rel, function(d) file.exists(file.path(root, d, "_weft.yml")))
}

# The `scripts_skip` of a settings root of `root` (a path from it, "" for `root`), normalised and read once.
scripts_skip_getter <- function(root) {
  skips <- list()
  function(sroot) {
    key <- if (nzchar(sroot)) sroot else "."
    if (is.null(skips[[key]])) {
      skips[[key]] <<- list(scripts_skip_list(lint_config(if (nzchar(sroot)) file.path(root, sroot) else root)$scripts_skip))
    }
    skips[[key]][[1L]]
  }
}

# Whether the script `rel` is left out by the `scripts_skip` (`skip_of(settings root)`) of its own settings root.
script_skipped_in <- function(root, rel, skip_of) {
  sroot <- script_settings_root(root, rel)
  inner <- if (nzchar(sroot)) substring(rel, nchar(sroot) + 2L) else rel
  script_skipped(inner, skip_of(sroot))
}

# `skip` is a normalised list (see `scripts_skip_list()`), or NULL.
script_skipped <- function(rel, skip) {
  skip <- skip %||% character()
  if (!length(rel) || !length(skip)) return(rep(FALSE, length(rel)))
  skip <- sub("/+$", "", sub("^\\./", "", trimws(skip)))
  skip <- skip[nzchar(skip)]
  parts <- strsplit(rel, "/", fixed = TRUE)
  vapply(seq_along(rel), function(i) {
    for (e in skip) {
      if (grepl("/", e, fixed = TRUE)) {
        if (rel[i] == e || startsWith(rel[i], paste0(e, "/"))) return(TRUE)
      } else if (e %in% parts[[i]]) {
        return(TRUE)
      }
    }
    FALSE
  }, NA)
}

# ---- writing --------------------------------------------------------------------------------------

# Write `bytes` (raw) to `path` by writing a temporary file in the same folder
# and renaming it over the target, so a reader never sees half a file. Makes the
# folder; keeps the mode of the file it replaces. Stops when it cannot write.
# With `skip_same`, a file that already holds these bytes is left alone (and its
# time kept). Returns whether it wrote.
write_atomic <- function(path, bytes, skip_same = FALSE) {
  d <- dirname(path)
  if (!dir.exists(d)) {
    dir.create(d, recursive = TRUE)
    if (!dir.exists(d)) stop("cannot create the folder ", d, call. = FALSE)
  }
  exists <- file.exists(path) && !dir.exists(path)
  if (skip_same && exists && identical(readBin(path, "raw", file.size(path)), bytes)) {
    return(invisible(FALSE))
  }
  tmp <- tempfile(paste0(".", basename(path), ".tmp"), tmpdir = d)
  on.exit(unlink(tmp), add = TRUE)
  writeBin(bytes, tmp)
  if (exists) Sys.chmod(tmp, file.mode(path), use_umask = FALSE)
  rename_over(tmp, path)
  invisible(TRUE)
}

# rename `tmp` over `path`; where the rename fails, copy it
rename_over <- function(tmp, path) {
  if (!suppressWarnings(file.rename(tmp, path))) {
    if (!file.copy(tmp, path, overwrite = TRUE)) stop("cannot write ", path, call. = FALSE)
  }
}

# Write lines of text, each followed by `eol`, as UTF-8, atomically. A shell
# script must not get CRLF, so `eol` is explicit.
write_lines_atomic <- function(x, path, eol = "\n", skip_same = FALSE) {
  write_atomic(path, charToRaw(paste0(enc2utf8(x), eol, collapse = "")), skip_same)
}

# Copy a file atomically, as `file.copy()` does: TRUE when it was copied, FALSE
# when it was not (or `overwrite` is FALSE and `to` exists).
copy_atomic <- function(from, to, overwrite = TRUE) {
  if (!overwrite && file.exists(to)) return(FALSE)
  tryCatch({
    write_atomic(to, readBin(from, "raw", file.size(from)))
    Sys.chmod(to, file.mode(from), use_umask = FALSE)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
}

# `saveRDS()` to a temporary file in the folder of `path`, then a rename.
write_rds_atomic <- function(object, path, ...) {
  d <- dirname(path)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  tmp <- tempfile(paste0(".", basename(path), ".tmp"), tmpdir = d)
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(object, tmp, ...)
  rename_over(tmp, path)
  invisible(path)
}
