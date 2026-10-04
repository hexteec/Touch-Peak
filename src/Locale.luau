--[[
	UI strings in Polish and English.

	The "auto" language picks Polish when Studio or the operating system runs
	in Polish, English otherwise.
]]

local STRINGS = {
	pl = {
		buttonTooltip = "Sterowanie kamerą dotykiem",

		statusOn = "Włączony",
		statusPaused = "Wstrzymany",

		tabGestures = "Gesty",
		tabSettings = "Ustawienia",

		actDrag = "Przeciągnij",
		effDrag = "obraca kamerę",
		actTapDrag = "Stuknij i przeciągnij",
		effTapDrag = "przesuwa widok",
		actStrip = "Suwak przy krawędzi",
		effStrip = "przybliża i oddala",
		actTap = "Stuknij",
		effTap = "zaznacza obiekt",
		actDoubleTap = "Stuknij dwa razy",
		effDoubleTap = "ustawia kamerę na obiekcie",
		actHold = "Przytrzymaj",
		effHold = "dodaje do zaznaczenia albo usuwa",
		actTwoFingers = "Dwa palce",
		effTwoFingers = "zoom i przesuwanie, gdy Studio je widzi",

		hudRotate = "Obrót",
		hudZoom = "Zoom",
		hudPan = "Przesuwanie",
		hudBoth = "Zoom i przesuwanie",
		noGesture = "brak",

		toastSelected = "Zaznaczono: %s",
		toastAdded = "Dodano: %s",
		toastRemoved = "Odznaczono: %s",
		toastCleared = "Zaznaczenie wyczyszczone",
		toastFocused = "Kamera na: %s",
		toastNothingToFocus = "Stuknij dwa razy w obiekt, żeby go pokazać",
		toastPausedByTool = "Wstrzymano, bo wybrano inne narzędzie",
		toastResumed = "Sterowanie dotykiem włączone",
		toastSelectionItems = "%d obiektów",
		toastMouseOnly = "Studio widzi dotyk jako mysz. Przesuwanie: stuknij i przeciągnij. Zoom: suwak z boku.",

		groupSensitivity = "Czułość",
		rotateSpeed = "Obrót",
		zoomSpeed = "Zoom",
		panSpeed = "Przesuwanie",

		groupCamera = "Kamera",
		rotateMode = "Obrót",
		rotateModeOrbit = "Orbita",
		rotateModeLook = "W miejscu",
		inertia = "Bezwładność",
		inertiaHint = "Kamera wyhamowuje po machnięciu",
		invertRotate = "Odwróć obrót",
		invertRotateHint = "Kamera kręci się w drugą stronę",
		invertPan = "Odwróć przesuwanie",
		invertPanHint = "Kamera leci tam, gdzie palec",
		combineGestures = "Zoom i przesuwanie naraz",
		combineGesturesHint = "Przy gestach dwoma palcami",

		groupZoom = "Suwak zoomu",
		showZoomStrip = "Pokazuj suwak",
		showZoomStripHint = "Przy krawędzi widoku",
		zoomSide = "Strona",
		zoomSideLeft = "Lewa",
		zoomSideRight = "Prawa",

		groupSelection = "Zaznaczanie i widok",
		selectModels = "Zaznaczaj całe modele",
		selectModelsHint = "Tak jak kliknięcie w Studio",
		showTouches = "Pokazuj dotyk",
		showTouchesHint = "Okręgi pod palcami",
		mouseInput = "Mysz i rysik",
		mouseInputHint = "Działają jak jeden palec",
		language = "Język",
		languageAuto = "Auto",

		groupDiagnostics = "Diagnostyka",
		touchScreen = "Ekran dotykowy",
		detected = "wykryty",
		notDetected = "nie wykryto",
		diagInput = "Ostatnie wejście",
		inputTouch = "dotyk",
		inputMouse = "mysz",
		inputNone = "brak",
		diagTouchEvents = "Zdarzenia dotyku",
		diagTouchFingers = "Najwięcej palców naraz",
		diagMouseClicks = "Kliknięcia myszą",
		diagMouseMoves = "Ruchy myszy",
		diagPinch = "Gesty szczypania",
		version = "Wersja",
		reset = "Przywróć domyślne",
	},

	en = {
		buttonTooltip = "Touch camera controls",

		statusOn = "On",
		statusPaused = "Paused",

		tabGestures = "Gestures",
		tabSettings = "Settings",

		actDrag = "Drag",
		effDrag = "rotates the camera",
		actTapDrag = "Tap, then drag",
		effTapDrag = "pans the view",
		actStrip = "Edge slider",
		effStrip = "zooms in and out",
		actTap = "Tap",
		effTap = "selects an object",
		actDoubleTap = "Double-tap",
		effDoubleTap = "frames the object",
		actHold = "Press and hold",
		effHold = "adds to or removes from the selection",
		actTwoFingers = "Two fingers",
		effTwoFingers = "zoom and pan, when Studio sees both",

		hudRotate = "Rotate",
		hudZoom = "Zoom",
		hudPan = "Pan",
		hudBoth = "Zoom and pan",
		noGesture = "none",

		toastSelected = "Selected: %s",
		toastAdded = "Added: %s",
		toastRemoved = "Removed: %s",
		toastCleared = "Selection cleared",
		toastFocused = "Framed: %s",
		toastNothingToFocus = "Double-tap an object to frame it",
		toastPausedByTool = "Paused because another tool was picked",
		toastResumed = "Touch controls on",
		toastSelectionItems = "%d objects",
		toastMouseOnly = "Studio sees touch as a mouse. Pan: tap, then drag. Zoom: the edge slider.",

		groupSensitivity = "Sensitivity",
		rotateSpeed = "Rotate",
		zoomSpeed = "Zoom",
		panSpeed = "Pan",

		groupCamera = "Camera",
		rotateMode = "Rotate",
		rotateModeOrbit = "Orbit",
		rotateModeLook = "In place",
		inertia = "Inertia",
		inertiaHint = "The camera glides after a flick",
		invertRotate = "Invert rotation",
		invertRotateHint = "The camera turns the other way",
		invertPan = "Invert pan",
		invertPanHint = "The camera moves with your finger",
		combineGestures = "Zoom and pan together",
		combineGesturesHint = "For two-finger gestures",

		groupZoom = "Zoom slider",
		showZoomStrip = "Show slider",
		showZoomStripHint = "At the edge of the view",
		zoomSide = "Side",
		zoomSideLeft = "Left",
		zoomSideRight = "Right",

		groupSelection = "Selection and view",
		selectModels = "Select whole models",
		selectModelsHint = "Same as clicking in Studio",
		showTouches = "Show touches",
		showTouchesHint = "Rings under your fingers",
		mouseInput = "Mouse and pen",
		mouseInputHint = "Act as one finger",
		language = "Language",
		languageAuto = "Auto",

		groupDiagnostics = "Diagnostics",
		touchScreen = "Touch screen",
		detected = "detected",
		notDetected = "not detected",
		diagInput = "Last input",
		inputTouch = "touch",
		inputMouse = "mouse",
		inputNone = "none",
		diagTouchEvents = "Touch events",
		diagTouchFingers = "Most fingers at once",
		diagMouseClicks = "Mouse clicks",
		diagMouseMoves = "Mouse moves",
		diagPinch = "Pinch gestures",
		version = "Version",
		reset = "Reset to defaults",
	},
}

local GESTURE_KEYS = {
	rotate = "hudRotate",
	zoom = "hudZoom",
	pan = "hudPan",
	both = "hudBoth",
}

local function systemLanguage(): string
	local ids = {}
	pcall(function()
		table.insert(ids, game:GetService("StudioService").StudioLocaleId)
	end)
	pcall(function()
		table.insert(ids, game:GetService("LocalizationService").SystemLocaleId)
	end)
	for _, id in ids do
		if type(id) == "string" and string.lower(string.sub(id, 1, 2)) == "pl" then
			return "pl"
		end
	end
	return "en"
end

local Locale = {}
Locale.__index = Locale

Locale.Strings = STRINGS

function Locale.new(language: string?)
	local self = setmetatable({}, Locale)
	self:SetLanguage(language or "auto")
	return self
end

function Locale:SetLanguage(language: string)
	if language == "auto" or not STRINGS[language] then
		language = systemLanguage()
	end
	self.language = language
	self._strings = STRINGS[language]
end

function Locale:t(key: string, ...: any): string
	local text = self._strings[key] or STRINGS.en[key] or key
	if select("#", ...) > 0 then
		return string.format(text, ...)
	end
	return text
end

-- Display name of a recognizer gesture ("rotate", "zoom", "pan", "both").
function Locale:gesture(name: string?): string
	return self:t(if name then GESTURE_KEYS[name] or "noGesture" else "noGesture")
end

return Locale
