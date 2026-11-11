-- Film inventory and costs are open to every approved account (Diego,
-- 2026-11-11). The privacy policy describes them since 2026-10-22
-- (dperabeles/analogdb#49), and the notice wait was waived because Diego is
-- the only active user. feature_enabled still requires an approved profile.
update app_private.feature_flags
   set enabled_for_everyone = true
 where feature in ('film_inventory', 'costs');
