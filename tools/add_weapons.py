#!/usr/bin/env python3
"""Ajoute au jeu des armes du catalogue de tools/gen_weapons.py sans régénérer le reste.

Usage : python3 tools/add_weapons.py <id> [<id> ...]

tools/gen_weapons.py réécrit toutes les armes et toutes les tables de butin ; depuis, des tables
ont été retouchées (plafonds de drop, butin des boss) et une régénération complète les ferait
dériver. Ce script, lui :
  - écrit data/weapons/<id>.tres et data/items/wpn_<id>.tres pour les ids donnés (stats de
    gen_weapons.WEAPONS, mêmes règles d'armurerie) ;
  - ajoute leurs entrées aux tables gérées (gen_weapons.TABLE_TIERS) en gardant, pour chaque
    rareté, le poids total des armes à feu de la table : le poids d'une rareté est réparti entre
    davantage de modèles (même chance de trouver une arme de cette rareté, plus de variété).
    Rareté sans arme à feu dans la table : le poids d'un modèle (gen_weapons.TIER_WEIGHTS),
    partagé entre les nouveaux modèles.
Les autres entrées et les tables propres aux ennemis ne sont pas touchées.
"""
from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_weapons as gw  # noqa: E402

ENTRY_RE = re.compile(r'^&"([^"]+)":\s*([0-9.eE+-]+),?\s*$')


def write_lf(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def fmt_weight(v: float) -> str:
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    return ("%.6f" % v).rstrip("0").rstrip(".")


def weapon_row(wid: str):
    for row in gw.WEAPONS:
        if row[0] == wid:
            return row
    raise SystemExit("arme inconnue de gen_weapons.WEAPONS : " + wid)


def patch_table(path: str, kind: str, new_rows: list) -> bool:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"entries = \{\n(.*?)\n\}", text, re.S)
    if m is None:
        return False
    entries: dict[str, str] = {}
    for line in m.group(1).splitlines():
        mm = ENTRY_RE.match(line.strip())
        if mm:
            entries[mm.group(1)] = mm.group(2)
    rarity_of = {"wpn_" + w[0]: w[2] for w in gw.WEAPONS if w[1] != "gadget"}
    tier, mult = gw.TABLE_TIERS[kind]
    changed = False
    for r in range(5):
        adds = ["wpn_" + w[0] for w in new_rows if w[2] == r and "wpn_" + w[0] not in entries]
        if not adds:
            continue
        olds = [k for k in entries if rarity_of.get(k) == r]
        if olds:
            total = sum(float(entries[k]) for k in olds)
            each = total / (len(olds) + len(adds))
            for k in olds:
                entries[k] = fmt_weight(float(entries[k]) * len(olds) / (len(olds) + len(adds)))
        else:
            # Rareté nouvelle dans la table : le poids d'UN modèle, partagé entre les nouveaux.
            each = gw.TIER_WEIGHTS[tier][r] * mult / len(adds)
        for k in adds:
            entries[k] = fmt_weight(each)
        changed = True
    if not changed:
        return False
    body = ",\n".join('&"%s": %s' % (k, entries[k]) for k in sorted(entries))
    write_lf(path, text[: m.start()] + "entries = {\n" + body + "\n}" + text[m.end():])
    return True


def main(ids: list[str]) -> int:
    if not ids:
        print(__doc__)
        return 1
    rows = [weapon_row(i) for i in ids]
    for (wid, cat, rarity, name, desc, adj) in rows:
        st = gw.build_stats(wid, cat, rarity, adj)
        write_lf(os.path.join(gw.WEAPON_DIR, wid + ".tres"), gw.weapon_tres(wid, cat, rarity, name, desc, st))
        write_lf(os.path.join(gw.ITEM_DIR, "wpn_" + wid + ".tres"), gw.item_tres(wid, name, desc, rarity, st))
        dps = (st["damage"] * st["projectile_count"] + st["explosion_damage"]) * st["fire_rate"]
        print("%-20s %-16s %d  dps %6.1f  %-4s %5d or" % (wid, cat, rarity, dps, st["unlock_mode"], st["price_gold"]))
    n = 0
    for kind in sorted(gw.TABLE_TIERS):
        path = os.path.join(gw.TABLE_DIR, kind + ".tres")
        if os.path.exists(path) and patch_table(path, kind, rows):
            n += 1
    print("%d armes écrites, %d tables complétées." % (len(rows), n))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
