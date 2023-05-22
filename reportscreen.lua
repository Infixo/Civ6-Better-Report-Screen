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
include("TabSupport");

-- Exposing functions and variables
if not ExposedMembers.RMA then ExposedMembers.RMA = {} end;
RMA = ExposedMembers.RMA;

-- Expansions check
bIsRiseFall = Modding.IsModActive("1B28771A-C749-434B-9053-D1380C553DE9"); -- Rise & Fall
print("Rise & Fall    :", (bIsRiseFall and "YES" or "no"));
bIsGatheringStorm = Modding.IsModActive("4873eb62-8ccc-4574-b784-dda455e74e68"); -- Gathering Storm
print("Gathering Storm:", (bIsGatheringStorm and "YES" or "no"));
bIsMonopolies = GameCapabilities.HasCapability("CAPABILITY_MONOPOLIES"); -- Monopoly and Corporations Mode
print("Monopolies     :", (bIsMonopolies and "YES" or "no"));

-- Configuration options
bOptionModifiers = ( GlobalParameters.BRS_OPTION_MODIFIERS == 1 );

-- Global constants
LL = Locale.Lookup;
ENDCOLOR = "[ENDCOLOR]";
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

-- Instance Managers
m_simpleIM = InstanceManager:new("SimpleInstance", "Top", Controls.Stack); -- Non-Collapsable, simple
m_groupIM  = InstanceManager:new("GroupInstance",  "Top", Controls.Stack); -- Collapsable

-- Remember last tab variable: ARISTOS
m_kCurrentTab = 1;

-- 230510 Dirty flags - if true then the data needs to be updated
g_DirtyFlag = {
	YIELDS = true,
	YIELDSDETAILS = true,
	RESOURCES = true,
	CITYSTATUS = true,
	GOSSIP = true,
	DEALS = true,
	UNITS = true,
	POLICY = true,
	MINOR = true,
	CITIES2 = true,
};


-- Tab support
local DATA_FIELD_SELECTION: string = "Selection";
local m_tabIM: table = InstanceManager:new("TabInstance", "Button", Controls.TabContainer);
local m_tabs: table = nil;

-- Collapsing support
local m_uiGroups			:table = nil;	-- Track the groups on-screen for collapse all action.
local m_isCollapsing		:boolean = true;


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
		Timer1Tick("Page "..Locale.Lookup(name));
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
	
	InitializeYields();
	InitializeResources();
	InitializePolicy();
	InitializeMinor();
	
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
