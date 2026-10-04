--[[
	Test runner: `lune run tests/run` from the repository root.
]]

local process = require("@lune/process")

local Test = require("./lib/Test")
local World = require("./lib/World")

local SPECS = {
	"GestureRecognizer",
	"CameraController",
	"SelectionController",
	"Settings",
	"Interface",
	"App",
}

local context = {
	describe = Test.describe,
	it = Test.it,
	expect = Test.expect,
	World = World,
}

for _, name in SPECS do
	print("\n" .. name)
	local spec = require(`./specs/{name}.spec`)
	spec(context)
end

local results = Test.results()
print(string.format("\n%d passed, %d failed", results.passed, results.failed))
for _, failure in results.failures do
	print("\n\27[31m" .. failure.name .. "\27[0m\n" .. tostring(failure.err))
end

process.exit(if results.failed == 0 then 0 else 1)
