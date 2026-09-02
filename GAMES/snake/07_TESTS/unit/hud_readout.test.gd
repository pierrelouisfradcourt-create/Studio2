# hud_readout.test.gd — ligne render.hud_numbers. Le texte lu a l'ecran et la valeur de
# l'etat expose sont STRICTEMENT EGAUX : le nombre affiche se re-parse EXACTEMENT en la
# valeur d'origine, pour le score courant et le meilleur score. Testable en headless.
extends RefCounted

const HUD = preload("res://06_RUNTIME/adapters/presentation/hud.gd")

func run(h) -> void:
	h.eq(HUD.valeur_score_depuis_texte(HUD.texte_score(0)), 0, "score 0 : texte<->etat egaux")
	h.eq(HUD.valeur_score_depuis_texte(HUD.texte_score(42)), 42, "score 42 : texte<->etat egaux")
	h.eq(HUD.valeur_meilleur_depuis_texte(HUD.texte_meilleur(0)), 0, "record 0 : texte<->etat egaux")
	h.eq(HUD.valeur_meilleur_depuis_texte(HUD.texte_meilleur(7)), 7, "record 7 : texte<->etat egaux")
