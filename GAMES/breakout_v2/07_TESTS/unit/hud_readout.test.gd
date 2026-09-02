# hud_readout.test.gd — ligne render.hud_lives_score (volet texte). Le texte affiche se
# re-parse EXACTEMENT en la valeur de l'etat (round-trip strict) : aucun ecart lu/reel.
extends RefCounted

const Hud = preload("res://06_RUNTIME/adapters/presentation/hud.gd")

func run(h) -> void:
	# --- format ---
	h.eq(Hud.texte_vies(3), "Vies: 3", "texte vies formate")
	h.eq(Hud.texte_score(120), "Score: 120", "texte score formate")

	# --- round-trip STRICT vies ---
	for vi in [0, 1, 3, 17]:
		h.eq(Hud.valeur_vies_depuis_texte(Hud.texte_vies(vi)), vi, "round-trip vies = " + str(vi))

	# --- round-trip STRICT score ---
	for sc in [0, 10, 250, 9990]:
		h.eq(Hud.valeur_score_depuis_texte(Hud.texte_score(sc)), sc, "round-trip score = " + str(sc))
