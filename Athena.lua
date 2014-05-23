-----------------------------------------------------------------------------------------------
-- Client Lua Script for Athena 
-- Copyright (c) DoctorVanGogh on Wildstar Forums. All rights reserved
-- Wildstar ©2011-2014 Carbine, LLC and NCSOFT Corporation
-----------------------------------------------------------------------------------------------
 
require "Window"
require "CraftingLib"
 
-----------------------------------------------------------------------------------------------
-- Athena Module Definition
-----------------------------------------------------------------------------------------------
local NAME = "Athena"

local Athena = Apollo.GetPackage("Gemini:Addon-1.0").tPackage:NewAddon(
																NAME, 
																true, 
																{ 
																	"CraftingGrid", 
																	"Gemini:Logging-1.2", 
																	"GeminiColor",
																	"Gemini:Locale-1.0"
																}, 
																"Gemini:Hook-1.0")
															
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
local ktHintArrowDefaultColors = {
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

local glog
local GeminiColor
local GeminiLocale
local GeminiLogging

-----------------------------------------------------------------------------------------------
-- Athena OnInitialize
-----------------------------------------------------------------------------------------------
function Athena:OnInitialize()
	GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	glog = GeminiLogging:GetLogger({
		level = GeminiLogging.DEBUG,
		pattern = "%d [%c:%n] %l - %m",
		appender = "GeminiConsole"
	})	

	self.log = glog
	
	GeminiColor= Apollo.GetPackage("GeminiColor").tPackage
	self.gcolor = GeminiColor
		
	
	GeminiLocale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage		
	self.localization = GeminiLocale:GetLocale(NAME)
	
	self.tColors = ktHintArrowDefaultColors
	
	self.IsCraftingGridHooked = self:Hook_CraftingGrid()
	
	-- preinitialize in case there is *no* data to deserialize in <see cref="Athena.OnRestore" /> and it never
	-- get's called.
	self.tLastMarkersList = setmetatable({}, mtSchematicLog)	
		
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("AthenaConfigForm.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)		
	
	if self.IsCraftingGridHooked then	
		self:CheckForCraftingGridMarkerListInitialization()
	end
end


function Athena:OnDocumentReady()
	glog:debug(string.format("OnDocumentReady"))

	if self.xmlDoc == nil then
		return
	end
	
	self.wndMain = Apollo.LoadForm(self.xmlDoc, "AthenaConfigForm", nil, self)
	self.xmlDoc = nil;
	
	Apollo.RegisterSlashCommand("athena", "OnSlashCommand", self)
	
	self:InitializeForm()
	
	self.wndMain:Show(false);
end

function Athena:OnSlashCommand(strCommand, strParam)
	self:ToggleWindow()
end

function Athena:OnConfigure(sCommand, sArgs)
	self.wndMain:Show(false)
	self:ToggleWindow()
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
					wndMarker:SetBGColor(self.tColors[eHotCold])
				end
			end		
		end
	end			
end

function Athena:CraftingGrid_OnDocumentReady()
	Athena:CopyRestoredMarkersToCraftingGrid()
end

-----------------------------------------------------------------------------------------------
-- Athena functions
-----------------------------------------------------------------------------------------------
function Athena:UpdateColorContainer(container, key)	
	local color = self.tColors[key]
	local colorHex
	
	glog:debug(string.format("UpdateColorContainer(%s) - color=%s", tostring(key), tostring(color)))
		
	if type(color) == "table" then
		colorHex = self.gcolor:RGBAPercToHex(color.r, color.g, color.b, color.a)
	elseif type(color) == "string"  then
		colorHex = color
	elseif type(color) == "userdata" then
		color = color:ToTable()
		colorHex = self.gcolor:RGBAPercToHex(color.r, color.g, color.b, color.a)		
	end
	
	container:SetData(key)
	
	local picker = container:FindChild("ColorPickerButton")
	
	picker:UpdatePixie(1, {
		strSprite = "BasicSprites:WhiteFill",
		cr = color ,
		loc = { fPoints = {0,0,1,1}, nOffsets = {4,4,-4,-3}}		
	})
	picker:SetData(colorHex)
	local edit = container:FindChild("ColorValueEdit")
	edit:SetText(colorHex:upper())

	local preview = container:FindChild("ArrowPreview")
	preview:SetBGColor(color)
end


function Athena:InitializeForm()
	if not self.wndMain then
		return
	end
	
	GeminiLocale:TranslateWindow(self.localization, self.wndMain)		

	self.wndMain:FindChild("HeaderLabel"):SetText(NAME)
	local tColors = {
		["ColorHot"] = CraftingLib.CodeEnumCraftingDiscoveryHotCold.Hot,
		["ColorWarm"] = CraftingLib.CodeEnumCraftingDiscoveryHotCold.Warm,
		["ColorCold"] = CraftingLib.CodeEnumCraftingDiscoveryHotCold.Cold	
	}
	
	for strName, key in pairs(tColors) do
		self:UpdateColorContainer(self.wndMain:FindChild(strName), key)
	end
	
	if self.locSavedWindowLoc then
		self.wndMain:MoveToLocation(self.locSavedWindowLoc)
	end	
end


-- Define general functions here
function Athena:Hook_CraftingGrid()
	local tCraftingGrid = Apollo.GetAddon("CraftingGrid")
	if tCraftingGrid == nil then
		return false
	end
	
	self:PostHook(tCraftingGrid ,"RedrawAll")
	self:PostHook(tCraftingGrid ,"OnDocumentReady", "CraftingGrid_OnDocumentReady")	
	
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
	
	
	tSave.tColors = {}
	for key,col in pairs(self.tColors) do	
		if type(col) == "table" then
			tSave.tColors[key] = self.gcolor:RGBAPercToHex(col.r, col.g, col.b, col.a)
		elseif type(col) == "string"  then
			tSave.tColors[key] = col
		elseif type(col) == "userdata" then
			local color = col:ToTable()
			tSave.tColors[key] = self.gcolor:RGBAPercToHex(color.r, color.g, color.b, color.a)		
		end	
	end	
	
	local locWindowLocation = self.wndMain and self.wndMain:GetLocation() or self.locSavedWindowLoc						
	tSave.tWindowLocation = locWindowLocation and locWindowLocation:ToTable() or nil

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
		
	return tJournal, tData.tColors, tData.tWindowLocation 
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

	local tLastMarkers, tColors, tWindowLocation
			
	local version = tData.version	
	
	if version == nil then
		-- sry, can't read unversioned data
	else
		if version == "1" then
			tLastMarkers, tColors, tWindowLocation = self:RestoreV1Data(tData)	
		end		
	end		
		
	--[[
		 Do *NOT* deserialize into <see cref="CraftingGrid" />'s  <see cref="CraftingGrid.tLastMarkersList" /> yet, 
	 	it gets initialized to <code>{}</code> in <see cref="CraftingGrid.OnDocumentReady"/>, which will be called
	 	*after* we have finished, so any setting here is pointless.
	 	Instead store a reference, so our own OnDocumentReady hook from <see cref="CreateDerivedCraftingGridMetatable" />  
	 	can copy the value after <see cref="CraftingGrid" />'s call.
	]]
	self.tLastMarkersList = setmetatable(tLastMarkers or {}, mtSchematicLog)	
	self.tColors = tColors or ktHintArrowDefaultColors	
	
	if tWindowLocation then
		self.locSavedWindowLoc = WindowLocation.new(tWindowLocation)	
	end

	self:CheckForCraftingGridMarkerListInitialization()
	
end


---------------------------------------------------------------------------------------------------
-- AthenaConfigForm Functions
---------------------------------------------------------------------------------------------------
function Athena:ToggleWindow( wndHandler, wndControl, eMouseButton )
	if self.wndMain:IsVisible() then
		self.wndMain:Close()
	else
		self:InitializeForm()
	
		self.wndMain:Show(true)
		self.wndMain:ToFront()
	end
end

function Athena:WindowMove( wndHandler, wndControl, nOldLeft, nOldTop, nOldRight, nOldBottom )
	self.locSavedWindowLoc = self.wndMain:GetLocation()
end


function Athena:ColorValueChanged( wndHandler, wndControl, strText )
	local bFound, _, strKey = strText:find("^(#?%x%x%x%x%x%x%x%x)$")	
	glog:debug(string.format("ColorValueChanged(%s)", tostring(bFound)))	
	
	if bFound then
		local parent = wndControl:GetParent()
		local key = parent:GetData()

		self.tColors[key] = strText
		self:UpdateColorContainer(parent, key)
	end
end

function Athena:ColorPickerSignal( wndHandler, wndControl, eMouseButton )
	local parent = wndControl:GetParent()
	self.gcolor:ShowColorPicker(self, "OnColorPicked", true, wndControl:GetData(), {container = parent, key= parent:GetData()})
end

function Athena:OnColorPicked(strColor, token)
	glog:debug(string.format("OnColorPicked(%s) - key=%s", tostring(strColor), tostring(token and token.key)))

	local key = token.key
	local container = token.container
	
	self.tColors[key] = strColor
	self:UpdateColorContainer(container, key)
end


