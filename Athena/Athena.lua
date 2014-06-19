-----------------------------------------------------------------------------------------------
-- Client Lua Script for Athena 
-- Copyright (c) DoctorVanGogh on Wildstar Forums. All rights reserved
-- Wildstar ©2011-2014 Carbine, LLC and NCSOFT Corporation
-----------------------------------------------------------------------------------------------
 
require "Window"
require "CraftingLib"
require "ApolloColor"
 
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

local kstrDefaultLogLevel = "WARN"
local kfDefaultMarkerOpacity = 1.0

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
		level = GeminiLogging.INFO,
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
	self.tLastMarkersList = {}
	
	-- init log level
	self.strLogLevel = kstrDefaultLogLevel
	
	-- init marker opacity
	self.fMarkerOpacity = kfDefaultMarkerOpacity 
	
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("AthenaConfigForm.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)		
	
	if self.IsCraftingGridHooked then	
		self:CheckForCraftingGridMarkerListInitialization()
	end
end


function Athena:OnDocumentReady()
	glog:debug("OnDocumentReady")

	if self.xmlDoc == nil then
		return
	end
	
	self.wndMain = Apollo.LoadForm(self.xmlDoc, "AthenaConfigForm", nil, self)	
	self.wndMain:FindChild("HeaderLabel"):SetText(NAME)
	
	GeminiLocale:TranslateWindow(self.localization, self.wndMain)			
	
	self.wndLogLevelsPopup = self.wndMain:FindChild("LogLevelChoices")
	self.wndLogLevelsPopup:Show(false)
		
	self.wndMain:FindChild("LogLevelButton"):AttachWindow(self.wndLogLevelsPopup)
	self.xmlDoc = nil
	
	Apollo.RegisterSlashCommand("athena", "OnSlashCommand", self)
	
	self:InitializeForm()
	
	self.wndMain:Show(false);
	
	Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
	
end

function Athena:OnSlashCommand(strCommand, strParam)
	self:ToggleWindow()
end

function Athena:OnConfigure(sCommand, sArgs)
	if self.wndMain then
		self.wndMain:Show(false)
		self:ToggleWindow()
	end
end


function Athena:OnWindowManagementReady()
    Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = "Athena"})
end

-----------------------------------------------------------------------------------------------
-- Athena Hooks for CraftingGrid
-----------------------------------------------------------------------------------------------
function Athena:RedrawAll() 	
	if not self.tCraftingGrid.wndMain then
		return 
	end

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
					glog:warn("No raw hot/cold data for schematic %s, attempt #%s", tostring(tCurrentCraft.nSchematicId), tostring(idx))
				else
					wndMarker:SetBGColor(self.tColors[eHotCold])
				end
			end		
		end
	end			
end

function Athena:OnCraftingSchematicLearned(tCraftingGrid, idTradeskill, idSchematic)

	glog:debug("OnCraftingSchematicLearned(%s, %s)", tostring(idTradeskill), tostring(idSchematic))
	if not tCraftingGrid.wndMain or not tCraftingGrid.wndMain:IsValid() then
		return
	end

	local tSchematicInfo = CraftingLib.GetSchematicInfo(idSchematic)
	local nParentId = tSchematicInfo and tSchematicInfo.nParentSchematicId or idSchematic
	tCraftingGrid.tLastMarkersList[idSchematic] = nil
	
	if idSchematic ~= nParentId then
		tSchematicInfo = CraftingLib.GetSchematicInfo(nParentId)
		local allKnown = true
			
		if tSchematicInfo then
			for _ , tSchem in ipairs(tSchematicInfo.tSubRecipes) do
				if tSchem.bIsUndiscovered then
					allKnown = false
					break
				end			
			end
		end
		
		glog:debug("  parentId=%s, allKnown=%s", tostring(nParentId), tostring(allKnown))
		
		if allKnown then
			tCraftingGrid.tLastMarkersList[nParentId] = nil
		end				
	end
		
	tCraftingGrid.bFullDestroyNeeded = true
end

function Athena:HelperBuildMarker()
	glog:debug("HelperBuildMarker")
	
	if not self.tCraftingGrid or not self.tCraftingGrid.wndMarker then
		return
	end
	
	self.tCraftingGrid.wndMarker:SetOpacity(self.fMarkerOpacity)	
end

function Athena:CraftingGrid_OnDocumentReady()
	self:CopyRestoredMarkersToCraftingGrid()
end

-----------------------------------------------------------------------------------------------
-- Athena functions
-----------------------------------------------------------------------------------------------
function Athena:UpdateColorContainer(container, key)	
	local color = self.tColors[key]
	local colorHex
	
	glog:debug("UpdateColorContainer(%s) - color=%s", tostring(key), tostring(color))
		
	if type(color) == "table" then
		colorHex = self.gcolor:RGBAPercToHex(color.r, color.g, color.b, color.a)
	elseif type(color) == "string"  then
		colorHex = color
	elseif type(color) == "userdata" then
		color = color:ToTable()
		colorHex = self.gcolor:RGBAPercToHex(color.r, color.g, color.b, color.a)		
	end
	
	local picker = container:FindChild("ColorPickerButton")

	local oldData = container:GetData()

	if oldData == nil then
		local popup = self.gcolor:CreateColorPicker(self, "OnColorPicked", true, colorHex, container, key);
		popup:Show(false)
		picker:AttachWindow(popup)	
	end
		
	container:SetData(key)
	
	
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

	local tColors = {
		["ColorHot"] = CraftingLib.CodeEnumCraftingDiscoveryHotCold.Hot,
		["ColorWarm"] = CraftingLib.CodeEnumCraftingDiscoveryHotCold.Warm,
		["ColorCold"] = CraftingLib.CodeEnumCraftingDiscoveryHotCold.Cold	
	}
	
	for strName, key in pairs(tColors) do
		self:UpdateColorContainer(self.wndMain:FindChild(strName), key)
	end
	
	self.wndMain:FindChild("LogLevelButton"):SetText(self.strLogLevel)

	self.wndMain:FindChild("MarkerOpacitySlider"):SetValue(self.fMarkerOpacity)	
	self.wndMain:FindChild("MarkerPreview"):SetOpacity(self.fMarkerOpacity)	
end


-- Define general functions here
function Athena:Hook_CraftingGrid()
	local tCraftingGrid = Apollo.GetAddon("CraftingGrid")
	if tCraftingGrid == nil then
		return false
	end
	
	self:PostHook(tCraftingGrid ,"RedrawAll")
	self:PostHook(tCraftingGrid ,"OnDocumentReady", "CraftingGrid_OnDocumentReady")	
	self:PostHook(tCraftingGrid ,"HelperBuildMarker", "HelperBuildMarker")
	self:RawHook(tCraftingGrid, "OnCraftingSchematicLearned")
	
	
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
			--[[ 
				tAttempt  has:
					["nPosX"] = nNewPosX,
					["nPosY"] = nNewPosY,
					["idSchematic"] = nSchematicId,
					["strTooltip"] = strTooltipSaved,
					["strHotOrCold"] = Apollo.GetString("CoordCrafting_ViewLastCraft"),
	  			    ["eDirection"]  
			]]
				
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
	
	tSave.strLogLevel = self.strLogLevel
	tSave.fMarkerOpacity = self.fMarkerOpacity
	
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
		
	return tJournal, tData.tColors, tData.strLogLevel, tData.fMarkerOpacity
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

	local tLastMarkers, tColors, strLogLevel, fMarkerOpacity 
			
	local version = tData.version	
	
	if version == nil then
		-- sry, can't read unversioned data
	else
		if version == "1" then
			tLastMarkers, tColors, strLogLevel, fMarkerOpacity = self:RestoreV1Data(tData)	
		end		
	end		
	
	self.strLogLevel = strLogLevel or kstrDefaultLogLevel
	self.log:SetLevel(self.strLogLevel)	
	
	self.fMarkerOpacity = fMarkerOpacity or kfDefaultMarkerOpacity
		
	--[[
		 Do *NOT* deserialize into <see cref="CraftingGrid" />'s  <see cref="CraftingGrid.tLastMarkersList" /> yet, 
	 	it gets initialized to <code>{}</code> in <see cref="CraftingGrid.OnDocumentReady"/>, which will be called
	 	*after* we have finished, so any setting here is pointless.
	 	Instead store a reference, so our own OnDocumentReady hook <see cref="CraftingGrid_OnDocumentReady" />  
	 	can copy the value after <see cref="CraftingGrid" />'s call.
	]]
	self.tLastMarkersList = tLastMarkers or {}
	self.tColors = tColors or ktHintArrowDefaultColors	
	
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

function Athena:ColorValueChanged( wndHandler, wndControl, strText )
	local bFound, _, strKey = strText:find("^(#?%x%x%x%x%x%x%x%x)$")	
	glog:debug("ColorValueChanged(%s)", tostring(bFound))	
	
	if bFound then
		local parent = wndControl:GetParent()
		local key = parent:GetData()

		self.tColors[key] = strText
		self:UpdateColorContainer(parent, key)
	end
end


function Athena:OnColorPicked(strColor, container, key)
	glog:debug("OnColorPicked(%s) - key=%s", tostring(strColor), tostring(key))

	self.tColors[key] = strColor
	self:UpdateColorContainer(container, key)
end


function Athena:AdvancedCheckToggle( wndHandler, wndControl, eMouseButton )
	if wndHandler ~= wndControl then
		return
	end	
	
	local wndAdvanced = self.wndMain:FindChild("AdvancedContainer")
	local wndContent = self.wndMain:FindChild("Content")
		
	if wndHandler:IsChecked() then
		wndAdvanced:Show(true)	
	else
		wndAdvanced:Show(false)	
		wndContent:SetVScrollPos(0)
	end	

	wndContent:ArrangeChildrenVert()
end


function Athena:OnSelectLogLevelFormClose( wndHandler, wndControl, eMouseButton )
	local wndForm = wndControl:GetParent() 
	wndForm:Close()
end


function Athena:LogLevelSelectSignal( wndHandler, wndControl, eMouseButton )
	if wndHandler ~= wndControl then
		return
	end

	wndControl:GetParent():Close()	
		
	local text = wndControl:GetText()
	self.strLogLevel = text
	self.log:SetLevel(text)	
	self.wndMain:FindChild("LogLevelButton"):SetText(text)
end

function Athena:OnMarkerOpacityChanged( wndHandler, wndControl, fNewValue, fOldValue )
	glog:debug("OnMarkerOpacityChanged: %.1f", fNewValue)

	if wndHandler ~= wndControl then
		return
	end
	
	self.fMarkerOpacity = fNewValue
	self.wndMain:FindChild("MarkerPreview"):SetOpacity(self.fMarkerOpacity)	
end

