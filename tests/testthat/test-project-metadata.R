# Stage 1 of dev/quarto-project-metadata.md: rules P1, P2, P3, P8 and P9, for the R lints.
#   P1  Quarto's layers for Quarto's keys (_quarto.yml, profiles, _quarto.yml.local, each folder's
#       _metadata.yml from below the root down, the document); findings A1 to A4, D1 to D7, F1, F2.
#   P2  deep merge across files, no merge within a document; findings B1, F3.
#   P3  `weft:` is read from _weft.yml and the document only; rule 5.8.8's config-place lint flags it
#       in every other Quarto project file and under `format: <fmt>:`.
#   P8  an .Rmd with no _quarto.yml above it has no layers.
#   P9  profiles in the lints: QUARTO_PROFILE, else `profile: default` in _quarto.yml.local or _quarto.yml.
# The surfaces: `lang` through the claim-word lint (English "All 3 sites rose." gives "all, rose", any
# other language gives nothing); the cache level through tar-cache; `bibliography` through citation-key;
# misplaced `weft:` through config-place.

# ---- helpers ---------------------------------------------------------------------------------------

PM_CLAIM <- "All 3 sites rose."
PM_ENGLISH <- "all, rose"
PM_CHUNK <- c("```{r}", "x <- tar_read(fit)", "```")
PM_CACHE_DOC <- c("Some prose before.", "", PM_CHUNK, "", "Some prose after.")
PM_QUARTO <- c("project:", "  type: default")

# run `rules` over `files` with QUARTO_PROFILE set to `profile` (NA: unset), and return the findings
pm_run <- function(files, rules, profile = NA_character_, env = parent.frame()) {
  withr::local_envvar(c(QUARTO_PROFILE = profile))
  lint_fixture(files, rules = rules, env = env)
}

# the claim-word texts of the document `doc` (English: "all, rose"; another language: none)
pm_lang <- function(files, doc, profile = NA_character_, env = parent.frame()) {
  x <- pm_run(files, "claim-word", profile, env)
  x$text[x$rule == "claim-word" & x$file == doc]
}

# the tar-cache texts of the document `doc` ("fit" when the chunk counts as cached)
pm_cache <- function(files, doc, profile = NA_character_, env = parent.frame()) {
  x <- pm_run(files, "tar-cache", profile, env)
  x$text[x$rule == "tar-cache" & x$file == doc]
}

# the citation-key texts of the document `doc`
pm_cite <- function(files, doc, env = parent.frame()) {
  x <- pm_run(files, "citation-key", NA_character_, env)
  sort(x$text[x$rule == "citation-key" & x$file == doc])
}

pm_cfg_place <- function(files, profile = NA_character_, env = parent.frame()) {
  x <- pm_run(files, "config-place", profile, env)
  x[x$rule == "config-place", , drop = FALSE]
}

# ---- P1: the nested _metadata.yml, nearest wins (A1, A2, A3, A4) ------------------------------------

test_that("P1 A1: the root _metadata.yml does not count for a document in a subfolder (cache)", {
  files <- list("_quarto.yml" = PM_QUARTO, "_metadata.yml" = c("execute:", "  cache: true"),
                "sub/a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, "sub/a.qmd"), character())
})

test_that("P1 A1: the root _metadata.yml does not count for a document in a subfolder (lang)", {
  files <- list("_quarto.yml" = PM_QUARTO, "_metadata.yml" = "lang: de", "sub/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "sub/a.qmd"), PM_ENGLISH)
})

test_that("P1 A1: the root _metadata.yml does not count for a document in a subfolder (bibliography)", {
  files <- list("_quarto.yml" = PM_QUARTO, "_metadata.yml" = "bibliography: refs.bib",
                "refs.bib" = F3D_BIBTEX, "sub/a.qmd" = "Known @smith2020.\n")
  expect_identical(pm_cite(files, "sub/a.qmd"), "smith2020")
})

test_that("P1 A2: the root _metadata.yml counts for a document in the root, over _quarto.yml (cache)", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "execute:", "  cache: false"),
                "_metadata.yml" = c("execute:", "  cache: true"), "a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, "a.qmd"), "fit")
})

test_that("P1 A2: the root _metadata.yml counts for a document in the root, over _quarto.yml (lang)", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "lang: en"), "_metadata.yml" = "lang: de", "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd"), character())
})

test_that("P1 A2: a root _metadata.yml bibliography counts for a document in the root", {
  files <- list("_quarto.yml" = PM_QUARTO, "_metadata.yml" = "bibliography: refs.bib",
                "refs.bib" = F3D_BIBTEX, "a.qmd" = "Known @smith2020 and @ghost2001.\n")
  expect_identical(pm_cite(files, "a.qmd"), "ghost2001")
})

test_that("P1 A3: every folder below the root is read and the nearest wins (cache, .yaml too)", {
  doc <- "s1/s2/s3/a.qmd"
  # s1 says cache, the nearest (.yaml) says not: no finding
  files <- list("_quarto.yml" = PM_QUARTO, "s1/_metadata.yml" = c("execute:", "  cache: true"),
                "s1/s2/s3/_metadata.yaml" = c("execute:", "  cache: false"), "s1/s2/s3/a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, doc), character())
  # s1 says not, the nearest says cache: a finding
  files <- list("_quarto.yml" = PM_QUARTO, "s1/_metadata.yml" = c("execute:", "  cache: false"),
                "s1/s2/s3/_metadata.yaml" = c("execute:", "  cache: true"), "s1/s2/s3/a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, doc), "fit")
  # a folder in between is read too
  files <- list("_quarto.yml" = PM_QUARTO, "s1/s2/_metadata.yml" = c("execute:", "  cache: true"),
                "s1/s2/s3/a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, doc), "fit")
})

test_that("P1 A3: every folder below the root is read and the nearest wins (lang)", {
  doc <- "s1/s2/s3/a.qmd"
  files <- list("_quarto.yml" = PM_QUARTO, "s1/_metadata.yml" = "lang: en",
                "s1/s2/s3/_metadata.yaml" = "lang: de", "s1/s2/s3/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, doc), character())
  files <- list("_quarto.yml" = PM_QUARTO, "s1/_metadata.yml" = "lang: de",
                "s1/s2/s3/_metadata.yaml" = "lang: en", "s1/s2/s3/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, doc), PM_ENGLISH)
  # an outer folder's alone applies
  files <- list("_quarto.yml" = PM_QUARTO, "s1/_metadata.yml" = "lang: de", "s1/s2/s3/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, doc), character())
})

test_that("P1 A3: a document's own front matter beats every _metadata.yml", {
  files <- list("_quarto.yml" = PM_QUARTO, "s1/_metadata.yml" = "lang: de",
                "s1/a.qmd" = c("---", "lang: en", "---", "", PM_CLAIM))
  expect_identical(pm_lang(files, "s1/a.qmd"), PM_ENGLISH)
})

test_that("P1 A4: with no _quarto.yml the document's own folder's _metadata.yml counts (cache)", {
  files <- list("sub/_metadata.yml" = c("execute:", "  cache: true"), "sub/a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, "sub/a.qmd"), "fit")
})

test_that("P1 A4: with no _quarto.yml the document's own folder's _metadata.yml counts (lang)", {
  files <- list("sub/_metadata.yml" = "lang: de", "sub/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "sub/a.qmd"), character())
  # and with the lone document in the project folder itself
  files <- list("_metadata.yml" = "lang: de", "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd"), character())
})

test_that("P1 A4: with no _quarto.yml only the document's own folder counts, not its parent", {
  files <- list("_metadata.yml" = "lang: de", "sub/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "sub/a.qmd"), PM_ENGLISH)
})

# ---- P1: one spelling per folder, .yml before .yaml ---------------------------------------------------

test_that("P1: with both _metadata.yml and _metadata.yaml in a folder only the .yml is read (cache)", {
  files <- list("_quarto.yml" = PM_QUARTO, "sub/_metadata.yml" = c("execute:", "  cache: true"),
                "sub/_metadata.yaml" = c("execute:", "  cache: false"), "sub/a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, "sub/a.qmd"), "fit")
  files <- list("_quarto.yml" = PM_QUARTO, "sub/_metadata.yml" = c("execute:", "  cache: false"),
                "sub/_metadata.yaml" = c("execute:", "  cache: true"), "sub/a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, "sub/a.qmd"), character())
})

test_that("P1: with both spellings in a folder only the .yml is read (lang); a lone .yaml is read", {
  files <- list("_quarto.yml" = PM_QUARTO, "sub/_metadata.yml" = "lang: en", "sub/_metadata.yaml" = "lang: de",
                "sub/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "sub/a.qmd"), PM_ENGLISH)
  files <- list("_quarto.yml" = PM_QUARTO, "sub/_metadata.yaml" = "lang: de", "sub/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "sub/a.qmd"), character())
})

# ---- P1, P9: profiles, _quarto.yml.local ------------------------------------------------------------

test_that("P9 D1: an active profile's _quarto-<name>.yml is over _quarto.yml (QUARTO_PROFILE)", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "lang: en"), "_quarto-p1.yml" = "lang: de", "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd", profile = "p1"), character())
  # no profile active: the profile file is ignored
  expect_identical(pm_lang(files, "a.qmd"), PM_ENGLISH)
  # another profile active: ignored too
  expect_identical(pm_lang(files, "a.qmd", profile = "p2"), PM_ENGLISH)
})

test_that("P9 D1: a profile's .yaml spelling works, and its execute: cache counts", {
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto-p1.yaml" = c("execute:", "  cache: true"), "a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, "a.qmd", profile = "p1"), "fit")
  expect_identical(pm_cache(files, "a.qmd"), character())
})

test_that("P9 D2: a profile is under _metadata.yml", {
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto-p1.yml" = "lang: en", "_metadata.yml" = "lang: de",
                "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd", profile = "p1"), character())
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto-p1.yml" = "lang: de", "_metadata.yml" = "lang: en",
                "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd", profile = "p1"), PM_ENGLISH)
})

test_that("P9 D3: with two profiles named the first named wins", {
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto-p1.yml" = "lang: de", "_quarto-p2.yml" = "lang: en",
                "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd", profile = "p1,p2"), character())
  expect_identical(pm_lang(files, "a.qmd", profile = "p2,p1"), PM_ENGLISH)
  # a key only the later profile sets still applies
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto-p1.yml" = "title: T", "_quarto-p2.yml" = "lang: de",
                "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd", profile = "p1,p2"), character())
})

test_that("P9 D4: `profile: default` in _quarto.yml activates a profile when QUARTO_PROFILE is unset", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "profile:", "  default: p1"), "_quarto-p1.yml" = "lang: de",
                "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd"), character())
  # QUARTO_PROFILE wins over the default
  files[["_quarto-p2.yml"]] <- "lang: en"
  expect_identical(pm_lang(files, "a.qmd", profile = "p2"), PM_ENGLISH)
})

test_that("P9 D4: `profile: default` in _quarto.yml.local activates a profile too", {
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto.yml.local" = c("profile:", "  default: p1"),
                "_quarto-p1.yml" = "lang: de", "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd"), character())
})

test_that("P1 D5: _quarto.yml.local is over _quarto.yml and over the profiles, under _metadata.yml", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "lang: en"), "_quarto.yml.local" = "lang: de", "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd"), character())
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto-p1.yml" = "lang: en", "_quarto.yml.local" = "lang: de",
                "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd", profile = "p1"), character())
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto.yml.local" = "lang: de", "_metadata.yml" = "lang: en",
                "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd"), PM_ENGLISH)
})

test_that("P1 D5: a misnamed _quarto.local.yml is ignored", {
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto.local.yml" = "lang: de", "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd"), PM_ENGLISH)
})

test_that("P1 D6: _metadata-p1.yml is ignored", {
  files <- list("_quarto.yml" = PM_QUARTO, "_metadata-p1.yml" = "lang: de", "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd", profile = "p1"), PM_ENGLISH)
})

# ---- P1: format: html: <key> beats <key> in one file (F1, F2) ---------------------------------------------

test_that("P1 F1: in _quarto.yml `format: html: lang` beats the top-level lang", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "lang: de", "format:", "  html:", "    lang: en"), "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd"), PM_ENGLISH)
  files <- list("_quarto.yml" = c(PM_QUARTO, "lang: en", "format:", "  html:", "    lang: de"), "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd"), character())
})

test_that("P1 F1: in a document `format: html: lang` beats the top-level lang", {
  front <- c("---", "lang: de", "format:", "  html:", "    lang: en", "---", "")
  expect_identical(pm_lang(list("a.qmd" = c(front, PM_CLAIM)), "a.qmd"), PM_ENGLISH)
  front <- c("---", "lang: en", "format:", "  html:", "    lang: de", "---", "")
  expect_identical(pm_lang(list("a.qmd" = c(front, PM_CLAIM)), "a.qmd"), character())
})

test_that("P1 F2: in a _metadata.yml `format: html: lang` beats the top-level lang", {
  files <- list("_quarto.yml" = PM_QUARTO, "sub/_metadata.yml" = c("lang: de", "format:", "  html:", "    lang: en"),
                "sub/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "sub/a.qmd"), PM_ENGLISH)
})

test_that("P1 F2: a format-scoped lang in a lower file does not beat a higher file's top-level lang", {
  # layers first: the document's top-level lang is the later layer
  files <- list("_quarto.yml" = c(PM_QUARTO, "format:", "  html:", "    lang: en"),
                "a.qmd" = c("---", "lang: de", "---", "", PM_CLAIM))
  expect_identical(pm_lang(files, "a.qmd"), character())
})

# ---- P2: deep merge across files, list concatenation, no merge within a document (B1, F3) ----------------

test_that("P2 B1: bibliographies of the project, the folder and the document combine", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "bibliography: refs.bib"),
                "sub/_metadata.yml" = "bibliography: local.bib",
                "refs.bib" = F3D_BIBTEX, "sub/local.bib" = F3D_BIBTEX2, "sub/refs.json" = F3D_CSLJSON,
                "sub/a.qmd" = f3d_doc("Known @smith2020, @other2015, @jsonkey2019 and @ghost2001.",
                                      "bibliography: refs.json"))
  expect_identical(pm_cite(files, "sub/a.qmd"), "ghost2001")
})

test_that("P2 B1: maps merge across files: a sibling key in a nearer file does not clear execute: cache", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "execute:", "  cache: true"),
                "_metadata.yml" = c("execute:", "  echo: false"), "a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, "a.qmd"), "fit")
})

test_that("P2 B1: a folder's list joins the project's list and a scalar joins a list", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "bibliography:", "  - refs.bib"),
                "sub/_metadata.yml" = c("bibliography:", "  - local.bib"),
                "refs.bib" = F3D_BIBTEX, "sub/local.bib" = F3D_BIBTEX2, "sub/refs.json" = F3D_CSLJSON,
                "sub/a.qmd" = f3d_doc("Known @smith2020, @other2015 and @jsonkey2019.",
                                      c("bibliography: refs.json")))
  expect_identical(pm_cite(files, "sub/a.qmd"), character())
})

test_that("P2 F3: within a document a later block replaces bibliography, it does not add to it", {
  doc <- c("---", "title: T", "bibliography: refs.bib", "---", "",
           "Known @smith2020, @other2015 and @ghost2001.", "",
           "---", "bibliography: other.bib", "---", "", "More words.")
  files <- list("a.qmd" = doc, "refs.bib" = F3D_BIBTEX, "other.bib" = F3D_BIBTEX2)
  expect_identical(pm_cite(files, "a.qmd"), c("ghost2001", "smith2020"))
})

test_that("P2 F3: a later block's bibliography replaces the document's own, but the project's still adds", {
  doc <- c("---", "title: T", "bibliography: refs.bib", "---", "",
           "Known @smith2020, @other2015, @jsonkey2019 and @ghost2001.", "",
           "---", "bibliography: other.bib", "---", "", "More words.")
  files <- list("_quarto.yml" = c(PM_QUARTO, "bibliography: refs.json"), "a.qmd" = doc,
                "refs.bib" = F3D_BIBTEX, "other.bib" = F3D_BIBTEX2, "refs.json" = F3D_CSLJSON)
  expect_identical(pm_cite(files, "a.qmd"), c("ghost2001", "smith2020"))
})

# ---- P3: config-place flags weft: in every Quarto project file -------------------------------------------

PM_WEFT <- c("weft:", "  claim_words:", "    add: [ratio]")

test_that("P3: weft: in _quarto.yml and _metadata.yml is still flagged (control)", {
  files <- list("_quarto.yml" = c(PM_QUARTO, PM_WEFT), "ch/_metadata.yml" = PM_WEFT, "a.qmd" = "Words.\n")
  x <- pm_cfg_place(files)
  expect_identical(sort(x$file), c("_quarto.yml", "ch/_metadata.yml"))
})

test_that("P3: weft: in _quarto-<profile>.yml is flagged, with or without the profile active", {
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto-p1.yml" = PM_WEFT, "_quarto-p2.yaml" = PM_WEFT,
                "a.qmd" = "Words.\n")
  expect_identical(sort(pm_cfg_place(files)$file), c("_quarto-p1.yml", "_quarto-p2.yaml"))
  expect_identical(sort(pm_cfg_place(files, profile = "p1")$file), c("_quarto-p1.yml", "_quarto-p2.yaml"))
})

test_that("P3: weft: in _quarto.yml.local is flagged", {
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto.yml.local" = PM_WEFT, "a.qmd" = "Words.\n")
  expect_identical(pm_cfg_place(files)$file, "_quarto.yml.local")
})

test_that("P3: weft: in a metadata-files: target named in _quarto.yml is flagged", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "metadata-files:", "  - meta/extra.yml"),
                "meta/extra.yml" = PM_WEFT, "other.yml" = PM_WEFT, "a.qmd" = "Words.\n")
  expect_identical(pm_cfg_place(files)$file, "meta/extra.yml")
})

test_that("P3: format: html: weft: is flagged in _quarto.yml, _metadata.yml, a profile and .local", {
  fmt <- c("format:", "  html:", "    weft:", "      claim_words:", "        add: [ratio]")
  files <- list("_quarto.yml" = c(PM_QUARTO, fmt), "ch/_metadata.yml" = fmt, "_quarto-p1.yml" = fmt,
                "_quarto.yml.local" = fmt, "a.qmd" = "Words.\n")
  expect_identical(sort(pm_cfg_place(files)$file),
                   sort(c("_quarto.yml", "ch/_metadata.yml", "_quarto-p1.yml", "_quarto.yml.local")))
})

test_that("P3: format: html: weft: in a document's front matter is flagged; a top-level weft: is not", {
  fmt <- c("---", "format:", "  html:", "    weft:", "      claim_words:", "        add: [ratio]", "---", "", "Words.")
  x <- pm_cfg_place(list("a.qmd" = fmt))
  expect_identical(x$file, "a.qmd")
  expect_identical(x$line, 4L)
  top <- c("---", "weft:", "  claim_words:", "    add: [ratio]", "---", "", "Words.")
  expect_identical(nrow(pm_cfg_place(list("a.qmd" = top))), 0L)
})

test_that("P3: format: html: weft: in an .Rmd's front matter is flagged too", {
  fmt <- c("---", "format:", "  html:", "    weft:", "      claim_words:", "        add: [ratio]", "---", "", "Words.")
  x <- pm_cfg_place(list("a.Rmd" = fmt))
  expect_identical(x$file, "a.Rmd")
})

test_that("P3: weft: from Quarto's project files changes no setting (a claim word added there has no effect)", {
  ratio <- "The ratio was clear."
  fmt <- c("format:", "  html:", "    weft:", "      claim_words:", "        add: [ratio]")
  cases <- list(
    `_quarto.yml` = list("_quarto.yml" = c(PM_QUARTO, PM_WEFT)),
    `_metadata.yml` = list("_quarto.yml" = PM_QUARTO, "_metadata.yml" = PM_WEFT),
    `_quarto.yml.local` = list("_quarto.yml" = PM_QUARTO, "_quarto.yml.local" = PM_WEFT),
    `metadata-files` = list("_quarto.yml" = c(PM_QUARTO, "metadata-files:", "  - extra.yml"), "extra.yml" = PM_WEFT),
    `format: html: weft:` = list("_quarto.yml" = c(PM_QUARTO, fmt)))
  for (nm in names(cases)) {
    files <- c(cases[[nm]], list("a.qmd" = ratio))
    x <- pm_run(files, "claim-word")
    expect_identical(x$text[x$rule == "claim-word"], character(), label = nm)
  }
})

test_that("P3: weft: in a profile file changes no setting, with the profile active", {
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto-p1.yml" = PM_WEFT, "a.qmd" = "The ratio was clear.")
  x <- pm_run(files, "claim-word", profile = "p1")
  expect_identical(x$text[x$rule == "claim-word"], character())
})

test_that("P3: weft: format: html: weft: in a document changes no setting; a top-level weft: does (control)", {
  fmt <- c("---", "format:", "  html:", "    weft:", "      claim_words:", "        add: [ratio]", "---", "",
           "The ratio was clear.")
  x <- pm_run(list("a.qmd" = fmt), "claim-word")
  expect_identical(x$text[x$rule == "claim-word"], character())
  top <- c("---", "weft:", "  claim_words:", "    add: [ratio]", "---", "", "The ratio was clear.")
  x <- pm_run(list("a.qmd" = top), "claim-word")
  expect_identical(x$text[x$rule == "claim-word"], "ratio")
})

# ---- P8: an .Rmd has layers only under a _quarto.yml -------------------------------------------------------

test_that("P8: an .Rmd with no _quarto.yml above it ignores _metadata.yml (cache)", {
  files <- list("sub/_metadata.yml" = c("execute:", "  cache: true"), "sub/a.Rmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, "sub/a.Rmd"), character())
  # the .qmd control reads it (A4)
  files <- list("sub/_metadata.yml" = c("execute:", "  cache: true"), "sub/a.qmd" = PM_CACHE_DOC)
  expect_identical(pm_cache(files, "sub/a.qmd"), "fit")
})

test_that("P8: an .Rmd with no _quarto.yml above it ignores _metadata.yml (lang)", {
  files <- list("sub/_metadata.yml" = "lang: de", "sub/a.Rmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "sub/a.Rmd"), PM_ENGLISH)
  files <- list("_metadata.yml" = "lang: de", "a.Rmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.Rmd"), PM_ENGLISH)
})

test_that("P8: an .Rmd with no _quarto.yml above it ignores _quarto.yml-style files", {
  files <- list("_quarto.yml.local" = "lang: de", "a.Rmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.Rmd"), PM_ENGLISH)
  files <- list("_quarto-p1.yml" = "lang: de", "a.Rmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.Rmd", profile = "p1"), PM_ENGLISH)
})

test_that("P8: an .Rmd with no _quarto.yml still reads its own front matter", {
  files <- list("_metadata.yml" = "lang: en", "a.Rmd" = c("---", "lang: de", "---", "", PM_CLAIM))
  expect_identical(pm_lang(files, "a.Rmd"), character())
})

test_that("P8: an .Rmd under a _quarto.yml gets the layers (lang), as a .qmd does", {
  for (ext in c("Rmd", "qmd")) {
    doc <- paste0("sub/a.", ext)
    files <- stats::setNames(list(PM_QUARTO, "lang: de", PM_CLAIM), c("_quarto.yml", "sub/_metadata.yml", doc))
    expect_identical(pm_lang(files, doc), character(), label = ext)
  }
})

test_that("P8: an .Rmd under a _quarto.yml gets the layers (cache), as a .qmd does", {
  for (ext in c("Rmd", "qmd")) {
    doc <- paste0("sub/a.", ext)
    files <- stats::setNames(list(PM_QUARTO, c("execute:", "  cache: true"), PM_CACHE_DOC),
                             c("_quarto.yml", "sub/_metadata.yml", doc))
    expect_identical(pm_cache(files, doc), "fit", label = ext)
  }
})

test_that("P8: an .Rmd under a _quarto.yml gets profiles and the local file", {
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto-p1.yml" = "lang: de", "a.Rmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.Rmd", profile = "p1"), character())
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto.yml.local" = "lang: de", "a.Rmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.Rmd"), character())
})

# ---- the disagreement found: lang from _metadata.yml and profiles, as the knit does --------------------------

test_that("P1 lang: the lints take lang from a folder's _metadata.yml, as the knit does", {
  files <- list("_quarto.yml" = PM_QUARTO, "sub/_metadata.yml" = "lang: de", "sub/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "sub/a.qmd"), character())
})

test_that("P1 lang: the lints take lang from a profile, as the knit does", {
  files <- list("_quarto.yml" = PM_QUARTO, "_quarto-p1.yml" = "lang: de", "a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "a.qmd", profile = "p1"), character())
})

test_that("P1 lang: _quarto.yml's lang still applies when nothing nearer sets one (control)", {
  files <- list("_quarto.yml" = c(PM_QUARTO, "lang: de"), "sub/_metadata.yml" = "title: T", "sub/a.qmd" = PM_CLAIM)
  expect_identical(pm_lang(files, "sub/a.qmd"), character())
})
