# Coup A — « prisme → panel ×5 » : état des lieux et scoping (2026-07-13)

- **Demande** : Pierre, « regarde pour le prisme » — investigation seulement, pas de
  construction. Ce document ne propose RIEN de ratifié, ne code rien.
- **Position dans l'arbre** : `STUDIO_MASTER_SCHEMA.html` Détail E (« L'ARBRE »), coup A,
  actuellement noté `prior : bilans tri-IA · n=0` — jamais testé, contrairement au coup B
  (builder → pool) = WFL-01, maintenant à n=2 (`lab/workflow_lab/WFL-01/`).
- **claim_verdict** : NO_CLAIM_ALLOWED

## 1. Ce qui existe mécaniquement aujourd'hui (vérifié dans le code, pas supposé)

- `scripts/forge/contracts/s1-prisme.yaml` : **UN SEUL agent** (`capability_role: prisme`,
  résolu Opus 4.8 dans `roles.yaml`), qui produit **UN SEUL** artefact
  `product_snapshot.md` {voit, fait, ressent, regles_observables[]}.
- Le seul endroit où le panel ×5 (« CEO · GD · Front · Back · Joueur ») est mentionné dans
  tout le repo : 2 lignes de texte dans `STUDIO_MASTER_SCHEMA.html` (détail A et détail B).
  Aucun contrat `.yaml`, aucun protocole, aucune trace de recherche écrite (le
  « prior : bilans tri-IA » renvoie aux sessions Gemini/GPT lues via Chrome le 2026-07-12,
  jamais transcrites en document autonome — je n'ai retrouvé aucun compte-rendu séparé).
- **Divergence trouvée entre le récit du schéma et le câblage réel** : le texte du schéma
  affirme « la WIREMAP (s5) recombine ces visions + les patterns du WORLD SCAN ». Mais
  `scripts/forge/contracts/s5-wiremap.yaml` a pour `mandatory_read` UNIQUEMENT le
  `blueprint.yaml` (s4) et la `featuremap` (s3) — **pas** `product_snapshot.md`
  directement. C'est en réalité **s3 Décompo** qui lit le Prisme
  (`scripts/forge/contracts/s3-decompo.yaml` : `mandatory_read` cite explicitement
  « l'artefact product_snapshot.md produit par le Prisme »), pas s5. Le récit visuel du
  schéma est donc imprécis sur QUI recombine — à corriger dans le schéma lui-même, mais
  surtout : ça déplace le vrai point de recombinaison d'un cran vers l'amont (s3, pas s5).

## 2. Le problème d'architecture que ce coup pose — non résolu, nulle part

Aujourd'hui, s3 (Décompo) a un contrat écrit pour lire **UN** `product_snapshot.md`. Si s1
devient un panel de 5 agents-visions, s3 recevrait 5 artefacts potentiellement
**contradictoires** entre eux par construction (un CEO qui priorise la rétention et un
Game Designer qui priorise le fun ne convergent pas naturellement ; un Joueur qui veut de
la simplicité et un Front qui liste des contraintes de faisabilité UI non plus). Aucune
étape de la chaîne actuelle n'est contractée pour arbitrer ça :
- Ni fusionner automatiquement (dangereux — un LLM-arbitre non-outillé recrée exactement
  le risque que la Forge s'interdit ailleurs : un jugement non mécanique déguisé en fait).
- Ni transmettre les 5 en parallèle jusqu'à s3 sans fusion (alors s3 doit devenir un
  arbitre à son tour — mission différente de son contrat actuel « analyste qui énumère »).
- Ni remonter systématiquement en HumanGate (Pierre) à CHAQUE run — cohérent avec la
  doctrine (« un flou non tranché... remonte en fog »), mais ça change la nature du move :
  ce ne serait plus une automatisation, ce serait un panel consultatif suivi d'un choix
  humain à chaque partie forgée. Est-ce le but visé ? Pas tranché dans le schéma actuel.

**C'est le vrai obstacle**, pas la mécanique de spawn de 5 agents (ça, c'est trivial —
WFL-01 a déjà prouvé qu'un pool d'agents bornés isolés peut produire un artefact correct).
Le problème est en aval : personne n'a encore écrit CE QUE fait le studio de 5 visions
divergentes.

## 3. Coût structurel attendu, comparé à WFL-01 (coup B)

WFL-01 touchait `s9-build`, une étape **tardive** : le protocole a pu forker après
`s0→s5` (cache), donc chaque rollout ne repayait que la fin de chaîne — c'est explicitement
la règle 6 du protocole (« fork au plus tard »). Le coup A touche `s1`, l'étape la **plus
en amont possible** juste après le charter : rien n'est réutilisable en cache, **tout**
`s2→s12` doit re-tourner à chaque rollout de test. Un WFL-02 sur ce coup coûterait donc
mécaniquement bien plus cher par rollout qu'un WFL-01 (qui ne touchait que 5 fichiers en
fin de chaîne) — à budgétiser AVANT tout run, comme l'exige la règle 5 du protocole.

## 4. Recommandation — ne pas construire maintenant

Avant tout protocole WFL-02 instancié sur ce coup, il manque un préalable qui n'est pas
une question d'expérimentation mais une **décision de conception** : qui/quoi absorbe la
divergence entre les 5 visions, et à quelle étape. Tant que ce n'est pas tranché, remplir
le gabarit `WORKFLOW_LAB_PROTOCOL.md` §4 pour ce coup produirait une case « Coup (le diff,
UNE variable) » qui cache en réalité DEUX variables non séparées (spawn du panel + méthode
de recombinaison) — violerait la règle 1 du protocole (« 1 coup = 1 variable »).

**Proposition, pas décidée** : scinder en deux coups distincts et testables séparément —
1. **Coup A1** (petit, testable seul) : s1 panel ×5 qui produit 5 `product_snapshot_<lens>.md`
   distincts, **sans** tenter de les fusionner — juste vérifier mécaniquement qu'ils
   restent chacun valides au sens du contrat actuel (4 sections, aucun flou), et que le
   surcoût (tokens/temps, comme mesuré pour WFL-01 dans `cost_robustness.md`) reste
   praticable.
2. **Coup A2** (dépend de A1, plus gros) : le mécanisme de recombinaison lui-même — une
   fois qu'on sait ce que 5 vraies sorties parallèles contiennent (pas des sorties
   imaginées), concevoir COMMENT s3 (ou une nouvelle étape) les absorbe.

Aucun des deux n'est lancé ici — remonté pour go/no-go Pierre, avec le tableau qu'il
demandera pour trancher.

```
software_verdict: (aucun — investigation, aucun code produit)
evidence_verdict: MECHANICAL_VALIDATION_ONLY (lecture directe des contrats .yaml et du schéma, pas de supposition)
claim_verdict: NO_CLAIM_ALLOWED
```
