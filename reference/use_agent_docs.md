# Write the agent documents: an AGENTS.md block and a skill

Writes, under the project root, a block in `AGENTS.md` (created when
absent) and the weft skill, that tell a coding agent the rules of a weft
project: a failed claim is a finding to report, a check is never changed
to make a render pass, a commit that removes constructs carries the
`Weft-Removed` trailer, and values for one chapter go in `dict_local`.

## Usage

``` r
use_agent_docs(path = ".", overwrite = FALSE, skills = "auto")
```

## Arguments

- path:

  A directory in the project.

- overwrite:

  Replace a block or skill file weft wrote that has since been edited.

- skills:

  The skills folders to write into: a character vector of preset names
  or folders relative to the project root. The default, `"auto"`, writes
  `.agents/skills`, and also `.claude/skills` when the project root
  holds a `.claude` folder, a `CLAUDE.md` or a `CLAUDE.local.md` (Claude
  Code reads `.claude/skills` and not `.agents/skills`); only the
  project root is looked at, and the call's first lines say which file
  or folder chose `.claude/skills`. `"auto"` may be combined with other
  items, as in `c("auto", "gemini")`. `skills = "agents"` writes
  `.agents/skills` alone. You can also install the plugin with
  `/plugin marketplace add vorpalvorpal/weft`. The other presets are
  `agents` (`.agents/skills`), `claude` (`.claude/skills`), `codex`
  (`.agents/skills`), `gemini` (`.gemini/skills`), `opencode`
  (`.opencode/skills`), `kimi` (`.kimi-code/skills`) and `cursor`
  (`.cursor/skills`). An item with a `/` or starting with `.` is a
  folder; an absolute path or one with a `..` part is an error. Folders
  that come to the same place are written once.
  [`character()`](https://rdrr.io/r/base/character.html) writes the
  `AGENTS.md` block only. A weft-written copy in a preset folder that is
  not named, and is older than this weft, is not touched; the call says
  so and how to update it.

## Value

The paths written, invisibly
([`character()`](https://rdrr.io/r/base/character.html) when nothing
changed): `AGENTS.md` first, then the skill files folder by folder in
the order given.

## Details

The skill is `<folder>/weft/SKILL.md` with `references/syntax.md` and
`references/reports.md` beside it, written into each skills folder named
by `skills`. The same texts go into every folder.
[`agent_docs()`](https://vorpalvorpal.github.io/weft/reference/agent_docs.md)
prints the installed package's version of each.

The `AGENTS.md` block sits between `<!-- weft:start ... -->` and
`<!-- weft:end -->` lines, appended after the file's last line with one
blank line before it; the rest of the file is never touched. The start
line and the last line of each skill file carry the weft version and a
hash. Each file is judged alone: one weft wrote and nobody edited is
replaced when its text would differ; an edited one is left as it is
unless `overwrite = TRUE`; a file with no weft line is another author's
and is never replaced. One copy being edited does not stop the others
being written.

When `CLAUDE.md` exists and does not hold `@AGENTS.md`, or `GEMINI.md`
exists and holds neither `@AGENTS.md` nor `@./AGENTS.md`, the call says
to add that line; neither file is written. It says what it will write
first. [`suppressMessages()`](https://rdrr.io/r/base/message.html)
silences it.

## Examples

``` r
dir <- tempfile("weft-example")
dir.create(dir)
writeLines("", file.path(dir, "_weft.yml"))
writeLines(c(
  "---",
  "title: Survey",
  "---",
  "",
  "We visited 14 sites.",
  "",
  "```{r}",
  "n_high <- 3",
  "```",
  "",
  "[No site | One site | # sites]{n=n_high} read high."
), file.path(dir, "survey.Rmd"))
use_agent_docs(dir)
#> weft will write, under /tmp/Rtmpubk0QI/weft-example1abb66864cf8:
#>   AGENTS.md  (new: the weft rules for coding agents)
#>   .agents/skills/weft/SKILL.md  (new: the weft skill for coding agents)
#>   .agents/skills/weft/references/reports.md  (new: the weft skill for coding agents)
#>   .agents/skills/weft/references/syntax.md  (new: the weft skill for coding agents)
#> Wrote: 4 files, listed above.
list.files(dir, recursive = TRUE, all.files = TRUE)
#> [1] ".agents/skills/weft/SKILL.md"             
#> [2] ".agents/skills/weft/references/reports.md"
#> [3] ".agents/skills/weft/references/syntax.md" 
#> [4] "AGENTS.md"                                
#> [5] "_weft.yml"                                
#> [6] "survey.Rmd"                               
unlink(dir, recursive = TRUE)
```
