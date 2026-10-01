extends "res://jeu/principal.gd"
## Le VRAI `jeu/principal.gd`, pour le banc et le test des écrans : mêmes actions, mêmes signaux.
## Seules différences : on choisit les vues montées (un banc ne dépend pas des lots voisins),
## on peut glisser une fausse vue Entrees, et chaque commande de menu est notée au journal avec
## la réponse de la simulation (acceptée ou refusée).

const FausseEntrees = preload("res://jeu/ecrans/banc_entrees.gd")

## Noms des vues à monter (« monde », « hud », « ecrans »…) ; vide : toutes.
var vues_voulues: Array = ["ecrans"]
## Vrai : une fausse vue Entrees (pause_demandee, vider, tactile) est posée à la place de la vraie.
var fausses_entrees := false
## Les commandes envoyées par les écrans : {cmd, ok, mode} (mode : celui de la partie juste après).
var journal: Array = []

func _monter(chemin: String) -> void:
	var nom := chemin.get_file().get_basename()
	if nom == "entrees" and fausses_entrees:
		var fausse := FausseEntrees.new()
		fausse.name = "Entrees"
		add_child(fausse)
		vues[nom] = fausse
		return
	if vues_voulues.is_empty() or nom in vues_voulues:
		super(chemin)

func commande(cmd: Dictionary) -> bool:
	var ok := super(cmd)
	journal.append({"cmd": cmd, "ok": ok, "mode": partie.game.mode if partie.game != null else "town"})
	return ok
