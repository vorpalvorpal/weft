# Package E1 (dev/design-e1.md): the configuration cache (CF1 to CF6, T11), fmt_*() reading the same
# configuration outside a knit (A1) and speed (T12). Every test works in a temporary directory.

# a project root in a temporary directory; the working directory is moved to `sub` below it
e1c_project <- function(yml = NULL, sub = ".", env = parent.frame()) {
  root <- normalizePath(withr::local_tempdir(.local_envir = env))
  if (!is.null(yml)) writeLines(yml, file.path(root, "_weft.yml"))
  wd <- file.path(root, sub)
  dir.create(wd, recursive = TRUE, showWarnings = FALSE)
  withr::local_dir(wd, .local_envir = env)
  weft:::string_config_reset()
  root
}

e1c_text <- function(x) as.character(x)

test_that("T11 CF5: string_config_reset() exists and returns without error", {
  expect_no_error(weft:::string_config_reset())
})

test_that("T11 CF2: the root is found upward from the working directory: _weft.yml two folders above", {
  e1c_project("digits: 3", sub = file.path("a", "b"))
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.142")
})

test_that("T11 CF2: a folder with only _quarto.yml and no _weft.yml gives the defaults", {
  root <- e1c_project(NULL)
  writeLines("project:\n  type: default", file.path(root, "_quarto.yml"))
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.1")
})

test_that("T11 CF2/CF3: the cache is keyed on existence, size and modification time; a failed read keeps nothing", {
  root <- e1c_project("digits: 3")
  yml <- file.path(root, "_weft.yml")
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.142")
  mt <- file.info(yml)$mtime
  bad <- "digits: {"                       # same byte length as "digits: 3", not valid YAML
  expect_identical(nchar(bad), nchar("digits: 3"))
  writeLines(bad, yml)
  Sys.setFileTime(yml, mt)
  # same size and modification time: served from the cache
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.142")
  # a changed modification time reads the file again, and the read fails
  Sys.setFileTime(yml, mt + 10)
  expect_error(weft("`r pi`{.num}"), class = "weft_config_error")
  # nothing was cached: the next call fails again
  expect_error(weft("`r pi`{.num}"), class = "weft_config_error")
  # fix the file
  writeLines("digits: 2", yml)
  Sys.setFileTime(yml, mt + 20)
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.14")
})

test_that("T11 CF2: a changed size is noticed at once", {
  root <- e1c_project("digits: 3")
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.142")
  writeLines(c("digits: 2", "# a longer file"), file.path(root, "_weft.yml"))
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.14")
})

test_that("T11 CF2: deleting _weft.yml gives the defaults on the next call", {
  root <- e1c_project("digits: 3")
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.142")
  unlink(file.path(root, "_weft.yml"))
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.1")
})

test_that("T11 CF2: a _weft.yml that appears is read on the next call", {
  root <- e1c_project(NULL)
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.1")
  writeLines("digits: 3", file.path(root, "_weft.yml"))
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.142")
})

test_that("T11 CF1/CF2: setwd() to another project is followed at once", {
  a <- normalizePath(withr::local_tempdir())
  b <- normalizePath(withr::local_tempdir())
  writeLines("digits: 3", file.path(a, "_weft.yml"))
  writeLines("digits: 2", file.path(b, "_weft.yml"))
  weft:::string_config_reset()
  withr::local_dir(a)
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.142")
  setwd(b)
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.14")
  setwd(a)
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.142")
})

test_that("T11 CF4: two projects whose units: give one unit different symbols each print their own", {
  a <- normalizePath(withr::local_tempdir())
  b <- normalizePath(withr::local_tempdir())
  writeLines(c("units:", "  zze1cf:", "    symbol: AA"), file.path(a, "_weft.yml"))
  writeLines(c("units:", "  zze1cf:", "    symbol: BB"), file.path(b, "_weft.yml"))
  weft:::string_config_reset()
  withr::local_dir(a)
  for (i in 1:2) {
    setwd(a)
    expect_identical(e1c_text(weft("`r u(3, zze1cf)`{.num}")), "3 AA")
    setwd(b)
    expect_identical(e1c_text(weft("`r u(3, zze1cf)`{.num}")), "3 BB")
  }
})

test_that("T11 CF1: in a knit with weft_setup(), a document's front matter wins over the project file for a weft() call", {
  lines <- c(
    "```{r a, results='asis', echo=FALSE}",
    "cat('DIGITS:', as.character(weft::weft('`r pi`{.num}')), '\\n')",
    "```", "")
  res <- render_rmd(lines, front = c("weft:", "  digits: 2"), files = list("_weft.yml" = "digits: 3"),
                    format = "knit", in_process = TRUE)
  expect_false(res$failed, label = res$message)
  expect_match(res$md, "DIGITS: 3.14", fixed = TRUE)
  # control: without the front matter the project file applies
  res2 <- render_rmd(lines, files = list("_weft.yml" = "digits: 3"), format = "knit", in_process = TRUE)
  expect_false(res2$failed, label = res2$message)
  expect_match(res2$md, "DIGITS: 3.142", fixed = TRUE)
})

# ---- A1: fmt_*() read the same configuration as weft() outside a knit -------------------------

test_that("A1: fmt_num() and weft() print the same digits with the working directory in a project", {
  e1c_project("digits: 3")
  expect_identical(as.character(unclass(fmt_num(pi))), "3.142")
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.142")
})

test_that("A1: from a directory with no project both print the defaults", {
  e1c_project(NULL)
  expect_identical(as.character(unclass(fmt_num(pi))), "3.1")
  expect_identical(e1c_text(weft("`r pi`{.num}")), "3.1")
})

test_that("A1: the phrase functions and a plain label read the project configuration too", {
  e1c_project("digits: 3")
  expect_identical(as.character(unclass(fmt_pct(0.12345, target = "plain"))),
                   e1c_text(weft("`r 0.12345`{.pct}")))
})

test_that("A1: a configuration error outside a knit is a weft_config_error from fmt_num() as from weft()", {
  root <- e1c_project("digits: 3")
  writeLines("digits: {", file.path(root, "_weft.yml"))
  Sys.setFileTime(file.path(root, "_weft.yml"), Sys.time() + 5)
  expect_error(fmt_num(pi), class = "weft_config_error")
  expect_error(weft("`r pi`{.num}"), class = "weft_config_error")
})

# ---- T12: speed (CF6) --------------------------------------------------------------------------

test_that("T12 CF6: a warm weft() call costs at most 20 times a fmt_num() call", {
  skip_on_cran()
  e1c_project(c("digits: 2"))
  x <- 1.5
  weft("Mean `r x`{.num} m")                   # warm the cache
  t_weft <- cpu_time_min(function() for (i in 1:200) weft("Mean `r x`{.num} m"))
  t_fmt <- cpu_time_min(function() for (i in 1:200) fmt_num(x))
  expect_lte(t_weft, 20 * max(t_fmt, 0.005))
})
