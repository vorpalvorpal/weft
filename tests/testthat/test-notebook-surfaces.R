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
  new <- nbs_ipynb(list(nbs_md("Prose.", NBS_BAD, "", "More.", "A [a site]{n=\"j\" if=\"y\"} here.")))
  p <- v4_proj(list("nb.ipynb" = old$lines), git = TRUE)
  base <- g_head(p$top)
  g_write(p$top, "nb.ipynb", new$lines)
  g_add(p$top)
  g_commit(p$top, "second")
  r <- v4_verify(p$root, since = base, static = TRUE)
  a <- as.data.frame(unclass(r$res$added), stringsAsFactors = FALSE)
  expect_identical(a$file, "nb.ipynb")
  expect_identical(a$line, new$at(1L, 5L))
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
