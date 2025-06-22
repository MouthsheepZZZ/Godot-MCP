@tool
class_name MCPLogger
extends RefCounted

# Log Level Constants
const LOG_LEVEL_ERROR = 0   # Only errors
const LOG_LEVEL_INFO  = 1   # Errors and important info
const LOG_LEVEL_DEBUG = 2   # Detailed debug information

var log_level := LOG_LEVEL_INFO
var prefix := ""

func _init(p_prefix := "", p_level := LOG_LEVEL_INFO):
	prefix = p_prefix
	log_level = p_level

func error(message: String) -> void:
	if LOG_LEVEL_ERROR <= log_level:
		if prefix.is_empty():
			print("[ERROR] " + message)
		else:
			print("[ERROR] [" + prefix + "] " + message)

func info(message: String) -> void:
	if LOG_LEVEL_INFO <= log_level:
		if prefix.is_empty():
			print("[INFO] " + message)
		else:
			print("[INFO] [" + prefix + "] " + message)

func debug(message: String) -> void:
	if LOG_LEVEL_DEBUG <= log_level:
		if prefix.is_empty():
			print("[DEBUG] " + message)
		else:
			print("[DEBUG] [" + prefix + "] " + message)

func client_log(client_id, message: String, level := LOG_LEVEL_DEBUG) -> void:
	if level <= log_level:
		if level == LOG_LEVEL_ERROR:
			print("[ERROR] [Client ", client_id, "] ", message)
		elif level == LOG_LEVEL_INFO:
			print("[INFO] [Client ", client_id, "] ", message)
		else:
			print("[DEBUG] [Client ", client_id, "] ", message)

func set_level(level: int) -> void:
	log_level = level
	info("Log level set to %d" % level)

# Singleton pattern
static var _instance: MCPLogger

static func get_instance() -> MCPLogger:
	if not _instance:
		_instance = MCPLogger.new()
	return _instance