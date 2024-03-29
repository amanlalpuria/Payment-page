module Engineering.Helpers.Events where

import Prelude (Unit, bind, pure, show, unit, ($), (*>), (/=), (<$>), (<<<), (<>), (=<<), (==), (>>=), (||))
import Product.Types (Account(..), Bank(..), SDKParams, SIM, UPIState(..))

import Web.Event.Event (EventType(..), Event) as DOM
import Control.Monad.Except (runExcept)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Halogen.VDom.DOM.Prop (Prop(..))
import Unsafe.Coerce as U

{-- ======= --}
{-- import Prelude --}
import Effect.Aff (launchAff_, makeAff, nonCanceler)
import Effect.Aff.AVar (new) as AVar
import Effect.Class (liftEffect)
import Effect.Timer (setTimeout)
{-- import Control.Monad.Eff.Unsafe (unsafeCoerceEff) --}
import Control.Monad.State.Trans (evalStateT) as S
{-- import DOM.Event.Types (EventType(..), Event) as DOM --}
import Data.Array (length)
import Data.Either (Either(Right, Left), hush)
import Data.Function.Uncurried (runFn2)
import Data.Lens ((^.))
import Foreign.Object (empty)
import Data.String (drop) as S
import Engineering.Helpers.Commons (callAPI', liftFlow, mkNativeRequest, showUI',  unsafeJsonStringify,  NativeRequest(..))
import Engineering.Helpers.Types.Accessor (_customerId, _orderId, _orderToken, _session_token)
import Engineering.Helpers.Utils (eligibleForUPI, upiMethodPayload, getString )
import Engineering.OS.Permission (checkIfPermissionsGranted, requestPermissions) as P
import Externals.UPI.Flow (getInstalledUPIAppsPayload)
import Externals.UPI.Types (UPIIntentPayload)
import JBridge as UPI
import Presto.Core.Flow (Flow, doAff)
import Presto.Core.Language.Runtime.API (APIRunner)
import Presto.Core.Language.Runtime.Interpreter (PermissionCheckRunner, PermissionRunner(..), PermissionTakeRunner, Runtime(..), UIRunner, run)
import Presto.Core.Utils.Encoding (defaultEncodeJSON)
import Presto.Core.Types.Language.Flow (saveS)
import Presto.Core.Types.API (defaultDecodeResponse)
import Remote.Config (encKey, merchantId, baseUrl)
import Remote.Types
import Tracker.Tracker (trackHyperPayEvent')
import UI.Utils

foreign import registerEvent :: String -> (DOM.Event → Effect Unit) -> (DOM.Event -> Effect Unit)

foreign import startUPI' :: forall a. UPIIntentPayload -> (a -> Effect Unit ) -> (forall val . val -> Effect Unit) -> Effect Unit

foreign import getPayload :: forall json. Effect {|json}

makeEvent :: forall a. (a -> Effect Unit) -> (DOM.Event → Effect Unit)
makeEvent push = \ev -> do
    _ <- push (U.unsafeCoerce ev)
    pure unit

makeLazyLoadEvent :: forall a. (a -> Effect Unit ) -> (DOM.Event → Effect Unit)
makeLazyLoadEvent push = \ev -> do
    _ <-  setTimeout 300 (push (U.unsafeCoerce ev))
    pure unit

makeGetUpiAppsEvent :: forall a. String -> (a -> Effect Unit ) -> (DOM.Event → Effect Unit)
makeGetUpiAppsEvent orderId push = \ev -> do
        _ <- startUPI' (getInstalledUPIAppsPayload (upiMethodPayload orderId)) push (trackHyperPayEvent' "response_from_upi")
        pure unit

{-- makeGetUpiEvent :: forall a. SDKParams -> Array SIM -> (a -> Effect Unit ) -> (DOM.Event → Effect Unit) --}
{-- makeGetUpiEvent sdkParams sims push = \ev -> do --}
{--         _ <- flowToEff push fn --}
{--         {1-- _ <- startUPI' (getInstalledUPIAppsPayload (upiMethodPayload orderId)) push (trackHyperPayEvent' "response_from_upi") --1} --}
{--         pure unit --}

{--     where --}
{--           fn = (upiOnboardingFlow sdkParams sims) --}

handleWalletEvent :: forall a. LinkingState -> String -> String -> String -> (a -> Effect Unit) -> (DOM.Event → Effect Unit)
handleWalletEvent st gateway otp walletId push = \ev -> do
    payload <- getPayload
    let customer_id = getString payload "customer_id"
        token = getString payload "sessionToken"
        headers = [ { field : "Content-Type", value : "application/x-www-form-urlencoded" }]
        reqBody = case st of
                       Linking -> unsafeJsonStringify $
                                    { gateway : gateway
                                    , command : "authenticate"
                                    , client_auth_token : token
                                    }
                       OTPView -> unsafeJsonStringify $
                                    { command : "link"
                                    , client_auth_token : token
                                    , otp : otp
                                    }
                       _ -> ""

        url = case st of
                   Linking -> baseUrl <> "/customers/" <> customer_id <> "/wallets"
                   OTPView -> baseUrl <> "/wallets/" <> walletId
                   _ -> ""

        req = NativeRequest
                  { method : "POST"
                  , url
                  , payload :   reqBody
                  , headers
                  }

    _ <- callAPI' (\_ -> pure unit) (push <<< U.unsafeCoerce <<< getResp) req  --  push (U.unsafeCoerce ev)
    pure unit

	where
		getResp :: String -> Maybe CreateWalletResp
		getResp = hush <<< runExcept <<< defaultDecodeResponse


onFocus :: forall a. (a -> Effect Unit) -> (Boolean -> a) -> Prop (Effect Unit)
onFocus push f = Handler (DOM.EventType "onFocus") (Just <<< (makeEvent (push <<< f <<< toBool)))

onResize :: forall a. (a -> Effect Unit) -> (Int -> a) -> Prop (Effect Unit)
onResize push f = Handler (DOM.EventType "onResize") (Just <<< (makeEvent (push <<< f)))


onClickHandleWallet :: forall a. LinkingState -> String -> String -> String -> (a ->  Effect Unit) -> (Maybe CreateWalletResp -> a) -> Prop (Effect Unit)
onClickHandleWallet st gateway otp walletId push f = Handler  (DOM.EventType "onClick") (Just <<< (handleWalletEvent st gateway otp walletId (push <<< f)))

{-- lazyLoadList :: forall a. (a -> Effect Unit ) -> (Unit -> a) -> Prop (Effect Unit) --}
{-- lazyLoadList push f = Handler (DOM.EventType "lazyLoadList") (Just <<< fn) --}
{--     where --}
{--               fn = registerEvent "lazyLoadList" (makeLazyLoadEvent (push <<< f)) --}


{-- getUpiApps :: forall a b. String -> (a -> Effect Unit ) -> (b -> a) -> Prop (Effect Unit) --}
{-- getUpiApps orderId push f = Handler (DOM.EventType "getUpiApps") (Just <<< fn) --}
{-- 	where --}
{-- 		fn = registerEvent "getUpiApps" (makeGetUpiAppsEvent orderId (push <<< f)) --}


{-- getUpi :: forall a b. SDKParams -> Array SIM -> (a -> Effect Unit ) -> (b -> a) -> Prop (Effect Unit) --}
{-- getUpi sdkParams sims push f = Handler (DOM.EventType "getUpi") (Just <<< fn) --}
{-- 	where --}
{-- 		fn = registerEvent "getUpi" (makeGetUpiEvent sdkParams sims (push <<< f)) --}


toBool :: String -> Boolean
toBool =
    case _ of
         "true" -> true
         _ -> false

cardNumberHandler :: forall b. String -> (b -> Effect Unit) -> (DOM.Event -> Effect Unit)
cardNumberHandler id push = \str -> do
	_ <- pure $ _cardNumberHanlder id str push
	pure unit

expiryHandler :: forall b. String -> (b -> Effect Unit) -> (DOM.Event -> Effect Unit)
expiryHandler id push = \str -> do
	_ <- pure $ _expiryHandler id str push
	pure unit

registerNewListener :: forall a b . (String -> (b -> Effect Unit) -> (DOM.Event -> Effect Unit)) -> String -> (a -> Effect Unit) -> (b -> a) -> Prop (Effect Unit)
registerNewListener handler id push f = Handler (DOM.EventType "onChange") (Just <<< (handler id (push <<< f)))

registerNewEvent :: forall a b . String -> (a -> Effect Unit) -> (b -> a) -> Prop (Effect Unit)
registerNewEvent eventType push f = Handler (DOM.EventType eventType) (Just <<< (makeEvent (push <<< f)))


-- foreign import timerHandlerImpl :: forall a. Int -> (a ->  Effect Unit) -> Effect Unit

-- foreign import cancelTimerHandler :: Unit -> Unit

-- timerHandler :: forall a. Int -> (a ->  Effect Unit) -> (DOM.Event → Effect Unit)
-- timerHandler time push = \ev -> do
--     _ <- timerHandlerImpl time push
--     pure unit

-- attachTimer :: forall a. Int -> (a ->  Effect Unit) -> (Int -> a) -> Prop (Effect Unit)
-- attachTimer time push f = Handler (DOM.EventType "executeTimer") (Just <<< timerHandler time (push <<< f))


getFlag :: String
getFlag = if os == "ANDROID" then "1" else "001"


flowToEff :: forall a b. ( a -> Effect Unit) -> Flow b -> Effect Unit
flowToEff push flow = do
   let runtime = Runtime uiRunner permissionRunner apiRunner
   let freeFlow = S.evalStateT (run runtime (exeFunction push flow))
   launchAff_ (AVar.new empty >>= freeFlow)
   where
     uiRunner :: UIRunner
     uiRunner a = makeAff (\cb -> do
       _ <- runFn2 showUI' (cb <<< Right) ""
       pure $ nonCanceler)

     permissionCheckRunner :: PermissionCheckRunner
     permissionCheckRunner = P.checkIfPermissionsGranted

     permissionTakeRunner :: PermissionTakeRunner
     permissionTakeRunner = P.requestPermissions

     permissionRunner :: PermissionRunner
     permissionRunner = PermissionRunner permissionCheckRunner permissionTakeRunner

     apiRunner :: APIRunner
     apiRunner request = makeAff (\cb -> do
       _ <- callAPI' (cb <<< Left) (cb <<< Right) (mkNativeRequest request)
       pure $ nonCanceler)

     exeFunction :: (a -> Effect Unit) -> Flow b -> Flow Unit
     exeFunction push' = (=<<) (\val -> doAff do (liftEffect) (push' $ U.unsafeCoerce val))

