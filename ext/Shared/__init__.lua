-- Stores LevelData DataContainer.
local PrimaryLevel = nil

-- This is a global table that stores the save file data as a 
-- Lua table. Will be populated on-demand by
-- the server via NetEvents on the client-side
CustomLevelData = nil
local indexCount = 0
local customRegistryGuid = Guid('5FAD87FD-9934-4D44-A5BE-7C5B38FCE6AF')
local customRegistry = nil
local worldPartRefIndex = nil

local function PatchOriginalObject(object, world)
	if(object.originalRef == nil) then
		print("Object without original reference found, dynamic object?")
		return
	end
	local s_Reference = nil
	if(object.originalRef.partitionGuid == nil or object.originalRef.partitionGuid == "nil") then -- perform a search without partitionguid
		 s_Reference = ResourceManager:SearchForInstanceByGuid(Guid(object.originalRef.instanceGuid))
		 if(s_Reference == nil) then
		 	print("Unable to find original reference: " .. object.originalRef.instanceGuid)
		 	return
		 end
	else
		 s_Reference = ResourceManager:FindInstanceByGuid(Guid(object.originalRef.partitionGuid), Guid(object.originalRef.instanceGuid))
		 if(s_Reference == nil) then
		 	print("Unable to find original reference: " .. object.originalRef.instanceGuid .. " in partition " .. object.originalRef.partitionGuid)
		 	return
		 end
	end
	s_Reference = _G[s_Reference.typeInfo.name](s_Reference)
	s_Reference:MakeWritable()
	if(object.isDeleted) then
		s_Reference.excluded = true
	end
	if(object.localTransform) then
		s_Reference.blueprintTransform = LinearTransform(object.localTransform) -- LinearTransform(object.localTransform)
	else
		s_Reference.blueprintTransform = LinearTransform(object.transform) -- LinearTransform(object.transform)
	end
end

local function AddCustomObject(object, world)
	--[[for k,v in pairs(object) do
		print("k: " .. k)
		print("v: " .. v)
	end]]--
	local blueprint = ResourceManager:FindInstanceByGuid(Guid(object.blueprintCtrRef.partitionGuid), Guid(object.blueprintCtrRef.instanceGuid))
	if blueprint == nil then
		print('Cannot find blueprint with guid ' .. tostring(blueprint.instanceGuid))
	end

	-- Filter BangerEntityData.
	if blueprint:Is('ObjectBlueprint') then
		local objectBlueprint = ObjectBlueprint(blueprint)
		if objectBlueprint.object and objectBlueprint.object:Is('BangerEntityData') then
			return
		end
	end

	local s_Reference = ReferenceObjectData()
	customRegistry.referenceObjectRegistry:add(s_Reference)
	if(object.localTransform) then	
		s_Reference.blueprintTransform = LinearTransform(object.localTransform)
	else
		s_Reference.blueprintTransform = LinearTransform(object.transform)
	end
	--print("AddCustomObject: " .. object.transform)
	s_Reference.blueprint = Blueprint(blueprint)
	-- s_Reference.blueprint:MakeWritable()

	if(objectVariations[object.variation] == nil) then
		pendingVariations[object.variation] = s_Reference
	else
		s_Reference.objectVariation = objectVariations[object.variation]
	end
	s_Reference.indexInBlueprint = #world.objects + indexCount + 1
	s_Reference.isEventConnectionTarget = Realm.Realm_None
	s_Reference.isPropertyConnectionTarget = Realm.Realm_None

	world.objects:add(s_Reference)
end

local function CreateWorldPart()
	local world = WorldPartData()
	customRegistry.blueprintRegistry:add(world)
	
	--find index
	for _, object in pairs(PrimaryLevel.objects) do
		if object:Is('WorldPartReferenceObjectData') then
			local obj = WorldPartReferenceObjectData(object)
			if obj.blueprint:Is('WorldPartData') then
				local worldPart = WorldPartData(obj.blueprint)
				if #worldPart.objects ~= 0 then
					local rod = worldPart.objects[#worldPart.objects] -- last one in array
					if rod and rod:Is('ReferenceObjectData') then
						rod = ReferenceObjectData(rod)
						if rod.indexInBlueprint > indexCount then
							indexCount = rod.indexInBlueprint
						end
					end
				end
			end
		end
	end

	print('indexCount is:')
	print(indexCount)

	for index, object in pairs(CustomLevelData.data) do
		if(not object.isVanilla) then
			if(not CustomLevelData.vanillaOnly) then
				AddCustomObject(object, world)
			end
		else
			PatchOriginalObject(object, world)
		end
	end

	local s_WorldPartReference = WorldPartReferenceObjectData()
	s_WorldPartReference.blueprint = world

	s_WorldPartReference.isEventConnectionTarget = Realm.Realm_None
	s_WorldPartReference.isPropertyConnectionTarget = Realm.Realm_None
	s_WorldPartReference.excluded = false

	return s_WorldPartReference
end

Events:Subscribe('Partition:Loaded', function(p_Partition)
if SharedUtils:GetLevelName() ~= 'Levels/XP5_003/XP5_003' then
        return
    end
	if p_Partition == nil then
		return
	end
	
	local s_Instances = p_Partition.instances

	for _, l_Instance in pairs(s_Instances) do
		if l_Instance == nil then
			print('Instance is null?')
			break
		end
		if(l_Instance:Is("Blueprint")) then
			--print("-------"..Blueprint(l_Instance).name)
		end
		if(l_Instance.typeInfo.name == "LevelData") then
			local s_Instance = LevelData(l_Instance)
			if(s_Instance.name == SharedUtils:GetLevelName()) then
				print("Primary level")
				s_Instance:MakeWritable()
				PrimaryLevel = s_Instance
				if(SharedUtils:IsClientModule()) then
					NetEvents:Send('MapLoader-BR-XP5-003:GetLevel')
				end
			end
		elseif l_Instance:Is('ObjectVariation') then
			-- Store all variations in a map.
			local variation = ObjectVariation(l_Instance)
			objectVariations[variation.nameHash] = variation
			if pendingVariations[variation.nameHash] ~= nil then
				for _, object in pairs(pendingVariations[variation.nameHash]) do
					object.objectVariation = variation
				end

				pendingVariations[variation.nameHash] = nil
			end
		end
	end
end)

Events:Subscribe('Level:LoadingInfo', function(p_Info)
if SharedUtils:GetLevelName() ~= 'Levels/XP5_003/XP5_003' then
        return
    end
	if(p_Info == "Registering entity resources") then
		if(not CustomLevelData) then
			print("No custom level specified.")
			return
		end

		print("Patching level")
		customRegistry = customRegistry or RegistryContainer(customRegistryGuid)
		local s_WorldPartReference = CreateWorldPart()

		s_WorldPartReference.indexInBlueprint = #PrimaryLevel.objects
		
		PrimaryLevel.objects:add(s_WorldPartReference)
		worldPartRefIndex = #PrimaryLevel.objects
		local s_Container = PrimaryLevel.registryContainer
		s_Container:MakeWritable()
		s_Container.referenceObjectRegistry:add(s_WorldPartReference)
		refObjRegistryIndex = #s_Container.referenceObjectRegistry
		print('Level patched')
	end
end)

Events:Subscribe('Level:Destroy', function()
if SharedUtils:GetLevelName() ~= 'Levels/XP5_003/XP5_003' then
        return
    end
	objectVariations = {}
	pendingVariations = {}
	indexCount = 0
	if worldPartRefIndex ~= nil and PrimaryLevel ~= nil then
		PrimaryLevel.objects:erase(worldPartRefIndex)
	end

	if refObjRegistryIndex ~= nil and PrimaryLevel ~= nil and PrimaryLevel.registryContainer ~= nil then
		PrimaryLevel.registryContainer.referenceObjectRegistry:erase(refObjRegistryIndex)
	end
	worldPartRefIndex = nil
	refObjRegistryIndex = nil
	customRegistry = nil

	-- PrimaryLevel = nil
end)

Events:Subscribe('Level:LoadResources', function()
if SharedUtils:GetLevelName() ~= 'Levels/XP5_003/XP5_003' then
        return
    end
	print("Loading resources")
	objectVariations = {}
	pendingVariations = {}
end)

Events:Subscribe('Level:RegisterEntityResources', function(levelData)
if SharedUtils:GetLevelName() ~= 'Levels/XP5_003/XP5_003' then
        return
    end
	customRegistry = customRegistry or RegistryContainer(customRegistryGuid)
	ResourceManager:AddRegistry(customRegistry, ResourceCompartment.ResourceCompartment_Game)
end)


---Bundles


Events:Subscribe('Level:LoadResources', function()
if SharedUtils:GetLevelName() ~= 'Levels/XP5_003/XP5_003' then
        return
    end
		print('Mounting XP3 Chunks...')
        ResourceManager:MountSuperBundle('xp3chunks')
		print('Mounting XP1 Chunks...')
        ResourceManager:MountSuperBundle('xp1chunks')
		print('Mounting Alborz Chunks...')
        ResourceManager:MountSuperBundle('levels/xp3_alborz/xp3_alborz')
		print('Mounting Shield Chunks...')
        ResourceManager:MountSuperBundle('levels/xp3_Shield/xp3_Shield')
		print('Mounting Wake Chunks...')
        ResourceManager:MountSuperBundle('levels/xp1_004/xp1_004')
end)


Hooks:Install('ResourceManager:LoadBundles', 500, function(hook, bundles, compartment)
if SharedUtils:GetLevelName() ~= 'Levels/XP5_003/XP5_003' then
        return
    end


        if #bundles == 1 and bundles[1] == SharedUtils:GetLevelName() then
            print('Only loading \''..bundles[1]..'\', injecting bundles...')

            bundles = {
			    'levels/xp3_Shield/xp3_Shield', -- xp3_Shield
				'levels/xp3_alborz/xp3_alborz', -- xp3_alborz
				'levels/xp1_004/xp1_004', -- xp1_003
                bundles[1],
            }

            hook:Pass(bundles, compartment)

        else

            i = #bundles
            print('Loading additional bundle \''..bundles[i]..'\'...')

        end

end)


-- 2D tree removal

ParameterModificationType = {
	ModifyParameters = 0,		-- Modifies parameters if they exist.
	ModifyOrAddParameters = 1,	-- Modifies parameters if they exist, adds them if they don't.
	ReplaceParameters = 2,		-- Clears existing parameters and adds the specified parameters.
}

local CONFIG = require('__shared/config')

Events:Subscribe('Partition:Loaded', function(partition)
	if partition.primaryInstance:Is('MeshVariationDatabase') then
		local meshVariationDatabase = MeshVariationDatabase(partition.primaryInstance)

		ModifyDatabase(meshVariationDatabase)
	end
end)

function ModifyDatabase(meshVariationDatabase)
	for index, entry in pairs(meshVariationDatabase.entries) do
		entry = MeshVariationDatabaseEntry(entry)

		local meshConfig = CONFIG[entry.mesh.instanceGuid:ToString('D')]

		if meshConfig ~= nil then
			if entry.variationAssetNameHash == (meshConfig.VARIATION_HASH or 0) then
				ModifyEntry(entry, meshConfig)
			end
		end
	end
end

function ModifyEntry(entry, meshConfig)
	entry:MakeWritable()

	for materialIndex, materialConfig in pairs(meshConfig.MATERIALS) do
		local meshMaterial = entry.materials[materialIndex].material

		local shaderConfig = materialConfig.SHADER
		if shaderConfig ~= nil then	
			CallOrRegisterLoadHandler(meshMaterial, shaderConfig, ModifyMeshMaterial)
		end

		local textureConfig = materialConfig.TEXTURES
		if textureConfig ~= nil then
			if textureConfig.TYPE == ParameterModificationType.ReplaceParameters then
				entry.materials[materialIndex] = MeshVariationDatabaseMaterial()

				CallOrRegisterLoadHandler(meshMaterial, entry.materials[materialIndex], function(databaseMaterial, meshMaterial)
					databaseMaterial.material = MeshMaterial(meshMaterial)
				end)
			end

			if textureConfig.PARAMETERS ~= nil then
				ModifyTextureParameters(entry.materials[materialIndex], textureConfig)
			end
		end
	end
end

function CallOrRegisterLoadHandler(instance, userData, handler)
	if instance.isLazyLoaded then
		instance:RegisterLoadHandler(userData, handler)
	else
		handler(userData, instance)
	end
end

function ModifyMeshMaterial(shaderConfig, meshMaterial)
	meshMaterial = MeshMaterial(meshMaterial)
	meshMaterial:MakeWritable()

	if shaderConfig.NAME ~= nil then
		local shaderGraph = ShaderGraph()
		shaderGraph.name = shaderConfig.NAME

		meshMaterial.shader.shader = shaderGraph
	end

	if shaderConfig.TYPE == ParameterModificationType.ReplaceParameters then
		meshMaterial.shader.vectorParameters:clear()
	end

	if shaderConfig.PARAMETERS ~= nil then
		ModifyVectorParameters(shaderConfig, meshMaterial)		
	end
end

function ModifyVectorParameters(shaderConfig, meshMaterial)	
	local parameterIndexMap = CreateParamaterIndexMap(meshMaterial.shader.vectorParameters)
	
	for parameterName, parameterConfig in pairs(shaderConfig.PARAMETERS) do	
		if parameterIndexMap[parameterName] ~= nil then
			local parameter = meshMaterial.shader.vectorParameters[parameterIndexMap[parameterName]]
			parameter.value = parameterConfig.VALUE
		elseif shaderConfig.TYPE ~= ParameterModificationType.ModifyParameters then
			local parameter = VectorShaderParameter()
			parameter.parameterName = parameterName
			parameter.parameterType = parameterConfig.TYPE
			parameter.value = parameterConfig.VALUE

			meshMaterial.shader.vectorParameters:add(parameter)
		else
			print("ERROR: Invalid vector parameter specified: no "..parameterName.." parameter for material: "..meshMaterial.instanceGuid:ToString('P'))
		end
	end
end


function ModifyTextureParameters(databaseMaterial, textureConfig)
	local parameterIndexMap = CreateParamaterIndexMap(databaseMaterial.textureParameters)

	for parameterName, textureName in pairs(textureConfig.PARAMETERS) do
		local texture = TextureAsset()
		texture.name = textureName

		if parameterIndexMap[parameterName] ~= nil then
			local parameter = databaseMaterial.textureParameters[parameterIndexMap[parameterName]]
			parameter.value = texture
		elseif textureConfig.TYPE ~= ParameterModificationType.ModifyParameters then
			local parameter = TextureShaderParameter()
			parameter.parameterName = parameterName
			parameter.value = texture

			databaseMaterial.textureParameters:add(parameter)
		else
			print("ERROR: Invalid texture parameter specified: no "..parameterName.." parameter for material: "..databaseMaterial.material.instanceGuid:ToString('P'))
		end
	end
end


function CreateParamaterIndexMap(parameters)
	local indexMap = {}

	for index, parameter in ipairs(parameters) do
		indexMap[parameter.parameterName] = index
	end

	return indexMap
end

