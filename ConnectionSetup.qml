import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
    id: root

    property color foreground: Color.popups.text
    property color accent: Color.accent
    property color urgent: Color.urgent
    property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.56)
    property string fontFamily: Style.font.family
    property bool busy: false
    property bool hasSavedPassword: false
    property bool canCancel: false
    property string profileId: ""
    property alias focusTarget: profileField
    readonly property bool editingExisting: profileId !== ""
    readonly property string engineLabel: engineField.value === "mysql" ? "MySQL" : "PostgreSQL"
    readonly property bool valid: profileField.text.trim() !== "" && hostField.text.trim() !== "" && databaseField.text.trim() !== "" && userField.text.trim() !== "" && Number(portField.text) >= 1 && Number(portField.text) <= 65535 && (!sshToggle.checked || (sshHostField.text.trim() !== "" && sshUserField.text.trim() !== "" && Number(sshPortField.text) >= 1 && Number(sshPortField.text) <= 65535))

    signal connectRequested(var values, string password, bool remember)
    signal cancelRequested()

    function applyEngine(next) {
        var previous = engineField.value;
        engineField.value = next;
        if (previous === next)
            return;
        var oldPort = previous === "mysql" ? 3306 : 5432;
        var oldDatabase = previous === "mysql" ? "mysql" : "postgres";
        var oldUser = previous === "mysql" ? "root" : "postgres";
        if (Number(portField.text) === oldPort)
            portField.text = next === "mysql" ? "3306" : "5432";
        if (databaseField.text.trim() === oldDatabase)
            databaseField.text = next === "mysql" ? "mysql" : "postgres";
        if (userField.text.trim() === oldUser)
            userField.text = next === "mysql" ? "root" : "postgres";
    }

    function load(values, remembered) {
        var source = values || {};
        profileId = String(source.id || "");
        var engine = String(source.engine || "postgresql") === "mysql" ? "mysql" : "postgresql";
        engineField.value = engine;
        profileField.text = String(source.name || source.profileName || "Postgres");
        toneField.value = String(source.tone || "accent");
        hostField.text = String(source.host === undefined ? "127.0.0.1" : source.host);
        portField.text = String(source.port || (engine === "mysql" ? 3306 : 5432));
        databaseField.text = String(source.database || (engine === "mysql" ? "mysql" : "postgres"));
        userField.text = String(source.user || (engine === "mysql" ? "root" : "postgres"));
        sslField.value = String(source.sslMode || "prefer");
        passwordField.text = "";
        rememberToggle.checked = source.rememberPassword === undefined ? true : source.rememberPassword === true;
        sshToggle.checked = source.sshEnabled === true;
        sshHostField.text = String(source.sshHost || "");
        sshPortField.text = String(source.sshPort || 22);
        sshUserField.text = String(source.sshUser || "");
        identityField.text = String(source.sshIdentityFile || "");
        Qt.callLater(function() {
            profileField.forceActiveFocus();
            profileField.selectAll();
        });
    }

    function submit() {
        if (!valid || busy)
            return ;
        connectRequested({
            "configured": true,
            "engine": engineField.value,
            "id": profileId,
            "name": profileField.text.trim(),
            "profileName": profileField.text.trim(),
            "tone": toneField.value,
            "host": hostField.text.trim(),
            "port": Number(portField.text),
            "database": databaseField.text.trim(),
            "user": userField.text.trim(),
            "sslMode": sslField.value,
            "rememberPassword": rememberToggle.checked,
            "sshEnabled": sshToggle.checked,
            "sshHost": sshHostField.text.trim(),
            "sshPort": Number(sshPortField.text),
            "sshUser": sshUserField.text.trim(),
            "sshIdentityFile": identityField.text.trim()
        }, passwordField.text, rememberToggle.checked);
    }

    Layout.fillWidth: true
    implicitHeight: form.implicitHeight + Style.space(28)
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.025)
    borderSpec: Border.controlSpec("normal", foreground, accent)
    radius: Style.cornerRadius

    ColumnLayout {
        id: form

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(14)
        spacing: Style.space(10)

        RowLayout {
            Layout.fillWidth: true

            Rectangle {
                Layout.preferredWidth: Style.space(8)
                Layout.preferredHeight: Style.space(8)
                radius: width / 2
                color: root.accent
            }

            Text {
                text: "PROFILE"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "READ ONLY"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.8
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            TextField {
                id: profileField
                Layout.fillWidth: true
                placeholderText: "Profile name"
                foreground: root.foreground
            }

            Dropdown {
                id: toneField
                Layout.preferredWidth: Style.space(150)
                showLabel: false
                value: "accent"
                options: [{ "value": "accent", "label": "Accent tone" }, { "value": "soft", "label": "Soft tone" }, { "value": "warm", "label": "Warm tone" }, { "value": "neutral", "label": "Neutral tone" }]
                foreground: root.foreground
                onChanged: function(next) { value = next; }
            }

            Dropdown {
                id: engineField
                Layout.preferredWidth: Style.space(142)
                showLabel: false
                value: "postgresql"
                options: [{ "value": "postgresql", "label": "PostgreSQL" }, { "value": "mysql", "label": "MySQL 8+" }]
                foreground: root.foreground
                onChanged: function(next) { root.applyEngine(next); }
            }
        }

        PanelSeparator {
            Layout.fillWidth: true
            foreground: root.foreground
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: root.engineLabel.toUpperCase()
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "DATABASE TARGET"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.8
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            TextField {
                id: hostField
                Layout.fillWidth: true
                placeholderText: root.engineLabel + " host"
                foreground: root.foreground
                onAccepted: portField.forceActiveFocus()
            }

            TextField {
                id: portField
                Layout.preferredWidth: Style.space(112)
                placeholderText: "DB port"
                foreground: root.foreground
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 65535 }
                onAccepted: databaseField.forceActiveFocus()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            TextField {
                id: databaseField
                Layout.fillWidth: true
                placeholderText: "Database"
                foreground: root.foreground
                onAccepted: userField.forceActiveFocus()
            }

            TextField {
                id: userField
                Layout.fillWidth: true
                placeholderText: "Database user"
                foreground: root.foreground
                onAccepted: passwordField.forceActiveFocus()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            TextField {
                id: passwordField
                Layout.fillWidth: true
                password: true
                placeholderText: root.editingExisting ? (root.hasSavedPassword ? "Password saved · blank keeps it" : "Password · blank keeps current") : "Password (optional)"
                foreground: root.foreground
                onAccepted: root.submit()
            }

            Dropdown {
                id: sslField
                Layout.preferredWidth: Style.space(150)
                showLabel: false
                value: "prefer"
                options: [{ "value": "disable", "label": "TLS disabled" }, { "value": "prefer", "label": "TLS preferred" }, { "value": "require", "label": "TLS required" }, { "value": "verify-ca", "label": "Verify CA" }, { "value": "verify-full", "label": "Verify host" }]
                foreground: root.foreground
                onChanged: function(next) { value = next; }
            }
        }

        Toggle {
            id: rememberToggle
            Layout.fillWidth: true
            label: "Remember database password"
            description: "Stored in your desktop keyring. Editing this profile never exposes it."
            checked: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: checked = !checked
        }

        PanelSeparator {
            Layout.fillWidth: true
            foreground: root.foreground
        }

        Toggle {
            id: sshToggle
            Layout.fillWidth: true
            label: "Connect through an SSH gateway"
            description: "Use this when " + root.engineLabel + " is only reachable from another machine."
            checked: false
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: checked = !checked
        }

        RowLayout {
            visible: sshToggle.checked
            Layout.fillWidth: true
            spacing: Style.space(8)

            TextField {
                id: sshHostField
                Layout.fillWidth: true
                placeholderText: "SSH host"
                foreground: root.foreground
            }

            TextField {
                id: sshPortField
                Layout.preferredWidth: Style.space(112)
                placeholderText: "SSH port"
                foreground: root.foreground
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 65535 }
            }
        }

        RowLayout {
            visible: sshToggle.checked
            Layout.fillWidth: true
            spacing: Style.space(8)

            TextField {
                id: sshUserField
                Layout.fillWidth: true
                placeholderText: "SSH user"
                foreground: root.foreground
            }

            TextField {
                id: identityField
                Layout.fillWidth: true
                placeholderText: "Identity file (optional)"
                foreground: root.foreground
            }
        }

        Text {
            visible: sshToggle.checked
            Layout.fillWidth: true
            text: "Hazel manages the local forwarding endpoint automatically. Use an SSH agent or identity file; changed host keys still fail safely."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: root.editingExisting ? "Blank password keeps the credential already in use." : "Connection details stay in Omarchy; credentials do not."
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
            }

            Button {
                visible: root.canCancel
                text: "Cancel"
                focusable: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.cancelRequested()
            }

            Button {
                text: root.busy ? "Saving…" : (root.editingExisting ? "Save changes" : "Add profile")
                enabled: root.valid && !root.busy
                bordered: true
                focusable: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.submit()
            }
        }
    }
}
