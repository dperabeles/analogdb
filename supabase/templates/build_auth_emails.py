#!/usr/bin/env python3
"""Build the Supabase access emails in Contacto v38.

One source for the confirmation and password-reset emails, in Spanish and
English. `python3 supabase/templates/build_auth_emails.py` writes
confirmation.html and recovery.html next to this file, each with Go template
conditionals on `.Data.locale` (Spanish when it is missing). Supabase reads
the subjects from config.toml.

`--preview DIR` also writes the four fixed-language versions with sample
values, to look at them in a browser before applying anything.

The look follows the app's access screen (contacto_access_view.dart): dot
field, compact brand, eyebrow, large title, muted copy, a numbered
registration plate and the orange primary action with its arrow. Email
clients are not Flutter, so:

- tables and inline styles; dark mode and the narrow layout live in <style>,
  which Apple Mail and iOS Mail honour and others ignore without breaking;
- Instrument Sans loads from Google Fonts where the client allows it, with
  the system sans as fallback;
- the brand mark is drawn with table cells, not an image, so it shows even
  with images blocked;
- the dot field is a CSS background: clients that drop it show the plain
  page colour.
"""

from __future__ import annotations

import argparse
import html
import pathlib

HERE = pathlib.Path(__file__).resolve().parent

# Contacto v38 palette (contacto-guia-diseno/datos/tokens.json).
LIGHT = {
    "bg": "#E8E6DE",
    "text": "#14110d",
    "muted": "#625e55",
    "line": "#aaa69a",
    "line_soft": "#c8c4b8",
    "dot": "#b5afa3",
    "accent": "#d94a2a",
    "accent_ink": "#080604",
    "accent_text": "#a82602",
}
DARK = {
    "bg": "#14110d",
    "text": "#f3eadb",
    "muted": "#afa89d",
    "line": "#49443b",
    "line_soft": "#332d25",
    "dot": "#625b50",
    "accent_text": "#eb5b3b",
}

FONT = "'Instrument Sans',-apple-system,'Helvetica Neue',Helvetica,Arial,sans-serif"

EN = '{{ if and .Data.locale (eq .Data.locale "en") }}'

COPY = {
    "confirmation": {
        "html_title": ("Confirma tu cuenta de Analog Archive", "Confirm your Analog Archive account"),
        "preheader": (
            "Confirma tu correo para entrar a Analog Archive.",
            "Confirm your email to sign in to Analog Archive.",
        ),
        "eyebrow": ("Acceso / Registro", "Access / Sign up"),
        "title": ("Confirma<br>tu correo.", "Confirm<br>your email."),
        "copy": (
            "Creaste una cuenta en Analog Archive. Confirma tu correo para entrar a la app.",
            "You created an Analog Archive account. Confirm your email to sign in to the app.",
        ),
        "plate": (
            "El enlace sirve una vez y vence en una hora.",
            "The link works once and expires in an hour.",
        ),
        "action": ("Confirmar correo", "Confirm email"),
        "footer": (
            "Si no creaste esta cuenta, ignora este correo.",
            "If you didn&rsquo;t create this account, ignore this email.",
        ),
        "link": "https://analog-archive.com/confirm?token_hash={{ .TokenHash }}&type=email",
    },
    "recovery": {
        "html_title": ("Restablece tu acceso a Analog Archive", "Reset your Analog Archive password"),
        "preheader": (
            "Elige una contraseña nueva para Analog Archive.",
            "Choose a new password for Analog Archive.",
        ),
        "eyebrow": ("Acceso / Recuperación", "Access / Recovery"),
        "title": ("Nueva<br>contraseña.", "A new<br>password."),
        "copy": (
            "Pediste cambiar la contraseña de tu cuenta. Abre el enlace para elegir una nueva.",
            "You asked to change your account password. Open the link to choose a new one.",
        ),
        "plate": (
            "El enlace vence en una hora. Tu contraseña actual sigue activa hasta que pongas otra.",
            "The link expires in an hour. Your current password works until you set a new one.",
        ),
        "action": ("Elegir contraseña nueva", "Choose a new password"),
        "footer": (
            "Si no lo pediste tú, ignora este correo.",
            "If you didn&rsquo;t ask for this, ignore this email.",
        ),
        "link": "https://analog-archive.com/reset-password?token_hash={{ .TokenHash }}&type=recovery",
    },
}

SHARED = {
    "fallback": ("¿No abre el botón? Copia este enlace:", "Button not opening? Copy this link:"),
    "lang": ("es", "en"),
}


def pick(pair: tuple[str, str], lang: str | None) -> str:
    """One language, or both behind the locale conditional."""
    es, en = pair
    if lang == "es":
        return es
    if lang == "en":
        return en
    return f"{EN}{en}{{{{ else }}}}{es}{{{{ end }}}}"


def mark() -> str:
    """The film-strip mark: an orange frame with two rows of perforations."""
    hole = (
        '<td class="bgc" width="4" height="4" '
        f'style="width:4px;height:4px;background:{LIGHT["bg"]};font-size:0;line-height:0;">&nbsp;</td>'
    )
    gap = '<td width="4" height="4" style="font-size:0;line-height:0;">&nbsp;</td>'
    side = '<td width="3" style="width:3px;font-size:0;line-height:0;">&nbsp;</td>'
    middle = '<td width="16" style="width:16px;font-size:0;line-height:0;">&nbsp;</td>'
    pad = '<tr><td colspan="5" height="3" style="height:3px;font-size:0;line-height:0;">&nbsp;</td></tr>'
    rows = [pad]
    for i in range(4):
        rows.append(f"<tr>{side}{hole}{middle}{hole}{side}</tr>")
        if i < 3:
            rows.append(f"<tr>{side}{gap}{middle}{gap}{side}</tr>")
    rows.append(pad)
    return (
        '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="30" '
        f'style="width:30px;border-collapse:separate;background:{LIGHT["accent"]};border-radius:4px;">'
        + "".join(rows)
        + "</table>"
    )


def build(kind: str, lang: str | None, link: str, email: str) -> str:
    c = COPY[kind]
    L, D = LIGHT, DARK
    t = lambda key: pick(c[key], lang)  # noqa: E731
    s = lambda key: pick(SHARED[key], lang)  # noqa: E731
    dots_light = (
        f"radial-gradient(circle,{L['dot']} 1px,transparent 1.3px)"
    )
    dots_dark = f"radial-gradient(circle,{D['dot']} 1px,transparent 1.3px)"
    return f"""<!doctype html>
<html lang="{s('lang')}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>{t('html_title')}</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600&display=swap" rel="stylesheet">
<style>
  :root {{ color-scheme: light dark; supported-color-schemes: light dark; }}
  body {{ margin:0; padding:0; }}
  a {{ text-decoration:none; }}
  @media (prefers-color-scheme: dark) {{
    .page {{ background-color:{D['bg']} !important; background-image:{dots_dark} !important; }}
    .bgc {{ background:{D['bg']} !important; }}
    .tx {{ color:{D['text']} !important; }}
    .mu {{ color:{D['muted']} !important; }}
    .at {{ color:{D['accent_text']} !important; }}
    .ln {{ border-color:{D['line']} !important; }}
    .ls {{ border-color:{D['line_soft']} !important; }}
  }}
  @media (max-width: 480px) {{
    .pad {{ padding:28px 18px 24px 18px !important; }}
    .title {{ font-size:35px !important; }}
    .copy {{ font-size:13px !important; }}
  }}
</style>
</head>
<body class="page" style="margin:0;padding:0;background-color:{L['bg']};background-image:{dots_light};background-size:17px 17px;">
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:{L['bg']};">{t('preheader')}</div>
<table role="presentation" class="page" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:{L['bg']};background-image:{dots_light};background-size:17px 17px;">
<tr><td align="center">
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:480px;">
<tr><td class="pad" style="padding:36px 34px 28px 34px;font-family:{FONT};">

  <!-- brand: mark and wordmark on the page colour, so the dots stop around them -->
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 30px 0;">
    <tr>
      <td class="bgc" valign="middle" style="background:{L['bg']};padding:5px;">{mark()}</td>
      <td class="bgc" valign="middle" style="background:{L['bg']};padding:5px 7px;">
        <div class="tx" style="font-family:{FONT};font-size:29px;line-height:26px;font-weight:600;letter-spacing:-0.07em;color:{L['text']};">analog<br>archive</div>
      </td>
    </tr>
  </table>

  <!-- eyebrow -->
  <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
    <td class="bgc mu" style="background:{L['bg']};font-family:{FONT};font-size:10.5px;line-height:14px;font-weight:500;letter-spacing:0.06em;text-transform:uppercase;color:{L['muted']};">{t('eyebrow')}</td>
  </tr></table>

  <!-- title -->
  <h1 class="title tx" style="margin:13px 0 0 0;font-family:{FONT};font-size:39px;line-height:1.04;font-weight:500;letter-spacing:-0.055em;color:{L['text']};">{t('title')}</h1>

  <!-- copy -->
  <p class="copy mu" style="margin:18px 0 0 0;font-family:{FONT};font-size:14px;line-height:1.5;font-weight:500;color:{L['muted']};">{t('copy')}</p>

  <!-- registration plate: «01», the address it went to, and the one thing to know -->
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:22px 0 0 0;">
    <tr><td class="mu" style="font-family:{FONT};font-size:12px;line-height:9px;height:9px;color:{L['muted']};padding:0 0 0 0;">+</td></tr>
    <tr><td>
      <table role="presentation" class="ln" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-top:1px solid {L['line']};border-bottom:1px solid {L['line']};">
        <tr>
          <td class="bgc tx" width="48" valign="middle" style="width:48px;background:{L['bg']};padding:18px 0 18px 16px;font-family:{FONT};font-size:40px;line-height:40px;font-weight:400;letter-spacing:-0.06em;color:{L['text']};">01</td>
          <td class="bgc" valign="middle" style="background:{L['bg']};padding:18px 16px 18px 16px;">
            <div class="tx" style="font-family:{FONT};font-size:12px;line-height:1.5;font-weight:500;color:{L['text']};word-break:break-all;">{email}</div>
            <div class="mu" style="margin-top:3px;font-family:{FONT};font-size:12px;line-height:1.5;font-weight:500;color:{L['muted']};">{t('plate')}</div>
          </td>
        </tr>
      </table>
    </td></tr>
    <tr><td align="right" class="mu" style="font-family:{FONT};font-size:12px;line-height:9px;height:9px;color:{L['muted']};">+</td></tr>
  </table>

  <!-- primary action -->
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:25px 0 0 0;">
    <tr><td style="background:{L['accent']};">
      <a href="{link}" style="display:block;padding:12px 16px;font-family:{FONT};font-size:16px;line-height:24px;font-weight:600;letter-spacing:-0.02em;color:{L['accent_ink']};text-decoration:none;"><span style="float:right;font-size:24px;line-height:24px;font-weight:400;">&rarr;</span>{t('action')}</a>
    </td></tr>
  </table>

  <!-- the same link, written out -->
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:22px 0 0 0;">
    <tr><td class="bgc mu" style="background:{L['bg']};font-family:{FONT};font-size:12px;line-height:1.5;font-weight:500;color:{L['muted']};">{s('fallback')}</td></tr>
    <tr><td class="bgc" style="background:{L['bg']};padding-top:4px;font-family:{FONT};font-size:12px;line-height:1.5;font-weight:500;word-break:break-all;"><a class="at" href="{link}" style="color:{L['accent_text']};text-decoration:none;">{link}</a></td></tr>
  </table>

  <!-- footer -->
  <table role="presentation" class="ls" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:28px 0 0 0;border-top:1px solid {L['line_soft']};">
    <tr><td class="bgc mu" style="background:{L['bg']};padding:16px 0 0 0;font-family:{FONT};font-size:12px;line-height:1.5;font-weight:500;color:{L['muted']};">{t('footer')}</td></tr>
    <tr><td class="bgc mu" style="background:{L['bg']};padding:14px 0 0 0;font-family:{FONT};font-size:10.5px;line-height:14px;font-weight:500;letter-spacing:0.06em;text-transform:uppercase;color:{L['muted']};"><a class="mu" href="https://analog-archive.com" style="color:{L['muted']};text-decoration:none;">analog-archive.com &#8599;</a></td></tr>
  </table>

</td></tr>
</table>
</td></tr>
</table>
</body>
</html>
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", type=pathlib.Path)
    args = ap.parse_args()
    for kind, c in COPY.items():
        (HERE / f"{kind}.html").write_text(build(kind, None, c["link"], "{{ .Email }}"))
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
        for kind, c in COPY.items():
            for lang in ("es", "en"):
                link = c["link"].replace("{{ .TokenHash }}", "pkce_0f3c9a7e2b").replace("&", "&amp;")
                out = build(kind, lang, link, html.escape("tu@correo.com" if lang == "es" else "you@email.com"))
                (args.preview / f"{kind}-{lang}.html").write_text(out)


if __name__ == "__main__":
    main()
