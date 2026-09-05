# p1_alpha — brief IMPORTÉ DE V1, ce n'est PAS un projet V2

Migré le 2026-09-05 (GO Pierre) depuis `C:\TACTICAL_CHESS_STUDIO\lab\forge_briefs\p1_alpha\`
(V1, HEAD `58095ba9`, lecture seule).

**Pourquoi il est ici et pas dans `EVIDENCE/_V1_FIXTURES/` avec les autres fixtures V1** : il est
résolu par du CODE DE PRODUCTION — `run_real._read_project_brief_text` passe par
`project_brief_path(project)`, qui ne connaît que `EVIDENCE/briefs/<projet>`. Une fixture que la
production doit trouver ne peut pas vivre ailleurs qu'à l'emplacement canonique. L'isolement des
fixtures V1 ne vaut que là où le TEST résout lui-même le chemin ; ici, non.

**Ce que ce brief rend vérifiable** : `_project_declares_normative_structure` — la détection du
marqueur `structure_imposee` qui autorise `modification_locus: aucune_requise` (locus R3). Sans
lui, deux tests de `forge/tests/test_r3_locus.py` échouaient.

**Aucun run V2 ne s'appuie sur ce projet.** Il n'entre dans aucune preuve V2, aucun verdict V2.
À exclure de tout inventaire des projets réels du studio.
