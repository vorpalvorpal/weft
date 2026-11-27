# The alias policy (commit 94f1cf2, NEWS "weft still refuses an `is` that is exactly another
# unit"). ud_sync() refuses, before install_unit(), an `is` that converts with factor 1 to an
# earlier row (project or default), and an `is` that is exactly a database unit with a
# non-ASCII symbol or none (1 degree, degree, 1 ohm, gallon). Nothing is installed.
# ASCII only: non-ASCII is written as \u escapes. The units database is session-global;
# g2_cfg() and g2_cfg_err() restore the default state when the test ends.
if (!exists("g2_cfg_err")) source(file.path(dirname(Filter(file.exists, c(testthat::test_path("helper-2g.R"), testthat::test_path("..", "helper-2g.R")))[[1]]), "helper-2g.R"))
g2_need()

# how a database unit prints now, as a probe that a refused row left it alone
ap_show <- function(token) {
  c(num = f2_tx(fmt_num(g2_u(5, token))), word = f2_tx(fmt_num(g2_u(5, token), unit_form = "name")))
}
ap_not_a_unit <- function(token) inherits(f2_cond(g2_u(2, token)), "weft_unit_error")

test_that("alias policy: an is: of factor 1 to an earlier project row gets the same-unit problem, nothing installed", {
  before <- ap_show("s")
  e <- g2_cfg_err(c("units:", "  zzapa:", "    is: 1 s", "  zzapb:", "    is: 1 zzapa"))
  f2_has_class(e, "weft_config_error")
  f2_msg_has(e, "`zzapb`", "`zzapa`", "same unit")
  expect_true(ap_not_a_unit("zzapb"))
  expect_identical(ap_show("s"), before)
})

test_that("alias policy: a different spelling of the same unit as an earlier project row is refused too", {
  e <- g2_cfg_err(c("units:", "  zzapc:", "    is: 1 s", "  zzapd:", "    is: 1 sec"))
  f2_has_class(e, "weft_config_error")
  f2_msg_has(e, "`zzapd`", "same unit as `zzapc`")
  expect_true(ap_not_a_unit("zzapd"))
})

test_that("alias policy: an is: of factor 1 to a default row gets the same-unit problem, nothing installed", {
  before <- ap_show("mi")
  e <- g2_cfg_err(c("units:", "  zzape:", "    is: mi/h"))     # mph is a default row
  f2_has_class(e, "weft_config_error")
  f2_msg_has(e, "`zzape`", "same unit")
  expect_true(ap_not_a_unit("zzape"))
  expect_identical(ap_show("mi"), before)
  expect_equal(g2_factor("mph", "mi/h"), 1, tolerance = 1e-9)  # the default row is untouched
})

test_that("alias policy: an is: that is exactly a database unit with a non-ASCII symbol says to write the unit it is", {
  cases <- list(list(def = "1 degree", name = "degree", sym = "\u00b0", key = "zzapdeg"),
                list(def = "degree", name = "degree", sym = "\u00b0", key = "zzapdegb"),
                list(def = "1 ohm", name = "ohm", sym = "\u03a9", key = "zzapohm"))
  for (cs in cases) {
    before <- ap_show(cs$name)
    e <- g2_cfg_err(c("units:", paste0("  ", cs$key, ":"), paste0("    is: ", cs$def)))
    f2_has_class(e, "weft_config_error")
    f2_msg_has(e, paste0("`", cs$key, "`"), "already", paste0("write `", cs$sym, "`"))
    expect_true(ap_not_a_unit(cs$key), label = cs$key)
    expect_identical(ap_show(cs$name), before, label = cs$def)
  }
})

test_that("alias policy: an is: that is exactly a unit with no symbol (gallon) is refused, nothing installed", {
  before <- ap_show("gallon")
  e <- g2_cfg_err(c("units:", "  zzapgal:", "    is: gallon"))
  f2_has_class(e, "weft_config_error")
  f2_msg_has(e, "`zzapgal`")
  # gal is a default row for the gallon, so either message may win; both refuse
  expect_true(grepl("same unit", f2_msg(e), fixed = TRUE) || grepl("already", f2_msg(e), fixed = TRUE),
              label = f2_msg(e))
  expect_true(ap_not_a_unit("zzapgal"))
  expect_identical(ap_show("gallon"), before)
  expect_false(grepl("zzapgal", ap_show("gallon")[["num"]], fixed = TRUE))   # not a printed alias
})

test_that("alias policy: control - an is: with a factor other than 1 installs and converts", {
  expect_null(g2_cfg_err(c("units:", "  zzapkm:", "    is: 1000 m")))
  g2_cfg(c("units:", "  zzapkm:", "    is: 1000 m"))
  expect_equal(g2_factor("zzapkm", "m"), 1000, tolerance = 1e-9)
  expect_equal(g2_cv(u(2, zzapkm), "m"), f2("2,000~m"))
})

test_that("alias policy: control - a factor of 2 on an earlier project row installs", {
  g2_cfg(c("units:", "  zzapr:", "    is: 1 m", "  zzaps:", "    is: 2 zzapr"))
  expect_equal(g2_cv(u(10, zzaps), "m"), f2("20~m"))
})

test_that("alias policy: after a refused row and a read of the default state, the database is clean", {
  e <- g2_cfg_err(c("units:", "  zzapx:", "    is: 1 degree"))
  expect_false(is.null(e))
  g2_cfg(NULL)
  expect_true(ap_not_a_unit("zzapx"))
  expect_true(is.na(g2_factor("zzapkm", "m")))                  # nothing leaked from the control above
  expect_true(is.na(g2_factor("zzapr", "m")))
  expect_equal(g2_factor("gal", "L"), 3.785411784, tolerance = 1e-6)
})
