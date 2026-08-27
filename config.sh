# config.sh — optional user configuration for common.sh
#
# Copy or symlink this file to ~/scripts/config.sh, then add to your rc:
#   [ -f ~/scripts/config.sh ] && . ~/scripts/config.sh
#
# Or source it before common.sh in your rc file.
#
# All settings default to off; uncomment to enable.

# Enable shell keybindings (Alt+arrows, ^X/^B/^Y/^Q).
# Set to 1 to activate the bindkey block in common.sh.
#export SCRIPTS_KEYBINDINGS=1

# Where the notebooks repo is checked out. common.sh only defines the helpers
# that need it (e.g. ClaudeDashboard) when this directory exists.
# export NOTEBOOK_FOLDER="$HOME/notebooks"
