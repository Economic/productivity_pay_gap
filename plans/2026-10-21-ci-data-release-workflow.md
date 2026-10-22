# Plan: CI checks, weekly data refresh, manual releases, and change reports

Date: 2026-10-21

## Goals

1. Protect `main`: changes arrive only through pull requests, and a PR can merge only after CI checks pass.
2. Run a weekly job with the latest packages and data, and email me (through a GitHub notification) only when the published numbers change.
3. Keep releases a manual decision: a "Create release" button creates a dated release with the four final data files and notes.
4. Produce a "what changed and why" report, the same way locally and in CI.
5. Keep everything reproducible locally with `tar_make()`, so I can see changes before opening a PR.

## Decisions made

| Topic | Decision |
|---|---|
| PR checks | Offline rebuild must match the committed files exactly, plus sanity checks. The change report is posted on the PR for information only and never blocks a merge: it is built in a separate step that can't fail the check. |
| When checks run | On every PR to `main` and on every push to `main` (which, once `main` is protected, means merges). |
| Releases | Manual. A `workflow_dispatch` workflow creates tag `vYYYY.M.D` and attaches the four final CSVs plus the report. It refuses if nothing but access dates changed since the last release. A second release on the same day is allowed only as an explicit correction with a reason, tagged `vYYYY.M.D.2`. |
| Merge vs. release | Separate decisions. Merging a PR updates the numbers on `main` but publishes nothing. `main` can run ahead of the latest release. A release is a snapshot of `main` that I publish when I decide, typically when a new quarter arrives rather than for small revisions. |
| Weekly run | Scheduled weekly, plus a manual button. Updates all packages (`renv::update()`), pulls fresh data, runs the pipeline, writes the report. |
| Notification | One rolling PR from a `data-refresh` branch, assigned to `benzipperer`. The run comments (and so emails) only when a web-visible output changes compared with what I last saw: the open refresh PR, or `main` if none is open. The PR title, which becomes the email subject, labels the change: "New quarter: 2026q3" or "Revisions only (largest: 0.1 points, 2026q2 pay, from CPI)". Separately, a failed run sends GitHub's failure email, and so does a run whose hours download fell back to the committed file (see "Hours spreadsheet"). |
| "Web-visible" change | Any change to `data_final/epi_productivity_pay_gap_web.csv` or `data_final/epi_productivity_pay_gap_web_stats.csv`. These files are already rounded, so smaller revisions are reported but don't trigger email. |
| Hours spreadsheet | Downloaded automatically with `BLS_DOWNLOAD_EMAIL` in the `User-Agent` header. The release date is read from the ReadMe sheet. If the download fails, the committed file is used and the report says so. The weekly run then finishes as usual and ends as failed, so GitHub's failure email tells me, every week until the download works again. The sources CSV keeps the dates of the last successful download. |

### Already verified

- BLS returns an empty response without an email in the header and the full file with one (tested locally 2026-10-21). The downloaded file matched the committed one byte for byte, and the ReadMe sheet contains "Data released September 3, 2026".
- `epidatatools`, `epitargets`, and `realtalk` are public repos, so CI can install them without a token.
- I have admin rights on the repo. There is no `.github/` folder.
- Since 2026-10-21, the "protect main" ruleset requires pull requests and merge commits on `main` (see Phase 4).
- Phase 0 confirmed these from GitHub's servers on 2026-10-21 (Actions runs 39713125588 and 39713207415):
  - all three repo secrets are set
  - the BLS API key works ("REQUEST_SUCCEEDED") and the BEA API key works (68 rows from NIPA table 1.7.5)
  - BLS accepts the hours download with `BLS_DOWNLOAD_EMAIL` in the `User-Agent` header. The file URL now redirects (301 to `/web/prod2/total-economy-hours-employment.xlsx`), so the download must follow redirects. The file matched the committed one byte for byte.
  - the built-in Actions token can open and close a draft PR (test PRs #7 and #8)

## How it fits together

### Three pipeline modes, one `_targets.R`

- **Live (default, local `tar_make()`)**: fetches BLS and BEA API data and the BLS hours file, caching each for one day as now.
- **Offline (`TAR_PROJECT=offline`)**: never touches the network. It rebuilds everything from the committed raw data. CI uses this mode for the PR check.
- **Fresh live (CI weekly run)**: live mode with an empty `_targets/` store, so every source is fetched again.

Offline mode uses its own `targets` store, so switching modes locally doesn't invalidate the live cache.

### Where files live

Layout:

- `data_inputs/`: static configuration and inputs that never change (`bls_series_codes.csv`, `bea_series_codes.csv`, `bls_EEU00500006.csv`).
- `data_raw/` (new): everything fetched from outside, committed: `bls_api_output.csv`, `bea_api_output.csv`, `total-economy-hours-employment.xlsx`, and `fetch_log.csv`.
- `data_outputs/`: derived intermediate files (`bls_pay.csv`, `bls_hours.csv`, `prices.csv`).
- `data_final/` (renamed from `release/` in Phase 1): the four final data files. On `main` they can be ahead of the latest release, which is why the folder isn't called `release/`. File names, and the names of the files attached to GitHub releases, stay the same.
- `reports/` (new, gitignored): `change_report.md`.

The rule is simple: live mode writes `data_raw/`, and offline mode only reads it.

### Access dates move into committed data

The sources CSV currently takes access dates from when each target was built. An offline rebuild in CI would stamp the wrong date. Instead:

- Live fetch targets record their dates in `data_raw/fetch_log.csv`, one row per source (`bls_api_output`, `bea_api_output`, `bls_hours`, `prices`), with the date accessed and a status (for example, "download failed (...); kept file released 2026-09-03"). After a failed download, the source's row keeps the date accessed of its last successful download, because that download is where the data came from. Only the status records the failure.
- Publication dates are not in the fetch log, because they come from the data itself: the hours release date from the spreadsheet, and the `realtalk` date from its version. (As built; the plan first had date published and version columns in the log.) If the hours spreadsheet is ever committed by hand, its `date_accessed` in the fetch log must be updated too. A sanity check catches a publication date later than the access date.
- `document_data()` reads the fetch log instead of the `source_dates` target.
- The hours publication date is parsed from the spreadsheet's ReadMe sheet, so `data_inputs/bls_hours_dates.csv` is deleted.

### Local workflow (after this plan)

1. `tar_make()` fetches data (cached one day), rebuilds outputs, runs sanity checks, and writes `reports/change_report.md` comparing against `origin/main`.
2. I review the report and `git diff`.
3. Optional: `TAR_PROJECT=offline` + `tar_make()` runs the same rebuild CI will run.
4. I create a branch, commit, push, and open the PR with `gh pr create --body-file reports/change_report.md`.

### Weekly refresh flow

1. Check out `main`, restore packages, run `renv::update()` then `renv::snapshot()`.
2. Run the pipeline in fresh live mode with secrets `BLS_API_KEY`, `BEA_API_KEY`, `BLS_DOWNLOAD_EMAIL`.
3. Write the report to the run's summary page (always).
4. Compare the two web files with the "last seen" version: the open refresh PR's branch, or `main` if no refresh PR is open.
5. If they differ: commit all changed files onto a fresh branch from `main`, force-push it to `data-refresh`, open the PR (or update its title and description, with the title carrying the change label), and post the report as a comment.
6. If they don't differ: do nothing to the branch or PR, with one exception. If a refresh PR is open and the fresh web files also match `main` (for example, because a local data PR with the same numbers was merged), close the refresh PR with the comment "`main` already has these numbers".
7. If the hours download fell back to the committed file, steps 3 to 6 still happen as usual. Then the run ends as failed with the message "hours download failed; used the committed file released <date>", so GitHub's failure email tells me. Otherwise a blocked download could go unnoticed, especially in a week when nothing else changes or when BLS has just published a new quarter.
8. If the run fails for any other reason, GitHub sends its own failure email. The BLS and BEA API fetches have no fallback, so an API failure stops the pipeline, and next week's run tries again. GitHub sends failure emails for scheduled runs to whoever created or last changed the workflow's schedule.

**Merging a refresh PR** takes two clicks:

1. Approve the held check run ("Approve and run workflows").
2. Merge, once the check passes.

The PR is not a draft. It was at first, as a guard against merging by accident, but the held check already does that, so the draft only added a "Ready for review" click (changed 2026-10-22).

GitHub does run the `pull_request` check on a PR the bot opened, but holds the run until a maintainer approves it, and the PR's required check follows that held run. Phase 5 test 1 showed this; the plan first assumed the check wouldn't run at all, and started it separately with `workflow_dispatch`, which didn't count. The approval is a deliberate gate: the PR's files come from a job that ran freshly updated package code. A GitHub App token would remove the click, and the gate with it.

### Release flow

1. Click "Run workflow" on the release workflow (on `main`). Inputs: `dry_run` (checkbox), `correction` (checkbox), and `reason` (text, required when `correction` is ticked).
2. **One commit throughout**: the run records the commit it started from (`github.sha`) and uses only that commit. The offline check and the release job both check it out, and the attached files come from that checkout. The run creates the tag itself on that commit, through the GitHub API, before creating the release. The API refuses to create a tag that already exists, so a stray tag can never be reused. (`gh release create --target` is not enough on its own: GitHub ignores `--target` when the tag already exists.) A merge during the run can't mix commits. The offline check runs first.
3. **No-change guard**: if the four final files match the previous release, ignoring the `date_accessed` column of the sources CSV (which changes on every data pull), it stops with "Nothing changed since vX". There is no override. The guard only catches pointless releases, such as an accidental click on an unchanged `main`. Whether a change is worth releasing is my decision, made from the report.
4. It computes the tag from today's date in Eastern time:
   - No release today: `vYYYY.M.D`. If `correction` is ticked, it stops, since there's nothing to correct.
   - A release already exists today and `correction` is not ticked: it stops with "vYYYY.M.D already exists; tick 'correction' and give a reason to publish a corrected release". This catches double-clicks.
   - A release already exists today and `correction` is ticked: next suffix, `vYYYY.M.D.2` (then `.3`, and so on).
   - The chosen tag already exists without a release (for example, pushed by hand): it stops and asks me to delete the stray tag.
5. It regenerates the report against the previous release tag (not `main`), so the notes cover everything since the last release. For a correction, the previous release is the one being corrected, so the report shows exactly what the fix changed.
6. It creates the GitHub release, titled "Version YYYY.M.D" (or "Version YYYY.M.D.2"), with notes headed "Latest updates through YYYYqN". A correction's notes start with "Correction to vYYYY.M.D: <reason>". It attaches the four final CSVs and the report. The release is created as a draft first. After uploading, the workflow checks that the tag resolves to the pinned commit and that each attached file's digest matches the file in the checkout, then publishes the draft. If any check fails, it deletes the draft and the tag it created, so nothing becomes public.
7. With `dry_run` ticked, it runs every check and prints the tag and notes without creating anything.

Published releases are never deleted or overwritten.

## The change report

Generated by a `change_report` target (always rerun), comparing current files with a baseline git ref. The baseline is `origin/main` by default; set `PPG_BASELINE` to override it (the release workflow uses the previous tag). Baseline files are read with `git show <ref>:<path>`.

Sections:

1. **Summary**:
   - a change label: "New quarter: 2026q3", or "Revisions only" with the largest web-visible revision and its main source
   - baseline ref and date; latest quarter, old and new; whether web-visible outputs changed; headline stats, old and new
   - a reminder of unreleased changes, if any: "`main` has unreleased changes since v2026.9.14", with a one-line list (comparing `main` with the latest release tag, ignoring access dates)
2. **Inputs changed**
   - Per source (BLS CES seasonally adjusted and not, BEA NDP, compensation, and wages, BLS hours, `realtalk` CPI): access and publication dates, latest period available, number of revised values, number of new values.
   - Packages: version changes from `renv.lock`, with EPI packages listed first.
   - Code: changed files under `R/`, `_targets.R`, and `data_inputs/`.
   - Warnings: for example, hours download failed, or installed packages don't match `renv.lock`.
3. **Outputs changed**
   - New periods added, and which source determined the latest period before and after.
   - Web file: count of quarters whose rounded values changed, and the largest changes.
   - Web stats: old and new values.
   - Full data file: count of changed values and largest revision, by series and frequency.
4. **Why** (deterministic; see "How the 'why' is computed" below)
   - Contributions from NDP, hours, CES wages, NIPA compensation, NIPA wages, and CPI to each index revision, in index points.
   - Any remainder is reported as "code or method change", with the changed files listed.
   - Shown for the latest common quarter, for the headline growth stats, and as a summary across all revised quarters, with a one-sentence plain-language summary for each index.
5. **Checks**: sanity check results.

Markdown only for now. Charts could be added later as an HTML report attached to releases.

### How the "why" is computed

1. **Exact log identity.** Each index is a product of input ratios relative to 1948q1:
   - productivity index = 100 × (NDP_t / NDP_0) × (H_0 / H_t) × (CPI_0 / CPI_t)
   - pay index = 100 × (W_t / W_0) × (COMP_t / COMP_0) × (WAGE_0 / WAGE_t) × (CPI_0 / CPI_t)

   With Δ meaning new minus old, the revision `Δlog(index_t)` equals the sum over inputs of `±(Δlog(input_t) − Δlog(input_0))`. This is an identity, so the result doesn't depend on any ordering of inputs and always comes out the same for the same files.
2. **Index points.** Each log contribution is multiplied by the logarithmic mean of the old and new index values, L(a, b) = (a − b) / (log a − log b), or a when a = b. The contributions then add up exactly to the change in points, even when inputs offset each other.
3. **Remainder check.** Compare the sum of contributions with the actual revision from the pipeline. If the code is unchanged, the remainder is rounding error. Anything above 1e-8 in logs is reported as "code or method change". This check applies to the unrounded index series in the full data file. The web stats are built from rounded indexes, so they get their own treatment in step 6.
4. **Upstream code changes.** A change in `R/bls.R` (for example, the wage splice) shows up inside an input's contribution, not in the remainder. The report names such changes but doesn't measure them separately. When `R/bls.R`, `R/bea.R`, `R/prices.R`, `R/web.R`, or the BLS or BEA series code files changed, a warning names the files and says the contributions of the inputs they shape (and, for `R/web.R`, the web data and the rounding lines) may include a change in method. (Simplified 2026-10-22. The first version reran the current cleaning code on the baseline's raw files, to split wage, hours and CPI contributions into data and code parts. That needed the working tree, an unchanged `realtalk`, and raw files in the current format, and took most of the review rounds. Methodology changes are rare, and a person reviews them anyway.)
5. **New periods.** No old value exists to split. Report each source's latest available period, before and after, and which source limits the latest common quarter.
6. **Headline stats.** `R/web.R` publishes four kinds of stat, each for productivity and pay. Each gets its own treatment:

   | Stat | Formula | How its revision is split |
   |---|---|---|
   | Total growth, 1979q4 to latest | G = I_T / I_1979q4, shown as G − 1 | Log identity with 1979q4 as the base (the 1948q1 terms cancel). Points via the log mean of old and new G. |
   | Average annual growth, 1948q1 to 1979q4 | a = G^(1/years) − 1, with G = I_1979q4 / I_1948q1 | log(1 + a) = log(G) / years, so each input's log contribution is divided by the number of years. Points via the log mean of old and new 1 + a. The base here is 1948q1, so revisions to 1948 inputs matter. |
   | Average annual growth, 1979q4 to latest | as above, with 1979q4 to latest | As above, with 1979q4 as the base. |
   | Productivity growth as a multiple of pay growth | R = (G_prod − 1) / (G_pay − 1); the code divides the larger total growth by the smaller | Not split. Shown as old and new values only; it follows from the two total growth stats, which are split. |

   - All splits use stats recomputed from the unrounded indexes, where the identity is exact. The published stats come from indexes already rounded to one decimal. For example, for the 2026q1 pay growth factor in the v2026.7.30 to v2026.9.14 comparison, rounding alone leaves a log remainder of −7.8e-5, checked 2026-10-21. So the gap between each published stat and its unrounded version gets a separate "rounding" line, never "code or method change". If `R/web.R` changed, the rounding lines also hold that change's effect, and the warning in step 4 names `R/web.R`. (Simplified 2026-10-22. After checkpoint review job 77, the report briefly recomputed each published stat from the rounded web data, to separate rounding from changes in `R/web.R`. That copy of `R/web.R`'s arithmetic went stale whenever `R/web.R` changed on purpose, and produced edge cases in four more review rounds.)
   - A web revision whose index didn't change is attributed to "a change in R/web.R" in the change label, not to an input.
   - When the latest quarter moves, the end point and the number of years change. Report the effect of the added quarters separately from revisions to existing quarters. (As built: revisions are measured at the earlier of the two end quarters, with "Added quarters" and "Removed quarters" lines, so the split also works when a quarter disappears.)
7. **Base-period revisions.** Revisions to 1948q1 values move every quarter, so they get their own line.
8. **Limits.** This identifies which input moved and by how much, not why an agency revised its data. The report gives publication dates and the range of revised periods. The plain-language summaries are templates filled in largest contributor first, not generated text.

A prototype on v2026.7.30 compared with v2026.9.14 (313 common quarters) gave a maximum remainder of 8.9e-16. For 2026q1, it attributed the −0.507 point productivity revision to CPI (−0.460) and hours (−0.047), and the −0.280 point pay revision entirely to CPI.

## Implementation phases

Every phase happens on its own branch and ends with a checkpoint review before its PR opens:

```sh
roborev review --branch --base main --panel checkpoint_panel --wait
```

Fix real findings. Record findings that need several unusual conditions at once in "Risks" below instead of adding code.

### Before Phase 0: Review harness

1. Add `.roborev.toml`, adapted from `~/projects/bls-index/.roborev.toml`. It sets the same reviewers and panels, guidelines written for this repo's stakes, and diff exclusions for generated files and large data files.
2. Add "Working here", "Reviews (roborev)" and "Style" sections to AGENTS.md.
3. Run `roborev init` (without `--agent`, since `.roborev.toml` exists) to register the repo and install the post-commit, pre-push and post-rewrite hooks. Confirm with `roborev config validate --local` and `roborev quickstart`.
4. Commit the harness and this plan on a branch. The post-commit hook reviews each commit.
5. Run a design review of this plan before Phase 0: `roborev review --branch --base main --panel design_only_panel --wait`. Settle its findings, then merge the branch through a PR.

**Verification**: the first hook review appears in `roborev list`. The exclusions get checked on the first Phase 1 commit that moves or rebuilds data files: its review should leave out the large data files. The docs don't say whether file-name patterns match at any depth, so check this rather than assume it.

### Phase 0: Feasibility checks (done 2026-10-21; results under "Already verified")

1. ~~Add repo secrets `BLS_API_KEY`, `BEA_API_KEY`, `BLS_DOWNLOAD_EMAIL`.~~ Done 2026-10-21 in GitHub settings.
2. ~~Allow Actions to create pull requests (Settings → Actions → General).~~ Done 2026-10-21.

   The local `gh` token can't read secrets or Actions settings, so step 3 confirms both in a real run.
3. Push a throwaway workflow, triggered on push to a `spike/*` branch, with two jobs:
   - **Secrets and downloads**: report whether each secret is set, without printing values. Make one small BLS API call and one small BEA API call with the keys. Download the hours file with `BLS_DOWNLOAD_EMAIL` in the `User-Agent` header, and report the file size and the "Data released" line from its ReadMe sheet. This answers whether BLS accepts downloads from GitHub's servers.
   - **Bot PR**: with `pull-requests: write`, open a draft PR from the spike branch to `main` using the built-in token, then close it. This confirms the Actions setting.
4. Remove the spike workflow in a follow-up commit, and record the results in this plan. Merge the branch (`spike/phase-0`) through a PR, so its net change is the plan and AGENTS.md updates.

**Exit criteria**: both API keys work from CI, I know whether automated hours download works from CI, and the bot can open PRs.

### Phase 1: Restructure the pipeline (local only; built 2026-10-21, results below)

1. Create `data_raw/` and move the two API outputs and the hours spreadsheet there with `git mv`. Rename `release/` to `data_final/` with `git mv`. Update paths in `_targets.R` and `R/document_data.R`.
2. Add a live hours download target (one-day cache, `User-Agent` from `BLS_DOWNLOAD_EMAIL`, following redirects). On failure, keep the committed file and record the failure in the fetch log, keeping the dates of the last successful download (see "Access dates move into committed data"). Treat a response that isn't a valid spreadsheet as a failure: the first Phase 0 run got HTTP success with a 23-byte body.
3. Add `fetch_log.csv`, written in live mode and read in offline mode. Seed it with the dates currently in `release/epi_productivity_pay_gap_sources.csv`.
4. Parse the hours release date from the ReadMe sheet. Delete `data_inputs/bls_hours_dates.csv`.
5. Add offline mode with its own store. As built: `TAR_PROJECT=offline` selects the `offline` project in `_targets.yaml`, whose store is `_targets_offline/`. This uses the targets mechanism for separate stores, so one setting picks both the mode and the store (the plan first named a `PPG_OFFLINE` variable).
6. Add sanity check targets that stop the pipeline on failure:
   - no missing quarters from 1948q1 to the latest quarter in the web file
   - both indexes equal 100 in 1948q1 (and in 1948 for annual data)
   - both web series end in the same quarter
   - annual data only for complete years
   - web stats are finite and parse correctly
   - every source in the sources CSV has an access date, and publication dates are not after access dates
   - installed package versions match `renv.lock` (error offline, warning in live mode)
7. Stop committing `_targets/meta/meta`: add `_targets/` to the root `.gitignore` and `git rm --cached` it.

**Verification**: run offline mode on the committed data. Every file in `data_final/` and `data_outputs/` must match the version committed before Phase 1 (then in `release/` and `data_outputs/`) byte for byte, with one expected exception: the `data_location` column of the sources CSV, which now points to `data_raw/` for the moved files. Then do one live run and confirm only expected files change. Finally, do a live run with `BLS_DOWNLOAD_EMAIL` unset, so BLS refuses the download. The pipeline must finish using the committed hours file, the fetch log must record the failure, and the hours dates in the sources CSV must not change.

**Results (2026-10-21)**:

- The offline rebuild in a fresh store reproduced every file in `data_final/` and `data_outputs/` byte for byte, except the hours row of the sources CSV. There, `data_location` now points to `data_raw/`, and `access_method` changed from "manual download" to "download", since the file is now downloaded automatically.
- Three live runs, starting from the committed fetch log:
  - with `BLS_DOWNLOAD_EMAIL` empty (download skipped)
  - with a User-Agent that isn't an email ("R download test"), which BLS refused ("downloaded length 0 != reported length 1325")
  - with the real email

  In the first two, the pipeline finished with the committed spreadsheet, the fetch log recorded why, and the hours row kept its 2026-09-09 access date. The third downloaded the spreadsheet, identical to the committed one, and recorded 2026-10-21. All checks passed in every run.
- The live runs changed only the expected files: the two API results, the fetch log, `data_outputs/bls_pay.csv`, and the final files. New BLS and BEA data since 2026-09-13 moved productivity growth since 1979q4 from 93.7% to 94.4%, and pay growth from 32.7% to 32.5%. These data changes were not committed, so the Phase 1 PR is a restructure only; the first weekly run or a local data PR brings the new data in.
- Each sanity check was tested against data broken on purpose, and stopped the pipeline.

### Phase 2: Change report (built 2026-10-21, results below)

1. Write a baseline loader that reads final, raw, and intermediate files and `renv.lock` at a git ref. It must handle older refs, where files sit at their pre-Phase 1 paths: `release/` instead of `data_final/`, and the API outputs and hours spreadsheet outside `data_raw/`. Every release through v2026.9.14 uses the old paths.
2. Write each report section as its own function returning a small table, plus one function that assembles the Markdown.
3. Implement the log decomposition and the "code or method change" remainder.
4. Add the `change_report` target.

**Verification**: run the report comparing v2026.9.14 with v2026.7.30. Between those releases only data and `renv.lock` changed, so the remainder should be close to zero and the contributions should be plausible. Nothing may be attributed to "code or method change", including in the headline stats. Also run it against an unchanged working tree; it should report no changes. Finally, test a revision to the base period: copy the baseline inputs, change the 1948 CPI values, and check that the 1948–1979 stats reconcile exactly to a CPI contribution (apart from the separate rounding line), while the stats based at 1979q4 show no change.

**Results (2026-10-21)**:

- **v2026.7.30 to v2026.9.14:**
  - The report labels it "New quarter: 2026q2", and nothing is attributed to a code or method change.
  - The largest remainder is 8.9e-16 in logs for the indexes, and about 1e-13 percentage points for the stats.
  - The 2026q1 split matches the earlier prototype: productivity −0.507 points (CPI −0.460, hours −0.047), and pay −0.280 (CPI).
  - Every stat's contributions and rounding add up exactly to its published change. For example, productivity growth since 1979q4 went from 93.2% to 93.7%: +0.706 from the added quarter, −0.213 from CPI, −0.022 from hours, and +0.028 from rounding.
- **Unchanged working tree against `origin/main`:** "No changes". The only unreleased change since v2026.9.14 is the sources CSV, which is correct: `main` has the corrected hours dates.
- **1% higher 1948 CPI:**
  - Every quarter from 1949q1 is revised, all of it from CPI.
  - The base period section shows the 1948q1 CPI revision.
  - The 1948–1979 stats reconcile to a CPI contribution of +0.032 percentage points each, with a rounding line.
  - The stats based at 1979q4 don't change.
- **Simulated code change in `R/bls.R`** (pre-1964 wages 2% higher, no data change): the pay revision is attributed to CES wages, only quarters from 1964q1 are revised, and the warning names `R/bls.R`. (Before the 2026-10-22 simplification, the report split this into data and code parts.)
- **Cases added after the reviews:**
  - **Removed values:** a quarter removed from the final files is labeled "Quarters removed: 2026q2", and a removed annual value is counted.
  - **Stats only:** a change in the web stats alone gets its own label.
  - **R/web.R changes:** with `R/web.R` changed, a changed stat formula shows as a +0.3 rounding line and the warning names `R/web.R`. Web data rounded differently while the indexes didn't change is labeled "from a change in R/web.R".
  - **Shell characters in refs:** a branch named `test(pay)` loads, and a ref containing `$(...)` is rejected without running a command.
  - **Other rounding on both sides:** two-decimal web rounding on both sides, with revisions and an added quarter, gives no method-change warning.
  - **Baselines:** releases from v2026.3.11 on load. v2025.9.3 and v2026.1.16 store the BLS API results in an older format, and predate `renv.lock`, so they stop with a clear message.
- **Floating-point noise:** values computed in floating point differ by about 1e-14 between runs even when nothing changed. The real series are rescaled to the latest quarter's CPI, and that cancels out of the indexes only up to rounding. So the report counts a value as revised only if it changed by more than 1e-9 in relative terms.

### Phase 3: PR check workflow

1. Add `.github/workflows/check.yml`, triggered on `pull_request` to `main`, `push` to `main`, `workflow_dispatch`, and `workflow_call`.
2. Run on `ubuntu-24.04`, not `ubuntu-latest`. `.Rprofile` only uses prebuilt Posit binary packages for known Ubuntu codenames such as noble (24.04), so a future `ubuntu-latest` would compile every package from source.
3. Steps: check out with full history; set up R using the version in `renv.lock` (`r-lib/actions/setup-r`); restore packages with caching (`r-lib/actions/setup-renv`); run offline `tar_make()` for every target except the change report; fail if `git diff --exit-code -- data_final data_outputs` shows any difference.
4. Then, in a separate step that can't fail the job (`continue-on-error: true`), build the report and write it, or its error message, to the job summary. Post or update one PR comment with it only for PRs from branches in this repo, because PRs from forks get a read-only token.

**Verification**: open two test PRs. One changes only the README and should pass. One changes rounding in `R/web.R` without rebuilding and should fail on the diff step. Then, on the README PR, make the report step fail on purpose (for example, by setting `PPG_BASELINE` to a ref that doesn't exist): the check must still pass.

5. After the check job has run once, add it to the required status checks of the "protect main" ruleset (Phase 4). A check only appears in the ruleset's list after it has run.

**Results (2026-10-22)** (PR #13):

- **First run failed** installing packages. The prebuilt `igraph` binary needs `libglpk`, which the runner image lacks. The workflow now installs the system libraries that `renv::restore()` lists, except `cmake` and `pandoc`, which are needed only to compile packages or render documents. All R packages install as binaries: CRAN packages from Posit Package Manager, `realtalk` from economic.r-universe, and the two GitHub packages from source, all pure R.
- **Second run passed** in about 2 minutes 20 seconds. The offline rebuild on the runner matched the committed files byte for byte, so the "exact match is brittle across machines" risk didn't occur. The change report read "No changes", and it was posted as a PR comment by `github-actions`.
- **The plan's README-only test PR** was covered by PR #13 itself, which changes only `.github/` and docs.
- **Stale outputs** (PR #14, rounding in `R/web.R` changed without rebuilding): the check failed at the comparison step and named `data_final/epi_productivity_pay_gap_web.csv`.
- **Failing report** (PR #15, `PPG_BASELINE` set to a ref that doesn't exist): the report step errored, the run summary said the report could not be built, and the check passed. With `continue-on-error`, GitHub shows a failed step's conclusion as "success"; the workflow reads the step's outcome instead.
- The test PRs were closed and their branches deleted.

### Phase 4: Protect `main` (done 2026-10-22)

The "protect main" ruleset on the default branch is active, with:

- a pull request required, with 0 required approvals
- no bypass list, so admins follow the same rules
- force pushes and branch deletion blocked
- merge commits only (no squash or rebase)
- branches not required to be up to date, since that would force a rebuild for every unrelated merge
- the `check` job required, from GitHub Actions (added 2026-10-22, after Phase 3's first run)

**Verification**: a direct `git push` to `main` is rejected.

### Phase 5: Weekly refresh workflow

1. Add `.github/workflows/refresh.yml` with `schedule` and `workflow_dispatch`, on `ubuntu-24.04`. GitHub's schedules are in UTC and ignore daylight saving time, so use `cron: "7 12 * * 1"`: Monday 8:07 a.m. EDT, 7:07 a.m. EST. The odd minute avoids the top-of-hour rush, when GitHub delays scheduled runs.
2. Permissions: `contents: write`, `pull-requests: write`, `actions: write`. Set `GITHUB_PAT` to the built-in token so `renv::update()` doesn't hit GitHub API limits for the GitHub-hosted EPI packages.
3. Implement the flow under "Weekly refresh flow" above.

As built, the workflow has three jobs. The split keeps package code away from the write token, since `renv::update()` installs whatever is new:

- **build** (read-only token):
  - updates every package, then fetches and rebuilds with the three API secrets
  - writes the change report to the run summary and reads the hours status from the fetch log
  - uploads the changed files as an artifact
- **publish** (`contents`, `pull-requests` and `issues` write; `issues` because assigning a PR goes through the issues API): checks out the build job's commit and unpacks the artifact into a staging directory. `.github/scripts/copy-refresh-files.sh` then copies in only regular files at allowlisted paths, and `.github/scripts/update-refresh-pr.sh` updates the PR. It runs no R or package code. (After checkpoint review job 143. The first version unpacked the artifact straight over the checkout, where a crafted `.git/config` could have run commands with the write token present.)
- **hours:** runs after publishing, and fails the run if the hours download fell back.

A `dry_run` input for manual runs skips publishing, and publishing runs only on `main`.

**Verification**:

- Run it manually: it opens a PR assigned to me, I get an email, and the check runs on the PR and shows as the required check.
- Run it again right away: it changes nothing and sends no email.
- On a throwaway branch, point the hours download at a file that doesn't exist and run the workflow there. The report and the run summary must still be written, the run must end as failed with the fallback message, and I must get GitHub's failure email.
- Mark the PR ready and merge it.

If the dispatched check doesn't satisfy the ruleset, fall back to a GitHub App token for creating the PR (needs an Economic org admin). (Resolved by test 1: approving the held check run is enough, so no App token is needed. See "Merging a refresh PR" above.)

**Results (2026-10-22)**:

- **Test 1** (run 39730736190):
  - The manual run opened draft PR #17, "Data refresh: Revisions only (largest: 2.4 points, 2025q2 productivity, from NDP)", assigned to me. The new data since 2026-09-13 includes BEA revisions.
  - The check started with `workflow_dispatch` passed on the PR's commit but didn't count. GitHub had also created a `pull_request` run for the bot's PR and held it (`action_required`), and the PR followed that run.
  - Approving the held run (run 39730903579) ran the check, which passed; the PR then showed `check` passing and was blocked only as a draft.
- **Test 2** (run 39731398993): a second run right away found "The web files match origin/data-refresh, so there is nothing new to report". The PR's commit and comments were unchanged, so no email went out.
- **Checkpoint reviews:**
  - Job 143's high finding (a crafted artifact could overwrite `.git/config` in the publish job) and low finding (publish from the build's commit) are fixed. So is job 148's low note (close a stale refresh PR before comparing with it). Job 143 finished only after PR #16 was merged; the fixes went in a follow-up PR.
  - The copy script was tested locally against five crafted artifacts: a `.git/config`, a symlink, a nested path, a newline in a file name, and a dotfile. Each was rejected, and nothing was copied.
- **Test 3** (run 39732719173): a dry run on a throwaway branch, with the hours download pointed at a file that doesn't exist.
  - The build job succeeded and wrote the change report, and publishing was skipped.
  - The hours job failed the run with "BLS hours spreadsheet: download failed (cannot open URL '.../does-not-exist.xlsx': HTTP status was '404 Not Found'); kept file released 2026-09-03", which sends GitHub's failure email.
  - The branch was deleted afterward.
- **Duplicate reports:** approving the check on PR #17 also posted the check's change report as a comment, duplicating the refresh workflow's report. Worse, the check updates "its" comment with `--edit-last`, which on a refresh PR would overwrite the refresh workflow's latest weekly comment. The check no longer comments on refresh PRs (branch `data-refresh`); its report still goes to the run summary.

### Phase 6: Release workflow

1. Add `.github/workflows/release.yml` (`workflow_dispatch`, with `dry_run`, `correction`, and `reason` inputs). It reuses the check through `workflow_call`, passing the pinned commit, then follows "Release flow" above.
2. Look into GitHub's immutable releases setting, which as far as I know prevents changing or deleting a published release's tag and files. If it works as expected, turn it on so "never overwrite" is enforced in the GitHub interface too.

**Verification** (all as dry runs):

- On a test branch whose final files match the latest release except for access dates, the no-change guard stops the run.
- On a test branch with changed final files: no `correction` gives the expected `vYYYY.M.D` tag and notes; `correction` ticked with no release today stops; `correction` ticked without a reason stops.
- The same-day branch logic (existing tag, with and without `correction`) is tested by pointing the date at an existing release tag, for example with a `date` override input available only in dry runs.
- A tag that exists without a release stops the run: push a throwaway tag such as `v2000.1.1`, run a dry run dated that day, then delete the tag.

Make the first real release with the next data update. Afterward, confirm that the tag points at the commit the run started from, and that the attached files match `data_final/` at that commit byte for byte.

**As built (2026-10-22)**: `.github/workflows/release.yml` has three jobs.

- **plan** (read-only) runs `.github/scripts/release-plan.sh`. It applies the tag rules, the stray-tag check and the no-change guard. The guard compares the four final files with the previous release in Python's `csv` module, dropping the `date_accessed` column; releases through v2026.9.14 keep the files in `release/`. It also refuses a real release from any branch but `main`.
- **check** is `check.yml` called at the same commit, with the change report's baseline set to the previous release. When called this way, `check.yml` uploads the report as an artifact, for the release notes.
- **release** (`contents: write`; runs no R) runs `.github/scripts/publish-release.sh`:
  - creates the tag through the API, and the release as a draft with the four final CSVs and the report attached
  - checks that the tag points at the commit and downloads every file again to compare it byte for byte
  - only then publishes, marking the release as latest
  - if anything fails before publishing, deletes the draft and the tag
  - if the report is missing, the notes say so rather than blocking the release

The plan script was tested locally against the real releases, in eight cases:

- a normal release today gives `v2026.10.22`, compared with `v2026.9.14`
- a correction without a reason stops
- a correction with no release that day stops
- a same-day release without the correction box stops
- a same-day correction gives `v2026.9.14.2`
- an unchanged commit (`v2026.9.14` itself) stops with "Nothing changed since v2026.9.14, apart from access dates"
- a real release from another branch stops
- a stray local tag stops

The dry-run path of the publish script was also tested locally. The publishing path runs for the first time on the first real release, and its own checks (tag commit, byte-for-byte files) guard it.

### Phase 7: Documentation and cleanup

1. README: new layout, local workflow, weekly run, PRs and checks, releasing, and `BLS_DOWNLOAD_EMAIL`. State plainly that official data comes from GitHub releases, and that the files on `main` may include updates that haven't been released yet.
2. AGENTS.md: modes, checks, workflows, "never push to `main`", and how to run the offline check.
3. Optional: retitle the v2026.3.23 release, currently "Version 2023.3.26". Leave the two old tags without a `v` as they are, since renaming tags breaks links.

## Risks

- **BLS starts blocking GitHub's servers, or moves the file.** Neither is happening as of 2026-10-21 (see Phase 0). If it happens, the download fails, the committed file is used, the weekly report flags it, and the run ends as failed, so I get GitHub's failure email every week until it's fixed. I then commit the file through a PR when BLS publishes.
- **Exact match is brittle across machines.** Floating-point output could differ between my machine and the runner. Both are x86-64 Linux, so this is unlikely. If it happens, compare numbers with a tiny tolerance instead of comparing bytes.
- **Org settings block the bot.** The Economic org may forbid Actions from creating PRs, or creating a GitHub App may need an org admin.
- **Scheduled workflows get switched off.** GitHub disables them on public repos after 60 days without repository activity. Data changes nearly every month, so the bot's pushes should keep it active. If GitHub disables the workflow anyway, it shows a banner and I re-enable it.
- **Weekly package updates break the pipeline.** That is the point of updating everything weekly: I get a failure email, and `main` is unaffected.

### Accepted risks in the change report (decided 2026-10-21)

The change report is informational. None of these can put a wrong number into a release: releases are manual, the PR check guarantees that the committed numbers are reproducible, and a change to published numbers still shows in the web data diff and in the list of changed code. Reviewers should not report these as defects.

1. **Changes in `R/web.R` aren't detected from the numbers.** The report doesn't recompute the published stats or check how the web data is rounded. When `R/web.R` changes, the warning names it, and the change's effect shows in the web data and in the rounding lines of the headline stats. (After the 2026-10-22 simplification. This replaces a narrower risk from checkpoint review job 97.)
2. **The report's expectations go stale.** `index_terms` in `R/report_why.R` encodes how `R/combine.R` builds the indexes. After an intentional change to `R/combine.R` that doesn't update `index_terms`, reports flag false method changes until it is updated. AGENTS.md says to update both in the same PR.
3. **Code changes that shape the inputs are named, not measured.** For changes to `R/bls.R`, `R/bea.R`, `R/prices.R`, or the BLS and BEA series code files, the warning names the file, and the change's effect shows in the contributions of the inputs that file shapes.
4. **Releases before v2026.3.11 can't be baselines.** v2025.9.3 and v2026.1.16 store the BLS API results in an older format, and the report stops with a clear message.
5. **Revisions smaller than 1e-9 in relative terms aren't counted.** That threshold hides floating-point noise and is far below published precision.
6. **A stale `origin/main` baseline.** A local run without `git fetch` compares with an old `main`. CI always fetches first.
7. **A wrong access date for a hand-committed hours spreadsheet.** If the spreadsheet is committed by hand without updating its date in `data_raw/fetch_log.csv`, the sources CSV shows the wrong access date. If the old date is earlier than the spreadsheet's release date, a sanity check stops the pipeline. The README says to update the date.

## Resolved questions

1. **`data_raw/` layout**: yes, move the API outputs and the hours spreadsheet into `data_raw/`.
2. **Schedule**: Monday 8 a.m. Eastern, which picks up the previous week's BLS and BEA releases.
3. **Approvals and bypass**: no approvals required and no admin bypass.
4. **Same-day releases**: fail by default. A same-day correction is allowed only with the `correction` box ticked and a reason, and gets a `.2` suffix. A no-change guard stops releases whose files match the previous release. See "Release flow".
5. **Report storage**: reports are not committed. They live in PR comments, run summaries (kept 90 days), and release notes.
6. **Release guard**: compare all four final files with the previous release, ignoring only the sources CSV's `date_accessed` column. The guard only stops pointless releases; whether to release is my call. A stricter rule (web files only) would block releases I might sometimes want, such as the corrected hours dates now on `main`, the only change to the final files since v2026.9.14.
7. **Rename `release/` to `data_final/`** in Phase 1, matching the other `data_*` folders. Files on `main` can be ahead of the latest release, and the name `release/` suggests otherwise. Nothing outside the repo reads files from `main`, so neither this rename nor the `data_raw/` move breaks anything. File names, and the names of the files attached to GitHub releases, stay the same.

8. **Stale refresh PR**: if the fresh numbers match `main` while a refresh PR is open (for example, after merging a local data PR), the weekly run closes the refresh PR with the comment "`main` already has these numbers". That causes one notification.
9. **One refresh PR for data and packages**: package updates that change no numbers never open a PR by themselves. They ride along the next time the numbers change.
10. **Merge commits only** (`gh pr merge N --merge`), as in bls-index. Rebase merging would put commits where code and data disagree directly onto `main`. Squash and rebase would both replace the commits roborev reviewed with new ones it never saw. Merge commits keep every reviewed commit in `main`'s history, and `git log --first-parent main` still shows one entry per PR. (Changed from squash only on 2026-10-21.)
11. **No extra release notifications**: the plan stops at publishing the GitHub release. Updating the EPI page and SWADL stays as it is now.

## Open questions

None as of 2026-10-21.
