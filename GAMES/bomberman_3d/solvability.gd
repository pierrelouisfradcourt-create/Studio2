# solvability.gd — point d'entree de l'oracle de solvabilite R9.
# A la racine du projet (categorie godot.project_root), lance par
# scripts/forge/solvability_godot.mjs via `--seed=<n> --max_ticks=<m>`.
#
# CE QUI EST EXIGE ICI, ET POURQUOI C'EST PLUS DUR QU'UNE VICTOIRE :
# un bot qui ne pose JAMAIS de bombe survit tres bien et peut « gagner » un LAST_STANDING
# par elimination mutuelle des autres. Le critere est donc une VICTOIRE PAR ELIMINATION
# ACTIVE : le bot doit gagner ET au moins une mort adverse doit lui etre ATTRIBUEE.
# Sans cette clause on prouverait la survie, pas la jouabilite — mode de panne deja
# constate sur survival_arena et collect_runner (oracles verts, jeu injouable).
#
# Le bot joue par le MEME canal d'entree public que le clavier (une intention par tick,
# passee a Loop.step) et relit l'etat a chaque tick : boucle fermee, aucune ecriture
# directe dans l'etat.
#
# PROTOCOLE DE SORTIE : une seule ligne
# `FORGE_TRIAL {"succeeded": bool, "ticks": number|null}` puis `quit(0)` DANS TOUS LES CAS.
# L'echec s'exprime par `succeeded: false`, jamais par un code de retour non nul :
# knowledge_base/systems/adapters/godot_trial.mjs leve sur tout statut non nul, ce qui
# ferait rendre BLOCKED a l'oracle au lieu de FAIL.
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const Content = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_policy.gd")

const MAX_TICKS_DEFAUT := 12000
const NB_ACTEURS := 4


func _lire_arg(nom: String, defaut: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(nom + "="):
			var v := a.substr((nom + "=").length())
			if v.is_valid_int():
				return int(v)
	return defaut


# Releve de position, pour le canal de DIAGNOSTIC seulement. Un essai perdu doit pouvoir
# etre lu : « ou etait chacun a la fin » distingue un bot bloque d'un bot qui tourne.
func _positions(s) -> Array:
	var out: Array = []
	for a in s.acteurs:
		out.append({"c": [a["cellule"].x, a["cellule"].y], "vivant": a["vivant"],
			"r": a["rayon"], "b": a["bombes_max"]})
	return out


func _initialize() -> void:
	var graine := _lire_arg("--seed", 1)
	var max_ticks := _lire_arg("--max_ticks", MAX_TICKS_DEFAUT)
	if max_ticks <= 0:
		max_ticks = MAX_TICKS_DEFAUT

	# La graine selectionne la carte : chaque carte du catalogue est reellement exercee.
	var index := (graine - 1) % Content.nb_cartes()
	var desc: Dictionary = Content.descripteur(index)
	var carte: Dictionary = Validator.carte_validee(desc)
	if not carte["valide"]:
		print("FORGE_DIAG ", JSON.stringify({"raison": "carte refusee", "motifs": carte["motifs"]}))
		print("FORGE_TRIAL ", JSON.stringify({"succeeded": false, "ticks": null}))
		quit(0)
		return

	# VARIANCE MESUREE, pas decorative. La politique du bot est deterministe et ne consulte
	# pas la graine : sans rotation, les 50 essais rejoueraient EXACTEMENT la meme partie et
	# l'oracle n'aurait aucun pouvoir discriminant (mesure du 2026-08-10 : 3 graines, 3
	# diagnostics identiques au caractere pres). La graine fait donc tourner l'ATTRIBUTION
	# DES SPAWNS, ce qui exerce reellement les quatre coins de l'arene.
	var spawns: Array = carte["spawns"].duplicate()
	var decalage: int = (graine - 1) % max(1, spawns.size())
	var tournes: Array = []
	for i in range(spawns.size()):
		tournes.append(spawns[(i + decalage) % spawns.size()])
	carte["spawns"] = tournes

	var s = State.initial(carte, desc, graine, NB_ACTEURS)
	var ticks := 0
	while s.statut == P.EN_COURS and ticks < max_ticks:
		var intentions: Array = []
		for i in range(s.acteurs.size()):
			# Seul l'acteur 0 est AGRESSIF. Les adversaires fuient et se deplacent mais ne
			# posent jamais de bombe : si le bot teste gagne, ce n'est pas parce que les
			# autres se sont entretues.
			intentions.append(Bot.decider(s, i, i == P.INDEX_JOUEUR))
		s = Loop.step(s, intentions)["state"]
		ticks += 1

	# ELIMINATION ACTIVE : au moins une mort adverse attribuee a une bombe du bot teste.
	var kills := 0
	for m in s.morts:
		if int(m["tueur"]) == P.INDEX_JOUEUR and int(m["victime"]) != P.INDEX_JOUEUR:
			kills += 1

	var gagne: bool = s.statut == P.GAGNE
	var reussi: bool = gagne and kills > 0

	# Releve de diagnostic sur un canal DISTINCT du recu (prefixe different, donc jamais
	# confondu) : un essai perdu doit pouvoir etre DIAGNOSTIQUE.
	print("FORGE_DIAG ", JSON.stringify({
		"graine": graine, "carte": index, "statut": s.statut, "ticks": ticks,
		"gagne": gagne, "kills_du_bot": kills, "morts": s.morts.size(),
		"vivants": s.vivants().size(),
		"destructibles_restants": s.arene.nb_destructibles(),
		"budget_epuise": ticks >= max_ticks,
		"morts_detail": s.morts,
		"powerups_au_sol": s.powerups.size(),
		"densite_lue": s.densite_powerup,
		"poids_lus": s.poids_powerup,
		"positions": _positions(s),
		"bombes_en_cours": s.bombes.size(),
	}))
	print("FORGE_TRIAL ", JSON.stringify({
		"succeeded": reussi, "ticks": (ticks if reussi else null)
	}))
	quit(0)
