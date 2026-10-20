class_name Interactable
extends StaticBody3D
## Something the hand uses rather than carries: a button, a breaker, a hatch
## control, a crate lid, a hull breach to seal. Click for instant actions; jobs
## with `hold_time` need the button held (and the aim kept) until done. A job may
## need a tool: a prop of kind `tool` carried in the hand.

signal used

var display_name := ""
var verb := "Use"
var hold_time := 0.0
var tool := ""
var tool_name := ""
var enabled := true
## Shown instead of the verb when the control is disabled.
var disabled_hint := ""
## Partial work survives letting go (sealing a breach), or resets (a held button).
var keep_progress := false
var progress := 0.0
var on_use: Callable
## Where the hand touched it last (world space), for controls that care where: the map.
var hit_point := Vector3.ZERO
## Optional: polled every frame for a live verb, e.g. "Open" / "Close".
var verb_fn: Callable
## Optional: the mouse wheel turns this control (called with +1 / -1).
var on_wheel: Callable
## Optional: LMB held on it and the mouse moved drags it (called with the mouse travel in
## pixels; the view stays still meanwhile). A press without moving is still a plain use.
var on_drag: Callable
## Optional: polled for a live reading shown under the name, e.g. "42 %".
var value_fn: Callable
## Something to take hold of, not to work (a screen): LMB pulls the keeper in to it like any
## surface. `on_open` (E) opens it full size.
var grip := false
var on_open: Callable


static func make(parent: Node3D, p_name: String, p_verb: String, shape: Shape3D, pos := Vector3.ZERO, basis := Basis()) -> Interactable:
	var it := Interactable.new()
	it.display_name = p_name
	it.verb = p_verb
	it.transform = Transform3D(basis, pos)
	Kit.collider(it, shape)
	parent.add_child(it)
	return it


func _init() -> void:
	collision_layer = Layers.USE
	collision_mask = 0


func current_verb() -> String:
	return verb_fn.call() if verb_fn.is_valid() else verb


## Can the hand start this job right now (given what it carries)?
func usable_with(carried_kind: String) -> bool:
	if not enabled:
		return false
	return tool == "" or carried_kind == tool or (tool == "*" and carried_kind != "")


func hint_for(carried_kind: String) -> String:
	if grip:
		var g := Loc.t("Hold LMB") + "  " + Loc.t("pull yourself to it")
		if on_open.is_valid():
			g += "    " + Loc.t("E  open the screen")
		if on_wheel.is_valid():
			g += "    " + Loc.t("Wheel  zoom")
		return g
	if not enabled:
		return disabled_hint
	if tool != "" and not usable_with(carried_kind):
		return Loc.t("Needs:") + " " + Loc.t(tool_name)
	var v := current_verb()
	var s := (Loc.t("Hold LMB") if hold_time > 0.0 else Loc.t("LMB")) + "  " + Loc.t(v) if v != "" else ""
	if on_wheel.is_valid():
		s += ("    " if s != "" else "") + Loc.t("Wheel  turn")
	return s


func complete() -> void:
	progress = 0.0
	if on_use.is_valid():
		on_use.call()
	used.emit()
