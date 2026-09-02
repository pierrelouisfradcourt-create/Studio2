# Proposition — garde mécanique anti-git-destructif (mission P2)

Contrat : `scripts/forge/contracts/p2-garde-git-mecanique.yaml`
Statut : **PRÉPARÉ, NON ACTIVÉ**. Ce document propose un patch de
`.claude/settings.json` — il n'a **pas** été appliqué. `git diff -- .claude/settings.json`
est vide (vérifié ci-dessous, section « Preuve settings.json intouché »).

Décision d'origine : retour niveau 1 Pierre, 2026-07-27, point 4 — « le contrat texte
ne suffit plus. Déplacer les interdictions git destructrices dans un garde mécanique
[…] avec override humain explicite. La règle doit devenir impossible à contourner
par oubli ».

## 1. Les trois occurrences réelles

Sources : `lab/forge_runs/RUN_INDEX.md`.

| # | Run | Date | Commande (forme réelle) | Conséquence |
|---|-----|------|--------------------------|-------------|
| V4 | mission V4 brancher-propose-brick | 2026-07-26 | revert temporaire de hunks de `driver.py` (equivalent `git checkout -- scripts/forge/driver.py` sur un fichier portant 3 chantiers non commités) | aucun dommage final, vérifié par comptage de marqueurs après coup |
| N1-1 | étape 1 findings red-team audibles | 2026-07-27 | `git stash push` / `git stash pop` sur `run_real.py`, arbre à 58 fichiers non commités | aucun dommage, vérifié après coup (`git stash list` ne contenait que le stash pré-existant) |
| N1-3 | étape N1-3 (nettoyage learning_curve) | 2026-07-27 | `git checkout -- knowledge_base/learning_curve.jsonl`, **interdit explicitement par le contrat de cette mission** | l'agent a ensuite « réparé » en RESTAURANT une pollution de test réelle (diagnostic erroné : il a cru la ligne antérieure à sa session, alors qu'elle datait d'une vérification du jour même, cf. `conftest.py:12-19`) |

La 3e a eu lieu **malgré une interdiction déjà écrite en prose** dans le contrat —
c'est précisément ce qui motive ce garde : une règle appliquée par l'environnement
ne peut pas être « oubliée », contrairement à une règle textuelle.

## 2. Mécanisme livré (préparé, pas câblé)

Deux fichiers nouveaux, aucune modification de fichier existant :

- `scripts/forge/git_guard.py` — logique pure, stdlib uniquement (même exigence que
  `forge.hook_guard`, pour la même raison : ce module est appelé depuis un hook
  fail-closed, une dépendance tierce absente romprait TOUTES les commandes
  Bash/PowerShell mentionnant "git", pas seulement celle visée).
- `.claude/hooks/pretool_git_guard.py` — hook mince PreToolUse : lit stdin JSON,
  appelle `forge.git_guard.evaluate_command`, sort `0` (autoriser) ou `2` (bloquer).
  Patron repris de `.claude/hooks/pretool_forge_guard.py` (test de chaîne pur avant
  tout import fragile).

Le hook n'est testé qu'indirectement (tests sur le module pur, patron identique à
`test_hook_guard.py` qui ne teste pas non plus `pretool_forge_guard.py` directement) :
le fichier hook n'a aucune branche logique propre, tout vit dans `git_guard.py`.

### Politique de détection

1. La commande ne mentionne pas "git" (insensible à la casse) → **jamais analysée
   plus loin**, retour immédiat autorisé. Ce garde ne gêne aucun usage non-git de
   Bash/PowerShell.
2. Sinon, la commande est découpée sur les séparateurs shell de haut niveau
   (`&&`, `||`, `;`, `|`) pour repérer chaque invocation `git` distincte.
3. Pour chaque segment contenant `git`, les options globales
   (`-C <dir>`, `-c <k=v>`, `--git-dir=…`, etc.) sont sautées jusqu'à la première
   sous-commande.
4. Sous-commande dans `{checkout, restore, stash}` → **BLOQUÉ**, sauf override
   humain valide (section 4).
5. Toute exception pendant l'analyse d'une commande qui mentionne "git" → **BLOQUÉ**
   (fail-closed sur sa surface, garde-fou 2 du contrat). Toute exception sur une
   commande qui ne mentionne pas "git" → autorisé (le bug du garde ne casse pas
   l'usage général de Bash/PowerShell — même compromis que `pretool_forge_guard.py`,
   qui est fail-open hors périmètre Forge).

## 3. Table commande → verdict

| Commande | Verdict | Motif |
|---|---|---|
| `git checkout -- scripts/forge/driver.py` (forme V4) | **BLOQUÉ** | sous-commande `checkout` |
| `git stash push -- scripts/forge/run_real.py` (forme N1-1) | **BLOQUÉ** | sous-commande `stash` |
| `git stash pop` (forme N1-1) | **BLOQUÉ** | sous-commande `stash` |
| `git checkout -- knowledge_base/learning_curve.jsonl` (forme N1-3) | **BLOQUÉ** | sous-commande `checkout` |
| `git -C lab/forge_runs/pong checkout -- state.json` | **BLOQUÉ** | option globale `-C` sautée, sous-commande `checkout` détectée |
| `git restore knowledge_base/learning_curve.jsonl` | **BLOQUÉ** | sous-commande `restore` |
| `git restore --staged scripts/forge/driver.py` | **BLOQUÉ** | sous-commande `restore` |
| `git stash` / `git stash list` / `git stash apply` / `git stash drop` / `git stash clear` | **BLOQUÉ** | `stash` bloqué quelle que soit la sous-sous-commande (contrat : « stash, toutes sous-commandes ») |
| `git --no-pager checkout -- foo.txt` | **BLOQUÉ** | option globale sans argument sautée, `checkout` détecté |
| `git diff -- foo.txt && git checkout -- foo.txt` | **BLOQUÉ** | 2e segment destructeur détecté même après un 1er segment inoffensif |
| `git status; git restore foo.txt` | **BLOQUÉ** | idem avec séparateur `;` |
| `git status` / `git status --porcelain` | **PASSE** | liste blanche explicite |
| `git diff -- .claude/settings.json` | **PASSE** | liste blanche explicite |
| `git log --oneline -5` | **PASSE** | liste blanche explicite |
| `git show HEAD:scripts/forge/driver.py` | **PASSE** | liste blanche explicite |
| `npm test` (aucun "git") | **PASSE** | non analysé (hors surface du garde) |
| `git checkout -- foo.txt` + override frais et valide | **PASSE** | override humain accepté (tracé dans le motif renvoyé) |
| `git checkout -- foo.txt` + override expiré (>10 min) | **BLOQUÉ** | override refusé, expiré |
| `git checkout -- foo.txt` + override malformé/illisible | **BLOQUÉ** | override refusé, fail-closed |

28 tests dans `scripts/forge/tests/test_git_guard.py` couvrent cette table
(RED/GREEN section 6).

## 4. Variantes NON couvertes (honnêteté exigée, garde-fou 3)

Documenté dans l'en-tête de `scripts/forge/git_guard.py` et prouvé par
`test_limite_documentee_alias_git_non_couvert` :

- **Alias git utilisateur** (`git co` configuré comme alias de `checkout`) — non
  reconnu, seule la forme canonique est détectée.
- **Wrappers indirects** : script `.sh`/`.ps1` qui appelle git en interne,
  `subprocess.run(["git","checkout",...])` en Python, `Invoke-Expression`
  PowerShell construite dynamiquement — le garde analyse le TEXTE passé à
  `tool_input.command`, jamais ce qu'un interpréteur exécute réellement à
  l'intérieur.
- **Obfuscation par variable shell** (`X=checkout; git $X`).
- **Binaire `git` renommé ou PATH détourné.**
- **Syntaxe de quoting exotique** où la sous-commande n'est pas séparée du reste
  par un espace ASCII simple.
- **Autre outil d'exécution que `Bash`/`PowerShell`** : le hook ne matche que ces
  deux noms d'outil (`GUARDED_TOOLS` dans `pretool_git_guard.py`) ; un futur outil
  d'exécution de commande sous un autre nom ne serait pas couvert tant qu'il n'est
  pas ajouté à cette liste.

## 5. Mécanisme d'override — et ses limites honnêtes

**Mécanisme proposé** : un fichier sentinelle horodaté,
`.claude/HUMAN_GIT_OVERRIDE.json`, contenant `{"timestamp_epoch": <epoch>, "reason": "<texte>"}`.
Le garde l'accepte seulement si :
- le fichier existe et est un JSON valide avec ces deux champs ;
- `reason` est non vide (une trace, pas un interrupteur muet) ;
- l'écart entre l'heure d'appel et `timestamp_epoch` est ≤ 10 minutes (fenêtre
  courte : un override est un geste ponctuel pour UNE commande, pas un
  interrupteur qu'on laisse ouvert toute une session).

Le mécanisme ne CONSOMME pas automatiquement le fichier après un usage (pas
implémenté dans cette mission — au-delà du périmètre demandé, qui est de préparer
le garde, pas de l'activer) : Pierre supprime le fichier lui-même après usage, ou
la fenêtre de 10 minutes l'expire naturellement. C'est une limite assumée, à
discuter si le garde est un jour activé (un mécanisme one-shot serait strictement
plus sûr).

**LIMITE CENTRALE, honnêtement annoncée (c'est le point exact du garde-fou 4 du
contrat — « un override qu'un agent peut se donner tout seul ne vaut rien »)** :

`forge.git_guard._read_override` vérifie la PRÉSENCE, la FRAÎCHEUR et la FORME du
fichier — il ne peut **pas** vérifier QUI l'a écrit. La garantie d'origine humaine
ne vient **pas** de ce module : elle doit venir d'une règle *externe*, dans
`.claude/settings.json`, qui interdit à tout agent d'écrire ou modifier ce fichier
précis (section 7, item 2 du patch proposé). **Sans cette règle de permission,
n'importe quel agent ayant accès à `Write`/`Edit` sur `.claude/**` peut créer ce
fichier lui-même et s'auto-délivrer l'override** — exactement le défaut que ce
garde doit éliminer.

Or **`.claude/settings.json` actuel autorise déjà `Write(.claude/**)` et
`Edit(.claude/**)`** (bloc `permissions.allow`, lignes 9-10) — un périmètre qui
couvrirait aujourd'hui `.claude/HUMAN_GIT_OVERRIDE.json` si rien de plus
spécifique n'était ajouté. Le patch proposé (section 7) ajoute donc un `deny`
explicite sur ce chemin précis. **Hypothèse non vérifiée par cette mission** (à
confirmer par Pierre ou par la documentation Claude Code) : que `deny` l'emporte
bien sur un `allow` plus large quand les deux matchent le même chemin. C'est
l'hypothèse de précédence la plus courante dans ce genre de système de
permissions, mais je ne l'ai pas testée en conditions réelles ici (le contrat
interdit de modifier `settings.json` — donc de le vérifier en conditions réelles)
et je préfère le dire plutôt que l'affirmer.

**Autres limites, dans le même esprit d'honnêteté** :
- Un hook `PreToolUse` est une protection côté **harnais client**, pas un
  sandbox. Elle dépend de l'intégrité de `.claude/settings.json` lui-même : un
  agent qui aurait la permission d'éditer `settings.json` pourrait retirer le
  hook entièrement (c'est déjà vrai du garde Forge existant
  `pretool_forge_guard.py` — pas une régression introduite ici). Cette mission
  ne modifiant pas `settings.json`, une **recommandation complémentaire** (section
  7, item 3) propose d'exclure `settings.json` lui-même du périmètre `Write(.claude/**)`/
  `Edit(.claude/**)` actuel — hors du périmètre strict de cette mission mais
  directement pertinente à l'intégrité du garde, donc signalée pour décision Pierre
  séparée.
- Ce garde ne protège pas contre un humain qui exécute une commande git
  destructrice dans un terminal **en dehors** de Claude Code — hors scope,
  attendu (le contrat vise « pour un agent »).
- Le sentinelle n'est pas consommé automatiquement (voir ci-dessus) : entre sa
  création et son expiration (10 min), TOUTE commande destructrice de l'agent
  passerait, pas seulement celle que Pierre avait en tête en le créant. À
  documenter dans l'usage : créer le sentinelle juste avant la commande visée,
  le supprimer juste après.

## 6. TDD — RED puis GREEN

### RED (module absent)

```
$ .venv312/Scripts/python.exe -m pytest scripts/forge/tests/test_git_guard.py -v
...
ImportError while importing test module 'scripts/forge/tests/test_git_guard.py'.
...
E   ModuleNotFoundError: No module named 'forge.git_guard'
=========================== short test summary info ===========================
ERROR scripts/forge/tests/test_git_guard.py
!!!!!!!!!!!!!!!!!!! Interrupted: 1 error during collection !!!!!!!!!!!!!!!!!!!!
============================== 1 error in 0.18s ===============================
```

### GREEN (module implémenté)

```
$ .venv312/Scripts/python.exe -m pytest scripts/forge/tests/test_git_guard.py -v
...
28 passed in 0.12s
```

(Un premier passage a d'abord fait échouer `test_override_absent_ne_change_rien` —
défaut dans l'ASSERTION du test elle-même, un `or` toujours partiellement vrai,
pas dans `git_guard.py`. Corrigé, puis 28/28 verts.)

### Suite complète (référence 917 passed, 1 skipped)

```
$ .venv312/Scripts/python.exe -m pytest scripts/forge/tests/ -q
...
945 passed, 1 skipped in 54.06s
```

`945 = 917 + 28` — zéro régression, les 28 nouveaux tests sont bien ajoutés.

### Exécution manuelle du hook (stdin → exit code)

```
$ echo '{"tool_name":"Bash","tool_input":{"command":"git checkout -- knowledge_base/learning_curve.jsonl"}}' \
  | .venv312/Scripts/python.exe .claude/hooks/pretool_git_guard.py ; echo exit=$?
[git-guard] commande refusée : ... -- aucun override (sentinelle absent)
exit=2

$ echo '{"tool_name":"Bash","tool_input":{"command":"git status --porcelain"}}' \
  | .venv312/Scripts/python.exe .claude/hooks/pretool_git_guard.py ; echo exit=$?
exit=0

$ echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' \
  | .venv312/Scripts/python.exe .claude/hooks/pretool_git_guard.py ; echo exit=$?
exit=0

$ echo '{"tool_name":"PowerShell","tool_input":{"command":"git stash pop"}}' \
  | .venv312/Scripts/python.exe .claude/hooks/pretool_git_guard.py ; echo exit=$?
[git-guard] commande refusée : ... (stash) -- aucun override (sentinelle absent)
exit=2
```

## 7. Patch proposé de `.claude/settings.json` (NON APPLIQUÉ)

Le fichier actuel (`.claude/settings.json`) porte, entre autres :

```json
"permissions": {
    "allow": [
        "Write(studio_core/**)",
        "Edit(studio_core/**)",
        "Write(studio/openclaw-workspace/**)",
        "Edit(studio/openclaw-workspace/**)",
        "Edit(autopilot.py)",
        "Write(.claude/**)",
        "Edit(.claude/**)"
    ],
    "ask": [ "Write(lab/chains/**)", "Edit(lab/chains/**)" ],
    "deny": [
        "Bash(rm -rf *)",
        "Bash(git push --force*)",
        "Bash(git push -f *)",
        "Bash(git reset --hard*)",
        "Bash(git clean -fd*)",
        "Read(**\\.env*)",
        "Bash(cat *.env*)"
    ]
},
"hooks": {
    "PreToolUse": [
        {
            "matcher": "Task",
            "hooks": [{"type": "command", "command": "python .claude/hooks/pretool_forge_guard.py"}]
        }
    ],
    ...
}
```

### Item 1 — ajouter le garde git (cœur de cette mission)

Ajouter, dans `hooks.PreToolUse`, deux entrées **après** celle du matcher `"Task"`
(ne pas la retirer) :

```json
{
    "matcher": "Bash",
    "hooks": [
        { "type": "command", "command": "python .claude/hooks/pretool_git_guard.py" }
    ]
},
{
    "matcher": "PowerShell",
    "hooks": [
        { "type": "command", "command": "python .claude/hooks/pretool_git_guard.py" }
    ]
}
```

### Item 2 — protéger le sentinelle d'override (nécessaire pour que l'override soit réellement humain — section 5)

Ajouter dans `permissions.deny` :

```json
"Write(.claude/HUMAN_GIT_OVERRIDE.json)",
"Edit(.claude/HUMAN_GIT_OVERRIDE.json)"
```

Sans cet ajout, l'override décrit en section 5 est un théâtre : n'importe quel
agent peut créer ce fichier lui-même via `Write(.claude/**)`, actuellement permis.

### Item 3 — recommandation complémentaire, HORS PÉRIMÈTRE strict de cette mission, signalée pour décision Pierre séparée

Réduire `"Write(.claude/**)"` / `"Edit(.claude/**)"` pour exclure
`.claude/settings.json` lui-même (par exemple en ajoutant
`"Write(.claude/settings.json)"` / `"Edit(.claude/settings.json)"` à `deny`), afin
qu'aucun agent ne puisse retirer les hooks de garde en éditant `settings.json`
directement. Cette recommandation N'EST PAS appliquée ni même décidée ici — elle
dépasse le périmètre de la mission (« NE PAS MODIFIER `.claude/settings.json` » /
« le hook Forge existant … INTOUCHÉ ») et touche à un mécanisme plus large que le
seul garde git. Signalée parce qu'elle conditionne directement la solidité de
l'override (section 5).

### Résultat final proposé pour le bloc `hooks.PreToolUse` (vue d'ensemble, items 1 seulement — item 3 non inclus)

```json
"PreToolUse": [
    {
        "matcher": "Task",
        "hooks": [
            { "type": "command", "command": "python .claude/hooks/pretool_forge_guard.py" }
        ]
    },
    {
        "matcher": "Bash",
        "hooks": [
            { "type": "command", "command": "python .claude/hooks/pretool_git_guard.py" }
        ]
    },
    {
        "matcher": "PowerShell",
        "hooks": [
            { "type": "command", "command": "python .claude/hooks/pretool_git_guard.py" }
        ]
    }
]
```

## 8. Preuve settings.json intouché

```
$ git diff -- .claude/settings.json
[sortie vide]
```

## 9. Fichiers de cette mission (`git status --porcelain`, périmètre de la mission uniquement)

```
?? .claude/hooks/pretool_git_guard.py
?? scripts/forge/git_guard.py
?? scripts/forge/tests/test_git_guard.py
?? docs/forge/GARDE_GIT_MECANIQUE_PROPOSITION.md
```

(Le dépôt porte par ailleurs ~73 autres fichiers non commités d'autres chantiers,
préexistants à cette mission et non touchés par elle — cf. `git status` général.)

## 10. skipped_validation

1. **Précédence `deny` vs `allow` non vérifiée en conditions réelles** (section 5) :
   je n'ai pas pu appliquer le patch pour tester si le `deny` proposé sur
   `.claude/HUMAN_GIT_OVERRIDE.json` l'emporte réellement sur
   `allow: Write(.claude/**)` — le contrat interdit de modifier `settings.json`.
   À vérifier par Pierre avant d'activer, ou par une mission dédiée hors périmètre.
2. **Le hook n'est pas testé en conditions réelles de session Claude Code**
   (câblé dans un vrai `PreToolUse`) — seulement exécuté manuellement en ligne de
   commande avec des payloads JSON construits à la main (section 6). Le format
   exact de l'événement `PreToolUse` réel (noms de champs, présence de
   `tool_input.command` pour `Bash`/`PowerShell`) est supposé identique au patron
   `pretool_forge_guard.py`, pas re-vérifié contre une trace réelle de session.
3. **Le fichier hook mince (`pretool_git_guard.py`) n'a pas de test automatisé
   dédié** — patron assumé identique à `pretool_forge_guard.py`/`hook_guard.py`
   (toute la logique vit dans le module testé, le hook ne fait que du wiring).
   Justifié en section 2, mais c'est un choix, pas une garantie testée.
4. **Consommation one-shot du sentinelle non implémentée** (section 5) — le
   fichier reste valide pendant toute sa fenêtre de fraîcheur (10 min), pas
   seulement pour une commande. Limite assumée, hors périmètre de préparation
   demandé.
5. **Aucune commande git destructrice n'a été exécutée pendant cette mission**
   (garde-fou 7 du contrat) — vérifiable par le git status final (section 9) :
   aucune commande git au-delà de `status`/`diff` n'apparaît dans l'historique
   de cette session.
