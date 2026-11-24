extends RefCounted
## Stage 14 (D1): every modal window — a "sheet" — is registered here, and only this class shows or hides one.
## A sheet is a full-screen scrim (a dim ColorRect) with its panel inside. The stack decides what Back / Esc closes
## (the top sheet), whether the world gets input (no, while any sheet is open) and what a tap on the scrim does.
## `visible` of a sheet node stays the single source of truth: open shows it at once (and fades it in), close hides it
## at once, so code and tests may read `node.visible`; they never write it (a test greps for that).
## Bug 1 of stage 14: a scrim used to close on a press; the same tap then arrived again (touch and its emulated mouse
## twin) and reopened the window under it. Now a scrim reacts only to a left-button RELEASE whose press began on it, so
## the order and the number of twin events don't matter. A sheet is closed by name: hiding a control sends it a fake
## release, which must not close the sheet underneath.

const FADE := 0.12

var sheets := {}           # name -> {node, dismiss: Callable, scrim: bool, back_pass: bool}
var stack: Array[String] = []
var pressed_on := {}       # name -> true while a left press that began on this scrim is held


## dismiss — what closing by the user means for this sheet (default: just close it); scrim — a tap on the dim
## dismisses it; back_pass — Back / Esc doesn't close it and goes on (the first-start language choice).
func add(sheet_name: String, node: Control, dismiss: Callable = Callable(), scrim := false, back_pass := false) -> void:
	sheets[sheet_name] = {"node": node, "dismiss": dismiss, "scrim": scrim, "back_pass": back_pass}
	node.visible = false
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.gui_input.connect(_scrim_input.bind(sheet_name))


func has(sheet_name: String) -> bool:
	return sheets.has(sheet_name)


func open(sheet_name: String) -> void:
	if not sheets.has(sheet_name):
		return
	var node: Control = sheets[sheet_name]["node"]
	stack.erase(sheet_name)
	stack.append(sheet_name)
	pressed_on.erase(sheet_name)
	if node.get_parent():
		node.get_parent().move_child(node, -1)   # the newest sheet is drawn and hit-tested on top
	var was := node.visible
	node.visible = true
	if not was and node.is_inside_tree():
		node.modulate.a = 0.0
		node.create_tween().tween_property(node, "modulate:a", 1.0, FADE)


func close(sheet_name: String) -> void:
	if not sheets.has(sheet_name):
		return
	stack.erase(sheet_name)
	pressed_on.erase(sheet_name)
	var node: Control = sheets[sheet_name]["node"]
	node.visible = false
	node.modulate.a = 1.0


func toggle(sheet_name: String) -> void:
	if is_open(sheet_name):
		close(sheet_name)
	else:
		open(sheet_name)


func is_open(sheet_name: String) -> bool:
	return stack.has(sheet_name)


func any_open() -> bool:
	return not stack.is_empty()


func top() -> String:
	return "" if stack.is_empty() else stack[-1]


## Back / Esc: dismiss the top sheet. false — nothing to close here (or the top sheet lets Back through).
func back() -> bool:
	var n := top()
	if n == "":
		return false
	if sheets[n]["back_pass"]:
		return false
	dismiss(n)
	return true


func dismiss(sheet_name: String) -> void:
	var d: Callable = sheets[sheet_name]["dismiss"]
	if d.is_valid():
		d.call()
	else:
		close(sheet_name)


func close_all() -> void:
	for n in stack.duplicate():
		close(n)


func _scrim_input(e: InputEvent, sheet_name: String) -> void:
	if not (e is InputEventMouseButton) or (e as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	if e.pressed:
		pressed_on[sheet_name] = true
	elif pressed_on.get(sheet_name, false):
		pressed_on.erase(sheet_name)
		if sheets[sheet_name]["scrim"] and top() == sheet_name:
			dismiss(sheet_name)
