# vctrs operations keep names on self-formatting values exactly as they do for
# a plain named double (ruling 27 Nov; spec 3.12, design case 73). The expected
# value in each test comes from vctrs applied to the plain double.

# the plain named double with the same numbers and names as the value `v`
plain_of <- function(v) stats::setNames(as.numeric(v), names(v))

named_val <- function() val_num(c(a = 1.5, b = 2.25, c = 3.125))

test_that("names 1: control, base c() and format() keep names", {
  v <- named_val()
  expect_identical(names(c(v, v)), names(c(plain_of(v), plain_of(v))))
  expect_identical(names(format(v)), c("a", "b", "c"))
})

test_that("names 2: vec_c() of named values keeps the names", {
  skip_if_not_installed("vctrs")
  v <- named_val()
  w <- val_num(c(d = 9.5, e = 10.5))
  got <- vctrs::vec_c(v, w)
  want <- vctrs::vec_c(plain_of(v), plain_of(w))
  expect_s3_class(got, "weft_val")
  expect_identical(names(got), names(want))
  expect_identical(names(got), c("a", "b", "c", "d", "e"))
  expect_identical(as.numeric(got), as.numeric(want))
})

test_that("names 3: vec_c() of a named and an unnamed value follows vctrs", {
  skip_if_not_installed("vctrs")
  v <- named_val()
  u <- val_num(c(7.5, 8.5))
  got <- vctrs::vec_c(v, u)
  want <- vctrs::vec_c(plain_of(v), as.numeric(u))
  expect_identical(names(got), names(want))
  got2 <- vctrs::vec_c(u, v)
  want2 <- vctrs::vec_c(as.numeric(u), plain_of(v))
  expect_identical(names(got2), names(want2))
})

test_that("names 4: vec_c() with outer names follows vctrs", {
  skip_if_not_installed("vctrs")
  v <- named_val()
  v <- named_val()
  s <- val_num(1.5)
  got <- vctrs::vec_c(a = s)
  want <- vctrs::vec_c(a = 1.5)
  expect_identical(names(got), names(want))
  expect_identical(names(got), "a")
  # a length > 1 value needs a name spec, as a plain double does
  expect_identical(names(vctrs::vec_c(a = v, .name_spec = "{outer}_{inner}")),
                   names(vctrs::vec_c(a = plain_of(v),
                                      .name_spec = "{outer}_{inner}")))
  expect_identical(names(vctrs::vec_c(a = s, b = s)),
                   names(vctrs::vec_c(a = 1.5, b = 1.5)))
})

test_that("names 5: vec_slice() keeps the names", {
  skip_if_not_installed("vctrs")
  v <- named_val()
  got <- vctrs::vec_slice(v, c(3, 1))
  want <- vctrs::vec_slice(plain_of(v), c(3, 1))
  expect_s3_class(got, "weft_val")
  expect_identical(names(got), names(want))
  expect_identical(as.numeric(got), as.numeric(want))
  expect_identical(names(vctrs::vec_slice(v, 2)), "b")
})

test_that("names 6: vec_names() gives the names", {
  skip_if_not_installed("vctrs")
  v <- named_val()
  expect_identical(vctrs::vec_names(v), vctrs::vec_names(plain_of(v)))
  u <- val_num(c(1.5, 2.5))
  expect_identical(vctrs::vec_names(u), vctrs::vec_names(as.numeric(u)))
})

test_that("names 7: vec_c() of a value and a double is a double with vctrs names", {
  skip_if_not_installed("vctrs")
  v <- named_val()
  got <- vctrs::vec_c(v, 1)
  want <- vctrs::vec_c(plain_of(v), 1)
  expect_identical(class(got), class(want))
  expect_identical(names(got), names(want))
  got2 <- vctrs::vec_c(1, v)
  want2 <- vctrs::vec_c(1, plain_of(v))
  expect_identical(class(got2), class(want2))
  expect_identical(names(got2), names(want2))
})

test_that("names 8: the shown text still matches per element after slicing", {
  skip_if_not_installed("vctrs")
  v <- named_val()
  expect_identical(format(vctrs::vec_slice(v, 2)), format(v)[2])
  expect_identical(names(format(vctrs::vec_slice(v, 2))), "b")
  expect_identical(format(vctrs::vec_slice(v, c(3, 1))), format(v)[c(3, 1)])
})

test_that("names 9: a dplyr mutate() and filter() round trip keeps the names", {
  skip_if_not_installed("vctrs")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("tibble")
  v <- named_val()
  p <- plain_of(v)
  got <- dplyr::filter(dplyr::mutate(tibble::tibble(x = v), k = 1), k == 1)
  want <- dplyr::filter(dplyr::mutate(tibble::tibble(x = p), k = 1), k == 1)
  expect_identical(names(got$x), names(want$x))
  got2 <- dplyr::filter(tibble::tibble(x = v), as.numeric(x) > 2)
  want2 <- dplyr::filter(tibble::tibble(x = p), x > 2)
  expect_identical(names(got2$x), names(want2$x))
  expect_identical(format(got2$x), format(v)[2:3])
})
