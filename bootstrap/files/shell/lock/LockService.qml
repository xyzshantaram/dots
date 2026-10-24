pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// Session-lock state and PAM. Lock.qml drives WlSessionLock from `locked`;
// every LockSurface shares the one PamContext below.

Singleton {
    id: root

    // Stays true until PAM returns Success.
    property bool locked: false

    // Mirrors WlSessionLock.secure: every output is covered. Written by
    // Lock.qml, which owns the WlSessionLock instance.
    property bool secure: false

    property bool pamActive: false
    property bool pamChecking: false
    property string pamMessage: ""

    // Survives the PAM restart after a failure, so the user actually sees it.
    property string pamError: ""

    function lock(): void {
        if (root.locked) return;
        root.pamError = "";
        root.pamMessage = "";
        root.locked = true;
        if (!pam.active) pam.active = true;
    }

    function respond(text: string): void {
        if (!pam.active) {
            pam.active = true;
            return;
        }
        if (!pam.responseRequired) return;
        root.pamError = "";
        root.pamChecking = true;
        pam.respond(text);
    }

    PamContext {
        id: pam
        config: "qslock"

        onActiveChanged: root.pamActive = pam.active
        onMessageChanged: root.pamMessage = pam.message || ""

        onCompleted: result => {
            root.pamChecking = false;
            if (result === PamResult.Success) {
                root.locked = false;
                root.pamError = "";
                root.pamMessage = "";
                root.pamActive = false;
                return;
            }
            root.pamError = result === PamResult.Failed
                ? "Authentication failed"
                : "PAM error — try again";
            root.pamActive = false;
            Qt.callLater(() => { if (root.locked) pam.active = true; });
        }

        onError: err => {
            console.warn("[LockService] PAM error:", err);
            root.pamChecking = false;
            root.pamError = "PAM error — try again";
        }
    }
}
