--[[
	커스텀 테스트 러너 엔트리 모듈입니다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local testsRoot = ReplicatedStorage:WaitForChild("Tests")
local specsRoot = testsRoot:WaitForChild("specs")
local TestFramework = require(testsRoot:WaitForChild("TestFramework"))

local function collectSpecModules(root: Instance): { ModuleScript }
	local modules = {}

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ModuleScript") and string.find(descendant.Name, ".spec", 1, true) ~= nil then
			table.insert(modules, descendant)
		end
	end

	table.sort(modules, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)

	return modules
end

local function loadSpecs(specModules: { ModuleScript })
	local loadErrors = {}

	for _, specModule in specModules do
		local ok, err = pcall(require, specModule)
		if not ok then
			table.insert(loadErrors, ("[%s] %s"):format(specModule:GetFullName(), tostring(err)))
		end
	end

	if #loadErrors > 0 then
		error("[TEST] spec load failed\n" .. table.concat(loadErrors, "\n"))
	end
end

TestFramework.reset()
local specModules = collectSpecModules(specsRoot)
loadSpecs(specModules)

local result = TestFramework.runAll()
print(("[TEST] total=%d passed=%d failed=%d"):format(result.total, result.passed, result.failed))

if result.failed > 0 then
	error("[TEST] custom tests failed")
end

print("[TEST] All custom tests passed")
return true
