#!/usr/bin/env bash
# Install LG TV Remote Plasma 6 widget

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR/package"
PLASMOID_ID="com.codekitties.lgtv.remote"

echo "Installing LG TV Remote Plasma widget..."

# Check for Python websockets module
if ! python3 -c "import websockets" 2>/dev/null; then
    echo ""
    echo "WARNING: Python 'websockets' module not found!"
    echo ""
    echo "The widget requires Python with websockets to control your TV."
    echo ""
    echo "NixOS: Add to configuration.nix:"
    echo "  environment.systemPackages = ["
    echo "    (python3.withPackages (ps: [ ps.websockets ]))"
    echo "  ];"
    echo ""
    echo "Or use the dev shell: nix develop"
    echo ""
    echo "Other distros: pip install --user websockets"
    echo ""
fi

# Remove old installation if exists
if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -q "$PLASMOID_ID"; then
    echo "Removing previous installation..."
    kpackagetool6 -t Plasma/Applet -r "$PLASMOID_ID" 2>/dev/null || true
fi

# Install the plasmoid
echo "Installing plasmoid from $PACKAGE_DIR..."
kpackagetool6 -t Plasma/Applet -i "$PACKAGE_DIR"

echo ""
echo "Installation complete!"
echo ""
echo "To use the widget:"
echo "  1. Right-click on your panel or desktop"
echo "  2. Select 'Add Widgets' or 'Enter Edit Mode'"
echo "  3. Search for 'LG TV Remote'"
echo "  4. Drag it to your panel or desktop"
echo ""
echo "First time setup:"
echo "  1. Enter your TV name (any name you choose)"
echo "  2. Enter your TV's IP address"
echo "  3. Click 'Auth' and accept the pairing on your TV"
echo ""
