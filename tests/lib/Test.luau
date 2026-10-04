--[[
	A very small describe/it/expect test framework for Lune.
]]

local Test = {}

local results = { passed = 0, failed = 0, failures = {} }
local stack = {}

local function fullName(name: string): string
	local parts = table.clone(stack)
	table.insert(parts, name)
	return table.concat(parts, " › ")
end

function Test.describe(name: string, body: () -> ())
	table.insert(stack, name)
	body()
	table.remove(stack)
end

function Test.it(name: string, body: () -> ())
	local label = fullName(name)
	local ok, err = xpcall(body, debug.traceback)
	if ok then
		results.passed += 1
		print("  \27[32m✓\27[0m " .. label)
	else
		results.failed += 1
		table.insert(results.failures, { name = label, err = err })
		print("  \27[31m✗ " .. label .. "\27[0m")
	end
end

local function format(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function closeTo(a: any, b: any, tolerance: number): boolean
	local kind = typeof(a)
	if kind ~= typeof(b) then
		return false
	end
	if kind == "number" then
		return math.abs(a - b) <= tolerance
	elseif kind == "Vector2" or kind == "Vector3" then
		return (a - b).Magnitude <= tolerance
	end
	error("closeTo does not support " .. kind)
end

function Test.expect(actual: any)
	local expectation = {}

	function expectation.toBe(expected: any)
		if actual ~= expected then
			error(`expected {format(actual)} to be {format(expected)}`, 2)
		end
	end

	function expectation.never(expected: any)
		if actual == expected then
			error(`expected {format(actual)} not to be {format(expected)}`, 2)
		end
	end

	function expectation.toBeCloseTo(expected: any, tolerance: number?)
		if not closeTo(actual, expected, tolerance or 1e-3) then
			error(`expected {format(actual)} to be close to {format(expected)}`, 2)
		end
	end

	function expectation.toBeGreaterThan(expected: number)
		if not (actual > expected) then
			error(`expected {format(actual)} > {format(expected)}`, 2)
		end
	end

	function expectation.toBeLessThan(expected: number)
		if not (actual < expected) then
			error(`expected {format(actual)} < {format(expected)}`, 2)
		end
	end

	function expectation.toBeTruthy()
		if not actual then
			error(`expected {format(actual)} to be truthy`, 2)
		end
	end

	function expectation.toBeFalsy()
		if actual then
			error(`expected {format(actual)} to be falsy`, 2)
		end
	end

	return expectation
end

function Test.results()
	return results
end

return Test
