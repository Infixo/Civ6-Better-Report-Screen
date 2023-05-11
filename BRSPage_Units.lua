-- ===========================================================================
-- Better Report Screen - page Units
-- Author: Infixo
-- 2023-05-10: Created
-- ===========================================================================

m_kUnitDataReport = nil; -- global for debug purposes
m_kModifiersUnits = nil; -- to show various abilities and effects

-- support for mods that add new formation classes
local m_kSupportedFormationClasses: table = {
	FORMATION_CLASS_CIVILIAN = true,
	FORMATION_CLASS_LAND_COMBAT = true,
	FORMATION_CLASS_NAVAL = true,
	FORMATION_CLASS_SUPPORT = true,
	FORMATION_CLASS_AIR = true,
};

-- 230425 #7 cache for storing list of units for abilities
g_AbilitiesUnits = {}; -- this is based on TypeTags table, so it is static

--BRS !! Added function to sort out tables for units
-- Infixo: this is only used by Upgrade Callback; parent will be used a flag; must be set to nil when leaving report screen
local tUnitSort = { type = "", group = "", parent = nil };

function GetDataUnits()
	print("GetDataUnits");
	
	local playerID: number = Game.GetLocalPlayer();
	if playerID == PlayerTypes.NONE or platerID == PlayerTypes.OBSERVER then
		UI.DataError("Unable to get valid playerID for report screen.");
		return;
	end
	
	local player	:table  = Players[playerID];
	local pTreasury	:table	= player:GetTreasury();
	local MaintenanceDiscountPerUnit:number = pTreasury:GetMaintDiscountPerUnit(); -- this will be used in 2 reports
	local pUnits    :table  = player:GetUnits(); -- 230425 moved
	local kUnitDataReport:table = {};
	local group_name:string;
	local tUnitsDist:table = {}; -- temp table for calculating units' distance from cities

	--Timer2Start();
	for _, unit in pUnits:Members() do
		--print("unit", unit:GetID());
		local unitInfo:table = GameInfo.Units[unit:GetUnitType()];
		local formationClass:string = unitInfo.FormationClass; -- FORMATION_CLASS_CIVILIAN, FORMATION_CLASS_LAND_COMBAT, FORMATION_CLASS_NAVAL, FORMATION_CLASS_SUPPORT, FORMATION_CLASS_AIR
		-- categorize
		group_name = string.sub(formationClass, 17);
		if formationClass == "FORMATION_CLASS_CIVILIAN" then
			-- need to split into sub-classes
			if unit:GetGreatPerson():IsGreatPerson() then group_name = "GREAT_PERSON";
			elseif unitInfo.MakeTradeRoute then           group_name = "TRADER";
			elseif unitInfo.Spy then                      group_name = "SPY";
			elseif unit:GetReligiousStrength() > 0 then group_name = "RELIGIOUS";
			end
		end
		-- tweak to handle new, unknown formation classes
		if not m_kSupportedFormationClasses[formationClass] then
			print("WARNING: GetDataUnits Unknown formation class", formationClass, "for unit", unitInfo.UnitType);
			group_name = "SUPPORT";
		end
		-- store for Units tab report
		if kUnitDataReport[group_name] == nil then
			if     group_name == "LAND_COMBAT" then  kUnitDataReport[group_name] = { ID= 1, func= group_military, Header= "UnitsMilitaryHeaderInstance",   Entry= "UnitsMilitaryEntryInstance" };
			elseif group_name == "NAVAL" then        kUnitDataReport[group_name] = { ID= 2, func= group_military, Header= "UnitsMilitaryHeaderInstance",   Entry= "UnitsMilitaryEntryInstance" };
			elseif group_name == "AIR" then          kUnitDataReport[group_name] = { ID= 3, func= group_military, Header= "UnitsMilitaryHeaderInstance",   Entry= "UnitsMilitaryEntryInstance" };
			elseif group_name == "SUPPORT" then      kUnitDataReport[group_name] = { ID= 4, func= group_military, Header= "UnitsMilitaryHeaderInstance",   Entry= "UnitsMilitaryEntryInstance" };
			elseif group_name == "CIVILIAN" then     kUnitDataReport[group_name] = { ID= 5, func= group_civilian, Header= "UnitsCivilianHeaderInstance",   Entry= "UnitsCivilianEntryInstance" };
			elseif group_name == "RELIGIOUS" then    kUnitDataReport[group_name] = { ID= 6, func= group_religious,Header= "UnitsReligiousHeaderInstance",  Entry= "UnitsReligiousEntryInstance" };
			elseif group_name == "GREAT_PERSON" then kUnitDataReport[group_name] = { ID= 7, func= group_great,    Header= "UnitsGreatPeopleHeaderInstance",Entry= "UnitsGreatPeopleEntryInstance" };
			elseif group_name == "SPY" then          kUnitDataReport[group_name] = { ID= 8, func= group_spy,      Header= "UnitsSpyHeaderInstance",        Entry= "UnitsSpyEntryInstance" };
			elseif group_name == "TRADER" then       kUnitDataReport[group_name] = { ID= 9, func= group_trader,   Header= "UnitsTraderHeaderInstance",     Entry= "UnitsTraderEntryInstance" };
			end
			--print("...creating a new unit group", formationClass, group_name);
			kUnitDataReport[group_name].Name = "LOC_BRS_UNITS_GROUP_"..group_name;
			kUnitDataReport[group_name].units = {};
		end
		table.insert( kUnitDataReport[group_name].units, unit );
		-- add some unit specific data
		unit.MaintenanceAfterDiscount = math.max(GetUnitMaintenance(unit) - MaintenanceDiscountPerUnit, 0); -- cannot go below 0
		-- store data for distance calculations
		unit.NearCityDistance = 9999;
		unit.NearCityName = "";
		unit.NearCityIsCapital = false;
		unit.NearCityIsOurs = true;
		-- Gathering Storm
		if bIsGatheringStorm then
			unit.ResMaint = "";
			local unitInfoXP2:table = GameInfo.Units_XP2[ unitInfo.UnitType ];
			if unitInfoXP2 ~= nil and unitInfoXP2.ResourceMaintenanceType ~= nil then
				unit.ResMaint = "[ICON_"..unitInfoXP2.ResourceMaintenanceType.."]";
			end
		end
		-- Rock Band
		unit.IsRockBand = false;
		unit.RockBandAlbums = 0;
		unit.RockBandLevel = 0;
		if bIsGatheringStorm and unitInfo.PromotionClass == "PROMOTION_CLASS_ROCK_BAND" then
			unit.IsRockBand = true;
			unit.RockBandAlbums = unit:GetRockBand():GetAlbumSales();
			unit.RockBandLevel = unit:GetRockBand():GetRockBandLevel();
		end
		table.insert( tUnitsDist, unit );
	end
	--Timer2Tick("GetDataUnits: main loop"); -- insignificant
	
	-- calculate distance to the closest city for all units
	-- must iterate through all living players and their cities
	--print("GetDataUnits: calculate distance");
	--Timer2Start();
	for _,player in ipairs(PlayerManager.GetAlive()) do
		local bIsOurs:boolean = ( player:GetID() == playerID );
		for _,city in player:GetCities():Members() do
			local iCityX:number, iCityY:number = city:GetX(), city:GetY();
			local sCityName:string = Locale.Lookup( city:GetName() );
			local bIsCapital:boolean = city:IsCapital();
			for _,unit in ipairs(tUnitsDist) do
				local iDistance:number = Map.GetPlotDistance( unit:GetX(), unit:GetY(), iCityX, iCityY );
				if iDistance < unit.NearCityDistance then
					unit.NearCityDistance = iDistance;
					unit.NearCityName = sCityName;
					unit.NearCityIsCapital = bIsCapital;
					unit.NearCityIsOurs = bIsOurs;
				end
			end
		end
	end
	--Timer2Tick("GetDataUnits: distance"); -- insignificant
	
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
	--print("GetDataUnits: modifiers");
	--Timer2Start();
	m_kModifiersUnits ={}; -- clear main table
	local tTrackedUnits:table = {};
	for _,unit in player:GetUnits():Members() do
		tTrackedUnits[ unit:GetID() ] = true;
		m_kModifiersUnits[ unit:GetID() ] = {};
	end
	
	-- main loop
	for _,instID in ipairs(GameEffects.GetModifiers()) do
		local iOwnerID:number = GameEffects.GetModifierOwner( instID );
		--local iPlayerID:number = GameEffects.GetObjectsPlayerId( iOwnerID );
		local sOwnerType:string = GameEffects.GetObjectType( iOwnerID ); -- LOC_MODIFIER_OBJECT_CITY, LOC_MODIFIER_OBJECT_PLAYER, LOC_MODIFIER_OBJECT_GOVERNOR
		local sOwnerName:string = GameEffects.GetObjectName( iOwnerID ); -- LOC_CITY_xxx_NAME, LOC_LEADER_xxx_NAME, etc.
		local tSubjects:table = GameEffects.GetModifierSubjects( instID ); -- table of objectIDs or nil
		--print("checking", instID, sOwnerName, sOwnerType, iOwnerID, iPlayerID); -- debug
		
		local function RegisterModifierForUnit(iUnitID:number, sSubjectType:string, sSubjectName:string)
			-- 230511 allocate memory only when registering
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
			--print("registering for unit", iUnitID, data.ID, sSubjectType, sSubjectName);
			-- fix for sudden changes in modifier system, like Veterancy changed in March 2018 patch
			-- some modifiers might be removed, but still are attached to objects from old games
			-- the game itself seems to be resistant to such situation
			if data.Modifier == nil then print("WARNING! GetDataUnits/Modifiers: Ignoring non-existing modifier", data.ID, data.Definition.Id, sOwnerName, sSubjectName); return end
			data.UnitID = iUnitID;
			if sSubjectType == nil or sSubjectName == nil then
				data.SubjectType = nil;
				data.SubjectName = nil;
			else -- register as subject
				data.SubjectType = sSubjectType;
				data.SubjectName = sSubjectName;
			end
			-- 230425 #7 filter out the modifiers from abilities that do not match the unit's class
			-- 
			local isValid: boolean = false;
			if data.Modifier.EffectType == "EFFECT_GRANT_ABILITY" then
				local ability: string = data.Arguments.AbilityType;
				local unit: table = pUnits:FindID(iUnitID);
				if unit then
					local unitType: string = GameInfo.Units[unit:GetUnitType()].UnitType;
					if g_AbilitiesUnits[ability] and g_AbilitiesUnits[ability][unitType] then isValid = true; end
				end
			else
				isValid = true; -- we don't check other effects, but could be extended later
			end
			if isValid then table.insert(m_kModifiersUnits[iUnitID], data); end
			-- debug output
			--print("--------- Tracking", iUnitID, data.ID, sOwnerType, sOwnerName, sSubjectName);
			--print("- Valid?", isValid and "yes" or "NO");
			--for k,v in pairs(data) do print(k,v); end
			--print("- Modifier:", data.Definition.Id);
			--print("- Collection:", data.Modifier.CollectionType);
			--print("- Effect:", data.Modifier.EffectType);
			--print("- Arguments:");
			--for k,v in pairs(data.Arguments) do print(k,v); end -- debug
		end
		
		-- this part is for units as subjects; to make it more unified it will simply analyze all subjects' sets
		if tSubjects then
			for _,subjectID in ipairs(tSubjects) do
				-- 230511 check if ours at all
				if GameEffects.GetObjectsPlayerId(subjectID) == playerID then
					local sSubjectType:string = GameEffects.GetObjectType( subjectID );
					local sSubjectName:string = GameEffects.GetObjectName( subjectID );
					if sSubjectType == "LOC_MODIFIER_OBJECT_UNIT" then
						-- find a unit
						local sSubjectString:string = GameEffects.GetObjectString( subjectID );
						local iUnitID:number      = tonumber( string.match(sSubjectString, "Unit: (%d+)") );
						local iUnitOwnerID:number = tonumber( string.match(sSubjectString, "Owner: (%d+)") );
						--print("unit:", sSubjectString, "decode:", iUnitOwnerID, iUnitID);
						if iUnitID and iUnitOwnerID and iUnitOwnerID == playerID and tTrackedUnits[iUnitID] then
							RegisterModifierForUnit(iUnitID, sSubjectType, sSubjectName);
						end
					end -- if unit
				end -- if ours
			end -- subjects
		end
		
		-- 230511 Units very often (always?) have itself as a subject, so it is more prudent to first check
		-- subjects and then only add those modifiers that are new; otherwise there will be duplicates as 
		-- the same modifiers will be registered from owner check and then subject check
		-- this part is for units as owners, we need to decode the unit and see if it's ours
		
		local function IsRegistered(iUnitID: number)
			if not m_kModifiersUnits[iUnitID] then return false; end
			for _,mod in ipairs( m_kModifiersUnits[iUnitID] ) do
				if mod.ID == instID then return true; end
			end
			return false;
		end
		
		if GameEffects.GetObjectsPlayerId(iOwnerID) == playerID and sOwnerType == "LOC_MODIFIER_OBJECT_UNIT" then
			-- find a unit
			local sOwnerString:string = GameEffects.GetObjectString( iOwnerID );
			local iUnitID:number      = tonumber( string.match(sOwnerString, "Unit: (%d+)") );
			local iUnitOwnerID:number = tonumber( string.match(sOwnerString, "Owner: (%d+)") );
			--print("unit:", sOwnerString, "decode:", iUnitOwnerID, iUnitID);
			if iUnitID and iUnitOwnerID and iUnitOwnerID == playerID and tTrackedUnits[iUnitID] and not IsRegistered(iUnitID) then
				RegisterModifierForUnit(iUnitID);
			end
		end
		
	end
	--Timer2Tick("GetDataUnits: modifiers"); -- this part takes like 95% of the entire function, approx. 60 milisecs to process 10000 modifiers
	--print("--------------"); print("FOUND MODIFIERS FOR UNITS"); for k,v in pairs(m_kModifiersUnits) do print(k, #v); end

	return kUnitDataReport;
end

function UpdateUnitsData()
	print("UpdateUnitsData");
	Timer1Start();
	m_kUnitDataReport = GetDataUnits();
	Timer1Tick("UpdateUnitsData");
	g_DirtyFlag.UNITS = false;
end

-- returns the name of the City that the unit is currently in, or ""
function GetCityForUnit(pUnit:table)
	local pCity:table = Cities.GetCityInPlot( pUnit:GetX(), pUnit:GetY() );
	return ( pCity and Locale.Lookup(pCity:GetName()) ) or "";
end

-- returns the icon for the District that the unit is currently in, or ""
function GetDistrictIconForUnit(pUnit:table)
	local pPlot:table = Map.GetPlot( pUnit:GetX(), pUnit:GetY() );
	if not pPlot then return ""; end -- assert
	local eDistrictType:number = pPlot:GetDistrictType();
	--print("Unit", pUnit:GetName(), eDistrictType);
	if eDistrictType < 0 then return ""; end
	local sDistrictType:string = GameInfo.Districts[ eDistrictType ].DistrictType;
	if GameInfo.DistrictReplaces[ sDistrictType ] then sDistrictType = GameInfo.DistrictReplaces[ sDistrictType ].ReplacesDistrictType; end
	return GetFontIconForDistrict(sDistrictType);
end

function unit_sortFunction( descend, type, t, a, b )
	local aUnit, bUnit

	if type == "type" then
		aUnit = UnitManager.GetTypeName( t[a] )
		bUnit = UnitManager.GetTypeName( t[b] )
	elseif type == "name" then
		aUnit = Locale.Lookup( t[a]:GetName() )
		bUnit = Locale.Lookup( t[b]:GetName() )
		if aUnit == bUnit then
			aUnit = t[a]:GetMilitaryFormation()
			bUnit = t[b]:GetMilitaryFormation()
		end
	elseif type == "maintenance" then
		aUnit = t[a].MaintenanceAfterDiscount;
		bUnit = t[b].MaintenanceAfterDiscount;
	elseif type == "status" then
		aUnit = UnitManager.GetActivityType( t[a] )
		bUnit = UnitManager.GetActivityType( t[b] )
	elseif type == "level" then
		aUnit = t[a]:GetExperience():GetLevel();
		bUnit = t[b]:GetExperience():GetLevel();
	elseif type == "exp" then
		aUnit = t[a]:GetExperience():GetExperiencePoints()
		bUnit = t[b]:GetExperience():GetExperiencePoints()
	elseif type == "health" then
		aUnit = t[a]:GetMaxDamage() - t[a]:GetDamage()
		bUnit = t[b]:GetMaxDamage() - t[b]:GetDamage()
	elseif type == "move" then
		if ( t[a]:GetFormationUnitCount() > 1 ) then
			aUnit = t[a]:GetFormationMovesRemaining()
		else
			aUnit = t[a]:GetMovesRemaining()
		end
		if ( t[b]:GetFormationUnitCount() > 1 ) then
			bUnit = t[b]:GetFormationMovesRemaining()
		else
			bUnit = t[b]:GetMovesRemaining()
		end
	elseif type == "charge" then
		aUnit = t[a]:GetBuildCharges()
		bUnit = t[b]:GetBuildCharges()
	elseif type == "yield" then
		aUnit = t[a].yields
		bUnit = t[b].yields
	elseif type == "route" then
		aUnit = t[a].route
		bUnit = t[b].route
	elseif type == "class" then
		aUnit = t[a]:GetGreatPerson():GetClass()
		bUnit = t[b]:GetGreatPerson():GetClass()
	elseif type == "strength" then
		aUnit = t[a]:GetReligiousStrength()
		bUnit = t[b]:GetReligiousStrength()
	elseif type == "spread" then
		aUnit = t[a]:GetSpreadCharges()
		bUnit = t[b]:GetSpreadCharges()
	elseif type == "mission" then
		aUnit = t[a].mission
		bUnit = t[b].mission
	elseif type == "turns" then
		aUnit = t[a].turns
		bUnit = t[b].turns
	elseif type == "city" then
		aUnit = t[a].NearCityName
		bUnit = t[b].NearCityName
		if aUnit == bUnit then
			aUnit = t[a].NearCityDistance
			bUnit = t[b].NearCityDistance
		end
		--[[
		if aUnit ~= "" and bUnit ~= "" then 
			if descend then return aUnit > bUnit else return aUnit < bUnit end
		else
			if     aUnit == "" then return false;
			elseif bUnit == "" then return true;
			else                    return false; end
		end
		--]]
	elseif type == "albums" then
		aUnit = t[a].RockBandAlbums;
		bUnit = t[b].RockBandAlbums;
		--[[
		if bIsGatheringStorm and GameInfo.Units[t[a]:GetUnitType()].PromotionClass == "PROMOTION_CLASS_ROCK_BAND" then
			aUnit = t[a]:GetRockBand():GetAlbumSales();
		end
		if bIsGatheringStorm and GameInfo.Units[t[b]:GetUnitType()].PromotionClass == "PROMOTION_CLASS_ROCK_BAND" then
			bUnit = t[b]:GetRockBand():GetAlbumSales();
		end
		--]]
	else
		return false; -- assert
	end
	
	if descend then return aUnit > bUnit else return aUnit < bUnit end
	
end

function sort_units( type, group, parent )

	local i = 0
	local unit_group = m_kUnitDataReport[group]
	
	for _, unit in spairs( unit_group.units, function( t, a, b ) return unit_sortFunction( parent.Descend, type, t, a, b ) end ) do
		i = i + 1
		local unitInstance = parent.Children[i]
		
		common_unit_fields( unit, unitInstance )
		if unit_group.func then unit_group.func( unit, unitInstance, group, parent, type ) end
		
		unitInstance.LookAtButton:RegisterCallback( Mouse.eLClick, function() Close(); UI.LookAtPlot( unit:GetX( ), unit:GetY( ) ); UI.SelectUnit( unit ); end )
		unitInstance.LookAtButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound( "Main_Menu_Mouse_Over" ); end )
	end
	
end

function common_unit_fields( unit, unitInstance )

	--if unitInstance.Formation then unitInstance.Formation:SetHide( true ) end

	local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas( "ICON_" .. UnitManager.GetTypeName( unit ), 32 )
	unitInstance.UnitType:SetTexture( textureOffsetX, textureOffsetY, textureSheet )
	--unitInstance.UnitType:SetToolTipString( Locale.Lookup( GameInfo.Units[UnitManager.GetTypeName( unit )].Name ) )
	unitInstance.UnitType:SetToolTipString( Locale.Lookup(GameInfo.Units[unit:GetUnitType()].Name).."[NEWLINE]"..Locale.Lookup(GameInfo.Units[unit:GetUnitType()].Description) );

	-- debug section to see Modifiers for all units
	--[[
	local tPromoTT:table = {};
	table.insert(tPromoTT, Locale.Lookup( GameInfo.Units[UnitManager.GetTypeName( unit )].Name ));
	local tUnitModifiers:table = m_kModifiersUnits[ unit:GetID() ];
	if table.count(tUnitModifiers) > 0 then table.insert(tPromoTT, TOOLTIP_SEP); end
	local i = 0;
	for _,mod in ipairs(tUnitModifiers) do
		i = i + 1;
		table.insert(tPromoTT, i..". "..Locale.Lookup(mod.OwnerName)..": "..mod.Modifier.ModifierId.." ("..RMA.GetObjectNameForModifier(mod.Modifier.ModifierId)..") "..mod.Modifier.EffectType.." "..( mod.Modifier.Text and "|"..Locale.Lookup(mod.Modifier.Text).."|" or "-"));
	end
	unitInstance.UnitType:SetToolTipString( table.concat(tPromoTT, "[NEWLINE]") );
	--]]

	unitInstance.UnitName:SetText( Locale.Lookup(unit:GetName()) );
	
	-- adds the status icon
	local activityType:number = UnitManager.GetActivityType( unit )
	--print("Unit", unit:GetID(),activityType,unit:GetSpyOperation(),unit:GetSpyOperationEndTurn());
	unitInstance.UnitStatus:SetHide( false )
	local bIsMoving:boolean = true; -- Infixo
	
	if activityType == ActivityTypes.ACTIVITY_SLEEP then
		local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas( "ICON_STATS_SLEEP", 22 )
		unitInstance.UnitStatus:SetTexture( textureOffsetX, textureOffsetY, textureSheet )
		bIsMoving = false;
	elseif activityType == ActivityTypes.ACTIVITY_HOLD then
		local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas( "ICON_STATS_SKIP", 22 )
		unitInstance.UnitStatus:SetTexture( textureOffsetX, textureOffsetY, textureSheet )
	elseif activityType ~= ActivityTypes.ACTIVITY_AWAKE and unit:GetFortifyTurns() > 0 then
		local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas( "ICON_DEFENSE", 22 )
		unitInstance.UnitStatus:SetTexture( textureOffsetX, textureOffsetY, textureSheet )
		bIsMoving = false;
	else
		-- just use a random icon for sorting purposes
		local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas( "ICON_STATS_SPREADCHARGES", 22 )
		unitInstance.UnitStatus:SetTexture( textureOffsetX, textureOffsetY, textureSheet )
		unitInstance.UnitStatus:SetHide( true )
	end
	if activityType == ActivityTypes.ACTIVITY_SENTRY then bIsMoving = false; end
	if unit:GetSpyOperation() ~= -1 then bIsMoving = false; end
	
	-- moves here to mark units that should move this turn
	if ( unit:GetFormationUnitCount() > 1 ) then
		unitInstance.UnitMove:SetText( tostring(unit:GetFormationMovesRemaining()).."/"..tostring(unit:GetFormationMaxMoves()).." [ICON_Formation]" );
		--unitInstance.Formation:SetHide( false )
		unitInstance.UnitMove:SetToolTipString( Locale.Lookup("LOC_HUD_UNIT_ACTION_AUTOEXPLORE_IN_FORMATION") );
	elseif unitInstance.UnitMove then
		if unit:GetMovesRemaining() == 0 then bIsMoving = false; end
		unitInstance.UnitMove:SetText( (bIsMoving and "[COLOR_Red]" or "")..tostring( unit:GetMovesRemaining() ).."/"..tostring( unit:GetMaxMoves() )..(bIsMoving and "[ENDCOLOR]" or "") )
		unitInstance.UnitMove:SetToolTipString( "" );
	end
	
	unit.District = GetDistrictIconForUnit(unit);
	unitInstance.UnitDistrict:SetText(unit.District);
	--unit.City = GetCityForUnit(unit);
	--unitInstance.UnitCity:SetText(unit.City);
	local sCityName:string = ( unit.NearCityIsCapital and "[ICON_Capital]" or "" )..unit.NearCityName;
	if     unit.NearCityDistance == 0 then sCityName = "[COLOR:16,232,75,160]"..sCityName.."[ENDCOLOR]";
	elseif unit.NearCityIsOurs        then sCityName = sCityName.." "..unit.NearCityDistance;
	else                                   sCityName = "[COLOR_Red]"..sCityName.." "..unit.NearCityDistance.."[ENDCOLOR]"; end
	unitInstance.UnitCity:SetText( (unit.NearCityDistance > 3) and "" or sCityName );
	
	unitInstance.UnitMaintenance:SetText( toPlusMinusString(-unit.MaintenanceAfterDiscount) );
	if bIsGatheringStorm then
		unitInstance.UnitMaintenance:SetText( unit.ResMaint..tostring(unit.MaintenanceAfterDiscount));
	end
end

-- simple texts for modifiers' effects
local tTextsForEffects:table = {
	EFFECT_ATTACH_MODIFIER = "LOC_GREATPERSON_PASSIVE_NAME_DEFAULT",
	EFFECT_ADJUST_UNIT_EXTRACT_SEA_ARTIFACTS = "[ICON_RESOURCE_SHIPWRECK]",
	EFFECT_ADJUST_UNIT_NUM_ATTACKS = "LOC_PROMOTION_WOLFPACK_DESCRIPTION",
	EFFECT_ADJUST_UNIT_ATTACK_AND_MOVE = "LOC_PROMOTION_GUERRILLA_DESCRIPTION",
	EFFECT_ADJUST_UNIT_MOVE_AND_ATTACK = "LOC_PROMOTION_GUERRILLA_DESCRIPTION",
	EFFECT_ADJUST_UNIT_BYPASS_COMBAT_UNIT = "LOC_ABILITY_BYPASS_COMBAT_UNIT_NAME",
	EFFECT_ADJUST_UNIT_IGNORE_TERRAIN_COST = "LOC_ABILITY_IGNORE_TERRAIN_COST_NAME", -- Arguments.Type = ALL HILLS FOREST
	EFFECT_ADJUST_UNIT_PARADROP_ABILITY = "LOC_UNITCOMMAND_PARADROP_DESCRIPTION",
	EFFECT_ADJUST_UNIT_SEE_HIDDEN = "LOC_ABILITY_SEE_HIDDEN_NAME",
	EFFECT_ADJUST_UNIT_HIDDEN_VISIBILITY = "LOC_ABILITY_STEALTH_NAME",
	EFFECT_ADJUST_UNIT_RAIDING = "LOC_ABILITY_COASTAL_RAID_NAME",
	EFFECT_ADJUST_UNIT_IGNORE_RIVERS = "LOC_PROMOTION_AMPHIBIOUS_NAME",
	EFFECT_ADJUST_UNIT_IGNORE_SHORES = "[ICON_CheckmarkBlue]{LOC_UNITOPERATION_DISEMBARK_DESCRIPTION}",
	EFFECT_ADJUST_PLAYER_RANDOM_CIVIC_BOOST_GOODY_HUT = "{LOC_HUD_POPUP_CIVIC_BOOST_UNLOCKED}[ICON_CivicBoosted]",
	EFFECT_ADJUST_PLAYER_RANDOM_TECHNOLOGY_BOOST_GOODY_HUT = "{LOC_HUD_POPUP_TECH_BOOST_UNLOCKED}[ICON_TechBoosted]",
};

function group_military( unit, unitInstance, group, parent, type )

	-- for military we'll show its base strength also
	local eFormation:number = unit:GetMilitaryFormation();
	local iCombat:number, iRanged:number, iBombard:number = unit:GetCombat(), unit:GetRangedCombat(), unit:GetBombardCombat();
	
	-- name will be: name .. formation .. strength
	local sText:string = Locale.Lookup( unit:GetName() );
	if     eFormation == MilitaryFormationTypes.CORPS_FORMATION then sText = sText .. " [ICON_Corps]";
	elseif eFormation == MilitaryFormationTypes.ARMY_FORMATION  then sText = sText .. " [ICON_Army]" ;
	end
	if     iBombard > 0 then sText = sText.." [ICON_Bombard]"..tostring(iBombard);
	elseif iRanged > 0  then sText = sText.." [ICON_Ranged]"..tostring(iRanged);
	elseif iCombat > 0  then sText = sText.." [ICON_Strength]"..tostring(iCombat);
	end
	unitInstance.UnitName:SetText( sText );

	-- Level and Promotions
	local unitExp : table = unit:GetExperience()
	local iUnitLevel:number = unitExp:GetLevel();
	if     iUnitLevel < 2  then unitInstance.UnitLevel:SetText( tostring(iUnitLevel) );
	elseif iUnitLevel == 2 then unitInstance.UnitLevel:SetText( tostring(iUnitLevel).." [ICON_Promotion]" );
	else                        unitInstance.UnitLevel:SetText( tostring(iUnitLevel).." [ICON_Promotion]"..string.rep("*", iUnitLevel-2) ); end
	local tPromoTT:table = {};
	for _,promo in ipairs(unitExp:GetPromotions()) do
		table.insert(tPromoTT, Locale.Lookup(GameInfo.UnitPromotions[promo].Name)..": "..Locale.Lookup(GameInfo.UnitPromotions[promo].Description));
	end
	-- this section might grow!
	local tUnitModifiers:table = m_kModifiersUnits[ unit:GetID() ];
	--local isDebug: boolean = (unit:GetID() == 8781824); -- debug, will show only a specific unit
	local tMod:table = nil;
	local sText:string = "";
	if table.count(tUnitModifiers) > 0 then table.insert(tPromoTT, TOOLTIP_SEP); end
	local iPromoNum:number = 0;
	--local tExtraTT:table = {};
	for _,mod in ipairs(tUnitModifiers) do
		--if isDebug then dshowrectable(mod); end
		local function AddExtraPromoText(sText:string)
			--if isDebug then print("AddExtraPromoText", mod.OwnerName, mod.Modifier.ModifierId, sText); end
			local sExtra:string = Locale.Lookup(mod.OwnerName).." ("..RMA.GetObjectNameForModifier(mod.Modifier.ModifierId)..") "..sText;
			--for _,txt in ipairs(tExtraTT) do if txt == sExtra then return; end end -- check if already added, do not add duplicates -- 230511 buggy, as e.g. armory and military xp bonus produce the same string
			iPromoNum = iPromoNum + 1;
			table.insert(tPromoTT, tonumber(iPromoNum)..". "..sExtra);
			--table.insert(tExtraTT, sExtra);
		end
		tMod = mod.Modifier;
		sText = ""; if tMod.Text then sText = Locale.Lookup(tMod.Text); end
		if sText ~= "" then
			AddExtraPromoText( sText );
		elseif tMod.EffectType == "EFFECT_ADJUST_PLAYER_STRENGTH_MODIFIER" or tMod.EffectType == "EFFECT_ADJUST_UNIT_DIPLO_VISIBILITY_COMBAT_MODIFIER" then
            if tMod.Arguments.Amount ~= nil then
                AddExtraPromoText( string.format("%+d [ICON_Strength]", tonumber(tMod.Arguments.Amount))); -- Strength
            elseif tMod.Arguments.Max ~= nil then
                AddExtraPromoText( string.format("%+d [ICON_Strength]", tonumber(tMod.Arguments.Max))); -- Vampires, stregth from Barbs
            else
                AddExtraPromoText( "[ICON_Strength]" ); -- Vampires, strength
            end
		elseif tMod.EffectType == "EFFECT_GRANT_ABILITY" then
			local unitAbility:table = GameInfo.UnitAbilities[ tMod.Arguments.AbilityType ];
			if unitAbility and unitAbility.Name and unitAbility.Description then -- 2019-08-30 some Abilities have neither Name nor Description
				AddExtraPromoText( Locale.Lookup(unitAbility.Name)..": "..Locale.Lookup(unitAbility.Description)); -- LOC_CIVICS_KEY_ABILITY
			else
				AddExtraPromoText( tMod.EffectType.." [COLOR_Red]"..tMod.Arguments.AbilityType.."[ENDCOLOR]")
			end
		elseif tMod.EffectType == "EFFECT_GRANT_PROMOTION" then
			local unitPromotion:table = GameInfo.UnitPromotions[ tMod.Arguments.PromotionType ];
			if unitPromotion then
				AddExtraPromoText( Locale.Lookup(unitPromotion.Name)..": "..Locale.Lookup(unitPromotion.Description));
			else
				AddExtraPromoText( tMod.EffectType.." [COLOR_Red]"..tMod.Arguments.PromotionType.."[ENDCOLOR]")
			end
		elseif tMod.EffectType == "EFFECT_ADJUST_UNIT_EXPERIENCE_MODIFIER" then
			AddExtraPromoText( string.format("%+d%% ", tonumber(tMod.Arguments.Amount))..Locale.Lookup("LOC_HUD_UNIT_PANEL_XP")); -- +x%
		elseif tMod.EffectType == "EFFECT_ADJUST_UNIT_FLANKING_BONUS_MODIFIER" then
			AddExtraPromoText( Locale.Lookup("LOC_COMBAT_PREVIEW_FLANKING_BONUS_DESC", tMod.Arguments.Percent.."%") ); -- +x%
		elseif tMod.EffectType == "EFFECT_ADJUST_UNIT_SEA_MOVEMENT" or tMod.EffectType == "EFFECT_ADJUST_UNIT_MOVEMENT" then
			AddExtraPromoText( string.format("%+d [ICON_Movement]", tonumber(tMod.Arguments.Amount))); -- Movement
		elseif tMod.EffectType == "EFFECT_ADJUST_UNIT_VALID_TERRAIN" then
			AddExtraPromoText( Locale.Lookup( GameInfo.Terrains[tMod.Arguments.TerrainType].Name ) );
		elseif tMod.EffectType == "EFFECT_ADJUST_UNIT_ATTACK_RANGE" then
			AddExtraPromoText( string.format("%+d [ICON_Range]", tonumber(tMod.Arguments.Amount)));
		elseif tTextsForEffects[tMod.EffectType] then
			AddExtraPromoText( Locale.Lookup(tTextsForEffects[tMod.EffectType]) );
		elseif tMod.EffectType == "EFFECT_ADJUST_UNIT_STRENGTH_REDUCTION_FOR_DAMAGE_MODIFIER" then
			AddExtraPromoText( string.format("[ICON_Damaged] -%d%%", tonumber(tMod.Arguments.Amount)) ); -- +x%
		elseif tMod.EffectType == "EFFECT_ADJUST_UNIT_POST_COMBAT_HEAL" then
			AddExtraPromoText( Locale.Lookup("LOC_BRS_HEADER_HEALTH")..string.format(" %+d", tonumber(tMod.Arguments.Amount)) ); -- +x HP
		elseif tMod.EffectType == "EFFECT_ADJUST_UNIT_BARBARIAN_COMBAT" then
			local iAdvStr:number = tonumber(tMod.Arguments.Amount);
			AddExtraPromoText( string.gsub(Locale.Lookup("LOC_COMBAT_PREVIEW_BONUS_VS_BARBARIANS", iAdvStr), "+"..tostring(iAdvStr), "+"..tostring(iAdvStr).." [ICON_Strength]") );  -- +{1_Value} Advantage vs. Barbarians
		elseif tMod.EffectType == "EFFECT_ADJUST_UNIT_SUPPORT_BONUS_MODIFIER" then
			AddExtraPromoText( Locale.Lookup("LOC_COMBAT_PREVIEW_SUPPORT_BONUS_DESC", tonumber(tMod.Arguments.Percent)) ); -- +x% support bonus
		else
			AddExtraPromoText( "[COLOR_Grey]"..tMod.EffectType.."[ENDCOLOR]" );
		end
	end
	unitInstance.UnitLevel:SetToolTipString( table.concat(tPromoTT, "[NEWLINE]") );
	
	-- XP and Promotion Available
	local bCanStart, tResults = UnitManager.CanStartCommand( unit, UnitCommandTypes.PROMOTE, true, true );
	unitInstance.UnitExp:SetText( tostring(unitExp:GetExperiencePoints()).."/"..tostring(unitExp:GetExperienceForNextLevel())..((bCanStart and tResults) and " [ICON_Promotion]" or "") );
	unitInstance.UnitExp:SetToolTipString( (bCanStart and tResults) and Locale.Lookup("LOC_HUD_UNIT_ACTION_AUTOEXPLORE_PROMOTION_AVAILABLE") or "" );

	-- Unit Health
	local iHealthPoints:number = unit:GetMaxDamage() - unit:GetDamage();
	local fHealthPercent:number = iHealthPoints / unit:GetMaxDamage();
	local sHealthColor:string = "";
	-- Common format is 0xBBGGRRAA (BB blue, GG green, RR red, AA alpha); stupid Firaxis - it's 0xAABBGGRR
	if     fHealthPercent > 0.7 then sHealthColor = "[COLOR:16,232,75,160]";   -- COLORS.METER_HP_GOOD 0xFF4BE810
	elseif fHealthPercent > 0.4 then sHealthColor = "[COLOR:248,255,45,160]";  -- COLORS.METER_HP_OK   0xFF2DFFF8
	else                             sHealthColor = "[COLOR:245,1,1,160]"; end -- COLORS.METER_HP_BAD  0xFF0101F5
	unitInstance.UnitHealth:SetText( sHealthColor..tostring(iHealthPoints).."/"..tostring(unit:GetMaxDamage()).."[ENDCOLOR]" );
	
	-- upgrade flag
	unitInstance.Upgrade:SetHide( true )
	--ARISTOS: a "looser" test for the Upgrade action, to be able to show the disabled arrow if Upgrade is not possible
	local bCanStart = UnitManager.CanStartCommand( unit, UnitCommandTypes.UPGRADE, true);
	if ( bCanStart ) then
		unitInstance.Upgrade:SetHide( false )
		--ARISTOS: Now we "really" test if we can Upgrade the unit!
		local bCanStartNow, tResults = UnitManager.CanStartCommand( unit, UnitCommandTypes.UPGRADE, false, true);
		unitInstance.Upgrade:SetDisabled(not bCanStartNow);
		unitInstance.Upgrade:SetAlpha((not bCanStartNow and 0.5) or 1 ); --ARISTOS: dim if not upgradeable
		-- upgrade callback
		unitInstance.Upgrade:RegisterCallback( Mouse.eLClick, function()
			-- the only case where we need to re-sort units preserving current order
			-- actual re-sort must be done in Event, otherwise unit info is not refreshed (ui cache?)
			tUnitSort.type = type; tUnitSort.group = group; tUnitSort.parent = parent;
			UnitManager.RequestCommand( unit, UnitCommandTypes.UPGRADE );
		end )
		-- tooltip
		local upgradeToUnit:table = GameInfo.Units[tResults[UnitCommandResults.UNIT_TYPE]];
		local toolTipString:string = Locale.Lookup( "LOC_UNITOPERATION_UPGRADE_INFO", Locale.Lookup(upgradeToUnit.Name), unit:GetUpgradeCost() ); -- Upgrade to {1_Unit}: {2_Amount} [ICON_Gold]Gold
		-- Gathering Storm
		if bIsGatheringStorm then toolTipString = toolTipString .. AddUpgradeResourceCost(unit, upgradeToUnit); end
		if tResults[UnitOperationResults.FAILURE_REASONS] then
			-- Add the reason(s) to the tool tip
			for i,v in ipairs(tResults[UnitOperationResults.FAILURE_REASONS]) do
				toolTipString = toolTipString .. "[NEWLINE]" .. "[COLOR:Red]" .. Locale.Lookup(v) .. "[ENDCOLOR]";
			end
		end
		unitInstance.Upgrade:SetToolTipString( toolTipString );
	end
	
end

-- modified function from UnitPanel_Expansion2.lua, adds also maintenance resource cost
function AddUpgradeResourceCost( pUnit:table, upgradeToUnitInfo:table )
	local toolTipString:string = "";
	-- requires
	local upgradeResource, upgradeResourceCost = pUnit:GetUpgradeResourceCost();
	if (upgradeResource ~= nil and upgradeResource >= 0) then
		local resourceName:string = Locale.Lookup(GameInfo.Resources[upgradeResource].Name);
		local resourceIcon = "[ICON_" .. GameInfo.Resources[upgradeResource].ResourceType .. "]";
		toolTipString = toolTipString .. "[NEWLINE]" .. Locale.Lookup("LOC_UNITOPERATION_UPGRADE_RESOURCE_INFO", upgradeResourceCost, resourceIcon, resourceName); -- Requires: {1_Amount} {2_ResourceIcon} {3_ResourceName}
	end
	-- maintenance info
	local unitInfoXP2:table = GameInfo.Units_XP2[ upgradeToUnitInfo.UnitType ];
	if unitInfoXP2 ~= nil then
		-- upgrade to unit name
		toolTipString = toolTipString.."[NEWLINE]"..Locale.Lookup(upgradeToUnitInfo.Name).." [ICON_GoingTo]";
		-- gold
		if upgradeToUnitInfo.Maintenance > 0 then
			toolTipString = toolTipString.." "..Locale.Lookup("LOC_TOOLTIP_BASE_COST", upgradeToUnitInfo.Maintenance, "[ICON_Gold]", "LOC_YIELD_GOLD_NAME"); -- Base Cost: {1_Amount} {2_YieldIcon} {3_YieldName}
		end
		-- resources
		if unitInfoXP2.ResourceMaintenanceType ~= nil then
			local resourceName:string = Locale.Lookup(GameInfo.Resources[ unitInfoXP2.ResourceMaintenanceType ].Name);
			local resourceIcon = "[ICON_" .. GameInfo.Resources[unitInfoXP2.ResourceMaintenanceType].ResourceType .. "]";
			toolTipString = toolTipString.." "..Locale.Lookup("LOC_UNIT_PRODUCTION_FUEL_CONSUMPTION", unitInfoXP2.ResourceMaintenanceAmount, resourceIcon, resourceName); -- Consumes: {1_Amount} {2_Icon} {3_FuelName} per turn.
		end
	end
	return toolTipString;
end

function group_civilian( unit, unitInstance, group, parent, type )

	ShowUnitPromotions(unit, unitInstance);
	unitInstance.UnitCharges:SetText( tostring(unit:GetBuildCharges()) );
	unitInstance.UnitAlbums:SetText("");
	
	if unit.IsRockBand then
		unitInstance.UnitCharges:SetText("");
		unitInstance.UnitAlbums:SetText( tostring(unit.RockBandAlbums) );
	end
	
end

function group_great( unit, unitInstance, group, parent, type )

	unitInstance.UnitClass:SetText( Locale.Lookup( GameInfo.GreatPersonClasses[unit:GetGreatPerson():GetClass()].Name ) )

end

function ShowUnitPromotions(unit:table, unitInstance:table)
	-- Level and Promotions
	local tPromoTT:table = {};
	for _,promo in ipairs(unit:GetExperience():GetPromotions()) do
		table.insert(tPromoTT, Locale.Lookup(GameInfo.UnitPromotions[promo].Name)..": "..Locale.Lookup(GameInfo.UnitPromotions[promo].Description));
	end
	local sLevel:string = "";
	if unit.IsRockBand then sLevel = tostring(unit.RockBandLevel); end
	if     #tPromoTT == 0 then unitInstance.UnitLevel:SetText(sLevel);
	elseif #tPromoTT == 1 then unitInstance.UnitLevel:SetText(sLevel.." [ICON_Promotion]");
	else                       unitInstance.UnitLevel:SetText(sLevel.." [ICON_Promotion]"..string.rep("*", #tPromoTT-1) ); end
	unitInstance.UnitLevel:SetToolTipString( table.concat(tPromoTT, "[NEWLINE]") );
end

function group_religious( unit, unitInstance, group, parent, type )

	ShowUnitPromotions(unit, unitInstance);
	unitInstance.UnitSpreads:SetText( unit:GetSpreadCharges() )
	unitInstance.UnitStrength:SetText( unit:GetReligiousStrength() )

end

function group_spy( unit, unitInstance, group, parent, type )

	ShowUnitPromotions(unit, unitInstance);

	-- operation
	local operationType : number = unit:GetSpyOperation();
	
	unitInstance.UnitOperation:SetText( "-" );
	unitInstance.UnitTurns:SetText( "[COLOR_Red]0[ENDCOLOR]" );
	unit.mission = "-";
	unit.turns = 0;

	if ( operationType ~= -1 ) then
		-- Mission Name
		local operationInfo:table = GameInfo.UnitOperations[operationType];
		unit.mission = Locale.Lookup( operationInfo.Description );
		unitInstance.UnitOperation:SetText( unit.mission );
		-- Turns Remaining
		unit.turns = unit:GetSpyOperationEndTurn() - Game.GetCurrentGameTurn()
		--unitInstance.UnitTurns:SetText( Locale.Lookup( "LOC_UNITPANEL_ESPIONAGE_MORE_TURNS", unit:GetSpyOperationEndTurn() - Game.GetCurrentGameTurn() ) )
		unitInstance.UnitTurns:SetText( tostring(unit.turns) );
	end

end

function group_trader( unit, unitInstance, group, parent, type )

	local owningPlayer:table = Players[unit:GetOwner()];
	local cities:table = owningPlayer:GetCities();
	--[[
	local yieldtype: table = {
		YIELD_FOOD = "[ICON_Food]",
		YIELD_PRODUCTION = "[ICON_Production]",
		YIELD_GOLD = "[ICON_Gold]",
		YIELD_SCIENCE = "[ICON_Science]",
		YIELD_CULTURE = "[ICON_Culture]",
		YIELD_FAITH = "[ICON_Faith]",
	};
	--]]
	local yields : string = ""
	
	unitInstance.UnitYields:SetText( "" );
	unitInstance.UnitRoute:SetText( "[COLOR_Red]"..Locale.Lookup("LOC_UNITOPERATION_MAKE_TRADE_ROUTE_DESCRIPTION") );
	unit.yields = ""
	unit.route = "No Route"

	for _, city in cities:Members() do
		local outgoingRoutes:table = city:GetTrade():GetOutgoingRoutes();
	
		for i,route in ipairs(outgoingRoutes) do
			if unit:GetID() == route.TraderUnitID then
				-- Find origin city
				local originCity:table = cities:FindID(route.OriginCityID);

				-- Find destination city
				local destinationPlayer:table = Players[route.DestinationCityPlayer];
				local destinationCities:table = destinationPlayer:GetCities();
				local destinationCity:table = destinationCities:FindID(route.DestinationCityID);

				-- Set origin to destination name
				if originCity and destinationCity then
					unitInstance.UnitRoute:SetText( Locale.Lookup("LOC_HUD_UNIT_PANEL_TRADE_ROUTE_NAME", originCity:GetName(), destinationCity:GetName()) )
					unit.route = Locale.Lookup("LOC_HUD_UNIT_PANEL_TRADE_ROUTE_NAME", originCity:GetName(), destinationCity:GetName())
				end

				for j, yieldInfo in pairs( route.OriginYields ) do
					if yieldInfo.Amount > 0 then
						yields = yields .. GameInfo.Yields[yieldInfo.YieldIndex].IconString .. toPlusMinusString(yieldInfo.Amount);
						unitInstance.UnitYields:SetText( yields )
						unit.yields = yields
					end
				end
			end
		end
	end
	
end

function ViewUnitsPage()
	print("ViewUnitsPage");
	
	if g_DirtyFlag.UNITS then UpdateUnitsData(); end

	ResetTabForNewPageContent();
	tUnitSort.parent = nil;
	
	for iUnitGroup, kUnitGroup in spairs( m_kUnitDataReport, function( t, a, b ) return t[b].ID > t[a].ID end ) do
		local instance : table = NewCollapsibleGroupInstance()
		
		instance.RowHeaderButton:SetText( Locale.Lookup(kUnitGroup.Name) );
		instance.RowHeaderLabel:SetHide( false ); --BRS
		instance.RowHeaderLabel:SetText( Locale.Lookup("LOC_HUD_REPORTS_TOTALS").." "..tostring(#kUnitGroup.units) );
		instance.AmenitiesContainer:SetHide(true);
        instance.IndustryContainer:SetHide(true); -- 2021-05-21
        instance.MonopolyContainer:SetHide(true); -- 2021-05-21
		
		local pHeaderInstance:table = {}
		ContextPtr:BuildInstanceForControl( kUnitGroup.Header, pHeaderInstance, instance.ContentStack )

		-- Infixo: important info - iUnitGroup is NOT integer nor table, it is a STRING taken from FORMATION_CLASS_xxx
		if pHeaderInstance.UnitTypeButton then     pHeaderInstance.UnitTypeButton:RegisterCallback(    Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "type", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitNameButton then     pHeaderInstance.UnitNameButton:RegisterCallback(    Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "name", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitStatusButton then   pHeaderInstance.UnitStatusButton:RegisterCallback(  Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "status", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitLevelButton then    pHeaderInstance.UnitLevelButton:RegisterCallback(   Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "level", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitExpButton then      pHeaderInstance.UnitExpButton:RegisterCallback(     Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "exp", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitHealthButton then   pHeaderInstance.UnitHealthButton:RegisterCallback(  Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "health", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitMoveButton then     pHeaderInstance.UnitMoveButton:RegisterCallback(    Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "move", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitChargeButton then   pHeaderInstance.UnitChargeButton:RegisterCallback(  Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "charge", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitYieldButton then    pHeaderInstance.UnitYieldButton:RegisterCallback(   Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "yield", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitRouteButton then    pHeaderInstance.UnitRouteButton:RegisterCallback(   Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "route", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitClassButton then    pHeaderInstance.UnitClassButton:RegisterCallback(   Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "class", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitStrengthButton then pHeaderInstance.UnitStrengthButton:RegisterCallback(Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "strength", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitSpreadButton then   pHeaderInstance.UnitSpreadButton:RegisterCallback(  Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "spread", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitMissionButton then  pHeaderInstance.UnitMissionButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "mission", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitTurnsButton then    pHeaderInstance.UnitTurnsButton:RegisterCallback(   Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "turns", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitCityButton then     pHeaderInstance.UnitCityButton:RegisterCallback(    Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "city", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitMaintenanceButton then pHeaderInstance.UnitMaintenanceButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "maintenance", iUnitGroup, instance ) end ) end
		if pHeaderInstance.UnitAlbumsButton then
			if bIsGatheringStorm then
				pHeaderInstance.UnitAlbumsButton:RegisterCallback( Mouse.eLClick, function() instance.Descend = not instance.Descend; sort_units( "albums", iUnitGroup, instance ) end );
			else
				pHeaderInstance.UnitAlbumsLabel:SetText("");
			end
		end

		instance.Descend = false;
		for _,unit in spairs( kUnitGroup.units, function( t, a, b ) return unit_sortFunction( false, "name", t, a, b ) end ) do -- initial sort by name ascending
			local unitInstance:table = {}
			table.insert( instance.Children, unitInstance )
			
			ContextPtr:BuildInstanceForControl( kUnitGroup.Entry, unitInstance, instance.ContentStack );
			
			common_unit_fields( unit, unitInstance )
			
			if kUnitGroup.func then kUnitGroup.func( unit, unitInstance, iUnitGroup, instance, "name" ) end
			
			-- allows you to select a unit and zoom to them
			unitInstance.LookAtButton:RegisterCallback( Mouse.eLClick, function() Close(); UI.LookAtPlot( unit:GetX( ), unit:GetY( ) ); UI.SelectUnit( unit ); end )
			unitInstance.LookAtButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound( "Main_Menu_Mouse_Over" ); end )
		end

		SetGroupCollapsePadding(instance, 0); --pFooterInstance.Top:GetSizeY() )
		RealizeGroup( instance );
	end

	Controls.Stack:CalculateSize();
	Controls.Scroll:CalculateSize();
	
	Controls.CollapseAll:SetHide( false );
	Controls.BottomYieldTotals:SetHide( true )
	Controls.BottomResourceTotals:SetHide( true )
	Controls.BottomPoliciesFilters:SetHide( true );
	Controls.BottomMinorsFilters:SetHide( true );
	Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - SIZE_HEIGHT_PADDING_BOTTOM_ADJUST );
	-- Remember this tab when report is next opened: ARISTOS
	m_kCurrentTab = 6;
end

-- 230425 create cache that stores units assigned to abilities
function InitializeAbilitiesUnits()
	-- first pass - extract all abilities and assigned classes
	for row in GameInfo.TypeTags() do
		if string.sub(row.Type, 1, 8) == "ABILITY_" then
			if g_AbilitiesUnits[row.Type] == nil then g_AbilitiesUnits[row.Type] = {}; end
			g_AbilitiesUnits[row.Type][row.Tag] = true;
		end
	end
	-- second pass - extract units
	for row in GameInfo.TypeTags() do
		if string.sub(row.Type, 1, 5) == "UNIT_" then
			-- register the unit for all abilities that have its class
			for _,units in pairs(g_AbilitiesUnits) do -- key is not important now
				if units[row.Tag] then units[row.Type] = true; end
			end
		end
	end
end

function InitializeUnits()
	Events.UnitUpgraded.Add(
		function()
			if ContextPtr:IsHidden() then return; end
			-- refresh data and re-sort group which upgraded unit was from
			--m_kUnitDataReport = GetDataUnits();
			UpdateUnitsData();
			sort_units( tUnitSort.type, tUnitSort.group, tUnitSort.parent );
		end );
end

print("BRS: Loaded file BRSPage_Units.lua");
