# best_score.gd — ligne bestscore.pure. Logique PURE du meilleur score : max(ancien,
# final). Vit HORS de l'etat de partie ; ne touche jamais FileAccess ; n'est lu par
# AUCUNE regle de jeu (etancheite). RefCounted.
extends RefCounted

# max(ancien, score_final). Une seule mise a jour, a l'entree dans un statut terminal.
static func mettre_a_jour(ancien: int, score_final: int) -> int:
	return max(ancien, score_final)
