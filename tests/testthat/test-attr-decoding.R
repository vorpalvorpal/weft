# One decoding of an attribute value for every reader (rules 1.2.2 and 1.2.3, as the knit's scanner
# reads them), and a key matched only as a whole attribute name. Ruling (Robin): in a quoted value
# `\"`, `\'` and `\|` are the character, `\ ` (backslash space) is a space, and a line break (with the
# content indent that follows it in a list item) reads as one space; `file=` never matches
# `profile="a"` or `datafile="a"`. Three readers outside the knit's scanner are held to it here:
#   A  the `file=` of a `.weft-values` block, read by the named-value lints. Seen through
#      named-unpublished (N144, as test-simplify-regressions.R part B): a key of a values file the
#      document reads is a publication. Each test has a decoy values file that a wrong reading would
#      read instead, so a wrong reading names a different name. A fenced block's attributes sit on its
#      opening line, so a value broken over a line (item 2) cannot occur here and is not tested.
#   B  the `cite=` of a cite span, read by the cite-key lint (L29, rule 5.4.1): the keys it flags.
#   C  the governor keys `n=`, `if=`, `sign=`, `list=`, read by weft:::values_source_names() (N45,
#      rule 3.8.7): the names a document names.
# Each part opens with a control that reads a plain value.
# Helpers: helper-3.R (lint_fixture, lf_by_rule), helper-3d.R (f3d_doc, f3d_run, expect_texts,
# F3D_BIBTEX), helper-6d.R (w6d_doc, W6D_E70), helper-6b.R (b6_write_doc). ASCII only; every project
# is a temporary folder.

# ---- A: the file= of a .weft-values block (named-value lints) ---------------------------------------

AD_BODY <- "The depth is `depth`{.num} and the width `width`{.num}."
ad_vals <- function(name) sprintf("{\"weft\":1,\"values\":{\"%s\":{\"t\":\"float\",\"v\":\"1.5\"}}}", name)
# a values block whose opening line holds `attrs`, and an empty body
ad_block <- function(attrs) c(paste0("````{.weft-values ", attrs, "}"), "````")

# the names named-unpublished reports for main.qmd, of depth and width, in a project holding `files`
ad_unpublished <- function(files, env = parent.frame()) {
  x <- lint_fixture(files, rules = NULL, tier = 1:2, env = env)
  x <- lf_by_rule(x, "named-unpublished")
  x <- x[x$file == "main.qmd", , drop = FALSE]
  c("depth", "width")[c(W6D_E70("depth"), W6D_E70("width")) %in% x$message]
}
ad_main <- function(attrs) w6d_doc(c(AD_BODY, "", ad_block(attrs)))

test_that("A control: a plain file=\"vals.json\" is read", {
  files <- list("main.qmd" = ad_main("file=\"vals.json\""), "vals.json" = ad_vals("depth"))
  expect_identical(ad_unpublished(files), "width")
})

test_that("A, 1.2.3: `\\ ` in a file= value is a space: my\\ vals.json reads `my vals.json`", {
  files <- list("main.qmd" = ad_main(r"{file="my\ vals.json"}"),
                "my vals.json" = ad_vals("depth"),      # the file the value names
                "my\\ vals.json" = ad_vals("width"))    # decoy: the name with the backslash kept
  expect_identical(ad_unpublished(files), "width")
})

test_that("A, 1.2.3: `\\ ` at the start of a file= value is a leading space, not a backslash", {
  # a values file whose name starts with a space; the decoy keeps the backslash
  files <- list("main.qmd" = ad_main(r"{file="sub/\ v.json"}"),
                "sub/ v.json" = ad_vals("depth"),
                "sub/\\ v.json" = ad_vals("width"))
  expect_identical(ad_unpublished(files), "width")
})

test_that("A, whole name: profile=\"vals.json\" alone is not a file=, so no values file is read", {
  files <- list("main.qmd" = ad_main("profile=\"vals.json\""), "vals.json" = ad_vals("depth"))
  expect_identical(ad_unpublished(files), c("depth", "width"))
})

test_that("A, whole name: datafile= and data-file= are not file= either", {
  for (k in c("datafile", "data-file")) {
    files <- list("main.qmd" = ad_main(sprintf("%s=\"vals.json\"", k)), "vals.json" = ad_vals("depth"))
    expect_identical(ad_unpublished(files), c("depth", "width"), info = k)
  }
})

test_that("A, whole name: the real file= beside a longer name ending in file is the one read", {
  for (k in c("profile", "datafile")) {
    files <- list("main.qmd" = ad_main(sprintf("%s=\"decoy.json\" file=\"vals.json\"", k)),
                  "vals.json" = ad_vals("depth"),
                  "decoy.json" = ad_vals("width"))
    expect_identical(ad_unpublished(files), "width", info = k)
  }
})

# ---- B: the cite= of a cite span (cite-key, L29) ----------------------------------------------------

# the keys cite-key flags in a document with `body` and refs.bib (smith2020, doe:2018, real2001) beside it
ad_cite <- function(body, ext = "qmd", env = parent.frame()) {
  files <- stats::setNames(list(f3d_doc(body, "bibliography: refs.bib"), F3D_BIBTEX),
                           c(paste0("doc.", ext), "refs.bib"))
  f3d_run(files, "cite-key", env = env)
}

test_that("B control: cite-key flags the key of a plain cite= value not in the bibliography", {
  for (ext in c("qmd", "Rmd")) {
    expect_texts(ad_cite(r"{A [10 m]{cite="smith2020; ghost2001"} depth.}", ext), "cite-key", "ghost2001")
  }
})

test_that("B, 1.2.3: `\\ ` in a cite= value is a space, so the key after it is the bare key", {
  for (ext in c("qmd", "Rmd")) {
    expect_texts(ad_cite(r"{A [10 m]{cite="smith2020;\ ghost2001"} depth.}", ext), "cite-key", "ghost2001")
    expect_texts(ad_cite(r"{A [10 m]{cite="see\ @ghost2001"} depth.}", ext), "cite-key", "ghost2001")
  }
})

test_that("B, 1.2.3: a cite= value broken over a line reads with one space at the break", {
  for (ext in c("qmd", "Rmd")) {
    # in a paragraph
    expect_texts(ad_cite(c(r"{A [10 m]{cite="smith2020;}", r"{ghost2001"} depth.}"), ext),
                 "cite-key", "ghost2001")
    # in a list item, the item's content indent after the break is dropped
    expect_texts(ad_cite(c(r"{- A [10 m]{cite="ghost1;}", r"{  ghost2"} depth.}"), ext),
                 "cite-key", c("ghost1", "ghost2"))
  }
})

test_that("B, whole name: xcite= or data-cite= is not a cite span, and its keys are not read", {
  for (ext in c("qmd", "Rmd")) {
    expect_texts(ad_cite(r"{A [10 m]{xcite="ghost1"} and [3 m]{data-cite="ghost2"} depth.}", ext),
                 "cite-key", character())
  }
})

test_that("B, whole name: the real cite= beside a longer name ending in cite is the one read", {
  for (ext in c("qmd", "Rmd")) {
    expect_texts(ad_cite(r"{A [10 m]{xcite="ghost1" cite="ghost2"} depth.}", ext), "cite-key", "ghost2")
    expect_texts(ad_cite(r"{A [10 m]{xcite="ghost1" cite="smith2020"} depth.}", ext), "cite-key",
                 character())
  }
})

# ---- C: the governor keys n=, if=, sign=, list= (values_source_names, N45) --------------------------

ad_names <- function(lines, env = parent.frame()) {
  sort(weft:::values_source_names(b6_write_doc(lines, dir = withr::local_tempdir(.local_envir = env))))
}

test_that("C control: plain governor values are read", {
  got <- ad_names(c("A [one | many]{n=\"k\"} and [a | b]{if=\"flag > lim\"}.",
                    "A [c | d]{sign=\"s\"} and [lst]{list=\"items\"}."))
  expect_identical(got, sort(c("k", "flag", "lim", "s", "items")))
})

test_that("C, 1.2.3: `\\ ` in a governor value is a space", {
  got <- ad_names(c(r"{A [a | b]{if="cmp >\ other"}.}",
                    r"{A [one | many]{n="\ k"} and [lst]{list="\ items"}.}"))
  expect_identical(got, sort(c("cmp", "other", "k", "items")))
})

test_that("C, 1.2.3: `\\\"` and `\\'` in a governor value are the quote, and the string they make is no name", {
  got <- ad_names(c(r"{A [a | b]{if="tier == \"sev\" || late"}.}",
                    r"{A [c | d]{if='site == \'north\' || ok'}.}"))
  expect_identical(got, sort(c("tier", "late", "site", "ok")))
})

test_that("C, 1.2.3: a governor value broken over a line reads with one space at the break", {
  got <- ad_names(c(r"{A [a | b]{if="cmp >}", r"{other"}.}",
                    "",
                    r"{- An item [c | d]{if="site == 'north}", r"{  south' || ok"}.}"))
  expect_identical(got, sort(c("cmp", "other", "site", "ok")))
})

test_that("C, whole name: xn=, data-if=, design= and checklist= are not governors", {
  got <- ad_names(c(r"{A [one | many]{xn="k1"} and [a | b]{data-if="flag1"}.}",
                    r"{A [c | d]{design="s1"} and [lst]{checklist="items1"}.}",
                    r"{A `real`{.num}.}"))
  expect_identical(got, "real")
})

test_that("C, whole name: the real governor beside a longer name ending in it is the one read", {
  got <- ad_names(c(r"{A [one | many]{xn="k1" n="k"} and [a | b]{data-if="flag1" if="flag"}.}",
                    r"{A [c | d]{design="s1" sign="s"} and [lst]{checklist="items1" list="items"}.}"))
  expect_identical(got, sort(c("k", "flag", "s", "items")))
})
