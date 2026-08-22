import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
    readonly property var panelItem: panelLoader.item

    function connectionSignature() {
        var value = root.settings || {
        };
        return JSON.stringify({
            "profiles": value.profiles || [],
            "closedRefreshSec": value.closedRefreshSec || 5,
            "openRefreshSec": value.openRefreshSec || 2,
            "historyHours": value.historyHours || 6
        });
    }

    function leaderWidget() {
        if (!root.bar || typeof root.bar.moduleWidgets !== "function")
            return root;

        var peers = root.bar.moduleWidgets(root.moduleName);
        var signature = root.connectionSignature();
        for (var i = 0; i < peers.length; i++) {
            var peer = peers[i];
            if (peer && typeof peer.connectionSignature === "function" && peer.connectionSignature() === signature)
                return peer;

        }
        return root;
    }

    function open() {
        if (panelLoader.item)
            panelLoader.item.open();

    }

    function close() {
        if (panelLoader.item)
            panelLoader.item.close();

    }

    function toggle() {
        if (panelLoader.item)
            panelLoader.item.toggle();

    }

    function refresh() {
        if (panelLoader.item)
            panelLoader.item.refresh();

    }

    function closeForPopoutSwitch() {
        if (panelLoader.item)
            panelLoader.item.closeForPopoutSwitch();

    }

    function injectPanel() {
        if (!panelLoader.item)
            return ;

        panelLoader.item.bar = root.bar;
        panelLoader.item.anchorItem = button;
        panelLoader.item.hostWidget = root;
        panelLoader.item.settings = root.settings;
        var leader = root.leaderWidget();
        panelLoader.item.collectorActive = leader === root;
        panelLoader.item.sourcePanel = leader && leader.panelItem ? leader.panelItem : null;
        leaderElection.restart();
    }

    moduleName: "ryrobes.hazel"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Loader {
        id: panelLoader

        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel();
            Qt.callLater(root.injectPanel);
        }
    }

    Timer {
        id: leaderElection

        interval: 250
        repeat: false
        onTriggered: {
            if (!panelLoader.item)
                return ;

            var leader = root.leaderWidget();
            panelLoader.item.collectorActive = leader === root;
            panelLoader.item.sourcePanel = leader && leader.panelItem ? leader.panelItem : null;
        }
    }

    WidgetButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        text: panelLoader.item ? panelLoader.item.toolbarText : "—"
        labelVisible: false
        keepSpace: true
        fixedWidth: vertical ? barSize : horizontalContent.implicitWidth + Style.space(12)
        fixedHeight: vertical ? verticalContent.implicitHeight + Style.space(10) : barSize
        foreground: panelLoader.item ? panelLoader.item.toolbarBaseColor : (root.bar ? root.bar.barForeground : Color.foreground)
        fontSize: Style.font.caption
        horizontalMargin: Style.space(6)
        active: panelLoader.item ? panelLoader.item.toolbarActive : false
        activeColor: panelLoader.item ? panelLoader.item.toolbarColor : Color.urgent
        tooltipText: panelLoader.item ? panelLoader.item.toolbarTooltip : "Hazel · connecting"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.MiddleButton)
                root.refresh();
            else
                root.toggle();
        }

        Row {
            id: horizontalContent
            visible: !button.vertical
            anchors.centerIn: parent
            spacing: Style.space(5)

            HazelMark {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(18)
                height: Style.space(16)
                tint: button.active && button.useActiveColor ? button.activeColor : button.foreground
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: button.text
                color: button.active && button.useActiveColor ? button.activeColor : button.foreground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                renderType: Text.NativeRendering
            }
        }

        Column {
            id: verticalContent
            visible: button.vertical
            anchors.centerIn: parent
            spacing: Style.space(2)

            HazelMark {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(18)
                height: Style.space(15)
                tint: button.active && button.useActiveColor ? button.activeColor : button.foreground
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: button.text
                color: button.active && button.useActiveColor ? button.activeColor : button.foreground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                renderType: Text.NativeRendering
            }
        }
    }

}
