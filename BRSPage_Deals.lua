-- ===========================================================================
-- Better Report Screen - page Deals
-- Author: Infixo
-- 2023-05-10: Created
-- ===========================================================================

m_kCurrentDeals = nil; -- global for debug purposes

function GetDataDeals()
	print("GetDataDeals");
	
	local playerID	:number = Game.GetLocalPlayer();
	if playerID == PlayerTypes.NONE or playerID == PlayerTypes.OBSERVER then
		UI.DataError("Unable to get valid playerID for report screen.");
		return;
	end
	
	local kCurrentDeals: table = {};
	local kPlayers: table = PlayerManager.GetAliveMajors();
	local iTotal: number = 0;

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
	
	for j, pDeal in spairs( m_kCurrentDeals, function( t, a, b ) return t[b].EndTurn > t[a].EndTurn end ) do
		--print("deal", pDeal.EndTurn, Game.GetCurrentGameTurn(), pDeal.EndTurn-Game.GetCurrentGameTurn());
		local iNumTurns:number = pDeal.EndTurn - Game.GetCurrentGameTurn();
		--local turns = "turns"
		--if ending == 1 then turns = "turn" end

		local instance : table = NewCollapsibleGroupInstance()

		instance.RowHeaderButton:SetText( Locale.Lookup("LOC_HUD_REPORTS_TRADE_DEAL_WITH")..pDeal.WithCivilization );
		instance.RowHeaderLabel:SetText( tostring(iNumTurns).." "..Locale.Lookup("LOC_HUD_REPORTS_TURNS_UNTIL_COMPLETED", iNumTurns).." ("..tostring(pDeal.EndTurn)..")" );
		instance.RowHeaderLabel:SetHide( false );
		instance.AmenitiesContainer:SetHide(true);
        instance.IndustryContainer:SetHide(true); -- 2021-05-21
        instance.MonopolyContainer:SetHide(true); -- 2021-05-21

		local dealHeaderInstance : table = {}
		ContextPtr:BuildInstanceForControl( "DealsHeader", dealHeaderInstance, instance.ContentStack )

		local iSlots = #pDeal.Sending

		if iSlots < #pDeal.Receiving then iSlots = #pDeal.Receiving end

		for i = 1, iSlots do
			local dealInstance : table = {}
			ContextPtr:BuildInstanceForControl( "DealsInstance", dealInstance, instance.ContentStack )
			table.insert( instance.Children, dealInstance )
		end

		for i, pDealItem in pairs( pDeal.Sending ) do
			if pDealItem.Icon then
				instance.Children[i].Outgoing:SetText( pDealItem.Icon .. " " .. pDealItem.Name )
			else
				instance.Children[i].Outgoing:SetText( pDealItem.Name )
			end
		end

		for i, pDealItem in pairs( pDeal.Receiving ) do
			if pDealItem.Icon then
				instance.Children[i].Incoming:SetText( pDealItem.Icon .. " " .. pDealItem.Name )
			else
				instance.Children[i].Incoming:SetText( pDealItem.Name )
			end
		end
	
		local pFooterInstance:table = {}
		ContextPtr:BuildInstanceForControl( "DealsFooterInstance", pFooterInstance, instance.ContentStack )
		pFooterInstance.Outgoing:SetText( Locale.Lookup("LOC_HUD_REPORTS_TOTALS")..#pDeal.Sending )
		pFooterInstance.Incoming:SetText( Locale.Lookup("LOC_HUD_REPORTS_TOTALS")..#pDeal.Receiving )
	
		SetGroupCollapsePadding( instance, pFooterInstance.Top:GetSizeY() )
		RealizeGroup( instance );
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
