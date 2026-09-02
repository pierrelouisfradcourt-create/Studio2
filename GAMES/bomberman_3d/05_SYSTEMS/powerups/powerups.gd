# powerups.gd — REVELATION et APPLICATION. Data-driven : ce module ne connait AUCUN
# power-up par son nom, seulement la table `params.POWERUP_DEFS`.
#
# C'est la propriete qui se prouve au lot L7 : ajouter un power-up de nature « stat » doit
# etre une modification de la TABLE, sans toucher a ce fichier.
# Logique PURE. Depend de params et rng.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Rng = preload("res://05_SYSTEMS/rng/rng.gd")


# Un power-up apparait-il sur une case qui vient d'etre liberee ? Tirage SEEDE : la graine
# est passee et la suivante est rendue, aucun etat cache.
# Rend {"identifiant": String (vide = aucun), "graine": int}.
static func reveler(densite: int, poids: Dictionary, graine: int) -> Dictionary:
	var g: int = Rng.suivant(graine)
	if densite <= 0:
		return {"identifiant": "", "graine": g}
	if Rng.entier(g, 100) >= densite:
		return {"identifiant": "", "graine": Rng.suivant(g)}
	var g2: int = Rng.suivant(g)
	return {"identifiant": Rng.pondere(g2, poids, P.POWERUP_IDS), "graine": g2}


# Applique un power-up aux capacites d'un acteur, EN RESPECTANT SES BORNES. Rend true si
# une capacite a REELLEMENT change — un power-up ramasse au plafond ne ment pas sur son
# effet, il rend false.
static func appliquer(acteur: Dictionary, identifiant: String) -> bool:
	if not P.POWERUP_DEFS.has(identifiant):
		return false
	var d: Dictionary = P.POWERUP_DEFS[identifiant]
	if String(d["nature"]) != "stat":
		return false
	var champ: String = String(d["stat"])
	if not acteur.has(champ):
		return false
	var avant: int = int(acteur[champ])
	var apres: int = clamp(avant + int(d["delta"]), int(d["min"]), int(d["max"]))
	if apres == avant:
		return false
	acteur[champ] = apres
	return true


# Ramassage : un acteur vivant qui occupe une case portant un power-up le consomme.
# Rend la liste des ramassages {acteur, identifiant, effet} — `effet` dit si la capacite a
# change, pour que le HUD et l'oracle ne confondent pas « ramasse » et « a servi ».
static func ramasser(state) -> Array:
	var faits: Array = []
	for i in range(state.acteurs.size()):
		var a: Dictionary = state.acteurs[i]
		if not a["vivant"]:
			continue
		var c: Vector2i = a["cellule"]
		if not state.powerups.has(c):
			continue
		var id: String = String(state.powerups[c])
		state.powerups.erase(c)
		faits.append({"acteur": i, "identifiant": id, "effet": appliquer(a, id)})
	return faits
