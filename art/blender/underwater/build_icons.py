"""Icônes d'objets de la station sous-marine (SVG peints, 64x64 -> 128 px).

Usage (depuis la racine du projet) :
    python3 art/blender/underwater/build_icons.py

Sorties : assets/sprites/underwater/icons/<id>.svg (référencées par data/items/uw_*.tres
et key_uw_*.tres). Même style que data/items/icons/ : dégradés, contour sombre net.
"""
from __future__ import annotations

import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "underwater", "icons")
INK = "#0e1620"

HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="128" height="128">\n'


def svg(defs: str, body: str) -> str:
    return HEAD + "<defs>" + defs + "</defs>\n" + body + "\n</svg>\n"


def radial(id_: str, stops: list[tuple[float, str]], cx=0.35, cy=0.3, r=0.75) -> str:
    s = "".join('<stop offset="%g" stop-color="%s"/>' % (o, c) for o, c in stops)
    return '<radialGradient id="%s" cx="%g" cy="%g" r="%g">%s</radialGradient>' % (id_, cx, cy, r, s)


def linear(id_: str, stops: list[tuple[float, str]], x2=0, y2=1) -> str:
    s = "".join('<stop offset="%g" stop-color="%s"/>' % (o, c) for o, c in stops)
    return '<linearGradient id="%s" x1="0" y1="0" x2="%g" y2="%g">%s</linearGradient>' % (id_, x2, y2, s)


ICONS: dict[str, str] = {}

# Perle nacrée dans une coquille ouverte.
ICONS["uw_pearl"] = svg(
    radial("p", [(0, "#ffffff"), (0.55, "#eae6f4"), (1, "#9a94b8")]) +
    linear("s", [(0, "#f6c6b0"), (1, "#a8605a")]),
    '<g stroke="%s" stroke-width="1.8" stroke-linejoin="round">'
    '<path d="M6,40 Q32,62 58,40 Q32,48 6,40 Z" fill="url(#s)"/>'
    '<path d="M10,40 Q12,14 32,10 Q52,14 54,40 Q32,30 10,40 Z" fill="url(#s)"/>'
    '<path d="M18,36 Q20,20 32,16 M46,36 Q44,20 32,16 M32,16 L32,32" fill="none" stroke="#7a3a40" stroke-width="1.2"/>'
    '<circle cx="32" cy="42" r="9" fill="url(#p)"/>'
    '<circle cx="29" cy="39" r="2.4" fill="#ffffff" stroke="none"/></g>' % INK)

# Perle noire aux reflets irisés.
ICONS["uw_black_pearl"] = svg(
    radial("p", [(0, "#a0e8ff"), (0.25, "#5a4a8a"), (0.7, "#1a1830"), (1, "#05050c")]) +
    radial("h", [(0, "#c890ff"), (1, "#c890ff00")], 0.5, 0.5, 0.5),
    '<circle cx="32" cy="34" r="26" fill="url(#h)" opacity="0.6"/>'
    '<g stroke="%s" stroke-width="2"><circle cx="32" cy="34" r="17" fill="url(#p)"/></g>'
    '<path d="M22,28 Q26,20 34,19" fill="none" stroke="#e0f4ff" stroke-width="2.6" stroke-linecap="round"/>'
    '<circle cx="40" cy="42" r="2" fill="#60c0ff"/>' % INK)

# Fiole d'échantillon biologique (liquide vert, étiquette).
ICONS["uw_bio_sample"] = svg(
    linear("g", [(0, "#b8ffcc"), (1, "#2a9a5a")]) + linear("v", [(0, "#e8f8ff"), (1, "#9ab8c8")], 1, 0),
    '<g stroke="%s" stroke-width="1.8" stroke-linejoin="round">'
    '<rect x="22" y="6" width="20" height="8" rx="2" fill="#5a6a7a"/>'
    '<path d="M24,14 L24,52 Q24,60 32,60 Q40,60 40,52 L40,14 Z" fill="url(#v)"/>'
    '<path d="M24.8,30 L39.2,30 L39.2,52 Q39.2,59 32,59 Q24.8,59 24.8,52 Z" fill="url(#g)"/>'
    '<rect x="26" y="36" width="12" height="9" fill="#f4ecd8" stroke-width="1.2"/>'
    '<path d="M28,40 L36,40 M28,43 L34,43" stroke="#4a5060" stroke-width="1"/></g>'
    '<circle cx="30" cy="50" r="1.6" fill="#e8fff0"/><circle cx="35" cy="54" r="1.1" fill="#e8fff0"/>' % INK)

# Seringue de sérum mutagène (violet luisant).
ICONS["uw_mutagen"] = svg(
    linear("m", [(0, "#f0a0ff"), (1, "#6a1aa0")], 1, 0) + radial("h", [(0, "#d070ff"), (1, "#d070ff00")], 0.5, 0.5, 0.5),
    '<circle cx="32" cy="32" r="28" fill="url(#h)" opacity="0.5"/>'
    '<g stroke="%s" stroke-width="1.8" stroke-linejoin="round" transform="rotate(-40 32 32)">'
    '<rect x="14" y="26" width="30" height="12" rx="3" fill="#dfeef4"/>'
    '<rect x="16" y="28" width="20" height="8" fill="url(#m)" stroke-width="1"/>'
    '<rect x="44" y="29" width="8" height="6" fill="#7a8a9a"/>'
    '<path d="M52,32 L62,32" stroke-width="2.2"/>'
    '<rect x="6" y="24" width="8" height="16" rx="2" fill="#7a8a9a"/>'
    '<path d="M20,28 L20,36 M26,28 L26,36 M32,28 L32,36" stroke="#3a1050" stroke-width="1"/></g>' % INK)

# Bouteille d'oxygène (jaune, robinet).
ICONS["uw_oxygen_tank"] = svg(
    linear("y", [(0, "#ffe27a"), (0.5, "#f0b830"), (1, "#a86a18")], 1, 0),
    '<g stroke="%s" stroke-width="1.8" stroke-linejoin="round">'
    '<rect x="26" y="4" width="12" height="7" rx="2" fill="#8a96a6"/>'
    '<path d="M38,7 L46,7 L46,11" fill="none" stroke-width="2.4"/>'
    '<path d="M20,20 Q20,11 32,11 Q44,11 44,20 L44,56 Q44,60 40,60 L24,60 Q20,60 20,56 Z" fill="url(#y)"/>'
    '<rect x="20" y="26" width="24" height="6" fill="#2a3440" stroke-width="1.2"/>'
    '<text x="32" y="47" font-family="sans-serif" font-weight="bold" font-size="11" text-anchor="middle" fill="#2a3440" stroke="none">O2</text>'
    '</g><path d="M24,18 L24,54" stroke="#fff6c8" stroke-width="2" opacity="0.8"/>' % INK)

# Trousse de plongée (étanche, croix rouge).
ICONS["uw_medkit"] = svg(
    linear("o", [(0, "#ff9a50"), (1, "#c0501a")]),
    '<g stroke="%s" stroke-width="1.8" stroke-linejoin="round">'
    '<path d="M22,16 L22,10 L42,10 L42,16" fill="none" stroke-width="3"/>'
    '<rect x="6" y="16" width="52" height="40" rx="6" fill="url(#o)"/>'
    '<rect x="6" y="30" width="52" height="5" fill="#3a3440" stroke-width="1"/>'
    '<rect x="24" y="20" width="16" height="30" rx="2" fill="#f4f0e8" stroke-width="1.4"/>'
    '<rect x="17" y="27" width="30" height="16" rx="2" fill="#f4f0e8" stroke-width="1.4"/>'
    '<rect x="28" y="23" width="8" height="24" fill="#d0242a" stroke="none"/>'
    '<rect x="20" y="31" width="24" height="8" fill="#d0242a" stroke="none"/></g>' % INK)

# Composants électroniques (carte verte + puces).
ICONS["uw_components"] = svg(
    linear("b", [(0, "#4ac08a"), (1, "#1a6a4a")]),
    '<g stroke="%s" stroke-width="1.6" stroke-linejoin="round">'
    '<path d="M8,14 L50,10 L56,50 L14,54 Z" fill="url(#b)"/>'
    '<rect x="20" y="20" width="14" height="12" fill="#2a2e3a" transform="rotate(-5 27 26)"/>'
    '<rect x="36" y="34" width="10" height="10" fill="#2a2e3a" transform="rotate(-5 41 39)"/>'
    '<circle cx="18" cy="42" r="4" fill="#d0a040"/>'
    '<path d="M34,24 L46,22 M22,36 L34,44 M12,22 L20,24" fill="none" stroke="#e8d070" stroke-width="1.4"/></g>'
    '<circle cx="46" cy="20" r="2.2" fill="#ff4a3a"/>' % INK)

# Vanne en laiton (volant à rayons).
ICONS["uw_brass_valve"] = svg(
    radial("b", [(0, "#fff0a0"), (0.5, "#d8a040"), (1, "#7a5020")]),
    '<g stroke="%s" stroke-width="1.8" fill="none">'
    '<circle cx="32" cy="32" r="22" stroke-width="7"/>'
    '<circle cx="32" cy="32" r="22" stroke="url(#b)" stroke-width="4.5"/>'
    '<path d="M32,10 L32,54 M10,32 L54,32 M16,16 L48,48 M48,16 L16,48" stroke-width="4.5"/>'
    '<path d="M32,10 L32,54 M10,32 L54,32 M16,16 L48,48 M48,16 L16,48" stroke="#d8a040" stroke-width="2.4"/>'
    '<circle cx="32" cy="32" r="7" fill="url(#b)"/></g>' % INK)

# Corail rare (branches rouge-orangé).
ICONS["uw_rare_coral"] = svg(
    linear("c", [(0, "#ffb08a"), (1, "#d0303a")]),
    '<g stroke="%s" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round">'
    '<path d="M30,60 L30,40 Q20,34 16,18 M30,40 Q34,26 30,10 M31,44 Q44,36 48,20 M44,30 Q52,30 56,22 M22,30 Q12,28 8,20" '
    'fill="none" stroke-width="9"/>'
    '<path d="M30,60 L30,40 Q20,34 16,18 M30,40 Q34,26 30,10 M31,44 Q44,36 48,20 M44,30 Q52,30 56,22 M22,30 Q12,28 8,20" '
    'fill="none" stroke="url(#c)" stroke-width="5.6"/>'
    '<rect x="20" y="56" width="22" height="6" rx="2" fill="#6a7480"/></g>'
    '<circle cx="16" cy="18" r="2" fill="#ffe0c8"/><circle cx="30" cy="10" r="2" fill="#ffe0c8"/><circle cx="48" cy="20" r="2" fill="#ffe0c8"/>' % INK)

# Cœur de corail (légendaire : cœur pétrifié lumineux).
ICONS["uw_coral_heart"] = svg(
    radial("h", [(0, "#ffe8a0"), (0.4, "#ff7a3a"), (1, "#8a1a2a")]) + radial("g", [(0, "#ffb050"), (1, "#ffb05000")], 0.5, 0.5, 0.5),
    '<circle cx="32" cy="34" r="30" fill="url(#g)" opacity="0.7"/>'
    '<g stroke="%s" stroke-width="2" stroke-linejoin="round">'
    '<path d="M32,56 Q8,40 10,22 Q12,10 24,12 Q30,13 32,20 Q34,13 40,12 Q52,10 54,22 Q56,40 32,56 Z" fill="url(#h)"/>'
    '<path d="M22,22 Q26,30 22,38 M32,24 L32,44 M42,22 Q38,30 42,38" fill="none" stroke="#ffd8a8" stroke-width="1.6"/>'
    '<path d="M12,20 L6,12 M52,20 L58,12 M32,20 L32,8" fill="none" stroke="#e05a4a" stroke-width="3"/></g>' % INK)

# Carreaux de harpon (faisceau).
ICONS["uw_harpoon_bolts"] = svg(
    linear("s", [(0, "#e8f0f8"), (1, "#7a8a9a")], 1, 0),
    '<g stroke="%s" stroke-width="1.6" stroke-linejoin="round">' % INK +
    "".join('<g transform="translate(%d,%d) rotate(-35 32 32)">'
            '<rect x="6" y="30" width="44" height="4" fill="url(#s)"/>'
            '<path d="M50,26 L60,32 L50,38 L52,32 Z" fill="#c8d4e0"/>'
            '<path d="M6,28 L14,32 L6,36 Z" fill="#d04a2a"/></g>' % (dx, dy)
            for dx, dy in ((-6, -6), (0, 0), (6, 6))) +
    '<rect x="22" y="30" width="20" height="6" rx="2" fill="#6a4a30" transform="rotate(-35 32 33)"/></g>')

# Journal de recherche (carnet étanche, sceau).
ICONS["uw_research_log"] = svg(
    linear("b", [(0, "#3a7ab0"), (1, "#1a3a60")], 1, 1),
    '<g stroke="%s" stroke-width="1.8" stroke-linejoin="round">'
    '<path d="M12,8 L50,8 L50,58 L12,58 Z" fill="url(#b)"/>'
    '<path d="M16,8 L16,58" stroke-width="1.2"/>'
    '<rect x="22" y="16" width="22" height="12" fill="#e8e0c8" stroke-width="1.2"/>'
    '<path d="M25,20 L41,20 M25,24 L37,24" stroke="#3a4050" stroke-width="1"/>'
    '<circle cx="34" cy="44" r="7" fill="#e0b040"/>'
    '<path d="M30,44 Q34,38 38,44 Q34,50 30,44 Z" fill="#2a5a8a" stroke-width="1"/>'
    '<rect x="50" y="20" width="5" height="10" fill="#c03030" stroke-width="1.2"/></g>' % INK)

# Ambre gris (bloc cireux doré).
ICONS["uw_ambergris"] = svg(
    radial("a", [(0, "#fff0c0"), (0.5, "#c8a060"), (1, "#6a4a2a")]),
    '<g stroke="%s" stroke-width="2" stroke-linejoin="round">'
    '<path d="M10,40 Q8,24 22,18 Q32,10 44,16 Q58,22 56,38 Q54,52 38,54 Q20,56 10,40 Z" fill="url(#a)"/>'
    '<path d="M20,30 Q24,26 30,28 M36,40 Q42,36 46,40 M24,44 Q28,42 30,46" fill="none" stroke="#8a6a3a" stroke-width="1.4"/></g>'
    '<path d="M18,26 Q22,20 30,20" fill="none" stroke="#fff8e0" stroke-width="2.2" stroke-linecap="round"/>' % INK)


def key_icon(head: str, glow: str, bit: str) -> str:
    return svg(
        radial("h", [(0, "#ffffff"), (0.5, head), (1, "#2a3a4a")]) + radial("g", [(0, glow), (1, glow + "00")], 0.5, 0.5, 0.5),
        '<circle cx="22" cy="22" r="20" fill="url(#g)" opacity="0.6"/>'
        '<g stroke="%s" stroke-width="2" stroke-linejoin="round">'
        '<circle cx="22" cy="22" r="13" fill="url(#h)"/>'
        '<circle cx="22" cy="22" r="5" fill="#1a2430"/>'
        '<path d="M31,31 L56,56" stroke-width="8" stroke-linecap="round"/>'
        '<path d="M31,31 L56,56" stroke="#c8d4e0" stroke-width="4.5" stroke-linecap="round"/>'
        '<path d="M46,46 L40,52 M52,52 L46,58" stroke-width="5" stroke-linecap="round"/>'
        '<path d="M46,46 L40,52 M52,52 L46,58" stroke="#c8d4e0" stroke-width="2.6" stroke-linecap="round"/>'
        '%s</g>' % (INK, bit))


# Clef du laboratoire : tête cyan, symbole d'éprouvette.
ICONS["key_uw_lab"] = key_icon("#4ad8e8", "#60f0ff",
                               '<path d="M20,14 L20,24 Q20,28 22,28 Q24,28 24,24 L24,14" fill="#7affb0" stroke-width="1.2"/>')
# Clef de la fosse : tête corail, symbole de vague.
ICONS["key_uw_trench"] = key_icon("#ff7a5a", "#ff9a60",
                                  '<path d="M14,22 Q18,17 22,22 Q26,27 30,22" fill="none" stroke="#fff0d0" stroke-width="2"/>')


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, data in ICONS.items():
        with open(os.path.join(OUT, name + ".svg"), "w") as f:
            f.write(data)
        print("ICON", name)


if __name__ == "__main__":
    main()
