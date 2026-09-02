# contacts.gd — detection et resolution des contacts Pac-Man / fantome
# (lignes contacts.detection, contacts.resolution). UNIQUE endroit ou l'etat d'un
# fantome decide du SENS d'un contact.
extends RefCounted

const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const House = preload("res://05_SYSTEMS/ghost_house/ghost_house.gd")
const Score = preload("res://05_SYSTEMS/score/score.gd")


# Detection dans les DEUX situations (ligne contacts.detection) :
#  (a) meme case en FIN de tick ;
#  (b) ECHANGE de cases sur la meme arete PENDANT le tick (croisement en sens inverse).
# Retourne les index des fantomes en contact, dans l'ordre fixe des index.
static func detecter(
		pac_avant: Vector2i, pac_apres: Vector2i,
		fantomes_avant: Array, fantomes_apres: Array, dehors: Array) -> Array:
	var touches: Array = []
	for i in range(fantomes_apres.size()):
		if not dehors[i]:
			continue
		var meme_case: bool = fantomes_apres[i] == pac_apres
		var echange: bool = fantomes_apres[i] == pac_avant and pac_apres == fantomes_avant[i]
		if meme_case or echange:
			touches.append(i)
	return touches


# Resolution (ligne contacts.resolution) : l'etat du fantome — et lui seul — aiguille
# l'issue. Fantome Effraye -> CAPTURE (retour en maison, gain selon le rang, vies
# INCHANGEES). Fantome hostile -> perte de vie, signalee a l'appelant qui la fait
# appliquer par end_conditions (unique proprietaire du compteur de vies).
static func resoudre(s, touches: Array) -> Dictionary:
	var captures: Array = []
	var hostile: bool = false
	for i in touches:
		if s.effrayes[i]:
			Score.ajouter(s, Score.valeur_capture(s.rang_capture))
			s.rang_capture += 1
			House.renvoyer(s, i)
			captures.append(i)
		else:
			hostile = true
	if hostile:
		Chase.rafraichir_etats(s)
	return {"captures": captures, "hostile": hostile}
