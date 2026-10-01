class_name StudioTransitions
extends CanvasLayer

## Fondus et changement de scène avec chargement en arrière-plan.
## Posé au-dessus de tout (couche 100), il traverse les changements de scène s'il est
## enfant de la racine (autoload ou add_child sur get_tree().root).

signal fondu_termine
signal scene_changee(chemin: String)

const COUCHE := 100
const DUREE_DEFAUT := 0.35

var couleur := Color.BLACK
var _voile: ColorRect


func _ready() -> void:
	layer = COUCHE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_voile = ColorRect.new()
	_voile.color = Color(couleur, 0.0)
	_voile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voile.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_voile)


## Assombrit (vers 1.0) ou éclaircit (vers 0.0). Bloque les clics tant que le voile est posé.
func fondu(vers: float, duree: float = DUREE_DEFAUT) -> void:
	_voile.mouse_filter = Control.MOUSE_FILTER_STOP if vers > 0.0 else Control.MOUSE_FILTER_IGNORE
	var t := create_tween()
	t.tween_property(_voile, "color:a", vers, duree)
	await t.finished
	fondu_termine.emit()


## Fondu au noir, chargement en arrière-plan, changement de scène, retour.
func vers_scene(chemin: String, duree: float = DUREE_DEFAUT) -> Error:
	var err := ResourceLoader.load_threaded_request(chemin)
	if err != OK:
		return err
	await fondu(1.0, duree)
	while ResourceLoader.load_threaded_get_status(chemin) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var paquet := ResourceLoader.load_threaded_get(chemin) as PackedScene
	if paquet == null:
		await fondu(0.0, duree)
		return ERR_CANT_OPEN
	get_tree().change_scene_to_packed(paquet)
	await get_tree().process_frame
	scene_changee.emit(chemin)
	await fondu(0.0, duree)
	return OK
