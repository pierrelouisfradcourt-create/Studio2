# state_banner.gd — indication d'etat de poursuite lisible a l'ecran
# (ligne render.chase_state_indicator). C'est ce qui rend la bascule PERCEPTIBLE au
# joueur, et pas seulement presente dans les donnees.
extends RefCounted

const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")

const MENTION_DISPERSION := "FANTOMES : DISPERSION"
const MENTION_POURSUITE := "FANTOMES : POURSUITE"
const MENTION_EFFRAYE := "FANTOMES : EFFRAYES"

# V2 : lues dans le descripteur de palette unique, jamais ecrites ici.
const COULEUR_DISPERSION := Palette.ETAT_DISPERSION
const COULEUR_POURSUITE := Palette.ETAT_POURSUITE
const COULEUR_EFFRAYE := Palette.ETAT_EFFRAYE


# Mention affichee, deduite du SEUL releve observable.
static func mention(releve: Dictionary) -> String:
	if releve["effraye_restant"] > 0:
		return MENTION_EFFRAYE
	if releve["mode"] == "DISPERSION":
		return MENTION_DISPERSION
	return MENTION_POURSUITE


static func couleur(releve: Dictionary) -> Color:
	if releve["effraye_restant"] > 0:
		return COULEUR_EFFRAYE
	if releve["mode"] == "DISPERSION":
		return COULEUR_DISPERSION
	return COULEUR_POURSUITE


# Deux releves donnent-ils une indication DIFFERENTE a l'ecran ? C'est la grandeur
# assertee au tick precedant le seuil et au tick du seuil.
static func indication_differente(avant: Dictionary, apres: Dictionary) -> bool:
	return mention(avant) != mention(apres)


static func nom_mode_lisible(mode: int) -> String:
	if mode == Chase.Mode.DISPERSION:
		return MENTION_DISPERSION
	if mode == Chase.Mode.POURSUITE:
		return MENTION_POURSUITE
	return MENTION_EFFRAYE
