# Package E1 (dev/design-e1.md): Python's weft_str() calls R's weft() and returns the markdown (T14; PY1, ST4).
# Skips as the existing guest tests do (helper-5c.R).

test_that("T14 PY1: weft_str() of one string returns the markdown str", {
  py_forms_ready()
  py_set(t_e1_k = "2")
  got <- py_val("weft_str('*a* [one | # sites]{n=\"py$t_e1_k\"} m^2^')")
  expect_identical(got, "*a* 2 sites m^2^")
  expect_identical(py_val("type(weft_str('*a*')).__name__"), "str")
})

test_that("T14 PY1: several strings give a list of str, each markdown", {
  py_forms_ready()
  got <- py_val("weft_str(['*a*', 'm^2^', 'plain'])")
  expect_identical(unlist(got), c("*a*", "m^2^", "plain"))
  expect_identical(py_val("type(weft_str(['*a*', 'b'])).__name__"), "list")
})

test_that("T14 PY1: a failure outside a knit raises at once in Python", {
  py_forms_ready()
  r <- py_try("weft_str('Check `r claim(1, . > 100)`.')")
  expect_false(r$ok)
  expect_gt(nchar(r$msg), 0L)
})
