# presentation.gd — ADAPTATEUR DE PRESENTATION (category system.adapter, allowed_deps
# [economy, collection, upgrades, progression, goals, prestige, world_content]).
# Rend a partir du SEUL etat observable : identite visuelle DISTINCTE par rarete de chaton
# et FEEDBACK visible au clic sur la pelote (rebond + touffe de laine + texte flottant +N).
# Lit l'etat, ne le mute jamais, ne consulte aucune regle, n'appelle ni input ni audio.
extends Node

const SPRITE_DIR: String = "res://04_ASSETS/sprites/"

# Teinte de halo/badge par rarete (echelle froide -> precieuse, art_bible §1). Deux raretes
# donnent donc deux couleurs distinctes -> difference en pixels au-dela d'un seuil.
const TINTS: Dictionary = {
	"common":    Color(0.72, 0.72, 0.72),
	"uncommon":  Color(0.55, 0.77, 0.54),
	"rare":      Color(0.44, 0.66, 0.86),
	"epic":      Color(0.69, 0.49, 0.78),
	"legendary": Color(0.95, 0.72, 0.02),
}

static func tint_for(rarity: String) -> Color:
	return TINTS.get(rarity, Color(0.72, 0.72, 0.72))


static func _sprite_path_for(rarity: String) -> String:
	return SPRITE_DIR + "kitten_%s.svg" % rarity


# Panneau visuel d'un chaton : halo teinte par rarete + texture de la rarete. Deux raretes
# ne se confondent JAMAIS (teinte dominante + sprite distincts).
static func make_kitten_sprite(kitten: Dictionary) -> Control:
	var rarity: String = String(kitten.get("rarity", "common"))
	var panel := ColorRect.new()
	panel.color = tint_for(rarity)
	panel.custom_minimum_size = Vector2(44, 44)
	panel.size = Vector2(44, 44)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("rarity", rarity)
	var tex := TextureRect.new()
	var res = load(_sprite_path_for(rarity))
	if res != null:
		tex.texture = res
	tex.position = Vector2(3, 3)
	tex.size = Vector2(38, 38)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tex)
	return panel


# FEEDBACK de clic : une touffe de laine + un texte flottant "+N" qui monte et s'efface. Rend
# la zone pelote DIFFERENTE en pixels entre avant et apres le clic (preuve runtime_alive).
func pop(center: Vector2, amount: int) -> void:
	var fx := TextureRect.new()
	var res = load(SPRITE_DIR + "fx_click_feedback.svg")
	if res != null:
		fx.texture = res
	fx.size = Vector2(40, 40)
	fx.position = center - Vector2(20, 20)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	var label := Label.new()
	label.text = "+%d" % amount
	label.position = center - Vector2(8, 26)
	label.add_theme_color_override("font_color", Color(0.35, 0.24, 0.17))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position", label.position - Vector2(0, 34), 0.6)
	tw.tween_property(label, "modulate:a", 0.0, 0.6)
	tw.tween_property(fx, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(label.queue_free)
	tw.tween_callback(fx.queue_free)
