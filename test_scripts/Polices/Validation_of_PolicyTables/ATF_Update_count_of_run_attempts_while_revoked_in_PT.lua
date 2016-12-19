---------------------------------------------------------------------------------------------
-- Requirement summary:
--   [Policies] "usage_and_error_counts" and "count_of_run_attempts_while_revoked" update
--
-- Description:
-- SDL is built with "-DEXTENDED_POLICY: EXTERNAL_PROPRIETARY" flag
--     Incrementing value in 'count_of_run_attempts_while_revoked' section of LocalPT
--     1. Used preconditions:
--        Delete SDL log file and policy table
--        Close current connection
--        Make backup copy of preloaded PT
--        Overwrite preloaded PT adding list of groups for specific app
--        Connect device
--        Register app
--        Revoke app group by PTU
--
--     2. Performed steps
--        Activate revoked app
--        Check "count_of_run_attempts_while_revoked" value of LocalPT
--
-- Expected result:
--        PoliciesManager increments "count_of_run_attempts_while_revoked" at PolicyTable
---------------------------------------------------------------------------------------------------------
--[[ General configuration parameters ]]
config.deviceMAC = "12ca17b49af2289436f303e0166030a21e525d266e209267433801a8fd4071a0"

--[[ Required Shared libraries ]]
local commonFunctions = require ('user_modules/shared_testcases/commonFunctions')
local commonSteps = require('user_modules/shared_testcases/commonSteps')
local testCasesForPolicyTable = require('user_modules/shared_testcases/testCasesForPolicyTable')

--[[ Local Variables ]]
local HMIAppID
local appID = "0000001"

--[[ General Precondition before ATF start ]]
commonSteps:DeleteLogsFileAndPolicyTable()
testCasesForPolicyTable.Delete_Policy_table_snapshot()

--[[ General Settings for configuration ]]
Test = require('connecttest')
require('user_modules/AppTypes')
require('cardinalities')

--[[ Precondtions]]
commonFunctions:newTestCasesGroup("Preconditions")
function Test:Precondition_trigger_getting_device_consent()
  testCasesForPolicyTable:trigger_getting_device_consent(self, config.application1.registerAppInterfaceParams.appName, config.deviceMAC)
end

function Test:TestStep_PTU_appPermissionsConsentNeeded_true()
  local RequestIdGetURLS = self.hmiConnection:SendRequest("SDL.GetURLS", { service = 7 })
  EXPECT_HMIRESPONSE(RequestIdGetURLS,{result = {code = 0, method = "SDL.GetURLS", urls = {{url = "http://policies.telematics.ford.com/api/policies"}}}})
  :Do(function(_,_)
  self.hmiConnection:SendNotification("BasicCommunication.OnSystemRequest", { requestType = "PROPRIETARY", fileName = "filename"})

  EXPECT_NOTIFICATION("OnSystemRequest", { requestType = "PROPRIETARY" })
  :Do(function(_,_)
  self.mobileSession:SendRPC("SystemRequest", { fileName = "PolicyTableUpdate", requestType = "PROPRIETARY"},
  "files/PTU_NewPermissionsForUserConsent.json")

  local systemRequestId
  EXPECT_HMICALL("BasicCommunication.SystemRequest")
  :Do(function(_,data)
  systemRequestId = data.id
  self.hmiConnection:SendNotification("SDL.OnReceivedPolicyUpdate", { policyfile = "/tmp/fs/mp/images/ivsu_cache/PolicyTableUpdate"})

  local function to_run()
    self.hmiConnection:SendResponse(systemRequestId,"BasicCommunication.SystemRequest", "SUCCESS", {})
  end
  RUN_AFTER(to_run, 500)
  end)

  EXPECT_HMINOTIFICATION("SDL.OnStatusUpdate", {status = "UPDATING"}, {status = "UP_TO_DATE"}):Times(2)
  :Do(function(_,data)
  if(data.params.status == "UP_TO_DATE") then

    EXPECT_HMINOTIFICATION("SDL.OnAppPermissionChanged",
    {appID = self.applications[config.application1.registerAppInterfaceParams.appName], appPermissionsConsentNeeded = true })
    :Do(function(_,_)
    local RequestIdListOfPermissions = self.hmiConnection:SendRequest("SDL.GetListOfPermissions",
    { appID = self.applications[config.application1.registerAppInterfaceParams.appName]})

    EXPECT_HMIRESPONSE(RequestIdListOfPermissions)
    :Do(function(_,data1)
    local groups = {}
    if #data1.result.allowedFunctions > 0 then
      for i = 1, #data1.result.allowedFunctions do
        groups[i] = {
          name = data1.result.allowedFunctions[i].name,
          id = data1.result.allowedFunctions[i].id,
          allowed = true}
        end
      end
      self.hmiConnection:SendNotification("SDL.OnAppPermissionConsent", { appID = self.applications[config.application1.registerAppInterfaceParams.appName], consentedFunctions = groups, source = "GUI"})
      EXPECT_NOTIFICATION("OnPermissionsChange")
      end)
      end)
    end
    end)
    end)
    end)
  end

  function Test:Precondition_trigger_user_request_update_from_HMI()
    testCasesForPolicyTable:trigger_user_request_update_from_HMI(self)
  end

  function Test:Precondition_PTU_revoke_app()
    HMIAppID = self.applications[config.application1.registerAppInterfaceParams.appName]
    local RequestIdGetURLS = self.hmiConnection:SendRequest("SDL.GetURLS", { service = 7 })
    EXPECT_HMIRESPONSE(RequestIdGetURLS,{result = {code = 0, method = "SDL.GetURLS", urls = {{url = "http://policies.telematics.ford.com/api/policies"}}}})
    :Do(function()
    self.hmiConnection:SendNotification("BasicCommunication.OnSystemRequest", { requestType = "PROPRIETARY", fileName = "filename"})

    EXPECT_NOTIFICATION("OnSystemRequest", { requestType = "PROPRIETARY" })
    :Do(function()
    local CorIdSystemRequest = self.mobileSession:SendRPC("SystemRequest",
    { fileName = "PolicyTableUpdate", requestType = "PROPRIETARY"}, "files/PTU_AppRevokedGroup.json")

    EXPECT_HMICALL("BasicCommunication.SystemRequest")
    :Do(function(_,data)
    self.hmiConnection:SendNotification("SDL.OnReceivedPolicyUpdate", { policyfile = "/tmp/fs/mp/images/ivsu_cache/PolicyTableUpdate"})

    local function to_run()
      self.hmiConnection:SendResponse(data.id,"BasicCommunication.SystemRequest", "SUCCESS", {})
    end
    RUN_AFTER(to_run, 500)
    self.mobileSession:ExpectResponse(CorIdSystemRequest, {success = true, resultCode = "SUCCESS"})
    end)

    EXPECT_HMINOTIFICATION("SDL.OnStatusUpdate",
    {status = "UPDATING"}, {status = "UP_TO_DATE"}):Times(2)
    :Do(function(_,data)
    if(data.params.status == "UP_TO_DATE") then
      EXPECT_HMINOTIFICATION("SDL.OnAppPermissionChanged", {appID = HMIAppID, isAppPermissionsRevoked = true, appRevokedPermissions = {"DataConsent"}})
      :Do(function(_,_)
      local RequestIdListOfPermissions = self.hmiConnection:SendRequest("SDL.GetListOfPermissions", { appID = HMIAppID })
      EXPECT_HMIRESPONSE(RequestIdListOfPermissions)
      :Do(function()
      local ReqIDGetUserFriendlyMessage = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", {language = "EN-US", messageCodes = {"AppPermissionsRevoked"}})
      EXPECT_HMIRESPONSE(ReqIDGetUserFriendlyMessage, { result = { code = 0, messages = {{ messageCode = "AppPermissionsRevoked"}}, method = "SDL.GetUserFriendlyMessage"}})
      end)
      end)
    end
    end)
    end)
    end)

    EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "NONE", systemContext = "MAIN", audioStreamingState = "NOT_AUDIBLE" })
  end

  --[[ Test ]]
  commonFunctions:newTestCasesGroup("Test")
  function Test:TestStep1_Activate_app_isAppPermissionRevoked_true()
    local RequestIdActivateAppAgain = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = self.applications[config.application1.registerAppInterfaceParams.appName] })
    EXPECT_HMIRESPONSE(RequestIdActivateAppAgain, { result = { code = 0, method = "SDL.ActivateApp", isAppRevoked = true}})
  end

  function Test:TestStep2_Check_count_of_run_attempts_while_revoked_incremented_in_PT()
    local file = io.open("/tmp/fs/mp/images/ivsu_cache/sdl_snapshot.json", "r")
    local json_data = file:read("*all") -- may be abbreviated to "*a";
    file:close()
    local json = require("modules/json")
    local data = json.decode(json_data)
    local CountOfAttemptsWhileRevoked = data.policy_table.usage_and_error_counts.app_level[appID].count_of_run_attempts_while_revoked
    if CountOfAttemptsWhileRevoked == 1 then
      return true
    else
      self:FailTestCase("Wrong count_of_run_attempts_while_revoked. Expected: " .. 1 .. ", Actual: " .. CountOfAttemptsWhileRevoked)
    end
  end

  --[[ Postconditions ]]
  commonFunctions:newTestCasesGroup("Postconditions")
  testCasesForPolicyTable:Restore_preloaded_pt()

  function Test.Postcondition_StopSDL()
    StopSDL()
  end