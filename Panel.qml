import "Model.js" as Model
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Panel {
    id: root

    property var anchorItem: null
    property var hostWidget: null
    property string expandedProfileId: ""
    property bool collectorActive: true
    property var sourcePanel: null
    property bool remotePanelOpen: false
    property bool configuring: false
    property bool editingProfile: false
    property string editingProfileId: ""
    property int collectorRevision: 0
    property string pendingCredentialProfileId: ""
    property string pendingCredentialPassword: ""
    property bool pendingCredentialRemember: true
    property bool pendingCredentialApply: false
    property int pendingCredentialAttempts: 0
    property int viewWindowHours: normalizedHistoryWindow(setting("historyHours", 6))
    property var localInstances: []

    readonly property color foreground: bar ? bar.barForeground : Color.popups.text
    readonly property color accent: Color.accent
    readonly property color urgent: bar ? bar.urgent : Color.urgent
    readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.56)
    readonly property color warning: Qt.tint(accent, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.52))
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property string toolbarMode: String(setting("toolbarMetric", "Adaptive"))
    readonly property var instances: collectorActive || !sourcePanel ? localInstances : sourcePanel.instances
    readonly property var fleet: Model.fleetSummary(instanceStates(instances))
    readonly property var representative: representativeInstance(instances)
    readonly property var notable: notableEvent()
    readonly property bool hasExpandedProfile: expandedProfileId !== ""
    readonly property string toolbarText: Model.fleetBarLabel(instanceStates(instances), toolbarMode, bar ? bar.vertical : false)
    readonly property bool toolbarActive: fleet.total === 0 || fleet.severity !== "normal"
    readonly property color toolbarColor: fleet.severity === "critical" || fleet.total === 0 ? urgent : warning
    readonly property color toolbarBaseColor: {
        var tone = representative ? profileTone(representative.profile.tone) : accent;
        return Qt.tint(foreground, Qt.rgba(tone.r, tone.g, tone.b, 0.24));
    }
    readonly property string toolbarTooltip: Model.escapeMarkup(tooltipText())

    function copyProfile(source) {
        var profile = {};
        var value = source || {};
        for (var key in value)
            profile[key] = value[key];
        profile.enabled = value.enabled === undefined ? true : value.enabled === true;
        return profile;
    }

    function legacyProfile() {
        var value = root.settings || {};
        var engine = String(value.engine || "postgresql");
        var defaults = Model.engineDefaults(engine);
        return {
            "id": String(value.activeProfileId || "default-postgres"),
            "name": String(value.profileName || "Postgres"),
            "profileName": String(value.profileName || "Postgres"),
            "configured": value.configured === true,
            "enabled": true,
            "engine": engine,
            "host": value.host === undefined ? "127.0.0.1" : String(value.host),
            "port": Number(value.port || defaults.port),
            "database": String(value.database || defaults.database),
            "user": String(value.user || defaults.user),
            "sslMode": String(value.sslMode || "prefer"),
            "rememberPassword": value.rememberPassword === undefined ? true : value.rememberPassword === true,
            "tone": String(value.tone || "accent"),
            "sshEnabled": value.sshEnabled === true,
            "sshHost": String(value.sshHost || ""),
            "sshPort": Number(value.sshPort || 22),
            "sshUser": String(value.sshUser || ""),
            "sshIdentityFile": String(value.sshIdentityFile || ""),
            "sshLocalPort": Number(value.sshLocalPort || 55439)
        };
    }

    function profileList() {
        var value = root.settings || {};
        var stored = value.profiles;
        if (stored && Number(stored.length) > 0) {
            var profiles = [];
            for (var i = 0; i < stored.length; i++)
                profiles.push(copyProfile(stored[i]));
            return profiles;
        }
        return value.configured === true ? [legacyProfile()] : [];
    }

    function profileById(profileId, profiles) {
        var source = profiles || profileList();
        var wanted = String(profileId || "");
        for (var i = 0; i < source.length; i++) {
            if (String(source[i].id || "") === wanted)
                return source[i];
        }
        return null;
    }

    function toggleProfileExpansion(profileId) {
        var wanted = String(profileId || "");
        expandedProfileId = expandedProfileId === wanted ? "" : wanted;
    }

    function referenceProfile(profiles, preferredId) {
        var source = profiles || profileList();
        var preferred = profileById(preferredId || (root.settings || {}).activeProfileId, source);
        return preferred || (source.length > 0 ? source[0] : legacyProfile());
    }

    function profileTone(tone) {
        if (tone === "warm")
            return Qt.tint(accent, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.32));
        if (tone === "soft")
            return Qt.tint(accent, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.28));
        if (tone === "neutral")
            return foreground;
        return accent;
    }

    function normalizedHistoryWindow(value) {
        var wanted = Number(value);
        var choices = [1, 3, 6, 24];
        var closest = 6;
        var distance = Number.POSITIVE_INFINITY;
        for (var i = 0; i < choices.length; i++) {
            var nextDistance = Math.abs(choices[i] - wanted);
            if (nextDistance < distance) {
                distance = nextDistance;
                closest = choices[i];
            }
        }
        return closest;
    }

    function flatProfileSettings(profile, profiles) {
        return {
            "profiles": profiles,
            "activeProfileId": profile.id,
            "configured": profiles.length > 0,
            "engine": profile.engine || "postgresql",
            "profileName": profile.name,
            "host": profile.host,
            "port": profile.port,
            "database": profile.database,
            "user": profile.user,
            "sslMode": profile.sslMode,
            "rememberPassword": profile.rememberPassword === undefined ? true : profile.rememberPassword === true,
            "tone": profile.tone,
            "sshEnabled": profile.sshEnabled === true,
            "sshHost": profile.sshHost || "",
            "sshPort": profile.sshPort || 22,
            "sshUser": profile.sshUser || "",
            "sshIdentityFile": profile.sshIdentityFile || "",
            "sshLocalPort": profile.sshLocalPort || 55439
        };
    }

    function collectorSettings(profile) {
        var result = copyProfile(profile);
        result.activeProfileId = profile.id;
        result.profileName = profile.name || profile.profileName || "Postgres";
        result.configured = true;
        result.closedRefreshSec = Number(setting("closedRefreshSec", 5));
        result.openRefreshSec = Number(setting("openRefreshSec", 2));
        result.historyHours = 24;
        return result;
    }

    function persistSettings(values) {
        var entry = { "id": root.moduleName };
        var current = root.settings || {};
        for (var existing in current) {
            if (existing !== "id")
                entry[existing] = current[existing];
        }
        for (var key in values)
            entry[key] = values[key];
        root.settings = entry;
        if (root.hostWidget && "settings" in root.hostWidget)
            root.hostWidget.settings = entry;
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry);
        return entry;
    }

    function collectorModelIndex(profileId) {
        var wanted = String(profileId || "");
        for (var i = 0; i < collectorProfiles.count; i++) {
            if (String(collectorProfiles.get(i).entryId || "") === wanted)
                return i;
        }
        return -1;
    }

    function syncCollectors() {
        var profiles = profileList();
        if (expandedProfileId !== "" && !profileById(expandedProfileId, profiles))
            expandedProfileId = "";
        for (var i = collectorProfiles.count - 1; i >= 0; i--) {
            if (!profileById(collectorProfiles.get(i).entryId, profiles))
                collectorProfiles.remove(i);
        }
        for (var p = 0; p < profiles.length; p++) {
            var profile = profiles[p];
            var index = collectorModelIndex(profile.id);
            if (index < 0)
                collectorProfiles.append({ "entryId": String(profile.id), "profileData": profile });
            else
                collectorProfiles.setProperty(index, "profileData", profile);
        }
        instancePublishTimer.restart();
    }

    function controllerForProfile(profileId) {
        var wanted = String(profileId || "");
        for (var i = 0; i < collectorRepeater.count; i++) {
            var controller = collectorRepeater.itemAt(i);
            if (controller && String(controller.profileId || "") === wanted)
                return controller;
        }
        return null;
    }

    function collectorOwner() {
        return collectorActive || !sourcePanel ? root : sourcePanel;
    }

    function buildLocalInstances() {
        var rows = [];
        for (var i = 0; i < collectorRepeater.count; i++) {
            var controller = collectorRepeater.itemAt(i);
            if (!controller || !controller.profileData || controller.profileData.enabled === false)
                continue;
            rows.push({
                "profile": controller.profileData,
                "state": controller.state,
                "errorText": controller.errorText,
                "historyHours": controller.historyHours,
                "passwordRemembered": controller.passwordRemembered,
                "keyringBusy": controller.keyringBusy
            });
        }
        return rows;
    }

    function publishInstances() {
        localInstances = buildLocalInstances();
        collectorRevision++;
    }

    function syncInstanceRows() {
        var source = instances || [];
        var structuralChange = instanceRows.count !== source.length;
        if (!structuralChange) {
            for (var i = 0; i < source.length; i++) {
                var sourceId = String(source[i].profile.id || "");
                if (String(instanceRows.get(i).entryId || "") !== sourceId) {
                    structuralChange = true;
                    break;
                }
            }
        }

        if (structuralChange) {
            instanceRows.clear();
            for (var added = 0; added < source.length; added++) {
                var row = source[added];
                instanceRows.append({
                    "entryId": String(row.profile.id || ""),
                    "profileData": row.profile,
                    "stateData": row.state,
                    "errorData": String(row.errorText || ""),
                    "historyHoursData": Number(row.historyHours || 6)
                });
            }
            return;
        }

        for (var updated = 0; updated < source.length; updated++) {
            var next = source[updated];
            instanceRows.setProperty(updated, "profileData", next.profile);
            instanceRows.setProperty(updated, "stateData", next.state);
            instanceRows.setProperty(updated, "errorData", String(next.errorText || ""));
            instanceRows.setProperty(updated, "historyHoursData", Number(next.historyHours || 6));
        }
    }

    function focusRowIndex(profileId) {
        var wanted = String(profileId || "");
        var rank = 0;
        for (var i = 0; i < instanceRows.count; i++) {
            var id = String(instanceRows.get(i).entryId || "");
            if (id === expandedProfileId)
                continue;
            if (id === wanted)
                return rank;
            rank++;
        }
        return rank;
    }

    function instanceStates(rows) {
        var result = [];
        var source = rows || [];
        for (var i = 0; i < source.length; i++)
            result.push(source[i].state);
        return result;
    }

    function representativeInstance(rows) {
        var source = rows || [];
        var best = null;
        var bestScore = -1;
        for (var i = 0; i < source.length; i++) {
            var row = source[i];
            var state = row.state || Model.emptyState();
            var score = !state.connected ? 1000000 : (state.severity === "critical" ? 750000 : (state.severity === "warning" ? 500000 : 0));
            score += Number(state.connections.blocked || 0) * 10000;
            score += Number(state.connections.waiting || 0) * 1000;
            score += Number(state.connections.active || 0);
            if (score > bestScore) {
                best = row;
                bestScore = score;
            }
        }
        return best;
    }

    function editConnection() {
        showProfiles();
    }

    function editProfile(profile) {
        configuring = true;
        editingProfile = true;
        editingProfileId = String(profile.id || "");
        var owner = collectorOwner();
        var controller = owner.controllerForProfile(editingProfileId);
        connectionSetup.load(profile, controller ? controller.passwordRemembered : false);
    }

    function internalTunnelPort(profileId) {
        var text = String(profileId || "hazel");
        var hash = 0;
        for (var i = 0; i < text.length; i++)
            hash = ((hash * 31) + text.charCodeAt(i)) >>> 0;
        return 56000 + (hash % 5000);
    }

    function addProfile() {
        configuring = true;
        editingProfile = true;
        editingProfileId = "";
        connectionSetup.load({
            "engine": "postgresql",
            "name": "Postgres",
            "enabled": true,
            "host": "127.0.0.1",
            "port": 5432,
            "database": "postgres",
            "user": "postgres",
            "sslMode": "prefer",
            "rememberPassword": true,
            "tone": "accent",
            "sshPort": 22
        }, false);
    }

    function showProfiles() {
        configuring = true;
        editingProfile = false;
        editingProfileId = "";
    }

    function setProfileEnabled(profile, enabled) {
        var profiles = profileList();
        for (var i = 0; i < profiles.length; i++) {
            if (String(profiles[i].id || "") === String(profile.id || "")) {
                profiles[i].enabled = enabled === true;
                break;
            }
        }
        var reference = referenceProfile(profiles);
        persistSettings(flatProfileSettings(reference, profiles));
        if (enabled !== true && String(profile.id || "") === expandedProfileId)
            expandedProfileId = "";
    }

    function queueCredential(profileId, password, remember, shouldApply) {
        pendingCredentialProfileId = String(profileId || "");
        pendingCredentialPassword = String(password || "");
        pendingCredentialRemember = remember === true;
        pendingCredentialApply = shouldApply === true;
        pendingCredentialAttempts = 0;
        credentialApplyTimer.restart();
    }

    function saveConnection(values, password, remember) {
        var profile = copyProfile(values);
        if (!profile.id)
            profile.id = "profile-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1679616).toString(36);
        profile.name = String(profile.name || profile.profileName || "Postgres");
        profile.profileName = profile.name;
        profile.rememberPassword = remember === true;
        var profiles = profileList();
        var previous = profileById(profile.id, profiles);
        var owner = collectorOwner();
        var oldController = previous ? owner.controllerForProfile(profile.id) : null;
        var preservedPassword = String(password || "") === "" && oldController ? oldController.sessionPassword : "";
        var replaced = false;
        for (var i = 0; i < profiles.length; i++) {
            if (String(profiles[i].id || "") === String(profile.id)) {
                profile.enabled = previous.enabled === undefined ? true : previous.enabled === true;
                profile.sshLocalPort = Number(previous.sshLocalPort || internalTunnelPort(profile.id));
                profiles[i] = profile;
                replaced = true;
                break;
            }
        }
        if (!replaced) {
            profile.enabled = true;
            profile.sshLocalPort = internalTunnelPort(profile.id);
            profiles.push(profile);
        }
        persistSettings(flatProfileSettings(profile, profiles));
        configuring = false;
        editingProfile = false;
        editingProfileId = "";
        var enteredPassword = String(password || "");
        var effectivePassword = enteredPassword !== "" ? enteredPassword : preservedPassword;
        owner.queueCredential(profile.id, effectivePassword, remember, enteredPassword !== "" || preservedPassword !== "" || !remember);
    }

    function refresh() {
        if (!collectorActive && sourcePanel) {
            sourcePanel.refresh();
            return;
        }
        for (var i = 0; i < collectorRepeater.count; i++) {
            var controller = collectorRepeater.itemAt(i);
            if (controller && controller.active)
                controller.refresh();
        }
    }

    function editingCredentialStatus(revision) {
        var touched = revision;
        var owner = collectorOwner();
        var controller = owner.controllerForProfile(editingProfileId);
        return {
            "remembered": controller ? controller.passwordRemembered : false,
            "busy": controller ? controller.keyringBusy : false
        };
    }

    function tooltipText() {
        if (instances.length === 0)
            return "Hazel · monitoring paused\nOpen Config to enable a database";
        var lines = ["Hazel · " + fleet.connected + "/" + fleet.total + " online · " + fleet.active + " active"];
        for (var i = 0; i < instances.length; i++) {
            var row = instances[i];
            var state = row.state;
            var name = String(row.profile.name || row.profile.profileName || "Postgres");
            lines.push(name + " · " + (state.connected ? state.statusLabel + " · " + state.connections.active + " active" : (row.errorText || "connecting")));
        }
        return lines.join("\n");
    }

    function notableEvent() {
        var states = instanceStates(instances);
        var blocked = 0;
        var lockWaiting = 0;
        var unavailable = 0;
        var oldestLockSeconds = 0;
        var failedMutations = 0;
        var pendingMutations = 0;
        var memoryPercent = 0;
        for (var i = 0; i < states.length; i++) {
            var state = states[i] || {};
            var connections = state.connections || {};
            if (state.connected !== true)
                unavailable++;
            blocked += Number(connections.blocked || 0);
            lockWaiting += Number(connections.lockWaiting || 0);
            oldestLockSeconds = Math.max(oldestLockSeconds, Number(connections.oldestLockWaitSeconds || 0));
            failedMutations += Number((state.maintenance || {}).failedMutations || 0);
            pendingMutations += Number((state.maintenance || {}).pendingMutations || 0);
            memoryPercent = Math.max(memoryPercent, Number(state.capacityPercent || 0));
        }
        var age = oldestLockSeconds > 0 ? " · " + Model.formatDuration(oldestLockSeconds) : "";
        if (blocked > 0)
            return { "label": blocked + " BLOCKED" + age, "tone": urgent };
        if (failedMutations > 0)
            return { "label": failedMutations + (failedMutations === 1 ? " MUTATION FAILED" : " MUTATIONS FAILED"), "tone": urgent };
        if (memoryPercent >= 95)
            return { "label": "MEMORY " + Math.round(memoryPercent) + "%", "tone": urgent };
        if (unavailable > 0)
            return { "label": unavailable + (unavailable === 1 ? " PROFILE DOWN" : " PROFILES DOWN"), "tone": urgent };
        if (lockWaiting > 0)
            return { "label": lockWaiting + (lockWaiting === 1 ? " LOCK WAIT" : " LOCK WAITS") + age, "tone": warning };
        if (pendingMutations > 0)
            return { "label": pendingMutations + (pendingMutations === 1 ? " MUTATION PENDING" : " MUTATIONS PENDING"), "tone": warning };
        return { "label": "", "tone": accent };
    }

    function statusColor() {
        if (fleet.total === 0 || fleet.severity === "critical")
            return urgent;
        if (fleet.severity === "warning")
            return warning;
        return representative ? profileTone(representative.profile.tone) : accent;
    }

    function switchPanel(direction) {
        if (bar && typeof bar.switchPanelFrom === "function")
            return bar.switchPanelFrom(hostWidget || root, direction);
        return false;
    }

    moduleName: "ryrobes.hazel"
    manageIpc: false

    onSettingsChanged: collectorSyncTimer.restart()
    onInstancesChanged: instanceRowSyncTimer.restart()
    onOpenedChanged: {
        if (!collectorActive && sourcePanel)
            sourcePanel.remotePanelOpen = opened;
        if (opened) {
            if (profileList().length === 0)
                addProfile();
            else
                refresh();
            Qt.callLater(function() {
                if (!root.configuring)
                    keyCatcher.forceActiveFocus();
            });
        } else if (profileList().length > 0) {
            configuring = false;
            editingProfile = false;
            editingProfileId = "";
        }
    }
    onSourcePanelChanged: {
        if (!collectorActive && sourcePanel && opened)
            sourcePanel.remotePanelOpen = true;
    }
    Component.onCompleted: {
        syncCollectors();
        instanceRowSyncTimer.restart();
    }

    ListModel {
        id: collectorProfiles
        dynamicRoles: true
    }

    ListModel {
        id: instanceRows
        dynamicRoles: true
    }

    Timer {
        id: collectorSyncTimer
        interval: 0
        repeat: false
        onTriggered: root.syncCollectors()
    }

    Timer {
        id: instancePublishTimer
        interval: 0
        repeat: false
        onTriggered: root.publishInstances()
    }

    Timer {
        id: instanceRowSyncTimer
        interval: 0
        repeat: false
        onTriggered: root.syncInstanceRows()
    }

    Timer {
        id: credentialApplyTimer
        interval: 80
        repeat: false
        onTriggered: {
            var controller = root.controllerForProfile(root.pendingCredentialProfileId);
            if (!controller && root.pendingCredentialAttempts < 12) {
                root.pendingCredentialAttempts++;
                restart();
                return;
            }
            if (controller && root.pendingCredentialApply)
                controller.applyCredential(root.pendingCredentialPassword, root.pendingCredentialRemember, false);
            root.pendingCredentialProfileId = "";
            root.pendingCredentialPassword = "";
            root.pendingCredentialApply = false;
        }
    }

    Repeater {
        id: collectorRepeater
        model: collectorProfiles

        delegate: HazelController {
            required property var profileData
            settings: root.collectorSettings(profileData)
            active: root.collectorActive && profileData.enabled !== false
            panelOpen: root.opened || root.remotePanelOpen
            onStateChanged: instancePublishTimer.restart()
            onErrorTextChanged: instancePublishTimer.restart()
            onPasswordRememberedChanged: instancePublishTimer.restart()
            onKeyringBusyChanged: instancePublishTimer.restart()
            onActiveChanged: instancePublishTimer.restart()
        }
    }

    KeyboardPanel {
        id: panel

        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: root.configuring && root.editingProfile ? connectionSetup.focusTarget : keyCatcher
        centerOnBar: false
        contentWidth: panel.fittedContentWidth(root.configuring
            ? (root.editingProfile ? Style.space(560) : Style.space(720))
            : (root.hasExpandedProfile ? Style.space(940) : Style.space(900)))
        contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(760))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction); }
            onTextKey: function(text) {
                if (text === "r" || text === "R")
                    root.refresh();
                else if (text === "c" || text === "C")
                    root.showProfiles();
            }

            ScrollView {
                id: scrollArea
                anchors.fill: parent
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: contentColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                ColumnLayout {
                    id: contentColumn
                    width: scrollArea.availableWidth
                    spacing: Style.space(12)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(10)

                        HazelMark {
                            Layout.preferredWidth: headerTitles.implicitHeight
                            Layout.preferredHeight: headerTitles.implicitHeight
                            Layout.maximumWidth: headerTitles.implicitHeight
                            Layout.maximumHeight: headerTitles.implicitHeight
                            Layout.alignment: Qt.AlignVCenter
                            tint: root.statusColor()
                        }

                        ColumnLayout {
                            id: headerTitles
                            Layout.fillWidth: true
                            spacing: 1

                            HazelWordmark {
                                readonly property real titleHeight: Style.font.title + Style.space(4)

                                Layout.preferredWidth: titleHeight * designWidth / designHeight
                                Layout.preferredHeight: titleHeight
                                Layout.maximumWidth: Layout.preferredWidth
                                Layout.maximumHeight: titleHeight
                                tint: root.foreground
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.fleet.total + " MONITORED · " + root.fleet.connected + " ONLINE · " + root.fleet.active + " ACTIVE"
                                color: root.muted
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                font.letterSpacing: 1
                                elide: Text.ElideRight
                            }
                        }

                        RowLayout {
                            visible: root.notable.label !== ""
                            Layout.maximumWidth: Style.space(190)
                            spacing: Style.space(6)

                            Rectangle {
                                Layout.preferredWidth: Style.space(3)
                                Layout.preferredHeight: Style.space(15)
                                radius: width / 2
                                color: root.notable.tone
                                opacity: 0.82
                            }

                            Text {
                                Layout.minimumWidth: 0
                                Layout.fillWidth: true
                                text: root.notable.label
                                color: root.notable.tone
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                font.letterSpacing: 0.8
                                elide: Text.ElideRight
                            }
                        }

                        Button {
                            text: "Config"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            tooltipText: "Profiles and monitoring set (C)"
                            onClicked: root.showProfiles()
                        }

                        Button {
                            visible: !root.configuring
                            text: "↻"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fontSize: Style.font.body
                            tooltipText: "Refresh every enabled profile now (R)"
                            onClicked: root.refresh()
                        }
                    }

                    PanelSeparator {
                        Layout.fillWidth: true
                        foreground: root.foreground
                    }

                    ProfileWorkspace {
                        visible: root.configuring && !root.editingProfile
                        Layout.fillWidth: true
                        profiles: root.profileList()
                        foreground: root.foreground
                        accent: root.accent
                        urgent: root.urgent
                        muted: root.muted
                        fontFamily: root.fontFamily
                        onProfileEnabledChanged: function(profile, enabled) { root.setProfileEnabled(profile, enabled); }
                        onProfileEdited: function(profile) { root.editProfile(profile); }
                        onProfileAdded: root.addProfile()
                        onCloseRequested: {
                            root.configuring = false;
                            root.editingProfile = false;
                            root.editingProfileId = "";
                            Qt.callLater(function() { keyCatcher.forceActiveFocus(); });
                        }
                    }

                    ConnectionSetup {
                        id: connectionSetup
                        visible: root.configuring && root.editingProfile
                        Layout.fillWidth: true
                        foreground: root.foreground
                        accent: root.accent
                        urgent: root.urgent
                        muted: root.muted
                        fontFamily: root.fontFamily
                        busy: root.editingCredentialStatus(root.collectorRevision).busy
                        hasSavedPassword: root.editingCredentialStatus(root.collectorRevision).remembered
                        canCancel: root.profileList().length > 0
                        onConnectRequested: function(values, password, remember) { root.saveConnection(values, password, remember); }
                        onCancelRequested: {
                            if (root.profileList().length > 0) {
                                root.editingProfile = false;
                                root.editingProfileId = "";
                            } else {
                                root.configuring = false;
                                root.editingProfile = false;
                            }
                            Qt.callLater(function() { keyCatcher.forceActiveFocus(); });
                        }
                    }

                    ColumnLayout {
                        visible: !root.configuring && root.instances.length === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.space(180)
                        spacing: Style.space(8)

                        Item { Layout.fillHeight: true }
                        Text {
                            Layout.fillWidth: true
                            text: "No profiles are being monitored"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.subtitle
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Open Config and enable every database Hazel should keep in view."
                            color: root.muted
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Open Config"
                            bordered: true
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fontSize: Style.font.caption
                            onClicked: root.showProfiles()
                        }
                        Item { Layout.fillHeight: true }
                    }

                    GridLayout {
                        visible: !root.configuring && instanceRows.count > 0
                        Layout.fillWidth: true
                        columns: instanceRows.count > 1 ? 2 : 1
                        columnSpacing: Style.space(9)
                        rowSpacing: Style.space(9)

                        Repeater {
                            model: instanceRows

                            delegate: InstanceBlock {
                                required property int index
                                required property string entryId
                                required property var profileData
                                required property var stateData
                                required property string errorData
                                required property real historyHoursData

                                readonly property int focusIndex: root.focusRowIndex(entryId)

                                Layout.fillWidth: true
                                Layout.columnSpan: instanceRows.count > 1 && expanded ? 2 : 1
                                Layout.row: expanded ? 0 : (root.hasExpandedProfile ? 1 + Math.floor(focusIndex / 2) : Math.floor(index / 2))
                                Layout.column: expanded ? 0 : (root.hasExpandedProfile ? focusIndex % 2 : index % 2)
                                profile: profileData
                                snapshot: stateData
                                errorText: errorData
                                historyHours: root.viewWindowHours
                                expanded: entryId === root.expandedProfileId
                                minimized: root.hasExpandedProfile && !expanded
                                foreground: root.foreground
                                accent: root.profileTone(profileData.tone)
                                urgent: root.urgent
                                warning: root.warning
                                muted: root.muted
                                fontFamily: root.fontFamily
                                onExpansionRequested: root.toggleProfileExpansion(entryId)
                                onHistoryWindowRequested: function(hours) { root.viewWindowHours = root.normalizedHistoryWindow(hours); }
                            }
                        }
                    }
                }
            }
        }
    }
}
