"""
analogdb — Migración inicial de JSON a Supabase.

Uso:
    py supabase/migrate.py

Lee el JSON exportado del HTML y lo sube a Supabase via REST API:
  1. Puebla `film_stocks` con el catálogo Wikipedia + stocks del usuario
  2. Inserta `cameras` y `labs` únicas
  3. Inserta `rolls` con las FK resueltas

Seguro de re-ejecutar: usa upsert on conflict para catálogos y
borra rolls previos antes de re-insertar (idempotente).
"""
import json, sys, os
import urllib.request, urllib.error

# ═══════════════════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════════════════
SUPABASE_URL = "https://dqjjxxqruxxfsfoejdzl.supabase.co"
SUPABASE_KEY = "sb_publishable_t8qzsNZaeCwAIbpEIoBPTQ_wF_30652"
JSON_PATH    = r"C:\Users\arqdi\Downloads\film-rolls-2026-04-19.json"

HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=representation",
}

# ═══════════════════════════════════════════════════════════════
# Catálogo Wikipedia (espejo del FILM_CATALOG en el HTML)
# ═══════════════════════════════════════════════════════════════
FILM_CATALOG = {
 'AgfaPhoto':   [('APX 100',100,'B/W'),('APX 400',400,'B/W'),('Color 400',400,'COLOR')],
 'ADOX':        [('CMS 20 II PRO',20,'B/W'),('HR-50',50,'B/W'),('CHS 100 II',100,'B/W'),('Scala 50',50,'SLIDE')],
 'Bergger':     [('Pancro 400',400,'B/W')],
 'CatLABS':     [('X FILM 80',80,'B/W'),('X FILM 100 Color',100,'COLOR'),('X FILM 320',320,'B/W'),('X FILM 320 Pro',320,'B/W')],
 'CineStill':   [('bwXX',250,'B/W'),('50D',50,'COLOR'),('400D',400,'COLOR'),('800T',800,'COLOR'),('Red Rum',200,'COLOR')],
 'Ferrania':    [('Orto',50,'B/W'),('P30',80,'B/W'),('P33',160,'B/W')],
 'Flic Film':   [('Wolfen 100',100,'B/W'),('UltraPan 100',100,'B/W'),('UltraPan 200',200,'B/W'),('UltraPan 400',400,'B/W'),('Elektra 100',100,'COLOR'),('Cine color 50D',50,'COLOR'),('Cine color 250D',250,'COLOR'),('Cine color 500T',500,'COLOR'),('Chrome',100,'SLIDE')],
 'Foma':        [('Fomapan 100 Classic',100,'B/W'),('Fomapan 200 Creative',200,'B/W'),('Fomapan 400 Action',400,'B/W'),('Foma Ortho 400',400,'B/W'),('Fomapan R 100',100,'SLIDE')],
 'Fujifilm':    [('Neopan 100 Acros II',100,'B/W'),('Fujifilm 200',200,'COLOR'),('Fujifilm 400',400,'COLOR'),('Velvia 50',50,'SLIDE'),('Velvia 100',100,'SLIDE'),('Provia 100F',100,'SLIDE')],
 'Harman':      [('Phoenix 200',200,'COLOR'),('Phoenix II 200',200,'COLOR'),('RED 125',125,'COLOR')],
 'Ilford':      [('PAN 100',100,'B/W'),('PAN 400',400,'B/W'),('PANF Plus',50,'B/W'),('FP4 Plus',125,'B/W'),('HP5 Plus',400,'B/W'),('DELTA 100',100,'B/W'),('DELTA 400',400,'B/W'),('DELTA 3200',1000,'B/W'),('ORTHO Plus',80,'B/W'),('SFX 200',200,'B/W'),('XP2 Super',400,'B/W')],
 'Kentmere':    [('PAN 100',100,'B/W'),('PAN 200',200,'B/W'),('PAN 400',400,'B/W')],
 'Kodak':       [('Tri-X',400,'B/W'),('T-MAX 100',100,'B/W'),('T-MAX 400',400,'B/W'),('T-MAX P3200',800,'B/W'),('Double-X',250,'B/W'),('ColorPlus 200',200,'COLOR'),('ProImage 100',100,'COLOR'),('Gold 200',200,'COLOR'),('UltraMax 400',400,'COLOR'),('Portra 160',160,'COLOR'),('Portra 400',400,'COLOR'),('Portra 800',800,'COLOR'),('Ektar 100',100,'COLOR'),('Ektachrome E100',100,'SLIDE'),('Vision3 50D',50,'COLOR'),('Vision3 250D',250,'COLOR'),('Vision3 200T',200,'COLOR'),('Vision3 500T',500,'COLOR')],
 'Kosmo Foto':  [('Mono',100,'B/W'),('Agent Shadow',400,'B/W')],
 'Lomography':  [('Earl Grey',100,'B/W'),('Lady Grey',400,'B/W'),('Berlin 400',400,'B/W'),('Potsdam 100',100,'B/W'),('Fantome Kino',8,'B/W'),('Babylon Kino',13,'B/W'),('Color Negative 100',100,'COLOR'),('Color Negative 400',400,'COLOR'),('Color Negative 800',800,'COLOR'),('LomoChrome Turquoise XR',400,'COLOR'),('LomoChrome Purple XR',400,'COLOR'),('LomoChrome Metropolis XR',400,'COLOR'),("LomoChrome Color '92",400,'COLOR'),('LomoChrome Classicolor 200',200,'COLOR'),('Redscale XR',100,'COLOR')],
 'Luckyfilm':   [('SHD 100',100,'B/W'),('SHD 400',400,'B/W'),('C200',200,'COLOR')],
 'Rollei':      [('RPX 25',25,'B/W'),('RPX 100',100,'B/W'),('RPX 400',400,'B/W'),('Retro 80S',80,'B/W'),('Retro 400S',400,'B/W'),('Superpan 200',200,'B/W'),('Infrared 400',400,'B/W')],
 'Shanghai':    [('GP3 100',100,'B/W')],
 'Filmdongdong':[('Aerocolor III',125,'COLOR')],
 'Reto':        [('Maple 100',100,'COLOR')],
 'Japan Camera Hunter': [('Streetpan 400',400,'B/W')],
}

# ═══════════════════════════════════════════════════════════════
# Helpers HTTP (urllib, sin dependencias)
# ═══════════════════════════════════════════════════════════════
def http(method, path, body=None, params=None):
    url = f"{SUPABASE_URL}/rest/v1/{path}"
    if params:
        url += "?" + "&".join(f"{k}={v}" for k,v in params.items())
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=HEADERS)
    try:
        with urllib.request.urlopen(req) as resp:
            body_resp = resp.read()
            return json.loads(body_resp) if body_resp else None
    except urllib.error.HTTPError as e:
        print(f"  !! HTTP {e.code} {method} {path}")
        print(f"     {e.read().decode(errors='replace')[:500]}")
        sys.exit(1)

def select(table, **filters):
    return http("GET", table, params={**filters, "select": "*"})

def insert(table, row):
    return http("POST", table, body=row)

def upsert(table, row, on_conflict):
    params = {"on_conflict": on_conflict}
    return http("POST", table, body=row, params=params)

# ═══════════════════════════════════════════════════════════════
# Helpers de lookup/upsert con cache
# ═══════════════════════════════════════════════════════════════
_cache = {"stocks": {}, "cameras": {}, "labs": {}}

def get_or_create_stock(manufacturer, name, iso=None, ftype=None):
    if not manufacturer and not name: return None
    key = (manufacturer or '', name or '')
    if key in _cache["stocks"]: return _cache["stocks"][key]
    row = {"manufacturer": manufacturer or '', "name": name or '',
           "iso": iso, "type": ftype if ftype in ('COLOR','B/W','SLIDE') else None,
           "in_catalog": False}
    headers = {**HEADERS, "Prefer": "return=representation,resolution=merge-duplicates"}
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/film_stocks?on_conflict=manufacturer,name",
        data=json.dumps(row).encode(), method="POST", headers=headers)
    with urllib.request.urlopen(req) as resp:
        out = json.loads(resp.read())
    sid = out[0]["id"]
    _cache["stocks"][key] = sid
    return sid

def get_or_create_camera(maker, model, fmt=None, ctype=None):
    if not maker and not model: return None
    key = (maker or '', model or '')
    if key in _cache["cameras"]: return _cache["cameras"][key]
    row = {"maker": maker or None, "model": model or None,
           "format": fmt or None, "type": ctype or None}
    headers = {**HEADERS, "Prefer": "return=representation,resolution=merge-duplicates"}
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/cameras?on_conflict=maker,model",
        data=json.dumps(row).encode(), method="POST", headers=headers)
    with urllib.request.urlopen(req) as resp:
        out = json.loads(resp.read())
    cid = out[0]["id"]
    _cache["cameras"][key] = cid
    return cid

def get_or_create_lab(name):
    if not name: return None
    if name in _cache["labs"]: return _cache["labs"][name]
    row = {"name": name}
    headers = {**HEADERS, "Prefer": "return=representation,resolution=merge-duplicates"}
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/labs?on_conflict=name",
        data=json.dumps(row).encode(), method="POST", headers=headers)
    with urllib.request.urlopen(req) as resp:
        out = json.loads(resp.read())
    lid = out[0]["id"]
    _cache["labs"][name] = lid
    return lid

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════
def main():
    print("▶ Leyendo JSON:", JSON_PATH)
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        rolls = json.load(f)
    print(f"  {len(rolls)} rollos en el JSON")

    # ── 1. Limpiar rolls (por si re-corres la migración)
    print("▶ Limpiando tabla rolls…")
    http("DELETE", "rolls", params={"id": "gte.0"})

    # ── 2. Sembrar catálogo Wikipedia en film_stocks
    print("▶ Sembrando catálogo Wikipedia (film_stocks)…")
    catalog_rows = []
    for man, stocks in FILM_CATALOG.items():
        for name, iso, ftype in stocks:
            catalog_rows.append({
                "manufacturer": man, "name": name,
                "iso": iso, "type": ftype, "in_catalog": True,
            })
    headers = {**HEADERS, "Prefer": "resolution=merge-duplicates"}
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/film_stocks?on_conflict=manufacturer,name",
        data=json.dumps(catalog_rows).encode(), method="POST", headers=headers)
    with urllib.request.urlopen(req) as resp:
        resp.read()
    print(f"  {len(catalog_rows)} stocks del catálogo")

    # ── 3. Preload cache de stocks
    print("▶ Cacheando IDs de film_stocks…")
    all_stocks = http("GET", "film_stocks", params={"select": "id,manufacturer,name"})
    for s in all_stocks:
        _cache["stocks"][(s["manufacturer"], s["name"])] = s["id"]
    print(f"  {len(_cache['stocks'])} stocks cacheados")

    # ── 4. Migrar cada rollo
    print("▶ Migrando rollos…")
    inserted = 0
    errors   = 0
    for r in rolls:
        try:
            stock_id = get_or_create_stock(
                r.get('MANUFACTURER'), r.get('FILM STOCK'),
                r.get('ISO'), r.get('FILM TYPE'))
            camera_id = get_or_create_camera(
                r.get('MAKER'), r.get('MODEL NAME'),
                r.get('C. FORMAT'), r.get('C. TYPE'))
            dev_id  = get_or_create_lab(r.get('DEV'))
            scan_id = get_or_create_lab(r.get('SCAN'))

            # Normalizar locations y photo_types a arrays
            def to_arr(v):
                if not v: return []
                sep = '|' if '|' in v else ','
                return [x.strip() for x in str(v).split(sep) if x.strip()]

            fresh = None
            ef = r.get('EXP/FRESH')
            if ef == 'FRESH':   fresh = True
            if ef == 'EXPIRED': fresh = False

            def to_int(v):
                try: return int(v) if v not in (None,'','-') else None
                except: return None

            def to_date(v):
                if not v: return None
                s = str(v)[:10]
                return s if len(s) == 10 else None

            roll_row = {
                "code":          r.get('#'),
                "film_stock_id": stock_id,
                "iso_pushed":    to_int(r.get('ISO @')),
                "format":        to_int(r.get('FORMAT')),
                "exp_count":     to_int(r.get('EXP')),
                "exp_taken":     to_int(r.get('# EXP')),
                "fresh":         fresh,
                "push_pull":     r.get('PUSH/PULL') or None,
                "camera_id":     camera_id,
                "lens":          r.get('LENS') or None,
                "locations":     to_arr(r.get('LOCATIONS')),
                "photo_types":   to_arr(r.get('PHOTO TYPE')),
                "started":       to_date(r.get('STARTED')),
                "finished":      to_date(r.get('FINISHED')),
                "status":        r.get('STATUS') or None,
                "dev_lab_id":    dev_id,
                "scan_lab_id":   scan_id,
                "rating":        to_int(r.get('RATING')) or 0,
                "notes":         r.get('NOTES') or None,
            }
            insert("rolls", roll_row)
            inserted += 1
        except Exception as e:
            errors += 1
            print(f"  ✗ Error en rollo {r.get('#')}: {e}")

    print(f"\n✅ Migración completada: {inserted} insertados, {errors} errores")
    print(f"   Stocks totales:  {len(_cache['stocks'])}")
    print(f"   Cámaras únicas:  {len(_cache['cameras'])}")
    print(f"   Labs únicos:     {len(_cache['labs'])}")

if __name__ == "__main__":
    main()
