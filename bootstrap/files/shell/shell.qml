// The shell.
//
//   qs -p ~/.config/shell    run it
//   qs -p ~/.config/shell    run it again after an edit, replacing the instance
//
// This is now the only config. The tree it was built beside is gone, and
// 120-quickshell.ts deletes any ~/.config/quickshell it finds — a bare `qs`
// reads that path, and it would load a bar with no click-catcher.
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
