"""Icônes d'objets des Pyramides d'Égypte (SVG 64x64 peints à plat, contour sombre, reflet chaud).

Usage : python3 art/blender/egypt_pyramids/build_eg_icons.py  ->  assets/sprites/egypt_pyramids/icons/<id>.svg
Même style que art/blender/mall/build_mall_icons.py (dégradés or / lapis / grès, contour #1e1218).
"""
from __future__ import annotations

import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "egypt_pyramids", "icons")

HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="128" height="128">\n<defs>'
        '<linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffe9a0"/><stop offset="0.5" stop-color="#d9a234"/><stop offset="1" stop-color="#7a4c12"/></linearGradient>'
        '<linearGradient id="lapis" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6a8cff"/><stop offset="1" stop-color="#1a2a7a"/></linearGradient>'
        '<linearGradient id="stone" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f0d8a8"/><stop offset="1" stop-color="#8a6236"/></linearGradient>'
        '<linearGradient id="clay" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e0905a"/><stop offset="1" stop-color="#7a3a1a"/></linearGradient>'
        '<linearGradient id="linen" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff4dc"/><stop offset="1" stop-color="#a08a66"/></linearGradient>'
        '<radialGradient id="gem" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#ffffff"/><stop offset="0.4" stop-color="#8af0c0"/><stop offset="1" stop-color="#1a7a50"/></radialGradient>'
        '<radialGradient id="ruby" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#ffffff"/><stop offset="0.4" stop-color="#ff7a8a"/><stop offset="1" stop-color="#8a0a2a"/></radialGradient>'
        '</defs>\n<g stroke="#1e1218" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round">\n')
TAIL = '</g></svg>\n'

ICONS = {
    "eg_gold_scarab": '<ellipse cx="32" cy="36" rx="16" ry="13" fill="url(#gold)"/><path d="M32,23 L32,49 M18,36 L46,36" fill="none"/>'
                      '<ellipse cx="32" cy="20" rx="8" ry="6" fill="url(#lapis)"/><path d="M14,30 L8,22 M50,30 L56,22 M14,42 L8,50 M50,42 L56,50" fill="none"/>',
    "eg_ankh": '<ellipse cx="32" cy="18" rx="9" ry="11" fill="none" stroke="#1e1218" stroke-width="9"/><ellipse cx="32" cy="18" rx="9" ry="11" fill="none" stroke="url(#gold)" stroke-width="5"/>'
               '<rect x="28" y="28" width="8" height="30" rx="2" fill="url(#gold)"/><rect x="14" y="30" width="36" height="8" rx="2" fill="url(#gold)"/>',
    "eg_pharaoh_scepter": '<path d="M30,58 L30,18 Q30,6 42,6 Q52,6 52,16 Q52,24 44,24" fill="none" stroke="#1e1218" stroke-width="9"/>'
                          '<path d="M30,58 L30,18 Q30,6 42,6 Q52,6 52,16 Q52,24 44,24" fill="none" stroke="url(#gold)" stroke-width="5"/>'
                          '<rect x="27" y="28" width="6" height="5" fill="url(#lapis)"/><rect x="27" y="40" width="6" height="5" fill="url(#lapis)"/>'
                          '<circle cx="30" cy="58" r="3.5" fill="url(#ruby)"/>',
    "eg_lapis_necklace": '<path d="M8,12 Q32,56 56,12" fill="none" stroke="url(#gold)" stroke-width="4"/>'
                         '<circle cx="18" cy="28" r="4" fill="url(#lapis)"/><circle cx="46" cy="28" r="4" fill="url(#lapis)"/><circle cx="32" cy="40" r="6" fill="url(#lapis)"/><circle cx="25" cy="36" r="3.5" fill="url(#gold)"/><circle cx="39" cy="36" r="3.5" fill="url(#gold)"/>',
    "eg_emerald_eye": '<path d="M8,32 Q32,8 56,32 Q32,56 8,32 Z" fill="url(#gold)"/><circle cx="32" cy="32" r="10" fill="url(#gem)"/><circle cx="32" cy="32" r="4" fill="#1e1218"/>'
                      '<path d="M40,44 L48,56 M24,44 L22,56" fill="none"/>',
    "eg_canopic_jar": '<path d="M20,22 L18,52 Q32,58 46,52 L44,22 Z" fill="url(#stone)"/><ellipse cx="32" cy="18" rx="12" ry="8" fill="url(#clay)"/>'
                      '<path d="M26,16 L30,14 M34,14 L38,16" fill="none"/><path d="M24,34 L40,34 M24,42 L36,42" stroke="#7a4c12" fill="none"/>',
    "eg_papyrus": '<rect x="14" y="12" width="36" height="40" rx="3" fill="url(#linen)"/><rect x="10" y="8" width="44" height="7" rx="3" fill="url(#clay)"/><rect x="10" y="49" width="44" height="7" rx="3" fill="url(#clay)"/>'
                  '<path d="M20,22 L44,22 M20,29 L38,29 M20,36 L44,36 M20,43 L34,43" stroke="#4a3a2a" fill="none"/>',
    "eg_incense": '<path d="M22,30 L18,54 L46,54 L42,30 Z" fill="url(#clay)"/><rect x="18" y="26" width="28" height="6" rx="2" fill="url(#gold)"/>'
                  '<path d="M28,24 Q24,16 30,10 Q26,4 32,2" fill="none" stroke="#c8c0c0"/><path d="M38,24 Q42,16 36,10" fill="none" stroke="#c8c0c0"/>',
    "eg_honey_pot": '<path d="M18,24 Q14,48 22,54 L42,54 Q50,48 46,24 Z" fill="url(#clay)"/><rect x="16" y="18" width="32" height="8" rx="3" fill="url(#linen)"/>'
                    '<path d="M24,34 Q32,40 40,34 L40,46 Q32,50 24,46 Z" fill="url(#gold)"/>',
    "eg_dates": '<ellipse cx="22" cy="40" rx="8" ry="11" fill="#7a3a1a"/><ellipse cx="38" cy="36" rx="8" ry="11" fill="#9a4a22"/><ellipse cx="30" cy="48" rx="8" ry="10" fill="#6a2e14"/>'
                '<path d="M30,10 L22,30 M30,10 L38,26 M30,10 L30,40" fill="none" stroke="#3a7a2a" stroke-width="3"/>',
    "eg_healing_balm": '<rect x="16" y="22" width="32" height="32" rx="6" fill="url(#stone)"/><rect x="22" y="12" width="20" height="12" rx="3" fill="url(#gold)"/>'
                       '<path d="M32,30 L32,48 M23,39 L41,39" stroke="#2a8a5a" stroke-width="6" fill="none"/>',
    "eg_water_skin": '<path d="M20,18 Q10,36 22,54 L42,54 Q54,36 44,18 Z" fill="#a86a3a"/><rect x="26" y="8" width="12" height="12" rx="3" fill="#5a3a1a"/>'
                     '<path d="M24,30 Q32,26 40,30" fill="none" stroke="#6a3a1a"/>',
    "eg_silver_coins": '<ellipse cx="28" cy="42" rx="16" ry="8" fill="#c8ccd8"/><ellipse cx="28" cy="36" rx="16" ry="8" fill="#e8ecf4"/><ellipse cx="38" cy="26" rx="14" ry="7" fill="#dfe3ec"/>'
                       '<path d="M32,24 L44,24 M38,21 L38,29" stroke="#7a7a8a" fill="none"/>',
    "eg_bronze_dagger": '<path d="M32,6 L26,20 L30,44 L34,44 L38,20 Z" fill="#c8a060"/><rect x="22" y="42" width="20" height="6" rx="2" fill="url(#gold)"/><rect x="28" y="48" width="8" height="12" rx="2" fill="url(#lapis)"/>',
    "key_eg_treasury": '<circle cx="22" cy="24" r="12" fill="none" stroke="#1e1218" stroke-width="9"/><circle cx="22" cy="24" r="12" fill="none" stroke="url(#gold)" stroke-width="5"/>'
                       '<path d="M30,32 L54,56 M48,50 L54,44 M42,44 L48,38" fill="none" stroke="url(#gold)" stroke-width="6"/><circle cx="22" cy="24" r="4" fill="url(#ruby)"/>',
}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, body in ICONS.items():
        with open(os.path.join(OUT, name + ".svg"), "w") as f:
            f.write(HEAD + body + "\n" + TAIL)
    print("ICONS", len(ICONS), OUT)


if __name__ == "__main__":
    main()
