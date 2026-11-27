# The html target of the formatters and of format() (stage H1 of dev/design-html-target.md: rules RT1 to
# RT6, HR1 to HR7, messages E100, E107 to E109, decision D104). The H0 results amend the design: format()
# returns class c("html", "character") plus attr "html" = TRUE; HR2 also escapes ' and ", each - of a run of
# two or more, and each . of a run of three or more. Rows come from helper-target-rich.R. ASCII only.

# ---- HR2, HR4: the rows of section 3 ------------------------------------------------------------------

test_that("HR2, HR4, RT2: every fmt_*() row of the numbers and classes table under target = \"html\"", {
  rich_expect_fmt_rows(RICH_FMT_ROWS, "html", "html")
})

test_that("HR4, RT6: every unit row under target = \"html\"", {
  rich_expect_fmt_rows(RICH_UNIT_ROWS, "html", "html")
})

test_that("HR2, HR3, HR4, HR5, HR6, HR7, RT4: every row of text an author writes in weft()", {
  rich_expect_text_rows(RICH_TEXT_ROWS, "html", "html")
})

test_that("HR2 (H0): straight quotes, runs of dashes and runs of dots are numeric entities", {
  rich_expect_text_rows(RICH_H0_ROWS, "html", "html")
})

test_that("HR3: the start of the text", {
  rich_expect_text_rows(RICH_START_ROWS, "html", "html")
})

# ---- HR1, HR4, HR5, HR6 -------------------------------------------------------------------------------------

test_that("HR1: no tag outside i, b, sup, sub, span and br is ever written", {
  g2_cfg(NULL)
  texts <- c(vapply(RICH_FMT_ROWS, function(r) f2_tx(r$f(target = "html")), ""),
             vapply(RICH_UNIT_ROWS, function(r) f2_tx(r$f(target = "html")), ""),
             vapply(RICH_TEXT_ROWS, function(r) rich_fmt_text(rich_weft(r$x), "html"), ""))
  tags <- unlist(regmatches(texts, gregexpr("</?[A-Za-z][A-Za-z0-9]*", texts)))
  expect_true(all(sub("^</?", "", tags) %in% c("i", "b", "sup", "sub", "span", "br")))
})

test_that("HR4: strong emphasis is an em and a strong nested; an empty run writes nothing", {
  g2_cfg(NULL)
  expect_match(rich_fmt_text(weft("***x***"), "html"), "^(<i><b>x</b></i>|<b><i>x</i></b>)$")
  expect_identical(rich_fmt_text(weft("a[]{.x}b"), "html"), "ab")
  expect_identical(rich_fmt_text(weft("[x]{}"), "html"), "x")
})

test_that("HR5: each newline is <br>, \\r\\n is one, two newlines are <br><br>", {
  g2_cfg(NULL)
  expect_identical(rich_fmt_text(weft("a\r\nb"), "html"), "a<br>b")
  expect_identical(rich_fmt_text(weft("a\nb"), "html"), "a<br>b")
  expect_identical(rich_fmt_text(weft("a\n\nb"), "html"), "a<br><br>b")
})

test_that("HR6: span attributes are id, class, the keys style, title, lang and dir, then data-KEY, in that order", {
  g2_cfg(NULL)
  h <- function(x) rich_fmt_text(weft(x), "html")
  expect_identical(h("[x]{.a .b}"), "<span class=\"a b\">x</span>")
  expect_identical(h("[x]{k='v' .c #i}"), "<span id=\"i\" class=\"c\" data-k=\"v\">x</span>")
  expect_identical(h("[x]{lang='en' dir='rtl' title='t'}"), "<span lang=\"en\" dir=\"rtl\" title=\"t\">x</span>")
  expect_identical(h("[x]{title='a & b <c>'}"), "<span title=\"a &amp; b &lt;c&gt;\">x</span>")
  expect_identical(h("[x]{title='say \"hi\"'}"), "<span title=\"say &quot;hi&quot;\">x</span>")
  expect_identical(h("[x]{title='a*b'}"), "<span title=\"a&#42;b\">x</span>")
})

# ---- RT3: the attribute; markdown is unchanged --------------------------------------------------------------

test_that("RT3: the result carries target = \"html\", the printed record and the unit attribute", {
  g2_cfg(NULL)
  x <- fmt_num(5, target = "html")
  expect_s3_class(x, "weft_text")
  expect_identical(attr(x, "target"), "html")
  expect_equal(attr(x, "number"), 5)
  y <- fmt_num(u(5, m^2), target = "html")
  expect_identical(attr(y, "unit"), "m<sup>2</sup>")
  expect_identical(attr(y, "target"), "html")
  expect_false(is.null(attr(y, "unit_form")))
})

test_that("RT2: with target = \"markdown\" every row is as it is with no target, and has no target attribute", {
  for (r in c(RICH_FMT_ROWS, RICH_UNIT_ROWS)) {
    g2_cfg(r$yml)
    a <- r$f()
    b <- r$f(target = "markdown")
    expect_identical(b, a, label = paste("row", r$id))
    expect_null(attr(b, "target"), label = paste("row", r$id))
  }
})

test_that("RT4: format(weft, target = \"markdown\") is not an html object", {
  x <- format(weft("a *b*"), target = "markdown")
  expect_false(inherits(x, "html"))
  expect_null(attr(x, "html"))
})

# ---- the plain reading agrees ------------------------------------------------------------------------------

html_text_of <- function(h) {
  h <- gsub("<br>", "\n", h, fixed = TRUE)
  xml2::xml_text(xml2::read_html(paste0("<body>", h, "</body>"), encoding = "UTF-8"))
}

test_that("HR1, HR2: the text of the HTML is the plain form, for every row with no superscript, span or formula", {
  skip_if_not_installed("xml2")
  fmt <- Filter(function(r) r$plain, c(RICH_FMT_ROWS, RICH_UNIT_ROWS))
  for (r in fmt) {
    g2_cfg(r$yml)
    expect_identical(html_text_of(f2_tx(r$f(target = "html"))), f2_tx(r$f(target = "plain")),
                     label = paste("row", r$id))
  }
  g2_cfg(NULL)
  for (r in Filter(function(r) r$plain, c(RICH_TEXT_ROWS, RICH_H0_ROWS, RICH_START_ROWS))) {
    w <- rich_weft(r$x)
    expect_identical(html_text_of(rich_fmt_text(w, "html")), unname(as.character(w)), label = paste("row", r$id))
  }
})

# ---- D88: the HTML survives the markdown pass ggtext makes ----------------------------------------------------

md_pass <- function(h) {
  out <- markdown::markdownToHTML(text = h, options = c("use_xhtml", "fragment_only"))
  out <- sub("^<p>", "", out)
  sub("</p>\n?$", "", out)
}
dom_of <- function(h) {
  doc <- xml2::read_html(paste0("<body>", h, "</body>"), encoding = "UTF-8")
  body <- xml2::xml_find_first(doc, "//body")
  list(text = xml2::xml_text(body), names = xml2::xml_name(xml2::xml_find_all(body, ".//*")))
}

test_that("D88, HR2, HR3: every html row reads the same after the markdown pass (text and element names)", {
  skip_if_not_installed("ggtext")
  skip_if_not_installed("markdown")
  skip_if_not_installed("xml2")
  hs <- character()
  for (r in c(RICH_FMT_ROWS, RICH_UNIT_ROWS)) {
    g2_cfg(r$yml)
    hs[[r$id]] <- f2_tx(r$f(target = "html"))
  }
  g2_cfg(NULL)
  for (r in c(RICH_TEXT_ROWS, RICH_H0_ROWS, RICH_START_ROWS)) hs[[r$id]] <- rich_fmt_text(rich_weft(r$x), "html")
  for (id in names(hs)) {
    expect_identical(dom_of(md_pass(hs[[id]])), dom_of(hs[[id]]), label = paste("row", id))
  }
})

test_that("D91: a list in html gives no ul or li element after the markdown pass", {
  skip_if_not_installed("ggtext")
  skip_if_not_installed("markdown")
  skip_if_not_installed("xml2")
  g2_cfg(NULL)
  for (f in list(fmt_ul, fmt_ol)) {
    h <- f2_tx(f(c("a", "b"), target = "html"))
    expect_false(any(c("ul", "ol", "li") %in% dom_of(md_pass(h))$names))
  }
})

# ---- RT4: format() ---------------------------------------------------------------------------------------------

test_that("RT4, D98 (H0): format(x, target = \"html\") has class c(\"html\", \"character\") and attr html = TRUE", {
  x <- format(weft("a"), target = "html")
  expect_identical(class(x), c("html", "character"))
  expect_true(isTRUE(attr(x, "html")))
  y <- format(weft(c(k = "a", m = "b")), target = "html")
  expect_identical(names(y), c("k", "m"))
  expect_identical(class(y), c("html", "character"))
})

test_that("RT4: NA is \"NA\" and names are kept", {
  x <- format(weft(c(k = "a *b*", m = NA_character_)), target = "html")
  expect_identical(unname(unclass(x)), c("a <i>b</i>", "NA"))
  expect_identical(names(x), c("k", "m"))
})

test_that("RT4: an element joined as text is escaped as text, not read again as markdown", {
  x <- c(weft("a"), "b*c*", "d_e_")
  expect_identical(unname(as.character(unclass(format(x, target = "html")))),
                   c("a", "b&#42;c&#42;", "d&#95;e&#95;"))
})

test_that("RT1: every fmt_*() takes target = \"html\" and returns a weft_text with that target", {
  g2_cfg(NULL)
  fns <- sort(grep("^fmt_", getNamespaceExports("weft"), value = TRUE))
  expect_setequal(fns, names(RICH_CALLS))
  for (nm in fns) {
    x <- RICH_CALLS[[nm]](target = "html")
    expect_s3_class(x, "weft_text")
    expect_identical(attr(x, "target"), "html", label = nm)
    expect_false(grepl("[*_`\\\\^~$]", gsub("&#[0-9]+;|&[a-z]+;", "", gsub("<[^>]+>", "", f2_tx(x)))), label = nm)
  }
})

# ---- RT1, E100 -------------------------------------------------------------------------------------------------

test_that("RT1, E100: the message of a bad target names html and marquee", {
  e <- f2_cond(fmt_num(1, target = "rtf"))
  rich_expect_error(e, "weft_construct_error", RICH_E100("rtf"))
  e <- f2_cond(weft:::apply_formatters(3, ".num", target = "rtf"))
  rich_expect_error(e, "weft_construct_error", RICH_E100("rtf"))
})

test_that("RT1: the message of a bad target of format() names html and marquee", {
  e <- f2_cond(format(weft("a"), target = "rtf"))
  rich_expect_error(e, "weft_construct_error", RICH_E100_FORMAT("rtf"))
})

test_that("RT1: html and marquee are accepted by apply_formatters() and format()", {
  g2_cfg(NULL)
  for (t in c("html", "marquee")) {
    expect_null(f2_cond(weft:::apply_formatters(3, ".num", target = t)))
    expect_null(f2_cond(format(weft("a"), target = t)))
  }
})

# ---- RT5: mixing ------------------------------------------------------------------------------------------------

test_that("RT5, E107: an html text cannot be formatted again, except from its number", {
  g2_cfg(NULL)
  h <- fmt_num(5, target = "html")
  rich_expect_error(f2_cond(fmt_strong(h)), "weft_value_error", RICH_E107("HTML", "html"))
  rich_expect_error(f2_cond(fmt_strong(h, target = "html")), "weft_value_error", RICH_E107("HTML", "html"))
  expect_identical(f2_tx(fmt_num(h)), "5")
  expect_identical(f2_tx(fmt_strong(fmt_num(5), target = "html")), "<b>5</b>")
})

test_that("RT5, E108: a TeX text reaching an html result", {
  g2_cfg(NULL)
  e <- f2_cond(fmt_strong(fmt_num(5, target = "tex"), target = "html"))
  rich_expect_error(e, "weft_value_error", RICH_E108("HTML", "html"))
})

test_that("RT5, E109: an html or TeX text cannot join a weft object; a plain one can", {
  g2_cfg(NULL)
  rich_expect_error(f2_cond(c(weft("a"), fmt_num(5, target = "html"))), "weft_construct_error",
                    RICH_E109("HTML", "html"))
  w <- weft(c("a", "b"))
  e <- f2_cond(w[2] <- fmt_num(5, target = "tex"))
  rich_expect_error(e, "weft_construct_error", RICH_E109("TeX", "tex"))
  expect_null(f2_cond(c(weft("a"), fmt_num(5, target = "plain"))))
  expect_null(f2_cond(c(weft("a"), fmt_num(5))))
})

# ---- RT6 --------------------------------------------------------------------------------------------------------

test_that("RT6: fmt_unit() takes target = \"html\"", {
  g2_cfg(NULL)
  x <- fmt_unit(u(1, m^2), target = "html")
  expect_identical(f2_tx(x), "m<sup>2</sup>")
  expect_identical(attr(x, "target"), "html")
})

# ---- D104: project formatters ---------------------------------------------------------------------------------

test_that("D104, RT2: a project formatter's markdown is read and rendered under html", {
  rich_install("fmt_tidy", function(x, ...) paste0("*", x, "*"))
  g2_cfg(rich_reg(".tidy", "fmt_tidy"))
  expect_identical(rich_fmt_text(weft("`r 3`{.tidy}"), "html"), "<i>3</i>")
})

test_that("D104, RT2: a formatter that lists tex is called with target = \"markdown\" under html", {
  store <- new.env()
  store$seen <- character()
  rich_install("fmt_seen", function(x, target = "markdown", ...) {
    store$seen <- c(store$seen, target)
    paste0("[", x, "]")
  })
  g2_cfg(rich_reg(".seen", "fmt_seen", extra = "    targets: [markdown, tex]"))
  out <- rich_fmt_text(weft("`r 3`{.seen}"), "html")
  expect_true(length(store$seen) >= 1L)
  expect_true(all(store$seen == "markdown"))
  expect_identical(out, "&#91;3&#93;")
})

test_that("D104, rule 1.4.8: targets: lists markdown and optionally tex; plain, html and marquee are refused", {
  rich_install("fmt_notarget", function(x, ...) "ok")
  bad <- list(
    list("[markdown, plain]", "markdown, plain"), list("[plain]", "plain"),
    list("[markdown, html]", "markdown, html"), list("[markdown, marquee]", "markdown, marquee"),
    list("[markdown, tex, plain]", "markdown, tex, plain"), list("[html]", "html"))
  for (b in bad) {
    e <- g2_cfg_err(rich_reg(".badt", "fmt_notarget", "number", paste0("    targets: ", b[[1]])))
    rich_expect_error(e, "weft_config_error", RICH_E104(".badt", b[[2]]))
  }
})

test_that("D104, rule 1.4.8: the accepted forms of targets: still read", {
  rich_install("fmt_notarget", function(x, ...) "ok")
  for (t in c("[markdown]", "[markdown, tex]", "[tex, markdown]")) {
    expect_null(g2_cfg_err(rich_reg(".okt", "fmt_notarget", "number", paste0("    targets: ", t))), label = t)
  }
})

# ---- HR7: a collected failure ---------------------------------------------------------------------------------

test_that("HR7, RT4: in a knit in draft mode, a failure marker formatted for html is text", {
  chunk <- c("```{r wz, results='asis', echo=FALSE}",
             "x <- weft::weft(\"`zz`{.num}\")", "cat('GOT:', format(x, target = 'html'), '\\n')", "```", "")
  d <- b6_knit(chunk, draft = TRUE)
  b6_expect_knitted(d)
  expect_true(any(grepl("&lt;&lt;weft: no value, [a-z]+ [A-Za-z0-9_.-]+&gt;&gt;", d$text)))
  expect_false(any(grepl("<<weft:", d$text, fixed = TRUE)))
})

# ---- speed ----------------------------------------------------------------------------------------------------

test_that("RT2: 200 html formats take less than twice as long as 200 plain formats", {
  skip_on_cran()
  w <- weft("a *b* 10^2^")
  t_html <- system.time(for (i in 1:200) format(w, target = "html"))[["elapsed"]]
  t_plain <- system.time(for (i in 1:200) format(w, target = "plain"))[["elapsed"]]
  expect_lt(t_html, 2 * max(t_plain, 0.05))
})
