# Godot MCP (Model Context Protocol)

A comprehensive integration between Godot Engine and AI assistants using the Model Context Protocol (MCP). This plugin allows AI assistants to interact with your Godot projects, providing powerful capabilities for code assistance, scene manipulation, and project management.

## Fork of ee0pdt/godot-mcp by @tobitege

This fork fixes websocket and protocol issues so that it now works with
FastMCP 1.20.25, Godot 4.4 in Windows 11 and Cursor 0.48.x (probably 0.47, too).
Coding assisted by Google Gemini 2.5 and Claude 3.7 Sonnet.

## Features

- **Full Godot Project Access**: AI assistants can access and modify scripts, scenes, nodes, and project resources
- **Two-way Communication**: Send project data to AI and apply suggested changes directly in the editor
- **Command Categories**:
  - **Node Commands**: Create, modify, and manage nodes in your scenes
  - **Script Commands**: Edit, analyze, and create GDScript files
  - **Scene Commands**: Manipulate scenes and their structure
  - **Project Commands**: Access project settings and resources
  - **Editor Commands**: Control various editor functionality

## Quick Setup

### 1. Clone the Repository

```bash
git clone https://github.com/ee0pdt/godot-mcp.git
cd godot-mcp
```

### 2. Set Up the MCP Server

```bash
cd server
npm install
npm run build
# Return to project root
cd ..
```

### 3. Set Up Claude Desktop

1. Edit or create the Claude Desktop config file:

   ```bash
   # For macOS
   nano ~/Library/Application\ Support/Claude/claude_desktop_config.json
   ```

2. Add the following configuration (or use the included `claude_desktop_config.json` as a reference):

   ```json
   {
	 "mcpServers": {
	   "godot-mcp": {
		 "command": "node",
		 "args": [
		   "PATH_TO_YOUR_PROJECT/server/dist/index.js"
		 ],
		 "env": {
		   "MCP_TRANSPORT": "stdio"
		 }
	   }
	 }
   }
   ```
   > **Note**: Replace `PATH_TO_YOUR_PROJECT` with the absolute path to where you have this repository stored.

3. Restart Claude Desktop

### 4. Open the Example Project in Godot

1. Open Godot Engine
2. Select "Import" and navigate to the cloned repository
3. Open the `project.godot` file
4. The MCP plugin is already enabled in this example project

## Using MCP with Claude

After setup, you can work with your Godot project directly from Claude using natural language. Here are some examples:

### Example Prompts

```sh
@mcp godot-mcp read godot://script/current

I need help optimizing my player movement code. Can you suggest improvements?
```

```sh
@mcp godot-mcp run get-scene-tree

Add a cube in the middle of the scene and then make a camera that is looking at the cube.
```

```sh
@mcp godot-mcp read godot://scene/current

Create an enemy AI that patrols between waypoints and attacks the player when in range.
```

### Natural Language Tasks Claude Can Perform

- "Create a main menu with play, options, and quit buttons"
- "Add collision detection to the player character"
- "Implement a day/night cycle system"
- "Refactor this code to use signals instead of direct references"
- "Debug why my player character falls through the floor sometimes"

## Available Resources and Commands

### Resource Endpoints

- `godot://script/current` - The currently open script
- `godot://scene/current` - The currently open scene
- `godot://project/info` - Project metadata and settings

### Command Categories

#### Node Commands

- `get-scene-tree` - Returns the scene tree structure
- `get-node-properties` - Gets properties of a specific node
- `create-node` - Creates a new node
- `delete-node` - Deletes a node
- `modify-node` - Updates node properties

#### Script Commands

- `list-project-scripts` - Lists all scripts in the project
- `read-script` - Reads a specific script
- `modify-script` - Updates script content
- `create-script` - Creates a new script
- `analyze-script` - Provides analysis of a script

#### Scene Commands

- `list-project-scenes` - Lists all scenes in the project
- `read-scene` - Reads scene structure
- `create-scene` - Creates a new scene
- `save-scene` - Saves current scene

#### Project Commands

- `get-project-settings` - Gets project settings
- `list-project-resources` - Lists project resources

#### Editor Commands

- `get-editor-state` - Gets current editor state
- `run-project` - Runs the project
- `stop-project` - Stops the running project

## Troubleshooting

### Connection Issues

- Ensure the plugin is enabled in Godot's Project Settings
- Check the Godot console for any error messages
- Verify the server is running when Claude Desktop launches it

### Plugin Not Working

- Reload Godot project after any configuration changes
- Check for error messages in the Godot console
- Make sure all paths in your Claude Desktop config are absolute and correct

## Adding the Plugin to Your Own Godot Project

If you want to use the MCP plugin in your own Godot project:

1. Copy the `addons/godot_mcp` folder to your Godot project's `addons` directory
2. Open your project in Godot
3. Go to Project > Project Settings > Plugins
4. Enable the "Godot MCP" plugin

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Documentation

For more detailed information, check the documentation in the `docs` folder:

- [Getting Started](docs/getting-started.md)
- [Installation Guide](docs/installation-guide.md)
- [Command Reference](docs/command-reference.md)
- [Architecture](docs/architecture.md)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Changes

### Version 1.1.0

Version was tested with Godot 4.4 and FastMCP 1.20.25 in Windows 11.

### Major System Improvements

1. **Standardized Logging**: Created a unified logging system across all components
2. **JSON-RPC 2.0 Compatibility**: Fixed crucial issues in WebSocket message handling
3. **Noise Reduction**: Moved verbose debugging messages to the DEBUG level
4. **Improved Error Feedback**: Better error messages with component identification
5. **Runtime Control**: Added the ability to adjust log levels for specific components

### WebSocket Communication

- Fixed WebSocket handshake issues by removing unnecessary protocol parameters
- Implemented proper JSON-RPC 2.0 protocol support throughout the system
- Enhanced error handling and response formatting to comply with JSON-RPC specifications
- Crucial version bump of FastMCP to 1.20.25

### Godot Plugin

- Updated response formatting in all command processors to use JSON-RPC 2.0 format
- Fixed packet handling by updating deprecated methods (changed `get_len()` to `size()`)
- Enhanced logging system with different log levels for better debugging
- Improved client tracking and connection management
- Added welcome message in JSON-RPC 2.0 notification format

### Node.js Server

- Added connection health verification at startup with ping and test commands
- Enhanced message handling with better parsing and error management
- Improved command queue tracking with detailed logging
- Updated timeout handling and reconnection logic for better reliability

## 1. `addons/godot_mcp/utils/logger.gd` (New file)

- Created a centralized logging system with the `MCPLogger` class
- Implemented standardized log levels (ERROR, INFO, DEBUG)
- Added component-specific prefixing for better log identification
- Provided both instance-based and singleton access patterns
- Enabled client-specific logging with ID-tagged messages

## 2. `addons/godot_mcp/mcp_server.gd`

- Fixed JSON-RPC 2.0 message handling for proper WebSocket communication
- Updated to use the shared logger system
- Changed verbose message logging from default to DEBUG level only
- Added proper welcome message using JSON-RPC 2.0 notification format
- Improved error handling for WebSocket connections
- Simplified setting log levels through the logger delegation

## 3. `addons/godot_mcp/websocket_server.gd`

- Converted to use the centralized logging system
- Changed verbose response logs to DEBUG level to reduce console noise
- Added proper log level control function
- Maintained the same functionality with cleaner code

## 4. `addons/godot_mcp/command_handler.gd`

- Fixed critical bug where it looked for "type" instead of "method" in JSON-RPC 2.0 messages
- Updated error response format to follow JSON-RPC 2.0 specification
- Integrated with the centralized logging system
- Added proper command ID handling for JSON-RPC 2.0
- Changed verbose command details to DEBUG level

## 5. `addons/godot_mcp/commands/base_command_processor.gd`

- Integrated with the shared logging system
- Removed duplicate log level code
- Updated error reporting to use the centralized logger
- Changed verbose property parsing details to DEBUG level
- Added log level control function

These changes have substantially improved the maintainability, readability, and functionality of the Godot MCP plugin while reducing log noise during normal operation.

- 1.0.0: Initial release
