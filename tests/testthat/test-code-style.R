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
