--[=[
	@class StateObjectModule

	StateObject 클래스와 부가 유틸리티를 함께 내보내는 최종 인터페이스 모듈입니다.
]=]

local Class = require("@self/Class")

local StateObjectModule = {}

StateObjectModule.new = Class.new
StateObjectModule.fromDefaultValuesByKey = Class.fromDefaultValuesByKey
StateObjectModule.IsStateObject = Class.IsStateObject

StateObjectModule.GenerateCustomStateObjectTypeAnnotation =
	require("@self/GenerateCustomStateObjectTypeAnnotation")

StateObjectModule.SaveUtil = require("@self/SaveUtil")

export type StateInfo<Value = any> = Class.StateInfo<Value>
export type ChangedBehavior = Class.ChangedBehavior
export type Get<Key = string, Value = any> = Class.Get<Key, Value>
export type Set<Key = string, Value = any> = Class.Set<Key, Value>
export type Update<Key = string, Value = any> = Class.Update<Key, Value>
export type GetChangedSignal<Key = string, Value = any> = Class.GetChangedSignal<Key, Value>
export type Observe<Key = string, Value = any> = Class.Observe<Key, Value>
export type CustomStateObject<
	Key = string,
	GetType = Get,
	SetType = Set,
	UpdateType = Update,
	GetChangedSignalType = GetChangedSignal,
	ObserveType = Observe
> = Class.CustomStateObject<Key, GetType, SetType, UpdateType, GetChangedSignalType, ObserveType>
export type StateObject<StateParamsByKey = { [string]: StateInfo }> = Class.StateObject<
	StateParamsByKey
>
export type StateObjectParams = Class.StateObjectParams
export type AddStateParams<T = any> = Class.AddStateParams<T>

return StateObjectModule
