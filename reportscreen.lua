print("Loading ReportScreen.lua from Better Report Screen version "..GlobalParameters.BRS_VERSION_MAJOR.."."..GlobalParameters.BRS_VERSION_MINOR);
-- ===========================================================================
--	ReportScreen
--	All the data
--  Copyright 2016-2018, Firaxis Games
-- ===========================================================================
--  Better Report Screen by Infixo, 2018-2023
--  Navigation helper
--	1: Yields		UpdateYieldsData		ViewYieldsPage		BRSPage_Yields
--	2: Resources	UpdateResourcesData		ViewResourcesPage	BRSPage_Resources
--	3: CityStatus	UpdateCityStatusData	ViewCityStatusPage	BRSPage_CityStatus
--	4: Gossip		UpdateGossipData		ViewGossipPage		BRSPage_Gossip
--	5: Deals		UpdateDealsData			ViewDealsPage		BRSPage_Deals
--	6: Units		UpdateUnitsData			ViewUnitsPage		BRSPage_Units
--	7: Policy		UpdatePolicyData		ViewPolicyPage		BRSPage_Policy
--	8: Minor		UpdateMinorData			ViewMinorPage		BRSPage_Minor
--	9: Cities2		UpdateCities2Data		ViewCities2Page		BRSPage_Cities2
-- ===========================================================================

include("CitySupport"); -- GetCityData
include("Civ6Common");
include("InstanceManager");
--include("SupportFunctions"); -- TruncateString, TruncateStringWithTooltip, Clamp, Round
include("TabSupport");
--include("LeaderIcon"); -- Used by Gossip page

-- exposing functions and variables
if not ExposedMembers.RMA then ExposedMembers.RMA = {} end;
RMA = ExposedMembers.RMA;

-- Expansions check
bIsRiseFall = Modding.IsModActive("1B28771A-C749-434B-9053-D1380C553DE9"); -- Rise & Fall
print("Rise & Fall    :", (bIsRiseFall and "YES" or "no"));
bIsGatheringStorm = Modding.IsModActive("4873eb62-8ccc-4574-b784-dda455e74e68"); -- Gathering Storm
print("Gathering Storm:", (bIsGatheringStorm and "YES" or "no"));
bIsMonopolies = GameCapabilities.HasCapability("CAPABILITY_MONOPOLIES"); -- Monopoly and Corporations Mode
print("Monopolies     :", (bIsMonopolies and "YES" or "no"));

-- configuration options
local bOptionModifiers:boolean = ( GlobalParameters.BRS_OPTION_MODIFIERS == 1 );


-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
LL = Locale.Lookup;
ENDCOLOR = "[ENDCOLOR]";
local DATA_FIELD_SELECTION						:string = "Selection";
SIZE_HEIGHT_PADDING_BOTTOM_ADJUST = 87;	-- (Total Y - (scroll area + THIS PADDING)) = bottom area
TOOLTIP_SEP         = "-------------------";
TOOLTIP_SEP_NEWLINE = "[NEWLINE]"..TOOLTIP_SEP.."[NEWLINE]";


-- ===========================================================================
-- Infixo: this is an iterator to replace pairs
-- it sorts t and returns its elements one by one
-- source: https://stackoverflow.com/questions/15706270/sort-a-table-in-lua
function spairs( t, order_function )
	local keys:table = {}; -- actual table of keys that will bo sorted
	for key,_ in pairs(t) do table.insert(keys, key); end
	
	if order_function then
		table.sort(keys, function(a,b) return order_function(t, a, b) end)
	else
		table.sort(keys)
	end
	-- iterator here
	local i:number = 0;
	return function()
		i = i + 1;
		if keys[i] then
			return keys[i], t[keys[i]]
		end
	end
end
-- !! end of function

-- ===========================================================================
--	VARIABLES
-- ===========================================================================

m_simpleIM				= InstanceManager:new("SimpleInstance",			"Top",		Controls.Stack);				-- Non-Collapsable, simple
m_tabIM					= InstanceManager:new("TabInstance",			"Button",	Controls.TabContainer);
m_strategicResourcesIM	= InstanceManager:new("ResourceAmountInstance",	"Info",		Controls.StrategicResources);
m_bonusResourcesIM		= InstanceManager:new("ResourceAmountInstance",	"Info",		Controls.BonusResources);
m_luxuryResourcesIM		= InstanceManager:new("ResourceAmountInstance",	"Info",		Controls.LuxuryResources);
m_groupIM				= InstanceManager:new("GroupInstance",			"Top",		Controls.Stack);				-- Collapsable

m_tabs = nil;
local m_uiGroups			:table = nil;	-- Track the groups on-screen for collapse all action.

local m_isCollapsing		:boolean = true;

-- !!
-- Remember last tab variable: ARISTOS
m_kCurrentTab = 1;
-- !!

-- 230510 Dirty flags - if true then the data needs to be updated
g_DirtyFlag = {
	YIELDS = true,
	RESOURCES = true,
	CITYSTATUS = true,
	GOSSIP = true,
	DEALS = true,
	UNITS = true,
	POLICY = true,
	MINOR = true,
	CITIES2 = true,
};


-- ===========================================================================
-- 230510 SupportFunctions: TruncateString, TruncateStringWithTooltip, Clamp, Round
-- ===========================================================================

-- ===========================================================================
--	Round()
--	Rounds a number to X decimal places.
--	Original version from: http://lua-users.org/wiki/SimpleRound
-- ===========================================================================
function Round(num:number, idp:number)
  local mult:number = 10^(idp or 0);
  return math.floor(num * mult + 0.5) / mult;
end

-- ===========================================================================
--	Clamp()
--	Returns the value passed, only changing if it's above or below the min/max
-- ===========================================================================
function Clamp( value:number, min:number, max:number )
	if value < min then 
		return min;
	elseif value > max then
		return max;
	else
		return value;
	end
end

-- ===========================================================================
--	Sets a Label or control that contains a label (e.g., GridButton) with
--	a string that, if necessary, will be truncated.
--
--	RETURNS: true if truncated.
-- ===========================================================================
function TruncateString(control, resultSize, longStr, trailingText)

	local textControl = control;

	-- Ensure this has the actual text control
	if control.GetTextControl ~= nil then
		textControl = control:GetTextControl();
		UI.AssertMsg(textControl.SetTruncateWidth ~= nil, "Calling TruncateString with an unsupported control");
	end

	-- TODO if trailingText is ever used, add a way to do it to TextControl
	UI.AssertMsg(trailingText == nil or trailingText == "", "trailingText is not supported");

	if(longStr == nil) then
		longStr = control:GetText();
	end
	
	--TODO a better solution than this function would be ideal
		--calling SetText implicitly truncates if the flag is set
		--a AutoToolTip flag could be made to avoid setting the tooltip from lua
		--trailingText could be added, right now its just an ellipsis but it could be arbitrary
		--this would avoid the weird type shenanigans when truncating TextButtons, TextControls, etc

	if textControl ~= nil then
		textControl:SetTruncateWidth(resultSize);

		if control.SetText ~= nil then
			control:SetText(longStr);
		else
			textControl:SetText(longStr);
		end
	else
		UI.AssertMsg(false, "Attempting to truncate a NIL control");
	end

	if textControl.IsTextTruncated ~= nil then
		return textControl:IsTextTruncated();
	else
		UI.AssertMsg(false, "Calling IsTextTruncated with an unsupported control");
		return true;
	end
end

-- ===========================================================================
--	Same as TruncateString(), but if truncation occurs automatically adds
--	the full text as a tooltip.
-- ===========================================================================
function TruncateStringWithTooltip(control, resultSize, longStr, trailingText)
	local isTruncated = TruncateString( control, resultSize, longStr, trailingText );
	if isTruncated then
		control:SetToolTipString( longStr );
	else
		control:SetToolTipString( nil );
	end
	return isTruncated;
end

-- ===========================================================================
--	Same as TruncateStringWithTooltip(), but removes leading white space
--	before truncation
-- ===========================================================================
function TruncateStringWithTooltipClean(control, resultSize, longStr, trailingText)
	local cleanString = longStr:match("^%s*(.-)%s*$");
	local isTruncated = TruncateString( control, resultSize, longStr, trailingText );
	if isTruncated then
		control:SetToolTipString( cleanString );
	else
		control:SetToolTipString( nil );
	end
	return isTruncated;
end


-- ===========================================================================
-- Time helpers and debug routines
-- ===========================================================================

local MILISECS_PER_TICK: number = 10000;
local m_StartTime1: number = 0;
local m_StartTime2: number = 0;

function Timer1Start()
	m_StartTime1 = GetTickCount(); -- Automation.GetTime()
	--print("Timer1 Start", fStartTime1)
end
function Timer2Start()
	m_StartTime2 = GetTickCount(); -- Automation.GetTime()
	--print("Timer2 Start() (start)", fStartTime2)
end
function Timer1Tick(txt:string)
	print("Timer1:", txt, math.floor( (GetTickCount()-m_StartTime1)/MILISECS_PER_TICK ), "milisecs");
end
function Timer2Tick(txt:string)
	print("Timer2:", txt, math.floor( (GetTickCount()-m_StartTime2)/MILISECS_PER_TICK ), "milisecs");
end

-- debug routine - prints a table (no recursion)
function dshowtable(tTable:table)
	if tTable == nil then print("dshowtable: table is nil"); return; end
	for k,v in pairs(tTable) do
		print(k, type(v), tostring(v));
	end
end

-- debug routine - prints a table, and tables inside recursively (up to 5 levels)
function dshowrectable(tTable:table, iLevel:number)
	local level:number = 0;
	if iLevel ~= nil then level = iLevel; end
	for k,v in pairs(tTable) do
		print(string.rep("---:",level), k, type(v), tostring(v));
		if type(v) == "table" and level < 5 then dshowrectable(v, level+1); end
	end
end


-- ===========================================================================
-- Updated functions from Civ6Common, to include rounding to 1 decimal digit
-- ===========================================================================
function toPlusMinusString( value:number )
	if value == 0 then return "0"; end
	return Locale.ToNumber(math.floor((value*10)+0.5)/10, "+#,###.#;-#,###.#");
end

function toPlusMinusNoneString( value:number )
	if value == 0 then return " "; end
	return Locale.ToNumber(math.floor((value*10)+0.5)/10, "+#,###.#;-#,###.#");
end


-- ===========================================================================
--	Single exit point for display
-- ===========================================================================
function Close()
	if not ContextPtr:IsHidden() then
		UI.PlaySound("UI_Screen_Close");
	end

	UIManager:DequeuePopup(ContextPtr);
	LuaEvents.ReportScreen_Closed();
	--print("Closing... current tab is:", m_kCurrentTab);
	
	-- 230510 Set dirty flags to true
	for flag,_ in pairs(g_DirtyFlag) do g_DirtyFlag[flag] = true; end
end


-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnCloseButton()
	Close();
end


-- ===========================================================================
--	Single entry point for display
-- ===========================================================================
function Open( tabToOpen:number )
	--print("FUN Open()", tabToOpen);
	UIManager:QueuePopup( ContextPtr, PopupPriority.Medium );
	Controls.ScreenAnimIn:SetToBeginning();
	Controls.ScreenAnimIn:Play();
	UI.PlaySound("UI_Screen_Open");
	--LuaEvents.ReportScreen_Opened();
	
	-- To remember the last opened tab when the report is re-opened: ARISTOS
	if tabToOpen ~= nil then m_kCurrentTab = tabToOpen; end
	Resize();
	m_tabs.SelectTab( m_kCurrentTab );
	
	-- show number of cities in the title bar
	local playerID: number = Game.GetLocalPlayer();
	if playerID == PlayerTypes.NONE or playerID == PlayerTypes.OBSERVER then
		Controls.TotalsLabel:SetText("");
		Controls.TotalsLabel:SetToolTipString("");
		return;
	end
	local pPlayer: table = Players[playerID];
	local iCit: number = Players[playerID]:GetCities():GetCount();
	local iWon:number, iDis:number, iBul:number, iPop:number = 0, 0, 0, 0;
	-- count districts and population
	for _,city in pPlayer:GetCities():Members() do
		iDis = iDis + city:GetDistricts():GetNumZonedDistrictsRequiringPopulation();
		iPop = iPop + city:GetPopulation();
	end
	local playerStats: table = pPlayer:GetStats();
	-- count wonders and buildings
	for building in GameInfo.Buildings() do
		local num: number = playerStats:GetNumBuildingsOfType(building.Index);
		if building.IsWonder then iWon = iWon + num; else iBul = iBul + num; end
	end
	local iCiv:number, iMil:number = 0, 0;
	-- count units
	for _,unit in pPlayer:GetUnits():Members() do
		if GameInfo.Units[unit:GetUnitType()].FormationClass == "FORMATION_CLASS_CIVILIAN" then iCiv = iCiv + 1; else iMil = iMil + 1; end
	end -- for
	Controls.TotalsLabel:SetText( Locale.Lookup("LOC_DIPLOMACY_DEAL_CITIES").." "..tostring(iCit) );
	
	-- build a tooltip with details
	local tTT:table = {};
	table.insert(tTT, Locale.Lookup("LOC_RAZE_CITY_POPULATION_LABEL").." "..tostring(iPop));
	table.insert(tTT, Locale.Lookup("LOC_TECH_FILTER_WONDERS")..": "..tostring(iWon));
	table.insert(tTT, Locale.Lookup("LOC_DEAL_CITY_DISTRICTS_TOOLTIP").." "..tostring(iDis));
	table.insert(tTT, Locale.Lookup("LOC_TOOLTIP_PLOT_BUILDINGS_TEXT").." "..tostring(iBul));
	table.insert(tTT, Locale.Lookup("LOC_TECH_FILTER_UNITS")..": "..tostring(iCiv+iMil));
	table.insert(tTT, Locale.Lookup("LOC_MILITARY")..": "..tostring(iMil));
	table.insert(tTT, Locale.Lookup("LOC_FORMATION_CLASS_CIVILIAN_NAME")..": "..tostring(iCiv));
	Controls.TotalsLabel:SetToolTipString( table.concat(tTT, "[NEWLINE]") );
end


-- ===========================================================================
--	UI Callback
--	Collapse all the things!
-- ===========================================================================
function OnCollapseAllButton()
	if m_uiGroups == nil or table.count(m_uiGroups) == 0 then
		return;
	end

	for i,instance in ipairs( m_uiGroups ) do
		if instance["isCollapsed"] ~= m_isCollapsing then
			instance["isCollapsed"] = m_isCollapsing;
			instance.CollapseAnim:Reverse();
			RealizeGroup( instance );
		end
	end
	Controls.CollapseAll:LocalizeAndSetText(m_isCollapsing and "LOC_HUD_REPORTS_EXPAND_ALL" or "LOC_HUD_REPORTS_COLLAPSE_ALL");
	m_isCollapsing = not m_isCollapsing;
end


-- ===========================================================================
--	Populate with all data required for any/all report tabs.
-- ===========================================================================

function GetData()
	--print("FUN GetData() - start");
	
	local kResources	:table = {};
	local kCityData		:table = {};
	local kCityTotalData:table = {
		Income	= {},
		Expenses= {},
		Net		= {},
		Treasury= {}
	};
	local kUnitData		:table = {};


	kCityTotalData.Income[YieldTypes.CULTURE]	= 0;
	kCityTotalData.Income[YieldTypes.FAITH]		= 0;
	kCityTotalData.Income[YieldTypes.FOOD]		= 0;
	kCityTotalData.Income[YieldTypes.GOLD]		= 0;
	kCityTotalData.Income[YieldTypes.PRODUCTION]= 0;
	kCityTotalData.Income[YieldTypes.SCIENCE]	= 0;
	kCityTotalData.Income["TOURISM"]			= 0;
	kCityTotalData.Expenses[YieldTypes.GOLD]	= 0;
	
	local playerID	:number = Game.GetLocalPlayer();
	if playerID == PlayerTypes.NONE then
		UI.DataError("Unable to get valid playerID for report screen.");
		return;
	end

	local player	:table  = Players[playerID];
	local pCulture	:table	= player:GetCulture();
	local pTreasury	:table	= player:GetTreasury();
	local pReligion	:table	= player:GetReligion();
	local pScience	:table	= player:GetTechs();
	local pResources:table	= player:GetResources();		
	local MaintenanceDiscountPerUnit:number = pTreasury:GetMaintDiscountPerUnit(); -- this will be used in 2 reports
	local pUnits    :table  = player:GetUnits(); -- 230425 moved

	-- ==========================
	-- BRS !! this will use the m_kUnitDataReport to fill out player's unit info
	-- ==========================
	--print("FUN GetData() - unit data report");
	local tSupportedFormationClasses:table = { FORMATION_CLASS_CIVILIAN = true, FORMATION_CLASS_LAND_COMBAT = true, FORMATION_CLASS_NAVAL = true, FORMATION_CLASS_SUPPORT = true, FORMATION_CLASS_AIR = true };
	local kUnitDataReport:table = {};
	local group_name:string;
	local tUnitsDist:table = {}; -- temp table for calculating units' distance from cities

	for _, unit in player:GetUnits():Members() do
		local unitInfo:table = GameInfo.Units[unit:GetUnitType()];
		local formationClass:string = unitInfo.FormationClass; -- FORMATION_CLASS_CIVILIAN, FORMATION_CLASS_LAND_COMBAT, FORMATION_CLASS_NAVAL, FORMATION_CLASS_SUPPORT, FORMATION_CLASS_AIR
		-- categorize
		group_name = string.gsub(formationClass, "FORMATION_CLASS_", "");
		if formationClass == "FORMATION_CLASS_CIVILIAN" then
			-- need to split into sub-classes
			if unit:GetGreatPerson():IsGreatPerson() then group_name = "GREAT_PERSON";
			elseif unitInfo.MakeTradeRoute then           group_name = "TRADER";
			elseif unitInfo.Spy then                      group_name = "SPY";
			elseif unit:GetReligiousStrength() > 0 then group_name = "RELIGIOUS";
			end
		end
		-- tweak to handle new, unknown formation classes
		if not tSupportedFormationClasses[formationClass] then
			print("WARNING: GetData Unknown formation class", formationClass, "for unit", unitInfo.UnitType);
			group_name = "SUPPORT";
		end
		-- store for Units tab report
		if kUnitDataReport[group_name] == nil then
			if     group_name == "LAND_COMBAT" then  kUnitDataReport[group_name] = { ID= 1, func= group_military, Header= "UnitsMilitaryHeaderInstance",   Entry= "UnitsMilitaryEntryInstance" };
			elseif group_name == "NAVAL" then        kUnitDataReport[group_name] = { ID= 2, func= group_military, Header= "UnitsMilitaryHeaderInstance",   Entry= "UnitsMilitaryEntryInstance" };
			elseif group_name == "AIR" then          kUnitDataReport[group_name] = { ID= 3, func= group_military, Header= "UnitsMilitaryHeaderInstance",   Entry= "UnitsMilitaryEntryInstance" };
			elseif group_name == "SUPPORT" then      kUnitDataReport[group_name] = { ID= 4, func= group_military, Header= "UnitsMilitaryHeaderInstance",   Entry= "UnitsMilitaryEntryInstance" };
			elseif group_name == "CIVILIAN" then     kUnitDataReport[group_name] = { ID= 5, func= group_civilian, Header= "UnitsCivilianHeaderInstance",   Entry= "UnitsCivilianEntryInstance" };
			elseif group_name == "RELIGIOUS" then    kUnitDataReport[group_name] = { ID= 6, func= group_religious,Header= "UnitsReligiousHeaderInstance",  Entry= "UnitsReligiousEntryInstance" };
			elseif group_name == "GREAT_PERSON" then kUnitDataReport[group_name] = { ID= 7, func= group_great,    Header= "UnitsGreatPeopleHeaderInstance",Entry= "UnitsGreatPeopleEntryInstance" };
			elseif group_name == "SPY" then          kUnitDataReport[group_name] = { ID= 8, func= group_spy,      Header= "UnitsSpyHeaderInstance",        Entry= "UnitsSpyEntryInstance" };
			elseif group_name == "TRADER" then       kUnitDataReport[group_name] = { ID= 9, func= group_trader,   Header= "UnitsTraderHeaderInstance",     Entry= "UnitsTraderEntryInstance" };
			end
			--print("...creating a new unit group", formationClass, group_name);
			kUnitDataReport[group_name].Name = "LOC_BRS_UNITS_GROUP_"..group_name;
			kUnitDataReport[group_name].units = {};
		end
		table.insert( kUnitDataReport[group_name].units, unit );
		-- add some unit specific data
		unit.MaintenanceAfterDiscount = math.max(GetUnitMaintenance(unit) - MaintenanceDiscountPerUnit, 0); -- cannot go below 0
		-- store data for distance calculations
		unit.NearCityDistance = 9999;
		unit.NearCityName = "";
		unit.NearCityIsCapital = false;
		unit.NearCityIsOurs = true;
		-- Gathering Storm
		if bIsGatheringStorm then
			unit.ResMaint = "";
			local unitInfoXP2:table = GameInfo.Units_XP2[ unitInfo.UnitType ];
			if unitInfoXP2 ~= nil and unitInfoXP2.ResourceMaintenanceType ~= nil then
				unit.ResMaint = "[ICON_"..unitInfoXP2.ResourceMaintenanceType.."]";
			end
		end
		-- Rock Band
		unit.IsRockBand = false;
		unit.RockBandAlbums = 0;
		unit.RockBandLevel = 0;
		if bIsGatheringStorm and unitInfo.PromotionClass == "PROMOTION_CLASS_ROCK_BAND" then
			unit.IsRockBand = true;
			unit.RockBandAlbums = unit:GetRockBand():GetAlbumSales();
			unit.RockBandLevel = unit:GetRockBand():GetRockBandLevel();
		end
		table.insert( tUnitsDist, unit );
	end
	
	-- calculate distance to the closest city for all units
	-- must iterate through all living players and their cities
	for _,player in ipairs(PlayerManager.GetAlive()) do
		local bIsOurs:boolean = ( player:GetID() == playerID );
		for _,city in player:GetCities():Members() do
			local iCityX:number, iCityY:number = city:GetX(), city:GetY();
			local sCityName:string = Locale.Lookup( city:GetName() );
			local bIsCapital:boolean = city:IsCapital();
			for _,unit in ipairs(tUnitsDist) do
				local iDistance:number = Map.GetPlotDistance( unit:GetX(), unit:GetY(), iCityX, iCityY );
				if iDistance < unit.NearCityDistance then
					unit.NearCityDistance = iDistance;
					unit.NearCityName = sCityName;
					unit.NearCityIsCapital = bIsCapital;
					unit.NearCityIsOurs = bIsOurs;
				end
			end
		end
	end
	
	-- ==========================
	-- !! end of edit
	-- ==========================
	
	-----------------------------------
	-- MODIFIERS
	-- scan only once, select those for a) player's cities b) with desired effects
	-- store in a similar fashion as city data i.e. indexed by CityName
	-- on a city level a simple table, each entry contains:
	-- .ID - instance ID from GameEffects.GetModifiers
	-- .Active - boolean, as returned by GameEffects.GetModifierActive
	-- .Definition - table, as returned by GameEffects.GetModifierDefinition
	-- .Arguments - table, reference to .Arguments from .Definition (easy access)
	-- .OwnerType, .OwnerName - strings, as returned by GameEffects.GetObjectType and GetObjectName - for debug
	-- .Modifier - static as returned by RMA.FetchAndCacheData
	-----------------------------------
	--print("FUN GetData() - modifiers");
	m_kModifiers = {}; -- clear main table
	m_kModifiersUnits ={}; -- clear main table
	local sTrackedPlayer:string = PlayerConfigurations[playerID]:GetLeaderName(); -- LOC_LEADER_xxx_NAME
	--print("Tracking player", sTrackedPlayer); -- debug
	--[[ not used
	local tTrackedEffects:table = {
		EFFECT_ADJUST_CITY_YIELD_CHANGE = true, -- all listed as Modifiers in CityPanel
		EFFECT_ADJUST_CITY_YIELD_MODIFIER = true, -- e.g. governor's +20%, Wonders use it, some beliefs
		EFFECT_ADJUST_CITY_YIELD_PER_POPULATION = true, -- e.g. Theocracy and Communism
		EFFECT_ADJUST_CITY_YIELD_PER_DISTRICT = true, -- e.g. Democtratic Legacy +2 Production per district
		EFFECT_ADJUST_FOLLOWER_YIELD_MODIFIER = true, -- Work Ethic belief +1% Production; use the number of followers of the majority religion in the city
		--EFFECT_ADJUST_CITY_YIELD_FROM_FOREIGN_TRADE_ROUTES_PASSING_THROUGH = true, -- unknown
	};
	--]]
	--for k,v in pairs(tTrackedEffects) do print(k,v); end -- debug
	local tTrackedOwners:table = {};
	for _,city in player:GetCities():Members() do
		tTrackedOwners[ city:GetName() ] = true;
		m_kModifiers[ city:GetName() ] = {}; -- we need al least empty table for each city
	end
	local tTrackedUnits:table = {};
	for _,unit in player:GetUnits():Members() do
		tTrackedUnits[ unit:GetID() ] = true;
		m_kModifiersUnits[ unit:GetID() ] = {};
	end
	--for k,v in pairs(tTrackedOwners) do print(k,v); end -- debug
	-- main loop
	for _,instID in ipairs(GameEffects.GetModifiers()) do
		local iOwnerID:number = GameEffects.GetModifierOwner( instID );
		local iPlayerID:number = GameEffects.GetObjectsPlayerId( iOwnerID );
		local sOwnerType:string = GameEffects.GetObjectType( iOwnerID ); -- LOC_MODIFIER_OBJECT_CITY, LOC_MODIFIER_OBJECT_PLAYER, LOC_MODIFIER_OBJECT_GOVERNOR
		local sOwnerName:string = GameEffects.GetObjectName( iOwnerID ); -- LOC_CITY_xxx_NAME, LOC_LEADER_xxx_NAME, etc.
		local tSubjects:table = GameEffects.GetModifierSubjects( instID ); -- table of objectIDs or nil
		--print("checking", instID, sOwnerName, sOwnerType, iOwnerID, iPlayerID); -- debug
		
		local instdef:table = GameEffects.GetModifierDefinition(instID);
		local data:table = {
			ID = instID,
			Active = GameEffects.GetModifierActive(instID), -- should always be true? but check to be safe
			Definition = instdef, -- .Id has the static name
			Arguments = instdef.Arguments, -- same structure as static, Name = Value
			OwnerType = sOwnerType,
			OwnerName = sOwnerName,
			SubjectType = nil, -- will be filled for modifiers taken from Subjects
			SubjectName = nil, -- will be filled for modifiers taken from Subjects
			UnitID = nil, -- will be used only for units' modifiers
			Modifier = RMA.FetchAndCacheData(instdef.Id),
		};
		
		local function RegisterModifierForCity(sSubjectType:string, sSubjectName:string)
			--print("registering for city", data.ID, sSubjectType, sSubjectName);
			-- fix for sudden changes in modifier system, like Veterancy changed in March 2018 patch
			-- some modifiers might be removed, but still are attached to objects from old games
			-- the game itself seems to be resistant to such situation
			if data.Modifier == nil then print("WARNING! GetData/Modifiers: Ignoring non-existing modifier", data.ID, data.Definition.Id, sOwnerName, sSubjectName); return end
			if sSubjectType == nil or sSubjectName == nil then
				data.SubjectType = nil;
				data.SubjectName = nil;
				table.insert(m_kModifiers[sOwnerName], data);
			else -- register as subject
				data.SubjectType = sSubjectType;
				data.SubjectName = sSubjectName;
				table.insert(m_kModifiers[sSubjectName], data);
			end
			-- debug output
			--print("--------- Tracking", data.ID, sOwnerType, sOwnerName, sSubjectName);
			--for k,v in pairs(data) do print(k,v); end
			--print("- Modifier:", data.Definition.Id);
			--print("- Collection:", data.Modifier.CollectionType);
			--print("- Effect:", data.Modifier.EffectType);
			--print("- Arguments:");
			--for k,v in pairs(data.Arguments) do print(k,v); end -- debug
		end
		
		local function RegisterModifierForUnit(iUnitID:number, sSubjectType:string, sSubjectName:string)
			--print("registering for unit", iUnitID, data.ID, sSubjectType, sSubjectName);
			-- fix for sudden changes in modifier system, like Veterancy changed in March 2018 patch
			-- some modifiers might be removed, but still are attached to objects from old games
			-- the game itself seems to be resistant to such situation
			if data.Modifier == nil then print("WARNING! GetData/Modifiers: Ignoring non-existing modifier", data.ID, data.Definition.Id, sOwnerName, sSubjectName); return end
			data.UnitID = iUnitID;
			if sSubjectType == nil or sSubjectName == nil then
				data.SubjectType = nil;
				data.SubjectName = nil;
			else -- register as subject
				data.SubjectType = sSubjectType;
				data.SubjectName = sSubjectName;
			end
			-- 230425 #7 filter out the modifiers from abilities that do not match the unit's class
			-- 
			local isValid: boolean = false;
			if data.Modifier.EffectType == "EFFECT_GRANT_ABILITY" then
				local ability: string = data.Arguments.AbilityType;
				local unit: table = pUnits:FindID(iUnitID);
				if unit then
					local unitType: string = GameInfo.Units[unit:GetUnitType()].UnitType;
					if g_AbilitiesUnits[ability] and g_AbilitiesUnits[ability][unitType] then isValid = true; end
				end
			else
				isValid = true; -- we don't check other effects, but could be extended later
			end
			if isValid then table.insert(m_kModifiersUnits[iUnitID], data); end
			-- debug output
			--print("--------- Tracking", iUnitID, data.ID, sOwnerType, sOwnerName, sSubjectName);
			--print("- Valid?", isValid and "yes" or "NO");
			--for k,v in pairs(data) do print(k,v); end
			--print("- Modifier:", data.Definition.Id);
			--print("- Collection:", data.Modifier.CollectionType);
			--print("- Effect:", data.Modifier.EffectType);
			--print("- Arguments:");
			--for k,v in pairs(data.Arguments) do print(k,v); end -- debug
		end
		
		-- this part is for modifiers attached directly to the city (COLLECTION_OWNER)
		if tTrackedOwners[ sOwnerName ] then
			RegisterModifierForCity(); -- City is owner
		end
		
		-- this part is for modifiers attached to the player
		-- we need to analyze Subjects (COLLECTION_PLAYER_CITIES, COLLECTION_PLAYER_CAPITAL_CITY)
		-- GetModifierTrackedObjects gives all Subjects, but GetModifierSubjects gives only those with met requirements!
		if sOwnerType == "LOC_MODIFIER_OBJECT_PLAYER" and sOwnerName == sTrackedPlayer and tSubjects then
			for _,subjectID in ipairs(tSubjects) do
				local sSubjectType:string = GameEffects.GetObjectType( subjectID ); -- LOC_MODIFIER_OBJECT_CITY, LOC_MODIFIER_OBJECT_PLAYER, LOC_MODIFIER_OBJECT_GOVERNOR
				local sSubjectName:string = GameEffects.GetObjectName( subjectID ); -- LOC_CITY_xxx_NAME, LOC_LEADER_xxx_NAME, etc.
				if sSubjectType == "LOC_MODIFIER_OBJECT_CITY" and tTrackedOwners[sSubjectName] then RegisterModifierForCity(sSubjectType, sSubjectName); end
			end
		end
		
		-- this part is for modifiers attached to Districts
		-- we process all districts, but sOwnerName contains DistrictName if necessary LOC_DISTRICT_xxx_NAME
		-- for each there is always a set of Subjects, even if only 1 for a singular effect
		-- those subjects can be LOC_MODIFIER_OBJECT_DISTRICT or LOC_MODIFIER_OBJECT_PLOT_YIELDS
		-- then we need to find its City, which is stupidly hidden in a description string "District: districtID, Owner: playerID, City: cityID"
		if iPlayerID == playerID and sOwnerType == "LOC_MODIFIER_OBJECT_DISTRICT" and tSubjects then
			for _,subjectID in ipairs(tSubjects) do
				local sSubjectType:string = GameEffects.GetObjectType( subjectID );
				local sSubjectName:string = GameEffects.GetObjectName( subjectID );
				if sSubjectType == "LOC_MODIFIER_OBJECT_DISTRICT" then
					-- find a city
					local sSubjectString:string = GameEffects.GetObjectString( subjectID );
					local iCityID:number = tonumber( string.match(sSubjectString, "City: (%d+)") );
					--print("city:", sSubjectString, "decode:", iCityID);
					if iCityID ~= nil then
						local pCity:table = player:GetCities():FindID(iCityID);
						if pCity and tTrackedOwners[pCity:GetName()] then RegisterModifierForCity(sSubjectType, pCity:GetName()); end
					end
				end
			end
		end
		
		-- this part is for units as owners, we need to decode the unit and see if it's ours
		if sOwnerType == "LOC_MODIFIER_OBJECT_UNIT" then
			-- find a unit
			local sOwnerString:string = GameEffects.GetObjectString( iOwnerID );
			local iUnitID:number      = tonumber( string.match(sOwnerString, "Unit: (%d+)") );
			local iUnitOwnerID:number = tonumber( string.match(sOwnerString, "Owner: (%d+)") );
			--print("unit:", sOwnerString, "decode:", iUnitOwnerID, iUnitID);
			if iUnitID and iUnitOwnerID and iUnitOwnerID == playerID and tTrackedUnits[iUnitID] then
				RegisterModifierForUnit(iUnitID);
			end
		end
		
		-- this part is for units as subjects; to make it more unified it will simply analyze all subjects' sets
		if tSubjects then
			for _,subjectID in ipairs(tSubjects) do
				local sSubjectType:string = GameEffects.GetObjectType( subjectID );
				local sSubjectName:string = GameEffects.GetObjectName( subjectID );
				if sSubjectType == "LOC_MODIFIER_OBJECT_UNIT" then
					-- find a unit
					local sSubjectString:string = GameEffects.GetObjectString( subjectID );
					local iUnitID:number      = tonumber( string.match(sSubjectString, "Unit: (%d+)") );
					local iUnitOwnerID:number = tonumber( string.match(sSubjectString, "Owner: (%d+)") );
					--print("unit:", sSubjectString, "decode:", iUnitOwnerID, iUnitID);
					if iUnitID and iUnitOwnerID and iUnitOwnerID == playerID and tTrackedUnits[iUnitID] then
						RegisterModifierForUnit(iUnitID, sSubjectType, sSubjectName);
					end
				end -- unit
			end -- subjects
		end
		
	end
	--print("--------------"); print("FOUND MODIFIERS FOR CITIES"); for k,v in pairs(m_kModifiers) do print(k, #v); end
	--print("--------------"); print("FOUND MODIFIERS FOR UNITS"); for k,v in pairs(m_kModifiersUnits) do print(k, #v); end

	--print("FUN GetData() - cities");
	local pCities = player:GetCities();
	for i, pCity in pCities:Members() do	
		local cityName	:string = pCity:GetName();
			
		-- Big calls, obtain city data and add report specific fields to it.
		local data		:table	= GetCityData( pCity );
		data.Resources			= GetCityResourceData( pCity ); -- Add more data (not in CitySupport)			
		--data.WorkedTileYields, data.NumWorkedTiles, data.SpecialistYields, data.NumSpecialists = GetWorkedTileYieldData( pCity, pCulture );	-- Add more data (not in CitySupport)

		-- Add to totals.
		kCityTotalData.Income[YieldTypes.CULTURE]	= kCityTotalData.Income[YieldTypes.CULTURE] + data.CulturePerTurn;
		kCityTotalData.Income[YieldTypes.FAITH]		= kCityTotalData.Income[YieldTypes.FAITH] + data.FaithPerTurn;
		kCityTotalData.Income[YieldTypes.FOOD]		= kCityTotalData.Income[YieldTypes.FOOD] + data.FoodPerTurn;
		kCityTotalData.Income[YieldTypes.GOLD]		= kCityTotalData.Income[YieldTypes.GOLD] + data.GoldPerTurn;
		kCityTotalData.Income[YieldTypes.PRODUCTION]= kCityTotalData.Income[YieldTypes.PRODUCTION] + data.ProductionPerTurn;
		kCityTotalData.Income[YieldTypes.SCIENCE]	= kCityTotalData.Income[YieldTypes.SCIENCE] + data.SciencePerTurn;
		kCityTotalData.Income["TOURISM"]			= kCityTotalData.Income["TOURISM"] + data.WorkedTileYields["TOURISM"];
			
		kCityData[cityName] = data;

		-- Add outgoing route data
		data.OutgoingRoutes = pCity:GetTrade():GetOutgoingRoutes();
		data.IncomingRoutes = pCity:GetTrade():GetIncomingRoutes();

		for eResourceType,amount in pairs(data.Resources) do
			AddResourceData(kResources, eResourceType, cityName, "LOC_HUD_REPORTS_TRADE_OWNED", amount);
		end
		
		-- ADDITIONAL DATA
		
		-- Modifiers
		data.Modifiers = m_kModifiers[ cityName ]; -- just a reference to the main table
		
		-- real housing from improvements - this is a permanent fix for data.Housing field, so it is safe to use it later
		data.RealHousingFromImprovements = GetRealHousingFromImprovements(pCity);
		data.Housing = data.Housing - data.HousingFromImprovements + data.RealHousingFromImprovements;
		data.HousingFromImprovements = data.RealHousingFromImprovements;
		
		-- number of followers of the main religion
		data.MajorityReligionFollowers = 0;
		local eDominantReligion:number = pCity:GetReligion():GetMajorityReligion();
		if eDominantReligion > 0 then -- WARNING! this rules out pantheons!
			for _, religionData in pairs(pCity:GetReligion():GetReligionsInCity()) do
				if religionData.Religion == eDominantReligion then data.MajorityReligionFollowers = religionData.Followers; end
			end
		end
		--print("Majority religion followers for", cityName, data.MajorityReligionFollowers);
		
		-- Garrison in a city
		data.IsGarrisonUnit = false;
		local pPlotCity:table = Map.GetPlot( pCity:GetX(), pCity:GetY() );
		for _,unit in ipairs(Units.GetUnitsInPlot(pPlotCity)) do
			if GameInfo.Units[ unit:GetUnitType() ].FormationClass == "FORMATION_CLASS_LAND_COMBAT" then
				data.IsGarrisonUnit = true;
				data.GarrisonUnitName = Locale.Lookup( unit:GetName() );
				break;
			end
		end
		
		-- count all districts and specialty ones
		data.NumDistricts = 0;
		data.NumSpecialtyDistricts = 0
		for _,district in pCity:GetDistricts():Members() do
			local districtInfo:table = GameInfo.Districts[ district:GetType() ];
			if district:IsComplete() and not districtInfo.CityCenter and                             districtInfo.DistrictType ~= "DISTRICT_WONDER" then
				data.NumDistricts = data.NumDistricts + 1;
			end
			if district:IsComplete() and not districtInfo.CityCenter and districtInfo.OnePerCity and districtInfo.DistrictType ~= "DISTRICT_WONDER" then
				data.NumSpecialtyDistricts = data.NumSpecialtyDistricts + 1;
			end
		end

		-- current production type
		data.CurrentProductionType = "NONE";
		local iCurrentProductionHash:number = pCity:GetBuildQueue():GetCurrentProductionTypeHash();
		if iCurrentProductionHash ~= 0 then
			if     GameInfo.Buildings[iCurrentProductionHash] ~= nil then data.CurrentProductionType = "BUILDING";
			elseif GameInfo.Districts[iCurrentProductionHash] ~= nil then data.CurrentProductionType = "DISTRICT";
			elseif GameInfo.Units[iCurrentProductionHash]     ~= nil then data.CurrentProductionType = "UNIT";
			elseif GameInfo.Projects[iCurrentProductionHash]  ~= nil then data.CurrentProductionType = "PROJECT";
			end
		end
		
		-- Growth and related data
		-- This part of code is from CityPanelOverview.lua, retrofitted to use here (it uses data as prepared by CitySupport.lua)
		-- line 1, data.FoodPerTurn
		data.FoodConsumption = -(data.FoodPerTurn - data.FoodSurplus); -- line 2, it will be always negative!
		-- line 3, data.FoodSurplus
		-- line 4, data.HappinessGrowthModifier
		-- line 5, data.OccupationMultiplier
		data.FoodPerTurnModified = 0; -- line 6, modified food per turn [=line3 * (1+line4+line5)
		-- line 7, data.HousingMultiplier
		-- line 8a vanilla, data.OccupationMultiplier
		-- line 8b ris&fal, loyalty calculated
		data.TotalFoodSurplus = 0; -- line 9, as displayed in City Details
		-- line 10, data.TurnsUntilGrowth
		-- growth changes related to Loyalty
		if bIsRiseFall or bIsGatheringStorm then
			data.LoyaltyGrowthModifier = Round( 100 * pCity:GetGrowth():GetLoyaltyGrowthModifier() - 100, 0 );
			data.LoyaltyLevelName = GameInfo.LoyaltyLevels[ pCity:GetCulturalIdentity():GetLoyaltyLevel() ].Name;
		end
		
		local tGrowthTT:table = {}; -- growth tooltip
		local function AddGrowthToolTip(sText:string, fValue:number, sSuffix:string)
			if fValue then table.insert(tGrowthTT, Locale.Lookup(sText)..": "..toPlusMinusString(fValue)..(sSuffix and sSuffix or ""));
			else           table.insert(tGrowthTT, Locale.Lookup(sText)..": "..Locale.Lookup("LOC_HUD_CITY_NOT_APPLICABLE")); end
		end
		local function AddGrowthToolTipSeparator()
			table.insert(tGrowthTT, "----------");
		end

		AddGrowthToolTip("LOC_HUD_CITY_FOOD_PER_TURN", data.FoodPerTurn); -- line 1: food per turn
		AddGrowthToolTip("LOC_HUD_CITY_FOOD_CONSUMPTION", data.FoodConsumption); -- line 2: food consumption
		AddGrowthToolTipSeparator();
		AddGrowthToolTip("LOC_HUD_CITY_GROWTH_FOOD_PER_TURN", data.FoodSurplus); -- line 3: food growth per turn

		if data.TurnsUntilGrowth > -1 then
			-- GROWTH IN: Set bonuses and multipliers
			AddGrowthToolTip("LOC_HUD_CITY_HAPPINESS_GROWTH_BONUS", Round(data.HappinessGrowthModifier, 0), "%"); -- line 4: amenities (happiness) growth bonus
			AddGrowthToolTip("LOC_HUD_CITY_OTHER_GROWTH_BONUSES", Round(data.OtherGrowthModifiers * 100, 0), "%"); -- line 5: other growth bonuses
			AddGrowthToolTipSeparator();
			local growthModifier =  math.max(1 + (data.HappinessGrowthModifier/100) + data.OtherGrowthModifiers, 0); -- This is unintuitive but it's in parity with the logic in City_Growth.cpp
			data.FoodPerTurnModified = Round(data.FoodSurplus * growthModifier, 2); -- line 6
			AddGrowthToolTip("LOC_HUD_CITY_MODIFIED_GROWTH_FOOD_PER_TURN", data.FoodPerTurnModified); -- line 6: modified food per turn
			table.insert(tGrowthTT, Locale.Lookup("LOC_HUD_CITY_HOUSING_MULTIPLIER")..": "..data.HousingMultiplier); -- line 7: housing multiplier
			data.TotalFoodSurplus = data.FoodPerTurnModified * data.HousingMultiplier;
			-- occupied
			if data.Occupied then data.TotalFoodSurplus = data.FoodPerTurnModified * data.OccupationMultiplier; end
			AddGrowthToolTip("LOC_HUD_CITY_OCCUPATION_MULTIPLIER", (data.Occupied and data.OccupationMultiplier * 100) or nil, "%"); -- line 8a
			if bIsRiseFall or bIsGatheringStorm then
				if data.LoyaltyGrowthModifier ~= 0 then AddGrowthToolTip(data.LoyaltyLevelName, data.LoyaltyGrowthModifier, "%"); -- line 8b
				else table.insert(tGrowthTT, Locale.Lookup(data.LoyaltyLevelName)..": "..Locale.Lookup("LOC_CULTURAL_IDENTITY_LOYALTY_NO_GROWTH_PENALTY")); end -- line 8b
			end
			AddGrowthToolTipSeparator();
			-- final
			AddGrowthToolTip("LOC_HUD_CITY_TOTAL_FOOD_SURPLUS", data.TotalFoodSurplus, (data.TotalFoodSurplus > 0 and "[ICON_FoodSurplus]") or "[ICON_FoodDeficit]"); -- line 9
			if data.Occupied then AddGrowthToolTip("LOC_HUD_CITY_GROWTH_OCCUPIED"); -- line 10, occupied: no growth
			else table.insert(tGrowthTT, Locale.Lookup("LOC_HUD_CITY_TURNS_UNTIL_CITIZEN_BORN", math.abs(data.TurnsUntilGrowth))); end -- line 10
		else
			-- CITIZEN LOST IN: In a deficit, no bonuses or multipliers apply
			AddGrowthToolTip("LOC_HUD_CITY_HAPPINESS_GROWTH_BONUS"); -- line 4: amenities (happiness) growth bonus
			AddGrowthToolTip("LOC_HUD_CITY_OTHER_GROWTH_BONUSES"); -- line 5: other growth bonuses
			AddGrowthToolTipSeparator();
			data.FoodPerTurnModified = data.FoodSurplus; -- line 6
			AddGrowthToolTip("LOC_HUD_CITY_MODIFIED_GROWTH_FOOD_PER_TURN", data.FoodPerTurnModified); -- line 6: modified food per turn
			AddGrowthToolTip("LOC_HUD_CITY_HOUSING_MULTIPLIER"); -- line 7: housing multiplier
			AddGrowthToolTip("LOC_HUD_CITY_OCCUPATION_MULTIPLIER", (data.Occupied and data.OccupationMultiplier * 100) or nil, "%"); -- line 8a
			if bIsRiseFall or bIsGatheringStorm then AddGrowthToolTip(data.LoyaltyLevelName); end -- line 8b
			AddGrowthToolTipSeparator();
			data.TotalFoodSurplus = data.FoodPerTurnModified; -- line 9
			AddGrowthToolTip("LOC_HUD_CITY_TOTAL_FOOD_DEFICIT", data.TotalFoodSurplus, "[ICON_FoodDeficit]"); -- line 9
			table.insert(tGrowthTT, "[Color:StatBadCS]"..string.upper(Locale.Lookup("LOC_HUD_CITY_STARVING")).."[ENDCOLOR]"); -- starving marker
			table.insert(tGrowthTT, Locale.Lookup("LOC_HUD_CITY_TURNS_UNTIL_CITIZEN_LOST", math.abs(data.TurnsUntilGrowth))); -- line 10
		end	
		
		data.TotalFoodSurplusToolTip = table.concat(tGrowthTT, "[NEWLINE]");

		-- Gathering Storm
		--if bIsGatheringStorm then AppendXP2CityData(data); end
	
	end -- for Cities:Members

	kCityTotalData.Expenses[YieldTypes.GOLD] = pTreasury:GetTotalMaintenance();

	-- NET = Income - Expense
	kCityTotalData.Net[YieldTypes.GOLD]			= kCityTotalData.Income[YieldTypes.GOLD] - kCityTotalData.Expenses[YieldTypes.GOLD];
	kCityTotalData.Net[YieldTypes.FAITH]		= kCityTotalData.Income[YieldTypes.FAITH];

	-- Treasury
	kCityTotalData.Treasury[YieldTypes.CULTURE]		= Round( pCulture:GetCultureYield(), 0 );
	kCityTotalData.Treasury[YieldTypes.FAITH]		= Round( pReligion:GetFaithBalance(), 0 );
	kCityTotalData.Treasury[YieldTypes.GOLD]		= Round( pTreasury:GetGoldBalance(), 0 );
	kCityTotalData.Treasury[YieldTypes.SCIENCE]		= Round( pScience:GetScienceYield(), 0 );
	kCityTotalData.Treasury["TOURISM"]				= Round( kCityTotalData.Income["TOURISM"], 0 );

	-- Units (TODO: Group units by promotion class and determine total maintenance cost)
	--print("FUN GetData() - units");
	--local MaintenanceDiscountPerUnit:number = pTreasury:GetMaintDiscountPerUnit(); -- used also for Units tab, so defined earlier
	--local pUnits :table = player:GetUnits(); -- 230425 move up
	for i, pUnit in pUnits:Members() do
		local pUnitInfo:table = GameInfo.Units[pUnit:GetUnitType()];
		-- get localized unit name with appropriate suffix
		local unitName :string = Locale.Lookup(pUnitInfo.Name);
		local unitMilitaryFormation = pUnit:GetMilitaryFormation();
		if (unitMilitaryFormation == MilitaryFormationTypes.CORPS_FORMATION) then
			--unitName = unitName.." "..Locale.Lookup( (pUnitInfo.Domain == "DOMAIN_SEA" and "LOC_HUD_UNIT_PANEL_FLEET_SUFFIX") or "LOC_HUD_UNIT_PANEL_CORPS_SUFFIX");
			--unitName = unitName.." [ICON_Corps]";
		elseif (unitMilitaryFormation == MilitaryFormationTypes.ARMY_FORMATION) then
			--unitName = unitName.." "..Locale.Lookup( (pUnitInfo.Domain == "DOMAIN_SEA" and "LOC_HUD_UNIT_PANEL_ARMADA_SUFFIX") or "LOC_HUD_UNIT_PANEL_ARMY_SUFFIX");
			--unitName = unitName.." [ICON_Army]";
		else
			--BRS Civilian units can be NO_FORMATION (-1) or STANDARD (0)
			unitMilitaryFormation = MilitaryFormationTypes.STANDARD_FORMATION; -- 0
		end
		-- calculate unit maintenance with discount if active
		local TotalMaintenanceAfterDiscount:number = math.max(GetUnitMaintenance(pUnit) - MaintenanceDiscountPerUnit, 0); -- cannot go below 0
		local unitTypeKey = pUnitInfo.UnitType..unitMilitaryFormation;
		if kUnitData[unitTypeKey] == nil then
			kUnitData[unitTypeKey] = { Name = Locale.Lookup(pUnitInfo.Name), Formation = unitMilitaryFormation, Count = 1, Maintenance = TotalMaintenanceAfterDiscount };
			if bIsGatheringStorm then kUnitData[unitTypeKey].ResCount = 0; end
		else
			kUnitData[unitTypeKey].Count = kUnitData[unitTypeKey].Count + 1;
			kUnitData[unitTypeKey].Maintenance = kUnitData[unitTypeKey].Maintenance + TotalMaintenanceAfterDiscount;
		end
		-- Gathering Storm
		if bIsGatheringStorm then
			kUnitData[unitTypeKey].ResIcon = "";
			local unitInfoXP2:table = GameInfo.Units_XP2[ pUnitInfo.UnitType ];
			if unitInfoXP2 ~= nil and unitInfoXP2.ResourceMaintenanceType ~= nil then
				kUnitData[unitTypeKey].ResIcon  = "[ICON_"..unitInfoXP2.ResourceMaintenanceType.."]";
				kUnitData[unitTypeKey].ResCount = kUnitData[unitTypeKey].ResCount + unitInfoXP2.ResourceMaintenanceAmount;
			end
		end
	end

	-- =================================================================
	-- BRS Current Deals Info (didn't wanna mess with diplomatic deal data
	-- below, maybe later
	-- =================================================================
	--print("FUN GetData() - deals");
	local kCurrentDeals : table = {}
	local kPlayers : table = PlayerManager.GetAliveMajors()
	local iTotal = 0

	for _, pOtherPlayer in ipairs( kPlayers ) do
		local otherID:number = pOtherPlayer:GetID()
		if  otherID ~= playerID then
			
			local pPlayerConfig	:table = PlayerConfigurations[otherID]
			local pDeals		:table = DealManager.GetPlayerDeals( playerID, otherID )
			
			if pDeals ~= nil then

				for i, pDeal in ipairs( pDeals ) do
					iTotal = iTotal + 1

					local Receiving : table = { Agreements = {}, Gold = {}, Resources = {} }
					local Sending : table = { Agreements = {}, Gold = {}, Resources = {} }

					Receiving.Resources = pDeal:FindItemsByType( DealItemTypes.RESOURCES, DealItemSubTypes.NONE, otherID )
					Receiving.Gold = pDeal:FindItemsByType( DealItemTypes.GOLD, DealItemSubTypes.NONE, otherID )
					Receiving.Agreements = pDeal:FindItemsByType( DealItemTypes.AGREEMENTS, DealItemSubTypes.NONE, otherID )

					Sending.Resources = pDeal:FindItemsByType( DealItemTypes.RESOURCES, DealItemSubTypes.NONE, playerID )
					Sending.Gold = pDeal:FindItemsByType( DealItemTypes.GOLD, DealItemSubTypes.NONE, playerID )
					Sending.Agreements = pDeal:FindItemsByType( DealItemTypes.AGREEMENTS, DealItemSubTypes.NONE, playerID )

					kCurrentDeals[iTotal] =
					{
						WithCivilization = Locale.Lookup( pPlayerConfig:GetCivilizationDescription() ),
						EndTurn = 0,
						Receiving = {},
						Sending = {}
					}

					local iDeal = 0

					for pReceivingName, pReceivingGroup in pairs( Receiving ) do
						for _, pDealItem in ipairs( pReceivingGroup ) do

							iDeal = iDeal + 1

							kCurrentDeals[iTotal].EndTurn = pDealItem:GetEndTurn()
							kCurrentDeals[iTotal].Receiving[iDeal] = { Amount = pDealItem:GetAmount() }

							local deal = kCurrentDeals[iTotal].Receiving[iDeal]

							if pReceivingName == "Agreements" then
								deal.Name = pDealItem:GetSubTypeNameID()
							elseif pReceivingName == "Gold" then
								deal.Name = deal.Amount.." "..Locale.Lookup("LOC_DIPLOMACY_DEAL_GOLD_PER_TURN");
								deal.Icon = "[ICON_GOLD]"
							else
								if deal.Amount > 1 then
									deal.Name = pDealItem:GetValueTypeNameID() .. "(" .. deal.Amount .. ")"
								else
									deal.Name = pDealItem:GetValueTypeNameID()
								end
								deal.Icon = "[ICON_" .. pDealItem:GetValueTypeID() .. "]"
							end

							deal.Name = Locale.Lookup( deal.Name )
						end
					end

					iDeal = 0

					for pSendingName, pSendingGroup in pairs( Sending ) do
						for _, pDealItem in ipairs( pSendingGroup ) do

							iDeal = iDeal + 1

							kCurrentDeals[iTotal].EndTurn = pDealItem:GetEndTurn()
							kCurrentDeals[iTotal].Sending[iDeal] = { Amount = pDealItem:GetAmount() }
							
							local deal = kCurrentDeals[iTotal].Sending[iDeal]

							if pSendingName == "Agreements" then
								deal.Name = pDealItem:GetSubTypeNameID()
							elseif pSendingName == "Gold" then
								deal.Name = deal.Amount.." "..Locale.Lookup("LOC_DIPLOMACY_DEAL_GOLD_PER_TURN");
								deal.Icon = "[ICON_GOLD]"
							else
								if deal.Amount > 1 then
									deal.Name = pDealItem:GetValueTypeNameID() .. "(" .. deal.Amount .. ")"
								else
									deal.Name = pDealItem:GetValueTypeNameID()
								end
								deal.Icon = "[ICON_" .. pDealItem:GetValueTypeID() .. "]"
							end

							deal.Name = Locale.Lookup( deal.Name )
						end
					end
				end
			end
		end
	end

	-- =================================================================
	
	local kDealData	:table = {};
	local kPlayers	:table = PlayerManager.GetAliveMajors();
	for _, pOtherPlayer in ipairs(kPlayers) do
		local otherID:number = pOtherPlayer:GetID();
		local currentGameTurn = Game.GetCurrentGameTurn();
		if  otherID ~= playerID then			
			
			local pPlayerConfig	:table = PlayerConfigurations[otherID];
			local pDeals		:table = DealManager.GetPlayerDeals(playerID, otherID);
			
			if pDeals ~= nil then
				for i,pDeal in ipairs(pDeals) do
				
					--if pDeal:IsValid() then -- BRS
					-- 230508 #8 I don't know why this check's been added - there is none in the vanilla game
					-- I discovered that when a player has less money than is due from per turn deals then those gold deal items are considered
					-- "invalid" thus making an entire deal "invalid"; with this check such deal is omitted and not shown.
					
					-- Add outgoing gold deals
					local pOutgoingDeal :table	= pDeal:FindItemsByType(DealItemTypes.GOLD, DealItemSubTypes.NONE, playerID);
					if pOutgoingDeal ~= nil then
						for i,pDealItem in ipairs(pOutgoingDeal) do
							local duration		:number = pDealItem:GetDuration();
							local remainingTurns:number = duration - (currentGameTurn - pDealItem:GetEnactedTurn());
							if duration ~= 0 then
								local gold :number = pDealItem:GetAmount();
								table.insert( kDealData, {
									Type		= DealItemTypes.GOLD,
									Amount		= gold,
									Duration	= remainingTurns, -- Infixo was duration in BRS
									IsOutgoing	= true,
									PlayerID	= otherID,
									Name		= Locale.Lookup( pPlayerConfig:GetCivilizationDescription() )
								});						
							end
						end
					end

					-- Add outgoing resource deals
					pOutgoingDeal = pDeal:FindItemsByType(DealItemTypes.RESOURCES, DealItemSubTypes.NONE, playerID);
					if pOutgoingDeal ~= nil then
						for i,pDealItem in ipairs(pOutgoingDeal) do
							local duration		:number = pDealItem:GetDuration();
							local remainingTurns:number = duration - (currentGameTurn - pDealItem:GetEnactedTurn());
							if duration ~= 0 then
								local amount		:number = pDealItem:GetAmount();
								local resourceType	:number = pDealItem:GetValueType();
								table.insert( kDealData, {
									Type			= DealItemTypes.RESOURCES,
									ResourceType	= resourceType,
									Amount			= amount,
									Duration		= remainingTurns, -- Infixo was duration in BRS
									IsOutgoing		= true,
									PlayerID		= otherID,
									Name			= Locale.Lookup( pPlayerConfig:GetCivilizationDescription() )
								});
								
								local entryString:string = Locale.Lookup("LOC_HUD_REPORTS_ROW_DIPLOMATIC_DEALS") .. " (" .. Locale.Lookup(pPlayerConfig:GetPlayerName()) .. " " .. Locale.Lookup("LOC_REPORTS_NUMBER_OF_TURNS", remainingTurns) .. ")";
								AddResourceData(kResources, resourceType, entryString, "LOC_HUD_REPORTS_TRADE_EXPORTED", -1 * amount);				
							end
						end
					end
					
					-- Add incoming gold deals
					local pIncomingDeal :table = pDeal:FindItemsByType(DealItemTypes.GOLD, DealItemSubTypes.NONE, otherID);
					if pIncomingDeal ~= nil then
						for i,pDealItem in ipairs(pIncomingDeal) do
							local duration		:number = pDealItem:GetDuration();
							local remainingTurns:number = duration - (currentGameTurn - pDealItem:GetEnactedTurn());
							if duration ~= 0 then
								local gold :number = pDealItem:GetAmount()
								table.insert( kDealData, {
									Type		= DealItemTypes.GOLD;
									Amount		= gold,
									Duration	= remainingTurns, -- Infixo was duration in BRS
									IsOutgoing	= false,
									PlayerID	= otherID,
									Name		= Locale.Lookup( pPlayerConfig:GetCivilizationDescription() )
								});						
							end
						end
					end

					-- Add incoming resource deals
					pIncomingDeal = pDeal:FindItemsByType(DealItemTypes.RESOURCES, DealItemSubTypes.NONE, otherID);
					if pIncomingDeal ~= nil then
						for i,pDealItem in ipairs(pIncomingDeal) do
							local duration		:number = pDealItem:GetDuration();
							if duration ~= 0 then
								local amount		:number = pDealItem:GetAmount();
								local resourceType	:number = pDealItem:GetValueType();
								local remainingTurns:number = duration - (currentGameTurn - pDealItem:GetEnactedTurn());
								table.insert( kDealData, {
									Type			= DealItemTypes.RESOURCES,
									ResourceType	= resourceType,
									Amount			= amount,
									Duration		= remainingTurns, -- Infixo was duration in BRS
									IsOutgoing		= false,
									PlayerID		= otherID,
									Name			= Locale.Lookup( pPlayerConfig:GetCivilizationDescription() )
								});
								
								local entryString:string = Locale.Lookup("LOC_HUD_REPORTS_ROW_DIPLOMATIC_DEALS") .. " (" .. Locale.Lookup(pPlayerConfig:GetPlayerName()) .. " " .. Locale.Lookup("LOC_REPORTS_NUMBER_OF_TURNS", remainingTurns) .. ")";
								AddResourceData(kResources, resourceType, entryString, "LOC_HUD_REPORTS_TRADE_IMPORTED", amount);				
							end
						end
					end	
					--end	-- BRS end
				end							
			end

		end
	end

	-- Add resources provided by city states
	for i, pMinorPlayer in ipairs(PlayerManager.GetAliveMinors()) do
		local pMinorPlayerInfluence:table = pMinorPlayer:GetInfluence();		
		if pMinorPlayerInfluence ~= nil then
			local suzerainID:number = pMinorPlayerInfluence:GetSuzerain();
			if suzerainID == playerID then
				for row in GameInfo.Resources() do
					-- 230508 #11 GetExportedResourceAmount usually returns 0 thus the resource is not registered as coming from city-state
					-- It only later is recognized as generic "gameplay bonus" due to difference in total vs. registered so far
					local resourceAmount:number = pMinorPlayer:GetResources():GetExportedResourceAmount(row.Index) + pMinorPlayer:GetResources():GetResourceAmount(row.Index);
					if resourceAmount > 0 then
						local pMinorPlayerConfig:table = PlayerConfigurations[pMinorPlayer:GetID()];
						local entryString:string = Locale.Lookup("LOC_HUD_REPORTS_CITY_STATE") .. " (" .. Locale.Lookup(pMinorPlayerConfig:GetPlayerName()) .. ")";
						AddResourceData(kResources, row.Index, entryString, "LOC_CITY_STATES_SUZERAIN", resourceAmount);
					end
				end
			end
		end
	end
	
	kResources = AddMiscResourceData(pResources, kResources);

	--BRS !! changed
	return kCityData, kCityTotalData, kResources, kUnitData, kDealData, kCurrentDeals, kUnitDataReport;
end

-- ===========================================================================
-- Obtain unit maintenance, BRS: left here because 2 reports are using it
-- This function will use GameInfo for vanilla game and UnitManager for R&F/GS
function GetUnitMaintenance(pUnit:table)
	if bIsRiseFall or bIsGatheringStorm then
		-- Rise & Fall version
		local iUnitInfoHash:number = GameInfo.Units[ pUnit:GetUnitType() ].Hash;
		local unitMilitaryFormation = pUnit:GetMilitaryFormation();
		if unitMilitaryFormation == MilitaryFormationTypes.CORPS_FORMATION then return UnitManager.GetUnitCorpsMaintenance(iUnitInfoHash); end
		if unitMilitaryFormation == MilitaryFormationTypes.ARMY_FORMATION  then return UnitManager.GetUnitArmyMaintenance(iUnitInfoHash); end
																				return UnitManager.GetUnitMaintenance(iUnitInfoHash);
	end
	-- vanilla version
	local iUnitMaintenance:number = GameInfo.Units[ pUnit:GetUnitType() ].Maintenance;
	local unitMilitaryFormation = pUnit:GetMilitaryFormation();
	if unitMilitaryFormation == MilitaryFormationTypes.CORPS_FORMATION then return math.ceil(iUnitMaintenance * 1.5); end -- it is 150% rounded UP
	if unitMilitaryFormation == MilitaryFormationTypes.ARMY_FORMATION  then return iUnitMaintenance * 2; end -- it is 200%
	                                                                        return iUnitMaintenance;
end


-- ===========================================================================
--	Set a group to it's proper collapse/open state
--	Set + - in group row
-- ===========================================================================
function RealizeGroup( instance:table )
	local v :number = (instance["isCollapsed"]==false and instance.RowExpandCheck:GetSizeY() or 0);
	instance.RowExpandCheck:SetTextureOffsetVal(0, v);

	instance.ContentStack:CalculateSize();	
	instance.CollapseScroll:CalculateSize();
	
	local groupHeight	:number = instance.ContentStack:GetSizeY();
	instance.CollapseAnim:SetBeginVal(0, -(groupHeight - instance["CollapsePadding"]));
	instance.CollapseScroll:SetSizeY( groupHeight );				

	instance.Top:ReprocessAnchoring();
end

-- ===========================================================================
--	Callback
--	Expand or contract a group based on its existing state.
-- ===========================================================================
function OnToggleCollapseGroup( instance:table )
	instance["isCollapsed"] = not instance["isCollapsed"];
	instance.CollapseAnim:Reverse();
	RealizeGroup( instance );
end

-- ===========================================================================
--	Toggle a group expanding / collapsing
--	instance,	A group instance.
-- ===========================================================================
function OnAnimGroupCollapse( instance:table)
		-- Helper
	function lerp(y1:number,y2:number,x:number)
		return y1 + (y2-y1)*x;
	end
	local groupHeight	:number = instance.ContentStack:GetSizeY();
	local collapseHeight:number = instance["CollapsePadding"]~=nil and instance["CollapsePadding"] or 0;
	local startY		:number = instance["isCollapsed"]==true  and groupHeight or collapseHeight;
	local endY			:number = instance["isCollapsed"]==false and groupHeight or collapseHeight;
	local progress		:number = instance.CollapseAnim:GetProgress();
	local sizeY			:number = lerp(startY,endY,progress);
		
	instance.CollapseAnim:SetSizeY( groupHeight );		-- BRS added, INFIXO CHECK
	instance.CollapseScroll:SetSizeY( sizeY );	
	instance.ContentStack:ReprocessAnchoring();	
	instance.Top:ReprocessAnchoring()

	Controls.Stack:CalculateSize();
	Controls.Scroll:CalculateSize();			
end


-- ===========================================================================
function SetGroupCollapsePadding( instance:table, amount:number )
	instance["CollapsePadding"] = amount;
end


-- ===========================================================================
function ResetTabForNewPageContent()
	m_uiGroups = {};
	m_simpleIM:ResetInstances();
	m_groupIM:ResetInstances();
	m_isCollapsing = true;
	Controls.CollapseAll:LocalizeAndSetText("LOC_HUD_REPORTS_COLLAPSE_ALL");
	Controls.Scroll:SetScrollValue( 0 );	
end


-- ===========================================================================
--	Instantiate a new collapsable row (group) holder & wire it up.
--	ARGS:	(optional) isCollapsed
--	RETURNS: New group instance
-- ===========================================================================
function NewCollapsibleGroupInstance( isCollapsed:boolean )
	if isCollapsed == nil then
		isCollapsed = false;
	end
	local instance:table = m_groupIM:GetInstance();	
	instance.ContentStack:DestroyAllChildren();
	instance["isCollapsed"]		= isCollapsed;
	instance["CollapsePadding"] = nil;				-- reset any prior collapse padding

	--BRS !! added
	instance["Children"] = {}
	instance["Descend"] = false
	-- !!

	instance.CollapseAnim:SetToBeginning();
	if isCollapsed == false then
		instance.CollapseAnim:SetToEnd();
	end	

	instance.RowHeaderButton:RegisterCallback( Mouse.eLClick, function() OnToggleCollapseGroup(instance); end );			
  	instance.RowHeaderButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	instance.CollapseAnim:RegisterAnimCallback(               function() OnAnimGroupCollapse( instance ); end );

	table.insert( m_uiGroups, instance );

	return instance;
end


-- ===========================================================================
--	debug - Create a test page.
-- ===========================================================================
function ViewTestPage()

	ResetTabForNewPageContent();

	local instance:table = NewCollapsibleGroupInstance();	
	instance.RowHeaderButton:SetText( "Test City Icon 1" );
	instance.Top:SetID("foo");
	
	local pHeaderInstance:table = {}
	ContextPtr:BuildInstanceForControl( "CityIncomeHeaderInstance", pHeaderInstance, instance.ContentStack ) ;	

	local pCityInstance:table = {};
	ContextPtr:BuildInstanceForControl( "CityIncomeInstance", pCityInstance, instance.ContentStack ) ;

	for i=1,3,1 do
		local pLineItemInstance:table = {};
		ContextPtr:BuildInstanceForControl("CityIncomeLineItemInstance", pLineItemInstance, pCityInstance.LineItemStack );
	end

	local pFooterInstance:table = {};
	ContextPtr:BuildInstanceForControl("CityIncomeFooterInstance", pFooterInstance, instance.ContentStack  );
	
	SetGroupCollapsePadding(instance, pFooterInstance.Top:GetSizeY() );
	RealizeGroup( instance );
	
	Controls.BottomYieldTotals:SetHide( true );
	Controls.BottomResourceTotals:SetHide( true );
	Controls.BottomPoliciesFilters:SetHide( true );
	Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - (Controls.BottomYieldTotals:GetSizeY() + SIZE_HEIGHT_PADDING_BOTTOM_ADJUST ) );
end


-- ===========================================================================
--	YIELDS PAGE
-- ===========================================================================
include("BRSPage_Yields");

-- ===========================================================================
-- RESOURCES PAGE
-- ===========================================================================
include("BRSPage_Resources");

-- ===========================================================================
-- GOSSIP PAGE
-- ===========================================================================
include("BRSPage_Gossip");

-- ===========================================================================
-- CITY STATUS PAGE
-- ===========================================================================
include("BRSPage_CityStatus");

-- ===========================================================================
-- UNITS PAGE
-- ===========================================================================
include("BRSPage_Units");

-- ===========================================================================
-- CURRENT DEALS PAGE
-- ===========================================================================
include("BRSPage_Deals");

-- ===========================================================================
-- POLICY PAGE
-- ===========================================================================
include("BRSPage_Policy");

-- ===========================================================================
-- MINOR PAGE
-- ===========================================================================
include("BRSPage_Minor");

-- ===========================================================================
-- CITIES 2 PAGE - GATHERING STORM
-- ===========================================================================
include("BRSPage_Cities2");

-- ===========================================================================
--
-- ===========================================================================
function AddTabSection( name:string, populateCallback:ifunction )
	local kTab		:table				= m_tabIM:GetInstance();	
	kTab.Button[DATA_FIELD_SELECTION]	= kTab.Selection;

	local callback	:ifunction	= function()
		if m_tabs.prevSelectedControl ~= nil then
			m_tabs.prevSelectedControl[DATA_FIELD_SELECTION]:SetHide(true);
		end
		kTab.Selection:SetHide(false);
		Timer1Start();
		populateCallback();
		Timer1Tick("Section "..Locale.Lookup(name).." populated");
	end

	kTab.Button:GetTextControl():SetText( Locale.Lookup(name) );
	kTab.Button:SetSizeToText( 0, 20 ); -- default 40,20
    kTab.Button:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	m_tabs.AddTab( kTab.Button, callback );
end


-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	local uiMsg :number = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then 
		local uiKey = pInputStruct:GetKey();
		if uiKey == Keys.VK_ESCAPE then
			if ContextPtr:IsHidden()==false then
				Close();
				return true;
			end
		end		
	end
	return false;
end

local m_ToggleReportsId:number = Input.GetActionId("ToggleReports");
--print("ToggleReports key is", m_ToggleReportsId);

function OnInputActionTriggered( actionId )
	--print("FUN OnInputActionTriggered", actionId);
	if actionId == m_ToggleReportsId then
		--print(".....Detected F8.....")
		if ContextPtr:IsHidden() then Open(); else Close(); end
	end
end

-- ===========================================================================
function Resize()
	local topPanelSizeY:number = 30;

	x,y = UIManager:GetScreenSizeVal();
	Controls.Main:SetSizeY( y - topPanelSizeY );
	Controls.Main:SetOffsetY( topPanelSizeY * 0.5 );
end

-- ===========================================================================
--	Game Event Callback
-- ===========================================================================
function OnLocalPlayerTurnEnd()
	if(GameConfiguration.IsHotseat()) then
		OnCloseButton();
	end
end

-- ===========================================================================
function LateInitialize()
	--Resize(); -- June Patch

	m_tabs = CreateTabs( Controls.TabContainer, 42, 34, UI.GetColorValueFromHexLiteral(0xFF331D05) );
	AddTabSection( "LOC_HUD_REPORTS_TAB_YIELDS",		ViewYieldsPage );
	AddTabSection( "LOC_HUD_REPORTS_TAB_RESOURCES",		ViewResourcesPage );
	AddTabSection( "LOC_HUD_REPORTS_TAB_CITIES",	ViewCityStatusPage );
	if GameCapabilities.HasCapability("CAPABILITY_GOSSIP_REPORT") then
		AddTabSection( "LOC_HUD_REPORTS_TAB_GOSSIP", ViewGossipPage );
	end
	AddTabSection( "LOC_HUD_REPORTS_TAB_DEALS",			ViewDealsPage );
	AddTabSection( "LOC_HUD_REPORTS_TAB_UNITS",			ViewUnitsPage );
	AddTabSection( "LOC_HUD_REPORTS_TAB_POLICIES",		ViewPolicyPage );
	AddTabSection( "LOC_HUD_REPORTS_TAB_MINORS",		ViewMinorPage );
	if bIsGatheringStorm then AddTabSection( "LOC_HUD_REPORTS_TAB_CITIES2", ViewCities2Page ); end

	m_tabs.SameSizedTabs(20);
	m_tabs.CenterAlignTabs(-10);
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnInit( isReload:boolean )
	LateInitialize();
	if isReload then		
		if ContextPtr:IsHidden() == false then
			Open();
		end
	end
	m_tabs.AddAnimDeco(Controls.TabAnim, Controls.TabArrow);	
end


-- ===========================================================================
-- CHECKBOXES
-- ===========================================================================

-- Checkboxes for hiding city details and free units/buildings

function OnToggleHideCityBuildings()
	local isChecked = Controls.HideCityBuildingsCheckbox:IsSelected();
	Controls.HideCityBuildingsCheckbox:SetSelected( not isChecked );
	ViewYieldsPage()
end

function OnToggleHideFreeBuildings()
	local isChecked = Controls.HideFreeBuildingsCheckbox:IsSelected();
	Controls.HideFreeBuildingsCheckbox:SetSelected( not isChecked );
	ViewYieldsPage()
end

function OnToggleHideFreeUnits()
	local isChecked = Controls.HideFreeUnitsCheckbox:IsSelected();
	Controls.HideFreeUnitsCheckbox:SetSelected( not isChecked );
	ViewYieldsPage()
end

-- Checkboxes for different resources in Resources tab

function OnToggleStrategic()
	local isChecked = Controls.StrategicCheckbox:IsSelected();
	Controls.StrategicCheckbox:SetSelected( not isChecked );
	ViewResourcesPage();
end

function OnToggleLuxury()
	local isChecked = Controls.LuxuryCheckbox:IsSelected();
	Controls.LuxuryCheckbox:SetSelected( not isChecked );
	ViewResourcesPage();
end

function OnToggleBonus()
	local isChecked = Controls.BonusCheckbox:IsSelected();
	Controls.BonusCheckbox:SetSelected( not isChecked );
	ViewResourcesPage();
end

-- Checkboxes for policy filters

function OnToggleInactivePolicies()
	local isChecked = Controls.HideInactivePoliciesCheckbox:IsSelected();
	Controls.HideInactivePoliciesCheckbox:SetSelected( not isChecked );
	ViewPolicyPage();
end

function OnToggleNoImpactPolicies()
	local isChecked = Controls.HideNoImpactPoliciesCheckbox:IsSelected();
	Controls.HideNoImpactPoliciesCheckbox:SetSelected( not isChecked );
	ViewPolicyPage();
end

-- Checkboxes for minors filters

function OnToggleNotMetMinors()
	local isChecked = Controls.HideNotMetMinorsCheckbox:IsSelected();
	Controls.HideNotMetMinorsCheckbox:SetSelected( not isChecked );
	ViewMinorPage();
end

function OnToggleNoImpactMinors()
	local isChecked = Controls.HideNoImpactMinorsCheckbox:IsSelected();
	Controls.HideNoImpactMinorsCheckbox:SetSelected( not isChecked );
	ViewMinorPage();
end


-- ===========================================================================
function Initialize()

	InitializePolicyData();
	InitializeAbilitiesUnits(); -- 230425 cache for abilities

	-- UI Callbacks
	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetInputHandler( OnInputHandler, true );

	InitializeUnits();

	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnCloseButton );
	Controls.CloseButton:RegisterCallback(	Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.CollapseAll:RegisterCallback( Mouse.eLClick, OnCollapseAllButton );
	Controls.CollapseAll:RegisterCallback(	Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	--BRS Yields tab toggle
	Controls.HideCityBuildingsCheckbox:RegisterCallback( Mouse.eLClick, OnToggleHideCityBuildings )
	Controls.HideCityBuildingsCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end )
	Controls.HideCityBuildingsCheckbox:SetSelected( true );
	Controls.HideFreeBuildingsCheckbox:RegisterCallback( Mouse.eLClick, OnToggleHideFreeBuildings )
	Controls.HideFreeBuildingsCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end )
	Controls.HideFreeBuildingsCheckbox:SetSelected( true );
	Controls.HideFreeUnitsCheckbox:RegisterCallback( Mouse.eLClick, OnToggleHideFreeUnits )
	Controls.HideFreeUnitsCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end )
	Controls.HideFreeUnitsCheckbox:SetSelected( true );
	
	--ARISTOS: Resources toggle
	Controls.LuxuryCheckbox:RegisterCallback( Mouse.eLClick, OnToggleLuxury );
	Controls.LuxuryCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.LuxuryCheckbox:SetSelected( true );
	Controls.StrategicCheckbox:RegisterCallback( Mouse.eLClick, OnToggleStrategic );
	Controls.StrategicCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.StrategicCheckbox:SetSelected( true );
	Controls.BonusCheckbox:RegisterCallback( Mouse.eLClick, OnToggleBonus );
	Controls.BonusCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.BonusCheckbox:SetSelected( false ); -- not so important

	-- Polices Filters
	Controls.HideInactivePoliciesCheckbox:RegisterCallback( Mouse.eLClick, OnToggleInactivePolicies );
	Controls.HideInactivePoliciesCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.HideInactivePoliciesCheckbox:SetSelected( true );
	Controls.HideNoImpactPoliciesCheckbox:RegisterCallback( Mouse.eLClick, OnToggleNoImpactPolicies );
	Controls.HideNoImpactPoliciesCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.HideNoImpactPoliciesCheckbox:SetSelected( false );

	-- Minors Filters
	Controls.HideNotMetMinorsCheckbox:RegisterCallback( Mouse.eLClick, OnToggleNotMetMinors );
	Controls.HideNotMetMinorsCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.HideNotMetMinorsCheckbox:SetSelected( true );
	Controls.HideNoImpactMinorsCheckbox:RegisterCallback( Mouse.eLClick, OnToggleNoImpactMinors );
	Controls.HideNoImpactMinorsCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.HideNoImpactMinorsCheckbox:SetSelected( false );

	-- Events
	LuaEvents.TopPanel_OpenReportsScreen.Add(  function() Open();  end );
	LuaEvents.TopPanel_CloseReportsScreen.Add( function() Close(); end );
	LuaEvents.ReportsList_OpenYields.Add(     function() Open(1); end );
	LuaEvents.ReportsList_OpenResources.Add(  function() Open(2); end );
	LuaEvents.ReportsList_OpenCityStatus.Add( function() Open(3); end );
	if GameCapabilities.HasCapability("CAPABILITY_GOSSIP_REPORT") then
		LuaEvents.ReportsList_OpenGossip.Add( function() Open(4); end );
	end
	LuaEvents.ReportsList_OpenDeals.Add(      function() Open(5); end );
	LuaEvents.ReportsList_OpenUnits.Add(      function() Open(6); end );
	LuaEvents.ReportsList_OpenPolicies.Add(   function() Open(7); end );
	LuaEvents.ReportsList_OpenMinors.Add(     function() Open(8); end );
	if bIsGatheringStorm then LuaEvents.ReportsList_OpenCities2.Add( function() Open(9); end ); end
	
	Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );
	Events.InputActionTriggered.Add( OnInputActionTriggered );
end
Initialize();

print("OK loaded ReportScreen.lua from Better Report Screen");
