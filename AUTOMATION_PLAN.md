# Monthly pipeline automation plan

Goal: every month, with no (or almost no) human involvement, fetch fresh
CDS seasonal forecast data for a set of country/crop combinations, run
them through DSSAT, and publish the results somewhere the farmer-facing
app can read them - with a human only pulled in when something genuinely
needs a decision.

This document assumes you can program but haven't worked with pipeline
schedulers before - it avoids jargon where possible and explains the
"why" behind each choice.

## The idea in one sentence

A scheduled script starts a Claude Code session once a month; that
session follows a written playbook (a "Skill") to run and watch over the
whole pipeline for every country on this month's list, and only
interrupts a human if it hits something it can't resolve on its own.

## Step by step

**0. One-time setup (before the schedule ever runs)**
- Make sure the machine that will run this has CDS credentials
  (`~/.cdsapirc`) and any credentials the upload step needs (step 6)
  already configured - the scheduled run won't be able to type in a
  password, so anything it needs has to already be sitting there.
- Apply the two pipeline fixes from `cds_timing_investigation_findings.txt`
  (shared bbox per country instead of per zone; parallel worker pool
  built once per country instead of once per zone) - this isn't strictly
  required to get automation running, but it's what turns "56 hours per
  country" into "under an hour," which changes how ambitious the schedule
  can be.
- Write the Skill (see step 3) - a text file with instructions Claude
  Code follows every time it's invoked this way.

**1. A task list file names what to run this cycle**
A plain text (or YAML) file, e.g. `usecases/schedule/2026-10.txt`,
listing which existing usecase configs to run:
```
usecases/configs/KEN/maize_full.yml
usecases/configs/MWI/maize_full.yml
usecases/configs/MOZ/maize_full.yml
usecases/configs/MOZ/soybean_full.yml
```
Pointing at the existing YAML configs (rather than inventing a new format)
means the country/crop/season details only live in one place - editing
this list is the only thing that changes month to month.

**2. A real scheduler fires a `.sh` script on a fixed date**
Plain Linux `cron` is the natural choice here (e.g. `0 6 10 * *` = 6am on
the 10th of every month, a couple of days after CDS's usual release, to
leave buffer). One thing to confirm: does the machine this runs on stay
up and unchanged month to month? If yes, cron on that machine is enough.
If the machine could get rebuilt or replaced, the trigger needs to live
somewhere more durable than that one machine (this is a decision to make
with whoever manages the infrastructure - flagged as open below).

**3. The `.sh` script calls Claude Code non-interactively, pointed at a Skill**
This is the actual shell command - written so it can be copy-pasted and
adjusted:
```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=~/Alvaro_repos/agwise-planting-date-and-cultivar
TASK_LIST="usecases/schedule/$(date +%Y-%m).txt"
LOG_DIR="$REPO_DIR/logs/automation"
mkdir -p "$LOG_DIR"

cd "$REPO_DIR"
claude -p "/run-forecast-pipeline $TASK_LIST" \
  --dangerously-skip-permissions \
  > "$LOG_DIR/run_$(date +%F_%H%M).log" 2>&1
```
Notes on the flags, since they matter:
- `-p` ("print mode") runs Claude Code once, non-interactively, and exits
  when it's done - this is what makes it scriptable instead of needing
  someone to sit at a terminal. It stays running for as long as the whole
  job takes (potentially a few hours), which is fine - just don't wrap it
  in a short timeout.
- `--dangerously-skip-permissions` turns off the normal "ask before doing
  something risky" prompts. That's a real, deliberate tradeoff: it's
  necessary because nobody is there to click "approve" at 6am, but it
  only makes sense because the Skill's job is scoped to a well-understood,
  repeatable, non-destructive pipeline (it downloads data and writes new
  files - it doesn't delete anything or touch anyone else's systems). If
  that scope ever grows to include riskier actions, this flag deserves a
  second look.
- `/run-forecast-pipeline` is the Skill name (step 4), and the task-list
  path is passed as its argument.

**4. The Skill: what Claude Code actually does once invoked**
This is a written playbook (a file Claude Code reads every time it's
asked to run this Skill) - it needs to say, in plain instructions:
- For each line in the task list: run that usecase's pipeline (data
  fetch, weather/soil files, DSSAT run, merge, dashboard build).
- Watch the real output as it runs rather than just waiting on a timer -
  recognize the failure patterns already logged in `data_sourcing_bugs.txt`
  and `future_work.txt`, and decide: keep waiting, retry, skip one bad
  site and continue, or flag the whole usecase as failed.
- One usecase failing should never stop the others - they're independent,
  so keep going through the rest of the list regardless.
- If the whole run gets interrupted partway (machine restart, credit
  limit, anything) - re-running the same task list later should pick up
  from wherever it left off rather than redoing finished work. Most of
  the pipeline already skips work that's already done (existing weather
  files, existing FILEX files, etc.), so the Skill should rely on that
  rather than re-implementing its own progress tracking.
- Write a plain-language report at the end: which usecases succeeded,
  which failed and why, anything that needed a judgment call along the
  way. Save it somewhere permanent (not just in the chat) - e.g.
  `logs/automation/report_2026-10.md` - so it's readable later even by a
  different session.

**5. Escalate only on genuine surprises**
If something fails in a way that matches a known, already-documented
issue, the Skill handles it itself (retries, skips, or works around it)
and just notes it in the report. It should only actively notify a human
when it hits something new that isn't already covered by the bugs log -
that's the "little to no human interaction" bar.

**6. Publish the results**
Once a usecase's dashboard data is built, upload it to wherever the
farmer-facing app reads from (an `rsync`/`scp` to a server, an S3-style
upload, a database write - whichever matches how that app is actually
built). **This is the one piece still undecided** - it depends on the
app's serving setup, which isn't settled yet.

## Recommended CPU and memory

Based on what we actually measured this session, on the pod we're using
right now (8 CPUs, 32 GB RAM, per the container's real limits - not the
much larger numbers the host machine reports):
- The DSSAT-side steps for one whole country (weather/soil setup, FILEX
  creation, running the model, merging results) finish in well under an
  hour on this pod once the two fixes in
  `cds_timing_investigation_findings.txt` are applied, using about 7
  parallel workers at roughly 1-2 GB each.
- The CDS fetch step is not CPU- or memory-hungry at all - it's mostly
  waiting on network requests, and the actual downloaded files are tens
  of megabytes.
- **Recommendation: 8-16 CPUs and 16-32 GB RAM is comfortable** for
  running one country's pipeline at a time - i.e., a machine about the
  size of the one we're already using is enough, no need to provision
  something bigger by default.
- With the fixes applied, one country's full run (fetch + DSSAT + merge)
  is on the order of 1-1.5 hours. Running your 6-7 countries **one after
  another** on a single machine like this should comfortably finish
  within a single day - there's likely no need to run them concurrently
  on multiple machines at all, which simplifies things a lot compared to
  where this conversation started.
- If you do want them running at the same time instead of one after
  another (e.g. to finish in under an hour instead of half a day), plan
  on roughly one machine of this size per country running concurrently -
  but check this against your actual scale needs before spending on it,
  since sequential already looks fast enough for a monthly job.

## Open questions (need a decision, not yet resolved here)

1. **Where does step 6 actually upload to?** Depends on the app's serving
   infrastructure, which we don't have visibility into yet.
2. **Does the trigger machine (step 2) stay stable month to month?** If
   not, cron alone isn't durable enough and the trigger needs to live
   somewhere that survives a rebuild.
3. **Different countries may have different season calendars** (per
   earlier discussion: 2-3 months before season start, then monthly
   through the season) - the task list per month may need to differ by
   country rather than being one fixed list, or the Skill needs simple
   logic to check "is this country in its active window this month."

---

## Review notes (pipeline-developer pass)

A second look at the draft above changed a few things worth calling out
explicitly, since they're the kind of detail that's easy to miss on a
first pass:

- **Resumability was underspecified at first.** The original draft didn't
  say what happens if the monthly run itself gets interrupted halfway
  through. Added explicit guidance (step 4) to lean on the pipeline's
  existing "skip if already done" behavior rather than inventing new
  progress-tracking - simpler and less likely to drift out of sync with
  how the pipeline actually works.
- **One country's failure shouldn't block the rest.** Added explicitly in
  step 4 - obvious in hindsight, but worth stating so it's not assumed
  away.
- **The CPU/memory section originally assumed we'd need several
  concurrent machines**, carried over from earlier in this conversation
  before we had real timing numbers. Once the two pipeline fixes are
  accounted for, one modest machine running countries sequentially is
  probably enough - said so plainly rather than over-provisioning out of
  habit.
- **The `--dangerously-skip-permissions` flag needed an explicit
  justification**, not just a mention - it's a real safety tradeoff, and
  the plan should say out loud why it's acceptable here (a scoped,
  non-destructive, well-understood pipeline) rather than leave it looking
  like a shortcut.
