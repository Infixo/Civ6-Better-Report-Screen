print("Loading PartialScreenHooks_BRS_vanilla.lua from Better Report Screen "..GlobalParameters.BRS_VERSION_MAJOR.."."..GlobalParameters.BRS_VERSION_MINOR);
-- ===========================================================================
-- Better Report Screen
-- Author: Infixo
-- 2019-02-17: Created
-- ===========================================================================


-- ===========================================================================
-- CACHE BASE FUNCTIONS
-- ===========================================================================
include("PartialScreenHooks");
--BRS_BASE_CloseAllPopups = CloseAllPopups;
--BRS_BASE_OnInputActionTriggered = OnInputActionTriggered;

include("PartialScreenHooks_BRS");

print("OK loaded PartialScreenHooks_BRS_vanilla.lua from Better Report Screen");