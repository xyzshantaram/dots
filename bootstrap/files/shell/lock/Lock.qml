import QtQuick
import Quickshell
import Quickshell.Wayland

// The WlSessionLock instance. Not per screen: Quickshell instantiates the
// `surface` Component once for each output. Instantiated by Shell.qml, not
// inside a Variants block.

WlSessionLock {
    id: sessionLock

    locked: LockService.locked
    surface: Component { LockSurface { } }

    onSecureChanged: {
        LockService.secure = sessionLock.secure;
    }
}
