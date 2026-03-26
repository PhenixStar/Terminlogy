# Store the initial ZDOTDIR value
TERMINOLGY_ZDOTDIR="$ZDOTDIR"

# Source the original zshenv
[ -f ~/.zshenv ] && source ~/.zshenv

# Detect if ZDOTDIR has changed
if [ "$ZDOTDIR" != "$TERMINOLGY_ZDOTDIR" ]; then
  # If changed, manually source your custom zshrc from the original TERMINOLGY_ZDOTDIR
  [ -f "$TERMINOLGY_ZDOTDIR/.zshrc" ] && source "$TERMINOLGY_ZDOTDIR/.zshrc"
fi