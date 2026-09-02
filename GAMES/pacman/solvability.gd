# solvability.gd — point d'entree de l'oracle de solvabilite R9 (lignes
# solvability.verdict, bot.solvability_per_map).
# A la racine du projet (categorie godot.project_root), charge par
# scripts/forge/solvability_godot.mjs via `--seed=<n> --max_ticks=<m>`.
#
# Un bot DETERMINISTE joue une partie complete par le MEME canal d'entree public que le
# clavier, en BOUCLE FERMEE (il relit l'etat courant a chaque tick), et doit GAGNER.
#
# V2 — COUVERTURE MULTI-CARTES : la GRAINE selectionne la carte du catalogue, par
# (graine - 1) modulo le nombre de cartes. Les 50 essais de l'oracle exercent donc
# REELLEMENT chaque carte embarquee : prouver la solvabilite cinquante fois sur la
# premiere carte ne dirait rien de la seconde.
#
# PROTOCOLE DE SORTIE (correction B2, red-team s6) : une seule ligne
# `FORGE_TRIAL {"succeeded": bool, "ticks": number|null}` puis `quit(0)` DANS TOUS LES
# CAS. L'echec s'exprime par `succeeded: false`, jamais par un code de retour non nul :
# knowledge_base/systems/adapters/godot_trial.mjs leve sur tout statut non nul, ce qui
# ferait rendre BLOCKED a l'oracle au lieu de FAIL, et arreterait les essais suivants.
extends SceneTree

const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/solvability_bot.gd")
const Verdict = preload("res://06_RUNTIME/adapters/solvability_bot/verdict.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const Probe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")

const MAX_TICKS_DEFAUT := 20000


func _lire_arg(nom: String, defaut: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(nom + "="):
			var v := a.substr((nom + "=").length())
			if v.is_valid_int():
				return int(v)
	return defaut


func _initialize() -> void:
	var graine := _lire_arg("--seed", 1)
	var max_ticks := _lire_arg("--max_ticks", MAX_TICKS_DEFAUT)
	if max_ticks <= 0:
		max_ticks = MAX_TICKS_DEFAUT

	# La graine choisit la carte : chaque carte du catalogue est reellement exercee.
	var index := Bot.index_de_la_graine(graine, Shell.nb_niveaux())
	var carte = Shell.carte(index)
	var evaluation: Dictionary = Bot.jouer_carte(carte, graine, max_ticks, Shell.cadence(index))

	# Releve de diagnostic sur un canal DISTINCT du recu (prefixe different, donc jamais
	# confondu) : un essai perdu doit pouvoir etre DIAGNOSTIQUE — carte, defaite, budget
	# epuise ou collectibles restants — sans relancer une instrumentation ad hoc.
	print("PACMAN_TRIAL ", JSON.stringify({
		"seed": graine,
		"index_carte": index,
		"carte": evaluation.get("carte", ""),
		"consommees": evaluation["consommees"],
		"total_pose": evaluation["total_pose"],
		"statut": evaluation["statut"],
	}))
	print(Verdict.recu(evaluation))
	quit(0)
