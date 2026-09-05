# goals.gd — LOGIQUE PURE (category system, allowed_deps [world_content, collection,
# progression]). Calcule le texte du HUD `objectif` : un objectif initial non vide au
# demarrage (guidage, garde-fou (j)), puis des objectifs successifs distincts a mesure que
# la collection grandit et que les ronrons montent. Proprietaire unique du contenu de
# `objectif`. `live_progress` (ronrons plancher affiches) est INJECTE : goals ne lit pas le
# module economy, il recoit un entier — la partie vivante qui rend chaque objectif distinct.
extends RefCounted

const Collection = preload("res://05_SYSTEMS/collection/collection.gd")
const Progression = preload("res://05_SYSTEMS/progression/progression.gd")

# --- seuils de guidage ISOLES (garde-fou (d)) -------------------------------------
const GARDEN_TIER: int = 3   # palier ouvrant le jardin (nomme la possibilite suivante)

# Phrase de guidage selon l'etat de progression (ce que le joueur doit faire ENSUITE).
static func _phrase(state: Dictionary, places_array: Array) -> String:
	var kittens: int = Collection.count(state)
	if kittens <= 0:
		return "Caresse la pelote, puis adopte ton premier chaton"
	if Progression.lieu2_unlocked(state, places_array):
		return "Le jardin est ouvert — tente un prestige pour un bonus permanent"
	if kittens >= GARDEN_TIER - 1:
		return "Adopte encore un chaton pour ouvrir le jardin"
	return "Adopte d'autres chatons (tu en as %d) pour agrandir le refuge" % kittens

# Objectif affiche. La phrase GUIDE ; le suffixe vivant (ronrons plancher) garantit qu'un
# objectif atteint est TEXTUELLEMENT distinct du precedent (maillon NEXT_GOAL new_distinct)
# et que deux branches d'un choix (collection differente, progres different) le sont aussi
# (maillon DECISION PLAYER_GOAL).
static func objective(state: Dictionary, places_array: Array, live_progress: int) -> String:
	return "%s [ronrons %d]" % [_phrase(state, places_array), live_progress]
