# Helpers for test-engine-fence-agree.R. ASCII only.

# ---- group 1: the metadata-block cases, one table for every reader --------------------------------------

# The probe: a `---` block that sets chunk_claims to collect. A reader that finds the block as a block gives
# "collect"; one that finds it hidden inside a fence (or a quote, comment ...) gives the default, "stop".
EFA_PROBE <- c("---", "weft:", "  chunk_claims: collect", "---")

# a case: name, the lines of the document, the answer (the value R's reader gives today, "collect" or "stop")
efa_mb <- function(name, lines, want) list(name = name, lines = lines, want = want)

EFA_MB_CASES <- list(
  efa_mb("control-plain-probe", c("# T", "", EFA_PROBE), "collect"),
  efa_mb("control-probe-after-closed-fence", c("```text", "x", "```", "", EFA_PROBE), "collect"),
  efa_mb("control-probe-inside-closed-fence", c("```text", EFA_PROBE, "```"), "stop"),
  efa_mb("control-probe-inside-closed-tilde-fence", c("~~~", EFA_PROBE, "~~~"), "stop"),
  efa_mb("control-probe-inside-chunk", c("```{r}", EFA_PROBE, "```"), "stop"),
  # R1: a backtick in a backtick fence's info string: not an opener
  efa_mb("R1-backtick-info-is-not-a-fence", c("``` a`b", "", EFA_PROBE), "collect"),
  efa_mb("R1-tilde-info-backtick-is-not-a-fence", c("~~~ a`b", "", EFA_PROBE, "~~~"), "collect"),
  # 27 Nov: Pandoc markdown reads a fence only for one word or a braced attribute block
  efa_mb("R1-two-word-info-is-not-a-fence", c("```text a", "", EFA_PROBE, "```"), "collect"),
  efa_mb("R1-two-word-tilde-info-is-not-a-fence", c("~~~ a b", "", EFA_PROBE, "~~~"), "collect"),
  efa_mb("R1-one-word-info-after-a-space-is-a-fence", c("``` text", "", EFA_PROBE, "```"), "stop"),
  efa_mb("R1-attribute-block-info-is-a-fence", c("```{.text .x}", "", EFA_PROBE, "```"), "stop"),
  efa_mb("R1-tilde-one-word-info-is-a-fence", c("~~~ text", "", EFA_PROBE, "~~~"), "stop"),
  efa_mb("R1-chunk-header-backtick-is-a-chunk", c("```{r a`b}", EFA_PROBE, "```"), "stop"),
  # R2: indent and closers
  efa_mb("R2-3-space-fence-hides", c("   ```", "", EFA_PROBE, "   ```"), "stop"),
  efa_mb("R2-4-space-fence-is-code", c("    ```", "", EFA_PROBE), "collect"),
  efa_mb("R2-longer-closer-closes-plain", c("```text", "x", "`````", "", EFA_PROBE), "collect"),
  efa_mb("R2-shorter-closer-does-not-close-plain", c("````text", "x", "```", "", EFA_PROBE, "````"), "stop"),
  efa_mb("R2-text-after-closer-is-not-a-closer", c("```text", "x", "``` y", "", EFA_PROBE, "```"), "stop"),
  efa_mb("R2-other-character-does-not-close", c("```text", "x", "~~~", "", EFA_PROBE, "```"), "stop"),
  efa_mb("R2-4-space-closer-does-not-close-plain", c("```text", "x", "    ```", "", EFA_PROBE, "```"), "stop"),
  efa_mb("R2-chunk-shorter-closer-closes", c("````{r}", "x", "```", "", EFA_PROBE), "collect"),
  efa_mb("R2-chunk-indented-closer-closes", c("```{r}", "x", "    ```", "", EFA_PROBE), "collect"),
  efa_mb("R2-chunk-tilde-does-not-close", c("```{r}", "x", "~~~", "", EFA_PROBE, "```"), "stop"),
  efa_mb("R2-chunk-indented-4-is-a-chunk", c("para", "", "    ```{r}", "    x", "", EFA_PROBE, "    ```"), "stop"),
  # R3: an unclosed fence runs to the end
  efa_mb("R3-unclosed-chunk-swallows", c("```{r}", "x", "", EFA_PROBE), "stop"),
  # amended 27 Nov (1cb2897): Pandoc's markdown reader reads an unclosed plain fence as no fence, so its text is
  # prose and a later block is a block (an unclosed chunk is still a chunk to knitr, which runs it to the end)
  efa_mb("R3-unclosed-plain-fence-is-prose", c("```text", "x", "", EFA_PROBE), "collect"),
  efa_mb("R3-unclosed-tilde-fence-is-prose", c("~~~", "x", "", EFA_PROBE), "collect"),
  efa_mb("R3-unclosed-plain-fence-closed-later-hides", c("```text", "x", "", EFA_PROBE, "```"), "stop"),
  # R4: quotes
  efa_mb("R4-quoted-unclosed-fence-is-prose", c("> ```", "> a", "", EFA_PROBE, "t"), "collect"),
  efa_mb("R4-quoted-closed-fence", c("> ```", "> x", "> ```", "", EFA_PROBE), "collect"),
  efa_mb("R4-unclosed-plain-fence-with-a-quoted-line-is-prose", c("```", "> ```", "", EFA_PROBE), "collect"),
  efa_mb("R4-quoted-line-does-not-close-outside-fence", c("```", "> ```", "", EFA_PROBE, "```"), "stop"),
  efa_mb("R4-chunk-quoted-line-closes-unquoted-chunk", c("```{r}", "> ```", "", EFA_PROBE), "collect"),
  efa_mb("R4-chunk-unquoted-closer-closes-quoted-chunk", c("> ```{r}", "> x", "```", "", EFA_PROBE), "collect"),
  efa_mb("R4-chunk-quoted-unclosed-runs-to-the-end", c("> ```{r}", "> x", "", EFA_PROBE), "stop"),
  # R5: comments hide plain fences, not chunks
  efa_mb("R5-comment-hides-plain-fence", c("<!--", "```", "-->", "", EFA_PROBE), "collect"),
  efa_mb("R5-comment-chunk-still-runs-and-swallows", c("<!--", "```{r}", "x", "-->", "", EFA_PROBE), "stop"),
  efa_mb("R5-comment-chunk-closed-then-probe", c("<!--", "```{r}", "x", "```", "-->", "", EFA_PROBE), "collect")
)

# ---- running one table through each reader ---------------------------------------------------------------

# Write each case of `cases` (each with $name and $lines) to its own folder as doc.qmd; returns the folders.
efa_write <- function(cases, env = parent.frame()) {
  base <- normalizePath(withr::local_tempdir(.local_envir = env), winslash = "/")
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir(.local_envir = env), .local_envir = env)
  dirs <- vapply(seq_along(cases), function(i) {
    d <- file.path(base, sprintf("c%02d", i))
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    writeBin(charToRaw(paste0(paste(cases[[i]]$lines, collapse = "\n"), "\n")), file.path(d, "doc.qmd"))
    d
  }, "")
  stats::setNames(dirs, vapply(cases, `[[`, "", "name"))
}

# chunk_claims as R reads it ("stop" is the default)
efa_r_claims <- function(dir) {
  v <- weft:::read_front_matter(file.path(dir, "doc.qmd"))$weft$chunk_claims
  if (is.null(v)) "stop" else v
}

EFA_LUA_CLAIMS <- '
local lib = arg[1]
local config = dofile(lib .. "/config.lua")
for i = 2, #arg do
  local dir = arg[i]
  local f = io.open(dir .. "/doc.qmd", "rb")
  local text = f and f:read("a") or nil
  if f then f:close() end
  local ok, cfg = pcall(config.load, dir .. "/doc.qmd", text, dir)
  io.write(ok and tostring(cfg.chunk_claims) or "error", "\\n")
end
'

# one line of output per folder, or NULL (with a failed expectation) when the reader did not run
efa_lua_claims <- function(dirs) {
  script <- file.path(dirname(dirs[[1]]), "driver-claims.lua")
  writeLines(EFA_LUA_CLAIMS, script)
  lib <- file.path(dirname(filter_path("weft.lua")), "weftlib")
  res <- lua_run(script, c(lib, unname(dirs)))
  got <- strsplit(res$stdout, "\n", fixed = TRUE)[[1]]
  testthat::expect_identical(length(got), length(dirs), label = paste("one Lua line per case;", res$stderr))
  if (length(got) != length(dirs)) return(NULL)
  got
}

efa_py_claims <- function(dirs) {
  spec <- file.path(dirname(dirs[[1]]), "spec.json")
  writeLines(jsonlite::toJSON(list(source = file.path(dirs, "doc.qmd"), folder = unname(dirs)),
                              auto_unbox = FALSE), spec)
  code <- paste(
    "import json",
    "from weft import _config",
    sprintf("s = json.load(open('%s'))", spec),
    "for src, folder in zip(s['source'], s['folder']):",
    "    print(_config.chunk_claims(src, folder))",
    sep = "\n")
  x <- py_plain(code)
  testthat::expect_identical(x$status, 0L, label = x$stderr)
  got <- strsplit(x$stdout, "\n", fixed = TRUE)[[1]]
  testthat::expect_identical(length(got), length(dirs), label = "one Python line per case")
  if (length(got) != length(dirs)) return(NULL)
  got
}

efa_jl_claims <- function(dirs) {
  q <- function(x) paste0("\"", x, "\"")
  code <- c("using Weft",
            sprintf("for (src, folder) in [%s]",
                    paste(sprintf("(%s, %s)", q(file.path(dirs, "doc.qmd")), q(dirs)), collapse = ", ")),
            "    println(Weft.chunk_claims_setting(src, folder))",
            "end")
  r <- jle_cases(paste(code, collapse = "\n"))[[1]]
  testthat::expect_identical(r$emsg, "", label = "the Julia reader ran")
  got <- strsplit(sub("\n$", "", r$out), "\n", fixed = TRUE)[[1]]
  testthat::expect_identical(length(got), length(dirs), label = "one Julia line per case")
  if (length(got) != length(dirs)) return(NULL)
  got
}

# ---- the oracles -----------------------------------------------------------------------------------------

efa_skip_if_no_quarto <- function() testthat::skip_if(!nzchar(Sys.which("quarto")), "quarto is not available")

# the engine Quarto itself picks for a document: `quarto inspect` on a real file (NA when it refuses)
efa_quarto_engine <- function(lines) {
  d <- withr::local_tempdir()
  f <- file.path(d, "a.qmd")
  writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), f)
  out <- suppressWarnings(system2("quarto", c("inspect", shQuote(f)), stdout = TRUE, stderr = FALSE))
  j <- tryCatch(jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(j) || length(j$engines) == 0L) NA_character_ else j$engines[[1]]
}

# what Pandoc (reading `fmt`) makes of a document holding one fence whose body line is x: "fence" when the
# body line is the content of a CodeBlock (the fence was read as a fence), "code" when the CodeBlock holds the
# fence lines themselves (an indented code block), "none" when there is no CodeBlock
# and efa_pandoc_has_meta(lines, "weft") says whether Pandoc reads a metadata block that sets that key
efa_pandoc_has_meta <- function(lines, key, fmt = "markdown") {
  out <- suppressWarnings(system2("quarto", c("pandoc", "-f", fmt, "-t", "json"),
                                  input = paste0(paste(lines, collapse = "\n"), "\n"), stdout = TRUE, stderr = FALSE))
  key %in% names(jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)$meta)
}

efa_pandoc_verdict <- function(lines, fmt = "markdown") {
  out <- suppressWarnings(system2("quarto", c("pandoc", "-f", fmt, "-t", "json"),
                                  input = paste0(paste(lines, collapse = "\n"), "\n"), stdout = TRUE, stderr = FALSE))
  j <- jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
  walk <- function(t) {
    if (!is.list(t)) return(character())
    here <- if (identical(t[["t"]], "CodeBlock")) t[["c"]][[2]] else character()
    c(here, unlist(lapply(t, walk), use.names = FALSE))
  }
  texts <- walk(j$blocks)
  if (length(texts) == 0L) "none" else if (any(texts == "x")) "fence" else "code"
}

# ---- group 2: chunk headers and the engine ---------------------------------------------------------------

# a case: the document, the engine Quarto picks (from `quarto inspect`, Quarto 1.11.9), and whether knitr
# runs the chunk (checked by knitting; knitr 1.51 chunk.begin `^[\t >]*```+\s*\{([a-zA-Z0-9_]+( *[ ,].*)?)\}\s*$`)
efa_hdr <- function(name, lines, quarto, knitr_runs) list(name = name, lines = lines, quarto = quarto, knitr_runs = knitr_runs)
efa_body <- function(hdr) c(hdr, "1 + 1", "```")

EFA_HDR_CASES <- list(
  efa_hdr("control-r", efa_body("```{r}"), "knitr", TRUE),
  efa_hdr("control-r-with-options", efa_body("```{r, echo=FALSE}"), "knitr", TRUE),
  efa_hdr("control-r-with-label", efa_body("```{r setup}"), "knitr", TRUE),
  efa_hdr("control-python", efa_body("```{python}"), "jupyter", TRUE),
  efa_hdr("control-rust-is-not-r", efa_body("```{rust}"), "jupyter", TRUE),
  efa_hdr("control-no-chunk", "Some prose.", "markdown", FALSE),
  efa_hdr("control-plain-r-fence", efa_body("```r"), "markdown", FALSE),
  efa_hdr("control-r-in-a-quote", c("> ```{r}", "> 1 + 1", "> ```"), "knitr", TRUE),
  efa_hdr("control-r-indented-4", c("para", "", "    ```{r}", "    1 + 1", "    ```"), "knitr", TRUE),
  efa_hdr("control-r-in-a-comment", c("<!--", efa_body("```{r}"), "-->"), "knitr", TRUE),
  efa_hdr("control-r-with-a-backtick-in-the-header", efa_body("```{r a`b}"), "knitr", TRUE),
  efa_hdr("upper-R-is-r", efa_body("```{R}"), "knitr", TRUE),
  efa_hdr("upper-Python-is-python", efa_body("```{Python}"), "jupyter", TRUE),
  efa_hdr("upper-Julia-is-julia", efa_body("```{Julia}"), "julia", TRUE),
  efa_hdr("upper-R-in-a-quote", c("> ```{R}", "> 1 + 1", "> ```"), "knitr", TRUE),
  efa_hdr("trailing-space-r", efa_body("```{r }"), "knitr", TRUE),
  efa_hdr("leading-and-trailing-space", efa_body("```{ r }"), "markdown", FALSE),
  efa_hdr("leading-space-only", efa_body("```{ r}"), "markdown", FALSE),
  efa_hdr("space-before-python-is-not-python", efa_body("```{ python }"), "markdown", FALSE),
  efa_hdr("space-r-then-a-python-chunk", c(efa_body("```{python}"), efa_body("```{ r }")), "jupyter", TRUE),
  efa_hdr("tilde-fence-is-no-chunk", efa_body("~~~{r}"), "markdown", FALSE),
  efa_hdr("text-after-the-brace-is-no-chunk", efa_body("```{r} x"), "markdown", FALSE),
  # Quarto's chunk regex ends the name at the first character outside [a-zA-Z0-9_.]; knitr's needs a space or a
  # comma after the name. They disagree on these three.
  efa_hdr("dash-after-name", efa_body("```{r-x}"), "knitr", FALSE),
  efa_hdr("equals-after-name", efa_body("```{r=1}"), "knitr", FALSE),
  efa_hdr("dot-in-name-is-another-language", efa_body("```{r.x}"), "jupyter", FALSE),
  # a header that runs across lines: Quarto's language regex lets `[^}]*` cross a line end, so the opener `{r` with
  # its `}` on a later line is a chunk of language r (`quarto inspect`, 1.11.9); knitr's pattern works line by
  # line, so it runs no such chunk. Quarto's engine is the answer; weft must agree with it.
  efa_hdr("multiline-r-header", c("```{r", "echo=FALSE}", "1 + 1", "```"), "knitr", FALSE),
  efa_hdr("multiline-r-header-after-a-comma", c("```{r,", "echo=FALSE}", "1 + 1", "```"), "knitr", FALSE),
  efa_hdr("multiline-r-header-brace-three-lines-on", c("```{r", "x <- 1", "y <- 2", "}", "```"), "knitr", FALSE),
  efa_hdr("multiline-r-header-blank-line-between", c("```{r", "", "echo=FALSE}", "1 + 1", "```"), "knitr", FALSE),
  efa_hdr("multiline-python-header", c("```{python", "echo=FALSE}", "1 + 1", "```"), "jupyter", FALSE),
  efa_hdr("multiline-julia-header", c("```{julia", "echo=FALSE}", "1 + 1", "```"), "julia", FALSE),
  efa_hdr("multiline-python-then-r-chunk", c("```{python", "echo=FALSE}", "1", "```", "", efa_body("```{r}")), "knitr", TRUE),
  efa_hdr("multiline-space-before-name-is-no-chunk", c("```{ r", "}", "1 + 1", "```"), "markdown", FALSE),
  efa_hdr("multiline-text-after-first-brace-is-no-chunk", c("```{r} x", "}", "1 + 1", "```"), "markdown", FALSE),
  efa_hdr("opener-with-no-closing-brace-is-no-chunk", c("```{r", "1 + 1", "```"), "markdown", FALSE)
)

# an unclosed chunk: knitr runs it (to the end of the file), but Quarto's engine choice does not see it (checked
# on a file that ends with a newline; the same header with no final newline is seen)
EFA_UNCLOSED_CASES <- list(
  efa_hdr("unclosed-r-with-code", c("```{r}", "1 + 1"), "markdown", TRUE),
  efa_hdr("unclosed-r-header-only", "```{r}", "markdown", TRUE)
)

# ---- group 5: front-matter keys against the engine -------------------------------------------------------

# Quarto's markdownExecutionEngine (src/execute/engine.ts, 1.11.9) loops over the engines in order (knitr,
# jupyter, markdown; a project's `engines:` first, and the julia engine ahead of knitr), and for each engine takes
# it when the metadata has a truthy key of its name (`knitr:`, `jupyter:`, `markdown:`) or `engine:` /
# `execute: engine:` equal to the name. A key therefore beats an `engine:` that names a later engine.
efa_eng <- function(name, fm, body, want) {
  list(name = name, lines = c("---", fm, "---", "", body), quarto = want)
}
EFA_PROSE <- "Some prose."
EFA_PYCHUNK <- c("```{python}", "1", "```")
EFA_RCHUNK <- c("```{r}", "1", "```")
EFA_KNITR_MAP <- c("knitr:", "  opts_chunk:", "    echo: false")

EFA_ENGINE_CASES <- list(
  # new behaviour: a knitr key beats an engine that names a later engine
  efa_eng("knitr-key-beats-engine-jupyter", c("engine: jupyter", "knitr: true"), EFA_PROSE, "knitr"),
  efa_eng("knitr-map-beats-engine-jupyter", c("engine: jupyter", EFA_KNITR_MAP), EFA_PROSE, "knitr"),
  efa_eng("knitr-key-beats-engine-jupyter-with-python-chunk", c("engine: jupyter", "knitr: true"), EFA_PYCHUNK, "knitr"),
  efa_eng("knitr-key-beats-jupyter-key", c("jupyter: python3", "knitr: true"), EFA_PROSE, "knitr"),
  efa_eng("knitr-map-beats-jupyter-key", c("jupyter: python3", EFA_KNITR_MAP), EFA_PROSE, "knitr"),
  efa_eng("knitr-key-beats-jupyter-key-with-r-chunk", c("jupyter: python3", "knitr: true"), EFA_RCHUNK, "knitr"),
  efa_eng("knitr-key-beats-engine-markdown", c("engine: markdown", "knitr: true"), EFA_PROSE, "knitr"),
  efa_eng("knitr-map-beats-engine-markdown", c("engine: markdown", EFA_KNITR_MAP), EFA_PROSE, "knitr"),
  efa_eng("knitr-key-beats-execute-engine-jupyter", c("execute:", "  engine: jupyter", "knitr: true"), EFA_PROSE, "knitr"),
  efa_eng("knitr-key-beats-engine-markdown-and-jupyter-key", c("engine: markdown", "jupyter: python3", "knitr: true"), EFA_PROSE, "knitr"),
  # Quarto's own order: the jupyter key is looked at before engine: markdown, so it wins there
  efa_eng("jupyter-key-beats-engine-markdown", c("engine: markdown", "jupyter: python3"), EFA_PROSE, "jupyter"),
  efa_eng("engine-knitr-beats-jupyter-key", c("engine: knitr", "jupyter: python3"), EFA_PROSE, "knitr"),
  efa_eng("engine-jupyter-with-markdown-key-stays-jupyter", c("engine: jupyter", "markdown: true"), EFA_PROSE, "jupyter"),
  efa_eng("engine-knitr-with-markdown-key-stays-knitr", c("engine: knitr", "markdown: true"), EFA_PROSE, "knitr"),
  # the julia engine is looked at before knitr, so a knitr key does not beat it
  efa_eng("engine-julia-beats-knitr-key", c("engine: julia", "knitr: true"), EFA_PROSE, "julia"),
  efa_eng("engine-julia-beats-knitr-map", c("engine: julia", EFA_KNITR_MAP), EFA_PROSE, "julia"),
  # controls
  efa_eng("knitr-map-alone-is-knitr", EFA_KNITR_MAP, EFA_PROSE, "knitr"),
  efa_eng("knitr-key-with-python-chunk-is-knitr", EFA_KNITR_MAP, EFA_PYCHUNK, "knitr"),
  efa_eng("knitr-false-is-not-a-claim", "knitr: false", EFA_PROSE, "markdown"),
  efa_eng("control-engine-jupyter", "engine: jupyter", EFA_PROSE, "jupyter"),
  efa_eng("control-engine-knitr-with-python-chunk", "engine: knitr", EFA_PYCHUNK, "knitr"),
  efa_eng("execute-engine-knitr", c("execute:", "  engine: knitr"), EFA_PYCHUNK, "knitr"),
  efa_eng("control-jupyter-key", "jupyter: python3", EFA_PROSE, "jupyter"),
  efa_eng("control-jupyter-key-with-r-chunk", "jupyter: python3", EFA_RCHUNK, "jupyter"),
  efa_eng("control-engine-markdown-with-r-chunk", "engine: markdown", EFA_RCHUNK, "markdown"),
  efa_eng("execute-engine-markdown-with-r-chunk", c("execute:", "  engine: markdown"), EFA_RCHUNK, "markdown"),
  efa_eng("control-engine-julia", "engine: julia", EFA_PROSE, "julia"),
  efa_eng("control-knitr-key-in-a-format-is-no-claim", c("engine: jupyter", "format:", "  html:", "    knitr: true"), EFA_PROSE, "jupyter")
)

# ---- group 3: plain fences inside list items --------------------------------------------------------------

sp <- function(n) strrep(" ", n)
# a fence of `n` spaces' indent, body line x, closed
efa_fence_at <- function(n, ch = "```") paste0(sp(n), c(ch, "x", ch))

# a case: the lines, `want` ("fence", "code" or "none") as `pandoc -f markdown` reads it (the ruling of 27 Nov,
# 1cb2897: plain fences follow Pandoc's markdown reader, which Quarto uses, wherever it differs from CommonMark)
efa_li <- function(name, lines, want) list(name = name, lines = lines, want = want)

EFA_LIST_CASES <- list(
  # controls: no list
  efa_li("control-top-level-3-spaces", c("para", "", efa_fence_at(3)), "fence"),
  efa_li("control-top-level-4-spaces-is-indented-code", c("para", "", efa_fence_at(4)), "code"),
  efa_li("control-a-list-that-has-ended-is-no-list", c("- item", "", "para", "", efa_fence_at(4)), "code"),
  # `- item`: the content column is 2, so 4, 5 are fences (2, 3 deep) and 6, 7, 8 are indented code
  efa_li("dash-item-fence-at-2", c("- item", "", efa_fence_at(2)), "fence"),
  efa_li("dash-item-fence-at-3", c("- item", "", efa_fence_at(3)), "fence"),
  efa_li("dash-item-fence-at-4", c("- item", "", efa_fence_at(4)), "fence"),
  efa_li("dash-item-fence-at-5", c("- item", "", efa_fence_at(5)), "fence"),
  efa_li("dash-item-fence-at-6-is-code", c("- item", "", efa_fence_at(6)), "code"),
  efa_li("dash-item-fence-at-7-is-code", c("- item", "", efa_fence_at(7)), "code"),
  efa_li("dash-item-fence-at-8-is-code", c("- item", "", efa_fence_at(8)), "code"),
  efa_li("star-item-fence-at-4", c("* item", "", efa_fence_at(4)), "fence"),
  efa_li("plus-item-fence-at-4", c("+ item", "", efa_fence_at(4)), "fence"),
  efa_li("dash-item-tilde-fence-at-4", c("- item", "", efa_fence_at(4, "~~~")), "fence"),
  # `1. item`: the content column is 3
  efa_li("ol-item-fence-at-3", c("1. item", "", efa_fence_at(3)), "fence"),
  efa_li("ol-item-fence-at-4", c("1. item", "", efa_fence_at(4)), "fence"),
  efa_li("ol-item-fence-at-6", c("1. item", "", efa_fence_at(6)), "fence"),
  efa_li("ol-item-fence-at-7-is-code", c("1. item", "", efa_fence_at(7)), "code"),
  efa_li("ol-item-fence-at-8-is-code", c("1. item", "", efa_fence_at(8)), "code"),
  # `10. item`: the content column is 4
  efa_li("ol10-item-fence-at-4", c("10. item", "", efa_fence_at(4)), "fence"),
  efa_li("ol10-item-fence-at-6", c("10. item", "", efa_fence_at(6)), "fence"),
  efa_li("ol10-item-fence-at-8-is-code", c("10. item", "", efa_fence_at(8)), "code"),
  efa_li("ol-paren-item-fence-at-7-is-code", c("1) item", "", efa_fence_at(7)), "code"),
  # a wide marker, `-   item`: the content column is 4
  efa_li("wide-dash-item-fence-at-4", c("-   item", "", efa_fence_at(4)), "fence"),
  efa_li("wide-dash-item-fence-at-7", c("-   item", "", efa_fence_at(7)), "fence"),
  efa_li("wide-dash-item-fence-at-8-is-code", c("-   item", "", efa_fence_at(8)), "code"),
  # nested lists: the indent is measured from the inner item's content column
  efa_li("nested-dash-fence-at-4", c("- a", "  - b", "", efa_fence_at(4)), "fence"),
  efa_li("nested-dash-fence-at-6", c("- a", "  - b", "", efa_fence_at(6)), "fence"),
  efa_li("nested-dash-fence-at-7", c("- a", "  - b", "", efa_fence_at(7)), "fence"),
  efa_li("nested-dash-fence-at-8-is-code", c("- a", "  - b", "", efa_fence_at(8)), "code"),
  efa_li("nested-dash-fence-at-10-is-code", c("- a", "  - b", "", efa_fence_at(10)), "code"),
  efa_li("ol-then-dash-fence-at-5", c("1. a", "   - b", "", efa_fence_at(5)), "fence"),
  efa_li("ol-then-dash-fence-at-8", c("1. a", "   - b", "", efa_fence_at(8)), "fence"),
  efa_li("ol-then-dash-fence-at-9-is-code", c("1. a", "   - b", "", efa_fence_at(9)), "code"),
  # continuation paragraphs: the item goes on, so the content column does not move
  efa_li("continuation-paragraph-fence-at-4", c("- item", "", "  continued", "", efa_fence_at(4)), "fence"),
  efa_li("continuation-paragraph-fence-at-6-is-code", c("- item", "", "  continued", "", efa_fence_at(6)), "code"),
  efa_li("ol-continuation-paragraph-fence-at-6", c("1. item", "", "   continued", "", efa_fence_at(6)), "fence"),
  # lazy continuation: a fence line with no indent ends the list, and is a plain top-level fence
  efa_li("lazy-line-then-fence-at-2", c("- item", "lazy", efa_fence_at(2)), "fence"),
  efa_li("lazy-line-then-fence-at-0", c("- item", "lazy", efa_fence_at(0)), "fence"),
  # a fence with no blank line before it, in a list item: Pandoc's markdown reader does not read it as a fence (it
  # reads the lines as inline code or text); CommonMark does, and the ruling follows Pandoc
  efa_li("lazy-line-then-fence-at-4-is-no-fence", c("- item", "lazy", efa_fence_at(4)), "none"),
  efa_li("no-blank-line-fence-at-4-is-no-fence", c("- item", efa_fence_at(4)), "none"),
  efa_li("no-blank-line-fence-at-2", c("- item", efa_fence_at(2)), "fence"),
  efa_li("no-blank-line-fence-at-6-is-no-fence-for-either", c("- item", efa_fence_at(6)), "none"),
  # an empty list item: its content column is 2 (Pandoc markdown reads a fence; CommonMark reads code)
  efa_li("empty-item-fence-at-4", c("-", "", efa_fence_at(4)), "fence"),
  efa_li("empty-item-fence-at-2", c("-", "", efa_fence_at(2)), "fence"),
  efa_li("empty-item-fence-at-6-is-code", c("-", "", efa_fence_at(6)), "code")
)

# ---- group 4: the last line of an unclosed chunk ---------------------------------------------------------

# a case: the lines (an unclosed chunk, the offending text on its last line), the findings (rule@line) wanted
# from the lint rules that read a chunk's code lines
efa_last <- function(name, lines, want, rules) list(name = name, lines = lines, want = want, rules = rules)
EFA_LAST_CASES <- list(
  efa_last("label-is-the-only-line", c("```{r}", "#| label: x"), character(), "chunk-label"),
  efa_last("label-is-the-last-of-two-option-lines", c("```{r}", "#| echo: false", "#| label: x"), character(), "chunk-label"),
  efa_last("label-is-in-the-header", c("```{r x}", "1"), character(), "chunk-label"),
  efa_last("control-no-label-one-code-line", c("```{r}", "1"), "chunk-label@1", "chunk-label"),
  efa_last("control-no-label-header-only", c("```{r}"), "chunk-label@1", "chunk-label"),
  efa_last("control-closed-twin-of-the-label-case", c("```{r}", "#| label: x", "```"), character(), "chunk-label"),
  efa_last("fig-alt-on-the-last-line-counts", c("```{r}", "#| label: fig-d", "#| fig-cap: C", "#| fig-alt: A"), "anchor-unused@2", c("figure", "anchor-unused")),
  efa_last("fig-cap-on-the-last-line-counts", c("```{r}", "#| label: fig-d", "#| fig-alt: A", "#| fig-cap: C"), "anchor-unused@2", c("figure", "anchor-unused")),
  efa_last("control-fig-alt-missing", c("```{r}", "#| label: fig-d", "#| fig-cap: C"), c("figure@1", "anchor-unused@2"), c("figure", "anchor-unused")),
  efa_last("tbl-cap-on-the-last-line-counts", c("```{r}", "#| label: tbl-d", "#| tbl-cap: C"), "anchor-unused@2", c("table-caption", "anchor-unused")),
  efa_last("dict-assign-on-the-last-line", c("```{r}", "#| label: z", "dict$k <- 1"), "dict-assign@3", "dict-assign"),
  efa_last("dict-key-on-the-last-line", c("```{r}", "#| label: z", "y <- dict$zzz"), "dict-key@3", "dict-key"),
  efa_last("tar-cache-with-a-read-on-the-last-line", c("```{r}", "#| label: z", "#| cache: true", "tar_read(fitt)"), "tar-cache@4", "tar-cache"),
  efa_last("a-reference-to-a-label-on-the-last-line", c("See @fig-d.", "", "```{r}", "#| label: fig-d", "#| fig-cap: C", "#| fig-alt: A"), character(), c("xref", "anchor-unused", "figure"))
)

# a project's `engines:` list puts those engines ahead of the others in Quarto's loop (checked with `quarto inspect`,
# 1.11.9): with jupyter first, the `jupyter:` key, or `engine: jupyter`, beats a `knitr:` key; with markdown first
# the `knitr:` key still wins (markdown has no key here)
efa_proj <- function(name, engines, fm, want) {
  list(name = name, want = want,
       files = list("_quarto.yml" = c("project:", "  title: p", paste0("engines: ", engines)),
                    "doc.qmd" = c("---", fm, "---", "", EFA_PROSE)))
}
EFA_PROJECT_CASES <- list(
  efa_proj("project-engines-jupyter-first-jupyter-key-beats-knitr-key", "[jupyter, knitr]", c("jupyter: python3", "knitr: true"), "jupyter"),
  efa_proj("project-engines-jupyter-first-engine-jupyter-beats-knitr-key", "[jupyter, knitr]", c("engine: jupyter", "knitr: true"), "jupyter"),
  efa_proj("project-engines-markdown-first-knitr-key-still-wins", "[markdown]", "knitr: true", "knitr"),
  efa_proj("project-engines-knitr-first-knitr-key-wins", "[knitr, jupyter]", c("engine: jupyter", "knitr: true"), "knitr")
)

efa_project_write <- function(cases, env = parent.frame()) {
  base <- normalizePath(withr::local_tempdir(.local_envir = env), winslash = "/")
  vapply(seq_along(cases), function(i) {
    d <- file.path(base, sprintf("p%02d", i))
    for (nm in names(cases[[i]]$files)) f3_write(file.path(d, nm), cases[[i]]$files[[nm]])
    d
  }, "")
}

# ---- group 6: the project's `engines:` list from profile files and the local file -------------------------

# Quarto merges, into _quarto.yml, the file `_quarto-<profile>.yml` (or .yaml) of each active profile, and then
# `_quarto.yml.local` (or `_quarto.yaml.local`; NOT `_quarto.local.yml`, which it never reads). Lists are joined:
# the base file's entries first. A profile is active through QUARTO_PROFILE, `_environment` or `_environment.local`
# (a QUARTO_PROFILE= line), `profile: default:` in `_quarto.yml.local`, or `profile: default:` in `_quarto.yml`
# (all checked with `quarto inspect`, 1.11.9, and in the bundled quarto.js: mergeProfiles, localProjectConfigFile).
# The document claims both `knitr:` and `jupyter:`: it is knitr unless the project lists jupyter first.
EFA_PROF_FM <- c("jupyter: python3", "knitr: true")
efa_prof <- function(name, want, files, env = NA_character_) {
  base <- list("_quarto.yml" = c("project:", "  title: p"), "doc.qmd" = c("---", EFA_PROF_FM, "---", "", EFA_PROSE))
  list(name = name, want = want, env = env, files = utils::modifyList(base, files))
}
EFA_JUP <- "engines: [jupyter]"
EFA_PROFILE_CASES <- list(
  efa_prof("control-no-engines-is-knitr", "knitr", list()),
  efa_prof("profile-file-active", "jupyter", list("_quarto-prof.yml" = EFA_JUP), env = "prof"),
  efa_prof("profile-file-not-active", "knitr", list("_quarto-prof.yml" = EFA_JUP)),
  efa_prof("another-profile-active", "knitr", list("_quarto-prof.yml" = EFA_JUP), env = "other"),
  efa_prof("profile-yaml-extension", "jupyter", list("_quarto-prof.yaml" = EFA_JUP), env = "prof"),
  efa_prof("two-profiles-active", "jupyter",
           list("_quarto-p1.yml" = "engines: [markdown]", "_quarto-p2.yml" = EFA_JUP), env = "p1,p2"),
  efa_prof("profile-engines-follow-the-base-engines-jupyter-base", "jupyter",
           list("_quarto.yml" = c("project:", "  title: p", EFA_JUP), "_quarto-prof.yml" = "engines: [knitr]"), env = "prof"),
  efa_prof("profile-engines-follow-the-base-engines-knitr-base", "knitr",
           list("_quarto.yml" = c("project:", "  title: p", "engines: [knitr]"), "_quarto-prof.yml" = EFA_JUP), env = "prof"),
  efa_prof("local-file", "jupyter", list("_quarto.yml.local" = EFA_JUP)),
  efa_prof("local-file-yaml-extension", "jupyter", list("_quarto.yaml.local" = EFA_JUP)),
  efa_prof("local-file-with-a-profile-active", "jupyter",
           list("_quarto.yml.local" = EFA_JUP, "_quarto-prof.yml" = "engines: [markdown]"), env = "prof"),
  efa_prof("quarto-dot-local-dot-yml-is-not-read", "knitr", list("_quarto.local.yml" = EFA_JUP)),
  efa_prof("quarto-minus-local-yml-is-not-read", "knitr", list("_quarto-local.yml" = EFA_JUP)),
  efa_prof("profile-default-in-quarto-yml", "jupyter",
           list("_quarto.yml" = c("project:", "  title: p", "profile:", "  default: prof"), "_quarto-prof.yml" = EFA_JUP)),
  efa_prof("profile-default-in-the-local-file", "jupyter",
           list("_quarto.yml.local" = c("profile:", "  default: prof"), "_quarto-prof.yml" = EFA_JUP)),
  efa_prof("profile-from-the-environment-file", "jupyter",
           list("_environment" = "QUARTO_PROFILE=prof", "_quarto-prof.yml" = EFA_JUP))
)

# the folders of the cases, one each (the files are written as the case says)
efa_prof_write <- function(cases, env = parent.frame()) {
  base <- normalizePath(withr::local_tempdir(.local_envir = env), winslash = "/")
  vapply(seq_along(cases), function(i) {
    d <- file.path(base, sprintf("q%02d", i))
    for (nm in names(cases[[i]]$files)) f3_write(file.path(d, nm), cases[[i]]$files[[nm]])
    d
  }, "")
}
