return function(t)
	local describe, it, expect, World = t.describe, t.it, t.expect, t.World
	local Vector2, Vector3, CFrame = World.Vector2, World.Vector3, World.CFrame
	local task = require("@lune/task")

	local function setup()
		local world = World.new()
		world.groundPlane = true
		world.camera.CFrame = CFrame.lookAt(Vector3.new(0, 20, 40), Vector3.new(0, 0, 0))
		local App = world:require("App")
		local plugin = world:plugin()
		local app = App.new(plugin)
		local uis = world.userInputService

		local h = { world = world, app = app, plugin = plugin, uis = uis }

		function h.touchDown(position: Vector2)
			local input = world:input("Touch", position)
			uis.InputBegan:Fire(input, false)
			return input
		end
		function h.touchMove(input, position: Vector2)
			input.Position = Vector3.new(position.X, position.Y, 0)
			input.UserInputState = World.Enum.UserInputState.Change
			uis.InputChanged:Fire(input, false)
		end
		function h.frame()
			world.heartbeat:Fire(1 / 60)
		end
		function h.touchUp(input)
			input.UserInputState = World.Enum.UserInputState.End
			uis.InputEnded:Fire(input, false)
			uis.TouchEnded:Fire(input, false)
		end
		function h.drag(input, from: Vector2, to: Vector2)
			for step = 1, 8 do
				h.touchMove(input, from:Lerp(to, step / 8))
			end
		end
		function h.screenOf(point: Vector3): Vector2
			local projected = world.camera:WorldToViewportPoint(point)
			return Vector2.new(projected.X, projected.Y)
		end

		return h
	end

	describe("App", function()
		it("opens the window, takes the mouse and listens to touches", function()
			local h = setup()
			local opened = nil
			h.app.OpenChanged:Connect(function(open)
				opened = open
			end)
			h.app:Toggle()
			expect(opened).toBe(true)
			expect(h.plugin:IsActivated()).toBe(true)
			expect(h.world.coreGui:FindFirstChild("TouchPeak") ~= nil).toBe(true)
			expect(h.app.panel:IsVisible()).toBe(true)
			expect(h.app.panel:IsCollapsed()).toBe(false)
			expect(h.uis.InputBegan:Count()).toBeGreaterThan(0)
		end)

		it("rotates the camera with one finger", function()
			local h = setup()
			h.app:Open()
			local before = h.world.camera.CFrame
			local finger = h.touchDown(Vector2.new(400, 400))
			h.drag(finger, Vector2.new(400, 400), Vector2.new(600, 400))
			h.touchUp(finger)
			expect((h.world.camera.CFrame.Position - before.Position).Magnitude).toBeGreaterThan(5)
		end)

		it("pinches and pans with two fingers", function()
			local h = setup()
			h.app:Open()
			local distance = h.world.camera.CFrame.Position.Magnitude
			local a = h.touchDown(Vector2.new(560, 360))
			local b = h.touchDown(Vector2.new(720, 360))
			for step = 1, 10 do
				h.touchMove(a, Vector2.new(560 - step * 8, 360))
				h.touchMove(b, Vector2.new(720 + step * 8, 360))
				h.frame()
			end
			h.touchUp(a)
			h.touchUp(b)
			expect(h.world.camera.CFrame.Position.Magnitude).toBeLessThan(distance * 0.75)

			local look = h.world.camera.CFrame.LookVector
			local position = h.world.camera.CFrame.Position
			a = h.touchDown(Vector2.new(500, 300))
			b = h.touchDown(Vector2.new(600, 300))
			for step = 1, 10 do
				h.touchMove(a, Vector2.new(500 + step * 10, 300))
				h.touchMove(b, Vector2.new(600 + step * 10, 300))
				h.frame()
			end
			h.touchUp(a)
			h.touchUp(b)
			-- Panning moves without turning.
			expect(h.world.camera.CFrame.LookVector).toBeCloseTo(look, 1e-4)
			expect((h.world.camera.CFrame.Position - position).Magnitude).toBeGreaterThan(1)
		end)

		it("selects with a tap and focuses with a double tap", function()
			local h = setup()
			h.app:Open()
			local part = h.world:part({ Name = "Tower", Size = Vector3.new(4, 8, 4), CFrame = CFrame.new(10, 4, 0) })
			local spot = h.screenOf(Vector3.new(10, 4, 0))

			h.touchUp(h.touchDown(spot))
			expect(h.world.selection:Get()[1]).toBe(part)

			h.touchUp(h.touchDown(spot))
			for _ = 1, 60 do
				h.world.heartbeat:Fire(1 / 60)
			end
			expect(h.screenOf(Vector3.new(10, 4, 0))).toBeCloseTo(World.ScreenSize / 2, 0.01)
		end)

		it("adds to the selection with a long press", function()
			local h = setup()
			h.app:Open()
			local a = h.world:part({ Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(-8, 2, 0) })
			local b = h.world:part({ Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(8, 2, 0) })
			h.world.selection:Set({ a })
			local finger = h.touchDown(h.screenOf(Vector3.new(8, 2, 0)))
			task.wait(0.7)
			h.touchUp(finger)
			local selected = h.world.selection:Get()
			expect(#selected).toBe(2)
			expect(table.find(selected, b) ~= nil).toBe(true)
		end)

		it("ignores touches that start on the window", function()
			local h = setup()
			h.app:Open()
			local before = h.world.camera.CFrame.Position
			local root = h.world.coreGui.TouchPeak.TouchPeakPanel
			local inside = Vector2.new(root.Position.X.Offset + 150, root.Position.Y.Offset + 300)
			local finger = h.touchDown(inside)
			h.drag(finger, inside, inside - Vector2.new(400, 0))
			h.touchUp(finger)
			expect(h.world.camera.CFrame.Position).toBeCloseTo(before)
		end)

		it("treats the mouse as a finger, but not right after a touch", function()
			local h = setup()
			h.app:Open()
			local before = h.world.camera.CFrame.Position
			local mouse = h.world:input("MouseButton1", Vector2.new(300, 300))
			h.uis.InputBegan:Fire(mouse, false)
			h.uis.InputChanged:Fire(h.world:input("MouseMovement", Vector2.new(500, 300)), false)
			h.uis.InputEnded:Fire(mouse, false)
			local moved = h.world.camera.CFrame.Position
			expect((moved - before).Magnitude).toBeGreaterThan(1)

			-- A touch followed by Windows' synthetic mouse events must not double up.
			local finger = h.touchDown(Vector2.new(300, 300))
			h.touchUp(finger)
			local afterTouch = h.world.camera.CFrame.Position
			h.uis.InputBegan:Fire(mouse, false)
			h.uis.InputChanged:Fire(h.world:input("MouseMovement", Vector2.new(700, 300)), false)
			h.uis.InputEnded:Fire(mouse, false)
			expect(h.world.camera.CFrame.Position).toBeCloseTo(afterTouch)
		end)

		it("lets a real touch replace a synthetic mouse press without a tap", function()
			local h = setup()
			h.app:Open()
			local taps = 0
			h.app.recognizer.Tap:Connect(function()
				taps += 1
			end)
			local mouse = h.world:input("MouseButton1", Vector2.new(300, 300))
			h.uis.InputBegan:Fire(mouse, false)
			h.touchUp(h.touchDown(Vector2.new(300, 300)))
			h.uis.InputEnded:Fire(mouse, false)
			expect(taps).toBe(1)
		end)

		it("drops fingers that ended without an event", function()
			local h = setup()
			h.app:Open()
			local stale = h.touchDown(Vector2.new(200, 200))
			stale.UserInputState = World.Enum.UserInputState.End
			local finger = h.touchDown(Vector2.new(400, 400))
			h.touchMove(finger, Vector2.new(450, 400))
			expect(h.app.recognizer:GetGesture()).toBe("rotate")
			expect(h.app.recognizer:GetTouchCount()).toBe(1)
			h.touchUp(finger)
		end)

		it("forgets every finger when Studio loses focus", function()
			local h = setup()
			h.app:Open()
			h.touchDown(Vector2.new(200, 200))
			h.touchDown(Vector2.new(300, 200))
			h.uis.WindowFocusReleased:Fire()
			expect(h.app.recognizer:GetTouchCount()).toBe(0)
		end)

		it("recovers when Studio never reports the mouse release", function()
			local h = setup()
			h.app:Open()
			local mouse = h.world:input("MouseButton1", Vector2.new(300, 300))
			h.uis.InputBegan:Fire(mouse, false)
			h.uis.InputChanged:Fire(h.world:input("MouseMovement", Vector2.new(400, 300)), false)
			-- The release happened outside the viewport: no InputEnded.

			-- The next press still works and starts a fresh drag (no jump from the old position).
			local before = h.world.camera.CFrame
			local press = h.world:input("MouseButton1", Vector2.new(800, 300))
			h.uis.InputBegan:Fire(press, false)
			h.uis.InputChanged:Fire(h.world:input("MouseMovement", Vector2.new(830, 300)), false)
			h.uis.InputEnded:Fire(press, false)
			local turned =
				math.deg(math.acos(math.clamp(before.LookVector:Dot(h.world.camera.CFrame.LookVector), -1, 1)))
			expect(turned).toBeGreaterThan(1)
			expect(turned).toBeLessThan(15) -- 30 px of drag, not the 500 px jump to the old press
		end)

		it("stops a drag whose button is no longer held", function()
			local h = setup()
			h.app:Open()
			local mouse = h.world:input("MouseButton1", Vector2.new(300, 300))
			h.uis.InputBegan:Fire(mouse, false)
			h.uis.InputChanged:Fire(h.world:input("MouseMovement", Vector2.new(400, 300)), false)
			local cframe = h.world.camera.CFrame
			h.uis.mouseButton1Pressed = false
			h.uis.InputChanged:Fire(h.world:input("MouseMovement", Vector2.new(700, 300)), false)
			expect(h.world.camera.CFrame.Position).toBeCloseTo(cframe.Position)
			expect(h.app.recognizer:GetTouchCount()).toBe(0)
		end)

		it("restarts a finger whose InputObject begins again", function()
			local h = setup()
			h.app:Open()
			local finger = h.touchDown(Vector2.new(300, 300))
			h.touchMove(finger, Vector2.new(360, 300))
			-- Lost InputEnded, then the same object comes back for a new touch.
			finger.Position = Vector3.new(900, 300, 0)
			finger.UserInputState = World.Enum.UserInputState.Begin
			h.uis.InputBegan:Fire(finger, false)
			expect(h.app.recognizer:GetTouchCount()).toBe(1)
			expect(h.app.recognizer:GetMode()).toBe("pending")
		end)

		it("zooms with the edge strip: finger up moves in, down moves out", function()
			local h = setup()
			h.app:Open()
			local strip = h.world.coreGui.TouchPeak.TouchPeakZoomStrip
			expect(strip.Visible).toBe(true)
			local body = strip.Body
			local center = body.AbsolutePosition + body.AbsoluteSize / 2
			local distance = h.world.camera.CFrame.Position.Magnitude
			local look = h.world.camera.CFrame.LookVector

			local finger = h.world:input("Touch", center)
			body.InputBegan:Fire(finger)
			h.touchMove(finger, center - Vector2.new(0, 160))
			expect(h.world.camera.CFrame.Position.Magnitude).toBeCloseTo(distance * math.exp(-1), 0.05)
			h.touchMove(finger, center)
			expect(h.world.camera.CFrame.Position.Magnitude).toBeCloseTo(distance, 0.05)
			h.uis.InputEnded:Fire(finger, false)
			expect(h.world.camera.CFrame.LookVector).toBeCloseTo(look, 1e-4)
		end)

		it("does not rotate the camera when the strip is touched", function()
			local h = setup()
			h.app:Open()
			local body = h.world.coreGui.TouchPeak.TouchPeakZoomStrip.Body
			local center = body.AbsolutePosition + body.AbsoluteSize / 2
			local before = h.world.camera.CFrame
			local finger = h.touchDown(center)
			h.drag(finger, center, center + Vector2.new(300, 0))
			h.touchUp(finger)
			expect(h.world.camera.CFrame.LookVector).toBeCloseTo(before.LookVector, 1e-6)
		end)

		it("moves the strip to the other edge and hides it when asked", function()
			local h = setup()
			h.app:Open()
			local strip = h.world.coreGui.TouchPeak.TouchPeakZoomStrip
			expect(strip.AnchorPoint.X).toBe(0)
			h.app.settings:Set("zoomSide", "right")
			expect(strip.AnchorPoint.X).toBe(1)
			h.app:SetActive(false)
			expect(strip.Visible).toBe(false)
			h.app:SetActive(true)
			expect(strip.Visible).toBe(true)
			h.app.settings:Set("showZoomStrip", false)
			expect(strip.Visible).toBe(false)
		end)

		it("pans with tap-and-drag and keeps the selection", function()
			local h = setup()
			h.app:Open()
			local part = h.world:part({ Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(-12, 2, 0) })
			h.world.selection:Set({ part })
			local look = h.world.camera.CFrame.LookVector
			local position = h.world.camera.CFrame.Position
			local spot = World.ScreenSize / 2

			h.touchUp(h.touchDown(spot)) -- the tap alone would clear the selection
			local finger = h.touchDown(spot)
			h.drag(finger, spot, spot + Vector2.new(200, 0))
			h.touchUp(finger)

			expect(h.world.camera.CFrame.LookVector).toBeCloseTo(look, 1e-4)
			expect((h.world.camera.CFrame.Position - position).Magnitude).toBeGreaterThan(5)
			expect(h.world.selection:Get()[1]).toBe(part)
		end)

		it("zooms with Roblox's pinch event when raw fingers are missing", function()
			local h = setup()
			h.app:Open()
			local distance = h.world.camera.CFrame.Position.Magnitude
			local positions = { Vector2.new(600, 360), Vector2.new(680, 360) }
			local state = World.Enum.UserInputState
			h.uis.TouchPinch:Fire(positions, 1, 0, state.Begin, false)
			h.uis.TouchPinch:Fire(positions, 1.5, 0, state.Change, false)
			h.uis.TouchPinch:Fire(positions, 2, 0, state.Change, false)
			h.uis.TouchPinch:Fire(positions, 2, 0, state.End, false)
			expect(h.world.camera.CFrame.Position.Magnitude).toBeCloseTo(distance / 2, 0.5)
		end)

		local function diagnostic(world, title: string): string
			for _, row in world.coreGui.TouchPeak.TouchPeakPanel.Body.Content.Pages.Settings:GetChildren() do
				if row:FindFirstChild("Title") and row.Title.Text == title and row:FindFirstChild("Value") then
					return row.Value.Text
				end
			end
			error("no diagnostics row " .. title)
		end

		it("shows what Studio delivers in the diagnostics", function()
			local h = setup()
			h.app:Open()
			local a = h.touchDown(Vector2.new(300, 300))
			local b = h.touchDown(Vector2.new(500, 300))
			h.touchUp(a)
			h.touchUp(b)
			task.wait(0.35)
			expect(diagnostic(h.world, "Touch events")).toBe("4")
			expect(diagnostic(h.world, "Most fingers at once")).toBe("2")
			expect(diagnostic(h.world, "Last input")).toBe("touch")
		end)

		it("tells touch screen users once that Studio sends a mouse", function()
			local h = setup()
			h.app:Open()
			local mouse = h.world:input("MouseButton1", Vector2.new(300, 300))
			h.uis.InputBegan:Fire(mouse, false)
			expect(diagnostic(h.world, "Last input")).toBe("mouse")
			h.uis.InputChanged:Fire(h.world:input("MouseMovement", Vector2.new(400, 300)), false)
			h.uis.InputEnded:Fire(mouse, false)
			local notes = 0
			for _, label in h.world.coreGui.TouchPeak:GetDescendants() do
				if label:IsA("TextLabel") and string.find(label.Text, "Studio sees touch as a mouse", 1, true) then
					notes += 1
				end
			end
			expect(notes).toBe(1)
		end)

		it("ignores the mouse when the option is off", function()
			local h = setup()
			h.app.settings:Set("mouseInput", false)
			h.app:Open()
			local before = h.world.camera.CFrame.Position
			local mouse = h.world:input("MouseButton1", Vector2.new(300, 300))
			h.uis.InputBegan:Fire(mouse, false)
			h.uis.InputChanged:Fire(h.world:input("MouseMovement", Vector2.new(600, 300)), false)
			h.uis.InputEnded:Fire(mouse, false)
			expect(h.world.camera.CFrame.Position).toBeCloseTo(before)
		end)

		it("pauses from the window toggle and resumes", function()
			local h = setup()
			h.app:Open()
			h.app.panel._params.onActiveChanged(false)
			expect(h.plugin:IsActivated()).toBe(false)
			local before = h.world.camera.CFrame.Position
			local finger = h.touchDown(Vector2.new(400, 400))
			h.drag(finger, Vector2.new(400, 400), Vector2.new(700, 400))
			h.touchUp(finger)
			expect(h.world.camera.CFrame.Position).toBeCloseTo(before)
			expect(h.app:IsOpen()).toBe(true)

			h.app.panel._params.onActiveChanged(true)
			expect(h.plugin:IsActivated()).toBe(true)
		end)

		it("pauses when Studio switches to another tool", function()
			local h = setup()
			h.app:Open()
			-- Studio deactivates the plugin by itself.
			h.plugin._activated = false
			h.app:OnPluginDeactivated()
			local label = h.world.coreGui.TouchPeak.TouchPeakPanel.Body.Status.Label
			expect(label.Text).toBe("Paused")
			expect(h.app:IsOpen()).toBe(true)
		end)

		it("closes, and reopens expanded", function()
			local h = setup()
			h.app:Open()
			h.app.panel:SetCollapsed(true, true)
			h.app:Toggle()
			expect(h.app:IsOpen()).toBe(false)
			expect(h.plugin:IsActivated()).toBe(false)
			task.wait(0.3)
			expect(h.world.coreGui.TouchPeak.TouchPeakPanel.Visible).toBe(false)
			h.app:Toggle()
			expect(h.app.panel:IsCollapsed()).toBe(false)
			expect(h.world.coreGui.TouchPeak.TouchPeakPanel.Visible).toBe(true)
		end)

		it("rebuilds the window when the language changes", function()
			local h = setup()
			h.app:Open()
			h.app.settings:Set("language", "pl")
			task.wait(0.05)
			local label = h.world.coreGui.TouchPeak.TouchPeakPanel.Body.Status.Label
			expect(label.Text).toBe("Włączony")
			local panels = 0
			for _, child in h.world.coreGui.TouchPeak:GetChildren() do
				if child.Name == "TouchPeakPanel" then
					panels += 1
				end
			end
			expect(panels).toBe(1)
		end)

		it("starts from the toolbar button", function()
			local world = World.new()
			local plugin = world:plugin()
			world:runPlugin(plugin)
			local button = plugin.toolbars[1].buttons[1]
			expect(plugin.toolbars[1].name).toBe("Touch Peak")
			expect(button.text).toBe("Touch Peak")

			button.Click:Fire()
			expect(button.active).toBe(true)
			expect(plugin:IsActivated()).toBe(true)
			expect(world.coreGui.TouchPeak.TouchPeakPanel.Visible).toBe(true)

			-- Picking another Studio tool pauses touch controls but keeps the window.
			plugin._activated = false
			plugin.Deactivation:Fire()
			expect(button.active).toBe(true)
			expect(world.coreGui.TouchPeak.TouchPeakPanel.Body.Status.Label.Text).toBe("Paused")

			button.Click:Fire()
			expect(button.active).toBe(false)

			plugin.Unloading:Fire()
			expect(world.coreGui:FindFirstChild("TouchPeak")).toBe(nil)
		end)

		it("cleans everything up when the plugin unloads", function()
			local h = setup()
			h.app:Open()
			h.app:Destroy()
			expect(h.world.coreGui:FindFirstChild("TouchPeak")).toBe(nil)
			expect(h.plugin:IsActivated()).toBe(false)
			expect(h.uis.InputBegan:Count()).toBe(0)
		end)
	end)
end
