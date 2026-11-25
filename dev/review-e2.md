# Review of package E2 (bare names read R), 2026-11-26

Independent review (opus) of e83fcc7..5bb4aa1 against `dev/design-e2.md`
and its rulings. R not run by the reviewer. Rulings by the orchestrator
(authority delegated by Robin).

## Findings and rulings

**G1. Bug. `auto()` is never fetched under `names_from: python` or
`julia`** (R/guest.R:303: the fetch is guarded by `values_r_names(s)`).
The setting's main use case fails "no value". *Ruling:* fix; fetch
`auto()`'s changes under every `names_from`.

**G2. Bug. R reads named values in front matter written in block form**
(`abstract: |` then a line holding `` `n`{.num} ``): `mask_front_matter()`
keeps block-scalar lines visible and `render_named` never checks front
matter. *Ruling:* fix; a row in front matter (and in an end metadata
block) is always left for the filter (BN6, D5).

**G3. Bug. The secret leak survives in draft mode through unresolved
captions**: the caption list runs `cond_names()` on any `if` governor in a
caption carrying the 2.3.5 error. *Ruling:* governor names never go on the
caption list; only bare named values in an unresolved caption do. A
governor span in such a caption is a construct error (2.3.5); in draft it
is marked, and its names are not published. Alternative: keep governors
that fit the filter's grammar; refused, since the caption fails anyway
and any publication of a governor's tokens is the leak's shape.

**G4. Gap. The unresolved-caption list misses caching set at run time**
(`knitr::opts_chunk$set(cache = TRUE)`, `cache: !expr ...`). *Ruling:*
when the caption hook finds a caption not resolved, it adds the caption's
bare named values to the names R leaves (and so publishes). The static
list stays for the source-level error.

**G5. Gap. The stale-session check (BN11) can fail a correct render**
when the document itself set the value above the read and the value
equals the one held before the render (renders looped in one session,
chunks run interactively first, `weft_setup()` after assignments).
*Ruling:* a read is noted as possibly stale only when no R chunk executed
above it assigns the name. "Assigns" is read from the parsed code of the
executed chunks: `<-`, `=`, `->`, `<<-`, `->>`, `assign("name", ...)`, a
`for` variable, and `list2env`/`assign` with a non-literal name or code
that does not parse counts as assigning every name (no note). The check
errs towards not failing. Alternative: compare object identity after each
chunk; refused, as R has no supported cheap identity for all objects.

**G6. Gap. A function published as E45 collides with a guest's value.**
*Ruling:* R does not publish a function at all: the name is left for the
filter, which takes a guest's value if one is published and otherwise
fails "no value", as it would without R. This restores D2's reason.

## Implementer's choices (accepted, with a spec note)

`weft()` literals keep resolver `hooks` under every `names_from`; spec
2.13.14 must say so. A named value inside `.weft-literal` is left as
written. `weft_impl(read_names = FALSE)` for Python's `weft_str()`; note
in its docs that outside a knit a bare name prints as written.

## Spec and docs

- 3.8.7: restate the definition of "the names the document names" (it was
  deleted with old 2.13.11): `NAME{` plus governor names in any 1.2.2
  form, outside string literals, through includes up to 8 deep.
- Around line 2537: "the publication check of 2.13.11" is stale.
- 1.12.8: `` `x` `` and `` `r x` `` also differ for functions and for
  names a guest publishes later.
- Wrap the long lines added to the spec and `vignettes/named-values.Rmd`.
- `named-values.Rmd`:166-178: the loop's output shows three lines and
  defines `mean_ntu`; "A named value in math and raw LaTeX" says R reads
  the name there in a knitr document.
