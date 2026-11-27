# Notebooks and percent scripts on the surfaces beyond lints(): the commit gate, verify(), checks() and status().
# Spec: dev/PACKAGE-SCOPING.md 2.1.6 P7, 5.1.8, 6, 8, 9.5.3; dev/decisions.md "Project, folder, include and
# notebook metadata (2026-11-27)", which says lints() lists .ipynb and the gate, verify(), checks() and
# status() do not yet, and that percent scripts are not linted. ASCII only. Invented content only.
#
# ---- COST NOTE (measured 27 Nov 2026, Quarto 1.11.9, Jupyter from ~/.venvs/jupyter) --------------------------
#
# Which .py files Quarto treats as documents. Quarto's own test (quarto.js, isJupyterPercentScript, used by the
# jupyter engine's claimsFile) is: the extension is .py (also .jl and .r), and the text matches, on any line,
#   ^\s*#\s*%%+\s+\[(markdown|raw)\]      (multiline)
# So a .py is a document if and only if it has a `# %% [markdown]` or `# %% [raw]` line anywhere. A `.py` that
# has only `# %%` code cells, or none, is NOT claimed: `quarto inspect` of a project leaves it out of
# files.input and `quarto render x.py` stops with "Can't determine execution engine". An ordinary module is
# therefore never swept in, EXCEPT a module that happens to hold a `# %% [markdown]` line (a module with a
# stray cell marker): Quarto renders that, so a weft that follows Quarto reads it too. Detection must be that
# regex, not "has `# %%`": a percent script with code cells only is not a document. Percent scripts in .jl
# and .r are claimed by the same rule; weft's P7 names .py only, and no test here covers .jl or .r.
# An .ipynb under the project root is a Quarto document, except under a `.` folder (.ipynb_checkpoints)
# and a `_` folder (where it is an include, not a render target).
#
# What each surface costs.
#  * gate: reads the JSON of each staged .ipynb on both sides of a commit. Measured: parsing a 1.7 MB notebook
#    (2000 cells, outputs included) with jsonlite takes 0.03 s; reading the lines takes 0.02 s. A commit that
#    touches no notebook reads none. CHEAP.
#  * checks() and status(): read the same files with the same reader (status() only needs to know a Jupyter
#    document exists for its `python` row, and starts no R and runs no kernel, 9.5.3). CHEAP.
#  * verify(), static part and `since`: the same read, no kernel. CHEAP, and tested here with static = TRUE.
#  * verify(), render part: IMPORTANT, NOT TESTED. Rendering a percent .py runs the script through Jupyter
#    (measured: a two-cell script that writes a file did write it, 3.6 s for a trivial one), so verify() would
#    execute user code in a .py that a user may think of as a module. Rendering an .ipynb with no outputs did
#    NOT execute it (Quarto renders notebooks as stored unless `execute: enabled: true` or --execute), so there
#    verify() would not produce values from the kernel at all. Either way the decision (does verify() execute
#    notebooks and scripts? does it honour freeze and `execute: enabled: false`?) is Robin's, not a test's.
#
# Test choices. Positions: an .ipynb finding is at the line of the JSON file that holds the source line
# (P7, decisions.md); a percent .py finding is at the line of the .py file (no mapping is needed: the cell body
# is the file's own lines, with `# ` stripped). Fixtures are the notebooks Jupyter writes: one source line per
# JSON line. Surfaces that read notebooks must also leave alone: an ordinary .py module, a code-only percent
# script, and notebooks in `.ipynb_checkpoints` and `_freeze`. A .qmd behaves as before (twin controls).

# ---- building notebooks and scripts --------------------------------------------------------------------------

NBS_GUARD <- function(cond, word = "exceeded the limit") sprintf("The site [%s]{if=\"%s\"} on most days.", word, cond)
NBS_BAD <- paste("A", F3_BAD_TWO, "here.")   # the construct error of rule 1.1.5, one line

# a cell: list(type, lines)
nbs_md <- function(...) list(type = "markdown", lines = c(...))
nbs_raw <- function(...) list(type = "raw", lines = c(...))
nbs_code <- function(...) list(type = "code", lines = c(...))

nbs_q <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))

# the lines of an .ipynb as Jupyter writes it (one source line per JSON line) and `at(cell, k)`, the JSON line
# that holds line k of the source of cell number `cell`
nbs_ipynb <- function(cells) {
  out <- c("{", " \"cells\": [")
  at <- vector("list", length(cells))
  for (i in seq_along(cells)) {
    cl <- cells[[i]]
    out <- c(out, "  {", sprintf("   \"cell_type\": \"%s\",", cl$type))
    if (cl$type == "code") out <- c(out, "   \"execution_count\": null,")
    out <- c(out, "   \"metadata\": {},")
    if (cl$type == "code") out <- c(out, "   \"outputs\": [],")
    out <- c(out, "   \"source\": [")
    n <- length(cl$lines)
    at[[i]] <- length(out) + seq_len(n)
    src <- paste0(vapply(seq_len(n), function(k) {
      nbs_q(if (k < n) paste0(cl$lines[[k]], "\n") else cl$lines[[k]])
    }, ""), c(rep(",", max(n - 1L, 0L)), ""))
    out <- c(out, paste0("    ", src), "   ]", if (i < length(cells)) "  }," else "  }")
  }
  out <- c(out, " ],",
           " \"metadata\": {\"kernelspec\": {\"display_name\": \"Python 3\", \"language\": \"python\", \"name\": \"python3\"}},",
           " \"nbformat\": 4,", " \"nbformat_minor\": 5", "}")
  stopifnot(jsonlite::validate(paste(out, collapse = "\n")))
  list(lines = out, at = function(cell, k) at[[cell]][k])
}

# the lines of a percent script and `at(cell, k)`, the line of the file that holds line k of cell `cell`'s body
nbs_py <- function(cells) {
  out <- character()
  at <- vector("list", length(cells))
  for (i in seq_along(cells)) {
    cl <- cells[[i]]
    hdr <- if (cl$type == "code") "# %%" else paste0("# %% [", cl$type, "]")
    out <- c(out, hdr)
    n <- length(cl$lines)
    at[[i]] <- length(out) + seq_len(n)
    body <- if (cl$type == "code") cl$lines else ifelse(nzchar(cl$lines), paste0("# ", cl$lines), "#")
    out <- c(out, body, "")
  }
  list(lines = out, at = function(cell, k) at[[cell]][k])
}

# a Python module with no cell marker at all, holding text a weft reader would object to if it read it
nbs_module <- function(extra = NBS_BAD) {
  c("import os", "", "def f(x):", sprintf("    # %s", extra), sprintf("    return \"%s\"", gsub("\"", "'", extra)))
}
# a percent script with code cells only: Quarto does not claim it (no markdown or raw cell)
nbs_code_only_script <- function(extra = NBS_BAD) {
  c("# %%", sprintf("# %s", extra), "x = 1", "", "# %%", "print(x)", "")
}

# ---- the lints() oracle -----------------------------------------------------------------------------------

nbs_lint_lines <- function(root, file) {
  x <- lints(root, rules = "construct", tier = 1:2)
  x$line[x$file == file]
}

# ---- verify(), static part ---------------------------------------------------------------------------------

nbs_verify <- function(files, ..., env = parent.frame()) {
  v4_env(env = env)
  p <- v4_proj(files, env = env)
  list(p = p, r = v4_verify(p$root, static = TRUE, ...))
}
nbs_errs <- function(r) {
  if (is.null(r$res$errors)) return(data.frame(file = character(), line = integer()))
  as.data.frame(unclass(r$res$errors), stringsAsFactors = FALSE)
}

test_that("notebooks N0: the lints() oracle places a finding at the JSON line (control, as built today)", {
  nb <- nbs_ipynb(list(nbs_md("# Title", "", "Prose.", NBS_BAD), nbs_code("x = 1")))
  root <- lint_proj(list("nb.ipynb" = nb$lines))
  expect_identical(nbs_lint_lines(root, "nb.ipynb"), nb$at(1L, 4L))
  # one source line per JSON line, so the JSON line is not the cell's line
  expect_gt(nb$at(1L, 4L), 4L)
})

test_that("notebooks verify: a construct error in an .ipynb fails static verify() at the JSON line", {
  nb <- nbs_ipynb(list(nbs_md("# Title", "", "Prose.", NBS_BAD), nbs_code("x = 1")))
  v <- nbs_verify(list("nb.ipynb" = nb$lines))
  e <- nbs_errs(v$r)
  expect_false(is.null(v$r$err), label = "verify() raised")
  expect_identical(e$file, "nb.ipynb")
  expect_identical(e$line, nb$at(1L, 4L))
  expect_identical(e$line, nbs_lint_lines(v$p$root, "nb.ipynb"))
})

test_that("notebooks verify: a construct error in a percent .py with a markdown cell fails static verify()", {
  py <- nbs_py(list(nbs_code("x = 1"), nbs_md("# Title", "", NBS_BAD)))
  v <- nbs_verify(list("script.py" = py$lines))
  e <- nbs_errs(v$r)
  expect_false(is.null(v$r$err), label = "verify() raised")
  expect_identical(e$file, "script.py")
  expect_identical(e$line, py$at(2L, 3L))
})

test_that("notebooks verify: a raw cell of a percent .py is read as well", {
  py <- nbs_py(list(nbs_raw("---", "title: t", "---"), nbs_md(NBS_BAD)))
  v <- nbs_verify(list("script.py" = py$lines))
  expect_identical(nbs_errs(v$r)$line, py$at(2L, 1L))
})

test_that("notebooks verify: control, files that are not weft documents are left alone", {
  nb <- nbs_ipynb(list(nbs_md(NBS_BAD)))
  v <- nbs_verify(list(
    "pkg/util.py" = nbs_module(),                       # an ordinary module
    "pkg/cells.py" = nbs_code_only_script(),           # percent cells but none markdown or raw: not claimed
    ".ipynb_checkpoints/nb-checkpoint.ipynb" = nb$lines,
    "_freeze/nb/copy.ipynb" = nb$lines,
    "ok.qmd" = V4_PLAIN_DOC))
  expect_null(v$r$err, label = if (!is.null(v$r$err)) conditionMessage(v$r$err) else "no error")
  expect_identical(nrow(nbs_errs(v$r)), 0L)
})

test_that("notebooks verify: a module with a stray markdown cell marker IS a Quarto document, so it is read", {
  # Quarto claims any .py with a `# %% [markdown]` line, so a weft that follows Quarto reads it (cost note)
  mod <- c(nbs_module(), "", "# %% [markdown]", paste("#", NBS_BAD))
  v <- nbs_verify(list("util.py" = mod))
  expect_identical(nbs_errs(v$r)$line, length(mod))
})

test_that("notebooks verify: control, a .qmd behaves as before", {
  v <- nbs_verify(list("a.qmd" = c("Prose.", "", NBS_BAD)))
  e <- nbs_errs(v$r)
  expect_identical(e$file, "a.qmd")
  expect_identical(e$line, 3L)
})

test_that("notebooks verify: since lists a finding added in a notebook at its JSON line, not one already in HEAD", {
  v4_env()
  old <- nbs_ipynb(list(nbs_md("Prose.", NBS_BAD)))
  # ruling 27 Nov: a construct error is listed apart from `added` (8.1.1, 6.2.2), so the finding
  # added is a typed numeral, a tier-1 finding that is not a construct error
  new <- nbs_ipynb(list(nbs_md("Prose.", NBS_BAD, "", "More.", "The site had 42 visits.")))
  p <- v4_proj(list("nb.ipynb" = old$lines), git = TRUE)
  base <- g_head(p$top)
  g_write(p$top, "nb.ipynb", new$lines)
  g_add(p$top)
  g_commit(p$top, "second")
  r <- v4_verify(p$root, since = base, static = TRUE)
  a <- as.data.frame(unclass(r$res$added), stringsAsFactors = FALSE)
  expect_identical(a$file[a$rule == "numeral"], "nb.ipynb")
  expect_identical(a$line[a$rule == "numeral"], new$at(1L, 5L))
})

# ---- checks() -----------------------------------------------------------------------------------------------

GUARDS <- c("x > 5", "y < 2")
nbs_guard_lines <- function() c("Intro.", "", NBS_GUARD(GUARDS[[1]], "one"), "", NBS_GUARD(GUARDS[[2]], "two"))

test_that("notebooks checks: guards in an .ipynb markdown cell are listed at their JSON lines, as a .qmd lists them", {
  nb <- nbs_ipynb(list(nbs_md(nbs_guard_lines()), nbs_code("x = 1")))
  root <- lint_proj(list("nb.ipynb" = nb$lines, "twin.qmd" = nbs_guard_lines()))
  x <- as.data.frame(unclass(checks(root)), stringsAsFactors = FALSE)
  n <- x[x$file == "nb.ipynb", , drop = FALSE]
  q <- x[x$file == "twin.qmd", , drop = FALSE]
  expect_identical(q$line, c(3L, 5L))                        # control: the .qmd is read as before
  expect_identical(n$line, nb$at(1L, c(3L, 5L)))
  expect_identical(n$cond, q$cond)
  expect_identical(n$role, q$role)
})

test_that("notebooks checks: guards in a percent .py markdown cell are listed at their lines in the file", {
  py <- nbs_py(list(nbs_code("x = 1"), nbs_md(nbs_guard_lines())))
  root <- lint_proj(list("script.py" = py$lines))
  x <- as.data.frame(unclass(checks(root)), stringsAsFactors = FALSE)
  expect_identical(x$file, rep("script.py", 2L))
  expect_identical(x$line, py$at(2L, c(3L, 5L)))
  expect_identical(x$cond, GUARDS)
})

test_that("notebooks checks: control, an ordinary .py, a code-only script and non-document notebooks add no rows", {
  nb <- nbs_ipynb(list(nbs_md(nbs_guard_lines())))
  gl <- NBS_GUARD("z == 1")
  root <- lint_proj(list(
    "twin.qmd" = nbs_guard_lines(),
    "util.py" = nbs_module(gl),
    "cells.py" = nbs_code_only_script(gl),
    ".ipynb_checkpoints/nb-checkpoint.ipynb" = nb$lines,
    "_freeze/nb/copy.ipynb" = nb$lines))
  x <- as.data.frame(unclass(checks(root)), stringsAsFactors = FALSE)
  expect_identical(unique(x$file), "twin.qmd")
  expect_identical(x$line, c(3L, 5L))
})

# ---- the gate ----------------------------------------------------------------------------------------------

# a notebook document with guard paragraphs for `conds`, and the gate's rows for one file
nbs_gate_cells <- function(conds) list(nbs_md(j7_gdoc(conds)), nbs_code("x = 1"))
nbs_rows <- function(res, file) {
  r <- as.data.frame(unclass(res$checks), stringsAsFactors = FALSE)
  r[r$file == file, , drop = FALSE]
}

test_that("notebooks gate: a guard removed from a staged .ipynb is reported at its JSON line in HEAD, as for a .qmd", {
  before <- nbs_ipynb(nbs_gate_cells(c("n1 > 1", "n2 > 3")))
  after <- nbs_ipynb(nbs_gate_cells("n1 > 1"))
  d <- g_scenario(list("nb.ipynb" = before$lines, "twin.qmd" = j7_gdoc(c("n1 > 1", "n2 > 3"))),
                  list("nb.ipynb" = after$lines, "twin.qmd" = j7_gdoc("n1 > 1")))
  res <- g_gate(d)
  q <- nbs_rows(res, "twin.qmd")
  expect_identical(q$line, 3L)                               # control: the .qmd is read as before
  expect_identical(q$verdict, "none")
  n <- nbs_rows(res, "nb.ipynb")
  expect_identical(n$line, before$at(1L, 3L))
  expect_identical(n$cond, "n2 > 3")
  expect_identical(n$verdict, q$verdict)
})

test_that("notebooks gate: a deleted .ipynb gives a row for each of its checks", {
  before <- nbs_ipynb(nbs_gate_cells(c("n1 > 1", "n2 > 3")))
  d <- g_scenario(list("nb.ipynb" = before$lines, "keep.qmd" = j7_gdoc("k1 > 1")), list("nb.ipynb" = NULL))
  res <- g_gate(d)
  n <- nbs_rows(res, "nb.ipynb")
  expect_identical(n$verdict, rep("deleted", 2L))
  expect_identical(n$line, before$at(1L, c(1L, 3L)))
})

test_that("notebooks gate: a guard removed from a staged percent .py markdown cell is reported at its line", {
  before <- nbs_py(list(nbs_code("x = 1"), nbs_md(j7_gdoc(c("n1 > 1", "n2 > 3")))))
  after <- nbs_py(list(nbs_code("x = 1"), nbs_md(j7_gdoc("n1 > 1"))))
  d <- g_scenario(list("script.py" = before$lines), list("script.py" = after$lines))
  res <- g_gate(d)
  n <- nbs_rows(res, "script.py")
  expect_identical(n$line, before$at(2L, 3L))
  expect_identical(n$cond, "n2 > 3")
  expect_identical(n$verdict, "none")
})

test_that("notebooks gate: control, staged edits to an ordinary .py, a code-only script and a checkpoint are ignored", {
  gl <- NBS_GUARD("z == 1")
  nb <- nbs_ipynb(list(nbs_md(j7_gdoc(c("n1 > 1", "n2 > 3")))))
  nb2 <- nbs_ipynb(list(nbs_md(j7_gdoc("n1 > 1"))))
  d <- g_scenario(
    list("util.py" = nbs_module(gl), "cells.py" = nbs_code_only_script(gl),
         ".ipynb_checkpoints/nb-checkpoint.ipynb" = nb$lines, "a.qmd" = j7_gdoc("a1 > 1")),
    list("util.py" = nbs_module("nothing"), "cells.py" = nbs_code_only_script("nothing"),
         ".ipynb_checkpoints/nb-checkpoint.ipynb" = nb2$lines, "a.qmd" = j7_gdoc("a1 > 1")))
  res <- g_gate(d)
  expect_identical(nrow(nbs_rows(res, "util.py")), 0L)
  expect_identical(nrow(nbs_rows(res, "cells.py")), 0L)
  expect_false(any(grepl("ipynb_checkpoints", res$checks$file)))
})

test_that("notebooks gate: control, a .qmd behaves as before", {
  d <- g_scenario(list("a.qmd" = j7_gdoc(c("a1 > 1", "a2 > 3"))), list("a.qmd" = j7_gdoc("a1 > 1")))
  res <- g_gate(d)
  q <- nbs_rows(res, "a.qmd")
  expect_identical(q$line, 3L)
  expect_identical(q$verdict, "none")
})

# ---- status() ----------------------------------------------------------------------------------------------

nbs_status <- function(files, env = parent.frame()) {
  d <- u4_dir(files)
  git_env(env)
  h4_env(env)
  h4_status(d)
}
has_python_row <- function(st) "python" %in% st$part

test_that("notebooks status: control, a .qmd with a {python} chunk gives the python row; no Jupyter document, none", {
  q <- c("---", "title: t", "---", "", "```{python}", "x = 1", "```")
  expect_true(has_python_row(nbs_status(list("a.qmd" = q))))
  expect_false(has_python_row(nbs_status(list("a.qmd" = u4_qmd()))))
})

test_that("notebooks status: an .ipynb is a Jupyter document, so the python row appears", {
  nb <- nbs_ipynb(list(nbs_md("# Title"), nbs_code("x = 1")))
  expect_true(has_python_row(nbs_status(list("a.qmd" = u4_qmd(), "nb.ipynb" = nb$lines))))
})

test_that("notebooks status: a percent .py with a markdown cell is a Jupyter document too", {
  py <- nbs_py(list(nbs_md("# Title"), nbs_code("x = 1")))
  expect_true(has_python_row(nbs_status(list("a.qmd" = u4_qmd(), "script.py" = py$lines))))
})

test_that("notebooks status: control, an ordinary .py, a code-only script and non-document notebooks add no python row", {
  nb <- nbs_ipynb(list(nbs_md("# Title")))
  st <- nbs_status(list("a.qmd" = u4_qmd(), "util.py" = nbs_module(), "cells.py" = nbs_code_only_script(),
                        ".ipynb_checkpoints/nb-checkpoint.ipynb" = nb$lines, "_freeze/nb/copy.ipynb" = nb$lines))
  expect_false(has_python_row(st))
})

# ---- verify(), render part (real Quarto and Jupyter; each render costs seconds) --------------------------------
# verify() renders an .ipynb or a percent .py exactly as `quarto render` of the project would: a notebook as
# stored (not executed) unless its front matter says `execute: enabled: true`; a percent script executed through
# Jupyter unless `execute: enabled: false` (or a _freeze entry) says not. Claims in a Python document are
# `claim()` calls in code cells (a markdown cell holds no claim), found by the file line of the call.

nbs_marker_code <- function(...) nbs_code("open('MARKER', 'w').write('ran')", ...)

nbs_render_project <- function(files, env = parent.frame()) {
  skip_if_no_jupyter()
  v4_env(libs = TRUE, env = env)
  scratch <- withr::local_tempdir(.local_envir = env)
  for (d in c("data", "runtime", "ipython")) dir.create(file.path(scratch, d))
  withr::local_envvar(QUARTO_PYTHON = jupyter_python(), PYTHONPATH = py_lib_6e(), PYTHONDONTWRITEBYTECODE = "1",
                      JUPYTER_DATA_DIR = file.path(scratch, "data"), JUPYTER_RUNTIME_DIR = file.path(scratch, "runtime"),
                      IPYTHONDIR = file.path(scratch, "ipython"), .local_envir = env)
  dir <- normalizePath(withr::local_tempdir(.local_envir = env), winslash = "/")
  writeLines(c("project:", "  type: default", "format: html"), file.path(dir, "_quarto.yml"))
  put_files(dir, c(files, list("_weft.yml" = "draft: false")))
  suppressMessages(utils::capture.output(weft::use_quarto(dir)))
  dir
}
nbs_marker <- function(dir) file.exists(file.path(dir, "MARKER"))

test_that("notebooks verify render: an .ipynb with no outputs is rendered as stored, as quarto render does, and not executed", {
  skip_if_no_quarto()
  nb <- nbs_ipynb(list(nbs_md("# Title", "", "Prose."), nbs_marker_code()))
  dir <- nbs_render_project(list("nb.ipynb" = nb$lines))
  r <- v4_verify(dir)
  expect_false(nbs_marker(dir), label = "verify() did not execute the notebook")
  expect_null(r$err, label = if (!is.null(r$err)) conditionMessage(r$err) else "no error")
  x <- qm_render(dir)
  expect_identical(x$status, 0L, label = x$log)
  expect_false(nbs_marker(dir), label = "quarto render did not execute it either")
})

NBS_FAIL_CODE <- c("from weft import claim", "n = 7", "claim(n, '> 10')")

test_that("notebooks verify render: a percent .py is executed, and a failing claim is reported at its own file line", {
  skip_if_no_quarto()
  py <- nbs_py(list(nbs_md("# Title"), nbs_marker_code(), nbs_code(NBS_FAIL_CODE)))
  dir <- nbs_render_project(list("script.py" = py$lines))
  r <- v4_verify(dir)
  expect_true(nbs_marker(dir), label = "the script was executed")
  expect_false(is.null(r$err), label = "verify() raised")
  k <- as.data.frame(unclass(r$res$knit), stringsAsFactors = FALSE)
  k <- k[k$file == "script.py", , drop = FALSE]
  expect_identical(k$line, py$at(3L, 3L))
})

test_that("notebooks verify render: a percent .py with execute: enabled: false in its front-matter cell is not executed", {
  skip_if_no_quarto()
  py <- nbs_py(list(nbs_raw("---", "execute:", "  enabled: false", "---"), nbs_md("# Title"),
                    nbs_marker_code(), nbs_code(NBS_FAIL_CODE)))
  dir <- nbs_render_project(list("script.py" = py$lines))
  r <- v4_verify(dir)
  expect_false(nbs_marker(dir), label = "the script was not executed")
  k <- if (is.null(r$res$knit)) data.frame(file = character()) else as.data.frame(unclass(r$res$knit))
  expect_false("script.py" %in% k$file)
})

test_that("notebooks verify render: an .ipynb with execute: enabled: true is executed", {
  skip_if_no_quarto()
  nb <- nbs_ipynb(list(nbs_raw("---", "execute:", "  enabled: true", "---"), nbs_md("# Title"), nbs_marker_code()))
  dir <- nbs_render_project(list("nb.ipynb" = nb$lines))
  r <- v4_verify(dir)
  expect_true(nbs_marker(dir), label = "the notebook was executed")
})

# ==== notebook files: files = and skipped folders (formerly test-notebook-files.R) ====
# Two gaps left by the notebook surfaces (test-notebook-surfaces.R). ASCII only. Invented content only.
#
# 1. `files =` of lints(), checks() and verify() takes an .ipynb and a percent .py as well as .qmd, .Rmd and .R
#    (ruling 27 Nov 2026). A .py that is not a percent script (Quarto's isJupyterPercentScript: a
#    `# %% [markdown]` or `# %% [raw]` line) is refused as not a document Quarto renders. Its message, like the
#    message for a missing file, names .ipynb and percent scripts.
# 2. Folders Quarto leaves out of a project's inputs. MEASURED 27 Nov 2026 with `quarto inspect`, Quarto 1.11.9,
#    and read in the bundled quarto.js (projectInputFilesInternal, engineIgnoreDirs): the rule is NOT
#    `pyvenv.cfg` (only a hint message for an unactivated environment uses that, via isEnvDir). Quarto skips a
#    folder by its NAME, at any depth, whatever it holds: node_modules, and each engine's ignoreDirs: renv,
#    packrat, rsconnect (knitr) and venv, env (julia engine). Case is significant (not testable on a
#    case-insensitive disk). Not skipped: a folder holding pyvenv.cfg under any other name ("myenv"), a
#    conda environment (a conda-meta folder) under any other name, "envx", "environment". Dot folders (.venv)
#    and `_` folders are skipped as before. Inside a skipped folder a .qmd is skipped too.
#    decisions.md says the rule is `pyvenv.cfg`; the test follows Quarto, and the decision text is wrong.

NBF_GUARDS <- c("x > 5", "y < 2")
# a notebook cell holding a construct error and two guards, so every surface has something to report
nbf_body <- function() c("Prose.", "", NBS_BAD, "", NBS_GUARD(NBF_GUARDS[[1]], "one"), "", NBS_GUARD(NBF_GUARDS[[2]], "two"))
nbf_ipynb <- function() nbs_ipynb(list(nbs_md(nbf_body()), nbs_code("x = 1")))
nbf_pys <- function() nbs_py(list(nbs_code("x = 1"), nbs_md(nbf_body())))

# the three documents put in each folder of the fixture
nbf_docs <- function(dir) {
  setNames(list(nbf_ipynb()$lines, nbf_pys()$lines, nbf_body()),
           file.path(dir, c("n.ipynb", "p.py", "b.qmd")))
}
NBF_SKIPPED <- c("env", "venv", "renv", "packrat", "rsconnect", "node_modules", "pk/env", "deep/venv", ".venv")
NBF_READ <- c("myenv", "envx", "environment", "conda_env")
nbf_fixture <- function() {
  skipped <- do.call(c, lapply(NBF_SKIPPED, nbf_docs))
  read <- do.call(c, lapply(NBF_READ, nbf_docs))
  c(list("top.qmd" = nbf_body()), skipped, read,
    list("env/pyvenv.cfg" = "home = /usr", "myenv/pyvenv.cfg" = "home = /usr",
         ".venv/pyvenv.cfg" = "home = /usr", "conda_env/conda-meta/history" = "# none"))
}
nbf_files <- function(dirs, kinds = c("n.ipynb", "p.py", "b.qmd")) {
  as.vector(outer(kinds, dirs, function(k, d) file.path(d, k)))
}
nbf_df <- function(x) {
  d <- as.data.frame(unclass(x), stringsAsFactors = FALSE)
  rownames(d) <- NULL
  d
}
nbf_msg <- function(e) cli::ansi_strip(conditionMessage(e))

# ---- the runners: the data frame of findings or rows each function gives, with or without files ---------------

nbf_lints <- function(root, files = NULL) nbf_df(lints(root, files = files, rules = "construct", tier = 1:2))
nbf_checks <- function(root, files = NULL) nbf_df(checks(root, files = files))
nbf_verify <- function(root, files = NULL) {
  r <- v4_verify(root, static = TRUE, files = files)
  list(err = r$err, df = nbs_errs(r))
}
nbf_only <- function(d, file) {
  d <- d[d$file == file, , drop = FALSE]
  rownames(d) <- NULL
  d
}

# ---- 1. files = ----------------------------------------------------------------------------------------------

NBF_PROJECT <- function() list("nb.ipynb" = nbf_ipynb()$lines, "script.py" = nbf_pys()$lines,
                               "util.py" = nbs_module(), "a.qmd" = nbf_body())

nbf_check_refusal <- function(e, what, ordinary = FALSE) {
  expect_false(is.null(e), label = paste(what, "raised"))
  msg <- nbf_msg(e)
  expect_true(grepl("`files` must name existing", msg, fixed = TRUE), label = paste(what, msg))
  expect_true(grepl(".ipynb", msg, fixed = TRUE), label = paste(what, ".ipynb named"))
  expect_true(grepl("percent script", msg, fixed = TRUE), label = paste(what, "percent scripts named"))
  if (ordinary) expect_true(grepl("not a document Quarto renders", msg, fixed = TRUE), label = paste(what, msg))
}

test_that("notebook files lints: files = an .ipynb gives what lints() gives for it, with no files", {
  root <- lint_proj(NBF_PROJECT())
  x <- nbf_lints(root, "nb.ipynb")
  expect_gt(nrow(x), 0L)
  expect_identical(unique(x$file), "nb.ipynb")
  expect_identical(x, nbf_only(nbf_lints(root), "nb.ipynb"))
})

test_that("notebook files lints: files = a percent .py gives what lints() gives for it, with no files", {
  root <- lint_proj(NBF_PROJECT())
  expect_identical(nbf_lints(root, "script.py"), nbf_only(nbf_lints(root), "script.py"))
})

test_that("notebook files lints: control, files = a .qmd is as before", {
  root <- lint_proj(NBF_PROJECT())
  x <- nbf_lints(root, "a.qmd")
  expect_gt(nrow(x), 0L)
  expect_identical(x, nbf_only(nbf_lints(root), "a.qmd"))
})

test_that("notebook files lints: an ordinary .py, and a missing file, are refused with the message that names notebooks", {
  root <- lint_proj(NBF_PROJECT())
  nbf_check_refusal(f2_cond(lints(root, files = "util.py")), "util.py", ordinary = TRUE)
  nbf_check_refusal(f2_cond(lints(root, files = "gone.ipynb")), "gone.ipynb")
  expect_true(grepl("gone.ipynb", nbf_msg(f2_cond(lints(root, files = "gone.ipynb"))), fixed = TRUE))
})

test_that("notebook files checks: files = an .ipynb or a percent .py gives its rows of checks() with no files", {
  root <- lint_proj(NBF_PROJECT())
  all <- nbf_checks(root)
  for (f in c("nb.ipynb", "script.py", "a.qmd")) {
    x <- nbf_checks(root, f)
    expect_identical(unique(x$file), f, label = f)
    expect_identical(x$cond, NBF_GUARDS, label = f)
    expect_identical(x, nbf_only(all, f), label = f)
  }
})

test_that("notebook files checks: an ordinary .py, and a missing file, are refused", {
  root <- lint_proj(NBF_PROJECT())
  nbf_check_refusal(f2_cond(checks(root, files = "util.py")), "util.py", ordinary = TRUE)
  nbf_check_refusal(f2_cond(checks(root, files = "gone.ipynb")), "gone.ipynb")
})

test_that("notebook files verify: files = an .ipynb or a percent .py reports what verify() reports for it, with no files", {
  v4_env()
  p <- v4_proj(NBF_PROJECT())
  all <- nbf_verify(p$root)$df
  for (f in c("nb.ipynb", "script.py", "a.qmd")) {
    x <- nbf_verify(p$root, f)
    expect_false(is.null(x$err), label = paste(f, "raised"))
    expect_identical(unique(x$df$file), f, label = f)
    expect_identical(x$df, nbf_only(all, f), label = f)
  }
})

test_that("notebook files verify: an ordinary .py, and a missing file, are refused", {
  v4_env()
  p <- v4_proj(NBF_PROJECT())
  nbf_check_refusal(nbf_verify(p$root, "util.py")$err, "util.py", ordinary = TRUE)
  nbf_check_refusal(nbf_verify(p$root, "gone.ipynb")$err, "gone.ipynb")
})

# ---- 2. virtual-environment and other folders Quarto skips -----------------------------------------------------

nbf_expected <- function(kinds) c("top.qmd", nbf_files(NBF_READ, kinds))

test_that("notebook folders lints: skips the folders Quarto skips, reads the others (a percent .py is linted, 5.1.8)", {
  root <- lint_proj(nbf_fixture())
  x <- nbf_lints(root)
  expect_true(all(nbf_expected(c("n.ipynb", "p.py", "b.qmd")) %in% x$file), label = "control: the folders Quarto reads are read")
  expect_setequal(unique(x$file), nbf_expected(c("n.ipynb", "p.py", "b.qmd")))
})

test_that("notebook folders checks: skips the folders Quarto skips, reads the others", {
  root <- lint_proj(nbf_fixture())
  x <- nbf_checks(root)
  expect_true(all(nbf_expected(c("n.ipynb", "p.py", "b.qmd")) %in% x$file), label = "control: the folders Quarto reads are read")
  expect_setequal(unique(x$file), nbf_expected(c("n.ipynb", "p.py", "b.qmd")))
})

test_that("notebook folders verify (static): skips the folders Quarto skips, reads the others", {
  v4_env()
  p <- v4_proj(nbf_fixture())
  x <- nbf_verify(p$root)
  expect_true(all(nbf_expected(c("n.ipynb", "p.py", "b.qmd")) %in% x$df$file), label = "control: the folders Quarto reads are read")
  expect_setequal(unique(x$df$file), nbf_expected(c("n.ipynb", "p.py", "b.qmd")))
})

test_that("notebook folders verify (static): files = names a document in a folder Quarto reads (the controls hold once files = takes .ipynb)", {
  v4_env()
  p <- v4_proj(nbf_fixture())
  # control: a document in a folder Quarto reads
  x <- nbf_verify(p$root, "myenv/n.ipynb")
  expect_identical(unique(x$df$file), "myenv/n.ipynb")
})

test_that("notebook folders gate: a guard removed from a document is reported unless it sits in a folder Quarto skips", {
  before <- function() {
    docs <- list("top.qmd" = j7_gdoc(c("n1 > 1", "n2 > 3")))
    for (d in c(NBF_SKIPPED, NBF_READ)) {
      docs[[file.path(d, "n.ipynb")]] <- nbs_ipynb(nbs_gate_cells(c("n1 > 1", "n2 > 3")))$lines
      docs[[file.path(d, "p.py")]] <- nbs_py(list(nbs_code("x = 1"), nbs_md(j7_gdoc(c("n1 > 1", "n2 > 3")))))$lines
      docs[[file.path(d, "b.qmd")]] <- j7_gdoc(c("n1 > 1", "n2 > 3"))
    }
    c(docs, list("env/pyvenv.cfg" = "home = /usr", "myenv/pyvenv.cfg" = "home = /usr",
                 "conda_env/conda-meta/history" = "# none"))
  }
  after <- function() {
    docs <- list("top.qmd" = j7_gdoc("n1 > 1"))
    for (d in c(NBF_SKIPPED, NBF_READ)) {
      docs[[file.path(d, "n.ipynb")]] <- nbs_ipynb(nbs_gate_cells("n1 > 1"))$lines
      docs[[file.path(d, "p.py")]] <- nbs_py(list(nbs_code("x = 1"), nbs_md(j7_gdoc("n1 > 1"))))$lines
      docs[[file.path(d, "b.qmd")]] <- j7_gdoc("n1 > 1")
    }
    docs
  }
  res <- g_gate(g_scenario(before(), after()))
  expect_true(all(nbf_expected(c("n.ipynb", "p.py", "b.qmd")) %in% res$checks$file), label = "control: the folders Quarto reads are read")
  expect_setequal(unique(res$checks$file), nbf_expected(c("n.ipynb", "p.py", "b.qmd")))
})

test_that("notebook folders status: a notebook only in folders Quarto skips gives no python row", {
  docs <- do.call(c, lapply(NBF_SKIPPED, function(d) setNames(list(nbf_ipynb()$lines), file.path(d, "n.ipynb"))))
  st <- nbs_status(c(list("a.qmd" = u4_qmd()), docs, list("env/pyvenv.cfg" = "home = /usr")))
  expect_false(has_python_row(st))
})

test_that("notebook folders status: a percent script only in folders Quarto skips gives no python row", {
  docs <- do.call(c, lapply(NBF_SKIPPED, function(d) setNames(list(nbf_pys()$lines), file.path(d, "p.py"))))
  st <- nbs_status(c(list("a.qmd" = u4_qmd()), docs, list("env/pyvenv.cfg" = "home = /usr")))
  expect_false(has_python_row(st))
})

test_that("notebook folders status: control, a notebook in a folder Quarto reads gives the python row", {
  for (d in NBF_READ) {
    files <- c(list("a.qmd" = u4_qmd(), "myenv/pyvenv.cfg" = "home = /usr"),
               setNames(list(nbf_ipynb()$lines), file.path(d, "n.ipynb")))
    expect_true(has_python_row(nbs_status(files)), label = d)
  }
})

test_that("notebook folders status: control, a percent script in a folder Quarto reads gives the python row", {
  for (d in NBF_READ) {
    files <- c(list("a.qmd" = u4_qmd(), "myenv/pyvenv.cfg" = "home = /usr"),
               setNames(list(nbf_pys()$lines), file.path(d, "p.py")))
    expect_true(has_python_row(nbs_status(files)), label = d)
  }
})
