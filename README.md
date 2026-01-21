# LG TV Remote for KDE Plasma 6

A KDE Plasma 6 widget to control your LG webOS TV directly from your desktop.

![Plasma Widget](https://img.shields.io/badge/Plasma-6.0+-blue)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Power Control**: Turn your TV on (Wake-on-LAN) and off
- **Navigation**: D-pad controls for menu navigation  
- **Volume**: Volume up/down and mute/unmute
- **Keyboard Shortcuts**: Control your TV with keyboard
- **Persistent Daemon**: Fast response with background connection
- **SSL Support**: Works with newer TV firmware

## Installation

### Step 1: Install Python websockets

**NixOS** - Add to your `configuration.nix`:
```nix
environment.systemPackages = with pkgs; [
  (python3.withPackages (ps: [ ps.websockets ]))
];
```

**Other distros**:
```bash
pip install --user websockets
```

### Step 2: Install the Widget

**Option A: From .plasmoid file** (easiest)
1. Download `lgtv-remote.plasmoid` from [Releases](https://github.com/jaredcat/plasmoid-lgtv-remote/releases)
2. Open System Settings → Appearance → Plasma Style
3. Click "Get New..." → "Install from File..."
4. Select the downloaded `.plasmoid` file

**Option B: From source**
```bash
git clone https://github.com/jaredcat/plasmoid-lgtv-remote.git
cd plasmoid-lgtv-remote/plasmoid
./install.sh
```

### Step 3: Add to Panel

1. Right-click your panel → "Add Widgets"
2. Search for "LG TV Remote"
3. Drag to your panel

### Step 4: Setup

1. Click the widget to open it
2. Enter your TV's IP address (find in TV Settings → Network)
3. Enter a name for your TV (e.g., "LivingRoomTV")
4. Click "Auth" and accept the pairing on your TV screen

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Arrow Keys | Navigate |
| Enter | OK/Select |
| Backspace/Esc | Back |
| + / = | Volume Up |
| - | Volume Down |
| Shift + = | Unmute |
| Shift + - | Mute |

## Power On (Wake-on-LAN)

For Power On to work, enable "Wake on LAN" on your TV:
- Settings → Network → "Mobile TV On" or "Wake on LAN"

## Updating the Widget

After reinstalling, refresh Plasma:
```bash
plasmashell --replace &
```

## Building from Source

```bash
# Clone
git clone https://github.com/jaredcat/plasmoid-lgtv-remote.git
cd plasmoid-lgtv-remote

# NixOS: Enter dev shell
nix develop

# Install
cd plasmoid && ./install.sh

# Package for distribution
./package.sh
```

## Creating a Release

Push a version tag to trigger automatic packaging:
```bash
git tag v1.0.0
git push origin v1.0.0
```

The GitHub Action will create a release with the `.plasmoid` file attached.

## Troubleshooting

### Widget not appearing after install
```bash
plasmashell --replace &
```

### "websockets module not found"
Install the Python websockets module (see Step 1 above).

### Authentication fails
- Make sure TV is on and connected to network
- Check the IP address is correct
- Accept the pairing prompt on TV screen

### Power On doesn't work
- Enable "Wake on LAN" in TV network settings
- Wait a few seconds after Power Off before trying Power On

## License

MIT License

## Credits

- Protocol based on [LGWebOSRemote](https://github.com/klattimer/LGWebOSRemote)
- Built for KDE Plasma 6
