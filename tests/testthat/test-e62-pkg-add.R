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
  out <- suppressWarnings(system2(
    Sys.which("julia"), c(paste0("--project=", proj), "-e", shQuote(code)),
    stdout = TRUE, stderr = TRUE,
    env = paste0("JULIA_DEPOT_PATH=", depot, ":")))
  expect_null(attr(out, "status"), label = paste(utils::tail(out, 15), collapse = "\n"))
  expect_true(any(out == "INSTALLED=true"), label = paste(utils::tail(out, 15), collapse = "\n"))
})
