# Film inventory — concurrency evidence (staging, 2026-10-22 UTC)

Two calls sent one after the other through the SQL connector never overlap, so
they cannot prove concurrency (a first attempt that way ran sequentially and
was discarded). Real overlap came from two `pg_cron` jobs scheduled together:
each job runs in its own background connection.

Setup, committed in staging: account `conc-a@inventario.invalid` (feature
member), one 35 mm camera, synthetic film stock. Each job is a `do` block that
acts as that account (`request.jwt.claims` + `set local role authenticated`),
calls `public.inventory_load`, catches any error into the result, and writes
its timestamps to a scratch table at the end of its own transaction.

## Last unit, two different commands

Stock: 1 available unit. Job a1 loads and keeps its transaction open 6 s.
Job a2 waits 1 s and loads with another command id.

| job | started | load called | load returned | result | finished |
|---|---|---|---|---|---|
| a1 | 04:24:49.252 | 04:24:49.252 | 04:24:49.268 | roll R002 created | 04:24:55.271 |
| a2 | 04:24:49.254 | 04:24:50.256 | 04:24:50.263 | `P1104 stock_conflict` | 04:24:50.263 |

a2 asked while a1 still held the unit: the locked unit was skipped and a2 got
`stock_conflict` without waiting. One roll, zero available.

## Same command twice at the same time

Stock: 2 available units. Both jobs use command `…cb000`; b1 keeps its
transaction open 6 s, b2 calls 1 s later.

| job | load called | load returned | result |
|---|---|---|---|
| b1 | 04:25:21.487 | 04:25:21.500 | roll 50 (R003), unit 133e1088… |
| b2 | 04:25:22.492 | 04:25:27.507 | roll 50 (R003), unit 133e1088… |

b2 waited on the command lock until b1 committed (04:25:27.503) and then
returned b1's receipt. One roll, one unit used, one available.

## After

The jobs were unscheduled and their run history deleted. The account was
deleted with `app.borrando_cuenta` on: 0 rows left in the inventory tables,
`rolls`, `deleted_rows`, `feature_members` and `username_claims`; scratch
table dropped; pg_net queue empty.
