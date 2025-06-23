@tool
class_name MCPNodeCommands
extends MCPBaseCommandProcessor

func process_command(client_id: int, command_type: String, params: Dictionary, command_id: String) -> bool:
	match command_type:
		"create_node":
			_create_node(client_id, params, command_id)
			return true
		"delete_node":
			_delete_node(client_id, params, command_id)
			return true
		"update_node_property":
			_update_node_property(client_id, params, command_id)
			return true
		"get_node_properties":
			_get_node_properties(client_id, params, command_id)
			return true
		"list_nodes":
			_list_nodes(client_id, params, command_id)
			return true
	return false  # Command not handled

func _create_node(client_id: int, params: Dictionary, command_id: String) -> void:
	var parent_path = params.get("parent_path", "/root")
	var node_type = params.get("node_type", "Node")
	var node_name = params.get("node_name", "NewNode")

	var resolved_parent_path = parent_path
	var scene_root = EditorInterface.get_edited_scene_root()
	if scene_root:
		var scene_root_path = scene_root.get_path()
		if parent_path == "/root" or parent_path == scene_root_path:
			resolved_parent_path = scene_root_path

	# Validation
	if not ClassDB.class_exists(node_type):
		return _send_error(client_id, "Invalid node type: %s" % node_type, command_id)

	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCPPlugin")
	if not plugin:
		return _send_error(client_id, "GodotMCPPlugin not found in Engine metadata", command_id)

	var editor_interface = plugin.get_editor_interface()
	var edited_scene_root = editor_interface.get_edited_scene_root()

	if not edited_scene_root:
		return _send_error(client_id, "No scene is currently being edited", command_id)

	# Get the parent node using the editor node helper
	var parent = _get_editor_node(resolved_parent_path)
	if not parent:
		return _send_error(client_id, "Parent node not found: %s" % parent_path, command_id)

	# Create the node
	var node
	if ClassDB.can_instantiate(node_type):
		node = ClassDB.instantiate(node_type)
	else:
		return _send_error(client_id, "Cannot instantiate node of type: %s" % node_type, command_id)

	if not node:
		return _send_error(client_id, "Failed to create node of type: %s" % node_type, command_id)

	# Set the node name
	node.name = node_name

	# Add the node to the parent
	parent.add_child(node)

	# Set owner for proper serialization
	node.owner = edited_scene_root

	# Mark the scene as modified
	_mark_scene_modified()

	var new_node_path = parent.get_path().to_string() + "/" + node_name
	if scene_root:
		var scene_root_path = scene_root.get_path()
		if new_node_path.begins_with(scene_root_path):
			if new_node_path == scene_root_path:
				new_node_path = "/root"
			else:
				new_node_path = "/root" + new_node_path.substr(scene_root_path.length())

	_send_success(client_id, {
		"node_path": new_node_path
	}, command_id)

func _delete_node(client_id: int, params: Dictionary, command_id: String) -> void:
	var node_path = params.get("node_path", "")

	# Validation
	if node_path.is_empty():
		return _send_error(client_id, "Node path cannot be empty", command_id)

	var resolved_node_path = node_path
	var scene_root = EditorInterface.get_edited_scene_root()
	if scene_root:
		var scene_root_path = scene_root.get_path()
		if node_path == "/root" or node_path == scene_root_path:
			resolved_node_path = scene_root_path

	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCPPlugin")
	if not plugin:
		return _send_error(client_id, "GodotMCPPlugin not found in Engine metadata", command_id)

	var editor_interface = plugin.get_editor_interface()
	var edited_scene_root = editor_interface.get_edited_scene_root()

	if not edited_scene_root:
		return _send_error(client_id, "No scene is currently being edited", command_id)

	# Get the node using the editor node helper
	var node = _get_editor_node(resolved_node_path)
	if not node:
		return _send_error(client_id, "Node not found: %s" % node_path, command_id)

	# Cannot delete the root node
	if node == edited_scene_root:
		return _send_error(client_id, "Cannot delete the root node", command_id)

	# Get parent for operation
	var parent = node.get_parent()
	if not parent:
		return _send_error(client_id, "Node has no parent: %s" % node_path, command_id)

	# Remove the node
	parent.remove_child(node)
	node.queue_free()

	# Mark the scene as modified
	_mark_scene_modified()

	var aliased_path = node_path
	if scene_root:
		var scene_root_path = scene_root.get_path()
		if node_path == scene_root_path:
			aliased_path = "/root"

	_send_success(client_id, {
		"deleted_node_path": aliased_path
	}, command_id)

func _update_node_property(client_id: int, params: Dictionary, command_id: String) -> void:
	var node_path = params.get("node_path", "")
	var property_name = params.get("property", "")
	var property_value = params.get("value")

	# Validation
	if node_path.is_empty():
		return _send_error(client_id, "Node path cannot be empty", command_id)

	if property_name.is_empty():
		return _send_error(client_id, "Property name cannot be empty", command_id)

	if property_value == null:
		return _send_error(client_id, "Property value cannot be null", command_id)

	var resolved_node_path = node_path
	var scene_root = EditorInterface.get_edited_scene_root()
	if scene_root:
		var scene_root_path = scene_root.get_path()
		if node_path == "/root" or node_path == scene_root_path:
			resolved_node_path = scene_root_path

	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCPPlugin")
	if not plugin:
		return _send_error(client_id, "GodotMCPPlugin not found in Engine metadata", command_id)

	# Get the node using the editor node helper
	var node = _get_editor_node(resolved_node_path)
	if not node:
		return _send_error(client_id, "Node not found: %s" % node_path, command_id)

	# Check if the property exists
	if not property_name in node:
		return _send_error(client_id, "Property %s does not exist on node %s" % [property_name, node_path], command_id)

	# Parse property value for Godot types
	var parsed_value = _parse_property_value(property_value)

	# Get current property value for undo
	var old_value = node.get(property_name)

	# Get undo/redo system
	var undo_redo = _get_undo_redo()
	if not undo_redo:
		# Fallback method if we can't get undo/redo
		node.set(property_name, parsed_value)
		_mark_scene_modified()
	else:
		# Use undo/redo for proper editor integration
		undo_redo.create_action("Update Property: " + property_name)
		undo_redo.add_do_property(node, property_name, parsed_value)
		undo_redo.add_undo_property(node, property_name, old_value)
		undo_redo.commit_action()

	# Mark the scene as modified
	_mark_scene_modified()

	var aliased_path = node_path
	if scene_root:
		var scene_root_path = scene_root.get_path()
		if node_path.begins_with(scene_root_path):
			if node_path == scene_root_path:
				aliased_path = "/root"
			else:
				aliased_path = "/root" + node_path.substr(scene_root_path.length())

	_send_success(client_id, {
		"node_path": aliased_path,
		"property": property_name,
		"value": property_value,
		"parsed_value": str(parsed_value)
	}, command_id)

func _get_node_properties(client_id: int, params: Dictionary, command_id: String) -> void:
	var node_path = params.get("node_path", "")

	# Validation
	if node_path.is_empty():
		return _send_error(client_id, "Node path cannot be empty", command_id)

	var resolved_node_path = node_path
	var scene_root = EditorInterface.get_edited_scene_root()
	if scene_root:
		var scene_root_path = scene_root.get_path()
		if node_path == "/root" or node_path == scene_root_path:
			resolved_node_path = scene_root_path

	# Get the node using the editor node helper
	var node = _get_editor_node(resolved_node_path)
	if not node:
		return _send_error(client_id, "Node not found: %s" % node_path, command_id)

	# Get all properties
	var properties = {}
	var property_list = node.get_property_list()

	for prop in property_list:
		var name = prop["name"]
		if not name.begins_with("_"):  # Skip internal properties
			properties[name] = node.get(name)

	var aliased_path = node_path
	if scene_root:
		var scene_root_path = scene_root.get_path()
		if node_path.begins_with(scene_root_path):
			if node_path == scene_root_path:
				aliased_path = "/root"
			else:
				aliased_path = "/root" + node_path.substr(scene_root_path.length())

	_send_success(client_id, {
		"node_path": aliased_path,
		"properties": properties
	}, command_id)

func _list_nodes(client_id: int, params: Dictionary, command_id: String) -> void:
	var parent_path = params.get("parent_path", "/root")

	var aliased_parent_path = parent_path
	var resolved_parent_path = parent_path
	var scene_root = EditorInterface.get_edited_scene_root()
	if scene_root:
		var scene_root_path = scene_root.get_path()
		if parent_path == "/root" or parent_path == scene_root_path:
			resolved_parent_path = scene_root_path
			aliased_parent_path = "/root"

	# Get the parent node using the editor node helper
	var parent = _get_editor_node(resolved_parent_path)
	if not parent:
		return _send_error(client_id, "Parent node not found: %s" % parent_path, command_id)

	# Get children
	var children = []
	for child in parent.get_children():
		var child_path = child.get_path().to_string()
		if scene_root:
			var scene_root_path = scene_root.get_path()
			if child_path.begins_with(scene_root_path):
				if child_path == scene_root_path:
					child_path = "/root"
				else:
					child_path = "/root" + child_path.substr(scene_root_path.length())
		
		children.append({
			"name": child.name,
			"type": child.get_class(),
			"path": child_path
		})

	_send_success(client_id, {
		"parent_path": aliased_parent_path,
		"children": children
	}, command_id)
