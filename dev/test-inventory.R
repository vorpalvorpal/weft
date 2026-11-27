# Per-test inventory of the whole suite, and a compare mode that shows what a change to the
# test suite lost (work package 0 of dev/test-suite-plan.md). ASCII only.
#
#   Rscript dev/test-inventory.R OUT_STEM [--filter=REGEX]
#       runs the suite; writes OUT_STEM.rds, OUT_STEM.csv and OUT_STEM.failures.txt
#   Rscript dev/test-inventory.R --compare BEFORE.rds AFTER.rds
#       prints added/removed tests, nb changes, new skips, new failures and time per file
#
# Columns: file, test, key (file::test, #n for a repeated name), nb, skipped, failed, error,
# real (seconds). Run it alone: one R process at a time (see CLAUDE.mac.md).

inventory_run <- function(filter = NULL) {
  pkgload::load_all(quiet = TRUE)
  res <- devtools::test(filter = filter, reporter = testthat::ListReporter$new(), stop_on_failure = FALSE)
  df <- as.data.frame(res)
  key <- paste0(df$file, "::", df$test)
  key <- ifelse(duplicated(key), paste0(key, "#", ave(seq_along(key), key, FUN = seq_along)), key)
  inv <- data.frame(file = df$file, test = df$test, key = key, nb = df$nb, skipped = df$skipped,
                    failed = df$failed, error = df$error, real = df$real, stringsAsFactors = FALSE)
  reason <- vapply(res, function(t) {
    bad <- Filter(function(r) inherits(r, c("expectation_failure", "expectation_error")), t$results)
    if (!length(bad)) return(NA_character_)
    strsplit(conditionMessage(bad[[1L]]), "\n", fixed = TRUE)[[1L]][1L]
  }, "")
  list(inv = inv, reason = reason[inv$failed > 0 | inv$error])
}

inventory_write <- function(x, stem) {
  saveRDS(x$inv, paste0(stem, ".rds"))
  utils::write.csv(x$inv, paste0(stem, ".csv"), row.names = FALSE)
  bad <- x$inv[x$inv$failed > 0 | x$inv$error, ]
  writeLines(if (nrow(bad)) paste0(bad$key, "  --  ", x$reason) else character(), paste0(stem, ".failures.txt"))
  cat(sprintf("%d files, %d tests, %d expectations, %d skipped, %d failing, %.1f min\n",
              length(unique(x$inv$file)), nrow(x$inv), sum(x$inv$nb), sum(x$inv$skipped),
              nrow(bad), sum(x$inv$real) / 60))
}

per_file <- function(inv) tapply(inv$real, inv$file, sum)

inventory_compare <- function(before, after) {
  a <- readRDS(before)
  b <- readRDS(after)
  show <- function(title, x) {
    cat(sprintf("%s: %d\n", title, length(x)))
    if (length(x)) cat(paste0("  ", x), sep = "\n")
  }
  show("Tests removed", setdiff(a$key, b$key))
  show("Tests added", setdiff(b$key, a$key))
  both <- intersect(a$key, b$key)
  ia <- a[match(both, a$key), ]
  ib <- b[match(both, b$key), ]
  d <- ia$nb != ib$nb
  show("nb changed", if (any(d)) paste0(both[d], " (", ia$nb[d], " -> ", ib$nb[d], ")") else character())
  show("New skips", both[ib$skipped & !ia$skipped])
  fixed <- (ia$failed > 0 | ia$error) & !(ib$failed > 0 | ib$error)
  show("Failed before, passing now", both[fixed])
  new_fail <- (ib$failed > 0 | ib$error) & !(ia$failed > 0 | ia$error)
  show("New failures", c(both[new_fail], setdiff(b$key[b$failed > 0 | b$error], a$key)))
  fa <- per_file(a)
  fb <- per_file(b)
  files <- sort(union(names(fa), names(fb)))
  t <- data.frame(file = files, before = round(unname(fa[files]), 1), after = round(unname(fb[files]), 1))
  t$diff <- t$after - t$before
  t <- t[is.na(t$diff) | abs(t$diff) >= 1, ]
  cat("Time per file (s), changes of 1 s or more:\n")
  if (nrow(t)) print(t, row.names = FALSE)
  cat(sprintf("Total: %.1f s -> %.1f s (%.1f -> %.1f min)\n", sum(a$real), sum(b$real),
              sum(a$real) / 60, sum(b$real) / 60))
}

main <- function(args) {
  if (identical(args[1L], "--compare")) {
    if (length(args) != 3L) stop("usage: --compare BEFORE.rds AFTER.rds")
    return(inventory_compare(args[2L], args[3L]))
  }
  flt <- grep("^--filter=", args, value = TRUE)
  stem <- sub("\\.(rds|csv)$", "", setdiff(args, flt))
  if (length(stem) != 1L) stop("usage: test-inventory.R OUT_STEM [--filter=REGEX]")
  inventory_write(inventory_run(if (length(flt)) sub("^--filter=", "", flt) else NULL), stem)
}

if (!interactive() && sys.nframe() == 0L) main(commandArgs(trailingOnly = TRUE))
