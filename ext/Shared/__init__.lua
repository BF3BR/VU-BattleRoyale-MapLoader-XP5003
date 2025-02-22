GameObjectOriginType = {
	Vanilla = 1,
	Custom = 2,
	CustomChild = 3
}

-- This is a global table that stores the save file data as a Lua table. Will be populated on-demand by
-- the server via NetEvents on the client-side
g_CustomLevelData = nil

-- Stores LevelData DataContainer guids.
local m_CustomLevelData = nil

local m_IndexCount = 0
local m_OriginalLevelIndeces = {}
local m_LastLoadedMap = nil
local m_ObjectVariations = {}
local m_PendingVariations = {}

local function PatchOriginalObject(p_Object, p_World)
	if p_Object.originalRef == nil then
		print("Object without original reference found, dynamic object?")
		return
	end
	local s_Reference = nil
	if p_Object.originalRef.partitionGuid == nil or p_Object.originalRef.partitionGuid == "nil" then -- perform a search without partitionguid
		 s_Reference = ResourceManager:SearchForInstanceByGuid(Guid(p_Object.originalRef.instanceGuid))
		 if s_Reference == nil then
		 	print("Unable to find original reference: " .. p_Object.originalRef.instanceGuid)
		 	return
		 end
	else
		 s_Reference = ResourceManager:FindInstanceByGuid(Guid(p_Object.originalRef.partitionGuid), Guid(p_Object.originalRef.instanceGuid))
		 if s_Reference == nil then
		 	print("Unable to find original reference: " .. p_Object.originalRef.instanceGuid .. " in partition " .. p_Object.originalRef.partitionGuid)
		 	return
		 end
	end
	s_Reference = _G[s_Reference.typeInfo.name](s_Reference)
	s_Reference:MakeWritable()
	if p_Object.isDeleted then
		s_Reference.excluded = true
	end
	if p_Object.localTransform then
		s_Reference.blueprintTransform = LinearTransform(p_Object.localTransform) -- LinearTransform(p_Object.localTransform)
	else
		s_Reference.blueprintTransform = LinearTransform(p_Object.transform) -- LinearTransform(p_Object.transform)
	end
end

local function AddCustomObject(p_Object, p_World, p_RegistryContainer)
	local s_Blueprint = ResourceManager:FindInstanceByGuid(Guid(p_Object.blueprintCtrRef.partitionGuid), Guid(p_Object.blueprintCtrRef.instanceGuid))
	if s_Blueprint == nil then
		print('Cannot find blueprint with guid ' .. tostring(p_Object.blueprintCtrRef.instanceGuid))
	end

	-- Filter BangerEntityData.
	if s_Blueprint:Is('ObjectBlueprint') then
		local s_ObjectBlueprint = ObjectBlueprint(s_Blueprint)
		if s_ObjectBlueprint.object and s_ObjectBlueprint.object:Is('BangerEntityData') then
			return
		end
	end

	local s_Reference = ReferenceObjectData()
	p_RegistryContainer.referenceObjectRegistry:add(s_Reference)
	if p_Object.localTransform then	
		s_Reference.blueprintTransform = LinearTransform(p_Object.localTransform)
	else
		s_Reference.blueprintTransform = LinearTransform(p_Object.transform)
	end
	--print("AddCustomObject: " .. p_Object.transform)
	s_Reference.blueprint = Blueprint(s_Blueprint)
	-- s_Reference.blueprint:MakeWritable()

	if m_ObjectVariations[p_Object.variation] == nil then
		m_PendingVariations[p_Object.variation] = s_Reference
	else
		s_Reference.objectVariation = m_ObjectVariations[p_Object.variation]
	end
	s_Reference.indexInBlueprint = #p_World.objects + m_IndexCount + 1
	s_Reference.isEventConnectionTarget = Realm.Realm_None
	s_Reference.isPropertyConnectionTarget = Realm.Realm_None

	p_World.objects:add(s_Reference)
end

local function CreateWorldPart(p_PrimaryLevel, p_RegistryContainer)
	local s_World = WorldPartData()
	p_RegistryContainer.blueprintRegistry:add(s_World)
	
	--find index
	for _, l_Object in pairs(p_PrimaryLevel.objects) do
		if l_Object:Is('WorldPartReferenceObjectData') then
			local l_RefObjectData = WorldPartReferenceObjectData(l_Object)
			if l_RefObjectData.blueprint:Is('WorldPartData') then
				local s_WorldPart = WorldPartData(l_RefObjectData.blueprint)
				if #s_WorldPart.objects ~= 0 then
					local s_ROD = s_WorldPart.objects[#s_WorldPart.objects] -- last one in array
					if s_ROD and s_ROD:Is('ReferenceObjectData') then
						s_ROD = ReferenceObjectData(s_ROD)
						if s_ROD.indexInBlueprint > m_IndexCount then
							m_IndexCount = s_ROD.indexInBlueprint
						end
					end
				end
			end
		end
	end
	-- m_IndexCount = 30000
	print('Index count is: '..tostring(m_IndexCount))

	for _, l_Object in pairs(g_CustomLevelData.data) do
		if l_Object.origin == GameObjectOriginType.Custom then
			if not g_CustomLevelData.vanillaOnly then
				AddCustomObject(l_Object, s_World, p_RegistryContainer)
			end
		elseif l_Object.origin == GameObjectOriginType.Vanilla then
			PatchOriginalObject(l_Object, s_World)
		end
		-- TODO handle CustomChild
	end
	m_LastLoadedMap = SharedUtils:GetLevelName()

	local s_WorldPartReference = WorldPartReferenceObjectData()
	s_WorldPartReference.blueprint = s_World

	s_WorldPartReference.isEventConnectionTarget = Realm.Realm_None
	s_WorldPartReference.isPropertyConnectionTarget = Realm.Realm_None
	s_WorldPartReference.excluded = false

	return s_WorldPartReference
end

-- nº 1 in calling order
Events:Subscribe('Level:LoadResources', function()
	print("-----Loading resources")
	m_ObjectVariations = {}
	m_PendingVariations = {}
end)

-- nº 2 in calling order 
Events:Subscribe('Partition:Loaded', function(p_Partition)
	if p_Partition == nil then
		return
	end
	
	local s_Instances = p_Partition.instances

	for _, l_Instance in pairs(s_Instances) do
		if l_Instance == nil then
			print('Instance is null?')
			break
		end
		-- if l_Instance:Is("Blueprint") then
			--print("-------"..Blueprint(l_Instance).name)
		-- end
		if l_Instance.typeInfo.name == "LevelData" then
			local s_Instance = LevelData(l_Instance)
			if (s_Instance.name == SharedUtils:GetLevelName()) then
				print("----Registering PrimaryLevel guids")
				s_Instance:MakeWritable()

				m_CustomLevelData = {
					instanceGuid = s_Instance.instanceGuid,
					partitionGuid = s_Instance.partitionGuid
				}
				if (SharedUtils:IsClientModule()) then
					NetEvents:Send('MapLoader-BR-XP5-003:GetLevel')
				end
			end
		elseif l_Instance:Is('ObjectVariation') then
			-- Store all variations in a map.
			local s_Variation = ObjectVariation(l_Instance)
			m_ObjectVariations[s_Variation.nameHash] = s_Variation
			if m_PendingVariations[s_Variation.nameHash] ~= nil then
				for _, l_Object in pairs(m_PendingVariations[s_Variation.nameHash]) do
					l_Object.objectVariation = s_Variation
				end

				m_PendingVariations[s_Variation.nameHash] = nil
			end
		end
	end
end)

-- nº 3 in calling order
Events:Subscribe('Level:LoadingInfo', function(p_Info)
	if p_Info == "Registering entity resources" then
		print("-----Loading Info - Registering entity resources")

		if not g_CustomLevelData then
			print("No custom level specified.")
			return
		end

		if m_CustomLevelData == nil then
			print("m_CustomLevelData is nil, something went wrong")
			return
		end

		local s_PrimaryLevel = ResourceManager:FindInstanceByGuid(m_CustomLevelData.partitionGuid, m_CustomLevelData.instanceGuid)

		if s_PrimaryLevel == nil then
			print("Couldn\'t find PrimaryLevel DataContainer, aborting")
			return
		end

		s_PrimaryLevel = LevelData(s_PrimaryLevel)

		if m_LastLoadedMap == SharedUtils:GetLevelName() then
			print('Same map loading, skipping')
			return
		end

		print("Patching level")
		local s_RegistryContainer = s_PrimaryLevel.registryContainer
		if s_RegistryContainer == nil then
			print('No registryContainer found, this shouldn\'t happen')
		end
		s_RegistryContainer = RegistryContainer(s_RegistryContainer)
		s_RegistryContainer:MakeWritable()

		local s_WorldPartReference = CreateWorldPart(s_PrimaryLevel, s_RegistryContainer)

		s_WorldPartReference.indexInBlueprint = #s_PrimaryLevel.objects
		
		s_PrimaryLevel.objects:add(s_WorldPartReference)

		-- Save original indeces in case LevelData has to be reset to default state later.
		m_OriginalLevelIndeces = {
			objects = #s_PrimaryLevel.objects,
			ROFs = #s_RegistryContainer.referenceObjectRegistry,
			blueprints = #s_RegistryContainer.blueprintRegistry,
			entity = #s_RegistryContainer.entityRegistry
		}
		s_RegistryContainer.referenceObjectRegistry:add(s_WorldPartReference)
		print('Level patched')
	end
end)

-- Remove all DataContainer references and reset vars
Events:Subscribe('Level:Destroy', function()
	m_ObjectVariations = {}
	m_PendingVariations = {}
	m_IndexCount = 0

	-- TODO: remove all custom objects from level registry and leveldata if next round is
	-- the same map but a different save, once that is implemented. If it's a different map
	-- there is no need to clear anything, as the leveldata will be unloaded and a new one loaded
end)

Events:Subscribe('Level:LoadResources', function()
		print('Mounting XP3 Chunks...')
        ResourceManager:MountSuperBundle('xp3chunks')
		print('Mounting XP1 Chunks...')
        ResourceManager:MountSuperBundle('xp1chunks')
		print('Mounting XP2 Chunks...')
        ResourceManager:MountSuperBundle('xp2chunks')
		print('Mounting Alborz Chunks...')
        ResourceManager:MountSuperBundle('levels/xp3_alborz/xp3_alborz')
		print('Mounting Shield Chunks...')
        ResourceManager:MountSuperBundle('levels/xp3_Shield/xp3_Shield')
		print('Mounting Wake Chunks...')
        ResourceManager:MountSuperBundle('levels/xp1_004/xp1_004')
end)


Hooks:Install('ResourceManager:LoadBundles', 500, function(hook, bundles, compartment)

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