--[=[
	@class StateObjectSaveUtil
	
	StateObject 값을 Roblox Instance Attribute 및 Property와 동기화하기 위한 직렬화 유틸리티입니다.
	주로 StateObject 를 플러그인의 설정 값과 연동시킬 때 유용합니다
	
	인스턴스의 경우, 절대경로로 저장합니다. 
]=]

local HttpService = game:GetService("HttpService")

local Signal = require("../roblox_packages/Signal")
local TableUtil = require("../roblox_packages/TableUtil")

local StateObject = require("./Class")

local function getInstancePath(instance: Instance): { string }?
	if not instance:IsDescendantOf(game) then
		return
	end

	local path = {}
	local current = instance
	while current and current ~= game do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end

	return path
end

local function getInstanceFromPath(path: { string })
	local instance = game
	for i, instanceName in path do
		instance = instance:FindFirstChild(instanceName)

		if not instance then
			return nil
		end
	end
	return instance
end

local function encodeByType(v: any, vType: string)
	if vType == "Instance" then
		return getInstancePath(v)
	elseif vType == "Color3" then
		return { v.R, v.G, v.B }
	elseif vType == "Vector2" then
		return { v.X, v.Y }
	elseif vType == "Vector3" then
		return { v.X, v.Y, v.Z }
	elseif vType == "UDim" then
		return { v.Scale, v.Offset }
	elseif vType == "UDim2" then
		return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif vType == "CFrame" then
		return { v:GetComponents() }
	elseif vType == "string" then
		return v
	elseif vType == "boolean" then
		return v
	elseif vType == "number" then
		return v
	end

	error("Unsupported type: " .. vType)
end

local function decodeByType(v, vType: string): any
	if vType == "Instance" then
		return getInstanceFromPath(v)
	elseif vType == "Color3" then
		return Color3.new(v[1], v[2], v[3])
	elseif vType == "Vector2" then
		return Vector2.new(v[1], v[2])
	elseif vType == "Vector3" then
		return Vector3.new(v[1], v[2], v[3])
	elseif vType == "UDim" then
		return UDim.new(v[1], v[2])
	elseif vType == "UDim2" then
		return UDim2.new(v[1], v[2], v[3], v[4])
	elseif vType == "CFrame" then
		return CFrame.new(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12])
	elseif vType == "string" then
		return v
	elseif vType == "boolean" then
		return v
	elseif vType == "number" then
		return v
	end

	error("Unsupported type: " .. vType)
end

local function encodeTableElements(t: { [any]: any }): { [any]: any }
	local new = {}
	for k, v in t do
		local vType = typeof(v)
		if vType == "table" then
			new[k] = encodeTableElements(v)
		else
			new[k] = encodeByType(v, vType)
		end
	end
	return new
end

local function decodeTableElements(
	t: { [any]: any },
	refToGetOriginalType: any
): { [any]: any }
	local new = {}
	for k, v in t do
		local referenceValue = if typeof(refToGetOriginalType) == "table"
			then refToGetOriginalType[k]
			else nil
		local originalType = if referenceValue == nil then typeof(v) else typeof(referenceValue)

		if originalType == "table" and typeof(v) == "table" then
			new[k] = decodeTableElements(v, referenceValue)
		else
			new[k] = decodeByType(v, originalType)
		end
	end
	return new
end

local StateObjectSaveUtil = {}

--[=[
	StateObject 값을 Instance Attribute에 저장 가능한 형태로 직렬화합니다.
	
	@param value - 원본 값.
	@param stateInfo - 상태 메타데이터.
	@return - Attribute에 기록할 값.
]=]
function StateObjectSaveUtil.EncodeValue(value: any, stateInfo: StateObject.StateInfo)
	local metadata = stateInfo.Metadata
	if metadata and metadata.IsInstance then
		local instancePath = encodeByType(value, "Instance")
		if instancePath == nil then
			return nil
		end
		return HttpService:JSONEncode(instancePath)
	end

	local valueType = typeof(stateInfo.Default)
	if valueType == "table" then
		return HttpService:JSONEncode(encodeTableElements(value))
	end

	return value
end

--[=[
	Instance Attribute에서 읽어 온 값을 상태 값으로 복원합니다.
	
	@param encoded - 직렬화된 값.
	@param stateInfo - 상태 메타데이터.
	@return - 복원된 값.
]=]
function StateObjectSaveUtil.DecodeValue(encoded: any, stateInfo: StateObject.StateInfo)
	local value = encoded

	local metadata = stateInfo.Metadata
	if metadata and metadata.IsInstance then
		if value == nil then
			return nil
		end
		local instancePath = HttpService:JSONDecode(value)
		return decodeByType(instancePath, "Instance")
	end

	if typeof(stateInfo.Default) ~= "table" then
		return value
	end

	if value == nil then
		return nil
	end

	value = HttpService:JSONDecode(value)
	value = decodeTableElements(value, stateInfo.Default)

	if metadata and metadata.MergeWithDefaultOnStart then
		return TableUtil.merge(stateInfo.Default, value)
	end

	return value
end

--[=[
	[[StateObject]] 와 `Class.Instance` Attribute 간의 양방향 동기화를 설정합니다.

	동작 방식:
	초기 동기화에서 `Attribute` 가 없으면 [[StateObject]]의 현재 값을 `Attribute` 에 기록합니다.
	초기 동기화에서 `Attribute` 가 이미 있으면 `Attribute` 값을 디코드해 [[StateObject]]에 반영합니다.
	이후에는 `Attribute` 변경과 [[StateObject]] 변경을 서로 반대편에 전파해 양방향 동기화를 유지합니다.
	`stateInfo.Metadata.AttributeSyncEnabled == false`인 키는 동기화 대상에서 제외됩니다.
	내부 플래그로 자기 자신이 유발한 변경은 무시해 순환 갱신을 방지합니다.
	
	@param stateObject - 동기화할 상태 객체.
	@param instance - 연동할 Roblox Instance.
	@return - 모든 연결을 해제하는 함수.
]=]
function StateObjectSaveUtil.BindStateObjectAndInstanceAttributes(
	stateObject: StateObject.StateObject,
	instance: Instance
): () -> ()
	local conns = {}
	local isSyncingFromAttributeByKey = {}
	local isSyncingFromStateByKey = {}

	for key, stateInfo in stateObject:GetStateInfosByKey() do
		local metadata = stateInfo.Metadata

		if metadata and metadata.AttributeSyncEnabled == false then
			continue
		end

		local encodedValue = instance:GetAttribute(key)
		if encodedValue == nil then
			isSyncingFromStateByKey[key] = true
			instance:SetAttribute(
				key,
				StateObjectSaveUtil.EncodeValue(stateObject:Get(key), stateInfo)
			)
			isSyncingFromStateByKey[key] = nil
		else
			isSyncingFromAttributeByKey[key] = true
			stateObject:Set(key, StateObjectSaveUtil.DecodeValue(encodedValue, stateInfo))
			isSyncingFromAttributeByKey[key] = nil
		end

		local attributeConn = instance:GetAttributeChangedSignal(key):Connect(function()
			if isSyncingFromStateByKey[key] then
				return
			end

			isSyncingFromAttributeByKey[key] = true
			stateObject:Set(
				key,
				StateObjectSaveUtil.DecodeValue(instance:GetAttribute(key), stateInfo)
			)
			isSyncingFromAttributeByKey[key] = nil
		end)

		local stateConn = stateObject:GetChangedSignal(key):Connect(function(newValue)
			if isSyncingFromAttributeByKey[key] then
				return
			end

			isSyncingFromStateByKey[key] = true
			instance:SetAttribute(key, StateObjectSaveUtil.EncodeValue(newValue, stateInfo))
			isSyncingFromStateByKey[key] = nil
		end)

		table.insert(conns, attributeConn)
		table.insert(conns, stateConn)
	end

	return function()
		for _, conn in conns do
			conn:Disconnect()
		end
	end
end

return StateObjectSaveUtil
