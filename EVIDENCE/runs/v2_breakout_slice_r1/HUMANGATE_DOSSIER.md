# HumanGate — v2_breakout_slice · v2_breakout_slice_r1

software_verdict: OK · evidence_verdict: MECHANICAL_VALIDATION_ONLY · claim_verdict: NO_CLAIM_ALLOWED · verify_run: AUTHENTIQUE

## Oracles
{"s10a-oracle-code": "OK", "s10b-oracle-archi": "OK", "s10c-oracle-wiremap": "OK", "s12-verdict": "OK"}

## Couverture (feature_map ↔ wiremap)
{"design": {"regime": "JOINED", "status": "JOINED", "capacites": 10, "capacites_couvertes": 10, "lignes": 9, "lignes_sans_couvre": 0, "capacites_non_couvertes": 0, "couverture_fantome": 0, "forme_satisfaite": true}, "built": {"regime": "JOINED", "status": "JOINED", "capacites": 10, "capacites_couvertes": 10, "lignes": 9, "lignes_sans_couvre": 0, "capacites_non_couvertes": 0, "couverture_fantome": 0, "forme_satisfaite": true}}

## Suite réelle des convocations
s3-decompo → s4-archi → s5-wiremap → s5-wiremap → s9-build → s10a-oracle-code → s10b-oracle-archi → s10c-oracle-wiremap → s12-verdict → s9-build → s9-build → s10a-oracle-code → s10b-oracle-archi → s10c-oracle-wiremap → s12-verdict
égale à un profil ORDER : non

## Compteurs (deux unités distinctes)
- décisions du Director enregistrées au moment du dossier : 13
- pas exécutés (entrées de la suite) : 15
- pas attendus d'après les décisions : 15 → cohérent
- décisions sans pas exécuté : ['gate_open', 'halt', 'humangate', 'requalify']
- pas par décision `qa` : 4 (s10a-oracle-code, s10b-oracle-archi, s10c-oracle-wiremap, s12-verdict)

## Décisions du Director
- D-v2_breakout_slice_r1-1 · convoke · decompose · SECTION_ABSENT · effet CHANGED · progrès NONE
- D-v2_breakout_slice_r1-2 · convoke · architect · SECTION_ABSENT · effet CHANGED · progrès NONE
- D-v2_breakout_slice_r1-3 · convoke · wiremap · SECTION_ABSENT · effet CHANGED · progrès IMPROVED
- D-v2_breakout_slice_r1-4 · reconvoke · wiremap · JOIN_LINES_WITHOUT_COUVRE · effet CHANGED · progrès IMPROVED
- D-v2_breakout_slice_r1-5 · gate_open ·  · SUFFICIENCY_JOINED · effet  · progrès 
- D-v2_breakout_slice_r1-6 · build · builder · BUILD_REQUIRED · effet CHANGED · progrès IMPROVED
- D-v2_breakout_slice_r1-7 · qa ·  · QA_REQUIRED · effet  · progrès 
- D-v2_breakout_slice_r1-8 · build · builder · ORACLE_RED · effet NO_EFFECT · progrès NONE
- D-v2_breakout_slice_r1-9 · build · builder · ORACLE_RED · effet NO_EFFECT · progrès NONE
- D-v2_breakout_slice_r1-10 · halt ·  · ORACLE_RED_PERSISTENT · effet  · progrès 
- D-v2_breakout_slice_r1-11 · requalify ·  · ORACLE_RED_PERSISTENT · effet  · progrès 
- D-v2_breakout_slice_r1-12 · qa ·  · QA_REQUIRED · effet  · progrès 
- D-v2_breakout_slice_r1-13 · humangate ·  · VERDICT_OK_AUTHENTIC · effet  · progrès 

## Objections conservées
- AMD-20260903T164128Z-join-lines-without-couvre-wiremap-lot3-director- · objection director → ['wiremap'] : JOIN_LINES_WITHOUT_COUVRE : ta production précédente n'a pas joint la feature_map
- AMD-20260903T171927Z-join-lines-without-couvre-wiremap-v2-breakout-sl · objection director → ['wiremap'] : JOIN_LINES_WITHOUT_COUVRE : ta production précédente n'a pas joint la feature_map
- AMD-20260903T173125Z-oracle-red-builder-v2-breakout-slice-r1 · objection director → ['builder'] : ORACLE_RED : le jeu construit ne passe pas les oracles déterministes
- AMD-20260903T174307Z-oracle-red-builder-v2-breakout-slice-r1 · objection director → ['builder'] : ORACLE_RED : le jeu construit ne passe pas les oracles déterministes

## Coût LLM : 6.6708 $

## Non prouvé
- valeur du jeu (Pierre joue)
- variance de l'oracle de solvabilité (défaut connu)
- UX · design_metrics · game_flow (sections DOCUMENTED_ONLY)
- revue indépendante (red team non convoquée en v0)

no_global_ready_verdict: true
