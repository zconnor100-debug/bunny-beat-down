class_name Despawner
## Timed cleanup for debris (gibs, helmets, corpses): after `seconds` the node
## sinks into the ground and is freed, so the island never fills up with bits.
## Timers hold a WeakRef, never the node itself, so nothing breaks if the node
## was already freed by something else (a gib blown apart, a scene change).

## Where loose debris should live (the match world if there is one).
static func debris_parent(from: Node) -> Node:
	var tree := from.get_tree()
	if FX.instance and FX.instance.is_inside_tree():
		return FX.instance.get_parent()
	return tree.current_scene if tree.current_scene else tree.root


static func schedule(node: Node3D, seconds: float, sink := 0.6) -> void:
	if node == null or not node.is_inside_tree():
		return
	node.get_tree().create_timer(seconds, false).timeout.connect(_sink.bind(weakref(node), sink))


## Calls `fn(node)` after `seconds` if the node still exists.
static func after(node: Node, seconds: float, fn: Callable) -> void:
	if node == null or not node.is_inside_tree():
		return
	node.get_tree().create_timer(seconds, false).timeout.connect(_call_if_alive.bind(weakref(node), fn))


static func _call_if_alive(wr: WeakRef, fn: Callable) -> void:
	var node: Node = wr.get_ref()
	if node and is_instance_valid(node):
		fn.call(node)


static func _sink(wr: WeakRef, sink: float) -> void:
	var node := wr.get_ref() as Node3D
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
		(node as RigidBody3D).collision_layer = 0
	var tw := node.create_tween()
	tw.tween_property(node, "global_position", node.global_position + Vector3.DOWN * sink, 2.0)
	tw.tween_callback(node.queue_free)
