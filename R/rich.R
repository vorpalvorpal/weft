# The html and marquee targets (dev/design-html-target.md; spec rules 1.4.25 and 1.4.26): renderers over
# the runs the plain reader makes (R/plain.R), as the ANSI target is. A formatter under one of them runs
# as under markdown, and its text is read by PL1 to PL10 and written by HR (html) or MQ (marquee), so the
# three derived targets (plain, html, marquee) never disagree on what a text says.

# The targets whose text is the markdown read by PL and rendered (RT2).
DERIVED_TARGETS <- c("plain", "html", "marquee")

# How a target is named in a message (E107 to E109).
TARGET_WORDS <- c(tex = "TeX", html = "HTML", marquee = "marquee")

# ---- shared ----------------------------------------------------------------------------------

# The runs of one markdown string; a string with none of the characters a rule starts on is one text run.
rich_read <- function(s) {
  if (grepl(PLAIN_SPECIAL_RE, s, perl = TRUE)) plain_read(s) else list(plain_run("text", text = s))
}

rich_render <- function(runs, kind) {
  if (identical(kind, "html")) html_render(runs) else marquee_render(runs)
}

# The text of markdown `x` under the derived target `kind`, element by element (an NA stays NA).
rich_text <- function(x, kind) {
  if (identical(kind, "plain")) return(plain_text(x))
  if (!length(x)) return(x)
  x <- as.character(x)
  ok <- !is.na(x)
  x[ok] <- vapply(x[ok], function(s) rich_render(rich_read(s), kind), "", USE.NAMES = FALSE)
  x
}

# The result of a formatter under a derived target (FT1, RT2, RT3): its text, its unit and its unit
# suffixes read by PL and rendered; every other attribute kept.
derived_finish <- function(out, kind) {
  a <- attributes(out)
  x <- rich_text(as.character(unclass(out)), kind)
  attributes(x) <- a
  if (!is.null(a$unit)) attr(x, "unit") <- rich_text(a$unit, kind)
  if (!is.null(a$unit_suffix)) attr(x, "unit_suffix") <- rich_text(a$unit_suffix, kind)
  attr(x, "target") <- kind
  x
}

# The html or marquee rendering of a `weft` object (RT4): names kept, NA as "NA". An element whose plain
# text is not the plain reading of its markdown (joined as text by c() or `[<-`, or changed by a function
# that kept the attributes, C4 and WS10) is its plain text, escaped as text.
weft_rich <- function(x, kind) {
  p <- weft_plain(x)
  md <- weft_md_attr(x, p)
  out <- unname(as.character(p))
  for (i in seq_along(out)) {
    if (is.na(out[[i]])) {
      out[[i]] <- "NA"
      next
    }
    runs <- if (is.na(md[[i]])) NULL else rich_read(md[[i]])
    if (is.null(runs) || !identical(out[[i]], plain_render(runs))) runs <- list(plain_run("text", text = out[[i]]))
    out[[i]] <- rich_render(runs, kind)
  }
  names(out) <- names(p)
  out
}

# ---- HR: the HTML rendering (rule 1.4.25) ------------------------------------------------------

# HR2: the characters a text run writes as entities, for HTML and for the markdown pass ggtext makes first.
HTML_ESCAPES <- c(
  "&" = "&amp;", "<" = "&lt;", ">" = "&gt;", "\"" = "&quot;", "'" = "&#39;",
  "*" = "&#42;", "_" = "&#95;", "`" = "&#96;", "\\" = "&#92;", "[" = "&#91;", "]" = "&#93;",
  "^" = "&#94;", "~" = "&#126;", "$" = "&#36;", "{" = "&#123;", "}" = "&#125;")

HTML_DIGITS <- as.character(0:9)

# HR2, HR5: a text run as HTML. In an attribute value (`attr = TRUE`) a newline is `&#10;`, not `<br>`.
html_text <- function(s, attr = FALSE) {
  if (!nzchar(s)) return("")
  ch <- strsplit(s, "", fixed = TRUE)[[1L]]
  n <- length(ch)
  out <- ch
  hit <- match(ch, names(HTML_ESCAPES))
  out[!is.na(hit)] <- HTML_ESCAPES[hit[!is.na(hit)]]
  # smartypants (markdown 1.x): a `/` between two digits makes a fraction, `(c)`, `(r)` and `(tm)` symbols
  dig <- ch %in% HTML_DIGITS
  sl <- which(ch == "/")
  sl <- sl[sl > 1L & sl < n]
  out[sl[dig[sl - 1L] & dig[sl + 1L]]] <- "&#47;"
  for (p in which(ch == "(")) {
    nxt <- if (p < n) tolower(paste(ch[(p + 1L):min(n, p + 3L)], collapse = "")) else ""
    if (startsWith(nxt, "c)") || startsWith(nxt, "r)") || startsWith(nxt, "tm)")) out[[p]] <- "&#40;"
  }
  # smartypants under every markdown version (H0): dash runs make dashes, dot runs an ellipsis
  r <- rle(ch)
  ends <- cumsum(r$lengths)
  starts <- ends - r$lengths + 1L
  for (k in which((r$values == "-" & r$lengths >= 2L) | (r$values == "." & r$lengths >= 3L))) {
    out[starts[[k]]:ends[[k]]] <- if (r$values[[k]] == "-") "&#45;" else "&#46;"
  }
  nl <- which(ch == "\n")
  if (length(nl)) {
    if (attr) {
      out[nl] <- "&#10;"
    } else {
      out[nl] <- "<br>"
      # HR5: `\r\n` is one line break
      cr <- nl[nl > 1L]
      cr <- cr[ch[cr - 1L] == "\r"] - 1L
      out[cr] <- ""
    }
  }
  paste(out, collapse = "")
}

# HR3: the start of the whole text, when it is text (a tag starts with `<`, which text never does).
html_start <- function(s) {
  if (!nzchar(s)) return(s)
  c1 <- substr(s, 1L, 1L)
  ent <- switch(c1, "#" = "&#35;", "-" = "&#45;", "+" = "&#43;", "=" = "&#61;", " " = "&#32;",
                "\t" = "&#9;", NULL)
  if (!is.null(ent)) return(paste0(ent, substring(s, 2L)))
  if (c1 %in% HTML_DIGITS) {
    m <- regmatches(s, regexec("^([0-9]+)([.)])([ \t]|$)", s))[[1L]]
    if (length(m)) {
      return(paste0(m[[2L]], if (m[[3L]] == ".") "&#46;" else "&#41;", substring(s, nchar(m[[2L]]) + 2L)))
    }
  }
  s
}

html_render <- function(runs) html_start(html_runs(runs))

html_runs <- function(runs) paste(vapply(runs, html_run, ""), collapse = "")

# HR4
html_run <- function(r) {
  switch(
    r$type,
    text = , code = , math = html_text(r$text),
    em = html_wrap("i", r$kids),
    strong = html_wrap("b", r$kids),
    sup = html_wrap("sup", r$kids),
    sub = html_wrap("sub", r$kids),
    span = html_span(r))
}

# An empty run writes nothing.
html_wrap <- function(tag, kids) {
  inner <- html_runs(kids)
  if (!nzchar(inner)) return("")
  paste0("<", tag, ">", inner, "</", tag, ">")
}

html_span <- function(r) {
  inner <- html_runs(r$kids)
  if (!nzchar(inner)) return("")
  a <- html_attrs(r$attrs)
  if (!nzchar(a)) return(inner)
  paste0("<span", a, ">", inner, "</span>")
}

HTML_OWN_KEYS <- c("style", "title", "lang", "dir")

# HR6: a span's block, read by the scanner's attribute parser, as HTML attributes (with a leading space
# each): the id, the classes, then the keys in the order written, any key but style, title, lang and dir
# as `data-KEY`, as Pandoc's HTML writer does. A block the parser refuses gives none.
html_attrs <- function(block) {
  ch <- strsplit(block, "", fixed = TRUE)[[1L]]
  b <- parse_block_strict(ch, 1L, length(ch))
  if (!isTRUE(b$ok)) return("")
  one <- function(key, value) paste0(" ", key, "=\"", html_text(value, attr = TRUE), "\"")
  out <- character()
  if (!is.na(b$id)) out <- c(out, one("id", b$id))
  if (length(b$classes)) out <- c(out, one("class", paste(substring(b$classes, 2L), collapse = " ")))
  if (length(b$names)) {
    keys <- ifelse(b$names %in% HTML_OWN_KEYS, b$names, paste0("data-", b$names))
    out <- c(out, unlist(Map(one, keys, b$values), use.names = FALSE))
  }
  paste(out, collapse = "")
}

# ---- MQ: the marquee rendering (rule 1.4.26) ---------------------------------------------------

# MQ1: the characters a text run puts a backslash before.
MQ_SPECIAL <- c("\\", "`", "*", "_", "~", "[", "]", "{", "}", "<", ">", "&", "$", "^")

# MQ1, MQ4: a text run (or a formula, H0 correction 4) as marquee text.
mq_text <- function(s) {
  if (!nzchar(s)) return("")
  s <- gsub("\r\n", "\n", s, fixed = TRUE)
  ch <- strsplit(s, "", fixed = TRUE)[[1L]]
  hit <- ch %in% MQ_SPECIAL
  ch[hit] <- paste0("\\", ch[hit])
  out <- paste(ch, collapse = "")
  if (!grepl("\n", out, fixed = TRUE)) return(out)
  # two or more newlines are a paragraph break; one is a hard break, a backslash and the newline
  out <- gsub("\n{2,}", "\001", out, perl = TRUE)
  out <- gsub("\n", "\\\n", out, fixed = TRUE)
  gsub("\001", "\n\n", out, fixed = TRUE)
}

# MQ3: a code span, fenced by one backtick more than the longest run inside, padded when an end is one.
mq_code <- function(s) {
  if (!nzchar(s)) return("")
  m <- gregexpr("`+", s)[[1L]]
  longest <- if (m[[1L]] == -1L) 0L else max(attr(m, "match.length"))
  fence <- strrep("`", longest + 1L)
  pad <- if (startsWith(s, "`") || endsWith(s, "`")) " " else ""
  paste0(fence, pad, s, pad, fence)
}

marquee_render <- function(runs) mq_lines(mq_runs(runs))

mq_runs <- function(runs) paste(vapply(runs, mq_run, ""), collapse = "")

mq_run <- function(r) {
  switch(
    r$type,
    text = , math = mq_text(r$text),
    code = mq_code(r$text),
    em = mq_wrap("em", r$kids),
    strong = mq_wrap("str", r$kids),
    sup = mq_wrap("sup", r$kids),
    sub = mq_wrap("sub", r$kids),
    span = mq_runs(r$kids))
}

# A custom span; an empty run writes nothing.
mq_wrap <- function(style, kids) {
  inner <- mq_runs(kids)
  if (!nzchar(inner)) return("")
  paste0("{.", style, " ", inner, "}")
}

# MQ2: the start of the text and of each written line.
mq_lines <- function(s) {
  if (!grepl("\n", s, fixed = TRUE)) return(mq_line_start(s))
  lines <- strsplit(s, "\n", fixed = TRUE)[[1L]]
  if (endsWith(s, "\n")) lines <- c(lines, "")
  paste(vapply(lines, mq_line_start, "", USE.NAMES = FALSE), collapse = "\n")
}

mq_line_start <- function(l) {
  if (!nzchar(l)) return(l)
  lead <- regexpr("^[ \t]+", l)
  if (lead > 0L) {
    # a no-break space for each leading space or tab, so that four make no indented code block
    k <- attr(lead, "match.length")
    return(paste0(strrep("\u00a0", k), substring(l, k + 1L)))
  }
  if (substr(l, 1L, 1L) %in% c("#", "-", "+", "=", ":")) return(paste0("\\", l))
  sub("^([0-9]+)([.)])([ \t]|$)", "\\1\\\\\\2\\3", l)
}
