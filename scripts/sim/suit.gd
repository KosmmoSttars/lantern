class_name Suit
extends RefCounted
## The EVA umbilical. There is no suit to put on and no thruster pack: the button on the reel in
## the airlock clips the hose on, and outside the keeper moves by hand along the hull; the hose
## keeps them within HOSE_LEN of the station. (Breathing is a given, inside or out.)

## How far the hose reaches from its reel in the airlock (m).
const HOSE_LEN := 60.0
## Hauling yourself back along the hose (m/s).
const REEL_SPEED := 1.4

## On the hose (`worn` kept with it, for the helmet lamp and the old saves).
var worn := false
var clipped := false


func tick(_dt: float, _sim: ShipSim) -> void:
	worn = clipped


func to_dict() -> Dictionary:
	return {"worn": worn, "clipped": clipped}


func from_dict(d: Dictionary) -> void:
	for k: String in d:
		if k in ["worn", "clipped"]:
			set(k, d[k])
