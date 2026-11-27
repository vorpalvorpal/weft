# use_agent_docs(skills = "auto"): the default writes .agents/skills, and .claude/skills as well when
# the project root holds a .claude folder, a CLAUDE.md or a CLAUDE.local.md.
# Spec: dev/PACKAGE-SCOPING.md 9.3.8; ruling of 27 Nov 2026 in dev/design-agent-docs.md.
# Helpers come from helper-4b.R, helper-4d.R and helper-quarto.R; the ones here are prefixed aa_. ASCII only.
#
# READINGS ASSUMED:
#   - the call's first lines are the announcement; the file or folder that chose .claude/skills is
#     named in them (CLAUDE.md, CLAUDE.local.md, or .claude), checked within the first six lines;
#   - the returned paths are relative to the root once passed through u4_rel().

AA_AGENTS <- ".agents/skills/weft/SKILL.md"
AA_CLAUDE <- ".claude/skills/weft/SKILL.md"
aa_skill_files <- function(d) grep("SKILL\\.md$", tree(d), value = TRUE)
aa_proj <- function(files = list(), claude_dir = FALSE) {
  d <- u4_dir(c(list(`_weft.yml` = "draft: false"), files))
  if (claude_dir) dir.create(file.path(d, ".claude"))
  d
}
aa_head <- function(s) paste(utils::head(s$lines, 6L), collapse = "\n")
aa_path <- function(d, rel) file.path(d, rel)
AA_GH <- "https://github.com/example-org/example-repo.git"
aa_files <- function(folder) file.path(folder, "weft", c("SKILL.md", "references/syntax.md", "references/reports.md"))
aa_edit <- function(f) {                        # append a line before the marker
  x <- readLines(f)
  writeLines(append(x, "My own rule.", after = length(x) - 1L), f)
}
aa_stale <- function(f) {                       # an older, unedited copy
  x <- readLines(f)
  writeLines(h4_forge(x, function(b) c(b[1:2], "An older line.", b[-(1:2)])), f)
}

test_that("auto: a .claude folder alone gives both skills folders", {
  d <- aa_proj(claude_dir = TRUE)
  h4_agent(d)
  expect_setequal(aa_skill_files(d), c(AA_AGENTS, AA_CLAUDE))
  for (f in c(".agents/skills", ".claude/skills"))
    for (p in c("SKILL.md", "references/syntax.md", "references/reports.md"))
      expect_true(file.exists(aa_path(d, file.path(f, "weft", p))), label = file.path(f, p))
})

test_that("auto: a CLAUDE.md alone gives both skills folders", {
  d <- aa_proj(list(`CLAUDE.md` = "# Claude"))
  h4_agent(d)
  expect_setequal(aa_skill_files(d), c(AA_AGENTS, AA_CLAUDE))
  expect_identical(u4_read(d, "CLAUDE.md"), "# Claude")
})

test_that("auto: a CLAUDE.local.md alone gives both skills folders", {
  d <- aa_proj(list(`CLAUDE.local.md` = "# Mine"))
  h4_agent(d)
  expect_setequal(aa_skill_files(d), c(AA_AGENTS, AA_CLAUDE))
})

test_that("auto: no trigger gives .agents/skills alone", {
  d <- aa_proj(list(`GEMINI.md` = "@AGENTS.md", `README.md` = "x"))
  h4_agent(d)
  expect_identical(aa_skill_files(d), AA_AGENTS)
  expect_false(dir.exists(aa_path(d, ".claude")))
})

test_that("auto: a trigger in a subfolder, not the root, does not count", {
  d <- aa_proj(list(`sub/CLAUDE.md` = "x", `sub/CLAUDE.local.md` = "x", `other/.claude/settings.json` = "{}"))
  dir.create(file.path(d, "sub", ".claude"))
  h4_agent(d)
  expect_identical(aa_skill_files(d), AA_AGENTS)
  expect_false(dir.exists(aa_path(d, ".claude")))
})

test_that("auto: skills = 'agents' with a trigger writes .agents/skills alone", {
  d <- aa_proj(list(`CLAUDE.md` = "# Claude"), claude_dir = TRUE)
  h4_agent(d, skills = "agents")
  expect_identical(aa_skill_files(d), AA_AGENTS)
  expect_false(dir.exists(aa_path(d, ".claude/skills")))
})

test_that("auto: c('auto', 'gemini') adds .gemini/skills, with and without a trigger", {
  d <- aa_proj(list(`CLAUDE.md` = "# Claude"))
  h4_agent(d, skills = c("auto", "gemini"))
  expect_setequal(aa_skill_files(d), c(AA_AGENTS, AA_CLAUDE, ".gemini/skills/weft/SKILL.md"))
  d2 <- aa_proj()
  h4_agent(d2, skills = c("auto", "gemini"))
  expect_setequal(aa_skill_files(d2), c(AA_AGENTS, ".gemini/skills/weft/SKILL.md"))
})

test_that("auto: c('auto', 'claude') writes each folder once, with and without a trigger", {
  for (trigger in list(list(), list(`CLAUDE.md` = "# Claude"))) {
    d <- aa_proj(trigger)
    s <- h4_say(weft::use_agent_docs(d, skills = c("auto", "claude")))
    rel <- u4_rel(s$value, d)
    expect_false(anyDuplicated(rel) > 0L)
    expect_identical(sum(rel == AA_CLAUDE), 1L)
    expect_identical(sum(rel == AA_AGENTS), 1L)
    expect_identical(sum(grepl(AA_CLAUDE, s$lines, fixed = TRUE)), 1L)
    expect_setequal(aa_skill_files(d), c(AA_AGENTS, AA_CLAUDE))
  }
})

test_that("auto: the call says which folders it writes, in its first lines", {
  d <- aa_proj(list(`CLAUDE.md` = "# Claude"))
  s <- h4_say(weft::use_agent_docs(d))
  expect_match(aa_head(s), ".agents/skills", fixed = TRUE)
  expect_match(aa_head(s), ".claude/skills", fixed = TRUE)
  d2 <- aa_proj()
  s2 <- h4_say(weft::use_agent_docs(d2))
  expect_match(aa_head(s2), ".agents/skills", fixed = TRUE)
  expect_false(grepl(".claude/skills", aa_head(s2), fixed = TRUE))
})

test_that("auto: the message names CLAUDE.md as the trigger", {
  d <- aa_proj(list(`CLAUDE.md` = "# Claude"))
  s <- h4_say(weft::use_agent_docs(d))
  expect_match(aa_head(s), "CLAUDE.md", fixed = TRUE)
})

test_that("auto: the message names CLAUDE.local.md as the trigger", {
  d <- aa_proj(list(`CLAUDE.local.md` = "# Mine"))
  s <- h4_say(weft::use_agent_docs(d))
  expect_match(aa_head(s), "CLAUDE.local.md", fixed = TRUE)
})

test_that("auto: the message names the .claude folder as the trigger", {
  d <- aa_proj(claude_dir = TRUE)
  s <- h4_say(weft::use_agent_docs(d))
  head <- gsub(".claude/skills", "SKILLS", aa_head(s), fixed = TRUE)   # leave only other mentions of .claude
  expect_match(head, ".claude", fixed = TRUE)
})

test_that("auto: a stale weft-written .claude copy is updated under the default", {
  d <- aa_proj()
  h4_agent(d, skills = c("agents", "claude"))
  claude <- aa_path(d, AA_CLAUDE)
  aa_stale(claude)
  old <- readLines(claude)
  s <- h4_say(weft::use_agent_docs(d))
  expect_false(identical(readLines(claude), old))
  expect_true(AA_CLAUDE %in% u4_rel(s$value, d))
  expect_false(grepl("was not updated", s$text, fixed = TRUE))
  expect_identical(unname(tools::md5sum(claude)), unname(tools::md5sum(aa_path(d, AA_AGENTS))))
})

test_that("auto: an edited .claude copy is left alone under the default", {
  d <- aa_proj()
  h4_agent(d, skills = c("agents", "claude"))
  claude <- aa_path(d, AA_CLAUDE)
  aa_edit(claude)
  edited <- readLines(claude)
  s <- h4_say(weft::use_agent_docs(d))
  expect_identical(readLines(claude), edited)
  expect_false(AA_CLAUDE %in% u4_rel(s$value, d))
})

test_that("auto: the returned paths hold every file of both folders and AGENTS.md, once each", {
  d <- aa_proj(list(`CLAUDE.md` = "# Claude"))
  res <- u4_rel(h4_agent(d), d)
  expect_false(anyDuplicated(res) > 0L)
  want <- c("AGENTS.md", aa_files(".agents/skills"), aa_files(".claude/skills"))
  expect_setequal(res, want)
  d2 <- aa_proj()
  res2 <- u4_rel(h4_agent(d2), d2)
  expect_setequal(res2, c("AGENTS.md", aa_files(".agents/skills")))
})

test_that("auto: a second call writes nothing more and returns character()", {
  d <- aa_proj(list(`CLAUDE.md` = "# Claude"))
  h4_agent(d)
  before <- h4_snap(d)
  s <- h4_say(weft::use_agent_docs(d))
  expect_identical(s$value, character())
  expect_identical(h4_snap(d), before)
})

test_that("auto: use_weft() uses the default, so a CLAUDE.md project gets .claude/skills too", {
  dir <- h4_repo(list(`index.qmd` = u4_qmd(), `CLAUDE.md` = "# Claude"), weft = character(),
                 origin = AA_GH)
  h4_weft(dir)
  for (p in c(aa_files(".agents/skills"), aa_files(".claude/skills")))
    expect_true(file.exists(aa_path(dir, p)), label = p)
})
