from pathlib import Path
import importlib.util
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
HTML_PATH = ROOT / "analog-db-dashboard.html"
MIGRATE_PATH = ROOT / "supabase" / "migrate.py"
DB_MIGRATION_PATH = ROOT / "supabase" / "migrations" / "20260504_extend_historical_film_stock_catalog.sql"

REQUIRED_STOCKS = {
    "AgfaPhoto": {
        "Vista Plus 200": (200, "COLOR"),
        "Vista Plus 400": (400, "COLOR"),
        "CT Precisa 100": (100, "SLIDE"),
    },
    "Agfa": {
        "Ultra 100": (100, "COLOR"),
        "Optima 100": (100, "COLOR"),
        "Optima 200": (200, "COLOR"),
    },
    "Ferrania": {
        "Solaris 100": (100, "COLOR"),
        "Solaris 200": (200, "COLOR"),
        "Solaris 400": (400, "COLOR"),
        "Solaris 800": (800, "COLOR"),
    },
    "Fujifilm": {
        "Fujicolor 100": (100, "COLOR"),
        "Superia Premium 400": (400, "COLOR"),
        "Fujicolor Industrial 100": (100, "COLOR"),
        "Fujicolor Industrial 400": (400, "COLOR"),
        "Natura 1600": (1600, "COLOR"),
        "Superia 100": (100, "COLOR"),
        "Superia 200": (200, "COLOR"),
        "Superia X-TRA 400": (400, "COLOR"),
        "Superia X-TRA 800": (800, "COLOR"),
        "Superia 1600": (1600, "COLOR"),
        "Reala 100": (100, "COLOR"),
        "Pro 160S": (160, "COLOR"),
        "Pro 160C": (160, "COLOR"),
        "Pro 160NS": (160, "COLOR"),
        "Pro 400H": (400, "COLOR"),
        "Neopan 400": (400, "B/W"),
        "Neopan 1600": (1600, "B/W"),
        "Neopan 100 Acros": (100, "B/W"),
    },
    "Kodak": {
        "Portra 160NC": (160, "COLOR"),
        "Portra 160VC": (160, "COLOR"),
        "Portra 400NC": (400, "COLOR"),
        "Portra 400VC": (400, "COLOR"),
        "Portra 400UC": (400, "COLOR"),
        "Plus-X 125": (125, "B/W"),
        "BW400CN": (400, "B/W"),
        "Elite Chrome 100": (100, "SLIDE"),
        "Elite Chrome 200": (200, "SLIDE"),
        "Ektachrome E100G": (100, "SLIDE"),
        "Ektachrome E100VS": (100, "SLIDE"),
        "Ektachrome E200": (200, "SLIDE"),
    },
    "Konica Minolta": {
        "Centuria 100": (100, "COLOR"),
        "Centuria 200": (200, "COLOR"),
        "Centuria 400": (400, "COLOR"),
        "Centuria 800": (800, "COLOR"),
        "VX 100": (100, "COLOR"),
        "VX 200": (200, "COLOR"),
        "VX 400": (400, "COLOR"),
    },
}


def load_migrate_catalog():
    spec = importlib.util.spec_from_file_location("analogdb_migrate", MIGRATE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return {
        manufacturer: {name: (iso, film_type) for name, iso, film_type in stocks}
        for manufacturer, stocks in module.FILM_CATALOG.items()
    }


def load_html_catalog_entries():
    html = HTML_PATH.read_text()
    match = re.search(r"const FILM_CATALOG = \{(?P<body>.*?)\n\};", html, re.S)
    if not match:
        raise AssertionError("FILM_CATALOG constant not found in dashboard HTML")

    entries = {}
    manufacturer_pattern = re.compile(r"^\s*'([^']+)':\s*\[(.*)\],$", re.M)
    stock_pattern = re.compile(r"\['((?:\\'|[^'])+)',\s*(\d+),\s*'([^']+)'\]")
    for manufacturer, stock_blob in manufacturer_pattern.findall(match.group("body")):
        entries[manufacturer] = {
            name.replace("\\'", "'"): (int(iso), film_type)
            for name, iso, film_type in stock_pattern.findall(stock_blob)
        }
    return entries


def load_db_migration_entries():
    sql = DB_MIGRATION_PATH.read_text()
    row_pattern = re.compile(
        r"\('([^']+)', '([^']+)', (\d+), '(COLOR|B/W|SLIDE)', true\)"
    )
    entries = {}
    for manufacturer, name, iso, film_type in row_pattern.findall(sql):
        entries.setdefault(manufacturer, {})[name] = (int(iso), film_type)
    return entries


class FilmCatalogTests(unittest.TestCase):
    def assert_required_stocks(self, catalog):
        for manufacturer, stocks in REQUIRED_STOCKS.items():
            self.assertIn(manufacturer, catalog)
            for name, expected_meta in stocks.items():
                self.assertEqual(catalog[manufacturer].get(name), expected_meta)

    def test_migrate_catalog_includes_historical_and_japan_market_stocks(self):
        self.assert_required_stocks(load_migrate_catalog())

    def test_dashboard_catalog_includes_historical_and_japan_market_stocks(self):
        self.assert_required_stocks(load_html_catalog_entries())

    def test_db_migration_safely_upserts_historical_and_japan_market_stocks(self):
        sql = DB_MIGRATION_PATH.read_text().lower()

        self.assert_required_stocks(load_db_migration_entries())
        self.assertIn("on conflict (manufacturer, name) do update", sql)
        self.assertNotIn("delete from", sql)
        self.assertNotIn("truncate", sql)
        self.assertNotIn("drop table", sql)

    def test_catalogs_do_not_define_duplicate_manufacturer_name_pairs(self):
        for catalog in (load_migrate_catalog(), load_html_catalog_entries(), load_db_migration_entries()):
            pairs = [(manufacturer, name) for manufacturer, stocks in catalog.items() for name in stocks]
            self.assertEqual(len(pairs), len(set(pairs)))

    def test_canonical_names_distinguish_historical_variants(self):
        catalog = load_migrate_catalog()

        self.assertEqual(catalog["Fujifilm"]["Neopan 100 Acros"], (100, "B/W"))
        self.assertEqual(catalog["Fujifilm"]["Neopan 100 Acros II"], (100, "B/W"))
        self.assertEqual(catalog["Kodak"]["Ektachrome E100"], (100, "SLIDE"))
        self.assertEqual(catalog["Kodak"]["Ektachrome E100G"], (100, "SLIDE"))


if __name__ == "__main__":
    unittest.main()
