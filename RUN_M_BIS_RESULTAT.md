# RUN M bis — RÉSULTAT

*2026-09-02 · second run réel du Studio V2, après les lots B · C-1 · C-2 · D-1 · D-2.
**V1 non modifié** : `58095ba9`, 76 écarts — identiques au snapshot d'ouverture de session.
Toutes les affirmations ci-dessous sont **re-vérifiées et reproduites** par mes soins.*

```
RUN M      6 étapes / 13 · HALT à s6 · aucun jeu
RUN M bis  9 étapes / 13 · HALT à s10a · UN JEU QUI SE CHARGE ET SE JOUE
7,60 $ · 2 056 s · run_status HALTED · decision BLOCKED
```

| étape | RUN M | M bis | |
|---|---|---|---|
| s0-contrat | OK (att. 2) | **OK att. 1** | `check_charter` PASS |
| s2 · s1 · s3 · s4 | OK | **OK** | tous oracles amont à 0 problème |
| s5-wiremap | OK / jointure VIDE | **OK / JOINED 17-17** | voir §2 |
| **s6-redteam-plan** | **HALT** `unrecognized_model` | **OK — runner `qwen`** | voir §1 |
| **s9-build** | non atteinte | **OK** | **`GAMES/runm_breakout/` — 14 fichiers** |
| s10a-oracle-code | non atteinte | **BLOCKED** | voir §3 |

---

## 1 · Les lots ont fait ce qu'ils annonçaient

```
s6-redteam-plan   runner = qwen   reviewer = qwen2.5-14b-instruct   qwen_ok = True
route_degradation ABSENT sur les 8 étapes LLM exécutées
```
**Lot B tient hors des tests** : l'adaptateur extrait a porté la chaîne réelle jusqu'au bout.
**C-1 fonctionne aussi par son silence** : `route_degradation` absent partout signifie *aucune
dégradation* — avant ce lot, l'absence ne voulait rien dire, puisque le champ n'était jamais écrit.

## 2 · La jointure tient — mais D-1 n'a **pas** été exercé

```
join_check                      JOINED · 17/17 · 0 fantôme · forme_satisfaite true
join_check_apres_reparation     JOINED · identique champ à champ · ecart_avec_avant null
repair                          OK_SANS_REPARATION · 0 cycle · 0 token · 0 champ écrit
```

> **L'agent a couvert les 17 capacités correctement, du premier coup. La boucle n'a rien eu à
> faire.** Les deux reçus sont identiques parce qu'**il ne s'est rien passé entre eux**.

**Je ne compte donc pas D-1 comme prouvé.** C'est la première issue de la liste que j'avais posée
avant le run — *l'agent couvre correctement* — c'est-à-dire de la **variance**, pas la
démonstration que le déplacement du défaut est fermé. La correction est en place, testée
unitairement, **et toujours pas mise à l'épreuve en conditions réelles**.
**D-2, lui, est exercé** : les deux reçus existent et sont lisibles. Ici ils disent la même chose ;
c'est leur travail de le dire quand c'est vrai.

## 3 · La nouvelle cause d'arrêt — un défaut d'encodage, reproduit

```python
# forge/oracle.py:122   l'oracle du jeu
completed = subprocess.run(spec.command, cwd=..., capture_output=True, text=True, timeout=...)
                                                                       ^^^^^^^^^ sans encoding
# forge/oracle.py:183 · :214 · :266   les TROIS autres appels du MÊME fichier
cp = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", ...)
```

**Reproduit sur ce poste** (locale `cp1252`) :
```
text=True seul        UnicodeDecodeError: byte 0x90 — stdout is None  -> fh.write(None) -> TypeError -> HALT
+ encoding="utf-8"    892 caractères, exit 0
```
L'octet fautif vient du cadre `╔═══╗` que **le jeu lui-même** imprime.

**Et l'oracle du jeu, lancé à la main, PASSE :**
```
VOLET 1 logique       6 tests
VOLET 2 solvabilité   SOLVABLE — un bot gagne, plan trouvé, score 480
RÉSULTAT GLOBAL: PASS
```
> **s10a aurait été VERT.** La chaîne n'a pas buté sur un défaut du jeu : elle a buté sur sa propre
> lecture de la sortie. Trois `subprocess.run` sur quatre respectent la règle `CLAUDE.md`
> (« encoding='utf-8' explicite ») ; le quatrième ne la respecte pas.

**Ce n'est pas une régression de migration** : `forge/oracle.py` est identique à V1 hors chemins.
Le défaut est **latent depuis V1 et dépend de la locale du shell de lancement** — il ne s'était
jamais manifesté parce qu'aucun run V1 n'avait été lancé depuis un shell `cp1252`.

## 4 · Le jeu — ce qui est mesuré, et ce qui ne l'est pas

```
GAMES/runm_breakout/   14 fichiers
  index.html · main · engine · progression · rng · render · input · hud (.mjs)
  run-oracle.mjs · solvability.mjs · e2e.mjs · reuse_ratio.mjs · server.mjs · BUILD_REPORT.md
```

**SE CHARGE : oui.** Canvas, 40 briques, HUD, `window.__game` exposé, 0 erreur console, 114 frames
en 1,5 s.
**SE JOUE : partiellement.** Raquette pilotée au clavier (amplitude 360 px), 10 renvois de balle,
score 0 → 70, 3 vies conservées, « Rejouer » fonctionne. Défaite observée sans joueur.
**Victoire : NON ATTEINTE en 20 s — non mesurée.**

*Une mesure a été invalidée en cours de route par Fable et je le relaie : la première observation
« raquette immobile » venait du pane navigateur de session (0 frame rAF, pane masqué) — **un
artefact d'instrument**, pas un défaut du jeu.*

## 5 · Trois défauts HÉRITÉS, rendus visibles par ce run

| # | | statut |
|---|---|---|
| **A** | **s6 est un OK par construction** : `blocked, findings = False, []` n'est jamais réassigné sur le chemin Qwen. L'artefact est un plan au futur, sans revue. Profil **identique sur `p1_beta`, `p2_beta`, `p3_alpha` en V1** | hérité — pas une régression |
| **B** | **le jeu produit porte son propre « déclaré ≠ exécuté »** : `run-oracle.mjs` annonce « Logic + Solvabilité + **E2E** » et **saute l'E2E en dur** (Playwright non résoluble). Le verdict global dit `PASS` | à traiter — c'est le motif du studio, reproduit par la chaîne dans son produit |
| **C** | **deux reçus `ESCALADE` à 0 réparation** (s3) avec 3 signaux `DISCRIMINANCE` — **aucun lecteur décisionnel**. L'étape est OK par absence de lecteur, pas par jugement | 9ᵉ occurrence du motif |

*Sur C, je corrige une de mes propres mesures : j'avais contre-mesuré « 15 lecteurs Python de
`REPARE` » — c'était `EVENT_PREPARED`, une correspondance de sous-chaîne. Fable avait raison.*

---

## Ce que RUN M bis prouve, et ce qu'il ne prouve pas

**Prouvé** — la chaîne migrée va de la vision au **jeu jouable** : 9 étapes, 14 fichiers de jeu,
oracle du jeu vert quand on sait lire sa sortie, jointure tenue, aucune écriture hors surfaces V2,
V1 intact.

**Non prouvé** — aucun verdict signé (`verify_run` : « VÉRIFICATION : IMPOSSIBLE »), la clé V2 n'a
jamais servi, **D-1 non exercé**, victoire du jeu non atteinte, E2E jamais exécuté.

**Et toujours rien sur la thèse V2** : ce run a exercé les 13 stations fixes de V1 dans les
surfaces de V2. C'était son objet.

```
status_by_surface:
  lots_B_C_D_tiennent:     TESTED   # s6 sur qwen, route_degradation absent, 2 reçus
  jointure_JOINED:         TESTED   # 17/17, avant = après
  D1_exerce:               NOT_MEASURED  # aucune réparation n'a eu lieu
  cause_arret_reproduite:  TESTED   # text=True sans encoding -> stdout None
  oracle_du_jeu_vert:      TESTED   # PASS, SOLVABLE, lancé à la main
  jeu_se_charge:           TESTED
  jeu_se_joue:             PARTIEL  # victoire non atteinte
  verdict_signe:           NOT_FOUND
  v1_intact:               TESTED   # 58095ba9, 76 écarts = snapshot d'ouverture
```
`software_verdict: BLOCKED` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
