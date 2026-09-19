function clamp(value, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function asBool(value, fallback) {
  if (value === true || value === false) return value
  var s = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (s === "true" || s === "1" || s === "yes" || s === "on") return true
  if (s === "false" || s === "0" || s === "no" || s === "off") return false
  return fallback
}

function asNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function normalizeAccel(value) {
  var s = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (s === "" || s === "[[empty]]" || s === "adaptive" || s === "default") return "adaptive"
  if (s === "flat") return "flat"
  if (s.indexOf("custom") === 0) return "custom"
  return "adaptive"
}

function accelLabel(profile) {
  var p = normalizeAccel(profile)
  if (p === "flat") return "Flat"
  if (p === "custom") return "Custom"
  return "Adaptive"
}

function speedPercentFromSensitivity(sensitivity) {
  return Math.round(clamp((asNumber(sensitivity, 0) + 1) * 50, 0, 100))
}

function sensitivityFromSpeedPercent(percent) {
  return Math.round((clamp(percent, 0, 100) / 50 - 1) * 100) / 100
}

function scrollPercentFromFactor(factor) {
  var f = clamp(asNumber(factor, 1), 0.1, 2.0)
  if (f <= 1)
    return Math.round(((f - 0.1) / 0.9) * 50)
  return Math.round(50 + (f - 1.0) * 50)
}

function factorFromScrollPercent(percent) {
  var p = clamp(percent, 0, 100)
  if (p <= 50)
    return Math.round((0.1 + (p / 50) * 0.9) * 100) / 100
  return Math.round((1.0 + ((p - 50) / 50)) * 100) / 100
}

function speedName(percent) {
  var p = clamp(percent, 0, 100)
  if (p <= 12) return "Glacial"
  if (p <= 28) return "Slow"
  if (p <= 42) return "Gentle"
  if (p <= 58) return "Natural"
  if (p <= 72) return "Quick"
  if (p <= 88) return "Fast"
  return "Lightning"
}

function heroMeta(state, speedPercent) {
  var parts = [accelLabel(state.accelProfile).toUpperCase()]
  parts.push(Math.round(speedPercent) + "%")
  if (state.naturalScroll) parts.push("NATURAL")
  if (state.leftHanded) parts.push("LEFT")
  return parts.join(" · ")
}

function emptyState() {
  return {
    sensitivity: 0,
    accelProfile: "adaptive",
    naturalScroll: false,
    scrollFactor: 1,
    leftHanded: false,
    touchpadNaturalScroll: false,
    touchpadScrollFactor: 0.4,
    disableWhileTyping: true,
    tapToClick: true,
    clickfingerBehavior: true,
    hasTouchpad: false
  }
}

function parseState(raw) {
  var state = emptyState()
  var parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return state }
  if (!parsed || typeof parsed !== "object") return state

  state.sensitivity = clamp(asNumber(parsed.sensitivity, 0), -1, 1)
  state.accelProfile = normalizeAccel(parsed.accelProfile)
  state.naturalScroll = asBool(parsed.naturalScroll, false)
  state.scrollFactor = clamp(asNumber(parsed.scrollFactor, 1), 0.1, 2)
  state.leftHanded = asBool(parsed.leftHanded, false)
  state.touchpadNaturalScroll = asBool(parsed.touchpadNaturalScroll, state.naturalScroll)
  state.touchpadScrollFactor = clamp(asNumber(parsed.touchpadScrollFactor, 0.4), 0.1, 2)
  state.disableWhileTyping = asBool(parsed.disableWhileTyping, true)
  state.tapToClick = asBool(parsed.tapToClick, true)
  state.clickfingerBehavior = asBool(parsed.clickfingerBehavior, true)
  state.hasTouchpad = asBool(parsed.hasTouchpad, false)
  return state
}

function statePayload(state) {
  return JSON.stringify({
    sensitivity: clamp(asNumber(state.sensitivity, 0), -1, 1),
    accelProfile: normalizeAccel(state.accelProfile),
    naturalScroll: !!state.naturalScroll,
    scrollFactor: clamp(asNumber(state.scrollFactor, 1), 0.1, 2),
    leftHanded: !!state.leftHanded,
    touchpadNaturalScroll: !!state.touchpadNaturalScroll,
    touchpadScrollFactor: clamp(asNumber(state.touchpadScrollFactor, 0.4), 0.1, 2),
    disableWhileTyping: !!state.disableWhileTyping,
    tapToClick: !!state.tapToClick,
    clickfingerBehavior: !!state.clickfingerBehavior
  })
}

function visibleSections(hasTouchpad) {
  var list = ["speed", "accel", "natural", "scroll", "primary"]
  if (hasTouchpad) {
    list.push("touchScroll")
    list.push("tap")
    list.push("dwt")
    list.push("clickfinger")
  }
  return list
}

function sectionIsSlider(section) {
  return section === "speed" || section === "scroll" || section === "touchScroll"
}

function sectionIsChoice(section) {
  return section === "accel" || section === "primary"
}

function sectionChoiceCount(section) {
  return sectionIsChoice(section) ? 2 : 0
}

function sectionFirstIndex(section) {
  if (sectionIsSlider(section)) return -1
  return 0
}
