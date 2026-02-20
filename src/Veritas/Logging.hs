-- | Structured logging via katip.
module Veritas.Logging
  ( initLogEnv
  , closeLogEnv
  , LogEnv
  , Severity(..)
  , logMsg
  , Namespace
  , runKatipT
  , KatipT
  , ls
  , showLS
  , LogStr
  ) where

import qualified Katip
import Katip (LogEnv, Severity(..), logMsg, Namespace, runKatipT, KatipT, ls, showLS, LogStr)
import Katip (mkHandleScribeWithFormatter, mkHandleScribe, jsonFormat, ColorStrategy(..), permitItem, Verbosity(..))
import Katip (registerScribe, defaultScribeSettings)
import System.IO (stdout)
import System.Environment (lookupEnv)

-- | Initialize a LogEnv with a stdout scribe.
-- Uses VERITAS_LOG_FORMAT to choose between JSON ("json") and bracket (default).
-- Uses VERITAS_LOG_LEVEL to set minimum severity (default "InfoS").
initLogEnv :: IO LogEnv
initLogEnv = do
  format <- maybe "bracket" id <$> lookupEnv "VERITAS_LOG_FORMAT"
  levelStr <- maybe "InfoS" id <$> lookupEnv "VERITAS_LOG_LEVEL"
  let severity = parseSeverity levelStr
  scribe <- case format of
    "json" -> mkHandleScribeWithFormatter jsonFormat ColorIfTerminal stdout (permitItem severity) V2
    _      -> mkHandleScribe ColorIfTerminal stdout (permitItem severity) V2
  env <- Katip.initLogEnv "veritas" "production"
  registerScribe "stdout" scribe defaultScribeSettings env

-- | Close all scribes in the log environment.
closeLogEnv :: LogEnv -> IO ()
closeLogEnv env = Katip.closeScribes env >> pure ()

-- | Parse a severity string, defaulting to InfoS.
parseSeverity :: String -> Severity
parseSeverity s = case s of
  "DebugS"     -> DebugS
  "InfoS"      -> InfoS
  "NoticeS"    -> NoticeS
  "WarningS"   -> WarningS
  "ErrorS"     -> ErrorS
  "CriticalS"  -> CriticalS
  "AlertS"     -> AlertS
  "EmergencyS" -> EmergencyS
  _            -> InfoS
