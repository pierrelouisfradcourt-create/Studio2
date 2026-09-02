# runtime_loop.gd — ligne runtime.fixed_step_accumulator. Cadenceur du produit : convertit le
# temps ecoule reel en nombre de ticks de simulation a PAS FIXE. RATTRAPAGE BORNE : chaque tick
# consomme EXACTEMENT un pas (acc -= pas) et le RESTE fractionnaire est CONSERVE dans
# l'accumulateur -> le nombre de ticks pour une duree cumulee donnee ne depend PAS du decoupage
# des trames (donc pas du framerate). Un plafond nomme (params.MAX_TICKS_PAR_FRAME) borne le
# nombre de ticks par appel pour ne jamais spiraler apres une trame tres longue ; au-dela du
# plafond, le surplus est JETE (voir commentaire dans avancer). Logique d'accumulation PURE et
# testable en headless ; le pilote de scene (Node) l'appelle avec le delta reel du moteur. C'est
# ICI, dans l'ADAPTATEUR, que le delta du moteur entre et est arrete : la logique pure
# (05_SYSTEMS) ne le voit jamais. RefCounted.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Pas fixe du cadenceur, en millisecondes (derive du pas de simulation, un seul porteur).
static func pas_ms() -> float:
	return P.TICK_DT_FIXED_MS

# Avance l'accumulateur et decide combien de ticks appliquer.
#   accumulateur_ms : temps accumule non consomme (ms)
#   delta_ms        : temps ecoule depuis le dernier appel (ms) — vient du moteur en runtime
#   gelee           : gel strict (fin de partie) -> aucun temps accumule, aucun tick
# Renvoie {"ticks": int (0..MAX_TICKS_PAR_FRAME), "accumulateur": float (reste, < un pas hors gel)}.
# RATTRAPAGE BORNE : on RETRANCHE un pas entier par tick (acc -= pas) et on CONSERVE le reste
# fractionnaire -> N trames de duree cumulee T produisent floor(T/pas) ticks quel que soit le
# decoupage des trames (propriete DURABLE, independante du framerate). Le nombre de ticks par
# appel est plafonne a MAX_TICKS_PAR_FRAME pour ne jamais spiraler ; le surplus AU-DELA du
# plafond est JETE (l'accumulateur est ramene sous un pas) — decision assumee : mieux vaut
# perdre un retard ingerable qu'accumuler une dette de ticks qui figerait le jeu.
static func avancer(accumulateur_ms: float, delta_ms: float, gelee: bool) -> Dictionary:
	if gelee:
		return {"ticks": 0, "accumulateur": accumulateur_ms}
	var pas: float = pas_ms()
	var acc: float = accumulateur_ms + delta_ms
	var ticks: int = 0
	while acc >= pas and ticks < P.MAX_TICKS_PAR_FRAME:
		acc -= pas
		ticks += 1
	# Plafond atteint alors qu'il resterait des ticks a appliquer : SURPLUS JETE, on ne garde
	# que le reste fractionnaire (sous un pas) pour ne pas spiraler la trame suivante.
	if acc >= pas:
		acc = fmod(acc, pas)
	return {"ticks": ticks, "accumulateur": acc}
