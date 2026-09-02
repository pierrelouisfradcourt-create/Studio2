# verdict.gd — verdict de solvabilite (ligne solvability.verdict).
#
# CORRECTION B2 (red-team s6) : le PROTOCOLE DE SORTIE n'est PAS un code de retour.
# L'executeur reel — knowledge_base/systems/adapters/godot_trial.mjs — leve des qu'un
# essai sort avec un statut non nul, et scripts/forge/solvability_godot.mjs rend alors
# BLOCKED sans jouer les essais suivants. Un echec s'exprime donc par
# `"succeeded": false` dans le recu, et le processus sort TOUJOURS avec le code 0.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")

const LIBELLE_SOLVABLE := "SOLVABLE"
const LIBELLE_INJOUABLE := "INJOUABLE"
const PREFIXE_RECU := "FORGE_TRIAL "


# Le verdict lu sur l'etat final : GAGNE avec consommes == total pose et restantes == 0.
static func evaluer(s, ticks_joues: int) -> Dictionary:
	var gagne: bool = (
		s.statut == State.Statut.GAGNE
		and s.consommees == s.total_pose
		and s.total_pose - s.consommees == 0
	)
	return {
		"succeeded": gagne,
		"ticks": ticks_joues if gagne else null,
		"libelle": LIBELLE_SOLVABLE if gagne else LIBELLE_INJOUABLE,
		"consommees": s.consommees,
		"total_pose": s.total_pose,
		"statut": s.statut,
	}


# La ligne UNIQUE attendue par l'adaptateur d'essai. Un seul recu par execution.
static func recu(evaluation: Dictionary) -> String:
	return PREFIXE_RECU + JSON.stringify({
		"succeeded": evaluation["succeeded"],
		"ticks": evaluation["ticks"],
	})
