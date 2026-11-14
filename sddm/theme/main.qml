import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root

    readonly property real s: parseFloat(config.scale || "1")
    readonly property color bg: "#282828"
    readonly property color fg: "#d4d4d4"
    readonly property color muted: "#bdae93"
    readonly property color border: "#7c6f64"
    readonly property color yellow: "#fabd2f"
    readonly property color green: "#b8bb26"
    readonly property color red: "#fb4934"

    property bool capsLocked: false
    property int sessionIndex: sessionModel.lastSession >= 0 ? sessionModel.lastSession : 0
    property date now: new Date()

    FontLoader {
        source: "HackNerdFont-Regular.ttf"
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Image {
        anchors.fill: parent
        source: config.background || "background.jpg"
        fillMode: Image.PreserveAspectCrop
    }

    Rectangle {
        anchors.fill: parent
        color: "#cc282828"
    }

    Rectangle {
        id: card
        width: 380 * root.s
        height: content.height + 64 * root.s
        radius: 8 * root.s
        anchors.centerIn: parent
        color: root.bg
        border.color: root.border
        border.width: 2 * root.s

        Column {
            id: content
            x: 32 * root.s
            width: parent.width - 64 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 16 * root.s

            Label {
                text: Qt.formatDateTime(root.now, "HH:mm")
                color: root.fg
                font.pixelSize: 56 * root.s
                font.family: "Hack Nerd Font"
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Label {
                text: Qt.formatDateTime(root.now, "dddd, d MMMM")
                color: root.muted
                font.pixelSize: 16 * root.s
                font.family: "Hack Nerd Font"
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
            }

            TextField {
                id: userField
                width: parent.width
                text: userModel.lastUser || ""
                placeholderText: qsTr("User")
                color: root.fg
                placeholderTextColor: root.muted
                font.pixelSize: 18 * root.s
                font.family: "Hack Nerd Font"
                leftPadding: 14 * root.s
                topPadding: 12 * root.s
                bottomPadding: 12 * root.s
                background: Rectangle {
                    color: "#32302f"
                    border.color: userField.activeFocus ? root.yellow : root.border
                    border.width: 2 * root.s
                }
                Keys.onPressed: root.watchCaps(event)
                onAccepted: passField.forceActiveFocus()
            }

            TextField {
                id: passField
                width: parent.width
                placeholderText: qsTr("Password")
                echoMode: TextInput.Password
                color: root.fg
                placeholderTextColor: root.muted
                font.pixelSize: 18 * root.s
                font.family: "Hack Nerd Font"
                leftPadding: 14 * root.s
                topPadding: 12 * root.s
                bottomPadding: 12 * root.s
                background: Rectangle {
                    color: "#32302f"
                    border.color: passField.activeFocus ? root.yellow : root.border
                    border.width: 2 * root.s
                }
                Keys.onPressed: root.watchCaps(event)
                onAccepted: root.tryLogin()
            }

            Label {
                text: qsTr("Caps Lock")
                color: root.yellow
                font.pixelSize: 14 * root.s
                font.family: "Hack Nerd Font"
                visible: root.capsLocked
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Button {
                id: loginButton
                width: parent.width
                height: 48 * root.s
                text: qsTr("Log in")
                font.pixelSize: 18 * root.s
                font.family: "Hack Nerd Font"
                enabled: userField.length > 0 && passField.length > 0
                background: Rectangle {
                    color: loginButton.enabled
                        ? (loginButton.hovered ? "#c8d04a" : root.green)
                        : "#504945"
                }
                contentItem: Label {
                    text: loginButton.text
                    color: loginButton.enabled ? "#282828" : root.muted
                    font: loginButton.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.tryLogin()
            }

            Label {
                id: failLabel
                text: qsTr("Login failed")
                color: root.red
                font.pixelSize: 14 * root.s
                font.family: "Hack Nerd Font"
                visible: false
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Row {
                width: parent.width
                Label {
                    id: sessionLabel
                    text: sessionModel.count > 0
                        ? sessionModel.data(sessionModel.index(root.sessionIndex, 0), 0x0100)
                        : ""
                    color: root.muted
                    font.pixelSize: 14 * root.s
                    font.family: "Hack Nerd Font"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: parent.width - sessionLabel.width - 2 * 40 * root.s; height: 1 }
                PowerButton {
                    glyph: "\uf2f1"
                    onClicked: sddm.reboot()
                }
                PowerButton {
                    glyph: "\uf011"
                    onClicked: sddm.powerOff()
                }
            }
        }
    }

    component PowerButton: Label {
        id: control
        property string glyph
        signal clicked
        text: glyph
        color: mouseArea.containsMouse ? root.red : root.muted
        font.pixelSize: 18 * root.s
        font.family: "Hack Nerd Font"
        leftPadding: 20 * root.s
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: control.clicked()
        }
    }

    function watchCaps(event) {
        if (event.key === Qt.Key_CapsLock) capsLocked = !capsLocked
    }

    function tryLogin() {
        failLabel.visible = false
        sddm.login(userField.text, passField.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            failLabel.visible = true
            passField.selectAll()
            passField.forceActiveFocus()
        }
        function onLoginSucceeded() {
            failLabel.visible = false
        }
    }
}
