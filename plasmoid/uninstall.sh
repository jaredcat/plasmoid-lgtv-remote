#!/usr/bin/env bash
# Uninstall LG TV Remote Plasma widget

PLASMOID_ID="com.codekitties.lgtv.remote"

echo "Uninstalling LG TV Remote..."

if kpackagetool6 -t Plasma/Applet -r "$PLASMOID_ID" 2>/dev/null; then
    echo "Successfully uninstalled."
else
    echo "Widget not found or already uninstalled."
fi
