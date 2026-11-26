# weft follows `{{< include >}}` the way Quarto expands it (the include rules I1 to I7, ruled on
# 2026-11-26 from experiments on Quarto 1.11.9). Every place that follows includes is held to the same
# rules, each through its cheapest observable:
#
#   scan     weft:::values_source_names(): the names R publishes for (N45)
#   python   weft._source_names(): the Python twin of that scan (3.8.7)
#   filter   the Lua filter's include map: the `files` of its ledger header (N112), and the file and
#            line it gives a construct (N89, 2.13.6)
#   targets  weft:::report_reads(): the dictionary keys a report reads (4.6.5)
#   named    the lint named-unpublished: a chunk of an included file publishes (N144)
#   doclint  the lint engine (L34): a document another includes is not alone
#   knit     a failure's file and line in a Quarto render (2.7.4); two renders in all
#
# The rules pinned here:
#   I1  a line is an include only when the whole line is `{{< include PATH >}}`, with exactly one space
#       inside each bracket; leading and trailing white space is allowed. Text before or after, a list
#       marker, `> `, a code span, a one-line HTML comment, the escaped `{{</* include x */>}}` and
#       `{{<include x>}}` are not includes.
#   I2  the name is exact lowercase `include` in the main document; in an included file any case.
#   I3  the path is the first parameter: "..." or '...' (a space allowed), or a bare run.
#   I4  every path, at any depth, resolves against the MAIN document's folder, never the including
#       file's; a leading / against the Quarto project root (the folder of _quarto.yml), else the main
#       document's folder.
#   I5  a line inside a plain fence (``` or ~~~) or a multi-line HTML comment counts; a line inside a
#       ```{shortcodes=false} block does not.
#   I6  a cycle among included files terminates; there is no depth limit.
#
# READING TAKEN (see the report): an include inside an executable cell. The ruling says a line inside a
# ```{r} cell does not count, but Quarto 1.11.9 expands it: processMarkdownIncludes() (quarto.js 76225)
# skips only a cell holding ```{shortcodes=false}, and a knitr render of
#     ```{r}
#     #| eval: false
#     {{< include x.qmd >}}
#     ```
# echoes the text of x.qmd. These tests follow Quarto: the include in an {r} cell is followed. The cases
# are named `cell_r`, so that the reading is easy to turn round.
#
# ASCII only. Made-up content. No test writes outside a temporary folder.

# results made once and read by several tests (the Python run, the two Quarto renders)
.ir <- new.env()

# ---- the cases ---------------------------------------------------------------------------------------

# The name a file carries in the scans: n_ and its path without the extension, made an identifier.
ir_nm <- function(path) paste0("n_", gsub("[^A-Za-z0-9]+", "_", sub("\\.[^./]*$", "", path)))

# A case: `main` is the main document's project-relative path; `files` maps every file (the main too) to
# its include lines (the lines that make the structure; the content each site needs is added around
# them); `follow` are the files Quarto expands, `skip` the files it does not; `project` writes a
# _quarto.yml at the root. `cell` marks a case whose include sits in a code cell or fence, whose content
# makes no sense to some sites (they leave it out).
ir_case <- function(rule, main, files, follow, skip = character(), project = FALSE, cell = FALSE) {
  list(rule = rule, main = main, files = files, follow = follow, skip = skip, project = project,
       cell = cell)
}

inc <- function(path) sprintf("{{< include %s >}}", path)

# I1: lines that are not includes, each naming t.qmd (a file that exists)
IR_NOT_INCLUDES <- c(
  text_before    = "Text before {{< include t.qmd >}}",
  text_after     = "{{< include t.qmd >}} and text after",
  list_item      = "- {{< include t.qmd >}}",
  numbered_item  = "1. {{< include t.qmd >}}",
  block_quote    = "> {{< include t.qmd >}}",
  code_span      = "`{{< include t.qmd >}}`",
  inline_comment = "<!-- {{< include t.qmd >}} -->",
  escaped        = "{{</* include t.qmd */>}}",
  no_spaces      = "{{<include t.qmd>}}",
  no_space_after = "{{<include t.qmd >}}",
  no_space_end   = "{{< include t.qmd>}}"
)

ir_cases <- function() {
  chain <- sprintf("c%02d.qmd", 1:12)
  chain_files <- stats::setNames(lapply(seq_along(chain), function(i) {
    if (i < length(chain)) inc(chain[i + 1L]) else character()
  }), chain)
  cases <- list(
    # I4: a nested include resolves against the main document's folder
    I4_nested = ir_case("I4", "doc.qmd",
      list("doc.qmd" = inc("sub/one.qmd"), "sub/one.qmd" = inc("two.qmd"),
           "two.qmd" = character(), "sub/two.qmd" = character()),
      follow = c("sub/one.qmd", "two.qmd"), skip = "sub/two.qmd"),
    I4_nested_main_in_folder = ir_case("I4", "docs/doc.qmd",
      list("docs/doc.qmd" = inc("inc/a.qmd"), "docs/inc/a.qmd" = inc("b.qmd"),
           "docs/b.qmd" = character(), "docs/inc/b.qmd" = character()),
      follow = c("docs/inc/a.qmd", "docs/b.qmd"), skip = "docs/inc/b.qmd"),
    I4_dotdot = ir_case("I4", "docs/doc.qmd",
      list("docs/doc.qmd" = inc("inc/a.qmd"), "docs/inc/a.qmd" = inc("../x.qmd"),
           "x.qmd" = character(), "docs/x.qmd" = character()),
      follow = c("docs/inc/a.qmd", "x.qmd"), skip = "docs/x.qmd"),
    I4_slash_project = ir_case("I4", "docs/doc.qmd",
      list("docs/doc.qmd" = inc("/shared/x.qmd"),
           "shared/x.qmd" = character(), "docs/shared/x.qmd" = character()),
      follow = "shared/x.qmd", skip = "docs/shared/x.qmd", project = TRUE),
    I4_slash_project_nested = ir_case("I4", "docs/doc.qmd",
      list("docs/doc.qmd" = inc("inc/a.qmd"), "docs/inc/a.qmd" = inc("/shared/x.qmd"),
           "shared/x.qmd" = character(), "docs/shared/x.qmd" = character()),
      follow = c("docs/inc/a.qmd", "shared/x.qmd"), skip = "docs/shared/x.qmd", project = TRUE),
    I4_slash_no_project = ir_case("I4", "docs/doc.qmd",
      list("docs/doc.qmd" = inc("/shared/x.qmd"),
           "shared/x.qmd" = character(), "docs/shared/x.qmd" = character()),
      follow = "docs/shared/x.qmd", skip = "shared/x.qmd"),
    # I3: the first parameter, quoted or bare
    I3_double_quoted_space = ir_case("I3", "doc.qmd",
      list("doc.qmd" = inc("\"my part.qmd\""), "my part.qmd" = character(), "my.qmd" = character()),
      follow = "my part.qmd", skip = "my.qmd"),
    I3_single_quoted_space = ir_case("I3", "doc.qmd",
      list("doc.qmd" = inc("'my other.qmd'"), "my other.qmd" = character(), "my.qmd" = character()),
      follow = "my other.qmd", skip = "my.qmd"),
    I3_nested_quoted = ir_case("I3", "doc.qmd",
      list("doc.qmd" = inc("t.qmd"), "t.qmd" = inc("\"sub/my part.qmd\""),
           "sub/my part.qmd" = character()),
      follow = c("t.qmd", "sub/my part.qmd")),
    I3_first_parameter = ir_case("I3", "doc.qmd",
      list("doc.qmd" = inc("t.qmd u.qmd"), "t.qmd" = character(), "u.qmd" = character()),
      follow = "t.qmd", skip = "u.qmd"),
    # I1: white space around the shortcode is allowed
    I1_spaces_around = ir_case("I1", "doc.qmd",
      list("doc.qmd" = c(paste0("   ", inc("t.qmd"), "   "), "", paste0("    ", inc("u.qmd"))),
           "t.qmd" = character(), "u.qmd" = character()),
      follow = c("t.qmd", "u.qmd")),
    # I2: case
    I2_upper_in_main = ir_case("I2", "doc.qmd",
      list("doc.qmd" = c("{{< INCLUDE t.qmd >}}", "", "{{< Include u.qmd >}}"),
           "t.qmd" = character(), "u.qmd" = character()),
      follow = character(), skip = c("t.qmd", "u.qmd")),
    I2_upper_in_included = ir_case("I2", "doc.qmd",
      list("doc.qmd" = inc("t.qmd"), "t.qmd" = "{{< INCLUDE u.qmd >}}", "u.qmd" = character()),
      follow = c("t.qmd", "u.qmd")),
    # I5: fences and comments count; a shortcodes=false block does not
    I5_fence_backticks = ir_case("I5", "doc.qmd",
      list("doc.qmd" = c("```", inc("t.qmd"), "```"), "t.qmd" = character()),
      follow = "t.qmd", cell = TRUE),
    I5_fence_tildes = ir_case("I5", "doc.qmd",
      list("doc.qmd" = c("~~~", inc("t.qmd"), "~~~"), "t.qmd" = character()),
      follow = "t.qmd", cell = TRUE),
    I5_fence_in_included = ir_case("I5", "doc.qmd",
      list("doc.qmd" = inc("t.qmd"), "t.qmd" = c("```", inc("u.qmd"), "```"), "u.qmd" = character()),
      follow = c("t.qmd", "u.qmd"), cell = TRUE),
    I5_comment_multiline = ir_case("I5", "doc.qmd",
      list("doc.qmd" = c("<!--", inc("t.qmd"), "-->"), "t.qmd" = character()),
      follow = "t.qmd", cell = TRUE),
    I5_shortcodes_false = ir_case("I5", "doc.qmd",
      list("doc.qmd" = c("```{shortcodes=false}", inc("t.qmd"), "```"), "t.qmd" = character()),
      follow = character(), skip = "t.qmd", cell = TRUE),
    # READING (see the head of the file): Quarto expands an include inside an {r} cell
    I5_cell_r = ir_case("I5", "doc.qmd",
      list("doc.qmd" = c("```{r}", "#| eval: false", inc("t.qmd"), "```"), "t.qmd" = character()),
      follow = "t.qmd", cell = TRUE),
    # I6: a cycle among included files ends; no depth limit
    I6_cycle = ir_case("I6", "doc.qmd",
      list("doc.qmd" = inc("a.qmd"), "a.qmd" = inc("b.qmd"), "b.qmd" = inc("a.qmd")),
      follow = c("a.qmd", "b.qmd")),
    I6_self = ir_case("I6", "doc.qmd",
      list("doc.qmd" = inc("a.qmd"), "a.qmd" = inc("a.qmd")),
      follow = "a.qmd"),
    I6_deep = ir_case("I6", "doc.qmd", c(list("doc.qmd" = inc(chain[1])), chain_files),
      follow = chain)
  )
  for (nm in names(IR_NOT_INCLUDES)) {
    cases[[paste0("I1_not_", nm)]] <- ir_case("I1", "doc.qmd",
      list("doc.qmd" = IR_NOT_INCLUDES[[nm]], "t.qmd" = character()),
      follow = character(), skip = "t.qmd")
  }
  cases
}

# Write a case into a fresh folder. `content(path, is_main, case)` gives the lines each file holds
# besides its include lines (put first, then a blank line, then the include lines). Returns the root.
ir_write <- function(case, content, root = NULL, env = parent.frame()) {
  if (is.null(root)) root <- withr::local_tempdir(.local_envir = env)
  root <- normalizePath(root, winslash = "/")
  put <- function(rel, lines) {
    p <- file.path(root, rel)
    dir.create(dirname(p), showWarnings = FALSE, recursive = TRUE)
    writeLines(lines, p, useBytes = TRUE)
  }
  if (isTRUE(case$project)) put("_quarto.yml", c("project:", "  type: default"))
  for (f in names(case$files)) {
    body <- content(f, identical(f, case$main), case)
    put(f, c(body, if (length(case$files[[f]])) c("", case$files[[f]])))
  }
  root
}

# the content of the scans: each file carries a named value of its own name
ir_scan_content <- function(path, is_main, case) sprintf("Value `%s`{.num} here.", ir_nm(path))

ir_label <- function(id, case, what) {
  sprintf("%s [%s]: %s (main %s)", id, case$rule, what, case$main)
}

# ---- scan: weft:::values_source_names() ------------------------------------------------------------

# one expectation per case: every followed file's name is read, no skipped file's name is
ir_check_scan <- function(got, id, case) {
  missing <- setdiff(ir_nm(c(case$main, case$follow)), got)
  extra <- intersect(ir_nm(case$skip), got)
  expect_true(length(missing) == 0L && length(extra) == 0L,
              label = ir_label(id, case, sprintf("names {%s}: missing {%s}, read but not included {%s}",
                                                 paste(sort(got), collapse = ", "),
                                                 paste(missing, collapse = ", "), paste(extra, collapse = ", "))))
}

ir_scan_test <- function(rule) {
  cases <- ir_cases()
  for (id in names(cases)) {
    case <- cases[[id]]
    if (!identical(case$rule, rule)) next
    root <- ir_write(case, ir_scan_content)
    got <- weft:::values_source_names(file.path(root, case$main))
    ir_check_scan(got, id, case)
  }
}

test_that("scan, I4: a nested include, `..` and a leading / resolve against the main document's folder or the project root", {
  ir_scan_test("I4")
})

test_that("scan, I3: a quoted path may hold a space, in either quotes; only the first parameter is the path", {
  ir_scan_test("I3")
})

test_that("scan, I1: only a line that is the whole shortcode, one space inside each bracket, is an include", {
  ir_scan_test("I1")
})

test_that("scan, I2: `include` is lowercase in the main document and any case in an included file", {
  ir_scan_test("I2")
})

test_that("scan, I5: a plain fence and a multi-line comment count, a shortcodes=false block does not, an {r} cell counts (reading)", {
  ir_scan_test("I5")
})

test_that("scan, I6: a cycle among included files ends; twelve levels of include are all read", {
  ir_scan_test("I6")
})

# ---- python: weft._source_names() --------------------------------------------------------------------

# weft._source_names of every case, in one Python run, made once for the tests below
ir_python <- function() {
  if (!is.null(.ir$python)) return(.ir$python)
  py <- py_exe6k()
  cases <- ir_cases()
  paths <- list()
  for (id in names(cases)) {
    root <- ir_write(cases[[id]], ir_scan_content)
    paths[[id]] <- file.path(root, cases[[id]]$main)
  }
  dir <- withr::local_tempdir()
  input <- file.path(dir, "paths.json")
  writeLines(jsonlite::toJSON(paths, auto_unbox = TRUE), input)
  script <- file.path(dir, "run.py")
  writeLines(c(
    "import sys, json",
    "import weft",
    "paths = json.load(open(sys.argv[1]))",
    "out = {}",
    "for k, p in paths.items():",
    "    try:",
    "        out[k] = sorted(weft._source_names(p))",
    "    except Exception as e:",
    "        out[k] = ['ERROR: ' + type(e).__name__ + ': ' + str(e)]",
    "print(json.dumps(out))"), script)
  out <- suppressWarnings(system2(py, c(shQuote(script), shQuote(input)),
                                  env = paste0("PYTHONPATH=", py_lib6k()), stdout = TRUE, stderr = FALSE))
  testthat::expect(length(out) >= 1L, "the Python run printed its result")
  .ir$python <- jsonlite::fromJSON(out[length(out)], simplifyVector = FALSE)
  .ir$python
}

ir_python_test <- function(rule) {
  got <- ir_python()
  cases <- ir_cases()
  for (id in names(cases)) {
    if (!identical(cases[[id]]$rule, rule)) next
    ir_check_scan(as.character(unlist(got[[id]])), paste("python", id), cases[[id]])
  }
}

test_that("python, I4: a nested include, `..` and a leading / resolve against the main document's folder or the project root", {
  ir_python_test("I4")
})

test_that("python, I3: a quoted path may hold a space, in either quotes; only the first parameter is the path", {
  ir_python_test("I3")
})

test_that("python, I1: only a line that is the whole shortcode, one space inside each bracket, is an include", {
  ir_python_test("I1")
})

test_that("python, I2: `include` is lowercase in the main document and any case in an included file", {
  ir_python_test("I2")
})

test_that("python, I5: a plain fence and a multi-line comment count, a shortcodes=false block does not, an {r} cell counts (reading)", {
  ir_python_test("I5")
})

test_that("python, I6: a cycle among included files ends; twelve levels of include are all read", {
  ir_python_test("I6")
})

# ---- filter: the include map (the ledger header's `files`) --------------------------------------------

IR_BLOCK <- g6_block(depth = fr_float("12.5"), run = "R1", at = 1794822900L)

ir_filter_content <- function(path, is_main, case) {
  if (is_main) c(IR_BLOCK, "", "Depth `depth`{.num}.") else sprintf("Text of %s.", path)
}

# the parsed header of the one ledger the run wrote, wherever it sits
ir_ledger_header <- function(res) {
  led <- grep("^_weft/ledger/.*\\.jsonl$", names(res$files), value = TRUE)
  testthat::expect(length(led) == 1L, sprintf("one ledger written (got: %s; stderr: %s)",
                                              paste(names(res$files), collapse = ", "), res$stderr))
  if (length(led) != 1L) return(NULL)
  g6_json(strsplit(res$files[[led]], "\n", fixed = TRUE)[[1]][1])
}

# The files of the header, as project-relative paths. The header's keys are relative to the project
# root or to the main document's folder; which one is read off the main document's own key.
ir_header_files <- function(h, main) {
  keys <- sub("^\\./", "", names(h$files))
  if (main %in% keys || dirname(main) == ".") return(sort(keys))
  if (basename(main) %in% keys) {
    base <- dirname(main)
    norm <- vapply(keys, function(k) {
      parts <- strsplit(file.path(base, k), "/", fixed = TRUE)[[1]]
      out <- character()
      for (p in parts) {
        if (p == "..") out <- out[-length(out)] else if (p != ".") out <- c(out, p)
      }
      paste(out, collapse = "/")
    }, "")
    return(sort(unname(norm)))
  }
  sort(keys)
}

ir_filter_test <- function(rule) {
  cases <- ir_cases()
  for (id in names(cases)) {
    case <- cases[[id]]
    if (!identical(case$rule, rule)) next
    # Quarto's project root is the folder of _quarto.yml; the filter's needs _weft.yml for the ledger,
    # so a case without a project cannot tell the two apart: those are left to the other sites
    if (identical(id, "I4_slash_no_project")) next
    files <- list()
    others <- setdiff(names(case$files), case$main)
    for (f in others) {
      files[[f]] <- c(ir_filter_content(f, FALSE, case), if (length(case$files[[f]])) c("", case$files[[f]]))
    }
    if (isTRUE(case$project)) files[["_quarto.yml"]] <- c("project:", "  type: default")
    md <- c(ir_filter_content(case$main, TRUE, case), "", case$files[[case$main]])
    run_in <- dirname(case$main)
    res <- filter_md(md, files = files, name = case$main, run_in = run_in, weft_yml = G6_YML,
                     env = c(WEFT_RUN = "R1"), to = "plain")
    expect_identical(res$status, 0L, label = ir_label(id, case, paste("the filter ran:", res$stderr)))
    h <- ir_ledger_header(res)
    if (is.null(h)) next
    got <- ir_header_files(h, case$main)
    expect_identical(got, sort(c(case$main, case$follow)),
                     label = ir_label(id, case, sprintf("the include map {%s}", paste(got, collapse = ", "))))
  }
}

test_that("filter, I4: the include map resolves every path against the main document's folder or the project root", {
  ir_filter_test("I4")
})

test_that("filter, I3: the include map takes a quoted path with a space, and only the first parameter", {
  ir_filter_test("I3")
})

test_that("filter, I1: the include map holds only lines that are the whole shortcode", {
  ir_filter_test("I1")
})

test_that("filter, I2: the include map takes lowercase `include` in the main document, any case below", {
  ir_filter_test("I2")
})

test_that("filter, I5: the include map follows fences and comments, not a shortcodes=false block; an {r} cell counts (reading)", {
  ir_filter_test("I5")
})

test_that("filter, I6: the include map ends on a cycle and has no depth limit", {
  ir_filter_test("I6")
})

# ---- filter: the line of a construct in an included file (N89) ----------------------------------------

IR_DRAFT <- c(WEFT_DRAFT = "1")

test_that("filter lines, I4: a construct of a nested include is located in the file Quarto read, by its own line", {
  md <- c("First `m`{.num}.", "", inc("sub/a.md"))
  files <- list("sub/a.md" = c("Mid `m`{.num}.", "", inc("b.md")),
                "b.md" = c("Root b.", "", "Root `m`{.num}."),
                "sub/b.md" = c("Sub `m`{.num}."))
  # Pandoc reads the files in Quarto's order of expansion: the main document, then sub/a.md, then b.md
  res <- filter_md(md, files = files, to = "plain", env = IR_DRAFT, extra_inputs = c("sub/a.md", "b.md"))
  expect_identical(res$status, 0L)
  expect_true(grepl("Mid <<weft: no value, line 1>>.", res$output, fixed = TRUE))       # control
  expect_true(grepl("Root <<weft: no value, line 3>>.", res$output, fixed = TRUE), label = res$output)
  expect_true(fm_entry(res$stderr, "^  (\\./)?b\\.md:3  ")$found, label = res$stderr)
  expect_false(grepl("sub/b\\.md", res$stderr), label = res$stderr)
})

test_that("filter lines, I1: a line that is not an include does not move the main document's constructs into the file it names", {
  for (nm in names(IR_NOT_INCLUDES)) {
    form <- sub("t.qmd", "neg.md", IR_NOT_INCLUDES[[nm]], fixed = TRUE)
    md <- c(form, "", "After `m`{.num}.")
    res <- filter_md(md, files = list("neg.md" = c("Neg `m`{.num}.")), to = "plain", env = IR_DRAFT)
    expect_identical(res$status, 0L, label = nm)
    expect_true(grepl("After <<weft: no value, line 3>>.", res$output, fixed = TRUE),
                label = paste(nm, ":", res$output))
    expect_false(grepl("neg\\.md", res$stderr), label = paste(nm, ":", res$stderr))
  }
})

test_that("filter lines, I3: a quoted include path with a space is followed for lines", {
  md <- c("First `m`{.num}.", "", inc("\"my part.md\""))
  res <- filter_md(md, files = list("my part.md" = c("Part.", "", "Part `m`{.num}.")), to = "plain",
                   env = IR_DRAFT, extra_inputs = "my part.md")
  expect_identical(res$status, 0L)
  expect_true(grepl("Part <<weft: no value, line 3>>.", res$output, fixed = TRUE), label = res$output)
  expect_true(fm_entry(res$stderr, "^  (\\./)?my part\\.md:3  ")$found, label = res$stderr)
})

# ---- targets: weft:::report_reads() ------------------------------------------------------------------

ir_targets_content <- function(path, is_main, case) sprintf("Value `r dict$%s` here.", ir_nm(path))

ir_targets_test <- function(rule) {
  cases <- ir_cases()
  for (id in names(cases)) {
    case <- cases[[id]]
    if (!identical(case$rule, rule)) next
    root <- ir_write(case, ir_targets_content)
    keys <- ir_nm(names(case$files))
    got <- withr::with_dir(root, weft:::report_reads(case$main, globalenv(), keys)$keys)
    want <- ir_nm(c(case$main, case$follow))
    expect_true(setequal(as.character(got), want),
                label = ir_label(id, case, sprintf("keys {%s} are {%s}", paste(sort(got), collapse = ", "),
                                                   paste(sort(want), collapse = ", "))))
  }
}

test_that("targets, I4: a report's includes resolve against the main document's folder or the project root", {
  ir_targets_test("I4")
})

test_that("targets, I3: a report's quoted include path may hold a space; only the first parameter is the path", {
  ir_targets_test("I3")
})

test_that("targets, I1: only a line that is the whole shortcode is an include of a report", {
  ir_targets_test("I1")
})

test_that("targets, I2: `include` is lowercase in the report and any case in an included file", {
  ir_targets_test("I2")
})

test_that("targets, I5: a report's include in a fence or a multi-line comment is followed, not in a shortcodes=false block; in an {r} cell it is (reading)", {
  ir_targets_test("I5")
})

test_that("targets, I6: a report's includes end on a cycle and have no depth limit", {
  ir_targets_test("I6")
})

# ---- named: the lint named-unpublished (N144) --------------------------------------------------------

# The main document uses, by name, the name of every other file; each other file holds a Python chunk
# that sets its own name. A name is unpublished exactly when its file is not followed.
ir_named_content <- function(path, is_main, case) {
  if (is_main) {
    others <- setdiff(names(case$files), case$main)
    c("---", "engine: jupyter", "---", "",
      paste(sprintf("`%s`{.num}", ir_nm(others)), collapse = " "), "")
  } else {
    w6d_py(sprintf("%s = 1", ir_nm(path)))
  }
}

ir_named_test <- function(rule) {
  cases <- ir_cases()
  for (id in names(cases)) {
    case <- cases[[id]]
    # a fence or cell in the main document would hold the included chunk: no plain reading of N144
    if (!identical(case$rule, rule) || isTRUE(case$cell)) next
    root <- ir_write(case, ir_named_content)
    x <- lints(root, rules = NULL, tier = 1:2)
    x <- lf_by_rule(x, "named-unpublished")
    x <- x[x$file == case$main, , drop = FALSE]
    others <- setdiff(names(case$files), case$main)
    flagged <- others[vapply(others, function(f) W6D_E70(ir_nm(f)) %in% x$message, NA)]
    expect_identical(sort(flagged), sort(intersect(case$skip, others)),
                     label = ir_label(id, case, sprintf("files whose chunk was not counted {%s}",
                                                        paste(flagged, collapse = ", "))))
  }
}

test_that("named, I4: a chunk of a nested include counts from the file Quarto reads", {
  ir_named_test("I4")
})

test_that("named, I3: a chunk of a file included by a quoted path with a space counts", {
  ir_named_test("I3")
})

test_that("named, I1: a chunk of a file named on a line that is not an include does not count", {
  ir_named_test("I1")
})

test_that("named, I2: `include` is lowercase in the main document and any case in an included file", {
  ir_named_test("I2")
})

test_that("named, I6: a cycle ends, and a chunk twelve includes deep counts", {
  ir_named_test("I6")
})

# ---- doclint: the lint engine (L34): a document another includes is not alone -------------------------

IR_ALONE <- r"{Words [a site]{if="ok"} more.}"

ir_engine_files <- function(files) {
  x <- lint_fixture(files, rules = "engine", tier = 1:2)
  sort(lf_by_rule(x, "engine")$file)
}

test_that("doclint, I4: a nested include, and a leading /, resolve against the main document's folder or the project root", {
  # index.qmd includes sub/_one.qmd, which includes two.qmd: Quarto reads the root's two.qmd
  got <- ir_engine_files(list("index.qmd" = inc("sub/_one.qmd"), "sub/_one.qmd" = inc("two.qmd"),
                              "two.qmd" = IR_ALONE, "sub/two.qmd" = IR_ALONE))
  expect_false("two.qmd" %in% got, label = paste("listed:", paste(got, collapse = ", ")))
  # a leading / in a project: the root's shared/a.qmd, not ch/shared/a.qmd
  got <- ir_engine_files(list("_quarto.yml" = c("project:", "  type: default"),
                              "ch/index.qmd" = inc("/shared/a.qmd"),
                              "shared/a.qmd" = IR_ALONE, "ch/shared/a.qmd" = IR_ALONE))
  expect_identical(got, "ch/shared/a.qmd")
  # a leading / with no project: the main document's folder
  got <- ir_engine_files(list("ch/index.qmd" = inc("/shared/a.qmd"),
                              "shared/a.qmd" = IR_ALONE, "ch/shared/a.qmd" = IR_ALONE))
  expect_identical(got, "shared/a.qmd")
})

test_that("doclint, I3: a document included by a quoted path with a space is not alone", {
  for (line in c(inc("\"my a.qmd\""), inc("'my a.qmd'"))) {
    got <- ir_engine_files(list("index.qmd" = line, "my a.qmd" = IR_ALONE))
    expect_identical(got, character(), label = line)
  }
})

test_that("doclint, I1: a document named on a line that is not an include is still alone", {
  for (nm in names(IR_NOT_INCLUDES)) {
    form <- sub("t.qmd", "a.qmd", IR_NOT_INCLUDES[[nm]], fixed = TRUE)
    got <- ir_engine_files(list("index.qmd" = form, "a.qmd" = IR_ALONE))
    expect_identical(got, "a.qmd", label = nm)
  }
})

test_that("doclint, I2: `include` is lowercase in the main document and any case in an included file", {
  got <- ir_engine_files(list("index.qmd" = "{{< INCLUDE a.qmd >}}", "a.qmd" = IR_ALONE))
  expect_identical(got, "a.qmd")
  got <- ir_engine_files(list("index.qmd" = inc("_mid.qmd"), "_mid.qmd" = "{{< INCLUDE a.qmd >}}",
                              "a.qmd" = IR_ALONE))
  expect_identical(got, character())
})

test_that("doclint, I5: an include in a fence or a multi-line comment counts, not in a shortcodes=false block; in an {r} cell it does (reading)", {
  counts <- list(backticks = c("```", inc("a.qmd"), "```"), tildes = c("~~~", inc("a.qmd"), "~~~"),
                 comment = c("<!--", inc("a.qmd"), "-->"),
                 cell_r = c("```{r}", "#| eval: false", inc("a.qmd"), "```"))
  for (nm in names(counts)) {
    got <- ir_engine_files(list("index.qmd" = counts[[nm]], "a.qmd" = IR_ALONE))
    expect_identical(got, character(), label = nm)
  }
  got <- ir_engine_files(list("index.qmd" = c("```{shortcodes=false}", inc("a.qmd"), "```"),
                              "a.qmd" = IR_ALONE))
  expect_identical(got, "a.qmd", label = "shortcodes=false")
})

test_that("doclint, I6: a cycle among included documents ends, and neither is alone", {
  got <- ir_engine_files(list("index.qmd" = inc("a.qmd"), "a.qmd" = c(IR_ALONE, "", inc("b.qmd")),
                              "b.qmd" = c(IR_ALONE, "", inc("a.qmd"))))
  expect_identical(got, character())
})

# ---- knit: a failure's file and line under Quarto (2.7.4) ---------------------------------------------

IR_PRE <- "k <- 3"
IR_FAIL <- "`r claim(k, . > 100)`"

# One render of the cases that ARE includes (I4, I3, I5) and one of the lines that are NOT (I1); each
# render is made once for the tests that read it.
ir_render <- function(which) {
  if (!is.null(.ir[[which]])) return(.ir[[which]])
  if (which == "follow") {
    main <- c(
      paste("Main 1", IR_FAIL), "",                         # 1
      inc("sub/one.qmd"), "",                               # 3: I4
      paste("Main 5", IR_FAIL), "",                         # 5
      inc("\"my part.qmd\""), "",                           # 7: I3
      paste("Main 9", IR_FAIL), "",                         # 9
      "```", inc("fenced.qmd"), "```", "",                  # 11-13: I5, a plain fence
      paste("Main 15", IR_FAIL), "",                        # 15
      "```{r}", "#| eval: false", inc("chunky.qmd"), "```", "",  # 17-20: an {r} cell (reading)
      paste("Main 22", IR_FAIL)                             # 22
    )
    files <- list(
      "sub/one.qmd" = c("One line 1.", "", inc("two.qmd")),
      "two.qmd" = c("Root two line 1.", "", paste("Root two line 3", IR_FAIL)),
      "sub/two.qmd" = c(paste("Sub two line 1", IR_FAIL)),
      "my part.qmd" = c("Space line 1.", "", paste("Space line 3", IR_FAIL)),
      "fenced.qmd" = c("fenced one", "fenced two", "fenced three", "fenced four"),
      "chunky.qmd" = c("x <- 1", "y <- 2", "z <- 3", "w <- 4")
    )
  } else {
    main <- c(
      paste("Main 1", IR_FAIL), "",                         # 1
      "- {{< include neg.qmd >}}", "",                      # 3
      paste("Main 5", IR_FAIL), "",                         # 5
      "{{</* include neg.qmd */>}}", "",                    # 7
      paste("Main 9", IR_FAIL), "",                         # 9
      "{{<include neg.qmd>}}", "",                          # 11
      paste("Main 13", IR_FAIL), "",                        # 13
      "Text before {{< include neg.qmd >}}", "",            # 15
      paste("Main 17", IR_FAIL)                             # 17
    )
    files <- list("neg.qmd" = c("Neg line 1.", "Neg line 2.", "", paste("Neg line 4", IR_FAIL)))
  }
  .ir[[which]] <- render_qmd(main, code = IR_PRE, files = files)
  .ir[[which]]
}

test_that("knit, control: the render fails and names the main document's first line", {
  skip_if_no_quarto()
  res <- ir_render("follow")
  expect_true(res$failed)
  expect_match(res$message, at_line(res, 1))
})

test_that("knit, I4: a failure in a nested include names the file Quarto read (the root's two.qmd), by its own line", {
  skip_if_no_quarto()
  res <- ir_render("follow")
  expect_match(res$message, "(?<![/A-Za-z0-9_])two\\.qmd:3\\b", perl = TRUE)
  expect_false(grepl("sub/two\\.qmd", res$message), label = res$message)
  expect_match(res$message, at_line(res, 5))
})

test_that("knit, I3: a failure in a file included by a quoted path with a space names that file and line", {
  skip_if_no_quarto()
  res <- ir_render("follow")
  expect_match(res$message, "my part\\.qmd:3\\b")
  expect_match(res$message, at_line(res, 9))
})

test_that("knit, I5: an include inside a plain fence is expanded, so the lines below it stay the main document's", {
  skip_if_no_quarto()
  res <- ir_render("follow")
  expect_match(res$message, at_line(res, 15))
})

test_that("knit, I5 (reading): an include inside an {r} cell is expanded too, so the lines below it stay right", {
  skip_if_no_quarto()
  res <- ir_render("follow")
  expect_match(res$message, at_line(res, 22))
})

test_that("knit, I1: lines that are not includes (a list item, the escaped form, no spaces, text before) map nothing", {
  skip_if_no_quarto()
  res <- ir_render("not")
  expect_true(res$failed)
  expect_false(grepl("neg\\.qmd", res$message), label = res$message)
  for (k in c(1L, 5L, 9L, 13L, 17L)) expect_match(res$message, at_line(res, k))
})
