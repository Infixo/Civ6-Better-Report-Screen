-- ===========================================================================
-- Better Report Screen - page Cities2
-- Author: Infixo
-- 2023-05-10: Created
-- ===========================================================================

m_kCity2Data = nil; -- global for debug purposes

-- ===========================================================================
-- Gathering Storm City Data

local tPowerImprovements:table = {
	IMPROVEMENT_GEOTHERMAL_PLANT   = 4, -- GEOTHERMAL_GENERATE_POWER
	IMPROVEMENT_SOLAR_FARM         = 2, -- SOLAR_FARM_GENERATE_POWER
	IMPROVEMENT_WIND_FARM          = 2, -- WIND_FARM_GENERATE_POWER
	IMPROVEMENT_OFFSHORE_WIND_FARM = 2, -- OFFSHORE_WIND_FARM_GENERATE_POWER
};
-- fill improvements from MODIFIER_SINGLE_CITY_ADJUST_FREE_POWER modifiers
function InitializePowerImprovements()
end

local tPowerBuildings:table = {
	BUILDING_COAL_POWER_PLANT        = 4, --RESOURCE_COAL
	BUILDING_FOSSIL_FUEL_POWER_PLANT = 4, --RESOURCE_OIL
	BUILDING_POWER_PLANT             =16, --RESOURCE_URANIUM
	--BUILDING_HYDROELECTRIC_DAM       = 6, -- separately
};
-- fill buildings from Buildings_XP2 and MODIFIER_SINGLE_CITY_ADJUST_FREE_POWER modifiers
function InitializePowerBuildings()
end

-- Re: Power from CityPanelPower
-- Consumed - these are sources that give power - here PowerProduced!
-- Required - these are buildings that require power - here PowerConsumed!
-- Generated - seems to be empty

--2021-05-13 Monopolies and Corporations
local eImprovementIndustry:number    = -1;
local eImprovementCorporation:number = -1;
if bIsMonopolies then
    eImprovementIndustry    = GameInfo.Improvements.IMPROVEMENT_INDUSTRY.Index;
    eImprovementCorporation = GameInfo.Improvements.IMPROVEMENT_CORPORATION.Index;
end

-- ===========================================================================
function GetDataCities2()
	print("GetDataCities2");
	
	local playerID	:number = Game.GetLocalPlayer();
	if playerID == PlayerTypes.NONE or playerID == PlayerTypes.OBSERVER then
		UI.DataError("Unable to get valid playerID for report screen.");
		return;
	end

	m_kCity2Data = {}; -- reset the main table

	for _,pCity in Players[playerID]:GetCities():Members() do
		local cityName	:string = pCity:GetName();
		--print("city", cityName);
		-- Big calls, obtain city data and add report specific fields to it.
		local data: table = GetCityData( pCity );
		if bIsGatheringStorm then AppendXP2CityData(data); end
		m_kCity2Data[cityName] = data;
	end
end

function AppendXP2CityData(data:table)
	--print("AppendXP2CityData");
	-- data is the main city data record filled with tons of info

	local pCity:table = data.City;
	local pCityPower:table = pCity:GetPower();

	-- Power consumption [icon required_number / consumed_number]
	data.IsUnderpowered = false;
	data.PowerIcon = "";
	data.PowerRequired = 0;
	data.PowerConsumed = 0;
	data.PowerConsumedTT = {};

	-- Power: Status from CityPanelPower
	local freePower:number = pCityPower:GetFreePower();
	local temporaryPower:number = pCityPower:GetTemporaryPower();
	local currentPower:number = freePower + temporaryPower;
	local requiredPower:number = pCityPower:GetRequiredPower();
	local powerStatusName:string = "LOC_POWER_STATUS_POWERED_NAME"; -- [ICON_Power] Powered
	local powerStatusDescription:string = "LOC_POWER_STATUS_POWERED_DESCRIPTION"; -- Buildings or Projects which require [ICON_Power] Power are fully effective.
	data.PowerIcon = "[ICON_Power]";
	if (requiredPower == 0) then
		powerStatusName = "LOC_POWER_STATUS_NO_POWER_NEEDED_NAME"; -- Normal
		powerStatusDescription = "LOC_POWER_STATUS_NO_POWER_NEEDED_DESCRIPTION"; -- This city does not require any [ICON_Power] Power.
		data.PowerIcon = "";
	elseif (not pCityPower:IsFullyPowered()) then
		powerStatusName = "LOC_POWER_STATUS_UNPOWERED_NAME"; -- [ICON_PowerInsufficient] Unpowered
		powerStatusDescription = "LOC_POWER_STATUS_UNPOWERED_DESCRIPTION";
		data.PowerIcon = "[ICON_PowerInsufficient]";
		data.IsUnderpowered = true;
	elseif (pCityPower:IsFullyPoweredByActiveProject()) then
		currentPower = requiredPower;
		data.PowerIcon = "[ICON_Power][COLOR_Green]![ENDCOLOR]"
	end
	
	table.insert(data.PowerConsumedTT, Locale.Lookup(powerStatusName));
	table.insert(data.PowerConsumedTT, Locale.Lookup(powerStatusDescription));
	
	----Required from CityPanelPower.lua
	if requiredPower > 0 then
		table.insert(data.PowerConsumedTT, "");
		table.insert(data.PowerConsumedTT, Locale.Lookup("LOC_POWER_PANEL_REQUIRED_POWER")); --..Round(requiredPower, 1)); -- [SIZE:16]{1_PowerAmount} [SIZE:12]Required
	end
	local requiredPowerBreakdown:table = pCityPower:GetRequiredPowerSources();
	for _,innerTable in ipairs(requiredPowerBreakdown) do
		local scoreSource, scoreValue = next(innerTable);
		table.insert(data.PowerConsumedTT, string.format("[ICON_Bullet]%d[ICON_Power] %s", scoreValue, scoreSource));
	end

	-----Consumed from CityPanelPower.lua
	if currentPower > 0 then
		table.insert(data.PowerConsumedTT, "");
		table.insert(data.PowerConsumedTT, Locale.Lookup("LOC_POWER_PANEL_CONSUMED_POWER")); --..Round(currentPower, 1)); -- [SIZE:16]{1_PowerAmount} [SIZE:12]Consumed
	end
	local temporaryPowerBreakdown:table = pCityPower:GetTemporaryPowerSources();
	for _,innerTable in ipairs(temporaryPowerBreakdown) do
		local scoreSource, scoreValue = next(innerTable);
		table.insert(data.PowerConsumedTT, string.format("[ICON_Bullet]%d[ICON_Power] %s", scoreValue, scoreSource));
	end
	local freePowerBreakdown:table = pCityPower:GetFreePowerSources();
	for _,innerTable in ipairs(freePowerBreakdown) do
		local scoreSource, scoreValue = next(innerTable);
		table.insert(data.PowerConsumedTT, string.format("[ICON_Bullet]%d[ICON_Power] %s", scoreValue, scoreSource));
	end
	
	data.PowerRequired = requiredPower;
	data.PowerConsumed = currentPower;
	data.PowerConsumedTT = table.concat(data.PowerConsumedTT, "[NEWLINE]");
	
	-- Power produced [number]
	-- buildings, improvements. Details in tooltip.
	data.PowerProduced = 0; -- sort by
	data.PowerProducedTT = {}; -- list of buildings and improvements
	data.PowerPlantResType = "Bullet";
	data.PowerPlantResUsed = 0;
	-- Resource_Consumption.PowerProvided
	table.insert(data.PowerProducedTT, Locale.Lookup("LOC_POWER_PANEL_GENERATED_POWER")); --..Round(data.PowerProduced, 1)); -- [SIZE:16]{1_PowerAmount} [SIZE:12]Required
	-- buildings
	for building,power in pairs(tPowerBuildings) do
		if GameInfo.Buildings[building] ~= nil and pCity:GetBuildings():HasBuilding( GameInfo.Buildings[building].Index ) then
			--data.PowerProduced = data.PowerProduced + power;
			data.PowerPlantResType = GameInfo.Buildings_XP2[building].ResourceTypeConvertedToPower;
			table.insert(data.PowerProducedTT, string.format("[ICON_Bullet][ICON_%s]%s", data.PowerPlantResType, Locale.Lookup(GameInfo.Buildings[building].Name)));
			break; -- there can be only one!
		end
	end
	-----Generated from CityPanelPower
	local generatedPowerBreakdown:table = pCityPower:GetGeneratedPowerSources();
	--if #generatedPowerBreakdown > 0 then
	--end
	local iPlantPower:number = 0;
	for _,innerTable in ipairs(generatedPowerBreakdown) do
		local scoreSource, scoreValue = next(innerTable);
		--print("powerplant", data.PowerPlantRes, "score", scoreSource, scoreValue);
		table.insert(data.PowerProducedTT, string.format("[ICON_Bullet]%s [ICON_Power]%d", scoreSource, scoreValue));
		if string.find(scoreSource, data.PowerPlantResType) ~= nil then
			iPlantPower = iPlantPower + scoreValue; -- sum up all places where power goes
		end
	end
	-- calculate how many resources are consumed
	if data.PowerPlantResType ~= "Bullet" then
		local iPowerProvided:number = GameInfo.Resource_Consumption[data.PowerPlantResType].PowerProvided;
		data.PowerPlantResUsed = math.floor(iPlantPower/iPowerProvided);
		if data.PowerPlantResUsed * iPowerProvided < iPlantPower then data.PowerPlantResUsed = data.PowerPlantResUsed + 1; end
		data.PowerProduced = data.PowerProduced + data.PowerPlantResUsed * iPowerProvided;
		table.insert(data.PowerProducedTT, string.format("[ICON_Bullet]%s %d[ICON_%s] [Icon_GoingTo] %d[ICON_Power]",
			Locale.Lookup("LOC_UI_PEDIA_POWER_COST"),
			data.PowerPlantResUsed, data.PowerPlantResType,
			data.PowerPlantResUsed * iPowerProvided));
	end
	
	-- treat Hydroelectric Dam separately for now
	if GameInfo.Buildings.BUILDING_HYDROELECTRIC_DAM ~= nil and pCity:GetBuildings():HasBuilding( GameInfo.Buildings.BUILDING_HYDROELECTRIC_DAM.Index ) then
		local power = 6;
		data.PowerProduced = data.PowerProduced + power;
		table.insert(data.PowerProducedTT, string.format("[ICON_Bullet]%d[ICON_Power] %s", power, Locale.Lookup(GameInfo.Buildings.BUILDING_HYDROELECTRIC_DAM.Name)));
	end
	-- support for Hydroelectric Dam Upgrade from RBU
	if GameInfo.Buildings.BUILDING_HYDROELECTRIC_DAM_UPGRADE ~= nil and pCity:GetBuildings():HasBuilding( GameInfo.Buildings.BUILDING_HYDROELECTRIC_DAM_UPGRADE.Index ) then
		local power = 2;
		data.PowerProduced = data.PowerProduced + power;
		table.insert(data.PowerProducedTT, string.format("[ICON_Bullet]%d[ICON_Power] %s", power, Locale.Lookup(GameInfo.Buildings.BUILDING_HYDROELECTRIC_DAM_UPGRADE.Name)));
	end
	
	-- Cities: CO2 footprint calculation? Is it possible?
	--"Resource_Consumption" table has a field "CO2perkWh" INTEGER NOT NULL DEFAULT 0,
	--GameClimate.GetPlayerResourceCO2Footprint( m_playerID, kResourceInfo.Index );
	data.CO2Footprint = 0; -- must be calculated manually; sort by
	data.CO2FootprintTT = "";
	if data.PowerPlantResUsed > 0 then
		local resConsInfo = GameInfo.Resource_Consumption[data.PowerPlantResType];
		data.CO2Footprint = data.PowerPlantResUsed * resConsInfo.PowerProvided * resConsInfo.CO2perkWh / 1000;
		data.CO2FootprintTT = string.format("%d[ICON_%s] @ %d", data.PowerPlantResUsed, data.PowerPlantResType, resConsInfo.CO2perkWh);
	end

	-- Cities: Nuclear power plant [risk_icon / nuclear icon / num turns]
	data.HasNuclearPowerPlant = false;
	if GameInfo.Buildings["BUILDING_POWER_PLANT"] ~= nil and pCity:GetBuildings():HasBuilding( GameInfo.Buildings["BUILDING_POWER_PLANT"].Index ) then data.HasNuclearPowerPlant = true; end
	data.ReactorAge = -1;
	data.NuclearAccidentIcon = "[ICON_CheckmarkBlue]";
	data.NuclearPowerPlantTT = {};
	
	-- code from ToolTipLoader_Expansion2
	local kFalloutManager = Game.GetFalloutManager();
	local iReactorAge:number = kFalloutManager:GetReactorAge(pCity);
	if (iReactorAge ~= nil) then
		data.ReactorAge = iReactorAge;
		table.insert(data.NuclearPowerPlantTT, Locale.Lookup("LOC_TOOLTIP_PROJECT_REACTOR_AGE", iReactorAge));
	end
	local iAccidentThreshold:number = kFalloutManager:GetReactorAccidentThreshold(pCity);
	if (iAccidentThreshold ~= nil) then
		if (iAccidentThreshold > 0) then
			data.NuclearAccidentIcon = "[COLOR_Red]![ENDCOLOR]";
			table.insert(data.NuclearPowerPlantTT, Locale.Lookup("LOC_TOOLTIP_PROJECT_REACTOR_ACCIDENT1_POSSIBLE"));
		end
		if (iAccidentThreshold > 1) then
			data.NuclearAccidentIcon = "[COLOR_Red]!![ENDCOLOR]";
			table.insert(data.NuclearPowerPlantTT, Locale.Lookup("LOC_TOOLTIP_PROJECT_REACTOR_ACCIDENT2_POSSIBLE"));
		end
		if (iAccidentThreshold > 2) then
			data.NuclearAccidentIcon = "[COLOR_Red]!!![ENDCOLOR]";
			table.insert(data.NuclearPowerPlantTT, Locale.Lookup("LOC_TOOLTIP_PROJECT_REACTOR_ACCIDENT3_POSSIBLE"));
		end
	end
	data.NuclearPowerPlantTT = table.concat(data.NuclearPowerPlantTT, "[NEWLINE]");

	-- Dam district & Flood info [num tiles / dam icon]
	-- Flood indicator, dam yes/no.
	data.NumRiverFloodTiles = 0; -- sort by
	data.HasDamDistrict = HasCityDistrict(data, "DISTRICT_DAM");
	data.RiverFloodDamTT = {};

	-- Info about Flood barrier. [num tiles / flood barrier icon]
	-- Num of endangered tiles, per level. Tooltip - info about features (improvement, district, etc).
	data.NumFloodTiles = 0; -- sort by
	data.HasFloodBarrier = false; 
	if GameInfo.Buildings["BUILDING_FLOOD_BARRIER"] ~= nil and pCity:GetBuildings():HasBuilding( GameInfo.Buildings["BUILDING_FLOOD_BARRIER"].Index ) then data.HasFloodBarrier = true; end
	data.FloodTilesTT = {};

	-- Flood Barrier Per turn maintenance. [number]
	-- probably manually calculated?
	local iBaseMaintenance:number = 0;
	if GameInfo.Buildings.BUILDING_FLOOD_BARRIER ~= nil then iBaseMaintenance = GameInfo.Buildings.BUILDING_FLOOD_BARRIER.Maintenance; end
	data.FloodBarrierMaintenance = 0;
	data.FloodBarrierMaintenanceTT = "";
	
	-- from ClimateScreen.lua
	local m_firstSeaLevelEvent = -1;
	local m_currentSeaLevelEvent, m_currentSeaLevelPhase = -1, 0;
	local iCurrentClimateChangePoints = GameClimate.GetClimateChangeForLastSeaLevelEvent();
	for row in GameInfo.RandomEvents() do
		if (row.EffectOperatorType == "SEA_LEVEL") then
			if (m_firstSeaLevelEvent == -1) then
				m_firstSeaLevelEvent = row.Index;
			end
			if (row.ClimateChangePoints == iCurrentClimateChangePoints) then
				m_currentSeaLevelEvent = row.Index; 
				m_currentSeaLevelPhase = m_currentSeaLevelEvent - m_firstSeaLevelEvent + 1;
			end
		end
	end
	
	-- Cities: Number of RR tiles in the city borders [number]
	-- this seems easy - iterate through tiles and use Plot:GetRouteType()
	data.NumRailroads = 0; -- sort by
	data.NumRailroadsTT = "";
	
	-- iterate through city plots and check tiles
	local cityPlots:table = Map.GetCityPlots():GetPurchasedPlots(pCity);
	for _, plotID in ipairs(cityPlots) do
		local plot:table = Map.GetPlotByIndex(plotID);
		local plotX			: number = plot:GetX()
		local plotY			: number = plot:GetY()
		-- power sources from improvements
		-- they are all done via modifiers - add later more dynamic approach
		local eImprovementType:number = plot:GetImprovementType();
		if eImprovementType > -1 then
			local imprInfo:table = GameInfo.Improvements[eImprovementType];
			if imprInfo ~= nil and tPowerImprovements[imprInfo.ImprovementType] ~= nil then
				if plot:IsImprovementPillaged() then
					table.insert(data.PowerProducedTT, string.format("[ICON_Bullet]%d[ICON_Power] %s %s", 0, Locale.Lookup(imprInfo.Name), Locale.Lookup("LOC_TOOLTIP_PLOT_PILLAGED_TEXT")));
				else
					data.PowerProduced = data.PowerProduced + tPowerImprovements[imprInfo.ImprovementType];
					table.insert(data.PowerProducedTT, string.format("[ICON_Bullet]%d[ICON_Power] %s", tPowerImprovements[imprInfo.ImprovementType], Locale.Lookup(imprInfo.Name)));
				end
 			end
		end
		-- tiles that can be flooded by a river LOC_FLOOD_WARNING_ICON_TOOLTIP
		local function CheckPlotContent(plot:table, tooltip:table, extra:string)
			if plot:GetDistrictType()    ~= -1 then table.insert(tooltip, string.format("%s %s", Locale.Lookup(GameInfo.Districts[plot:GetDistrictType()].Name), extra)); end
			if plot:GetImprovementType() ~= -1 then
				local str = string.format("%s %s", Locale.Lookup(GameInfo.Improvements[plot:GetImprovementType()].Name), extra);
				if plot:GetResourceType() ~= -1 then
					local resource = GameInfo.Resources[plot:GetResourceType()];
					str = "[ICON_"..resource.ResourceType.."]"..Locale.Lookup(resource.Name).." "..str;
				end
				table.insert(tooltip, str);
			end
		end
		if RiverManager.CanBeFlooded(plot) then
			data.NumRiverFloodTiles = data.NumRiverFloodTiles + 1;
			CheckPlotContent(plot, data.RiverFloodDamTT, "");
		end
		-- tiles that can be submerged
		local eCoastalLowland:number = TerrainManager.GetCoastalLowlandType(plot);
		if eCoastalLowland ~= -1 then
			local extra:string = "";
			if TerrainManager.IsFlooded(plot)   then extra = Locale.Lookup("LOC_COASTAL_LOWLAND_FLOODED"); end
			if TerrainManager.IsSubmerged(plot) then extra = Locale.Lookup("LOC_COASTAL_LOWLAND_SUBMERGED"); end
			data.NumFloodTiles = data.NumFloodTiles + 1;
			CheckPlotContent(plot, data.FloodTilesTT, extra);
		end
		-- railroads
		local eRoute:number = plot:GetRouteType()
		if eRoute ~= -1 and GameInfo.Routes[eRoute] ~= nil and GameInfo.Routes[eRoute].RouteType == "ROUTE_RAILROAD" then data.NumRailroads = data.NumRailroads + 1; end
        
	end
	data.RiverFloodDamTT = table.concat(data.RiverFloodDamTT, "[NEWLINE]");
	data.FloodTilesTT = table.concat(data.FloodTilesTT, "[NEWLINE]");
	data.FloodBarrierMaintenance = iBaseMaintenance * (m_currentSeaLevelPhase+1) * data.NumFloodTiles;
	--data.FloodBarrierMaintenanceTT = string.format("%d %d %d", iBaseMaintenance, m_currentSeaLevelPhase, data.NumFloodTiles);
	
	if #data.PowerProducedTT == 1 then data.PowerProducedTT = "";
	else                               data.PowerProducedTT = table.concat(data.PowerProducedTT, "[NEWLINE]"); end
	
	-- Canals
	data.NumCanals = 0;
	for _,district in ipairs(data.BuildingsAndDistricts) do
		if district.isBuilt and district.Type == "DISTRICT_CANAL" then data.NumCanals = data.NumCanals + 1; end
	end
    
    -- 2021-05-21 Monopolies and Corporations Mode
    if bIsMonopolies then
        data.HasIndustry = false;
        data.HasCorporation = false;
        data.Industry = "";
        data.IndustryTT = "";
        local localPlayerID:number = Game.GetLocalPlayer();
        local pGameEconomic:table = Game.GetEconomicManager();
        local sResList:string, sResListTT:string = "", ""; -- resource list - just to see what is possible
        local bHasRes:boolean = false;

        -- iterate through city plots
        for _, plotID in ipairs(cityPlots) do
            local plot:table = Map.GetPlotByIndex(plotID);
            local plotX			: number = plot:GetX()
            local plotY			: number = plot:GetY()
            local eResourceType:number = plot:GetResourceType();
            -- is there a resource at all
            if eResourceType > -1 then
                local resourceInfo:table = GameInfo.Resources[eResourceType];
                local sResourceType:string = resourceInfo.ResourceType;
                if resourceInfo.ResourceClassType == "RESOURCECLASS_LUXURY" and GameInfo.ResourceIndustries[sResourceType] ~= nil then -- also check if there is an industry around it!
                    -- only luxuries are important
                    local sResIcon:string = "[ICON_"..sResourceType.."]";
                    -- find industry effect and type - match [ICON_xxx]
                    local sEffectI:string = LL(GameInfo.ResourceIndustries[sResourceType].ResourceEffectTExt);
                    local sIndustryType:string = string.match(sEffectI, "%[ICON_%a+%]");
                    -- find corporation effect and type - match [ICON_xxx]
                    local sEffectC:string = LL(GameInfo.ResourceCorporations[sResourceType].ResourceEffectTExt);
                    local sCorpoType:string = string.match(sEffectC, "%[ICON_%a+%]");
                    -- check for industry / corpo
                    local eImprovementType:number = plot:GetImprovementType();
                    -- there can be only 1 industry or corpo in a city, so check first for that
                    if eImprovementType == eImprovementCorporation then
                        -- there is a corporation
                        data.HasCorporation = true;
                        data.Industry = string.format("[ICON_%s] %s [ICON_GreatWork_Product]", sResourceType, sCorpoType);
                        data.IndustryTT = string.format("%s[NEWLINE][ICON_%s] %s%s", LL("LOC_IMPROVEMENT_CORPORATION_NAME"), sResourceType, LL(resourceInfo.Name), sEffectC);
                    elseif eImprovementType == eImprovementIndustry then
                        -- there is an industry
                        data.HasIndustry = true;
                        data.Industry = sResIcon..sIndustryType;
                        data.IndustryTT = string.format("%s[NEWLINE]%s %s%s", LL("LOC_IMPROVEMENT_INDUSTRY_NAME"), sResIcon, LL(resourceInfo.Name), sEffectI);
                        -- check if we can upgrade it to corporation
                        if pGameEconomic:CanHaveCorporation(localPlayerID, eResourceType) then
                            data.Industry = data.Industry.."[COLOR_Green]![ENDCOLOR]";
                            data.IndustryTT = data.IndustryTT.."[NEWLINE][ICON_GoingTo]"..LL("LOC_IMPROVEMENT_CORPORATION_NAME")..sEffectC;
                        end
                    else -- build resource list
                        -- add resource only if there is no industry nor corpo yet around it
                        if not pGameEconomic:HasIndustryOf(localPlayerID, eResourceType) and not pGameEconomic:HasCorporationOf(localPlayerID, eResourceType) then
                            sResList = sResList..sResIcon;
                            sResListTT = sResListTT..(bHasRes and "[NEWLINE]" or "")..sResIcon..LL(resourceInfo.Name)..sEffectI;
                            bHasRes = true;
                            -- if we can have an industry - add the mark
                            if pGameEconomic:CanHaveIndustry(localPlayerID, eResourceType) then
                                sResList = sResList.."[COLOR_Green]![ENDCOLOR]";
                                sResListTT = sResListTT.."[NEWLINE][ICON_GoingTo]"..LL("LOC_IMPROVEMENT_INDUSTRY_NAME");
                            end
                        end -- no IC yet
                    end
                end -- luxury only
            end -- resource check
            -- if there is no industry nor corpo - put res list
            if not data.HasIndustry and not data.HasCorporation then
                data.Industry = sResList;
                data.IndustryTT = sResListTT;
            end
        end -- city plots
    end -- monopolies mode
	--print("..xp2 data appended");
end

function UpdateCities2Data()
	print("UpdateCities2Data");
	Timer1Start();
	GetDataCities2();
	Timer1Tick("UpdateCities2Data");
	g_DirtyFlag.CITIES2 = false;
end

-- helpers

function city2_fields( kCityData, pCityInstance )

	local function ColorRed(text) return("[COLOR_Red]"..tostring(text).."[ENDCOLOR]"); end -- Infixo: helper
	local function ColorGreen(text) return("[COLOR_Green]"..tostring(text).."[ENDCOLOR]"); end -- Infixo: helper
	local function ColorWhite(text) return("[COLOR_White]"..tostring(text).."[ENDCOLOR]"); end -- Infixo: helper
	local sText:string = "";
	local tToolTip:table = {};

	-- Status
	--if kCityData.IsNuclearRisk then
		--sText = sText.."[ICON_RESOURCE_URANIUM]"; table.insert(tToolTip, Locale.Lookup("LOC_EMERGENCY_NAME_NUCLEAR"));
	--end
	--if kCityData.IsUnderpowered then
		--sText = sText.."[ICON_PowerInsufficient]"; table.insert(tToolTip, Locale.Lookup("LOC_POWER_STATUS_UNPOWERED_NAME"));
	--end
	pCityInstance.Status:SetText( sText );
	pCityInstance.Status:SetToolTipString( table.concat(tToolTip, "[NEWLINE]") );
	
	-- Icon
	-- not used
	
	-- CityName
	TruncateStringWithTooltip(pCityInstance.CityName, 178, (kCityData.IsCapital and "[ICON_Capital]" or "")..Locale.Lookup(kCityData.CityName));
	
	-- Population
	pCityInstance.Population:SetText(ColorWhite(kCityData.Population));
	pCityInstance.Population:SetToolTipString("");

	-- Power consumption [icon required_number / consumed_number]
	pCityInstance.PowerConsumed:SetText(string.format("%s %s / %s",
		kCityData.PowerIcon,
		kCityData.PowerRequired > 0 and ColorWhite(kCityData.PowerRequired) or tostring(kCityData.PowerRequired),
		kCityData.IsUnderpowered and ColorRed(kCityData.PowerConsumed) or tostring(kCityData.PowerConsumed)));
	pCityInstance.PowerConsumed:SetToolTipString(kCityData.PowerConsumedTT);

	-- Power produced [number]
	pCityInstance.PowerProduced:SetText(string.format("[ICON_%s] %d", kCityData.PowerPlantResType, kCityData.PowerProduced));
	pCityInstance.PowerProduced:SetToolTipString(kCityData.PowerProducedTT);

	-- CO2 footprint [resource number]
	--if kCityData.CO2Footprint > 0 then
		pCityInstance.CO2Footprint:SetText(string.format("[ICON_%s] %.1f", kCityData.PowerPlantResType, kCityData.CO2Footprint));
		pCityInstance.CO2Footprint:SetToolTipString(kCityData.CO2FootprintTT);
	--else
		--pCityInstance.CO2Footprint:SetText("0");
		--pCityInstance.CO2Footprint:SetToolTipString(kCityData.CO2FootprintTT);
	--end

	-- Nuclear power plant [nuclear icon / num turns]
	if kCityData.HasNuclearPowerPlant then sText = kCityData.NuclearAccidentIcon.."[ICON_RESOURCE_URANIUM]"..ColorWhite(kCityData.ReactorAge);
	else                                   sText = "[ICON_Bullet]"; end
	pCityInstance.NuclearPowerPlant:SetText(sText);
	pCityInstance.NuclearPowerPlant:SetToolTipString(kCityData.NuclearPowerPlantTT);

	-- Dam district & Flood info [num tiles / dam icon]
	sText = tostring(kCityData.NumRiverFloodTiles);
	if kCityData.HasDamDistrict then sText = sText.." [ICON_Checkmark]"; end
	pCityInstance.RiverFloodDam:SetText(sText);
	pCityInstance.RiverFloodDam:SetToolTipString(kCityData.RiverFloodDamTT);

	-- Info about Flood barrier. [num tiles / flood barrier icon]
	sText = tostring(kCityData.NumFloodTiles);
	if kCityData.HasFloodBarrier then sText = sText.." [ICON_Checkmark]"; end
	pCityInstance.FloodBarrier:SetText(sText);
	pCityInstance.FloodBarrier:SetToolTipString(kCityData.FloodTilesTT);

	-- Flood Barrier Per turn maintenance [number]
	pCityInstance.BarrierMaintenance:SetText(kCityData.HasFloodBarrier and ColorWhite(kCityData.FloodBarrierMaintenance) or tostring(kCityData.FloodBarrierMaintenance));
	pCityInstance.BarrierMaintenance:SetToolTipString(kCityData.FloodBarrierMaintenanceTT);
	
	-- Number of RR tiles in the city borders [number]
	pCityInstance.Railroads:SetText(tostring(kCityData.NumRailroads));
	pCityInstance.Railroads:SetToolTipString(kCityData.NumRailroadsTT);
	
	-- Number of Canal districts [icons]
	pCityInstance.Canals:SetText(string.rep("[ICON_DISTRICT_CANAL]", kCityData.NumCanals));
    
    -- 2021-05-21 Monopolies and Corporations Mode
    if bIsMonopolies then
        pCityInstance.Industry:SetText(kCityData.Industry);
        pCityInstance.Industry:SetToolTipString(kCityData.IndustryTT);
        pCityInstance.Industry:SetHide(false);
    else
        pCityInstance.Industry:SetHide(true);
    end
end

function sort_cities2( type, instance )

	local i = 0
	
	for _, kCityData in spairs( m_kCity2Data, function( t, a, b ) return city2_sortFunction( instance.Descend, type, t, a, b ); end ) do
		i = i + 1
		local cityInstance = instance.Children[i]

		city2_fields( kCityData, cityInstance )

		-- go to the city after clicking
		cityInstance.GoToCityButton:RegisterCallback( Mouse.eLClick, function() Close(); UI.LookAtPlot( kCityData.City:GetX(), kCityData.City:GetY() ); UI.SelectCity( kCityData.City ); end );
		cityInstance.GoToCityButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound( "Main_Menu_Mouse_Over" ); end );
	end
	
end

function city2_sortFunction( descend, type, t, a, b )

	local aCity = 0
	local bCity = 0
	
	if type == "name" then
		aCity = Locale.Lookup( t[a].CityName );
		bCity = Locale.Lookup( t[b].CityName );
	elseif type == "pop" then
		aCity = t[a].Population;
		bCity = t[b].Population;
	elseif type == "status" then
		--if t[a].IsUnderpowered then aCity = aCity + 20; else aCity = aCity + 10; end
		--if t[b].IsUnderpowered then bCity = bCity + 20; else bCity = bCity + 10; end
		--if t[a].IsNuclearRisk then aCity = aCity + 20; else aCity = aCity + 10; end
		--if t[b].IsNuclearRisk then bCity = bCity + 20; else bCity = bCity + 10; end
	elseif type == "icon" then
		-- not used
	elseif type == "powcon" then
		aCity = t[a].PowerRequired;
		bCity = t[b].PowerRequired;
		if aCity == bCity then
			aCity = t[a].PowerConsumed;
			bCity = t[b].PowerConsumed;
		end
	elseif type == "pwprod" then
		aCity = t[a].PowerProduced;
		bCity = t[b].PowerProduced;
	elseif type == "co2" then
		--aCity = t[a].CO2Footprint;
		--bCity = t[b].CO2Footprint;
	elseif type == "nuclear" then
		aCity = t[a].ReactorAge;
		bCity = t[b].ReactorAge;
	elseif type == "dam" then
		aCity = t[a].NumRiverFloodTiles;
		bCity = t[b].NumRiverFloodTiles;
	elseif type == "barrier" then
		aCity = t[a].NumFloodTiles;
		bCity = t[b].NumFloodTiles;
	elseif type == "fbcost" then
		aCity = t[a].FloodBarrierMaintenance;
		bCity = t[b].FloodBarrierMaintenance;
	elseif type == "numrr" then
		aCity = t[a].NumRailroads;
		bCity = t[b].NumRailroads;
	else
		-- nothing to do here
	end
	
	if descend then return bCity > aCity; else return bCity < aCity; end
	
end

function ViewCities2Page()
	print("ViewCities2Page");

	if g_DirtyFlag.CITIES2 then UpdateCities2Data(); end
	
	ResetTabForNewPageContent();

	local instance:table = m_simpleIM:GetInstance();
	instance.Top:DestroyAllChildren();
	
	instance.Children = {}
	instance.Descend = true
	
	local pHeaderInstance:table = {};
	ContextPtr:BuildInstanceForControl( "CityStatus2HeaderInstance", pHeaderInstance, instance.Top );
	
	pHeaderInstance.CityStatusButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "status", instance ) end )
	--pHeaderInstance.CityIconButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "icon", instance ) end ) -- not used
	pHeaderInstance.CityNameButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "name", instance ) end )
	pHeaderInstance.CityPopulationButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "pop", instance ) end )
	pHeaderInstance.CityPowerConsumedButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "powcon", instance ) end )
	pHeaderInstance.CityPowerProducedButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "pwprod", instance ) end )
	--pHeaderInstance.CityCO2FootprintButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "co2", instance ) end )
	pHeaderInstance.CityNuclearPowerPlantButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "nuclear", instance ) end )
	pHeaderInstance.CityRiverFloodDamButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "dam", instance ) end )
	pHeaderInstance.CityFloodBarrierButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "barrier", instance ) end )
	pHeaderInstance.CityBarrierMaintenanceButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "fbcost", instance ) end );
	pHeaderInstance.CityRailroadsButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities2( "numrr", instance ) end );
    pHeaderInstance.CityIndustryButton:SetHide(not bIsMonopolies);

	-- 
	for _, kCityData in spairs( m_kCity2Data, function( t, a, b ) return city2_sortFunction( true, "name", t, a, b ); end ) do -- initial sort by name ascending

		local pCityInstance:table = {}

		ContextPtr:BuildInstanceForControl( "CityStatus2EntryInstance", pCityInstance, instance.Top );
		table.insert( instance.Children, pCityInstance );
		
		city2_fields( kCityData, pCityInstance );

		-- go to the city after clicking
		pCityInstance.GoToCityButton:RegisterCallback( Mouse.eLClick, function() Close(); UI.LookAtPlot( kCityData.City:GetX(), kCityData.City:GetY() ); UI.SelectCity( kCityData.City ); end );
		pCityInstance.GoToCityButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound( "Main_Menu_Mouse_Over" ); end );

	end

	Controls.Stack:CalculateSize();
	Controls.Scroll:CalculateSize();

	Controls.CollapseAll:SetHide( true );
	Controls.BottomYieldTotals:SetHide( true );
	Controls.BottomResourceTotals:SetHide( true );
	Controls.BottomPoliciesFilters:SetHide( true );
	Controls.BottomMinorsFilters:SetHide( true );
	Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - SIZE_HEIGHT_PADDING_BOTTOM_ADJUST);
	-- Remember this tab when report is next opened: ARISTOS
	m_kCurrentTab = 9;
end

print("BRS: Loaded file BRSPage_Cities2.lua");
