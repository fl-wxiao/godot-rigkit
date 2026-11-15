@tool
extends EditorPlugin
## RigKit needs no editor integration: every class is a global `class_name`.
## The plugin exists only so the addon is visible in Project Settings > Plugins,
## and so we can print the one thing users get wrong (process order).


func _enter_tree() -> void:
	print("RigKit enabled. FootLockRig must run AFTER your animation system (raise its process_priority).")


func _exit_tree() -> void:
	pass
