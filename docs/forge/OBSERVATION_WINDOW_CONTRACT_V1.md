# OBSERVATION_WINDOW_CONTRACT_V1

*2026-08-04. Le pré-requis bloquant de `RUNTIME_DRIFT_ORACLE_CONTRACT_V1`, tranché.
Implémenté dans `scripts/forge/runtime_inventory_oracle.py` (`ObservationWindow`).*

---

## Pourquoi une fenêtre est obligatoire

Sans elle, **« jamais observé » veut dire « jamais cherché »**.

La preuve n'est pas théorique, elle a été vécue aujourd'hui :

```
repair_runtime   15h00  →  DECLARED_NOT_OBSERVED
repair_runtime   18h00  →  DECLARED_AND_OBSERVED
```

Rien n'avait changé dans le code entre les deux. Seule la trace était apparue. Un oracle
qui aurait conclu « rôle mort » à 15 h se serait trompé de trois heures.

## Définition

```yaml
observation_window:
  days:     int | null     # null = tout l'historique disponible
  projects: [str]          # [] = tous les projets observés
  sources:  ["lab/reports/observer/*/events.jsonl"]
```

**Sources incluses** : uniquement les `events.jsonl` de l'Observer — c'est-à-dire des
reçus signés (`dispatch.prepared` / `spawn_executed`) et des traces mécaniques
(`repair.result`). **Exclus** : la documentation, les YAML, le code, les rapports de
session. Une déclaration n'est jamais une observation.

**Projets concernés** au 2026-08-04 : `breakout_v2`, `pong`, `tetris`, `p5_gridnav`,
`repair_runtime_v1`. Ce sont ceux qui ont tourné — pas un échantillon choisi.

## Les trois états, à ne jamais confondre

| état | condition | lecture |
|---|---|---|
| `observed` | ≥ 1 événement **dans** la fenêtre | ça a tourné, récemment |
| `observed_outside_window` | des événements existent, tous **hors** fenêtre | ça a tourné, plus depuis |
| `never_observed` | aucun événement, quelle que soit la fenêtre | jamais vu — pas forcément mort |

À quoi s'ajoute une quatrième information, portée par `declared_at` (date du commit qui a
introduit le rôle dans `roles.yaml`, `null` si non commité) :

```
declared_at récent + never_observed   →  normal, personne n'a encore eu l'occasion
declared_at ancien + never_observed   →  question légitime
```

## Interdiction absolue

```
DECLARED_NOT_OBSERVED  ≠  mort
```

La sortie porte `requires_observation_window: true` sur **chaque** entrée, et le cas est
classé `INFORMATION`, jamais `ALERTE`. Un rôle rare n'est pas un rôle mort ; le studio a
déjà la règle — *gelé ≠ mort*. Aucun gel, aucune suppression, aucun score : la décision
appartient à Pierre.

## État mesuré — fenêtre 30 jours, 2026-08-04

| rôle | `declared_at` | statut |
|---|---|---|
| `art_director` | 2026-07-14 | `never_observed` |
| `forge_toolsmith` | 2026-07-27 | `never_observed` — **20 contrats le déclarent** |
| `orchestrator` | 2026-07-23 | `never_observed` — **descriptif assumé** par `roles.yaml` |
| `run_orchestrator` | 2026-07-23 | `never_observed` |

Aucun `observed_outside_window` aujourd'hui : les 4 non observés le sont *absolument*, pas
par effet de fenêtre. C'est une information plus forte que « hors fenêtre », et c'est
justement parce que la fenêtre existe qu'on peut le dire.

## Limite portée par la fenêtre elle-même

Elle ne mesure que ce qui **passe par la porte**. Un runtime qui s'exécute sans émettre de
reçu est `never_observed` avec la même certitude apparente qu'un rôle réellement inactif —
et c'était le cas de `repair_step.mjs` jusqu'à ce matin. C'est pour ça que le troisième
axe (`observed_code_not_declared`) existe, et pourquoi il ne doit jamais être fusionné
avec celui-ci.
