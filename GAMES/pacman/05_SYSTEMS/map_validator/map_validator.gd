# map_validator.gd — VERDICT DE VALIDITE d'un descripteur de carte
# (lignes validator.map_verdict, core.error_handling).
#
# Le contenu devenant une DONNEE, la donnee malformee devient la premiere entree hors
# domaine du jeu. Une carte invalide est declaree telle AVEC SON MOTIF avant d'etre
# jouee : elle n'est pas jouee a moitie. Aucune exception n'est levee — le refus est une
# VALEUR DE RETOUR.
#
# Logique PURE. Depend de map_schema, maze et pellets.
extends RefCounted

const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")
const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")

# Vocabulaire ferme des motifs de refus, dans l'ordre d'examen declare.
const MOTIF_CHAMP_MANQUANT := "champ_obligatoire_manquant"
const MOTIF_PLAN_NON_RECTANGULAIRE := "plan_non_rectangulaire"
const MOTIF_SYMBOLE_INCONNU := "symbole_hors_legende"
const MOTIF_DEPART_IMPRATICABLE := "depart_impraticable"
const MOTIF_MAISON_INCOHERENTE := "maison_incoherente"
const MOTIF_TUNNEL_IMPRATICABLE := "ligne_de_bouclage_impraticable"
const MOTIF_COLLECTIBLE_INATTEIGNABLE := "collectible_inatteignable"

const MOTIFS: Array = [
	MOTIF_CHAMP_MANQUANT,
	MOTIF_PLAN_NON_RECTANGULAIRE,
	MOTIF_SYMBOLE_INCONNU,
	MOTIF_DEPART_IMPRATICABLE,
	MOTIF_MAISON_INCOHERENTE,
	MOTIF_TUNNEL_IMPRATICABLE,
	MOTIF_COLLECTIBLE_INATTEIGNABLE,
]

# Nombre de places de maison exigees : une par fantome.
const PLACES_ATTENDUES: int = 4


# Verdict STRUCTUREL sur le descripteur brut, AVANT toute construction de carte.
static func verdict_descripteur(desc: Dictionary) -> Dictionary:
	var motifs: Array = []
	var manquants: Array = Schema.champs_manquants(desc)
	if not manquants.is_empty():
		motifs.append(MOTIF_CHAMP_MANQUANT)
		return {"valide": false, "motifs": motifs, "details": manquants}
	var plan = desc["plan"]
	if not (plan is Array) or not Schema.plan_rectangulaire(plan):
		motifs.append(MOTIF_PLAN_NON_RECTANGULAIRE)
		return {"valide": false, "motifs": motifs, "details": []}
	var inconnus: Array = Schema.symboles_inconnus(plan)
	if not inconnus.is_empty():
		motifs.append(MOTIF_SYMBOLE_INCONNU)
		return {"valide": false, "motifs": motifs, "details": inconnus}
	return {"valide": true, "motifs": motifs, "details": []}


# Verdict TOPOLOGIQUE sur la carte construite : depart praticable, maison presente et
# coherente, ligne de bouclage praticable de bout en bout, collectibles tous
# atteignables depuis le depart.
static func verdict_topologie(carte) -> Dictionary:
	var motifs: Array = []
	if not carte.praticable(carte.DEPART_PACMAN):
		motifs.append(MOTIF_DEPART_IMPRATICABLE)
	if not maison_coherente(carte):
		motifs.append(MOTIF_MAISON_INCOHERENTE)
	if not tunnel_praticable(carte):
		motifs.append(MOTIF_TUNNEL_IMPRATICABLE)
	var grille: PackedByteArray = Pellets.poser(carte)
	if not Pellets.tous_atteignables(carte, grille, carte.DEPART_PACMAN):
		motifs.append(MOTIF_COLLECTIBLE_INATTEIGNABLE)
	return {"valide": motifs.is_empty(), "motifs": motifs, "details": []}


# La maison est COHERENTE : quatre places declarees, un centre de type maison, une
# sortie praticable hors de la maison.
static func maison_coherente(carte) -> bool:
	if carte.PLACES_MAISON.size() != PLACES_ATTENDUES:
		return false
	if carte.type_case(carte.MAISON_CENTRE) != Maze.Type.MAISON:
		return false
	if not carte.praticable(carte.SORTIE_MAISON):
		return false
	return true


# La ligne de bouclage est praticable DE BOUT EN BOUT : ses deux extremites sont
# praticables, et le bouclage relie donc reellement les deux bords.
static func tunnel_praticable(carte) -> bool:
	var y: int = carte.LIGNE_TUNNEL
	if y == Schema.LIGNE_ABSENTE:
		return false
	if not carte.praticable(Vector2i(0, y)):
		return false
	if not carte.praticable(Vector2i(carte.LARGEUR - 1, y)):
		return false
	return carte.praticable(carte.boucler(Vector2i(-1, y)))


# VERDICT COMPLET : structure puis topologie. Une carte invalide n'est jamais construite
# a moitie — la topologie n'est examinee que si la structure tient.
static func verifier(desc: Dictionary) -> Dictionary:
	var v: Dictionary = verdict_descripteur(desc)
	if not v["valide"]:
		return v
	var carte = Maze.depuis_descripteur(desc)
	return verdict_topologie(carte)


# CARTE VALIDEE, ou rien. Point de passage OBLIGE entre un descripteur et une partie :
# une carte n'est JAMAIS jouee sans que son verdict ait ete rendu. La carte est `null`
# quand le verdict refuse, et le MOTIF accompagne toujours le refus.
static func carte_validee(desc: Dictionary) -> Dictionary:
	var v: Dictionary = verdict_descripteur(desc)
	if not v["valide"]:
		return {"valide": false, "motifs": v["motifs"], "details": v["details"], "carte": null}
	var carte = Maze.depuis_descripteur(desc)
	var t: Dictionary = verdict_topologie(carte)
	if not t["valide"]:
		return {"valide": false, "motifs": t["motifs"], "details": t["details"], "carte": null}
	return {"valide": true, "motifs": [], "details": [], "carte": carte}
