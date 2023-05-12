-- ===========================================================================
-- Better Report Screen - page Resources
-- Author: Infixo
-- 2023-05-10: Created
-- ===========================================================================

m_kResourceData = nil; -- global for debug purposes

local m_strategicResourcesIM: table = InstanceManager:new("ResourceAmountInstance",	"Info", Controls.StrategicResources);
local m_bonusResourcesIM: table     = InstanceManager:new("ResourceAmountInstance",	"Info", Controls.BonusResources);
local m_luxuryResourcesIM: table    = InstanceManager:new("ResourceAmountInstance",	"Info", Controls.LuxuryResources);

function AddMiscResourceData(pResourceData:table, kResourceTable:table)
	if bIsGatheringStorm then return AddMiscResourceDataXP2(pResourceData, kResourceTable); end
	
	-- Resources not yet accounted for come from other gameplay bonuses
	if pResourceData then
		for row in GameInfo.Resources() do
			local internalResourceAmount:number = pResourceData:GetResourceAmount(row.Index);
			if (internalResourceAmount > 0) then
				if (kResourceTable[row.Index] ~= nil) then
					if (internalResourceAmount > kResourceTable[row.Index].Total) then
						AddResourceData(kResourceTable, row.Index, "LOC_HUD_REPORTS_MISC_RESOURCE_SOURCE", "-", internalResourceAmount - kResourceTable[row.Index].Total);
					end
				else
					AddResourceData(kResourceTable, row.Index, "LOC_HUD_REPORTS_MISC_RESOURCE_SOURCE", "-", internalResourceAmount);
				end
			end
		end
	end
	return kResourceTable;
end

function AddMiscResourceDataXP2(pResourceData:table, kResourceTable:table)
	--Append our resource entries before we continue
	kResourceTable = AppendXP2ResourceData(kResourceTable);

	-- Resources not yet accounted for come from other gameplay bonuses
	if pResourceData then
		for row in GameInfo.Resources() do
			local internalResourceAmount:number = pResourceData:GetResourceAmount(row.Index);
			local resourceUnitConsumptionPerTurn:number = -pResourceData:GetUnitResourceDemandPerTurn(row.ResourceType);
			local resourcePowerConsumptionPerTurn:number = -pResourceData:GetPowerResourceDemandPerTurn(row.ResourceType);
			local resourceAccumulationPerTurn:number = pResourceData:GetResourceAccumulationPerTurn(row.ResourceType);
			local resourceDelta:number = resourceUnitConsumptionPerTurn + resourcePowerConsumptionPerTurn + resourceAccumulationPerTurn;
			if (row.ResourceClassType == "RESOURCECLASS_STRATEGIC") then
				internalResourceAmount = resourceDelta;
			end
			if (internalResourceAmount > 0 or internalResourceAmount < 0) then
				if (kResourceTable[row.Index] ~= nil) then
					if (internalResourceAmount > kResourceTable[row.Index].Total) then
						AddResourceData(kResourceTable, row.Index, "LOC_HUD_REPORTS_MISC_RESOURCE_SOURCE", "-", internalResourceAmount - kResourceTable[row.Index].Total);
					end
				else
					AddResourceData(kResourceTable, row.Index, "LOC_HUD_REPORTS_MISC_RESOURCE_SOURCE", "-", internalResourceAmount);
				end
			end

			--Stockpile only?
			if pResourceData:GetResourceAmount(row.ResourceType) > 0 then
				AddResourceData(kResourceTable, row.Index, "", "", 0);
			end

		end
	end

	return kResourceTable;
end

function AppendXP2ResourceData(kResourceData:table)
	local playerID:number = Game.GetLocalPlayer();
	if playerID == PlayerTypes.NONE then
		UI.DataError("Unable to get valid playerID for ReportScreen_Expansion2.");
		return;
	end

	local player:table  = Players[playerID];

	local pResources:table	= player:GetResources();
	if pResources then
		for row in GameInfo.Resources() do
			local resourceHash:number = row.Hash;
			local resourceUnitCostPerTurn:number = pResources:GetUnitResourceDemandPerTurn(resourceHash);
			local resourcePowerCostPerTurn:number = pResources:GetPowerResourceDemandPerTurn(resourceHash);
			local reservedCostForProduction:number = pResources:GetReservedResourceAmount(resourceHash);
			local miscResourceTotal:number = pResources:GetResourceAmount(resourceHash);
			local importResources:number = pResources:GetResourceImportPerTurn(resourceHash);
			
			if resourceUnitCostPerTurn > 0 then
				AddResourceData(kResourceData, row.Index, "LOC_PRODUCTION_PANEL_UNITS_TOOLTIP", "-", -resourceUnitCostPerTurn);
			end

			if resourcePowerCostPerTurn > 0 then
				AddResourceData(kResourceData, row.Index, "LOC_UI_PEDIA_POWER_COST", "-", -resourcePowerCostPerTurn);
			end

			if reservedCostForProduction > 0 then
				AddResourceData(kResourceData, row.Index, "LOC_RESOURCE_REPORTS_ITEM_IN_RESERVE", "-", -reservedCostForProduction);
			end

			if kResourceData[row.Index] == nil and miscResourceTotal > 0 then
				local titleString:string = importResources > 0 and "LOC_RESOURCE_REPORTS_CITY_STATES" or "LOC_HUD_REPORTS_MISC_RESOURCE_SOURCE";
				AddResourceData(kResourceData, row.Index, titleString, "-", miscResourceTotal);
			elseif importResources > 0 then
				AddResourceData(kResourceData, row.Index, "LOC_RESOURCE_REPORTS_CITY_STATES", "-", importResources);
			end

		end
	end

	return kResourceData;
end

function AddResourceData( kResources:table, eResourceType:number, EntryString:string, ControlString:string, InAmount:number)
	local kResource :table = GameInfo.Resources[eResourceType];

	--Artifacts need to be excluded because while TECHNICALLY a resource, they do nothing to contribute in a way that is relevant to any other resource 
	--or screen. So... exclusion.
	if kResource.ResourceClassType == "RESOURCECLASS_ARTIFACT" then
		return;
	end

	local localPlayerID = Game.GetLocalPlayer();
	local localPlayer = Players[localPlayerID];
	if localPlayer then
		local pPlayerResources:table	=  localPlayer:GetResources();
		if pPlayerResources then
	
			if kResources[eResourceType] == nil then
				kResources[eResourceType] = {
					EntryList	= {},
					Icon		= "[ICON_"..kResource.ResourceType.."]",
					IsStrategic	= kResource.ResourceClassType == "RESOURCECLASS_STRATEGIC",
					IsLuxury	= GameInfo.Resources[eResourceType].ResourceClassType == "RESOURCECLASS_LUXURY",
					IsBonus		= GameInfo.Resources[eResourceType].ResourceClassType == "RESOURCECLASS_BONUS",
					Total		= 0
				};
				if bIsGatheringStorm then
					kResources[eResourceType].Maximum   = pPlayerResources:GetResourceStockpileCap(eResourceType);
					kResources[eResourceType].Stockpile = pPlayerResources:GetResourceAmount(eResourceType);
				end
			end

			if EntryString ~= "" then
				table.insert( kResources[eResourceType].EntryList, 
				{
					EntryText	= EntryString,
					ControlText = ControlString,
					Amount		= InAmount,					
				});
			end

			kResources[eResourceType].Total = kResources[eResourceType].Total + InAmount;
		end -- pPlayerResources
	end -- localPlayer
end

-- Obtain the total resources for a given city.
function GetCityResourceData( pCity:table )
	--print("GetCityResourceData", pCity:GetName());
	
	if bIsGatheringStorm then return GetCityResourceDataXP2(pCity); end
	
	-- Loop through all the plots for a given city; tallying the resource amount.
	local kResources : table = {};
	local cityPlots : table = Map.GetCityPlots():GetPurchasedPlots(pCity)
	for _, plotID in ipairs(cityPlots) do
		local plot			: table = Map.GetPlotByIndex(plotID)
		local plotX			: number = plot:GetX()
		local plotY			: number = plot:GetY()
		local eResourceType : number = plot:GetResourceType();

		-- TODO: Account for trade/diplomacy resources.
		if eResourceType ~= -1 and Players[pCity:GetOwner()]:GetResources():IsResourceExtractableAt(plot) then
			if kResources[eResourceType] == nil then
				kResources[eResourceType] = 1;
			else
				kResources[eResourceType] = kResources[eResourceType] + 1;
			end
		end
	end
	return kResources;
end

-- a new function used: GetResourcesExtractedByCity
function GetCityResourceDataXP2( pCity:table )
	-- Loop through all the plots for a given city; tallying the resource amount.
	local kResources : table = {};
	local localPlayerID = Game.GetLocalPlayer();
	local localPlayer = Players[localPlayerID];
	if localPlayer then
		local pPlayerResources:table = localPlayer:GetResources();
		if pPlayerResources then
			local kExtractedResources = pPlayerResources:GetResourcesExtractedByCity( pCity:GetID(), ResultFormat.SUMMARY );
			if kExtractedResources ~= nil and table.count(kExtractedResources) > 0 then
				for i, entry in ipairs(kExtractedResources) do
					if entry.Amount > 0 then
						kResources[entry.ResourceType] = entry.Amount;
					end
				end
			end
		end
	end
	return kResources;
end

function GetDataResources()
	print("GetDataResources");
	
	local kResources: table = {};
	
	local playerID: number = Game.GetLocalPlayer();
	if playerID == PlayerTypes.NONE or playerID == PlayerTypes.OBSERVER then
		UI.DataError("Unable to get valid playerID for report screen.");
		return;
	end

	local player: table = Players[playerID];
	
	local pCities = player:GetCities();
	for _,pCity in pCities:Members() do
		local cityName: string = pCity:GetName();
		local cityResources: table = GetCityResourceData( pCity ); -- Add more data (not in CitySupport)
		-- Add resources
		for eResourceType,amount in pairs(cityResources) do
			AddResourceData(kResources, eResourceType, cityName, "LOC_HUD_REPORTS_TRADE_OWNED", amount);
		end
	end -- for Cities:Members

	-- =================================================================
	
	local kDealData	:table = {};
	local kPlayers	:table = PlayerManager.GetAliveMajors();
	for _, pOtherPlayer in ipairs(kPlayers) do
		local otherID:number = pOtherPlayer:GetID();
		local currentGameTurn = Game.GetCurrentGameTurn();
		if otherID ~= playerID then
			
			local pPlayerConfig	:table = PlayerConfigurations[otherID];
			local pDeals		:table = DealManager.GetPlayerDeals(playerID, otherID);
			
			if pDeals ~= nil then
				for i,pDeal in ipairs(pDeals) do
				
					-- Add outgoing resource deals
					pOutgoingDeal = pDeal:FindItemsByType(DealItemTypes.RESOURCES, DealItemSubTypes.NONE, playerID);
					if pOutgoingDeal ~= nil then
						for i,pDealItem in ipairs(pOutgoingDeal) do
							local duration: number = pDealItem:GetDuration();
							if duration ~= 0 then
								local amount		:number = pDealItem:GetAmount();
								local resourceType	:number = pDealItem:GetValueType();
								local remainingTurns:number = duration - (currentGameTurn - pDealItem:GetEnactedTurn());
								
								local entryString:string = Locale.Lookup("LOC_HUD_REPORTS_ROW_DIPLOMATIC_DEALS") .. " (" .. Locale.Lookup(pPlayerConfig:GetPlayerName()) .. " " .. Locale.Lookup("LOC_REPORTS_NUMBER_OF_TURNS", remainingTurns) .. ")";
								AddResourceData(kResources, resourceType, entryString, "LOC_HUD_REPORTS_TRADE_EXPORTED", -1 * amount);				
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
								
								local entryString:string = Locale.Lookup("LOC_HUD_REPORTS_ROW_DIPLOMATIC_DEALS") .. " (" .. Locale.Lookup(pPlayerConfig:GetPlayerName()) .. " " .. Locale.Lookup("LOC_REPORTS_NUMBER_OF_TURNS", remainingTurns) .. ")";
								AddResourceData(kResources, resourceType, entryString, "LOC_HUD_REPORTS_TRADE_IMPORTED", amount);				
							end
						end
					end	
				end -- for
			end -- if
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
						local entryString:string = LL("LOC_HUD_REPORTS_CITY_STATE") .. " (" .. LL(pMinorPlayerConfig:GetPlayerName()) .. ")";
						AddResourceData(kResources, row.Index, entryString, "LOC_CITY_STATES_SUZERAIN", resourceAmount);
					end
				end
			end
		end
	end
	
	-- add misc res data
	local pResources: table = player:GetResources();
	kResources = AddMiscResourceData(pResources, kResources);

	return kResources;
end

function UpdateResourcesData()
	print("UpdateResourcesData");
	Timer1Start();
	m_kResourceData = GetDataResources();
	Timer1Tick("UpdateResourcesData");
	g_DirtyFlag.RESOURCES = false;
end

function ViewResourcesPage()
	print("ViewResourcesPage");
	
	if g_DirtyFlag.RESOURCES then UpdateResourcesData(); end

	ResetTabForNewPageContent();

	local strategicResources:string = "";
	local luxuryResources	:string = "";
	local kBonuses			:table	= {};
	local kLuxuries			:table	= {};
	local kStrategics		:table	= {};
    local localPlayerID = Game.GetLocalPlayer();
	local localPlayer = Players[localPlayerID];
    
    -- 2021-05-12 Monopolies Mode
	-- find out if Mercantilism is unlocked
	local bMercantailismUnlocked:boolean = false;
    if GameInfo.Civics.CIVIC_MERCANTILISM then
        bMercantailismUnlocked = localPlayer:GetCulture():HasCivic(GameInfo.Civics.CIVIC_MERCANTILISM.Index);
    end
	
	local function FormatStrategicTotal(iTot:number)
		if iTot < 0 then return "[COLOR_Red]"..tostring(iTot).."[ENDCOLOR]";
		else             return "+"..tostring(iTot); end
	end

	--for eResourceType,kSingleResourceData in pairs(m_kResourceData) do
	for eResourceType,kSingleResourceData in spairs(m_kResourceData, function(t,a,b) return Locale.Lookup(GameInfo.Resources[a].Name) < Locale.Lookup(GameInfo.Resources[b].Name) end) do
		
		local kResource :table = GameInfo.Resources[eResourceType];
		
		--!!ARISTOS: Only display list of selected resource types, according to checkboxes
		if (kSingleResourceData.IsStrategic and Controls.StrategicCheckbox:IsSelected()) or
			(kSingleResourceData.IsLuxury and Controls.LuxuryCheckbox:IsSelected()) or
			(kSingleResourceData.IsBonus and Controls.BonusCheckbox:IsSelected()) then

		local instance:table = NewCollapsibleGroupInstance();	

		instance.RowHeaderButton:SetText(  kSingleResourceData.Icon..Locale.Lookup( kResource.Name ) );
		instance.RowHeaderLabel:SetHide( false ); --BRS
		if kSingleResourceData.Total < 0 then
			instance.RowHeaderLabel:SetText( Locale.Lookup("LOC_HUD_REPORTS_TOTALS").." [COLOR_Red]"..tostring(kSingleResourceData.Total).."[ENDCOLOR]" );
		else
			instance.RowHeaderLabel:SetText( Locale.Lookup("LOC_HUD_REPORTS_TOTALS").." "..tostring(kSingleResourceData.Total) );
		end
		if bIsGatheringStorm and kSingleResourceData.IsStrategic then
			instance.RowHeaderLabel:SetText( Locale.Lookup("LOC_HUD_REPORTS_TOTALS")..string.format(" %d/%d ", kSingleResourceData.Stockpile, kSingleResourceData.Maximum)..FormatStrategicTotal(kSingleResourceData.Total) );
		end

		local pHeaderInstance:table = {};
		ContextPtr:BuildInstanceForControl( "ResourcesHeaderInstance", pHeaderInstance, instance.ContentStack ) ;

		local kResourceEntries:table = kSingleResourceData.EntryList;
		for i,kEntry in ipairs(kResourceEntries) do
			local pEntryInstance:table = {};
			ContextPtr:BuildInstanceForControl( "ResourcesEntryInstance", pEntryInstance, instance.ContentStack ) ;
			pEntryInstance.CityName:SetText( Locale.Lookup(kEntry.EntryText) );
			pEntryInstance.Control:SetText( Locale.Lookup(kEntry.ControlText) );
			pEntryInstance.Amount:SetText( (kEntry.Amount<=0) and tostring(kEntry.Amount) or "+"..tostring(kEntry.Amount) );
		end

		--local pFooterInstance:table = {};
		--ContextPtr:BuildInstanceForControl( "ResourcesFooterInstance", pFooterInstance, instance.ContentStack ) ;
		--pFooterInstance.Amount:SetText( tostring(kSingleResourceData.Total) );

		-- Show how many of this resource are being allocated to what cities
		local citiesProvidedTo: table = localPlayer:GetResources():GetResourceAllocationCities(GameInfo.Resources[kResource.ResourceType].Index);
		local numCitiesProvidingTo: number = table.count(citiesProvidedTo);
		if (numCitiesProvidingTo > 0) then
			--pFooterInstance.AmenitiesContainer:SetHide(false);
			instance.AmenitiesContainer:SetHide(false); ---BRS
			--pFooterInstance.Amenities:SetText("[ICON_Amenities][ICON_GoingTo]"..numCitiesProvidingTo.." "..Locale.Lookup("LOC_PEDIA_CONCEPTS_PAGEGROUP_CITIES_NAME"));
			instance.Amenities:SetText("[ICON_Amenities][ICON_GoingTo]"..Locale.Lookup("LOC_HUD_REPORTS_CITY_AMENITIES", numCitiesProvidingTo));
			local amenitiesTooltip: string = "";
			local playerCities = localPlayer:GetCities();
			for i,city in ipairs(citiesProvidedTo) do
				local cityName = Locale.Lookup(playerCities:FindID(city.CityID):GetName());
				if i ~=1 then
					amenitiesTooltip = amenitiesTooltip.. "[NEWLINE]";
				end
				amenitiesTooltip = amenitiesTooltip.. city.AllocationAmount.." [ICON_".. kResource.ResourceType.."] [Icon_GoingTo] " ..cityName;
			end
			--pFooterInstance.Amenities:SetToolTipString(amenitiesTooltip);
			instance.Amenities:SetToolTipString(amenitiesTooltip);
		else
			--pFooterInstance.AmenitiesContainer:SetHide(true);
			instance.AmenitiesContainer:SetHide(true);
		end
        
        -- 2021-05-12 Monopolies Mode
        if bIsMonopolies and kSingleResourceData.IsLuxury and GameInfo.ResourceIndustries[kResource.ResourceType] ~= nil then -- also check if there is an industry around it!
            local pGameEconomic:table = Game.GetEconomicManager();
            local iControlled:number = pGameEconomic:GetNumControlledResources(localPlayerID, eResourceType);
            local sText:string, sTT:string = "", "";
            local sTTHead = "[ICON_".. kResource.ResourceType.."]"..LL(kResource.Name);
            -- find industry effect and type - match [ICON_xxx]
            local sEffectI:string = LL(GameInfo.ResourceIndustries[kResource.ResourceType].ResourceEffectTExt);
            local sIndustryType:string = string.match(sEffectI, "%[ICON_%a+%]");
            -- find corporation effect and type - match [ICON_xxx]
            local sEffectC:string = LL(GameInfo.ResourceCorporations[kResource.ResourceType].ResourceEffectTExt);
            local sCorpoType:string = string.match(sEffectC, "%[ICON_%a+%]");
            -- logic goes top-down, i.e. from corporation to industry
            if pGameEconomic:HasCorporationOf(localPlayerID, eResourceType) then
                -- corpo: YES
                sText = string.format("%d %s  [ICON_GreatWork_Product][ICON_GreatWork_Product] %s", iControlled, sCorpoType, LL("LOC_IMPROVEMENT_CORPORATION_NAME"));
                sTT = sTTHead..sEffectC;
            else
                -- corpo: NO, check Industry
                if pGameEconomic:HasIndustryOf(localPlayerID, eResourceType) then
                    sText = string.format("%d %s  [ICON_GreatWork_Product] %s", iControlled, sIndustryType, LL("LOC_IMPROVEMENT_INDUSTRY_NAME"));
                else
                    sText = string.format("%d %s  [ICON_Not]", iControlled, sIndustryType);
                end
                sTT = sTTHead..sEffectI;
            end
            -- if we can have an industry - add the mark
            if pGameEconomic:CanHaveIndustry(localPlayerID, eResourceType) then
                sText = sText.." [ICON_New] "..LL("LOC_IMPROVEMENT_INDUSTRY_NAME");
                sTT = sTT.."[NEWLINE]"..LL("LOC_NOTIFICATION_INDUSTRY_OPPORTUNITY_SUMMARY", iControlled, "[ICON_".. kResource.ResourceType.."]", LL(kResource.Name)); -- {1_num} {2_ResourceIcon} {3_Resource}
            end
            -- if we can have a corpo - add the mark
            if pGameEconomic:CanHaveCorporation(localPlayerID, eResourceType) then
                sText = sText.." [ICON_New] "..LL("LOC_IMPROVEMENT_CORPORATION_NAME");
                sTT = sTT.."[NEWLINE]"..LL("LOC_NOTIFICATION_CORPORATION_OPPORTUNITY_SUMMARY", iControlled, "[ICON_".. kResource.ResourceType.."]", LL(kResource.Name)); -- {1_num} {2_ResourceIcon} {3_Resource}
                sTT = sTT.."[NEWLINE][ICON_GoingTo]"..LL("LOC_IMPROVEMENT_CORPORATION_NAME")..sEffectC;

            end
            -- show info
            instance.Industry:SetText(sText);
            instance.Industry:SetToolTipString(sTT);
            instance.IndustryContainer:SetHide(false);
        else
            instance.IndustryContainer:SetHide(true);
        end

        -- 2021-05-12 Monopolies Mode
        if bIsMonopolies and kSingleResourceData.IsLuxury and GameInfo.ResourceIndustries[kResource.ResourceType] ~= nil and bMercantailismUnlocked then
            local pGameEconomic:table = Game.GetEconomicManager();
            local iControlled:number = pGameEconomic:GetNumControlledResources(localPlayerID, eResourceType);
            local kMapResources:table = pGameEconomic:GetMapResources();
            local iTotal:number = kMapResources[eResourceType];
			local iMonopolyID:number = pGameEconomic:GetResourceMonopolyPlayer(eResourceType);
            local sText:string = string.format("%d/%d  %d%%  %s", iControlled, iTotal, 100*iControlled/iTotal, (iMonopolyID == localPlayerID and LL("LOC_RESREPORT_MONOPOLY_NAME") or LL("LOC_RESREPORT_CONTROL")));
            if 100*(iControlled+1)/iTotal > 60 then sText = sText.." [ICON_New]"; end
            if iMonopolyID == localPlayerID then sText = "[COLOR_Green]"..sText.."[ENDCOLOR]"; end
            instance.Monopoly:SetText(sText);
            instance.MonopolyContainer:SetHide(false);
        else
            instance.MonopolyContainer:SetHide(true);
        end

		--SetGroupCollapsePadding(instance, pFooterInstance.Top:GetSizeY() ); --BRS moved into if
		SetGroupCollapsePadding(instance, 0); --BRS no footer
		RealizeGroup( instance ); --BRS moved into if

		end -- ARISTOS checkboxes

		local tResBottomData:table = {
			Text    = kSingleResourceData.Icon..                                      tostring(kSingleResourceData.Total),
			ToolTip = kSingleResourceData.Icon..Locale.Lookup( kResource.Name ).." "..tostring(kSingleResourceData.Total),
		};
		if bIsGatheringStorm and kSingleResourceData.IsStrategic then
			tResBottomData.Text    = string.format("%s%d/%d ",     kSingleResourceData.Icon,                                  kSingleResourceData.Stockpile, kSingleResourceData.Maximum)..FormatStrategicTotal(kSingleResourceData.Total);
			tResBottomData.ToolTip = string.format("%s %s %d/%d ", kSingleResourceData.Icon, Locale.Lookup( kResource.Name ), kSingleResourceData.Stockpile, kSingleResourceData.Maximum)..FormatStrategicTotal(kSingleResourceData.Total);
		end
		if     kSingleResourceData.IsStrategic then table.insert(kStrategics, tResBottomData);
		elseif kSingleResourceData.IsLuxury    then table.insert(kLuxuries,   tResBottomData);
		else                                        table.insert(kBonuses,    tResBottomData); end
		
		--SetGroupCollapsePadding(instance, pFooterInstance.Top:GetSizeY() ); --BRS moved into if
		--RealizeGroup( instance ); --BRS moved into if
	end
	
	local function ShowResources(kResIM:table, kResources:table)
		kResIM:ResetInstances();
		for i,v in ipairs(kResources) do
			local resourceInstance:table = kResIM:GetInstance();
			resourceInstance.Info:SetText( v.Text );
			resourceInstance.Info:SetToolTipString( v.ToolTip );
		end
	end
	ShowResources(m_strategicResourcesIM, kStrategics);
	Controls.StrategicResources:CalculateSize();
	Controls.StrategicGrid:ReprocessAnchoring();
	ShowResources(m_bonusResourcesIM, kBonuses);
	Controls.BonusResources:CalculateSize();
	Controls.BonusGrid:ReprocessAnchoring();
	ShowResources(m_luxuryResourcesIM, kLuxuries);
	Controls.LuxuryResources:CalculateSize();
	Controls.LuxuryResources:ReprocessAnchoring();
	--Controls.LuxuryGrid:ReprocessAnchoring();
	
	Controls.Stack:CalculateSize();
	Controls.Scroll:CalculateSize();

	Controls.CollapseAll:SetHide( false );
	Controls.BottomYieldTotals:SetHide( true );
	Controls.BottomResourceTotals:SetHide( false ); -- ViewResourcesPage
	Controls.BottomPoliciesFilters:SetHide( true );
	Controls.BottomMinorsFilters:SetHide( true );
	Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - (Controls.BottomResourceTotals:GetSizeY() + SIZE_HEIGHT_PADDING_BOTTOM_ADJUST ) );	
	-- Remember this tab when report is next opened: ARISTOS
	m_kCurrentTab = 2;
end

-- ===========================================================================
-- CHECKBOXES
-- ===========================================================================

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

-- ===========================================================================
function InitializeResources()
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
end

print("BRS: Loaded file BRSPage_Resources.lua");
