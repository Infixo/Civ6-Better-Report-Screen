-- ===========================================================================
-- Better Report Screen - page Minor
-- Author: Infixo
-- 2023-05-10: Created
-- ===========================================================================

m_kMinorData = nil; -- global for debug purposes

-- helper to get Category out of Civ Type; categories are: CULTURAL, INDUSTRIAL, MILITARISTIC, etc.
function GetCityStateCategory(sCivType:string)
	for row in GameInfo.TypeProperties() do
		if row.Type == sCivType and row.Name == "CityStateCategory" then return row.Value; end
	end
	print("ERROR: GetCityStateCategory() no City State category for", sCivType);
	return "UNKNOWN";
end

-- helper to get a Leader for a Minor; assumes only 1 leader per Minor
function GetCityStateLeader(sCivType:string)
	for row in GameInfo.CivilizationLeaders() do
		if row.CivilizationType == sCivType then return row.LeaderType; end
	end
	print("ERROR: GetCityStateLeader() no City State leader for", sCivType);
	return "UNKNOWN";
end

-- helper to get a Trait for a Minor Leader; assumes only 1 trait per Minor Leader
function GetCityStateTrait(sLeaderType:string)
	for row in GameInfo.LeaderTraits() do
		if row.LeaderType == sLeaderType then return row.TraitType; end
	end
	print("ERROR: GetCityStateTrait() no Trait for", sLeaderType);
	return "UNKNOWN";
end

function UpdateMinorData()
	print("UpdateMinorData");
	Timer1Start();

	local tMinorBonuses:table = {}; -- helper table to quickly access bonuses
	-- prepare empty categories
	m_kMinorData = {};
	for row in GameInfo.TypeProperties() do
		if row.Name == "CityStateCategory" and m_kMinorData[ row.Value ] == nil then
			m_kMinorData[ row.Value ] = {};
			tMinorBonuses[ row.Value ] = {};
		end
	end
	-- 2019-01-26: Australia scenario removes entries from TypeProperties but still uses those Categories
	for leader in GameInfo.Leaders() do
		if leader.InheritFrom == "LEADER_MINOR_CIV_DEFAULT" then
			local sCategory:string = string.gsub(leader.LeaderType, "LEADER_MINOR_CIV_", "");
			if m_kMinorData[ sCategory ] == nil then
				print("WARNING: UpdateMinorData() LeaderType", leader.LeaderType, "uses category that doesn't exist in TypeProperties; registering", sCategory);
				m_kMinorData[ sCategory ] = {};
				tMinorBonuses[ sCategory ] = {};
			end
		end
	end
	--print("*** Minors in TypeProperties ***"); dshowrectable(m_kMinorData); -- debug
	
	-- find out our level of involvement with alive Minors
	local tMinorRelations:table = {};
	local ePlayerID:number = Game.GetLocalPlayer();
	for _,minor in ipairs(PlayerManager.GetAliveMinors()) do
		-- we need to check for City State actually, because Free Cities are considered Minors as well
		if minor:IsMinor() then -- CIVILIZATION_LEVEL_CITY_STATE
			local minorRelation:table = {
				CivType    = PlayerConfigurations[minor:GetID()]:GetCivilizationTypeName(), -- CIVILIZATION_VILNIUS
				LeaderType = PlayerConfigurations[minor:GetID()]:GetLeaderTypeName(), -- LEADER_MINOR_CIV_VILNIUS
				IsSuzerained = ( minor:GetInfluence():GetSuzerain() == ePlayerID ), -- boolean
				NumTokens  = minor:GetInfluence():GetTokensReceived(ePlayerID),
				HasMet     = minor:GetDiplomacy():HasMet(ePlayerID),
				--HasMet     = Players[ePlayerID]:GetDiplomacy():HasMet(minor:GetID()),
			};
			tMinorRelations[ minorRelation.CivType ] = minorRelation;
		end
	end
	--print("*** Relations with Alive Minors ***"); dshowrectable(tMinorRelations);
	
	-- iterate through all Minors
	-- assumptions: no Civilization Traits are used, only Leader Traits; each has 1 leader; main leader is for Suzerain bonus; Inherited leaders are for small/medium/large bonuses
	
	-- first, fill out Inherited leaders
	for leader in GameInfo.Leaders() do
		if leader.InheritFrom == "LEADER_MINOR_CIV_DEFAULT" then
			local sCategory:string = string.gsub(leader.LeaderType, "LEADER_MINOR_CIV_", "");

			local function RegisterLeaderForInfluence(iNumTokens:number, sInfluence:string)
				local minorData:table = {
					--Index = civ.Index,
					CivType = leader.LeaderType,
					Category = sCategory,
					Name = LL("LOC_MINOR_CIV_"..sInfluence.."_INFLUENCE_ENVOYS"), -- unfortunately this is all hardcoded in LOCs, [ICON_Envoy]
					LeaderType = leader.LeaderType,
					Description = LL("LOC_MINOR_CIV_"..sCategory.."_TRAIT_"..sInfluence.."_INFLUENCE_BONUS"), -- unfortunately this is all hardcoded in LOCs
					NumTokens = iNumTokens, -- required number of envoys to achieve this influence level
					Trait = GetCityStateTrait(leader.LeaderType),
					Influence = 0, -- this will hold number of City States that with this influence level
					IsSuzerained = false, -- not used
					HasMet = false, -- will be true if any of that category has been met
					--Yields from modifiers
				};
				--print("registering leader", iNumTokens, sInfluence); dshowtable(minorData);
				-- impact from modifiers; the 5th parameter is used to select proper modifiers, it is the ONLY place where it is used
				minorData.Impact, minorData.Yields, minorData.ImpactToolTip, minorData.UnknownEffect = RMA.CalculateModifierEffect("Trait", minorData.Trait, ePlayerID, nil, sInfluence);
				minorData.IsImpact = false; -- for toggling options
				for _,value in pairs(minorData.Yields) do if value ~= 0 then minorData.IsImpact = true; break; end end
				-- done!
				table.insert(m_kMinorData[ minorData.Category ], minorData);
				tMinorBonuses[ minorData.Category ][ iNumTokens ] = minorData;
			end
			-- we will have to actually triple this
			RegisterLeaderForInfluence(1, "SMALL"); -- unfortunately this is all hardcoded in LOCs
			RegisterLeaderForInfluence(3, "MEDIUM");
			RegisterLeaderForInfluence(6, "LARGE");
		end
	end
	--dshowrectable(tMinorBonuses); -- debug
	-- OK UP TO THIS POINT
	-- second, fill out Main leaders
	for civ in GameInfo.Civilizations() do
		if civ.StartingCivilizationLevelType == "CIVILIZATION_LEVEL_CITY_STATE" then
			local minorData:table = {
				--Index = civ.Index,
				CivType = civ.CivilizationType,
				Category = GetCityStateCategory(civ.CivilizationType),
				Name = Locale.Lookup(civ.Name),
				LeaderType = GetCityStateLeader(civ.CivilizationType),
				Description = "", -- later
				NumTokens = 0, -- always 0
				Trait = "", -- later
				Influence = 0, -- this will hold number of envoys sent to this CS
				IsSuzerained = false, -- later
				HasMet = false, -- later
				--Yields from modifiers
			};
			--print("*** Found CS ***"); dshowtable(minorData);
			minorData.Trait = GetCityStateTrait(minorData.LeaderType);
			local tMinorRelation:table = tMinorRelations[ civ.CivilizationType ];
			if tMinorRelation ~= nil then
				minorData.Influence = tMinorRelation.NumTokens;
				minorData.IsSuzerained = tMinorRelation.IsSuzerained;
				minorData.HasMet = tMinorRelation.HasMet;
				-- register in bonuses
				for _,bonus in pairs(tMinorBonuses[minorData.Category]) do
					if minorData.Influence >= bonus.NumTokens then bonus.Influence = bonus.Influence + 1; end
					if minorData.HasMet then bonus.HasMet = true; end
				end
			end
			-- description is actually a suzerain bonus descripion
			-- it can contain many lines, from many Traits
			local tStr:table = {};
			for row in GameInfo.LeaderTraits() do
				if row.LeaderType == minorData.LeaderType then
					local sLeaderTrait:string = row.TraitType;
					for trait in GameInfo.Traits() do
						if trait.TraitType == sLeaderTrait and not trait.InternalOnly then table.insert(tStr, Locale.Lookup(trait.Description)); end
					end
				end
			end
			if #tStr == 0 then print("WARNING: UpdateMinorData() no traits for", minorData.Name); end
			minorData.Description = table.concat(tStr, "[NEWLINE]");
			--print("=== before RMA ===");
			-- impact from modifiers
			minorData.Impact, minorData.Yields, minorData.ImpactToolTip, minorData.UnknownEffect = RMA.CalculateModifierEffect("Trait", minorData.Trait, ePlayerID, nil);
			--print("=== after RMA ===");
			minorData.IsImpact = false; -- for toggling options
			for _,value in pairs(minorData.Yields) do if value ~= 0 then minorData.IsImpact = true; break; end end
			-- done!
			--print("*** Inserting CS ***"); dshowtable(minorData);
			table.insert(m_kMinorData[ minorData.Category ], minorData);
		end -- level City State
	end -- all civs

	Timer1Tick("UpdateMinorData");
	--dshowrectable(m_kMinorData);
	g_DirtyFlag.MINOR = false;
end

function ViewMinorPage()
	print("ViewMinorPage");
	
	if g_DirtyFlag.MINOR then UpdateMinorData(); end

	ResetTabForNewPageContent();

	for minorGroup,minors in spairs( m_kMinorData, function(t,a,b) return a < b; end ) do -- simple sort by group code name
		local instance : table = NewCollapsibleGroupInstance()
		
		instance.RowHeaderButton:SetText( Locale.Lookup("LOC_CITY_STATES_TYPE_"..minorGroup) );
		instance.RowHeaderLabel:SetHide( false );
		instance.AmenitiesContainer:SetHide(true);
        instance.IndustryContainer:SetHide(true); -- 2021-05-21
        instance.MonopolyContainer:SetHide(true); -- 2021-05-21
		
		local pHeaderInstance:table = {}
		ContextPtr:BuildInstanceForControl( "PolicyHeaderInstance", pHeaderInstance, instance.ContentStack ) -- instance ID, pTable, stack
		pHeaderInstance.PolicyHeaderLabelName:SetText( Locale.Lookup("LOC_HUD_REPORTS_CITY_STATE") );
		local iNumRows:number = 0;
		pHeaderInstance.PolicyHeaderButtonLOYALTY:SetHide( not (bIsRiseFall or bIsGatheringStorm) );
		
		-- set sorting callbacks
		--if pHeaderInstance.UnitTypeButton then     pHeaderInstance.UnitTypeButton:RegisterCallback(    Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "type", iUnitGroup, instance ) end ) end
		--if pHeaderInstance.UnitNameButton then     pHeaderInstance.UnitNameButton:RegisterCallback(    Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "name", iUnitGroup, instance ) end ) end
		--if pHeaderInstance.UnitStatusButton then   pHeaderInstance.UnitStatusButton:RegisterCallback(  Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "status", iUnitGroup, instance ) end ) end

		-- fill a single group
		--for _,policy in ipairs(policies) do
		for _,minor in spairs( minors, function(t,a,b) return t[a].Name < t[b].Name; end ) do -- sort by name
		
			--FILTERS
			if (not Controls.HideNotMetMinorsCheckbox:IsSelected() or minor.HasMet) and
				(not Controls.HideNoImpactMinorsCheckbox:IsSelected() or minor.IsImpact) then
		
			local pMinorInstance:table = {}
			ContextPtr:BuildInstanceForControl( "PolicyEntryInstance", pMinorInstance, instance.ContentStack ) -- instance ID, pTable, stack
			pMinorInstance.PolicyEntryYieldLOYALTY:SetHide( not (bIsRiseFall or bIsGatheringStorm) );
			if minor.NumTokens == 0 then iNumRows = iNumRows + 1; end
			
			-- status with tooltip
			local sStatusText:string = "";
			local sStatusToolTip:string = "";
			if minor.Influence > 0 then sStatusText = "[ICON_CheckSuccess]"; sStatusToolTip = Locale.Lookup("LOC_ENVOY_NAME");           end
			if minor.IsSuzerained  then sStatusText = "[ICON_Checkmark]";    sStatusToolTip = Locale.Lookup("LOC_CITY_STATES_SUZERAIN"); end
			pMinorInstance.PolicyEntryStatus:SetText(sStatusText);
			pMinorInstance.PolicyEntryStatus:SetToolTipString(sStatusToolTip);     
			
			-- name with description
			local sMinorName:string = minor.Name;
			if minor.HasMet and minor.NumTokens == 0 then sMinorName = "[ICON_Capital]"..sMinorName; end
			if     minor.NumTokens > 0 then sMinorName = sMinorName.." "..tostring(minor.Influence);
			elseif minor.Influence > 0 then sMinorName = sMinorName.." [COLOR_White]"..tostring(minor.Influence).."[ENDCOLOR] [ICON_Envoy]"; end
			TruncateString(pMinorInstance.PolicyEntryName, 278, sMinorName); -- [ICON_Checkmark] [ICON_CheckSuccess] [ICON_CheckFail] [ICON_CheckmarkBlue]
			pMinorInstance.PolicyEntryName:SetToolTipString(minor.Description);
			
			-- impact with modifiers
			local sMinorImpact:string = ( minor.Impact == "" and "[ICON_CheckmarkBlue]" ) or minor.Impact;
			if minor.UnknownEffect then sMinorImpact = sMinorImpact.." [COLOR_Red]!"; end
			-- this plugin shows actual impact as an additional info; only for influence bonuses
			if minor.NumTokens > 0 then
				local tActualYields:table = {};
				for yield,value in pairs(minor.Yields) do tActualYields[yield] = value * minor.Influence; end
				local sActualInfo:string = RMA.YieldTableGetInfo(tActualYields);
				if sActualInfo ~= "" then sMinorImpact = sMinorImpact.."  ("..sActualInfo..")"; end
			end
			TruncateString(pMinorInstance.PolicyEntryImpact, 218, sMinorImpact);
			if bOptionModifiers then pMinorInstance.PolicyEntryImpact:SetToolTipString(minor.CivType.." / "..minor.LeaderType.."[NEWLINE]"..minor.Trait..TOOLTIP_SEP_NEWLINE..minor.ImpactToolTip); end
			
			-- fill out yields
			for yield,value in pairs(minor.Yields) do
				if value ~= 0 then pMinorInstance["PolicyEntryYield"..yield]:SetText(toPlusMinusNoneString(value)); end
			end
			
			end -- FILTERS
			
		end
		
		instance.RowHeaderLabel:SetText( Locale.Lookup("LOC_HUD_REPORTS_TOTALS").." "..tostring(iNumRows) );
		
		-- no footer
		SetGroupCollapsePadding(instance, 0);
		RealizeGroup( instance );
	end
	
	-- finishing
	Controls.Stack:CalculateSize();
	Controls.Scroll:CalculateSize();

	Controls.CollapseAll:SetHide( false );
	Controls.BottomYieldTotals:SetHide( true );
	Controls.BottomResourceTotals:SetHide( true );
	Controls.BottomPoliciesFilters:SetHide( true );
	Controls.BottomMinorsFilters:SetHide( false ); -- ViewMinorPage
	Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - (Controls.BottomMinorsFilters:GetSizeY() + SIZE_HEIGHT_PADDING_BOTTOM_ADJUST ) );	
	
	-- Remember this tab when report is next opened: ARISTOS
	m_kCurrentTab = 8;
end

-- ===========================================================================
-- CHECKBOXES
-- ===========================================================================

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
function InitializeMinor()
	-- Minors Filters
	Controls.HideNotMetMinorsCheckbox:RegisterCallback( Mouse.eLClick, OnToggleNotMetMinors );
	Controls.HideNotMetMinorsCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.HideNotMetMinorsCheckbox:SetSelected( true );
	Controls.HideNoImpactMinorsCheckbox:RegisterCallback( Mouse.eLClick, OnToggleNoImpactMinors );
	Controls.HideNoImpactMinorsCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.HideNoImpactMinorsCheckbox:SetSelected( false );
end

print("BRS: Loaded file BRSPage_Minor.lua");
