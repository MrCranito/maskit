#!/usr/bin/env python3
"""Analyse d'une campagne de playtest (journaux JSON du bot + simulation des drops).

Usage : python3 tools/playtest/analyze.py --root DOSSIER_DES_JOURNAUX --out docs/playtest/<date>
        [--drops drops.json] [--passes A,B,boss,duel]

Produit dans --out :
  - resume_<passe>.json : agrégats (comptes, moyennes) par passe ;
  - parties_<passe>.csv : une ligne par partie (journal résumé, sans les listes brutes) ;
  - graphiques/*.png : graphiques ;
  - tableaux.md : tableaux Markdown prêts à coller dans le rapport.
"""
import argparse
import csv
import glob
import json
import os
import re
import statistics as st
from collections import Counter, defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DIFF = ["Facile", "Normal", "Difficile", "Expert", "Cauchemar"]
RAR = ["Commun", "Peu commun", "Rare", "Épique", "Légendaire"]
MAPN = {"perm_dust_creek": "Dust Creek", "perm_station_kagami": "Station Kagami", "perm_galeries_lumiere": "Galeries Lumière"}
INK, VIOLET, VIOLET_L = "#06070D", "#7C4DFF", "#B79BFF"
RCOL = ["#9AA0A6", "#4CAF50", "#4A90E2", "#9C5BE8", "#F5A623"]


def load_pass(root: str, name: str) -> list[dict]:
    out = []
    for p in sorted(glob.glob(os.path.join(root, name, "*.json"))):
        if os.path.basename(p).startswith("_"):
            continue
        try:
            d = json.load(open(p))
        except Exception:
            continue
        d["_id"] = os.path.basename(p)[:-5]
        out.append(d)
    return out


def mean(xs):
    xs = [x for x in xs if x is not None]
    return round(st.mean(xs), 2) if xs else None


def pct(a, b):
    return round(100.0 * a / b, 1) if b else 0.0


def names(n: str) -> str:
    return n


def enemy_names() -> dict[str, str]:
    out = {}
    for p in glob.glob(os.path.join(ROOT, "data", "enemies", "*.tres")):
        t = open(p, encoding="utf-8").read()
        k = re.search(r'^kind = &"([^"]+)"', t, re.M)
        n = re.search(r'^display_name = "([^"]+)"', t, re.M)
        if k:
            out[k.group(1)] = n.group(1) if n else k.group(1)
    return out


ENAMES = enemy_names()


def en(k: str) -> str:
    return "%s (`%s`)" % (ENAMES[k], k) if k in ENAMES else "`%s`" % k


# --- Raids ------------------------------------------------------------------------------

def raids_summary(games: list[dict]) -> dict:
    s = {"n": len(games)}
    by = defaultdict(list)
    for g in games:
        by[(g["map"], g["difficulty"], g["profile"])].append(g)
    combos = []
    for (m, d, p), gs in sorted(by.items()):
        combos.append({"map": m, "difficulty": d, "profile": p, "n": len(gs),
                       "extraction": pct(sum(g["outcome"] == "extraction" for g in gs), len(gs)),
                       "mort": pct(sum(g["outcome"] == "mort" for g in gs), len(gs)),
                       "duree": mean([g["duration"] for g in gs]),
                       "or": mean([g.get("gold_estimate", 0) for g in gs if g["outcome"] == "extraction"]),
                       "xp": mean([g.get("xp", 0) for g in gs])})
    s["combos"] = combos
    # Par carte × difficulté (tous profils).
    md = []
    for m in sorted({g["map"] for g in games}):
        for d in range(5):
            gs = [g for g in games if g["map"] == m and g["difficulty"] == d]
            if not gs:
                continue
            md.append({"map": m, "difficulty": d, "n": len(gs),
                       "extraction": pct(sum(g["outcome"] == "extraction" for g in gs), len(gs)),
                       "duree": mean([g["duration"] for g in gs]),
                       "survie_mediane": round(st.median([g["duration"] for g in gs if g["outcome"] == "mort"]), 1)
                       if any(g["outcome"] == "mort" for g in gs) else None,
                       "kills": mean([sum(g["kills"].values()) for g in gs]),
                       "pv_min": mean([g["hp_min"] for g in gs])})
    s["map_diff"] = md
    # Ennemis : dangerosité.
    seen, dmg, hits, kills, killers, dealt, ttk = Counter(), Counter(), Counter(), Counter(), Counter(), Counter(), defaultdict(list)
    for g in games:
        seen.update(g.get("seen", {}))
        dmg.update({k: v for k, v in g.get("damage_taken", {}).items()})
        hits.update(g.get("hits_taken", {}))
        kills.update(g.get("kills", {}))
        dealt.update(g.get("damage_dealt", {}))
        if g["outcome"] == "mort":
            killers[g.get("killer") or "inconnu"] += 1
        for k, arr in g.get("ttk", {}).items():
            ttk[k].extend(arr)
    rows = []
    for k in sorted(set(seen) | set(dmg) | set(kills)):
        rows.append({"kind": k, "vus": seen[k], "tues": kills[k], "degats_recus": round(dmg[k], 1),
                     "degats_par_rencontre": round(dmg[k] / seen[k], 1) if seen[k] else None,
                     "coups": hits[k], "morts_causees": killers[k],
                     "ttk_median": round(st.median(ttk[k]), 2) if ttk[k] else None,
                     "degats_infliges": round(dealt[k], 1)})
    rows.sort(key=lambda r: -(r["degats_par_rencontre"] or 0))
    s["enemies"] = rows
    s["killers"] = killers.most_common()
    # Butin.
    src_r = defaultdict(lambda: [0] * 5)
    for g in games:
        for src, by_r in g.get("items", {}).items():
            for r, c in by_r.items():
                src_r[src][int(r)] += c
    s["items_by_source"] = {k: v for k, v in src_r.items()}
    s["items_per_raid"] = {k: [round(c / max(len(games), 1), 2) for c in v] for k, v in src_r.items()}
    ext = [g for g in games if g["outcome"] == "extraction"]
    s["or_par_extraction"] = mean([g.get("gold_estimate", 0) for g in ext])
    s["or_par_raid"] = mean([g.get("gold_estimate", 0) if g["outcome"] == "extraction" else 0 for g in games])
    s["xp_par_raid"] = mean([g.get("xp", 0) for g in games])
    s["xp_par_extraction"] = mean([g.get("xp", 0) for g in ext])
    s["xp_par_mort"] = mean([g.get("xp", 0) for g in games if g["outcome"] == "mort"])
    s["tirs_par_raid"] = mean([sum(g.get("shots", {}).values()) for g in games])
    s["conteneurs_par_raid"] = mean([g.get("containers_opened", 0) for g in games])
    s["cadavres_par_raid"] = mean([g.get("corpses_searched", 0) for g in games])
    s["soins_par_raid"] = mean([g.get("heals_used", 0) for g in games])
    s["equipements_par_raid"] = mean([g.get("gadgets_used", 0) for g in games])
    s["esquives_par_raid"] = mean([g.get("dodges", 0) for g in games])
    # Qualité technique.
    stuck = Counter()
    unreach = Counter()
    for g in games:
        stuck.update(g.get("stuck_enemies", {}))
        unreach.update(g.get("unreachable_kinds", {}))
    s["ennemis_bloques"] = stuck.most_common()
    s["conteneurs_inaccessibles"] = unreach.most_common()
    s["conteneurs_inaccessibles_par_raid"] = mean([g.get("unreachable_containers", 0) for g in games])
    errs = Counter()
    warns = Counter()
    err_seed = {}
    for g in games:
        for e in g.get("errors", []):
            key = re.sub(r"\d+\.\d+", "N", e)[:180]
            errs[key] += 1
            err_seed.setdefault(key, (g["map"], g["seed"], g["difficulty"], g["profile"]))
        for w in g.get("warnings", []):
            warns[re.sub(r"\d+\.\d+", "N", w)[:180]] += 1
    s["erreurs"] = [(k, c, err_seed[k]) for k, c in errs.most_common(25)]
    s["avertissements"] = warns.most_common(25)
    s["image_la_plus_lente_ms"] = max([g.get("worst_frame_ms", 0) for g in games] or [0])
    s["image_moyenne_ms"] = mean([g.get("avg_frame_ms", 0) for g in games])
    s["bot_bloque_par_raid"] = mean([g.get("bot_stuck", 0) for g in games])
    s["elites"] = {}
    for g in games:
        for k, v in g.get("elites", {}).items():
            e = s["elites"].setdefault(k, {"met": 0, "killed": 0})
            e["met"] += v.get("met", 0)
            e["killed"] += v.get("killed", 0)
    s["boss_rencontres"] = sum(1 for g in games if g.get("boss", {}).get("kind"))
    s["boss_tues"] = sum(1 for g in games if g.get("boss", {}).get("killed"))
    return s


# --- Boss et duels ----------------------------------------------------------------------

def boss_summary(games: list[dict]) -> dict:
    out = defaultdict(list)
    for g in games:
        out[g.get("boss_kind") or g.get("boss", {}).get("kind", "?")].append(g)
    res = {}
    for k, gs in out.items():
        rows = []
        for d in (1, 2):
            for tier in ("debutant", "moyen", "equipe"):
                sub = [g for g in gs if g["difficulty"] == d and g["tier"] == tier]
                if not sub:
                    continue
                wins = [g for g in sub if g["outcome"] == "victoire" or g.get("boss", {}).get("killed")]
                deaths = [g for g in sub if g["outcome"] == "mort"]
                rows.append({"difficulty": d, "tier": tier, "n": len(sub), "victoires": len(wins),
                             "taux": pct(len(wins), len(sub)),
                             "duree": mean([g["duration"] for g in sub]),
                             "pv_boss_restants": mean([g.get("boss", {}).get("hp_ratio_end", g.get("boss", {}).get("hp_ratio_at_death")) for g in sub]),
                             "phase_mort": Counter(g.get("boss_phase_at_death", -1) for g in deaths).most_common(),
                             "tueurs": Counter(g.get("killer") or "?" for g in deaths).most_common(3),
                             "competence": Counter(g.get("boss", {}).get("death_skill") or "?" for g in deaths).most_common(3),
                             "pv_joueur_victoire": mean([g.get("hp_end") for g in wins])})
        res[k] = rows
    return res


def duel_summary(games: list[dict]) -> list[dict]:
    by = defaultdict(list)
    for g in games:
        by[g.get("enemy", "?")].append(g)
    rows = []
    for k, gs in sorted(by.items()):
        for tier in ("moyen", "equipe"):
            sub = [g for g in gs if g["tier"] == tier]
            if not sub:
                continue
            wins = [g for g in sub if g["outcome"] == "victoire"]
            rows.append({"kind": k, "tier": tier, "n": len(sub), "victoires": len(wins),
                         "taux": pct(len(wins), len(sub)), "duree": mean([g["duration"] for g in sub]),
                         "ttk": mean([g.get("ttk_avg", {}).get(k) for g in wins]),
                         "pv_restants": mean([g.get("hp_end") for g in wins]),
                         "degats_recus": mean([sum(g.get("damage_taken", {}).values()) for g in sub])})
    return rows


# --- Drops ------------------------------------------------------------------------------

def item_rarity() -> dict[str, int]:
    out = {}
    for p in glob.glob(os.path.join(ROOT, "data", "items", "*.tres")):
        t = open(p, encoding="utf-8").read()
        i = re.search(r'^id = &"([^"]+)"', t, re.M)
        r = re.search(r"^rarity = (\d)", t, re.M)
        if i:
            out[i.group(1)] = int(r.group(1)) if r else 0
    return out


def drops_summary(drops: dict) -> dict:
    rar = item_rarity()
    over = []
    by_source = []
    for src, ctxs in drops["sources"].items():
        ref = ctxs.get("d1_f0")
        if not ref:
            continue
        for item, p in ref["per_item"].items():
            r = rar.get(item, 0)
            if (r >= 4 and p >= 0.01) or (r == 3 and p >= 0.04):
                over.append({"source": src, "item": item, "rarete": r, "chance": round(100 * p, 3)})
        by_source.append({"source": src, "vide": round(100 * ref["empty"], 1), "objets": round(ref["items_avg"], 2),
                          "valeur": round(ref["value_avg"], 1),
                          "rarete": [round(100 * x / max(ref["items_avg"], 1e-9), 2) for x in ref["rarity"]],
                          "epique_ou_mieux": round(100 * (ref["rarity"][3] + ref["rarity"][4]), 3),
                          "par_difficulte": {k: round(100 * (v["rarity"][3] + v["rarity"][4]), 3)
                                             for k, v in ctxs.items() if isinstance(v, dict) and "rarity" in v}})
    return {"plafonds_depasses": over, "sources": by_source}


def observed_vs_sim(raids: list[dict], drops: dict) -> list[dict]:
    """Part d'objets Épiques+ par source : observé en raid vs simulé (même difficulté moyenne)."""
    obs = defaultdict(lambda: [0] * 5)
    for g in raids:
        for src, by_r in g.get("items", {}).items():
            for r, c in by_r.items():
                obs[src][int(r)] += c
    out = []
    groups = {"conteneur": "conteneur:", "tresor": "tresor:", "cadavre": "cadavre:", "sol": "sol:"}
    for name, prefix in groups.items():
        o = obs.get(name)
        if not o or sum(o) == 0:
            continue
        sims = [v for k, v in drops["sources"].items() if k.startswith(prefix)]
        tot = [0.0] * 5
        for s in sims:
            ref = s.get("d1_f0")
            if ref:
                for i in range(5):
                    tot[i] += ref["rarity"][i]
        simtot = sum(tot) or 1
        out.append({"source": name, "observe_n": sum(o),
                    "observe": [round(100 * x / sum(o), 2) for x in o],
                    "simule": [round(100 * x / simtot, 2) for x in tot]})
    return out


# --- Économie ----------------------------------------------------------------------------

def balance_value(section: str, key: str, default: str) -> str:
    text = open(os.path.join(ROOT, "data", "balance.cfg"), encoding="utf-8").read()
    m = re.search(r"^\[%s\]\n(.*?)(?=^\[)" % re.escape(section), text, re.M | re.S)
    if not m:
        return default
    mm = re.search(r"^%s=(.+)$" % re.escape(key), m.group(1), re.M)
    return mm.group(1).strip() if mm else default


def death_xp(g: dict) -> float:
    """XP d'une mort recalculée par le barème (journaux écrits avant la correction du bot)."""
    base = float(balance_value("battle_pass", "xp_death", "60"))
    fac = float(balance_value("battle_pass", "xp_death_factor", "0.5"))
    kills = sum(g.get("kills", {}).values())
    minutes = min(g["duration"] / 60.0, float(balance_value("battle_pass", "xp_max_minutes", "20")))
    x = base + kills * float(balance_value("battle_pass", "xp_per_kill", "12")) * fac \
        + minutes * float(balance_value("battle_pass", "xp_per_minute", "15")) * fac
    return x * float(balance_value("raider", "xp_ratio", "1.0"))


def economy(games: list[dict]) -> dict:
    xs = [g.get("xp", 0) if (g.get("xp", 0) > 0 or g["outcome"] != "mort") else death_xp(g) for g in games]
    xp_raid = st.mean(xs) if xs else 0
    gold_raid = st.mean([g.get("gold_estimate", 0) if g["outcome"] == "extraction" else 0 for g in games]) if games else 0
    base = int(balance_value("raider", "xp_base", "400"))
    step = int(balance_value("raider", "xp_step", "150"))
    levels = []
    cum = 0
    for lv in range(2, 31):
        cum += base + step * (lv - 2)
        levels.append({"niveau": lv, "xp": cum, "raids": round(cum / xp_raid, 1) if xp_raid else None})
    weapons = []
    for pth in sorted(glob.glob(os.path.join(ROOT, "data", "weapons", "*.tres"))):
        t = open(pth, encoding="utf-8").read()
        wid = os.path.basename(pth)[:-5]
        if wid.startswith("gadget_"):
            continue
        mode = re.search(r'^unlock_mode = &"(\w+)"', t, re.M)
        mode = mode.group(1) if mode else "drop"
        price = re.search(r"^price_gold = (\d+)", t, re.M)
        price = int(price.group(1)) if price else 0
        kind = re.search(r'^unlock_enemy_kind = &"(\w*)"', t, re.M)
        kind = kind.group(1) if kind else ""
        kn = re.search(r"^unlock_kills = (\d+)", t, re.M)
        kn = int(kn.group(1)) if kn else 0
        row = {"arme": wid, "mode": mode, "prix": price}
        if mode == "kill" and kind:
            world_games = [g for g in games if g.get("world", "").startswith("world_01") == kind.startswith("fw_")
                           and (not kind.startswith("ss_") or "02" in g.get("world", ""))]
            kpr = st.mean([g.get("kills", {}).get(kind, 0) for g in world_games]) if world_games else 0
            row.update({"ennemi": kind, "kills": kn, "kills_par_raid": round(kpr, 2),
                        "raids_deblocage": round(kn / kpr, 1) if kpr else None})
        if price:
            row["raids_achat"] = round(price / gold_raid, 1) if gold_raid else None
        weapons.append(row)
    return {"xp_par_raid": round(xp_raid, 1), "or_par_raid": round(gold_raid, 1), "niveaux": levels, "armes": weapons}


# --- Graphiques -------------------------------------------------------------------------

def _style(ax, title):
    ax.set_title(title, color=INK, fontsize=11, loc="left")
    for sp in ("top", "right"):
        ax.spines[sp].set_visible(False)


def charts(out: str, sA: dict, sB: dict | None, boss: dict, duels: list, enemies: list):
    gdir = os.path.join(out, "graphiques")
    os.makedirs(gdir, exist_ok=True)
    # Extraction par difficulté et carte.
    fig, ax = plt.subplots(figsize=(7, 3.6))
    for i, m in enumerate(sorted({r["map"] for r in sA["map_diff"]})):
        rows = [r for r in sA["map_diff"] if r["map"] == m]
        ax.bar([r["difficulty"] + (i - 0.5) * 0.38 for r in rows], [r["extraction"] for r in rows], 0.36,
               label=MAPN.get(m, m), color=[VIOLET, VIOLET_L][i % 2])
    ax.set_xticks(range(5), DIFF)
    ax.set_ylabel("% d'extractions")
    ax.legend(frameon=False)
    _style(ax, "Passe A : taux d'extraction du bot par difficulté")
    fig.tight_layout()
    fig.savefig(os.path.join(gdir, "extraction_par_difficulte.png"), dpi=130)
    plt.close(fig)
    # Dangerosité des ennemis.
    rows = [r for r in enemies if r["vus"] >= 5][:16]
    if rows:
        fig, ax = plt.subplots(figsize=(7, 0.32 * len(rows) + 1.2))
        ax.barh([ENAMES.get(r["kind"], r["kind"]) for r in rows][::-1], [r["degats_par_rencontre"] for r in rows][::-1], color=VIOLET)
        ax.set_xlabel("PV perdus par ennemi rencontré")
        _style(ax, "Dégâts infligés au joueur par rencontre (passe A)")
        fig.tight_layout()
        fig.savefig(os.path.join(gdir, "dangerosite_ennemis.png"), dpi=130)
        plt.close(fig)
    # Boss.
    if boss:
        fig, ax = plt.subplots(figsize=(7, 3.4))
        labels, vals = [], []
        for k, rows2 in boss.items():
            for r in rows2:
                labels.append("%s\n%s %s" % (ENAMES.get(k, k).split(" ")[-1], DIFF[r["difficulty"]][:4], r["tier"][:3]))
                vals.append(r["taux"])
        ax.bar(range(len(vals)), vals, color=VIOLET)
        ax.set_xticks(range(len(vals)), labels, fontsize=6)
        ax.set_ylabel("% de victoires")
        _style(ax, "Boss : taux de victoire (difficulté, arsenal)")
        fig.tight_layout()
        fig.savefig(os.path.join(gdir, "boss_victoires.png"), dpi=130)
        plt.close(fig)
    if duels:
        fig, ax = plt.subplots(figsize=(7, 3.2))
        lab = ["%s\n%s" % (ENAMES.get(r["kind"], r["kind"]), r["tier"]) for r in duels]
        ax.bar(range(len(duels)), [r["taux"] for r in duels], color=[VIOLET if r["tier"] == "moyen" else VIOLET_L for r in duels])
        ax.set_xticks(range(len(duels)), lab, fontsize=6)
        ax.set_ylabel("% de victoires")
        _style(ax, "Élites en duel (Normal)")
        fig.tight_layout()
        fig.savefig(os.path.join(gdir, "elites_duels.png"), dpi=130)
        plt.close(fig)
    if sB:
        fig, ax = plt.subplots(figsize=(7, 3.4))
        keys = sorted({(r["map"], r["difficulty"]) for r in sB["map_diff"]})
        a = {(r["map"], r["difficulty"]): r["extraction"] for r in sA["map_diff"]}
        b = {(r["map"], r["difficulty"]): r["extraction"] for r in sB["map_diff"]}
        x = range(len(keys))
        ax.bar([i - 0.2 for i in x], [a.get(k, 0) for k in keys], 0.38, label="Passe A (avant)", color=VIOLET_L)
        ax.bar([i + 0.2 for i in x], [b.get(k, 0) for k in keys], 0.38, label="Passe B (après)", color=VIOLET)
        ax.set_xticks(list(x), ["%s\n%s" % (MAPN.get(m, m), DIFF[d]) for m, d in keys], fontsize=7)
        ax.set_ylabel("% d'extractions")
        ax.legend(frameon=False)
        _style(ax, "Avant / après réglages")
        fig.tight_layout()
        fig.savefig(os.path.join(gdir, "avant_apres.png"), dpi=130)
        plt.close(fig)


def write_csv(path: str, games: list[dict]):
    cols = ["_id", "mode", "map", "difficulty", "profile", "tier", "seed", "enemy", "outcome", "killer", "duration",
            "hp_min", "hp_end", "gold_estimate", "xp", "containers_opened", "corpses_searched", "heals_used",
            "gadgets_used", "dodges", "unreachable_containers", "bot_stuck", "worst_frame_ms"]
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols + ["kills", "damage_taken", "items"])
        for g in games:
            w.writerow([g.get(c, "") for c in cols] + [json.dumps(g.get("kills", {})), json.dumps(g.get("damage_taken", {})),
                                                       json.dumps(g.get("items", {}))])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--drops", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    A = load_pass(a.root, "A")
    B = load_pass(a.root, "B")
    BO = load_pass(a.root, "boss")
    DU = load_pass(a.root, "duel")
    res = {}
    if A:
        res["A"] = raids_summary(A)
        write_csv(os.path.join(a.out, "parties_A.csv"), A)
    if B:
        res["B"] = raids_summary(B)
        write_csv(os.path.join(a.out, "parties_B.csv"), B)
    if BO:
        res["boss"] = boss_summary(BO)
        write_csv(os.path.join(a.out, "parties_boss.csv"), BO)
    if DU:
        res["duel"] = duel_summary(DU)
        write_csv(os.path.join(a.out, "parties_duels.csv"), DU)
    if A:
        res["economie"] = economy(A + B)
    if a.drops and os.path.exists(a.drops):
        drops = json.load(open(a.drops))
        res["drops"] = drops_summary(drops)
        if A:
            res["drops"]["observe_vs_simule"] = observed_vs_sim(A + B, drops)
    json.dump(res, open(os.path.join(a.out, "resume.json"), "w"), indent=1, ensure_ascii=False)
    if A:
        charts(a.out, res["A"], res.get("B"), res.get("boss", {}), res.get("duel", []), res["A"]["enemies"])
    print("analyse écrite dans", a.out)


if __name__ == "__main__":
    main()
