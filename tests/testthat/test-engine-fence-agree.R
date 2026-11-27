# Follow-ups to A18 (commit 9fec4f1; ruling in dev/decisions.md, "Smaller rulings while building (2026-11-27)",
# amended paragraph; the finders' tests are test-fences-one.R). Five groups; the tables are in
# helper-engine-fence-agree.R. ASCII only.
#
# G1  The other readers' metadata-block finders must find the blocks R's metadata_blocks() finds (R1 to R5 of
#     test-fences-one.R: backtick in an info string, indent of at most 3, closers, `>` quotes, comments,
#     unclosed fences). Oracle: R's own reader, as it is now (read_front_matter() and metadata_blocks()). One table
#     (EFA_MB_CASES) is run through R, the Lua filter's config.load() (its metadata_blocks()), Python's
#     weft._config.chunk_claims() (its _blocks()) and Julia's Weft.chunk_claims_setting(). The probe in every case
#     is a block that sets `weft: chunk_claims: collect`: a reader that finds it as a block gives "collect", one
#     that sees it inside a fence, or not at all, gives the default "stop". Patterns after
#     test-include-front-matter.R and test-notebook-front-matter.R.
# G1b An unclosed plain fence is no fence to Pandoc's markdown reader: its text is prose. Oracle: `pandoc -f markdown
#     -t json` (the cases of G1 that are unclosed, checked in the test below); chunks still run to the end (knitr).
# G2  Which chunk headers choose Quarto's knitr engine, and which knitr runs. Two views, two oracles:
#       the engine Quarto picks: `quarto inspect` on a real file (Quarto 1.11.9; the language regex of
#         languagesWithClasses() in src/core/jupyter/... is `^[\t >]*```+\s*\{([a-zA-Z][a-zA-Z0-9_.]*)([^}]*)?\}\s*$`,
#         lower-cased, so `{R}` is r, `{ r }` is no chunk, and `{r-x}` and `{r=1}` are r; an `{r.x}` is the language
#         "r.x", which no engine claims, so it is Jupyter; an unclosed chunk with code is not seen at all);
#       what knitr runs: knitr 1.51 (chunk.begin `^[\t >]*```+\s*\{([a-zA-Z0-9_]+( *[ ,].*)?)\}\s*$`), checked by
#         knitting each header. `{R}` runs, `{ r }` does not, `{r-x}` and `{r=1}` do not.
#     Quarto's reading decides the engine (filter_resolves(), quarto_engine(), the Lua source_is_knitr());
#     knitr's decides what runs (find_chunks()). The conformance grammar table's row for `{ r }` says knitr; Quarto
#     says markdown (see the last test of the group).
# G3  Plain fences inside list items (the indent is measured from the item's content column; 4 or more past it is
#     indented code). Oracle: `quarto pandoc -f markdown -t json` on each document (the verdict is checked inside
#     the test as a control). Ruling 27 Nov (1cb2897): plain fences follow Pandoc's markdown reader, not CommonMark,
#     so a fence with no blank line before it, at indent 4 in a list item, is no fence, and an empty list item has
#     content column 2.
# G4  The last line of an unclosed chunk is a code line. The lint rules that read a chunk's code lines (design-3.md
#     L34, L35, L26: chunk-label, figure, table-caption, anchor-unused, xref, dict-assign, dict-key, tar-cache).
#     Oracle: knitr, which reads `#| label: x` on the last line of an unclosed chunk as the label.
# G5  A truthy `knitr:` key beats `engine: jupyter`, `jupyter:` and `engine: markdown`. Oracle: `quarto inspect`
#     on a real file, and markdownExecutionEngine() in src/execute/engine.ts (read from the bundled quarto.js):
#     it loops over the engines in order (knitr, jupyter, markdown) and takes the first whose key
#     (`yaml[engine.name]`) is truthy or whose `engine:` / `execute: engine:` names it. The julia engine is ahead of
#     knitr, so `engine: julia` keeps its engine against a `knitr:` key. weft's Python and Julia readers expose no
#     engine function, so only R and Lua are tested.

# ---- G1 ---------------------------------------------------------------------------------------------------

efa_names <- vapply(EFA_MB_CASES, `[[`, "", "name")
efa_wants <- vapply(EFA_MB_CASES, `[[`, "", "want")

test_that("G1 (R): the oracle itself: read_front_matter() and metadata_blocks() give each case's answer", {
  dirs <- efa_write(EFA_MB_CASES)
  for (i in seq_along(EFA_MB_CASES)) {
    expect_identical(efa_r_claims(dirs[[i]]), efa_wants[[i]], label = efa_names[[i]])
    n <- nrow(as.data.frame(weft:::metadata_blocks(EFA_MB_CASES[[i]]$lines)))
    expect_identical(n, if (efa_wants[[i]] == "collect") 1L else 0L, label = paste("blocks:", efa_names[[i]]))
  }
})

test_that("G1 (oracle): Pandoc reads the probe as a metadata block exactly where the table says collect", {
  efa_skip_if_no_quarto()
  # Chunks are knitr's, not Pandoc's, so only the cases with no `{r}` header are checked here. One plain case is left
  # out: Pandoc's markdown reader reads a fence only when its info string is one word or an attribute block, so
  # "~~~ a`b" is no fence to it (it reads prose, so the probe below it would be a block), where CommonMark and the
  # R1 ruling say a tilde fence's info may hold a backtick. Reported to the coordinator, not yet ruled.
  for (cs in EFA_MB_CASES) {
    if (any(grepl("^[ >]*(```|~~~)+ ?\\{", cs$lines)) || cs$name == "R1-tilde-info-backtick-is-a-fence") next
    expect_identical(efa_pandoc_has_meta(cs$lines, "weft"), cs$want == "collect", label = cs$name)
  }
})

test_that("G1b (oracle): Pandoc reads an unclosed plain fence as prose, not as a fence", {
  efa_skip_if_no_quarto()
  for (l in list(c("```text", "x"), c("~~~", "x"), c("```", "> ```", "x"), c("> ```", "> x", "", "para"), c("```", "x", "", "para"))) {
    expect_identical(efa_pandoc_verdict(l), "none", label = paste(l, collapse = " / "))
  }
})

test_that("G1 (Lua): config.load() finds the blocks R finds", {
  skip_if_no_lua_pandoc()
  dirs <- efa_write(EFA_MB_CASES)
  got <- efa_lua_claims(dirs)
  if (is.null(got)) return(invisible())
  for (i in seq_along(EFA_MB_CASES)) expect_identical(got[[i]], efa_wants[[i]], label = efa_names[[i]])
})

test_that("G1 (Python): weft._config.chunk_claims() finds the blocks R finds", {
  skip_if_no_jupyter()
  dirs <- efa_write(EFA_MB_CASES)
  got <- efa_py_claims(dirs)
  if (is.null(got)) return(invisible())
  for (i in seq_along(EFA_MB_CASES)) expect_identical(got[[i]], efa_wants[[i]], label = efa_names[[i]])
})

test_that("G1 (Julia): Weft.chunk_claims_setting() finds the blocks R finds", {
  skip_if_julia_disabled()
  dirs <- efa_write(EFA_MB_CASES)
  got <- efa_jl_claims(dirs)
  if (is.null(got)) return(invisible())
  for (i in seq_along(EFA_MB_CASES)) expect_identical(got[[i]], efa_wants[[i]], label = efa_names[[i]])
})

# ---- G2 ---------------------------------------------------------------------------------------------------

efa_all_hdr <- c(EFA_HDR_CASES, EFA_UNCLOSED_CASES)

test_that("G2 (oracles): Quarto picks the engine the table says, by `quarto inspect`", {
  efa_skip_if_no_quarto()
  for (cs in efa_all_hdr) expect_identical(efa_quarto_engine(cs$lines), cs$quarto, label = cs$name)
})

test_that("G2 (oracles): knitr's own chunk pattern accepts the headers the table says it runs", {
  skip_if_not_installed("knitr")
  pat <- knitr::all_patterns$md$chunk.begin
  for (cs in efa_all_hdr) {
    expect_identical(any(grepl(pat, cs$lines)), cs$knitr_runs, label = cs$name)
  }
})

test_that("G2 (R): quarto_engine() gives the engine Quarto picks", {
  for (cs in efa_all_hdr) expect_identical(weft:::quarto_engine(cs$lines), cs$quarto, label = cs$name)
})

test_that("G2 (R): filter_resolves() is FALSE exactly when Quarto picks knitr (no eval = FALSE here)", {
  for (cs in efa_all_hdr) {
    expect_identical(weft:::filter_resolves(cs$lines, "a.qmd"), cs$quarto != "knitr", label = cs$name)
  }
})

EFA_LUA_KNITR <- '
local lib = arg[1]
local config = dofile(lib .. "/config.lua")
for i = 2, #arg do
  local dir = arg[i]
  local f = io.open(dir .. "/doc.qmd", "rb")
  local text = f and f:read("a") or ""
  if f then f:close() end
  local ok, r = pcall(config.source_is_knitr, dir .. "/doc.qmd", text)
  io.write((not ok) and "error" or (r and "knitr" or "filter"), "\\n")
end
'

efa_lua_is_knitr <- function(cases) {
  dirs <- efa_write(cases, env = parent.frame())
  script <- file.path(dirname(dirs[[1]]), "driver-knitr.lua")
  writeLines(EFA_LUA_KNITR, script)
  lib <- file.path(dirname(filter_path("weft.lua")), "weftlib")
  res <- lua_run(script, c(lib, unname(dirs)))
  got <- strsplit(res$stdout, "\n", fixed = TRUE)[[1]]
  expect_identical(length(got), length(cases), label = paste("one Lua line per case;", res$stderr))
  if (length(got) != length(cases)) return(NULL)
  got
}

test_that("G2 (Lua): config.source_is_knitr() says knitr exactly when Quarto picks knitr", {
  skip_if_no_lua_pandoc()
  got <- efa_lua_is_knitr(efa_all_hdr)
  if (is.null(got)) return(invisible())
  for (i in seq_along(efa_all_hdr)) {
    expect_identical(got[[i]], if (efa_all_hdr[[i]]$quarto == "knitr") "knitr" else "filter", label = efa_all_hdr[[i]]$name)
  }
})

test_that("G2 (knitr's view): find_chunks() finds a chunk exactly where knitr's pattern runs one", {
  for (cs in efa_all_hdr) {
    expect_identical(length(weft:::find_chunks(cs$lines)) > 0L, cs$knitr_runs, label = cs$name)
  }
})

test_that("G2 (grammar table): the doc rows for `{R}` and `{ r }` carry Quarto's verdict", {
  efa_skip_if_no_quarto()
  d <- f6_read("grammar")
  d <- d[d$kind == "doc", , drop = FALSE]
  d$text <- gsub("%0A", "\n", d$text, fixed = TRUE)
  d$text <- f6_unesc(d$text)
  for (hdr in c("```{R}", "```{ r }")) {
    row <- d[startsWith(d$text, paste0(hdr, "\n")), , drop = FALSE]
    expect_identical(nrow(row), 1L, label = paste("one table row for", hdr))
    if (nrow(row) != 1L) next
    q <- efa_quarto_engine(strsplit(row$text, "\n", fixed = TRUE)[[1]])
    expect_identical(row$verdict, if (identical(q, "knitr")) "knitr" else "filter",
                     label = paste(hdr, "- Quarto picks", q))
  }
})

# ---- G3 ---------------------------------------------------------------------------------------------------

efa_fence_close <- function(lines) {
  open <- which(grepl("^ *(```|~~~)", lines))[[1]]
  r <- as.data.frame(weft:::fence_blocks(lines, rep(FALSE, length(lines))))
  r <- r[r$open == open, , drop = FALSE]
  if (nrow(r) == 0L) NA_integer_ else as.integer(r$close[[1]])
}

test_that("G3 (oracle): Pandoc reads each case as the table says", {
  efa_skip_if_no_quarto()
  for (cs in EFA_LIST_CASES) {
    expect_identical(efa_pandoc_verdict(cs$lines), cs$want, label = cs$name)
  }
})

test_that("G3 (R): fence_blocks() finds a fence in a list item where Pandoc markdown does, and none where it is code or prose", {
  for (cs in EFA_LIST_CASES) {
    got <- efa_fence_close(cs$lines)
    if (cs$want == "fence") {
      expect_identical(got, length(cs$lines), label = cs$name)
    } else {
      expect_true(is.na(got), label = cs$name)
    }
  }
})

test_that("G3 (R): a block inside a list item's fence is no front matter, a block after it is", {
  # the fence is closed inside the item, so the probe after the list is a block either way; this pins the close
  l <- c("- item", "", efa_fence_at(4), "", "para", "", EFA_PROBE)
  r <- as.data.frame(weft:::metadata_blocks(l))
  expect_identical(nrow(r), 1L)
  expect_identical(as.integer(r$open), 9L)
})

# ---- G4 ---------------------------------------------------------------------------------------------------

efa_found <- function(lines, rules) {
  r <- as.data.frame(unclass(lint_one(lines)), stringsAsFactors = FALSE)
  r <- r[r$rule %in% rules, , drop = FALSE]
  if (nrow(r) == 0L) character() else paste0(r$rule, "@", r$line)
}

test_that("G4 (oracle): knitr reads a `#| label:` on the last line of an unclosed chunk as the label", {
  skip_if_not_installed("knitr")
  old <- knitr::knit_hooks$get()
  withr::defer(knitr::knit_hooks$restore(old))
  knitr::knit_hooks$set(chunk = function(x, options) paste0("LABEL=", options$label, "\n"))
  run <- function(txt) paste(suppressMessages(knitr::knit(text = txt, quiet = TRUE)), collapse = "")
  expect_match(run("```{r}\n#| label: x\n"), "LABEL=x", fixed = TRUE)
  expect_match(run("```{r}\n#| echo: false\n#| label: x"), "LABEL=x", fixed = TRUE)
  expect_match(run("```{r}\n#| label: x\n```\n"), "LABEL=x", fixed = TRUE)
})

test_that("G4 (R lints): the last line of an unclosed chunk is read by every rule that reads a chunk's code", {
  for (cs in EFA_LAST_CASES) {
    expect_identical(efa_found(cs$lines, cs$rules), cs$want, label = cs$name)
  }
})

test_that("G4 (R lints): an unclosed chunk gives the findings of the same chunk closed on a later line", {
  for (cs in EFA_LAST_CASES) {
    expect_identical(efa_found(cs$lines, cs$rules), efa_found(c(cs$lines, "```"), cs$rules), label = cs$name)
  }
})

# ---- G5 ---------------------------------------------------------------------------------------------------

test_that("G5 (oracle): Quarto picks the engine the table says, by `quarto inspect`", {
  efa_skip_if_no_quarto()
  for (cs in EFA_ENGINE_CASES) expect_identical(efa_quarto_engine(cs$lines), cs$quarto, label = cs$name)
})

test_that("G5 (R): quarto_engine() gives the engine Quarto picks, a knitr: key included", {
  for (cs in EFA_ENGINE_CASES) expect_identical(weft:::quarto_engine(cs$lines), cs$quarto, label = cs$name)
})

test_that("G5 (R): filter_resolves() is FALSE exactly when Quarto picks knitr", {
  for (cs in EFA_ENGINE_CASES) {
    expect_identical(weft:::filter_resolves(cs$lines, "a.qmd"), cs$quarto != "knitr", label = cs$name)
  }
})

test_that("G5 (Lua): config.source_is_knitr() says knitr exactly when Quarto picks knitr", {
  skip_if_no_lua_pandoc()
  got <- efa_lua_is_knitr(EFA_ENGINE_CASES)
  if (is.null(got)) return(invisible())
  for (i in seq_along(EFA_ENGINE_CASES)) {
    expect_identical(got[[i]], if (EFA_ENGINE_CASES[[i]]$quarto == "knitr") "knitr" else "filter",
                     label = EFA_ENGINE_CASES[[i]]$name)
  }
})

# a project's engines: list (Quarto 1.11.9 `quarto inspect`): the same order, with the project's engines first
test_that("G5 (projects, oracle): Quarto picks the engine the table says when the project lists engines", {
  efa_skip_if_no_quarto()
  dirs <- efa_project_write(EFA_PROJECT_CASES)
  for (i in seq_along(EFA_PROJECT_CASES)) {
    out <- suppressWarnings(system2("quarto", c("inspect", shQuote(file.path(dirs[[i]], "doc.qmd"))), stdout = TRUE, stderr = FALSE))
    j <- jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
    expect_identical(j$engines[[1]], EFA_PROJECT_CASES[[i]]$want, label = EFA_PROJECT_CASES[[i]]$name)
  }
})

test_that("G5 (projects, R): quarto_engine(lines, file) follows the project's engines: list", {
  dirs <- efa_project_write(EFA_PROJECT_CASES)
  for (i in seq_along(EFA_PROJECT_CASES)) {
    f <- file.path(dirs[[i]], "doc.qmd")
    expect_identical(weft:::quarto_engine(readLines(f), f), EFA_PROJECT_CASES[[i]]$want, label = EFA_PROJECT_CASES[[i]]$name)
  }
})

test_that("G5 (projects, Lua): config.source_is_knitr() follows the project's engines: list", {
  skip_if_no_lua_pandoc()
  dirs <- efa_project_write(EFA_PROJECT_CASES)
  script <- file.path(dirname(dirs[[1]]), "driver-knitr.lua")
  writeLines(EFA_LUA_KNITR, script)
  res <- lua_run(script, c(file.path(dirname(filter_path("weft.lua")), "weftlib"), unname(dirs)))
  got <- strsplit(res$stdout, "\n", fixed = TRUE)[[1]]
  expect_identical(length(got), length(dirs), label = res$stderr)
  if (length(got) != length(dirs)) return(invisible())
  for (i in seq_along(dirs)) {
    expect_identical(got[[i]], if (EFA_PROJECT_CASES[[i]]$want == "knitr") "knitr" else "filter", label = EFA_PROJECT_CASES[[i]]$name)
  }
})
