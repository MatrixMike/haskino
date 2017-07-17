-------------------------------------------------------------------------------
-- |
-- Module      :  System.Hardware.Haskino.Data
--                Based on System.Hardware.Arduino.Data
-- Copyright   :  (c) University of Kansas
--                System.Hardware.Arduino (c) Levent Erkok
-- License     :  BSD3
-- Stability   :  experimental
--
-- Underlying data structures
-------------------------------------------------------------------------------
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures             #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NamedFieldPuns             #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}

module System.Hardware.Haskino.Data where

import           Control.Applicative
import           Control.Concurrent           (Chan, MVar, ThreadId, 
                                               withMVar, modifyMVar,
                                               modifyMVar_, putMVar,
                                               takeMVar, readMVar,
                                               newEmptyMVar)
import           Control.Monad                (ap, liftM2, forever)
import           Control.Monad.Trans
import           Control.Remote.Monad
import           Data.Bits                    ((.|.), (.&.), setBit)
import           Data.Int                     (Int8, Int16, Int32)
import           Data.List                    (intercalate)
import qualified Data.Map                     as M
import           Data.Maybe                   (listToMaybe)
import           Data.Monoid
import qualified Data.Set                     as S
import           Data.Word                    (Word8, Word16, Word32)
import           System.Hardware.Serialport   (SerialPort)

import           System.Hardware.Haskino.Expr
import           System.Hardware.Haskino.Utils

-----------------------------------------------------------------------------

-- | The Arduino remote monad
newtype Arduino a = Arduino (RemoteMonad ArduinoPrimitive a)
  deriving (Functor, Applicative, Monad)

instance MonadIO Arduino where
  liftIO m = Arduino $ primitive $ LiftIO m

type Pin  = Word8
type PinE = Expr Word8

-- Given a pin number, this function determines which port it belongs to
pinNoPortNo :: Pin -> Word8
pinNoPortNo n = n `quot` 8

-- | On the Arduino, pins are grouped into banks of 8.
-- Given a pin, this function determines which index it belongs to in its port
pinPortIndex :: Pin -> Word8
pinPortIndex p = p `rem` 8

-- | The mode for a pin.
data PinMode = INPUT
             | OUTPUT
             | INPUT_PULLUP
        deriving (Eq, Show, Enum)

-- | The mode for a triggering an interrupt on a pin.
data IntMode = LOW
             | CHANGE
             | FALLING
             | RISING
        deriving (Eq, Show, Enum)

-- | LCD's connected to the board
data LCD = LCD {
                 lcdController     :: LCDController -- ^ Actual controller
               , lcdState          :: MVar LCDData  -- ^ State information
               }

data LCDE = LCDE {
                  lcdControllerE   :: LCDController  -- ^ Actual controller
                , lcdStateE        :: LCDDataE  -- ^ State information
                }

-- | Hitachi LCD controller: See: <http://en.wikipedia.org/wiki/Hitachi_HD44780_LCD_controller>.
-- We model only the 4-bit variant, with RS and EN lines only. (The most common Arduino usage.)
-- The data sheet can be seen at: <http://lcd-linux.sourceforge.net/pdfdocs/hd44780.pdf>.
data LCDController =
    Hitachi44780 {
                       lcdRS       :: Pin  -- ^ Hitachi pin @ 4@: Register-select
                     , lcdEN       :: Pin  -- ^ Hitachi pin @ 6@: Enable
                     , lcdD4       :: Pin  -- ^ Hitachi pin @11@: Data line @4@
                     , lcdD5       :: Pin  -- ^ Hitachi pin @12@: Data line @5@
                     , lcdD6       :: Pin  -- ^ Hitachi pin @13@: Data line @6@
                     , lcdD7       :: Pin  -- ^ Hitachi pin @14@: Data line @7@
                     , lcdBL       :: Maybe Pin -- ^ Backlight control pin (if present)
                     , lcdRows     :: Word8  -- ^ Number of rows (typically 1 or 2, upto 4)
                     , lcdCols     :: Word8  -- ^ Number of cols (typically 16 or 20, upto 40)
                     , dotMode5x10 :: Bool -- ^ Set to True if 5x10 dots are used
                     }
    | I2CHitachi44780 {
                       address     :: Word8 -- ^ I2C Slave Address of LCD
                     , lcdRows     :: Word8  -- ^ Number of rows (typically 1 or 2, upto 4)
                     , lcdCols     :: Word8  -- ^ Number of cols (typically 16 or 20, upto 40)
                     , dotMode5x10 :: Bool -- ^ Set to True if 5x10 dots are used
                     }
                     deriving Show

-- | State of the LCD, a mere 8-bit word for the Hitachi
data LCDData = LCDData {
                  lcdDisplayMode    :: Word8         -- ^ Display mode (left/right/scrolling etc.)
                , lcdDisplayControl :: Word8         -- ^ Display control (blink on/off, display on/off etc.)
                , lcdGlyphCount     :: Word8         -- ^ Count of custom created glyphs (typically at most 8)
                , lcdBacklightState :: Bool
                }

data LCDDataE = LCDDataE {
                  lcdDisplayModeE    :: RemoteRef Word8         -- ^ Display mode (left/right/scrolling etc.)
                , lcdDisplayControlE :: RemoteRef Word8         -- ^ Display control (blink on/off, display on/off etc.)
                , lcdGlyphCountE     :: RemoteRef Word8         -- ^ Count of custom created glyphs (typically at most 8)
                , lcdBacklightStateE :: RemoteRef Bool
                }

-- | State of the connection
data ArduinoConnection = ArduinoConnection {
                message       :: String -> IO ()                      -- ^ Current debugging routine
              , bailOut       :: forall a. String -> [String] -> IO a -- ^ Clean-up and quit with a hopefully informative message
              , port          :: SerialPort                           -- ^ Serial port we are communicating on
              , firmwareID    :: String                               -- ^ The ID of the board (as identified by the Board itself)
              , deviceChannel :: Chan Response                        -- ^ Incoming messages from the board
              , processor     :: Processor                            -- ^ Type of processor on board
              , listenerTid   :: MVar ThreadId                        -- ^ ThreadId of the listener
              , refIndex      :: MVar Int                             -- ^ Index used for remote references
              }

type SlaveAddress = Word8
type SlaveAddressE = Expr Word8
type MinPulse = Word16
type MaxPulse = Word16
type TaskLength = Word16
type TaskID = Word8
type TaskIDE = Expr Word8
type TimeMillis = Word32
type TimeMillisE = Expr Word32
type TimeMicros = Word32
type TimeMicrosE = Expr Word32
type TaskPos = Word16
type VarSize = Word8

data ArduinoPrimitive :: * -> * where
     -- Commands
     SystemReset          :: ArduinoPrimitive () -- ^ Send system reset
     SetPinModeE          :: PinE -> Expr Word8               -> ArduinoPrimitive () -- ^ Set the mode on a pin
     DigitalPortWriteE    :: PinE -> Expr Word8 -> Expr Word8 -> ArduinoPrimitive ()
     DigitalWriteE        :: PinE -> Expr Bool                -> ArduinoPrimitive ()
     AnalogWriteE         :: PinE -> Expr Word16              -> ArduinoPrimitive ()
     ToneE                :: PinE -> Expr Word16 -> Maybe (Expr Word32) -> ArduinoPrimitive ()      -- ^ Play a tone on a pin
     NoToneE              :: PinE                              -> ArduinoPrimitive ()  -- ^ Stop playing a tone on a pin
     I2CWrite             :: SlaveAddressE -> Expr [Word8]     -> ArduinoPrimitive ()
     I2CConfig            ::                                      ArduinoPrimitive ()
     StepperSetSpeedE     :: Expr Word8 -> Expr Int32          -> ArduinoPrimitive ()
     ServoDetachE         :: Expr Word8                        -> ArduinoPrimitive ()
     ServoWriteE          :: Expr Word8 -> Expr Int16          -> ArduinoPrimitive ()
     ServoWriteMicrosE    :: Expr Word8 -> Expr Int16          -> ArduinoPrimitive ()
     CreateTaskE          :: TaskIDE    -> Arduino ()          -> ArduinoPrimitive ()
     DeleteTaskE          :: TaskIDE                           -> ArduinoPrimitive ()
     ScheduleTaskE        :: TaskIDE    -> TimeMillisE         -> ArduinoPrimitive ()
     ScheduleReset        ::                                      ArduinoPrimitive ()
     AttachIntE           :: PinE -> TaskIDE -> Expr Word8     -> ArduinoPrimitive ()
     DetachIntE           :: PinE                              -> ArduinoPrimitive ()
     Interrupts           ::                                      ArduinoPrimitive ()
     NoInterrupts         ::                                      ArduinoPrimitive ()
     GiveSemE             :: Expr Word8                        -> ArduinoPrimitive ()
     TakeSemE             :: Expr Word8                        -> ArduinoPrimitive ()
     WriteRemoteRefB      :: RemoteRef Bool    -> Expr Bool    -> ArduinoPrimitive ()
     WriteRemoteRefW8     :: RemoteRef Word8   -> Expr Word8   -> ArduinoPrimitive ()
     WriteRemoteRefW16    :: RemoteRef Word16  -> Expr Word16  -> ArduinoPrimitive ()
     WriteRemoteRefW32    :: RemoteRef Word32  -> Expr Word32  -> ArduinoPrimitive ()
     WriteRemoteRefI8     :: RemoteRef Int8    -> Expr Int8    -> ArduinoPrimitive ()
     WriteRemoteRefI16    :: RemoteRef Int16   -> Expr Int16   -> ArduinoPrimitive ()
     WriteRemoteRefI32    :: RemoteRef Int32   -> Expr Int32   -> ArduinoPrimitive ()
     WriteRemoteRefL8     :: RemoteRef [Word8] -> Expr [Word8] -> ArduinoPrimitive ()
     WriteRemoteRefFloat  :: RemoteRef Float   -> Expr Float   -> ArduinoPrimitive ()
     ModifyRemoteRefB     :: RemoteRef Bool    -> Expr Bool    -> ArduinoPrimitive ()
     ModifyRemoteRefW8    :: RemoteRef Word8   -> Expr Word8   -> ArduinoPrimitive ()
     ModifyRemoteRefW16   :: RemoteRef Word16  -> Expr Word16  -> ArduinoPrimitive ()
     ModifyRemoteRefW32   :: RemoteRef Word32  -> Expr Word32  -> ArduinoPrimitive ()
     ModifyRemoteRefI8    :: RemoteRef Int8    -> Expr Int8    -> ArduinoPrimitive ()
     ModifyRemoteRefI16   :: RemoteRef Int16   -> Expr Int16   -> ArduinoPrimitive ()
     ModifyRemoteRefI32   :: RemoteRef Int32   -> Expr Int32   -> ArduinoPrimitive ()
     ModifyRemoteRefL8    :: RemoteRef [Word8] -> Expr [Word8] -> ArduinoPrimitive ()
     ModifyRemoteRefFloat :: RemoteRef Float   -> Expr Float   -> ArduinoPrimitive ()
     Loop                 :: Arduino ()                        -> ArduinoPrimitive ()
     LoopE                :: Arduino ()                                  -> ArduinoPrimitive ()
     ForInE               :: Expr [Word8] -> (Expr Word8 -> Arduino ())  -> ArduinoPrimitive ()
     IfThenElseUnit       :: Bool -> Arduino () -> Arduino ()            -> ArduinoPrimitive ()
     IfThenElseUnitE      :: Expr Bool -> Arduino () -> Arduino ()       -> ArduinoPrimitive ()
     -- ToDo: add SPI commands
     -- Procedures
     QueryFirmware        :: ArduinoPrimitive Word16                   -- ^ Query the Firmware version installed
     QueryFirmwareE       :: ArduinoPrimitive (Expr Word16)                  -- ^ Query the Firmware version installed
     QueryProcessor       :: ArduinoPrimitive Processor                -- ^ Query the type of processor on
     QueryProcessorE      :: ArduinoPrimitive (Expr Word8)
     Micros               :: ArduinoPrimitive Word32
     MicrosE              :: ArduinoPrimitive (Expr Word32)
     Millis               :: ArduinoPrimitive Word32
     MillisE              :: ArduinoPrimitive (Expr Word32)
     DelayMillis          :: TimeMillis -> ArduinoPrimitive ()
     DelayMicros          :: TimeMicros -> ArduinoPrimitive ()
     DelayMillisE         :: TimeMillisE -> ArduinoPrimitive ()
     DelayMicrosE         :: TimeMicrosE -> ArduinoPrimitive ()
     DigitalRead          :: Pin -> ArduinoPrimitive Bool            -- ^ Read the avlue ona pin digitally
     DigitalReadE         :: PinE -> ArduinoPrimitive (Expr Bool)         -- ^ Read the avlue ona pin digitally
     DigitalPortRead      :: Pin -> Word8 -> ArduinoPrimitive Word8          -- ^ Read the values on a port digitally
     DigitalPortReadE     :: PinE -> Expr Word8 -> ArduinoPrimitive (Expr Word8)
     AnalogRead           :: Pin -> ArduinoPrimitive Word16          -- ^ Read the analog value on a pin
     AnalogReadE          :: PinE -> ArduinoPrimitive (Expr Word16)
     I2CRead              :: SlaveAddress -> Word8 -> ArduinoPrimitive [Word8]
     I2CReadE             :: SlaveAddressE -> Expr Word8 -> ArduinoPrimitive (Expr [Word8])
     Stepper2Pin          :: Word16 -> Pin -> Pin -> ArduinoPrimitive Word8
     Stepper2PinE         :: Expr Word16 -> PinE -> PinE -> ArduinoPrimitive (Expr Word8)
     Stepper4Pin          :: Word16 -> Pin -> Pin -> Pin -> Pin -> ArduinoPrimitive Word8
     Stepper4PinE         :: Expr Word16 -> PinE -> PinE -> PinE -> PinE -> ArduinoPrimitive (Expr Word8)
     StepperStepE         :: Expr Word8 -> Expr Int16 -> ArduinoPrimitive ()
     ServoAttach          :: Pin -> ArduinoPrimitive Word8
     ServoAttachE         :: PinE -> ArduinoPrimitive (Expr Word8)
     ServoAttachMinMax    :: Pin -> Int16 -> Int16 -> ArduinoPrimitive Word8
     ServoAttachMinMaxE   :: PinE -> Expr Int16 -> Expr Int16 -> ArduinoPrimitive (Expr Word8)
     ServoRead            :: Word8 -> ArduinoPrimitive Int16
     ServoReadE           :: Expr Word8 -> ArduinoPrimitive (Expr Int16)
     ServoReadMicros      :: Word8 -> ArduinoPrimitive Int16
     ServoReadMicrosE     :: Expr Word8 -> ArduinoPrimitive (Expr Int16)
     QueryAllTasks        :: ArduinoPrimitive [TaskID]
     QueryAllTasksE       :: ArduinoPrimitive (Expr [TaskID])
     QueryTask            :: TaskID -> ArduinoPrimitive (Maybe (TaskLength, TaskLength, TaskPos, TimeMillis))
     QueryTaskE           :: TaskIDE -> ArduinoPrimitive (Maybe (TaskLength, TaskLength, TaskPos, TimeMillis))
     BootTaskE            :: Expr [Word8] -> ArduinoPrimitive (Expr Bool)
     ReadRemoteRefB       :: RemoteRef Bool   -> ArduinoPrimitive (Expr Bool)
     ReadRemoteRefW8      :: RemoteRef Word8  -> ArduinoPrimitive (Expr Word8)
     ReadRemoteRefW16     :: RemoteRef Word16 -> ArduinoPrimitive (Expr Word16)
     ReadRemoteRefW32     :: RemoteRef Word32 -> ArduinoPrimitive (Expr Word32)
     ReadRemoteRefI8      :: RemoteRef Int8  -> ArduinoPrimitive (Expr Int8)
     ReadRemoteRefI16     :: RemoteRef Int16 -> ArduinoPrimitive (Expr Int16)
     ReadRemoteRefI32     :: RemoteRef Int32 -> ArduinoPrimitive (Expr Int32)
     ReadRemoteRefL8      :: RemoteRef [Word8] -> ArduinoPrimitive (Expr [Word8])
     ReadRemoteRefFloat   :: RemoteRef Float -> ArduinoPrimitive (Expr Float)
     NewRemoteRefB        :: Expr Bool   -> ArduinoPrimitive (RemoteRef Bool)
     NewRemoteRefW8       :: Expr Word8  -> ArduinoPrimitive (RemoteRef Word8)
     NewRemoteRefW16      :: Expr Word16 -> ArduinoPrimitive (RemoteRef Word16)
     NewRemoteRefW32      :: Expr Word32 -> ArduinoPrimitive (RemoteRef Word32)
     NewRemoteRefI8       :: Expr Int8  -> ArduinoPrimitive (RemoteRef Int8)
     NewRemoteRefI16      :: Expr Int16 -> ArduinoPrimitive (RemoteRef Int16)
     NewRemoteRefI32      :: Expr Int32 -> ArduinoPrimitive (RemoteRef Int32)
     NewRemoteRefL8       :: Expr [Word8] -> ArduinoPrimitive (RemoteRef [Word8])
     NewRemoteRefFloat    :: Expr Float -> ArduinoPrimitive (RemoteRef Float)
     IfThenElseBool       :: Bool -> Arduino Bool -> Arduino Bool -> ArduinoPrimitive Bool
     IfThenElseBoolE      :: Expr Bool -> Arduino (Expr Bool) -> Arduino (Expr Bool) -> ArduinoPrimitive (Expr Bool)
     IfThenElseWord8      :: Bool -> Arduino Word8 -> Arduino Word8 -> ArduinoPrimitive Word8
     IfThenElseWord8E     :: Expr Bool -> Arduino (Expr Word8) -> Arduino (Expr Word8) -> ArduinoPrimitive (Expr Word8)
     IfThenElseWord16     :: Bool -> Arduino Word16 -> Arduino Word16 -> ArduinoPrimitive Word16
     IfThenElseWord16E    :: Expr Bool -> Arduino (Expr Word16) -> Arduino (Expr Word16) -> ArduinoPrimitive (Expr Word16)
     IfThenElseWord32     :: Bool -> Arduino Word32 -> Arduino Word32 -> ArduinoPrimitive Word32
     IfThenElseWord32E    :: Expr Bool -> Arduino (Expr Word32) -> Arduino (Expr Word32) -> ArduinoPrimitive (Expr Word32)
     IfThenElseInt8       :: Bool -> Arduino Int8 -> Arduino Int8 -> ArduinoPrimitive Int8
     IfThenElseInt8E      :: Expr Bool -> Arduino (Expr Int8) -> Arduino (Expr Int8) -> ArduinoPrimitive (Expr Int8)
     IfThenElseInt16      :: Bool -> Arduino Int16 -> Arduino Int16 -> ArduinoPrimitive Int16
     IfThenElseInt16E     :: Expr Bool -> Arduino (Expr Int16) -> Arduino (Expr Int16) -> ArduinoPrimitive (Expr Int16)
     IfThenElseInt32      :: Bool -> Arduino Int32 -> Arduino Int32 -> ArduinoPrimitive Int32
     IfThenElseInt32E     :: Expr Bool -> Arduino (Expr Int32) -> Arduino (Expr Int32) -> ArduinoPrimitive (Expr Int32)
     IfThenElseL8         :: Bool -> Arduino [Word8] -> Arduino [Word8] -> ArduinoPrimitive [Word8]
     IfThenElseL8E        :: Expr Bool -> Arduino (Expr [Word8]) -> Arduino (Expr [Word8]) -> ArduinoPrimitive (Expr [Word8])
     IfThenElseFloat      :: Bool -> Arduino Float -> Arduino Float -> ArduinoPrimitive Float
     IfThenElseFloatE     :: Expr Bool -> Arduino (Expr Float) -> Arduino (Expr Float) -> ArduinoPrimitive (Expr Float)
     IfThenElseW8Unit     :: Expr Bool -> Arduino(ExprEither Word8 ()) -> Arduino(ExprEither Word8 ()) -> ArduinoPrimitive (ExprEither Word8 ())
     IfThenElseW8Bool     :: Expr Bool -> Arduino(ExprEither Word8 Bool) -> Arduino(ExprEither Word8 Bool) -> ArduinoPrimitive (ExprEither Word8 Bool)
     IfThenElseW8W8       :: Expr Bool -> Arduino(ExprEither Word8 Word8) -> Arduino(ExprEither Word8 Word8) -> ArduinoPrimitive (ExprEither Word8 Word8)
     IfThenElseW8W16      :: Expr Bool -> Arduino(ExprEither Word8 Word16) -> Arduino(ExprEither Word8 Word16) -> ArduinoPrimitive (ExprEither Word8 Word16)
     IfThenElseW8W32      :: Expr Bool -> Arduino(ExprEither Word8 Word32) -> Arduino(ExprEither Word8 Word32) -> ArduinoPrimitive (ExprEither Word8 Word32)
     IfThenElseW8I8       :: Expr Bool -> Arduino(ExprEither Word8 Int8) -> Arduino(ExprEither Word8 Int8) -> ArduinoPrimitive (ExprEither Word8 Int8)
     IfThenElseW8I16      :: Expr Bool -> Arduino(ExprEither Word8 Int16) -> Arduino(ExprEither Word8 Int16) -> ArduinoPrimitive (ExprEither Word8 Int16)
     IfThenElseW8I32      :: Expr Bool -> Arduino(ExprEither Word8 Int32) -> Arduino(ExprEither Word8 Int32) -> ArduinoPrimitive (ExprEither Word8 Int32)
     IfThenElseW8L8       :: Expr Bool -> Arduino(ExprEither Word8 [Word8]) -> Arduino(ExprEither Word8 [Word8]) -> ArduinoPrimitive (ExprEither Word8 [Word8])
     IfThenElseW8Float    :: Expr Bool -> Arduino(ExprEither Word8 Float) -> Arduino(ExprEither Word8 Float) -> ArduinoPrimitive (ExprEither Word8 Float)
     IfThenElseUnitUnit   :: Expr Bool -> Arduino(ExprEither () ()) -> Arduino(ExprEither () ()) -> ArduinoPrimitive (ExprEither () ())
     IfThenElseUnitW8     :: Expr Bool -> Arduino(ExprEither () Word8) -> Arduino(ExprEither () Word8) -> ArduinoPrimitive (ExprEither () Word8)
     WhileBool            :: Bool -> (Bool -> Bool) -> (Bool -> Arduino Bool) -> ArduinoPrimitive Bool
     WhileBoolE           :: (Expr Bool) -> (Expr Bool -> Expr Bool) -> (Expr Bool -> Arduino (Expr Bool)) -> ArduinoPrimitive (Expr Bool)
     WhileWord8           :: Word8 -> (Word8 -> Bool) -> (Word8 -> Arduino Word8) -> ArduinoPrimitive Word8
     WhileWord8E          :: (Expr Word8) -> (Expr Word8 -> Expr Bool) -> (Expr Word8 -> Arduino (Expr Word8)) -> ArduinoPrimitive (Expr Word8)
     WhileWord16          :: Word16 -> (Word16 -> Bool) -> (Word16 -> Arduino Word16) -> ArduinoPrimitive Word16
     WhileWord16E         :: (Expr Word16) -> (Expr Word16 -> Expr Bool) -> (Expr Word16 -> Arduino (Expr Word16)) -> ArduinoPrimitive (Expr Word16)
     WhileWord32          :: Word32 -> (Word32 -> Bool) -> (Word32 -> Arduino Word32) -> ArduinoPrimitive Word32
     WhileWord32E         :: (Expr Word32) -> (Expr Word32 -> Expr Bool) -> (Expr Word32 -> Arduino (Expr Word32)) -> ArduinoPrimitive (Expr Word32)
     WhileInt8            :: Int8 -> (Int8 -> Bool) -> (Int8 -> Arduino Int8) -> ArduinoPrimitive Int8
     WhileInt8E           :: (Expr Int8) -> (Expr Int8 -> Expr Bool) -> (Expr Int8 -> Arduino (Expr Int8)) -> ArduinoPrimitive (Expr Int8)
     WhileInt16           :: Int16 -> (Int16 -> Bool) -> (Int16 -> Arduino Int16) -> ArduinoPrimitive Int16
     WhileInt16E          :: (Expr Int16) -> (Expr Int16 -> Expr Bool) -> (Expr Int16 -> Arduino (Expr Int16)) -> ArduinoPrimitive (Expr Int16)
     WhileInt32           :: Int32 -> (Int32 -> Bool) -> (Int32 -> Arduino Int32) -> ArduinoPrimitive Int32
     WhileInt32E          :: (Expr Int32) -> (Expr Int32 -> Expr Bool) -> (Expr Int32 -> Arduino (Expr Int32)) -> ArduinoPrimitive (Expr Int32)
     WhileFloat           :: Float -> (Float -> Bool) -> (Float -> Arduino Float) -> ArduinoPrimitive Float
     WhileFloatE          :: (Expr Float) -> (Expr Float -> Expr Bool) -> (Expr Float -> Arduino (Expr Float)) -> ArduinoPrimitive (Expr Float)
     WhileL8              :: [Word8] -> ([Word8] -> Bool) -> ([Word8] -> Arduino [Word8]) -> ArduinoPrimitive [Word8]
     WhileL8E             :: (Expr [Word8]) -> (Expr [Word8] -> Expr Bool) -> (Expr [Word8] -> Arduino (Expr [Word8])) -> ArduinoPrimitive (Expr [Word8])
     IterateW8UnitE       :: Expr Word8 -> (Expr Word8 -> Arduino (ExprEither Word8 () )) -> ArduinoPrimitive (Expr () )
     IterateW8BoolE       :: Expr Word8 -> (Expr Word8 -> Arduino (ExprEither Word8 Bool )) -> ArduinoPrimitive (Expr Bool )
     IterateW8W8E         :: Expr Word8 -> (Expr Word8 -> Arduino (ExprEither Word8 Word8)) -> ArduinoPrimitive (Expr Word8)
     IterateW8W16E        :: Expr Word8 -> (Expr Word8 -> Arduino (ExprEither Word8 Word16)) -> ArduinoPrimitive (Expr Word16)
     IterateW8W32E        :: Expr Word8 -> (Expr Word8 -> Arduino (ExprEither Word8 Word32)) -> ArduinoPrimitive (Expr Word32)
     IterateW8I8E         :: Expr Word8 -> (Expr Word8 -> Arduino (ExprEither Word8 Int8)) -> ArduinoPrimitive (Expr Int8)
     IterateW8I16E        :: Expr Word8 -> (Expr Word8 -> Arduino (ExprEither Word8 Int16)) -> ArduinoPrimitive (Expr Int16)
     IterateW8I32E        :: Expr Word8 -> (Expr Word8 -> Arduino (ExprEither Word8 Int32)) -> ArduinoPrimitive (Expr Int32)
     IterateW8L8E         :: Expr Word8 -> (Expr Word8 -> Arduino (ExprEither Word8 [Word8])) -> ArduinoPrimitive (Expr [Word8])
     IterateW8FloatE      :: Expr Word8 -> (Expr Word8 -> Arduino (ExprEither Word8 Float)) -> ArduinoPrimitive (Expr Float)
     IterateUnitW8E       :: Expr () -> (Expr () -> Arduino (ExprEither () Word8)) -> ArduinoPrimitive (Expr Word8)
     IterateUnitUnitE     :: Expr () -> (Expr () -> Arduino (ExprEither () () )) -> ArduinoPrimitive (Expr () )
     LiftIO               :: IO a -> ArduinoPrimitive a
     Debug                :: String -> ArduinoPrimitive ()
     DebugE               :: Expr [Word8] -> ArduinoPrimitive ()
     DebugListen          :: ArduinoPrimitive ()
     Die                  :: String -> [String] -> ArduinoPrimitive ()
     -- ToDo: add SPI procedures

instance KnownResult ArduinoPrimitive where
  knownResult (SystemReset {}          ) = Just ()
  knownResult (SetPinModeE {}          ) = Just ()
  knownResult (DigitalPortWriteE {}    ) = Just ()
  knownResult (DigitalWriteE {}        ) = Just ()
  knownResult (AnalogWriteE {}         ) = Just ()
  knownResult (ToneE {}                ) = Just ()
  knownResult (NoToneE {}              ) = Just ()
  knownResult (I2CWrite {}             ) = Just ()
  knownResult (I2CConfig {}            ) = Just ()
  knownResult (StepperSetSpeedE {}     ) = Just ()
  knownResult (ServoDetachE {}         ) = Just ()
  knownResult (ServoWriteE {}          ) = Just ()
  knownResult (ServoWriteMicrosE {}    ) = Just ()
  knownResult (CreateTaskE {}          ) = Just ()
  knownResult (DeleteTaskE {}          ) = Just ()
  knownResult (ScheduleTaskE {}        ) = Just ()
  knownResult (ScheduleReset {}        ) = Just ()
  knownResult (AttachIntE {}           ) = Just ()
  knownResult (DetachIntE {}           ) = Just ()
  knownResult (Interrupts {}           ) = Just ()
  knownResult (NoInterrupts {}         ) = Just ()
  knownResult (GiveSemE {}             ) = Just ()
  knownResult (TakeSemE {}             ) = Just ()
  knownResult (WriteRemoteRefB {}      ) = Just ()
  knownResult (WriteRemoteRefW8 {}     ) = Just ()
  knownResult (WriteRemoteRefW16 {}    ) = Just ()
  knownResult (WriteRemoteRefW32  {}   ) = Just ()
  knownResult (WriteRemoteRefI8 {}     ) = Just ()
  knownResult (WriteRemoteRefI16 {}    ) = Just ()
  knownResult (WriteRemoteRefI32 {}    ) = Just ()
  knownResult (WriteRemoteRefL8 {}     ) = Just ()
  knownResult (WriteRemoteRefFloat {}  ) = Just ()
  knownResult (ModifyRemoteRefB {}     ) = Just ()
  knownResult (ModifyRemoteRefW8 {}    ) = Just ()
  knownResult (ModifyRemoteRefW16 {}   ) = Just ()
  knownResult (ModifyRemoteRefW32 {}   ) = Just ()
  knownResult (ModifyRemoteRefI8 {}    ) = Just ()
  knownResult (ModifyRemoteRefI16 {}   ) = Just ()
  knownResult (ModifyRemoteRefI32 {}   ) = Just ()
  knownResult (ModifyRemoteRefL8 {}    ) = Just ()
  knownResult (ModifyRemoteRefFloat {} ) = Just ()
  knownResult (Loop {}                 ) = Just ()
  knownResult (LoopE {}                ) = Just ()
  knownResult (ForInE {}               ) = Just ()
  knownResult (IfThenElseUnit {}       ) = Just ()
  knownResult (IfThenElseUnitE {}      ) = Just ()
  knownResult _                          = Nothing

systemReset :: Arduino ()
systemReset =  Arduino $ primitive SystemReset

setPinMode :: Pin -> PinMode -> Arduino ()
setPinMode p pm =  Arduino $ primitive $ SetPinModeE (lit p) (lit $ fromIntegral $ fromEnum pm)

setPinModeE :: PinE -> PinMode -> Arduino ()
setPinModeE p pm =  Arduino $ primitive $ SetPinModeE p (lit $ fromIntegral $ fromEnum pm)

digitalWrite :: Pin -> Bool -> Arduino ()
digitalWrite p b = Arduino $ primitive $ DigitalWriteE (lit p) (lit b)

digitalWriteE :: PinE -> Expr Bool -> Arduino ()
digitalWriteE p b = Arduino $ primitive $ DigitalWriteE p b

digitalPortWrite :: Pin -> Word8 -> Word8 -> Arduino ()
digitalPortWrite p b m = Arduino $ primitive $ DigitalPortWriteE (lit p) (lit b) (lit m)

digitalPortWriteE :: PinE -> Expr Word8 -> Expr Word8 -> Arduino ()
digitalPortWriteE p b m = Arduino $ primitive $ DigitalPortWriteE p b m

analogWrite :: Pin -> Word16 -> Arduino ()
analogWrite p w = Arduino $ primitive $ AnalogWriteE (lit p) (lit w)

analogWriteE :: PinE -> Expr Word16 -> Arduino ()
analogWriteE p w = Arduino $ primitive $ AnalogWriteE p w

tone :: Pin -> Word16 -> Maybe Word32 -> Arduino ()
tone p f Nothing = Arduino $ primitive $ ToneE (lit p) (lit f) Nothing
tone p f (Just d) = Arduino $ primitive $ ToneE (lit p) (lit f) (Just $ lit d)

toneE :: PinE -> Expr Word16 -> Maybe (Expr Word32) -> Arduino ()
toneE p f d = Arduino $ primitive $ ToneE p f d

noTone :: Pin -> Arduino ()
noTone p = Arduino $ primitive $ NoToneE (lit p)

noToneE :: PinE -> Arduino ()
noToneE p = Arduino $ primitive $ NoToneE p

i2cWrite :: SlaveAddress -> [Word8] -> Arduino ()
i2cWrite sa ws = Arduino $ primitive $ I2CWrite (lit sa) (lit ws)

i2cWriteE :: SlaveAddressE -> Expr [Word8] -> Arduino ()
i2cWriteE sa ws = Arduino $ primitive $ I2CWrite sa ws

i2cConfig :: Arduino ()
i2cConfig = Arduino $ primitive $ I2CConfig

stepperSetSpeed :: Word8 -> Int32 -> Arduino ()
stepperSetSpeed st sp = Arduino $ primitive $ StepperSetSpeedE (lit st) (lit sp)

stepperSetSpeedE :: Expr Word8 -> Expr Int32 -> Arduino ()
stepperSetSpeedE st sp = Arduino $ primitive $ StepperSetSpeedE st sp

servoDetach :: Word8 -> Arduino ()
servoDetach s = Arduino $ primitive $ ServoDetachE (lit s)

servoDetachE :: Expr Word8 -> Arduino ()
servoDetachE s = Arduino $ primitive $ ServoDetachE s

servoWrite :: Word8 -> Int16 -> Arduino ()
servoWrite s w = Arduino $ primitive $ ServoWriteE (lit s) (lit w)

servoWriteE :: Expr Word8 -> Expr Int16 -> Arduino ()
servoWriteE s w = Arduino $ primitive $ ServoWriteE s w

servoWriteMicros :: Word8 -> Int16 -> Arduino ()
servoWriteMicros s w = Arduino $ primitive $ ServoWriteMicrosE (lit s) (lit w)

servoWriteMicrosE :: Expr Word8 -> Expr Int16 -> Arduino ()
servoWriteMicrosE s w = Arduino $ primitive $ ServoWriteMicrosE s w

createTask :: TaskID -> Arduino () -> Arduino ()
createTask tid ps = Arduino $ primitive $ CreateTaskE (lit tid) ps

createTaskE :: TaskIDE -> Arduino () -> Arduino ()
createTaskE tid ps = Arduino $ primitive  $ CreateTaskE tid ps

deleteTask :: TaskID -> Arduino ()
deleteTask tid = Arduino $ primitive $ DeleteTaskE (lit tid)

deleteTaskE :: TaskIDE -> Arduino ()
deleteTaskE tid = Arduino $ primitive $ DeleteTaskE tid

scheduleTask :: TaskID -> TimeMillis -> Arduino ()
scheduleTask tid tt = Arduino $ primitive $ ScheduleTaskE (lit tid) (lit tt)

scheduleTaskE :: TaskIDE -> TimeMillisE -> Arduino ()
scheduleTaskE tid tt = Arduino $ primitive $ ScheduleTaskE tid tt

attachInt :: Pin -> TaskID -> IntMode -> Arduino ()
attachInt p tid m = Arduino $ primitive $ AttachIntE (lit p) (lit tid) (lit $ fromIntegral $ fromEnum m)

attachIntE :: PinE -> TaskIDE -> IntMode -> Arduino ()
attachIntE p tid m = Arduino $ primitive $ AttachIntE p tid (lit $ fromIntegral $ fromEnum m)

detachInt :: Pin -> Arduino ()
detachInt p = Arduino $ primitive $ DetachIntE (lit p)

detachIntE :: PinE -> Arduino ()
detachIntE p = Arduino $ primitive $ DetachIntE p

interrupts :: Arduino ()
interrupts = Arduino $ primitive $ Interrupts

noInterrupts :: Arduino ()
noInterrupts = Arduino $ primitive $ NoInterrupts

scheduleReset :: Arduino ()
scheduleReset = Arduino $ primitive ScheduleReset

giveSem :: Word8 -> Arduino ()
giveSem id = Arduino $ primitive $ GiveSemE (lit id)

giveSemE :: Expr Word8 -> Arduino ()
giveSemE id = Arduino $ primitive $ GiveSemE id

takeSem :: Word8 -> Arduino ()
takeSem id = Arduino $ primitive $ TakeSemE (lit id)

takeSemE :: Expr Word8 -> Arduino ()
takeSemE id = Arduino $ primitive $ TakeSemE id

loopE :: Arduino () -> Arduino()
loopE ps = Arduino $ primitive $ LoopE ps

forInE :: Expr [Word8] -> (Expr Word8 -> Arduino ()) -> Arduino ()
forInE ws f = Arduino $ primitive $ ForInE ws f

ifThenElseUnit :: Bool -> Arduino () -> Arduino () -> Arduino ()
ifThenElseUnit b tps eps = Arduino $ primitive $ IfThenElseUnit b tps eps

ifThenElseUnitE :: Expr Bool -> Arduino () -> Arduino () -> Arduino ()
ifThenElseUnitE be tps eps = Arduino $ primitive $ IfThenElseUnitE be tps eps

class ExprB a => RemoteReference a where
    newRemoteRef    :: Expr a -> Arduino (RemoteRef a)
    readRemoteRef   :: RemoteRef a -> Arduino (Expr a)
    writeRemoteRef  :: RemoteRef a -> Expr a -> Arduino ()
    modifyRemoteRef :: RemoteRef a -> (Expr a -> Expr a) ->
                             Arduino ()

instance RemoteReference Bool where
    newRemoteRef n      = Arduino $ primitive $ NewRemoteRefB n
    readRemoteRef n     = Arduino $ primitive $ ReadRemoteRefB n
    writeRemoteRef r e  = Arduino $ primitive $ WriteRemoteRefB r e
    modifyRemoteRef (RemoteRefB i) f = 
        Arduino $ primitive $ ModifyRemoteRefB (RemoteRefB i) (f $ RefB i)

instance RemoteReference Word8 where
    newRemoteRef n      = Arduino $ primitive $ NewRemoteRefW8 n
    readRemoteRef n     = Arduino $ primitive $ ReadRemoteRefW8 n
    writeRemoteRef r e  = Arduino $ primitive $ WriteRemoteRefW8 r e
    modifyRemoteRef (RemoteRefW8 i) f = 
        Arduino $ primitive $ ModifyRemoteRefW8 (RemoteRefW8 i) (f $ RefW8 i)

instance RemoteReference Word16 where
    newRemoteRef n      = Arduino $ primitive $ NewRemoteRefW16 n
    readRemoteRef n     = Arduino $ primitive $ ReadRemoteRefW16 n
    writeRemoteRef r e  = Arduino $ primitive $ WriteRemoteRefW16 r e
    modifyRemoteRef (RemoteRefW16 i) f = 
        Arduino $ primitive $ ModifyRemoteRefW16 (RemoteRefW16 i) (f $ RefW16 i)

instance RemoteReference Word32 where
    newRemoteRef n      = Arduino $ primitive $ NewRemoteRefW32 n
    readRemoteRef n     = Arduino $ primitive $ ReadRemoteRefW32 n
    writeRemoteRef r e  = Arduino $ primitive $ WriteRemoteRefW32 r e
    modifyRemoteRef (RemoteRefW32 i) f = 
        Arduino $ primitive $ ModifyRemoteRefW32 (RemoteRefW32 i) (f $ RefW32 i)

instance RemoteReference Int8 where
    newRemoteRef n      = Arduino $ primitive $ NewRemoteRefI8 n
    readRemoteRef n     = Arduino $ primitive $ ReadRemoteRefI8 n
    writeRemoteRef r e  = Arduino $ primitive $ WriteRemoteRefI8 r e
    modifyRemoteRef (RemoteRefI8 i) f = 
        Arduino $ primitive $ ModifyRemoteRefI8 (RemoteRefI8 i) (f $ RefI8 i)

instance RemoteReference Int16 where
    newRemoteRef n      = Arduino $ primitive $ NewRemoteRefI16 n
    readRemoteRef n     = Arduino $ primitive $ ReadRemoteRefI16 n
    writeRemoteRef r e  = Arduino $ primitive $ WriteRemoteRefI16 r e
    modifyRemoteRef (RemoteRefI16 i) f = 
        Arduino $ primitive $ ModifyRemoteRefI16 (RemoteRefI16 i) (f $ RefI16 i)

instance RemoteReference Int32 where
    newRemoteRef n      = Arduino $ primitive $ NewRemoteRefI32 n
    readRemoteRef n     = Arduino $ primitive $ ReadRemoteRefI32 n
    writeRemoteRef r e  = Arduino $ primitive $ WriteRemoteRefI32 r e
    modifyRemoteRef (RemoteRefI32 i) f = 
        Arduino $ primitive $ ModifyRemoteRefI32 (RemoteRefI32 i) (f $ RefI32 i)

instance RemoteReference [Word8] where
    newRemoteRef n      = Arduino $ primitive $ NewRemoteRefL8 n
    readRemoteRef n     = Arduino $ primitive $ ReadRemoteRefL8 n
    writeRemoteRef r e  = Arduino $ primitive $ WriteRemoteRefL8 r e
    modifyRemoteRef (RemoteRefL8 i) f = 
        Arduino $ primitive $ ModifyRemoteRefL8 (RemoteRefL8 i) (f $ RefList8 i)

instance RemoteReference Float where
    newRemoteRef n      = Arduino $ primitive $ NewRemoteRefFloat n
    readRemoteRef n     = Arduino $ primitive $ ReadRemoteRefFloat n
    writeRemoteRef r e  = Arduino $ primitive $ WriteRemoteRefFloat r e
    modifyRemoteRef (RemoteRefFloat i) f = 
        Arduino $ primitive $ ModifyRemoteRefFloat (RemoteRefFloat i) (f $ RefFloat i)

loop :: Arduino () -> Arduino ()
loop m = Arduino $ primitive $ Loop m

queryFirmware :: Arduino Word16
queryFirmware = Arduino $ primitive QueryFirmware

queryFirmwareE :: Arduino (Expr Word16)
queryFirmwareE = Arduino $ primitive QueryFirmwareE

queryProcessor :: Arduino Processor
queryProcessor = Arduino $ primitive QueryProcessor

queryProcessorE :: Arduino (Expr Word8)
queryProcessorE = Arduino $ primitive QueryProcessorE

micros :: Arduino Word32
micros = Arduino $ primitive Micros

microsE :: Arduino (Expr Word32)
microsE = Arduino $ primitive MicrosE

millis :: Arduino Word32
millis = Arduino $ primitive Millis

millisE :: Arduino (Expr Word32)
millisE = Arduino $ primitive MillisE

delayMillis :: TimeMillis -> Arduino ()
delayMillis t = Arduino $ primitive $ DelayMillis t

delayMillisE :: TimeMillisE -> Arduino ()
delayMillisE t = Arduino $ primitive $ DelayMillisE t

delayMicros :: TimeMicros -> Arduino ()
delayMicros t = Arduino $ primitive $ DelayMicros t

delayMicrosE :: TimeMicrosE -> Arduino ()
delayMicrosE t = Arduino $ primitive $ DelayMicrosE t

digitalRead :: Pin -> Arduino Bool
digitalRead p = Arduino $ primitive $ DigitalRead p

digitalReadE :: PinE -> Arduino (Expr Bool)
digitalReadE p = Arduino $ primitive $ DigitalReadE p

digitalPortRead :: Pin -> Word8 -> Arduino Word8
digitalPortRead p m = Arduino $ primitive $ DigitalPortRead p m

digitalPortReadE :: PinE -> Expr Word8 -> Arduino (Expr Word8)
digitalPortReadE p m = Arduino $ primitive $ DigitalPortReadE p m

analogRead :: Pin -> Arduino Word16
analogRead p = Arduino $ primitive $ AnalogRead p

analogReadE :: PinE -> Arduino (Expr Word16)
analogReadE p = Arduino $ primitive $ AnalogReadE p

i2cRead :: SlaveAddress -> Word8 -> Arduino [Word8]
i2cRead sa cnt = Arduino $ primitive $ I2CRead sa cnt

i2cReadE :: SlaveAddressE -> Expr Word8 -> Arduino (Expr [Word8])
i2cReadE sa cnt = Arduino $ primitive $ I2CReadE sa cnt

stepper2Pin :: Word16 -> Pin -> Pin -> Arduino Word8
stepper2Pin s p1 p2 = Arduino $ primitive $ Stepper2Pin s p1 p2

stepper2PinE :: Expr Word16 -> PinE -> PinE -> Arduino (Expr Word8)
stepper2PinE s p1 p2 = Arduino $ primitive $ Stepper2PinE s p1 p2

stepper4Pin :: Word16 -> Pin -> Pin -> Pin -> Pin -> Arduino Word8
stepper4Pin s p1 p2 p3 p4 = Arduino $ primitive $ Stepper4Pin s p1 p2 p3 p4

stepper4PinE :: Expr Word16 -> PinE -> PinE -> PinE -> PinE -> Arduino (Expr Word8)
stepper4PinE s p1 p2 p3 p4 = Arduino $ primitive $ Stepper4PinE s p1 p2 p3 p4

stepperStep :: Word8 -> Int16 -> Arduino ()
stepperStep st s = Arduino $ primitive $ StepperStepE (lit st) (lit s)

stepperStepE :: Expr Word8 -> Expr Int16 -> Arduino ()
stepperStepE st s = Arduino $ primitive $ StepperStepE st s

servoAttach :: Pin -> Arduino Word8
servoAttach p = Arduino $ primitive $ ServoAttach p

servoAttachE :: PinE -> Arduino (Expr Word8)
servoAttachE p = Arduino $ primitive $ ServoAttachE p

servoAttachMinMax :: Pin -> Int16 -> Int16 -> Arduino Word8
servoAttachMinMax p min max = Arduino $ primitive $ ServoAttachMinMax p min max

servoAttachMinMaxE :: PinE -> Expr Int16 -> Expr Int16 -> Arduino (Expr Word8)
servoAttachMinMaxE p min max = Arduino $ primitive $ ServoAttachMinMaxE p min max

servoRead :: Word8 -> Arduino Int16
servoRead s = Arduino $ primitive $ ServoRead s

servoReadE :: Expr Word8 -> Arduino (Expr Int16)
servoReadE s = Arduino $ primitive $ ServoReadE s

servoReadMicros :: Word8 -> Arduino Int16
servoReadMicros s = Arduino $ primitive $ ServoReadMicros s

servoReadMicrosE :: Expr Word8 -> Arduino (Expr Int16)
servoReadMicrosE s = Arduino $ primitive $ ServoReadMicrosE s

queryAllTasks :: Arduino [TaskID]
queryAllTasks = Arduino $ primitive QueryAllTasks

queryAllTasksE :: Arduino (Expr [TaskID])
queryAllTasksE = Arduino $ primitive QueryAllTasksE

queryTask :: TaskID -> Arduino (Maybe (TaskLength, TaskLength, TaskPos, TimeMillis))
queryTask tid = Arduino $ primitive $ QueryTask tid

queryTaskE :: TaskIDE -> Arduino (Maybe (TaskLength, TaskLength, TaskPos, TimeMillis))
queryTaskE tid = Arduino $ primitive $ QueryTaskE tid

bootTaskE :: Expr [Word8] -> Arduino (Expr Bool)
bootTaskE tids = Arduino $ primitive $ BootTaskE tids

debug :: String -> Arduino ()
debug msg = Arduino $ primitive $ Debug msg

debugE :: Expr [Word8] -> Arduino ()
debugE msg = Arduino $ primitive $ DebugE msg

debugListen :: Arduino ()
debugListen = Arduino $ primitive $ DebugListen

die :: String -> [String] -> Arduino ()
die msg msgs = Arduino $ primitive $ Die msg msgs

class ExprB a => ArduinoConditional a where
    ifThenElse   :: Bool -> Arduino a -> Arduino a -> Arduino a
    ifThenElseE  :: Expr Bool -> Arduino (Expr a) -> 
                        Arduino (Expr a) -> Arduino (Expr a)
    while        :: a -> (a -> Bool) -> (a -> Arduino a) -> Arduino a
    whileE       :: Expr a -> (Expr a -> Expr Bool) ->
                        (Expr a -> Arduino (Expr a)) -> Arduino (Expr a)

instance ArduinoConditional Bool where
    ifThenElse b tps eps   = Arduino $ primitive $ IfThenElseBool b tps eps
    ifThenElseE be tps eps = Arduino $ primitive $ IfThenElseBoolE be tps eps
    while iv bf bdf        = Arduino $ primitive $ WhileBool iv bf bdf
    whileE iv bf bdf       = Arduino $ primitive $ WhileBoolE iv bf bdf

instance ArduinoConditional Word8 where
    ifThenElse b tps eps   = Arduino $ primitive $ IfThenElseWord8 b tps eps
    ifThenElseE be tps eps = Arduino $ primitive $ IfThenElseWord8E be tps eps
    while iv bf bdf        = Arduino $ primitive $ WhileWord8 iv bf bdf
    whileE iv bf bdf       = Arduino $ primitive $ WhileWord8E iv bf bdf

instance ArduinoConditional Word16 where
    ifThenElse b tps eps   = Arduino $ primitive $ IfThenElseWord16 b tps eps
    ifThenElseE be tps eps = Arduino $ primitive $ IfThenElseWord16E be tps eps
    while iv bf bdf        = Arduino $ primitive $ WhileWord16 iv bf bdf
    whileE iv bf bdf       = Arduino $ primitive $ WhileWord16E iv bf bdf

instance ArduinoConditional Word32 where
    ifThenElse b tps eps   = Arduino $ primitive $ IfThenElseWord32 b tps eps
    ifThenElseE be tps eps = Arduino $ primitive $ IfThenElseWord32E be tps eps
    while iv bf bdf        = Arduino $ primitive $ WhileWord32 iv bf bdf
    whileE iv bf bdf       = Arduino $ primitive $ WhileWord32E iv bf bdf

instance ArduinoConditional Int8 where
    ifThenElse b tps eps   = Arduino $ primitive $ IfThenElseInt8 b tps eps
    ifThenElseE be tps eps = Arduino $ primitive $ IfThenElseInt8E be tps eps
    while iv bf bdf        = Arduino $ primitive $ WhileInt8 iv bf bdf
    whileE iv bf bdf       = Arduino $ primitive $ WhileInt8E iv bf bdf

instance ArduinoConditional Int16 where
    ifThenElse b tps eps   = Arduino $ primitive $ IfThenElseInt16 b tps eps
    ifThenElseE be tps eps = Arduino $ primitive $ IfThenElseInt16E be tps eps
    while iv bf bdf        = Arduino $ primitive $ WhileInt16 iv bf bdf
    whileE iv bf bdf       = Arduino $ primitive $ WhileInt16E iv bf bdf

instance ArduinoConditional Int32 where
    ifThenElse b tps eps   = Arduino $ primitive $ IfThenElseInt32 b tps eps
    ifThenElseE be tps eps = Arduino $ primitive $ IfThenElseInt32E be tps eps
    while iv bf bdf        = Arduino $ primitive $ WhileInt32 iv bf bdf
    whileE iv bf bdf       = Arduino $ primitive $ WhileInt32E iv bf bdf

instance ArduinoConditional [Word8] where
    ifThenElse b tps eps   = Arduino $ primitive $ IfThenElseL8 b tps eps
    ifThenElseE be tps eps = Arduino $ primitive $ IfThenElseL8E be tps eps
    while iv bf bdf        = Arduino $ primitive $ WhileL8 iv bf bdf
    whileE iv bf bdf       = Arduino $ primitive $ WhileL8E iv bf bdf

instance ArduinoConditional Float where
    ifThenElse b tps eps   = Arduino $ primitive $ IfThenElseFloat b tps eps
    ifThenElseE be tps eps = Arduino $ primitive $ IfThenElseFloatE be tps eps
    while iv bf bdf        = Arduino $ primitive $ WhileFloat iv bf bdf
    whileE iv bf bdf       = Arduino $ primitive $ WhileFloatE iv bf bdf

class (ExprB a, ExprB b) => ArduinoIterate a b where
    iterateE  :: Expr a -> (Expr a -> Arduino (ExprEither a b)) -> Arduino (Expr b)
    ifThenElseEither   :: Expr Bool -> Arduino (ExprEither a b) -> Arduino (ExprEither a b) -> Arduino (ExprEither a b)

instance ArduinoIterate Word8 () where
    iterateE iv bf = Arduino $ primitive $ IterateW8UnitE iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseW8Unit be te ee

instance ArduinoIterate Word8 Bool where
    iterateE iv bf = Arduino $ primitive $ IterateW8BoolE iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseW8Bool be te ee

instance ArduinoIterate Word8 Word8 where
    iterateE iv bf = Arduino $ primitive $ IterateW8W8E iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseW8W8 be te ee

instance ArduinoIterate Word8 Word16 where
    iterateE iv bf = Arduino $ primitive $ IterateW8W16E iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseW8W16 be te ee

instance ArduinoIterate Word8 Word32 where
    iterateE iv bf = Arduino $ primitive $ IterateW8W32E iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseW8W32 be te ee

instance ArduinoIterate Word8 Int8 where
    iterateE iv bf = Arduino $ primitive $ IterateW8I8E iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseW8I8 be te ee

instance ArduinoIterate Word8 Int16 where
    iterateE iv bf = Arduino $ primitive $ IterateW8I16E iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseW8I16 be te ee

instance ArduinoIterate Word8 Int32 where
    iterateE iv bf = Arduino $ primitive $ IterateW8I32E iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseW8I32 be te ee

instance ArduinoIterate Word8 [Word8] where
    iterateE iv bf = Arduino $ primitive $ IterateW8L8E iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseW8L8 be te ee

instance ArduinoIterate Word8 Float where
    iterateE iv bf = Arduino $ primitive $ IterateW8FloatE iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseW8Float be te ee

instance ArduinoIterate () Word8 where
    iterateE iv bf = Arduino $ primitive $ IterateUnitW8E iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseUnitW8 be te ee

instance ArduinoIterate () () where
    iterateE iv bf  = Arduino $ primitive $ IterateUnitUnitE iv bf
    ifThenElseEither be te ee = Arduino $ primitive $ IfThenElseUnitUnit be te ee

{-
whileE' :: ArduinoIterate a a => Expr a -> (Expr a -> Expr Bool) ->
                     (Expr a -> Arduino (Expr a)) -> Arduino (Expr a)
whileE' i tf bf = iterateE i ibf
  where
    ibf i' = do
        res <- bf i'
        ifThenElseEither (tf res) (return $ ExprLeft res) (return $ ExprRight res)

loopE' :: Arduino a -> Arduino (Expr ())
loopE' bf = iterateE LitUnit ibf
  where
    ibf _ = do
        bf
        return $ ExprLeft LitUnit
-}

-- | A response, as returned from the Arduino
data Response = DelayResp
              | Firmware Word16                      -- ^ Firmware version (maj/min)
              | ProcessorType Word8                  -- ^ Processor report
              | MicrosReply Word32                   -- ^ Elapsed Microseconds
              | MillisReply Word32                   -- ^ Elapsed Milliseconds
              | DigitalReply Word8                   -- ^ Status of a pin
              | DigitalPortReply Word8               -- ^ Status of a port
              | AnalogReply Word16                   -- ^ Status of an analog pin
              | StringMessage  String                -- ^ String message from Firmware
              | I2CReply [Word8]                     -- ^ Response to a I2C Read
              | Stepper2PinReply Word8
              | Stepper4PinReply Word8
              | StepperStepReply
              | ServoAttachReply Word8
              | ServoReadReply Int16
              | ServoReadMicrosReply Int16
              | QueryAllTasksReply [Word8]           -- ^ Response to Query All Tasks
              | QueryTaskReply (Maybe (TaskLength, TaskLength, TaskPos, TimeMillis))
              | BootTaskResp Word8
              | NewReply Word8
              | ReadRefBReply Bool
              | ReadRefW8Reply Word8
              | ReadRefW16Reply Word16
              | ReadRefW32Reply Word32
              | ReadRefI8Reply Int8
              | ReadRefI16Reply Int16
              | ReadRefI32Reply Int32
              | ReadRefL8Reply [Word8]
              | ReadRefFloatReply Float
              | IfThenElseBReply Bool
              | IfThenElseW8Reply Word8
              | IfThenElseW16Reply Word16
              | IfThenElseW32Reply Word32
              | IfThenElseI8Reply Int8
              | IfThenElseI16Reply Int16
              | IfThenElseI32Reply Int32
              | IfThenElseL8Reply [Word8]
              | IfThenElseFloatReply Float
              | WhileBReply Bool
              | WhileW8Reply Word8
              | WhileW16Reply Word16
              | WhileW32Reply Word32
              | WhileI8Reply Int8
              | WhileI16Reply Int16
              | WhileI32Reply Int32
              | WhileL8Reply [Word8]
              | WhileFloatReply Float
              | DebugResp
              | FailedNewRef
              | Unimplemented (Maybe String) [Word8] -- ^ Represents messages currently unsupported
              | EmptyFrame
              | InvalidChecksumFrame [Word8]
    deriving Show

-- | Haskino Firmware commands, see:
-- | https://github.com/ku-fpg/haskino/wiki/Haskino-Firmware-Protocol-Definition
data FirmwareCmd = BC_CMD_SYSTEM_RESET
                 | BC_CMD_SET_PIN_MODE
                 | BC_CMD_DELAY_MILLIS
                 | BC_CMD_DELAY_MICROS
                 | BC_CMD_LOOP
                 | BC_CMD_WHILE
                 | BC_CMD_IF_THEN_ELSE
                 | BC_CMD_FORIN
                 | BS_CMD_REQUEST_VERSION
                 | BS_CMD_REQUEST_TYPE
                 | BS_CMD_REQUEST_MICROS
                 | BS_CMD_REQUEST_MILLIS
                 | BS_CMD_DEBUG
                 | DIG_CMD_READ_PIN
                 | DIG_CMD_WRITE_PIN
                 | DIG_CMD_READ_PORT
                 | DIG_CMD_WRITE_PORT
                 | ALG_CMD_READ_PIN
                 | ALG_CMD_WRITE_PIN
                 | ALG_CMD_TONE_PIN
                 | ALG_CMD_NOTONE_PIN
                 | I2C_CMD_CONFIG
                 | I2C_CMD_READ
                 | I2C_CMD_WRITE
                 | STEP_CMD_2PIN
                 | STEP_CMD_4PIN
                 | STEP_CMD_SET_SPEED
                 | STEP_CMD_STEP
                 | SRVO_CMD_ATTACH
                 | SRVO_CMD_DETACH
                 | SRVO_CMD_WRITE
                 | SRVO_CMD_WRITE_MICROS
                 | SRVO_CMD_READ
                 | SRVO_CMD_READ_MICROS
                 | SCHED_CMD_CREATE_TASK
                 | SCHED_CMD_DELETE_TASK
                 | SCHED_CMD_ADD_TO_TASK
                 | SCHED_CMD_SCHED_TASK
                 | SCHED_CMD_QUERY_ALL
                 | SCHED_CMD_QUERY
                 | SCHED_CMD_RESET
                 | SCHED_CMD_BOOT_TASK
                 | SCHED_CMD_GIVE_SEM
                 | SCHED_CMD_TAKE_SEM
                 | SCHED_CMD_ATTACH_INT
                 | SCHED_CMD_DETACH_INT
                 | SCHED_CMD_INTERRUPTS
                 | SCHED_CMD_NOINTERRUPTS
                 | REF_CMD_NEW
                 | REF_CMD_READ
                 | REF_CMD_WRITE
                 | EXPR_CMD_RET
                 | UNKNOWN_COMMAND
                deriving Show

-- | Compute the numeric value of a command
firmwareCmdVal :: FirmwareCmd -> Word8
firmwareCmdVal BC_CMD_SYSTEM_RESET      = 0x10
firmwareCmdVal BC_CMD_SET_PIN_MODE      = 0x11
firmwareCmdVal BC_CMD_DELAY_MILLIS      = 0x12
firmwareCmdVal BC_CMD_DELAY_MICROS      = 0x13
firmwareCmdVal BC_CMD_WHILE             = 0x14
firmwareCmdVal BC_CMD_IF_THEN_ELSE      = 0x15
firmwareCmdVal BC_CMD_LOOP              = 0x16
firmwareCmdVal BC_CMD_FORIN             = 0x17
firmwareCmdVal BS_CMD_REQUEST_VERSION   = 0x20
firmwareCmdVal BS_CMD_REQUEST_TYPE      = 0x21
firmwareCmdVal BS_CMD_REQUEST_MICROS    = 0x22
firmwareCmdVal BS_CMD_REQUEST_MILLIS    = 0x23
firmwareCmdVal BS_CMD_DEBUG             = 0x24
firmwareCmdVal DIG_CMD_READ_PIN         = 0x30
firmwareCmdVal DIG_CMD_WRITE_PIN        = 0x31
firmwareCmdVal DIG_CMD_READ_PORT        = 0x32
firmwareCmdVal DIG_CMD_WRITE_PORT       = 0x33
firmwareCmdVal ALG_CMD_READ_PIN         = 0x40
firmwareCmdVal ALG_CMD_WRITE_PIN        = 0x41
firmwareCmdVal ALG_CMD_TONE_PIN         = 0x42
firmwareCmdVal ALG_CMD_NOTONE_PIN       = 0x43
firmwareCmdVal I2C_CMD_CONFIG           = 0x50
firmwareCmdVal I2C_CMD_READ             = 0x51
firmwareCmdVal I2C_CMD_WRITE            = 0x52
firmwareCmdVal STEP_CMD_2PIN            = 0x60
firmwareCmdVal STEP_CMD_4PIN            = 0x61
firmwareCmdVal STEP_CMD_SET_SPEED       = 0x62
firmwareCmdVal STEP_CMD_STEP            = 0x63
firmwareCmdVal SRVO_CMD_ATTACH          = 0x80
firmwareCmdVal SRVO_CMD_DETACH          = 0x81
firmwareCmdVal SRVO_CMD_WRITE           = 0x82
firmwareCmdVal SRVO_CMD_WRITE_MICROS    = 0x83
firmwareCmdVal SRVO_CMD_READ            = 0x84
firmwareCmdVal SRVO_CMD_READ_MICROS     = 0x85
firmwareCmdVal SCHED_CMD_CREATE_TASK    = 0xA0
firmwareCmdVal SCHED_CMD_DELETE_TASK    = 0xA1
firmwareCmdVal SCHED_CMD_ADD_TO_TASK    = 0xA2
firmwareCmdVal SCHED_CMD_SCHED_TASK     = 0xA3
firmwareCmdVal SCHED_CMD_QUERY          = 0xA4
firmwareCmdVal SCHED_CMD_QUERY_ALL      = 0xA5
firmwareCmdVal SCHED_CMD_RESET          = 0xA6
firmwareCmdVal SCHED_CMD_BOOT_TASK      = 0xA7
firmwareCmdVal SCHED_CMD_TAKE_SEM       = 0xA8
firmwareCmdVal SCHED_CMD_GIVE_SEM       = 0xA9
firmwareCmdVal SCHED_CMD_ATTACH_INT     = 0xAA
firmwareCmdVal SCHED_CMD_DETACH_INT     = 0xAB
firmwareCmdVal SCHED_CMD_INTERRUPTS     = 0xAC
firmwareCmdVal SCHED_CMD_NOINTERRUPTS   = 0xAD
firmwareCmdVal REF_CMD_NEW              = 0xC0
firmwareCmdVal REF_CMD_READ             = 0xC1
firmwareCmdVal REF_CMD_WRITE            = 0xC2
firmwareCmdVal EXPR_CMD_RET             = 0xD0

-- | Compute the numeric value of a command
firmwareValCmd :: Word8 -> FirmwareCmd
firmwareValCmd 0x10 = BC_CMD_SYSTEM_RESET
firmwareValCmd 0x11 = BC_CMD_SET_PIN_MODE
firmwareValCmd 0x12 = BC_CMD_DELAY_MILLIS
firmwareValCmd 0x13 = BC_CMD_DELAY_MICROS
firmwareValCmd 0x14 = BC_CMD_WHILE
firmwareValCmd 0x15 = BC_CMD_IF_THEN_ELSE
firmwareValCmd 0x16 = BC_CMD_LOOP
firmwareValCmd 0x17 = BC_CMD_FORIN
firmwareValCmd 0x20 = BS_CMD_REQUEST_VERSION
firmwareValCmd 0x21 = BS_CMD_REQUEST_TYPE
firmwareValCmd 0x22 = BS_CMD_REQUEST_MICROS
firmwareValCmd 0x23 = BS_CMD_REQUEST_MILLIS
firmwareValCmd 0x24 = BS_CMD_DEBUG
firmwareValCmd 0x30 = DIG_CMD_READ_PIN
firmwareValCmd 0x31 = DIG_CMD_WRITE_PIN
firmwareValCmd 0x32 = DIG_CMD_READ_PORT
firmwareValCmd 0x33 = DIG_CMD_WRITE_PORT
firmwareValCmd 0x40 = ALG_CMD_READ_PIN
firmwareValCmd 0x41 = ALG_CMD_WRITE_PIN
firmwareValCmd 0x42 = ALG_CMD_TONE_PIN
firmwareValCmd 0x43 = ALG_CMD_NOTONE_PIN
firmwareValCmd 0x50 = I2C_CMD_CONFIG
firmwareValCmd 0x51 = I2C_CMD_READ
firmwareValCmd 0x52 = I2C_CMD_WRITE
firmwareValCmd 0x60 = STEP_CMD_2PIN
firmwareValCmd 0x61 = STEP_CMD_4PIN
firmwareValCmd 0x62 = STEP_CMD_SET_SPEED
firmwareValCmd 0x63 = STEP_CMD_STEP
firmwareValCmd 0x80 = SRVO_CMD_ATTACH
firmwareValCmd 0x81 = SRVO_CMD_DETACH
firmwareValCmd 0x82 = SRVO_CMD_WRITE
firmwareValCmd 0x83 = SRVO_CMD_WRITE_MICROS
firmwareValCmd 0x84 = SRVO_CMD_READ
firmwareValCmd 0x85 = SRVO_CMD_READ_MICROS
firmwareValCmd 0xA0 = SCHED_CMD_CREATE_TASK
firmwareValCmd 0xA1 = SCHED_CMD_DELETE_TASK
firmwareValCmd 0xA2 = SCHED_CMD_ADD_TO_TASK
firmwareValCmd 0xA3 = SCHED_CMD_SCHED_TASK
firmwareValCmd 0xA4 = SCHED_CMD_QUERY
firmwareValCmd 0xA5 = SCHED_CMD_QUERY_ALL
firmwareValCmd 0xA6 = SCHED_CMD_RESET
firmwareValCmd 0xA7 = SCHED_CMD_BOOT_TASK
firmwareValCmd 0xA8 = SCHED_CMD_TAKE_SEM
firmwareValCmd 0xA9 = SCHED_CMD_GIVE_SEM
firmwareValCmd 0xAA = SCHED_CMD_ATTACH_INT
firmwareValCmd 0xAB = SCHED_CMD_DETACH_INT
firmwareValCmd 0xAC = SCHED_CMD_INTERRUPTS
firmwareValCmd 0xAD = SCHED_CMD_NOINTERRUPTS
firmwareValCmd 0xC0 = REF_CMD_NEW
firmwareValCmd 0xC1 = REF_CMD_READ
firmwareValCmd 0xC2 = REF_CMD_WRITE
firmwareValCmd 0xD0 = EXPR_CMD_RET
firmwareValCmd _    = UNKNOWN_COMMAND

data RefType = REF_BOOL
             | REF_WORD8
             | REF_WORD16
             | REF_WORD32
             | REF_INT8
             | REF_INT16
             | REF_INT32
             | REF_LIST8
             | REF_FLOAT
             | REF_UNIT
            deriving (Show, Enum)

-- | Firmware replies, see:
-- | https://github.com/ku-fpg/haskino/wiki/Haskino-Firmware-Protocol-Definition
data FirmwareReply =  BC_RESP_DELAY
                   |  BC_RESP_IF_THEN_ELSE
                   |  BC_RESP_WHILE
                   |  BS_RESP_VERSION
                   |  BS_RESP_TYPE
                   |  BS_RESP_MICROS
                   |  BS_RESP_MILLIS
                   |  BS_RESP_STRING
                   |  BS_RESP_DEBUG
                   |  DIG_RESP_READ_PIN
                   |  DIG_RESP_READ_PORT
                   |  ALG_RESP_READ_PIN
                   |  I2C_RESP_READ
                   |  STEP_RESP_2PIN
                   |  STEP_RESP_4PIN
                   |  STEP_RESP_STEP
                   |  SRVO_RESP_ATTACH
                   |  SRVO_RESP_READ
                   |  SRVO_RESP_READ_MICROS
                   |  SCHED_RESP_QUERY
                   |  SCHED_RESP_QUERY_ALL
                   |  SCHED_RESP_BOOT
                   |  REF_RESP_NEW
                   |  REF_RESP_READ
                   |  EXPR_RESP_RET
                deriving Show

getFirmwareReply :: Word8 -> Either Word8 FirmwareReply
getFirmwareReply 0x18 = Right BC_RESP_DELAY
getFirmwareReply 0x19 = Right BC_RESP_IF_THEN_ELSE
getFirmwareReply 0x1A = Right BC_RESP_WHILE
getFirmwareReply 0x28 = Right BS_RESP_VERSION
getFirmwareReply 0x29 = Right BS_RESP_TYPE
getFirmwareReply 0x2A = Right BS_RESP_MICROS
getFirmwareReply 0x2B = Right BS_RESP_MILLIS
getFirmwareReply 0x2C = Right BS_RESP_STRING
getFirmwareReply 0x2D = Right BS_RESP_DEBUG
getFirmwareReply 0x38 = Right DIG_RESP_READ_PIN
getFirmwareReply 0x39 = Right DIG_RESP_READ_PORT
getFirmwareReply 0x48 = Right ALG_RESP_READ_PIN
getFirmwareReply 0x58 = Right I2C_RESP_READ
getFirmwareReply 0x68 = Right STEP_RESP_2PIN
getFirmwareReply 0x69 = Right STEP_RESP_4PIN
getFirmwareReply 0x6A = Right STEP_RESP_STEP
getFirmwareReply 0x88 = Right SRVO_RESP_ATTACH
getFirmwareReply 0x89 = Right SRVO_RESP_READ
getFirmwareReply 0x8A = Right SRVO_RESP_READ_MICROS
getFirmwareReply 0xB0 = Right SCHED_RESP_QUERY
getFirmwareReply 0xB1 = Right SCHED_RESP_QUERY_ALL
getFirmwareReply 0xB2 = Right SCHED_RESP_BOOT
getFirmwareReply 0xC8 = Right REF_RESP_NEW
getFirmwareReply 0xC9 = Right REF_RESP_READ
getFirmwareReply 0xD8 = Right EXPR_RESP_RET
getFirmwareReply n    = Left n

data Processor = ATMEGA8
               | ATMEGA168
               | ATMEGA328P
               | ATMEGA1280
               | ATMEGA256
               | ATMEGA32U4
               | ATMEGA644P
               | ATMEGA644
               | ATMEGA645
               | SAM3X8E
               | X86
               | QUARK
               | UNKNOWN_PROCESSOR
    deriving (Eq, Show, Enum)
