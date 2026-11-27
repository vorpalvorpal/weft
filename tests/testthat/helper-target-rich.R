# Shared rows for the html and marquee targets (dev/design-html-target.md, sections 3 and 6, with the
# H0 corrections applied: HR2 gains quotes, dash runs and dot runs; math in marquee is escaped as text;
# E110, MQ6, D103 and marquee_version() are gone). ASCII only: non-ASCII is written as \u escapes.
# Helpers used: helper-2g.R (g2_cfg, g2_cfg_err), helper-2f.R (f2_tx, f2_cond).
#
# A formatter row:  id, f (a function of `...` that calls the formatter with `...` last), yml (the
#   _weft.yml lines it needs, or NULL), html, mq, plain (TRUE when the markdown holds no superscript,
#   subscript, span or formula, so the plain text must equal the text of the HTML).
# An author-text row: id, x (a string given to weft(), or a function that returns a weft object), html,
#   mq, plain.

rich_row <- function(id, f, html, mq, yml = NULL, plain = FALSE) {
  list(id = id, f = f, html = html, mq = mq, yml = yml, plain = plain)
}
rich_w <- function(id, x, html, mq, plain = FALSE) {
  list(id = id, x = x, html = html, mq = mq, plain = plain)
}

RICH_FMT_ROWS <- list(
  rich_row("num_neg", function(...) fmt_num(-1234567.89, ...), "\u22121,234,567.9", "\u22121,234,567.9", plain = TRUE),
  rich_row("num_thin", function(...) fmt_num(1234567.89, ...), "1\u2009234\u2009567.9", "1\u2009234\u2009567.9",
           yml = "big_mark: \"\u2009\"", plain = TRUE),
  rich_row("num_plus", function(...) fmt_num(3, plus = TRUE, ...), "&#43;3", "\\+3", plain = TRUE),
  rich_row("num_minus_hyphen", function(...) fmt_num(-3, ...), "&#45;3", "\\-3", yml = "minus: \"-\"", plain = TRUE),
  rich_row("pct", function(...) fmt_pct(0.123, ...), "12.3%", "12.3%", plain = TRUE),
  rich_row("sci_pos", function(...) fmt_sci(1234567, ...), "1.2 \u00d7 10<sup>6</sup>", "1.2 \u00d7 10{.sup 6}"),
  rich_row("sci_neg", function(...) fmt_sci(-0.000123, ...), "\u22121.2 \u00d7 10<sup>\u22124</sup>",
           "\u22121.2 \u00d7 10{.sup \u22124}"),
  rich_row("sci_zero", function(...) fmt_sci(0, ...), "0", "0", plain = TRUE),
  rich_row("p_lt", function(...) fmt_p(0.0001, ...), "p &lt; 0.001", "p \\< 0.001", plain = TRUE),
  rich_row("p_eq", function(...) fmt_p(0.03, ...), "p = 0.030", "p = 0.030", plain = TRUE),
  rich_row("p_gt", function(...) fmt_p(0.995, ...), "p &gt; 0.99", "p \\> 0.99", plain = TRUE),
  rich_row("p_label", function(...) fmt_p(0.0001, ...), "<i>p</i> &lt; 0.001", "{.em p} \\< 0.001",
           yml = "p_label: \"*p*\"", plain = TRUE),
  rich_row("range", function(...) fmt_range(c(1.23, 3.45), ...), "1.2\u20133.5", "1.2\u20133.5", plain = TRUE),
  rich_row("range_neg", function(...) fmt_range(c(-1, 3), ...), "\u22121 to 3", "\u22121 to 3", plain = TRUE),
  rich_row("range_plus", function(...) fmt_range(c(1, 3), plus = TRUE, ...), "&#43;1 to +3", "\\+1 to +3", plain = TRUE),
  rich_row("word", function(...) fmt_word(3, ...), "three", "three", plain = TRUE),
  rich_row("a_an", function(...) fmt_a(8, ...), "an 8", "an 8", plain = TRUE),
  rich_row("date", function(...) fmt_date(as.Date("2024-03-05"), ...), "5 March 2024", "5 March 2024", plain = TRUE),
  rich_row("and", function(...) fmt_and(c(1, 2, 3), ...), "1, 2 and 3", "1, 2 and 3", plain = TRUE),
  rich_row("em", function(...) fmt_em("Eucalyptus", ...), "<i>Eucalyptus</i>", "{.em Eucalyptus}", plain = TRUE),
  rich_row("strong", function(...) fmt_strong("high", ...), "<b>high</b>", "{.str high}", plain = TRUE),
  rich_row("ul", function(...) fmt_ul(c("a", "b"), ...), "&#45; a<br>- b", "\\- a\\\n\\- b", plain = TRUE),
  rich_row("ol", function(...) fmt_ol(c("a", "b"), ...), "1&#46; a<br>2. b", "1\\. a\\\n2\\. b", plain = TRUE),
  rich_row("dl", function(...) fmt_dl(c(a = "1", b = "2"), ...), "a<br>:   1<br><br>b<br>:   2",
           "a\\\n\\:   1\n\nb\\\n\\:   2", plain = TRUE)
)

RICH_UNIT_ROWS <- list(
  rich_row("u_mgL", function(...) fmt_num(u(5, mg/L), ...), "5\u00a0mg/L", "5\u00a0mg/L", plain = TRUE),
  rich_row("u_m2", function(...) fmt_num(u(5, m^2), ...), "5\u00a0m<sup>2</sup>", "5\u00a0m{.sup 2}"),
  rich_row("u_s1", function(...) fmt_num(u(5, s^-1), ...), "5\u00a0s<sup>\u22121</sup>", "5\u00a0s{.sup \u22121}"),
  rich_row("u_kgms", function(...) fmt_num(u(5, kg*m/s^2), ...), "5\u00a0kg\u00b7m/s<sup>2</sup>",
           "5\u00a0kg\u00b7m/s{.sup 2}"),
  rich_row("u_degC", function(...) fmt_num(u(20, degC), ...), "20\u00a0\u00b0C", "20\u00a0\u00b0C", plain = TRUE),
  rich_row("u_name", function(...) fmt_num(u(5, mg/L), unit_form = "name", ...), "5\u00a0milligrams per litre",
           "5\u00a0milligrams per litre", plain = TRUE),
  rich_row("u_range", function(...) fmt_range(u(c(1.2, 3.4), m), ...), "1.2\u20133.4\u00a0m", "1.2\u20133.4\u00a0m",
           plain = TRUE),
  rich_row("unit", function(...) fmt_unit(u(1, m^2), ...), "m<sup>2</sup>", "m{.sup 2}")
)

RICH_TEXT_ROWS <- list(
  rich_w("em_star", "*Eucalyptus* sp.", "<i>Eucalyptus</i> sp.", "{.em Eucalyptus} sp.", plain = TRUE),
  rich_w("em_underscore", "_Eucalyptus_ sp.", "<i>Eucalyptus</i> sp.", "{.em Eucalyptus} sp.", plain = TRUE),
  rich_w("sub", "H~2~O", "H<sub>2</sub>O", "H{.sub 2}O"),
  rich_w("sup_n", "10^n^", "10<sup>n</sup>", "10{.sup n}"),
  rich_w("sup_raw", "m<sup>2</sup>", "m<sup>2</sup>", "m{.sup 2}"),
  rich_w("entity", "1.2 &times; 10", "1.2 \u00d7 10", "1.2 \u00d7 10", plain = TRUE),
  rich_w("span_style", "[Depth]{style='color:#c00'} at 4", "<span style=\"color:#c00\">Depth</span> at 4",
         "Depth at 4"),
  rich_w("span_class", "[x]{.smallcaps}", "<span class=\"smallcaps\">x</span>", "x"),
  rich_w("span_all", "[x]{#a .b custom-style='C'}", "<span id=\"a\" class=\"b\" data-custom-style=\"C\">x</span>", "x"),
  rich_w("star_escaped", "2 \\* 3", "2 &#42; 3", "2 \\* 3", plain = TRUE),
  rich_w("amp_lt", "a & b < c", "a &amp; b &lt; c", "a \\& b \\< c", plain = TRUE),
  rich_w("snake", "snake_case_name", "snake&#95;case&#95;name", "snake\\_case\\_name", plain = TRUE),
  rich_w("braces", "a {b}", "a &#123;b&#125;", "a \\{b\\}", plain = TRUE),
  # H0 correction 4: math in marquee is escaped as text
  rich_w("math", "$x^2$ is", "&#36;x&#94;2&#36; is", "\\$x\\^2\\$ is"),
  rich_w("code", "Run `f()` now", "Run f() now", "Run `f()` now", plain = TRUE),
  rich_w("smartypants", "1/2 of (c) sites", "1&#47;2 of &#40;c) sites", "1/2 of (c) sites", plain = TRUE),
  rich_w("hash", "# 3 sites", "&#35; 3 sites", "\\# 3 sites", plain = TRUE),
  rich_w("newline", "Line one\nline two", "Line one<br>line two", "Line one\\\nline two", plain = TRUE),
  rich_w("raw_tag", "<span style='x'>a</span>", "&lt;span style=&#39;x&#39;&gt;a&lt;/span&gt;",
         "\\<span style='x'\\>a\\</span\\>", plain = TRUE),
  rich_w("marker", "<<weft: no value, line 3>>", "&lt;&lt;weft: no value, line 3&gt;&gt;",
         "\\<\\<weft: no value, line 3\\>\\>", plain = TRUE),
  rich_w("joined", function() c(weft("a"), "b*c*")[2], "b&#42;c&#42;", "b\\*c\\*", plain = TRUE),
  rich_w("na", function() weft(NA_character_), "NA", "NA")
)

# H0 correction 3: HR2 gains four rules (straight quotes, dash runs, dot runs)
RICH_H0_ROWS <- list(
  rich_w("quotes", "it's 5'10\"", "it&#39;s 5&#39;10&quot;", "it's 5'10\"", plain = TRUE),
  rich_w("dashes2", "a -- b", "a &#45;&#45; b", "a -- b", plain = TRUE),
  rich_w("dashes3", "a --- b", "a &#45;&#45;&#45; b", "a --- b", plain = TRUE),
  rich_w("dash1", "a-b", "a-b", "a-b", plain = TRUE),
  rich_w("dots3", "wait...", "wait&#46;&#46;&#46;", "wait...", plain = TRUE),
  rich_w("dots4", "x....", "x&#46;&#46;&#46;&#46;", "x....", plain = TRUE),
  rich_w("dots2", "wait..", "wait..", "wait..", plain = TRUE),
  rich_w("dash_start", "-- a", "&#45;&#45; a", "\\-- a", plain = TRUE)
)

# HR3 and MQ2: the start of the text
RICH_START_ROWS <- list(
  rich_w("start_plus", "+1 site", "&#43;1 site", "\\+1 site", plain = TRUE),
  rich_w("start_equals", "= x", "&#61; x", "\\= x", plain = TRUE),
  rich_w("start_colon", ": x", ": x", "\\: x", plain = TRUE),
  rich_w("start_digit_dot", "3. sites", "3&#46; sites", "3\\. sites", plain = TRUE),
  rich_w("start_digit_paren", "3) sites", "3&#41; sites", "3\\) sites", plain = TRUE),
  rich_w("start_digit_end", "2024.", "2024&#46;", "2024\\.", plain = TRUE),
  rich_w("start_digit_plain", "5 sites", "5 sites", "5 sites", plain = TRUE),
  rich_w("start_decimal", "3.5 sites", "3.5 sites", "3.5 sites", plain = TRUE)
)

rich_weft <- function(x) if (is.function(x)) x() else weft(x)

# the text of a weft object formatted for a target, with every attribute dropped
rich_fmt_text <- function(w, target) unname(as.character(unclass(format(w, target = target))))

# run the formatter rows of one column; each row reads its own _weft.yml first
rich_expect_fmt_rows <- function(rows, col, target, env = parent.frame()) {
  for (r in rows) {
    g2_restore(env)
    got <- withr::with_dir(f2_proj(r$yml, env = env), f2_tx(r$f(target = target)))
    testthat::expect_identical(got, r[[col]], label = paste(target, "fmt row", r$id))
  }
}
rich_expect_text_rows <- function(rows, col, target, env = parent.frame()) {
  g2_cfg(NULL, env = env)
  for (r in rows) {
    testthat::expect_identical(rich_fmt_text(rich_weft(r$x), target), r[[col]], label = paste(target, "text row", r$id))
  }
}

# every exported fmt_*(), with arguments valid under every target
RICH_CALLS <- list(
  fmt_num = function(...) fmt_num(1234.5, ...),
  fmt_pct = function(...) fmt_pct(0.123, ...),
  fmt_sci = function(...) fmt_sci(1234567, ...),
  fmt_no = function(...) fmt_no(2, ...),
  fmt_word = function(...) fmt_word(3, ...),
  fmt_count = function(...) fmt_count(3, ...),
  fmt_ord = function(...) fmt_ord(3, ...),
  fmt_and = function(...) fmt_and(c("a", "b", "c"), ...),
  fmt_or = function(...) fmt_or(c("a", "b"), ...),
  fmt_p = function(...) fmt_p(0.03, ...),
  fmt_date = function(...) fmt_date(as.Date("2024-03-05"), ...),
  fmt_range = function(...) fmt_range(c(1, 3), ...),
  fmt_pairs = function(...) fmt_pairs(c(a = 1, b = 2), ...),
  fmt_ul = function(...) fmt_ul(c("a", "b"), ...),
  fmt_ol = function(...) fmt_ol(c("a", "b"), ...),
  fmt_dl = function(...) fmt_dl(c(a = "x", b = "y"), ...),
  fmt_cap = function(...) fmt_cap("abc", ...),
  fmt_a = function(...) fmt_a(8, ...),
  fmt_strong = function(...) fmt_strong("a", ...),
  fmt_em = function(...) fmt_em("a", ...),
  fmt_unit = function(...) fmt_unit(u(5, "mg/L"), ...)
)

# a project formatter's function lives in the global environment for the length of a test
rich_install <- function(name, fn, env = parent.frame()) {
  assign(name, fn, envir = globalenv())
  withr::defer(rm(list = name, envir = globalenv()), envir = env)
  invisible(fn)
}
rich_reg <- function(cls, fn, stage = "text", extra = NULL) {
  c("formatters:", paste0("  ", cls, ":"), paste0("    function: ", fn), paste0("    stage: ", stage), extra)
}

# the messages (design RT1, RT5, section 3)
RICH_E100 <- function(got) {
  sprintf("`target` must be \"markdown\", \"tex\", \"plain\", \"html\" or \"marquee\"; got \"%s\".", got)
}
RICH_E100_FORMAT <- function(got) {
  sprintf("`target` must be \"plain\", \"markdown\", \"ansi\", \"html\" or \"marquee\"; got \"%s\".", got)
}
RICH_E104 <- function(f, got) {
  sprintf("The formatter `%s` has `targets: %s`; `targets` lists markdown and, optionally, tex (rule 1.4.8).", f, got)
}
RICH_E107 <- function(what, target) {
  sprintf(paste0("This text was formatted for %s (target = \"%s\"), and weft cannot format it again. Give the ",
                 "formatter the value itself, or a text made without `target`, and put `target` on the outer ",
                 "call: fmt_strong(fmt_num(x), target = \"%s\") (rule 3.4.11)."), what, target, target)
}
RICH_E108 <- function(what, target) {
  sprintf(paste0("This text was formatted for TeX (target = \"tex\") and would print here as %s. Format the ",
                 "number again, with target = \"%s\" (rule 3.4.11)."), what, target)
}
RICH_E109 <- function(what, target) {
  sprintf(paste0("A text formatted for %s (target = \"%s\") cannot join a weft text: its markup would be read ",
                 "as text. Join texts made without `target`, then format the result (rule 3.6.3)."), what, target)
}

rich_expect_error <- function(e, class, msg) {
  testthat::expect_false(is.null(e), label = "an error was raised")
  testthat::expect_true(inherits(e, class), label = paste("class", class))
  testthat::expect_true(inherits(e, "weft_error"), label = "class weft_error")
  testthat::expect_identical(conditionMessage(e), msg)
}
