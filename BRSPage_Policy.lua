-- ===========================================================================
-- Better Report Screen - page Policy
-- Author: Infixo
-- 2023-05-10: Created
-- ===========================================================================

m_kPolicyData = nil; -- global for debug purposes

local tPolicyOrder:table = {
	SLOT_MILITARY = 1,
	SLOT_ECONOMIC = 2,
	SLOT_DIPLOMATIC = 3,
	SLOT_GREAT_PERSON = 4,
	SLOT_WILDCARD = 5,
	SLOT_DARKAGE = 6,
	SLOT_PANTHEON = 7,
	SLOT_FOLLOWER = 8,
};

local tPolicyGroupNames:table = {};

function InitializePolicyData()
	-- Compatbility tweak for mods adding new slot types (e.g. Rule with Faith)
	for row in GameInfo.GovernmentSlots() do
		if tPolicyOrder[row.GovernmentSlotType] == nil and row.GovernmentSlotType ~= "SLOT_WILDCARD" then
			tPolicyOrder[row.GovernmentSlotType] = table.count(tPolicyOrder) + 1;
		end
	end
	-- init group names
	for slot,_ in pairs(tPolicyOrder) do
		tPolicyGroupNames[ slot ] = Locale.Lookup( string.gsub(slot, "SLOT_", "LOC_GOVT_POLICY_TYPE_") );
	end
	-- exceptions
	tPolicyGroupNames.SLOT_GREAT_PERSON = Locale.Lookup("LOC_PEDIA_GOVERNMENTS_PAGEGROUP_GREATPEOPLE_POLICIES_NAME");
	tPolicyGroupNames.SLOT_PANTHEON     = Locale.Lookup("LOC_PEDIA_RELIGIONS_PAGEGROUP_PANTHEON_BELIEFS_NAME");
	tPolicyGroupNames.SLOT_FOLLOWER     = Locale.Lookup("LOC_PEDIA_RELIGIONS_PAGEGROUP_FOLLOWER_BELIEFS_NAME");
	-- Rise & Fall
	if not (bIsRiseFall or bIsGatheringStorm) then
		--tPolicyOrder.SLOT_WILDCARD = nil; -- 2019-01-26: Nubia Scenario uses SLOT_WILDCARD
		tPolicyOrder.SLOT_DARKAGE = nil;
	end
	--print("*** POLICY ORDER ***"); dshowtable(tPolicyOrder);
	--print("*** POLICY GROUP NAMES ***"); dshowtable(tPolicyGroupNames);
end


function UpdatePolicyData()
	print("UpdatePolicyData");
	Timer1Start();
	m_kPolicyData = {}; for slot,_ in pairs(tPolicyOrder) do m_kPolicyData[slot] = {}; end -- reset all data
	local ePlayerID:number = Game.GetLocalPlayer();
	local pPlayer:table = Players[ePlayerID];
	if not pPlayer then return; end -- assert
	local pPlayerCulture:table = pPlayer:GetCulture();
	-- find out which polices are slotted now
	local tSlottedPolicies:table = {};
	for i = 0, pPlayerCulture:GetNumPolicySlots()-1 do
		if pPlayerCulture:GetSlotPolicy(i) ~= -1 then tSlottedPolicies[ pPlayerCulture:GetSlotPolicy(i) ] = true; end
	end
	--print("...Slotted policies"); dshowtable(tSlottedPolicies);
	-- iterate through all policies
	for policy in GameInfo.Policies() do
		local policyData:table = {
			Index = policy.Index,
			Name = Locale.Lookup(policy.Name),
			Description = Locale.Lookup(policy.Description),
			--Yields from modifiers
			-- Status TODO from Player:GetCulture?
			IsActive = (pPlayerCulture:IsPolicyUnlocked(policy.Index) and not pPlayerCulture:IsPolicyObsolete(policy.Index)),
			IsSlotted = ((tSlottedPolicies[ policy.Index ] and true) or false),
		};
		--print("Policy:", policy.Index, policy.PolicyType, policy.GovernmentSlotType, "active/slotted", policyData.IsActive, policyData.IsSlotted);
		-- dshowtable(policyData); -- !!!BUG HERE with Aesthetics CTD!!! Also with CRAFTSMEN, could be others - DON'T USE
		local sSlotType:string = policy.GovernmentSlotType;
		if sSlotType == "SLOT_WILDCARD" then --sSlotType = ((policy.RequiresGovernmentUnlock and "SLOT_WILDCARD") or "SLOT_DARKAGE"); end
			-- 2019-01-26: Better check for Dark Age policies
			if GameInfo.Policies_XP1 ~= nil and GameInfo.Policies_XP1[policy.PolicyType] ~= nil then sSlotType = "SLOT_DARKAGE"; end
		end
		--print("...inserting policy", policyData.Name, "into", sSlotType);
		table.insert(m_kPolicyData[sSlotType], policyData);
		-- policy impact from modifiers
		policyData.Impact, policyData.Yields, policyData.ImpactToolTip, policyData.UnknownEffect = RMA.CalculateModifierEffect("Policy", policy.PolicyType, ePlayerID, nil);
		policyData.IsImpact = false; -- for toggling options
		for _,value in pairs(policyData.Yields) do if value ~= 0 then policyData.IsImpact = true; break; end end
	end
	-- iterate through all beliefs
	for belief in GameInfo.Beliefs() do
		if belief.BeliefClassType == "BELIEF_CLASS_PANTHEON" or belief.BeliefClassType == "BELIEF_CLASS_FOLLOWER" then
			local policyData:table = {
				Index = belief.Index,
				Name = Locale.Lookup(belief.Name),
				Description = Locale.Lookup(belief.Description),
				--Yields from modifiers
				-- Status TODO from Player:GetCulture?
				IsActive = true, -- not used by pantheons
				IsSlotted = ( pPlayer:GetReligion():GetPantheon() == belief.Index ),
			};
			local sSlotType:string = string.gsub(belief.BeliefClassType, "BELIEF_CLASS_", "SLOT_");
			--print("...inserting belief", policyData.Name, "into", sSlotType);
			table.insert(m_kPolicyData[sSlotType], policyData);
			-- belief impact from modifiers
			policyData.Impact, policyData.Yields, policyData.ImpactToolTip, policyData.UnknownEffect = RMA.CalculateModifierEffect("Belief", belief.BeliefType, ePlayerID, nil);
			policyData.IsImpact = false; -- for toggling options
			for _,value in pairs(policyData.Yields) do if value ~= 0 then policyData.IsImpact = true; break; end end
		end -- pantheons
	end -- all beliefs
	Timer1Tick("UpdatePolicyData");
	--for policyGroup,policies in pairs(m_kPolicyData) do print(policyGroup, table.count(policies)); end
	g_DirtyFlag.POLICY = false;
end


function ViewPolicyPage()
	print("ViewPolicyPage");
	
	if g_DirtyFlag.POLICY then UpdatePolicyData(); end
	
	ResetTabForNewPageContent();

	-- fill
	--for iUnitGroup, kUnitGroup in spairs( m_kUnitDataReport, function( t, a, b ) return t[b].ID > t[a].ID end ) do
	--for policyGroup,policies in pairs(m_kPolicyData) do
	for policyGroup,policies in spairs( m_kPolicyData, function(t,a,b) return tPolicyOrder[a] < tPolicyOrder[b]; end ) do -- simple sort by group code name
		--print("PolicyGroup:", policyGroup);
		local instance : table = NewCollapsibleGroupInstance()
		
		instance.RowHeaderButton:SetText( tPolicyGroupNames[policyGroup] );
		instance.RowHeaderLabel:SetHide( false );
		instance.AmenitiesContainer:SetHide(true);
        instance.IndustryContainer:SetHide(true); -- 2021-05-21
        instance.MonopolyContainer:SetHide(true); -- 2021-05-21
		
		local pHeaderInstance:table = {}
		ContextPtr:BuildInstanceForControl( "PolicyHeaderInstance", pHeaderInstance, instance.ContentStack ) -- instance ID, pTable, stack
		if policyGroup == "SLOT_PANTHEON" or policyGroup == "SLOT_FOLLOWER" then pHeaderInstance.PolicyHeaderLabelName:SetText( Locale.Lookup("LOC_BELIEF_NAME") ); end
		local iNumRows:number = 0;
		pHeaderInstance.PolicyHeaderButtonLOYALTY:SetHide( not (bIsRiseFall or bIsGatheringStorm) );
		
		-- set sorting callbacks
		--if pHeaderInstance.UnitTypeButton then     pHeaderInstance.UnitTypeButton:RegisterCallback(    Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "type", iUnitGroup, instance ) end ) end
		--if pHeaderInstance.UnitNameButton then     pHeaderInstance.UnitNameButton:RegisterCallback(    Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "name", iUnitGroup, instance ) end ) end
		--if pHeaderInstance.UnitStatusButton then   pHeaderInstance.UnitStatusButton:RegisterCallback(  Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "status", iUnitGroup, instance ) end ) end

		-- fill a single group
		--for _,policy in ipairs(policies) do
		for _,policy in spairs( policies, function(t,a,b) return t[a].Name < t[b].Name; end ) do -- sort by name
			--print("Policy:", policy.Name);
			--dshowtable(policy);
			--FILTERS
			if (not Controls.HideInactivePoliciesCheckbox:IsSelected() or policy.IsActive) and
				(not Controls.HideNoImpactPoliciesCheckbox:IsSelected() or policy.IsImpact) then
		
			local pPolicyInstance:table = {}
			--table.insert( instance.Children, unitInstance )
			
			ContextPtr:BuildInstanceForControl( "PolicyEntryInstance", pPolicyInstance, instance.ContentStack ) -- instance ID, pTable, stack
			pPolicyInstance.PolicyEntryYieldLOYALTY:SetHide( not (bIsRiseFall or bIsGatheringStorm) );
			iNumRows = iNumRows + 1;
			
			--common_unit_fields( unit, unitInstance ) -- fill a single entry
			-- status with tooltip
			local sStatusText:string;
			local sStatusToolTip:string = "Id "..tostring(policy.Index);
			if policy.IsActive then sStatusText = "[ICON_CheckSuccess]"; sStatusToolTip = sStatusToolTip.." Active policy";
			else                    sStatusText = "[ICON_CheckFail]";    sStatusToolTip = sStatusToolTip.." Inactive policy (obsolete or not yet unlocked)"; end
			--print("...status", sStatusText);
			pPolicyInstance.PolicyEntryStatus:SetText(sStatusText);
			--pPolicyInstance.PolicyEntryStatus:SetToolTipString(sStatusToolTip);
			
			-- name with description
			local sPolicyName:string = policy.Name;
			if policy.IsSlotted then sPolicyName = "[ICON_Checkmark]"..sPolicyName; end
			--print("...description", policy.Description);
			TruncateString(pPolicyInstance.PolicyEntryName, 278, sPolicyName); -- [ICON_Checkmark] [ICON_CheckSuccess] [ICON_CheckFail] [ICON_CheckmarkBlue]
			pPolicyInstance.PolicyEntryName:SetToolTipString(policy.Description);
			
			-- impact with modifiers
			local sPolicyImpact:string = ( policy.Impact == "" and "[ICON_CheckmarkBlue]" ) or policy.Impact;
			if policy.UnknownEffect then sPolicyImpact = sPolicyImpact.." [COLOR_Red]!"; end
			--print("...impact", sPolicyImpact);
			TruncateString(pPolicyInstance.PolicyEntryImpact, 218, sPolicyImpact);
			--print("...tooltip", sStatusToolTip, policy.ImpactToolTip);
			--print("...tooltip", sStatusToolTip..TOOLTIP_SEP_NEWLINE..policy.ImpactToolTip);
			if bOptionModifiers then pPolicyInstance.PolicyEntryImpact:SetToolTipString(sStatusToolTip..TOOLTIP_SEP_NEWLINE..policy.ImpactToolTip); end
			--print("Yields:");
			-- fill out yields
			for yield,value in pairs(policy.Yields) do
				--print("...yield,value", yield, value);
				if value ~= 0 then pPolicyInstance["PolicyEntryYield"..yield]:SetText(toPlusMinusNoneString(value)); end
			end
			
			end -- FILTERS
			
		end
		
		instance.RowHeaderLabel:SetText( Locale.Lookup("LOC_HUD_REPORTS_TOTALS").." "..tostring(iNumRows) );
		
		-- no footer
		SetGroupCollapsePadding(instance, 0 );
		RealizeGroup( instance );
	end
	
	-- finishing
	Controls.Stack:CalculateSize();
	Controls.Scroll:CalculateSize();

	Controls.CollapseAll:SetHide( false );
	Controls.BottomYieldTotals:SetHide( true );
	Controls.BottomResourceTotals:SetHide( true );
	Controls.BottomPoliciesFilters:SetHide( false ); -- ViewPolicyPage
	Controls.BottomMinorsFilters:SetHide( true );
	Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - (Controls.BottomPoliciesFilters:GetSizeY() + SIZE_HEIGHT_PADDING_BOTTOM_ADJUST ) );	
	-- Remember this tab when report is next opened: ARISTOS
	m_kCurrentTab = 7;
end

-- ===========================================================================
-- CHECKBOXES
-- ===========================================================================

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

-- ===========================================================================
function InitializePolicy()
	-- Polices Filters
	Controls.HideInactivePoliciesCheckbox:RegisterCallback( Mouse.eLClick, OnToggleInactivePolicies );
	Controls.HideInactivePoliciesCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.HideInactivePoliciesCheckbox:SetSelected( true );
	Controls.HideNoImpactPoliciesCheckbox:RegisterCallback( Mouse.eLClick, OnToggleNoImpactPolicies );
	Controls.HideNoImpactPoliciesCheckbox:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
	Controls.HideNoImpactPoliciesCheckbox:SetSelected( false );
end

print("BRS: Loaded file BRSPage_Policy.lua");
