local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tests = ReplicatedStorage:WaitForChild("Tests")

local TestFramework = require(Tests:WaitForChild("TestFramework"))
local describe = TestFramework.describe
local expect = TestFramework.expect
local it = TestFramework.it

local StateObject = require(ReplicatedStorage:WaitForChild("StateObject"))
local SaveUtil = StateObject.SaveUtil

describe("StateObject", function()
	it("supports get/set/update after fromDefaultValuesByKey", function()
		local state = StateObject.fromDefaultValuesByKey({
			Health = 100,
			Name = "Player",
		})

		expect(state:Get("Health")).toBe(100)
		expect(state:Get("Name")).toBe("Player")

		state:Set("Health", 120)
		state:Update("Health", function(value)
			return value + 1
		end)

		expect(state:Get("Health")).toBe(121)
		expect(StateObject.IsStateObject(state)).toBe(true)
		expect(StateObject.IsStateObject({})).toBe(false)
	end)

	it("fires change signals immediately in Immediate mode", function()
		local state = StateObject.new({
			Health = {
				Default = 100,
			},
		}, {
			ChangedBehavior = "Immediate",
		})

		local perKeySignals = {}
		local objectSignals = {}

		state:GetChangedSignal("Health"):Connect(function(newValue)
			table.insert(perKeySignals, newValue)
		end)

		state.Changed:Connect(function(key, value)
			table.insert(objectSignals, { key, value })
		end)

		state:Set("Health", 130)

		expect(perKeySignals).toEqual({ 130 })
		expect(#objectSignals).toBe(1)
		expect(objectSignals[1][1]).toBe("Health")
		expect(objectSignals[1][2]).toBe(130)
	end)

	it("emits only the final value for multiple sets in Deferred mode", function()
		local state = StateObject.new({
			Score = {
				Default = 0,
			},
		}, {
			ChangedBehavior = "Deferred",
		})

		local signalValues = {}
		state:GetChangedSignal("Score"):Connect(function(newValue)
			table.insert(signalValues, newValue)
		end)

		state:Set("Score", 1)
		state:Set("Score", 2)
		state:Set("Score", 3)

		task.wait()

		expect(signalValues).toEqual({ 3 })
		expect(state:Get("Score")).toBe(3)
	end)

	it("observe emits both current and subsequent values", function()
		local state = StateObject.new({
			Mode = {
				Default = "Idle",
			},
		}, {
			ChangedBehavior = "Immediate",
		})

		local observedValues = {}
		local conn = state:Observe("Mode", function(value)
			table.insert(observedValues, value)
		end)

		task.wait()
		state:Set("Mode", "Run")
		task.wait()

		conn:Disconnect()

		expect(observedValues[1]).toBe("Idle")
		expect(observedValues[2]).toBe("Run")
	end)

	it("clone copies table values and metadata independently", function()
		local source = StateObject.new({
			Data = {
				Default = { Count = 1 },
				Metadata = { Tag = "Original" },
			},
		}, {
			ChangedBehavior = "Immediate",
		})

		source:Set("Data", { Count = 5 })

		local clone = source:Clone()
		local cloneData = clone:Get("Data")
		local sourceData = source:Get("Data")

		expect(cloneData).toEqual({ Count = 5 })
		expect(sourceData).toEqual({ Count = 5 })

		cloneData.Count = 99
		expect(source:Get("Data").Count).toBe(5)

		local cloneMetadata = clone:GetStateMetadata("Data")
		cloneMetadata.Tag = "ChangedInClone"
		expect(source:GetStateMetadata("Data").Tag).toBe("Original")
	end)
end)

describe("StateObject.SaveUtil", function()
	it("serializes and deserializes table values", function()
		local stateInfo = {
			Default = {
				Position = Vector3.new(0, 0, 0),
				Enabled = true,
			},
		}

		local original = {
			Position = Vector3.new(10, 20, 30),
			Enabled = false,
		}

		local encoded = SaveUtil.EncodeValue(original, stateInfo)
		local decoded = SaveUtil.DecodeValue(encoded, stateInfo)

		expect(decoded.Position).toBe(original.Position)
		expect(decoded.Enabled).toBe(false)
	end)

	it("serializes instance path when IsInstance metadata is set", function()
		local folder = Instance.new("Folder")
		folder.Name = "StateObject_SaveUtil_InstancePath_Test"
		folder.Parent = workspace

		local stateInfo = {
			Default = nil,
			Metadata = {
				IsInstance = true,
			},
		}

		local encoded = SaveUtil.EncodeValue(folder, stateInfo)
		local decoded = SaveUtil.DecodeValue(encoded, stateInfo)

		expect(typeof(encoded)).toBe("string")
		expect(decoded).toBe(folder)

		folder:Destroy()
	end)

	it("syncs state and instance attributes bidirectionally", function()
		local state = StateObject.new({
			Health = {
				Default = 100,
			},
				LocalOnly = {
					Default = "Secret",
					Metadata = {
						AttributeSyncEnabled = false,
					},
				},
		}, {
			ChangedBehavior = "Immediate",
		})

		local target = Instance.new("Folder")
		target.Name = "StateObject_SaveUtil_Bind_Test"
		target.Parent = workspace

		local disconnect = SaveUtil.BindStateObjectAndInstanceAttributes(state, target)

		expect(target:GetAttribute("Health")).toBe(100)
		expect(target:GetAttribute("LocalOnly")).toBe(nil)

		state:Set("Health", 150)
		task.wait()
		expect(target:GetAttribute("Health")).toBe(150)

		target:SetAttribute("Health", 200)
		task.wait()
		expect(state:Get("Health")).toBe(200)

		disconnect()

		state:Set("Health", 300)
		task.wait()
		expect(target:GetAttribute("Health")).toBe(200)

		target:Destroy()
	end)
end)

return true
