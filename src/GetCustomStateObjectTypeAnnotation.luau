--[=[
	@class StateObjectTypeAnnotation

	StateObject 상태 정의를 기반으로 CustomStateObject 타입 문자열을 생성하는 개발용 유틸리티 모듈입니다.
]=]

local METHOD_TYPE_NAMES = {
	"Get",
	"Set",
	"Update",
	"GetChangedSignal",
	"Observe",
}

local function escapeTypeStringLiteral(value: string): string
	value = string.gsub(value, "\\", "\\\\")
	value = string.gsub(value, "\n", "\\n")
	value = string.gsub(value, "\r", "\\r")
	value = string.gsub(value, "\t", "\\t")
	return string.gsub(value, "\"", "\\\"")
end

local function getTypeAnnotationOfStateInfo(stateInfo)
	local stateTypeAnnotation = stateInfo.TypeAnnotation
	if stateTypeAnnotation == nil then
		local valueType = typeof(stateInfo.Default)
		stateTypeAnnotation = if valueType == "nil" or valueType == "table"
			then "any"
			else valueType
	end

	return stateTypeAnnotation
end

local function getStateInfosByKey(stateObject)
	local getStateInfosByKeyMethod = stateObject.GetStateInfosByKey
	if typeof(getStateInfosByKeyMethod) == "function" then
		return getStateInfosByKeyMethod(stateObject)
	end

	return stateObject.StateInfosByKey
end

local function getSortedStateKeys(stateObject, stateInfosByKey)
	local getStateKeysMethod = stateObject.GetStateKeys
	local stateKeys = if typeof(getStateKeysMethod) == "function"
		then getStateKeysMethod(stateObject)
		else {}

	if typeof(getStateKeysMethod) ~= "function" then
		for key in stateInfosByKey do
			table.insert(stateKeys, key)
		end
	end

	table.sort(stateKeys)
	return stateKeys
end

local function GetCustomStateObjectTypeAnnotation(
	stateObject,
	moduleName: string?
): string
	local resolvedModuleName = moduleName or "StateObject"

	local stateInfosByKey = getStateInfosByKey(stateObject)
	local stateKeys = getSortedStateKeys(stateObject, stateInfosByKey)

	if #stateKeys == 0 then
		return `{resolvedModuleName}.StateObject`
	end

	local keyTypeAnnotations = {}
	local methodTypeAnnotationsByName = {}

	for _, methodTypeName in METHOD_TYPE_NAMES do
		methodTypeAnnotationsByName[methodTypeName] = {}
	end

	for _, key in stateKeys do
		local stateInfo = stateInfosByKey[key]
		if stateInfo == nil then
			continue
		end

		local escapedKey = escapeTypeStringLiteral(key)
		local keyTypeAnnotation = `"{escapedKey}"`
		local stateTypeAnnotation = getTypeAnnotationOfStateInfo(stateInfo)

		table.insert(keyTypeAnnotations, keyTypeAnnotation)

		for _, methodTypeName in METHOD_TYPE_NAMES do
			local methodTypeAnnotations = methodTypeAnnotationsByName[methodTypeName]
			table.insert(
				methodTypeAnnotations,
				`({resolvedModuleName}.{methodTypeName}<{keyTypeAnnotation}, {stateTypeAnnotation}>)`
			)
		end
	end

	if #keyTypeAnnotations == 0 then
		return `{resolvedModuleName}.StateObject`
	end

	local genericArguments = {
		`\t({table.concat(keyTypeAnnotations, `|`)})`,
	}

	for _, methodTypeName in METHOD_TYPE_NAMES do
		local methodTypeAnnotations = methodTypeAnnotationsByName[methodTypeName]
		table.insert(genericArguments, `\t({table.concat(methodTypeAnnotations, `&`)})`)
	end

	return `{resolvedModuleName}.CustomStateObject<\n{table.concat(genericArguments, `,\n`)}\n>`
end

return GetCustomStateObjectTypeAnnotation
