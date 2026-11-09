@tool
class_name ZeeScopeOverlay
extends "res://addons/dot_weapon/view/dot_weapon_scope_overlay.gd"

## What a player sees through a scope; the drawing and the exports live in dot-weapon's shared
## overlay (`view/dot_weapon_scope_overlay.gd`), which arena-weapons' AwScopeOverlay also
## extends. A game puts one of these in its HUD and calls [method follow] with its [ZeeViewModel]
## each frame.
