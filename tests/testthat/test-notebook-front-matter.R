# Stage 3 of the project-metadata rules (dev/quarto-project-metadata.md): P7 and P6.
#   P7  notebooks and percent scripts have front matter. In an .ipynb every raw or markdown cell whose
#       source is a `---` block is a block, in cell order; in a percent .py the same for `# %% [markdown]`
#       and `# %% [raw]` cells with the leading `# ` stripped. All readers read them: R read_front_matter()
#       and the lints, the Lua config.load, Python's and Julia's chunk_claims. The F1-F3 rules hold inside
#       the notebook (later block wins per top-level key, the whole value replaced; F2 decides what is a
#       block within a cell). A notebook is always Jupyter (J8).
#   P6  the `front-matter-quarto` lint (5.8.10) also flags a later block in a .qmd whose engine is Jupyter
#       (a {python} chunk and no engine key, or `jupyter:` in the first block), not under knitr or markdown.
# Probe: the setting `weft: chunk_claims: collect` (default stop). Ids are those of the findings table in
# the document. ASCII only.

# ---- building notebooks and scripts -----------------------------------------------------------------------

.nbfm <- new.env()
withr::local_envvar(R_USER_CACHE_DIR = tempfile("nbfm-cache-"), .local_envir = testthat::teardown_env())

NB_COLLECT <- c("---", "title: t", "weft:", "  chunk_claims: collect", "---")
nb_collect_only <- c("---", "weft:", "  chunk_claims: collect", "---")

# a cell: c(type, lines...); source lines carry their own newline except the last (nbformat)
nb_cell <- function(type, lines) {
  n <- length(lines)
  src <- if (n == 0L) character() else paste0(lines, c(rep("\n", n - 1L), ""))
  base <- list(cell_type = type, metadata = structure(list(), names = character()), source = I(src))
  if (type == "code") base <- c(base, list(execution_count = NA, outputs = list()))
  base
}
nb_raw <- function(...) nb_cell("raw", c(...))
nb_md <- function(...) nb_cell("markdown", c(...))
nb_code <- function(...) nb_cell("code", c(...))

# minimal nbformat-4 JSON text for `cells`; checked to be valid JSON with the cells intact
nb_json <- function(...) {
  cells <- list(...)
  nb <- list(nbformat = 4L, nbformat_minor = 4L,
             metadata = list(kernelspec = list(name = "python3", display_name = "Python 3", language = "python")),
             cells = cells)
  txt <- as.character(jsonlite::toJSON(nb, auto_unbox = TRUE, null = "null", na = "null", pretty = FALSE))
  testthat::expect_true(jsonlite::validate(txt), label = "the notebook JSON is valid")
  back <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  testthat::expect_identical(length(back$cells), length(cells), label = "the notebook keeps its cells")
  txt
}

# a percent script from cells: each is c(header, body lines); the body of a markdown or raw cell is
# commented with `# `
py_cell <- function(kind, ...) {
  body <- c(...)
  if (kind == "code") return(c("# %%", body, ""))
  c(paste0("# %% [", kind, "]"), if (length(body)) ifelse(nzchar(body), paste0("# ", body), "#"), "")
}

nb_write <- function(dir, name, text) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, name)
  con <- file(path, "wb")
  writeBin(charToRaw(enc2utf8(paste0(paste(text, collapse = "\n"), "\n"))), con)
  close(con)
  normalizePath(path, winslash = "/")
}

# the cases: id, file name, text of the file, and want (the chunk_claims the reader should give)
nb_cases <- function() {
  prose <- nb_md("# A notebook", "", "Some prose.")
  c1 <- nb_code("x = 1")
  list(
    list(id = "J1", file = "doc.ipynb", want = "collect",
         text = nb_json(nb_raw(NB_COLLECT), prose, c1)),
    list(id = "J2", file = "doc.ipynb", want = "collect",
         text = nb_json(nb_md(NB_COLLECT, "", "# Heading"), c1)),
    list(id = "J3", file = "doc.ipynb", want = "collect",
         text = nb_json(nb_raw("---", "weft:", "  chunk_claims: stop", "---"), prose, c1,
                        nb_raw("---", "weft:", "  chunk_claims: collect", "---"))),
    list(id = "J3 whole weft replaced", file = "doc.ipynb", want = "stop",
         text = nb_json(nb_raw("---", "weft:", "  chunk_claims: collect", "---"), c1,
                        nb_raw("---", "weft:", "  digits: 3", "---"))),
    list(id = "J4", file = "doc.ipynb", want = "collect",
         text = nb_json(prose, c1, nb_md("More prose."), nb_raw(nb_collect_only))),
    list(id = "J4 a markdown block later too", file = "doc.ipynb", want = "collect",
         text = nb_json(prose, c1, nb_md(nb_collect_only))),
    list(id = "F2 text above the --- in a markdown cell", file = "doc.ipynb", want = "stop",
         text = nb_json(nb_md("Intro words.", nb_collect_only), c1)),
    list(id = "F2 a --- rule in prose, then a blank line", file = "doc.ipynb", want = "stop",
         text = nb_json(nb_md("Intro.", "", "---", "", "weft:", "  chunk_claims: collect"), c1)),
    list(id = "J1 control: a code cell holding a block is not a block", file = "doc.ipynb", want = "stop",
         text = nb_json(prose, nb_code(nb_collect_only))),
    list(id = "J1 control: a notebook with no block", file = "doc.ipynb", want = "stop",
         text = nb_json(prose, c1)),
    list(id = "J5", file = "doc.py", want = "collect",
         text = c(py_cell("markdown", NB_COLLECT), py_cell("code", "x = 1"))),
    list(id = "J6", file = "doc.py", want = "collect",
         text = c(py_cell("raw", NB_COLLECT), py_cell("code", "x = 1"))),
    list(id = "K4", file = "doc.py", want = "collect",
         text = c(py_cell("code", "x = 1"), py_cell("markdown", "Prose."), py_cell("raw", nb_collect_only))),
    list(id = "J3 (py) later cell wins", file = "doc.py", want = "collect",
         text = c(py_cell("raw", "---", "weft:", "  chunk_claims: stop", "---"), py_cell("code", "x = 1"),
                  py_cell("markdown", nb_collect_only))),
    list(id = "J3 (py) whole weft replaced", file = "doc.py", want = "stop",
         text = c(py_cell("raw", "---", "weft:", "  chunk_claims: collect", "---"),
                  py_cell("markdown", "---", "weft:", "  digits: 3", "---"))),
    list(id = "F2 (py) text above the --- in a markdown cell", file = "doc.py", want = "stop",
         text = c(py_cell("markdown", "Intro words.", nb_collect_only))),
    list(id = "J5 control: a code cell with a commented block is not a block", file = "doc.py", want = "stop",
         text = c(py_cell("code", paste0("# ", NB_COLLECT), "x = 1"))),
    list(id = "J7", file = "doc.py", want = "stop",
         text = c(py_cell("code", "x = 1"), py_cell("code", "y = 2")))
  )
}

# every case written under one temporary folder, each in its own folder; memoised
nb_dirs <- function() {
  if (!is.null(.nbfm$cases)) return(.nbfm$cases)
  base <- normalizePath(tempfile("nbfm-"), winslash = "/", mustWork = FALSE)
  dir.create(base, recursive = TRUE)
  withr::defer(unlink(base, recursive = TRUE), envir = testthat::teardown_env())
  cs <- nb_cases()
  for (i in seq_along(cs)) {
    d <- file.path(base, sprintf("c%02d", i))
    cs[[i]]$dir <- d
    cs[[i]]$path <- nb_write(d, cs[[i]]$file, cs[[i]]$text)
  }
  .nbfm$cases <- cs
  cs
}
nb_case <- function(id) {
  cs <- nb_dirs()
  hit <- Filter(function(c) identical(c$id, id), cs)
  testthat::expect_length(hit, 1L)
  hit[[1]]
}
nb_case_ids <- function() vapply(nb_cases(), function(c) c$id, character(1))

# ---- R: read_front_matter() and read_config() -----------------------------------------------------------

test_that("P7 (R): the case notebooks and scripts are valid and written", {
  for (c in nb_dirs()) {
    expect_true(file.exists(c$path), label = c$id)
    if (c$file == "doc.ipynb") expect_true(jsonlite::validate(paste(readLines(c$path, warn = FALSE), collapse = "\n")),
                                           label = c$id)
  }
})

nb_r_front <- function(path) suppressWarnings(weft:::read_front_matter(path))
nb_r_claims <- function(c) {
  fm <- nb_r_front(c$path)
  suppressWarnings(weft:::read_config(c$dir, front = fm$weft, doc = c$path))$chunk_claims
}

for (id in nb_case_ids()) local({
  id <- id
  test_that(sprintf("P7 %s (R read_front_matter, read_config): chunk_claims is as the cells say", id), {
    withr::local_envvar(WEFT_DRAFT = NA)
    c <- nb_case(id)
    fm <- nb_r_front(c$path)
    if (c$want == "collect") expect_identical(fm$weft$chunk_claims, "collect", label = "front matter weft$chunk_claims")
    else expect_null(fm$weft$chunk_claims, label = "front matter weft$chunk_claims")
    expect_identical(nb_r_claims(c), c$want, label = "read_config()$chunk_claims")
  })
})

test_that("P7 J3 (R): a later raw cell replaces per top-level key; other keys of the first block stay", {
  c <- nb_dirs()[[1]]
  d <- file.path(dirname(c$dir), "j3-keys")
  p <- nb_write(d, "doc.ipynb", nb_json(
    nb_raw("---", "title: t", "lang: de", "weft:", "  chunk_claims: stop", "  digits: 2", "---"),
    nb_code("x = 1"),
    nb_raw("---", "weft:", "  chunk_claims: collect", "---")))
  fm <- nb_r_front(p)
  expect_identical(fm$lang, "de")
  expect_identical(fm$title, "t")
  expect_identical(fm$weft, list(chunk_claims = "collect"))
})

test_that("P7 J1 (R): the blocks of a notebook come in cell order, first raw cell included", {
  c <- nb_dirs()[[1]]
  d <- file.path(dirname(c$dir), "j1-order")
  p <- nb_write(d, "doc.ipynb", nb_json(
    nb_raw("---", "lang: fr", "---"), nb_md("---", "lang: de", "---")))
  expect_identical(nb_r_front(p)$lang, "de")
})

test_that("P7 J7 (R): a script with only code cells has no front matter and no error", {
  c <- nb_case("J7")
  expect_no_error(fm <- nb_r_front(c$path))
  expect_length(fm$weft, 0L)
  expect_length(fm$lang, 0L)
})

# ---- R lints read the notebook's front matter --------------------------------------------------------------

NB_ROSE <- "All 3 sites rose."
nb_cw <- function(text, env = parent.frame()) {
  lf_by_rule(lint_fixture(list("doc.ipynb" = text), rules = "claim-word", env = env), "claim-word")
}

test_that("P7 J1 (lints) control: the claim-word lint reads the prose of a notebook with no front matter", {
  x <- nb_cw(nb_json(nb_md(NB_ROSE), nb_code("x = 1")))
  expect_identical(x$text, "all, rose")
})

test_that("P7 J1 (lints): lang: de in the first raw cell is honoured by the claim-word lint", {
  expect_identical(nb_cw(nb_json(nb_raw("---", "lang: en", "---"), nb_md(NB_ROSE)))$text, "all, rose",
                   label = "non-vacuous: the same notebook under lang en is scanned")
  x <- nb_cw(nb_json(nb_raw("---", "lang: de", "---"), nb_md(NB_ROSE)))
  expect_identical(nrow(x), 0L)
})

test_that("P7 J2 (lints): lang: de in the first markdown cell is honoured", {
  expect_identical(nb_cw(nb_json(nb_md("---", "lang: en", "---"), nb_md(NB_ROSE)))$text, "all, rose",
                   label = "non-vacuous: the same notebook under lang en is scanned")
  x <- nb_cw(nb_json(nb_md("---", "lang: de", "---"), nb_md(NB_ROSE)))
  expect_identical(nrow(x), 0L)
})

test_that("P7 J3 (lints): a later raw cell wins over the first (lang en over lang de)", {
  x <- nb_cw(nb_json(nb_raw("---", "lang: de", "---"), nb_md(NB_ROSE), nb_raw("---", "lang: en", "---")))
  expect_identical(x$text, "all, rose")
  x <- nb_cw(nb_json(nb_raw("---", "lang: en", "---"), nb_md(NB_ROSE), nb_raw("---", "lang: de", "---")))
  expect_identical(nrow(x), 0L)
})

test_that("P7 J4 (lints): a raw front-matter cell that is not the first cell counts", {
  expect_identical(nb_cw(nb_json(nb_md(NB_ROSE), nb_code("x = 1"), nb_raw("---", "lang: en", "---")))$text,
                   "all, rose", label = "non-vacuous: the same notebook under lang en is scanned")
  x <- nb_cw(nb_json(nb_md(NB_ROSE), nb_code("x = 1"), nb_raw("---", "lang: de", "---")))
  expect_identical(nrow(x), 0L)
})

test_that("P7 F2 (lints): a markdown cell with text above a --- block is not front matter", {
  x <- nb_cw(nb_json(nb_md("Intro words.", "---", "lang: de", "---"), nb_md(NB_ROSE)))
  expect_identical(x$text, "all, rose")
})

# ---- J8: a notebook is always Jupyter ---------------------------------------------------------------------

FR_NB_RVAL <- "The depth is `r x`{.num} metres."
nb_engine <- function(text, env = parent.frame()) {
  lint_fixture(list("a.ipynb" = text), rules = "engine", tier = 1:2, env = env)
}

test_that("P7 J8 (engine lint): engine: markdown in a notebook is ignored; the notebook is Jupyter", {
  with_key <- nb_engine(nb_json(nb_raw("---", "engine: markdown", "---"), nb_md(FR_NB_RVAL)))
  expect_identical(nrow(with_key), 1L, label = "one engine finding for the notebook")
  expect_no_match(with_key$message, "engine: markdown", fixed = TRUE)
  none <- nb_engine(nb_json(nb_md(FR_NB_RVAL)))
  expect_identical(with_key$message, none$message, label = "the key changes nothing")
})

test_that("P7 J8 (engine lint): engine: knitr in a notebook's raw cell does not make it a knitr document", {
  x <- nb_engine(nb_json(nb_raw("---", "engine: knitr", "---"), nb_md(FR_NB_RVAL)))
  expect_identical(nrow(x), 1L, label = "a notebook with weft constructs is still a finding")
})

# ---- Lua: config.load -------------------------------------------------------------------------------------

NB_LUA <- '
local lib = arg[1]
local config = dofile(lib .. "/config.lua")
for i = 2, #arg do
  local path = arg[i]
  local dir = path:match("^(.*)/[^/]*$")
  local name = path:match("([^/]*)$")
  local f = io.open(path, "rb")
  local text = f and f:read("a") or nil
  if f then f:close() end
  local ok, cfg, problems = pcall(config.load, name, text, dir)
  if ok then
    io.write(pandoc.json.encode({ ok = true, chunk_claims = cfg.chunk_claims, nproblems = #problems }), "\\n")
  else
    io.write(pandoc.json.encode({ ok = false, err = tostring(cfg) }), "\\n")
  end
end
'

nb_lua_all <- function() {
  if (!is.null(.nbfm$lua)) return(.nbfm$lua)
  cs <- nb_dirs()
  script <- file.path(dirname(cs[[1]]$dir), "driver.lua")
  writeLines(NB_LUA, script)
  res <- lua_run(script, c(dirname(lua_num_path()), vapply(cs, function(c) c$path, character(1))))
  lines <- strsplit(res$stdout, "\n", fixed = TRUE)[[1]]
  testthat::expect_identical(length(lines), length(cs), label = paste("one Lua line per case;", res$stderr))
  out <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  names(out) <- vapply(cs, function(c) c$id, character(1))[seq_along(out)]
  .nbfm$lua <- out
  out
}

for (id in nb_case_ids()) local({
  id <- id
  test_that(sprintf("P7 %s (Lua config.load): chunk_claims is as the cells say", id), {
    skip_if_no_lua_pandoc()
    c <- nb_case(id)
    x <- nb_lua_all()[[id]]
    expect_false(is.null(x), label = "the driver reported this case")
    expect_true(isTRUE(x$ok), label = paste("config.load did not error:", x$err))
    expect_identical(x$chunk_claims, c$want)
  })
})

# ---- Python: weft._config.chunk_claims(source, folder) ----------------------------------------------------

nb_py_all <- function() {
  if (!is.null(.nbfm$py)) return(.nbfm$py)
  cs <- nb_dirs()
  spec <- file.path(dirname(cs[[1]]$dir), "spec.json")
  writeLines(jsonlite::toJSON(list(source = vapply(cs, function(c) c$path, character(1)),
                                   folder = vapply(cs, function(c) c$dir, character(1))), auto_unbox = FALSE), spec)
  code <- paste(
    "import json",
    "from weft import _config",
    sprintf("s = json.load(open('%s'))", spec),
    "for src, folder in zip(s['source'], s['folder']):",
    "    try:",
    "        print(_config.chunk_claims(src, folder))",
    "    except Exception as e:",
    "        print('ERROR ' + type(e).__name__ + ': ' + str(e).replace(chr(10), ' '))",
    sep = "\n")
  x <- py_plain(code)
  testthat::expect_identical(x$status, 0L, label = x$stderr)
  out <- strsplit(x$stdout, "\n", fixed = TRUE)[[1]]
  names(out) <- vapply(cs, function(c) c$id, character(1))[seq_along(out)]
  .nbfm$py <- out
  out
}

for (id in nb_case_ids()) local({
  id <- id
  test_that(sprintf("P7 %s (Python chunk_claims): as the cells say", id), {
    skip_if_no_jupyter()
    expect_identical(unname(nb_py_all()[id]), nb_case(id)$want)
  })
})

# ---- Julia: Weft.chunk_claims_setting(source, folder) -----------------------------------------------------

nb_jl_all <- function() {
  if (!is.null(.nbfm$jl)) return(.nbfm$jl)
  cs <- nb_dirs()
  q <- function(x) paste0("\"", x, "\"")
  code <- c("using Weft",
            sprintf("for (src, folder) in [%s]",
                    paste(sprintf("(%s, %s)", q(vapply(cs, function(c) c$path, character(1))),
                                  q(vapply(cs, function(c) c$dir, character(1)))), collapse = ", ")),
            "    try",
            "        println(Weft.chunk_claims_setting(src, folder))",
            "    catch e",
            "        println(\"ERROR \", replace(sprint(showerror, e), '\\n' => ' '))",
            "    end",
            "end")
  r <- jle_cases(paste(code, collapse = "\n"))[[1]]
  testthat::expect_identical(r$emsg, "", label = "the Julia reader ran")
  out <- strsplit(sub("\n$", "", r$out), "\n", fixed = TRUE)[[1]]
  names(out) <- vapply(cs, function(c) c$id, character(1))[seq_along(out)]
  .nbfm$jl <- out
  out
}

for (id in nb_case_ids()) local({
  id <- id
  test_that(sprintf("P7 %s (Julia chunk_claims_setting): as the cells say", id), {
    skip_if_julia_disabled()
    expect_identical(unname(nb_jl_all()[id]), nb_case(id)$want)
  })
})

# ---- P6: front-matter-quarto flags a later block under the Jupyter engine ------------------------------------

p6 <- function(lines, ext = "qmd", env = parent.frame()) {
  lf_by_rule(lint_one(lines, ext = ext, env = env), "front-matter-quarto")
}
P6_PY <- c("```{python}", "x = 1", "```")
P6_R <- c("```{r}", "x <- 1", "```")
# a document: first block (`...`), a body, then a later block after a blank line; returns the lines and the
# line of the later block's opening ---
nb_block <- function(...) c("---", c(...), "---")
p6_doc <- function(first = character(), body = P6_PY, later = "lang: fr") {
  head <- c("---", "title: T", first, "---", "", body, "", "Middle text.", "")
  list(lines = c(head, nb_block(later), "", "More text."), line = length(head) + 1L)
}

test_that("P6: a later block in a qmd with a python chunk and no engine key is a finding", {
  d <- p6_doc()
  x <- p6(d$lines)
  expect_identical(nrow(x), 1L)
  expect_identical(x$line, d$line)
  expect_identical(x$spec, "5.8.10")
})

test_that("P6: a later block under `jupyter:` in the first block is a finding, with no chunks at all", {
  d <- p6_doc("jupyter: python3", body = "Words.")
  x <- p6(d$lines)
  expect_identical(nrow(x), 1L)
  expect_identical(x$line, d$line)
})

test_that("P6: a later block under `engine: jupyter` in the first block is a finding", {
  d <- p6_doc("engine: jupyter", body = "Words.")
  expect_identical(nrow(p6(d$lines)), 1L)
})

test_that("P6: every later block is a finding (two later blocks, two findings)", {
  d <- p6_doc()
  x <- p6(c(d$lines, "", nb_block("title: Again")))
  expect_identical(nrow(x), 2L)
  expect_identical(x$line[[1]], d$line)
})

test_that("P6: a later block closed with `...` under Jupyter is a finding", {
  d <- p6_doc()
  lines <- d$lines
  lines[d$line + 2L] <- "..."
  expect_identical(nrow(p6(lines)), 1L)
})

test_that("P6: `engine: knitr` only in a later block does not stop the Jupyter reading (F6)", {
  d <- p6_doc(later = "engine: knitr")
  expect_identical(nrow(p6(d$lines)), 1L)
})

test_that("P6 control: the same document under engine: knitr has no finding", {
  d <- p6_doc("engine: knitr")
  expect_identical(nrow(p6(d$lines)), 0L)
})

test_that("P6 control: the same document under engine: markdown has no finding", {
  d <- p6_doc("engine: markdown")
  expect_identical(nrow(p6(d$lines)), 0L)
})

test_that("P6 control: a knitr: key in the first block has no finding", {
  d <- p6_doc(c("knitr:", "  opts_chunk:", "    echo: false"))
  expect_identical(nrow(p6(d$lines)), 0L)
})

test_that("P6 control: an R chunk and no engine key is knitr: no finding", {
  d <- p6_doc(body = P6_R)
  expect_identical(nrow(p6(d$lines)), 0L)
})

test_that("P6 control: no chunks and no engine key is the markdown engine: no finding", {
  d <- p6_doc(body = "Words.")
  expect_identical(nrow(p6(d$lines)), 0L)
})

test_that("P6 control: a Jupyter qmd with only its first block has no finding", {
  x <- p6(c("---", "title: T", "jupyter: python3", "---", "", P6_PY, "", "Text."))
  expect_identical(nrow(x), 0L)
})

test_that("P6 control: a --- inside a backtick fence or a setext heading in a Jupyter qmd is no finding", {
  fence <- c("---", "title: T", "---", "", P6_PY, "", "```", "---", "lang: fr", "---", "```", "", "End.")
  expect_identical(nrow(p6(fence)), 0L)
  setext <- c("---", "title: T", "---", "", P6_PY, "", "A heading", "---", "", "Paragraph.")
  expect_identical(nrow(p6(setext)), 0L)
})
