from pathlib import Path
import unittest


HTML_PATH = Path(__file__).resolve().parents[1] / "analog-db-dashboard.html"
SCHEMA_PATH = Path(__file__).resolve().parents[1] / "supabase" / "schema.sql"
MIGRATION_PATH = Path(__file__).resolve().parents[1] / "supabase" / "migrations" / "20260429_reactivate_rejected_profiles.sql"


class RejectedAdminUiTests(unittest.TestCase):
    def test_admin_dashboard_exposes_rejected_users_section_and_pending_reactivation_action(self):
        html = HTML_PATH.read_text()

        self.assertIn("async function loadRejectedUsers()", html)
        self.assertIn(".eq('status', 'rejected')", html)
        self.assertIn("function rejectedAdminUserCard(profile)", html)
        self.assertIn("Usuarios rechazados", html)
        self.assertIn("Reactivar", html)
        self.assertIn("p_status: 'pending'", html)
        self.assertIn("max-width:180px;width:100%", html)
        self.assertIn("font-size:10px;color:rgba(232,223,209,0.42);margin-top:8px;text-align:right;word-break:break-word;", html)

    def test_admin_status_function_allows_pending_and_clears_rejection_metadata(self):
        schema = SCHEMA_PATH.read_text()

        self.assertIn("if p_status not in ('pending', 'approved', 'rejected') then", schema)
        self.assertIn("rejected_at = case when p_status = 'rejected' then now() else null end", schema)
        self.assertIn("rejected_by = case when p_status = 'rejected' then actor_id else null end", schema)

    def test_reactivation_migration_exists(self):
        self.assertTrue(MIGRATION_PATH.exists())
        migration = MIGRATION_PATH.read_text()

        self.assertIn("create or replace function public.admin_set_profile_status", migration)
        self.assertIn("if p_status not in ('pending', 'approved', 'rejected') then", migration)

    def test_mobile_detail_technical_rows_escape_user_data_by_default(self):
        html = HTML_PATH.read_text()

        self.assertIn("row.html != null ? row.html : esc(row.text)", html)
        self.assertNotIn('row.v +', html)
        self.assertIn("techRows.push({ l: 'Cámara', text: cameraModel })", html)
        self.assertIn("techRows.push({ l: 'Lugar', text: locs.join(' · ') })", html)
        self.assertIn("techRows.push({ l: 'Rating', html:", html)


if __name__ == "__main__":
    unittest.main()
