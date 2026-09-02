# COMMUNICATION CONTRACT — sas 1/3 · **STABILISÉ**

*2026-09-01 · **PROTOCOLE UNIQUEMENT** · aucun code, aucun journal implémenté, aucune jointure
construite. Dépôt source `feeb29cb`, non touché.*

**Périmètre strict** : définir le protocole. Le journal d'amendements (sas 2) et la jointure
`expected ↔ actual` (sas 3) ne s'implémentent pas ici — *on ne fabrique pas une mécanique avant
d'avoir défini ce qu'elle doit prouver*.

---

## Décisions enregistrées avant le sas

| # | décision |
|---|---|
| **O-1** | **B — scinder `s2.7-gm-worldscan`** : `Research → System Design → {economy, system parameters}` · `Narration/GM → contenu narratif (optionnel)`. L'économie ne dépend plus d'une capacité optionnelle. Requalification + découplage d'un existant. |
| **O-2** | **Research est le producteur de `knowledge_packet.json`** ; `/world-scan` est le producteur opérationnel actuel — à documenter, plus à laisser implicite. |
| **O-3** | patron `product_snapshot` réutilisé : détection → producteur manquant → matérialisation → preuve → fermeture. |
| **rail** | **ORPHELIN assumé** — catalogue sans consommateur cible. Ne pas le brancher artificiellement. |
| **Q2** | **non touchée pendant ce sas.** |

---

## 1 · Le principe

> **Une notification adressée à une capacité devient une obligation de consommation vérifiable —
> pas une ligne ajoutée à un log.**

Une capacité **n'écrit jamais** dans la propriété d'une autre. Elle émet un message ; le message
engage son destinataire.

---

## 2 · Les trois types de message

Trois, et aucun autre.

```yaml
# --- champs communs, obligatoires ---
id:            AMD-<run>-<n>            # LA RÉFÉRENCE — c'est elle qui sera cherchée (§5)
type:          amendment | question | objection
from:          <capacité émettrice>
to:            [<capacités destinataires>]   # vide = information, jamais bloquant
subject:       <section ou objet affecté>    # ex. GAME_BLUEPRINT.game_flow
reason:        <pourquoi — jamais vide>
impact:        [<sections ou objets conséquents>]
evidence_ref:  [<refs de preuve : oracle, mesure, artefact, référence externe>]
blocking:      true | false
issued_at:     <ISO>
```

| type | champ propre | sémantique |
|---|---|---|
| **`amendment`** | `change:` | j'ai amendé **ma** section ; les destinataires réévaluent leurs conséquences |
| **`question`** | `question:` | j'ai besoin d'une décision d'un autre — **reste ouverte jusqu'à réponse** |
| **`objection`** | `claim:` · `severity:` | je conteste ; **conservée même rejetée**, cesse de bloquer sans disparaître |

**Interdit** : un 4ᵉ type. Ce qui n'est ni amendement, ni question, ni objection n'a pas à circuler
entre capacités.

---

## 3 · Propriété — frontières `permissions`

| section | propriétaire unique |
|---|---|
| `vision` · `constraints.must_not_have` · `scope` · **cibles** `design_metrics` | **Pierre** |
| `gameplay` | Gameplay |
| `systems` · `economy` | **System Design** *(après O-1)* |
| `ux` | UX |
| `art_direction` | Art |
| `technical_direction` · `ARCHITECTURE_CONTRACT` | Tech Architecture |
| `game_flow` | Design / System |
| `feature_map` · `wiremap` | **dérivés — jamais saisis à la main** |
| `decisions` | **Fable seul** |
| narration | Narration/GM *(optionnelle)* |

`write` d'une capacité = **sa section, et rien d'autre**. Réutilise le champ `permissions` existant
des contrats (`read/write/create/run/delete`) — **rien à inventer**.

---

## 4 · Le chemin d'une notification

```
capacité A ──message──▶ JOURNAL (hors run_dir, J1) ──▶ mandatory_read de B
                                                              │
                                                        convocation de B
                                                              │
                                              B PRODUIT son artefact de sortie
                                                              │
                                                 knowledge_trace --verify
                                                              │
                                        ref citée dans l'artefact de B ?
                                           ├── NON → BLOCKED
                                           └── OUI → consommé
```

Chaque maillon existe **sauf le journal** : `mandatory_read` (champ de contrat) ·
`knowledge_trace --verify` (sonde anti-théâtre) · `verify_run._check_knowledge_trace`
(**gate DUR**, *« même sévérité que la preuve mutation »*) · `driver.py:4667`.

---

## 5 · Consommation — ce que la mesure prouve, et ce qu'elle ne prouve pas

### La sémantique, dérivée du code
```js
const files = listFilesRecursive(absRunDir, tracePath);   // tout le run_dir, RÉCURSIF
matches = corpus.filter(c => needles.some(n => c.text.includes(n)));
status  = matches.length > 0 ? 'FOUND' : 'NOT_FOUND';
found_in: matches.slice(0, 5)                              // ← les fichiers où la ref a été vue
```

> **`FOUND` ne prouve pas que la capacité a compris.** Il prouve strictement qu'elle a
> **incorporé la référence du message dans sa propre production**. C'est la propriété mesurable ;
> le contrat ne revendique rien au-delà.

**Aucune notion d'ACK séparée n'est créée.** L'acquittement *est* l'incorporation.

### ⚠ Deux faux `FOUND` structurels — la mesure les impose au contrat

**F-1 · le journal.** `listFilesRecursive` n'exclut **que** le fichier de trace. Un journal
d'amendements placé dans le run_dir y serait lu, et la ref s'y trouverait par construction.
→ **résolu par J1** : le journal vit **hors du run_dir**. La sonde reste inchangée.

**F-2 · le prompt — et J1 ne le résout pas.**
```
contract.py:525   reads = "\n".join(f"- {r}" for r in contract["mandatory_read"])
                  prompt = f"…## À LIRE OBLIGATOIREMENT AVANT TOUTE ACTION\n{reads}…"
run_dir/context/prompt_<etape>_a<n>.txt   ← 520 lignes pour s4-archi, DANS le corpus (récursif)
```
Un message injecté via `mandatory_read` **apparaît toujours dans le prompt de B**, et le prompt est
persisté dans `context/`, donc dans le corpus. La sonde rendrait `FOUND` **sans que B ait produit
quoi que ce soit**.

> C'est *« une vérification verte sans avoir eu lieu »* — le mode de panne documenté quatre fois en
> une seule session de ce studio.

### La règle d'acquittement — formulation stabilisée
> **Une notification est consommée uniquement si sa `ref` apparaît dans un artefact
> explicitement désigné comme preuve de consommation par le contrat de sortie de la capacité
> destinataire.**

Trois exclusions mécaniques, et une seule admission :
```
ref dans le journal              → NON
ref dans context/prompt_*        → NON
ref dans un output NON désigné   → NON
ref dans l'output DÉSIGNÉ        → OUI
```

**La sonde reste inchangée.** `verifyTrace` retourne déjà `found_in` ; le contrat exige seulement
que `found_in` contienne l'artefact désigné. La responsabilité se déplace au bon endroit — **dans
le contrat de la capacité**, pas dans la sonde.

```
CAPABILITY CONTRACT
    ├── mandatory_read                     ← ce qu'elle DOIT lire (liste, existe déjà)
    ├── output_contract
    │     ├── production_outputs           ← ce qu'elle produit
    │     └── consumption_evidence         ← l'artefact qui FAIT FOI          (P3, sas 2)
    └── permissions                        ← ce qu'elle peut écrire
                 ↓  PRODUCTION  ↓
        knowledge_trace → verifyTrace → found_in ∈ consumption_evidence ?
```

**La sonde ne comprend jamais le workflow.** Elle vérifie une propriété objective : *la référence
a-t-elle été incorporée dans la sortie contractuellement désignée ?*

### Les quatre cas, et rien d'autre
| cas | interprétation |
|---|---|
| ref **absente** du run | non-consommé → **`BLOCKED`** |
| ref présente **dans l'artefact de sortie de B** | **consommé** |
| ref présente **uniquement** dans `context/prompt_*` ou le journal | **non-consommé** → `BLOCKED` (F-1/F-2) |
| message **non adressé** à la capacité | **aucune obligation** |
| message adressé, **production absente** | **`BLOCKED`** |

---

## 6 · Condition de blocage — et sa borne

```
message.blocking == true  ET  destinataire convoqué  ET  ref absente de son artefact de sortie
        ⇒  BLOCKED — la capacité n'est pas autorisée à clore son travail
```

| cas | effet |
|---|---|
| `to:` vide | information — jamais bloquant |
| `blocking: false` | consigné, réévaluation recommandée, aucune obligation |
| `question` ouverte adressée à B | **freeze interdit** tant que B n'a pas répondu |
| `objection` rejetée par Fable | **conservée**, cesse de bloquer, ne disparaît jamais |

### P1 — changement de politique, strictement borné *(sas 2, gate Pierre)*
```
AUJOURD'HUI   trace absente → avertissement NON BLOQUANT
              (« tous les runs n'en portent pas encore »)

CIBLE         capacité EFFECTIVEMENT NOTIFIÉE + trace/consommation absente → BLOCKED
```
> **La règle ne s'applique qu'aux capacités effectivement notifiées.** Sans cette borne, toute
> absence de trace historique — **88 run_dirs sur 89** — deviendrait un blocage global.

---

## 7 · Ce que le contrat réutilise — et n'invente pas

| brique | état mesuré | rôle |
|---|---|---|
| `permissions` (17 champs) | `read/write/create/run/delete` | frontière de propriété (§3) |
| `mandatory_read` | destination `prompt` — **doctrinal seul** | canal de convocation (§4) |
| `output_contract` | artefact déclaré par étape | **cible de l'acquittement** (§5) |
| `knowledge_trace --verify` | sonde anti-théâtre · `found_in` déjà retourné | preuve de consommation (§5) |
| `verify_run._check_knowledge_trace` | **gate DUR**, repris par `driver.py:4667` | condition de blocage (§6) |
| `design_questions.json` | matérialisé au RUN 1 (2 questions ART→GM répondues) | canal `question` |
| objections dans les verdicts | `HUMANGATE_READY_WITH_OBJECTION` | canal `objection` |

**Une seule pièce manquante : l'émetteur.** Il n'est pas dans ce sas.

---

## 8 · Ce que ce contrat n'autorise pas

- pas de 4ᵉ type de message · pas d'écriture directe dans la section d'une autre capacité ;
- pas de message sans `reason` · pas de message bloquant sans destinataire nommé ;
- **pas d'acquittement déclaratif** — seule l'incorporation vérifiée compte ;
- **pas de notion d'ACK séparée** ;
- pas de suppression d'une objection, même rejetée ;
- **pas de journal dans le run_dir** (J1) ;
- **pas d'acquittement par le prompt** (F-2) ;
- pas de blocage d'une capacité non notifiée (P1 borné) ;
- **pas d'implémentation** — ni du journal, ni de la jointure.

---

## 9 · Points stabilisés au sas 1

```
protocole ................ amendment / question / objection
propriété ................ frontières `permissions`
convocation .............. mandatory_read
consommation ............. citation textuelle de `ref` dans l'ARTEFACT DE SORTIE
                           (jamais le prompt, jamais le journal)
FOUND signifie ........... incorporation de la référence — PAS compréhension
vérification ............. knowledge_trace --verify (+ lecture de `found_in`)
gate ..................... verify_run
journal .................. hors run_dir — J1
émetteur ................. hors sas 1
jointure expected↔actual . hors sas 1
P1 « trace absente → BLOCKED » ... capacités NOTIFIÉES uniquement — sas 2, gate Pierre
Q2 / R8 .................. inchangée
```

## 10 · P3 — la forme de `consumption_evidence` est contrainte, mesuré

Déclarer l'artefact qui fait foi suppose de pouvoir l'écrire dans le contrat. Mesure sur les
**23 contrats d'étape** :

```
output_contract en prose (>- ou |) : 23 / 23
output_contract structuré          :  0 / 23
seul champ déjà structuré (liste YAML) du schéma 17 : mandatory_read
```

Trois formes possibles, et **une est exclue par une règle déjà ratifiée** :

| # | forme | coût | verdict |
|---|---|---|---|
| **a** | structurer `output_contract` en `production_outputs` + `consumption_evidence` | touche **23 contrats** + `contract.py::_render_prompt` (qui le rend en texte) + le validateur | lourd, mais fidèle au schéma proposé |
| **b** | **18ᵉ champ `consumption_evidence`**, liste YAML — *symétrique exact de `mandatory_read`* | additif ; optionnel, aucun contrat existant cassé | ⚠ `SCHEMA.md` dit explicitement que `SKIPPED_VALIDATION[]` « **n'est PAS un 18e champ** » — ajouter un 18ᵉ champ est une décision déjà refusée une fois, pour un autre sujet |
| **c** | convention de nommage, parsée depuis la prose | ~0 | **EXCLU** — règle ratifiée Pierre 2026-07-23 : *« Aucune décision ne vit dans un commentaire : toute donnée qui influence un comportement = champ structuré validé »*. `consumption_evidence` gouverne un **blocage** |

**La symétrie plaide pour (b)** : le protocole a déjà une liste d'entrée obligatoire
(`mandatory_read`) ; il lui faut une liste de sortie qui fait foi. Même forme, direction opposée.
Mais le refus antérieur d'un 18ᵉ champ doit être **arbitré explicitement**, pas contourné.

---

## Ordre des sas
```
1. COMMUNICATION CONTRACT           ← CLOS
2. AMENDMENT / NOTIFICATION LOG     émetteur · J1 · P1 · P3 · ratification KNOWLEDGE_RESOLVER_V1
3. EXPECTED_PROOF ↔ ACTUAL_PROOF    l'anneau
4. patch de frontière               seulement après
```

### Agenda du sas 2 — cinq sujets, et rien d'autre
```
1. ÉMETTEUR          la seule pièce manquante du protocole
2. J1                journal hors run_dir — garanti par le contrat, pas par la sonde
3. P1                trace absente → BLOCKED, pour capacités NOTIFIÉES uniquement
4. P3                forme de `consumption_evidence` : (a) structurer · (b) 18e champ · (c) EXCLU
5. RATIFICATION      KNOWLEDGE_RESOLVER_V1, aujourd'hui PROPOSED
```
**Hors périmètre du sas 2** : la jointure `expected ↔ actual` (sas 3) · **Q2 / R8** (décision
séparée, jamais déduite).

## Ouvert
| # | question | sas |
|---|---|---|
| **P1** | `trace absente → BLOCKED` pour capacité notifiée — politique sur une sonde ratifiée | 2, gate Pierre |
| **P2** | ratifier `KNOWLEDGE_RESOLVER_V1` (PROPOSED) | 2, gate Pierre |
| **P3** | quel artefact fait foi — et **sous quelle forme le déclarer** (voir §10) | 2 |
| Q2 | R8 appartient-il au modèle cible ? | **hors sas — décision séparée** |
| Q3 · Q5 | variance des métriques · qui décide du prochain jeu | plus tard |

```
status_by_surface:
  communication_contract:        DOCUMENTED_ONLY
  acquittement_semantics:        TESTED    # verifyTrace lu ligne à ligne, found_in retourné
  false_found_journal (F-1):     TESTED    # listFilesRecursive n'exclut que la trace → J1
  false_found_prompt  (F-2):     TESTED    # contract.py:525 + context/prompt_*.txt dans le corpus
  p1_scope_bound:                TESTED    # 88 run_dirs sur 89 sans trace
  amendment_log:                 NOT_FOUND # sas 2
  expected_actual_join:          NOT_FOUND # sas 3
  implementation:                BLOCKED
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
