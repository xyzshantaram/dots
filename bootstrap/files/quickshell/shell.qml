// The niri shell.
//
//   qs -p ~/.config/quickshell      run it
//   qs -p ~/.config/quickshell      run it again after an edit, replacing the instance
//
// niri starts it via `spawn-at-startup "qs"` (see 110-niri.ts), so on a normal
// session this file is already running and edits are picked up live.
//
// Everything is flat in this directory on purpose. QML resolves a sibling
// component by filename with no import at all, and the singletons declared in
// qmldir are visible to every file here — which is why there is no bar/
// subdirectory to import from and no relative-import chain to keep in mind.
// The one subdirectory is services/, and the files here import it by name.

import QtQuick
import Quickshell

ShellRoot {
    Bar {}
}
