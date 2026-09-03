# LOT B — EXTRACTION DE L'ADAPTATEUR LM · EXÉCUTION

*2026-09-02 · GO Pierre · **V1 non modifié** (`58095ba9`, 4 écarts de l'autre session).
Les 5 étapes de ton protocole, dans l'ordre.*

---

## 1-2 · Le périmètre exact — fermeture transitive depuis `QwenAdapter`

```
51 lignes sur 572  (8 %)      ·      34 définitions de premier niveau NON reprises

REPRIS      QwenAdapter (3) · _OpenAICompatAdapter (37) · ModelId (4)
            CouncilError + CouncilCallError (4) · LMSTUDIO_URL · 2 bornes de temps (3)
NON REPRIS  la lane /council — CouncilTask · CouncilRole · CouncilResult · Disagreement
                               ModelOpinion · _role_prompt   (GELÉE, CLAUDE.md:130)
            GeminiAdapter — API EXTERNE (GEMINI_API_KEY)
            ClaudeProxyAdapter · COUNCIL_WRITE_ACTION · ARTIFACT_DIR · REPO · governor
```

## 3 · L'extraction — `forge/lm_adapter.py`, **verbatim**

Le code n'est **pas réécrit** : chaque bloc porte sa provenance à la ligne près
(`council.py:47`, `:51-52`, `:67-72`, `:81-84`, `:261-297`, `:308-310`).

> **`ModelId` conserve ses trois valeurs alors que V2 n'en consomme aucune** (0 usage dans
> `forge/`). Je l'avais signalé avant le GO comme *le seul endroit où je pourrais dériver sans
> m'en apercevoir* — la simplification est donc **refusée explicitement**, et la raison est écrite
> dans l'en-tête du module. **On récupère, on ne reconstruit pas.**

### `forge/runtime.py` — deux changements
```python
- from council import QwenAdapter        # scripts/ est sur sys.path
+ from forge.lm_adapter import QwenAdapter
```
Et le **bricolage de `sys.path` a été supprimé** :
```python
- SCRIPTS_DIR = Path(__file__).resolve().parent.parent
- if str(SCRIPTS_DIR) not in sys.path: sys.path.insert(0, str(SCRIPTS_DIR))
```
Plus aucun chemin V1 n'est inséré dans `sys.path` au chargement du module. **L'import paresseux
est conservé** — il garde `runtime.py` importable si `requests` manque — mais **la dépendance
qu'il porte est désormais interne au paquet**, et c'est tout l'objet du lot.

## 4 · Preuve que Qwen fonctionne — appel RÉEL

```
adaptateur     forge.lm_adapter.QwenAdapter
modèle         ModelId.QWEN14B / qwen2.5-14b-instruct
endpoint       http://127.0.0.1:1234/v1
qwen_available()   True          ← était False avant l'extraction

appel réel à LM Studio (local, gratuit)
  prompt   : « Reponds exactement par le mot: PONG »
  réponse  : 'PONG'
  APPEL RÉUSSI
```

## 5 · Preuve que council / la lane / Gemini ne sont plus requis

```
scan_imports.py   IMPORTS NON RÉSOLUBLES : 2      ← était 4 ce matin, 3 après correction du scanner
                    bpy ×2  [module-level]   conditionnelle Blender, absence VISIBLE
                    council : DISPARU
                  `requests` apparaît désormais en dépendance tierce DÉCLARÉE

dans forge/ :  GeminiAdapter        0    (seule la valeur d'enum verbatim subsiste)
               endpoint externe     0
               lane council         0    (CouncilTask · CouncilRole · Disagreement · ModelOpinion)
```

---

## Ce que l'extraction a mis au jour — et qui me concerne

Trois tests de `test_runtime_inventory_oracle.py` parlaient de `council`. **L'un d'eux
s'appelait :**

```python
def test_council_est_importe_par_la_forge_donc_PAS_hors_perimetre():
    """Fait mesuré : `forge/runtime.py` importe `council.QwenAdapter`. Un fichier
    « legacy » importé par le runtime de la Forge est une dépendance, pas un vestige."""
```

> **Le test disait, dans son nom et dans sa docstring, exactement ce que j'ai nié ce matin.**
> J'ai classé `scripts/council.py` « hors périmètre V2 », et rangé CE test en
> `INTENTIONALLY_OUT_OF_SCOPE`. **La suite portait la réponse ; ma classification l'a fait taire.**
> RUN M s'est arrêté à s6 sur le `ModuleNotFoundError` qu'il annonçait.

Il est **retourné, pas supprimé** : il devient la garde de non-régression contre une
ré-introduction de la dépendance sortante — l'import doit venir du paquet, `from council import`
doit rester absent. Sa docstring porte cette histoire.

Les deux autres (`scripts/council.py` et `scripts/claude_proxy.py` présents dans le dépôt) restent
`OUT_OF_SCOPE` : ceux-là décrivent bien la **forme du dépôt V1**.

## Suite complète

```
2448 passed · 43 failed · 62 skipped        (était 2445 / 45 avant le lot)
```
**+3 passés, −2 échecs.** Aucune régression : les 43 restants sont la population déjà classée
(artefacts V1 non migrés, capacités conditionnelles, forme du dépôt V1).

```
status_by_surface:
  perimetre_mesure:      TESTED   # 51/572 lignes, fermeture transitive
  extraction_verbatim:   TESTED   # provenance ligne à ligne, ModelId non simplifié
  syspath_v1_supprime:   TESTED   # plus aucun chemin V1 inséré
  qwen_fonctionne:       TESTED   # appel réel -> 'PONG'
  council_plus_requis:   TESTED   # scan : 2 non résolubles, tous bpy
  lane_et_gemini_absents:TESTED   # 0 occurrence dans forge/
  test_inverse:          TESTED   # garde de non-régression, non supprimée
  suite:                 TESTED   # 2448 passed / 43 failed
  v1_intact:             TESTED   # 58095ba9
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Aucun commit.** `scan_imports.py` toujours non branché dans `validate_v2.py`.
**M bis n'est pas relancé** — c'est ta décision.
