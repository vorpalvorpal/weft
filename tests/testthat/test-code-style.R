# Code style guards over the package source. ASCII only.

# `<<-` and `->>` write to whichever enclosing environment first holds the name, and to the global
# environment when none does, so a later edit can change which variable is written without any error.
# The package holds state in named environments instead. A site with a strong reason may stay when its
# line carries the comment `# <<- ok: <reason>`.
test_that("R/ uses no super-assignment (<<- or ->>) without a recorded reason", {
  rdir <- testthat::test_path("..", "..", "R")
  skip_if_not(dir.exists(rdir), "the R/ folder of the source is not available")
  files <- list.files(rdir, pattern = "\\.[Rr]$", full.names = TRUE)
  expect_gt(length(files), 0L)
  hits <- character()
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    pd <- utils::getParseData(parse(f, keep.source = TRUE), includeText = TRUE)
    ln <- pd$line1[pd$token %in% c("LEFT_ASSIGN", "RIGHT_ASSIGN") & pd$text %in% c("<<-", "->>")]
    ln <- unique(ln[!grepl("#[ ]*<<- ok: [^ ]", lines[ln])])
    if (length(ln)) hits <- c(hits, sprintf("%s:%d", basename(f), ln))
  }
  expect(length(hits) == 0L,
         sprintf("%d super-assignment line(s) in R/:\n%s", length(hits), paste(hits, collapse = "\n")))
})

# A kept `<<-` is safe only while its target is bound in an enclosing function: when the binding is
# renamed or deleted, the write lands in the global environment with no error. codetools sees that.
test_that("every kept <<- writes a variable bound in an enclosing function", {
  skip_if_not_installed("codetools")
  st <- new.env(parent = emptyenv())
  st$msgs <- character()
  codetools::checkUsageEnv(asNamespace("weft"), report = function(s) st$msgs <- c(st$msgs, s))
  bad <- grep("no visible binding for '<<-' assignment", st$msgs, value = TRUE, fixed = TRUE)
  expect(length(bad) == 0L, paste(c("<<- to an unbound name:", trimws(bad)), collapse = "\n"))
})
