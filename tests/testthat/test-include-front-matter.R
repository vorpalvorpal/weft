# Stage 2 of the project-metadata rules (dev/quarto-project-metadata.md, P4 and P5; spec 2.7.4 I1-I7):
#   P5  an included file's front matter is part of the document: its blocks sit at the include's position
#       after full expansion, the later block winning per top-level key (F3, so a later `weft:` replaces the
#       whole earlier `weft:`); the included file's folder `_metadata.yml` does not apply; every reader
#       expands includes before it reads blocks: R read_front_matter() and the lints, the Lua
#       config.load(), Python's weft._config.chunk_claims() and Julia's Weft.chunk_claims_setting().
#   P4  engine keys come from the first block of the include-expanded text: an include on line 1 supplies
#       that block (I6 of the findings), one further down never does (I7). `.ipynb` and `.py` are untouched.
# Include paths resolve against the main document's folder (I4 of 2.7.4), so every file of a case sits in
# the case's folder, except where a case says otherwise. The setting observed through the four readers is
# `chunk_claims` (default stop; the values here are stop and collect). Temp dirs only; R_USER_CACHE_DIR is
# pointed at a temp dir wherever a knit could run. ASCII only.

# ---- fixtures -----------------------------------------------------------------------------------------

ifm_fm <- function(...) c("---", c(...), "---")
IFM_COLLECT <- c("weft:", "  chunk_claims: collect")
IFM_STOP <- c("weft:", "  chunk_claims: stop")
IFM_INC <- "{{< include inc.qmd >}}"
IFM_INCQ <- "{{< include \"inc.qmd\" >}}"

# one case: a name, the files of its folder (named list of line vectors) and the chunk_claims it must give
ifm_case <- function(name, files, want, new = TRUE) {
  list(name = name, files = files, want = want, new = new)
}

IFM_CASES <- list(
  ifm_case("control-no-include-inc-unread",
           list(doc.qmd = c(ifm_fm("title: T"), "", "Text."), inc.qmd = c(ifm_fm(IFM_COLLECT), "", "Inc.")),
           "stop", new = FALSE),
  ifm_case("control-own-block-collect",
           list(doc.qmd = c(ifm_fm("title: T", IFM_COLLECT), "", "Text.")), "collect", new = FALSE),
  ifm_case("I1-unquoted-include-sets-collect",
           list(doc.qmd = c(ifm_fm("title: T"), "", IFM_INC, "", "Text."),
                inc.qmd = c(ifm_fm(IFM_COLLECT), "", "Inc.")), "collect"),
  ifm_case("I1-quoted-include-sets-collect",
           list(doc.qmd = c(ifm_fm("title: T"), "", IFM_INCQ, "", "Text."),
                inc.qmd = c(ifm_fm(IFM_COLLECT), "", "Inc.")), "collect"),
  ifm_case("I1-included-block-wins-over-earlier-own-block",
           list(doc.qmd = c(ifm_fm("title: T", IFM_COLLECT), "", IFM_INC, "", "Text."),
                inc.qmd = c(ifm_fm(IFM_STOP), "", "Inc.")), "stop"),
  ifm_case("I1-own-later-block-wins-over-included",
           list(doc.qmd = c(ifm_fm("title: T"), "", IFM_INC, "", ifm_fm(IFM_STOP), "", "Text."),
                inc.qmd = c(ifm_fm(IFM_COLLECT), "", "Inc.")), "stop"),
  ifm_case("I1-F3-included-weft-replaces-whole-weft",
           list(doc.qmd = c(ifm_fm("title: T", IFM_COLLECT), "", IFM_INC, "", "Text."),
                inc.qmd = c(ifm_fm("weft:", "  digits: 4"), "", "Inc.")), "stop"),
  ifm_case("I1-include-without-front-matter-changes-nothing",
           list(doc.qmd = c(ifm_fm("title: T", IFM_COLLECT), "", IFM_INC, "", "Text."),
                inc.qmd = "Just text.\n"), "collect", new = FALSE),
  ifm_case("I2-include-above-own-block-is-overridden",
           list(doc.qmd = c(IFM_INC, "", ifm_fm("title: T", IFM_STOP), "", "Text."),
                inc.qmd = c(ifm_fm(IFM_COLLECT), "", "Inc.")), "stop", new = FALSE),
  ifm_case("I2-include-above-own-block-kept-where-own-block-is-silent",
           list(doc.qmd = c(IFM_INC, "", ifm_fm("title: T"), "", "Text."),
                inc.qmd = c(ifm_fm(IFM_COLLECT), "", "Inc.")), "collect"),
  ifm_case("I3-nested-include-sets-collect",
           list(doc.qmd = c(ifm_fm("title: T"), "", "{{< include one.qmd >}}", "", "Text."),
                one.qmd = c("One.", "", "{{< include two.qmd >}}"),
                two.qmd = c(ifm_fm(IFM_COLLECT), "", "Two.")), "collect"),
  ifm_case("I3-nested-order-inner-block-before-outer-later-block",
           list(doc.qmd = c(ifm_fm("title: T"), "", "{{< include one.qmd >}}", "", "Text."),
                one.qmd = c("{{< include two.qmd >}}", "", ifm_fm(IFM_STOP), "", "One."),
                two.qmd = c(ifm_fm(IFM_COLLECT), "", "Two.")), "stop"),
  ifm_case("I3-nested-order-outer-block-before-inner-include",
           list(doc.qmd = c(ifm_fm("title: T"), "", "{{< include one.qmd >}}", "", "Text."),
                one.qmd = c(ifm_fm(IFM_STOP), "", "{{< include two.qmd >}}", "", "One."),
                two.qmd = c(ifm_fm(IFM_COLLECT), "", "Two.")), "collect"),
  ifm_case("I3-two-includes-in-order-of-appearance-last-wins",
           list(doc.qmd = c(ifm_fm("title: T"), "", "{{< include one.qmd >}}", "", "{{< include two.qmd >}}"),
                one.qmd = c(ifm_fm(IFM_COLLECT), "", "One."), two.qmd = c(ifm_fm(IFM_STOP), "", "Two.")), "stop"),
  ifm_case("I3-two-includes-reversed-last-wins",
           list(doc.qmd = c(ifm_fm("title: T"), "", "{{< include two.qmd >}}", "", "{{< include one.qmd >}}"),
                one.qmd = c(ifm_fm(IFM_COLLECT), "", "One."), two.qmd = c(ifm_fm(IFM_STOP), "", "Two.")), "collect"),
  ifm_case("I1-missing-include-does-not-crash-the-reader",
           list(doc.qmd = c(ifm_fm("title: T", IFM_COLLECT), "", "{{< include nope.qmd >}}", "", "Text.")),
           "collect", new = FALSE),
  ifm_case("I1-missing-include-others-still-read",
           list(doc.qmd = c(ifm_fm("title: T"), "", "{{< include nope.qmd >}}", "", IFM_INC),
                inc.qmd = c(ifm_fm(IFM_COLLECT), "", "Inc.")), "collect")
)

ifm_write <- function(case, base) {
  dir <- file.path(base, case$name)
  for (nm in names(case$files)) f3_write(file.path(dir, nm), case$files[[nm]])
  dir
}

ifm_dirs <- function(env = parent.frame()) {
  base <- normalizePath(withr::local_tempdir(.local_envir = env), winslash = "/")
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir(.local_envir = env), .local_envir = env)
  stats::setNames(vapply(IFM_CASES, ifm_write, "", base = base), vapply(IFM_CASES, `[[`, "", "name"))
}

# ---- the readers: chunk_claims through each -----------------------------------------------------------

test_that("P5 (R): read_front_matter() and read_config() give each case's chunk_claims", {
  withr::local_envvar(WEFT_DRAFT = NA)
  dirs <- ifm_dirs()
  for (i in seq_along(IFM_CASES)) {
    cs <- IFM_CASES[[i]]
    doc <- file.path(dirs[[i]], "doc.qmd")
    got <- tryCatch(
      suppressWarnings(weft:::read_config(dirs[[i]], front = weft:::read_front_matter(doc)$weft, doc = doc)$chunk_claims),
      error = function(e) paste("error:", conditionMessage(e)))
    expect_identical(got, cs$want, label = cs$name)
  }
})

IFM_LUA <- '
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

test_that("P5 (Lua): config.load() gives each case's chunk_claims", {
  skip_if_no_lua_pandoc()
  dirs <- ifm_dirs()
  script <- file.path(dirname(dirs[[1]]), "driver.lua")
  writeLines(IFM_LUA, script)
  res <- lua_run(script, c(dirname(lua_num_path()), unname(dirs)))
  got <- strsplit(res$stdout, "\n", fixed = TRUE)[[1]]
  expect_identical(length(got), length(IFM_CASES), label = paste("one line per case;", res$stderr))
  if (length(got) != length(IFM_CASES)) return(invisible())
  for (i in seq_along(IFM_CASES)) expect_identical(got[[i]], IFM_CASES[[i]]$want, label = IFM_CASES[[i]]$name)
})

test_that("P5 (Python): weft._config.chunk_claims(source, folder) gives each case's value", {
  skip_if_no_jupyter()
  dirs <- ifm_dirs()
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
  expect_identical(x$status, 0L, label = x$stderr)
  got <- strsplit(x$stdout, "\n", fixed = TRUE)[[1]]
  expect_identical(length(got), length(IFM_CASES))
  if (length(got) != length(IFM_CASES)) return(invisible())
  for (i in seq_along(IFM_CASES)) expect_identical(got[[i]], IFM_CASES[[i]]$want, label = IFM_CASES[[i]]$name)
})

test_that("P5 (Julia): Weft.chunk_claims_setting(source, folder) gives each case's value", {
  skip_if_julia_disabled()
  dirs <- ifm_dirs()
  q <- function(x) paste0("\"", x, "\"")
  code <- c("using Weft",
            sprintf("for (src, folder) in [%s]",
                    paste(sprintf("(%s, %s)", q(file.path(dirs, "doc.qmd")), q(dirs)), collapse = ", ")),
            "    println(Weft.chunk_claims_setting(src, folder))",
            "end")
  r <- jle_cases(paste(code, collapse = "\n"))[[1]]
  expect_identical(r$emsg, "", label = "the Julia reader ran")
  got <- strsplit(sub("\n$", "", r$out), "\n", fixed = TRUE)[[1]]
  expect_identical(length(got), length(IFM_CASES))
  if (length(got) != length(IFM_CASES)) return(invisible())
  for (i in seq_along(IFM_CASES)) expect_identical(got[[i]], IFM_CASES[[i]]$want, label = IFM_CASES[[i]]$name)
})

# ---- R: other keys of the included front matter (lang, claim_words, title) ------------------------------

ifm_lint <- function(files, rules, env = parent.frame()) {
  x <- lint_fixture(files, rules = rules, tier = 1:2, env = env)
  x[x$file %in% "a.qmd", , drop = FALSE]
}
IFM_ROSE <- "All 3 sites rose."
IFM_RATIO <- "The ratio was clear."

test_that("I1 (R): read_front_matter() merges the included file's keys as a later block", {
  dirs <- ifm_dirs()
  d <- dirs[["I1-unquoted-include-sets-collect"]]
  fm <- weft:::read_front_matter(file.path(d, "doc.qmd"))
  expect_identical(fm$title, "T")
  expect_identical(fm$weft$chunk_claims, "collect")
  f2 <- withr::local_tempdir()
  f3_write(file.path(f2, "doc.qmd"), c(ifm_fm("title: T", "lang: de"), "", IFM_INC, "", "Text."))
  f3_write(file.path(f2, "inc.qmd"), c(ifm_fm("lang: fr", "subtitle: S"), "", "Inc."))
  fm <- weft:::read_front_matter(file.path(f2, "doc.qmd"))
  expect_identical(fm$lang, "fr", label = "the included block is later, so its lang wins")
  expect_identical(fm$subtitle, "S")
  expect_identical(fm$title, "T")
})

test_that("I1 (R lint): lang in an included file's front matter is honoured by the claim-word lint", {
  # control: the same lang in the document's own block
  x <- ifm_lint(list("a.qmd" = c(ifm_fm("title: T", "lang: de"), "", IFM_ROSE)), "claim-word")
  expect_identical(nrow(x), 0L, label = "control: own lang: de")
  x <- ifm_lint(list("a.qmd" = c(ifm_fm("title: T"), "", IFM_ROSE)), "claim-word")
  expect_identical(x$text, "all, rose", label = "control: no lang")
  for (inc in c(IFM_INC, IFM_INCQ)) {
    x <- ifm_lint(list("a.qmd" = c(ifm_fm("title: T"), "", inc, "", IFM_ROSE),
                       "inc.qmd" = c(ifm_fm("lang: de"), "", "Inc.")), "claim-word")
    expect_identical(nrow(x), 0L, label = inc)
  }
})

test_that("I1 + F3 (R lint): on a clash lang from the later block wins, the include's or the document's own", {
  x <- ifm_lint(list("a.qmd" = c(ifm_fm("title: T", "lang: de"), "", IFM_INC, "", IFM_ROSE),
                     "inc.qmd" = c(ifm_fm("lang: en"), "", "Inc.")), "claim-word")
  expect_identical(x$text, "all, rose", label = "include (later) en beats own de")
  x <- ifm_lint(list("a.qmd" = c(ifm_fm("title: T"), "", IFM_INC, "", ifm_fm("lang: de"), "", IFM_ROSE),
                     "inc.qmd" = c(ifm_fm("lang: en"), "", "Inc.")), "claim-word")
  expect_identical(nrow(x), 0L, label = "own later de beats include en")
})

test_that("I1 (R lint): a weft: setting (claim_words) in an included file's front matter is honoured", {
  add <- c("weft:", "  claim_words:", "    add: [ratio]")
  x <- ifm_lint(list("a.qmd" = c(ifm_fm("title: T"), "", IFM_RATIO)), "claim-word")
  expect_identical(nrow(x), 0L, label = "control: no setting")
  x <- ifm_lint(list("a.qmd" = c(ifm_fm("title: T", add), "", IFM_RATIO)), "claim-word")
  expect_identical(x$text, "ratio", label = "control: own setting")
  for (inc in c(IFM_INC, IFM_INCQ)) {
    x <- ifm_lint(list("a.qmd" = c(ifm_fm("title: T"), "", inc, "", IFM_RATIO),
                       "inc.qmd" = c(ifm_fm(add), "", "Inc.")), "claim-word")
    expect_identical(x$text, "ratio", label = inc)
  }
})

test_that("I1 + F3 (R lint): an included weft: replaces the document's earlier weft: whole", {
  add <- c("weft:", "  claim_words:", "    add: [ratio]")
  x <- ifm_lint(list("a.qmd" = c(ifm_fm("title: T", add), "", IFM_INC, "", IFM_RATIO),
                     "inc.qmd" = c(ifm_fm("weft:", "  claim_cap: 5"), "", "Inc.")), "claim-word")
  expect_identical(nrow(x), 0L)
})

test_that("I3 (R lint): a nested include's front matter is read, in order of appearance", {
  add <- c("weft:", "  claim_words:", "    add: [ratio]")
  files <- list("a.qmd" = c(ifm_fm("title: T"), "", "{{< include one.qmd >}}", "", IFM_RATIO),
                "one.qmd" = c("One.", "", "{{< include two.qmd >}}"),
                "two.qmd" = c(ifm_fm(add), "", "Two."))
  expect_identical(ifm_lint(files, "claim-word")$text, "ratio", label = "nested")
  files[["one.qmd"]] <- c("{{< include two.qmd >}}", "", ifm_fm("weft:", "  claim_cap: 5"), "", "One.")
  expect_identical(nrow(ifm_lint(files, "claim-word")), 0L, label = "one's later block replaces two's weft:")
})

test_that("I4 (R lint): the included file's folder _metadata.yml does not apply; its front matter does", {
  add <- c("weft:", "  claim_words:", "    add: [ratio]")
  files <- list("a.qmd" = c(ifm_fm("title: T"), "", "{{< include sub/inc.qmd >}}", "", IFM_ROSE, "", IFM_RATIO),
                "sub/inc.qmd" = c(ifm_fm(add), "", "Inc."),
                "sub/_metadata.yml" = "lang: de")
  x <- ifm_lint(files, "claim-word")
  expect_setequal(x$text, c("all, rose", "ratio"))
})

test_that("I1 (R lint): a missing include file does not crash the reader; the document's own front matter still applies", {
  x <- ifm_lint(list("a.qmd" = c(ifm_fm("title: T", "lang: de"), "", "{{< include nope.qmd >}}", "", IFM_ROSE)),
                "claim-word")
  expect_identical(nrow(x), 0L)
  fm <- weft:::read_front_matter(file.path(lint_proj(list("a.qmd" = c(ifm_fm("title: T"), "", "{{< include nope.qmd >}}"))),
                                           "a.qmd"))
  expect_identical(fm$title, "T")
})

# ---- P4 / I6 / I7: the engine ----------------------------------------------------------------------------

IFM_ENG_KNITR <- c(ifm_fm("engine: knitr"), "")
IFM_ENG_MD <- c(ifm_fm("engine: markdown"), "")
IFM_RVAL <- "The depth is `r x`{.num} metres."
IFM_PY <- c("```{python}", "x = 1", "```")
IFM_MSG4 <- "a.qmd holds weft constructs but is not marked `engine: knitr` and no document includes it (rule 5.8.9)."
IFM_MSG1_MD <- paste0("a.qmd holds weft constructs and is marked `engine: markdown`; weft constructs are evaluated ",
                      "only under `engine: knitr` (rule 5.8.9).")

ifm_engine <- function(files, env = parent.frame()) ifm_lint(files, "engine", env = env)

test_that("P4 control (R engine lint): engine: knitr in the document's own first block; none at all", {
  expect_identical(nrow(ifm_engine(list("a.qmd" = c(ifm_fm("engine: knitr"), "", IFM_RVAL)))), 0L)
  x <- ifm_engine(list("a.qmd" = c("Intro.", "", IFM_RVAL)))
  expect_identical(x$message, IFM_MSG4)
})

test_that("I6 + P4 (R engine lint): an include on line 1 of a file whose front matter has engine: knitr marks the document", {
  for (inc in c(IFM_INC, IFM_INCQ)) {
    x <- ifm_engine(list("a.qmd" = c(inc, "", IFM_RVAL), "inc.qmd" = c(IFM_ENG_KNITR, "Inc.")))
    expect_identical(nrow(x), 0L, label = inc)
  }
})

test_that("I6 + P4 (R engine lint): an include on line 1 with engine: markdown makes it the engine (case 1 finding)", {
  x <- ifm_engine(list("a.qmd" = c(IFM_INC, "", IFM_RVAL, "", IFM_PY), "inc.qmd" = c(IFM_ENG_MD, "Inc.")))
  expect_identical(nrow(x), 1L)
  expect_identical(x$message, IFM_MSG1_MD)
})

test_that("I6 + P4 (R engine lint): blank lines above the line-1 include do not matter (F2); the included block is first", {
  x <- ifm_engine(list("a.qmd" = c("", "", IFM_INC, "", IFM_RVAL), "inc.qmd" = c(IFM_ENG_KNITR, "Inc.")))
  expect_identical(nrow(x), 0L)
})

test_that("I6 + P4 (R engine lint): the included block is the first block, so a later own engine: key is ignored (F6)", {
  x <- ifm_engine(list("a.qmd" = c(IFM_INC, "", ifm_fm("engine: markdown"), "", IFM_RVAL),
                       "inc.qmd" = c(IFM_ENG_KNITR, "Inc.")))
  expect_identical(nrow(x), 0L)
})

test_that("I6 + P4 (R engine lint): a nested include on line 1 supplies the first block", {
  x <- ifm_engine(list("a.qmd" = c("{{< include one.qmd >}}", "", IFM_RVAL),
                       "one.qmd" = c("{{< include two.qmd >}}", "", "One."),
                       "two.qmd" = c(IFM_ENG_KNITR, "Two.")))
  expect_identical(nrow(x), 0L)
})

test_that("I7 + P4 (R engine lint): the same include mid-document does not pick the engine", {
  x <- ifm_engine(list("a.qmd" = c("Intro.", "", IFM_INC, "", IFM_RVAL), "inc.qmd" = c(IFM_ENG_KNITR, "Inc.")))
  expect_identical(nrow(x), 1L)
  expect_identical(x$message, IFM_MSG4)
  x <- ifm_engine(list("a.qmd" = c(ifm_fm("title: T"), "", IFM_INC, "", IFM_RVAL),
                       "inc.qmd" = c(IFM_ENG_KNITR, "Inc.")))
  expect_identical(x$message, IFM_MSG4, label = "after the document's own first block")
})

test_that("I6 (R engine lint): a missing file on line 1 does not crash the reader", {
  x <- ifm_engine(list("a.qmd" = c("{{< include nope.qmd >}}", "", IFM_RVAL)))
  expect_identical(nrow(x), 1L)
  expect_identical(x$message, IFM_MSG4)
})

# ---- P4 / I6 / I7 in the Lua filter: config.source_is_knitr ----------------------------------------------

# rows: cases of list(files = named list of line vectors, want = "knitr" or "filter"); `doc.qmd` is the document
IFM_KN <- list(
  list(id = "control: own engine: knitr", want = "knitr", new = FALSE,
       files = list(doc.qmd = c(ifm_fm("engine: knitr"), "", "Prose."))),
  list(id = "control: no engine, no chunk", want = "filter", new = FALSE,
       files = list(doc.qmd = c("Prose."))),
  list(id = "control: own engine: markdown with an r chunk", want = "filter", new = FALSE,
       files = list(doc.qmd = c(ifm_fm("engine: markdown"), "", "```{r}", "x <- 1", "```"))),
  list(id = "I6: line-1 include of engine: knitr", want = "knitr", new = TRUE,
       files = list(doc.qmd = c(IFM_INC, "", "Prose."), inc.qmd = c(IFM_ENG_KNITR, "Inc."))),
  list(id = "I6: line-1 quoted include of engine: knitr", want = "knitr", new = TRUE,
       files = list(doc.qmd = c(IFM_INCQ, "", "Prose."), inc.qmd = c(IFM_ENG_KNITR, "Inc."))),
  list(id = "I6: line-1 include of engine: markdown beats an r chunk", want = "filter", new = TRUE,
       files = list(doc.qmd = c(IFM_INC, "", "```{r}", "x <- 1", "```"), inc.qmd = c(IFM_ENG_MD, "Inc."))),
  list(id = "I6: nested line-1 include of engine: knitr", want = "knitr", new = TRUE,
       files = list(doc.qmd = c("{{< include one.qmd >}}", "", "Prose."),
                    one.qmd = c("{{< include two.qmd >}}", "", "One."), two.qmd = c(IFM_ENG_KNITR, "Two."))),
  list(id = "I6: the included first block beats a later own engine: key", want = "knitr", new = TRUE,
       files = list(doc.qmd = c(IFM_INC, "", ifm_fm("engine: markdown"), "", "Prose."),
                    inc.qmd = c(IFM_ENG_KNITR, "Inc."))),
  list(id = "I7: the same include after the own first block does not pick knitr", want = "filter", new = FALSE,
       files = list(doc.qmd = c(ifm_fm("title: T"), "", IFM_INC, "", "Prose."), inc.qmd = c(IFM_ENG_KNITR, "Inc."))),
  list(id = "I7: the same include after text does not pick knitr", want = "filter", new = FALSE,
       files = list(doc.qmd = c("Intro.", "", IFM_INC, "", "Prose."), inc.qmd = c(IFM_ENG_KNITR, "Inc."))),
  list(id = "I7: a mid-document include of engine: markdown does not stop an r chunk", want = "knitr", new = FALSE,
       files = list(doc.qmd = c("Intro.", "", IFM_INC, "", "```{r}", "x <- 1", "```"),
                    inc.qmd = c(IFM_ENG_MD, "Inc."))),
  list(id = "I6: a missing line-1 include does not crash (no engine, an r chunk: knitr)", want = "knitr", new = FALSE,
       files = list(doc.qmd = c("{{< include nope.qmd >}}", "", "```{r}", "x <- 1", "```")))
)

IFM_LUA_KN <- '
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

test_that("I6 + I7 + P4 (Lua): config.source_is_knitr follows an include on line 1 and no other", {
  skip_if_no_lua_pandoc()
  base <- normalizePath(withr::local_tempdir(), winslash = "/")
  dirs <- vapply(seq_along(IFM_KN), function(i) {
    for (nm in names(IFM_KN[[i]]$files)) f3_write(file.path(base, i, nm), IFM_KN[[i]]$files[[nm]])
    file.path(base, i)
  }, "")
  script <- file.path(base, "driver.lua")
  writeLines(IFM_LUA_KN, script)
  lib <- file.path(dirname(filter_path("weft.lua")), "weftlib")
  res <- lua_run(script, c(lib, dirs))
  got <- strsplit(res$stdout, "\n", fixed = TRUE)[[1]]
  expect_identical(length(got), length(IFM_KN), label = paste("one line per case;", res$stderr))
  if (length(got) != length(IFM_KN)) return(invisible())
  for (i in seq_along(IFM_KN)) expect_identical(got[[i]], IFM_KN[[i]]$want, label = IFM_KN[[i]]$id)
})
