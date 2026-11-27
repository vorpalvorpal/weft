# Test-suite plan: review-code-tests 3-6, 9-17 and sweep F1-F2

HEAD e0bc2e9: 323 test files, 55 helpers. Times are per-test `real` from `suite-end.rds` (27 Nov
12:58: 7,506 tests, 70,223 expectations, 34.0 min); `fin_suite.log` has no times. Scripts and
`suite-end.csv` are in `scratchpad/tp/`.

## Proof kit (WP0, before anything else)

- `dev/test-inventory.R`: a full run (offloaded, or alone here) writes file, test, nb, skipped,
  failed and time. Each package diffs before and after: same names and nb, no new skips.
- Planted bugs, applied in a `git archive` copy: the same tests must fail before and after.
- Golden output: where renders are shared or batched, each case's text is byte-identical.
- Other agents are changing `R/` and adding tests: re-run the greps at the start of each package.
  Aliases come first because new files may use the old helper names.

## Per proposal: now, change, risk, proof

**3. Git isolation.** About 240 tests in 20 files build repositories unisolated (`e2x_*`,
`f3d_scenario`, `i2_big_project`, `t7c_changes`, `d2_git_init`, `c2_git_repo`, `git_in`): test-changes (64), review-2e2 (56), changes-state
(29), changes-findings (26) and trial-2i-changes (20). `git_env()` (helper-4a.R:16) is the one
isolating helper, used by `g_repo`, `h4_repo*` and 9 test files. `e2x_git`/`d2_git` still
discard the exit status.
*Change:* move `git_env`, `g_git`, `g_ok_git` and `skip_if_no_git` to helper-0-common.R. Call
`git_env(env)` in each builder, and make the builders' git calls stop on a non-zero status.
*Risk:* `git_env` sets HOME to a temporary folder. That moves `tools::R_user_dir()`, so the
udunits disk cache (R/unit-names.R:163) goes cold in every test: slower, and a different code
path. Pin `R_USER_CACHE_DIR` to the session value inside `git_env`. Fixed commit dates make
every commit the same second; grep for any `--since` or time order (none found on 13 Nov).
*Proof:* run the 20 files under a hostile `GIT_CONFIG_GLOBAL` (a `core.hooksPath` whose
pre-commit exits 1, `commit.gpgsign=true`, `init.defaultBranch=trunk`). Before, they fail or run
on empty histories; after, the same names and nb pass.

**4. Gate edits.** test-gate-edits.R: 74 tests, 70.5 s, about 1 s each. One fresh `g_scenario`
and 1-2 cold gate runs per edit. New since 13 Nov: test-gate-checks.R:411-445 (N139) gates
the same 73 edits in 73 more repositories (53.7 s). Its assertions are a subset of gate-edits'
(n_removed, ok, trailer), plus `res$checks` columns and the E80 line.
*Change:* (a) move the N139 assertions into the gate-edits loop and delete that loop.
(b) Use one repository per file, with the baseline committed once. Per edit: write, stage, gate,
then `git checkout HEAD -- . && git reset -q && git clean -fdq`.
*Risk:* state leaking between edits; a merged assertion lost.
*Proof:* the union of assertions in the commit message; a clean `git status` asserted after each
reset; mutants (n_removed off by one, a `checks` column dropped, E80 wording) each fail.

**5. Child-R renders.** `render_rmd(in_process = FALSE)` is still the default. 115 call sites in
22 test files omit the flag (163 pass TRUE). The largest are conditions (16), failures (14),
syntax-fixtures (14), parity (12) and review-c (11). Measured: a child render costs about
0.55 s, an in-process one about 0.10 s.
*Change:* make `in_process = TRUE` the default. Pass `FALSE` explicitly in parity,
activation-cli and any test about `.Rprofile`, a new session or the hook chain. Grep the titles
for "fresh", "session", "Rprofile" and "stock".
*Risk:* state leaking from one render to the next makes a test pass for the wrong reason.
*Proof:* the suite run twice in one session, with the same result. The inventory diff. Planted
mutants: `weft_setup()` not installing a hook, a marker text changed, a line offset +1.

**16. Repeated renders.** What is left: test-parity.R:66 and :74 knit `parity_doc("rmd", FALSE)`
twice. test-condition-log.R:172-186 is a subset of test-ledger.R:621-640, the same cached double
render. (test-weft-str.R is gone; failures :82/:202 are different documents.) Memoise the
first, and fold the second into the ledger test. Under 10 s. Same proof as 5.

**6. Quarto.** 227 tests in 58 files reach a real `quarto render`: 8.2 min, about 2.4 s per
render. The largest are review-c (30 s), jl-claim-engine (28), julia-render (26), captions,
front-matter and quarto-render (23 each). No file renders an identical document twice.
*Change:* batch front-matter and captions as one multi-document project render, cached at file
level. Add opt-in `WEFT_TEST_FAST=1` to skip real Quarto renders. The default and CI run
everything. Wait for the other agents' front-matter and engine work to land first.
*Risk:* in a batch, one failing document hides another's output. A fast mode left on in CI.
*Proof:* golden html per case. Each document's own status is asserted. CI prints the fast flag
and fails if it is set.

**9. Shims.** `d2_need`, `g2_need` and `h2_need` (twice) fire at load time from 6 helpers. There
are about 38 `if (!exists(...)) source(...)` lines in 19 test files, and more in helper-2e1, 2i,
7c, closing and review-2d. *Change:* delete them. *Proof:* after `devtools::test()`,
`ls(globalenv())` is empty of helper names, and the inventory diff is clean.

**10. Session state.** Still present: `install_unit("rvquxc")` is never removed
(test-review-2a.R:326). `tar_make(callr_function = NULL)` runs in process in changes-state:160,
review-2e2:447, gate-sides:211 and helper-2e1:81, which attaches targets (fin_suite.log shows it
masking `one_of`). The `sentence_cache` entries from test-perf.R are left behind. A stray
`tests/testthat/Rplots.pdf` is in the tree.
*Change:* a `defer` for each, and a null device for plots. *Proof:* a temporary teardown hook
shows `search()`, the installed units and the cache size unchanged by each file.

**11 + F1. Helper families.** F1 is done (b6184fd, 14 Nov: helper-0-common.R, aliases), except
`weft_filter_path`/`filter_path`, which were left apart on purpose. The 8 families remain. For
example, error capture (`a2_err`, `c2_err`, `e1_err`, `f2_cond`: about 350 calls). Name collisions:
`m1`-`m10` (helper-5 vs test-formatter-options) and `g_cases` (helper-4a vs test-1g) mean
different things. *Change:* add canonical helpers to helper-0-common with one-line aliases, and
rename the colliding test-file locals. Migrate callers later. *Proof:* the inventory diff.
Mutation: an unclassed error in `validate_config()` must still fail the same tests.

**15 + F2. Dead code.** The 13 Nov list is gone. Dead now: 15 functions (`blocks_of`, `f3_chunk`,
`j7_arg`, `j7_guard`, `p7_err_msg`, `r6_paras`, `re6k`, `W6D_E6` and 7 test-file locals) and 4
constants (`G2_ENDASH`, `G2_DEG`, `H2_MINUS`, `H2_EN`). Copies across test files:
`expect_verify_failed` (3), `tt_*` (2), `scale_doc`, and `skip_if_no_git` in changes-findings. *Proof:* a grep shows each name only at its definition. Same test count.

**12. Inline git skips.** 187 lines of the form `Sys.which("git") ==`: changes (63), review-2e2
(53), trial-2i-changes (20). There are 37 calls of `skip_if_no_git()`. Replace them by script,
or drop them where the builder skips. *Proof:* the same skip count with git off `PATH`.

**13. Internals.** 950 `weft:::` calls to 127 functions from 152 files (334/45/61 on 13 Nov).
Wrap the three with the most calls: `read_config` (81 calls, 24 files), `scan_text`/`scan_file`
(61), `check_decisions` (40). `last_knit` is exported but called with `:::` in 10 files.
*Risk:* the other agents may change these signatures. Do this last in the structure phase.

**14. Gaps.** Still open: `dict_unmark()` has no behavioural test (decision-63 checks only the
export). `weft_arms_error`: no test. `weft_rehearse_error`: 1 of 5 paths tested.
`weft_knitr_too_old`: none. Closed: `weft_config_warning` (3 files) and `status()` (22).
*Change:* about 8 small tests. *Proof:* each fails against a planted mutant.

**17. Feature map.** A header comment in each primary feature file. No risk.

## Work packages (one implementer, one commit series each)

| WP | Items | Depends on |
|---|---|---|
| 0 | Proof kit, baseline inventory | none |
| A | 3 | 0 |
| B | 4 and the N139 fold | A (helpers in common) |
| C | 5, 16 | 0 |
| D | 6, fast mode | C; the other agents' front-matter work landed |
| E | 9, 10 | A to D |
| F | 11, F1 residue, 15/F2 | E |
| G | 12, 13 | F (`skip_if_no_git` in common) |
| H | 14 | none (can run alongside any) |
| I | duplicate merges (below) | F |
| J | 17 | I |

Run one full suite per WP, offloaded or alone (the R guard), and never two R processes at once.

## Minutes saved (default run, from 34.0 min)

| WP | Basis | Estimate |
|---|---|---|
| B | 53.7 s N139 loop removed; about 0.3 s per edit from a warm HEAD side | 1.0-1.3 min |
| C | 115 sites x 0.45 s, less about 20 kept as child; 16 under 10 s | 0.6-0.8 min |
| D | batching two files: 46 s down to about 15 s | about 0.5 min |
| Total | | about 2-2.5 min (7%) |

Fast mode saves another 8 min or so on local runs only. The 13 Nov estimates (7-9 min) were
taken while the machine was swapping; child renders and the gate are now cheaper. 93 tests over 3 s take
10.1 min; 4,912 tests under 0.1 s take 2.2 min.

## The "overkill" question

The 70,223 expectations measure loops, not tests. 102 tests (1.4%) hold 28,219 of them (40%).
One test, sweep-c's C1 guard comparing `gmatch()` with `gregexpr()` over every pattern, holds
8,688. Four conformance-6f tests hold 6,695, and those are cross-language tables, which stay.
The median test has 4 expectations. Duplication by text is low: 375 of 11,373 distinct
expectation lines occur in more than one file. Most of those are deliberate cross-language
pairs (julia/jupyter render, guest/julia prose, jl-put/py-put).

Review-round files share rule IDs with stage files (review-a and scan 17, review-2f and
unit-forms 12, review-b and failures 8), but a shared ID is the same rule, not the same
assertion. Most pin an edge case the review found (2e2 B's count 1 to 2 tests the
`(b - 1) * (a - 1)` boundary; C8 does not). Deleting them wholesale would lose coverage.

Worth merging (WP I, plus B):

1. gate-checks N139: 73 re-gated edits (WP B).
2. The structural reasons of `changes()`, near-copies in test-changes.R:196-222 (C8),
   test-review-2e2.R:621-627 (B) and test-trial-2i-changes.R:8-50 (I11). Each case builds a git
   repository. Merge them into one table-driven test (before, after, expected, origin), with
   every distinct triple kept, run through `changes()` over one repository. That saves about 60
   repository builds.
3. condition-log D22 into ledger D22 (see 16).
4. `expect_verify_failed`/`passed`, written three times: move them into helper-4c.

Evidence for each merge: the (input, expected) pairs before and after, none missing; the same
failures under a mutant (drop "crosses 1.0" for counts, change an arm label); a merged title that
cites its origins. Beyond these, do not cut: use the feature map (17) to find tests, and judge
value by mutation, not by counts.
