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
| Notification | One rolling draft PR from a `data-refresh` branch, assigned to `benzipperer`. The run comments (and so emails) only when a web-visible output changes compared with what I last saw: the open refresh PR, or `main` if none is open. The PR title, which becomes the email subject, labels the change: "New quarter: 2026q3" or "Revisions only (largest: 0.1 points, 2026q2 pay, from CPI)". |
| "Web-visible" change | Any change to `data_final/epi_productivity_pay_gap_web.csv` or `data_final/epi_productivity_pay_gap_web_stats.csv`. These files are already rounded, so smaller revisions are reported but don't trigger email. |
| Hours spreadsheet | Downloaded automatically with `BLS_DOWNLOAD_EMAIL` in the `User-Agent` header. The release date is read from the ReadMe sheet. If the download fails, the committed file is used and the report says so. |

### Already verified

- BLS returns an empty response without an email in the header and the full file with one (tested locally 2026-10-21). The downloaded file matched the committed one byte for byte, and the ReadMe sheet contains "Data released September 3, 2026".
- `epidatatools`, `epitargets`, and `realtalk` are public repos, so CI can install them without a token.
- I have admin rights on the repo. There is no `.github/` folder.
- Since 2026-10-21, the "protect main" ruleset requires pull requests and merge commits on `main` (see Phase 4).
- Repo secrets `BLS_API_KEY`, `BEA_API_KEY`, and `BLS_DOWNLOAD_EMAIL` are set, and Actions may create pull requests (both done in GitHub settings 2026-10-21; confirmed by a real run in Phase 0).

## How it fits together

### Three pipeline modes, one `_targets.R`

- **Live (default, local `tar_make()`)**: fetches BLS and BEA API data and the BLS hours file, caching each for one day as now.
- **Offline (`PPG_OFFLINE=true`)**: never touches the network. It rebuilds everything from the committed raw data. CI uses this mode for the PR check.
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

- Live fetch targets record their dates in `data_raw/fetch_log.csv`, one row per source: date accessed, date published (where known), version (for `realtalk`), and status (for example, "download failed, kept file released 2026-09-03").
- `document_data()` reads the fetch log instead of the `source_dates` target.
- The hours publication date is parsed from the spreadsheet's ReadMe sheet, so `data_inputs/bls_hours_dates.csv` is deleted.

### Local workflow (after this plan)

1. `tar_make()` fetches data (cached one day), rebuilds outputs, runs sanity checks, and writes `reports/change_report.md` comparing against `origin/main`.
2. I review the report and `git diff`.
3. Optional: `PPG_OFFLINE=true` + `tar_make()` runs the same check CI will run.
4. I create a branch, commit, push, and open the PR with `gh pr create --body-file reports/change_report.md`.

### Weekly refresh flow

1. Check out `main`, restore packages, run `renv::update()` then `renv::snapshot()`.
2. Run the pipeline in fresh live mode with secrets `BLS_API_KEY`, `BEA_API_KEY`, `BLS_DOWNLOAD_EMAIL`.
3. Write the report to the run's summary page (always).
4. Compare the two web files with the "last seen" version: the open refresh PR's branch, or `main` if no refresh PR is open.
5. If they differ: commit all changed files onto a fresh branch from `main`, force-push it to `data-refresh`, open the draft PR (or update its title and description, with the title carrying the change label), post the report as a comment, and trigger the check workflow on the branch.
6. If they don't differ: do nothing to the branch or PR, with one exception. If a refresh PR is open and the fresh web files also match `main` (for example, because a local data PR with the same numbers was merged), close the refresh PR with the comment "`main` already has these numbers".
7. If the run fails, GitHub sends its own failure email.

A PR opened with GitHub's built-in Actions token doesn't trigger `pull_request` workflows. Step 5 works around this by starting the check with `gh workflow run check.yml --ref data-refresh`; manual triggers are exempt from that limitation. Phase 5 verifies that this satisfies the required check.

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
4. **Upstream code changes.** A change in `R/bls.R` (for example, the wage splice) shows up inside an input's contribution, not in the remainder. For each input, check whether its raw data, its code, or both changed. If both changed, rerun the new code on the baseline raw data in offline mode and split that input's contribution into data and code parts.
5. **New periods.** No old value exists to split. Report each source's latest available period, before and after, and which source limits the latest common quarter.
6. **Headline stats.** `R/web.R` publishes four kinds of stat, each for productivity and pay. Each gets its own treatment:

   | Stat | Formula | How its revision is split |
   |---|---|---|
   | Total growth, 1979q4 to latest | G = I_T / I_1979q4, shown as G − 1 | Log identity with 1979q4 as the base (the 1948q1 terms cancel). Points via the log mean of old and new G. |
   | Average annual growth, 1948q1 to 1979q4 | a = G^(1/years) − 1, with G = I_1979q4 / I_1948q1 | log(1 + a) = log(G) / years, so each input's log contribution is divided by the number of years. Points via the log mean of old and new 1 + a. The base here is 1948q1, so revisions to 1948 inputs matter. |
   | Average annual growth, 1979q4 to latest | as above, with 1979q4 to latest | As above, with 1979q4 as the base. |
   | Productivity growth as a multiple of pay growth | R = (G_prod − 1) / (G_pay − 1); the code divides the larger total growth by the smaller | Not split. Shown as old and new values only; it follows from the two total growth stats, which are split. |

   - All splits use stats recomputed from the unrounded indexes, where the identity is exact. The published stats come from indexes already rounded to one decimal. For example, for the 2026q1 pay growth factor in the v2026.7.30 to v2026.9.14 comparison, rounding alone leaves a log remainder of −7.8e-5, checked 2026-10-21. So the gap between each published stat and its unrounded version gets a separate "rounding" line, never "code or method change".
   - When the latest quarter moves, the end point and the number of years change. Report the effect of the added quarters separately from revisions to existing quarters.
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

### Phase 0: Feasibility checks (on a branch, before anything else)

1. ~~Add repo secrets `BLS_API_KEY`, `BEA_API_KEY`, `BLS_DOWNLOAD_EMAIL`.~~ Done 2026-10-21 in GitHub settings.
2. ~~Allow Actions to create pull requests (Settings → Actions → General).~~ Done 2026-10-21.

   The local `gh` token can't read secrets or Actions settings, so step 3 confirms both in a real run.
3. Push a throwaway workflow, triggered on push to a `spike/*` branch, with two jobs:
   - **Secrets and downloads**: report whether each secret is set, without printing values. Make one small BLS API call and one small BEA API call with the keys. Download the hours file with `BLS_DOWNLOAD_EMAIL` in the `User-Agent` header, and report the file size and the "Data released" line from its ReadMe sheet. This answers whether BLS accepts downloads from GitHub's servers.
   - **Bot PR**: with `pull-requests: write`, open a draft PR from the spike branch to `main` using the built-in token, then close it. This confirms the Actions setting.
4. Remove the spike workflow in a follow-up commit, and record the results in this plan. Merge the branch (`spike/phase-0`) through a PR, so its net change is the plan and AGENTS.md updates.

**Exit criteria**: both API keys work from CI, I know whether automated hours download works from CI, and the bot can open PRs.

### Phase 1: Restructure the pipeline (local only)

1. Create `data_raw/` and move the two API outputs and the hours spreadsheet there with `git mv`. Rename `release/` to `data_final/` with `git mv`. Update paths in `_targets.R` and `R/document_data.R`.
2. Add a live hours download target (one-day cache, `User-Agent` from `BLS_DOWNLOAD_EMAIL`). On failure, keep the committed file and record the failure in the fetch log.
3. Add `fetch_log.csv`, written in live mode and read in offline mode. Seed it with the dates currently in `release/epi_productivity_pay_gap_sources.csv`.
4. Parse the hours release date from the ReadMe sheet. Delete `data_inputs/bls_hours_dates.csv`.
5. Add offline mode (`PPG_OFFLINE`) with its own store.
6. Add sanity check targets that stop the pipeline on failure:
   - no missing quarters from 1948q1 to the latest quarter in the web file
   - both indexes equal 100 in 1948q1 (and in 1948 for annual data)
   - both web series end in the same quarter
   - annual data only for complete years
   - web stats are finite and parse correctly
   - every source in the sources CSV has an access date, and publication dates are not after access dates
   - installed package versions match `renv.lock` (error offline, warning in live mode)
7. Stop committing `_targets/meta/meta`: add `_targets/` to the root `.gitignore` and `git rm --cached` it.

**Verification**: run offline mode on the committed data. Every file in `data_final/` and `data_outputs/` must match the version committed before Phase 1 (then in `release/` and `data_outputs/`) byte for byte, with one expected exception: the `data_location` column of the sources CSV, which now points to `data_raw/` for the moved files. Then do one live run and confirm only expected files change.

### Phase 2: Change report

1. Write a baseline loader that reads final, raw, and intermediate files and `renv.lock` at a git ref. It must handle older refs, where files sit at their pre-Phase 1 paths: `release/` instead of `data_final/`, and the API outputs and hours spreadsheet outside `data_raw/`. Every release through v2026.9.14 uses the old paths.
2. Write each report section as its own function returning a small table, plus one function that assembles the Markdown.
3. Implement the log decomposition and the "code or method change" remainder.
4. Add the `change_report` target.

**Verification**: run the report comparing v2026.9.14 with v2026.7.30. Between those releases only data and `renv.lock` changed, so the remainder should be close to zero and the contributions should be plausible. Nothing may be attributed to "code or method change", including in the headline stats. Also run it against an unchanged working tree; it should report no changes. Finally, test a revision to the base period: copy the baseline inputs, change the 1948 CPI values, and check that the 1948–1979 stats reconcile exactly to a CPI contribution (apart from the separate rounding line), while the stats based at 1979q4 show no change.

### Phase 3: PR check workflow

1. Add `.github/workflows/check.yml`, triggered on `pull_request` to `main`, `push` to `main`, `workflow_dispatch`, and `workflow_call`.
2. Run on `ubuntu-24.04`, not `ubuntu-latest`. `.Rprofile` only uses prebuilt Posit binary packages for known Ubuntu codenames such as noble (24.04), so a future `ubuntu-latest` would compile every package from source.
3. Steps: check out with full history; set up R using the version in `renv.lock` (`r-lib/actions/setup-r`); restore packages with caching (`r-lib/actions/setup-renv`); run offline `tar_make()` for every target except the change report; fail if `git diff --exit-code -- data_final data_outputs` shows any difference.
4. Then, in a separate step that can't fail the job (`continue-on-error: true`), build the report and write it, or its error message, to the job summary. Post or update one PR comment with it only for PRs from branches in this repo, because PRs from forks get a read-only token.

**Verification**: open two test PRs. One changes only the README and should pass. One changes rounding in `R/web.R` without rebuilding and should fail on the diff step. Then, on the README PR, make the report step fail on purpose (for example, by setting `PPG_BASELINE` to a ref that doesn't exist): the check must still pass.

5. After the check job has run once, add it to the required status checks of the "protect main" ruleset (Phase 4). A check only appears in the ruleset's list after it has run.

### Phase 4: Protect `main` (done 2026-10-21, except the required check)

The "protect main" ruleset on the default branch is active, with:

- a pull request required, with 0 required approvals
- no bypass list, so admins follow the same rules
- force pushes and branch deletion blocked
- merge commits only (no squash or rebase)
- branches not required to be up to date, since that would force a rebuild for every unrelated merge
- required status checks turned on, with no checks listed yet; Phase 3 step 5 adds the check job

**Verification**: a direct `git push` to `main` is rejected.

### Phase 5: Weekly refresh workflow

1. Add `.github/workflows/refresh.yml` with `schedule` and `workflow_dispatch`, on `ubuntu-24.04`. GitHub's schedules are in UTC and ignore daylight saving time, so use `cron: "7 12 * * 1"`: Monday 8:07 a.m. EDT, 7:07 a.m. EST. The odd minute avoids the top-of-hour rush, when GitHub delays scheduled runs.
2. Permissions: `contents: write`, `pull-requests: write`, `actions: write`. Set `GITHUB_PAT` to the built-in token so `renv::update()` doesn't hit GitHub API limits for the GitHub-hosted EPI packages.
3. Implement the flow under "Weekly refresh flow" above.

**Verification**:

- Run it manually: it opens a draft PR assigned to me, I get an email, and the check runs on the PR and shows as the required check.
- Run it again right away: it changes nothing and sends no email.
- Mark the PR ready and merge it.

If the dispatched check doesn't satisfy the ruleset, fall back to a GitHub App token for creating the PR (needs an Economic org admin).

### Phase 6: Release workflow

1. Add `.github/workflows/release.yml` (`workflow_dispatch`, with `dry_run`, `correction`, and `reason` inputs). It reuses the check through `workflow_call`, passing the pinned commit, then follows "Release flow" above.
2. Look into GitHub's immutable releases setting, which as far as I know prevents changing or deleting a published release's tag and files. If it works as expected, turn it on so "never overwrite" is enforced in the GitHub interface too.

**Verification** (all as dry runs):

- On a test branch whose final files match the latest release except for access dates, the no-change guard stops the run.
- On a test branch with changed final files: no `correction` gives the expected `vYYYY.M.D` tag and notes; `correction` ticked with no release today stops; `correction` ticked without a reason stops.
- The same-day branch logic (existing tag, with and without `correction`) is tested by pointing the date at an existing release tag, for example with a `date` override input available only in dry runs.
- A tag that exists without a release stops the run: push a throwaway tag such as `v2000.1.1`, run a dry run dated that day, then delete the tag.

Make the first real release with the next data update. Afterward, confirm that the tag points at the commit the run started from, and that the attached files match `data_final/` at that commit byte for byte.

### Phase 7: Documentation and cleanup

1. README: new layout, local workflow, weekly run, PRs and checks, releasing, and `BLS_DOWNLOAD_EMAIL`. State plainly that official data comes from GitHub releases, and that the files on `main` may include updates that haven't been released yet.
2. AGENTS.md: modes, checks, workflows, "never push to `main`", and how to run the offline check.
3. Optional: retitle the v2026.3.23 release, currently "Version 2023.3.26". Leave the two old tags without a `v` as they are, since renaming tags breaks links.

## Risks

- **BLS blocks GitHub's servers.** Then the hours file stays manual. The weekly report flags it, and I commit the file through a PR when BLS publishes.
- **Exact match is brittle across machines.** Floating-point output could differ between my machine and the runner. Both are x86-64 Linux, so this is unlikely. If it happens, compare numbers with a tiny tolerance instead of comparing bytes.
- **Org settings block the bot.** The Economic org may forbid Actions from creating PRs, or creating a GitHub App may need an org admin.
- **Scheduled workflows get switched off.** GitHub disables them on public repos after 60 days without repository activity. Data changes nearly every month, so the bot's pushes should keep it active. If GitHub disables the workflow anyway, it shows a banner and I re-enable it.
- **Weekly package updates break the pipeline.** That is the point of updating everything weekly: I get a failure email, and `main` is unaffected.

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
