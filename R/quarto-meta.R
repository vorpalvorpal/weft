# ---- Quarto's project layers (rules P1, P2, P8 and P9, spec 2.1.6) --------------------------------------------

# Quarto's own keys that weft reads (`lang`, `execute:`, `bibliography`) mean what Quarto makes of them, so the
# lints read them as Quarto does: from `_quarto.yml`, the active profiles, `_quarto.yml.local`, each folder's
# `_metadata.yml` below the project root down to the document's, then the document (rule P1). Across files
# the merge is deep (P2). `weft:` is not read from any of these files (P3). The evidence is in
# dev/quarto-project-metadata.md. The knit reads Quarto's own view through QUARTO_EXECUTE_INFO (cite.R).

# The documents Quarto renders whatever lies above them; an `.Rmd` (or `.md`) is Quarto's only under a
# `_quarto.yml` (P8).
QUARTO_OWN_EXT_RE <- "\\.(qmd|ipynb|py)$"

# The first of the files `names` in the folder `dir` that exists, or NA.
first_existing <- function(dir, names) {
  p <- file.path(dir, names)
  p <- p[file.exists(p)]
  if (length(p)) p[1L] else NA_character_
}

# The YAML mapping of a project file, its sequences kept as lists (so that `[a]` is a list and `a` is not);
# list() when the file is missing, broken or not a mapping. Read once in a walk.
quarto_layer_yaml <- function(path) {
  if (is.na(path)) return(list())
  walk_memo("quarto_layer_yaml", path, function() {
    if (!file.exists(path)) return(list())
    y <- tryCatch(yaml_read_text(read_source_text(path), file = path, handlers = list(seq = function(x) x)),
                  error = function(e) NULL)
    if (is.list(y) && !is.null(names(y))) y else list()
  })
}

# The profile names of a `profile: default:` (a name, names joined by commas, or a list), or none.
profile_default <- function(y) {
  p <- if (is.list(y)) y[["profile"]] else NULL
  d <- if (is.list(p) && !is.null(names(p))) p[["default"]] else NULL
  as.character(unlist(d))
}

# The active profiles of the project whose config file is `qfile`, the first named first (P9): those of
# QUARTO_PROFILE (which `quarto render --profile` sets), else `profile: default` in `_quarto.yml.local`, else
# in `_quarto.yml`.
quarto_profiles <- function(qfile) {
  env <- Sys.getenv("QUARTO_PROFILE", "")
  named <- if (nzchar(env)) {
    env
  } else {
    d <- profile_default(quarto_layer_yaml(paste0(qfile, ".local")))
    if (length(d)) d else profile_default(quarto_layer_yaml(qfile))
  }
  p <- trimws(unlist(strsplit(named, ",", fixed = TRUE)))
  unique(p[nzchar(p)])
}

# The project files whose metadata applies to the document at `path`, lowest first (P1, P8, P9), as paths:
# `_quarto.yml`; the active `_quarto-<name>.yml` profiles, the first named last, so that it wins;
# `_quarto.yml.local`; the `_metadata.yml` of each folder from the first below the project root down to the
# document's, the root's own only for a document in the root, of the two spellings the first. With no
# `_quarto.yml` above it, a document of Quarto's own has its folder's `_metadata.yml` (A4), and an `.Rmd` none.
quarto_layer_files <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  dir <- dirname(path)
  own <- grepl(QUARTO_OWN_EXT_RE, path, ignore.case = TRUE)
  key <- paste(dir, own, Sys.getenv("QUARTO_PROFILE", ""), sep = "|")
  walk_memo("quarto_layer_files", key, function() {
    qroot <- find_quarto_root(dir)
    if (is.null(qroot)) {
      f <- if (own) first_existing(dir, METADATA_MARKERS) else NA_character_
      return(f[!is.na(f)])
    }
    qfile <- first_existing(qroot, QUARTO_MARKERS)
    prof <- vapply(rev(quarto_profiles(qfile)),
                   function(p) first_existing(qroot, paste0("_quarto-", p, c(".yml", ".yaml"))), "")
    local <- paste0(qfile, ".local")
    parts <- if (identical(dir, qroot)) character() else strsplit(rel_to(dir, qroot), "/", fixed = TRUE)[[1L]]
    mdirs <- if (length(parts)) file.path(qroot, Reduce(function(a, b) paste0(a, "/", b), parts, accumulate = TRUE))
             else qroot
    meta <- vapply(mdirs, first_existing, "", names = METADATA_MARKERS, USE.NAMES = FALSE)
    files <- c(qfile, prof, if (file.exists(local)) local, meta)
    unname(files[!is.na(files)])
  })
}

# ---- the merge (P2) ------------------------------------------------------------------------------------------

q_is_map <- function(x) is.list(x) && !is.null(names(x))
q_is_array <- function(x) (is.list(x) && is.null(names(x))) || (is.atomic(x) && length(x) > 1L)

# `b` merged over `a` as Quarto merges its configs (lodash mergeWith with its array customiser): maps merge
# at every depth; arrays concatenate, `a`'s first, duplicates dropped, and a scalar against an array joins
# it; an empty array, `null` or `false` against an array leaves it; otherwise `b` replaces `a`, so a scalar,
# `null` or `false` replaces a map.
quarto_merge <- function(a, b) {
  if (q_is_map(a) && q_is_map(b)) {
    return(Reduce(function(acc, n) {
      acc[n] <- list(quarto_merge(acc[[n]], b[[n]]))
      acc
    }, names(b), a))
  }
  if (is.null(a)) return(b)
  if (q_is_array(a) || q_is_array(b)) {
    if (!length(b) || isFALSE(b)) return(a)
    if (!length(a) || isFALSE(a)) return(b)
    out <- c(as.list(a), as.list(b))
    return(out[!duplicated(out)])
  }
  b
}

# A path named in a metadata file, against the folder `base` that file sits in.
q_resolve <- function(p, base) {
  if (!length(p)) return(character())
  ifelse(grepl("^(/|~|[A-Za-z]:[/\\\\])", p), path.expand(p), file.path(base, p))
}

# One layer (a file's mapping, or the document's front matter) as the lints read it: the html format's keys
# (`format: html:`) merged deeply over the top-level ones, which they beat within one file (F1, F2); the
# `format:` key itself and every `weft:` key dropped (P3; a document's own `weft:` is read by config.R); and
# its `bibliography` made a list of paths against `base`, the layer's folder, as Quarto rebases them so
# that the files of every layer add up (`base` NULL: the paths as written).
quarto_layer_view <- function(y, base = NULL) {
  if (!q_is_map(y)) return(list())
  html <- if (q_is_map(y[["format"]]) && q_is_map(y[["format"]][["html"]])) y[["format"]][["html"]] else list()
  keep <- function(m) m[setdiff(names(m), c("format", "weft"))]
  v <- quarto_merge(keep(y), keep(html))
  if (!is.null(v[["bibliography"]])) {
    b <- as.character(unlist(v[["bibliography"]]))
    b <- b[!is.na(b) & nzchar(b)]
    v[["bibliography"]] <- as.list(if (is.null(base)) b else q_resolve(b, base))
  }
  v
}

# Quarto's merged view of the project files for the document at `path` (the html format), without the
# document's own front matter: list() when no file applies.
quarto_project_view <- function(path) {
  if (is.null(path) || is.na(path)) return(list())
  files <- quarto_layer_files(path)
  walk_memo("quarto_project_view", paste(files, collapse = "|"), function() {
    Reduce(function(acc, f) quarto_merge(acc, quarto_layer_view(quarto_layer_yaml(f), dirname(f))), files, list())
  })
}

# Quarto's merged view for the document at `path` whose front matter is `front` (read_front_matter(), its
# blocks already combined per top-level key, F3): the document over the project files (P1, P2).
quarto_doc_view <- function(path, front) {
  base <- if (is.null(path)) "." else dirname(normalizePath(path, winslash = "/", mustWork = FALSE))
  quarto_merge(quarto_project_view(path), quarto_layer_view(front, base))
}

# ---- where a `weft:` key does not belong (P3, rule 5.8.8) -----------------------------------------------------

# Quarto's project files under `root` that might hold a misplaced `weft:` key: every `_quarto.yml`, profile,
# `_quarto.yml.local` and `_metadata.yml`, active or not, and the `metadata-files:` targets that the Quarto
# config files (or the documents `docs`) name, as relative paths.
QUARTO_PROJECT_FILE_RE <- "^(_quarto(-[^/]+)?\\.ya?ml(\\.local)?|_metadata\\.ya?ml)$"

quarto_project_files <- function(root, docs = list()) {
  found <- project_doc_paths(root, "lint", QUARTO_PROJECT_FILE_RE)
  named <- function(y, base) {
    mf <- as.character(unlist(if (q_is_map(y)) y[["metadata-files"]] else NULL))
    mf <- mf[!is.na(mf) & nzchar(mf)]
    vapply(mf, function(p) dl_join(base, p), "", USE.NAMES = FALSE)
  }
  cfg <- found[grepl("^_quarto", basename(found))]
  targets <- c(unlist(lapply(cfg, function(f) named(quarto_layer_yaml(file.path(root, f)), dl_dir(f)))),
               unlist(lapply(names(docs), function(f) named(docs[[f]], dl_dir(f)))))
  targets <- targets[!is.na(targets) & file.exists(file.path(root, targets))]
  unique(c(found, targets))
}

# The lines of `lines` (a file's or a front-matter block's) that hold a `weft:` key under `format: <fmt>:`.
format_weft_lines <- function(lines) {
  starts <- which(grepl("^format[ \t]*:", lines))
  top <- grepl("^[^ \t#]", lines)
  unlist(lapply(starts, function(s) {
    nxt <- which(top & seq_along(lines) > s)
    end <- if (length(nxt)) nxt[1L] - 1L else length(lines)
    if (end <= s) return(integer())
    idx <- (s + 1L):end
    ind <- nchar(sub("^([ \t]*).*$", "\\1", lines[idx]))
    body <- nzchar(trimws(lines[idx])) & !grepl("^[ \t]*#", lines[idx])
    if (!any(body)) return(integer())
    idx[body & ind > min(ind[body]) & grepl("^[ \t]+weft[ \t]*:", lines[idx])]
  }))
}

# Whether a mapping holds `weft:` under some `format: <fmt>:`.
has_format_weft <- function(y) {
  f <- if (q_is_map(y)) y[["format"]] else NULL
  q_is_map(f) && any(vapply(f, function(m) q_is_map(m) && "weft" %in% names(m), NA))
}
