# Review of package E4 (the static side), 2026-11-26

Independent review (opus) of d95568d..a69d20b against `dev/design-e4.md`.
R not run by the reviewer. Rulings by the orchestrator.

## Bugs

**K1. A row's `line` is wrong after an escaped newline**
(`scan_weft_code` counts newlines in the decoded value).
`weft("Total:\nWe saw [a site | # sites]{n='k'}")` on line 5 gives line 6
to `arms()` and the gate's constructs. *Ruling:* fix; a row's line is the
source line of its first character (from the mapped offset), in scripts
and documents.

**K2. `obj$weft(...)`, `env$weft(...)`, `x@weft(...)` are read as weft
calls.** *Ruling:* fix; the function position must be exactly the symbol
`weft`, or `weft::weft` / `weft:::weft`.

**K3. A pipe with a positional argument reads the wrong argument.**
`"Saw 12" |> weft(e)` is `weft("Saw 12", e)`. *Ruling:* fix, and amend
C6: on the right of a pipe the left-hand side is `x` unless an argument is
named `x`; the placeholder `x = _` (native) and `.` (magrittr) put it
where they stand; `"a" %>% weft` without parentheses is read too.

## Gaps and the implementer's open choices

**K4. `scripts_skip` read only from the root disagrees with the gate.**
*Ruling:* decide skipping per script from its own settings root (the
nearest `_weft.yml`), with paths relative to that folder, in every reader.

**K5. `scripts_skip: ~` drops the default.** *Ruling:* a null value (an
empty or commented-out list) means the default `[tests]`; `[]` reads
every script. Alternative: M1; refused because an emptied key is more
likely a commented-out list than a wish to read tests.

**K6. A skipped or excluded script named in `files` or `path` gives
nothing.** *Ruling:* a note in `lints()`, `checks()` and `verify()`:
"`tests/a.R` is left out by `scripts_skip`" (or "by the document rules").

**K7. `lints(reader = "pandoc")` reads no scripts.** *Ruling:* scripts are
read by weft's reader whatever `reader` is (they do not need Pandoc).

**K8. `n_files` differs between `lints()` and `checks()`.** *Ruling:*
neither counts skipped scripts or scripts with no `weft` literal.

**K9. No parse note in `checks()`.** *Ruling:* add it, as for non-UTF-8.

**K10. Phrase literals (`lookup()`, `brk()`) keep the old column
handling.** *Ruling:* out of scope; recorded in `dev/current-state.md`.

**K11. `scripts_skip` entries with `*`, `?`, a leading `/` or a backslash
match nothing.** *Ruling:* M1 for each.

**K13. The gate cache can thrash** (every in-project `.R` file is a gate
document). *Ruling:* skipped scripts and scripts whose bytes do not
contain `weft` are not gate documents.

**K14. The byte prefilter comes after two YAML parses per script.**
*Ruling:* check the bytes for `weft` first, then open; read each file once.

**K15. One more full tree walk, through renv's library.** *Ruling:* the
script walk prunes excluded folders as it goes and does not follow
symbolic links into them.

**K20. Block-quoted chunks have two readers** (constructs found, prose not
read). *Ruling:* fix; `chunk_literals()` reads the de-quoted code, so C9's
one reader holds.

**K21. `grp` is not filtered with `ok`.** *Ruling:* fix.

## Docs and messages

K17 `verify()`'s `files` check says "paths of documents": use M3. K18 the
backticked `read` message: a NEWS line. K19 the "Scripts" section of
`vignettes/lints.Rmd` and rule 5.1.9: a file starting with `.` is left
out; "not valid UTF-8"; the `arms()` docs say a script that is not valid
UTF-8 lists nothing.

## Checked and fine (reviewer)

Taking escapes out of the prose mask (K12); removal, rename and newly
skipped scripts in the gate; ledger keys (K16).
