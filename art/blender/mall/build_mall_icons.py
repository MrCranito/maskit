"""Icônes d'objets du centre commercial (SVG 64x64 peints à plat, contour sombre, reflet chaud).

Usage : python3 art/blender/mall/build_mall_icons.py  ->  assets/sprites/mall/icons/<id>.svg
Même style que data/items/icons/*.svg (dégradés, contour #1e1218, reflet clair en haut à gauche).
"""
from __future__ import annotations

import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "mall", "icons")

HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="128" height="128">\n<defs>'
        '<linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffe9a0"/><stop offset="0.5" stop-color="#d9a234"/><stop offset="1" stop-color="#7a4c12"/></linearGradient>'
        '<linearGradient id="steel" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f2f4ff"/><stop offset="0.5" stop-color="#9aa0b4"/><stop offset="1" stop-color="#4a4e6a"/></linearGradient>'
        '<linearGradient id="screen" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#9af0ff"/><stop offset="1" stop-color="#3a4ab0"/></linearGradient>'
        '<linearGradient id="pink" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffb0dc"/><stop offset="1" stop-color="#b03a8a"/></linearGradient>'
        '<radialGradient id="gem" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#ffffff"/><stop offset="0.4" stop-color="#bff4ff"/><stop offset="1" stop-color="#3a8ac0"/></radialGradient>'
        '</defs>\n<g stroke="#1e1218" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round">\n')
TAIL = '</g></svg>\n'

ICONS = {
    "mall_gold_ring": '<ellipse cx="32" cy="40" rx="17" ry="14" fill="none" stroke="#1e1218" stroke-width="9"/>'
                      '<ellipse cx="32" cy="40" rx="17" ry="14" fill="none" stroke="url(#gold)" stroke-width="5"/>'
                      '<path d="M22,22 L32,12 L42,22 L32,30 Z" fill="url(#gem)"/><path d="M26,20 L32,15" stroke="#fff" fill="none"/>',
    "mall_diamond_necklace": '<path d="M8,10 Q32,52 56,10" fill="none" stroke="url(#gold)" stroke-width="3"/>'
                             '<path d="M22,38 L32,28 L42,38 L32,56 Z" fill="url(#gem)"/><path d="M26,37 L32,31" stroke="#fff" fill="none"/>'
                             '<circle cx="16" cy="24" r="3" fill="url(#gem)"/><circle cx="48" cy="24" r="3" fill="url(#gem)"/>',
    "mall_luxury_watch": '<rect x="24" y="4" width="16" height="56" rx="5" fill="#3a2a2a"/>'
                         '<circle cx="32" cy="32" r="15" fill="url(#gold)"/><circle cx="32" cy="32" r="11" fill="#1e2a4a"/>'
                         '<path d="M32,32 L32,24 M32,32 L38,35" stroke="#ffe9a0" fill="none"/><path d="M22,26 Q24,20 30,19" stroke="#fff6cc" fill="none"/>',
    "mall_smartphone": '<rect x="17" y="5" width="30" height="54" rx="6" fill="#2a2630"/><rect x="21" y="11" width="22" height="40" rx="2" fill="url(#screen)"/>'
                       '<path d="M24,40 L40,16" stroke="#e8f8ff" stroke-width="1.6" fill="none"/><circle cx="32" cy="55" r="1.8" fill="#6a6e80"/>',
    "mall_headphones": '<path d="M12,40 L12,30 Q12,10 32,10 Q52,10 52,30 L52,40" fill="none" stroke="#1e1218" stroke-width="7"/>'
                       '<path d="M12,40 L12,30 Q12,10 32,10 Q52,10 52,30 L52,40" fill="none" stroke="#7a4ab0" stroke-width="3.5"/>'
                       '<rect x="6" y="34" width="13" height="20" rx="5" fill="url(#pink)"/><rect x="45" y="34" width="13" height="20" rx="5" fill="url(#pink)"/>',
    "mall_game_console": '<rect x="5" y="18" width="54" height="28" rx="12" fill="#c03a4a"/><rect x="21" y="22" width="22" height="18" rx="2" fill="url(#screen)"/>'
                         '<path d="M11,32 L17,32 M14,29 L14,35" stroke="#fff" fill="none"/><circle cx="50" cy="29" r="2.6" fill="#ffd040"/><circle cx="46" cy="35" r="2.6" fill="#5ad0ff"/>',
    "mall_canned_food": '<rect x="16" y="12" width="32" height="42" rx="4" fill="url(#steel)"/><rect x="16" y="22" width="32" height="20" fill="#d8402e"/>'
                        '<ellipse cx="32" cy="12" rx="16" ry="4" fill="#c8ccd8"/><path d="M22,30 L42,30 M22,35 L36,35" stroke="#ffe0a0" fill="none"/>',
    "mall_energy_drink": '<rect x="20" y="8" width="24" height="48" rx="5" fill="#2a3a6a"/><path d="M34,16 L26,33 L33,33 L29,48 L40,28 L33,28 Z" fill="#7aff6a"/>'
                         '<ellipse cx="32" cy="9" rx="12" ry="3" fill="#c8ccd8"/>',
    "mall_painkillers": '<rect x="18" y="16" width="28" height="40" rx="4" fill="#f2f0ec"/><rect x="16" y="8" width="32" height="10" rx="3" fill="#3aa070"/>'
                        '<rect x="22" y="26" width="20" height="16" fill="#e8f4ff"/><path d="M32,29 L32,39 M27,34 L37,34" stroke="#d8402e" stroke-width="3" fill="none"/>',
    "mall_first_aid": '<rect x="6" y="18" width="52" height="38" rx="5" fill="#e8f0ec"/><path d="M24,18 L24,12 L40,12 L40,18" fill="none"/>'
                      '<path d="M32,26 L32,48 M21,37 L43,37" stroke="#d8302e" stroke-width="7" fill="none"/>',
    "mall_cash_bundle": '<rect x="6" y="20" width="52" height="26" rx="2" fill="#7ac080"/><rect x="10" y="16" width="52" height="26" rx="2" fill="#9ad8a0"/>'
                        '<circle cx="36" cy="29" r="7" fill="#c8f0c8"/><rect x="30" y="14" width="8" height="30" fill="#e8d8a8"/>',
    "mall_perfume": '<rect x="14" y="26" width="36" height="30" rx="8" fill="url(#pink)"/><rect x="26" y="16" width="12" height="10" fill="url(#gold)"/>'
                    '<rect x="24" y="8" width="16" height="9" rx="3" fill="#2a2630"/><path d="M20,34 Q22,30 28,29" stroke="#fff" fill="none"/>',
    "mall_gift_card": '<rect x="6" y="16" width="52" height="34" rx="5" fill="#7a4ab0"/><rect x="6" y="24" width="52" height="5" fill="#ffd040"/>'
                      '<path d="M44,16 L44,50" stroke="#ffd040" stroke-width="4" fill="none"/><path d="M38,12 Q44,18 44,16 Q44,18 50,12" fill="none"/>',
    "mall_batteries": '<rect x="10" y="16" width="16" height="38" rx="3" fill="#e8b040"/><rect x="10" y="16" width="16" height="12" fill="#2a2630"/>'
                      '<rect x="15" y="11" width="6" height="5" fill="#c8ccd8"/><rect x="34" y="16" width="16" height="38" rx="3" fill="#e8b040"/>'
                      '<rect x="34" y="16" width="16" height="12" fill="#2a2630"/><rect x="39" y="11" width="6" height="5" fill="#c8ccd8"/>',
    "key_mall_jewelry": '<rect x="6" y="14" width="52" height="36" rx="5" fill="url(#gold)"/><rect x="6" y="20" width="52" height="7" fill="#2a2630"/>'
                        '<rect x="12" y="33" width="12" height="10" rx="2" fill="#f2e0a0"/><path d="M34,36 L50,36 M34,42 L46,42" stroke="#7a4c12" fill="none"/>',
    "key_mall_offices": '<rect x="6" y="14" width="52" height="36" rx="5" fill="#2a3a6a"/><rect x="6" y="20" width="52" height="7" fill="#101420"/>'
                        '<rect x="12" y="33" width="12" height="10" rx="2" fill="url(#gold)"/><path d="M34,36 L50,36 M34,42 L46,42" stroke="#9ad0ff" fill="none"/>'
                        '<circle cx="50" cy="44" r="3" fill="#ff4a3a"/>',
}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, body in ICONS.items():
        with open(os.path.join(OUT, name + ".svg"), "w") as f:
            f.write(HEAD + body + "\n" + TAIL)
    print("ICONS", len(ICONS), OUT)


if __name__ == "__main__":
    main()
