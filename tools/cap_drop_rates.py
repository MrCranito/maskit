#!/usr/bin/env python3
"""Plafonne les taux de drop des objets Épiques et Légendaires dans les tables de butin.

Usage : python3 tools/cap_drop_rates.py [--check]

Règle (demande du testeur) : pour CHAQUE objet et CHAQUE source (conteneur, salle au trésor,
cadavre d'ennemi, élite, butin au sol), la chance d'obtenir l'objet en une fouille reste
  - sous LEGENDARY_MAX (1 %) pour un Légendaire,
  - sous EPIC_MAX (4 %) pour un Épique,
en difficulté Normale au rez-de-chaussée (contexte de référence de la page des taux de drop).
Les difficultés et étages plus élevés augmentent ces chances ([loot] rarity_*_bonus).

Le calcul reproduit LootRoller.roll (tirages pondérés sans remise, chance de vide, tirage en plus
et multiplicateurs de rareté en salle au trésor) et LootManager.roll_enemy_loot (butin au sol).
Les poids des objets trop fréquents sont réduits jusqu'à passer sous le plafond (avec une marge).
tools/gen_weapons.py appelle ce script à la fin, pour que les plafonds survivent à une régénération.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEGENDARY_MAX = 0.01
EPIC_MAX = 0.04
MARGIN = 0.92            # vise 92 % du plafond
DIFF, FLOOR = 1, 0       # Normal, rez-de-chaussée

ENTRY_RE = re.compile(r'&"([^"]+)":\s*([0-9.eE+-]+)')


def cfg_list(text: str, key: str, default: list) -> list:
    m = re.search(r"^%s=\[(.*?)\]" % key, text, re.M)
    return [float(x) for x in m.group(1).split(",")] if m else default


BAL = open(os.path.join(ROOT, "data", "balance.cfg"), encoding="utf-8").read()
DB = cfg_list(BAL, "rarity_difficulty_bonus", [0.0, 0.05, 0.15, 0.3, 0.45])
FB = cfg_list(BAL, "rarity_floor_bonus", [0.0, 0.05, 0.2, 0.35, 0.5])
SL = cfg_list(BAL, "super_loot_rarity_mult", [0.3, 0.7, 2.0, 6.0, 10.0])
m = re.search(r"^super_loot_extra_rolls=(\d+)", BAL, re.M)
SL_EXTRA = int(m.group(1)) if m else 1
m = re.search(r"^ground_drop_max=(\d+)", BAL, re.M)
GROUND_MAX = int(m.group(1)) if m else 2
m = re.search(r"^elite_extra_ground=(\d+)", BAL, re.M)
ELITE_EXTRA = int(m.group(1)) if m else 2


def val(text: str, key: str, default: str = "") -> str:
    mm = re.search(r"^%s = (.+)$" % re.escape(key), text, re.M)
    return mm.group(1).strip() if mm else default


RARITY: dict[str, int] = {}
for p in glob.glob(os.path.join(ROOT, "data", "items", "*.tres")):
    t = open(p, encoding="utf-8").read()
    RARITY[val(t, "id").replace("&", "").strip('"')] = int(val(t, "rarity", "0"))


def mult(r: int, super_loot: bool) -> float:
    x = (1 + DB[r] * DIFF) * (1 + FB[r] * abs(FLOOR))
    return x * SL[r] if super_loot else x


def incl_probs(w: dict[str, float], n: int) -> dict[str, float]:
    """Chance que chaque clé sorte au moins une fois en n tirages pondérés sans remise."""
    ids = list(w)
    ws = [w[i] for i in ids]
    k = len(ids)
    n = min(n, k)
    res = [0.0] * k

    def rec(chosen: int, prob: float, depth: int) -> None:
        if depth == n or prob < 1e-7:
            return
        rem = sum(ws[j] for j in range(k) if not (chosen >> j) & 1)
        if rem <= 0:
            return
        for j in range(k):
            if (chosen >> j) & 1:
                continue
            pj = prob * ws[j] / rem
            res[j] += pj
            rec(chosen | (1 << j), pj, depth + 1)

    rec(0, 1.0, 0)
    return dict(zip(ids, res))


def probs(entries: dict[str, float], draws: list[int], super_loot: bool, keep: float) -> dict[str, float]:
    w = {k: v * mult(RARITY[k], super_loot) for k, v in entries.items() if k in RARITY and v > 0}
    out = {k: 0.0 for k in w}
    for n in draws:
        pr = incl_probs(w, n)
        for k in out:
            out[k] += pr[k] / len(draws)
    return {k: v * keep for k, v in out.items()}


def contexts(name: str, t: dict) -> list[tuple[list[int], bool, float]]:
    """(tirages possibles, salle au trésor ?, part non vide) pour chaque usage de la table."""
    base = list(range(t["rmin"], max(t["rmin"], t["rmax"]) + 1))
    if name == "enemy_drop":
        # Butin au sol : chance jusqu'à 100 % (élite), 1..GROUND_MAX objets, +ELITE_EXTRA pour l'élite.
        normal = list(range(1, GROUND_MAX + 1))
        return [(normal, False, 1.0), ([n + ELITE_EXTRA for n in normal], False, 1.0)]
    return [(base, False, 1.0 - t["empty"]), ([n + SL_EXTRA for n in base], True, 1.0)]


def load(path: str) -> dict:
    text = open(path, encoding="utf-8").read()
    mm = re.search(r"entries = \{(.*?)\n\}", text, re.S)
    entries = {k: float(v) for k, v in ENTRY_RE.findall(mm.group(1))} if mm else {}
    return {"text": text, "m": mm, "entries": entries, "rmin": int(val(text, "rolls_min", "1")),
            "rmax": int(val(text, "rolls_max", "2")), "empty": float(val(text, "empty_chance", "0.1"))}


def worst(name: str, t: dict) -> dict[str, float]:
    out: dict[str, float] = {}
    for draws, sl, keep in contexts(name, t):
        for k, p in probs(t["entries"], draws, sl, keep).items():
            out[k] = max(out.get(k, 0.0), p)
    return out


def cap(item: str) -> float | None:
    r = RARITY.get(item, 0)
    return LEGENDARY_MAX if r >= 4 else (EPIC_MAX if r == 3 else None)


def fmt(x: float) -> str:
    s = ("%.6f" % x).rstrip("0").rstrip(".")
    return s if s not in ("", "0") else "0.000001"


def main() -> int:
    check_only = "--check" in sys.argv
    bad = 0
    changed = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "loot_tables", "*.tres"))):
        name = os.path.basename(path)[:-5]
        t = load(path)
        if not t["entries"]:
            continue
        before = dict(t["entries"])
        for _ in range(60):
            w = worst(name, t)
            over = {k: p for k, p in w.items() if cap(k) is not None and p >= cap(k) * MARGIN}
            if not over:
                break
            if check_only:
                for k, p in over.items():
                    if p >= cap(k):
                        bad += 1
                        print("  %-22s %-24s %.3f %%  (plafond %.0f %%)" % (name, k, p * 100, cap(k) * 100))
                break
            for k, p in over.items():
                t["entries"][k] *= max(min(cap(k) * MARGIN * 0.97 / p, 0.97), 0.05)
        if not check_only and t["entries"] != before:
            body = ",\n".join('&"%s": %s' % (k, fmt(t["entries"][k])) for k in sorted(t["entries"]))
            text = t["text"][: t["m"].start()] + "entries = {\n" + body + "\n}" + t["text"][t["m"].end():]
            open(path, "w", encoding="utf-8").write(text)
            changed += 1
    if check_only:
        print("OK : tous les Épiques < %d %% et Légendaires < %d %%" % (EPIC_MAX * 100, LEGENDARY_MAX * 100) if bad == 0
              else "%d dépassements" % bad)
        return 1 if bad else 0
    print("Plafonds appliqués : %d tables modifiées (Épique < %d %%, Légendaire < %d %%)." % (
        changed, EPIC_MAX * 100, LEGENDARY_MAX * 100))
    return 0


if __name__ == "__main__":
    sys.exit(main())
