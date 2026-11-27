# A18: one fence finder. The finders that see fences must agree, by the rulings R1 to R5. Plain fences follow
# CommonMark (as Pandoc reads them); executable chunks (`{r}`, ...) are found as knitr finds them, because
# knitr replaces each chunk with its output before Pandoc reads anything. The knitr facts below were checked
# by knitting small documents (knitr::all_patterns$md: begin `^[\t >]*```+\s*\{engine...\}\s*$`, end
# `^[\t >]*```+\s*$`):
#   a backtick in a chunk header is fine; a chunk may be indented any amount (4 spaces at top level or in a
#   list item runs); a chunk inside <!-- --> runs; a chunk is closed by the first line of 3 or more
#   backticks and spaces, at any indent, with or without a `>`, of any length (a shorter or a longer one
#   closes; "``` y" does not); an unquoted chunk is closed by a quoted "> ```" line, and a quoted chunk by
#   an unquoted one; a quoted chunk with no closer runs to the end of the file (not to the end of its
#   quote); an unclosed chunk runs to the end; tilde `~~~{r}` is not a chunk, and a `~~~` line does not
#   end a `{r}` chunk (knitr runs it as R code; checked by the orchestrator, 27 Nov).
# The rulings for plain fences:
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

test_that("R1 (plain): a backtick fence with a backtick in its info is not a fence, for fence_blocks()", {
  expect_true(is.na(fo_fb_close(c("``` a`b", "text", "```"), 1L)))
})

test_that("R1 (plain): a tilde fence's info string may hold a backtick", {
  expect_identical(fo_fb_close(c("~~~ a`b", "x", "~~~"), 1L), 3L)
})

test_that("R1 (plain): metadata_blocks() reads a block after a line that is not a fence opener", {
  expect_identical(fo_mb_pairs(c("``` a`b", "", "---", "k: v", "---")), "3-5")
})

test_that("R1 (plain): metadata_blocks() reads no block inside a tilde fence whose info holds a backtick", {
  expect_identical(fo_mb_pairs(c("~~~ a`b", "", "---", "k: v", "---", "~~~")), character())
})

test_that("R1 (chunk): knitr runs a chunk whose header holds a backtick, so every finder sees it", {
  l <- c("```{r a`b}", "x <- 1", "```")
  expect_identical(fo_fb_close(l, 1L), 3L)
  expect_identical(fo_ch_close(l, 1L), 3L)
  expect_true(fo_ch_closed(l, 1L))
})

test_that("R1 (chunk, metadata): a block inside a chunk with a backtick in its header is not a block", {
  l <- c("```{r a`b}", "---", "k: v", "---", "```")
  expect_identical(fo_mb_pairs(l), character())
})

test_that("R1 (lints): a chunk with a backtick in its header is a chunk and gets its chunk finding", {
  # (ruling 27 Nov: `{r a`b}` is labelled "a`b", so an unlabelled header is what tests it)
  r <- fo_lint(c("```{r, fig.cap = \"a`b\"}", "x <- 1", "```"))
  expect_true(any(r$rule == "chunk-label" & r$line == 1L))
  # the plain twin is text and gets none
  r2 <- fo_lint(c("``` a`b", "x <- 1", "```"))
  expect_false(any(r2$rule == "chunk-label"))
})

# ---- R2: closers and indentation -------------------------------------------------------------------------

test_that("R2 (plain): a closer needs the same character, at least the opener's length, and only spaces after", {
  expect_identical(fo_fb_close(c("```text", "x", "`````"), 1L), 3L)          # longer closes
  expect_identical(fo_fb_close(c("```text", "x", "```   ", "y"), 1L), 3L)     # trailing spaces
  expect_identical(fo_fb_close(c("```text", "x", "``` y", "z", "```"), 1L), 5L) # text after: not a closer
  expect_identical(fo_fb_close(c("```text", "x", "~~~", "```"), 1L), 4L)      # other character
  expect_identical(fo_fb_close(c("````text", "x", "```", "y", "````"), 1L), 5L) # shorter: not a closer
})

test_that("R2 (plain): a fence may be indented up to 3 spaces", {
  expect_identical(fo_fb_close(c("   ```text", "x", "   ```"), 1L), 3L)
  expect_identical(fo_mb_pairs(c("   ```", "", "---", "k: v", "---", "   ```")), character())
})

test_that("R2 (plain): 4 spaces is indented code, not a fence", {
  expect_true(is.na(fo_fb_close(c("    ```", "x", "    ```"), 1L)))
  expect_identical(fo_mb_pairs(c("    ```", "", "---", "k: v", "---")), "3-5")
})

test_that("R2 (chunk): a chunk closer is 3 or more backticks and spaces, of any length, as knitr reads it", {
  # a longer closer closes
  l1 <- c("```{r}", "x", "`````")
  expect_identical(fo_fb_close(l1, 1L), 3L)
  expect_identical(fo_ch_close(l1, 1L), 3L)
  # trailing spaces are allowed
  l2 <- c("```{r}", "x", "```   ", "y")
  expect_identical(fo_fb_close(l2, 1L), 3L)
  expect_identical(fo_ch_close(l2, 1L), 3L)
  # text after the closer: not a closer, the chunk runs on to the real one
  l3 <- c("```{r}", "x", "``` y", "z", "```")
  expect_identical(fo_fb_close(l3, 1L), 5L)
  expect_identical(fo_ch_close(l3, 1L), 5L)
  # a SHORTER closer closes a longer opener in knitr (it checks 3 or more, not the opener's length)
  l5 <- c("````{r}", "x", "```", "y", "````")
  expect_identical(fo_fb_close(l5, 1L), 3L)
  expect_identical(fo_ch_close(l5, 1L), 3L)
  # an indented closer closes, whatever the indent
  l6 <- c("```{r}", "x", "    ```", "y")
  expect_identical(fo_fb_close(l6, 1L), 3L)
  expect_identical(fo_ch_close(l6, 1L), 3L)
})

test_that("R2 (chunk): a `~~~` line does not end a {r} chunk; knitr's end pattern is backticks only", {
  l <- c("```{r}", "x", "~~~", "y", "```")
  expect_identical(fo_fb_close(l, 1L), 5L)
  expect_identical(fo_ch_close(l, 1L), 5L)
})

test_that("R2 (chunk): a chunk may be indented 3 spaces, 4 spaces, or sit in a list item, as knitr runs it", {
  l <- c("   ```{r}", "x", "   ```")
  expect_identical(fo_fb_close(l, 1L), 3L)
  expect_identical(fo_ch_close(l, 1L), 3L)
  l4 <- c("para", "", "    ```{r}", "    x", "    ```")
  expect_identical(fo_fb_close(l4, 3L), 5L)
  expect_identical(fo_ch_close(l4, 3L), 5L)
  ll <- c("- item", "", "    ```{r}", "    x", "    ```")
  expect_identical(fo_fb_close(ll, 3L), 5L)
  expect_identical(fo_ch_close(ll, 3L), 5L)
})

# ---- R3: an unclosed fence runs to line n ---------------------------------------------------------------

test_that("R3 (chunk): an unclosed chunk ends at the last line n in every finder, and is marked unclosed", {
  l <- c("```{r}", "x <- 1", "y <- 2")
  expect_identical(fo_fb_close(l, 1L), 3L)
  expect_identical(fo_ch_close(l, 1L), 3L)
  expect_false(fo_ch_closed(l, 1L))
})

test_that("R3 (plain and chunk): trailing blank lines are part of the unclosed fence", {
  expect_identical(fo_fb_close(c("~~~", "x <- 1", "", ""), 1L), 4L)
  expect_identical(fo_fb_close(c("```", "text"), 1L), 2L)
  l <- c("```{r}", "x <- 1", "", "")
  expect_identical(fo_fb_close(l, 1L), 4L)
  expect_identical(fo_ch_close(l, 1L), 4L)
  expect_false(fo_ch_closed(l, 1L))
})

test_that("R3: a closed fence is marked closed, and its close is the closer", {
  l <- c("```{r}", "x <- 1", "```", "after")
  expect_identical(fo_fb_close(l, 1L), 3L)
  expect_identical(fo_ch_close(l, 1L), 3L)
  expect_true(fo_ch_closed(l, 1L))
})

test_that("R3: an unclosed fence, plain or chunk, swallows a later metadata block", {
  expect_identical(fo_mb_pairs(c("```{r}", "x", "", "---", "k: v", "---")), character())
  expect_identical(fo_mb_pairs(c("```text", "x", "", "---", "k: v", "---")), character())
})

test_that("R3 (lints): an unclosed {r} fence gives the findings of the same fence closed on a last line", {
  open <- c("```{r}", "x <- 1", "`r foo`{.num}")
  closed <- c(open, "```")
  a <- fo_lint(open)
  b <- fo_lint(closed)
  expect_identical(a, b)
  expect_false(any(a$rule == "construct" & a$line == 3L))
})

# ---- R4: fences and block quotes -------------------------------------------------------------------------

test_that("R4 (plain): a quoted, unclosed fence closes at its quote's last line", {
  l <- c("> ```", "> x", "", "para")
  expect_identical(fo_fb_close(l, 1L), 2L)
})

test_that("R4 (plain): a quoted fence closed by a quoted closer is closed", {
  expect_identical(fo_fb_close(c("> ```", "> x", "> ```", "after"), 1L), 3L)
})

test_that("R4 (plain): a metadata block after a quoted unclosed fence is read", {
  expect_identical(fo_mb_pairs(c("> ```", "> a", "", "---", "k: v", "---", "t")), "4-6")
})

test_that("R4 (plain): a quoted line does not close a fence that started outside a quote", {
  expect_identical(fo_fb_close(c("```", "> ```", "x"), 1L), 3L)
  expect_identical(fo_mb_pairs(c("```", "> ```", "", "---", "k: v", "---")), character())
})

test_that("R4 (chunk): knitr's rule is the engine's, not the quote's: a quoted line closes an unquoted chunk", {
  l <- c("```{r}", "> ```", "x")
  expect_identical(fo_fb_close(l, 1L), 2L)
  expect_identical(fo_ch_close(l, 1L), 2L)
  expect_true(fo_ch_closed(l, 1L))
})

test_that("R4 (chunk): an unquoted closer closes a quoted chunk, and a quoted closer too", {
  l1 <- c("> ```{r}", "> x", "```", "text")
  expect_identical(fo_fb_close(l1, 1L), 3L)
  expect_identical(fo_ch_close(l1, 1L), 3L)
  l2 <- c("> ```{r}", "> x", "> ```", "after")
  expect_identical(fo_fb_close(l2, 1L), 3L)
  expect_identical(fo_ch_close(l2, 1L), 3L)
  expect_true(fo_ch_closed(l2, 1L))
})

test_that("R4 (chunk): a quoted chunk with no closer runs to the end of the file, not the end of its quote", {
  l <- c("> ```{r}", "> x", "", "para")
  expect_identical(fo_fb_close(l, 1L), 4L)
  expect_identical(fo_ch_close(l, 1L), 4L)
  expect_false(fo_ch_closed(l, 1L))
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

# (ruling 27 Nov: knitr runs inline R in a plain fence, test-scan.R "inline R in a fenced block that
# is not a chunk is read", so a bracketed span, which a fence does hide, tests the rule)
test_that("R4 (scan_text, find_fences): a quoted line does not close an outside fence, so its text is not scanned", {
  expect_equal(nrow(fo_scan(c("```", "> ```", "[a | b]{if=\"x\"}"))), 0L)
  r <- fo_scan(c("```", "> ```", "[a | b]{if=\"x\"}", "```", "[c | d]{if=\"y\"}"))
  expect_identical(r$line, 5L)
})

# ---- R5: fences hide front matter; comments hide plain fences ---------------------------------------------

test_that("R5: a YAML block inside a fence, plain or chunk, is not front matter, for every finder", {
  for (open in c("```", "```text", "```{r}", "~~~")) {
    close <- if (open == "~~~") "~~~" else "```"
    l <- c(open, "---", "weft:", "  chunk_claims: collect", "---", close)
    expect_identical(fo_mb_pairs(l), character(), label = open)
    expect_identical(weft:::front_block(l), character(), label = open)
    expect_null(fo_claims(l), label = open)
  }
  # the control: the same block with no fence is front matter
  expect_identical(fo_claims(c("---", "weft:", "  chunk_claims: collect", "---")), "collect")
})

test_that("R5: a block inside an unclosed fence is not front matter", {
  expect_null(fo_claims(c("```{r}", "---", "weft:", "  chunk_claims: collect", "---")))
  expect_null(fo_claims(c("```", "---", "weft:", "  chunk_claims: collect", "---")))
  expect_identical(fo_mb_pairs(c("~~~", "---", "k: v", "---")), character())
})

test_that("R5: a block inside a later fence is not a later block", {
  l <- c("# T", "", "```", "", "---", "weft:", "  chunk_claims: collect", "---", "```")
  expect_identical(fo_mb_pairs(l), character())
  expect_null(fo_claims(l))
})

test_that("R5 (plain): a plain fence inside an HTML comment is not a fence", {
  l <- c("<!--", "```", "-->", "", "---", "weft:", "  chunk_claims: collect", "---")
  expect_true(is.na(fo_fb_close(l, 2L)))
  expect_identical(fo_mb_pairs(l), "5-8")
  expect_identical(fo_claims(l), "collect")
})

test_that("R5 (chunk): knitr runs a chunk inside an HTML comment, so every finder sees it", {
  l <- c("<!--", "```{r}", "x <- 1", "```", "-->")
  expect_identical(fo_fb_close(l, 2L), 4L)
  expect_identical(fo_ch_close(l, 2L), 4L)
  expect_true(fo_ch_closed(l, 2L))
})

test_that("R5 (chunk): knitr finds a chunk opened inside a plain fence", {
  l <- c("```text", "```{r}", "x", "```", "y", "```")
  expect_identical(fo_ch_close(l, 2L), 4L)
})

test_that("R5 (lints): a {r} chunk inside an HTML comment gets its chunk finding; a plain fence there gets none", {
  r <- fo_lint(c("<!--", "```{r}", "x <- 1", "```", "-->"))
  expect_true(any(r$rule == "chunk-label" & r$line == 2L))
})
