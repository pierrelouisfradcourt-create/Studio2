# BASELINE — RUN M ter

*Ratifiée Pierre, 2026-09-03. **Référence de fonctionnement du socle V2.***

```
EVIDENCE/runs/runm_breakout/     934 Ko    ← LA BASELINE. Ne pas déplacer.
GAMES/runm_breakout/              85 Ko    ← le jeu produit
```

> ⚠ **Ne pas déplacer, ne pas renommer, ne pas écraser.** Le reçu d'oracle du verdict porte un
> chemin **relatif au dépôt** :
> `evidence_path = EVIDENCE/runs/runm_breakout/evidence/oracle_runm_breakout.log`
> Déplacer le run_dir romprait la vérifiabilité de la preuve. **Un prochain run doit porter un
> autre nom de projet** — relancer `runm_breakout` écraserait la baseline.

## Ce que la baseline établit

```
V2 transplanté
  -> exécution complète            13 / 13 étapes, run_status DONE
  -> s10a réellement atteint       après correction d'encodage
  -> mutation gate CONTRAIGNANT    4 refus, 6 tentatives de build
  -> escalade réellement exécutée  haiku -> sonnet -> opus, model_executed tracé
  -> s11 / s12
  -> verdict SIGNÉ                 clé forge/.forge_key (V2)
  -> verify_run = AUTHENTIQUE
```

**Énoncé factuel ratifié :**
> **Le Forge transplanté dans le Studio V2 sait produire un verdict signé authentifiable de bout
> en bout.**

`software_verdict: OK` · `decision: HUMANGATE_READY` ·
`evidence_verdict: MECHANICAL_VALIDATION_ONLY` · `claim_verdict: NO_CLAIM_ALLOWED` ·
`git_head: 2769dc8` · coût 16,43 $

## Ce que la baseline n'établit PAS

Elle mesure **la tuyauterie héritée** — les 13 stations fixes de V1 dans les surfaces de V2.
**Elle ne dit rien de la thèse architecturale V2** : ni `GAME_BLUEPRINT`, ni Fable directeur, ni
capacités convoquées dynamiquement. Ces objets **n'existent pas** dans le code mesuré.

Et elle porte, assumés, les défauts que les trois runs ont révélés — dont **le jeu produit se
gagne sans joueur**, avec un oracle de solvabilité à variance nulle.

## Le changement de phase

```
AVANT   « le tuyau devrait fonctionner »        hypothèse
APRÈS   baseline réelle, complète, authentifiée  mesure
```

**On ne construit plus sur une hypothèse.** La phase de sécurisation du socle est close ; la vraie
architecture V2 reste entièrement à construire.

## L'ordre ratifié pour la suite

```
1. Ratifier M ter comme baseline                    ✅ ce document
2. D-1 — réparer l'ENVELOPPE qui perd trois listes
   puis tester le chemin RÉEL oracle -> enveloppe -> agrégateur -> repair_loop
3. Indépendance de l'escalade — décision CONTRACTUELLE, pas un correctif de journalisation :
   « une escalade du builder ne doit JAMAIS modifier le modèle du reviewer indépendant »
   -> l'override passe de portée RUN à portée capability/step ;
      le reviewer conserve son propre routage
4. Construction de la vraie V2
```

```
status_by_surface:
  baseline_ratifiee:      RECORDED
  verdict_authentique:    TESTED     # verify_run, clé V2
  auto_reference_preuve:  TESTED     # evidence_path relatif — ne pas déplacer
  these_V2:               NOT_MEASURED
  D1:                     BLOCKED    # lot 2
  independance_escalade:  BLOCKED    # lot 3, décision contractuelle
```
