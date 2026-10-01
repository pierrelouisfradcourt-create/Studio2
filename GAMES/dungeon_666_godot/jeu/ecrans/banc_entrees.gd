extends Node
## Fausse vue Entrees pour le test des écrans : le contrat de jeu/entrees/entrees.gd vu d'Ecrans
## (signal `pause_demandee`, `vider()`, `tactile()`), sans rien lire du clavier ni de l'écran.

signal pause_demandee

var est_tactile := false
var vidages := 0

func vider() -> void:
	vidages += 1

func tactile() -> bool:
	return est_tactile

func lire() -> Dictionary:
	return D6Game.empty_input()
