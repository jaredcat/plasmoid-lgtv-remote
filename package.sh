#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR/plasmoid/package"
OUTPUT_NAME="lgtv-remote.plasmoid"
OUTPUT_PATH="$SCRIPT_DIR/$OUTPUT_NAME"

echo "Packaging LG TV Remote widget..."

# Remove old package if exists
rm -f "$OUTPUT_PATH"

# Create the .plasmoid file (it's just a zip)
cd "$PACKAGE_DIR"
zip -r "$OUTPUT_PATH" . -x "*.pyc" -x "__pycache__/*" -x ".git/*"

echo ""
echo "Package created: $OUTPUT_PATH"
echo ""
echo "Users can install it via:"
echo "  1. System Settings → Appearance → Plasma Style → Get New... → Install from File"
echo "  2. Or: kpackagetool6 -t Plasma/Applet -i $OUTPUT_NAME"
echo ""
echo "Requirements for users:"
echo "  - KDE Plasma 6"
echo "  - Python 3 with 'websockets' module"
echo "    NixOS: Add (python3.withPackages (ps: [ps.websockets])) to systemPackages"
echo "    Other: pip install websockets"
