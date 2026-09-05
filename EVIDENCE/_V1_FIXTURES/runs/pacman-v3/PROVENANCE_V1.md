# pacman-v3 — run HISTORIQUE V1, ré-ancré comme DONNÉE D'ENTRÉE de test

*Ré-ancré le 2026-09-05 (HumanGate HG2, option A, GO Pierre).*

- **Origine** : `C:\TACTICAL_CHESS_STUDIO\lab\forge_runs\pacman-v3` (V1, lecture seule)
- **HEAD V1 observé au moment de la copie** : `3a9ef2d3` (R6 : le HEAD observé fait foi, pas celui cité par un document)
- **Commit V1 d'origine des artefacts** : `b22a9804` (2026-08-06)
- **run_id porté par le manifest** : `pacman-v3-20260806`

## Périmètre copié — exactement 3 fichiers, byte-identiques (sha256 mesurés AVANT copie)

| octets | sha256 | fichier |
|---:|---|---|
| 2881 | `a15646462468b247384601818d46fc522b17306f79f7be099384752d099c6680` | `context/s9-build-godot-standard.manifest.jsonl` |
| 616 | `445189d64ec968523702c128b747ec3016a81bb2d776de40da84efe265495780` | `context/s9-build-godot-standard.reasoning_observability.jsonl` |
| 577 | `512f9476932e0e69c530ddd79d05465207f624745b44484e258857e3f44c436c` | `context/s9-build-godot-standard.tool_observability.jsonl` |

Seul le `.manifest.jsonl` est LU par `forge.learning_memory.promote_manifest_lessons`
(`run_dir/context/*.manifest.jsonl`) ; les deux autres sont énumérés par le test
(`test_manifest_lesson_promotion`) pour prouver la non-modification du corpus. Rien d'autre de
`lab/` n'a été ramené.

## Ce que c'est, et ce que ce n'est pas

Artefact d'un run V1 **jamais rejoué**. Ce n'est **PAS une preuve V2** : aucun run V2 ne l'a
produit, aucun verdict V2 ne s'appuie dessus, et il vit ici — jamais sous `EVIDENCE/runs/` —
précisément pour ne pas être compté parmi les preuves. Il sert la **traçabilité historique** de la
leçon « P1 … keycode brut, aucune traduction » (témoin `test_real_pacman_v3_manifest_promotes_at_least_one_lesson`),
pas à établir une capacité V2 : celle-ci est démontrée par les runs V2 (`runm_breakout`,
`v2_breakout_slice_r1`). Règles du dossier : `EVIDENCE/_V1_FIXTURES/README.md`.
