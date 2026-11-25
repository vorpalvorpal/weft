# Review of package E3 (console and ANSI), 2026-11-26

Independent review (opus) of 86f8a07 and ec24d94 against
`dev/design-e3.md`. R not run; cli's behaviour read from its source
(3.6.4). No input was found where `ansi_strip()` of the ANSI form differs
from the plain form. Rulings by the orchestrator.

## Findings and rulings

**H1. Bug. `print()` writes escapes into a sink in RStudio, or wherever
`cli.default_num_colors` is set.** `cli::num_ansi_colors(stdout())` skips
cli's sink check (that runs only for `"auto"`), and RStudio's count and
`cli.default_num_colors` are returned before the `isatty()` test.
*Ruling:* when `sink.number() > 0`, `print()` uses the smaller of the
`stdout()` count and the `"auto"` count, so a sink gets plain text unless
`cli.num_colors` or `R_CLI_NUM_COLORS` forces colour. C7 and D2 are
amended: `stdout()` does not see sinks.

**H2. Gap. A weft text with a line break loses its styles under
`{.val}`**: cli replaces `\n` with a space before `cli_format()`, keeping
the attributes, so the element reads as changed. *Ruling:* in
`cli_format.weft()`, an element whose plain text equals its markdown's
plain text with line breaks read as spaces is unchanged.

**H3. Nit. A failure marker in joined text is drawn bold red, against
C4's wording.** *Ruling:* keep the behaviour (the marker is the one thing
that must be seen); add "a failure marker in joined text is still drawn"
to C4 and rule 3.6.9.

**H4. Nit. Each print reads the markdown three times.** *Ruling:* read it
once per element and compare the rendered plain form to the element's
text.

**H5. Gap. A failure marker inside math (`\text{<<weft: ...>>}`) is not
styled; a marker broken over a line is not matched.** *Ruling:* style
markers inside math runs too, and match across line breaks.

**H6. Nit. The import of `cli_format` is kept;** its effect is that cli
loads with weft and the generic is findable, not that registration needs
it. Nothing recorded needs correcting beyond this note.

**H7. Nit. An empty emphasis writes an empty style pair.** *Ruling:*
write nothing for an empty styled run.

**H8. Docs nit. `{.val text {w}}` pastes the value and quotes it.**
*Ruling:* one sentence in the roxygen section: use `{.val {w}}` alone.
