return function(t)
	local describe, it, expect, World = t.describe, t.it, t.expect, t.World
	local Vector2, Vector3, CFrame = World.Vector2, World.Vector3, World.CFrame

	local CENTER = World.ScreenSize / 2

	local function setup(overrides: { [string]: any }?)
		local world = World.new()
		world.groundPlane = true
		local Settings = world:require("Settings")
		local CameraController = world:require("Camera/CameraController")
		local settings = Settings.new(nil)
		for key, value in overrides or {} do
			settings:Set(key, value)
		end
		local camera = world.camera
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 30, 40), Vector3.new(0, 0, 0))
		return world, CameraController.new(settings), camera, settings
	end

	local function screenPoint(camera, point: Vector3): Vector2
		local projected = camera:WorldToViewportPoint(point)
		return Vector2.new(projected.X, projected.Y)
	end

	local function pitchOf(cframe): number
		return math.deg(math.asin(cframe.LookVector.Y))
	end

	describe("CameraController", function()
		describe("rotation", function()
			it("orbits around the point in the middle of the screen", function()
				local _, controller, camera = setup()
				local distance = camera.CFrame.Position.Magnitude
				controller:BeginInteraction()
				controller:Rotate(Vector2.new(120, 0))
				controller:Rotate(Vector2.new(80, -40))

				expect(camera.CFrame.Position.Magnitude).toBeCloseTo(distance, 1e-3)
				-- Still looking straight at the origin.
				expect(screenPoint(camera, Vector3.zero)).toBeCloseTo(CENTER, 1e-2)
				expect(camera.Focus.Position).toBeCloseTo(Vector3.zero, 1e-3)
			end)

			it("moves the scene with the finger", function()
				local _, controller, camera = setup()
				-- A point on the side of the pivot that faces the camera.
				local marker = Vector3.new(0, 0, 10)
				local before = screenPoint(camera, marker)
				controller:Rotate(Vector2.new(60, 0))
				-- Dragging right turns the scene right: its near side follows the finger.
				expect(screenPoint(camera, marker).X).toBeGreaterThan(before.X + 20)
				-- The camera itself travelled to its left.
				expect(camera.CFrame.Position.X).toBeLessThan(0)
			end)

			it("can be inverted", function()
				local _, controller, camera = setup({ invertRotate = true })
				controller:Rotate(Vector2.new(60, 0))
				expect(camera.CFrame.Position.X).toBeGreaterThan(0)
			end)

			it("clamps the pitch and never rolls the camera", function()
				local _, controller, camera = setup()
				controller:Rotate(Vector2.new(0, 5000))
				expect(pitchOf(camera.CFrame)).toBeCloseTo(-88, 1e-2)
				controller:Rotate(Vector2.new(0, -10000))
				expect(pitchOf(camera.CFrame)).toBeCloseTo(88, 1e-2)
				for _ = 1, 20 do
					controller:Rotate(Vector2.new(37, -23))
				end
				expect(math.abs(camera.CFrame.RightVector.Y)).toBeLessThan(1e-4)
				expect(camera.CFrame.UpVector.Y).toBeGreaterThan(0)
			end)

			it("turns in place in look mode", function()
				local _, controller, camera = setup({ rotateMode = "look" })
				local position = camera.CFrame.Position
				controller:Rotate(Vector2.new(200, 50))
				expect(camera.CFrame.Position).toBeCloseTo(position, 1e-4)
				-- Like Studio's right-drag: dragging right turns the view right.
				expect(screenPoint(camera, Vector3.zero).X).toBeLessThan(CENTER.X - 50)
			end)

			it("picks a new pivot when something else moved the camera", function()
				local _, controller, camera = setup()
				controller:Rotate(Vector2.new(10, 0))
				-- Studio's own controls move the camera elsewhere.
				camera.CFrame = CFrame.lookAt(Vector3.new(100, 20, 0), Vector3.new(100, 0, -20))
				controller:Rotate(Vector2.new(50, 0))
				expect(screenPoint(camera, Vector3.new(100, 0, -20))).toBeCloseTo(CENTER, 1e-2)
			end)

			it("orbits a point in the air when looking at the sky", function()
				local world, controller, camera = setup()
				world.groundPlane = false
				camera.CFrame = CFrame.lookAt(Vector3.new(0, 10, 0), Vector3.new(0, 10, -10))
				camera.Focus = CFrame.new(0, 0, 0) -- behind / off axis: ignored
				controller:Rotate(Vector2.new(100, 0))
				local pivot = Vector3.new(0, 10, -40)
				expect((camera.CFrame.Position - pivot).Magnitude).toBeCloseTo(40, 1e-3)
			end)
		end)

		describe("panning", function()
			it("keeps the grabbed point under the fingers", function()
				local _, controller, camera = setup()
				local grab = Vector2.new(800, 500)
				local ray = camera:ScreenPointToRay(grab.X, grab.Y)
				local point = ray.Origin + ray.Direction * (-ray.Origin.Y / ray.Direction.Y)

				controller:BeginTwoFinger(grab)
				controller:Pan(Vector2.new(-120, 0))
				-- A pure sideways pan moves the point by exactly the finger movement.
				expect(screenPoint(camera, point)).toBeCloseTo(grab + Vector2.new(-120, 0), 0.5)
			end)

			it("can be inverted so the camera flies with the fingers", function()
				local _, controller, camera = setup({ invertPan = true })
				local before = camera.CFrame.Position
				controller:BeginTwoFinger(CENTER)
				controller:Pan(Vector2.new(100, 0))
				expect(camera.CFrame.Position.X).toBeGreaterThan(before.X)
			end)

			it("carries the orbit pivot along", function()
				local _, controller, camera = setup()
				local before = camera.CFrame.Position
				controller:BeginTwoFinger(CENTER)
				controller:Pan(Vector2.new(70, -40))
				local pivot = camera.CFrame.Position - before -- the origin, moved with the camera

				controller:BeginInteraction()
				local distance = (camera.CFrame.Position - pivot).Magnitude
				controller:Rotate(Vector2.new(90, 20))
				expect((camera.CFrame.Position - pivot).Magnitude).toBeCloseTo(distance, 1e-3)
				expect(screenPoint(camera, pivot)).toBeCloseTo(CENTER, 1e-2)
			end)
		end)

		describe("zooming", function()
			it("moves toward the point between the fingers", function()
				local _, controller, camera = setup()
				local pinch = Vector2.new(900, 450)
				local ray = camera:ScreenPointToRay(pinch.X, pinch.Y)
				local target = ray.Origin + ray.Direction * (-ray.Origin.Y / ray.Direction.Y)
				local distance = (target - camera.CFrame.Position).Magnitude

				controller:BeginTwoFinger(pinch)
				controller:Zoom(0.5, pinch)
				expect((target - camera.CFrame.Position).Magnitude).toBeCloseTo(distance / 2, 1e-3)
				-- The target stays under the fingers.
				expect(screenPoint(camera, target)).toBeCloseTo(pinch, 0.5)
			end)

			it("zooms out with a scale above one", function()
				local _, controller, camera = setup()
				local distance = camera.CFrame.Position.Magnitude
				controller:BeginTwoFinger(CENTER)
				controller:Zoom(2, CENTER)
				expect(camera.CFrame.Position.Magnitude).toBeCloseTo(distance * 2, 1e-3)
			end)

			it("respects the zoom sensitivity", function()
				local _, controller, camera = setup({ zoomSensitivity = 2 })
				local distance = camera.CFrame.Position.Magnitude
				controller:BeginTwoFinger(CENTER)
				controller:Zoom(0.5, CENTER)
				expect(camera.CFrame.Position.Magnitude).toBeCloseTo(distance / 4, 1e-3)
			end)

			it("flies through surfaces when zooming in very close", function()
				local _, controller, camera = setup()
				camera.CFrame = CFrame.lookAt(Vector3.new(0, 10, 0), Vector3.new(0, 0, 0) + Vector3.new(0, 0, -0.001))
				controller:BeginTwoFinger(CENTER)
				for _ = 1, 40 do
					controller:Zoom(0.8, CENTER)
				end
				-- The camera passed below the ground plane instead of stopping above it.
				expect(camera.CFrame.Position.Y).toBeLessThan(0)
			end)
		end)

		describe("focus and inertia", function()
			it("frames an object smoothly and orbits around it afterwards", function()
				local world, controller, camera = setup()
				local part = world:part({
					Size = Vector3.new(4, 4, 4),
					CFrame = CFrame.new(30, 2, -10),
				})
				local look = camera.CFrame.LookVector
				expect(controller:FocusOn({ part })).toBe(true)
				for _ = 1, 40 do
					controller:Step(1 / 60)
				end
				expect(controller:IsAnimating()).toBe(false)
				expect(camera.CFrame.LookVector).toBeCloseTo(look, 1e-4)
				expect(screenPoint(camera, Vector3.new(30, 2, -10))).toBeCloseTo(CENTER, 1e-2)

				local distance = (camera.CFrame.Position - Vector3.new(30, 2, -10)).Magnitude
				controller:BeginInteraction()
				controller:Rotate(Vector2.new(150, 30))
				expect((camera.CFrame.Position - Vector3.new(30, 2, -10)).Magnitude).toBeCloseTo(distance, 1e-3)
			end)

			it("frames whole models", function()
				local world, controller, camera = setup()
				local model = world:model("House")
				world:part({ Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(-20, 1, 0), Parent = model })
				world:part({ Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(-10, 1, 0), Parent = model })
				controller:FocusOn({ model })
				for _ = 1, 40 do
					controller:Step(1 / 60)
				end
				expect(screenPoint(camera, Vector3.new(-15, 1, 0))).toBeCloseTo(CENTER, 1e-2)
			end)

			it("returns false when there is nothing to frame", function()
				local world, controller = setup()
				expect(controller:FocusOn({})).toBe(false)
				expect(controller:FocusOn({ world.terrain })).toBe(false)
			end)

			it("keeps gliding after a flick and then stops", function()
				local _, controller, camera = setup()
				controller:Rotate(Vector2.new(1, 0))
				local start = camera.CFrame
				controller:StartInertia("rotate", Vector2.new(1500, 0))
				controller:Step(1 / 60)
				expect(camera.CFrame.Position).never(start.Position)
				for _ = 1, 300 do
					controller:Step(1 / 60)
				end
				expect(controller:IsAnimating()).toBe(false)
			end)

			it("ignores slow releases and respects the inertia setting", function()
				local _, controller = setup()
				controller:StartInertia("pan", Vector2.new(20, 0))
				expect(controller:IsAnimating()).toBe(false)
				local _, noInertia = setup({ inertia = false })
				noInertia:StartInertia("rotate", Vector2.new(2000, 0))
				expect(noInertia:IsAnimating()).toBe(false)
			end)

			it("stops animating when Studio moves the camera", function()
				local _, controller, camera = setup()
				controller:Rotate(Vector2.new(1, 0))
				controller:StartInertia("rotate", Vector2.new(1500, 0))
				camera.CFrame = CFrame.new(0, 50, 0)
				controller:Step(1 / 60)
				expect(controller:IsAnimating()).toBe(false)
				expect(camera.CFrame.Position).toBeCloseTo(Vector3.new(0, 50, 0))
			end)
		end)
	end)
end
