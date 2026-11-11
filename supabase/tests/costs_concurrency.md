# Costs — concurrency evidence (staging, 2026-10-22 UTC)

Same method as `film_inventory_concurrency.md`: two `pg_cron` jobs scheduled
together, each in its own background connection. Each job is a `do` block
that acts as the account (`request.jwt.claims` + `set local role
authenticated`), catches any error into its result and writes its timestamps
to a scratch table at the end of its own transaction.

Setup, committed in staging: account `conc-costs@inventario.invalid` with the
`costs` feature and one roll (362) without charges.

## Two devices save the lab costs of the same roll at once

Both jobs call `lab_costs_save` for roll 362 with `expected = []` and the same
wanted state (`dev_scan` 30000 MXN), with different command ids. j1 keeps its
transaction open 6 s after saving; j2 calls 1 s later.

| job | called | returned | result | finished |
|---|---|---|---|---|
| j1 | 14:48:15.205 | 14:48:15.216 | charge `60e2c5ae…` (`dev_scan`, version 1) | 14:48:21.219 |
| j2 | 14:48:16.204 | 14:48:21.228 | `P1105 version_conflict` | 14:48:21.228 |

j2 called while j1 was still open, waited on the per-account lock until j1
committed, and then found that what it had seen (`[]`) was no longer the
active state. One active charge, one row in total.

## After

The jobs were unscheduled and their run history deleted. The account was
deleted with `app.borrando_cuenta` on: 0 synthetic accounts, 0 lab charges,
0 rolls and 0 archived rows for it, 0 feature members, 0 command receipts;
scratch table dropped. The only cron job left is the pre-existing
`profile_username_cleanup`.
