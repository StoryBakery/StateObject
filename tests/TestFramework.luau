local TestFramework = {}

type TestCase = {
	name: string,
	callback: () -> (),
}

local suites: { string } = {}
local tests: { TestCase } = {}

local function deepEqual(left: any, right: any, visited: { [table]: { [table]: boolean } }?): boolean
	if left == right then
		return true
	end

	if typeof(left) ~= typeof(right) then
		return false
	end

	if typeof(left) ~= "table" then
		return false
	end

	visited = visited or {}
	local leftVisited = visited[left]
	if leftVisited and leftVisited[right] then
		return true
	end

	if not leftVisited then
		leftVisited = {}
		visited[left] = leftVisited
	end
	leftVisited[right] = true

	for key, leftValue in left do
		if not deepEqual(leftValue, right[key], visited) then
			return false
		end
	end

	for key in right do
		if left[key] == nil then
			return false
		end
	end

	return true
end

local function getTestName(name: string): string
	if #suites == 0 then
		return name
	end

	return table.concat(suites, " > ") .. " > " .. name
end

function TestFramework.reset()
	table.clear(suites)
	table.clear(tests)
end

function TestFramework.describe(name: string, callback: () -> ())
	table.insert(suites, name)
	local ok, err = pcall(callback)
	table.remove(suites, #suites)

	if not ok then
		error(err)
	end
end

function TestFramework.it(name: string, callback: () -> ())
	table.insert(tests, {
		name = getTestName(name),
		callback = callback,
	})
end

function TestFramework.expect(actual: any)
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				error(
					("[ASSERT] toBe failed\nactual: %s\nexpected: %s"):format(tostring(actual), tostring(expected))
				)
			end
		end,
		toEqual = function(expected: any)
			if not deepEqual(actual, expected) then
				error(
					("[ASSERT] toEqual failed\nactual: %s\nexpected: %s"):format(tostring(actual), tostring(expected))
				)
			end
		end,
	}
end

function TestFramework.runAll()
	local passed = 0
	local failed = 0

	for _, testCase in tests do
		local ok, err = pcall(testCase.callback)
		if ok then
			passed += 1
			print(("[PASS] %s"):format(testCase.name))
		else
			failed += 1
			warn(("[FAIL] %s\n%s"):format(testCase.name, tostring(err)))
		end
	end

	return {
		total = #tests,
		passed = passed,
		failed = failed,
	}
end

return TestFramework
