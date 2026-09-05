# Clôture de la paire pilote L/D — décisions Pierre 2026-08-30

## HumanGate L1 (p1_beta) : **FREEZE avec objection conservée**

Le verdict `HUMANGATE_READY_WITH_OBJECTION` est recevable comme **état du run** (chaîne et
verify_run authentiques) — PAS comme PASS logiciel sans réserve. Le survivant de mutation
`and→or@L149` reste **CLAIM UNVERIFIED** : interdit de le requalifier bénin, de supprimer
l'objection, de transformer le verdict en OK sans réserve, ou d'utiliser L1 comme preuve de
qualité du produit. Le hit tripwire `1.12` est distinct : **classé innocent après enquête**
(`scale()` CSS cosmétique), pas une contamination structurelle.

## Statuts du pilote (classement Pierre, verbatim)

| Surface | Statut |
|---|---|
| D1 conception | TESTED |
| D1 freeze | BLOCKED — incompatibilité R3×D |
| L1 chaîne complète / build / assets | TESTED |
| L1 s10 | TESTED avec objection |
| L1 s11 indépendant | TESTED |
| L1 verdict / verify_run | TESTED |
| Tripwire contamination | TESTED |
| Mutation and→or@L149 | UNKNOWN |
| Comparaison L/D | BLOCKED |
| M1-M7 | UNKNOWN — aucune analyse comparative ratifiée |

## Les trois findings (résultat réel du pilote — spécification du sas correctif)

1. R3-lite ne doit pas confondre **réponse à une question** et **modification mécanique du loop**.
2. La topologie doit permettre une **re-déclaration après la ronde du répondant**.
3. Une gate exigeant une modification doit être compatible avec un bras où l'objet est
   **normatif et immuable** (incompatibilité R3×D démontrée — cf. p1_alpha/PILOT_STOP_20260830.md).

## Séparation maintenue (verbatim)

```
L1 = chaîne exécutée jusqu'au bout
D1 = chaîne arrêtée honnêtement par incompatibilité de protocole
≠
L1 > D1
```

**Aucune conclusion expérimentale Libre vs Dirigé n'est tirée de cette paire.**

## Ordre de marche

Sas correctif R3/freeze AVANT toute analyse M1-M7 et toute nouvelle paire. Coûts de la paire :
L1 = 19 appels / 704 440 tokens · D1 = 8 appels / 357 811 tokens (~1,06 M total).

```
software_verdict: OK_WITH_OBJECTION
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
no_global_ready_verdict: true
```
