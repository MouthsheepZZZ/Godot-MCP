import WebSocket from 'ws';

/**
 * Response from Godot server
 */
export interface GodotResponse {
  status: 'success' | 'error';
  result?: any;
  message?: string;
  commandId?: string;
}

/**
 * Command to send to Godot
 */
export interface GodotCommand {
  type: string;
  params: Record<string, any>;
  commandId: string;
}

/**
 * Manages WebSocket connection to the Godot editor
 */
export class GodotConnection {
  private ws: WebSocket | null = null;
  private connected = false;
  private commandQueue: Map<string, {
    resolve: (value: any) => void;
    reject: (reason: any) => void;
    timeout: NodeJS.Timeout;
  }> = new Map();
  private commandId = 0;
  private keepAliveIntervalId: NodeJS.Timeout | null = null;

  /**
   * Creates a new Godot connection
   * @param url WebSocket URL for the Godot server
   * @param timeout Command timeout in ms
   * @param maxRetries Maximum number of connection retries
   * @param retryDelay Delay between retries in ms
   * @param pingInterval Ping interval in ms
   */
  constructor(
    private url: string = 'ws://127.0.0.1:9080',
    private timeout: number = 10000,
    private maxRetries: number = 3,
    private retryDelay: number = 2000,
    private pingInterval: number = 20000
  ) {
    console.error('GodotConnection created with URL:', this.url);
  }

  /**
   * Connects to the Godot WebSocket server
   */
  async connect(): Promise<void> {
    if (this.connected) return;

    let retries = 0;

    const tryConnect = (): Promise<void> => {
      return new Promise<void>((resolve, reject) => {
        console.error(`Connecting to Godot WebSocket server at ${this.url}... (Attempt ${retries + 1}/${this.maxRetries + 1})`);

        // Create WebSocket connection without protocols argument
        this.ws = new WebSocket(this.url);

        this.ws.on('open', () => {
          this.connected = true;
          console.error('Connected to Godot WebSocket server');
          this.startKeepAlive();
          resolve();
        });

        this.ws.on('message', (data: Buffer) => {
          try {
            const responseText = data.toString();
            console.error('Received raw response:', responseText);

            // Try to parse as JSON
            try {
              const response = JSON.parse(responseText);
              console.error('Parsed response:', response);

              // Find all pending command IDs - useful for debugging
              console.error('Pending commands:', Array.from(this.commandQueue.keys()));

              // Handle JSON-RPC responses
              if (response.jsonrpc === "2.0") {
                if (response.id) {
                  const commandId = response.id;
                  const pendingCommand = this.commandQueue.get(commandId);

                  if (pendingCommand) {
                    console.error(`Found pending command for ID: ${commandId}`);
                    clearTimeout(pendingCommand.timeout);
                    this.commandQueue.delete(commandId);

                    if (response.error) {
                      pendingCommand.reject(new Error(response.error.message || 'Unknown error'));
                    } else {
                      pendingCommand.resolve(response.result);
                    }
                  } else {
                    console.error(`No pending command found for ID: ${commandId}`);
                  }
                } else {
                  console.error('JSON-RPC notification received (no ID)');
                }
              } else if (response.commandId) {
                // Handle legacy format response
                const legacyCommandId = response.commandId;
                console.error(`Handling legacy format response with commandId: ${legacyCommandId}`);

                const pendingCommand = this.commandQueue.get(legacyCommandId);
                if (pendingCommand) {
                  console.error(`Found pending command for legacy ID: ${legacyCommandId}`);
                  clearTimeout(pendingCommand.timeout);
                  this.commandQueue.delete(legacyCommandId);

                  if (response.status === 'error') {
                    pendingCommand.reject(new Error(response.message || 'Unknown error'));
                  } else {
                    pendingCommand.resolve(response.result);
                  }
                } else {
                  console.error(`No pending command found for legacy ID: ${legacyCommandId}`);
                }
              } else {
                console.error('Response does not match any expected format. Neither JSON-RPC id nor legacy commandId found.');
              }
            } catch (parseError) {
              console.error('Error parsing JSON!');
            }
          } catch (error) {
            console.error('Error processing message:', error);
          }
        });

        this.ws.on('error', (error) => {
          const err = error as Error;
          console.error('WebSocket error:', err);
          console.error('WebSocket error details:', err.message, err.stack);
          // Attempt to reconnect on error
          if (this.connected) {
            this.tryReconnect();
          }
        });

        this.ws.on('close', (code, reason) => {
          if (this.connected) {
            console.error('Disconnected from Godot WebSocket server');
            this.connected = false;
            this.stopKeepAlive();
            // Attempt to reconnect when connection is lost
            this.tryReconnect();
          }
        });

        // Set connection timeout
        const connectionTimeout = setTimeout(() => {
          if (this.ws?.readyState !== WebSocket.OPEN) {
            if (this.ws) {
              this.ws.terminate();
              this.ws = null;
            }
            reject(new Error('Connection timeout'));
          }
        }, this.timeout);

        this.ws.on('open', () => {
          clearTimeout(connectionTimeout);
        });
      });
    };

    // Try connecting with retries
    while (retries <= this.maxRetries) {
      try {
        await tryConnect();
        return;
      } catch (error) {
        retries++;

        if (retries <= this.maxRetries) {
          console.error(`Connection attempt failed. Retrying in ${this.retryDelay}ms...`);
          await new Promise(resolve => setTimeout(resolve, this.retryDelay));
        } else {
          throw error;
        }
      }
    }
  }

  /**
   * Starts sending periodic pings to keep the connection alive.
   */
  private startKeepAlive(): void {
    this.stopKeepAlive();
    if (!this.ws) return;

    console.error(`Starting keep-alive ping after initial delay, then every ${this.pingInterval} ms`);

    // Delay the first ping slightly
    const initialDelay = 500; // Wait 500ms before first ping

    const sendPing = () => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.ws.ping(() => {}); // Send ping, ignore pong callback for simplicity
      } else {
        this.stopKeepAlive();
      }
    };

    // Schedule the first ping
    let firstPingTimeout = setTimeout(() => {
      sendPing();
      // After the first ping, set up the regular interval
      this.keepAliveIntervalId = setInterval(sendPing, this.pingInterval);
    }, initialDelay);

    // Store the initial timeout ID so stopKeepAlive can clear it too
    this.keepAliveIntervalId = firstPingTimeout as any; // Cast needed as it's initially a Timeout
  }

  /**
   * Stops sending periodic pings.
   */
  private stopKeepAlive(): void {
    if (this.keepAliveIntervalId) {
      console.error('Stopping keep-alive ping');
      clearInterval(this.keepAliveIntervalId);
      clearTimeout(this.keepAliveIntervalId);
      this.keepAliveIntervalId = null;
    }
  }

  /**
   * Attempts to reconnect to the Godot WebSocket server
   */
  private async tryReconnect(): Promise<void> {
    console.error('Attempting to reconnect...');
    if (this.ws) {
      this.ws.terminate();
      this.ws = null;
    }
    this.stopKeepAlive();
    this.connected = false;

    try {
      await this.connect();
    } catch (error) {
      console.error('Failed to reconnect:', error);
      // Schedule another reconnection attempt
      setTimeout(() => this.tryReconnect(), this.retryDelay);
    }
  }

  /**
   * Sends a command to Godot and waits for a response
   * @param type Command type
   * @param params Command parameters
   * @returns Promise that resolves with the command result
   */
  async sendCommand<T = any>(type: string, params: Record<string, any> = {}): Promise<T> {
    if (!this.ws || !this.connected) {
      try {
        await this.connect();
      } catch (error) {
        throw new Error(`Failed to connect: ${(error as Error).message}`);
      }
    }

    return new Promise<T>((resolve, reject) => {
      const commandId = `cmd_${this.commandId++}`;

      // Format command as JSON-RPC 2.0
      const command = {
        "jsonrpc": "2.0",
        "method": type,
        "params": params,
        "id": commandId
      };

      // Set timeout for command
      const timeoutId = setTimeout(() => {
        if (this.commandQueue.has(commandId)) {
          this.commandQueue.delete(commandId);
          console.error(`Command timed out: ${type} (ID: ${commandId})`);
          reject(new Error(`Command timed out: ${type}`));
        }
      }, this.timeout);

      // Store the promise resolvers
      this.commandQueue.set(commandId, {
        resolve,
        reject,
        timeout: timeoutId
      });

      // Send the command
      if (this.ws?.readyState === WebSocket.OPEN) {
        const commandStr = JSON.stringify(command);
        this.ws.send(commandStr);
      } else {
        clearTimeout(timeoutId);
        this.commandQueue.delete(commandId);
        const readyState = this.ws ? this.ws.readyState : 'null';
        reject(new Error(`WebSocket not connected, state: ${readyState}`));
      }
    });
  }

  /**
   * Disconnects from the Godot WebSocket server
   */
  disconnect(): void {
    this.stopKeepAlive();
    if (this.ws) {
      // Clear all pending commands
      this.commandQueue.forEach((command, commandId) => {
        clearTimeout(command.timeout);
        command.reject(new Error('Connection closed'));
        this.commandQueue.delete(commandId);
      });

      this.ws.close();
      this.ws = null;
      this.connected = false;
    }
  }

  /**
   * Checks if connected to Godot
   */
  isConnected(): boolean {
    return this.connected;
  }
}

// Singleton instance
let connectionInstance: GodotConnection | null = null;

/**
 * Gets the singleton instance of GodotConnection
 */
export function getGodotConnection(): GodotConnection {
  if (!connectionInstance) {
    connectionInstance = new GodotConnection();
  }
  return connectionInstance;
}