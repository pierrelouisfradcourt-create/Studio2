# solvability.gd — ligne proof.solvability_bot (point d'entree de l'oracle R9). A la
# racine du projet (categorie godot.project_root), charge par scripts/forge/
# solvability_godot.mjs via `--seed=<n> --max_ticks=<m>`. Un bot DETERMINISTE joue une
# partie complete par le MEME canal d'entree public que le clavier et doit GAGNER.
# Sortie : une ligne `FORGE_TRIAL {"succeeded": bool, "ticks": number|null}`, exit 0.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_policy.gd")

const MAX_TICKS_DEFAUT := 5000

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

	var s = State.initial(graine)
	var t := 0
	while t < max_ticks and s.statut == State.Statut.EN_COURS:
		var action: Vector2i = Bot.choisir_action(s)
		# Le bot PILOTE le canal public : l'action passe par le meme step() que le clavier.
		s = Loop.step(s, action)["etat"]
		t += 1

	var gagne: bool = (s.statut == State.Statut.TERMINE_GAGNE)
	var recu := {"succeeded": gagne, "ticks": (s.ticks if gagne else null)}
	print("FORGE_TRIAL " + JSON.stringify(recu))
	quit(0)
