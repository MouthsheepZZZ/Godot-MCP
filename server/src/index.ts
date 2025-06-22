import { FastMCP } from 'fastmcp';
import { nodeTools } from './tools/node_tools.js';
import { scriptTools } from './tools/script_tools.js';
import { sceneTools } from './tools/scene_tools.js';
import { editorTools } from './tools/editor_tools.js';
import { getGodotConnection } from './utils/godot_connection.js';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

// Console logs for debugging
console.error('--------------------------------------------');
console.error('Godot MCP Server Starting - DEBUG INFO');
console.error('Node.js version:', process.version);
console.error('Platform:', process.platform);
console.error('Working directory:', process.cwd());
console.error('--------------------------------------------');

// Import resources
import {
  sceneListResource,
  sceneStructureResource
} from './resources/scene_resources.js';
import {
  scriptResource,
  scriptListResource,
  scriptMetadataResource
} from './resources/script_resources.js';
import {
  projectStructureResource,
  projectSettingsResource,
  projectResourcesResource
} from './resources/project_resources.js';
import {
  editorStateResource,
  selectedNodeResource,
  currentScriptResource
} from './resources/editor_resources.js';

/**
 * Main entry point for the Godot MCP server
 */
async function main() {
  console.error('Starting Godot MCP server...');

  // Create FastMCP instance
  const server = new FastMCP({
    name: 'GodotMCP',
    version: '1.1.0',
  });

  // Register all tools
  [...nodeTools, ...scriptTools, ...sceneTools, ...editorTools].forEach(tool => {
    console.error(`Registering tool: ${tool.name}`);
    server.addTool(tool);
  });

  // Register all resources
  // Static resources
  server.addResource(sceneListResource);
  server.addResource(scriptListResource);
  server.addResource(projectStructureResource);
  server.addResource(projectSettingsResource);
  server.addResource(projectResourcesResource);
  server.addResource(editorStateResource);
  server.addResource(selectedNodeResource);
  server.addResource(currentScriptResource);
  server.addResource(sceneStructureResource);
  server.addResource(scriptResource);
  server.addResource(scriptMetadataResource);

  // Try to connect to Godot and test the connection
  try {
    const godot = getGodotConnection();
    await godot.connect();
    console.error('Successfully connected to Godot WebSocket server');

    // Send an immediate ping to keep the connection alive
    try {
      await godot.sendCommand('ping', {});
      console.error('Sent initial ping command to Godot');
    } catch (pingError) {
      console.error('Failed to send ping command:', pingError);
    }
  } catch (error) {
    const err = error as Error;
    console.warn(`Could not connect to Godot: ${err.message}`);
    console.warn('Will retry connection when commands are executed');
  }

  // Start the server
  server.start({
    transportType: 'stdio'
  });

  console.error('Godot MCP server started');

  // Handle cleanup
  const cleanup = () => {
    console.error('Shutting down Godot MCP server...');
    const godot = getGodotConnection();
    godot.disconnect();
    process.exit(0);
  };

  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);
}

// Start the server
main().catch(error => {
  console.error('Failed to start Godot MCP server:', error);
  process.exit(1);
});
