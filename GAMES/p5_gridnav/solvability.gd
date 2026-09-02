# Oracle de solvabilite (R9 : « un bot doit reellement gagner ») pour Patrol.
# Un bot deterministe utilise Patrol.next_step pour atteindre la sortie d'un
# labyrinthe seede, sous max_ticks. succeeded=true UNIQUEMENT si la sortie est
# reellement atteinte (boucle explicite pas-a-pas, jamais deduit).
#
# Purete du generateur (invariant obligatoire) : la carte est creusee SANS
# jamais interroger Patrol (ni next_step, ni path_length). Si le generateur
# demandait a la brique testee si un chemin existe, un next_step casse ne
# pourrait plus jamais etre detecte (le chemin de secours serait garanti par
# construction ET valide par la meme brique). Le chemin de secours est donc
# creuse inconditionnellement, a partir du seul seed.
#
# Lancer : godot --headless --path games/p5_gridnav --script res://solvability.gd -- --seed=<N> --max_ticks=<N>
# Emet   : FORGE_TRIAL {"succeeded": bool, "ticks": number|null}
# Exit   : 0 (toujours), ou 2 si argument manquant/invalide.
extends SceneTree

const Patrol = preload("res://core/patrol.gd")
const PREFIX := "FORGE_TRIAL "
const MAZE_WIDTH := 16
const MAZE_HEIGHT := 16
const DEFAULT_MAX_TICKS := 200

func _initialize() -> void:
	var args := _parse_args()
	if not args.has("seed"):
		printerr("argument --seed=<N> manquant")
		quit(2)
		return

	var seed_str: String = args["seed"]
	if not seed_str.is_valid_int():
		printerr("--seed argument doit etre un entier valide")
		quit(2)
		return

	var seed_value: int = int(seed_str)

	var max_ticks := DEFAULT_MAX_TICKS
	if args.has("max_ticks"):
		var max_ticks_str: String = args["max_ticks"]
		if max_ticks_str.is_valid_int():
			max_ticks = int(max_ticks_str)

	var result := solve(seed_value, max_ticks)

	print(PREFIX + JSON.stringify(result))
	quit(0)

## Fait jouer le bot Patrol.next_step sur une grille seedee, pas a pas, jusqu'a
## la cible ou jusqu'a max_ticks. Ne DEDUIT jamais le succes : ne renvoie
## succeeded=true que si la position finale EST reellement la cible.
## Retourne {"succeeded": bool, "ticks": int|null}.
func solve(seed: int, max_ticks: int) -> Dictionary:
	var grille := _generate_grid_deterministic(seed, MAZE_WIDTH, MAZE_HEIGHT)
	var start_pos := Vector2i(1, 1)
	var target_pos := Vector2i(MAZE_WIDTH - 2, MAZE_HEIGHT - 2)

	var ticks := 0
	var current_pos := start_pos
	while ticks < max_ticks and current_pos != target_pos:
		var next_pos: Vector2i = Patrol.next_step(grille, current_pos, target_pos)
		if next_pos == current_pos:
			# next_step ne progresse plus (cible inatteignable depuis ici) :
			# echouer explicitement plutot que consommer les ticks restants.
			break
		current_pos = next_pos
		ticks += 1

	var succeeded: bool = (current_pos == target_pos)
	return {"succeeded": succeeded, "ticks": (ticks if succeeded else null)}

## Genere une grille traversable/obstacle deterministe a partir du seed.
## Format Array[Array[bool]] (true=traversable), meme convention que patrol.gd.
## Hash lineaire (seed, x, y), aucun alea non seede (randi/randf/randomize/Time.*
## interdits). Un chemin de secours est ensuite creuse INCONDITIONNELLEMENT,
## sans jamais consulter Patrol (cf. en-tete du fichier).
func _generate_grid_deterministic(seed: int, width: int, height: int) -> Array:
	var grille := []
	var mod := 65521  # nombre premier
	for y in range(height):
		var row := []
		for x in range(width):
			var pos_hash: int = ((seed * (x + y * width)) + x * 73 + y * 83) % mod
			var wall: bool = (pos_hash % 10) > 3
			row.append(not wall)
		grille.append(row)

	var start := Vector2i(1, 1)
	var target := Vector2i(width - 2, height - 2)
	grille[start.y][start.x] = true
	grille[target.y][target.x] = true

	_carve_fallback_path(seed, width, height, start, target, grille)

	return grille

## Repli de secours : creuse un chemin monotone (n'avance que vers la cible)
## seede, UNIQUEMENT quand la grille issue du hash seul est injouable pour
## cette graine precise. Mute grille en place (fonction de secours interne,
## pas la brique publique Patrol).
func _carve_fallback_path(seed: int, width: int, height: int, start: Vector2i, target: Vector2i, grille: Array) -> void:
	var mod := 65521
	var cursor := start
	var step_index := 0
	var max_steps := width + height  # borne dure : un chemin monotone ne depasse jamais width+height pas
	while cursor != target and step_index < max_steps:
		var dx := target.x - cursor.x
		var dy := target.y - cursor.y
		var can_h := dx != 0
		var can_v := dy != 0
		var choose_horizontal: bool
		if can_h and can_v:
			var h: int = ((seed * 97) + step_index * 131 + cursor.x * 17 + cursor.y * 19) % mod
			choose_horizontal = (h % 2) == 0
		elif can_h:
			choose_horizontal = true
		else:
			choose_horizontal = false
		if choose_horizontal:
			cursor.x += (1 if dx > 0 else -1)
		else:
			cursor.y += (1 if dy > 0 else -1)
		grille[cursor.y][cursor.x] = true
		step_index += 1

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var parts := a.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
