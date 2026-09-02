# chase_clock_thresholds.test.gd — ligne chase.clock, capacite F25.
# Pour CHACUN des six seuils : l'etat juste avant, EXACTEMENT au seuil et juste apres
# correspond a la sequence declaree. Aucun retour en dispersion apres le sixieme seuil.
extends RefCounted

const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")


func run(h) -> void:
	var seuils: Array = Chase.seuils()
	h.eq(seuils.size(), 6, "chase.clock: six seuils exactement")
	h.eq(Chase.SEGMENTS.size(), 6, "chase.clock: six segments exactement")

	# Les seuils sont STRICTEMENT croissants : une sequence finie et ordonnee.
	var non_croissants: int = 0
	for i in range(1, seuils.size()):
		if not (seuils[i] > seuils[i - 1]):
			non_croissants += 1
	h.eq(non_croissants, 0, "chase.clock: seuils strictement croissants")
	h.eq(seuils, [133, 180, 313, 360, 493, 526], "chase.clock: valeurs cumulees exactes")

	# Pour chaque seuil : juste avant, au seuil, juste apres — valeurs STRICTES.
	for i in range(seuils.size()):
		var seuil: int = seuils[i]
		var avant: int = Chase.mode_global(seuil - 1)
		var au: int = Chase.mode_global(seuil)
		var apres: int = Chase.mode_global(seuil + 1)
		h.eq(avant, Chase.SEGMENTS[i][0], "chase.clock: seuil %d, juste avant" % seuil)
		h.ok(au != avant, "chase.clock: seuil %d, le mode CHANGE au seuil" % seuil)
		h.eq(au, apres, "chase.clock: seuil %d, le nouveau mode tient juste apres" % seuil)

	# Le premier segment commence en poursuite au tick 0 (worldscan, niveaux 1-4).
	h.eq(Chase.mode_global(0), Chase.Mode.POURSUITE, "chase.clock: poursuite au tick 0")

	# Aucun retour en dispersion apres le sixieme seuil : poursuite PERMANENTE.
	var dernier: int = seuils[seuils.size() - 1]
	var retours: int = 0
	for t in range(dernier, dernier + 500):
		if Chase.mode_global(t) == Chase.Mode.DISPERSION:
			retours += 1
	h.eq(retours, 0, "chase.clock: aucun retour en dispersion sur 500 ticks apres le sixieme seuil")
	h.eq(Chase.mode_global(dernier), Chase.MODE_FINAL, "chase.clock: mode final au sixieme seuil")

	# est_seuil ne reconnait QUE les six seuils : ni un de plus, ni un de moins.
	var faux_seuils: int = 0
	for t in range(0, dernier + 20):
		if Chase.est_seuil(t) != seuils.has(t):
			faux_seuils += 1
	h.eq(faux_seuils, 0, "chase.clock: est_seuil reconnait exactement les six seuils")
