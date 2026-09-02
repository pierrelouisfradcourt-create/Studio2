# test_game_state.gd — R7 Fin par blocage. Spawn legal -> continue ; spawn illegal (pile bloque
# l'entree) -> etat TERMINAL (game-over). Marathon : aucun etat gagne (2 statuts distincts).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

func run(h) -> void:
	# Deux statuts distincts, pas de victoire.
	h.ok(State.Statut.EN_COURS != State.Statut.GAME_OVER, "EN_COURS != GAME_OVER (pas d'etat gagne)")
	# Spawn legal sur puits vide.
	var s = State.initial(1)
	h.eq(s.status, State.Statut.EN_COURS, "etat initial en cours")
	h.eq(s.active.is_empty(), false, "premiere piece apparue")
	var before: int = s.pieces_spawned
	var ok: bool = s.spawn_piece(0)
	h.eq(ok, true, "spawn legal -> true")
	h.eq(s.status, State.Statut.EN_COURS, "toujours en cours apres spawn legal")
	h.eq(s.pieces_spawned, before + 1, "pieces_spawned +1 exact")
	# Spawn illegal : la pile remplit la zone d'entree -> game-over.
	var s2 = State.initial(1)
	for x in range(P.COLS):
		s2.grid[0][x] = 9
		s2.grid[1][x] = 9
	var ok2: bool = s2.spawn_piece(2)
	h.eq(ok2, false, "spawn bloque -> false")
	h.eq(s2.status, State.Statut.GAME_OVER, "spawn bloque -> game-over (R7)")
