#!/usr/bin/env python3
"""
LG TV Remote Daemon
Maintains a persistent WebSocket connection to the TV for fast command execution.
Listens on a Unix socket for commands from the Plasma widget.
"""

import asyncio
import json
import ssl
import sys
import os
import signal
from pathlib import Path

try:
    import websockets
except ImportError:
    print("ERROR: websockets module required", file=sys.stderr)
    sys.exit(1)

# Socket and config paths
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
SOCKET_PATH = RUNTIME_DIR / "lgtv-remote.sock"
PID_FILE = RUNTIME_DIR / "lgtv-remote.pid"
CONFIG_DIR = Path.home() / ".config" / "lgtv-remote"
CONFIG_FILE = CONFIG_DIR / "config.json"


def get_ssl_context():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def load_config():
    if CONFIG_FILE.exists():
        try:
            return json.loads(CONFIG_FILE.read_text())
        except:
            pass
    return {"tvs": {}}


class TVConnection:
    """Maintains persistent connection to a TV."""
    
    HANDSHAKE = {
        "type": "register",
        "id": "register_0",
        "payload": {
            "forcePairing": False,
            "pairingType": "PROMPT",
            "manifest": {
                "manifestVersion": 1,
                "appVersion": "1.1",
                "signed": {
                    "created": "20140509",
                    "appId": "com.lge.test",
                    "vendorId": "com.lge",
                    "localizedAppNames": {"": "LG Remote"},
                    "localizedVendorNames": {"": "LG Electronics"},
                    "permissions": [
                        "LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CLOSE",
                        "TEST_OPEN", "TEST_PROTECTED", "CONTROL_AUDIO",
                        "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK",
                        "CONTROL_INPUT_MEDIA_RECORDING",
                        "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_TV",
                        "CONTROL_POWER", "READ_APP_STATUS", "READ_CURRENT_CHANNEL",
                        "READ_INPUT_DEVICE_LIST", "READ_NETWORK_STATE",
                        "READ_RUNNING_APPS", "READ_TV_CHANNEL_LIST",
                        "WRITE_NOTIFICATION_TOAST", "READ_POWER_STATE",
                        "READ_COUNTRY_INFO", "CONTROL_MOUSE_AND_KEYBOARD",
                        "CONTROL_INPUT_TEXT"
                    ],
                    "serial": "2f930e2d2cfe083771f68e4fe7bb07"
                },
                "permissions": [
                    "LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CLOSE",
                    "TEST_OPEN", "TEST_PROTECTED", "CONTROL_AUDIO",
                    "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK",
                    "CONTROL_INPUT_MEDIA_RECORDING",
                    "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_TV",
                    "CONTROL_POWER", "READ_APP_STATUS", "READ_CURRENT_CHANNEL",
                    "READ_INPUT_DEVICE_LIST", "READ_NETWORK_STATE",
                    "READ_RUNNING_APPS", "READ_TV_CHANNEL_LIST",
                    "WRITE_NOTIFICATION_TOAST", "READ_POWER_STATE",
                    "READ_COUNTRY_INFO", "CONTROL_MOUSE_AND_KEYBOARD",
                    "CONTROL_INPUT_TEXT"
                ],
                "signatures": [{
                    "signatureVersion": 1,
                    "signature": "eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRyaMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A27Pq1n50cMchmcaXadJhGrOqH5YmHdOCj5NSHzJYrsW0HPlpuAx/ECMeIZYDh6RMqaFM2DXzdKX9NmmyqzJ3o/0lkk/N97gfVRLW5hA29yeAwaCViZNCP8iC9aO0q9fQojoa7NQnAtw=="
                }]
            }
        }
    }
    
    COMMANDS = {
        "volumeUp": ("ssap://audio/volumeUp", {}),
        "volumeDown": ("ssap://audio/volumeDown", {}),
        "off": ("ssap://system/turnOff", {}),
        "getVolume": ("ssap://audio/getVolume", {}),
        "getSystemInfo": ("ssap://system/getSystemInfo", {}),
    }
    
    def __init__(self, name, ip, client_key, use_ssl=True):
        self.name = name
        self.ip = ip
        self.client_key = client_key
        self.use_ssl = use_ssl
        self.ws = None
        self.input_ws = None
        self.msg_id = 0
        self.connected = False
    
    async def connect(self):
        """Connect and register with the TV."""
        protocol = "wss" if self.use_ssl else "ws"
        port = 3001 if self.use_ssl else 3000
        uri = f"{protocol}://{self.ip}:{port}"
        ssl_context = get_ssl_context() if self.use_ssl else None
        
        try:
            self.ws = await asyncio.wait_for(
                websockets.connect(uri, ssl=ssl_context, close_timeout=2),
                timeout=5
            )
            
            # Register
            import copy
            handshake = copy.deepcopy(self.HANDSHAKE)
            if self.client_key:
                handshake["payload"]["client-key"] = self.client_key
            
            await self.ws.send(json.dumps(handshake))
            
            # Wait for registration
            response = await asyncio.wait_for(self.ws.recv(), timeout=5)
            data = json.loads(response)
            
            if data.get("type") == "registered":
                self.connected = True
                # Get input socket for button commands
                await self._connect_input_socket()
                return True
            else:
                raise Exception(f"Registration failed: {data}")
                
        except Exception as e:
            self.connected = False
            raise
    
    async def _connect_input_socket(self):
        """Connect to the pointer input socket for button commands."""
        try:
            response = await self.send_command("ssap://com.webos.service.networkinput/getPointerInputSocket")
            socket_path = response.get("payload", {}).get("socketPath")
            
            if socket_path:
                ssl_context = get_ssl_context() if self.use_ssl else None
                self.input_ws = await websockets.connect(socket_path, ssl=ssl_context)
        except Exception as e:
            print(f"Warning: Could not connect input socket: {e}", file=sys.stderr)
    
    async def send_command(self, uri, payload=None):
        """Send a command to the TV."""
        if not self.ws or not self.connected:
            raise Exception("Not connected")
        
        self.msg_id += 1
        msg = {
            "type": "request",
            "id": f"cmd_{self.msg_id}",
            "uri": uri,
            "payload": payload or {}
        }
        await self.ws.send(json.dumps(msg))
        response = await asyncio.wait_for(self.ws.recv(), timeout=3)
        return json.loads(response)
    
    async def send_button(self, button):
        """Send a button press."""
        if not self.input_ws:
            # Try to reconnect input socket
            await self._connect_input_socket()
        
        if not self.input_ws:
            raise Exception("Input socket not available")
        
        cmd = f"type:button\nname:{button.upper()}\n\n"
        await self.input_ws.send(cmd)
        return {"success": True}
    
    async def execute(self, command, args=None):
        """Execute a command."""
        try:
            if command == "sendButton":
                button = args[0] if args else "ENTER"
                return await self.send_button(button)
            
            elif command == "mute":
                # Discrete mute (true) or unmute (false)
                mute_value = True  # default to mute
                if args and args[0].lower() in ("false", "0", "off"):
                    mute_value = False
                result = await self.send_command("ssap://audio/setMute", {"mute": mute_value})
                return {"success": True, "result": result, "muted": mute_value}
            
            elif command == "on":
                # Power on requires Wake-on-LAN
                return await self.wake_on_lan()
            
            elif command in self.COMMANDS:
                uri, payload = self.COMMANDS[command]
                result = await self.send_command(uri, payload)
                return {"success": True, "result": result}
            
            else:
                return {"success": False, "error": f"Unknown command: {command}"}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    async def wake_on_lan(self):
        """Send Wake-on-LAN magic packet to turn on TV."""
        import socket
        
        config = load_config()
        tv_config = config.get("tvs", {}).get(self.name, {})
        mac = tv_config.get("mac")
        
        if not mac:
            # Try to get MAC from TV (only works if TV is on)
            try:
                result = await self.send_command("ssap://system/getSystemInfo")
                # Store for future use but WoL won't work now since TV is already on
                return {"success": True, "message": "TV is already on"}
            except:
                return {"success": False, "error": "MAC address not saved. Turn TV on manually first, then use 'Auth' to save MAC."}
        
        try:
            # Create magic packet
            mac_bytes = bytes.fromhex(mac.replace(":", "").replace("-", ""))
            magic_packet = b'\xff' * 6 + mac_bytes * 16
            
            # Send to broadcast
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.sendto(magic_packet, ('255.255.255.255', 9))
            sock.close()
            
            return {"success": True, "message": "Wake-on-LAN packet sent"}
        except Exception as e:
            return {"success": False, "error": f"WoL failed: {e}"}
    
    async def close(self):
        """Close connections."""
        self.connected = False
        if self.input_ws:
            await self.input_ws.close()
        if self.ws:
            await self.ws.close()


class Daemon:
    """Daemon that handles commands from the widget."""
    
    def __init__(self):
        self.tv = None
        self.running = False
    
    async def handle_client(self, reader, writer):
        """Handle a command from the widget."""
        try:
            data = await asyncio.wait_for(reader.readline(), timeout=5)
            if not data:
                return
            
            request = json.loads(data.decode().strip())
            cmd = request.get("cmd")
            args = request.get("args", [])
            
            if cmd == "connect":
                # Connect to TV
                name = request.get("name")
                ip = request.get("ip")
                use_ssl = request.get("ssl", True)
                
                config = load_config()
                client_key = config.get("tvs", {}).get(name, {}).get("client_key")
                
                if self.tv:
                    await self.tv.close()
                
                self.tv = TVConnection(name, ip, client_key, use_ssl)
                try:
                    await self.tv.connect()
                    response = {"success": True, "message": "Connected"}
                except Exception as e:
                    response = {"success": False, "error": str(e)}
            
            elif cmd == "disconnect":
                if self.tv:
                    await self.tv.close()
                    self.tv = None
                response = {"success": True}
            
            elif cmd == "status":
                response = {"success": True, "connected": self.tv.connected if self.tv else False}
            
            elif cmd == "stop":
                self.running = False
                response = {"success": True, "message": "Stopping daemon"}
            
            elif self.tv and self.tv.connected:
                response = await self.tv.execute(cmd, args)
            
            else:
                response = {"success": False, "error": "Not connected to TV"}
            
            writer.write((json.dumps(response) + "\n").encode())
            await writer.drain()
            
        except asyncio.TimeoutError:
            pass
        except Exception as e:
            try:
                writer.write((json.dumps({"success": False, "error": str(e)}) + "\n").encode())
                await writer.drain()
            except:
                pass
        finally:
            writer.close()
            await writer.wait_closed()
    
    async def run(self):
        """Run the daemon."""
        # Remove old socket
        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink()
        
        # Write PID file
        PID_FILE.write_text(str(os.getpid()))
        
        self.running = True
        server = await asyncio.start_unix_server(self.handle_client, path=str(SOCKET_PATH))
        
        # Make socket accessible
        os.chmod(SOCKET_PATH, 0o600)
        
        print(f"Daemon listening on {SOCKET_PATH}", file=sys.stderr)
        
        async with server:
            while self.running:
                await asyncio.sleep(0.1)
        
        # Cleanup
        if self.tv:
            await self.tv.close()
        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink()
        if PID_FILE.exists():
            PID_FILE.unlink()


async def send_to_daemon(request):
    """Send a request to the daemon."""
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_unix_connection(path=str(SOCKET_PATH)),
            timeout=1
        )
        writer.write((json.dumps(request) + "\n").encode())
        await writer.drain()
        
        response = await asyncio.wait_for(reader.readline(), timeout=5)
        writer.close()
        await writer.wait_closed()
        
        return json.loads(response.decode().strip())
    except FileNotFoundError:
        return {"success": False, "error": "Daemon not running"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def is_daemon_running():
    """Check if daemon is running."""
    if not PID_FILE.exists():
        return False
    try:
        pid = int(PID_FILE.read_text().strip())
        os.kill(pid, 0)  # Check if process exists
        return True
    except (ProcessLookupError, ValueError):
        # Clean up stale files
        if PID_FILE.exists():
            PID_FILE.unlink()
        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink()
        return False


def main():
    if len(sys.argv) < 2:
        print("Usage: lgtv_daemon.py <command> [args...]")
        print("Commands: start, stop, status, connect, send, ...")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "start":
        if is_daemon_running():
            print(json.dumps({"success": False, "error": "Daemon already running"}))
            sys.exit(0)
        
        # Fork to background
        if os.fork() > 0:
            sys.exit(0)
        
        os.setsid()
        if os.fork() > 0:
            sys.exit(0)
        
        # Redirect stdio
        sys.stdin = open(os.devnull, 'r')
        sys.stdout = open(os.devnull, 'w')
        
        # Run daemon
        daemon = Daemon()
        asyncio.run(daemon.run())
    
    elif command == "stop":
        result = asyncio.run(send_to_daemon({"cmd": "stop"}))
        print(json.dumps(result))
    
    elif command == "status":
        if not is_daemon_running():
            print(json.dumps({"success": True, "running": False}))
        else:
            result = asyncio.run(send_to_daemon({"cmd": "status"}))
            result["running"] = True
            print(json.dumps(result))
    
    elif command == "connect":
        if len(sys.argv) < 4:
            print(json.dumps({"success": False, "error": "Usage: connect <name> <ip> [--no-ssl]"}))
            sys.exit(1)
        
        name = sys.argv[2]
        ip = sys.argv[3]
        use_ssl = "--no-ssl" not in sys.argv
        
        result = asyncio.run(send_to_daemon({
            "cmd": "connect",
            "name": name,
            "ip": ip,
            "ssl": use_ssl
        }))
        print(json.dumps(result))
    
    elif command == "send":
        if len(sys.argv) < 3:
            print(json.dumps({"success": False, "error": "Usage: send <command> [args...]"}))
            sys.exit(1)
        
        cmd = sys.argv[2]
        args = sys.argv[3].split(",") if len(sys.argv) > 3 and sys.argv[3] else []
        
        result = asyncio.run(send_to_daemon({"cmd": cmd, "args": args}))
        print(json.dumps(result))
    
    else:
        # Direct command to daemon
        args = sys.argv[2].split(",") if len(sys.argv) > 2 and sys.argv[2] else []
        result = asyncio.run(send_to_daemon({"cmd": command, "args": args}))
        print(json.dumps(result))


if __name__ == "__main__":
    main()
