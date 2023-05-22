-- ===========================================================================
-- Better Report Screen - page Yields
-- Author: Infixo
-- 2023-05-10: Created
-- ===========================================================================

-- this report uses 4 data tables, globals for debug purposes
m_kCityData = nil;
m_kCityTotalData = nil;
m_kUnitData = nil;	-- TODO: Show units by promotion class
m_kDealData = nil; -- diplomatic deals expenses displayed in the Yields page
-- BRS specific
m_kModifiers = nil; -- to calculate yield per pop and other modifier-ralated effects on the city level

local DARKEN_CITY_INCOME_AREA_ADDITIONAL_Y		:number = 6;
local SIZE_HEIGHT_BOTTOM_YIELDS					:number = 135;
local INDENT_STRING								:string = "      ";


function GetDataYields()
	print("GetDataYields");

	local playerID	:number = Game.GetLocalPlayer();
	if playerID == PlayerTypes.NONE or playerID == PlayerTypes.OBSERVER then
		UI.DataError("Unable to get valid playerID for report screen.");
		return;
	end
	
	local isShowDetails: boolean = not Controls.HideCityBuildingsCheckbox:IsSelected(); -- read detailed data only when needed

	local kCityData		:table = {};
	local kCityTotalData:table = {
		Income	= {},
		Expenses= {},
		Net		= {},
		Treasury= {}
	};
	local kUnitData: table = {};
	local kDealData: table = {};

	kCityTotalData.Income[YieldTypes.CULTURE]	= 0;
	kCityTotalData.Income[YieldTypes.FAITH]		= 0;
	kCityTotalData.Income[YieldTypes.FOOD]		= 0;
	kCityTotalData.Income[YieldTypes.GOLD]		= 0;
	kCityTotalData.Income[YieldTypes.PRODUCTION]= 0;
	kCityTotalData.Income[YieldTypes.SCIENCE]	= 0;
	kCityTotalData.Income["TOURISM"]			= 0;
	kCityTotalData.Expenses[YieldTypes.GOLD]	= 0;

	local player	:table  = Players[playerID];
	local pCulture	:table	= player:GetCulture();
	local pTreasury	:table	= player:GetTreasury();
	local pReligion	:table	= player:GetReligion();
	local pScience	:table	= player:GetTechs();
	local pUnits    :table  = player:GetUnits(); -- 230425 moved
	
	if isShowDetails then -- modifiers are needed only when details are shown
	
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
	--print("GetDataYields: modifiers");
	m_kModifiers = {}; -- clear main table
	local sTrackedPlayer:string = PlayerConfigurations[playerID]:GetLeaderName(); -- LOC_LEADER_xxx_NAME
	--print("Tracking player", sTrackedPlayer); -- debug
	--for k,v in pairs(tTrackedEffects) do print(k,v); end -- debug
	local tTrackedOwners:table = {};
	for _,city in player:GetCities():Members() do
		tTrackedOwners[ city:GetName() ] = true;
		m_kModifiers[ city:GetName() ] = {}; -- we need al least empty table for each city
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
			if data.Modifier == nil then print("WARNING! GetDataYields/Modifiers: Ignoring non-existing modifier", data.ID, data.Definition.Id, sOwnerName, sSubjectName); return end
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
		
	end
	--print("--------------"); print("FOUND MODIFIERS FOR CITIES"); for k,v in pairs(m_kModifiers) do print(k, #v); end
	
	end -- if isShowDetails

	-- =================================================================
	--print("GetDataYields: cities");
	for _,pCity in player:GetCities():Members() do
		local cityName: string = pCity:GetName();
		--print("city", LL(cityName));
			
		-- Big calls, obtain city data and add report specific fields to it.
		local data: table = GetCityData( pCity );
		data.WorkedTileYields, data.NumWorkedTiles, data.SpecialistYields, data.NumSpecialists = GetWorkedTileYieldData( pCity, pCulture );	-- Add more data (not in CitySupport)

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

		-- ADDITIONAL DATA
		
		-- Modifiers
		if isShowDetails then
			data.Modifiers = m_kModifiers[ cityName ]; -- just a reference to the main table
		end
		
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

	-- =================================================================
	-- Units (TODO: Group units by promotion class and determine total maintenance cost)
	--print("GetDataYields: units");
	local MaintenanceDiscountPerUnit:number = pTreasury:GetMaintDiscountPerUnit();
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
	for _, pOtherPlayer in ipairs(PlayerManager.GetAliveMajors()) do
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
							end
						end
					end	
					--end	-- BRS end
				end							
			end

		end
	end
	
	return kCityData, kCityTotalData, kUnitData, kDealData;
end

-- ===========================================================================
--	Obtain the yields from the worked plots
-- Infixo: again, original function is incomplete, the game uses a different algorithm
-- 1. Get info about all tiles and citizens from CityManager.GetCommandTargets
-- 2. If the plot is worked then
--    2a. if it is a District then Yield = NumSpecs * District_CitizenYieldChanges.YieldChange
--    2b. if it is NOT a District then Yield = plot:GetYield()
-- I will break it into 2 rows, "Worked Tiles" and "Specialists" to avoid confusion
-- ===========================================================================
function GetWorkedTileYieldData( pCity:table, pCulture:table )
	-- return data
	local kYields:table     = { YIELD_PRODUCTION = 0, YIELD_FOOD = 0, YIELD_GOLD = 0, YIELD_FAITH = 0, YIELD_SCIENCE = 0, YIELD_CULTURE	= 0, TOURISM = 0 };
	local kSpecYields:table = { YIELD_PRODUCTION = 0, YIELD_FOOD = 0, YIELD_GOLD = 0, YIELD_FAITH = 0, YIELD_SCIENCE = 0, YIELD_CULTURE	= 0 };
	local iNumWorkedPlots:number = 0;
	local iNumSpecialists:number = 0;
	
	-- code partially taken from PlotInfo.lua
	local tParameters:table = {};
	tParameters[CityCommandTypes.PARAM_MANAGE_CITIZEN] = UI.GetInterfaceModeParameter(CityCommandTypes.PARAM_MANAGE_CITIZEN);
	local tResults:table = CityManager.GetCommandTargets( pCity, CityCommandTypes.MANAGE, tParameters );
	if tResults == nil then
		print("ERROR: GetWorkedTileYieldData, GetCommandTargets returned nil")
		return kYields, 0, kSpecYields, 0;
	end

	local tPlots:table = tResults[CityCommandResults.PLOTS];
	local tUnits:table = tResults[CityCommandResults.CITIZENS];
	--local tMaxUnits		:table = tResults[CityCommandResults.MAX_CITIZENS]; -- not used
	--local tLockedUnits	:table = tResults[CityCommandResults.LOCKED_CITIZENS]; -- not used
	if tPlots == nil or table.count(tPlots) == 0 then
		print("ERROR: GetWorkedTileYieldData, GetCommandTargets returned 0 plots")
		return kYields, 0, kSpecYields, 0;
	end
	
	--print("--- PLOTS OF", pCity:GetName(), table.count(tPlots)); -- debug
	--print("--- CITIZENS OF", pCity:GetName(), table.count(tUnits)); -- debug

	for i,plotId in pairs(tPlots) do

		local kPlot	:table = Map.GetPlotByIndex(plotId);
		local index:number = kPlot:GetIndex();
		local eDistrictType:number = kPlot:GetDistrictType();
		local numUnits:number = tUnits[i];
		--local maxUnits:number = tMaxUnits[i];
		--print("..plot", index, kPlot:GetX(), kPlot:GetY(), eDistrictType, numUnits, "yields", kPlot:GetYield(0), kPlot:GetYield(1));
		
		if numUnits > 0 then -- if worked at all
			if eDistrictType > 0 then -- CITY_CENTER is treated as normal tile with yields, it is not a specialist
				-- district
				iNumSpecialists = iNumSpecialists + numUnits;
				local sDistrictType:string = GameInfo.Districts[ eDistrictType ].DistrictType;
				for row in GameInfo.District_CitizenYieldChanges() do
					if row.DistrictType == sDistrictType then
						kSpecYields[row.YieldType] = kSpecYields[row.YieldType] + numUnits * row.YieldChange;
					end
				end
			else
				-- normal tile or City Center
				iNumWorkedPlots = iNumWorkedPlots + 1;
				--for row in GameInfo.Yields() do
                    --kYields[row.YieldType] = kYields[row.YieldType] + kPlot:GetYield(row.Index);
				--end
                -- 2021-05-14 Support for mods that add new yield types e.g. DE:E
                for yield,idx in pairs(YieldTypes) do -- WARNING! In this context there are no extra yields from RMT - but this is ok, because they don't exist in the game anyway
                    kYields["YIELD_"..yield] = kYields["YIELD_"..yield] + kPlot:GetYield(idx);
				end
			end
		end
		-- Support tourism.
		-- Not a common yield, and only exposure from game core is based off
		-- of the plot so the sum is easily shown, but it's not possible to 
		-- show how individual buildings contribute... yet.
		--kYields.TOURISM = kYields.TOURISM + pCulture:GetTourismAt( index );
	end

	-- TOURISM
	-- Tourism from tiles like Wonders and Districts is not counted because they cannot be worked!
    local cityX:number, cityY:number = pCity:GetX(), pCity:GetY();
    --local iInside, iOutside = 0, 0;
	for _, plotID in ipairs(Map.GetCityPlots():GetPurchasedPlots(pCity)) do
        pPlot = Map.GetPlotByIndex(plotID);
		--print("...tourism at", plotID, pCulture:GetTourismAt( plotID )); -- debug
        if Map.GetPlotDistance(cityX, cityY, pPlot:GetX(), pPlot:GetY()) <= 3 then
            kYields.TOURISM = kYields.TOURISM + pCulture:GetTourismAt( plotID );
            --iInside = iInside + pCulture:GetTourismAt( plotID );
            --if pCulture:GetTourismAt( plotID ) > 0 then print("...inside tourism at", plotID, pCulture:GetTourismAt( plotID )); end -- debug
        else
            --iOutside = iOutside + pCulture:GetTourismAt( plotID );
        end
		--kYields.TOURISM = kYields.TOURISM + pCulture:GetTourismAt( plotID );
	end
    --print("tourism inside", iInside, "outside", iOutside);
	--print("--- SUMMARY OF", pCity:GetName(), iNumWorkedPlots, iNumSpecialists, "tourism:", kYields.TOURISM); -- debug
	return kYields, iNumWorkedPlots, kSpecYields, iNumSpecialists;
end

-- ===========================================================================
function UpdateYieldsData()
	print("UpdateYieldsData");
	Timer1Start();
	m_kCityData, m_kCityTotalData, m_kUnitData, m_kDealData = GetDataYields();
	Timer1Tick("UpdateYieldsData");
	g_DirtyFlag.YIELDS = false;
	if not Controls.HideCityBuildingsCheckbox:IsSelected() then g_DirtyFlag.YIELDSDETAILS = false; end
end

-- ===========================================================================
local sortCities : table = { by = "CityName", descend = false }

local function sortByCities( name )
	if name == sortCities.by then
		sortCities.descend = not sortCities.descend
	else
		sortCities.by = name
		sortCities.descend = true
		if name == "CityName" then sortCities.descend = false; end -- exception
	end
	ViewYieldsPage()
end

local function sortFunction( t, a, b )
	if sortCities.by == "TourismPerTurn" then
		if sortCities.descend then
			return t[b].WorkedTileYields["TOURISM"] < t[a].WorkedTileYields["TOURISM"]
		else
			return t[b].WorkedTileYields["TOURISM"] > t[a].WorkedTileYields["TOURISM"]
		end
	else
		if sortCities.descend then
			return t[b][sortCities.by] < t[a][sortCities.by]
		else
			return t[b][sortCities.by] > t[a][sortCities.by]
		end
	end
end

local populationToCultureScale:number = GameInfo.GlobalParameters["CULTURE_PERCENTAGE_YIELD_PER_POP"].Value / 100;
local populationToScienceScale:number = GameInfo.GlobalParameters["SCIENCE_PERCENTAGE_YIELD_PER_POP"].Value / 100; -- Infixo added science per pop

function ViewYieldsPage()
	print("ViewYieldsPage", g_DirtyFlag.YIELDS, g_DirtyFlag.YIELDSDETAILS, Controls.HideCityBuildingsCheckbox:IsSelected());

	if g_DirtyFlag.YIELDS or g_DirtyFlag.YIELDSDETAILS then UpdateYieldsData(); end

	ResetTabForNewPageContent();

	local pPlayer:table = Players[Game.GetLocalPlayer()]; --BRS

	local instance:table = nil;
	instance = NewCollapsibleGroupInstance();
	instance.RowHeaderButton:SetText( Locale.Lookup("LOC_HUD_REPORTS_ROW_CITY_INCOME") );
	instance.RowHeaderLabel:SetHide( true ); --BRS
	instance.AmenitiesContainer:SetHide(true);
	instance.IndustryContainer:SetHide(true); -- 2021-05-21
	instance.MonopolyContainer:SetHide(true); -- 2021-05-21
	
	local pHeaderInstance:table = {}
	ContextPtr:BuildInstanceForControl( "CityIncomeHeaderInstance", pHeaderInstance, instance.ContentStack ) ;	

	--BRS sorting
	-- sorting is a bit weird because ViewYieldsPage is called again and entire tab is recreated, so new callbacks are registered
	pHeaderInstance.CityNameButton:RegisterCallback( Mouse.eLClick, function() sortByCities( "CityName" ) end )
	pHeaderInstance.ProductionButton:RegisterCallback( Mouse.eLClick, function() sortByCities( "ProductionPerTurn" ) end )
	--pHeaderInstance.FoodButton:RegisterCallback( Mouse.eLClick, function() sortByCities( "FoodPerTurn" ) end )
	pHeaderInstance.FoodButton:RegisterCallback( Mouse.eLClick, function() sortByCities( "TotalFoodSurplus" ) end )
	pHeaderInstance.GoldButton:RegisterCallback( Mouse.eLClick, function() sortByCities( "GoldPerTurn" ) end )
	pHeaderInstance.FaithButton:RegisterCallback( Mouse.eLClick, function() sortByCities( "FaithPerTurn" ) end )
	pHeaderInstance.ScienceButton:RegisterCallback( Mouse.eLClick, function() sortByCities( "SciencePerTurn" ) end )
	pHeaderInstance.CultureButton:RegisterCallback( Mouse.eLClick, function() sortByCities( "CulturePerTurn" ) end )
	pHeaderInstance.TourismButton:RegisterCallback( Mouse.eLClick, function() sortByCities( "TourismPerTurn" ) end )

	local goldCityTotal		:number = 0;
	local faithCityTotal	:number = 0;
	local scienceCityTotal	:number = 0;
	local cultureCityTotal	:number = 0;
	local tourismCityTotal	:number = 0;
	
	-- helper for calculating lines from modifiers
	local function GetEmptyYieldsTable()
		return { YIELD_PRODUCTION = 0, YIELD_FOOD = 0, YIELD_GOLD = 0, YIELD_FAITH = 0, YIELD_SCIENCE = 0, YIELD_CULTURE = 0 };
	end
	-- Infixo needed to properly calculate yields from % modifiers (like amenities)
	local kBaseYields:table = GetEmptyYieldsTable();
	kBaseYields.TOURISM = 0;
	local function StoreInBaseYields(sYield:string, fValue:number) kBaseYields[ sYield ] = kBaseYields[ sYield ] + fValue; end

	-- ========== City Income ==========

	function CreatLineItemInstance(cityInstance:table, name:string, production:number, gold:number, food:number, science:number, culture:number, faith:number, bDontStore:boolean)
		local lineInstance:table = {};
		ContextPtr:BuildInstanceForControl("CityIncomeLineItemInstance", lineInstance, cityInstance.LineItemStack );
		TruncateStringWithTooltipClean(lineInstance.LineItemName, 345, name);
		lineInstance.Production:SetText( toPlusMinusNoneString(production));
		lineInstance.Food:SetText( toPlusMinusNoneString(food));
		lineInstance.Gold:SetText( toPlusMinusNoneString(gold));
		lineInstance.Faith:SetText( toPlusMinusNoneString(faith));
		lineInstance.Science:SetText( toPlusMinusNoneString(science));
		lineInstance.Culture:SetText( toPlusMinusNoneString(culture));
		--BRS Infixo needed to properly calculate yields from % modifiers (like amenities)
		if bDontStore then return lineInstance; end -- default: omit param and store
		StoreInBaseYields("YIELD_PRODUCTION", production);
		StoreInBaseYields("YIELD_FOOD", food);
		StoreInBaseYields("YIELD_GOLD", gold);
		StoreInBaseYields("YIELD_FAITH", faith);
		StoreInBaseYields("YIELD_SCIENCE", science);
		StoreInBaseYields("YIELD_CULTURE", culture);
		StoreInBaseYields("TOURISM", 0); -- not passed here
		--BRS end
		return lineInstance;
	end
	
	--BRS this function will be used to set singular fields in LineItemInstance, based on YieldType
	function SetFieldInLineItemInstance(lineItemInstance:table, yieldType:string, yieldValue:number)
		if     yieldType == "YIELD_PRODUCTION" then lineItemInstance.Production:SetText( toPlusMinusNoneString(yieldValue) );
		elseif yieldType == "YIELD_FOOD"       then lineItemInstance.Food:SetText(       toPlusMinusNoneString(yieldValue) );
		elseif yieldType == "YIELD_GOLD"       then lineItemInstance.Gold:SetText(       toPlusMinusNoneString(yieldValue) );
		elseif yieldType == "YIELD_FAITH"      then lineItemInstance.Faith:SetText(      toPlusMinusNoneString(yieldValue) );
		elseif yieldType == "YIELD_SCIENCE"    then lineItemInstance.Science:SetText(    toPlusMinusNoneString(yieldValue) );
		elseif yieldType == "YIELD_CULTURE"    then lineItemInstance.Culture:SetText(    toPlusMinusNoneString(yieldValue) );
		end
		StoreInBaseYields(yieldType, yieldValue);
	end

	for cityName,kCityData in spairs( m_kCityData, function( t, a, b ) return sortFunction( t, a, b ) end ) do --BRS sorting
		--print("show city", kCityData.CityName);
		local pCityInstance:table = {};
		ContextPtr:BuildInstanceForControl( "CityIncomeInstance", pCityInstance, instance.ContentStack ) ;
		pCityInstance.LineItemStack:DestroyAllChildren();
		TruncateStringWithTooltip(pCityInstance.CityName, 230, (kCityData.IsCapital and "[ICON_Capital]" or "")..Locale.Lookup(kCityData.CityName));
		pCityInstance.CityPopulation:SetText(kCityData.Population);

		--Great works
		local greatWorks:table = GetGreatWorksForCity(kCityData.City);
		
		-- Infixo reset base for amenities
		for yield,_ in pairs(kBaseYields) do kBaseYields[ yield ] = 0; end
		-- go to the city after clicking
		pCityInstance.GoToCityButton:RegisterCallback( Mouse.eLClick, function() Close(); UI.LookAtPlot( kCityData.City:GetX(), kCityData.City:GetY() ); UI.SelectCity( kCityData.City ); end );
		pCityInstance.GoToCityButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound( "Main_Menu_Mouse_Over" ); end );

		-- Current Production
		local kCurrentProduction:table = kCityData.ProductionQueue[1]; -- this returns a table from GetCurrentProductionInfoOfCity() modified a bit in CitySupport.lua
		pCityInstance.CurrentProduction:SetHide( kCurrentProduction == nil );
		if kCurrentProduction ~= nil then
			--print("**********", cityName); dshowrectable(kCurrentProduction);
			local tooltip:string = kCurrentProduction.Name.." [ICON_Turn]"..tostring(kCurrentProduction.Turns)..string.format(" (%d%%)", kCurrentProduction.PercentComplete*100);
			if kCurrentProduction.Description ~= nil then
				tooltip = tooltip .. "[NEWLINE]" .. Locale.Lookup(kCurrentProduction.Description);
			end
			pCityInstance.CurrentProduction:SetToolTipString( tooltip );

			if kCurrentProduction.Icons ~= nil then
				pCityInstance.CityBannerBackground:SetHide( false );
				-- Gathering Storm - there are 5 icons returned now
				for _,iconName in ipairs(kCurrentProduction.Icons) do
					if iconName ~= nil and pCityInstance.CurrentProduction:TrySetIcon(iconName) then break; end
				end
				pCityInstance.CityProductionMeter:SetPercent( kCurrentProduction.PercentComplete );
				pCityInstance.CityProductionNextTurn:SetPercent( kCurrentProduction.PercentCompleteNextTurn );			
				pCityInstance.ProductionBorder:SetHide( kCurrentProduction.Type == ProductionType.DISTRICT );
			else
				pCityInstance.CityBannerBackground:SetHide( true );
			end
		end

		-- Infixo: this is the place to add Yield Focus
		local function SetYieldTextAndFocusFlag(pLabel:table, fValue:number, eYieldType:number)
			local sText:string = toPlusMinusString(fValue);
			local sToolTip:string = "";
			if     kCityData.YieldFilters[eYieldType] == YIELD_STATE.FAVORED then
				sText = sText.."  [COLOR:0,255,0,255]!"; -- [ICON_FoodSurplus][ICON_CheckSuccess]
				sToolTip = Locale.Lookup("LOC_HUD_CITY_YIELD_FOCUSING", GameInfo.Yields[eYieldType].Name);
			elseif kCityData.YieldFilters[eYieldType] == YIELD_STATE.IGNORED then
				sText = sText.."  [COLOR:255,0,0,255]!"; -- [ICON_FoodDeficit][ICON_CheckFail]
				sToolTip = Locale.Lookup("LOC_HUD_CITY_YIELD_IGNORING", GameInfo.Yields[eYieldType].Name);
			end
			pLabel:SetText( sText );
			pLabel:SetToolTipString( sToolTip );
		end
		SetYieldTextAndFocusFlag( pCityInstance.Production,kCityData.ProductionPerTurn,YieldTypes.PRODUCTION );
		--SetYieldTextAndFocusFlag( pCityInstance.Food,      kCityData.FoodPerTurn,      YieldTypes.FOOD );
		SetYieldTextAndFocusFlag( pCityInstance.Food,      kCityData.TotalFoodSurplus, YieldTypes.FOOD );
		SetYieldTextAndFocusFlag( pCityInstance.Gold,      kCityData.GoldPerTurn,      YieldTypes.GOLD );
		SetYieldTextAndFocusFlag( pCityInstance.Faith,     kCityData.FaithPerTurn,     YieldTypes.FAITH );
		SetYieldTextAndFocusFlag( pCityInstance.Science,   kCityData.SciencePerTurn,   YieldTypes.SCIENCE );
		SetYieldTextAndFocusFlag( pCityInstance.Culture,   kCityData.CulturePerTurn,   YieldTypes.CULTURE );
		pCityInstance.Tourism:SetText( toPlusMinusString(kCityData.WorkedTileYields["TOURISM"]) ); -- unchanged (no focus feature here)
		-- BIG food tooltip
		pCityInstance.FoodContainer:SetToolTipString(kCityData.TotalFoodSurplusToolTip);

		-- Add to all cities totals
		goldCityTotal	= goldCityTotal + kCityData.GoldPerTurn;
		faithCityTotal	= faithCityTotal + kCityData.FaithPerTurn;
		scienceCityTotal= scienceCityTotal + kCityData.SciencePerTurn;
		cultureCityTotal= cultureCityTotal + kCityData.CulturePerTurn;
		tourismCityTotal= tourismCityTotal + kCityData.WorkedTileYields["TOURISM"];
		
		if not Controls.HideCityBuildingsCheckbox:IsSelected() then --BRS
		
		-- Worked Tiles
		if kCityData.NumWorkedTiles > 0 then 
			CreatLineItemInstance(	pCityInstance,
									Locale.Lookup("LOC_HUD_REPORTS_WORKED_TILES")..string.format("  [COLOR_White]%d[ENDCOLOR]", kCityData.NumWorkedTiles),
									kCityData.WorkedTileYields["YIELD_PRODUCTION"],
									kCityData.WorkedTileYields["YIELD_GOLD"],
									kCityData.WorkedTileYields["YIELD_FOOD"],
									kCityData.WorkedTileYields["YIELD_SCIENCE"],
									kCityData.WorkedTileYields["YIELD_CULTURE"],
									kCityData.WorkedTileYields["YIELD_FAITH"]);
		end

		-- Specialists
		if kCityData.NumSpecialists > 0 then
			CreatLineItemInstance(	pCityInstance,
									Locale.Lookup("LOC_BRS_SPECIALISTS")..string.format("  [COLOR_White]%d[ENDCOLOR]", kCityData.NumSpecialists),
									kCityData.SpecialistYields["YIELD_PRODUCTION"],
									kCityData.SpecialistYields["YIELD_GOLD"],
									kCityData.SpecialistYields["YIELD_FOOD"],
									kCityData.SpecialistYields["YIELD_SCIENCE"],
									kCityData.SpecialistYields["YIELD_CULTURE"],
									kCityData.SpecialistYields["YIELD_FAITH"]);
		end

		-- Additional Yields from Population
		-- added modifiers with EFFECT_ADJUST_CITY_YIELD_PER_POPULATION
		local tPopYields:table = GetEmptyYieldsTable(); -- will always show
		for _,mod in ipairs(kCityData.Modifiers) do
			if mod.Modifier.EffectType == "EFFECT_ADJUST_CITY_YIELD_PER_POPULATION" then
				tPopYields[ mod.Arguments.YieldType ] = tPopYields[ mod.Arguments.YieldType ] + kCityData.Population * tonumber(mod.Arguments.Amount);
			end
		end
		CreatLineItemInstance(	pCityInstance,
								Locale.Lookup("LOC_HUD_CITY_POPULATION")..string.format("  [COLOR_White]%d[ENDCOLOR]", kCityData.Population),
								tPopYields.YIELD_PRODUCTION,
								tPopYields.YIELD_GOLD,
								tPopYields.YIELD_FOOD    + kCityData.FoodConsumption, -- food
								tPopYields.YIELD_SCIENCE + kCityData.Population * populationToScienceScale,
								tPopYields.YIELD_CULTURE + kCityData.Population * populationToCultureScale,
								tPopYields.YIELD_FAITH);

		-- Main loop for all districts and buildings
		for i,kDistrict in ipairs(kCityData.BuildingsAndDistricts) do			
			--District line item
			--BRS GetYield() includes also GetAdjacencyYield(), so must subtract to not duplicate them
			local districtInstance = CreatLineItemInstance(	pCityInstance, 
															(kDistrict.isBuilt and kDistrict.Name) or Locale.Lookup("LOC_CITY_BANNER_PRODUCING", kDistrict.Name),
															kDistrict.Production - kDistrict.AdjacencyBonus.Production,
															kDistrict.Gold       - kDistrict.AdjacencyBonus.Gold,
															kDistrict.Food       - kDistrict.AdjacencyBonus.Food,
															kDistrict.Science    - kDistrict.AdjacencyBonus.Science,
															kDistrict.Culture    - kDistrict.AdjacencyBonus.Culture,
															kDistrict.Faith      - kDistrict.AdjacencyBonus.Faith);
			districtInstance.DistrictIcon:SetHide(false);
			districtInstance.DistrictIcon:SetIcon(kDistrict.Icon);

			function HasValidAdjacencyBonus(adjacencyTable:table)
				for _, yield in pairs(adjacencyTable) do
					if yield ~= 0 then
						return true;
					end
				end
				return false;
			end

			--Adjacency
			if kDistrict.isBuilt and HasValidAdjacencyBonus(kDistrict.AdjacencyBonus) then -- Infixo fix for checking if it is actually built!
				CreatLineItemInstance(	pCityInstance,
										INDENT_STRING .. Locale.Lookup("LOC_HUD_REPORTS_ADJACENCY_BONUS"),
										kDistrict.AdjacencyBonus.Production,
										kDistrict.AdjacencyBonus.Gold,
										kDistrict.AdjacencyBonus.Food,
										kDistrict.AdjacencyBonus.Science,
										kDistrict.AdjacencyBonus.Culture,
										kDistrict.AdjacencyBonus.Faith);
			end

			
			for i,kBuilding in ipairs(kDistrict.Buildings) do
				CreatLineItemInstance(	pCityInstance,
										INDENT_STRING ..  kBuilding.Name,
										kBuilding.ProductionPerTurn,
										kBuilding.GoldPerTurn,
										kBuilding.FoodPerTurn,
										kBuilding.SciencePerTurn,
										kBuilding.CulturePerTurn,
										kBuilding.FaithPerTurn);

				--Add great works
				if greatWorks[kBuilding.Type] ~= nil then
					--Add our line items!
					for _, kGreatWork in ipairs(greatWorks[kBuilding.Type]) do
						local sIconString:string = GameInfo.GreatWorkObjectTypes[ kGreatWork.GreatWorkObjectType ].IconString;
						local pLineItemInstance:table = CreatLineItemInstance(pCityInstance, INDENT_STRING..INDENT_STRING..sIconString..Locale.Lookup(kGreatWork.Name), 0, 0, 0, 0, 0, 0);
						for _, yield in ipairs(kGreatWork.YieldChanges) do
							SetFieldInLineItemInstance(pLineItemInstance, yield.YieldType, yield.YieldChange);
						end
					end
				end
			end
		end

		-- Display wonder yields
		if kCityData.Wonders then
			for _, wonder in ipairs(kCityData.Wonders) do
				if wonder.Yields[1] ~= nil or greatWorks[wonder.Type] ~= nil then
				-- Assign yields to the line item
					local pLineItemInstance:table = CreatLineItemInstance(pCityInstance, wonder.Name, 0, 0, 0, 0, 0, 0);
					pLineItemInstance.DistrictIcon:SetHide(false);
					pLineItemInstance.DistrictIcon:SetIcon("ICON_DISTRICT_WONDER");
					-- Show yields
					for _, yield in ipairs(wonder.Yields) do
						SetFieldInLineItemInstance(pLineItemInstance, yield.YieldType, yield.YieldChange);
					end
				end

				--Add great works
				if greatWorks[wonder.Type] ~= nil then
					--Add our line items!
					for _, kGreatWork in ipairs(greatWorks[wonder.Type]) do
						local sIconString:string = GameInfo.GreatWorkObjectTypes[ kGreatWork.GreatWorkObjectType ].IconString;
						local pLineItemInstance:table = CreatLineItemInstance(pCityInstance, INDENT_STRING..sIconString..Locale.Lookup(kGreatWork.Name), 0, 0, 0, 0, 0, 0);
						for _, yield in ipairs(kGreatWork.YieldChanges) do
							SetFieldInLineItemInstance(pLineItemInstance, yield.YieldType, yield.YieldChange);
						end
					end
				end
			end
		end

		-- Display yields from outgoing routes
		if kCityData.OutgoingRoutes then
			for i,route in ipairs(kCityData.OutgoingRoutes) do
				if route ~= nil then
					if route.OriginYields then
						-- Find destination city
						local pDestPlayer:table = Players[route.DestinationCityPlayer];
						local pDestPlayerCities:table = pDestPlayer:GetCities();
						local pDestCity:table = pDestPlayerCities:FindID(route.DestinationCityID);
						--Assign yields to the line item
						local pLineItemInstance:table = CreatLineItemInstance(pCityInstance, Locale.Lookup("LOC_HUD_REPORTS_TRADE_WITH", Locale.Lookup(pDestCity:GetName())), 0, 0, 0, 0, 0, 0);
						for j,yield in ipairs(route.OriginYields) do
							local yieldInfo = GameInfo.Yields[yield.YieldIndex];
							if yieldInfo then
								SetFieldInLineItemInstance(pLineItemInstance, yieldInfo.YieldType, yield.Amount);
							end
						end
					end
				end
			end
		end
		
		-- 230522 #14 Display yields from incoming routes
		if kCityData.IncomingRoutes then
			for _,route in ipairs(kCityData.IncomingRoutes) do
				if route ~= nil then
					if route.DestinationYields then
						-- Find origin city
						local pOrgPlayer:table = Players[route.OriginCityPlayer];
						local pOrgPlayerCities:table = pOrgPlayer:GetCities();
						local pOrgCity:table = pOrgPlayerCities:FindID(route.OriginCityID);
						--Assign yields to the line item
						local pLineItemInstance:table = CreatLineItemInstance(pCityInstance, LL("LOC_HUD_REPORTS_TRADE_WITH", LL(pOrgCity:GetName())), 0, 0, 0, 0, 0, 0);
						for _,yield in ipairs(route.DestinationYields) do
							local yieldInfo = GameInfo.Yields[yield.YieldIndex];
							if yieldInfo then
								SetFieldInLineItemInstance(pLineItemInstance, yieldInfo.YieldType, yield.Amount);
							end
						end
					end
				end
			end
		end

		-- Flat yields from Modifiers EFFECT_ADJUST_CITY_YIELD_CHANGE
		local tFlatYields:table = GetEmptyYieldsTable();
		local bFlatYields:boolean = false;
		for _,mod in ipairs(kCityData.Modifiers) do
			if mod.Modifier.EffectType == "EFFECT_ADJUST_CITY_YIELD_CHANGE" then
				tFlatYields[ mod.Arguments.YieldType ] = tFlatYields[ mod.Arguments.YieldType ] + tonumber(mod.Arguments.Amount);
				bFlatYields = true;
			end
		end
		--print("MOD from FLAT YIELDS"); for k,v in pairs(tFlatYields) do print(k,v); end
		if bFlatYields then
			CreatLineItemInstance(
				pCityInstance, Locale.Lookup("LOC_BRS_FROM_MODIFIERS"),
				tFlatYields.YIELD_PRODUCTION, tFlatYields.YIELD_GOLD, tFlatYields.YIELD_FOOD, tFlatYields.YIELD_SCIENCE, tFlatYields.YIELD_CULTURE, tFlatYields.YIELD_FAITH
			); -- this one needs to be stored
		end

		-- Flat yields from Modifiers EFFECT_ADJUST_CITY_YIELD_PER_DISTRICT
		if kCityData.NumSpecialtyDistricts > 0 then
			tFlatYields = GetEmptyYieldsTable();
			bFlatYields = false;
			for _,mod in ipairs(kCityData.Modifiers) do
				if mod.Modifier.EffectType == "EFFECT_ADJUST_CITY_YIELD_PER_DISTRICT" then
					tFlatYields[ mod.Arguments.YieldType ] = tFlatYields[ mod.Arguments.YieldType ] + tonumber(mod.Arguments.Amount) * kCityData.NumSpecialtyDistricts;
					bFlatYields = true;
				end
			end
			if bFlatYields then
				CreatLineItemInstance(
					pCityInstance, Locale.Lookup("LOC_BRS_HAVING_DISTRICTS", kCityData.NumSpecialtyDistricts),
					tFlatYields.YIELD_PRODUCTION, tFlatYields.YIELD_GOLD, tFlatYields.YIELD_FOOD, tFlatYields.YIELD_SCIENCE, tFlatYields.YIELD_CULTURE, tFlatYields.YIELD_FAITH
				); -- this one needs to be stored
			end
		end
		
		-- Flat yields from Modifiers EFFECT_ADJUST_CITY_PRODUCTION_BUILDING
		if kCityData.CurrentProductionType == "BUILDING" then
			tFlatYields = GetEmptyYieldsTable();
			bFlatYields = false;
			for _,mod in ipairs(kCityData.Modifiers) do
				if mod.Modifier.EffectType == "EFFECT_ADJUST_CITY_PRODUCTION_BUILDING" then
					tFlatYields.YIELD_PRODUCTION = tFlatYields.YIELD_PRODUCTION + tonumber(mod.Arguments.Amount);
					bFlatYields = true;
				end
			end
			if bFlatYields then
				CreatLineItemInstance(
					pCityInstance, Locale.Lookup("LOC_BRS_PROD_BUILDINGS"),
					tFlatYields.YIELD_PRODUCTION, tFlatYields.YIELD_GOLD, tFlatYields.YIELD_FOOD, tFlatYields.YIELD_SCIENCE, tFlatYields.YIELD_CULTURE, tFlatYields.YIELD_FAITH
				); -- this one needs to be stored
			end
		end
		
		-- Flat yields from Modifiers EFFECT_ADJUST_CITY_PRODUCTION_DISTRICT
		if kCityData.CurrentProductionType == "DISTRICT" then
			tFlatYields = GetEmptyYieldsTable();
			bFlatYields = false;
			for _,mod in ipairs(kCityData.Modifiers) do
				if mod.Modifier.EffectType == "EFFECT_ADJUST_CITY_PRODUCTION_DISTRICT" then
					tFlatYields.YIELD_PRODUCTION = tFlatYields.YIELD_PRODUCTION + tonumber(mod.Arguments.Amount);
					bFlatYields = true;
				end
			end
			if bFlatYields then
				CreatLineItemInstance(
					pCityInstance, Locale.Lookup("LOC_BRS_PROD_DISTRICTS"),
					tFlatYields.YIELD_PRODUCTION, tFlatYields.YIELD_GOLD, tFlatYields.YIELD_FOOD, tFlatYields.YIELD_SCIENCE, tFlatYields.YIELD_CULTURE, tFlatYields.YIELD_FAITH
				); -- this one needs to be stored
			end
		end
		
		-- Flat yields from Modifiers EFFECT_ADJUST_CITY_PRODUCTION_UNIT
		if kCityData.CurrentProductionType == "UNIT" then
			tFlatYields = GetEmptyYieldsTable();
			bFlatYields = false;
			for _,mod in ipairs(kCityData.Modifiers) do
				if mod.Modifier.EffectType == "EFFECT_ADJUST_CITY_PRODUCTION_UNIT" then
					tFlatYields.YIELD_PRODUCTION = tFlatYields.YIELD_PRODUCTION + tonumber(mod.Arguments.Amount);
					bFlatYields = true;
				end
			end
			if bFlatYields then
				CreatLineItemInstance(
					pCityInstance, Locale.Lookup("LOC_BRS_PROD_UNITS"),
					tFlatYields.YIELD_PRODUCTION, tFlatYields.YIELD_GOLD, tFlatYields.YIELD_FOOD, tFlatYields.YIELD_SCIENCE, tFlatYields.YIELD_CULTURE, tFlatYields.YIELD_FAITH
				); -- this one needs to be stored
			end
		end
		
		-- Religious followers EFFECT_ADJUST_FOLLOWER_YIELD_MODIFIER
		local tFollowersModifiers:table = GetEmptyYieldsTable(); -- not yields, but stores numbers anyway
		local bShowFollowers:boolean = false;
		for _,mod in ipairs(kCityData.Modifiers) do
			if mod.Modifier.EffectType == "EFFECT_ADJUST_FOLLOWER_YIELD_MODIFIER" then
				tFollowersModifiers[ mod.Arguments.YieldType ] = tFollowersModifiers[ mod.Arguments.YieldType ] + tonumber(mod.Arguments.Amount);
				bShowFollowers = true;
			end
		end
		--print("MOD from FOLLOWERS"); for k,v in pairs(tFollowersModifiers) do print(k,v); end
		if bShowFollowers then
			CreatLineItemInstance(	pCityInstance,
									Locale.Lookup("LOC_UI_RELIGION_FOLLOWERS")..string.format("  [COLOR_White]%d[ENDCOLOR]", kCityData.MajorityReligionFollowers),
									kBaseYields.YIELD_PRODUCTION * tFollowersModifiers.YIELD_PRODUCTION * kCityData.MajorityReligionFollowers / 100.0,
									kBaseYields.YIELD_GOLD       * tFollowersModifiers.YIELD_GOLD       * kCityData.MajorityReligionFollowers / 100.0,
									kBaseYields.YIELD_FOOD       * tFollowersModifiers.YIELD_FOOD       * kCityData.MajorityReligionFollowers / 100.0,
									kBaseYields.YIELD_SCIENCE    * tFollowersModifiers.YIELD_SCIENCE    * kCityData.MajorityReligionFollowers / 100.0,
									kBaseYields.YIELD_CULTURE    * tFollowersModifiers.YIELD_CULTURE    * kCityData.MajorityReligionFollowers / 100.0,
									kBaseYields.YIELD_FAITH      * tFollowersModifiers.YIELD_FAITH      * kCityData.MajorityReligionFollowers / 100.0,
									true); -- don't store in base yields, we'll need it for other rows
		end
		
		-- Percentage scaled yields from Modifiers EFFECT_ADJUST_CITY_YIELD_MODIFIER
		local tPercYields:table = GetEmptyYieldsTable();
		local bPercYields:boolean = false;
		for _,mod in ipairs(kCityData.Modifiers) do
			if mod.Modifier.EffectType == "EFFECT_ADJUST_CITY_YIELD_MODIFIER" then
				if tonumber(mod.Arguments.Amount) == nil then
					-- 2020-05-29 Special case for Maya civ - yields and percentages are encoded in a single argument as a group of values delimited with comma
					local yields:table, percentages:table = {}, {};
					for str in string.gmatch( mod.Arguments.YieldType, "[_%a]+" ) do table.insert(yields,      str) end
					for str in string.gmatch( mod.Arguments.Amount,    "-?%d+" )  do table.insert(percentages, str) end
					if #yields == #percentages then -- extra precaution for mods
						for i,yield in ipairs(yields) do
							tPercYields[ yield ] = tPercYields[ yield ] + tonumber(percentages[i]);
						end
					end
					--dshowtable(yields); dshowtable(percentages); dshowtable(tPercYields); -- debug
				else
					tPercYields[ mod.Arguments.YieldType ] = tPercYields[ mod.Arguments.YieldType ] + tonumber(mod.Arguments.Amount);
				end
				bPercYields = true;
			end
		end
		--print("MOD from PERC YIELDS", cityName); for k,v in pairs(tPercYields) do print(k,v); end
		if bPercYields then
			CreatLineItemInstance(	pCityInstance,
									Locale.Lookup("LOC_BRS_FROM_MODIFIERS_PERCENT"),
									kBaseYields.YIELD_PRODUCTION * tPercYields.YIELD_PRODUCTION / 100.0,
									kBaseYields.YIELD_GOLD       * tPercYields.YIELD_GOLD       / 100.0,
									kBaseYields.YIELD_FOOD       * tPercYields.YIELD_FOOD       / 100.0,
									kBaseYields.YIELD_SCIENCE    * tPercYields.YIELD_SCIENCE    / 100.0,
									kBaseYields.YIELD_CULTURE    * tPercYields.YIELD_CULTURE    / 100.0,
									kBaseYields.YIELD_FAITH      * tPercYields.YIELD_FAITH      / 100.0,
									true); -- don't store in base yields, we'll need it for other rows
		end

		-- Yields from Amenities -- Infixo TOTALLY WRONG amenities are applied to all yields, not only Worked Tiles; also must be the LAST calculated entry
		--local iYieldPercent = (Round(1 + (kCityData.HappinessNonFoodYieldModifier/100), 2)*.1); -- Infixo Buggy formula
		local fYieldPercent:number = kCityData.HappinessNonFoodYieldModifier/100.0;
		local sModifierColor:string;
		if     kCityData.HappinessNonFoodYieldModifier == 0 then sModifierColor = "COLOR_White";
		elseif kCityData.HappinessNonFoodYieldModifier  > 0 then sModifierColor = "COLOR_Green";
		else                                                     sModifierColor = "COLOR_Red"; -- <0
		end
		local lineInstance:table = CreatLineItemInstance(	pCityInstance,
								Locale.Lookup("LOC_HUD_REPORTS_HEADER_AMENITIES")..string.format("  ["..sModifierColor.."]%+d%%[ENDCOLOR]", kCityData.HappinessNonFoodYieldModifier),
								kBaseYields.YIELD_PRODUCTION * fYieldPercent,
								kBaseYields.YIELD_GOLD * fYieldPercent,
								0,
								kBaseYields.YIELD_SCIENCE * fYieldPercent,
								kBaseYields.YIELD_CULTURE * fYieldPercent,
								kBaseYields.YIELD_FAITH * fYieldPercent,
								true); -- don't store in base yields, we'll need it for other rows
		-- show base yields in the tooltips
		lineInstance.Production:SetToolTipString( kBaseYields.YIELD_PRODUCTION );
		lineInstance.Gold:SetToolTipString( kBaseYields.YIELD_GOLD );
		lineInstance.Science:SetToolTipString( kBaseYields.YIELD_SCIENCE );
		lineInstance.Culture:SetToolTipString( kBaseYields.YIELD_CULTURE );
		lineInstance.Faith:SetToolTipString( kBaseYields.YIELD_FAITH );

		pCityInstance.LineItemStack:CalculateSize();
		pCityInstance.Darken:SetSizeY( pCityInstance.LineItemStack:GetSizeY() + DARKEN_CITY_INCOME_AREA_ADDITIONAL_Y );
		pCityInstance.Top:ReprocessAnchoring();
		end --BRS if HideCityBuildingsCheckbox:IsSelected
	end

	local pFooterInstance:table = {};
	ContextPtr:BuildInstanceForControl("CityIncomeFooterInstance", pFooterInstance, instance.ContentStack  );
	pFooterInstance.Gold:SetText( "[Icon_GOLD]"..toPlusMinusString(goldCityTotal) );
	pFooterInstance.Faith:SetText( "[Icon_FAITH]"..toPlusMinusString(faithCityTotal) );
	pFooterInstance.Science:SetText( "[Icon_SCIENCE]"..toPlusMinusString(scienceCityTotal) );
	pFooterInstance.Culture:SetText( "[Icon_CULTURE]"..toPlusMinusString(cultureCityTotal) );
	pFooterInstance.Tourism:SetText( "[Icon_TOURISM]"..toPlusMinusString(tourismCityTotal) );

	SetGroupCollapsePadding(instance, pFooterInstance.Top:GetSizeY() );
	RealizeGroup( instance );

	-- ========== Building Expenses ==========

	--BRS It displays a long list with multiple same entries - no fun at all
	-- Collapse it in the same way as Units, i.e. show Name / Count / Gold
	local kBuildingExpenses:table = {};
	for cityName,kCityData in pairs(m_kCityData) do
		for _,kDistrict in ipairs(kCityData.BuildingsAndDistricts) do
			local key = kDistrict.Name;
			-- GS change: don't count pillaged districts and must be built
			if kDistrict.isPillaged == false and kDistrict.isBuilt == true then
				if kBuildingExpenses[key] == nil then kBuildingExpenses[key] = { Count = 0, Maintenance = 0 }; end -- init entry
				kBuildingExpenses[key].Count       = kBuildingExpenses[key].Count + 1;
				kBuildingExpenses[key].Maintenance = kBuildingExpenses[key].Maintenance + kDistrict.Maintenance;
			end
            -- 2021-05-18 fix for missing Maintenance data
            for _,kBuilding in ipairs(kDistrict.Buildings) do
                kBuilding.Maintenance = 0;
                if GameInfo.Buildings[kBuilding.Type] then
                    kBuilding.Maintenance = GameInfo.Buildings[kBuilding.Type].Maintenance;
                end
                --dshowtable(kBuilding); -- debug
                local key = kBuilding.Name;
                -- GS change: don't count pillaged buildings
                if kBuilding.isPillaged == false then
                    if kBuildingExpenses[key] == nil then kBuildingExpenses[key] = { Count = 0, Maintenance = 0 }; end -- init entry
                    kBuildingExpenses[key].Count       = kBuildingExpenses[key].Count + 1;
                    kBuildingExpenses[key].Maintenance = kBuildingExpenses[key].Maintenance + kBuilding.Maintenance;
                end
            end
		end
        --[[
		for _,kBuilding in ipairs(kCityData.Buildings) do
            dshowtable(kBuilding); -- debug
			local key = kBuilding.Name;
			-- GS change: don't count pillaged buildings
			if kBuilding.isPillaged == false then
				if kBuildingExpenses[key] == nil then kBuildingExpenses[key] = { Count = 0, Maintenance = 0 }; end -- init entry
				kBuildingExpenses[key].Count       = kBuildingExpenses[key].Count + 1;
				kBuildingExpenses[key].Maintenance = kBuildingExpenses[key].Maintenance + kBuilding.Maintenance;
			end
		end
        --]]
	end
	--BRS sort by name here somehow?
	
	instance = NewCollapsibleGroupInstance();
	instance.RowHeaderButton:SetText( Locale.Lookup("LOC_HUD_REPORTS_ROW_BUILDING_EXPENSES") );
	instance.RowHeaderLabel:SetHide( true ); --BRS
	instance.AmenitiesContainer:SetHide(true);
	instance.IndustryContainer:SetHide(true); -- 2021-05-21
	instance.MonopolyContainer:SetHide(true); -- 2021-05-21

	-- Header
	local pHeader:table = {};
	ContextPtr:BuildInstanceForControl( "BuildingExpensesHeaderInstance", pHeader, instance.ContentStack ) ;

	-- Buildings
	local iTotalBuildingMaintenance :number = 0;
	local bHideFreeBuildings:boolean = Controls.HideFreeBuildingsCheckbox:IsSelected(); --BRS
	for sName, data in spairs( kBuildingExpenses, function( t, a, b ) return Locale.Lookup(a) < Locale.Lookup(b) end ) do -- sorting by name (key)
		if data.Maintenance ~= 0 or not bHideFreeBuildings then
			local pBuildingInstance:table = {};
			ContextPtr:BuildInstanceForControl( "BuildingExpensesEntryInstance", pBuildingInstance, instance.ContentStack );
			TruncateStringWithTooltip(pBuildingInstance.BuildingName, 224, Locale.Lookup(sName)); 
			pBuildingInstance.BuildingCount:SetText( Locale.Lookup(data.Count) );
			pBuildingInstance.Gold:SetText( data.Maintenance == 0 and "0" or "-"..tostring(data.Maintenance));
			iTotalBuildingMaintenance = iTotalBuildingMaintenance - data.Maintenance;
		end
	end

	-- Footer
	local pBuildingFooterInstance:table = {};		
	ContextPtr:BuildInstanceForControl( "GoldFooterInstance", pBuildingFooterInstance, instance.ContentStack ) ;		
	pBuildingFooterInstance.Gold:SetText("[ICON_Gold]"..tostring(iTotalBuildingMaintenance) );

	SetGroupCollapsePadding(instance, pBuildingFooterInstance.Top:GetSizeY() );
	RealizeGroup( instance );

	-- ========== Unit Expenses ==========

	if GameCapabilities.HasCapability("CAPABILITY_REPORTS_UNIT_EXPENSES") then 
		instance = NewCollapsibleGroupInstance();
		instance.RowHeaderButton:SetText( Locale.Lookup("LOC_HUD_REPORTS_ROW_UNIT_EXPENSES") );
		instance.RowHeaderLabel:SetHide( true ); --BRS
		instance.AmenitiesContainer:SetHide(true);
        instance.IndustryContainer:SetHide(true); -- 2021-05-21
        instance.MonopolyContainer:SetHide(true); -- 2021-05-21

		-- Header
		local pHeader:table = {};
		ContextPtr:BuildInstanceForControl( "UnitExpensesHeaderInstance", pHeader, instance.ContentStack ) ;

		-- Units
		local iTotalUnitMaintenance:number = 0;
		local bHideFreeUnits:boolean = Controls.HideFreeUnitsCheckbox:IsSelected(); --BRS
		-- sort units by name field, which already contains a localized name, and by military formation
		for _,kUnitData in spairs( m_kUnitData, function(t,a,b) if t[a].Name == t[b].Name then return t[a].Formation < t[b].Formation else return t[a].Name < t[b].Name end end ) do
			if kUnitData.Maintenance ~= 0 or not bHideFreeUnits then
				local pUnitInstance:table = {};
				ContextPtr:BuildInstanceForControl( "UnitExpensesEntryInstance", pUnitInstance, instance.ContentStack );
				if     kUnitData.Formation == MilitaryFormationTypes.CORPS_FORMATION then pUnitInstance.UnitName:SetText(kUnitData.Name.." [ICON_Corps]");
				elseif kUnitData.Formation == MilitaryFormationTypes.ARMY_FORMATION  then pUnitInstance.UnitName:SetText(kUnitData.Name.." [ICON_Army]");
				else                                                                      pUnitInstance.UnitName:SetText(kUnitData.Name); end
				pUnitInstance.UnitCount:SetText(kUnitData.Count);
				pUnitInstance.Gold:SetText( kUnitData.Maintenance == 0 and "0" or "-"..tostring(kUnitData.Maintenance) );
				if bIsGatheringStorm and kUnitData.ResCount > 0 then
					pUnitInstance.UnitCount:SetText( kUnitData.Count..string.format(" /-%d%s", kUnitData.ResCount, kUnitData.ResIcon) );
				end
				iTotalUnitMaintenance = iTotalUnitMaintenance - kUnitData.Maintenance;
			end
		end

		-- Footer
		local pUnitFooterInstance:table = {};		
		ContextPtr:BuildInstanceForControl( "GoldFooterInstance", pUnitFooterInstance, instance.ContentStack ) ;		
		pUnitFooterInstance.Gold:SetText("[ICON_Gold]"..tostring(iTotalUnitMaintenance) );

		SetGroupCollapsePadding(instance, pUnitFooterInstance.Top:GetSizeY() );
		RealizeGroup( instance );
	end

	-- ========== Diplomatic Deals Expenses ==========
	
	if GameCapabilities.HasCapability("CAPABILITY_REPORTS_DIPLOMATIC_DEALS") then 
		instance = NewCollapsibleGroupInstance();	
		instance.RowHeaderButton:SetText( Locale.Lookup("LOC_HUD_REPORTS_ROW_DIPLOMATIC_DEALS") );
		instance.RowHeaderLabel:SetHide( true ); --BRS
		instance.AmenitiesContainer:SetHide(true);
        instance.IndustryContainer:SetHide(true); -- 2021-05-21
        instance.MonopolyContainer:SetHide(true); -- 2021-05-21

		local pHeader:table = {};
		ContextPtr:BuildInstanceForControl( "DealHeaderInstance", pHeader, instance.ContentStack ) ;

		local iTotalDealGold :number = 0;
		for i,kDeal in ipairs(m_kDealData) do
			if kDeal.Type == DealItemTypes.GOLD then
				local pDealInstance:table = {};		
				ContextPtr:BuildInstanceForControl( "DealEntryInstance", pDealInstance, instance.ContentStack ) ;		

				pDealInstance.Civilization:SetText( kDeal.Name );
				pDealInstance.Duration:SetText( kDeal.Duration );
				if kDeal.IsOutgoing then
					pDealInstance.Gold:SetText( "-"..tostring(kDeal.Amount) );
					iTotalDealGold = iTotalDealGold - kDeal.Amount;
				else
					pDealInstance.Gold:SetText( "+"..tostring(kDeal.Amount) );
					iTotalDealGold = iTotalDealGold + kDeal.Amount;
				end
			end
		end
		local pDealFooterInstance:table = {};		
		ContextPtr:BuildInstanceForControl( "GoldFooterInstance", pDealFooterInstance, instance.ContentStack ) ;		
		pDealFooterInstance.Gold:SetText("[ICON_Gold]"..tostring(iTotalDealGold) );

		SetGroupCollapsePadding(instance, pDealFooterInstance.Top:GetSizeY() );
		RealizeGroup( instance );
	end


	-- ========== TOTALS ==========

	Controls.Stack:CalculateSize();
	Controls.Scroll:CalculateSize();

	-- Totals at the bottom [Definitive values]
	local localPlayer = Players[Game.GetLocalPlayer()];
	--Gold
	local playerTreasury:table	= localPlayer:GetTreasury();
	Controls.GoldIncome:SetText( toPlusMinusNoneString( playerTreasury:GetGoldYield() ));
	Controls.GoldExpense:SetText( toPlusMinusNoneString( -playerTreasury:GetTotalMaintenance() ));	-- Flip that value!
	Controls.GoldNet:SetText( toPlusMinusNoneString( playerTreasury:GetGoldYield() - playerTreasury:GetTotalMaintenance() ));
	Controls.GoldBalance:SetText( m_kCityTotalData.Treasury[YieldTypes.GOLD] );

	
	--Faith
	local playerReligion:table	= localPlayer:GetReligion();
	Controls.FaithIncome:SetText( toPlusMinusNoneString(playerReligion:GetFaithYield()));
	Controls.FaithNet:SetText( toPlusMinusNoneString(playerReligion:GetFaithYield()));
	Controls.FaithBalance:SetText( m_kCityTotalData.Treasury[YieldTypes.FAITH] );

	--Science
	local playerTechnology:table	= localPlayer:GetTechs();
	Controls.ScienceIncome:SetText( toPlusMinusNoneString(playerTechnology:GetScienceYield()));
	Controls.ScienceBalance:SetText( m_kCityTotalData.Treasury[YieldTypes.SCIENCE] );
	
	--Culture
	local playerCulture:table	= localPlayer:GetCulture();
	Controls.CultureIncome:SetText(toPlusMinusNoneString(playerCulture:GetCultureYield()));
	Controls.CultureBalance:SetText(m_kCityTotalData.Treasury[YieldTypes.CULTURE] );
	
	--Tourism. We don't talk about this one much.
	Controls.TourismIncome:SetText( toPlusMinusNoneString( m_kCityTotalData.Income["TOURISM"] ));	
	Controls.TourismBalance:SetText( m_kCityTotalData.Treasury["TOURISM"] );
	
	Controls.CollapseAll:SetHide( false );
	Controls.BottomYieldTotals:SetHide( false ); -- ViewYieldsPage
	Controls.BottomYieldTotals:SetSizeY( SIZE_HEIGHT_BOTTOM_YIELDS );
	Controls.BottomResourceTotals:SetHide( true );
	Controls.BottomPoliciesFilters:SetHide( true );
	Controls.BottomMinorsFilters:SetHide( true );
	Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - (Controls.BottomYieldTotals:GetSizeY() + SIZE_HEIGHT_PADDING_BOTTOM_ADJUST ) );	
	-- Remember this tab when report is next opened: ARISTOS
	m_kCurrentTab = 1;
end

-- ===========================================================================
-- CHECKBOXES
-- ===========================================================================

-- Checkboxes for hiding city details and free units/buildings

function OnToggleHideCityBuildings() -- this is actually "Hide City Details"
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

-- ===========================================================================
function InitializeYields()
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
end

print("BRS: Loaded file BRSPage_Yields.lua");
