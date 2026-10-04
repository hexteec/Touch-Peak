return function(t)
	local describe, it, expect, World = t.describe, t.it, t.expect, t.World
	local Vector2 = World.Vector2
	local task = require("@lune/task")

	local function setup()
		local world = World.new()
		local Settings = world:require("Settings")
		local Locale = world:require("Locale")
		local Panel = world:require("UI/Panel")
		local Overlay = world:require("UI/Overlay")

		local gui = world.newInstance("ScreenGui")
		gui.Parent = world.coreGui

		local plugin = world:plugin()
		local settings = Settings.new(plugin)
		local calls = { active = {}, close = 0 }
		local panel = Panel.new({
			parent = gui,
			settings = settings,
			locale = Locale.new("pl"),
			active = true,
			touchDetected = false,
			onActiveChanged = function(active)
				table.insert(calls.active, active)
			end,
			onClose = function()
				calls.close += 1
			end,
		})
		local overlay = Overlay.new(gui, settings)
		return {
			world = world,
			gui = gui,
			panel = panel,
			overlay = overlay,
			settings = settings,
			plugin = plugin,
			calls = calls,
		}
	end

	local function find(root, name: string)
		for _, descendant in root:GetDescendants() do
			if descendant.Name == name then
				return descendant
			end
		end
		error("no descendant named " .. name)
	end

	local function textButtons(root, text: string)
		local out = {}
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("TextButton") and descendant.Text == text then
				table.insert(out, descendant)
			end
		end
		return out
	end

	describe("Panel", function()
		it("builds and opens in the top-right corner", function()
			local h = setup()
			h.panel:SetVisible(true)
			local root = find(h.gui, "TouchPeakPanel")
			expect(root.Visible).toBe(true)
			local position = root.Position
			expect(position.X.Offset + root.Size.X.Offset).toBeLessThan(World.ScreenSize.X)
			expect(position.Y.Offset).toBeGreaterThan(0)
		end)

		it("follows the viewport size until it is moved", function()
			local h = setup()
			local root = find(h.gui, "TouchPeakPanel")
			local x = root.Position.X.Offset
			h.gui:GetPropertyChangedSignal("AbsoluteSize"):Fire()
			expect(root.Position.X.Offset).toBe(x)
			expect(x).toBe(World.ScreenSize.X - 324 - 24)
		end)

		it("shows the active state in the header", function()
			local h = setup()
			local label = find(h.gui, "Status").Label
			expect(label.Text).toBe("Aktywny")
			h.panel:SetGesture("zoom")
			expect(label.Text).toBe("Aktywny · Przybliżanie")
			h.panel:SetActive(false)
			expect(label.Text).toBe("Wstrzymany")
		end)

		it("collapses into a pill and expands again", function()
			local h = setup()
			h.panel:SetVisible(true)
			local root = find(h.gui, "TouchPeakPanel")
			h.panel:SetCollapsed(true)
			expect(h.panel:IsCollapsed()).toBe(true)
			expect(root.Size.Y.Offset).toBe(62)
			task.wait(0.35)
			expect(find(h.gui, "Content").Visible).toBe(false)
			h.panel:SetCollapsed(false)
			expect(find(h.gui, "Content").Visible).toBe(true)
			expect(root.Size.Y.Offset).toBeGreaterThan(400)
		end)

		it("collapses from the chevron button and closes from the X", function()
			local h = setup()
			h.panel:SetVisible(true)
			local header = find(h.gui, "Header")
			header.Collapse.Activated:Fire()
			expect(h.panel:IsCollapsed()).toBe(true)
			header.Close.Activated:Fire()
			expect(h.calls.close).toBe(1)
		end)

		it("reports clicks on the touch toggle", function()
			local h = setup()
			local toggle = find(h.gui, "StatusCard").Toggle
			toggle.Activated:Fire()
			expect(h.calls.active[1]).toBe(false)
		end)

		it("is dragged by the header and remembers where", function()
			local h = setup()
			h.panel:SetVisible(true)
			local root = find(h.gui, "TouchPeakPanel")
			local start = root.Position
			local handle = find(h.gui, "DragHandle")
			local touch = h.world:input("Touch", Vector2.new(900, 40))
			handle.InputBegan:Fire(touch)
			touch.Position = World.Vector3.new(700, 90, 0)
			h.world.userInputService.InputChanged:Fire(touch)
			h.world.userInputService.InputEnded:Fire(touch)
			expect(root.Position.X.Offset).toBe(start.X.Offset - 200)
			expect(root.Position.Y.Offset).toBe(start.Y.Offset + 50)
			expect(h.settings:GetState("position").x).toBe(start.X.Offset - 200)
		end)

		it("keeps the window on screen while dragging", function()
			local h = setup()
			h.panel:SetVisible(true)
			local root = find(h.gui, "TouchPeakPanel")
			local handle = find(h.gui, "DragHandle")
			local mouse = h.world:input("MouseButton1", Vector2.new(900, 40))
			handle.InputBegan:Fire(mouse)
			h.world.userInputService.InputChanged:Fire(h.world:input("MouseMovement", Vector2.new(5000, 5000)))
			h.world.userInputService.InputEnded:Fire(mouse)
			expect(root.Position.X.Offset + root.Size.X.Offset).toBeLessThan(World.ScreenSize.X + 1)
			expect(root.Position.Y.Offset + root.Size.Y.Offset).toBeLessThan(World.ScreenSize.Y + 1)
		end)

		it("expands when the collapsed pill is tapped", function()
			local h = setup()
			h.panel:SetVisible(true)
			h.panel:SetCollapsed(true, true)
			local handle = find(h.gui, "DragHandle")
			local touch = h.world:input("Touch", Vector2.new(900, 40))
			handle.InputBegan:Fire(touch)
			h.world.userInputService.InputEnded:Fire(touch)
			expect(h.panel:IsCollapsed()).toBe(false)
		end)

		it("knows which screen points it covers", function()
			local h = setup()
			expect(h.panel:ContainsPoint(Vector2.new(1100, 100))).toBe(false) -- hidden
			h.panel:SetVisible(true)
			local root = find(h.gui, "TouchPeakPanel")
			local x, y = root.Position.X.Offset, root.Position.Y.Offset
			expect(h.panel:ContainsPoint(Vector2.new(x + 20, y + 20))).toBe(true)
			expect(h.panel:ContainsPoint(Vector2.new(x - 40, y + 20))).toBe(false)
			expect(h.panel:ContainsPoint(Vector2.new(100, 600))).toBe(false)
		end)

		it("switches tabs", function()
			local h = setup()
			local settingsTab = textButtons(h.gui, "Ustawienia")[1]
			settingsTab.Activated:Fire()
			expect(find(h.gui, "Pages").Settings.Position.X.Scale).toBe(0)
			expect(find(h.gui, "Pages").Gestures.Position.X.Scale).toBe(-1)
			expect(h.settings:GetState("tab")).toBe("settings")
		end)

		it("edits settings from the settings page", function()
			local h = setup()
			local page = find(h.gui, "Pages").Settings
			-- The first stepper is rotation sensitivity; press its plus button.
			local stepper = nil
			for _, descendant in page:GetDescendants() do
				if descendant.Name == "Plus" then
					stepper = descendant.Parent
					break
				end
			end
			stepper.Plus.Activated:Fire()
			expect(h.settings:Get("rotateSensitivity")).toBe(1.25)
			expect(stepper.Value.Text).toBe("1.25×")
			stepper.Minus.Activated:Fire()
			stepper.Minus.Activated:Fire()
			expect(stepper.Value.Text).toBe("0.75×")

			-- Changing a setting elsewhere updates the controls.
			h.settings:Set("rotateSensitivity", 2)
			expect(stepper.Value.Text).toBe("2.0×")

			local orbitButtons = textButtons(page, "W miejscu")
			orbitButtons[1].Activated:Fire()
			expect(h.settings:Get("rotateMode")).toBe("look")

			local reset = textButtons(page, "Przywróć domyślne")[1]
			reset.Activated:Fire()
			expect(h.settings:Get("rotateMode")).toBe("orbit")
			expect(stepper.Value.Text).toBe("1.0×")
		end)

		it("shows touch detection", function()
			local h = setup()
			h.panel:SetTouchDetected(true)
			h.panel:SetTouchCount(2)
			local chips = find(h.gui, "Chips")
			expect(string.find(chips.Fingers.Text, "2", 1, true) ~= nil).toBe(true)
		end)

		it("cleans up after itself", function()
			local h = setup()
			h.panel:Destroy()
			expect(#h.gui:GetChildren()).toBe(1) -- only the overlay remains
		end)
	end)

	describe("Overlay", function()
		it("draws a circle per finger and a line between two", function()
			local h = setup()
			h.overlay:TouchBegan("a", Vector2.new(100, 100))
			h.overlay:TouchBegan("b", Vector2.new(300, 100))
			local root = find(h.gui, "TouchPeakOverlay")
			local circles = 0
			for _, child in root:GetChildren() do
				if child:FindFirstChild("Core") then
					circles += 1
				end
			end
			expect(circles).toBe(2)
			h.overlay:TouchMoved("b", Vector2.new(300, 300))
			h.overlay:TouchEnded("a")
			h.overlay:TouchEnded("b")
			h.overlay:Ripple(Vector2.new(50, 50))
			h.overlay:ShowGesture("Obrót")
			h.overlay:ShowGesture(nil)
			h.overlay:Toast("Zaznaczono: Part")
			task.wait(0.5)
			local remaining = 0
			for _, child in root:GetChildren() do
				if child:FindFirstChild("Core") or child:FindFirstChild("Stroke") and child.Size.X.Offset == 76 then
					remaining += 1
				end
			end
			expect(remaining).toBe(0)
		end)

		it("respects the show touches setting", function()
			local h = setup()
			h.settings:Set("showTouches", false)
			h.overlay:TouchBegan("a", Vector2.new(100, 100))
			local root = find(h.gui, "TouchPeakOverlay")
			for _, child in root:GetChildren() do
				expect(child:FindFirstChild("Core")).toBe(nil)
			end
		end)
	end)

	describe("GestureIcons", function()
		it("builds every icon with looping animations", function()
			local world = World.new()
			local Icons = world:require("UI/GestureIcons")
			for _, name in { "rotate", "zoom", "pan", "tap", "doubleTap", "longPress" } do
				local icon, tweens = Icons[name]()
				expect(icon:IsA("Frame")).toBe(true)
				expect(#tweens > 0).toBe(true)
				for _, tween in tweens do
					tween:Play()
				end
			end
		end)
	end)
end
