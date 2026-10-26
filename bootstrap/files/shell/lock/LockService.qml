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

    // True while the lock is showing "Sleeping..." instead of the password
    // card. Set by prepareForSleep() and cleared by wakeUp().
    property bool sleeping: false

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
        root.sleeping = false;
        root.locked = true;
        if (!pam.active) pam.active = true;
    }

    /**
     * Lock for hibernation.
     *
     * Covers the screen like lock(), but drops the PAM conversation instead of
     * starting one. The conversation cannot survive the snapshot: it comes back
     * with an fprintd verification that timed out while the machine was asleep,
     * which is why fingerprint unlock did nothing on resume. wakeUp() starts a
     * fresh conversation instead.
     */
    function prepareForSleep(): void {
        root.pamError = "";
        root.pamMessage = "";
        root.pamChecking = false;
        root.sleeping = true;
        root.locked = true;
        pam.active = false;
    }

    /**
     * The other edge: show the prompt again and start a fresh conversation, so
     * pam_fprintd runs VerifyStart rather than resuming a dead one.
     */
    function wakeUp(): void {
        root.sleeping = false;
        root.pamError = "";
        root.pamMessage = "";
        if (!root.locked) return;
        pam.active = false;
        Qt.callLater(() => {
            if (root.locked && !root.sleeping) pam.active = true;
        });
    }

    function respond(text: string): void {
        if (root.sleeping) return;
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
            // Dropped for hibernation: whatever arrives is the cancellation,
            // not a wrong password, and wakeUp() starts a fresh conversation.
            // It must not unlock either.
            if (root.sleeping) return;
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
