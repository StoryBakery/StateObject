
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

local function GetCustomStateObjectTypeAnnotation(
	stateObject, 
	moduleName: string?
): string

	local moduleName = moduleName or "StateObject"
	
	local keyTypeAnnotations = {}
	local valueTypeAnnotations = {}
	local getTypeAnnotations = {}
	local setTypeAnnotations = {}
	local updateTypeAnnotations = {}
	local getChangedSignalTypeAnnotations = {}
	local observeTypeAnnotations = {}
	
	for key, stateInfo in stateObject.StateInfosByKey do
		table.insert(keyTypeAnnotations, key)

		local stateTypeAnnotation = getTypeAnnotationOfStateInfo(stateInfo)
		if not table.find(valueTypeAnnotations, stateTypeAnnotation) then
			table.insert(valueTypeAnnotations, stateTypeAnnotation)
		end
		
		table.insert(
			getTypeAnnotations, 
			`({moduleName}.Get<"{key}", {stateTypeAnnotation}>)`
		)
		table.insert(
			setTypeAnnotations, 
			`({moduleName}.Set<"{key}", {stateTypeAnnotation}>)`
		)
		table.insert(
			updateTypeAnnotations, 
			`({moduleName}.Update<"{key}", {stateTypeAnnotation}>)`
		)
		table.insert(
			getChangedSignalTypeAnnotations, 
			`({moduleName}.GetChangedSignal<"{key}", {stateTypeAnnotation}>)`
		)
		table.insert(
			observeTypeAnnotations, 
			`({moduleName}.Observe<"{key}", {stateTypeAnnotation}>)`
		)

	end

	return `{moduleName}.CustomStateObject<\n`..
		`\t("{table.concat(keyTypeAnnotations, `"|"`)}"),\n`..
		`\t({table.concat(valueTypeAnnotations, `|`)}),\n`..
		`\t({table.concat(getTypeAnnotations, `&`)}),\n`..
		`\t({table.concat(setTypeAnnotations, `&`)}),\n`..
		`\t({table.concat(updateTypeAnnotations, `&`)}),\n`..
		`\t({table.concat(getChangedSignalTypeAnnotations, `&`)}),\n`..
		`\t({table.concat(observeTypeAnnotations, `&`)})\n`..
		`>`
end

return GetCustomStateObjectTypeAnnotation