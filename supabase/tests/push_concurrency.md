# Push claim under concurrency (ANA-74)

`push_flush.sql` covers the lease inside one transaction: a row claimed by
one call is not handed out again for 2 minutes. Two overlapping sessions can
only be checked by hand:

1. Session 1: `begin; select outbox_id from public.push_claim(100);` (keep it open).
2. Session 2: `select outbox_id from public.push_claim(100);`
   Expected: none of session 1's rows (`for update skip locked`).
3. Session 1: `commit;`, then session 2 again.
   Expected: still none of them until 2 minutes pass (`claimed_at` lease).
