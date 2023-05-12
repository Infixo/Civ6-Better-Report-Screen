-- ===========================================================================
-- Better Report Screen - page Gossip
-- Author: Infixo
-- 2023-05-10: Created
-- ===========================================================================

--include("LeaderIcon"); -- Used by Gossip page

local GOSSIP_GROUP_TYPES: table = {
	"ALL",
	"BARBARIAN",
	"DIPLOMACY",
	"CITY",
	"CULTURE",
	"DISCOVER",
	"ESPIONAGE",
	"GREATPERSON",
	"MILITARY",
	"RELIGION",
	"SCIENCE",
	"SETTLEMENT",
	"VICTORY"
};

--Gossip filtering
local m_kGossipInstances:table = {};
local m_groupFilter:number = 1;	-- (1) Indicates Unfiltered by this criteria (Group Type Index)
local m_leaderFilter:number = -1; -- (-1) Indicates Unfilitered by this criteria (PlayerID)

function UpdateGossipData()
	print("UpdateGossipData");
	-- no data reading here, it reads all in ViewGossipPage
	g_DirtyFlag.GOSSIP = false;
end

--	Tab Callback
function ViewGossipPage()
	print("ViewGossipPage");
	
	if g_DirtyFlag.GOSSIP then UpdateGossipData(); end
	
	Timer1Start();
	ResetTabForNewPageContent();
	m_kGossipInstances = {};

	local playerID:number = Game.GetLocalPlayer();
	if playerID == -1 then
		--Observer. No report.
		return;
	end

	--Get our Diplomacy
	local pLocalPlayerDiplomacy:table = Players[playerID]:GetDiplomacy();
	if pLocalPlayerDiplomacy == nil then
		--This is a significant error
		UI.DataError("Diplomacy is nil! Cannot display Gossip Report");
		return;
	end

	--We use simple instances to mask generic content. So we need to ensure there are no
	--leftover children from the last instance.
	local instance:table = m_simpleIM:GetInstance();	
	instance.Top:DestroyAllChildren();

	local uiFilterInstance:table = {};
	ContextPtr:BuildInstanceForControl("GossipFilterInstance", uiFilterInstance, instance.Top);

	--Generate our filters for each group
	for i, type in pairs(GOSSIP_GROUP_TYPES) do
		local uiFilter:table = {};
		uiFilterInstance.GroupFilter:BuildEntry("InstanceOne", uiFilter);
		uiFilter.Button:SetText(Locale.Lookup("LOC_HUD_REPORTS_FILTER_" .. type));
		uiFilter.Button:SetVoid1(i);
		--uiFilter.Button:SetSizeX(252); -- moved to xml
	end
	uiFilterInstance.GroupFilter:RegisterSelectionCallback(function(i:number)
		uiFilterInstance.GroupFilter:GetButton():SetText(Locale.Lookup("LOC_HUD_REPORTS_FILTER_" .. GOSSIP_GROUP_TYPES[i]));
		m_groupFilter = i;
		FilterGossip();
	end);
	uiFilterInstance.GroupFilter:GetButton():SetText(Locale.Lookup("LOC_HUD_REPORTS_FILTER_ALL"));


	local pHeaderInstance:table = {}
	ContextPtr:BuildInstanceForControl( "GossipHeaderInstance", pHeaderInstance, instance.Top );
	
	local kGossipLog:table = {};	

	--Make our 'All' Filter for players
	local uiAllFilter:table = {};
	uiFilterInstance.PlayerFilter:BuildEntry("InstanceOne", uiAllFilter);
	uiAllFilter.LeaderIcon:SetIcon("ICON_LEADER_ALL");
	--uiAllFilter.LeaderIcon.Portrait:SetIcon("ICON_LEADER_ALL");
	--uiAllFilter.LeaderIcon.Portrait:SetHide(false);
	--uiAllFilter.LeaderIcon.TeamRibbon:SetHide(true);
	uiAllFilter.Button:SetText(Locale.Lookup("LOC_HUD_REPORTS_PLAYER_FILTER_ALL"));
	uiAllFilter.Button:SetVoid1(-1);
	--uiAllFilter.Button:SetSizeX(252); -- moved to xml
	
	--Timer1Tick("ViewGossipPage: filters");

	--Populate with all of our Gossip and build Player Filter
	for targetID, kPlayer in pairs(Players) do
		--If we are not ourselves, are a major civ, and we have met these people
		if targetID ~= playerID and kPlayer:IsMajor() and pLocalPlayerDiplomacy:HasMet(targetID) then
			--Append their gossip
			local bHasGossip:boolean = false;
			local kAppendTable:table = Game.GetGossipManager():GetRecentVisibleGossipStrings(0, playerID, targetID);
			for _, entry in pairs(kAppendTable) do
				table.insert(kGossipLog, entry);
				bHasGossip = true;
			end

			--If we had gossip, add them as a filter
			if bHasGossip then
				local uiFilter:table = {};
				uiFilterInstance.PlayerFilter:BuildEntry("InstanceOne", uiFilter);

				local leaderName:string = PlayerConfigurations[targetID]:GetLeaderTypeName();
				local iconName:string = "ICON_" .. leaderName;
				--Build and update
				--local filterLeaderIcon:table = LeaderIcon:AttachInstance(uiFilter.LeaderIcon);
				--filterLeaderIcon:UpdateIcon(iconName, targetID, true);
				uiFilter.LeaderIcon:SetIcon(iconName);
				uiFilter.Button:SetText(Locale.Lookup(PlayerConfigurations[targetID]:GetLeaderName()));
				uiFilter.Button:SetVoid1(targetID);
				--uiFilter.Button:SetSizeX(252); -- moved to xml
			end
		end
	end

	uiFilterInstance.PlayerFilter:RegisterSelectionCallback(function(i:number)
		if i == -1 then
			uiFilterInstance.LeaderIcon:SetIcon("ICON_LEADER_ALL");
			--uiFilterInstance.LeaderIcon.Portrait:SetIcon("ICON_LEADER_ALL");
			--uiFilterInstance.LeaderIcon.Portrait:SetHide(false);
			--uiFilterInstance.LeaderIcon.TeamRibbon:SetHide(true);
			--uiFilterInstance.LeaderIcon.Relationship:SetHide(true);
			uiFilterInstance.PlayerFilter:GetButton():SetText(Locale.Lookup("LOC_HUD_REPORTS_PLAYER_FILTER_ALL"));
		else
			local leaderName:string = PlayerConfigurations[i]:GetLeaderTypeName();
			local iconName:string = "ICON_" .. leaderName;
			--Build and update
			--local filterLeaderIcon:table = LeaderIcon:AttachInstance(uiFilterInstance.LeaderIcon);
			--filterLeaderIcon:UpdateIcon(iconName, i, true);
			uiFilterInstance.LeaderIcon:SetIcon(iconName);
			uiFilterInstance.PlayerFilter:GetButton():SetText(Locale.Lookup(PlayerConfigurations[i]:GetLeaderName()));
		end
		m_leaderFilter = i;
		FilterGossip();
	end);
	
	--Timer1Tick("ViewGossipPage: fetch all");

	uiFilterInstance.LeaderIcon:SetIcon("ICON_LEADER_ALL");
	--uiFilterInstance.LeaderIcon.Portrait:SetIcon("ICON_LEADER_ALL");
	--uiFilterInstance.LeaderIcon.Portrait:SetHide(false);
	--uiFilterInstance.LeaderIcon.TeamRibbon:SetHide(true);
	--uiFilterInstance.LeaderIcon.Relationship:SetHide(true);
	uiFilterInstance.PlayerFilter:GetButton():SetText(Locale.Lookup("LOC_HUD_REPORTS_PLAYER_FILTER_ALL"));

	table.sort(kGossipLog, function(a, b) return a[2] > b[2]; end);
	--Timer2Start();
	for _, kGossipEntry in pairs(kGossipLog) do
		local leaderName:string = PlayerConfigurations[kGossipEntry[4]]:GetLeaderTypeName();
		local iconName:string = "ICON_" .. leaderName;
		local pGossipInstance:table = {}
		ContextPtr:BuildInstanceForControl( "GossipEntryInstance", pGossipInstance, instance.Top ) ;

		local kGossipData:table = GameInfo.Gossips[kGossipEntry[3]];
		
		--Build and update
		--local gossipLeaderIcon:table = LeaderIcon:AttachInstance(pGossipInstance.Leader);
		--gossipLeaderIcon:UpdateIcon(iconName, kGossipEntry[4], true);
		pGossipInstance.LeaderIcon:SetIcon(iconName);
		pGossipInstance.LeaderName:SetText(LL(PlayerConfigurations[kGossipEntry[4]]:GetLeaderName()));
		
		pGossipInstance.Date:SetText(kGossipEntry[2]);
		pGossipInstance.Icon:SetIcon("ICON_GOSSIP_" .. kGossipData.GroupType);
		pGossipInstance.Description:SetText(kGossipEntry[1]);

		--Build our references
		table.insert(m_kGossipInstances, {instance = pGossipInstance, leaderID = kGossipEntry[4], gossipType = kGossipData.GroupType});
	end
	--Timer2Tick("ViewGossipPage: display only");
	--Timer1Tick("ViewGossipPage: display");

	--Refresh our sizes
	uiFilterInstance.GroupFilter:CalculateInternals();
	uiFilterInstance.PlayerFilter:CalculateInternals();

	Controls.Stack:CalculateSize();
	Controls.Scroll:CalculateSize();

	Controls.CollapseAll:SetHide(true);
	Controls.BottomYieldTotals:SetHide( true );
	Controls.BottomResourceTotals:SetHide( true );
	Controls.BottomPoliciesFilters:SetHide( true );
	Controls.BottomMinorsFilters:SetHide( true );
	Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - SIZE_HEIGHT_PADDING_BOTTOM_ADJUST );
	-- Remember this tab when report is next opened: ARISTOS
	m_kCurrentTab = 4;
	Timer1Tick("ViewGossipPage");
end

--	Filter Callbacks
function FilterGossip()
	local gossipGroupType:string = GOSSIP_GROUP_TYPES[m_groupFilter];
	for _, entry in pairs(m_kGossipInstances) do
		local bShouldHide:boolean = false;

		--Leader matches, or all?
		if m_leaderFilter ~= -1 and entry.leaderID ~= m_leaderFilter then
			bShouldHide = true;
		end

		--Group type, or all?
		if m_groupFilter ~= 1 and entry.gossipType ~= gossipGroupType then
			bShouldHide = true;
		end

		entry.instance.Top:SetHide(bShouldHide);
	end
end

print("BRS: Loaded file BRSPage_Gossip.lua");
