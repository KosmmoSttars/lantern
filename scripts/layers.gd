class_name Layers
extends RefCounted
## Physics layer bits shared by every script. Input actions live in Settings.

const WORLD := 1
const PROPS := 2
const PLAYER := 4
## Buttons, switches, hatches, crates: things the hand uses rather than carries.
const USE := 16
## Sockets and other trigger volumes.
const SENSOR := 32
## Racks, shelves, pods, lockers: exact shapes of everything built into the cabins. They stop the
## keeper and loose props, but not the hand ray, so switches set into panels stay in reach.
const FURNITURE := 64
## The EVA umbilical: the hand can take hold of it, but it never stops the body.
const HOSE := 128

## What the hand ray can stop on: walls block, props and controls are grabbable.
const HAND_RAY := WORLD | PROPS | USE | HOSE

