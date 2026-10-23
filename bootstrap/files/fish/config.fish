# Minimal fish config for the Arch side.
#
# Only what the shell needs to be pleasant on day one: a PATH for user
# binaries, the editor, and the fortune greeting in functions/. Aliases,
# abbreviations and tool paths are deliberately left for later, and can be
# copied from the Fedora config as they are wanted.
#
# The greeting lives in functions/fish_greeting.fish, the prompt in
# functions/fish_prompt.fish, git prompt colours in conf.d/git_prompt.fish.

set -gx PATH $HOME/.local/bin $PATH

# Bun, when the official installer put it under ~/.bun. setup-bun.sh installs to
# /usr/local instead, which needs no PATH entry. A no-op when bun is not there,
# so this file is still correct on a machine without it.
if test -x $HOME/.bun/bin/bun
    set -gx PATH $HOME/.bun/bin $PATH
end

set -gx EDITOR micro

# Tell programs which desktop they are running under. niri sets this itself,
# but shells started outside the session (TTY, ssh) should not claim a
# different one.
if not set -q XDG_CURRENT_DESKTOP
    set -gx XDG_CURRENT_DESKTOP niri
end
