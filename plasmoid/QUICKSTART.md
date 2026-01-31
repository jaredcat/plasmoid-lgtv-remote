# Quick Start Guide

## NixOS Users

```bash
# 1. Enter development shell
nix develop

# 2. Install widget
cd plasmoid && ./install.sh

# 3. Add to panel, configure IP, click Auth
```

For persistent use, add to your `configuration.nix`:
```nix
environment.systemPackages = [
  (python3.withPackages (ps: [ ps.websockets ]))
];
```

## Other Distros

```bash
# 1. Install dependency
pip install --user websockets

# 2. Install widget
cd plasmoid && ./install.sh

# 3. Add to panel, configure IP, click Auth
```

## First Time Setup

1. Right-click panel → "Add Widgets"
2. Search "LG TV Remote" → drag to panel
3. Click widget to open
4. Enter TV IP address and name
5. Click "Auth" → accept on TV screen

Done! Use buttons or keyboard shortcuts to control your TV.
