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
  property real touchpadSensitivity: 0
  property string touchpadAccelProfile: "adaptive"
  property bool touchpadNaturalScroll: false
  property real touchpadScrollFactor: 0.4
  property bool touchpadLeftHanded: false
  property bool disableWhileTyping: true
  property bool tapToClick: true
  property bool clickfingerBehavior: true
  property bool hasMouse: true
  property bool hasTouchpad: false
  property bool loaded: false

  // Detection is a heuristic, so a group it hides can be brought back by hand
  // until the shell restarts.
  property bool mouseRevealed: false
  property bool touchpadRevealed: false

  property real wheelAccumulator: 0
  property bool persistQueued: false
  property bool liveQueued: false
  property string pendingMode: "apply"
  property var pendingPayload: ({})

  property string focusSection: "speed"
  property int selectedIndex: -1
  property bool cursorActive: false

  readonly property string mouseGlyph: "󰍽"
  readonly property string touchpadGlyph: "󰌢"
  readonly property bool showMouse: root.hasMouse || root.mouseRevealed
  readonly property bool showTouchpad: root.hasTouchpad || root.touchpadRevealed
  readonly property string barGlyph: !root.hasMouse && root.hasTouchpad ? root.touchpadGlyph : root.mouseGlyph

  readonly property real speedPercent: Model.speedPercentFromSensitivity(root.sensitivity)
  readonly property real scrollPercent: Model.scrollPercentFromFactor(root.scrollFactor)
  readonly property real touchSpeedPercent: Model.speedPercentFromSensitivity(root.touchpadSensitivity)
  readonly property real touchScrollPercent: Model.scrollPercentFromFactor(root.touchpadScrollFactor)
  readonly property var visibleSections: Model.visibleSections(root.showMouse, root.showTouchpad)
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
      touchpadSensitivity: root.touchpadSensitivity,
      touchpadAccelProfile: root.touchpadAccelProfile,
      touchpadNaturalScroll: root.touchpadNaturalScroll,
      touchpadScrollFactor: root.touchpadScrollFactor,
      touchpadLeftHanded: root.touchpadLeftHanded,
      disableWhileTyping: root.disableWhileTyping,
      tapToClick: root.tapToClick,
      clickfingerBehavior: root.clickfingerBehavior
    }
  }

  function applyParsed(parsed) {
    root.sensitivity = parsed.sensitivity
    root.accelProfile = parsed.accelProfile
    root.naturalScroll = parsed.naturalScroll
    root.scrollFactor = parsed.scrollFactor
    root.leftHanded = parsed.leftHanded
    root.touchpadSensitivity = parsed.touchpadSensitivity
    root.touchpadAccelProfile = parsed.touchpadAccelProfile
    root.touchpadNaturalScroll = parsed.touchpadNaturalScroll
    root.touchpadScrollFactor = parsed.touchpadScrollFactor
    root.touchpadLeftHanded = parsed.touchpadLeftHanded
    root.disableWhileTyping = parsed.disableWhileTyping
    root.tapToClick = parsed.tapToClick
    root.clickfingerBehavior = parsed.clickfingerBehavior
    root.hasMouse = parsed.hasMouse
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

  function refreshDevices() {
    if (devicesProc.running) return
    devicesProc.command = ["python3", applyPath(), "devices"]
    devicesProc.running = true
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

  function setSliderPercent(section, percent, mode) {
    if (section === "speed") root.sensitivity = Model.sensitivityFromSpeedPercent(percent)
    else if (section === "scroll") root.scrollFactor = Model.factorFromScrollPercent(percent)
    else if (section === "touchSpeed") root.touchpadSensitivity = Model.sensitivityFromSpeedPercent(percent)
    else if (section === "touchScroll") root.touchpadScrollFactor = Model.factorFromScrollPercent(percent)
    else return
    queueApply(mode)
  }

  function sliderPercent(section) {
    if (section === "speed") return root.speedPercent
    if (section === "scroll") return root.scrollPercent
    if (section === "touchSpeed") return root.touchSpeedPercent
    if (section === "touchScroll") return root.touchScrollPercent
    return 0
  }

  function setChoice(section, value) {
    if (section === "accel") root.accelProfile = value
    else if (section === "primary") root.leftHanded = value === "right"
    else if (section === "touchAccel") root.touchpadAccelProfile = value
    else if (section === "touchPrimary") root.touchpadLeftHanded = value === "right"
    else return
    queueApply("apply")
  }

  function choiceValue(section) {
    if (section === "accel") return root.accelProfile === "flat" ? "flat" : "adaptive"
    if (section === "primary") return root.leftHanded ? "right" : "left"
    if (section === "touchAccel") return root.touchpadAccelProfile === "flat" ? "flat" : "adaptive"
    if (section === "touchPrimary") return root.touchpadLeftHanded ? "right" : "left"
    return ""
  }

  function choiceOptions(section) {
    return section === "accel" || section === "touchAccel" ? root.accelOptions : root.primaryOptions
  }

  function toggleChecked(section) {
    if (section === "natural") return root.naturalScroll
    if (section === "touchNatural") return root.touchpadNaturalScroll
    if (section === "tap") return root.tapToClick
    if (section === "dwt") return root.disableWhileTyping
    if (section === "clickfinger") return root.clickfingerBehavior
    return false
  }

  function flipToggle(section) {
    if (section === "natural") root.naturalScroll = !root.naturalScroll
    else if (section === "touchNatural") root.touchpadNaturalScroll = !root.touchpadNaturalScroll
    else if (section === "tap") root.tapToClick = !root.tapToClick
    else if (section === "dwt") root.disableWhileTyping = !root.disableWhileTyping
    else if (section === "clickfinger") root.clickfingerBehavior = !root.clickfingerBehavior
    else return
    queueApply("apply")
  }

  // A choice row lands on its current value, so the cursor never suggests a
  // setting that isn't active.
  function landingIndex(section) {
    if (!Model.sectionIsChoice(section)) return Model.sectionFirstIndex(section)
    var options = choiceOptions(section)
    for (var i = 0; i < options.length; i++)
      if (options[i].value === choiceValue(section)) return i
    return 0
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = landingIndex(focusSection)
      return
    }
    if (delta > 0) {
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = landingIndex(focusSection)
      }
    } else if (sIdx > 0) {
      focusSection = sections[sIdx - 1]
      selectedIndex = landingIndex(focusSection)
    }
  }

  function moveCursorH(delta) {
    if (Model.sectionIsSlider(focusSection)) {
      setSliderPercent(focusSection, sliderPercent(focusSection) + delta * 5, "apply")
      return
    }
    if (Model.sectionIsChoice(focusSection)) {
      var max = Model.sectionChoiceCount(focusSection) - 1
      var next = Math.max(0, Math.min(max, selectedIndex + delta))
      selectedIndex = next
      setChoice(focusSection, choiceOptions(focusSection)[next].value)
    }
  }

  function activateCursor() {
    if (focusSection === "revealMouse") { root.mouseRevealed = true; return }
    if (focusSection === "revealTouchpad") { root.touchpadRevealed = true; return }
    if (Model.sectionIsChoice(focusSection)) {
      var options = choiceOptions(focusSection)
      if (selectedIndex >= 0 && selectedIndex < options.length)
        setChoice(focusSection, options[selectedIndex].value)
      return
    }
    flipToggle(focusSection)
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = landingIndex(focusSection)
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

  // The icon adjusts whichever device the panel treats as primary.
  function nudgeBarSpeed(steps) {
    var section = root.hasMouse || !root.hasTouchpad ? "speed" : "touchSpeed"
    setSliderPercent(section, sliderPercent(section) + steps * 5, "apply")
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: root.barGlyph,
      value: sliderPercent(section)
    }))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      focusSection = root.visibleSections[0]
      selectedIndex = landingIndex(focusSection)
      cursorActive = false
    }
  }

  onVisibleSectionsChanged: clampCursor()

  Process {
    id: getProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyParsed(Model.parseState(text))
    }
  }

  Process {
    id: devicesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var devices = Model.parseDevices(text)
        if (!devices) return
        root.hasMouse = devices.hasMouse
        root.hasTouchpad = devices.hasTouchpad
      }
    }
  }

  // Hyprland reports no event for devices coming and going, so an open panel
  // asks. It stays quiet while closed and reads the state again on open.
  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: root.refreshDevices()
  }

  Process {
    id: setProc
    onRunningChanged: {
      if (running) return
      if (root.persistQueued || root.liveQueued) root.flushApply()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    tooltipText: Model.heroTitle(root.hasMouse, root.hasTouchpad)
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.nudgeBarSpeed(wheel.steps)
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
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: Model.heroTitle(root.hasMouse, root.hasTouchpad)
            iconSize: Style.font.title
            detail: "1.4.0"
            meta: Model.heroMeta(root.hasMouse, root.hasTouchpad, root.speedPercent, root.touchSpeedPercent)
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: heroIcon
          }

          Text {
            width: parent.width
            visible: !root.showMouse && !root.showTouchpad
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Connect a mouse or touchpad and its settings will appear here."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          DeviceGroup {
            width: parent.width
            visible: root.showMouse
            title: "MOUSE"
            glyph: root.mouseGlyph

            SliderRow { width: parent.width; sectionId: "speed"; label: "Speed" }
            SliderRow { width: parent.width; sectionId: "scroll"; label: "Scroll" }
            ChoiceRow { width: parent.width; sectionId: "accel"; label: "Acceleration" }
            ChoiceRow { width: parent.width; sectionId: "primary"; label: "Primary" }

            CompactToggle { width: parent.width; sectionId: "natural"; label: "Natural scroll" }
          }

          DeviceGroup {
            width: parent.width
            visible: root.showTouchpad
            title: "TOUCHPAD"
            glyph: root.touchpadGlyph

            SliderRow { width: parent.width; sectionId: "touchSpeed"; label: "Speed" }
            SliderRow { width: parent.width; sectionId: "touchScroll"; label: "Scroll" }
            ChoiceRow { width: parent.width; sectionId: "touchAccel"; label: "Acceleration" }
            ChoiceRow { width: parent.width; sectionId: "touchPrimary"; label: "Primary" }

            Grid {
              id: touchpadToggles
              width: parent.width
              columns: 2
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(4)
              readonly property real cellWidth: (width - columnSpacing) / 2

              CompactToggle { width: touchpadToggles.cellWidth; sectionId: "touchNatural"; label: "Natural scroll" }
              CompactToggle { width: touchpadToggles.cellWidth; sectionId: "tap"; label: "Tap to click" }
              CompactToggle { width: touchpadToggles.cellWidth; sectionId: "dwt"; label: "Pause while typing" }
              CompactToggle { width: touchpadToggles.cellWidth; sectionId: "clickfinger"; label: "Two-finger click" }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.showMouse || !root.showTouchpad

            RevealButton {
              visible: !root.showMouse
              sectionId: "revealMouse"
              text: "Show mouse settings"
              onClicked: root.mouseRevealed = true
            }

            RevealButton {
              visible: !root.showTouchpad
              sectionId: "revealTouchpad"
              text: "Show touchpad settings"
              onClicked: root.touchpadRevealed = true
            }
          }
        }
      }
    }
  }

  Component {
    id: heroIcon
    Text {
      textFormat: Text.PlainText
      text: root.barGlyph
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.title
    }
  }

  component DeviceGroup: Column {
    id: group
    required property string title
    required property string glyph
    default property alias rows: groupRows.data

    spacing: Style.space(6)

    PanelSeparator {
      foreground: root.bar.foreground
    }

    PanelSectionHeader {
      text: group.glyph + "  " + group.title
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Column {
      id: groupRows
      width: parent.width
      spacing: Style.space(4)
    }
  }

  component RowLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    width: Style.space(96)
    elide: Text.ElideRight
    anchors.verticalCenter: parent.verticalCenter
  }

  component SliderRow: CursorSurface {
    id: sliderRow
    required property string sectionId
    required property string label
    readonly property real percent: root.sliderPercent(sectionId)

    height: slider.implicitHeight
    hasCursor: root.cursorActive && root.focusSection === sectionId && root.selectedIndex === -1
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sliderRow)
    foreground: root.bar.foreground
    outline: true

    RowLabel {
      id: sliderLabel
      text: sliderRow.label
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
    }

    PanelSlider {
      id: slider
      bar: root.bar
      anchors.left: sliderLabel.right
      anchors.right: sliderValue.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      minimum: 0
      maximum: 100
      step: 5
      integer: true
      value: sliderRow.percent
      onMoved: function(v) { root.setSliderPercent(sliderRow.sectionId, v, "live") }
      onReleased: function(v) { root.setSliderPercent(sliderRow.sectionId, v, "apply") }
    }

    Text {
      id: sliderValue
      textFormat: Text.PlainText
      text: Math.round(slider.dragging ? slider.liveValue : sliderRow.percent) + "%"
      horizontalAlignment: Text.AlignRight
      width: Style.space(36)
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
    }

    HoverHandler {
      onHoveredChanged: if (hovered) {
        root.cursorActive = true
        root.focusSection = sliderRow.sectionId
        root.selectedIndex = -1
      }
    }
  }

  component ChoiceRow: Item {
    id: choiceRow
    required property string sectionId
    required property string label
    readonly property var options: root.choiceOptions(sectionId)

    implicitHeight: Style.space(30)

    RowLabel {
      id: choiceLabel
      text: choiceRow.label
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
    }

    Row {
      id: choiceButtons
      anchors.left: choiceLabel.right
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs
      readonly property real cellWidth: (width - spacing * (choiceRow.options.length - 1)) / choiceRow.options.length

      Repeater {
        model: choiceRow.options

        Button {
          required property var modelData
          required property int index
          width: choiceButtons.cellWidth
          text: modelData.label
          fontSize: Style.font.caption
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.sm
          verticalPadding: Style.space(3)
          bordered: true
          selected: root.choiceValue(choiceRow.sectionId) === modelData.value
          hasCursor: root.cursorActive && root.focusSection === choiceRow.sectionId && root.selectedIndex === index
          onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(choiceRow)
          onClicked: root.setChoice(choiceRow.sectionId, modelData.value)
          onHovered: function(isHovered) {
            if (!isHovered) return
            root.cursorActive = true
            root.focusSection = choiceRow.sectionId
            root.selectedIndex = index
          }
        }
      }
    }
  }

  component RevealButton: Button {
    id: revealButton
    required property string sectionId

    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.space(3)
    bordered: true
    hasCursor: root.cursorActive && root.focusSection === sectionId
    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.focusSection = revealButton.sectionId
      root.selectedIndex = 0
    }
  }

  component CompactToggle: BorderSurface {
    id: toggleRow
    required property string label
    required property string sectionId
    readonly property bool hasCursor: root.cursorActive && root.focusSection === sectionId

    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(toggleRow)

    implicitHeight: Style.space(32)
    radius: Style.cornerRadius
    color: "transparent"
    borderSpec: Border.controlSpec(
      hasCursor || mouse.containsMouse ? "hover-cursor" : "normal",
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
        checked: root.toggleChecked(toggleRow.sectionId)
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
      onClicked: root.flipToggle(toggleRow.sectionId)
    }
  }
}
