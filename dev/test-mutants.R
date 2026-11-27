# Planted-bug runner (work package 0 of dev/test-suite-plan.md). ASCII only.
#
#   Rscript dev/test-mutants.R MUTANTS.tsv OUT.tsv
#       for each mutant: a `git archive HEAD` copy in a temp folder, the replacement applied,
#       the filtered tests run there; OUT.tsv lists mutant id and failing test (file::test).
#       A mutant with no failing test is listed as "SURVIVED"; "NO-MATCH" means the string
#       was not found exactly once in the file.
#   Rscript dev/test-mutants.R --diff BEFORE.tsv AFTER.tsv
#       prints the failing-test sets that differ (empty output and exit 0: identical)
#
# Mutant file: tab-separated, header `id file old new filter`. `file` is under R/ or inst/,
# `old` is an exact string (no tabs), `new` replaces it, `filter` is a devtools::test() filter
# regex. Run alone: one R process at a time. The tests run in a child Rscript per mutant.

read_mutants <- function(path) {
  x <- utils::read.delim(path, quote = "", comment.char = "", stringsAsFactors = FALSE,
                         colClasses = "character", na.strings = character())
  stopifnot(identical(names(x), c("id", "file", "old", "new", "filter")))
  x
}

run_one <- function(m) {
  dir <- tempfile("mutant-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  tarf <- tempfile(fileext = ".tar")
  on.exit(unlink(tarf), add = TRUE)
  system2("git", c("archive", "--format=tar", "-o", tarf, "HEAD"))
  utils::untar(tarf, exdir = dir)
  f <- file.path(dir, m$file)
  txt <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  hits <- gregexpr(m$old, txt, fixed = TRUE)[[1L]]
  if (length(hits) != 1L || hits[1L] < 0L) return("NO-MATCH")
  writeLines(sub(m$old, m$new, txt, fixed = TRUE) |> (\(z) z)(), f, useBytes = TRUE)
  out <- tempfile(fileext = ".rds")
  code <- sprintf(paste0("res <- devtools::test(%s, filter = %s, stop_on_failure = FALSE,",
                         " reporter = testthat::ListReporter$new());",
                         " df <- as.data.frame(res);",
                         " saveRDS(paste0(df$file, '::', df$test)[df$failed > 0 | df$error], %s)"),
                  deparse(dir), deparse(m$filter), deparse(out))
  system2("Rscript", c("-e", shQuote(code)), stdout = FALSE, stderr = FALSE,
          env = c("NOT_CRAN=true", paste0("QUARTO_PYTHON=", path.expand("~/.venvs/jupyter/bin/python"))))
  if (!file.exists(out)) return("RUN-FAILED")
  failing <- readRDS(out)
  if (length(failing)) sort(unique(failing)) else "SURVIVED"
}

mutants_run <- function(mutants, out) {
  rows <- lapply(seq_len(nrow(mutants)), function(i) {
    m <- mutants[i, ]
    r <- run_one(m)
    cat(sprintf("%s: %s\n", m$id, if (length(r) == 1L && r %in% c("SURVIVED", "NO-MATCH", "RUN-FAILED")) r
                else sprintf("%d failing tests", length(r))))
    data.frame(id = m$id, failing = r, stringsAsFactors = FALSE)
  })
  utils::write.table(do.call(rbind, rows), out, sep = "\t", quote = FALSE, row.names = FALSE)
}

mutants_diff <- function(before, after) {
  a <- utils::read.delim(before, quote = "", stringsAsFactors = FALSE)
  b <- utils::read.delim(after, quote = "", stringsAsFactors = FALSE)
  ka <- paste(a$id, a$failing, sep = "\t")
  kb <- paste(b$id, b$failing, sep = "\t")
  if (length(setdiff(ka, kb))) cat("Only before:\n", paste0("  ", setdiff(ka, kb), "\n"), sep = "")
  if (length(setdiff(kb, ka))) cat("Only after:\n", paste0("  ", setdiff(kb, ka), "\n"), sep = "")
  invisible(setequal(ka, kb))
}

main <- function(args) {
  if (identical(args[1L], "--diff")) {
    same <- mutants_diff(args[2L], args[3L])
    quit(status = if (isTRUE(same)) 0L else 1L)
  }
  if (length(args) != 2L) stop("usage: test-mutants.R MUTANTS.tsv OUT.tsv | --diff BEFORE.tsv AFTER.tsv")
  mutants_run(read_mutants(args[1L]), args[2L])
}

if (!interactive() && sys.nframe() == 0L) main(commandArgs(trailingOnly = TRUE))
