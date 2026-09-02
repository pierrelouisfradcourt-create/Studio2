# runtime_loop.gd — ligne runtime.loop_no_catchup. Cadenceur du produit : convertit le
# temps ecoule reel en nombre de ticks a appliquer, SANS RATTRAPAGE (au plus 1 tick par
# appel, le surplus est jete). La logique d'accumulation est PURE et testable en headless ;
# le pilote de scene (Node) l'appelle avec le delta reel du moteur. RefCounted comme
# input_adapter : aucun Node requis pour raisonner sur l'accumulateur.
extends RefCounted

# Avance l'accumulateur d'un delta et decide combien de ticks appliquer.
#   accumulateur_ms : temps accumule non encore consomme (ms)
#   delta_ms        : temps ecoule depuis le dernier appel (ms) — vient du moteur en runtime
#   periode_ms      : periode d'un tick (etat.periode, derivee de params — jamais un litteral)
#   en_pause        : gel strict — aucun temps n'est accumule, aucun tick applique
# Renvoie {"ticks": int (0 ou 1), "accumulateur": float}.
# AUCUN RATTRAPAGE : meme apres une privation d'execution enorme, AU PLUS 1 tick est
# applique et le surplus d'accumulateur est JETE (remis a 0). Un serpent ne saute jamais
# 25 cases parce que la fenetre a gele 5 s.
static func avancer(accumulateur_ms: float, delta_ms: float, periode_ms: float, en_pause: bool) -> Dictionary:
	if en_pause:
		# Pause : l'accumulateur ne bouge pas, aucun tick. Reprise strictement neutre.
		return {"ticks": 0, "accumulateur": accumulateur_ms}
	var acc: float = accumulateur_ms + delta_ms
	if acc < periode_ms:
		return {"ticks": 0, "accumulateur": acc}
	# Seuil atteint : EXACTEMENT 1 tick, le reste du temps est perdu (pas de rattrapage).
	return {"ticks": 1, "accumulateur": 0.0}
