# TAXONOMIE DES DÉPENDANCES V2 — obligatoire · conditionnelle · test-only

*2026-09-02 · **MESURE ET CLASSEMENT** · aucun code modifié, aucun fichier copié.
Préalable à toute décision sur `council`, et au branchement de `scan_imports.py`.*

---

## 0 · L'axe qui compte n'est pas celui que j'attendais

Tu demandes trois catégories. La mesure en impose **une quatrième dimension, transverse**, et
c'est elle qui explique pourquoi RUN M s'est arrêté :

```
                         absence VISIBLE              absence SILENCIEUSE
  obligatoire            bpy  → ImportError net       council → avalée, motif FAUX
  conditionnelle         Godot → NOT_MEASURED honnête
  test-only              conftest → résoluble sous pytest
```

> **Ce qui rend une dépendance dangereuse n'est pas sa catégorie, c'est que son absence soit
> silencieuse.** `bpy` manque et le dit. `council` manque, l'exception est **avalée** par
> `qwen_available()`, et la chaîne journalise « lmstudio :1234 down » — un motif faux, sur un port
> ouvert. La catégorie n'aurait pas suffi à trier ; l'axe silence/visibilité, oui.

---

## 1 · Le classement des 6 trouvailles

| # | module | catégorie | absence | verdict |
|---|---|---|---|---|
| 1 | `council` | **OBLIGATOIRE au runner qwen** | **SILENCIEUSE** | **à traiter avant M bis** — §2 |
| 2 | `bpy` ×2 | **CONDITIONNELLE** (Blender) | visible (`ImportError` module-level) | **ne pas copier** — conforme à J-4 |
| 3 | `conftest` | **TEST-ONLY** | *fausse alerte de mon scan* — §3 | **rien à faire** |
| 4 | `numpy`, `pygltflib` | **TIERCE, non déclarée** | visible | à **nommer**, pas à traiter |

---

## 2 · `council` — la dépendance réelle fait ~50 lignes, le fichier en fait 572

```
scripts/council.py                                    572 lignes, suivi au HEAD
ce que la Forge V2 en utilise, EXACTEMENT :
    forge/runtime.py:64   from council import QwenAdapter
    forge/runtime.py:66   return QwenAdapter()
                          ... et rien d'autre. Une seule classe, un seul appel.

class QwenAdapter(_OpenAICompatAdapter):              3 lignes
    def __init__(self, base_url=LMSTUDIO_URL):
        super().__init__(ModelId.QWEN14B, base_url, "qwen2.5-14b-instruct")
```

**Ce que le fichier contient d'autre**, et qui n'a rien à faire en V2 :

```
CouncilTask · ModelOpinion · Disagreement · CouncilRole · Stance · _role_prompt
   -> la LANE /council, DÉCLARÉE GELÉE (CLAUDE.md:130, legacy gelés 2026-07-19)
GeminiAdapter
   -> adaptateur d'API EXTERNE (clé GEMINI_API_KEY)
```

> **Copier `council.py` tel quel importerait en V2 une lane gelée et un adaptateur d'API externe,
> pour obtenir 3 lignes de sous-classe.** Ce serait exactement la faute que la migration sélective
> a évitée sur les hooks et les skills — et une bien plus lourde, puisqu'elle concerne du code
> exécutable et un chemin réseau sortant.

**La dépendance réelle** est `_OpenAICompatAdapter` + `QwenAdapter` + `ModelId` + `CouncilCallError`
+ les constantes de timeout : **une cinquantaine de lignes, sans aucune dépendance à la lane**.

**Trois issues, non tranchées :**

| # | issue | ce qu'elle coûte |
|---|---|---|
| **A** | copier `scripts/council.py` en V2 | 572 lignes · importe une **lane gelée** · importe un adaptateur d'**API externe** · 0 modification de code |
| **B** | **extraire** l'adaptateur dans le paquet (`forge/lm_adapter.py`) et corriger `runtime.py:64` | ~50 lignes · **modification de code** (1 import) · aucune lane, aucun réseau externe · la Forge cesse de dépendre du fichier d'une lane |
| **C** | requalifier : le runner qwen devient une **capacité conditionnelle déclarée** | 0 ligne · mais il faut alors que son absence soit **visible**, ce qui est le vrai sujet — §4 |

*Mon avis, non ratifié : **B**, parce que la dépendance de la Forge à un fichier de lane est
elle-même le défaut. Mais B est une modification de code, et A/C ne le sont pas — c'est ta
décision, pas la mienne.*

---

## 3 · `conftest` — fausse alerte de mon propre scan, et je la corrige

```
forge/tests/conftest.py     EXISTE en V2
```
L'import est dans un test qui vérifie sa propre liste d'exemptions. Sous `pytest`, le répertoire
de test est sur `sys.path` : **l'import se résout**. Mon `find_spec("conftest")` échoue parce qu'il
interroge un `sys.path` **hors harnais**.

> **Ce n'est pas une dépendance manquante : c'est mon scanner qui a posé la question dans le
> mauvais contexte.** Même famille d'erreur que le piège git de ce matin — une mesure juste, posée
> au mauvais endroit, rend un faux positif crédible.

⇒ `scan_imports.py` devra **exclure les imports résolubles sous le harnais de test** avant tout
branchement automatique. C'est une correction à faire **avant** la décision 4.

---

## 4 · Ce que la définition doit trancher avant de brancher `scan_imports.py`

| catégorie | définition proposée | régime d'absence exigé |
|---|---|---|
| **OBLIGATOIRE** | sans elle, une étape de l'`ORDER` ne peut pas s'exécuter correctement | **absence VISIBLE et bloquante** — jamais avalée, jamais dégradée en silence |
| **CONDITIONNELLE** | requise par une capacité nommée (Blender/assets, Godot/visuel) | absence ⇒ **`NOT_MEASURED` explicite**, jamais un vert, jamais un repli muet |
| **TEST-ONLY** | résoluble uniquement sous le harnais | hors du périmètre du Studio — **exclue du scan** |
| **TIERCE DÉCLARÉE** | paquet installé, nommé dans un registre | absence ⇒ échec net à l'import |

**Et la règle que RUN M impose, quelle que soit la catégorie :**

> **Une dépendance dont l'absence est avalée puis re-étiquetée est un défaut de preuve, pas un
> défaut d'installation.** `qwen_available()` a transformé un `ModuleNotFoundError` en
> « lmstudio :1234 down ». Si le modèle substitué avait porté un nom Claude valide, s6 aurait
> tourné sur un runner **non indépendant** et **rien** ne l'aurait signalé.
> Le HALT n'a pas révélé la panne : **il l'a empêchée d'être silencieuse.**

---

## Décisions

```
1. council            OBLIGATOIRE / absence silencieuse   -> issue A, B ou C  [arbitrage Pierre]
2. bpy                CONDITIONNELLE                      -> ne pas copier    [conforme J-4]
3. conftest           TEST-ONLY                           -> rien a faire ; corriger le scanner
4. numpy, pygltflib   TIERCE non declaree                 -> nommer dans un registre
5. scan_imports.py    a corriger (contexte pytest) PUIS a brancher, sur definition ratifiee
```

**Rien n'a été copié, extrait ni modifié.** `scan_imports.py` n'est branché nulle part.

```
status_by_surface:
  taxonomie_proposee:      DOCUMENTED_ONLY
  council_perimetre_reel:  TESTED   # 1 classe, 2 lignes d'appel, sur 572
  council_lane_gelee:      TESTED   # CLAUDE.md:130 + GeminiAdapter (API externe)
  conftest_faux_positif:   TESTED   # forge/tests/conftest.py existe
  bpy_conditionnelle:      TESTED   # module-level, absence visible
  axe_silence:             TESTED   # exception avalee -> motif faux journalise
  decisions:               BLOCKED  # arbitrage Pierre
```
`software_verdict: OK` (mesure) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
