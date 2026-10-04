return function(t)
	local describe, it, expect, World = t.describe, t.it, t.expect, t.World
	local Vector2, Vector3, CFrame = World.Vector2, World.Vector3, World.CFrame

	local function setup(overrides: { [string]: any }?)
		local world = World.new()
		world.groundPlane = true
		local Settings = world:require("Settings")
		local SelectionController = world:require("Selection/SelectionController")
		local settings = Settings.new(nil)
		for key, value in overrides or {} do
			settings:Set(key, value)
		end
		world.camera.CFrame = CFrame.lookAt(Vector3.new(0, 10, 30), Vector3.new(0, 2, 0))
		return world, SelectionController.new(settings)
	end

	local function screenOf(world, point: Vector3): Vector2
		local projected = world.camera:WorldToViewportPoint(point)
		return Vector2.new(projected.X, projected.Y)
	end

	local function selected(world)
		return world.selection:Get()
	end

	describe("SelectionController", function()
		it("selects a loose part", function()
			local world, controller = setup()
			local part = world:part({ Name = "Crate", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(0, 2, 0) })
			expect(controller:SelectAt(screenOf(world, Vector3.new(0, 2, 0)))).toBe(part)
			expect(selected(world)[1]).toBe(part)
			expect(#selected(world)).toBe(1)
		end)

		it("selects the outermost model, like Studio", function()
			local world, controller = setup()
			local folder = world.newInstance("Folder")
			folder.Parent = world.workspace
			local house = world:model("House", folder)
			local door = world:model("Door", house)
			world:part({ Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(0, 2, 0), Parent = door })
			expect(controller:SelectAt(screenOf(world, Vector3.new(0, 2, 0)))).toBe(house)
		end)

		it("selects the part itself when model selection is off", function()
			local world, controller = setup({ selectModels = false })
			local house = world:model("House")
			local part = world:part({ Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(0, 2, 0), Parent = house })
			expect(controller:SelectAt(screenOf(world, Vector3.new(0, 2, 0)))).toBe(part)
		end)

		it("clears the selection when tapping terrain or empty space", function()
			local world, controller = setup()
			local part = world:part({ Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(0, 2, 0) })
			world.selection:Set({ part })
			expect(controller:SelectAt(Vector2.new(5, 5))).toBe(nil)
			expect(#selected(world)).toBe(0)
			world.selection:Set({ part })
			expect(controller:SelectAt(screenOf(world, Vector3.new(15, 0, 5)))).toBe(nil)
			expect(#selected(world)).toBe(0)
		end)

		it("looks through locked and invisible parts", function()
			local world, controller = setup()
			world:part({ Name = "Glass", Size = Vector3.new(20, 20, 1), CFrame = CFrame.new(0, 2, 10), Locked = true })
			world:part({ Name = "Ghost", Size = Vector3.new(20, 20, 1), CFrame = CFrame.new(0, 2, 6), Transparency = 1 })
			local target = world:part({ Name = "Target", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(0, 2, 0) })
			expect(controller:SelectAt(screenOf(world, Vector3.new(0, 2, 0)))).toBe(target)
		end)

		it("adds and removes with a long press", function()
			local world, controller = setup()
			local a = world:part({ Name = "A", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(-4, 1, 0) })
			local b = world:part({ Name = "B", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(4, 1, 0) })
			world.selection:Set({ a })

			local target, added = controller:ToggleAt(screenOf(world, Vector3.new(4, 1, 0)))
			expect(target).toBe(b)
			expect(added).toBe(true)
			expect(#selected(world)).toBe(2)

			target, added = controller:ToggleAt(screenOf(world, Vector3.new(-4, 1, 0)))
			expect(target).toBe(a)
			expect(added).toBe(false)
			expect(#selected(world)).toBe(1)
			expect(selected(world)[1]).toBe(b)
		end)

		it("leaves the selection alone when long pressing empty space", function()
			local world, controller = setup()
			local a = world:part({ Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(0, 1, 0) })
			world.selection:Set({ a })
			local target = controller:ToggleAt(Vector2.new(5, 5))
			expect(target).toBe(nil)
			expect(#selected(world)).toBe(1)
		end)
	end)
end
