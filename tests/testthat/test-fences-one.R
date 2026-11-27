# A18: one fence finder. The finders that see fences must agree, by the rulings R1 to R5 (CommonMark, as
# Pandoc reads it):
#   R1  a backtick fence whose info string holds a backtick is not an opener; a tilde fence's may
#   R2  a closer has the same character, is at least as long, and has only spaces after it; a fence is
#       indented at most 3 spaces
#   R3  an unclosed fence runs to the end of the document: the last line is n, and the finder says unclosed
#   R4  a fence opened inside a block quote ends where its quote ends; a quoted line does not close a fence
#       that started outside a quote
#   R5  a YAML block inside a fence is not front matter; a fence inside an HTML comment is not a fence
#
# The finders and their shapes (no finder is called from another test file):
#   fence_blocks(lines, inmeta)  data frame open, close, info (every fence)
#   find_chunks(lines)           list of list(open, close, engine, header, closed) (executable chunks)
#   metadata_blocks(lines)       data frame open, close (the `---` blocks)
#   front_block(lines)           the lines of the first block
# plus the surfaces scan_text(), read_front_matter() and lints() that read their answers.

# ---- helpers ---------------------------------------------------------------------------------------------

fo_fb <- function(l) as.data.frame(weft:::fence_blocks(l, rep(FALSE, length(l))))
fo_ch <- function(l) weft:::find_chunks(l)
fo_mb <- function(l) as.data.frame(weft:::metadata_blocks(l))

# the close line the finder gives the fence opened on line `open`; NA when it sees no fence there
fo_fb_close <- function(l, open) {
  r <- fo_fb(l)
  r <- r[r$open == open, , drop = FALSE]
  if (nrow(r) == 0L) NA_integer_ else as.integer(r$close[[1]])
}
fo_ch_close <- function(l, open) {
  ch <- Filter(function(x) x$open == open, fo_ch(l))
  if (length(ch) == 0L) NA_integer_ else as.integer(ch[[1]]$close)
}
fo_ch_closed <- function(l, open) {
  ch <- Filter(function(x) x$open == open, fo_ch(l))
  if (length(ch) == 0L) NA else ch[[1]]$closed
}
# the (open, close) pairs of the metadata blocks, as "open-close" strings
fo_mb_pairs <- function(l) {
  r <- fo_mb(l)
  if (nrow(r) == 0L) character() else paste0(r$open, "-", r$close)
}
# the first document whose front matter weft reads from `lines`
fo_fm <- function(lines) {
  f <- withr::local_tempfile(fileext = ".qmd", .local_envir = parent.frame())
  writeLines(lines, f)
  weft:::read_front_matter(f)
}
fo_claims <- function(lines) fo_fm(lines)$weft$chunk_claims
fo_scan <- function(lines) {
  r <- weft:::scan_text(paste(lines, collapse = "\n"))
  r[, intersect(c("kind", "line", "start", "end", "expr"), names(r)), drop = FALSE]
}
# lints() findings as rule, line, text
fo_lint <- function(lines) {
  r <- as.data.frame(unclass(lint_one(lines)), stringsAsFactors = FALSE)
  r <- r[, c("rule", "line", "text"), drop = FALSE]
  rownames(r) <- NULL
  r
}

# ---- R1: a backtick in a backtick fence's info string -----------------------------------------------------

test_that("R1: fence_blocks() and find_chunks() see no fence on a backtick opener with a backtick in its info", {
  l <- c("```{r a`b}", "x <- 1", "```")
  expect_true(is.na(fo_fb_close(l, 1L)))
  expect_true(is.na(fo_ch_close(l, 1L)))
})

test_that("R1: a tilde fence's info string may hold a backtick", {
  expect_identical(fo_fb_close(c("~~~ a`b", "x", "~~~"), 1L), 3L)
})

test_that("R1: metadata_blocks() reads a block after a line that is not a fence opener", {
  l <- c("``` a`b", "", "---", "k: v", "---")
  expect_identical(fo_mb_pairs(l), "3-5")
})

test_that("R1: metadata_blocks() reads no block inside a tilde fence whose info holds a backtick", {
  l <- c("~~~ a`b", "", "---", "k: v", "---", "~~~")
  expect_identical(fo_mb_pairs(l), character())
})

test_that("R1 (lints): the opener `{r a`b}` is text, so it gets no chunk finding and its lines are prose", {
  # the line is not a chunk, so there is no chunk-label finding on it
  r <- fo_lint(c("```{r a`b}", "x <- 1", "```"))
  expect_false(any(r$rule == "chunk-label" & r$line == 1L))
  # and the control: the same chunk without the backtick is found
  r2 <- fo_lint(c("```{r}", "x <- 1", "```"))
  expect_true(any(r2$rule == "chunk-label" & r2$line == 1L))
})

# ---- R2: closers and indentation -------------------------------------------------------------------------

test_that("R2: a closer needs the same character, at least the opener's length, and only spaces after it", {
  # a longer closer closes
  l1 <- c("```{r}", "x", "`````")
  expect_identical(fo_fb_close(l1, 1L), 3L)
  expect_identical(fo_ch_close(l1, 1L), 3L)
  # trailing spaces are allowed
  l2 <- c("```{r}", "x", "```   ", "y")
  expect_identical(fo_fb_close(l2, 1L), 3L)
  expect_identical(fo_ch_close(l2, 1L), 3L)
  # text after the closer means it is not a closer: the fence runs on to the real closer
  l3 <- c("```{r}", "x", "``` y", "z", "```")
  expect_identical(fo_fb_close(l3, 1L), 5L)
  expect_identical(fo_ch_close(l3, 1L), 5L)
  # a tilde line does not close a backtick fence
  l4 <- c("```{r}", "x", "~~~", "```")
  expect_identical(fo_fb_close(l4, 1L), 4L)
  expect_identical(fo_ch_close(l4, 1L), 4L)
  # a shorter closer does not close
  l5 <- c("````{r}", "x", "```", "y", "````")
  expect_identical(fo_fb_close(l5, 1L), 5L)
  expect_identical(fo_ch_close(l5, 1L), 5L)
})

test_that("R2: a fence may be indented up to 3 spaces", {
  l <- c("   ```{r}", "x", "   ```")
  expect_identical(fo_fb_close(l, 1L), 3L)
  expect_identical(fo_ch_close(l, 1L), 3L)
  expect_identical(fo_mb_pairs(c("   ```", "", "---", "k: v", "---", "   ```")), character())
})

test_that("R2: 4 spaces is indented code, not a fence", {
  l <- c("    ```{r}", "x", "    ```")
  expect_true(is.na(fo_fb_close(l, 1L)))
  expect_true(is.na(fo_ch_close(l, 1L)))
  # so a block after it is read
  expect_identical(fo_mb_pairs(c("    ```", "", "---", "k: v", "---")), "3-5")
})

# ---- R3: an unclosed fence runs to line n ---------------------------------------------------------------

test_that("R3: an unclosed fence ends at the last line n in every finder, and is marked unclosed", {
  l <- c("```{r}", "x <- 1", "y <- 2")
  expect_identical(fo_fb_close(l, 1L), 3L)
  expect_identical(fo_ch_close(l, 1L), 3L)
  expect_false(fo_ch_closed(l, 1L))
})

test_that("R3: the same holds for a tilde fence and for trailing blank lines", {
  expect_identical(fo_fb_close(c("~~~", "x <- 1", "", ""), 1L), 4L)
  l <- c("```{r}", "x <- 1", "", "")
  expect_identical(fo_fb_close(l, 1L), 4L)
  expect_identical(fo_ch_close(l, 1L), 4L)
  expect_false(fo_ch_closed(l, 1L))
  expect_identical(fo_fb_close(c("```", "text"), 1L), 2L)
})

test_that("R3: a closed fence is marked closed, and its close is the closer", {
  l <- c("```{r}", "x <- 1", "```", "after")
  expect_identical(fo_fb_close(l, 1L), 3L)
  expect_identical(fo_ch_close(l, 1L), 3L)
  expect_true(fo_ch_closed(l, 1L))
})

test_that("R3: an unclosed fence swallows a later metadata block", {
  l <- c("```{r}", "x", "", "---", "k: v", "---")
  expect_identical(fo_mb_pairs(l), character())
})

test_that("R3 (lints): an unclosed {r} fence gives the findings of the same fence closed on a last line", {
  open <- c("```{r}", "x <- 1", "`r foo`{.num}")
  closed <- c(open, "```")
  a <- fo_lint(open)
  b <- fo_lint(closed)
  expect_identical(a, b)
  # and the construct on line 3 is code, not prose, so no construct finding comes from it
  expect_false(any(a$rule == "construct" & a$line == 3L))
})

# ---- R4: fences and block quotes -------------------------------------------------------------------------

test_that("R4: a fence opened in a block quote ends where its quote ends, if nothing closes it first", {
  l <- c("> ```{r}", "> x", "", "para")
  fb <- fo_fb_close(l, 1L)
  ch <- fo_ch_close(l, 1L)
  # the quote's last line is 2; the blank line 3 ends the quote. Either is the quote's end; a run to
  # line 4 is not
  expect_true(fb %in% 2:3)
  expect_true(ch %in% 2:3)
  expect_identical(fb, ch)
  expect_false(fo_ch_closed(l, 1L))
})

test_that("R4: a quoted fence closed by a quoted closer is closed", {
  l <- c("> ```{r}", "> x", "> ```", "after")
  expect_identical(fo_fb_close(l, 1L), 3L)
  expect_identical(fo_ch_close(l, 1L), 3L)
  expect_true(fo_ch_closed(l, 1L))
})

test_that("R4: a metadata block after a quoted unclosed fence is read", {
  l <- c("> ```", "> a", "", "---", "k: v", "---", "t")
  expect_identical(fo_mb_pairs(l), "4-6")
})

test_that("R4: a quoted line does not close a fence that started outside a quote", {
  l <- c("```{r}", "> ```", "x")
  expect_identical(fo_fb_close(l, 1L), 3L)
  expect_identical(fo_ch_close(l, 1L), 3L)
  expect_false(fo_ch_closed(l, 1L))
  expect_identical(fo_mb_pairs(c("```", "> ```", "", "---", "k: v", "---")), character())
})

test_that("R4 (scan_text, find_fences): prose after a quoted unclosed fence is scanned as it would be unquoted", {
  quoted <- c("> ```", "> code", "", "Prose `r x`{.num} here.")
  plain <- c("code", "code", "", "Prose `r x`{.num} here.")
  expect_identical(fo_scan(quoted)$line, fo_scan(plain)$line)
  expect_gte(nrow(fo_scan(quoted)), 1L)
})

test_that("R4 (scan_text, find_fences): a metadata block after a quoted unclosed fence is scanned as a block", {
  tail <- c("", "---", "abstract: |", "  Text `r x`{.num}", "---")
  quoted <- c("> ```", "> code", tail)
  plain <- c("code", "code", tail)
  # offsets differ by the "> " prefix, so compare the lines and expressions
  expect_identical(fo_scan(quoted)[c("line", "expr")], fo_scan(plain)[c("line", "expr")])
  expect_gte(nrow(fo_scan(plain)), 1L)
})

test_that("R4 (scan_text, find_fences): a quoted line does not close an outside fence, so its text is not scanned", {
  expect_equal(nrow(fo_scan(c("```", "> ```", "`r x`{.num}"))), 0L)
  r <- fo_scan(c("```", "> ```", "`r x`{.num}", "```", "`r y`{.num}"))
  expect_identical(r$line, 5L)
})

# ---- R5: fences hide front matter; comments hide fences ------------------------------------------------

test_that("R5: a YAML block inside a fence is not front matter, for every finder", {
  l <- c("```", "---", "weft:", "  chunk_claims: collect", "---", "```")
  expect_identical(fo_mb_pairs(l), character())
  expect_identical(weft:::front_block(l), character())
  expect_null(fo_claims(l))
  # the control: the same block with no fence is front matter
  expect_identical(fo_claims(l[2:5]), "collect")
})

test_that("R5: a block inside an unclosed fence, or a tilde fence, is not front matter", {
  expect_null(fo_claims(c("```{r}", "---", "weft:", "  chunk_claims: collect", "---")))
  expect_null(fo_claims(c("~~~", "---", "weft:", "  chunk_claims: collect", "---", "~~~")))
  expect_identical(fo_mb_pairs(c("~~~", "---", "k: v", "---")), character())
})

test_that("R5: a block inside a later fence is not a later block", {
  l <- c("# T", "", "```", "", "---", "weft:", "  chunk_claims: collect", "---", "```")
  expect_identical(fo_mb_pairs(l), character())
  expect_null(fo_claims(l))
})

test_that("R5: a fence inside an HTML comment is not a fence, for every finder", {
  l <- c("<!--", "```{r}", "-->", "", "---", "weft:", "  chunk_claims: collect", "---")
  expect_true(is.na(fo_fb_close(l, 2L)))
  expect_true(is.na(fo_ch_close(l, 2L)))
  expect_identical(fo_mb_pairs(l), "5-8")
  # so the block after the comment is read
  expect_identical(fo_claims(l), "collect")
})

test_that("R5 (lints): a {r} chunk inside an HTML comment gets no chunk finding", {
  r <- fo_lint(c("<!--", "```{r}", "x <- 1", "```", "-->"))
  expect_false(any(r$rule == "chunk-label"))
})
