#!/bin/bash
# SUDO_ASKPASS helper: macOS password dialog (for casks whose installer runs through sudo, e.g. OverSight, BlockBlock).
osascript -e 'text returned of (display dialog "Mot de passe administrateur (installation sécurité)" default answer "" with hidden answer with title "macos-config")'
