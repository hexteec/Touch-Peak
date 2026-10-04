--[[
	UI strings in Polish and English.

	The "auto" language picks Polish when Studio or the operating system runs
	in Polish, English otherwise.
]]

local STRINGS = {
	pl = {
		buttonTooltip = "Sterowanie kamerą i zaznaczaniem dotykiem",

		statusActive = "Aktywny",
		statusPaused = "Wstrzymany",
		touchControl = "Sterowanie dotykiem",
		fingers = "Palce",
		fingersMouse = "Mysz",
		gesture = "Gest",
		noGesture = "brak",

		dragHint = "Przeciągnij nagłówek, aby przesunąć",

		tabGestures = "Gesty",
		tabSettings = "Ustawienia",

		gestureRotate = "Obrót kamery",
		gestureRotateHint = "Przesuń jednym palcem",
		gestureTapDrag = "Przybliżanie jednym palcem",
		gestureTapDragHint = "Stuknij, potem przeciągnij w górę lub w dół",
		gestureJoystick = "Joystick i suwak",
		gestureJoystickHint = "Lewy dolny róg: lot kamery i zoom",
		gestureTwoFingers = "Dwa palce",
		gestureTwoFingersHint = "Rozsuń: zoom · razem: przesuwanie",
		gestureTap = "Zaznacz obiekt",
		gestureTapHint = "Stuknij obiekt – pusty obszar odznacza",
		gestureDoubleTap = "Skup kamerę",
		gestureDoubleTapHint = "Stuknij dwukrotnie obiekt",
		gestureLongPress = "Dodaj / usuń z zaznaczenia",
		gestureLongPressHint = "Przytrzymaj palec na obiekcie",

		hudRotate = "Obrót",
		hudZoom = "Przybliżanie",
		hudPan = "Przesuwanie",
		hudBoth = "Zoom + pan",
		navPan = "Przesuń",
		navZoom = "Zoom",

		toastSelected = "Zaznaczono: %s",
		toastAdded = "Dodano: %s",
		toastRemoved = "Odznaczono: %s",
		toastCleared = "Wyczyszczono zaznaczenie",
		toastFocused = "Kamera na: %s",
		toastNothingToFocus = "Brak obiektu do pokazania",
		toastPausedByTool = "Wstrzymano – wybrano inne narzędzie",
		toastResumed = "Sterowanie dotykiem włączone",
		toastSelectionItems = "%d obiektów",
		toastMouseOnly = "Studio podaje dotyk jako mysz – zoom: stuknij i przeciągnij, przesuwanie: joystick",

		sectionSensitivity = "CZUŁOŚĆ",
		rotateSpeed = "Obrót",
		zoomSpeed = "Przybliżanie",
		panSpeed = "Przesuwanie",

		sectionCamera = "KAMERA",
		rotateMode = "Tryb obrotu",
		rotateModeOrbit = "Orbita",
		rotateModeLook = "W miejscu",
		inertia = "Bezwładność",
		inertiaHint = "Kamera płynnie wyhamowuje",
		combineGestures = "Zoom i pan razem",
		combineGesturesHint = "Oba gesty jednocześnie",
		invertRotate = "Odwróć obrót",
		invertRotateHint = "Odwrotny kierunek obrotu",
		invertPan = "Odwróć przesuwanie",
		invertPanHint = "Kamera leci w stronę ruchu palców",

		sectionSelection = "ZAZNACZANIE I WIDOK",
		selectModels = "Zaznaczaj całe modele",
		selectModelsHint = "Tak jak kliknięcie w Studio",
		showTouches = "Pokazuj dotyk",
		showTouchesHint = "Kółka pod palcami",
		mouseInput = "Mysz i rysik",
		mouseInputHint = "Lewy przycisk działa jak palec",
		showNavigator = "Joystick i suwak zoomu",
		showNavigatorHint = "W lewym dolnym rogu widoku",
		language = "Język",
		languageAuto = "Auto",

		sectionInfo = "DIAGNOSTYKA",
		touchScreen = "Ekran dotykowy",
		detected = "wykryty",
		notDetected = "nie wykryto",
		diagTouch = "Dotyk",
		diagTouchValue = "zdarzenia: %d · maks. palców: %d",
		diagMouse = "Mysz",
		diagMouseValue = "kliknięcia: %d · ruchy: %d",
		diagGestures = "Gesty Studio",
		diagGesturesValue = "pinch: %d · pan: %d · kółko: %d",
		reset = "Przywróć domyślne",
	},

	en = {
		buttonTooltip = "Touch camera controls and selection",

		statusActive = "Active",
		statusPaused = "Paused",
		touchControl = "Touch controls",
		fingers = "Fingers",
		fingersMouse = "Mouse",
		gesture = "Gesture",
		noGesture = "none",

		dragHint = "Drag the header to move",

		tabGestures = "Gestures",
		tabSettings = "Settings",

		gestureRotate = "Rotate camera",
		gestureRotateHint = "Drag with one finger",
		gestureTapDrag = "One-finger zoom",
		gestureTapDragHint = "Tap, then drag up or down",
		gestureJoystick = "Joystick and slider",
		gestureJoystickHint = "Bottom-left: fly the camera and zoom",
		gestureTwoFingers = "Two fingers",
		gestureTwoFingersHint = "Spread: zoom · together: pan",
		gestureTap = "Select object",
		gestureTapHint = "Tap an object – empty space clears",
		gestureDoubleTap = "Focus camera",
		gestureDoubleTapHint = "Double-tap an object",
		gestureLongPress = "Add / remove from selection",
		gestureLongPressHint = "Press and hold on an object",

		hudRotate = "Rotate",
		hudZoom = "Zoom",
		hudPan = "Pan",
		hudBoth = "Zoom + pan",
		navPan = "Pan",
		navZoom = "Zoom",

		toastSelected = "Selected: %s",
		toastAdded = "Added: %s",
		toastRemoved = "Removed: %s",
		toastCleared = "Selection cleared",
		toastFocused = "Focused: %s",
		toastNothingToFocus = "Nothing to focus on",
		toastPausedByTool = "Paused – another tool was selected",
		toastResumed = "Touch controls on",
		toastSelectionItems = "%d objects",
		toastMouseOnly = "Studio sends touch as a mouse – zoom: tap and drag, pan: joystick",

		sectionSensitivity = "SENSITIVITY",
		rotateSpeed = "Rotate",
		zoomSpeed = "Zoom",
		panSpeed = "Pan",

		sectionCamera = "CAMERA",
		rotateMode = "Rotation mode",
		rotateModeOrbit = "Orbit",
		rotateModeLook = "In place",
		inertia = "Inertia",
		inertiaHint = "Camera glides to a stop",
		combineGestures = "Zoom and pan together",
		combineGesturesHint = "Both gestures at once",
		invertRotate = "Invert rotation",
		invertRotateHint = "Reverse the rotation direction",
		invertPan = "Invert pan",
		invertPanHint = "Camera flies along with your fingers",

		sectionSelection = "SELECTION & VIEW",
		selectModels = "Select whole models",
		selectModelsHint = "Same as clicking in Studio",
		showTouches = "Show touches",
		showTouchesHint = "Circles under your fingers",
		mouseInput = "Mouse & pen",
		mouseInputHint = "Left button acts as a finger",
		showNavigator = "Joystick and zoom slider",
		showNavigatorHint = "Bottom-left corner of the view",
		language = "Language",
		languageAuto = "Auto",

		sectionInfo = "DIAGNOSTICS",
		touchScreen = "Touch screen",
		detected = "detected",
		notDetected = "not detected",
		diagTouch = "Touch",
		diagTouchValue = "events: %d · max fingers: %d",
		diagMouse = "Mouse",
		diagMouseValue = "clicks: %d · moves: %d",
		diagGestures = "Studio gestures",
		diagGesturesValue = "pinch: %d · pan: %d · wheel: %d",
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
