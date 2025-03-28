@tool
extends EditorPlugin

# Preload the logger class
const MCPLogger = preload("res://addons/godot_mcp/utils/logger.gd")

# Use the shared logger
var _logger := MCPLogger.new("MCP Server")

# Import log level constants for convenience
const LOG_LEVEL_INFO = MCPLogger.LOG_LEVEL_INFO
const LOG_LEVEL_DEBUG = MCPLogger.LOG_LEVEL_DEBUG

var tcp_server := TCPServer.new()
var port := 9080
var handshake_timeout := 3000 # ms
var debug_mode := true
var log_detailed := true  # Enable detailed logging
var log_level := LOG_LEVEL_INFO  # Default log level - can be changed at runtime
var command_handler = null  # Command handler reference

signal client_connected(id)
signal client_disconnected(id)
signal command_received(client_id, command)

class WebSocketClient:
	var tcp: StreamPeerTCP
	var id: int
	var ws: WebSocketPeer
	var state: int = -1 # -1: handshaking, 0: connected, 1: error/closed
	var handshake_time: int
	var last_poll_time: int
	var server_ref # Add reference to the outer server

	func _init(p_tcp: StreamPeerTCP, p_id: int, p_server_ref):
		tcp = p_tcp
		id = p_id
		server_ref = p_server_ref # Store the reference
		handshake_time = Time.get_ticks_msec()
		server_ref._log(id, "WebSocketClient created")

	func upgrade_to_websocket() -> bool:
		server_ref._log(id, "Attempting upgrade_to_websocket...")
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			server_ref._log(id, "TCP status not connected during upgrade attempt: " + str(tcp.get_status()))
			return false

		ws = WebSocketPeer.new()
		var err = ws.accept_stream(tcp)
		server_ref._log(id, "ws.accept_stream result: " + str(err))
		if err != OK:
			server_ref._log(id, "accept_stream failed immediately.")
			return false
		return err == OK

var clients := {}
var next_client_id := 1

func _enter_tree():
	# Store plugin instance for EditorInterface access
	Engine.set_meta("GodotMCPPlugin", self)

	_logger.info("\n=== MCP SERVER STARTING ===")

	# Initialize the command handler
	_logger.info("Creating command handler...")
	command_handler = preload("res://addons/godot_mcp/command_handler.gd").new()
	command_handler.name = "CommandHandler"
	add_child(command_handler)

	# Connect signals
	_logger.info("Connecting command handler signals...")
	self.connect("command_received", Callable(command_handler, "_handle_command"))

	# Start WebSocket server
	var err = tcp_server.listen(port)
	if err == OK:
		_logger.info("Listening on port " + str(port))
		set_process(true)
	else:
		_logger.error("Failed to listen on port " + str(port) + " error:" + str(err))

	_logger.info("=== MCP SERVER INITIALIZED ===\n")

func _exit_tree():
	# Remove plugin instance from Engine metadata
	if Engine.has_meta("GodotMCPPlugin"):
		Engine.remove_meta("GodotMCPPlugin")

	if tcp_server and tcp_server.is_listening():
		tcp_server.stop()

	clients.clear()

	_logger.info("=== MCP SERVER SHUTDOWN ===")

# Helper method to use the logger for client messages
func _log(client_id, message, level := LOG_LEVEL_DEBUG):
	_logger.client_log(client_id, message, level)

func _process(_delta):
	if not tcp_server.is_listening():
		return

	# Poll for new connections
	if tcp_server.is_connection_available():
		var tcp = tcp_server.take_connection()
		var id = next_client_id
		next_client_id += 1

		var client = WebSocketClient.new(tcp, id, self)
		clients[id] = client

		_logger.info("[Client " + str(id) + "] New TCP connection")

		# Try to upgrade immediately
		if client.upgrade_to_websocket():
			_logger.info("[Client " + str(id) + "] WebSocket handshake started")
			client.server_ref._log(id, "upgrade_to_websocket returned true")
		else:
			_logger.info("[Client " + str(id) + "] Failed to start WebSocket handshake")
			client.server_ref._log(id, "upgrade_to_websocket returned false")
			clients.erase(id)

	# Update clients
	var current_time = Time.get_ticks_msec()
	var ids_to_remove := []

	for id in clients:
		var client = clients[id]
		client.last_poll_time = current_time

		# Process client based on its state
		if client.state == -1: # Handshaking
			if client.ws != null:
				# Poll the WebSocket peer
				client.ws.poll()

				# Check WebSocket state
				var ws_state = client.ws.get_ready_state()
				client.server_ref._log(id, "State: " + str(ws_state))

				if ws_state == WebSocketPeer.STATE_OPEN:
					client.server_ref._log(id, "Handshake success (STATE_OPEN)")
					_logger.info("[Client " + str(id) + "] WebSocket handshake completed")
					client.state = 0

					# Emit connected signal
					emit_signal("client_connected", id)

					# Send welcome message using JSON-RPC 2.0 notification format
					var msg = JSON.stringify({
						"jsonrpc": "2.0",
						"method": "server.welcome",
						"params": {
							"message": "Welcome to Godot MCP WebSocket Server",
							"version": "1.1.0"
						}
					})
					client.ws.send_text(msg)

				elif ws_state != WebSocketPeer.STATE_CONNECTING:
					client.server_ref._log(id, "Handshake failed (State not OPEN or CONNECTING: " + str(ws_state) + ")")
					_logger.info("[Client " + str(id) + "] WebSocket handshake failed, state: " + str(ws_state))
					ids_to_remove.append(id)

				# Check for handshake timeout
				elif current_time - client.handshake_time > handshake_timeout:
					client.server_ref._log(id, "Handshake timed out after " + str(current_time - client.handshake_time) + "ms")
					_logger.info("[Client " + str(id) + "] WebSocket handshake timed out")
					ids_to_remove.append(id)
			else:
				# If TCP is still connected, try upgrading
				if client.tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
					client.server_ref._log(id, "TCP still connected, retrying upgrade...")
					if client.upgrade_to_websocket():
						_logger.info("[Client " + str(id) + "] WebSocket handshake started")
						client.server_ref._log(id, "Retry upgrade_to_websocket returned true")
					else:
						_logger.info("[Client " + str(id) + "] Failed to start WebSocket handshake on retry")
						client.server_ref._log(id, "Retry upgrade_to_websocket returned false")
						ids_to_remove.append(id)
				else:
					client.server_ref._log(id, "TCP disconnected during handshake (before upgrade attempt). Status: " + str(client.tcp.get_status()))
					_logger.info("[Client " + str(id) + "] TCP disconnected during handshake")
					ids_to_remove.append(id)

		elif client.state == 0: # Connected
			# Poll the WebSocket
			client.ws.poll()

			# Check state
			var ws_state = client.ws.get_ready_state()
			if ws_state != WebSocketPeer.STATE_OPEN:
				client.server_ref._log(id, "WebSocket closed unexpectedly. State: " + str(ws_state))
				_logger.info("[Client " + str(id) + "] WebSocket connection closed, state: " + str(ws_state))
				emit_signal("client_disconnected", id)
				ids_to_remove.append(id)
				continue

			# Process messages
			while client.ws.get_available_packet_count() > 0:
				var packet = client.ws.get_packet()
				var text = packet.get_string_from_utf8()

				# Extra debugging for raw data inspection
				var bytes = packet.size()
				client.server_ref._log(id, "PACKET RECEIVED: " + str(bytes) + " bytes", LOG_LEVEL_DEBUG)
				client.server_ref._log(id, "RAW UTF8 DATA: " + text, LOG_LEVEL_DEBUG)

				_logger.debug("[Client " + str(id) + "] RECEIVED RAW DATA: " + text)

				# Parse as JSON
				var json = JSON.new()
				var parse_result = json.parse(text)
				client.server_ref._log(id, "JSON parse result: " + str(parse_result), LOG_LEVEL_DEBUG)

				if parse_result == OK:
					var data = json.get_data()
					client.server_ref._log(id, "Parsed JSON: " + str(data), LOG_LEVEL_DEBUG)

					# Handle JSON-RPC protocol
					if data.has("jsonrpc") and data.get("jsonrpc") == "2.0":
						var req_id = data.get("id") # Get the request ID

						# Handle specific methods within JSON-RPC
						if data.has("method"):
							var method_name = data.get("method")

							if method_name == "ping":
								_logger.info("[Client " + str(id) + "] Received PING with id: " + str(req_id))
								var response = { "jsonrpc": "2.0", "id": req_id, "result": null }
								send_response(id, response)

							elif method_name == "initialize":
								_logger.info("[Client " + str(id) + "] Processing initialize method with id: " + str(req_id))
								var init_response = {
									"jsonrpc": "2.0",
									"id": req_id,
									"result": {
										"serverInfo": { "name": "GodotMCPAddon", "version": "1.1.0" },
										"capabilities": { "tools": true },
										# TODO: Get this list dynamically
										"tools": [
											{"name": "list_nodes", "description": "List nodes", "parameterSchema": {}},
											{"name": "create_script", "description": "Create script", "parameterSchema": {}},
										]
									}
								}
								send_response(id, init_response)

							else: # Other JSON-RPC methods
								_logger.info("[Client " + str(id) + "] Processing JSON-RPC method: " + method_name)
								# Emit signal for command handler to process
								emit_signal("command_received", id, data)

						else:
							# JSON-RPC notification (no method) or invalid request?
							_logger.info("[Client " + str(id) + "] Received JSON-RPC request without 'method'. Ignoring.")

					# Handle legacy command format (Not JSON-RPC)
					elif data.has("type"):
						var cmd_type = data.get("type")
						_logger.info("[Client " + str(id) + "] Processing legacy command: " + cmd_type)
						# Route command to command handler via signal
						emit_signal("command_received", id, data)

					else:
						# Unknown format
						_logger.info("[Client " + str(id) + "] Unknown command format. Ignoring.")

				else: # JSON Parse Failed
					_logger.error("[Client " + str(id) + "] Failed to parse JSON: " + json.get_error_message())

	# Remove clients that need to be removed
	for id in ids_to_remove:
		clients.erase(id)

# Function for command handler to send responses back to clients
func send_response(client_id: int, response: Dictionary) -> int:
	if not clients.has(client_id):
		_logger.error("Client %d not found" % client_id)
		return ERR_DOES_NOT_EXIST

	var client = clients[client_id]
	var json_text = JSON.stringify(response)

	_logger.debug("Sending response to client %d: %s" % [client_id, json_text])

	if client.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_logger.error("Client %d connection not open" % client_id)
		return ERR_UNAVAILABLE

	var result = client.ws.send_text(json_text)
	if result != OK:
		_logger.error("Error sending response to client %d: %d" % [client_id, result])

	return result

func is_server_active() -> bool:
	return tcp_server.is_listening()

func stop_server() -> void:
	if is_server_active():
		tcp_server.stop()
		clients.clear()
		_logger.info("MCP WebSocket server stopped")

func get_port() -> int:
	return port

# Utility function to set the log level at runtime
func set_log_level(level: int) -> void:
	_logger.set_level(level)
