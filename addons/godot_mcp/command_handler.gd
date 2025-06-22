@tool
class_name MCPCommandHandler
extends Node

# Preload the logger class
const MCPLogger = preload("res://addons/godot_mcp/utils/logger.gd")

# Use the shared logger
var _logger := MCPLogger.new("Command Handler")

var _websocket_server
var _command_processors = []

func _ready():
	_logger.info("Command handler initializing...")
	await get_tree().process_frame
	_websocket_server = get_parent()
	_logger.info("WebSocket server reference set: " + str(_websocket_server))

	# Initialize command processors
	_initialize_command_processors()

	_logger.info("Command handler initialized and ready to process commands")

func _initialize_command_processors():
	# Create and add all command processors
	var node_commands = MCPNodeCommands.new()
	var script_commands = MCPScriptCommands.new()
	var scene_commands = MCPSceneCommands.new()
	var project_commands = MCPProjectCommands.new()
	var editor_commands = MCPEditorCommands.new()
	var editor_script_commands = MCPEditorScriptCommands.new()  # Add our new processor

	# Set server reference for all processors
	node_commands._websocket_server = _websocket_server
	script_commands._websocket_server = _websocket_server
	scene_commands._websocket_server = _websocket_server
	project_commands._websocket_server = _websocket_server
	editor_commands._websocket_server = _websocket_server
	editor_script_commands._websocket_server = _websocket_server  # Set server reference

	# Add them to our processor list
	_command_processors.append(node_commands)
	_command_processors.append(script_commands)
	_command_processors.append(scene_commands)
	_command_processors.append(project_commands)
	_command_processors.append(editor_commands)
	_command_processors.append(editor_script_commands)  # Add to processor list

	# Add them as children for proper lifecycle management
	add_child(node_commands)
	add_child(script_commands)
	add_child(scene_commands)
	add_child(project_commands)
	add_child(editor_commands)
	add_child(editor_script_commands)  # Add as child

func _handle_command(client_id: int, command: Dictionary) -> void:
	var command_type = ""
	var params = {}
	var command_id = ""

	# Check if it's JSON-RPC and extract correctly
	if command.has("jsonrpc") and command.get("jsonrpc") == "2.0":
		command_type = command.get("method", "")
		params = command.get("params", {})
		# JSON-RPC uses "id", ensure it's treated as a string if present
		var rpc_id = command.get("id")
		if rpc_id != null:
			command_id = str(rpc_id)
	else:
		# Fallback for potential legacy format (adjust if needed)
		command_type = command.get("type", "")
		params = command.get("params", {})
		command_id = command.get("commandId", "")


	_logger.info("Processing command: %s (ID: %s)" % [command_type, command_id])

	# Try each processor until one handles the command
	for processor in _command_processors:
		# Pass the correctly extracted values
		if processor.process_command(client_id, command_type, params, command_id):
			_logger.debug("Command '%s' handled by processor %s" % [command_type, processor.get_class()])
			return

	# If no processor handled the command, send an error
	_logger.error("Command '%s' not handled by any processor." % command_type)
	_send_error(client_id, "Unknown or unhandled command: %s" % command_type, command_id)

func _send_error(client_id: int, message: String, command_id: String) -> void:
	# Use JSON-RPC error format
	var response = {
		"jsonrpc": "2.0",
		"error": {
			"code": -32601, # Method not found code
			"message": message
		}
	}
	if not command_id.is_empty():
		response["id"] = command_id # Use "id" for JSON-RPC

	# Ensure _websocket_server is valid before calling send_response
	if _websocket_server and _websocket_server.has_method("send_response"):
		_websocket_server.send_response(client_id, response)
		_logger.info("Sent error response for command ID '%s': %s" % [command_id, message])
	else:
		_logger.error("Error sending error response: _websocket_server invalid or missing send_response method.")

# Set the log level
func set_log_level(level: int) -> void:
	_logger.set_level(level)
