# Definitions shared by more than one helper file. testthat sources helpers alphabetically, and
# "helper-0-common.R" sorts before every other helper, so these exist when the others are read.

`%||%` <- function(a, b) if (is.null(a)) b else a

# the Python library folder that ships with weft
py_lib_6e <- function() normalizePath(system.file("python", package = "weft"), mustWork = FALSE)

# the text of an output file of a render, or ""
qm_read <- function(dir, rel) {
  p <- file.path(dir, rel)
  if (!file.exists(p)) return("")
  paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

# `quarto render <args>` in dir with the variables `vars` set, then `env` over them. Returns
# list(status, stdout, stderr, log). The helper that calls it sets up `vars` (and its own scratch).
quarto_render_env <- function(dir, args, vars, env) {
  lib <- weft_test_lib()
  if (nzchar(lib)) vars[["R_LIBS"]] <- paste(c(lib, .libPaths()), collapse = .Platform$path.sep)
  for (n in names(env)) vars[[n]] <- env[[n]]
  # a render on the julia engine starts Julia, which must not get the system libunwind (finding 22)
  vars <- c(vars, weft:::julia_child_env())
  withr::local_envvar(vars)
  withr::local_dir(dir)
  errf <- tempfile("q-err-")
  on.exit(unlink(errf), add = TRUE)
  out <- suppressWarnings(system2(Sys.which("quarto"), c("render", args), stdout = TRUE, stderr = errf))
  st <- attr(out, "status")
  err <- paste(readLines(errf, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  list(status = if (is.null(st)) 0L else as.integer(st), stdout = paste(out, collapse = "\n"), stderr = err,
       log = paste(c(out, err), collapse = "\n"))
}

# the scalar records of N22, written as compact JSON the way a writer would
fr_int <- function(digits) sprintf('{"t":"int","v":"%s"}', digits)
fr_float <- function(text) sprintf('{"t":"float","v":"%s"}', text)
fr_dec <- function(text) sprintf('{"t":"decimal","v":"%s"}', text)

# weft_str()'s old result (E1, dev/design-e1.md): the markdown form of a weft() object, unnamed, NA kept
weft_md <- function(x, .envir = parent.frame()) {
  w <- weft::weft(x, .envir = .envir)
  out <- unname(format(w, target = "markdown"))
  out[is.na(w)] <- NA_character_
  out
}

# ---- git isolation (moved from helper-4a.R; used by every helper that builds a repository) ----

skip_if_no_git <- function() {
  testthat::skip_if(!nzchar(Sys.which("git")), "git is not on the PATH")
}

# Isolate git for the calling test: no user or system configuration, an invented identity and fixed dates,
# no inherited repository variables. `env` is the frame the settings last until.
git_env <- function(env = parent.frame()) {
  empty_g <- withr::local_tempfile(.local_envir = env, lines = character())
  empty_s <- withr::local_tempfile(.local_envir = env, lines = character())
  home <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(
    GIT_CONFIG_GLOBAL = empty_g, GIT_CONFIG_SYSTEM = empty_s, GIT_CONFIG_NOSYSTEM = "1", HOME = home,
    XDG_CONFIG_HOME = file.path(home, "xdg"),
    GIT_AUTHOR_NAME = "Test Writer", GIT_AUTHOR_EMAIL = "writer@example.invalid",
    GIT_COMMITTER_NAME = "Test Writer", GIT_COMMITTER_EMAIL = "writer@example.invalid",
    GIT_AUTHOR_DATE = "2026-01-02T03:04:05+0000", GIT_COMMITTER_DATE = "2026-01-02T03:04:05+0000",
    GIT_DIR = NA, GIT_WORK_TREE = NA, GIT_INDEX_FILE = NA, GIT_COMMON_DIR = NA, GIT_PREFIX = NA,
    GIT_EDITOR = "true", GIT_TERMINAL_PROMPT = "0",
    .local_envir = env)
  invisible(NULL)
}

# Run git in `dir`; returns the output lines with the exit status as attribute "status".
g_git <- function(dir, ...) {
  args <- c("-C", dir, "-c", "core.quotepath=false", c(...))
  out <- suppressWarnings(system2("git", shQuote(args), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  structure(as.character(out), status = if (is.null(st)) 0L else st)
}
g_ok_git <- function(dir, ...) {
  out <- g_git(dir, ...)
  if (!identical(attr(out, "status"), 0L)) {
    stop("git failed: ", paste(c(...), collapse = " "), "\n", paste(out, collapse = "\n"))
  }
  invisible(out)
}
