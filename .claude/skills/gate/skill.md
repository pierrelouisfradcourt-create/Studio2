---
name: gate
description: HumanGate — ratifier ou rejeter une décision (oracle vert + HMAC + sign-off Pierre), puis consigner le verdict daté dans le decision-log versionné (studio_brain/decisions/decision-log.md). Destination ratifiée D4 2026-07-26 (ex-DREAMS.md legacy).
---

# /gate

Le point de souveraineté. Un verdict signé (`/verdict`) n'est qu'une *éligibilité* ; `/gate` est l'acte où **Pierre** ratifie ou rejette, et où la décision devient mémoire institutionnelle dans le **decision-log versionné du repo** (`studio_brain/decisions/decision-log.md`).

> Doctrine : *HumanGate décide merge/reject/freeze — pas Claude Code* (CLAUDE.md).
> Claude prépare le dossier et écrit la trace ; **Pierre seul tranche**.

---

## Phase 1 — Réunir le dossier

Avant de présenter une gate, rassembler les éléments opposables :

```
GATE — <objet> (IMP-XXX / HGD-xxx)
─────────────────────────────────────────────
oracle           : <PASS|FAIL|BLOCKED>   (<reason>)
HMAC             : <OK|INVALIDE|NON_SIGNÉ>
software_verdict : <OK|FAIL|BLOCKED>
evidence_verdict : <MECHANICAL_VALIDATION_ONLY|UNSIGNED>
claim_verdict    : NO_CLAIM_ALLOWED
fichiers touchés : <liste>
zones FORBIDDEN  : <aucune | LISTE — bloqueur>
─────────────────────────────────────────────
recommandation Claude : <MERGE | REJECT | FREEZE>  (RECOMMANDE uniquement)
```

Pré-conditions **dures** pour proposer un MERGE :

- oracle `PASS` **et** HMAC `OK` (sinon → la gate ne peut proposer que REJECT/FREEZE) ;
- aucun fichier dans `tests/ eval/ oracle/ bench/ puzzles/ .github/` ;
- `claim_verdict: NO_CLAIM_ALLOWED` présent.

Si une pré-condition manque → l'afficher comme bloqueur, ne pas présenter MERGE comme option.

---

## Phase 2 — Décision Pierre

Présenter les trois issues. **Attendre le choix explicite de Pierre** — ne jamais auto-ratifier.

| Décision | Effet |
|---|---|
| **MERGE** | La décision est adoptée → consignée `RATIFIÉ` dans le decision-log |
| **REJECT** | La décision est refusée → consignée `REJETÉ` + raison |
| **FREEZE** | Mise en attente (info manquante, fog) → consignée `GELÉ` + ce qui débloque |

Aucune valeur par défaut. Pas de réponse de Pierre = pas de gate franchie.

---

## Phase 3 — Consigner dans le decision-log versionné

Cible : `studio_brain/decisions/decision-log.md` (décision D4, Pierre 2026-07-26 — l'ancienne cible
`studio/openclaw-workspace/DREAMS.md` est LEGACY : ne plus y écrire ; son historique reste
en lecture). Le decision-log stipule « seul Pierre peut ajouter des entrées » : `/gate`
n'y écrit QUE le choix que Pierre vient de prononcer explicitement en session — le
sign-off Pierre (Phase 2) est la précondition absolue de toute écriture.

**Ajouter** (append, jamais réécrire) une entrée datée :

```markdown
## <date> — <objet> (IMP-XXX / HGD-xxx)
- décision   : RATIFIÉ | REJETÉ | GELÉ
- oracle     : <PASS|FAIL|BLOCKED>  ·  HMAC : <OK|…>
- fichiers   : <liste>
- raison     : <justification Pierre / ce qui débloque si GELÉ>
- ratifié par: Pierre — <date>
```

Encodage `utf-8` explicite. Écriture en append : ne **jamais** écraser une entrée existante.

### Cas particulier — objet issu d'une queue Forge (pending_review)

*(Câblage CV-16, mandat exécution Pierre 2026-07-30 — referme le trou « décisions enregistrées jamais appliquées » de l'audit de couche décisionnelle.)*

Si l'objet de cette gate correspond à un item lu via `node scripts/forge/pending_review.mjs`
— **les 6 queues de `QUEUE_FILES` sont désormais décidables** (réparation boucle de revue
2026-08-10 : `MATCH_FIELDS` dérive de `QUEUE_FILES`, plus aucune queue sans règle de
rapprochement) :

1. Après l'append dans le decision-log (ci-dessus), ajouter la même décision en une ligne
   JSONL à `lab/reports/pending_review_decisions.jsonl` :
   `{"ts":"<date>","queue":"<queue>","item":"<item>","decision":"ACCEPT|REJECT","motif":"<raison Pierre>"}`
   - **`<item>` = la colonne `item (à recopier en décision)` de la table**, jamais le sujet ni
     le libellé. C'est le champ `decision_item` du JSON stdout. Recopier une autre colonne
     produit une orpheline garantie — c'était le piège avant le 2026-08-10, où l'écran
     affichait `run_id` pour une queue rapprochée sur `capability_id`.
   - Un item affiché `(AUCUNE CLÉ)` n'est **pas** décidable en l'état : le record ne porte
     aucun champ de rapprochement. Le signaler à Pierre, ne rien inventer.
   - `decision` n'accepte QUE `ACCEPT` ou `REJECT`. Tout autre verbe (`POSTPONE`, `Accept`
     en casse mixte…) est désormais rapporté en `invalid` — il n'est plus silencieusement
     absorbé, mais il n'est pas appliqué pour autant.
2. Lancer d'abord en dry-run : `node scripts/forge/apply_decisions.mjs`
   — relire le JSON stdout (`changes`, `conflicts`, `orphaned`, `invalid`) avant d'appliquer.
3. Si `changes` contient bien l'item attendu et que `conflicts`/`orphaned`/`invalid` sont vides
   pour cet item : `node scripts/forge/apply_decisions.mjs --apply`, puis rapporter à Pierre le
   `written_files` retourné.
4. Échec, orphelin ou invalide : signaler à Pierre, ne rien forcer — le script ne devine jamais
   (règle « jamais inventée », `apply_decisions.mjs`).
5. Vérifier l'effet : relancer `node scripts/forge/pending_review.mjs` — l'item tranché doit
   avoir **quitté** la file (`reviewed_items` incrémenté, `pending_items` décrémenté). C'est
   l'accusé de réception de la décision ; son absence signale une boucle rompue.

**Le fichier de décisions n'a aucun écrivain en code — c'est volontaire (HumanGate).** La ligne
JSONL est ajoutée à la main, en append, par l'agent `/gate` sous dictée de Pierre. Aucun script
ne décide à sa place ; `apply_decisions` ne fait qu'apposer la trace d'une décision déjà prise.

Limite subsistante : `forge_bible_proposals` se rapproche sur `project` seul (son record ne
porte aucun identifiant de ligne) — une décision y marque **toutes** les entrées du projet.
Ces deux queues n'existent d'ailleurs pas encore sur disque : règle non vérifiée par données.

---

## Sortie

```
GATE <FRANCHIE|REFUSÉE|GELÉE> — <objet>
→ decision-log : entrée <date> ajoutée
→ <action de suivi : merge effectif / rollback / attente>
```

Le merge git effectif (si MERGE) reste une action séparée et explicite — `/gate` consigne la ratification, il ne pousse jamais.

---

## Hard rules

- **Pierre décide**, jamais Claude. Pas de sign-off Pierre = pas de gate.
- Le decision-log est **append-only** : on n'efface ni ne réécrit une décision passée. Une erreur se corrige par une nouvelle entrée datée.
- Pré-conditions MERGE non remplies (oracle rouge, HMAC KO, zone FORBIDDEN touchée) → MERGE indisponible, point.
- Jamais de `git commit`/`push` depuis `/gate` — la ratification est consignée, l'action git est séparée et explicite.
- `IMPROVEMENT_LEDGER.yaml` n'est pas édité à la main ici (passe par `kaizen_loop.py`).

## Cas d'erreur

| Situation | Action |
|---|---|
| decision-log absent | Anomalie (fichier versionné) — STOP, ne rien créer, signaler à Pierre |
| Pas de réponse Pierre | Gate non franchie — rien n'est consigné, on attend |
| Oracle `FAIL`/HMAC KO mais MERGE demandé | Refuser : signaler le bloqueur, proposer REJECT/FREEZE |
| Fichier FORBIDDEN dans le diff | Bloqueur dur — gate impossible, escalader |
| Conflit d'écriture decision-log | Append en fin de fichier, ne jamais fusionner/réordonner |
