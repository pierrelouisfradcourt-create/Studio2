# game_events.gd — SIX MOMENTS SONORES NOMMES (ligne events.sound_moments).
#
# Les six moments sont DERIVES de la comparaison entre l'etat AVANT, l'etat APRES et la
# transition d'application. Ce module emet des evenements NOMMES et ne joue AUCUN son :
# aucune API audio de la plateforme n'est referencee ici, et c'est cette ABSENCE qui est
# comptee sur 05_SYSTEMS. Le controle positif vit dans 06_RUNTIME/adapters/audio.
#
# Logique PURE. Ne depend que de game_state.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")

const SON_DEPLACEMENT := "son_deplacement"
const SON_COLLECTE := "son_collecte"
const SON_EFFRAYE := "son_effraye"
const SON_MORT := "son_mort"
const SON_VICTOIRE := "son_victoire"
const SON_PAUSE := "son_pause"

# ORDRE DECLARE des six moments : l'enumeration ne depend jamais d'un Dictionary.
const MOMENTS: Array = [
	SON_DEPLACEMENT, SON_COLLECTE, SON_EFFRAYE, SON_MORT, SON_VICTOIRE, SON_PAUSE,
]


static func moment_connu(nom: String) -> bool:
	return MOMENTS.has(nom)


# Le joueur a-t-il AVANCE pendant ce tick ?
static func a_avance(avant, apres) -> bool:
	return apres.pac != avant.pac


# Un collectible a-t-il ete ramasse pendant ce tick ?
static func a_collecte(avant, apres) -> bool:
	return apres.consommees > avant.consommees


# L'etat Effraye vient-il d'etre ARME ? Mesure sur la fenetre restante, qui ne remonte
# qu'a l'armement : elle DECROIT a tous les autres ticks.
static func est_entre_en_effraye(avant, apres) -> bool:
	return apres.effraye_restant > avant.effraye_restant


static func a_perdu_une_vie(avant, apres) -> bool:
	return apres.vies < avant.vies


static func a_gagne(avant, apres) -> bool:
	return apres.statut == State.Statut.GAGNE and avant.statut != State.Statut.GAGNE


# Evenements sonores du tick, dans l'ORDRE DECLARE des six moments. `ouverture_menu`
# porte la transition d'application (ouverture de pause ou de menu) : elle ne se lit pas
# dans l'etat de partie, elle est REMISE par l'appelant qui la connait.
static func evenements_sonores(avant, apres, ouverture_menu: bool) -> Array:
	var sortie: Array = []
	if a_avance(avant, apres):
		sortie.append(SON_DEPLACEMENT)
	if a_collecte(avant, apres):
		sortie.append(SON_COLLECTE)
	if est_entre_en_effraye(avant, apres):
		sortie.append(SON_EFFRAYE)
	if a_perdu_une_vie(avant, apres):
		sortie.append(SON_MORT)
	if a_gagne(avant, apres):
		sortie.append(SON_VICTOIRE)
	if ouverture_menu:
		sortie.append(SON_PAUSE)
	return sortie
