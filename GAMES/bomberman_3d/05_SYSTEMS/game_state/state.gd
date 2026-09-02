# state.gd — DETIENT l'etat de partie, N'AGIT sur aucune regle.
#
# La physique, la mort et la fin vivent dans les autres systemes, qui operent SUR lui.
# Statut EXACTEMENT parmi 4 (params) : EN_COURS / GAGNE / PERDU / NUL — jamais indefini.
# RefCounted (logique pure, deterministe, aucune horloge).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")

var arene = null                      # Arena, mutable en cours de partie
var acteurs: Array = []               # voir _acteur_neuf
var bombes: Array = []                # {proprietaire, cellule, meche, rayon}
var flammes: Dictionary = {}          # Vector2i -> ticks de letalite restants
# Vector2i -> index de l'acteur dont la bombe a produit cette flamme.
# SEPARE de `flammes` a dessein : une flamme dure plusieurs ticks, et son AUTEUR doit durer
# aussi longtemps qu'elle. Mesure du 2026-08-10 : sans cette table, toute mort survenue
# apres le tick de l'explosion sortait avec `tueur: -1`, ce qui faisait sous-compter les
# eliminations actives — l'oracle aurait declare injouable un jeu qui tue correctement.
var flammes_auteur: Dictionary = {}
var powerups: Dictionary = {}         # Vector2i -> identifiant (params.POWERUP_IDS)
var graine: int = 0
var ticks: int = 0
var statut: int = P.EN_COURS
var regle_victoire: String = P.VICTOIRE_LAST_STANDING
var densite_powerup: int = 0          # pourcentage de destructibles portant un power-up
var poids_powerup: Dictionary = {}
# Morts attribuees : {victime, tueur} — `tueur` = -1 si la victime s'est tuee seule.
# Existe pour que l'oracle de solvabilite puisse exiger une ELIMINATION ACTIVE et pas
# seulement une survie : sans cette trace, « le bot a gagne » ne distingue pas un bot qui
# joue d'un bot qui attend que les autres se tuent.
var morts: Array = []
# Nombre de blocs de mort subite deja tombes. Progression DERIVEE du temps a chaque tick
# (sudden_death.blocs_dus), ce compteur n'est que la memoire de ce qui a deja ete applique.
var blocs_tombes: int = 0
# Score du JOUEUR (acteur 0). Cumul de la partie ; remis a zero par une partie neuve.
var score: int = 0


static func _acteur_neuf(cellule: Vector2i) -> Dictionary:
	return {
		"cellule": cellule,
		"direction": P.BAS,
		"vivant": true,
		"bombes_max": P.BOMBES_BASE,
		"rayon": P.RAYON_BASE,
		"cooldown": P.MOVE_COOLDOWN_BASE,
		"cd_restant": 0,
		"bombes_actives": 0,
	}


# Etat initial neuf et deterministe. La carte est RECUE deja validee : cette fonction ne
# valide rien elle-meme (map_validator est le seul juge) et ne lit aucun fichier.
static func initial(carte_validee: Dictionary, desc: Dictionary, graine_val: int, nb_acteurs: int) -> Object:
	var s = load("res://05_SYSTEMS/game_state/state.gd").new()
	s.arene = carte_validee["arene"]
	s.graine = graine_val
	s.regle_victoire = String(desc["victory_rule"])
	s.poids_powerup = desc["powerup_rules"]
	s.densite_powerup = int(desc.get("powerup_densite", 0))
	var spawns: Array = carte_validee["spawns"]
	var n: int = min(nb_acteurs, spawns.size())
	for i in range(n):
		s.acteurs.append(_acteur_neuf(spawns[i]))
	return s


func clone() -> Object:
	var s = load("res://05_SYSTEMS/game_state/state.gd").new()
	s.arene = arene.clone()
	for a in acteurs:
		s.acteurs.append(a.duplicate())
	for b in bombes:
		s.bombes.append(b.duplicate())
	s.flammes = flammes.duplicate()
	s.flammes_auteur = flammes_auteur.duplicate()
	s.powerups = powerups.duplicate()
	s.graine = graine
	s.ticks = ticks
	s.statut = statut
	s.regle_victoire = regle_victoire
	s.densite_powerup = densite_powerup
	s.blocs_tombes = blocs_tombes
	s.score = score
	s.poids_powerup = poids_powerup.duplicate()
	for m in morts:
		s.morts.append(m.duplicate())
	return s


func vivants() -> Array:
	var sortie: Array = []
	for i in range(acteurs.size()):
		if acteurs[i]["vivant"]:
			sortie.append(i)
	return sortie


func bombe_sur(cellule: Vector2i) -> int:
	for i in range(bombes.size()):
		if bombes[i]["cellule"] == cellule:
			return i
	return -1


func case_letale(cellule: Vector2i) -> bool:
	return flammes.has(cellule) and int(flammes[cellule]) > 0
