-----------------------------------------------------------------------------------------------
-- Client Lua Script for Athena 
-- Original CraftingGrid routines Copyright (c) Carbine, LLC and NCSOFT Corporation
-- Additional function & changes Copyright (c) DoctorVanGogh on Wildstar Forums. All rights reserved
-- Wildstar ©2011-2014 Carbine, LLC and NCSOFT Corporation
-----------------------------------------------------------------------------------------------
 
require "Window"
require "CraftingLib"
 
-----------------------------------------------------------------------------------------------
-- Athena Module Definition
-----------------------------------------------------------------------------------------------
local Athena = Apollo.GetPackage("Gemini:Addon-1.0").tPackage:NewAddon("Athena", false, { "CraftingGrid", }, "Gemini:Hook-1.0")

-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
local ktHintArrowColors = {
	[CraftingLib.CodeEnumCraftingDiscoveryHotCold.Cold] = ApolloColor.new("ConMinor"),
	[CraftingLib.CodeEnumCraftingDiscoveryHotCold.Warm] = ApolloColor.new("ConModerate"),
	[CraftingLib.CodeEnumCraftingDiscoveryHotCold.Hot] = ApolloColor.new("ConTough")
}

local ktLastAttemptHotOrColdString =
{
	[CraftingLib.CodeEnumCraftingDiscoveryHotCold.Cold] 	= Apollo.GetString("CoordCrafting_Cold"),
	[CraftingLib.CodeEnumCraftingDiscoveryHotCold.Warm] 	= Apollo.GetString("CoordCrafting_Warm"),
	[CraftingLib.CodeEnumCraftingDiscoveryHotCold.Hot] 		= Apollo.GetString("CoordCrafting_Hot"),
	[CraftingLib.CodeEnumCraftingDiscoveryHotCold.Success] 	= Apollo.GetString("CoordCrafting_Success"),
}

local ktHotOrColdStringToHotCold =
{
	[Apollo.GetString("CoordCrafting_Cold")]	= CraftingLib.CodeEnumCraftingDiscoveryHotCold.Cold,
	[Apollo.GetString("CoordCrafting_Warm")] 	= CraftingLib.CodeEnumCraftingDiscoveryHotCold.Warm,
	[Apollo.GetString("CoordCrafting_Hot")]		= CraftingLib.CodeEnumCraftingDiscoveryHotCold.Hot,
	[Apollo.GetString("CoordCrafting_Success")] = CraftingLib.CodeEnumCraftingDiscoveryHotCold.Success,
}

local mtSchematicLog = {
	__newindex = function(t, k, v)
		--Print("INFO: Athena, SchematicLog.__newindex ["..tostring(k).."]=".. tostring(v))			
		-- only remove entries if we actually discovered *all* subrecipes			
		if v == nil then
			local tSchematicInfo = CraftingLib.GetSchematicInfo(k)	
			local allKnown = true
		
			for _ , tSchem in ipairs(tSchematicInfo.tSubRecipes) do
				if tSchem.bIsUndiscovered then
					allKnown = false
					break
				end			
			end
			if allKnown then
				rawset(t, k, nil)
			end	
		else
			rawset(t, k, v)
		end
	end
}


-----------------------------------------------------------------------------------------------
-- Athena OnInitialize
-----------------------------------------------------------------------------------------------
function Athena:OnInitialize()

	self.IsCraftingGridHooked = self:Hook_CraftingGrid()
	
	-- preinitialize in case there is *no* data to deserialize in <see cref="Athena.OnRestore" /> and it never
	-- get's called.
	self.tLastMarkersList = {}
	setmetatable(self.tLastMarkersList, mtSchematicLog)	
		
	if self.IsCraftingGridHooked then	
		self:CheckForCraftingGridMarkerListInitialization()
	end
end


-----------------------------------------------------------------------------------------------
-- Athena Hooks for CraftingGrid
-----------------------------------------------------------------------------------------------
function Athena:RedrawAll() 	
	-- colorize markers - assumes windows are found in same order as attempts are logged	
	local tCurrentCraft = CraftingLib.GetCurrentCraft()	
	
	if tCurrentCraft and tCurrentCraft.nSchematicId and self.tLastMarkersList[tCurrentCraft.nSchematicId] then				
		local markerWindows = {}
		
		for idx, child in ipairs(self.tCraftingGrid.wndMain:FindChild("CoordinateSchematic"):GetChildren()) do
			if child:GetName() == "GridLastMarker" then
				table.insert(markerWindows, child)
			end
		end								
	
		for idx , tAttempt in pairs(self.tLastMarkersList[tCurrentCraft.nSchematicId]) do
			local wndMarker = markerWindows[idx]
			if wndMarker then
				local eHotCold = tAttempt.eHotCold or ktHotOrColdStringToHotCold[tAttempt.strHotOrCold]
			
				if eHotCold  == nil then
					--Print("WARN: No raw hot/cold data for schematic "..tCurrentCraft.nSchematicId.." attempt #"..idx)
				else
					--Print("INFO: schematic "..tCurrentCraft.nSchematicId.." attempt #"..idx.." = ".. eHotCold)
					wndMarker:SetBGColor(ktHintArrowColors[eHotCold])
				end
			end		
		end
	end			
end

function Athena:OnDocumentReady()
	Athena:CopyRestoredMarkersToCraftingGrid()
end

-----------------------------------------------------------------------------------------------
-- Athena functions
-----------------------------------------------------------------------------------------------
-- Define general functions here
function Athena:Hook_CraftingGrid()
	local tCraftingGrid = Apollo.GetAddon("CraftingGrid")
	if tCraftingGrid == nil then
		return false
	end
	
	self:PostHook(tCraftingGrid ,"RedrawAll")
	self:PostHook(tCraftingGrid ,"OnDocumentReady")	
	
	-- store reference to <see cref="CraftingGrid" />
	self.tCraftingGrid = tCraftingGrid		
	
	self:CheckForCraftingGridMarkerListInitialization()
			
	return true
end

function Athena:CheckForCraftingGridMarkerListInitialization()
	if not self.IsCraftingGridHooked then
		return
	end

	-- check if <see cref="CraftingGrid" />'s loading of <see cref="CraftingGrid.xmlDoc" /> and it's subsequent call
	-- to <see cref="CraftingGrid.OnDocumentReady" /> has already completed (possibly asynchronously before we even got loaded).
	-- if so, <see cref="CraftingGrid.tLastMarkersList" /> is non <see langword="nil" />, so copy our values over
	if self.tCraftingGrid.tLastMarkersList ~= nil then
		self:CopyRestoredMarkersToCraftingGrid()
	end
end


function Athena:CopyRestoredMarkersToCraftingGrid() 	
	if not self.IsCraftingGridHooked then
		return
	end

	self.tCraftingGrid.tLastMarkersList = self.tLastMarkersList
end



function Athena:StoreV1Data(tMarkers)
	local tSave = {
		version = "1"
	}
			
	tSave.tJournal = {}
	for idSchematic, tJournal in pairs(tMarkers) do
		local tEntries = {}
		tSave.tJournal[idSchematic] = tEntries 
	
		for entryKey, tAttempt in ipairs(tJournal) do
			--tAttempt  has:
			--	["nPosX"] = nNewPosX,
			--	["nPosY"] = nNewPosY,
			--	["idSchematic"] = nSchematicId,
			--	["strTooltip"] = strTooltipSaved,
			--	["strHotOrCold"] = Apollo.GetString("CoordCrafting_ViewLastCraft"),
			--  ["eDirection"]
				
			tEntries[entryKey] = {
				["nPosX"] 			= tAttempt.nPosX,
				["nPosY"] 			= tAttempt.nPosY,
				["strTooltip"] 		= tAttempt.strTooltip,
				["eHotCold"] 		= tAttempt.eHotCold or ktHotOrColdStringToHotCold[tAttempt.strHotOrCold],
				["eDirection"] 		= tAttempt.eDirection								
			}		
		end
	end	

	return tSave
end

function Athena:RestoreV1Data(tData) 
	local tJournal = {}
	
	for idSchematic, tSchematicAttempts in pairs(tData.tJournal) do
		local tEntries = {}
		tJournal[idSchematic] = tEntries 
	
		for entryKey, tAttempt in pairs(tSchematicAttempts) do
			--tEntries[entryKey] = {
			--	nPosX = tAttempt.nPosX,
			--	nPosY = tAttempt.nPosY,
			--	strTooltip = tAttempt.strTooltip,
			--	eHotCold = tAttempt.eHotCold,
			--	eDirection = tAttempt.eDirection								
			--}		

			local tEntry = {
				["nPosX"] 			= tAttempt.nPosX,
				["nPosY"] 			= tAttempt.nPosY,
				["strTooltip"] 		= tAttempt.strTooltip,
				["eHotCold"] 		= tAttempt.eHotCold,
				["eDirection"] 		= tAttempt.eDirection,
				-- unpersisted derived values
				["strHotOrCold"] 	= ktLastAttemptHotOrColdString[tAttempt.eHotCold],
				["idSchematic"] 	= idSchematic
			}		
			tEntries[entryKey] = tEntry 			
		end
	end		
	
	return tJournal 
end	


function Athena:OnSaveSettings(eLevel)
	-- We save at character level,
	if (eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character) then
		return
	end
	
	if self.IsCraftingGridHooked then	
		return self:StoreV1Data(self.tCraftingGrid.tLastMarkersList)
	else
		-- in case something went wrong with the <see cref=CraftingGrid" /> hook, just make sure our stored data
		-- get's persisted correctly
		return self:StoreV1Data(self.tLastMarkersList)	
	end
end

function Athena:OnRestoreSettings(eLevel, tData)

	-- We restore at character level,
	if (eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character) then
		return
	end

	local tLastMarkers = {}	
			
	local version = tData.version	
	
	if version == nil then
		-- sry, can't read unversioned data
	else
		if version == "1" then
			tLastMarkers = self:RestoreV1Data(tData)	
		end		
	end	
	
	setmetatable(tLastMarkers, mtSchematicLog)	
	
	-- Do *NOT* deserialize into <see cref="CraftingGrid" />'s  <see cref="CraftingGrid.tLastMarkersList" /> yet, 
	-- it gets initialized to <code>{}</code> in <see cref="CraftingGrid.OnDocumentReady"/>, which will be called
	-- *after* we have finished, so any setting here is pointless.
	-- Instead store a reference, so our own OnDocumentReady hook from <see cref="CreateDerivedCraftingGridMetatable" />  
	-- can copy the value after <see cref="CraftingGrid" />'s call.
	self.tLastMarkersList = tLastMarkers
	
	self:CheckForCraftingGridMarkerListInitialization()
	
end

