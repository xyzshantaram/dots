// The shell.
//
//   qs -p ~/.config/shell      run this one
//   qs -p ~/.config/quickshell run the older one
//
// Two configs side by side on purpose: this tree is being built next to the
// working one, and niri still spawns the old one. Nothing here can take the
// laptop down while that is true.
//
// Everything below the root is one window. QML resolves a sibling component by
// filename with no import, and the singletons in core/, bar/ and float/ are
// declared in their own qmldir — so a directory states what it contains, which
// is the thing a flat tree stops doing once there are twenty files in it.

import QtQuick
import Quickshell

ShellRoot {
    Shell {}
}
