"""Icônes d'objets du Carnaval hanté (SVG 64x64 peints à plat, contour sombre, reflet).

Usage : python3 art/blender/haunted_carnival/build_hc_icons.py  ->  assets/sprites/haunted_carnival/icons/<id>.svg
Même style que art/blender/mall/build_mall_icons.py.
"""
from __future__ import annotations

import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "haunted_carnival", "icons")

HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="128" height="128">\n<defs>'
        '<linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffe9a0"/><stop offset="0.5" stop-color="#d9a234"/><stop offset="1" stop-color="#7a4c12"/></linearGradient>'
        '<linearGradient id="red" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff8a8a"/><stop offset="0.5" stop-color="#c0303a"/><stop offset="1" stop-color="#5a1020"/></linearGradient>'
        '<linearGradient id="violet" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#d8b0ff"/><stop offset="0.5" stop-color="#8a4ad0"/><stop offset="1" stop-color="#3a1a60"/></linearGradient>'
        '<linearGradient id="pink" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffc0e8"/><stop offset="1" stop-color="#c04a9a"/></linearGradient>'
        '<linearGradient id="cream" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff8ee"/><stop offset="1" stop-color="#c8b8a8"/></linearGradient>'
        '<radialGradient id="glass" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#ffffff"/><stop offset="0.4" stop-color="#d8c0ff"/><stop offset="1" stop-color="#5a3aa0"/></radialGradient>'
        '</defs>\n<g stroke="#1e1218" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round">\n')
TAIL = '</g></svg>\n'

ICONS = {
    "hc_ticket_roll": '<circle cx="30" cy="34" r="20" fill="url(#red)"/><circle cx="30" cy="34" r="7" fill="#3a1020"/>'
                      '<rect x="38" y="24" width="20" height="12" rx="2" fill="url(#cream)"/><path d="M42,30 L54,30" stroke="#c0303a" fill="none"/>',
    "hc_cotton_candy": '<path d="M30,34 L34,60" stroke="#f2e8d8" stroke-width="5" fill="none"/>'
                       '<circle cx="24" cy="28" r="12" fill="url(#pink)"/><circle cx="40" cy="24" r="13" fill="url(#pink)"/><circle cx="32" cy="14" r="10" fill="url(#pink)"/>'
                       '<path d="M22,20 Q26,14 32,16" stroke="#fff" fill="none"/>',
    "hc_plush_bear": '<circle cx="18" cy="16" r="7" fill="#b07a4c"/><circle cx="46" cy="16" r="7" fill="#b07a4c"/>'
                     '<circle cx="32" cy="24" r="16" fill="#c8905a"/><ellipse cx="32" cy="44" rx="17" ry="15" fill="#c8905a"/>'
                     '<circle cx="26" cy="22" r="2.5" fill="#1e1218"/><path d="M36,20 L40,24 M40,20 L36,24" stroke="#1e1218" fill="none"/>'
                     '<ellipse cx="32" cy="30" rx="5" ry="3.5" fill="#3a2020"/>',
    "hc_clown_grin": '<ellipse cx="32" cy="32" rx="22" ry="25" fill="url(#cream)"/><circle cx="23" cy="26" r="4.5" fill="#1e1218"/><circle cx="41" cy="26" r="4.5" fill="#1e1218"/>'
                     '<circle cx="32" cy="35" r="5" fill="url(#red)"/><path d="M20,44 Q32,54 44,44" stroke="#c0303a" stroke-width="4" fill="none"/>'
                     '<path d="M14,20 Q10,8 20,8 M50,20 Q54,8 44,8" stroke="#8a4ad0" stroke-width="4" fill="none"/>',
    "hc_crystal_ball": '<rect x="18" y="48" width="28" height="10" rx="3" fill="url(#gold)"/><circle cx="32" cy="30" r="20" fill="url(#glass)"/>'
                       '<path d="M22,24 Q26,16 34,16" stroke="#fff" fill="none"/>',
    "hc_prize_coins": '<circle cx="24" cy="38" r="13" fill="url(#gold)"/><circle cx="40" cy="30" r="13" fill="url(#gold)"/>'
                      '<circle cx="40" cy="30" r="8" fill="none" stroke="#7a4c12"/><path d="M40,25 L40,35 M36,30 L44,30" stroke="#7a4c12" fill="none"/>',
    "hc_caramel_apple": '<path d="M32,8 L32,20" stroke="#8a5a30" stroke-width="4" fill="none"/><circle cx="32" cy="38" r="20" fill="url(#red)"/>'
                        '<path d="M14,36 Q20,30 30,34 Q40,26 50,36" stroke="#d9a234" stroke-width="4" fill="none"/><path d="M22,28 Q24,22 30,22" stroke="#ffb0b0" fill="none"/>',
    "hc_popcorn_box": '<path d="M16,26 L20,58 L44,58 L48,26 Z" fill="url(#red)"/><path d="M22,26 L24,58 M32,26 L32,58 M42,26 L40,58" stroke="#fff0e0" stroke-width="3" fill="none"/>'
                      '<circle cx="22" cy="22" r="6" fill="#fff4d0"/><circle cx="34" cy="16" r="7" fill="#fff4d0"/><circle cx="44" cy="22" r="6" fill="#fff4d0"/>',
    "hc_ringmaster_whip": '<rect x="10" y="40" width="14" height="16" rx="3" fill="#3a2020" transform="rotate(-40 17 48)"/>'
                          '<path d="M22,42 Q40,20 44,10 Q50,20 56,30 Q52,24 46,26" stroke="#8a5a30" stroke-width="3" fill="none"/>'
                          '<rect x="8" y="12" width="20" height="14" rx="2" fill="url(#violet)"/><rect x="10" y="8" width="16" height="5" fill="#1e1218"/>',
    "hc_carousel_horse": '<path d="M32,8 L32,58" stroke="url(#gold)" stroke-width="4" fill="none"/>'
                         '<path d="M18,30 Q18,20 30,20 L40,22 Q50,18 52,28 L46,30 L44,40 L22,40 Z" fill="url(#cream)"/>'
                         '<path d="M30,20 Q34,12 42,14" stroke="#c0303a" stroke-width="3" fill="none"/><circle cx="46" cy="25" r="1.8" fill="#1e1218"/>'
                         '<path d="M24,40 L22,52 M42,40 L44,52" stroke="#c8b8a8" stroke-width="3" fill="none"/>',
    "hc_fuse_box": '<rect x="12" y="10" width="40" height="44" rx="4" fill="#3a3a48"/><rect x="18" y="16" width="28" height="16" fill="#5a3aa0"/>'
                   '<path d="M30,18 L26,26 L32,26 L28,32" stroke="#ffe060" stroke-width="2.5" fill="none"/>'
                   '<circle cx="22" cy="42" r="3" fill="#ff4a3a"/><circle cx="32" cy="42" r="3" fill="#6aff8a"/><circle cx="42" cy="42" r="3" fill="#ffe060"/>',
    "key_hc_director": '<circle cx="22" cy="24" r="13" fill="url(#gold)"/><circle cx="22" cy="24" r="5" fill="#1e1218"/>'
                       '<path d="M31,32 L52,52 M46,46 L52,40 M40,40 L46,34" stroke="url(#gold)" stroke-width="6" fill="none"/>'
                       '<circle cx="22" cy="24" r="13" fill="none" stroke="#8a4ad0" stroke-width="1.5" stroke-dasharray="3 2"/>',
}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, body in ICONS.items():
        with open(os.path.join(OUT, name + ".svg"), "w") as f:
            f.write(HEAD + body + "\n" + TAIL)
    print("ICONS", len(ICONS), OUT)


if __name__ == "__main__":
    main()
