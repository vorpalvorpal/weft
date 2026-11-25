# Review of package E1 (`weft()` and the plain target), 2026-11-26

Independent review (opus) of b2f1b12..53ebfdf against `dev/design-e1.md`
(with A1, A2) and E4's C10. R not run by the reviewer; Pandoc 3.8.3
probes. Rulings by the orchestrator (authority delegated by Robin).

## Findings and rulings

**F1. Bug. The cache leaves another project's units in force for a root
with no `_weft.yml`.** On a cache hit `project_units(root)` returns early
for a root with no file, so project A's `units:` (or a knit's front-matter
units) stay in force in folder B; and `current_config()` with no file uses
whatever is in `weft_env$units`.
*Ruling:* a root with no `_weft.yml` means the default units plus any the
session registered through the API, never another project's file or a
knit's front matter. On every `weft()` call and every `fmt_*()` call
outside a knit in such a root, if the units in force came from another
root's file or from a knit, the defaults are put back first. Track the
origin of the units in force (root and source) so this is a cheap check.

**F2. Bug. Python's `weft_str()` hides the knit's `x`.** The markup is
stored as `x` in the environment it is evaluated in.
*Ruling:* evaluate in a fresh environment whose parent is the knit's
global, with nothing bound in it; pass the markup as a value. An `NA`
result goes back to Python as missing (`None`), not the string `"NA"`.

**F3. Bug. Non-ASCII characters in R/plain.R's code.** *Ruling:* `\u`
escapes throughout, as in the other R files.

**F4. Gap. C10 misses a `!expr` caption written as a block scalar**
(`#| fig-cap: !expr |` then the code on following lines). *Ruling:* fix;
read the block scalar's text as the code.

**F5. Gap. The lints never read the strings of computed captions.**
*Ruling:* fix; a `weft()` literal in a `!expr` caption or a header option
such as `fig.cap = weft(...)` is read by the string lints as any other
`weft()` literal, with its position.

**F6. Gap. PL8 misses emphasis that closes inside a longer run**
(`**Total for *E. coli***`, `***Eucalyptus* sp.**`, `*a **b***`).
*Ruling:* follow Pandoc: a closing run may close an inner and an outer
emphasis together (split runs of three into one and two). PL8's wording
changes to match.

**F7. Nit. The emphasis and `^`/`~` closer search does not skip code spans
or math** (`*see `x*y`*`). *Ruling:* fix; code spans and math are opaque
to the search.

**F8. Nit. `[[<-` past the end drops the markdown; `is.na<-` errors;
`w[[5]]` gives NA.** *Ruling:* fix all three to behave as a character
vector would (extend the markdown with the new text; `is.na<-` sets NA;
out of bounds is base's error).

**F9. Gap. `pdf()` cannot draw superscripts and the minus sign.**
*Ruling:* document it (use `cairo_pdf()` or ragg for plots with weft
text); the example in R/weft.R draws no character outside Latin-1.

**F10. Nit. `conf_with_config()` builds on the working directory's
`_weft.yml`.** *Ruling:* fix; the conformance tables use the defaults
only.

**F11. Nit. The caption hook unwraps only a one-element `expression()`.**
*Ruling:* evaluate every element and use the last value, as knitr does.

**F12. Nit. Locating a header option fails with blanks after `}`.**
*Ruling:* fix; trim trailing white space before matching.

**F13. Nit. Two PL readings differ from Pandoc** (`x^a\ b^` gives a
no-break space in Pandoc; a code span's surrounding spaces are all
trimmed). *Ruling:* follow Pandoc; amend PL1 and PL2.

## Implementer's open choices (reviewer's view, accepted)

Message prefix by rewriting the condition: fine. C10 only for calls of
`weft()`: right. Header-option matching: fine apart from F12. Quarto
hook unwrap: fine apart from F11. `weft_markdown()` "changed" test:
sound. A1 for no-file roots: replaced by F1.
