extends Node
## Fausse vue Entrees pour le test des écrans : le contrat de jeu/entrees/entrees.gd vu d'Ecrans
## (signal `pause_demandee`, `vider()`, `tactile()`), sans rien lire du clavier ni de l'écran.

signal pause_demandee

var est_tactile := false
var vidages := 0
var visee := Vector2.ZERO # ce que `visee_bureau()` rend (posé par l'essai)

func vider() -> void:
	vidages += 1

func tactile() -> bool:
	return est_tactile

func visee_bureau() -> Vector2:
	return visee

func lire() -> Dictionary:
	return D6Game.empty_input()
