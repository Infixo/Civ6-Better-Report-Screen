-- ===========================================================================
-- Better Report Screen - page CityStatus
-- Author: Infixo
-- 2023-05-10: Created
-- ===========================================================================

m_kCity1Data = nil; -- global for debug purposes

-- 230522 #17 Districts with HitPoints can be garrisoned
local tGarrisonDistricts: table = {};
for row in GameInfo.Districts() do
	if row.HitPoints > 0 then tGarrisonDistricts[row.DistrictType] = true; end
end


-- ===========================================================================
-- REAL HOUSING FROM IMPROVEMENTS
-- Get the real housing from improvements, not rounded-down
-- The idea taken from CQUI, however CQUI's code is wrong(tested for vanilla and R&F) - the farm doesn't need to be worked, only created within borders
-- GetHousingFromImprovements() returns math.floor(), i.e. +0.5 is rounded to 0, must have 2 farms to get +1 housing

--[[ OBSOLETE as of 2020-06-09
-- Some improvements provide more housing when a tech or civic is unlocked
-- this is done via modifiers, so we need to find them first (EFFECT_ADJUST_IMPROVEMENT_HOUSING)
-- STEPWELL_HOUSING_WITHTECH (REQUIREMENT_PLAYER_HAS_TECHNOLOGY) TechnologyType
-- GOLFCOURSE_HOUSING_WITHGLOBLIZATION (REQUIREMENT_PLAYER_HAS_CIVIC) CivicType
-- MEKEWAP_HOUSING_WITHCIVILSERVICE (REQUIREMENT_PLAYER_HAS_CIVIC)
-- All set via SubjectRequirementSetId
-- However, it is not clear if Amount=1 in modifier means +1 housing or +0.5 just as with base values
-- CQUI calculates as +1 in this case, seems that wiki also says that each of them gives +1

-- this table will hold Tech or Civic requirement for increased Housing
local tImprMoreHousingReqs:table = nil;
local iFarmHousingForMaya:number = 0; -- 2020-05-28 Special case for Maya civ

function PopulateImprMoreHousingReqs()
	--print("PopulateImprMoreHousingReqs");
	tImprMoreHousingReqs = {};
	for mod in GameInfo.ImprovementModifiers() do
		local tMod:table = RMA.FetchAndCacheData(mod.ModifierID); -- one of cases with upper case ID
		--print(mod.ImprovementType, "fetched", tMod.ModifierId, tMod.EffectType, tMod.SubjectReqSetId);
		if tMod and tMod.EffectType == "EFFECT_ADJUST_IMPROVEMENT_HOUSING" and tMod.SubjectReqSet then
			--dshowrectable(tMod);
			-- now extract requirement!
			for _,req in ipairs(tMod.SubjectReqSet.Reqs) do
				-- 2020-05-28 Special case for Maya civ
				if req.ReqType == "REQUIREMENT_PLAYER_TYPE_MATCHES" and req.Arguments.CivilizationType == "CIVILIZATION_MAYA" then 
					iFarmHousingForMaya = tonumber(tMod.Arguments.Amount);
				elseif req.ReqType == "REQUIREMENT_PLAYER_HAS_TECHNOLOGY" then
					tImprMoreHousingReqs[ mod.ImprovementType ] = { IsTech = true, Prereq = req.Arguments.TechnologyType, Amount = tonumber(tMod.Arguments.Amount) };
				elseif req.ReqType == "REQUIREMENT_PLAYER_HAS_CIVIC" then
					tImprMoreHousingReqs[ mod.ImprovementType ] = { IsTech = false, Prereq = req.Arguments.CivicType, Amount = tonumber(tMod.Arguments.Amount) };
				end
			end
		end
	end
	print("Found", table.count(tImprMoreHousingReqs), "improvements with additional Housing.");
	for k,v in pairs(tImprMoreHousingReqs) do print(k, v.IsTech, v.Prereq, v.Amount); end
	print("Maya housing for Farms is", iFarmHousingForMaya);
end

function GetRealHousingFromImprovements(pCity:table)
	if tImprMoreHousingReqs == nil then PopulateImprMoreHousingReqs(); end -- do it once
	local iNumHousing:number = 0; -- we'll add data from Housing field in Improvements divided by TilesRequired which is usually 2
	-- 2020-05-28 Special case for Maya civ
	local ePlayerID:number = pCity:GetOwner();
	local bIsMaya:boolean = ( PlayerConfigurations[ePlayerID]:GetCivilizationTypeName() == "CIVILIZATION_MAYA" );
	-- check all plots in the city
	for _,plotIndex in ipairs(Map.GetCityPlots():GetPurchasedPlots(pCity)) do
		local pPlot:table = Map.GetPlotByIndex(plotIndex);
		if pPlot and pPlot:GetImprovementType() > -1 and not pPlot:IsImprovementPillaged() then
			local imprInfo:table = GameInfo.Improvements[ pPlot:GetImprovementType() ];
			iNumHousing = iNumHousing + imprInfo.Housing / imprInfo.TilesRequired; -- well, we can always add 0, right?
			-- now check if there's more with techs/civics
			-- this check is independent from base Housing: there could be an improvement that doesn't give housing as fresh but could later
			if tImprMoreHousingReqs[ imprInfo.ImprovementType ] then
				--print("ANALYZE WEIRD CASE", imprInfo.ImprovementType);
				local reqs:table = tImprMoreHousingReqs[ imprInfo.ImprovementType ];
				if reqs.IsTech then
					if Players[ePlayerID]:GetTechs():HasTech( GameInfo.Technologies[reqs.Prereq].Index ) then iNumHousing = iNumHousing + reqs.Amount; end
				else
					if Players[ePlayerID]:GetCulture():HasCivic( GameInfo.Civics[reqs.Prereq].Index ) then iNumHousing = iNumHousing + reqs.Amount; end
				end
			end
			-- 2020-05-28 Special case for Maya civ
			if imprInfo.ImprovementType == "IMPROVEMENT_FARM" and bIsMaya then
				iNumHousing = iNumHousing + iFarmHousingForMaya;
			end
		end
	end
	return iNumHousing;
end
--]]

-- 2020-06-09 new idea for calculations - calculate only a correction and apply to the game function
-- please note that another condition was added - a tile must be within workable distance - this is how the game's engine works
local iCityMaxBuyPlotRange:number = tonumber(GlobalParameters.CITY_MAX_BUY_PLOT_RANGE);
function GetRealHousingFromImprovements(pCity:table)
	local cityX:number, cityY:number = pCity:GetX(), pCity:GetY();
	--local centerIndex:number = Map.GetPlotIndex(pCity:GetLocation());
	local iNumHousing:number = 0; -- we'll add data from Housing field in Improvements divided by TilesRequired which is usually 2
	-- check all plots in the city
	for _,plotIndex in ipairs(Map.GetCityPlots():GetPurchasedPlots(pCity)) do
		local pPlot:table = Map.GetPlotByIndex(plotIndex);
		--print(centerIndex, plotIndex, Map.GetPlotDistance(cityX,cityY, pPlot:GetX(), pPlot:GetY()));
		if pPlot and pPlot:GetImprovementType() > -1 and not pPlot:IsImprovementPillaged() and Map.GetPlotDistance(cityX, cityY, pPlot:GetX(), pPlot:GetY()) <= iCityMaxBuyPlotRange then
			local imprInfo:table = GameInfo.Improvements[ pPlot:GetImprovementType() ];
			iNumHousing = iNumHousing + imprInfo.Housing / imprInfo.TilesRequired; -- well, we can always add 0, right?
		end
	end
	return pCity:GetGrowth():GetHousingFromImprovements() + Round(iNumHousing-math.floor(iNumHousing),1);
end

-- ===========================================================================
function GetDataCityStatus()
	print("GetDataCityStatus");
	
	local playerID: number = Game.GetLocalPlayer();
	if playerID == PlayerTypes.NONE or platerID == PlayerTypes.OBSERVER then
		UI.DataError("Unable to get valid playerID for report screen.");
		return;
	end
	
	m_kCity1Data = {}; -- reset the main table
	
	for i, pCity in Players[playerID]:GetCities():Members() do
		local cityName: string = pCity:GetName();
		--print("city", LL(cityName));
			
		-- Big calls, obtain city data and add report specific fields to it.
		local data: table = GetCityData( pCity );
			
		m_kCity1Data[cityName] = data;

		-- Add outgoing route data
		data.OutgoingRoutes = pCity:GetTrade():GetOutgoingRoutes();
		data.IncomingRoutes = pCity:GetTrade():GetIncomingRoutes();

		-- ADDITIONAL DATA
		
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
		data.IsGarrisonUnit = false; -- 230522 #10 See below in the loop
		
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
			-- 230522 #17 Garrison unit can be also in an Encampment, so we will handle all possible districts in one go
			if not data.IsGarrisonUnit and tGarrisonDistricts[districtInfo.DistrictType] then -- don't iterate if we already found a garrison
				for _,unit in ipairs(Units.GetUnitsInPlot( district:GetX(), district:GetY() )) do
					if unit:GetCombat() > 0 then
						data.IsGarrisonUnit = true;
						data.GarrisonUnitName = LL(unit:GetName());
						break;
					end
				end
			end
		end -- for districts
		
	end -- for Cities:Members
end

function UpdateCityStatusData()
	print("UpdateCityStatusData");
	Timer1Start();
	GetDataCityStatus();
	Timer1Tick("UpdateCityStatusData");
	g_DirtyFlag.CITYSTATUS = false;
end

function GetFontIconForDistrict(sDistrictType:string)
	-- exceptions first
	--if sDistrictType == "DISTRICT_HOLY_SITE"                   then return "[ICON_DISTRICT_HOLYSITE]";      end
	--if sDistrictType == "DISTRICT_ENTERTAINMENT_COMPLEX"       then return "[ICON_DISTRICT_ENTERTAINMENT]"; end
	if sDistrictType == "DISTRICT_WATER_ENTERTAINMENT_COMPLEX" then return "[ICON_DISTRICT_ENTERTAINMENT]"; end -- no need to check for mutuals with that
	--if sDistrictType == "DISTRICT_AERODROME"                   then return "[ICON_DISTRICT_WONDER]";        end -- no unique font icon for an aerodrome
	--if sDistrictType == "DISTRICT_CANAL"                       then return "[ICON_DISTRICT_WONDER]";        end -- no unique font icon for a canal
	--if sDistrictType == "DISTRICT_DAM"                         then return "[ICON_DISTRICT_WONDER]";        end -- no unique font icon for a dam
	if sDistrictType == "DISTRICT_GOVERNMENT"                  then return "[ICON_DISTRICT_GOVPLAZA]";      end
	-- default icon last
	return "[ICON_"..sDistrictType.."]";
end

local tDistrictsOrder:table = {
	-- Ancient Era
	--"DISTRICT_GOVERNMENT", -- to save space, will be treated separately
	"DISTRICT_HOLY_SITE", -- icon is DISTRICT_HOLYSITE
	"DISTRICT_CAMPUS",
	"DISTRICT_ENCAMPMENT",
	-- Classical Era
	"DISTRICT_THEATER",
	"DISTRICT_COMMERCIAL_HUB",
	"DISTRICT_HARBOR",
	"DISTRICT_ENTERTAINMENT_COMPLEX", -- with DISTRICT_WATER_ENTERTAINMENT_COMPLEX, icon is DISTRICT_ENTERTAINMENT
	-- Medieval Era
	"DISTRICT_INDUSTRIAL_ZONE",
	-- others
	"DISTRICT_AQUEDUCT",
	"DISTRICT_NEIGHBORHOOD",
	"DISTRICT_SPACEPORT",
	"DISTRICT_AERODROME", -- there is no font icon, so we'll use ICON_DISTRICT_WONDER
}
--for k,v in pairs(tDistrictsOrder) do print("tDistrictsOrder",k,v) end;

function HasCityDistrict(kCityData:table, sDistrictType:string)
	for _,district in ipairs(kCityData.BuildingsAndDistricts) do
		if district.isBuilt then
			local sDistrictInCity:string = district.Type;
			--if district.DistrictType == sDistrictType then return true; end
			if GameInfo.DistrictReplaces[ sDistrictInCity ] then sDistrictInCity = GameInfo.DistrictReplaces[ sDistrictInCity ].ReplacesDistrictType; end
			if sDistrictInCity == sDistrictType then return true; end
			-- check mutually exclusive
			for row in GameInfo.MutuallyExclusiveDistricts() do
				if sDistrictInCity == row.District and row.MutuallyExclusiveDistrict == sDistrictType then return true; end
			end
		end
	end
	return false;
end

-- districts
function GetDistrictsForCity(kCityData:table)
	local sDistricts:string = "";
	for _,districtType in ipairs(tDistrictsOrder) do
		local sDistrictIcon:string = "[ICON_Bullet]"; -- default empty
		if HasCityDistrict(kCityData, districtType) then
			sDistrictIcon = GetFontIconForDistrict(districtType);
		end
		sDistricts = sDistricts..sDistrictIcon;
	end
	return sDistricts;
end

-- helper from CityPanel.lua
function GetPercentGrowthColor( percent:number )
	if percent == 0 then return "Error"; end
	if percent <= 0.25 then return "WarningMajor"; end
	if percent <= 0.5 then return "WarningMinor"; end
	return "StatNormalCSGlow";
end

function city_fields( kCityData, pCityInstance )

	local function ColorRed(text) return("[COLOR_Red]"..tostring(text).."[ENDCOLOR]"); end -- Infixo: helper
	local function ColorGreen(text) return("[COLOR_Green]"..tostring(text).."[ENDCOLOR]"); end -- Infixo: helper

	-- Infixo: status will show various icons
	--pCityInstance.Status:SetText( kCityData.IsUnderSiege and Locale.Lookup("LOC_HUD_REPORTS_STATUS_UNDER_SEIGE") or Locale.Lookup("LOC_HUD_REPORTS_STATUS_NORMAL") );
	local sStatusText:string = "";
	local tStatusToolTip:table = {};
	if kCityData.Population > kCityData.Housing then
		sStatusText = sStatusText.."[ICON_HousingInsufficient]"; table.insert(tStatusToolTip, ColorRed(LL("LOC_CITY_BANNER_HOUSING_INSUFFICIENT")));
	end -- insufficient housing   
	if kCityData.AmenitiesNum < kCityData.AmenitiesRequiredNum then
		sStatusText = sStatusText.."[ICON_AmenitiesInsufficient]"; table.insert(tStatusToolTip, ColorRed(LL("LOC_CITY_BANNER_AMENITIES_INSUFFICIENT")));
	end -- insufficient amenities
	if kCityData.IsUnderSiege then
		sStatusText = sStatusText.."[ICON_UnderSiege]"; table.insert(tStatusToolTip, ColorRed(LL("LOC_HUD_REPORTS_STATUS_UNDER_SEIGE")));
	end -- under siege
	if kCityData.Occupied then
		sStatusText = sStatusText.."[ICON_Occupied]"; table.insert(tStatusToolTip, ColorRed(LL("LOC_HUD_CITY_GROWTH_OCCUPIED")));
	end -- occupied
	if HasCityDistrict(kCityData, "DISTRICT_GOVERNMENT") then
		sStatusText = sStatusText.."[ICON_DISTRICT_GOVPLAZA]"; table.insert(tStatusToolTip, "[COLOR:111,15,143,255]"..Locale.Lookup("LOC_DISTRICT_GOVERNMENT_NAME")..ENDCOLOR); -- ICON_DISTRICT_GOVERNMENT
	end
    -- 2021-05-31 Diplomatic Quarter
	if HasCityDistrict(kCityData, "DISTRICT_DIPLOMATIC_QUARTER") then
		sStatusText = sStatusText.."[ICON_DISTRICT_DIPLOMATIC_QUARTER]"; table.insert(tStatusToolTip, "[COLOR:111,15,143,255]"..Locale.Lookup("LOC_DISTRICT_DIPLOMATIC_QUARTER_NAME")..ENDCOLOR); -- ICON_DISTRICT_DIPLOMATIC_QUARTER
	end
    -- 2021-05-31 Preserve
	if HasCityDistrict(kCityData, "DISTRICT_PRESERVE") then
		sStatusText = sStatusText.."[ICON_DISTRICT_PRESERVE]"; table.insert(tStatusToolTip, "[COLOR:15,140,15,255]"..Locale.Lookup("LOC_DISTRICT_PRESERVE_NAME")..ENDCOLOR); -- ICON_DISTRICT_PRESERVE
	end
    
    
	local bHasWonder:boolean = false;
	for _,wonder in ipairs(kCityData.Wonders) do
		bHasWonder = true;
		table.insert(tStatusToolTip, wonder.Name);
	end
	if bHasWonder then sStatusText = sStatusText.."[ICON_DISTRICT_WONDER]"; end

	pCityInstance.Status:SetText( sStatusText );
	pCityInstance.Status:SetToolTipString( table.concat(tStatusToolTip, "[NEWLINE]") );
	
	-- Religions
	local eCityReligion:number = kCityData.City:GetReligion():GetMajorityReligion();
	local eCityPantheon:number = kCityData.City:GetReligion():GetActivePantheon();
	
	local function ShowReligionTooltip(sHeader:string)
		local tTT:table = {};
		table.insert(tTT, "[ICON_Religion]"..sHeader);
		table.sort(kCityData.Religions, function(a,b) return a.Followers > b.Followers; end);
		for _,rel in ipairs(kCityData.Religions) do
			--print(rel.ID, rel.ReligionType, rel.Followers);
			--table.insert(tTT, string.format("%s: %d", Game.GetReligion():GetName( math.max(0, rel.ID) ), rel.Followers)); -- LOC_UI_RELIGION_NUM_FOLLOWERS_TT
			table.insert(tTT, Locale.Lookup("LOC_UI_RELIGION_NUM_FOLLOWERS_TT", Game.GetReligion():GetName( math.max(0, rel.ID) ), rel.Followers));
		end
		pCityInstance.ReligionIcon:SetToolTipString(table.concat(tTT, "[NEWLINE]"));
	end
	
	if eCityReligion > 0 then
		local iconName : string = "ICON_" .. GameInfo.Religions[eCityReligion].ReligionType;
		local majorityReligionColor : number = UI.GetColorValue(GameInfo.Religions[eCityReligion].Color);
		if (majorityReligionColor ~= nil) then
			pCityInstance.ReligionIcon:SetColor(majorityReligionColor);
		end
		local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconName,22);
		if (textureOffsetX ~= nil) then
			pCityInstance.ReligionIcon:SetTexture( textureOffsetX, textureOffsetY, textureSheet );
		end
		pCityInstance.ReligionIcon:SetHide(false);
		--pCityInstance.ReligionIcon:SetToolTipString(Game.GetReligion():GetName(eCityReligion));
		ShowReligionTooltip( Game.GetReligion():GetName(eCityReligion) );
		
	elseif eCityPantheon >= 0 then
		local iconName : string = "ICON_" .. GameInfo.Religions[0].ReligionType;
		local majorityReligionColor : number = UI.GetColorValue(GameInfo.Religions.RELIGION_PANTHEON.Color);
		if (majorityReligionColor ~= nil) then
			pCityInstance.ReligionIcon:SetColor(majorityReligionColor);
		end
		local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconName,22);
		if (textureOffsetX ~= nil) then
			pCityInstance.ReligionIcon:SetTexture( textureOffsetX, textureOffsetY, textureSheet );
		end
		pCityInstance.ReligionIcon:SetHide(false);
		--pCityInstance.ReligionIcon:SetToolTipString(Locale.Lookup("LOC_HUD_CITY_PANTHEON_TT", GameInfo.Beliefs[eCityPantheon].Name));
		ShowReligionTooltip( Locale.Lookup("LOC_HUD_CITY_PANTHEON_TT", GameInfo.Beliefs[eCityPantheon].Name) );

	else
		pCityInstance.ReligionIcon:SetHide(true);
		pCityInstance.ReligionIcon:SetToolTipString("");
	end
	
	-- CityName
	--pCityInstance.CityName:SetText( Locale.Lookup( kCityData.CityName ) );
	TruncateStringWithTooltip(pCityInstance.CityName, 178, (kCityData.IsCapital and "[ICON_Capital]" or "")..Locale.Lookup(kCityData.CityName)..((kCityData.DistrictsNum < kCityData.DistrictsPossibleNum) and "[COLOR_Green]![ENDCOLOR]" or ""));
	
	-- Population and Housing
	-- a bit more complicated due to real housing from improvements - fix applied earlier
	--local fRealHousing:number = kCityData.Housing - kCityData.HousingFromImprovements + kCityData.RealHousingFromImprovements;
	local sPopulationText:string = "[COLOR_White]"..tostring(kCityData.Population).."[ENDCOLOR] / ";
	if kCityData.Population >= kCityData.Housing then sPopulationText = sPopulationText..ColorRed(kCityData.Housing);
	else                                              sPopulationText = sPopulationText..tostring(kCityData.Housing); end
	-- check for Sewer
	pCityInstance.Population:SetToolTipString("");
	if GameInfo.Buildings["BUILDING_SEWER"] ~= nil and kCityData.City:GetBuildings():HasBuilding( GameInfo.Buildings["BUILDING_SEWER"].Index ) then
		sPopulationText = sPopulationText..ColorGreen("!");
		pCityInstance.Population:SetToolTipString( Locale.Lookup("LOC_BUILDING_SEWER_NAME") );
	end
	pCityInstance.Population:SetText(sPopulationText);
	--[[ debug
	local tTT:table = {};
	table.insert(tTT, "Housing : "..kCityData.Housing);
	table.insert(tTT, "FromImpr: "..kCityData.HousingFromImprovements);
	table.insert(tTT, "RealImpr: "..kCityData.RealHousingFromImprovements);
	table.insert(tTT, "RealHous: "..kCityData.Housing);
	pCityInstance.Population:SetToolTipString(table.concat(tTT, "[NEWLINE]"));
	--]]
	
	-- GrowthRateStatus
	local sGRStatus:string = "0%";
	local sGRStatusTT:string = "LOC_HUD_REPORTS_STATUS_NORMAL";
	local sGRColor:string = "";
	if     kCityData.HousingMultiplier == 0 or kCityData.Occupied then sGRStatus = "LOC_HUD_REPORTS_STATUS_HALTED";                        sGRColor = "[COLOR:200,62,52,255]";  sGRStatusTT = sGRStatus; -- Error
	elseif kCityData.HousingMultiplier <= 0.25                    then sGRStatus = tostring(100 * kCityData.HousingMultiplier - 100).."%"; sGRColor = "[COLOR:200,146,52,255]"; sGRStatusTT = "LOC_HUD_REPORTS_STATUS_SLOWED";
	elseif kCityData.HousingMultiplier <= 0.5                     then sGRStatus = tostring(100 * kCityData.HousingMultiplier - 100).."%"; sGRColor = "[COLOR:206,199,91,255]"; sGRStatusTT = "LOC_HUD_REPORTS_STATUS_SLOWED";
	elseif kCityData.HappinessGrowthModifier > 0                  then sGRStatus = "+"..tostring(kCityData.HappinessGrowthModifier).."%";  sGRColor = "[COLOR_White]";          sGRStatusTT = "LOC_HUD_REPORTS_STATUS_ACCELERATED"; end -- GS addition
	pCityInstance.GrowthRateStatus:SetText( sGRColor..Locale.Lookup(sGRStatus)..(sGRColor~="" and "[ENDCOLOR]" or "") );
	pCityInstance.GrowthRateStatus:SetToolTipString(Locale.Lookup(sGRStatusTT));
	--if sGRColor ~= "" then pCityInstance.GrowthRateStatus:SetColorByName( sGRColor ); end

	-- Amenities
	if kCityData.AmenitiesNum < kCityData.AmenitiesRequiredNum then
		pCityInstance.Amenities:SetText( ColorRed(kCityData.AmenitiesNum).." / "..tostring(kCityData.AmenitiesRequiredNum) );
	else
		pCityInstance.Amenities:SetText( tostring(kCityData.AmenitiesNum).." / "..tostring(kCityData.AmenitiesRequiredNum) );
	end
	
	-- Happiness
	local happinessFormat:string = "%s";
	local happinessText:string = Locale.Lookup( GameInfo.Happinesses[kCityData.Happiness].Name );
	local happinessToolTip:string = happinessText;
	if kCityData.HappinessGrowthModifier < 0 then happinessFormat = "[COLOR:255,40,50,160]%s[ENDCOLOR]"; end -- StatBadCS    Color0="255,40,50,240" StatNormalCS Color0="200,200,200,240"
	if kCityData.HappinessGrowthModifier > 0 then happinessFormat = "[COLOR:80,255,90,160]%s[ENDCOLOR]"; end -- StatGoodCS   Color0="80,255,90,240"
	if kCityData.HappinessGrowthModifier ~= 0 then happinessText = string.format("%+d%% %+d%%", kCityData.HappinessGrowthModifier, kCityData.HappinessNonFoodYieldModifier); end
	pCityInstance.CitizenHappiness:SetText( string.format(happinessFormat, happinessText) );
	pCityInstance.CitizenHappiness:SetToolTipString( string.format(happinessFormat, happinessToolTip) );
	
	-- Strength and icon for Garrison Unit, and Walls
	local sStrength:string = tostring(kCityData.Defense);
	local sStrengthToolTip:string = "";
	local function CheckForWalls(sWallsType:string)
		local pCityBuildings:table = kCityData.City:GetBuildings();
		if GameInfo.Buildings[sWallsType] ~= nil and pCityBuildings:HasBuilding( GameInfo.Buildings[sWallsType].Index ) then
			sStrengthToolTip = sStrengthToolTip..(string.len(sStrengthToolTip) == 0 and "" or "[NEWLINE]")..Locale.Lookup(GameInfo.Buildings[ sWallsType ].Name);
			if pCityBuildings:IsPillaged( GameInfo.Buildings[ sWallsType ].Index ) then
				sStrength = sStrength.."[COLOR_Red]!";
				sStrengthToolTip = sStrengthToolTip.." "..Locale.Lookup("LOC_TOOLTIP_PLOT_PILLAGED_TEXT");
			else
				sStrength = sStrength.."[COLOR_Green]!";
			end
		end
	end
	CheckForWalls("BUILDING_WALLS");
	CheckForWalls("BUILDING_CASTLE");
	CheckForWalls("BUILDING_STAR_FORT");
	CheckForWalls("BUILDING_TSIKHE"); -- 2020-07-31 Added Tsikhe
	-- Garrison
	if kCityData.IsGarrisonUnit then 
		sStrength = sStrength.."[ICON_Fortified]";
		sStrengthToolTip = sStrengthToolTip..(string.len(sStrengthToolTip) == 0 and "" or "[NEWLINE]")..Locale.Lookup("LOC_BRS_TOOLTIP_GARRISON").." ("..kCityData.GarrisonUnitName..")";
	end
	pCityInstance.Strength:SetText( sStrength );
	pCityInstance.Strength:SetToolTipString( sStrengthToolTip );

	-- WarWeariness
	local warWearyValue:number = kCityData.AmenitiesLostFromWarWeariness;
	--pCityInstance.WarWeariness:SetText( (warWearyValue==0) and "0" or ColorRed("-"..tostring(warWearyValue)) );
	-- Damage
	--pCityInstance.Damage:SetText( tostring(kCityData.Damage) );	-- Infixo (vanilla version)
	local sDamageWWText:string = "0";
	if kCityData.HitpointsTotal > kCityData.HitpointsCurrent then sDamageWWText = ColorRed(kCityData.HitpointsTotal - kCityData.HitpointsCurrent); end
	sDamageWWText = sDamageWWText.." / "..( (warWearyValue==0) and "0" or ColorRed("-"..tostring(warWearyValue)) );
	pCityInstance.Damage:SetText( sDamageWWText );
	--pCityInstance.Damage:SetToolTipString( Locale.Lookup("LOC_HUD_REPORTS_HEADER_DAMAGE").." / "..Locale.Lookup("LOC_HUD_REPORTS_HEADER_WAR_WEARINESS") );
	
	-- Trading Posts
	kCityData.IsTradingPost = false;
	for _,tpPlayer in ipairs(kCityData.TradingPosts) do
		if tpPlayer == Game.GetLocalPlayer() then kCityData.IsTradingPost = true; break; end
	end
	pCityInstance.TradingPost:SetHide(not kCityData.IsTradingPost);
	
	-- Trading Routes
	local tTRTT:table = {};
	pCityInstance.TradeRoutes:SetText("[COLOR_White]"..( #kCityData.OutgoingRoutes > 0 and tostring(#kCityData.OutgoingRoutes) or "" ).."[ENDCOLOR]");
	for i,route in ipairs(kCityData.OutgoingRoutes) do
		-- Find destination city
		local pDestPlayer:table = Players[route.DestinationCityPlayer];
		local pDestPlayerCities:table = pDestPlayer:GetCities();
		local pDestCity:table = pDestPlayerCities:FindID(route.DestinationCityID);
		table.insert(tTRTT, Locale.Lookup(pDestCity:GetName()));
	end
	pCityInstance.TradeRoutes:SetToolTipString( table.concat(tTRTT, ", ") );
	
	-- Districts
	pCityInstance.Districts:SetText( GetDistrictsForCity(kCityData) );
	
	pCityInstance.Loyalty:SetShow(bIsRiseFall or bIsGatheringStorm);
	pCityInstance.Governor:SetShow(bIsRiseFall or bIsGatheringStorm);
	if not (bIsRiseFall or bIsGatheringStorm) then return end -- the 2 remaining fields are for Rise & Fall only
	
	-- Loyalty -- Infixo: this is not stored - try to store it for sorting later!
	local pCulturalIdentity = kCityData.City:GetCulturalIdentity();
	local currentLoyalty = pCulturalIdentity:GetLoyalty();
	local maxLoyalty = pCulturalIdentity:GetMaxLoyalty();
	local loyaltyPerTurn:number = pCulturalIdentity:GetLoyaltyPerTurn();
	local loyaltyFontIcon:string = loyaltyPerTurn >= 0 and "[ICON_PressureUp]" or "[ICON_PressureDown]";
	local iNumTurnsLoyalty:number = 0;
	if loyaltyPerTurn > 0 then
		iNumTurnsLoyalty = math.ceil((maxLoyalty-currentLoyalty)/loyaltyPerTurn);
		pCityInstance.Loyalty:SetText( loyaltyFontIcon..""..toPlusMinusString(loyaltyPerTurn).."/"..( iNumTurnsLoyalty == 0 and tostring(iNumTurnsLoyalty) or ColorGreen(iNumTurnsLoyalty) ) );
	elseif loyaltyPerTurn < 0 then
		iNumTurnsLoyalty = math.ceil(currentLoyalty/(-loyaltyPerTurn));
		pCityInstance.Loyalty:SetText( loyaltyFontIcon..""..ColorRed(toPlusMinusString(loyaltyPerTurn).."/"..iNumTurnsLoyalty) );
	else
		pCityInstance.Loyalty:SetText( loyaltyFontIcon.." 0" );
	end
	pCityInstance.Loyalty:SetToolTipString(loyaltyFontIcon .. " " .. Round(currentLoyalty, 1) .. "/" .. maxLoyalty);
	kCityData.Loyalty = currentLoyalty; -- Infixo: store for sorting
	kCityData.LoyaltyPerTurn = loyaltyPerTurn; -- Infixo: store for sorting

	-- Governor -- Infixo: this is not stored neither
	local pAssignedGovernor = kCityData.City:GetAssignedGovernor();
	if pAssignedGovernor then
		local eGovernorType = pAssignedGovernor:GetType();
		local governorDefinition = GameInfo.Governors[eGovernorType];
		local governorMode = pAssignedGovernor:IsEstablished() and "_FILL" or "_SLOT";
		local governorIcon = "ICON_" .. governorDefinition.GovernorType .. governorMode;
		pCityInstance.Governor:SetText("[" .. governorIcon .. "]");
		kCityData.Governor = governorDefinition.GovernorType;
		-- name and promotions
		local tGovernorTT:table = {};
		table.insert(tGovernorTT, Locale.Lookup(governorDefinition.Name)..", "..Locale.Lookup(governorDefinition.Title));
		for row in GameInfo.GovernorPromotions() do
			if pAssignedGovernor:HasPromotion( row.Index ) then table.insert(tGovernorTT, Locale.Lookup(row.Name)..": "..Locale.Lookup(row.Description)); end
		end
		pCityInstance.Governor:SetToolTipString(table.concat(tGovernorTT, "[NEWLINE]"));
	else
		pCityInstance.Governor:SetText("");
		pCityInstance.Governor:SetToolTipString("");
		kCityData.Governor = "";
	end

end

function sort_cities( type, instance )

	local i = 0
	
	for _, kCityData in spairs( m_kCityData, function( t, a, b ) return city_sortFunction( instance.Descend, type, t, a, b ); end ) do
		i = i + 1
		local cityInstance = instance.Children[i]

		city_fields( kCityData, cityInstance )

		-- go to the city after clicking
		cityInstance.GoToCityButton:RegisterCallback( Mouse.eLClick, function() Close(); UI.LookAtPlot( kCityData.City:GetX(), kCityData.City:GetY() ); UI.SelectCity( kCityData.City ); end );
		cityInstance.GoToCityButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound( "Main_Menu_Mouse_Over" ); end );
	end
	
end

function city_sortFunction( descend, type, t, a, b )

	local aCity = 0
	local bCity = 0
	
	if type == "name" then
		aCity = Locale.Lookup( t[a].CityName )
		bCity = Locale.Lookup( t[b].CityName )
	elseif type == "gover" then
		aCity = t[a].Governor
		bCity = t[b].Governor
	elseif type == "loyal" then
		aCity = t[a].Loyalty
		bCity = t[b].Loyalty
		if aCity == bCity then 
			aCity = t[a].City:GetCulturalIdentity():GetLoyaltyPerTurn();
			bCity = t[b].City:GetCulturalIdentity():GetLoyaltyPerTurn();
		end
	elseif type == "pop" then
		aCity = t[a].Population
		bCity = t[b].Population
		if aCity == bCity then -- same pop, sort by Housing
			aCity = t[a].Housing
			bCity = t[b].Housing
		end
	elseif type == "house" then -- Infixo: can leave it, will not be used
		aCity = t[a].Housing
		bCity = t[b].Housing
	elseif type == "amen" then
		aCity = t[a].AmenitiesNum
		bCity = t[b].AmenitiesNum
		if aCity == bCity then -- same amenities, sort by required
			aCity = t[a].AmenitiesRequiredNum
			bCity = t[b].AmenitiesRequiredNum
		end
	elseif type == "happy" then
		aCity = t[a].Happiness
		bCity = t[b].Happiness
		if aCity == bCity then -- same happiness, sort by difference in amenities
			aCity = t[a].AmenitiesNum - t[a].AmenitiesRequiredNum
			bCity = t[b].AmenitiesNum - t[b].AmenitiesRequiredNum
		end
	elseif type == "growth" then
		aCity = t[a].HousingMultiplier
		bCity = t[b].HousingMultiplier
	elseif type == "war" then
		aCity = t[a].AmenitiesLostFromWarWeariness
		bCity = t[b].AmenitiesLostFromWarWeariness
	elseif type == "status" then
		if t[a].IsUnderSiege == false then aCity = 10 else aCity = 20 end
		if t[b].IsUnderSiege == false then bCity = 10 else bCity = 20 end
	elseif type == "str" then
		aCity = t[a].Defense
		bCity = t[b].Defense
	elseif type == "dam" then
		aCity = t[a].Damage
		bCity = t[b].Damage
	elseif type == "trpost" then
		aCity = ( t[a].IsTradingPost and 1 or 0 );
		bCity = ( t[b].IsTradingPost and 1 or 0 );
	elseif type == "numtr" then
		aCity = #t[a].OutgoingRoutes;
		bCity = #t[b].OutgoingRoutes;
	elseif type == "districts" then
		aCity = t[a].NumDistricts
		bCity = t[b].NumDistricts
	elseif type == "religion" then
		aCity = t[a].City:GetReligion():GetMajorityReligion();
		bCity = t[b].City:GetReligion():GetMajorityReligion();
		if aCity > 0 and bCity > 0 then 
			-- both cities have religion
			if descend then return bCity > aCity else return bCity < aCity end
		elseif aCity > 0 then
			-- only A has religion, must ALWAYS be before B
			return true
		elseif bCity > 0 then
			-- only B has religion, must ALWAYS be before A
		end
		-- none has, check pantheons
		aCity = t[a].City:GetReligion():GetActivePantheon();
		bCity = t[b].City:GetReligion():GetActivePantheon();
		if aCity > 0 and bCity > 0 then 
			-- both cities have a pantheon
			if descend then return bCity > aCity else return bCity < aCity end
		elseif aCity > 0 then
			-- only A has pantheon, must ALWAYS be before B
			return true
		elseif bCity > 0 then
			-- only B has pantheon, must ALWAYS be before A
		end
		-- none has, no more checks
		return false
	else
		-- nothing to do here
	end
	
	if descend then return bCity > aCity else return bCity < aCity end

end

function ViewCityStatusPage()
	print("ViewCityStatusPage");
	
	if g_DirtyFlag.CITYSTATUS then UpdateCityStatusData(); end

	ResetTabForNewPageContent();

	local instance:table = m_simpleIM:GetInstance();
	instance.Top:DestroyAllChildren();
	
	instance.Children = {}
	instance.Descend = true
	
	local pHeaderInstance:table = {};
	ContextPtr:BuildInstanceForControl( "CityStatusHeaderInstance", pHeaderInstance, instance.Top );
	
	pHeaderInstance.CityGovernorButton:SetShow(bIsRiseFall or bIsGatheringStorm);
	pHeaderInstance.CityLoyaltyButton:SetShow(bIsRiseFall or bIsGatheringStorm);
	
	pHeaderInstance.CityReligionButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "religion", instance ) end )
	pHeaderInstance.CityNameButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "name", instance ) end )
	if bIsRiseFall or bIsGatheringStorm then pHeaderInstance.CityGovernorButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "gover", instance ) end ) end -- Infixo
	if bIsRiseFall or bIsGatheringStorm then pHeaderInstance.CityLoyaltyButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "loyal", instance ) end ) end -- Infixo
	pHeaderInstance.CityPopulationButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "pop", instance ) end )
	--pHeaderInstance.CityHousingButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "house", instance ) end ) end -- Infixo
	pHeaderInstance.CityGrowthButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "growth", instance ) end )
	pHeaderInstance.CityAmenitiesButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "amen", instance ) end )
	pHeaderInstance.CityHappinessButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "happy", instance ) end )
	--pHeaderInstance.CityWarButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "war", instance ) end )
	pHeaderInstance.CityDistrictsButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "districts", instance ) end )
	pHeaderInstance.CityStatusButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "status", instance ) end )
	pHeaderInstance.CityStrengthButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "str", instance ) end )
	pHeaderInstance.CityDamageButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "dam", instance ) end )
	pHeaderInstance.CityTradingPostButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "trpost", instance ) end );
	pHeaderInstance.CityTradeRoutesButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_cities( "numtr", instance ) end );

	-- 
	for _, kCityData in spairs( m_kCity1Data, function( t, a, b ) return city_sortFunction( true, "name", t, a, b ); end ) do -- initial sort by name ascending

		local pCityInstance:table = {}

		ContextPtr:BuildInstanceForControl( "CityStatusEntryInstance", pCityInstance, instance.Top );
		table.insert( instance.Children, pCityInstance );
		
		city_fields( kCityData, pCityInstance );

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
	m_kCurrentTab = 3;
end

print("BRS: Loaded file BRSPage_CityStatus.lua");
