extends "res://jeu/ville/onglet.gd"
## Labo du feel : l'onglet ne fait qu'accueillir le panneau réutilisable (panneau_labo.tscn),
## qui se tient à jour seul sur `app.reglages_change`.

@onready var panneau: Control = $PanneauLabo

func brancher(p_app: Node, p_partie: Node) -> void:
	super(p_app, p_partie)
	panneau.brancher(p_app, p_partie)
