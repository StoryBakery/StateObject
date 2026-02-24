--[=[
	@class StateObject
	
	상태 값을 테이블로 관리하고 신호 기반으로 변경을 내보내는 컨테이너입니다.
	기본값, 메타데이터, 즉시/지연 알림 모드를 지원하며 Vide 런타임 연동 헬퍼를 제공합니다.
]=]

local Signal = require("../roblox_packages/Signal")
local TableUtil = require("../roblox_packages/TableUtil")

local StateObject = {}

StateObject.__index = StateObject
StateObject.__type = "StateObject"

export type StateInfo<Value = any> = {
	Value: Value,
	Changed: Signal.ChangedSignal<Value>,

	Default: any,
	TypeAnnotation: string,
	Metadata: { [string]: any }?,
	OnCloneValue: ((value: Value) -> Value)?,
	OnChangedUnyielding: ((
		self: setmetatable<{ [string]: any }, typeof(StateObject)>,
		new: Value
	) -> ())?,
	_isReadyToFireChanged: boolean?,
}

export type ChangedBehavior = "Immediate" | "Deferred"

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

--[=[
	@type CustomStateObject
	
	미리 정의된 속성에 따라 자동완성을 제공해야할 때 타입입니다.
	주로 자동생성됨으로 수동으로 작성하는데에 적합하진 않습니다.
]=]
export type CustomStateObject<
	Key = string,
	GetType = Get,
	SetType = Set,
	UpdateType = Update,
	GetChangedSignalType = GetChangedSignal,
	ObserveType = Observe
> = {

	IsDestroyed: boolean,
	Destroying: Signal.Signal,
	Name: string?,
	StateInfosByKey: { [string]: StateInfo },

	Changed: Signal.ObjectChangedSignal,
	ChangedBehavior: ChangedBehavior,

	Destroy: (self: any) -> (),
	Get: GetType,
	Set: SetType,
	Update: UpdateType,
	GetChangedSignal: GetChangedSignalType,
	Observe: ObserveType,
	AddState: (self: any, key: Key, params: any) -> (),
	AddStates: (self: any, stateParamsByKey: { [Key]: any }) -> (),
	RemoveState: (self: any, key: Key) -> (),
	FindStateInfo: (self: any, key: Key) -> StateInfo?,
	GetStateInfo: (self: any, key: Key) -> StateInfo,
	GetStateInfosByKey: (self: any) -> { [string]: StateInfo },
	GetValuesByKey: (self: any) -> { [Key]: any },
	GetStateMetadata: (self: any, key: Key) -> { [Key]: any }?,
	GetStateKeys: (self: any) -> { string },
	HasState: (self: any, key: Key) -> boolean,

	Clone: (
		self: any
	) -> CustomStateObject<Key, GetType, SetType, UpdateType, GetChangedSignalType, ObserveType>,
}

--[=[
	@type StateObject
	상태 저장소와 신호 메서드를 제공하는 기본 구현입니다.
]=]
export type StateObject<StateParamsByKey = { [string]: StateInfo }> = CustomStateObject<
	keyof<StateParamsByKey> | string,
	Get<keyof<StateParamsByKey> | string, any>,
	Set<keyof<StateParamsByKey> | string, any>,
	Update<keyof<StateParamsByKey> | string, any>,
	GetChangedSignal<keyof<StateParamsByKey> | string, any>,
	Observe<keyof<StateParamsByKey> | string, any>
>

--[=[
	@interface StateObjectParams
	.ChangedBehavior ChangedBehavior? -- "Deferred"가 기본값입니다.
	.Name string? -- 디버깅용 식별자.
]=]
export type StateObjectParams = {
	ChangedBehavior: ChangedBehavior?,
	Name: string?,
}

--[=[
	@param stateParamsByKey - 초기 상태 정의.
	@param params - 변경 동작 설정.
	@return - 생성된 상태 객체.
]=]
function StateObject.new<StateParamsByKey>(
	stateParamsByKey: StateParamsByKey?,
	params: StateObjectParams?
): StateObject<StateParamsByKey>
	local self = setmetatable({}, StateObject)

	params = params or {}

	self.IsDestroyed = false
	self.Destroying = Signal.new()

	self.Name = params.Name

	self.StateInfosByKey = {}
	self.ChangedBehavior = params.ChangedBehavior or "Deferred"
	self.Changed = Signal.Immediate.new()

	if stateParamsByKey then
		self:AddStates(stateParamsByKey :: any)
	end

	return self :: any
end

type StateObjectFromDefaultValuesByKey<DefaultValuesByKey> = CustomStateObject<
	keyof<DefaultValuesByKey>,
	Get<keyof<DefaultValuesByKey>, any>,
	Set<keyof<DefaultValuesByKey>, any>,
	Update<keyof<DefaultValuesByKey>, any>,
	GetChangedSignal<keyof<DefaultValuesByKey>, any>,
	Observe<keyof<DefaultValuesByKey>, any>
>

--[=[
	@param defaultValuesByKey - 키와 기본값 매핑.
	@return - 기본값만 등록한 상태 객체.
]=]
function StateObject.fromDefaultValuesByKey<DefaultValuesByKey>(
	defaultValuesByKey: DefaultValuesByKey
): StateObjectFromDefaultValuesByKey<
	DefaultValuesByKey
>
	local self = StateObject.new()
	for key, value in pairs(defaultValuesByKey) do
		self:AddState(key, {
			Default = value,
		})
	end
	return self
end

--[=[
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
	@method Get
	@param key - 조회할 상태 키.
	@return - 현재 값.
]=]
function StateObject:Get(key: string): any
	local state = self.StateInfosByKey[key]
		or error(`State "{key}" is invalid member of StateObject "{self}".`)

	return state.Value
end

--[=[
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
	@method Update
	@param key string
	@param callback - 새 값을 계산하는 함수.
]=]
function StateObject:Update<T>(key: string, callback: (value: T) -> T)
	self:Set(key, callback(self:Get(key)))
end

--[=[
	@method GetChangedSignal
	@param key
	@return - 해당 상태의 변경 신호.
]=]
function StateObject:GetChangedSignal(key: string)
	local stateInfo = self.StateInfosByKey[key]
		or error(`State "{key}" is invalid member of StateObject "{self}".`)

	return stateInfo.Changed
end

--[=[
	@method Observe
	@param key
	@param callback - 자동 해제 가능한 관찰 콜백.
	@return - 연결 객체.
]=]
function StateObject:Observe(key: string, callback: (value: any) -> ()): Signal.Connection
	local stateInfo = self.StateInfosByKey[key]
		or error(`State "{key}" is invalid member of StateObject "{self}".`)

	task.spawn(callback, self:Get(key))

	return stateInfo.Changed:Connect(callback)
end

--[=[
	@interface AddStateParams<T>
    
	.Default - 초기 값.
	.OnCloneValue - Clone 시 값을 복제하는 함수.
	.TypeAnnotation - 타입 추론 힌트.
	.Metadata - 추가 메타데이터.
	.OnChangedUnyielding - 즉시 콜백.
]=]
export type AddStateParams<T = any> = {
	Default: T,
	OnCloneValue: ((value: T) -> T)?,
	TypeAnnotation: string?,
	OnChangedUnyielding: ((self: StateObject, new: T) -> ())?,
	Metadata: { [string]: any }?,
}

--[=[
	@method AddState
	새 상태 키를 등록하고 기본값과 메타데이터를 설정합니다.
	@param key string
	@param params - 상태 정의.
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
	@method FindStateInfo
	@param key string
	@return - 존재하면 상태 정보.
]=]
function StateObject:FindStateInfo(key: string): StateInfo?
	return self.StateInfosByKey[key]
end

--[=[
	@method GetStateInfo
	@param key string
	@return - 없으면 오류를 발생시킵니다.
]=]
function StateObject:GetStateInfo(key: string): StateInfo
	return self.StateInfosByKey[key]
		or error(`State "{key}" is invalid member of StateObject "{self}".`)
end

--[=[
	@method GetStateInfosByKey
	@return - 상태 정보 사본.
]=]
function StateObject:GetStateInfosByKey(): { [string]: StateInfo }
	return table.clone(self.StateInfosByKey)
end

--[=[
	@method GetValuesByKey
	@return - 현재 값 사본.
]=]
function StateObject:GetValuesByKey(): { [string]: any }
	local values = {}
	for key, stateInfo in self.StateInfosByKey do
		values[key] = stateInfo.Value
	end
	return values
end

--[=[
	@method GetStateMetadata
	@param key string
	@return - 메타데이터 사본.
]=]
function StateObject:GetStateMetadata(key: string): { [string]: any }?
	return self:GetStateInfo(key).Metadata
end

--[=[
	@method GetStateKeys
	@return - 등록된 상태 키 목록.
]=]
function StateObject:GetStateKeys(): { string }
	local keys = {}
	for key, state in self.StateInfosByKey do
		table.insert(keys, key)
	end
	return keys
end

--[=[
	@method HasState
	@param key string
	@return - 등록 여부.
]=]
function StateObject:HasState(key: string): boolean
	return self.StateInfosByKey[key] ~= nil
end

--[=[
	@method Clone
	
	@return - 값과 메타데이터를 복제한 새 컨테이너.
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

--[=[
	@function IsStateObject
	@param stateObject StateObject | any
	@return - __type 검사를 기반으로 한 판정.
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

local a = StateObject.new({
	Name = {
		Default = "ASd",
	},
})

local b: CustomStateObject

return StateObject
