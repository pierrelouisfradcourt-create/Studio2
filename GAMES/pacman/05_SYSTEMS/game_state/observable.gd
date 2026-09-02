# observable.gd — projection PURE de l'etat en releve observable
# (ligne state.observable_projection). Ne calcule RIEN de neuf, ne tient AUCUNE
# structure parallele : il recopie a plat ce que l'etat porte deja. Point d'observation
# UNIQUE du HUD, de la sonde de debug et du harnais de preuve.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")

# Cles du releve — vocabulaire ferme, lisible par un lecteur EXTERIEUR au runtime.
const CLES: Array = [
	"tick", "score", "vies", "restantes", "consommees", "total_pose",
	"statut", "statut_nom", "pac", "pac_dir", "fantomes", "etats_fantomes",
	"dehors", "mode", "effraye_restant", "rang_capture", "horloge",
	"niveau", "carte", "mode_jeu", "dash_actif", "dash_recharge",
]


static func nom_mode(mode: int) -> String:
	if mode == Chase.Mode.DISPERSION:
		return "DISPERSION"
	if mode == Chase.Mode.POURSUITE:
		return "POURSUITE"
	return "EFFRAYE"


static func projeter(s) -> Dictionary:
	var etats: Array = []
	for e in s.etats_fantomes:
		etats.append(nom_mode(e))
	return {
		"tick": s.ticks,
		"score": s.score,
		"vies": s.vies,
		"restantes": s.total_pose - s.consommees,
		"consommees": s.consommees,
		"total_pose": s.total_pose,
		"statut": s.statut,
		"statut_nom": Status.nom(s.statut),
		"pac": [s.pac.x, s.pac.y],
		"pac_dir": [s.pac_dir.x, s.pac_dir.y],
		"fantomes": _positions(s.fantomes),
		"etats_fantomes": etats,
		"dehors": s.dehors.duplicate(),
		"mode": nom_mode(Chase.mode_global(s.horloge)),
		"effraye_restant": s.effraye_restant,
		"rang_capture": s.rang_capture,
		"horloge": s.horloge,
		# V2 (ligne state.exposes_level_number) : le NUMERO DE NIVEAU, la carte courante
		# et le MODE DE JEU sont exposes ici, source UNIQUE lue a la fois par l'affichage
		# et par le lecteur exterieur — jamais deux calculs paralleles.
		"niveau": s.niveau,
		"carte": s.carte.ID if s.carte != null else "",
		"mode_jeu": Reglages.nom(s.mode),
		"dash_actif": s.dash_actif,
		"dash_recharge": s.dash_recharge,
	}


static func _positions(liste: Array) -> Array:
	var sortie: Array = []
	for p in liste:
		sortie.append([p.x, p.y])
	return sortie


# Egalite champ par champ de deux releves — base des comparaisons de trace.
static func egaux(a: Dictionary, b: Dictionary) -> bool:
	for c in CLES:
		if a.get(c) != b.get(c):
			return false
	return true
