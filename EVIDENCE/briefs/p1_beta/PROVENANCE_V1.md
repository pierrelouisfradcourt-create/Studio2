# p1_beta — brief IMPORTÉ DE V1, ce n'est PAS un projet V2

Migré le 2026-09-05 (GO Pierre) depuis `C:\TACTICAL_CHESS_STUDIO\lab\forge_briefs\p1_beta\`
(V1, HEAD `58095ba9`, lecture seule).

**Pourquoi il est ici et pas dans `EVIDENCE/_V1_FIXTURES/` avec les autres fixtures V1** : il est
résolu par du CODE DE PRODUCTION — `run_real._read_project_brief_text` passe par
`project_brief_path(project)`, qui ne connaît que `EVIDENCE/briefs/<projet>`. Une fixture que la
production doit trouver ne peut pas vivre ailleurs qu'à l'emplacement canonique. L'isolement des
fixtures V1 ne vaut que là où le TEST résout lui-même le chemin ; ici, non.

**Ce que ce brief rend vérifiable** : `p1_beta` est le bras LIBRE de la paire pilote — il ne porte
AUCUN marqueur de structure normative, et c'est précisément ce que le test vérifie
(`_project_declares_normative_structure(P1_BETA) is False`). Une fixture qui prouve une absence a
autant besoin d'exister qu'une fixture qui prouve une présence.

**Aucun run V2 ne s'appuie sur ce projet.** Il n'entre dans aucune preuve V2, aucun verdict V2.
À exclure de tout inventaire des projets réels du studio.
