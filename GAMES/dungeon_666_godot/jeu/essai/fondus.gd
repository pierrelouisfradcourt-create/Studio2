extends RefCounted
## Pour les ESSAIS sans fenêtre : laisser finir les fondus avant de libérer le jeu ou de quitter.
## Un fondu d'écran (StudioTransitions du kit : une coroutine qui attend la fin de son
## interpolation) coupé net par la libération de son nœud reste en mémoire jusqu'à la sortie, et
## Godot l'écrit : « ObjectDB instances leaked at exit ». Dans le jeu, cela n'arrive que si l'on
## ferme la fenêtre pendant un fondu (0,3 s), à l'instant où tout est rendu au système ; dans un
## essai, à chaque `app.free()`. Attendre ici garde ce message pour les vraies fuites.
##   await Fondus.laisser_finir(self)   # depuis un script SceneTree

const MAX_MS := 1000 # borne en temps réel : une interpolation sans fin n'arrête pas l'essai

static func laisser_finir(arbre: SceneTree) -> void:
	var limite := Time.get_ticks_msec() + MAX_MS
	while not arbre.get_processed_tweens().is_empty() and Time.get_ticks_msec() < limite:
		await arbre.process_frame
