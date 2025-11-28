--[=[
	@class StateObject
	
	상태 값을 테이블로 관리하고 신호 기반으로 변경을 내보내는 컨테이너입니다.
	기본값, 메타데이터, 즉시/지연 알림 모드를 지원하며 Vide 런타임 연동 헬퍼를 제공합니다.
]=]

local Signal = require("../roblox_packages/Signal")
local TableUtil = require("../roblox_packages/TableUtil")
local vide = require("../roblox_packages/vide")

local StateObject = {}

StateObject.__index = StateObject
StateObject.__type = "StateObject"

--#region Constructors

export type Get<Key = string, Value = any> = (self: any, key: Key) -> Value

export type Set<Key = string, Value = any> = (self: any, key: Key, value: Value) -> ()

export type Update<Key = string, Value = any> = (
	self: any,
	key: Key,
	callback: (value: Value) -> Value
) -> ()

export type GetChangedSignal<Key = string, Value = any> = (
	self: any,
	key: Key
) -> Signal.ChangedSignal<Value>

export type Observe<Key = string, Value = any> = (
	self: any,
	key: Key,
	callback: (value: Value) -> ()
) -> Signal.Connection

export type StateInfo<Value = any> = {
	Value: Value,
	Changed: Signal.ChangedSignal<Value>,

	Default: any,
	TypeAnnotation: string,
	Metadata: { [string]: any }?,
	OnCloneValue: ((value: Value) -> Value)?,
	OnChangedUnyielding: ((self: StateObject, new: Value) -> ())?,
	_isReadyToFireChanged: boolean?,
}

export type ChangedBehavior = "Immediate" | "Deferred"

export type CustomStateObject<
	Key = string,
	Value = any,
	Get = Get,
	Set = Set,
	Update = Update,
	GetChangedSignal = GetChangedSignal,
	Observe = Observe
> = setmetatable<{

	IsDestroyed: boolean,
	Destroying: Signal.Signal,
	StateInfosByKey: { [string]: StateInfo },

	Changed: Signal.ObjectChangedSignal,
	ChangedBehavior: ChangedBehavior,

	Get: Get,
	Set: Set,
	Update: Update,
	GetChangedSignal: GetChangedSignal,
	Observe: Observe,
	UseVideSelector: (key: string, runtime: any?)->( vide.Source<any> ),

	Clone: (self: any) -> CustomStateObject,
}, typeof(StateObject)>

--[=[
	@within StateObject
	@type StateObject CustomStateObject
	상태 저장소와 신호 메서드를 제공하는 기본 구현입니다.
]=]
export type StateObject = CustomStateObject

--[=[
	@interface StateObjectParams
	@within StateObject
	.ChangedBehavior ChangedBehavior? -- "Deferred"가 기본값입니다.
	.Name string? -- 디버깅용 식별자.
]=]
export type StateObjectParams = {
	ChangedBehavior: ChangedBehavior?,
	Name: string?,
}

--[=[
	@param stateParamsByKey {[string]: AddStateParams}? -- 초기 상태 정의.
	@param params StateObjectParams? -- 변경 동작 설정.
	@return StateObject -- 생성된 상태 객체.
]=]
function StateObject.new(
	stateParamsByKey: { [string]: AddStateParams }?,
	params: StateObjectParams?
): StateObject
	local self = setmetatable({}, StateObject)

	local params = params or {}

	self.IsDestroyed = false
	self.Destroying = Signal.new()

	self.Name = params.Name

	self.StateInfosByKey = {}
	self.ChangedBehavior = params.ChangedBehavior or "Deferred"
	self.Changed = Signal.Immediate.new()

	if stateParamsByKey then
		self:AddStates(stateParamsByKey)
	end

	return self
end

--[=[
	@param defaultValuesByKey {[string]: any} -- 키와 기본값 매핑.
	@return StateObject -- 기본값만 등록한 상태 객체.
]=]
function StateObject.fromDefaultValuesByKey(defaultValuesByKey: { [string]: any }): StateObject
	local self = StateObject.new()
	for key, value in pairs(defaultValuesByKey) do
		self:AddState(key, {
			Default = value,
		})
	end
	return self
end

--#region Methods

--[=[
	@within StateObject
	@method Destroy
	상태와 신호를 정리하고 추가 변경을 차단합니다.
]=]
function StateObject:Destroy()
	if self.IsDestroyed then
		return
	end

	self.IsDestroyed = true
	self.Destroying:Fire()

	self.Changed:Destroy()
	for key, state in self.StateInfosByKey do
		state.Changed:Destroy()
	end

	table.freeze(self :: any)
end

--[=[
	@within StateObject
	@method Get
	@param key string -- 조회할 상태 키.
	@return any -- 현재 값.
]=]
function StateObject:Get(key: string): any
	local state = self.StateInfosByKey[key]
		or error(`State "{key}" is invalid member of StateObject "{self}".`)

	return state.Value
end

--[=[
	@within StateObject
	@method Set
	지정한 키의 상태 값을 갱신하고 변경 신호를 발생시킵니다.
	@param key string
	@param value any
]=]
function StateObject:Set(key: string, value: any)
	local stateInfo = self.StateInfosByKey[key]
		or error(`State "{key}" is invalid member of StateObject "{self}".`)

	if stateInfo.Value == value then
		return
	end

	local OnChangedUnyielding = stateInfo.OnChangedUnyielding
	local lastValue = stateInfo.Value

	if OnChangedUnyielding and value ~= lastValue then
		OnChangedUnyielding(self, value)
	end

	stateInfo.Value = value
	if stateInfo._isReadyToFireChanged then
		return
	end

	if self.ChangedBehavior == "Deferred" then
		stateInfo._isReadyToFireChanged = true
		task.defer(function()
			local currentValue = stateInfo.Value
			if currentValue ~= lastValue then
				stateInfo.Changed:Fire(currentValue)
				self.Changed:Fire(key, currentValue)
			end
			stateInfo._isReadyToFireChanged = nil
		end)
	else
		if value ~= lastValue then
			stateInfo.Changed:Fire(value)
			self.Changed:Fire(key, value)
		end
	end
end

--[=[
	@within StateObject
	@method Update
	@param key string
	@param callback (value: any)->(any) -- 새 값을 계산하는 함수.
]=]
function StateObject:Update<T>(key: string, callback: (value: T) -> T)
	self:Set(key, callback(self:Get(key)))
end

--[=[
	@within StateObject
	@method GetChangedSignal
	@param key string
	@return Signal.ChangedSignal<any> -- 해당 상태의 변경 신호.
]=]
function StateObject:GetChangedSignal(key: string)
	local stateInfo = self.StateInfosByKey[key]
		or error(`State "{key}" is invalid member of StateObject "{self}".`)

	return stateInfo.Changed
end

--[=[
	@within StateObject
	@method Observe
	@param key string
	@param callback (value: any)->() -- 자동 해제 가능한 관찰 콜백.
	@return Signal.Connection -- 연결 객체.
]=]
function StateObject:Observe(key: string, callback: (value: any) -> ()): Signal.Connection
	local stateInfo = self.StateInfosByKey[key]
		or error(`State "{key}" is invalid member of StateObject "{self}".`)

	task.spawn(callback, self:Get(key))

	return stateInfo.Changed:Connect(callback)
end

--[=[
	@within StateObject
	@method UseVideSelector
	Vide 기반 컴포넌트에서 상태를 구독할 때 사용합니다.
]=]
function StateObject:UseVideSelector(key: string, runtime: any?): vide.Source<any>
	local videRuntime = vide or runtime

	local value = videRuntime.source(self:Get(key))

	videRuntime.effect(function()
		local conn = self:GetChangedSignal(key):Connect(value)
		vide.cleanup(function()
			conn:Disconnect()
		end)
	end)

	return value
end

--[=[
	@interface AddStateParams<T>
	@within StateObject
	.Default T -- 초기 값.
	.OnCloneValue ((value: T)->(T))? -- Clone 시 값을 복제하는 함수.
	.TypeAnnotation string? -- 타입 추론 힌트.
	.Metadata {[string]: any}? -- 추가 메타데이터.
	.OnChangedUnyielding ((self: StateObject, new: T)->())? -- 즉시 콜백.
]=]
export type AddStateParams<T = any> = {
	Default: T,
	OnCloneValue: ((value: T) -> T)?,
	TypeAnnotation: string?,
	OnChangedUnyielding: ((self: StateObject, new: T) -> ())?,
	Metadata: { [string]: any }?,
}

--[=[
	@within StateObject
	@method AddState
	새 상태 키를 등록하고 기본값과 메타데이터를 설정합니다.
	@param key string
	@param params AddStateParams -- 상태 정의.
]=]
function StateObject:AddState(key: string, params: AddStateParams)
	local metadata = params.Metadata
	if metadata ~= nil then
		metadata = table.clone(metadata)
	end

	local stateInfo: StateInfo = {
		Value = params.Default,
		Changed = Signal.Immediate.new(),

		Default = params.Default,
		OnCloneValue = params.OnCloneValue,
		TypeAnnotation = params.TypeAnnotation or typeof(params.Default),
		OnChangedUnyielding = params.OnChangedUnyielding,
		Metadata = metadata,
	}

	self.StateInfosByKey[key] = stateInfo
end

--[=[
	@within StateObject
	@method AddStates
	여러 상태를 한 번에 등록합니다.
	@param stateParamsByKey {[string]: AddStateParams}
]=]
function StateObject:AddStates(stateParamsByKey: { [string]: AddStateParams })
	for key, stateParam in stateParamsByKey do
		self:AddState(key, stateParam)
	end
end

--[=[
	@within StateObject
	@method RemoveState
	@param key string
	등록된 상태를 제거하고 관련 신호를 정리합니다.
]=]
function StateObject:RemoveState(key: string)
	local statesByKey = self.StateInfosByKey
	local state = statesByKey[key]
	if state == nil then
		warn(`Attempt to remove invalid key "{key}"`)
		return
	end

	state.Changed:Destroy()
	statesByKey[key] = nil
end

--[=[
	@within StateObject
	@method FindStateInfo
	@param key string
	@return StateInfo? -- 존재하면 상태 정보.
]=]
function StateObject:FindStateInfo(key: string): StateInfo?
	return self.StateInfosByKey[key]
end

--[=[
	@within StateObject
	@method GetStateInfo
	@param key string
	@return StateInfo -- 없으면 오류를 발생시킵니다.
]=]
function StateObject:GetStateInfo(key: string): StateInfo
	return self.StateInfosByKey[key]
		or error(`State "{key}" is invalid member of StateObject "{self}".`)
end

--[=[
	@within StateObject
	@method GetStateInfosByKey
	@return {[string]: StateInfo} -- 상태 정보 사본.
]=]
function StateObject:GetStateInfosByKey(): { [string]: StateInfo }
	return table.clone(self.StateInfosByKey)
end

--[=[
	@within StateObject
	@method GetValuesByKey
	@return {[string]: any} -- 현재 값 사본.
]=]
function StateObject:GetValuesByKey(): { [string]: any }
	local values = {}
	for key, stateInfo in self.StateInfosByKey do
		values[key] = stateInfo.Value
	end
	return values
end

--[=[
	@within StateObject
	@method GetStateMetadata
	@param key string
	@return {[string]: any}? -- 메타데이터 사본.
]=]
function StateObject:GetStateMetadata(key: string): { [string]: any }?
	return self:GetStateInfo(key).Metadata
end

--[=[
	@within StateObject
	@method GetStateKeys
	@return {string} -- 등록된 상태 키 목록.
]=]
function StateObject:GetStateKeys(): { string }
	local keys = {}
	for key, state in self.StateInfosByKey do
		table.insert(keys, key)
	end
	return keys
end

--[=[
	@within StateObject
	@method HasState
	@param key string
	@return boolean -- 등록 여부.
]=]
function StateObject:HasState(key: string): boolean
	return self.StateInfosByKey[key] ~= nil
end

--[=[
	@within StateObject
	@method Clone
	
	@return StateObject -- 값과 메타데이터를 복제한 새 컨테이너.
]=]
function StateObject:Clone(): StateObject
	local stateParamsByKey = {}

	for key, stateInfo in self.StateInfosByKey do
		local metadata = stateInfo.Metadata
		if metadata ~= nil then
			metadata = table.clone(metadata)
		end

		stateParamsByKey[key] = {
			Default = stateInfo.Default,
			OnCloneValue = stateInfo.OnCloneValue,
			TypeAnnotation = stateInfo.TypeAnnotation,
			OnChangedUnyielding = stateInfo.OnChangedUnyielding,
			Metadata = metadata,
		}
	end

	local clone = StateObject.new(stateParamsByKey, {
		ChangedBehavior = self.ChangedBehavior,
		Name = self.Name,
	})

	for key, stateInfo in self.StateInfosByKey do
		local clonedValue = stateInfo.Value

		if stateInfo.OnCloneValue then
			clonedValue = stateInfo.OnCloneValue(clonedValue)
		elseif typeof(clonedValue) == "table" then
			clonedValue = table.clone(clonedValue)
		end

		clone:Set(key, clonedValue)
	end

	return clone
end

--#region Functions

--[=[
	@within StateObject
	@function IsStateObject
	@param stateObject StateObject | any
	@return boolean -- __type 검사를 기반으로 한 판정.
]=]
function StateObject.IsStateObject(stateObject: StateObject | any): boolean
	if typeof(stateObject) ~= "table" then
		return false
	end

	local identifiedType = stateObject.__type
	if identifiedType ~= nil then
		return identifiedType == StateObject.__type
	end

	local metatable = getmetatable(stateObject)
	return metatable == StateObject
end

StateObject.GetCustomStateObjectTypeAnnotation = require(script.GetCustomStateObjectTypeAnnotation)

--[[ 모듈 반환부 ]]
return StateObject
