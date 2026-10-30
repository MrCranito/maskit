#!/usr/bin/env python3
"""Campagne de playtest automatique (bot headless), reprenable.

Usage :
  python3 tools/playtest/run_campaign.py --root DOSSIER --pass A|B|boss|duel|smoke [--jobs 2]
       [--godot CHEMIN] [--only ID] [--list]

- Le plan de chaque passe est fixe (seeds déterministes) : relancer la commande reprend où elle
  s'est arrêtée (une partie dont le journal <root>/<passe>/<id>.json existe est sautée).
- Au plus --jobs parties en parallèle (défaut 2 : la machine cible n'a que 2 cœurs).
- Chaque partie tourne avec son propre dossier de données Godot (XDG_DATA_HOME) : aucune
  sauvegarde du joueur n'est touchée, les parties parallèles ne se gênent pas.
- Une partie qui plante ou dépasse le délai est relancée une fois, puis notée dans
  <root>/<passe>/_echecs.json.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPS = {"fw": "perm_dust_creek", "ss": "perm_station_kagami", "mall": "perm_galeries_lumiere"}
PROFILES = ["prudent", "agressif", "fouilleur"]
ELITES = {"fw": ["fw_deserter", "fw_buffalo"], "ss": ["ss_drone_tieur", "ss_atlas"],
          "mall": ["mall_violent", "mall_store_warden"]}
TIERS = ["debutant", "moyen", "equipe"]


def plan(pass_name: str) -> list[dict]:
    jobs: list[dict] = []
    if pass_name in ("A", "B"):
        base = 1000 if pass_name == "A" else 5000
        n = 0
        if pass_name == "A":
            # 30 combinaisons carte × difficulté × profil, 3 fois chacune (90) ...
            for rep in range(3):
                for w in ("fw", "ss"):
                    for diff in range(5):
                        for p in PROFILES:
                            jobs.append({"mode": "raid", "map": MAPS[w], "difficulty": diff, "profile": p,
                                         "seed": base + n})
                            n += 1
            # ... + 10 sur Normal et Difficile.
            for k in range(10):
                w = ("fw", "ss")[k % 2]
                jobs.append({"mode": "raid", "map": MAPS[w], "difficulty": 1 + (k // 2) % 2,
                             "profile": PROFILES[k % 3], "seed": base + n})
                n += 1
        else:
            # Passe B (50) : combinaisons principales (Normal, Difficile), 4 fois + 2.
            for rep in range(4):
                for w in ("fw", "ss"):
                    for diff in (1, 2):
                        for p in PROFILES:
                            jobs.append({"mode": "raid", "map": MAPS[w], "difficulty": diff, "profile": p,
                                         "seed": base + n})
                            n += 1
            for k in range(2):
                jobs.append({"mode": "raid", "map": MAPS["fw"], "difficulty": 3, "profile": PROFILES[k],
                             "seed": base + n})
                n += 1
        for j in jobs:
            j["max_time"] = 420
    elif pass_name == "boss":
        n = 0
        for w in ("fw", "ss", "mall"):
            k = 0
            for diff in (1, 2):
                for tier in TIERS:
                    reps = 4 if tier == "equipe" or (tier == "moyen" and diff == 1) else 3
                    for r in range(reps):
                        if k >= 20:
                            break
                        jobs.append({"mode": "boss", "map": MAPS[w], "difficulty": diff, "tier": tier,
                                     "profile": "agressif", "seed": 9000 + n, "max_time": 480})
                        n += 1
                        k += 1
    elif pass_name == "duel":
        n = 0
        for w, kinds in ELITES.items():
            for kind in kinds:
                for r in range(10):
                    jobs.append({"mode": "duel", "map": MAPS[w], "difficulty": 1, "enemy": kind,
                                 "tier": "moyen" if r < 5 else "equipe", "profile": "prudent",
                                 "seed": 7000 + n, "max_time": 240})
                    n += 1
    elif pass_name == "smoke":
        jobs = [{"mode": "raid", "map": MAPS["fw"], "difficulty": 1, "profile": "fouilleur", "seed": 11,
                 "max_time": 60}]
    for i, j in enumerate(jobs):
        j["id"] = "%s_%03d_%s_%s_d%d_%s" % (pass_name, i, j["mode"], j["map"].replace("perm_", ""),
                                             j["difficulty"], j.get("enemy") or j.get("tier") or j["profile"])
    return jobs


def find_godot(arg: str) -> str:
    for c in (arg, os.environ.get("GODOT", ""), shutil.which("godot") or ""):
        if c and os.path.exists(c):
            return c
    sys.exit("Godot introuvable : --godot CHEMIN ou variable GODOT")


def run_job(godot: str, root: str, pass_name: str, job: dict, timeout: int) -> dict:
    out = os.path.join(root, pass_name, job["id"] + ".json")
    if os.path.exists(out):
        return {"id": job["id"], "status": "deja"}
    home = os.path.join(root, "_homes", job["id"])
    os.makedirs(home, exist_ok=True)
    args = [godot, "--headless", "--path", ROOT, "--fixed-fps", "60", "-s",
            "res://tools/playtest/playtest_main.gd", "--",
            "--mode=" + job["mode"], "--map=" + job["map"], "--difficulty=%d" % job["difficulty"],
            "--profile=" + job.get("profile", "prudent"), "--seed=%d" % job["seed"],
            "--max-time=%d" % job.get("max_time", 300), "--out=" + out]
    if job.get("tier"):
        args.append("--tier=" + job["tier"])
    if job.get("enemy"):
        args.append("--enemy=" + job["enemy"])
    # Dossier de données Godot propre à la partie (Linux : XDG_DATA_HOME ; Windows : APPDATA).
    env = dict(os.environ, XDG_DATA_HOME=home, APPDATA=home)
    last = ""
    for attempt in range(2):
        t0 = time.time()
        try:
            p = subprocess.run(args, env=env, capture_output=True, text=True, timeout=timeout)
            last = (p.stdout + p.stderr)[-3000:]
        except subprocess.TimeoutExpired as e:
            last = "délai dépassé (%d s)" % timeout
        if os.path.exists(out):
            shutil.rmtree(home, ignore_errors=True)
            return {"id": job["id"], "status": "ok", "real_s": round(time.time() - t0, 1)}
    shutil.rmtree(home, ignore_errors=True)
    return {"id": job["id"], "status": "echec", "log": last}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--pass", dest="pass_name", required=True)
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--max-jobs", type=int, default=2, help="plafond de parallélisme (2 par défaut, cf. brief)")
    ap.add_argument("--godot", default="")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--only", default="")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    jobs = plan(a.pass_name)
    if a.only:
        jobs = [j for j in jobs if a.only in j["id"]]
    if a.list:
        for j in jobs:
            print(j["id"])
        print(len(jobs), "parties")
        return
    godot = find_godot(a.godot)
    os.makedirs(os.path.join(a.root, a.pass_name), exist_ok=True)
    with open(os.path.join(a.root, a.pass_name, "_plan.json"), "w") as f:
        json.dump(jobs, f, indent=1)
    todo = [j for j in jobs if not os.path.exists(os.path.join(a.root, a.pass_name, j["id"] + ".json"))]
    print("%s : %d parties, %d à jouer, %d en parallèle" % (a.pass_name, len(jobs), len(todo), a.jobs), flush=True)
    fails = []
    done = 0
    with ThreadPoolExecutor(max_workers=max(1, min(a.jobs, a.max_jobs))) as ex:
        for r in ex.map(lambda j: run_job(godot, a.root, a.pass_name, j, a.timeout), todo):
            done += 1
            print("[%d/%d] %s %s %s" % (done, len(todo), r["id"], r["status"], r.get("real_s", "")), flush=True)
            if r["status"] == "echec":
                fails.append(r)
    fpath = os.path.join(a.root, a.pass_name, "_echecs.json")
    with open(fpath, "w") as f:
        json.dump(fails, f, indent=1)
    print("terminé : %d échecs" % len(fails))


if __name__ == "__main__":
    main()
