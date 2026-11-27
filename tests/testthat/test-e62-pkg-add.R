# E62 tells a Julia user to run `Pkg.add(url = ..., subdir = ...)`. This runs that exact line, taken from
# weft's own message, in a fresh Julia project and checks that the package is installed and loads.
# It needs the network and Julia, so it runs only where WEFT_TEST_PKG_ADD=true (CI sets it).

e62_pkg_add_line <- function() {
  msg <- weft:::MSG_E62
  m <- regmatches(msg, regexpr("Pkg\\.add\\(.*?\\)(?=\\. )", msg, perl = TRUE))
  m <- gsub("\\\"", "\"", m, fixed = TRUE)
  m
}

test_that("E62's Pkg.add line installs the Weft package into a fresh Julia project", {
  skip_if_not(identical(Sys.getenv("WEFT_TEST_PKG_ADD"), "true"), "WEFT_TEST_PKG_ADD is not 'true'")
  skip_if(!nzchar(Sys.which("julia")), "julia is not available")
  skip_on_cran()

  line <- e62_pkg_add_line()
  expect_match(line, "^Pkg\\.add\\(url = \"https://github\\.com/vorpalvorpal/weft\", subdir = \"inst/julia/Weft\"\\)$")

  proj <- withr::local_tempdir("weft-e62-")
  depot <- withr::local_tempdir("weft-e62-depot-")
  code <- paste0("using Pkg; ", line, "; using Weft; ",
                 "println(\"INSTALLED=\", haskey(Pkg.project().dependencies, \"Weft\"))")
  # A user's fresh shell has no R in it. The R test process has R's lib folder, and the system's, on
  # LD_LIBRARY_PATH, so a plain child `julia` loads the system libunwind and segfaults (exit 139, finding 22);
  # weft:::julia_child_env() takes the system folders out, as weft does for its own Julia children. Julia's
  # temporary files go in a test folder too, so that a crash leaves nothing in R's temp directory.
  tmp <- withr::local_tempdir("weft-e62-tmp-")
  env <- c(JULIA_DEPOT_PATH = paste0(depot, ":"), TMPDIR = tmp, weft:::julia_child_env())
  out <- suppressWarnings(system2(
    Sys.which("julia"), c(paste0("--project=", proj), "-e", shQuote(code)),
    stdout = TRUE, stderr = TRUE,
    env = paste0(names(env), "=", env)))
  expect_null(attr(out, "status"), label = paste(utils::tail(out, 15), collapse = "\n"))
  expect_true(any(out == "INSTALLED=true"), label = paste(utils::tail(out, 15), collapse = "\n"))
})
