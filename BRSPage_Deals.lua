-- ===========================================================================
-- Better Report Screen - page Deals
-- Author: Infixo
-- 2023-05-10: Created
-- 2023-05-22: New page design (#6)
-- ===========================================================================

m_kCurrentDeals = nil; -- global for debug purposes

function GetDataDeals()
	print("GetDataDeals");
	
	local playerID: number = Game.GetLocalPlayer();
	if playerID == PlayerTypes.NONE or playerID == PlayerTypes.OBSERVER then
		UI.DataError("Unable to get valid playerID for report screen.");
		return;
	end
	
	local kCurrentDeals: table = {};
	local kPlayers: table = PlayerManager.GetAliveMajors();
	local playerDiplomacy: table = Players[playerID]:GetDiplomacy();

	for _, pOtherPlayer in ipairs(kPlayers) do
		local otherID: number = pOtherPlayer:GetID();
		if otherID ~= playerID then
			local pDeals: table = DealManager.GetPlayerDeals(playerID, otherID);
			
			local dataPlayer: table = {
				WithCivilization = LL( PlayerConfigurations[otherID]:GetCivilizationShortDescription() ),
				Deals = {},
				EndTurn = 0,
				GoldBalance = 0,
			};
			if playerDiplomacy:HasMet(otherID) then table.insert(kCurrentDeals, dataPlayer); end
			
			if pDeals ~= nil then
				for _,pDeal in ipairs(pDeals) do
				
					local dataDeal: table = {
						Enacted = 0, -- start turn
						EndTurn = 0,
						Incoming = "",
						Outgoing = "",
					};
					table.insert(dataPlayer.Deals, dataDeal);
					
					local goldBalance: number, incoming: string, outgoing: string = 0, "", "";
					local otherPlayerID: number = otherID;

					-- Code from CQUI-Lite, diplomacydealview.lua
					for item in pDeal:Items() do
						local itemType: number = item:GetType();
						if itemType == DealItemTypes.GOLD then
							-- calculate balance, use GetAmount
							if item:GetFromPlayerID() == otherPlayerID then -- we gain
								incoming = incoming..", "..string.format("[ICON_Gold][COLOR_Gold]%d[ENDCOLOR]", item:GetAmount());     
								dataPlayer.GoldBalance = dataPlayer.GoldBalance + item:GetAmount();
							else -- we lose
								outgoing = outgoing..", "..string.format("[ICON_Gold][COLOR_Gold]%d[ENDCOLOR]", item:GetAmount());
								dataPlayer.GoldBalance = dataPlayer.GoldBalance - item:GetAmount();
							end 
						elseif itemType == DealItemTypes.RESOURCES then
							-- use GetValueTypeID and GetValueTypeNameID and GetAmount
							local str: string = string.format("[ICON_%s]%s", item:GetValueTypeID(), Locale.Lookup(item:GetValueTypeNameID()));
							if item:GetFromPlayerID() == otherPlayerID then incoming = incoming..", "..str;     -- we gain
							else                                            outgoing = outgoing..", "..str; end -- we lose
						elseif itemType == DealItemTypes.AGREEMENTS then
							-- use GetSubTypeID and GetSubTypeNameID
							local str: string = Locale.Lookup(item:GetSubTypeNameID());
							if item:GetFromPlayerID() == otherPlayerID then incoming = incoming..", "..str;     -- we gain
							else                                            outgoing = outgoing..", "..str; end -- we lose
						else
							print("BRS: GetDataDeals(), WARNING unsupported deal item type: ", GameInfo.Types[itemType].Type);
						end
						dataDeal.Enacted = item:GetEnactedTurn();
						dataDeal.EndTurn = item:GetEndTurn();
					end
					outgoing = string.sub(outgoing, 3); -- if nothing was added then it is still "" and this returns ""
					incoming = string.sub(incoming, 3);
					
					dataDeal.Incoming = incoming;
					dataDeal.Outgoing = outgoing;
				end -- for deals
				
				-- Sort by the closest to finish and find out when
				if #dataPlayer.Deals > 0 then
					table.sort(dataPlayer.Deals, function(a,b) return b.EndTurn > a.EndTurn; end);
					dataPlayer.EndTurn = dataPlayer.Deals[1].EndTurn; -- first one should be the closest one
				end
				
			end -- deals ~= nil
		end -- if not us
	end -- for all alive players
	return kCurrentDeals;
end

function UpdateDealsData()
	print("UpdateDealsData");
	Timer1Start();
	m_kCurrentDeals = GetDataDeals();
	Timer1Tick("UpdateDealsData");
	g_DirtyFlag.DEALS = false;
end

function ViewDealsPage()
	print("ViewDealsPage");
	
	if g_DirtyFlag.DEALS then UpdateDealsData(); end

	ResetTabForNewPageContent();
	
	for _,playerDeals in spairs( m_kCurrentDeals, function( t, a, b ) return t[b].EndTurn > t[a].EndTurn end ) do
	
		local currentTurn: number = Game.GetCurrentGameTurn();
		local iNumTurns:number = playerDeals.EndTurn - currentTurn;

		local instance: table = NewCollapsibleGroupInstance();

		instance.RowHeaderButton:SetText(string.format("%s (%d)", playerDeals.WithCivilization, #playerDeals.Deals));
		if playerDeals.GoldBalance ~= 0 then
			instance.RowHeaderButton:SetText(string.format("%s  [ICON_Gold][COLOR_Gold]%+d[ENDCOLOR]", instance.RowHeaderButton:GetText(), playerDeals.GoldBalance));
		end
		instance.RowHeaderLabel:SetText( playerDeals.EndTurn > 0 and tostring(iNumTurns).." "..Locale.Lookup("LOC_HUD_REPORTS_TURNS_UNTIL_COMPLETED", iNumTurns).." ("..tostring(playerDeals.EndTurn)..")" or "");
		instance.RowHeaderLabel:SetHide( false );
		instance.AmenitiesContainer:SetHide(true);
        instance.IndustryContainer:SetHide(true); -- 2021-05-21
        instance.MonopolyContainer:SetHide(true); -- 2021-05-21

		local dealHeaderInstance : table = {}
		ContextPtr:BuildInstanceForControl( "DealsHeader", dealHeaderInstance, instance.ContentStack )

		for _,deal in ipairs(playerDeals.Deals) do
			local dealInstance: table = {}
			ContextPtr:BuildInstanceForControl( "DealsInstance", dealInstance, instance.ContentStack )
			table.insert( instance.Children, dealInstance );
			-- Display single deal info
			dealInstance.Outgoing:SetText(deal.Outgoing);
			dealInstance.Incoming:SetText(deal.Incoming);
			dealInstance.Enacted:SetText(deal.Enacted);
			dealInstance.Turns:SetText(deal.EndTurn-currentTurn);
		end
	
		SetGroupCollapsePadding(instance, 0);
		RealizeGroup(instance);
	end

	Controls.Stack:CalculateSize();
	Controls.Scroll:CalculateSize();

	Controls.CollapseAll:SetHide( false );
	Controls.BottomYieldTotals:SetHide( true );
	Controls.BottomResourceTotals:SetHide( true );
	Controls.BottomPoliciesFilters:SetHide( true );
	Controls.BottomMinorsFilters:SetHide( true );
	Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - SIZE_HEIGHT_PADDING_BOTTOM_ADJUST);
	-- Remember this tab when report is next opened: ARISTOS
	m_kCurrentTab = 5;
end

print("BRS: Loaded file BRSPage_Deals.lua");
