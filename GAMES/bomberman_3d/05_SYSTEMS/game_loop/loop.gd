# loop.gd — LE TICK PUR : step(etat, intentions) -> {state, events}.
#
# SEUL orchestrateur : il ORDONNE les systemes sur un tick, il n'implemente AUCUNE regle.
# Ne mute JAMAIS l'entree (clone d'abord). RefCounted, aucune horloge, aucun alea non seede.
#
# ORDRE CANONIQUE, et pourquoi il est celui-la :
#   1. cooldowns          le temps passe pour tout le monde, y compris qui n'agit pas
#   2. intentions         deplacement ou pose
#   3. meches             une bombe arrivee a zero
#   4. explosions         chaine jusqu'au point fixe (aucun etat modifie pendant le calcul)
#   5. destruction        + revelation seedee des power-ups sur les cases liberees
#   6. letalite           les cases touchees deviennent letales MAINTENANT
#   7. ramassage          un acteur sur un power-up le prend
#   8. morts              un acteur sur une case letale meurt — donc des CE tick
#   9. decompte flammes   la letalite s'use apres avoir servi
#  10. fin de partie      derive de l'etat, jamais d'un compteur
#
# Les etapes 6 et 8 sont dans cet ordre a dessein : une bombe qui explose sur toi te tue au
# tick meme. L'ordre inverse offrirait une fenetre d'un tick pour survivre a une explosion
# subie — un bug invisible aux tests unitaires et immediatement sensible au jeu.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Movement = preload("res://05_SYSTEMS/movement_rules/movement.gd")
const Bombs = preload("res://05_SYSTEMS/bombs/bombs.gd")
const Explosion = preload("res://05_SYSTEMS/explosion/explosion.gd")
const PowerUps = preload("res://05_SYSTEMS/powerups/powerups.gd")
const Damage = preload("res://05_SYSTEMS/damage/damage.gd")
const Victory = preload("res://05_SYSTEMS/victory/victory.gd")
const SuddenDeath = preload("res://05_SYSTEMS/sudden_death/sudden_death.gd")
const Score = preload("res://05_SYSTEMS/score/score.gd")


# `intentions` : un entier par acteur (params.AUCUNE..POSER). Une liste plus courte que le
# nombre d'acteurs vaut AUCUNE pour les manquants — jamais une erreur.
static func step(state, intentions: Array) -> Dictionary:
	var s = state.clone()
	if s.statut != P.EN_COURS:
		return {"state": s, "events": []}
	var events: Array = []

	# (1) Le temps.
	Movement.decompter(s)

	# (2) Les intentions.
	for i in range(s.acteurs.size()):
		var intention: int = P.AUCUNE
		if i < intentions.size():
			intention = int(intentions[i])
		if intention == P.POSER:
			if Bombs.poser(s, i):
				events.append({"kind": "bombe_posee", "acteur": i,
					"cellule": s.acteurs[i]["cellule"]})
		elif intention != P.AUCUNE:
			if Movement.appliquer(s, i, intention):
				events.append({"kind": "deplacement", "acteur": i,
					"cellule": s.acteurs[i]["cellule"]})

	# (3) Les meches.
	var echues: Array = Bombs.tick_meches(s)

	if not echues.is_empty():
		# (4) La chaine, calculee sur un etat encore intact.
		var r: Dictionary = Explosion.resoudre(s, echues)

		# (5) Destruction + revelation seedee.
		for c in r["detruites"]:
			if s.arene.detruire(c):
				var rev: Dictionary = PowerUps.reveler(s.densite_powerup, s.poids_powerup, s.graine)
				s.graine = int(rev["graine"])
				if String(rev["identifiant"]) != "":
					s.powerups[c] = String(rev["identifiant"])
				events.append({"kind": "bloc_detruit", "cellule": c})

		# (6) Letalite, AVEC son auteur — qui doit survivre aussi longtemps que la flamme.
		var auteurs: Dictionary = r["auteur_par_case"]
		for c in r["flammes"]:
			s.flammes[c] = P.DUREE_FLAMME
			if auteurs.has(c):
				s.flammes_auteur[c] = auteurs[c]
		Bombs.retirer(s, r["explosees"])
		events.append({"kind": "explosion", "bombes": r["explosees"].size(),
			"cases": r["flammes"].size()})

		# (7) Ramassage.
		for f in PowerUps.ramasser(s):
			events.append({"kind": "powerup_ramasse", "acteur": int(f["acteur"]),
				"identifiant": String(f["identifiant"]), "effet": bool(f["effet"])})

		# (8) Morts, ATTRIBUEES.
		for m in Damage.appliquer(s):
			events.append({"kind": "mort", "victime": int(m["victime"]),
				"tueur": int(m["tueur"])})
	else:
		# Sans explosion ce tick, il reste des flammes residuelles et des power-ups au sol.
		for f in PowerUps.ramasser(s):
			events.append({"kind": "powerup_ramasse", "acteur": int(f["acteur"]),
				"identifiant": String(f["identifiant"]), "effet": bool(f["effet"])})
		for m in Damage.appliquer(s):
			events.append({"kind": "mort", "victime": int(m["victime"]),
				"tueur": int(m["tueur"])})

	# (9) La letalite s'use.
	Damage.decompter_flammes(s)

	# (10) MORT SUBITE : l'arene se referme. Placee APRES les morts par explosion et AVANT
	# l'evaluation de fin : un acteur ecrase ce tick doit compter dans le verdict du tick.
	var tombes: Array = SuddenDeath.appliquer(s)
	if not tombes.is_empty():
		events.append({"kind": "mort_subite", "cases": tombes.size()})

	# (11) Fin de partie.
	s.ticks += 1
	s.statut = Victory.evaluer(s)
	if s.statut != P.EN_COURS:
		events.append({"kind": "fin", "statut": s.statut})

	# (12) SCORE. Calcule APRES la fin de partie pour que la prime de victoire puisse etre
	# attribuee dans le meme tick que l'evenement qui la declenche.
	s.score += Score.total(events, P.INDEX_JOUEUR, s.statut == P.GAGNE)

	return {"state": s, "events": events}
