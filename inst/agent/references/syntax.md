# weft syntax

One example for each construct. Write these as shown; do not invent others.

## An inline value

A computed value, printed by its class. The class and options go in `{}`.

```markdown
Mean turbidity was `r mean_ntu`{.num}, or `r mean_ntu`{.num digits="2"} to two places.
`r share`{.pct} of samples exceeded the guideline (`r p_val`{.p}).
The mean rose by `r d_mean`{.num .plus} mg/L.
We sampled `r sites`{.and trunc="3"}.
```

Classes in use: `.num`, `.pct`, `.p`, `.sci`, `.ord`, `.count`, `.word`, `.date`,
`.range`, `.pairs`, `.and`, `.or`. `.plus` signs a number.

weft reads inline R wherever knitr evaluates it: prose, a code span, a fenced
block that is not a chunk, an HTML comment, math. Wrapping text in an HTML
comment does not switch its values or checks off.

Inside math (`$...$`, `$$...$$`, a math environment such as `align`) and raw
LaTeX (a `{=latex}` fence, another `\begin{...}` environment) a class block
writes TeX, not markdown:

```markdown
$a = `r x`{.num digits=2}$, $b = `r share`{.pct}$ -> $a = 8.23$, $b = 12.3\%$
```

Use `.num`, `.pct`, `.sci`, `.p`, `.plus`, `.range` and the unit classes there.
`.p` prints its own label, so write `` $`r p_val`{.p}$ ``. The words, emphasis
and list classes (`.word`, `.count`, `.ord`, `.date`, `.a`, `.cap`, `.em`,
`.strong`, `.and`, `.or`, `.pairs`, `.ul`, `.ol`, `.dl`) are a construct error
in math. A bare `` `r x` `` there prints as stock prints it, and `fmt_num(x)`
in it writes markdown; for code that builds a formula, `fmt_num(x, target =
"tex")` writes TeX. A project formatter needs `targets: [markdown, tex]` in
`_weft.yml` to be used in math. A named value (`` $`depth`{.num}$ ``) works in
math and raw LaTeX too: the filter resolves it and writes the same TeX.

## Spans that choose wording

```markdown
[No site | One site | # sites]{n="n_high"} read above the trigger.
```
`n`: the wording follows a count (none, one, many); `#` prints the count.

```markdown
Turbidity [rose | fell]{if="slope > 0"} over the year.
```
`if`: the first word when the condition is true, the second when false.

```markdown
Abundance [rose by # | fell by # | did not change]{.pct sign="d_abund"}.
```
`sign`: the wording follows the sign of the value; `#` prints it.

```markdown
[No sites were | # was | # were]{list="flagged"} flagged.
```
`list`: the wording follows the length of a vector; `#` prints the list.

```markdown
Earlier work found [0.5 m in the upper reach]{cite="@doe2019"}.
```
`cite`: a number quoted from a source; the key is in the bibliography.

## Quoting a value

A value goes in double quotes, single quotes, or none when it is one word:
`{if="tier == 'sev'"}`, `{if='tier == "sev"'}`, `{n=n_sites}`. Inside quotes,
`\"`, `\'` and `\|` stand for the character and `\ ` for a space (a value that
starts with a space: `last="\ plus "`); any other `\` is an error. In an R
string, give the value the quote the string does not use:
`weft("[severe | mild]{if='tier == \"sev\"'}")`. A raw string needs no R
escapes: `weft(r"([severe | mild]{if='tier == "sev"'})")`; it ends at `)"`, so a
value ending in `)` takes single quotes.

## A check

```r
n_sites <- claim(nrow(d), . >= 30)
n_obs <- claim(nrow(d), . >= 30, level = "warn")
```

`claim(x, check)` returns `x` and fails when `check` is false; `.` is the value.
A failed claim is a finding to report; do not edit the check to pass it.
In prose: `` `r claim(max(turbidity), . < u(50, NTU))`{.num} ``.

## Named values

In a knitr document a name in the inline block reads R: `` `worst`{.num} ``
prints what `` `r worst`{.num} `` prints. In a document that is not knit, code
publishes it: `put()` in Python, `@put` in Julia. Text an R chunk prints goes
through `weft()`.

```markdown
The worst reading was `worst`{.num} NTU.
```

## Strings in R code

`weft()` resolves the same markup in an R string, for text no chunk option
reaches: plot titles and labels, console and log messages, table cells. It
evaluates at the call, in the caller's environment; a name reads R there.
There is no `weft_str()` in R.

```r
n_high <- sum(turbidity > 10)
p + labs(subtitle = weft("[No site | One site | # sites]{n=n_high} above `trigger`{.num} NTU"))
```

The result gives plain text (Unicode superscripts, no markup) to a plot,
`cat()`, `paste()` and `message()`, and markdown when a chunk prints it.
`format(w, target = "markdown")` gives the markdown; `format(w, target =
"ansi")` the console form (emphasis in italic and bold where the console draws
styles), which `print()` uses. In cli, `{.val {w}}` draws the console form and
`{w}` the plain text. Tick labels: `labels = function(b) fmt_num(b, target =
"plain")`. For rich plot text, ggtext draws `format(w, target = "html")` and
marquee draws `format(w, target = "marquee")`; every `fmt_*()` takes the same
two targets for tick labels. A `weft` object given to ggtext or marquee as it is
draws its plain text. A failed check is collected as in prose in a knit with weft on;
elsewhere the first failure stops with an error.
Keep the markup a literal string: the lints and the commit gate read literal
`weft()` strings in chunks and in the project's `.R` files, and skip a computed
one (`paste0()`, `sprintf()`).

## A literal that must stay

```markdown
Samples were filtered through [0.45 um]{.weft-literal why="pore size set by the laboratory method"} membranes.
```
`.weft-literal` needs a real `why`. Do not use it to silence a finding.
<!-- weft-file: use_agent_docs @VERSION@ @HASH@ -->
