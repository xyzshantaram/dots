pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// The one org.freedesktop.Notifications server.
//
// A singleton rather than a child of the shell window: the shell is now one
// window per output, and a second NotificationServer would lose the D-Bus name
// to the first and draw nothing. Everything that shows a notification — the
// banners and the control centre — reads this instance.
Singleton {
    id: root

    /** The server itself, for the components that draw from it. */
    property alias server: notifications

    /**
     * Track everything we are told about.
     *
     * A notification only appears in `trackedNotifications` — which is what
     * both the banners and the panel's list read — once it is marked tracked,
     * and Quickshell leaves that to the consumer so a server can also be a
     * pass-through. This one is the only daemon on the bus, so everything that
     * arrives here is meant to be drawn.
     */
    NotificationServer {
        id: notifications

        onNotification: (note) => {
            note.tracked = true;
        }
    }
}
