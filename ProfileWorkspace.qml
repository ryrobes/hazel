import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

ColumnLayout {
    id: root

    property var profiles: []
    property color foreground: Color.popups.text
    property color accent: Color.accent
    property color urgent: Color.urgent
    property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.56)
    property string fontFamily: Style.font.family

    signal profileEnabledChanged(var profile, bool enabled)
    signal profileEdited(var profile)
    signal profileAdded()
    signal closeRequested()

    function toneColor(tone) {
        if (tone === "warm")
            return Qt.tint(accent, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.32));
        if (tone === "soft")
            return Qt.tint(accent, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.28));
        if (tone === "neutral")
            return foreground;
        return accent;
    }

    Layout.fillWidth: true
    spacing: Style.space(12)

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: "MONITORED PROFILES"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                font.letterSpacing: 1.1
            }

            Text {
                Layout.fillWidth: true
                text: "Enable every database Hazel should sample. Each enabled profile keeps its own live state and history."
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
            }
        }

        Button {
            text: "+ Add"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.profileAdded()
        }

        Button {
            text: "Done"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.closeRequested()
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Style.space(8)
        rowSpacing: Style.space(8)

        Repeater {
            model: root.profiles

            delegate: BorderSurface {
                id: profileCard

                required property var modelData
                readonly property bool monitored: modelData.enabled === undefined || modelData.enabled === true
                readonly property color tone: root.toneColor(String(modelData.tone || "accent"))

                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(118)
                color: Qt.rgba(tone.r, tone.g, tone.b, monitored ? 0.095 : 0.025)
                borderSpec: Border.controlSpec(monitored ? "active" : "normal", root.foreground, tone)
                radius: Style.cornerRadius

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Style.space(3)
                    color: profileCard.tone
                    opacity: profileCard.monitored ? 0.95 : 0.22
                    radius: parent.radius
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.space(11)
                    spacing: Style.space(4)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(6)

                        Rectangle {
                            Layout.preferredWidth: Style.space(7)
                            Layout.preferredHeight: Style.space(7)
                            radius: width / 2
                            color: profileCard.tone
                            opacity: profileCard.monitored ? 1 : 0.3
                        }

                        Text {
                            Layout.fillWidth: true
                            text: String(profileCard.modelData.name || profileCard.modelData.profileName || "Postgres")
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            text: profileCard.monitored ? "MONITOR" : "PAUSED"
                            color: profileCard.monitored ? profileCard.tone : root.muted
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        ToggleSwitch {
                            checked: profileCard.monitored
                            foreground: root.foreground
                            accent: profileCard.tone
                            trackHeight: Style.space(18)
                            onToggled: root.profileEnabledChanged(profileCard.modelData, !profileCard.monitored)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: String(profileCard.modelData.database || "postgres") + "  ·  " + String(profileCard.modelData.user || "postgres")
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: profileCard.modelData.sshEnabled === true
                            ? "SSH  " + String(profileCard.modelData.sshUser || "") + "@" + String(profileCard.modelData.sshHost || "")
                            : String(profileCard.modelData.host || "local socket") + ":" + String(profileCard.modelData.port || 5432)
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: profileCard.modelData.sshEnabled === true ? "TUNNELED" : "DIRECT"
                            color: root.muted
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        Button {
                            text: "Edit"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            onClicked: root.profileEdited(profileCard.modelData)
                        }
                    }
                }
            }
        }
    }
}
