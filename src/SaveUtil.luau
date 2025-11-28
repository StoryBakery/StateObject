--[=[
	@class StateObjectSaveUtil
	
	StateObject 값을 Roblox Instance Attribute 및 Property와 동기화하기 위한 직렬화 유틸리티입니다.
]=]



local HttpService = game:GetService("HttpService")

local Signal = require("../roblox_packages/Signal")
local TableUtil = require("../roblox_packages/TableUtil")
local CFrameUtil = require("../roblox_packages/CFrameUtil")
local StateObject = require("../roblox_packages/StateObject")
local msgpack = require("../roblox_packages/msgpack-luau")


local function getInstancePath(instance: Instance): {string}?
	if not instance:IsDescendantOf(game) then
		return
	end

	local path = {}
	local current = instance
	while current do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end

	return path
end

local function getInstanceFromPath(path: {string})
	local instance = game
	for i, instanceName in path do
		instance = instance:FindFirstChild(instanceName)

		if not instance then
			return nil
		end
	end
	return instance
end

local function toStringOrNumberTable(v: any, vType: string)
	if vType == "Instance" then
		return getInstancePath(v)

	elseif vType == "Color3" then
		return {v.R, v.G, v.B}

	elseif vType == "Vector2" then
		return {v.X, v.Y}

	elseif vType == "Vector3" then
		return {v.X, v.Y, v.Z}

	elseif vType == "UDim" then
		return {v.Scale, v.Offset}

	elseif vType == "UDim2" then
		return {v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset}

	elseif vType == "CFrame" then
		return CFrameUtil.ToQuaternionTable(v)
		
	elseif vType == "string" then
		return v
		
	elseif vType == "boolean" then
		return v
		
	elseif vType == "number" then
		return vType
	
	end
	
	error("Unsupported type: " .. vType)
end

local function fromStringOrNumberTable(v, vType: string): any
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
		return CFrameUtil.FromQuaternionTable(v)
		
	elseif vType == "string" then
		return v
		
	elseif vType == "boolean" then
		return v
		
	elseif vType == "number" then
		return vType
	end
	
	error("Unsupported type: " .. vType)
end

local function elementsToNumberOrStringTable(t: {[any]: any}): {[any]: any}
	local new = {}
	for k, v in t do
		local vType = typeof(v)
		if vType == "table" then
			new[k] = elementsToNumberOrStringTable(v)
		else
			new[k] = toStringOrNumberTable(v, vType)
		end
	end
	return new
end

local function elementsFromNumberOrStringTables(t: {[any]: any}, refToGetOriginalType: {[any]: any}): {[any]: any}
	local new = {}
	for k, v in t do
		local originalType = typeof(v)
		
		if originalType == "table" then
			new[k] = elementsFromNumberOrStringTables(v, refToGetOriginalType[k])
		
		else
			new[k] = fromStringOrNumberTable(v, originalType)
		end
	end
	return new
end

local StateObjectSaveUtil = {}

--[=[
	@within StateObjectSaveUtil
	@function EncodeValue
	StateObject 값을 Instance Attribute에 저장 가능한 형태로 직렬화합니다.
	@param value any -- 원본 값.
	@param stateInfo StateObject.StateInfo -- 상태 메타데이터.
	@return any -- Attribute에 기록할 값.
]=]
function StateObjectSaveUtil.EncodeValue(value: any, stateInfo: StateObject.StateInfo)
	local metadata = stateInfo.Metadata
	if metadata and metadata.IsInstance then
		return toStringOrNumberTable(value, "Instance")
	end
	
	local valueType = typeof(stateInfo.Default)
	if valueType ~= "table" then
		return toStringOrNumberTable(value, valueType)
	else
		return msgpack.encode(elementsToNumberOrStringTable(value))
	end
end

--[=[
	@within StateObjectSaveUtil
	@function DecodeValue
	Instance Attribute에서 읽어 온 값을 상태 값으로 복원합니다.
	@param encoded any -- 직렬화된 값.
	@param stateInfo StateObject.StateInfo -- 상태 메타데이터.
	@return any -- 복원된 값.
]=]
function StateObjectSaveUtil.DecodeValue(encoded: string, stateInfo: StateObject.StateInfo)
	local value = encoded
	
	local metadata = stateInfo.Metadata
	if not metadata then
		if typeof(stateInfo.Default) ~= "table" then
			return value
		else
			return msgpack.decode(value)
		end
	end
	
	value = msgpack.decode(value)
	if metadata.IsInstance then
		if value == nil then
			return nil
		end

		local instance = game
		for i, instanceName in value do
			instance = instance:FindFirstChild(instanceName)

			if not instance then
				return nil
			end
		end
		return instance

	elseif metadata.MergeWithDefaultOnStart then
		return TableUtil.merge(stateInfo.Default, value)
	end

	if typeof(stateInfo.Value) ~= "table" then
		return value
	else
		
		
		return msgpack.decode(value)
	end
end

--[=[
	@within StateObjectSaveUtil
	@function SyncBetweenStatesAndInstanceAttributes
	StateObject와 Instance Attribute 간의 양방향 동기화를 설정합니다.
	@param stateObject StateObject.StateObject -- 동기화할 상태 객체.
	@param instance Instance -- 연동할 Roblox Instance.
	@return () -> () -- 모든 연결을 해제하는 함수.
]=]
function StateObjectSaveUtil.SyncBetweenStatesAndInstanceAttributes(
	stateObject: StateObject.StateObject, 
	instance: Instance
): () -> ()
	local conns = {}
	
	for key, stateInfo in stateObject:GetStateInfosByKey() do
		local metadata = stateInfo.Metadata
		
		if metadata and metadata.SyncWithInstance == false then
			continue
		end
		
		stateObject:Set(
			key, 
			StateObjectSaveUtil.DecodeValue(
				instance:GetAttribute(key), 
				stateInfo
			)
		)

		local attributeConn = instance:GetAttributeChangedSignal(key):Connect(function()
			stateObject:Set(
				key, 
				StateObjectSaveUtil.DecodeValue(
					instance:GetAttribute(key), 
					stateInfo
				)
			)
		end)

		local stateConn = stateObject:GetChangedSignal(key):Connect(function(newValue)
			instance:SetAttribute(
				StateObjectSaveUtil.EncodeValue(newValue, stateInfo)
			)
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


--[[ 모듈 반환부 ]]
return StateObjectSaveUtil

