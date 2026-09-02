# map_validator.gd — VERDICT DE VALIDITE d'un descripteur de carte.
#
# Le contenu etant une DONNEE, la donnee malformee est la premiere entree hors domaine du
# jeu. Une carte invalide est declaree telle AVEC SON MOTIF avant d'etre jouee : elle n'est
# pas jouee a moitie. Aucune exception n'est levee — le refus est une VALEUR DE RETOUR.
#
# C'est le point de passage OBLIGE entre l'editeur de carte (a venir) et le runtime : les
# deux consommeront `carte_validee`, jamais deux representations concurrentes.
#
# Logique PURE. Depend de map_schema, arena, grid_nav.
#
# reused_from = CONCEPT (games/pacman/05_SYSTEMS/map_validator/map_validator.gd) pour la
# FORME (verdict structurel PUIS topologique, motifs en vocabulaire ferme, « carte validee
# ou rien ») + CODE_COPIE (grid_nav) pour l'atteignabilite.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")
const Arena = preload("res://05_SYSTEMS/arena/arena.gd")
const GridNav = preload("res://05_SYSTEMS/grid_nav/grid_nav.gd")

# Vocabulaire FERME des motifs de refus, dans l'ordre d'examen declare.
const MOTIF_CHAMP_MANQUANT := "champ_obligatoire_manquant"
const MOTIF_PLAN_NON_RECTANGULAIRE := "plan_non_rectangulaire"
const MOTIF_SYMBOLE_INCONNU := "symbole_hors_legende"
const MOTIF_BORD_NON_SOLIDE := "bord_non_solide"
const MOTIF_SPAWNS_INSUFFISANTS := "spawns_insuffisants"
const MOTIF_SPAWNS_ADJACENTS := "spawns_adjacents"
const MOTIF_SPAWN_ENFERME := "spawn_enferme"
const MOTIF_ARENE_NON_CONNEXE := "arene_non_connexe"
const MOTIF_REGLE_VICTOIRE_INCONNUE := "regle_de_victoire_inconnue"
const MOTIF_POWERUP_INCONNU := "powerup_hors_registre"

const MOTIFS: Array = [
	MOTIF_CHAMP_MANQUANT,
	MOTIF_PLAN_NON_RECTANGULAIRE,
	MOTIF_SYMBOLE_INCONNU,
	MOTIF_BORD_NON_SOLIDE,
	MOTIF_SPAWNS_INSUFFISANTS,
	MOTIF_SPAWNS_ADJACENTS,
	MOTIF_SPAWN_ENFERME,
	MOTIF_ARENE_NON_CONNEXE,
	MOTIF_REGLE_VICTOIRE_INCONNUE,
	MOTIF_POWERUP_INCONNU,
]

const REGLES_VICTOIRE: Array = [P.VICTOIRE_LAST_STANDING, P.VICTOIRE_CLEAR_ALL_BOTS]

# Nombre minimal d'acteurs qu'une carte doit pouvoir accueillir.
const SPAWNS_MINIMUM: int = 2


# Verdict STRUCTUREL sur le descripteur brut, AVANT toute construction d'arene.
static func verdict_descripteur(desc: Dictionary) -> Dictionary:
	var manquants: Array = Schema.champs_manquants(desc)
	if not manquants.is_empty():
		return {"valide": false, "motifs": [MOTIF_CHAMP_MANQUANT], "details": manquants}
	var plan = desc["plan"]
	if not (plan is Array) or not Schema.plan_rectangulaire(plan):
		return {"valide": false, "motifs": [MOTIF_PLAN_NON_RECTANGULAIRE], "details": []}
	var inconnus: Array = Schema.symboles_inconnus(plan)
	if not inconnus.is_empty():
		return {"valide": false, "motifs": [MOTIF_SYMBOLE_INCONNU], "details": inconnus}
	if not Schema.bord_solide(plan):
		return {"valide": false, "motifs": [MOTIF_BORD_NON_SOLIDE], "details": []}
	var regle = desc["victory_rule"]
	if not (regle is String) or not REGLES_VICTOIRE.has(regle):
		return {"valide": false, "motifs": [MOTIF_REGLE_VICTOIRE_INCONNUE], "details": [str(regle)]}
	var pu = desc["powerup_rules"]
	if not (pu is Dictionary):
		return {"valide": false, "motifs": [MOTIF_POWERUP_INCONNU], "details": ["powerup_rules n'est pas une table"]}
	var pu_inconnus: Array = []
	for cle in pu.keys():
		if not P.POWERUP_IDS.has(String(cle)):
			pu_inconnus.append(String(cle))
	if not pu_inconnus.is_empty():
		pu_inconnus.sort()
		return {"valide": false, "motifs": [MOTIF_POWERUP_INCONNU], "details": pu_inconnus}
	return {"valide": true, "motifs": [], "details": []}


# Murs INFRANCHISSABLES EN PERMANENCE : les cases solides seulement. Un destructible est un
# obstacle TEMPORAIRE — l'exiger franchissable ici serait declarer injouable toute arene
# Bomberman normale, dont le principe est justement d'ouvrir le terrain en le detruisant.
static func murs_permanents(arene) -> Dictionary:
	var murs: Dictionary = {}
	for y in range(arene.hauteur):
		for x in range(arene.largeur):
			var c := Vector2i(x, y)
			if arene.est_solide(c):
				murs[c] = true
	return murs


# Verdict TOPOLOGIQUE sur l'arene construite.
static func verdict_topologie(arene, spawns: Array) -> Dictionary:
	var motifs: Array = []
	var details: Array = []

	if spawns.size() < SPAWNS_MINIMUM:
		motifs.append(MOTIF_SPAWNS_INSUFFISANTS)
		details.append("%d spawn(s) pour %d minimum" % [spawns.size(), SPAWNS_MINIMUM])
		return {"valide": false, "motifs": motifs, "details": details}

	# Deux spawns adjacents rendraient la premiere bombe imparable : c'est une regle de
	# jouabilite, pas une coquetterie.
	for i in range(spawns.size()):
		for j in range(i + 1, spawns.size()):
			var d: Vector2i = spawns[i] - spawns[j]
			if abs(d.x) + abs(d.y) <= 1:
				motifs.append(MOTIF_SPAWNS_ADJACENTS)
				details.append("%s et %s" % [str(spawns[i]), str(spawns[j])])

	# Un spawn sans aucune sortie est une mort garantie au premier tick.
	var murs: Dictionary = murs_permanents(arene)
	for s in spawns:
		var sorties: int = 0
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if not arene.est_solide(s + d):
				sorties += 1
		if sorties == 0:
			motifs.append(MOTIF_SPAWN_ENFERME)
			details.append(str(s))

	# CONNEXITE : chaque spawn doit pouvoir en atteindre un autre une fois les
	# destructibles retires. Mesure par la brique BFS copiee (CODE_COPIE grid_nav) —
	# `path_length` rend -1 si inatteignable.
	for i in range(1, spawns.size()):
		if GridNav.path_length(spawns[0], spawns[i], murs) < 0:
			motifs.append(MOTIF_ARENE_NON_CONNEXE)
			details.append("%s inatteignable depuis %s" % [str(spawns[i]), str(spawns[0])])

	return {"valide": motifs.is_empty(), "motifs": motifs, "details": details}


# VERDICT COMPLET : structure puis topologie. Une carte invalide n'est jamais construite a
# moitie — la topologie n'est examinee que si la structure tient.
static func verifier(desc: Dictionary) -> Dictionary:
	var v: Dictionary = verdict_descripteur(desc)
	if not v["valide"]:
		return v
	var arene = Arena.depuis_descripteur(desc)
	return verdict_topologie(arene, Schema.spawn_points(desc["plan"]))


# CARTE VALIDEE, ou rien. Point de passage OBLIGE entre un descripteur et une partie : une
# carte n'est JAMAIS jouee sans que son verdict ait ete rendu. `arene` vaut `null` quand le
# verdict refuse, et le MOTIF accompagne toujours le refus.
static func carte_validee(desc: Dictionary) -> Dictionary:
	var v: Dictionary = verdict_descripteur(desc)
	if not v["valide"]:
		return {"valide": false, "motifs": v["motifs"], "details": v["details"],
			"arene": null, "spawns": []}
	var arene = Arena.depuis_descripteur(desc)
	var spawns: Array = Schema.spawn_points(desc["plan"])
	var t: Dictionary = verdict_topologie(arene, spawns)
	if not t["valide"]:
		return {"valide": false, "motifs": t["motifs"], "details": t["details"],
			"arene": null, "spawns": []}
	return {"valide": true, "motifs": [], "details": [], "arene": arene, "spawns": spawns}
