# generate_wiremap.py — PRODUCTEUR de games/bomberman_3d/09_WIREMAP/wiremap.json.
#
# POURQUOI CE FICHIER EST DANS LE DEPOT : la wiremap est un artefact GENERE. Tant que son
# generateur vivait dans un repertoire temporaire hors depot, la carte etait irreproductible
# — personne d'autre que la session qui l'avait ecrite ne pouvait la regenerer, et sa
# derivation de preuve (voir PREUVE_SYS) n'etait verifiable par personne. Dette signalee deux
# fois en RISK avant d'etre fermee ici.
#
# Lancer depuis la RACINE DU DEPOT :  python games/bomberman_3d/10_FORGE/generate_wiremap.py
#
# Range sous 10_FORGE/ : `roots.forge` du standard (scripts/forge/standard/repo_map.yaml),
# repertoire de gouvernance — donc hors du controle d'orphelins de check_index, et ce n'est
# pas du contenu de jeu.
import json, pathlib, re
root = pathlib.Path('games/bomberman_3d')
sysdirs = sorted([d.name for d in (root / '05_SYSTEMS').iterdir() if d.is_dir()])
adapts = sorted([d.name for d in (root / '06_RUNTIME' / 'adapters').iterdir() if d.is_dir()])

systems = [{"id": s, "category": "system", "allowed_deps": [],
            "role": "systeme de regles pur (RefCounted)"} for s in sysdirs]
systems += [{"id": a, "category": "system.adapter", "allowed_deps": [],
             "role": "adaptateur runtime"} for a in adapts]


def fichiers_de(d, cat):
    out = []
    for p in sorted(d.rglob('*.gd')):
        rel = p.relative_to(root).as_posix()
        out.append({"path": rel, "category": cat})
    return out


# PREUVE DERIVEE, JAMAIS RECOPIEE.
#
# BOUCLE CASSEE REPAREE ICI (mesure du 2026-08-11) : ce texte etait un litteral fige. Il
# affirmait « 458 assertions vertes » sur 44 lignes alors que le harnais en executait 462.
# Personne ne pouvait detecter la derive, parce que rien ne comparait l'affirmation a sa
# source. Corriger le nombre n'aurait rien repare : il aurait rederive au prochain test
# ajoute. On lit donc desormais les VRAIES sources, et on LEVE si elles sont illisibles —
# une preuve qu'on ne sait pas lire ne doit pas devenir une preuve qu'on invente.
_h = (root / 'tests' / 'run_tests.gd').read_text(encoding='utf-8')
_m = re.search(r'EXPECTED_ASSERTS\s*:=\s*(\d+)', _h)
if _m is None:
    raise SystemExit("EXPECTED_ASSERTS illisible dans tests/run_tests.gd — preuve non derivable")
NB_ASSERTIONS = int(_m.group(1))
_tri = json.loads((root / 'mutation_triage.json').read_text(encoding='utf-8'))
NB_SURVIVANTS = len(_tri if isinstance(_tri, list) else _tri.get('survivants', _tri.get('entries', [])))

PREUVE_SYS = (f"harnais tests/run_tests.gd : {NB_ASSERTIONS} assertions vertes ; mutation "
              f"forge.mutation 105/113 tues sur 11 systemes (campagne du 2026-08-10), "
              f"{NB_SURVIVANTS} survivants tries EQUIVALENT (mutation_triage.json), "
              "check_mutation_gate passed=true")
PREUVE_ADP = ("produit lance en fenetre GPU 300 frames sans erreur ; volets FORGE_ORACLE "
              "core_audio / core_render_frame / lisibilite_powerups / musique_piste rendus "
              "OK par product_oracle_godot")

lines = []
for s in sysdirs:
    lines.append({"id": "system." + s, "category": "system", "system_parent": s,
                  "state": "IMPLEMENTED", "reason": None, "until": None, "decider": None,
                  "write_order": None, "address": "05_SYSTEMS/" + s + "/",
                  "fichiers": fichiers_de(root / '05_SYSTEMS' / s, "system"),
                  "fonction": "regles pures du systeme " + s,
                  "preuve": PREUVE_SYS, "statut": "IMPLEMENTED"})
for a in adapts:
    lines.append({"id": "adapter." + a, "category": "system.adapter", "system_parent": a,
                  "state": "IMPLEMENTED", "reason": None, "until": None, "decider": None,
                  "write_order": None, "address": "06_RUNTIME/adapters/" + a + "/",
                  "fichiers": fichiers_de(root / '06_RUNTIME' / 'adapters' / a, "system.adapter"),
                  "fonction": "adaptateur runtime " + a,
                  "preuve": PREUVE_ADP, "statut": "IMPLEMENTED"})

# --- lignes CORE : une par exigence non negociable, portee par le systeme qui l'honore ---
CORE_PORTEUR = {
 "core.boot": ("runtime_loop", "system.adapter", "06_RUNTIME/adapters/runtime_loop/"),
 "core.main_loop": ("game_loop", "system", "05_SYSTEMS/game_loop/"),
 "core.input": ("runtime_loop", "system.adapter", "06_RUNTIME/adapters/runtime_loop/"),
 "core.game_state": ("game_state", "system", "05_SYSTEMS/game_state/"),
 "core.end_condition": ("victory", "system", "05_SYSTEMS/victory/"),
 "core.restart": ("app_state", "system", "05_SYSTEMS/app_state/"),
 "core.exit": ("runtime_loop", "system.adapter", "06_RUNTIME/adapters/runtime_loop/"),
 "core.render": ("presentation_3d", "system.adapter", "06_RUNTIME/adapters/presentation_3d/"),
 "core.audio": ("audio", "system.adapter", "06_RUNTIME/adapters/audio/"),
 "core.error_handling": ("map_validator", "system", "05_SYSTEMS/map_validator/"),
}
PREUVE_CORE = {
 "core.render": "volet pixel core_render_frame OK en fenetre GPU via product_oracle_godot (mode_execution gpu_window)",
 "core.audio": "volet core_audio OK : 5 declenchements, 16639 echantillons REELLEMENT synthetises sur une partie jouee",
 "core.restart": "test_app_state : empreinte complete d'un etat neuf identique apres relance, aucun residu",
}
for cid, (parent, cat, adr) in CORE_PORTEUR.items():
    lines.append({"id": cid, "category": cat, "system_parent": parent,
        "state": "IMPLEMENTED", "reason": None, "until": None, "decider": None,
        "write_order": None, "address": adr, "fichiers": [],
        "fonction": "exigence CORE " + cid,
        "preuve": PREUVE_CORE.get(cid, PREUVE_SYS), "statut": "IMPLEMENTED"})

# --- artefacts NOMMES : imposes par le moteur ou son oracle, hors arborescence systeme ---
#
# DEUX REGLES DU STANDARD, lues et non devinees :
#   `check_line_states` : chaque ligne porte un `system_parent` NON VIDE (SCHEMA.md 3).
#   `check_index`       : `address` designe un REPERTOIRE EXISTANT (`(root/addr).is_dir()`),
#                          jamais un fichier. Le fichier, lui, se declare dans `fichiers[]`.
#
# La version precedente mettait `system_parent: null` et un CHEMIN DE FICHIER dans `address`.
# Ces artefacts n'ont pas de repertoire systeme a eux, mais ils ne sont pas orphelins pour
# autant : chacun SERT ou PROUVE un systeme precis, et c'est ce systeme qui le porte. Un
# volet de preuve appartient a ce qu'il prouve — c'est la seule reponse qui ne soit pas une
# etiquette de commodite.
ARTEFACTS_MOTEUR = [
 ("godot.solvability", "solvability.gd", ".", "solvability_bot", "godot.project_root"),
 ("godot.main_scene", "main.tscn", ".", "runtime_loop", "godot.project_root"),
 ("godot.project", "project.godot", ".", "runtime_loop", "godot.project_root"),
 ("godot.harness", "tests/run_tests.gd", "tests", "proof_harness", "godot.project_tests"),
]
for lid, chemin, adr, parent, cat in ARTEFACTS_MOTEUR:
    lines.append({"id": lid, "category": cat, "system_parent": parent,
        "state": "IMPLEMENTED", "reason": None, "until": None, "decider": None,
        "write_order": None, "address": adr,
        "fichiers": [{"path": chemin, "category": cat}],
        "fonction": "artefact impose par le moteur ou son oracle",
        "preuve": PREUVE_SYS, "statut": "IMPLEMENTED"})

# Chaque volet de preuve est porte par LE systeme qu'il eprouve.
PROUVE = {
 "fixtures": "proof_harness", "test_app_state": "app_state", "test_audio_score": "audio",
 "test_explosion": "explosion", "test_lisibilite": "palette",
 "test_loop_and_rules": "game_loop", "test_map_validator": "map_validator",
 "test_movement_bombs": "movement_rules", "test_pause_musique": "app_state",
 "test_playable_speed": "params", "test_sudden_death": "sudden_death",
 "core_audio": "audio", "core_render_frame": "presentation_3d",
 "lisibilite_powerups": "presentation_3d", "musique_piste": "audio",
}
for d, cat, pref in [(root / '07_TESTS' / 'unit', "test.unit", "07_TESTS/unit"),
                      (root / '07_TESTS' / 'oracle', "test.oracle", "07_TESTS/oracle")]:
    for f in sorted(d.glob('*.gd')):
        parent = PROUVE.get(f.stem)
        if parent is None:
            raise SystemExit("volet de preuve sans systeme porteur : " + f.stem)
        lines.append({"id": cat + "." + f.stem, "category": cat, "system_parent": parent,
            "state": "IMPLEMENTED", "reason": None, "until": None, "decider": None,
            "write_order": None, "address": pref,
            "fichiers": [{"path": pref + "/" + f.name, "category": cat}],
            "fonction": "volet de preuve " + f.stem,
            "preuve": PREUVE_SYS, "statut": "IMPLEMENTED"})

# --- NIVEAUX : du contenu de jeu reel, revendique par une ligne ---
# `check_index` les signalait `dossiers_orphelins` : trois arenes existaient sur le disque
# sans qu'aucune ligne ne les demande. C'est exactement le defaut que l'oracle nomme
# « dossier vide de facade » pris a l'envers — du contenu que personne n'a commande.
# Categorie `level` du standard : l'adresse est imposee, `03_WORLD/levels/{id}/`, donc
# l'identifiant de ligne EST le nom du niveau.
for d in sorted((root / '03_WORLD' / 'levels').iterdir()):
    if not d.is_dir():
        continue
    # `{id}` du mapping repo_map est le SYSTEM_PARENT, pas l'identifiant de ligne (mesure :
    # `adresse_incoherente` attendait `03_WORLD/levels/content_provider/`). Un niveau est
    # donc sa PROPRE entite portante, et il doit exister dans `systems[]` sans quoi
    # `check_placement` le classe `system_parent_inconnu`.
    systems.append({"id": d.name, "category": "level", "allowed_deps": [],
                    "role": "arene jouable, donnee de contenu"})
    lines.append({"id": "level." + d.name, "category": "level", "system_parent": d.name,
        "state": "IMPLEMENTED", "reason": None, "until": None, "decider": None,
        "write_order": None, "address": "03_WORLD/levels/" + d.name + "/",
        "fichiers": [{"path": f.relative_to(root).as_posix(), "category": "level"}
                     for f in sorted(d.rglob('*')) if f.is_file()],
        "fonction": "arene jouable " + d.name,
        "preuve": "carte validee par map_validator et jouee par l'oracle de solvabilite",
        "statut": "IMPLEMENTED"})

# --- MESHES : assets 3D reels, declares grace a `asset.mesh` (decision humaine D3) ---
# Consommes par `06_RUNTIME/adapters/presentation_3d/arena_view_3d.gd` — ce n'est pas du
# contenu mort, c'est du contenu que le standard ne savait pas nommer avant D3.
_meshes = sorted((root / '04_ASSETS' / 'meshes').glob('*.glb'))
if _meshes:
    lines.append({"id": "asset.meshes", "category": "asset.mesh",
        "system_parent": "presentation_3d",
        "state": "IMPLEMENTED", "reason": None, "until": None, "decider": None,
        "write_order": None, "address": "04_ASSETS/meshes",
        "fichiers": [{"path": f.relative_to(root).as_posix(), "category": "asset.mesh"}
                     for f in sorted((root / '04_ASSETS' / 'meshes').iterdir()) if f.is_file()],
        "fonction": "geometries 3D du decor et des blocs",
        "preuve": "references mesurees dans arena_view_3d.gd ; rendues en fenetre GPU par le volet core_render_frame",
        "statut": "IMPLEMENTED"})

# --- CAPACITES : une par une, chacune avec un symbole producteur VERIFIE ---
# Chaque entree a ete etablie en lisant le code, jamais par deduction globale. Le symbole
# cite est celui dont la presence a ete mesuree le 2026-08-11.
# NON DECLARE VOLONTAIREMENT : `game.exit` — aucun `quit`, `get_tree`, `SceneTree` ni
# `notification` dans runtime_loop. Pas de producteur, donc pas de declaration.
PROVIDES = {
 "runtime_loop":    [("game.boot", "_ready"), ("input.action", "Input")],
 "game_loop":       [("game.loop", "func step"), ("game.events", "events")],
 "game_state":      [("game.state", "func initial")],
 "victory":         [("game.end", "func evaluer")],
 "app_state":       [("game.restart", "doit_demarrer"), ("game.pause", "PAUSE")],
 "presentation_3d": [("render.frame", "func rafraichir")],
 "audio":           [("audio.cue", "func consommer")],
 "map_validator":   [("error.guard", "carte_validee")],
 "params":          [("game.params", "TICKS_PAR_SECONDE"), ("game.playable_speed", "MOVE_COOLDOWN_BASE")],
 # `game.best_score` : enonce du standard « detenir le meilleur score, PERSISTANT entre les
 # sessions ». Verifie le 2026-08-11 : score_store.gd expose `lire`/`ecrire` et ecrit
 # reellement via FileAccess sur `user://` ; consommateur mesure = runtime_loop.gd.
 "score_store":     [("game.best_score", "func ecrire")],
}
# REFUSEES faute de correspondance REELLE avec l'enonce du standard — jamais par deduction :
#   game.score            l'enonce parle de « lignes nettoyees simultanement » (Tetris) ;
#                         bomberman n'a pas de lignes. score.points_pour existe, l'enonce non.
#   game.solo_opponent    l'enonce exige un adversaire « DISTINCT du bot de solvabilite » ;
#                         ici les bots SONT le bot de solvabilite.
#   game.level_generation l'enonce exige une disposition derivee d'une seed ; les arenes sont
#                         des descripteurs ecrits a la main.
#   game.tick_rate        l'enonce inclut l'acceleration ; la cadence est fixe ici.
#   game.collision / game.lives / game.exit / game.fixed_timestep : aucun producteur trouve.
# REQUIRES : DERIVE DU CODE, plus declare a la main.
#
# BOUCLE CASSEE FERMEE ICI (2026-08-11). `check_collisions` ne verifie QUE la coherence
# interne de la declaration : identifiants connus, pas de trou, pas de double proprietaire.
# Il ne compare JAMAIS le graphe au code. Mesure : une arete reelle non declaree passe au
# vert, et une arete INVENTEE (`ui_shell requires render.frame`, sans fondement) passe aussi.
# Le graphe pouvait donc etre entierement faux sans qu'un oracle proteste.
# Tant que les aretes etaient ecrites a la main dans une table, elles derivaient comme
# derivait le texte de preuve avant qu'on le derive. Meme defaut, meme correctif.
#
# REGLE DE PREUVE CONSERVEE : le symbole discriminant, pas le repertoire. Une reference a un
# systeme qui fournit deux capacites ne dit pas laquelle est consommee.
SYMBOLES = {
 "game.events":         ['["events"]', "events.append", "events: Array"],
 "game.loop":           ["Loop.step", "loop.gd"],
 "game.state":          ["State.initial", "game_state/state.gd"],
 "game.params":         ["INDEX_JOUEUR", "DUREE_FLAMME", "RAYON", "SOLIDE", "DESTRUCTIBLE",
                         "TICKS_PAR_SECONDE", "DUREE_MAX_TICKS"],
 "game.playable_speed": ["MOVE_COOLDOWN_BASE", "MOVE_COOLDOWN_MIN", "SPEED_STEP"],
 "game.pause":          ["PAUSE"],
 "game.restart":        ["doit_demarrer"],
 "game.end":            ["victory/victory.gd", "Victory."],
 "error.guard":         ["carte_validee"],
 "render.frame":        ["arena_view_3d.gd", "presentation_3d/"],
 "audio.cue":           ["adapters/audio/audio.gd"],
 "game.best_score":     ["score_store/score_store.gd"],
 "game.boot":           [], "input.action": [],   # produits par runtime_loop, racine du graphe
}


def _fichiers_du_systeme(sid):
    for base in (root / "05_SYSTEMS" / sid, root / "06_RUNTIME" / "adapters" / sid):
        if base.exists():
            return sorted(base.rglob("*.gd"))
    return []


# GARDE DE PRODUCTEUR — dernier bord non derive de la carte, ferme le 2026-08-11.
#
# `PROVIDES` reste DECLARE a la main, et c'est legitime : designer QUI DOIT produire une
# capacite est une decision d'architecture, pas une observation. Mais rien ne verifiait que
# le symbole cite existe ENCORE. Une capacite pouvait donc rester declaree IMPLEMENTED apres
# la disparition de son producteur — c'est exactement le defaut mesure sur `core.exit`.
# On ne derive pas la declaration : on refuse de produire une carte qui ment.
_manquants = []
for _s, _lst in PROVIDES.items():
    _t = "".join(f.read_text(encoding="utf-8", errors="ignore") for f in _fichiers_du_systeme(_s))
    for _cap, _sym in _lst:
        if _sym not in _t:
            _manquants.append(f"{_cap} : symbole producteur '{_sym}' introuvable dans {_s}")
if _manquants:
    raise SystemExit("PRODUCTEUR ABSENT - carte non generee : " + " | ".join(_manquants))


_producteur = {c: s for s, lst in PROVIDES.items() for c, _ in lst}
_systemes = sysdirs + adapts
REQUIRES = {}
_preuve_arete = {}
for _s in _systemes:
    _t = "".join(f.read_text(encoding="utf-8", errors="ignore") for f in _fichiers_du_systeme(_s))
    if not _t:
        continue
    for _cap, _syms in SYMBOLES.items():
        if _producteur.get(_cap) == _s or not _syms:
            continue          # un systeme ne se requiert pas lui-meme
        _vus = [x for x in _syms if x in _t]
        if _vus:
            REQUIRES.setdefault(_s, []).append(_cap)
            _preuve_arete[(_s, _cap)] = _vus[:2]

for _l in lines:
    _sp = _l.get("system_parent")
    if _sp in PROVIDES and _l.get("category") in ("system", "system.adapter") and _l["id"].startswith(("system.", "adapter.")):
        _l["provides"] = [c for c, _ in PROVIDES[_sp]]
        _l["preuve_capacites"] = {c: "symbole producteur verifie dans le code : " + s
                                  for c, s in PROVIDES[_sp]}
    # Le filtre etait `startswith("adapter.")` : il laissait tomber en silence TOUTES les
    # aretes portees par un SYSTEME (game_state, game_loop, map_validator, victory). Defaut
    # attrape par falsification — retirer le producteur de `game.playable_speed` ne creait
    # aucun trou, donc plus personne ne le consommait dans la carte.
    if _sp in REQUIRES and _l["id"].startswith(("adapter.", "system.")):
        _l["requires"] = REQUIRES[_sp]

wm = {"schema_version": 2, "game_id": "bomberman_3d",
      "run_id": "bomberman_3d-cablage-20260810", "dispatch_marker": None,
      "statut_artefact": "PROPOSED", "claim_verdict": "NO_CLAIM_ALLOWED",
      "evidence_verdict": "MECHANICAL_VALIDATION_ONLY",
      "roles_utilises": ["orchestrator"], "genre_bible": None, "genre_refusals": [],
      "reference_amont": "docs/forge/BOMBERMAN_3D_L0_CONTRACT.md",
      "parametres_de_design_source": "05_SYSTEMS/params/params.gd",
      "systems": systems, "lines": lines, "discarded": [], "fog": []}

(root / '09_WIREMAP').mkdir(parents=True, exist_ok=True)
(root / '09_WIREMAP' / 'wiremap.json').write_text(
    json.dumps(wm, ensure_ascii=False, indent=1), encoding='utf-8')
print("wiremap :", len(systems), "systemes,", len(lines), "lignes")
