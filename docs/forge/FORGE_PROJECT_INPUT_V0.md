# FORGE PROJECT INPUT — V0

Date : 2026-08-29 · Statut : **décisions du sas ratifiées Pierre 2026-08-29** (verdicts GO du sas
Project Input) ; la forme fine du schéma reste ouverte au sas suivant.
Référence normative : `docs/forge/FORGE_DESIGN_FREEDOM_SPEC_V0.md` — **ratification
séparée mais référencée** (décision Pierre). Hiérarchie :

```
FORGE_DESIGN_FREEDOM_SPEC_V0     — définit les règles disponibles (N1..N9)
        ▼
project_brief.yaml               — sélectionne/instancie pour CE projet + paramètres propres
        ▼
s0                               — transforme Brief → Charter (provenance tracée)
        ▼
charter → full_content → build + preuves
```

Le Brief n'est **pas une deuxième spec** : il ne redéfinit jamais une règle, il la **cite**.

## 1. L'artefact canonique — unique entrée projet

- Chemin : `lab/forge_briefs/<projet>/project_brief.yaml` (ratifié).
- Le profil de chaîne (`full_content`, …) est un **paramètre de lancement**, jamais un champ du Brief.
- `project_input + profile → RUN` ; la sortie est le dossier de preuves du run (PROJECT OUTPUT).

## 2. Schéma V0 (les champs ; la forme fine = prochain sas)

```yaml
projet: <slug>
intention: >            # ce qu'on cherche à obtenir/apprendre (produit OU expérience)
contraintes:
  normative_refs:       # règles issues de la spec canonique — CITÉES, jamais recopiées
    - spec: FORGE_DESIGN_FREEDOM_SPEC_V0
      rules: [N1, N2, N6]
  project_specific:     # décisions propres à CE projet
    techniques: [...]
    experimentales: [...]
cible: <plateforme>     # web/HTML, Godot, ...
references_autorisees:  # reference_jeu + docs design autorisés — SOURCE obligatoire par entrée
  - {ref: ..., source: "Pierre 2026-XX-XX"}   # source absente = FAIL ; fog explicite autorisé
criteres_sortie: [...]  # ce que le PROJECT OUTPUT doit contenir pour être recevable
libertes_deleguees: [...]  # liste EXPLICITE de ce que la chaîne décide seule
provenance:             # qui a écrit chaque champ, date, ratifié par qui — jamais fabriqué
```

Question à laquelle l'oracle doit savoir répondre pour toute contrainte : **vient-elle d'une règle
normative connue, d'une décision propre au projet, ou de nulle part ?** « De nulle part » (une
contrainte hors des deux bacs, une `normative_ref` vers une spec/règle inconnue) = **FAIL/BLOCKED**,
jamais une invention de l'agent.

## 3. Enforcement mécanique (fail-closed)

- **`check_project_brief`** (`forge.static_oracles`) : oracle déterministe non-LLM — champs requis
  non vides, aucun « à définir », `normative_refs` résolues contre le registre des specs connues,
  `references_autorisees` chacune avec source, provenance par champ. Même doctrine que
  `check_charter` : FAIL honnête avec raisons, jamais d'exception.
- **Pré-vol** (`run_real.py`) : pour tout profil dont l'ordre contient `s0-contrat` (chaîne qui
  DÉMARRE un projet), le Brief canonique doit exister ET passer `check_project_brief` **avant toute
  dépense LLM** — sinon exit 1, même étage que l'enregistrement d'oracle. Les profils sans s0
  (patch, micro, proof_only, …) ne changent pas : ils opèrent sur un projet existant.
- **Câblage s0** : le Brief est injecté ENTIER dans le prompt s0 comme **source de commande
  unique**, sha256 au manifest d'exécution. Le charter produit trace chaque design-intent au Brief
  (règle N2 de la spec référencée).

## 4. Entrées alternatives INTERDITES

| Entrée | Statut | Enforcement |
|---|---|---|
| Prose de conversation comme spec | interdite | doctrinal (s0 : « seule source = Brief ») + revue |
| `--task-*` / `--tasks-file` portant du design-intent | interdits pour le design | doctrinal — réservés aux consignes d'exécution (reprise, timeout, périmètre) |
| Fichier `design/` non listé dans `references_autorisees` | interdit | mécanique (sas suivant : filtrage de l'injection design/ sur la liste du Brief) |
| Charter pré-existant comme entrée | interdit — le charter est une SORTIE de s0 | mécanique (pré-vol) |
| Artefacts résiduels d'un run précédent | interdits | mécanique (garde `stale_run_dir`, extension au sas suivant) |

L'honnêteté de cette table est volontaire : ce qui n'est pas encore mécanisé est marqué doctrinal,
jamais présenté comme une garde qui existerait déjà.

## 5. Décisions du sas (ratifiées Pierre 2026-08-29)

`project_brief.yaml` GO · emplacement `lab/forge_briefs/<projet>/` GO · `check_project_brief`
pré-vol fail-closed GO · s0 transformateur Brief→Charter GO · profil = paramètre de lancement GO ·
entrées alternatives interdites GO · ratification séparée-mais-référencée avec la spec V0 ·
matérialisation (doc + schéma + oracle + câblage) GO · **fiches 3/5 et RUN 1 : GELÉES** ·
clé unique `asset_resolution.requests` (l'ambiguïté `resolutions|requests` de la fiche 2 est
supprimée).

## 6. Statuts

| Surface | Statut |
|---|---|
| Doc + hiérarchie normative | IMPLEMENTED (ce document) |
| `check_project_brief` + pré-vol + câblage s0 | à implémenter (paquet en cours) |
| Forme fine du schéma | prochain sas |
| Fidélité charter→build (N6) | UNKNOWN — identifié, hors périmètre de ce sas |

claim_verdict: NO_CLAIM_ALLOWED
