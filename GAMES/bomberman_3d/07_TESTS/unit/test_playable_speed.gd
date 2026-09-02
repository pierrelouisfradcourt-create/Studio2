# test_playable_speed.gd — BANDE DE JOUABILITE HUMAINE, verifiee en SECONDES.
#
# Pourquoi ce fichier existe. Retour Pierre du 2026-08-10 : « c'est trop rapide pour un
# humain ». Le jeu tournait a 10 cases/seconde avec une meche de 0,50 s, et AUCUN oracle ne
# pouvait le voir : toutes les durees etaient en ticks, et la base de temps vivait dans un
# autre fichier (runtime_loop). Une constante dont personne ne peut calculer l'unite n'est
# pas verifiable — elle est seulement plausible.
#
# Ce volet convertit et BORNE. Les bandes sont declarees ici, en clair, et un futur
# recalibrage qui sortirait de la bande echouera au lieu de passer en silence.
# Capacite visee : `game.playable_speed` (registre standard).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Bandes humaines declarees. Sources : cadence d'un Bomberman du commerce (personnage a
# quelques cases par seconde, meche de l'ordre de 2 a 3 s, manche de 1 a 3 minutes).
const CASES_S_MIN := 2.0
const CASES_S_MAX := 6.0
const CASES_S_MAX_BOOST := 10.0
const MECHE_S_MIN := 1.8
const MECHE_S_MAX := 3.5
const FLAMME_S_MIN := 0.25
const FLAMME_S_MAX := 1.2
const MANCHE_S_MIN := 45.0
const MANCHE_S_MAX := 240.0


func _sec(ticks: int) -> float:
	return float(ticks) / float(P.TICKS_PAR_SECONDE)


func _dans(h, v: float, lo: float, hi: float, nom: String) -> void:
	h.ok(v >= lo and v <= hi, "%s = %.2f (bande [%.2f, %.2f])" % [nom, v, lo, hi])


func run(h) -> void:
	h.gt(P.TICKS_PAR_SECONDE, 0, "vitesse: la base de temps est declaree et positive")

	# --- deplacement ---
	var cases_s: float = float(P.TICKS_PAR_SECONDE) / float(P.MOVE_COOLDOWN_BASE)
	_dans(h, cases_s, CASES_S_MIN, CASES_S_MAX, "vitesse: cases/s a vitesse initiale")
	var cases_s_max: float = float(P.TICKS_PAR_SECONDE) / float(P.MOVE_COOLDOWN_MIN)
	_dans(h, cases_s_max, CASES_S_MIN, CASES_S_MAX_BOOST, "vitesse: cases/s au plafond de SPEED_UP")
	h.gt(cases_s_max, cases_s, "vitesse: SPEED_UP accelere reellement")

	# --- bombes ---
	_dans(h, _sec(P.MECHE_TICKS), MECHE_S_MIN, MECHE_S_MAX, "vitesse: duree de meche (s)")
	_dans(h, _sec(P.DUREE_FLAMME), FLAMME_S_MIN, FLAMME_S_MAX, "vitesse: duree de flamme (s)")

	# La meche doit laisser de quoi sortir de sa propre croix a rayon maximal, sinon poser
	# une bombe serait un suicide garanti pour un humain.
	var pas_pendant_meche: int = P.MECHE_TICKS / P.MOVE_COOLDOWN_BASE
	h.gt(pas_pendant_meche, P.RAYON_MAX,
		"vitesse: la meche laisse plus de pas que le rayon maximal (fuite possible)")

	# --- manche ---
	var fermeture_ticks: int = 143 * P.MORT_SUBITE_PERIODE
	var manche_s: float = _sec(P.MORT_SUBITE_DEBUT + fermeture_ticks)
	_dans(h, manche_s, MANCHE_S_MIN, MANCHE_S_MAX, "vitesse: duree bornee d'une manche (s)")
	h.gt(_sec(P.MORT_SUBITE_DEBUT), 30.0,
		"vitesse: la mort subite laisse au moins 30 s de jeu ouvert")
	h.ok(P.DUREE_MAX_TICKS > P.MORT_SUBITE_DEBUT + fermeture_ticks,
		"vitesse: le nul par duree ne coupe pas la partie AVANT la fin de la fermeture")

	# --- coherence interne des bornes ---
	h.ok(P.MOVE_COOLDOWN_MIN < P.MOVE_COOLDOWN_BASE, "vitesse: le plancher est sous la base")
	h.gt(P.SPEED_STEP, 0, "vitesse: le pas de SPEED_UP est positif")
	var paliers: int = (P.MOVE_COOLDOWN_BASE - P.MOVE_COOLDOWN_MIN) / P.SPEED_STEP
	h.gt(paliers, 1, "vitesse: SPEED_UP offre plus d'un palier utile")
