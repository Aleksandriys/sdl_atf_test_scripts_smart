---------------------------------------------------------------------------------------------
-- Requirement summary:
-- [UI Interface] SDL behavior in case HMI does not respond to UI.IsReady_request
-- [HMI_API] UI.IsReady
-- [MOBILE_API] SetAudioStreamingIndicator
-- [HMI_API] [MOBILE_API] AudioStreamingIndicator enum
-- [HMI_API] SetAudioStreamingIndicator
--
-- Description:
-- In case SDL does NOT receive UI.IsReady_response during <DefaultTimeout> from HMI
-- and mobile app sends SetAudioStreamingIndicator (any single UI-related RPC)
-- SDL must:
-- transfer this UI-related RPC to HMI
-- respond with <received_resultCode_from_HMI> to mobile app
--
-- 1. Used preconditions
-- structure hmi_result_code with HMI result codes, success = true
-- Allow SetAudioStreamingIndicator by policy
-- In InitHMI_OnReady HMI does not replies to UI.Isready
-- Register and activate media application.
--
-- 2. Performed steps
-- Send SetAudioStreamingIndicator(audioStreamingIndicator)
-- audioStreamingIndicator is changing in loop PAUSE - PLAY
-- HMI->SDL: UI.SetAudioStreamingIndicator(resultcode: hmi_result_code)
--
-- Expected result:
-- SDL->HMI: UI.SetAudioStreamingIndicator(audioStreamingIndicator)
-- SDL->mobile: SetAudioStreamingIndicator_response(hmi_result_code, success:true)
---------------------------------------------------------------------------------------------

--[[ General configuration parameters ]]
config.deviceMAC = "12ca17b49af2289436f303e0166030a21e525d266e209267433801a8fd4071a0"
config.application1.registerAppInterfaceParams.appHMIType = {"MEDIA"}
config.application1.registerAppInterfaceParams.isMediaApplication = true

--[[ Required Shared libraries ]]
local commonFunctions = require ('user_modules/shared_testcases/commonFunctions')
local commonSteps = require('user_modules/shared_testcases/commonSteps')
local commonPreconditions = require('user_modules/shared_testcases/commonPreconditions')
local testCasesForUI_IsReady = require('user_modules/IsReady_Template/testCasesForUI_IsReady')
local testCasesForPolicyTable = require('user_modules/shared_testcases/testCasesForPolicyTable')
local mobile_session = require('mobile_session')


--[[ Local variables ]]
-- in scope of the CRQ info parameter is not specified, but will be left for any future use.
local hmi_result_code = {
	{ result_code = "SUCCESS", info = "" },
	{ result_code = "WARNINGS", info = "" },
	{ result_code = "WRONG_LANGUAGE", info = "" },
	{ result_code = "RETRY", info = "" },
	{ result_code = "SAVED", info = "" },
	{ result_code = "UNSUPPORTED_RESOURCE", info = "" },
}

--[[ General Precondition before ATF start ]]
testCasesForPolicyTable:precondition_updatePolicy_AllowFunctionInHmiLeves({"BACKGROUND", "FULL", "LIMITED"}, "SetAudioStreamingIndicator")
commonSteps:DeleteLogsFiles()

--TODO(istoimenova): shall be removed when issue: "ATF does not stop HB timers by closing session and connection" is fixed
config.defaultProtocolVersion = 2

--[[ General Settings for configuration ]]
Test = require('user_modules/connecttest_initHMI')
require('user_modules/AppTypes')

--[[ Preconditions ]]
commonFunctions:newTestCasesGroup("Preconditions")

function Test:Precondition_InitHMI_OnReady()
	testCasesForUI_IsReady.InitHMI_onReady_without_UI_IsReady(self, 1)
	EXPECT_HMICALL("UI.IsReady")
	-- Do not send HMI response of UI.IsReady
end

function Test:Precondition_connectMobile()
	self:connectMobile()
end

function Test:Precondition_StartSession()
	self.mobileSession = mobile_session.MobileSession(self, self.mobileConnection)
	self.mobileSession:StartService(7)
end

commonSteps:RegisterAppInterface("Precondition_RegisterAppInterface")

function Test:Precondition_ActivateApp()
  commonSteps:ActivateAppInSpecificLevel(self, self.applications[config.application1.registerAppInterfaceParams.appName])
  EXPECT_NOTIFICATION("OnHMIStatus", {systemContext = "MAIN", hmiLevel = "FULL"})
end

--[[ Test ]]
commonFunctions:newTestCasesGroup("Test")

for i = 1, #hmi_result_code do
  local IndicatorValue = "PAUSE"

  if ( math.fmod(i,2) ~= 0 ) then
    IndicatorValue = "PAUSE"
  else
    IndicatorValue = "PLAY"
  end

	Test["TestStep_SetAudioStreamingIndicator_"..hmi_result_code[i].result_code.."_audioStreamingIndicator_" .. IndicatorValue] = function(self)
	  local corr_id = self.mobileSession:SendRPC("SetAudioStreamingIndicator", { audioStreamingIndicator = IndicatorValue })

	  EXPECT_HMICALL("UI.SetAudioStreamingIndicator", { audioStreamingIndicator = IndicatorValue })
	  :Do(function(_,data) self.hmiConnection:SendResponse(data.id, data.method, hmi_result_code[i].result_code) end)

	  EXPECT_RESPONSE(corr_id, { success = true, resultCode = hmi_result_code[i].result_code})
	  EXPECT_NOTIFICATION("OnHashChange",{}):Times(0)
	end
end

--[[ Postconditions ]]
commonFunctions:newTestCasesGroup("Postconditions")
function Test.Postcondition_Restore_preloaded_pt()
	commonPreconditions:RestoreFile("sdl_preloaded_pt.json")
end

function Test.Postcondition_Stop()
  StopSDL()
end

return Test