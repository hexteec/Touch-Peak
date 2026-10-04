return function(t)
	local describe, it, expect, World = t.describe, t.it, t.expect, t.World
	local Vector2 = World.Vector2

	local EVENTS = {
		"InteractionBegan",
		"TouchCountChanged",
		"GestureChanged",
		"Rotate",
		"RotateEnded",
		"TwoFingerBegan",
		"Pan",
		"PanEnded",
		"Zoom",
		"Tap",
		"DoubleTap",
		"LongPress",
	}

	local function setup(options: { combine: boolean? }?)
		local world = World.new()
		local GestureRecognizer = world:require("Input/GestureRecognizer")

		local now = 0
		local scheduled = {}
		local recognizer = GestureRecognizer.new({
			clock = function()
				return now
			end,
			delay = function(seconds, callback)
				table.insert(scheduled, { at = now + seconds, callback = callback })
			end,
		})
		recognizer:SetCombine(options and options.combine or false)

		local log = {}
		for _, name in EVENTS do
			recognizer[name]:Connect(function(...)
				table.insert(log, { name = name, args = table.pack(...) })
			end)
		end

		local h = { recognizer = recognizer, log = log }

		function h.advance(seconds: number)
			now += seconds
			local due = {}
			for index = #scheduled, 1, -1 do
				if scheduled[index].at <= now then
					table.insert(due, 1, table.remove(scheduled, index))
				end
			end
			for _, entry in due do
				entry.callback()
			end
		end

		function h.events(name: string)
			local out = {}
			for _, entry in log do
				if entry.name == name then
					table.insert(out, entry.args)
				end
			end
			return out
		end

		function h.count(name: string): number
			return #h.events(name)
		end

		function h.sum(name: string): Vector2
			local total = Vector2.zero
			for _, args in h.events(name) do
				total += args[1]
			end
			return total
		end

		function h.product(name: string): number
			local total = 1
			for _, args in h.events(name) do
				total *= args[1]
			end
			return total
		end

		-- Moves a finger in `steps` evenly spaced events, `dt` seconds apart.
		function h.drag(id, from: Vector2, to: Vector2, steps: number, dt: number)
			for step = 1, steps do
				h.advance(dt)
				recognizer:TouchMoved(id, from:Lerp(to, step / steps))
			end
		end

		return h
	end

	describe("GestureRecognizer", function()
		describe("taps", function()
			it("fires Tap for a quick touch without movement", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(100, 100))
				h.advance(0.1)
				h.recognizer:TouchEnded("a")
				expect(h.count("Tap")).toBe(1)
				expect(h.events("Tap")[1][1]).toBeCloseTo(Vector2.new(100, 100))
				expect(h.count("Rotate")).toBe(0)
				expect(h.recognizer:GetMode()).toBe("idle")
			end)

			it("tolerates a little finger drift", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(100, 100))
				h.recognizer:TouchMoved("a", Vector2.new(106, 103))
				h.recognizer:TouchEnded("a")
				expect(h.count("Tap")).toBe(1)
				expect(h.count("Rotate")).toBe(0)
			end)

			it("turns a second quick tap into a DoubleTap", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(100, 100))
				h.advance(0.08)
				h.recognizer:TouchEnded("a")
				h.advance(0.12)
				h.recognizer:TouchBegan("b", Vector2.new(110, 104))
				h.advance(0.08)
				h.recognizer:TouchEnded("b")
				expect(h.count("Tap")).toBe(1)
				expect(h.count("DoubleTap")).toBe(1)
			end)

			it("keeps far apart or slow taps as separate taps", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(100, 100))
				h.recognizer:TouchEnded("a")
				h.recognizer:TouchBegan("b", Vector2.new(400, 100))
				h.recognizer:TouchEnded("b")
				h.advance(1)
				h.recognizer:TouchBegan("c", Vector2.new(400, 100))
				h.recognizer:TouchEnded("c")
				expect(h.count("Tap")).toBe(3)
				expect(h.count("DoubleTap")).toBe(0)
			end)
		end)

		describe("long press", function()
			it("fires after holding still and suppresses the tap", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(50, 60))
				h.advance(0.3)
				expect(h.count("LongPress")).toBe(0)
				h.advance(0.3)
				expect(h.count("LongPress")).toBe(1)
				-- Moving afterwards must not rotate the camera.
				h.recognizer:TouchMoved("a", Vector2.new(200, 60))
				h.recognizer:TouchEnded("a")
				expect(h.count("Tap")).toBe(0)
				expect(h.count("Rotate")).toBe(0)
				expect(h.recognizer:GetMode()).toBe("idle")
			end)

			it("is cancelled by dragging", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(50, 60))
				h.drag("a", Vector2.new(50, 60), Vector2.new(150, 60), 5, 0.02)
				h.advance(1)
				expect(h.count("LongPress")).toBe(0)
			end)

			it("is cancelled by lifting the finger", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(50, 60))
				h.advance(0.2)
				h.recognizer:TouchEnded("a")
				h.recognizer:TouchBegan("b", Vector2.new(50, 60))
				h.advance(0.4) -- the first timer is due now, but belongs to the old finger
				expect(h.count("LongPress")).toBe(0)
			end)
		end)

		describe("one finger rotation", function()
			it("reports the whole movement, including the tap slop", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(100, 100))
				h.drag("a", Vector2.new(100, 100), Vector2.new(300, 160), 10, 1 / 60)
				expect(h.sum("Rotate")).toBeCloseTo(Vector2.new(200, 60))
				expect(h.recognizer:GetGesture()).toBe("rotate")
			end)

			it("releases with a velocity for inertia", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(0, 0))
				h.drag("a", Vector2.new(0, 0), Vector2.new(600, 0), 30, 1 / 60) -- 1200 px/s
				h.recognizer:TouchEnded("a")
				local velocity = h.events("RotateEnded")[1][1]
				expect(velocity.X).toBeCloseTo(1200, 1)
				expect(velocity.Y).toBeCloseTo(0, 1e-6)
				expect(h.recognizer:GetGesture()).toBe(nil)
			end)

			it("releases with no velocity after holding still", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(0, 0))
				h.drag("a", Vector2.new(0, 0), Vector2.new(300, 0), 10, 1 / 60)
				h.advance(0.3)
				h.recognizer:TouchEnded("a")
				expect(h.events("RotateEnded")[1][1]).toBeCloseTo(Vector2.zero)
			end)
		end)

		describe("two fingers", function()
			it("zooms when the fingers spread apart", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(400, 300))
				h.recognizer:TouchBegan("b", Vector2.new(500, 300))
				expect(h.count("TwoFingerBegan")).toBe(1)
				for step = 1, 10 do
					h.advance(1 / 60)
					h.recognizer:TouchMoved("a", Vector2.new(400 - step * 5, 300))
					h.recognizer:TouchMoved("b", Vector2.new(500 + step * 5, 300))
					h.recognizer:Flush()
				end
				expect(h.recognizer:GetGesture()).toBe("zoom")
				-- 100 px apart -> 200 px apart: the scale halves the distance to the target.
				expect(h.product("Zoom")).toBeCloseTo(0.5)
				expect(h.count("Pan")).toBe(0)
				expect(h.count("Tap")).toBe(0)
			end)

			it("pans when both fingers move the same way", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(400, 300))
				h.recognizer:TouchBegan("b", Vector2.new(500, 300))
				for step = 1, 10 do
					h.advance(1 / 60)
					h.recognizer:TouchMoved("a", Vector2.new(400 + step * 8, 300 + step * 3))
					h.recognizer:TouchMoved("b", Vector2.new(500 + step * 8, 300 + step * 3))
					h.recognizer:Flush()
				end
				h.recognizer:TouchEnded("a")
				h.recognizer:TouchEnded("b")
				expect(h.sum("Pan")).toBeCloseTo(Vector2.new(80, 30))
				expect(h.count("Zoom")).toBe(0)
				expect(h.count("PanEnded")).toBe(1)
				expect(h.events("PanEnded")[1][1].Magnitude).toBeGreaterThan(100)
			end)

			it("does both at once in combined mode", function()
				local h = setup({ combine = true })
				h.recognizer:TouchBegan("a", Vector2.new(400, 300))
				h.recognizer:TouchBegan("b", Vector2.new(500, 300))
				for step = 1, 10 do
					h.recognizer:TouchMoved("a", Vector2.new(400 - step * 5, 300 + step * 4))
					h.recognizer:TouchMoved("b", Vector2.new(500 + step * 5, 300 + step * 4))
					h.recognizer:Flush()
				end
				expect(h.recognizer:GetGesture()).toBe("both")
				-- One zoom step per frame: no in/out wobble between the two finger events.
				expect(h.count("Zoom")).toBe(10)
				expect(h.product("Zoom")).toBeCloseTo(0.5)
				expect(h.sum("Pan")).toBeCloseTo(Vector2.new(0, 40))
			end)

			it("ignores the remaining finger after the gesture", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(400, 300))
				h.recognizer:TouchBegan("b", Vector2.new(500, 300))
				h.recognizer:TouchMoved("b", Vector2.new(560, 300))
				h.recognizer:TouchEnded("b")
				h.recognizer:TouchMoved("a", Vector2.new(100, 100))
				expect(h.count("Rotate")).toBe(0)
				h.recognizer:TouchEnded("a")
				expect(h.count("Tap")).toBe(0)
				expect(h.recognizer:GetMode()).toBe("idle")

				-- And the next gesture works normally.
				h.recognizer:TouchBegan("c", Vector2.new(100, 100))
				h.recognizer:TouchMoved("c", Vector2.new(150, 100))
				expect(h.count("Rotate")).toBe(1)
			end)

			it("switches from rotating to two fingers without rotating further", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(100, 100))
				h.recognizer:TouchMoved("a", Vector2.new(140, 100))
				expect(h.recognizer:GetGesture()).toBe("rotate")
				h.recognizer:TouchBegan("b", Vector2.new(300, 100))
				expect(h.recognizer:GetGesture()).toBe(nil)
				h.recognizer:TouchMoved("a", Vector2.new(120, 100))
				h.recognizer:TouchMoved("b", Vector2.new(320, 100))
				expect(h.count("Rotate")).toBe(1)
				expect(h.count("RotateEnded")).toBe(0)
			end)

			it("does not mistake a fast pan reported finger by finger for a pinch", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(400, 300))
				h.recognizer:TouchBegan("b", Vector2.new(500, 300))
				for step = 1, 6 do
					h.advance(1 / 60)
					-- 30 px per frame: the first finger alone looks like a big pinch.
					h.recognizer:TouchMoved("a", Vector2.new(400 + step * 30, 300))
					h.recognizer:TouchMoved("b", Vector2.new(500 + step * 30, 300))
					h.recognizer:Flush()
				end
				expect(h.recognizer:GetGesture()).toBe("pan")
				expect(h.count("Zoom")).toBe(0)
				expect(h.sum("Pan")).toBeCloseTo(Vector2.new(180, 0))
			end)

			it("still applies movement when nobody calls Flush", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(400, 300))
				h.recognizer:TouchBegan("b", Vector2.new(500, 300))
				h.recognizer:TouchMoved("b", Vector2.new(540, 300))
				expect(h.count("Zoom")).toBe(0)
				h.advance(0.06)
				h.recognizer:TouchMoved("b", Vector2.new(560, 300))
				expect(h.count("Zoom")).toBe(1)
				expect(h.product("Zoom")).toBeCloseTo(100 / 160)
			end)

			it("waits until the movement is clear before choosing", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(400, 300))
				h.recognizer:TouchBegan("b", Vector2.new(500, 300))
				h.recognizer:TouchMoved("a", Vector2.new(403, 300))
				h.recognizer:Flush()
				expect(h.recognizer:GetGesture()).toBe(nil)
				expect(h.count("Zoom") + h.count("Pan")).toBe(0)
			end)
		end)

		describe("finger bookkeeping", function()
			it("counts every finger, but tracks only two", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(100, 100))
				h.recognizer:TouchBegan("b", Vector2.new(200, 100))
				h.recognizer:TouchBegan("c", Vector2.new(300, 100))
				expect(h.recognizer:GetTouchCount()).toBe(3)
				h.recognizer:TouchMoved("c", Vector2.new(600, 400))
				expect(h.count("Pan") + h.count("Zoom")).toBe(0)
				h.recognizer:TouchEnded("c")
				h.recognizer:TouchEnded("b")
				h.recognizer:TouchEnded("a")
				expect(h.recognizer:GetTouchCount()).toBe(0)
				expect(h.recognizer:GetMode()).toBe("idle")
			end)

			it("ignores unknown fingers and duplicate events", function()
				local h = setup()
				h.recognizer:TouchMoved("ghost", Vector2.new(1, 1))
				h.recognizer:TouchEnded("ghost")
				h.recognizer:TouchBegan("a", Vector2.new(100, 100))
				h.recognizer:TouchBegan("a", Vector2.new(100, 100))
				expect(h.recognizer:GetTouchCount()).toBe(1)
				expect(h.count("InteractionBegan")).toBe(1)
			end)

			it("forgets everything on Cancel", function()
				local h = setup()
				h.recognizer:TouchBegan("a", Vector2.new(100, 100))
				h.recognizer:TouchMoved("a", Vector2.new(200, 100))
				h.recognizer:Cancel()
				expect(h.recognizer:GetTouchCount()).toBe(0)
				expect(h.recognizer:GetGesture()).toBe(nil)
				expect(h.recognizer:GetMode()).toBe("idle")
				h.advance(1)
				expect(h.count("LongPress")).toBe(0)
			end)
		end)
	end)
end
