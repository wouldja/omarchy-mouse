import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.wouldja.mouse"
  ipcTarget: "io.github.wouldja.mouse"

  property real sensitivity: 0
  property string accelProfile: "adaptive"
  property bool naturalScroll: false
  property real scrollFactor: 1
  property bool leftHanded: false
  property real touchpadScrollFactor: 0.4
  property bool disableWhileTyping: true
  property bool tapToClick: true
  property bool clickfingerBehavior: true
  property bool hasTouchpad: false
  property bool loaded: false

  property real wheelAccumulator: 0
  property bool persistQueued: false
  property bool liveQueued: false
  property string pendingMode: "apply"
  property var pendingPayload: ({})

  property string focusSection: "speed"
  property int selectedIndex: -1
  property bool cursorActive: false

  readonly property real speedPercent: Model.speedPercentFromSensitivity(root.sensitivity)
  readonly property real scrollPercent: Model.scrollPercentFromFactor(root.scrollFactor)
  readonly property real touchScrollPercent: Model.scrollPercentFromFactor(root.touchpadScrollFactor)
  readonly property var visibleSections: Model.visibleSections(root.hasTouchpad)
  readonly property string applyBin: {
    var url = String(Qt.resolvedUrl("apply.py"))
    return url.indexOf("file://") === 0 ? url.slice(7) : url
  }

  readonly property var accelOptions: [
    { value: "adaptive", label: "Adaptive" },
    { value: "flat", label: "Flat" }
  ]
  readonly property var primaryOptions: [
    { value: "left", label: "Left" },
    { value: "right", label: "Right" }
  ]

  function currentState() {
    return {
      sensitivity: root.sensitivity,
      accelProfile: root.accelProfile,
      naturalScroll: root.naturalScroll,
      scrollFactor: root.scrollFactor,
      leftHanded: root.leftHanded,
      touchpadNaturalScroll: root.naturalScroll,
      touchpadScrollFactor: root.touchpadScrollFactor,
      disableWhileTyping: root.disableWhileTyping,
      tapToClick: root.tapToClick,
      clickfingerBehavior: root.clickfingerBehavior
    }
  }

  function applyParsed(parsed) {
    root.sensitivity = parsed.sensitivity
    root.accelProfile = parsed.accelProfile === "flat" ? "flat" : (parsed.accelProfile === "custom" ? "custom" : "adaptive")
    root.naturalScroll = parsed.naturalScroll
    root.scrollFactor = parsed.scrollFactor
    root.leftHanded = parsed.leftHanded
    root.touchpadScrollFactor = parsed.touchpadScrollFactor
    root.disableWhileTyping = parsed.disableWhileTyping
    root.tapToClick = parsed.tapToClick
    root.clickfingerBehavior = parsed.clickfingerBehavior
    root.hasTouchpad = parsed.hasTouchpad
    root.loaded = true
  }

  function applyPath() {
    var path = root.applyBin
    if (path.indexOf("%") !== -1) {
      try { path = decodeURIComponent(path) } catch (e) {}
    }
    return path
  }

  function refresh() {
    if (getProc.running) return
    getProc.command = ["python3", applyPath(), "get"]
    getProc.running = true
  }

  function queueApply(mode) {
    root.pendingMode = mode
    root.pendingPayload = currentState()
    if (mode === "live") root.liveQueued = true
    else root.persistQueued = true
    if (!setProc.running) flushApply()
  }

  function flushApply() {
    var mode = root.persistQueued ? "apply" : "live"
    if (!root.persistQueued && !root.liveQueued) return
    root.persistQueued = false
    root.liveQueued = false
    setProc.command = ["python3", applyPath(), mode, Model.statePayload(root.pendingPayload)]
    setProc.running = true
  }

  function setSensitivityFromPercent(percent) {
    root.sensitivity = Model.sensitivityFromSpeedPercent(percent)
    queueApply("live")
  }

  function commitSensitivityFromPercent(percent) {
    root.sensitivity = Model.sensitivityFromSpeedPercent(percent)
    queueApply("apply")
  }

  function nudgeSpeed(steps) {
    commitSensitivityFromPercent(root.speedPercent + steps)
  }

  function setScrollFromPercent(percent) {
    root.scrollFactor = Model.factorFromScrollPercent(percent)
    queueApply("live")
  }

  function commitScrollFromPercent(percent) {
    root.scrollFactor = Model.factorFromScrollPercent(percent)
    queueApply("apply")
  }

  function setTouchScrollFromPercent(percent) {
    root.touchpadScrollFactor = Model.factorFromScrollPercent(percent)
    queueApply("live")
  }

  function commitTouchScrollFromPercent(percent) {
    root.touchpadScrollFactor = Model.factorFromScrollPercent(percent)
    queueApply("apply")
  }

  function setAccel(profile) {
    root.accelProfile = profile === "flat" ? "flat" : "adaptive"
    queueApply("apply")
  }

  function setNatural(enabled) {
    root.naturalScroll = !!enabled
    queueApply("apply")
  }

  function setLeftHanded(enabled) {
    root.leftHanded = !!enabled
    queueApply("apply")
  }

  function setTapToClick(enabled) {
    root.tapToClick = !!enabled
    queueApply("apply")
  }

  function setDisableWhileTyping(enabled) {
    root.disableWhileTyping = !!enabled
    queueApply("apply")
  }

  function setClickfinger(enabled) {
    root.clickfingerBehavior = !!enabled
    queueApply("apply")
  }

  function choiceValue(section) {
    if (section === "accel") return root.accelProfile === "flat" ? "flat" : "adaptive"
    if (section === "primary") return root.leftHanded ? "right" : "left"
    return ""
  }

  function choiceOptions(section) {
    if (section === "accel") return root.accelOptions
    if (section === "primary") return root.primaryOptions
    return []
  }

  function applyChoice(section, value) {
    if (section === "accel") setAccel(value)
    else if (section === "primary") setLeftHanded(value === "right")
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = Model.sectionFirstIndex(focusSection)
      return
    }
    if (delta > 0) {
      if (Model.sectionIsChoice(focusSection) && selectedIndex < Model.sectionChoiceCount(focusSection) - 1) {
        selectedIndex = selectedIndex + 1
        return
      }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = Model.sectionFirstIndex(focusSection)
      }
    } else {
      if (Model.sectionIsChoice(focusSection) && selectedIndex > 0) {
        selectedIndex = selectedIndex - 1
        return
      }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        selectedIndex = Model.sectionIsChoice(prev)
          ? Model.sectionChoiceCount(prev) - 1
          : Model.sectionFirstIndex(prev)
      }
    }
  }

  function moveCursorH(delta) {
    if (focusSection === "speed") {
      nudgeSpeed(delta * 5)
      return
    }
    if (focusSection === "scroll") {
      commitScrollFromPercent(root.scrollPercent + delta * 5)
      return
    }
    if (focusSection === "touchScroll") {
      commitTouchScrollFromPercent(root.touchScrollPercent + delta * 5)
      return
    }
    if (Model.sectionIsChoice(focusSection)) {
      var max = Model.sectionChoiceCount(focusSection) - 1
      var next = selectedIndex + delta
      if (next < 0) next = 0
      if (next > max) next = max
      selectedIndex = next
    }
  }

  function activateCursor() {
    if (focusSection === "natural") { setNatural(!root.naturalScroll); return }
    if (focusSection === "tap") { setTapToClick(!root.tapToClick); return }
    if (focusSection === "dwt") { setDisableWhileTyping(!root.disableWhileTyping); return }
    if (focusSection === "clickfinger") { setClickfinger(!root.clickfingerBehavior); return }
    if (Model.sectionIsChoice(focusSection)) {
      var options = choiceOptions(focusSection)
      if (selectedIndex >= 0 && selectedIndex < options.length)
        applyChoice(focusSection, options[selectedIndex].value)
    }
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = Model.sectionFirstIndex(focusSection)
      return
    }
    if (Model.sectionIsSlider(focusSection)) {
      selectedIndex = -1
      return
    }
    if (Model.sectionIsChoice(focusSection)) {
      var count = Model.sectionChoiceCount(focusSection)
      if (selectedIndex < 0) selectedIndex = 0
      if (selectedIndex > count - 1) selectedIndex = count - 1
      return
    }
    selectedIndex = 0
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function showSpeedOsd() {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: "󰍽",
      value: root.speedPercent
    }))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      focusSection = "speed"
      selectedIndex = -1
      cursorActive = false
    }
  }

  onHasTouchpadChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  Process {
    id: getProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyParsed(Model.parseState(text))
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseState(text)
        if (parsed && parsed.accelProfile)
          root.hasTouchpad = parsed.hasTouchpad
      }
    }
    onRunningChanged: {
      if (running) return
      if (root.persistQueued || root.liveQueued) root.flushApply()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍽"
    tooltipText: "Mouse"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.nudgeSpeed(wheel.steps * 5)
      root.showSpeedOsd()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(8)

          PanelHero {
            width: parent.width
            title: "Mouse"
            iconSize: Style.font.title
            detail: "1.2.0"
            meta: Model.heroMeta({
              accelProfile: root.accelProfile,
              naturalScroll: root.naturalScroll,
              leftHanded: root.leftHanded
            }, speedSection.dragging ? speedSection.liveValue : root.speedPercent)
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: heroIcon
          }

          SliderSection {
            id: speedSection
            width: parent.width
            sectionId: "speed"
            title: "POINTER SPEED"
            value: root.speedPercent
            valueText: Math.round(dragging ? liveValue : root.speedPercent) + "%"
            onMoved: function(v) { root.setSensitivityFromPercent(v) }
            onReleased: function(v) { root.commitSensitivityFromPercent(v) }
          }

          SliderSection {
            width: parent.width
            sectionId: "scroll"
            title: "SCROLL SPEED"
            value: root.scrollPercent
            valueText: Math.round(dragging ? liveValue : root.scrollPercent) + "%"
            onMoved: function(v) { root.setScrollFromPercent(v) }
            onReleased: function(v) { root.commitScrollFromPercent(v) }
          }

          Row {
            width: parent.width
            spacing: Style.space(10)

            ChoiceSection {
              width: (parent.width - parent.spacing) / 2
              sectionId: "accel"
              title: "ACCELERATION"
              options: root.accelOptions
              value: root.accelProfile === "flat" ? "flat" : "adaptive"
              onActivated: function(v) { root.setAccel(v) }
            }

            ChoiceSection {
              width: (parent.width - parent.spacing) / 2
              sectionId: "primary"
              title: "PRIMARY"
              options: root.primaryOptions
              value: root.leftHanded ? "right" : "left"
              onActivated: function(v) { root.setLeftHanded(v === "right") }
            }
          }

          Grid {
            id: switchGrid
            width: parent.width
            columns: 2
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(4)

            readonly property real cellWidth: (width - columnSpacing) / 2

            CompactToggle {
              width: switchGrid.cellWidth
              label: "Natural scroll"
              sectionId: "natural"
              checked: root.naturalScroll
              onClicked: root.setNatural(!root.naturalScroll)
            }

            CompactToggle {
              width: switchGrid.cellWidth
              visible: root.hasTouchpad
              label: "Tap to click"
              sectionId: "tap"
              checked: root.tapToClick
              onClicked: root.setTapToClick(!root.tapToClick)
            }

            CompactToggle {
              width: switchGrid.cellWidth
              visible: root.hasTouchpad
              label: "Pause while typing"
              sectionId: "dwt"
              checked: root.disableWhileTyping
              onClicked: root.setDisableWhileTyping(!root.disableWhileTyping)
            }

            CompactToggle {
              width: switchGrid.cellWidth
              visible: root.hasTouchpad
              label: "Two-finger click"
              sectionId: "clickfinger"
              checked: root.clickfingerBehavior
              onClicked: root.setClickfinger(!root.clickfingerBehavior)
            }
          }

          SliderSection {
            width: parent.width
            visible: root.hasTouchpad
            sectionId: "touchScroll"
            title: "TOUCHPAD SCROLL"
            value: root.touchScrollPercent
            valueText: Math.round(dragging ? liveValue : root.touchScrollPercent) + "%"
            onMoved: function(v) { root.setTouchScrollFromPercent(v) }
            onReleased: function(v) { root.commitTouchScrollFromPercent(v) }
          }
        }
      }
    }
  }

  Component {
    id: heroIcon
    Text {
      textFormat: Text.PlainText
      text: "󰍽"
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.title
    }
  }

  component SliderSection: Column {
    id: sliderSection
    required property string sectionId
    required property string title
    required property string valueText
    property real value: 0
    property real minimum: 0
    property real maximum: 100
    property real step: 5
    property alias dragging: slider.dragging
    property alias liveValue: slider.liveValue
    signal moved(real value)
    signal released(real value)

    spacing: Style.space(2)

    Item {
      width: parent.width
      implicitHeight: Math.max(header.implicitHeight, valueLabel.implicitHeight)

      PanelSectionHeader {
        id: header
        text: sliderSection.title
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: valueLabel
        textFormat: Text.PlainText
        text: sliderSection.valueText
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    CursorSurface {
      id: sliderRow
      width: parent.width
      height: slider.implicitHeight
      hasCursor: root.cursorActive && root.focusSection === sliderSection.sectionId && root.selectedIndex === -1
      onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sliderRow)
      foreground: root.bar.foreground
      outline: true

      PanelSlider {
        id: slider
        bar: root.bar
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        minimum: sliderSection.minimum
        maximum: sliderSection.maximum
        step: sliderSection.step
        integer: true
        value: sliderSection.value
        onMoved: function(v) { sliderSection.moved(v) }
        onReleased: function(v) { sliderSection.released(v) }
      }

      HoverHandler {
        onHoveredChanged: if (hovered) {
          root.cursorActive = true
          root.focusSection = sliderSection.sectionId
          root.selectedIndex = -1
        }
      }
    }
  }

  component ChoiceSection: Column {
    id: choiceSection
    required property string sectionId
    required property string title
    required property var options
    required property string value
    signal activated(string value)

    spacing: Style.space(4)

    PanelSectionHeader {
      text: choiceSection.title
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Grid {
      id: choiceRow
      width: parent.width
      columns: choiceSection.options.length
      spacing: Style.spacing.xs
      readonly property real cellWidth: columns > 0
        ? (width - spacing * (columns - 1)) / columns
        : 0

      Repeater {
        model: choiceSection.options

        Button {
          required property var modelData
          required property int index
          width: choiceRow.cellWidth
          text: modelData.label
          fontSize: Style.font.caption
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.sm
          verticalPadding: Style.space(4)
          bordered: true
          selected: choiceSection.value === modelData.value
          hasCursor: root.cursorActive && root.focusSection === choiceSection.sectionId && root.selectedIndex === index
          onClicked: choiceSection.activated(modelData.value)
          onHovered: function(isHovered) {
            if (!isHovered) return
            root.cursorActive = true
            root.focusSection = choiceSection.sectionId
            root.selectedIndex = index
          }
        }
      }
    }
  }

  component CompactToggle: BorderSurface {
    id: toggleRow
    required property string label
    required property string sectionId
    property bool checked: false
    signal clicked()

    implicitHeight: Style.space(32)
    radius: Style.cornerRadius
    color: "transparent"
    borderSpec: Border.controlSpec(
      (root.cursorActive && root.focusSection === sectionId) || mouse.containsMouse ? "hover-cursor" : "normal",
      root.bar.foreground, Color.accent)

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        text: toggleRow.label
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
        width: parent.width - switchControl.implicitWidth - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
      }

      ToggleSwitch {
        id: switchControl
        checked: toggleRow.checked
        interactive: false
        trackHeight: Style.space(16)
        foreground: root.bar.foreground
        accent: Color.accent
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = toggleRow.sectionId
        root.selectedIndex = 0
      }
      onClicked: toggleRow.clicked()
    }
  }
}
