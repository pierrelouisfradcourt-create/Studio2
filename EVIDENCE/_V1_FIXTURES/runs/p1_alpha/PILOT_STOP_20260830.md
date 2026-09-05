# Arrêt pilote D1 (p1_alpha) — décision Pierre 2026-08-30 (γ)

D1 est arrêté AU deadlock du design_freeze, comme **résultat pilote valide mais dégradé** —
preuves conservées, aucune nouvelle exécution, aucune modification de garde, aucun contournement.

Diagnostic ratifié (verbatim Pierre) : « ce n'est plus un simple faux positif de R3-lite, mais
une incompatibilité entre le protocole expérimental L/D et une gate de conception supposée
universelle » :

```
D  = « core_loop est normatif, le GM ne peut pas le modifier »
R3 = « une question sur core_loop n'est résolue que si core_loop est modifié »
→ contraintes incompatibles. Faire passer D1 exigerait précisément le contournement
  que nous refusons.
```

## Statuts D1 (classement Pierre)

| Surface | Statut |
|---|---|
| Conception | TESTED |
| Questions/réponses | TESTED |
| Freeze | BLOCKED — incompatibilité protocolaire démontrée |
| Build | NOT_FOUND |
| M2/M3 | BLOCKED |
| M1/M4/M5/M6/M7 | UNKNOWN jusqu'à la grille d'analyse |
| Paire L/D complète | BLOCKED |

## Les trois findings du pilote (le vrai résultat, gardes NON corrigées pendant le pilote)

1. **R3-lite : granularité insuffisante** — réponse thématique ≠ modification mécanique.
2. **Freeze : topologie des rondes insuffisante** — pas de créneau de re-déclaration ART après GM.
3. **R3 × D : incompatibilité structurelle** — une boucle normative ne peut pas satisfaire une
   gate exigeant sa modification.

## Ordre de marche ratifié

D1 STOP (preuves conservées) → L1 CONTINUE → résultat L1 → clôture du pilote → sas correctif
R3/freeze → seulement ensuite, décider si une paire L/D valide mérite d'être relancée.
**Pas de claim expérimental L/D à ce stade.**

claim_verdict: NO_CLAIM_ALLOWED
