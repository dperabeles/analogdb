# Inbox: two evaluations at the same time

Staging (`wxwfcxlyqnczujuoqnlj`), 2026-10-23 03:24 UTC. Two `execute_sql` calls
in one message run one after the other, so they prove nothing; two `pg_cron`
jobs run on their own connections.

## Setup (committed, then deleted)

- Synthetic account `conc@buzon.invalid`, inserted with
  `profiles_notify_approved` and `profiles_notify_pending_signup` disabled for
  that transaction only (no signup e-mail queued: `net.http_request_queue` = 0).
- 5 rolls `Developed` with no camera and no lab: 2 created 30 days ago (old),
  3 created now (new). Inbox activated one day ago.
- Table `app_private.zz_conc (job, started, ended)`.

## Jobs

`zz_inbox_c1` and `zz_inbox_c2`, both every `2 seconds`, each a `do` block that:
exits if its row already exists; inserts its start time; calls
`app_private.inbox_evaluate(account, '2026-11-01 15:00Z')`; sleeps 1 second
inside the same transaction (holding the per-account lock); writes its end time.

## Result

| job | started | ended |
|---|---|---|
| c2 | 03:24:13.166 | 03:24:14.188 |
| c1 | 03:24:13.168 | 03:24:15.207 |

- Started 2 ms apart; c1 waited for c2's lock and finished one second later.
- Notices: `backlog_incomplete` 1, `missing_camera` 3, `missing_lab` 3. That is
  exactly one evaluation (the old rolls in the group, one loose notice per gap
  of each new roll), with no duplicates.
- Every run in `cron.job_run_details`: `succeeded`.

## Cleanup

`cron.unschedule` of both jobs, their `cron.job_run_details` deleted, the
account deleted with `app.borrando_cuenta = 'si'`, `zz_conc` dropped. After:
0 jobs, 0 run rows, 0 accounts, 0 rolls, 0 inbox rows, 0 trash rows.

Timing of the large archive (300 rolls out of camera, 10 cameras, 36 frames
each, 205 notices): `inbox_evaluate` 0.12 s (0.14 s the second time),
`inbox_list` 0.07 s.
