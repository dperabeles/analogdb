from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HTML_PATH = ROOT / "analog-db-dashboard.html"
SCHEMA_PATH = ROOT / "supabase" / "schema.sql"
MIGRATION_PATH = ROOT / "supabase" / "migrations" / "20260501_roll_exposure_settings.sql"


class ExposureSettingsTests(unittest.TestCase):
    def test_roll_exposures_schema_contract_exists(self):
        schema = SCHEMA_PATH.read_text()
        migration = MIGRATION_PATH.read_text()

        for sql in (schema, migration):
            self.assertIn("public.roll_exposures", sql)
            self.assertIn("roll_id bigint not null references public.rolls(id) on delete cascade", sql)
            self.assertIn("frame_number integer not null check (frame_number > 0)", sql)
            self.assertIn("unique (roll_id, frame_number)", sql)
            self.assertIn("apertura text", sql)
            self.assertIn("shutter_speed text", sql)
            self.assertIn("multiple_exposures boolean", sql)

    def test_rolls_flat_exposes_frame_settings_count(self):
        schema = SCHEMA_PATH.read_text()
        migration = MIGRATION_PATH.read_text()

        for sql in (schema, migration):
            self.assertIn('as "FRAME SETTINGS"', sql)
            self.assertIn('r.updated_at,\n  coalesce(re_stats.frame_settings_count, 0)::integer as "FRAME SETTINGS"', sql)
            self.assertIn("left join lateral", sql)
            self.assertIn("from public.roll_exposures re", sql)
            self.assertIn("coalesce(re.multiple_exposures, false)", sql)

    def test_ui_uses_fixed_slots_and_dropdown_values(self):
        html = HTML_PATH.read_text()

        self.assertIn("if (fmt === '35') return 36;", html)
        self.assertIn("if (fmt === '120') return 16;", html)
        self.assertIn("'f/1.0'", html)
        self.assertIn("'f/32'", html)
        self.assertIn("'Bulbo'", html)
        self.assertIn("'4s'", html)
        self.assertIn("'2s'", html)
        self.assertIn("'1/8000'", html)

    def test_ui_surfaces_settings_entry_and_saved_indicator(self):
        html = HTML_PATH.read_text()

        self.assertIn("Settings por frame", html)
        self.assertIn("Frame settings", html)
        self.assertIn("exposureSettingsCountForRoll", html)
        self.assertIn("Settings ${settingsCount}", html)
        self.assertIn("Settings ' + esc(settingsCount)", html)


if __name__ == "__main__":
    unittest.main()
