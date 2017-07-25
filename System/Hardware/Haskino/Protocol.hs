-------------------------------------------------------------------------------
-- |
-- Module      :  System.Hardware.Haskino.Protocol
--                Based on System.Hardware.Arduino.Protocol
-- Copyright   :  (c) University of Kansas
--                System.Hardware.Arduino (c) Levent Erkok
-- License     :  BSD3
-- Stability   :  experimental
--
-- Internal representation of the Haskino Firmware protocol.
-------------------------------------------------------------------------------
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE ScopedTypeVariables #-}

module System.Hardware.Haskino.Protocol(framePackage, packageCommand, 
                                            packageProcedure, packageRemoteBinding,
                                            unpackageResponse, parseQueryResult,
                                            maxFirmwareSize, packageExpr,
                                            CommandState(..) ) where

import           Control.Monad.State
import           Control.Remote.Applicative.Types as T
import           Control.Remote.Monad
import           Control.Remote.Monad.Types       as T
import           Data.Bits                        (xor,shiftR,(.&.))
import qualified Data.ByteString                  as B
import           Data.Int                         (Int8, Int16, Int32)
import qualified Data.Map                         as M
import           Data.Word                        (Word8, Word16, Word32)

import           System.Hardware.Haskino.Data
import           System.Hardware.Haskino.Expr
import           System.Hardware.Haskino.Utils

-- | Maximum size of a Haskino Firmware message
maxFirmwareSize :: Int
maxFirmwareSize = 256

-- | Minimum and maximum servo pulse widths
minServo :: Int16 
minServo = 544

maxServo :: Int16 
maxServo = 2400

data CommandState = CommandState {ix        :: Int  
                                , ib        :: Int
                                , block     :: B.ByteString    
                                , blocks    :: [B.ByteString]}

framePackage :: B.ByteString -> B.ByteString
framePackage bs = B.append (B.concatMap escape bs) (B.append (escape $ check bs) (B.singleton 0x7E))
  where
    escape :: Word8 -> B.ByteString
    escape c = if c == 0x7E || c == 0x7D
               then B.pack $ [0x7D, xor c 0x20]
               else B.singleton c
    check b = B.foldl (+) 0 b

addCommand :: FirmwareCmd -> [Word8] -> State CommandState B.ByteString
addCommand cmd bs = return $ buildCommand cmd bs

buildCommand :: FirmwareCmd -> [Word8] -> B.ByteString
buildCommand cmd bs = B.pack $ firmwareCmdVal cmd : bs

-- | Package a request as a sequence of bytes to be sent to the board
-- using the Haskino Firmware protocol.
packageCommand :: forall a . ArduinoPrimitive a -> State CommandState B.ByteString
packageCommand SystemReset =
    addCommand BC_CMD_SYSTEM_RESET []
packageCommand (SetPinModeE p m) = 
    addCommand BC_CMD_SET_PIN_MODE (packageExpr p ++ packageExpr m)
packageCommand (DigitalWriteE p b) =
    addCommand DIG_CMD_WRITE_PIN (packageExpr p ++ packageExpr b)
packageCommand (DigitalPortWriteE p b m) =
    addCommand DIG_CMD_WRITE_PORT (packageExpr p ++ packageExpr b ++ packageExpr m)
packageCommand (AnalogWriteE p w) =
    addCommand ALG_CMD_WRITE_PIN (packageExpr p ++ packageExpr w)
packageCommand (ToneE p f (Just d)) =
    addCommand ALG_CMD_TONE_PIN (packageExpr p ++ packageExpr f ++ packageExpr d)
packageCommand (ToneE p f Nothing) =
    packageCommand (ToneE p f (Just 0))
packageCommand (NoToneE p) =
    addCommand ALG_CMD_NOTONE_PIN (packageExpr  p)
packageCommand (I2CWrite sa w8s) = 
    addCommand I2C_CMD_WRITE (packageExpr sa ++ packageExpr w8s)
packageCommand I2CConfig = 
    addCommand I2C_CMD_CONFIG []
packageCommand (StepperSetSpeedE st sp) = 
    addCommand STEP_CMD_SET_SPEED (packageExpr st ++ packageExpr sp)
packageCommand (ServoDetachE sv) = 
    addCommand SRVO_CMD_DETACH (packageExpr sv)
packageCommand (ServoWriteE sv w) = 
    addCommand SRVO_CMD_WRITE (packageExpr sv ++ packageExpr w)
packageCommand (ServoWriteMicrosE sv w) = 
    addCommand SRVO_CMD_WRITE_MICROS (packageExpr sv ++ packageExpr w)
packageCommand (DeleteTaskE tid) =
    addCommand SCHED_CMD_DELETE_TASK (packageExpr tid)
packageCommand (ScheduleTaskE tid tt) =
    addCommand SCHED_CMD_SCHED_TASK (packageExpr tid ++ packageExpr tt)
packageCommand ScheduleReset =
    addCommand SCHED_CMD_RESET []
packageCommand (AttachIntE p t m) =
    addCommand SCHED_CMD_ATTACH_INT (packageExpr p ++ packageExpr t ++ packageExpr m)
packageCommand (DetachIntE p) =
    addCommand SCHED_CMD_DETACH_INT (packageExpr p)
packageCommand (Interrupts) =
    addCommand SCHED_CMD_INTERRUPTS []
packageCommand (NoInterrupts) =
    addCommand SCHED_CMD_NOINTERRUPTS []
packageCommand (GiveSemE id) =
    addCommand SCHED_CMD_GIVE_SEM (packageExpr id)
packageCommand (TakeSemE id) =
    addCommand SCHED_CMD_TAKE_SEM (packageExpr id)
packageCommand (CreateTaskE tid m) = do
    (_, td) <- packageCodeBlock m
    s <- get
    let taskSize = fromIntegral (B.length td)
    cmd <- addCommand SCHED_CMD_CREATE_TASK ((packageExpr tid) ++ (packageExpr (LitW16 taskSize)) ++ (packageExpr (LitW16 (fromIntegral (ib s)))))                                   
    return $ (framePackage cmd) `B.append` (genAddToTaskCmds td)
  where
    -- Max command data size is max frame size - 7 
    -- command - 1 byte,checksum - 1 byte,frame flag - 1 byte
    -- task ID - 2 bytes (lit + constant), size - 2 bytes (lit + constant)
    maxCmdSize = maxFirmwareSize - 7
    genAddToTaskCmds tds | fromIntegral (B.length tds) > maxCmdSize = 
        addToTask (B.take maxCmdSize tds) 
            `B.append` (genAddToTaskCmds (B.drop maxCmdSize tds))
    genAddToTaskCmds tds = addToTask tds
    addToTask tds' = framePackage $ buildCommand SCHED_CMD_ADD_TO_TASK ((packageExpr tid) ++ 
                                                                          (packageExpr (LitW8 (fromIntegral (B.length tds')))) ++ 
                                                                          (B.unpack tds'))
packageCommand (WriteRemoteRefB (RemoteRefB i) e) = addWriteRefCommand EXPR_BOOL i e
packageCommand (WriteRemoteRefW8 (RemoteRefW8 i) e) = addWriteRefCommand EXPR_WORD8 i e
packageCommand (WriteRemoteRefW16 (RemoteRefW16 i) e) = addWriteRefCommand EXPR_WORD16 i e
packageCommand (WriteRemoteRefW32 (RemoteRefW32 i) e) = addWriteRefCommand EXPR_WORD32 i e
packageCommand (WriteRemoteRefI8 (RemoteRefI8 i) e) = addWriteRefCommand EXPR_INT8 i e
packageCommand (WriteRemoteRefI16 (RemoteRefI16 i) e) = addWriteRefCommand EXPR_INT16 i e
packageCommand (WriteRemoteRefI32 (RemoteRefI32 i) e) = addWriteRefCommand EXPR_INT32 i e
packageCommand (WriteRemoteRefL8 (RemoteRefL8 i) e) = addWriteRefCommand EXPR_LIST8 i e
packageCommand (WriteRemoteRefFloat (RemoteRefFloat i) e) = addWriteRefCommand EXPR_FLOAT i e
packageCommand (ModifyRemoteRefB (RemoteRefB i) f) = addWriteRefCommand EXPR_BOOL i f
packageCommand (ModifyRemoteRefW8 (RemoteRefW8 i) f) = addWriteRefCommand EXPR_WORD8 i f
packageCommand (ModifyRemoteRefW16 (RemoteRefW16 i) f) = addWriteRefCommand EXPR_WORD16 i f
packageCommand (ModifyRemoteRefW32 (RemoteRefW32 i) f) = addWriteRefCommand EXPR_WORD32 i f
packageCommand (ModifyRemoteRefI8 (RemoteRefI8 i) f) = addWriteRefCommand EXPR_INT8 i f
packageCommand (ModifyRemoteRefI16 (RemoteRefI16 i) f) = addWriteRefCommand EXPR_INT16 i f
packageCommand (ModifyRemoteRefI32 (RemoteRefI32 i) f) = addWriteRefCommand EXPR_INT32 i f
packageCommand (ModifyRemoteRefL8 (RemoteRefL8 i) f) = addWriteRefCommand EXPR_LIST8 i f
packageCommand (ModifyRemoteRefFloat (RemoteRefFloat i) f) = addWriteRefCommand EXPR_FLOAT i f
packageCommand (IfThenElseUnitE e cb1 cb2) = do
    (_, pc1) <- packageCodeBlock cb1
    (_, pc2) <- packageCodeBlock cb2
    let thenSize = word16ToBytes $ fromIntegral (B.length pc1)
    i <- addCommand BC_CMD_IF_THEN_ELSE ([fromIntegral $ fromEnum EXPR_UNIT, 0] ++ thenSize ++ (packageExpr e))
    return $ B.append i (B.append pc1 pc2)
packageCommand _ = error $ "packageCommand: Error Command not supported (It may have been a procedure)"

addWriteRefCommand :: ExprType -> Int -> Expr a -> State CommandState B.ByteString
addWriteRefCommand t i e = 
  addCommand REF_CMD_WRITE ([toW8 t, toW8 EXPR_WORD8, toW8 EXPR_LIT, fromIntegral i] ++ packageExpr e)

packageCodeBlock :: Arduino a -> State CommandState (a, B.ByteString)
packageCodeBlock (Arduino commands) = do
    startNewBlock 
    ret <- packMonad commands
    str <- endCurrentBlock
    return (ret, str)
  where
      startNewBlock :: State CommandState ()
      startNewBlock = do
          s <- get
          put s {block = B.empty, blocks = (block s) : (blocks s)}

      endCurrentBlock :: State CommandState B.ByteString
      endCurrentBlock = do
          s <- get
          put s {block = head $ blocks s, blocks = tail $ blocks s}
          return $ block s

      addToBlock :: B.ByteString -> State CommandState ()
      addToBlock bs = do
          s <- get
          put s {block = B.append (block s) bs}

      packShallowProcedure :: ArduinoPrimitive a -> a -> State CommandState a
      packShallowProcedure p r = do
          pp <- packageProcedure p
          addToBlock $ lenPackage pp
          return r

      packDeepProcedure :: ArduinoPrimitive a -> State CommandState Int
      packDeepProcedure p = do
          pp <- packageProcedure p
          addToBlock $ lenPackage pp
          s <- get
          put s {ib = (ib s) + 1}
          return $ ib s

      packNewRef :: ArduinoPrimitive a -> a -> State CommandState a
      packNewRef p r = do
          prb <- packageRemoteBinding p
          addToBlock $ lenPackage prb
          s <- get
          put s {ib = (ib s) + 1, ix = (ix s) + 1}
          return r

      packProcedure :: ArduinoPrimitive a -> State CommandState a
      packProcedure QueryFirmware = packShallowProcedure QueryFirmware 0
      packProcedure QueryFirmwareE = do
          i <- packDeepProcedure QueryFirmwareE 
          return $ RemBindW16 i
      packProcedure QueryProcessor = packShallowProcedure QueryProcessor UNKNOWN_PROCESSOR
      packProcedure QueryProcessorE = do
          i <- packDeepProcedure QueryProcessorE
          return $ RemBindW8 i
      packProcedure Micros = packShallowProcedure Micros 0
      packProcedure MicrosE = do
          i <- packDeepProcedure MicrosE
          return $ RemBindW32 i
      packProcedure Millis = packShallowProcedure Millis 0
      packProcedure MillisE = do
          i <- packDeepProcedure MillisE
          return $ RemBindW32 i
      packProcedure (DelayMillis ms) = packShallowProcedure (DelayMillis ms) ()
      packProcedure (DelayMillisE ms) = packShallowProcedure (DelayMillisE ms) ()
      packProcedure (DelayMicros ms) = packShallowProcedure (DelayMicros ms) ()
      packProcedure (DelayMicrosE ms) = packShallowProcedure (DelayMicrosE ms) ()
      packProcedure (DigitalRead p) = packShallowProcedure (DigitalRead p) False
      packProcedure (DigitalReadE p) = do
          i <- packDeepProcedure (DigitalReadE p)
          return $ RemBindB i
      packProcedure (DigitalPortRead p m) = packShallowProcedure (DigitalPortRead p m) 0
      packProcedure (DigitalPortReadE p m) = do
          i <- packDeepProcedure (DigitalPortReadE p m)
          return $ RemBindW8 i
      packProcedure (AnalogRead p) = packShallowProcedure (AnalogRead p) 0
      packProcedure (AnalogReadE p) = do
          i <- packDeepProcedure (AnalogReadE p)
          return $ RemBindW16 i
      packProcedure (I2CRead p n) = packShallowProcedure (I2CRead p n) []
      packProcedure (I2CReadE p n) = do
          i <- packDeepProcedure (I2CReadE p n)
          return $ RemBindList8 i
      packProcedure (Stepper2Pin s p1 p2) = packShallowProcedure (Stepper2Pin s p1 p2) 0
      packProcedure (Stepper2PinE s p1 p2) = do
          i <- packDeepProcedure (Stepper2PinE s p1 p2)
          return $ RemBindW8 i
      packProcedure (Stepper4Pin s p1 p2 p3 p4) = packShallowProcedure (Stepper4Pin s p1 p2 p3 p4) 0
      packProcedure (Stepper4PinE s p1 p2 p3 p4) = do
          i <- packDeepProcedure (Stepper4PinE s p1 p2 p3 p4)
          return $ RemBindW8 i
      packProcedure (StepperStepE st s) = packShallowProcedure (StepperStepE st s) ()
      packProcedure (ServoAttach p) = packShallowProcedure (ServoAttach p) 0
      packProcedure (ServoAttachE p) = do
          i <- packDeepProcedure (ServoAttachE p)
          return $ RemBindW8 i
      packProcedure (ServoAttachMinMax p min max) = packShallowProcedure (ServoAttachMinMax p min max) 0
      packProcedure (ServoAttachMinMaxE p min max) = do
          i <- packDeepProcedure (ServoAttachMinMaxE p min max)
          return $ RemBindW8 i
      packProcedure (ServoRead sv) = packShallowProcedure (ServoRead sv) 0
      packProcedure (ServoReadE sv) = do
          i <- packDeepProcedure (ServoReadE sv)
          return $ RemBindI16 i
      packProcedure (ServoReadMicros sv) = packShallowProcedure (ServoReadMicros sv) 0
      packProcedure (ServoReadMicrosE sv) = do
          i <- packDeepProcedure (ServoReadMicrosE sv)
          return $ RemBindI16 i
      packProcedure QueryAllTasks = packShallowProcedure QueryAllTasks []
      packProcedure QueryAllTasksE = do
          i <- packDeepProcedure QueryAllTasksE
          return $ RemBindList8 i
      packProcedure (QueryTask t) = packShallowProcedure (QueryTask t) Nothing
      packProcedure (QueryTaskE t) = packShallowProcedure (QueryTaskE t) Nothing
      packProcedure (BootTaskE tids) = do
          i <- packDeepProcedure (BootTaskE tids)
          return $ RemBindB i
      packProcedure (ReadRemoteRefB (RemoteRefB i')) = do
          i <- packDeepProcedure (ReadRemoteRefB (RemoteRefB i'))
          return $ RemBindB i
      packProcedure (ReadRemoteRefW8 (RemoteRefW8 i')) = do
          i <- packDeepProcedure (ReadRemoteRefW8 (RemoteRefW8 i'))
          return $ RemBindW8 i
      packProcedure (ReadRemoteRefW16 (RemoteRefW16 i')) = do
          i <- packDeepProcedure (ReadRemoteRefW16 (RemoteRefW16 i'))
          return $ RemBindW16 i
      packProcedure (ReadRemoteRefW32 (RemoteRefW32 i')) = do
          i <- packDeepProcedure (ReadRemoteRefW32 (RemoteRefW32 i'))
          return $ RemBindW32 i
      packProcedure (ReadRemoteRefI8 (RemoteRefI8 i')) = do
          i <- packDeepProcedure (ReadRemoteRefI8 (RemoteRefI8 i'))
          return $ RemBindI8 i
      packProcedure (ReadRemoteRefI16 (RemoteRefI16 i')) = do
          i <- packDeepProcedure (ReadRemoteRefI16 (RemoteRefI16 i'))
          return $ RemBindI16 i
      packProcedure (ReadRemoteRefI32 (RemoteRefI32 i')) = do
          i <- packDeepProcedure (ReadRemoteRefI32 (RemoteRefI32 i'))
          return $ RemBindI32 i
      packProcedure (ReadRemoteRefL8 (RemoteRefL8 i')) = do
          i <- packDeepProcedure (ReadRemoteRefL8 (RemoteRefL8 i'))
          return $ RemBindList8 i
      packProcedure (ReadRemoteRefFloat (RemoteRefFloat i')) = do
          i <- packDeepProcedure (ReadRemoteRefFloat (RemoteRefFloat i'))
          return $ RemBindFloat i
      packProcedure (NewRemoteRefB e) = do
          s <- get
          packNewRef (NewRemoteRefB e) (RemoteRefB (ix s))
      packProcedure (NewRemoteRefW8 e) = do
          s <- get
          packNewRef (NewRemoteRefW8 e) (RemoteRefW8 (ix s))
      packProcedure (NewRemoteRefW16 e) = do
          s <- get
          packNewRef (NewRemoteRefW16 e) (RemoteRefW16 (ix s))
      packProcedure (NewRemoteRefW32 e) = do
          s <- get
          packNewRef (NewRemoteRefW32 e) (RemoteRefW32 (ix s))
      packProcedure (NewRemoteRefI8 e) = do
          s <- get
          packNewRef (NewRemoteRefI8 e) (RemoteRefI8 (ix s))
      packProcedure (NewRemoteRefI16 e) = do
          s <- get
          packNewRef (NewRemoteRefI16 e) (RemoteRefI16 (ix s))
      packProcedure (NewRemoteRefI32 e) = do
          s <- get
          packNewRef (NewRemoteRefI32 e) (RemoteRefI32 (ix s))
      packProcedure (NewRemoteRefL8 e) = do
          s <- get
          packNewRef (NewRemoteRefL8 e) (RemoteRefL8 (ix s))
      packProcedure (NewRemoteRefFloat e) = do
          s <- get
          packNewRef (NewRemoteRefFloat e) (RemoteRefFloat (ix s))
      packProcedure (IfThenElseBoolE e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolE e cb1 cb2)
          return $ RemBindB i
      packProcedure (IfThenElseWord8E e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseWord8E e cb1 cb2)
          return $ RemBindW8 i
      packProcedure (IfThenElseWord16E e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseWord16E e cb1 cb2)
          return $ RemBindW16 i
      packProcedure (IfThenElseWord32E e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseWord32E e cb1 cb2)
          return $ RemBindW32 i
      packProcedure (IfThenElseInt8E e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseInt8E e cb1 cb2)
          return $ RemBindI8 i
      packProcedure (IfThenElseInt16E e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseInt16E e cb1 cb2)
          return $ RemBindI16 i
      packProcedure (IfThenElseInt32E e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseInt32E e cb1 cb2)
          return $ RemBindI32 i
      packProcedure (IfThenElseL8E e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8E e cb1 cb2)
          return $ RemBindList8 i
      packProcedure (IfThenElseFloatE e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatE e cb1 cb2)
          return $ RemBindFloat i
      -- The following IfThenElse* functions generated by toold/GenEitherTypes.hs
      packProcedure (IfThenElseUnitUnit e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseUnitUnit e cb1 cb2)
          return $ ExprLeft $ RemBindUnit i
      packProcedure (IfThenElseUnitBool e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseUnitBool e cb1 cb2)
          return $ ExprLeft $ RemBindUnit i
      packProcedure (IfThenElseUnitW8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseUnitW8 e cb1 cb2)
          return $ ExprLeft $ RemBindUnit i
      packProcedure (IfThenElseUnitW16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseUnitW16 e cb1 cb2)
          return $ ExprLeft $ RemBindUnit i
      packProcedure (IfThenElseUnitW32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseUnitW32 e cb1 cb2)
          return $ ExprLeft $ RemBindUnit i
      packProcedure (IfThenElseUnitI8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseUnitI8 e cb1 cb2)
          return $ ExprLeft $ RemBindUnit i
      packProcedure (IfThenElseUnitI16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseUnitI16 e cb1 cb2)
          return $ ExprLeft $ RemBindUnit i
      packProcedure (IfThenElseUnitI32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseUnitI32 e cb1 cb2)
          return $ ExprLeft $ RemBindUnit i
      packProcedure (IfThenElseUnitL8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseUnitL8 e cb1 cb2)
          return $ ExprLeft $ RemBindUnit i
      packProcedure (IfThenElseUnitFloat e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseUnitFloat e cb1 cb2)
          return $ ExprLeft $ RemBindUnit i
      packProcedure (IfThenElseBoolUnit e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolUnit e cb1 cb2)
          return $ ExprLeft $ RemBindB i
      packProcedure (IfThenElseBoolBool e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolBool e cb1 cb2)
          return $ ExprLeft $ RemBindB i
      packProcedure (IfThenElseBoolW8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolW8 e cb1 cb2)
          return $ ExprLeft $ RemBindB i
      packProcedure (IfThenElseBoolW16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolW16 e cb1 cb2)
          return $ ExprLeft $ RemBindB i
      packProcedure (IfThenElseBoolW32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolW32 e cb1 cb2)
          return $ ExprLeft $ RemBindB i
      packProcedure (IfThenElseBoolI8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolI8 e cb1 cb2)
          return $ ExprLeft $ RemBindB i
      packProcedure (IfThenElseBoolI16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolI16 e cb1 cb2)
          return $ ExprLeft $ RemBindB i
      packProcedure (IfThenElseBoolI32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolI32 e cb1 cb2)
          return $ ExprLeft $ RemBindB i
      packProcedure (IfThenElseBoolL8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolL8 e cb1 cb2)
          return $ ExprLeft $ RemBindB i
      packProcedure (IfThenElseBoolFloat e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseBoolFloat e cb1 cb2)
          return $ ExprLeft $ RemBindB i
      packProcedure (IfThenElseW8Unit e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW8Unit e cb1 cb2)
          return $ ExprLeft $ RemBindW8 i
      packProcedure (IfThenElseW8Bool e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW8Bool e cb1 cb2)
          return $ ExprLeft $ RemBindW8 i
      packProcedure (IfThenElseW8W8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW8W8 e cb1 cb2)
          return $ ExprLeft $ RemBindW8 i
      packProcedure (IfThenElseW8W16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW8W16 e cb1 cb2)
          return $ ExprLeft $ RemBindW8 i
      packProcedure (IfThenElseW8W32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW8W32 e cb1 cb2)
          return $ ExprLeft $ RemBindW8 i
      packProcedure (IfThenElseW8I8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW8I8 e cb1 cb2)
          return $ ExprLeft $ RemBindW8 i
      packProcedure (IfThenElseW8I16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW8I16 e cb1 cb2)
          return $ ExprLeft $ RemBindW8 i
      packProcedure (IfThenElseW8I32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW8I32 e cb1 cb2)
          return $ ExprLeft $ RemBindW8 i
      packProcedure (IfThenElseW8L8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW8L8 e cb1 cb2)
          return $ ExprLeft $ RemBindW8 i
      packProcedure (IfThenElseW8Float e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW8Float e cb1 cb2)
          return $ ExprLeft $ RemBindW8 i
      packProcedure (IfThenElseW16Unit e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW16Unit e cb1 cb2)
          return $ ExprLeft $ RemBindW16 i
      packProcedure (IfThenElseW16Bool e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW16Bool e cb1 cb2)
          return $ ExprLeft $ RemBindW16 i
      packProcedure (IfThenElseW16W8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW16W8 e cb1 cb2)
          return $ ExprLeft $ RemBindW16 i
      packProcedure (IfThenElseW16W16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW16W16 e cb1 cb2)
          return $ ExprLeft $ RemBindW16 i
      packProcedure (IfThenElseW16W32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW16W32 e cb1 cb2)
          return $ ExprLeft $ RemBindW16 i
      packProcedure (IfThenElseW16I8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW16I8 e cb1 cb2)
          return $ ExprLeft $ RemBindW16 i
      packProcedure (IfThenElseW16I16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW16I16 e cb1 cb2)
          return $ ExprLeft $ RemBindW16 i
      packProcedure (IfThenElseW16I32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW16I32 e cb1 cb2)
          return $ ExprLeft $ RemBindW16 i
      packProcedure (IfThenElseW16L8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW16L8 e cb1 cb2)
          return $ ExprLeft $ RemBindW16 i
      packProcedure (IfThenElseW16Float e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW16Float e cb1 cb2)
          return $ ExprLeft $ RemBindW16 i
      packProcedure (IfThenElseW32Unit e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW32Unit e cb1 cb2)
          return $ ExprLeft $ RemBindW32 i
      packProcedure (IfThenElseW32Bool e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW32Bool e cb1 cb2)
          return $ ExprLeft $ RemBindW32 i
      packProcedure (IfThenElseW32W8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW32W8 e cb1 cb2)
          return $ ExprLeft $ RemBindW32 i
      packProcedure (IfThenElseW32W16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW32W16 e cb1 cb2)
          return $ ExprLeft $ RemBindW32 i
      packProcedure (IfThenElseW32W32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW32W32 e cb1 cb2)
          return $ ExprLeft $ RemBindW32 i
      packProcedure (IfThenElseW32I8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW32I8 e cb1 cb2)
          return $ ExprLeft $ RemBindW32 i
      packProcedure (IfThenElseW32I16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW32I16 e cb1 cb2)
          return $ ExprLeft $ RemBindW32 i
      packProcedure (IfThenElseW32I32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW32I32 e cb1 cb2)
          return $ ExprLeft $ RemBindW32 i
      packProcedure (IfThenElseW32L8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW32L8 e cb1 cb2)
          return $ ExprLeft $ RemBindW32 i
      packProcedure (IfThenElseW32Float e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseW32Float e cb1 cb2)
          return $ ExprLeft $ RemBindW32 i
      packProcedure (IfThenElseI8Unit e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI8Unit e cb1 cb2)
          return $ ExprLeft $ RemBindI8 i
      packProcedure (IfThenElseI8Bool e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI8Bool e cb1 cb2)
          return $ ExprLeft $ RemBindI8 i
      packProcedure (IfThenElseI8W8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI8W8 e cb1 cb2)
          return $ ExprLeft $ RemBindI8 i
      packProcedure (IfThenElseI8W16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI8W16 e cb1 cb2)
          return $ ExprLeft $ RemBindI8 i
      packProcedure (IfThenElseI8W32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI8W32 e cb1 cb2)
          return $ ExprLeft $ RemBindI8 i
      packProcedure (IfThenElseI8I8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI8I8 e cb1 cb2)
          return $ ExprLeft $ RemBindI8 i
      packProcedure (IfThenElseI8I16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI8I16 e cb1 cb2)
          return $ ExprLeft $ RemBindI8 i
      packProcedure (IfThenElseI8I32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI8I32 e cb1 cb2)
          return $ ExprLeft $ RemBindI8 i
      packProcedure (IfThenElseI8L8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI8L8 e cb1 cb2)
          return $ ExprLeft $ RemBindI8 i
      packProcedure (IfThenElseI8Float e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI8Float e cb1 cb2)
          return $ ExprLeft $ RemBindI8 i
      packProcedure (IfThenElseI16Unit e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI16Unit e cb1 cb2)
          return $ ExprLeft $ RemBindI16 i
      packProcedure (IfThenElseI16Bool e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI16Bool e cb1 cb2)
          return $ ExprLeft $ RemBindI16 i
      packProcedure (IfThenElseI16W8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI16W8 e cb1 cb2)
          return $ ExprLeft $ RemBindI16 i
      packProcedure (IfThenElseI16W16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI16W16 e cb1 cb2)
          return $ ExprLeft $ RemBindI16 i
      packProcedure (IfThenElseI16W32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI16W32 e cb1 cb2)
          return $ ExprLeft $ RemBindI16 i
      packProcedure (IfThenElseI16I8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI16I8 e cb1 cb2)
          return $ ExprLeft $ RemBindI16 i
      packProcedure (IfThenElseI16I16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI16I16 e cb1 cb2)
          return $ ExprLeft $ RemBindI16 i
      packProcedure (IfThenElseI16I32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI16I32 e cb1 cb2)
          return $ ExprLeft $ RemBindI16 i
      packProcedure (IfThenElseI16L8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI16L8 e cb1 cb2)
          return $ ExprLeft $ RemBindI16 i
      packProcedure (IfThenElseI16Float e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI16Float e cb1 cb2)
          return $ ExprLeft $ RemBindI16 i
      packProcedure (IfThenElseI32Unit e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI32Unit e cb1 cb2)
          return $ ExprLeft $ RemBindI32 i
      packProcedure (IfThenElseI32Bool e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI32Bool e cb1 cb2)
          return $ ExprLeft $ RemBindI32 i
      packProcedure (IfThenElseI32W8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI32W8 e cb1 cb2)
          return $ ExprLeft $ RemBindI32 i
      packProcedure (IfThenElseI32W16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI32W16 e cb1 cb2)
          return $ ExprLeft $ RemBindI32 i
      packProcedure (IfThenElseI32W32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI32W32 e cb1 cb2)
          return $ ExprLeft $ RemBindI32 i
      packProcedure (IfThenElseI32I8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI32I8 e cb1 cb2)
          return $ ExprLeft $ RemBindI32 i
      packProcedure (IfThenElseI32I16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI32I16 e cb1 cb2)
          return $ ExprLeft $ RemBindI32 i
      packProcedure (IfThenElseI32I32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI32I32 e cb1 cb2)
          return $ ExprLeft $ RemBindI32 i
      packProcedure (IfThenElseI32L8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI32L8 e cb1 cb2)
          return $ ExprLeft $ RemBindI32 i
      packProcedure (IfThenElseI32Float e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseI32Float e cb1 cb2)
          return $ ExprLeft $ RemBindI32 i
      packProcedure (IfThenElseL8Unit e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8Unit e cb1 cb2)
          return $ ExprLeft $ RemBindList8 i
      packProcedure (IfThenElseL8Bool e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8Bool e cb1 cb2)
          return $ ExprLeft $ RemBindList8 i
      packProcedure (IfThenElseL8W8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8W8 e cb1 cb2)
          return $ ExprLeft $ RemBindList8 i
      packProcedure (IfThenElseL8W16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8W16 e cb1 cb2)
          return $ ExprLeft $ RemBindList8 i
      packProcedure (IfThenElseL8W32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8W32 e cb1 cb2)
          return $ ExprLeft $ RemBindList8 i
      packProcedure (IfThenElseL8I8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8I8 e cb1 cb2)
          return $ ExprLeft $ RemBindList8 i
      packProcedure (IfThenElseL8I16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8I16 e cb1 cb2)
          return $ ExprLeft $ RemBindList8 i
      packProcedure (IfThenElseL8I32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8I32 e cb1 cb2)
          return $ ExprLeft $ RemBindList8 i
      packProcedure (IfThenElseL8L8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8L8 e cb1 cb2)
          return $ ExprLeft $ RemBindList8 i
      packProcedure (IfThenElseL8Float e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseL8Float e cb1 cb2)
          return $ ExprLeft $ RemBindList8 i
      packProcedure (IfThenElseFloatUnit e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatUnit e cb1 cb2)
          return $ ExprLeft $ RemBindFloat i
      packProcedure (IfThenElseFloatBool e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatBool e cb1 cb2)
          return $ ExprLeft $ RemBindFloat i
      packProcedure (IfThenElseFloatW8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatW8 e cb1 cb2)
          return $ ExprLeft $ RemBindFloat i
      packProcedure (IfThenElseFloatW16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatW16 e cb1 cb2)
          return $ ExprLeft $ RemBindFloat i
      packProcedure (IfThenElseFloatW32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatW32 e cb1 cb2)
          return $ ExprLeft $ RemBindFloat i
      packProcedure (IfThenElseFloatI8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatI8 e cb1 cb2)
          return $ ExprLeft $ RemBindFloat i
      packProcedure (IfThenElseFloatI16 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatI16 e cb1 cb2)
          return $ ExprLeft $ RemBindFloat i
      packProcedure (IfThenElseFloatI32 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatI32 e cb1 cb2)
          return $ ExprLeft $ RemBindFloat i
      packProcedure (IfThenElseFloatL8 e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatL8 e cb1 cb2)
          return $ ExprLeft $ RemBindFloat i
      packProcedure (IfThenElseFloatFloat e cb1 cb2) = do
          i <- packDeepProcedure (IfThenElseFloatFloat e cb1 cb2)
          return $ ExprLeft $ RemBindFloat i
      packProcedure (IterateUnitUnitE iv bf) = do
          i <- packDeepProcedure (IterateUnitUnitE iv bf)
          return $ RemBindUnit i
      packProcedure (IterateUnitBoolE iv bf) = do
          i <- packDeepProcedure (IterateUnitBoolE iv bf)
          return $ RemBindB i
      packProcedure (IterateUnitW8E iv bf) = do
          i <- packDeepProcedure (IterateUnitW8E iv bf)
          return $ RemBindW8 i
      packProcedure (IterateUnitW16E iv bf) = do
          i <- packDeepProcedure (IterateUnitW16E iv bf)
          return $ RemBindW16 i
      packProcedure (IterateUnitW32E iv bf) = do
          i <- packDeepProcedure (IterateUnitW32E iv bf)
          return $ RemBindW32 i
      packProcedure (IterateUnitI8E iv bf) = do
          i <- packDeepProcedure (IterateUnitI8E iv bf)
          return $ RemBindI8 i
      packProcedure (IterateUnitI16E iv bf) = do
          i <- packDeepProcedure (IterateUnitI16E iv bf)
          return $ RemBindI16 i
      packProcedure (IterateUnitI32E iv bf) = do
          i <- packDeepProcedure (IterateUnitI32E iv bf)
          return $ RemBindI32 i
      packProcedure (IterateUnitL8E iv bf) = do
          i <- packDeepProcedure (IterateUnitL8E iv bf)
          return $ RemBindList8 i
      packProcedure (IterateUnitFloatE iv bf) = do
          i <- packDeepProcedure (IterateUnitFloatE iv bf)
          return $ RemBindFloat i
      packProcedure (IterateBoolUnitE iv bf) = do
          i <- packDeepProcedure (IterateBoolUnitE iv bf)
          return $ RemBindUnit i
      packProcedure (IterateBoolBoolE iv bf) = do
          i <- packDeepProcedure (IterateBoolBoolE iv bf)
          return $ RemBindB i
      packProcedure (IterateBoolW8E iv bf) = do
          i <- packDeepProcedure (IterateBoolW8E iv bf)
          return $ RemBindW8 i
      packProcedure (IterateBoolW16E iv bf) = do
          i <- packDeepProcedure (IterateBoolW16E iv bf)
          return $ RemBindW16 i
      packProcedure (IterateBoolW32E iv bf) = do
          i <- packDeepProcedure (IterateBoolW32E iv bf)
          return $ RemBindW32 i
      packProcedure (IterateBoolI8E iv bf) = do
          i <- packDeepProcedure (IterateBoolI8E iv bf)
          return $ RemBindI8 i
      packProcedure (IterateBoolI16E iv bf) = do
          i <- packDeepProcedure (IterateBoolI16E iv bf)
          return $ RemBindI16 i
      packProcedure (IterateBoolI32E iv bf) = do
          i <- packDeepProcedure (IterateBoolI32E iv bf)
          return $ RemBindI32 i
      packProcedure (IterateBoolL8E iv bf) = do
          i <- packDeepProcedure (IterateBoolL8E iv bf)
          return $ RemBindList8 i
      packProcedure (IterateBoolFloatE iv bf) = do
          i <- packDeepProcedure (IterateBoolFloatE iv bf)
          return $ RemBindFloat i
      -- The following Iterate*E functions generated by toold/GenEitherTypes.hs
      packProcedure (IterateW8UnitE iv bf) = do
          i <- packDeepProcedure (IterateW8UnitE iv bf)
          return $ RemBindUnit i
      packProcedure (IterateW8BoolE iv bf) = do
          i <- packDeepProcedure (IterateW8BoolE iv bf)
          return $ RemBindB i
      packProcedure (IterateW8W8E iv bf) = do
          i <- packDeepProcedure (IterateW8W8E iv bf)
          return $ RemBindW8 i
      packProcedure (IterateW8W16E iv bf) = do
          i <- packDeepProcedure (IterateW8W16E iv bf)
          return $ RemBindW16 i
      packProcedure (IterateW8W32E iv bf) = do
          i <- packDeepProcedure (IterateW8W32E iv bf)
          return $ RemBindW32 i
      packProcedure (IterateW8I8E iv bf) = do
          i <- packDeepProcedure (IterateW8I8E iv bf)
          return $ RemBindI8 i
      packProcedure (IterateW8I16E iv bf) = do
          i <- packDeepProcedure (IterateW8I16E iv bf)
          return $ RemBindI16 i
      packProcedure (IterateW8I32E iv bf) = do
          i <- packDeepProcedure (IterateW8I32E iv bf)
          return $ RemBindI32 i
      packProcedure (IterateW8L8E iv bf) = do
          i <- packDeepProcedure (IterateW8L8E iv bf)
          return $ RemBindList8 i
      packProcedure (IterateW8FloatE iv bf) = do
          i <- packDeepProcedure (IterateW8FloatE iv bf)
          return $ RemBindFloat i
      packProcedure (IterateW16UnitE iv bf) = do
          i <- packDeepProcedure (IterateW16UnitE iv bf)
          return $ RemBindUnit i
      packProcedure (IterateW16BoolE iv bf) = do
          i <- packDeepProcedure (IterateW16BoolE iv bf)
          return $ RemBindB i
      packProcedure (IterateW16W8E iv bf) = do
          i <- packDeepProcedure (IterateW16W8E iv bf)
          return $ RemBindW8 i
      packProcedure (IterateW16W16E iv bf) = do
          i <- packDeepProcedure (IterateW16W16E iv bf)
          return $ RemBindW16 i
      packProcedure (IterateW16W32E iv bf) = do
          i <- packDeepProcedure (IterateW16W32E iv bf)
          return $ RemBindW32 i
      packProcedure (IterateW16I8E iv bf) = do
          i <- packDeepProcedure (IterateW16I8E iv bf)
          return $ RemBindI8 i
      packProcedure (IterateW16I16E iv bf) = do
          i <- packDeepProcedure (IterateW16I16E iv bf)
          return $ RemBindI16 i
      packProcedure (IterateW16I32E iv bf) = do
          i <- packDeepProcedure (IterateW16I32E iv bf)
          return $ RemBindI32 i
      packProcedure (IterateW16L8E iv bf) = do
          i <- packDeepProcedure (IterateW16L8E iv bf)
          return $ RemBindList8 i
      packProcedure (IterateW16FloatE iv bf) = do
          i <- packDeepProcedure (IterateW16FloatE iv bf)
          return $ RemBindFloat i
      packProcedure (IterateW32UnitE iv bf) = do
          i <- packDeepProcedure (IterateW32UnitE iv bf)
          return $ RemBindUnit i
      packProcedure (IterateW32BoolE iv bf) = do
          i <- packDeepProcedure (IterateW32BoolE iv bf)
          return $ RemBindB i
      packProcedure (IterateW32W8E iv bf) = do
          i <- packDeepProcedure (IterateW32W8E iv bf)
          return $ RemBindW8 i
      packProcedure (IterateW32W16E iv bf) = do
          i <- packDeepProcedure (IterateW32W16E iv bf)
          return $ RemBindW16 i
      packProcedure (IterateW32W32E iv bf) = do
          i <- packDeepProcedure (IterateW32W32E iv bf)
          return $ RemBindW32 i
      packProcedure (IterateW32I8E iv bf) = do
          i <- packDeepProcedure (IterateW32I8E iv bf)
          return $ RemBindI8 i
      packProcedure (IterateW32I16E iv bf) = do
          i <- packDeepProcedure (IterateW32I16E iv bf)
          return $ RemBindI16 i
      packProcedure (IterateW32I32E iv bf) = do
          i <- packDeepProcedure (IterateW32I32E iv bf)
          return $ RemBindI32 i
      packProcedure (IterateW32L8E iv bf) = do
          i <- packDeepProcedure (IterateW32L8E iv bf)
          return $ RemBindList8 i
      packProcedure (IterateW32FloatE iv bf) = do
          i <- packDeepProcedure (IterateW32FloatE iv bf)
          return $ RemBindFloat i
      packProcedure (IterateI8UnitE iv bf) = do
          i <- packDeepProcedure (IterateI8UnitE iv bf)
          return $ RemBindUnit i
      packProcedure (IterateI8BoolE iv bf) = do
          i <- packDeepProcedure (IterateI8BoolE iv bf)
          return $ RemBindB i
      packProcedure (IterateI8W8E iv bf) = do
          i <- packDeepProcedure (IterateI8W8E iv bf)
          return $ RemBindW8 i
      packProcedure (IterateI8W16E iv bf) = do
          i <- packDeepProcedure (IterateI8W16E iv bf)
          return $ RemBindW16 i
      packProcedure (IterateI8W32E iv bf) = do
          i <- packDeepProcedure (IterateI8W32E iv bf)
          return $ RemBindW32 i
      packProcedure (IterateI8I8E iv bf) = do
          i <- packDeepProcedure (IterateI8I8E iv bf)
          return $ RemBindI8 i
      packProcedure (IterateI8I16E iv bf) = do
          i <- packDeepProcedure (IterateI8I16E iv bf)
          return $ RemBindI16 i
      packProcedure (IterateI8I32E iv bf) = do
          i <- packDeepProcedure (IterateI8I32E iv bf)
          return $ RemBindI32 i
      packProcedure (IterateI8L8E iv bf) = do
          i <- packDeepProcedure (IterateI8L8E iv bf)
          return $ RemBindList8 i
      packProcedure (IterateI8FloatE iv bf) = do
          i <- packDeepProcedure (IterateI8FloatE iv bf)
          return $ RemBindFloat i
      packProcedure (IterateI16UnitE iv bf) = do
          i <- packDeepProcedure (IterateI16UnitE iv bf)
          return $ RemBindUnit i
      packProcedure (IterateI16BoolE iv bf) = do
          i <- packDeepProcedure (IterateI16BoolE iv bf)
          return $ RemBindB i
      packProcedure (IterateI16W8E iv bf) = do
          i <- packDeepProcedure (IterateI16W8E iv bf)
          return $ RemBindW8 i
      packProcedure (IterateI16W16E iv bf) = do
          i <- packDeepProcedure (IterateI16W16E iv bf)
          return $ RemBindW16 i
      packProcedure (IterateI16W32E iv bf) = do
          i <- packDeepProcedure (IterateI16W32E iv bf)
          return $ RemBindW32 i
      packProcedure (IterateI16I8E iv bf) = do
          i <- packDeepProcedure (IterateI16I8E iv bf)
          return $ RemBindI8 i
      packProcedure (IterateI16I16E iv bf) = do
          i <- packDeepProcedure (IterateI16I16E iv bf)
          return $ RemBindI16 i
      packProcedure (IterateI16I32E iv bf) = do
          i <- packDeepProcedure (IterateI16I32E iv bf)
          return $ RemBindI32 i
      packProcedure (IterateI16L8E iv bf) = do
          i <- packDeepProcedure (IterateI16L8E iv bf)
          return $ RemBindList8 i
      packProcedure (IterateI16FloatE iv bf) = do
          i <- packDeepProcedure (IterateI16FloatE iv bf)
          return $ RemBindFloat i
      packProcedure (IterateI32UnitE iv bf) = do
          i <- packDeepProcedure (IterateI32UnitE iv bf)
          return $ RemBindUnit i
      packProcedure (IterateI32BoolE iv bf) = do
          i <- packDeepProcedure (IterateI32BoolE iv bf)
          return $ RemBindB i
      packProcedure (IterateI32W8E iv bf) = do
          i <- packDeepProcedure (IterateI32W8E iv bf)
          return $ RemBindW8 i
      packProcedure (IterateI32W16E iv bf) = do
          i <- packDeepProcedure (IterateI32W16E iv bf)
          return $ RemBindW16 i
      packProcedure (IterateI32W32E iv bf) = do
          i <- packDeepProcedure (IterateI32W32E iv bf)
          return $ RemBindW32 i
      packProcedure (IterateI32I8E iv bf) = do
          i <- packDeepProcedure (IterateI32I8E iv bf)
          return $ RemBindI8 i
      packProcedure (IterateI32I16E iv bf) = do
          i <- packDeepProcedure (IterateI32I16E iv bf)
          return $ RemBindI16 i
      packProcedure (IterateI32I32E iv bf) = do
          i <- packDeepProcedure (IterateI32I32E iv bf)
          return $ RemBindI32 i
      packProcedure (IterateI32L8E iv bf) = do
          i <- packDeepProcedure (IterateI32L8E iv bf)
          return $ RemBindList8 i
      packProcedure (IterateI32FloatE iv bf) = do
          i <- packDeepProcedure (IterateI32FloatE iv bf)
          return $ RemBindFloat i
      packProcedure (IterateL8UnitE iv bf) = do
          i <- packDeepProcedure (IterateL8UnitE iv bf)
          return $ RemBindUnit i
      packProcedure (IterateL8BoolE iv bf) = do
          i <- packDeepProcedure (IterateL8BoolE iv bf)
          return $ RemBindB i
      packProcedure (IterateL8W8E iv bf) = do
          i <- packDeepProcedure (IterateL8W8E iv bf)
          return $ RemBindW8 i
      packProcedure (IterateL8W16E iv bf) = do
          i <- packDeepProcedure (IterateL8W16E iv bf)
          return $ RemBindW16 i
      packProcedure (IterateL8W32E iv bf) = do
          i <- packDeepProcedure (IterateL8W32E iv bf)
          return $ RemBindW32 i
      packProcedure (IterateL8I8E iv bf) = do
          i <- packDeepProcedure (IterateL8I8E iv bf)
          return $ RemBindI8 i
      packProcedure (IterateL8I16E iv bf) = do
          i <- packDeepProcedure (IterateL8I16E iv bf)
          return $ RemBindI16 i
      packProcedure (IterateL8I32E iv bf) = do
          i <- packDeepProcedure (IterateL8I32E iv bf)
          return $ RemBindI32 i
      packProcedure (IterateL8L8E iv bf) = do
          i <- packDeepProcedure (IterateL8L8E iv bf)
          return $ RemBindList8 i
      packProcedure (IterateL8FloatE iv bf) = do
          i <- packDeepProcedure (IterateL8FloatE iv bf)
          return $ RemBindFloat i
      packProcedure (IterateFloatUnitE iv bf) = do
          i <- packDeepProcedure (IterateFloatUnitE iv bf)
          return $ RemBindUnit i
      packProcedure (IterateFloatBoolE iv bf) = do
          i <- packDeepProcedure (IterateFloatBoolE iv bf)
          return $ RemBindB i
      packProcedure (IterateFloatW8E iv bf) = do
          i <- packDeepProcedure (IterateFloatW8E iv bf)
          return $ RemBindW8 i
      packProcedure (IterateFloatW16E iv bf) = do
          i <- packDeepProcedure (IterateFloatW16E iv bf)
          return $ RemBindW16 i
      packProcedure (IterateFloatW32E iv bf) = do
          i <- packDeepProcedure (IterateFloatW32E iv bf)
          return $ RemBindW32 i
      packProcedure (IterateFloatI8E iv bf) = do
          i <- packDeepProcedure (IterateFloatI8E iv bf)
          return $ RemBindI8 i
      packProcedure (IterateFloatI16E iv bf) = do
          i <- packDeepProcedure (IterateFloatI16E iv bf)
          return $ RemBindI16 i
      packProcedure (IterateFloatI32E iv bf) = do
          i <- packDeepProcedure (IterateFloatI32E iv bf)
          return $ RemBindI32 i
      packProcedure (IterateFloatL8E iv bf) = do
          i <- packDeepProcedure (IterateFloatL8E iv bf)
          return $ RemBindList8 i
      packProcedure (IterateFloatFloatE iv bf) = do
          i <- packDeepProcedure (IterateFloatFloatE iv bf)
          return $ RemBindFloat i
      packProcedure (DebugE tids) = packShallowProcedure (DebugE tids) ()
      -- For sending as part of a Scheduler task, debug and die make no sense.  
      -- Instead of signalling an error, at this point they are just ignored.
      packProcedure (Debug _) = return ()
      packProcedure DebugListen = return ()
      packProcedure (Die _ _) = return ()
      packProcedure _ = error "packProcedure: unsupported Procedure (it may have been a command)"

      packAppl :: RemoteApplicative ArduinoPrimitive a -> State CommandState a
      packAppl (T.Primitive p) = case knownResult p of
                                   Just a -> do
                                              pc <- packageCommand p
                                              addToBlock $ lenPackage pc
                                              return a
                                   Nothing -> packProcedure p
      packAppl (T.Ap a1 a2) = do
          f <- packAppl a1
          g <- packAppl a2
          return $ f g
      packAppl (T.Pure a)  = return a
      packAppl (T.Alt _ _) = error "packAppl: \"Alt\" is not supported"
      packAppl  T.Empty    = error "packAppl: \"Empty\" is not supported"

      packMonad :: RemoteMonad  ArduinoPrimitive a -> State CommandState a
      packMonad (T.Appl app) = packAppl app
      packMonad (T.Bind m k) = do
          r <- packMonad m
          packMonad (k r)
      packMonad (T.Ap' m1 m2) = do
          f <- packMonad m1
          g <- packMonad m2
          return $ f g
      packMonad (T.Alt' _ _)  = error "packMonad: \"Alt\" is not supported"
      packMonad T.Empty'      = error "packMonad: \"Alt\" is not supported"
      packMonad (T.Catch _ _) = error "packMonad: \"Catch\" is not supported"
      packMonad (T.Throw  _)  = error "packMonad: \"Throw\" is not supported"

lenPackage :: B.ByteString -> B.ByteString
lenPackage package = B.append (lenEncode $ B.length package) package      

-- Length of the code block is encoded with a 1 or 3 byte sequence.
-- If the length is 0-254, the length is sent as a one byte value.
-- If the length is greater than 255, it is sent as a zero byte,
-- following by a 16 bit little endian length.
-- (Zero is not a valid length, as it would be an empty command)
lenEncode :: Int -> B.ByteString
lenEncode l = if l < 255
              then B.singleton $ fromIntegral l 
              else B.pack $ 0xFF : (word16ToBytes $ fromIntegral l)

packageProcedure :: ArduinoPrimitive a -> State CommandState B.ByteString
packageProcedure p = do
    s <- get
    packageProcedure' p (fromIntegral (ib s))
  where
    packageProcedure' :: ArduinoPrimitive a -> Int -> State CommandState B.ByteString
    packageProcedure' QueryFirmware ib    = addCommand BS_CMD_REQUEST_VERSION [fromIntegral ib]
    packageProcedure' QueryFirmwareE ib   = addCommand BS_CMD_REQUEST_VERSION [fromIntegral ib]
    packageProcedure' QueryProcessor ib   = addCommand BS_CMD_REQUEST_TYPE [fromIntegral ib]
    packageProcedure' QueryProcessorE ib  = addCommand BS_CMD_REQUEST_TYPE [fromIntegral ib]
    packageProcedure' Micros ib           = addCommand BS_CMD_REQUEST_MICROS [fromIntegral ib]
    packageProcedure' MicrosE ib          = addCommand BS_CMD_REQUEST_MICROS [fromIntegral ib]
    packageProcedure' Millis ib           = addCommand BS_CMD_REQUEST_MILLIS [fromIntegral ib]
    packageProcedure' MillisE ib          = addCommand BS_CMD_REQUEST_MILLIS [fromIntegral ib]
    packageProcedure' (DigitalRead p) ib  = addCommand DIG_CMD_READ_PIN ((fromIntegral ib) : (packageExpr $ lit p))
    packageProcedure' (DigitalReadE pe) ib = addCommand DIG_CMD_READ_PIN ((fromIntegral ib) : (packageExpr pe))
    packageProcedure' (DigitalPortRead p m) ib  = addCommand DIG_CMD_READ_PORT ((fromIntegral ib) : ((packageExpr $ lit p) ++ (packageExpr $ lit m)))
    packageProcedure' (DigitalPortReadE pe me) ib = addCommand DIG_CMD_READ_PORT ((fromIntegral ib) : ((packageExpr pe) ++ (packageExpr me)))
    packageProcedure' (AnalogRead p) ib   = addCommand ALG_CMD_READ_PIN ((fromIntegral ib) : (packageExpr $ lit p))
    packageProcedure' (AnalogReadE pe) ib = addCommand ALG_CMD_READ_PIN ((fromIntegral ib) : (packageExpr pe))
    packageProcedure' (I2CRead sa cnt) ib = addCommand I2C_CMD_READ ((fromIntegral ib) : ((packageExpr $ lit sa) ++ (packageExpr $ lit cnt)))
    packageProcedure' (I2CReadE sae cnte) ib = addCommand I2C_CMD_READ ((fromIntegral ib) : ((packageExpr sae) ++ (packageExpr cnte)))
    packageProcedure' (Stepper2Pin s p1 p2) ib = addCommand STEP_CMD_2PIN ((fromIntegral ib) : ((packageExpr $ lit s) ++ (packageExpr $ lit p1) ++ (packageExpr $ lit p2)))
    packageProcedure' (Stepper2PinE s p1 p2) ib = addCommand STEP_CMD_2PIN ((fromIntegral ib) : ((packageExpr s) ++ (packageExpr p1) ++ (packageExpr p2)))
    packageProcedure' (Stepper4Pin s p1 p2 p3 p4) ib = addCommand STEP_CMD_4PIN ((fromIntegral ib) : ((packageExpr $ lit s) ++ (packageExpr $ lit p1) ++ (packageExpr $ lit p2) ++ (packageExpr $ lit p3) ++ (packageExpr $ lit p4)))
    packageProcedure' (Stepper4PinE s p1 p2 p3 p4) ib = addCommand STEP_CMD_4PIN ((fromIntegral ib) : ((packageExpr s) ++ (packageExpr p1) ++ (packageExpr p2)++ (packageExpr p3) ++ (packageExpr p4)))
    packageProcedure' (StepperStepE st s) ib = addCommand STEP_CMD_STEP ((fromIntegral ib) : ((packageExpr st) ++ (packageExpr s)))
    packageProcedure' (ServoAttach p) ib = addCommand SRVO_CMD_ATTACH ((fromIntegral ib) : ((packageExpr $ lit p) ++ (packageExpr $ lit minServo) ++ (packageExpr $ lit maxServo)))
    packageProcedure' (ServoAttachE p) ib = addCommand SRVO_CMD_ATTACH ((fromIntegral ib) : ((packageExpr p) ++ (packageExpr $ lit minServo) ++ (packageExpr $ lit maxServo)))
    packageProcedure' (ServoAttachMinMax p min max) ib = addCommand SRVO_CMD_ATTACH ((fromIntegral ib) : ((packageExpr $ lit p) ++ (packageExpr $ lit min) ++ (packageExpr $ lit max)))
    packageProcedure' (ServoAttachMinMaxE p min max) ib = addCommand SRVO_CMD_ATTACH ((fromIntegral ib) : ((packageExpr p)++ (packageExpr min) ++ (packageExpr max)))
    packageProcedure' (ServoRead sv) ib = addCommand SRVO_CMD_READ ((fromIntegral ib) : ((packageExpr $ lit sv)))
    packageProcedure' (ServoReadE sv) ib = addCommand SRVO_CMD_READ ((fromIntegral ib) : ((packageExpr sv)))
    packageProcedure' (ServoReadMicros sv) ib = addCommand SRVO_CMD_READ_MICROS ((fromIntegral ib) : ((packageExpr $ lit sv)))
    packageProcedure' (ServoReadMicrosE sv) ib = addCommand SRVO_CMD_READ_MICROS ((fromIntegral ib) : ((packageExpr sv)))
    packageProcedure' QueryAllTasks ib    = addCommand SCHED_CMD_QUERY_ALL [fromIntegral ib]
    packageProcedure' QueryAllTasksE ib   = addCommand SCHED_CMD_QUERY_ALL [fromIntegral ib]
    packageProcedure' (QueryTask tid) ib  = addCommand SCHED_CMD_QUERY ((fromIntegral ib) : (packageExpr $ lit tid))
    packageProcedure' (QueryTaskE tide) ib = addCommand SCHED_CMD_QUERY ((fromIntegral ib) : (packageExpr tide))
    packageProcedure' (DelayMillis ms) ib  = addCommand BC_CMD_DELAY_MILLIS ((fromIntegral ib) : (packageExpr $ lit ms))
    packageProcedure' (DelayMillisE ms) ib = addCommand BC_CMD_DELAY_MILLIS ((fromIntegral ib) : (packageExpr ms))
    packageProcedure' (DelayMicros ms) ib  = addCommand BC_CMD_DELAY_MICROS ((fromIntegral ib) : (packageExpr $ lit ms))
    packageProcedure' (DelayMicrosE ms) ib = addCommand BC_CMD_DELAY_MICROS ((fromIntegral ib) : (packageExpr ms))
    packageProcedure' (BootTaskE tids) ib = addCommand SCHED_CMD_BOOT_TASK ((fromIntegral ib) : (packageExpr tids))
    packageProcedure' (ReadRemoteRefB (RemoteRefB i)) ib = packageReadRefProcedure EXPR_BOOL ib i
    packageProcedure' (ReadRemoteRefW8 (RemoteRefW8 i)) ib = packageReadRefProcedure EXPR_WORD8 ib i
    packageProcedure' (ReadRemoteRefW16 (RemoteRefW16 i)) ib = packageReadRefProcedure EXPR_WORD16 ib i
    packageProcedure' (ReadRemoteRefW32 (RemoteRefW32 i)) ib = packageReadRefProcedure EXPR_WORD32 ib i
    packageProcedure' (ReadRemoteRefI8 (RemoteRefI8 i)) ib = packageReadRefProcedure EXPR_INT8 ib i
    packageProcedure' (ReadRemoteRefI16 (RemoteRefI16 i)) ib = packageReadRefProcedure EXPR_INT16 ib i
    packageProcedure' (ReadRemoteRefI32 (RemoteRefI32 i)) ib = packageReadRefProcedure EXPR_INT32 ib i
    packageProcedure' (ReadRemoteRefL8 (RemoteRefL8 i)) ib = packageReadRefProcedure EXPR_LIST8 ib i
    packageProcedure' (ReadRemoteRefFloat (RemoteRefFloat i)) ib = packageReadRefProcedure EXPR_FLOAT ib i
    packageProcedure' (DebugE s) ib = addCommand BS_CMD_DEBUG ((fromIntegral ib) : (packageExpr s))
    packageProcedure' (IfThenElseBoolE e cb1 cb2) ib = packageIfThenElseProcedure EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseWord8E e cb1 cb2) ib = packageIfThenElseProcedure EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseWord16E e cb1 cb2) ib = packageIfThenElseProcedure EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseWord32E e cb1 cb2) ib = packageIfThenElseProcedure EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseInt8E e cb1 cb2) ib = packageIfThenElseProcedure EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseInt16E e cb1 cb2) ib = packageIfThenElseProcedure EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseInt32E e cb1 cb2) ib = packageIfThenElseProcedure EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseL8E e cb1 cb2) ib = packageIfThenElseProcedure EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseFloatE e cb1 cb2) ib = packageIfThenElseProcedure EXPR_FLOAT ib e cb1 cb2
      -- The following IfThenElse* functions generated by toold/GenEitherTypes.hs
    packageProcedure' (IfThenElseUnitUnit e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_UNIT EXPR_UNIT ib e cb1 cb2
    packageProcedure' (IfThenElseUnitBool e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_UNIT EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseUnitW8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_UNIT EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseUnitW16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_UNIT EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseUnitW32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_UNIT EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseUnitI8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_UNIT EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseUnitI16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_UNIT EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseUnitI32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_UNIT EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseUnitL8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_UNIT EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseUnitFloat e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_UNIT EXPR_FLOAT ib e cb1 cb2
    packageProcedure' (IfThenElseBoolUnit e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_BOOL EXPR_UNIT ib e cb1 cb2
    packageProcedure' (IfThenElseBoolBool e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_BOOL EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseBoolW8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_BOOL EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseBoolW16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_BOOL EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseBoolW32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_BOOL EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseBoolI8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_BOOL EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseBoolI16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_BOOL EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseBoolI32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_BOOL EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseBoolL8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_BOOL EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseBoolFloat e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_BOOL EXPR_FLOAT ib e cb1 cb2
    packageProcedure' (IfThenElseW8Unit e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD8 EXPR_UNIT ib e cb1 cb2
    packageProcedure' (IfThenElseW8Bool e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD8 EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseW8W8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD8 EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseW8W16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD8 EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseW8W32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD8 EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseW8I8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD8 EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseW8I16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD8 EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseW8I32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD8 EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseW8L8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD8 EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseW8Float e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD8 EXPR_FLOAT ib e cb1 cb2
    packageProcedure' (IfThenElseW16Unit e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD16 EXPR_UNIT ib e cb1 cb2
    packageProcedure' (IfThenElseW16Bool e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD16 EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseW16W8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD16 EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseW16W16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD16 EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseW16W32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD16 EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseW16I8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD16 EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseW16I16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD16 EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseW16I32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD16 EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseW16L8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD16 EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseW16Float e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD16 EXPR_FLOAT ib e cb1 cb2
    packageProcedure' (IfThenElseW32Unit e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD32 EXPR_UNIT ib e cb1 cb2
    packageProcedure' (IfThenElseW32Bool e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD32 EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseW32W8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD32 EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseW32W16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD32 EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseW32W32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD32 EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseW32I8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD32 EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseW32I16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD32 EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseW32I32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD32 EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseW32L8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD32 EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseW32Float e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_WORD32 EXPR_FLOAT ib e cb1 cb2
    packageProcedure' (IfThenElseI8Unit e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT8 EXPR_UNIT ib e cb1 cb2
    packageProcedure' (IfThenElseI8Bool e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT8 EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseI8W8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT8 EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseI8W16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT8 EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseI8W32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT8 EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseI8I8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT8 EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseI8I16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT8 EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseI8I32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT8 EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseI8L8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT8 EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseI8Float e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT8 EXPR_FLOAT ib e cb1 cb2
    packageProcedure' (IfThenElseI16Unit e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT16 EXPR_UNIT ib e cb1 cb2
    packageProcedure' (IfThenElseI16Bool e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT16 EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseI16W8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT16 EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseI16W16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT16 EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseI16W32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT16 EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseI16I8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT16 EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseI16I16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT16 EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseI16I32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT16 EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseI16L8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT16 EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseI16Float e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT16 EXPR_FLOAT ib e cb1 cb2
    packageProcedure' (IfThenElseI32Unit e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT32 EXPR_UNIT ib e cb1 cb2
    packageProcedure' (IfThenElseI32Bool e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT32 EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseI32W8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT32 EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseI32W16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT32 EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseI32W32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT32 EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseI32I8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT32 EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseI32I16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT32 EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseI32I32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT32 EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseI32L8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT32 EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseI32Float e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_INT32 EXPR_FLOAT ib e cb1 cb2
    packageProcedure' (IfThenElseL8Unit e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_LIST8 EXPR_UNIT ib e cb1 cb2
    packageProcedure' (IfThenElseL8Bool e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_LIST8 EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseL8W8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_LIST8 EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseL8W16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_LIST8 EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseL8W32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_LIST8 EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseL8I8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_LIST8 EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseL8I16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_LIST8 EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseL8I32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_LIST8 EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseL8L8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_LIST8 EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseL8Float e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_LIST8 EXPR_FLOAT ib e cb1 cb2
    packageProcedure' (IfThenElseFloatUnit e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_FLOAT EXPR_UNIT ib e cb1 cb2
    packageProcedure' (IfThenElseFloatBool e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_FLOAT EXPR_BOOL ib e cb1 cb2
    packageProcedure' (IfThenElseFloatW8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_FLOAT EXPR_WORD8 ib e cb1 cb2
    packageProcedure' (IfThenElseFloatW16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_FLOAT EXPR_WORD16 ib e cb1 cb2
    packageProcedure' (IfThenElseFloatW32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_FLOAT EXPR_WORD32 ib e cb1 cb2
    packageProcedure' (IfThenElseFloatI8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_FLOAT EXPR_INT8 ib e cb1 cb2
    packageProcedure' (IfThenElseFloatI16 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_FLOAT EXPR_INT16 ib e cb1 cb2
    packageProcedure' (IfThenElseFloatI32 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_FLOAT EXPR_INT32 ib e cb1 cb2
    packageProcedure' (IfThenElseFloatL8 e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_FLOAT EXPR_LIST8 ib e cb1 cb2
    packageProcedure' (IfThenElseFloatFloat e cb1 cb2) ib = packageIfThenElseEitherProcedure EXPR_FLOAT EXPR_FLOAT ib e cb1 cb2
      -- The following Iterate*E functions generated by toold/GenEitherTypes.hs
    packageProcedure' (IterateUnitUnitE iv bf) ib = packageIterateProcedure EXPR_UNIT EXPR_UNIT ib (RemBindUnit ib) iv bf
    packageProcedure' (IterateUnitBoolE iv bf) ib = packageIterateProcedure EXPR_UNIT EXPR_BOOL ib (RemBindUnit ib) iv bf
    packageProcedure' (IterateUnitW8E iv bf) ib = packageIterateProcedure EXPR_UNIT EXPR_WORD8 ib (RemBindUnit ib) iv bf
    packageProcedure' (IterateUnitW16E iv bf) ib = packageIterateProcedure EXPR_UNIT EXPR_WORD16 ib (RemBindUnit ib) iv bf
    packageProcedure' (IterateUnitW32E iv bf) ib = packageIterateProcedure EXPR_UNIT EXPR_WORD32 ib (RemBindUnit ib) iv bf
    packageProcedure' (IterateUnitI8E iv bf) ib = packageIterateProcedure EXPR_UNIT EXPR_INT8 ib (RemBindUnit ib) iv bf
    packageProcedure' (IterateUnitI16E iv bf) ib = packageIterateProcedure EXPR_UNIT EXPR_INT16 ib (RemBindUnit ib) iv bf
    packageProcedure' (IterateUnitI32E iv bf) ib = packageIterateProcedure EXPR_UNIT EXPR_INT32 ib (RemBindUnit ib) iv bf
    packageProcedure' (IterateUnitL8E iv bf) ib = packageIterateProcedure EXPR_UNIT EXPR_LIST8 ib (RemBindUnit ib) iv bf
    packageProcedure' (IterateUnitFloatE iv bf) ib = packageIterateProcedure EXPR_UNIT EXPR_FLOAT ib (RemBindUnit ib) iv bf
    packageProcedure' (IterateBoolUnitE iv bf) ib = packageIterateProcedure EXPR_BOOL EXPR_UNIT ib (RemBindB ib) iv bf
    packageProcedure' (IterateBoolBoolE iv bf) ib = packageIterateProcedure EXPR_BOOL EXPR_BOOL ib (RemBindB ib) iv bf
    packageProcedure' (IterateBoolW8E iv bf) ib = packageIterateProcedure EXPR_BOOL EXPR_WORD8 ib (RemBindB ib) iv bf
    packageProcedure' (IterateBoolW16E iv bf) ib = packageIterateProcedure EXPR_BOOL EXPR_WORD16 ib (RemBindB ib) iv bf
    packageProcedure' (IterateBoolW32E iv bf) ib = packageIterateProcedure EXPR_BOOL EXPR_WORD32 ib (RemBindB ib) iv bf
    packageProcedure' (IterateBoolI8E iv bf) ib = packageIterateProcedure EXPR_BOOL EXPR_INT8 ib (RemBindB ib) iv bf
    packageProcedure' (IterateBoolI16E iv bf) ib = packageIterateProcedure EXPR_BOOL EXPR_INT16 ib (RemBindB ib) iv bf
    packageProcedure' (IterateBoolI32E iv bf) ib = packageIterateProcedure EXPR_BOOL EXPR_INT32 ib (RemBindB ib) iv bf
    packageProcedure' (IterateBoolL8E iv bf) ib = packageIterateProcedure EXPR_BOOL EXPR_LIST8 ib (RemBindB ib) iv bf
    packageProcedure' (IterateBoolFloatE iv bf) ib = packageIterateProcedure EXPR_BOOL EXPR_FLOAT ib (RemBindB ib) iv bf
    packageProcedure' (IterateW8UnitE iv bf) ib = packageIterateProcedure EXPR_WORD8 EXPR_UNIT ib (RemBindW8 ib) iv bf
    packageProcedure' (IterateW8BoolE iv bf) ib = packageIterateProcedure EXPR_WORD8 EXPR_BOOL ib (RemBindW8 ib) iv bf
    packageProcedure' (IterateW8W8E iv bf) ib = packageIterateProcedure EXPR_WORD8 EXPR_WORD8 ib (RemBindW8 ib) iv bf
    packageProcedure' (IterateW8W16E iv bf) ib = packageIterateProcedure EXPR_WORD8 EXPR_WORD16 ib (RemBindW8 ib) iv bf
    packageProcedure' (IterateW8W32E iv bf) ib = packageIterateProcedure EXPR_WORD8 EXPR_WORD32 ib (RemBindW8 ib) iv bf
    packageProcedure' (IterateW8I8E iv bf) ib = packageIterateProcedure EXPR_WORD8 EXPR_INT8 ib (RemBindW8 ib) iv bf
    packageProcedure' (IterateW8I16E iv bf) ib = packageIterateProcedure EXPR_WORD8 EXPR_INT16 ib (RemBindW8 ib) iv bf
    packageProcedure' (IterateW8I32E iv bf) ib = packageIterateProcedure EXPR_WORD8 EXPR_INT32 ib (RemBindW8 ib) iv bf
    packageProcedure' (IterateW8L8E iv bf) ib = packageIterateProcedure EXPR_WORD8 EXPR_LIST8 ib (RemBindW8 ib) iv bf
    packageProcedure' (IterateW8FloatE iv bf) ib = packageIterateProcedure EXPR_WORD8 EXPR_FLOAT ib (RemBindW8 ib) iv bf
    packageProcedure' (IterateW16UnitE iv bf) ib = packageIterateProcedure EXPR_WORD16 EXPR_UNIT ib (RemBindW16 ib) iv bf
    packageProcedure' (IterateW16BoolE iv bf) ib = packageIterateProcedure EXPR_WORD16 EXPR_BOOL ib (RemBindW16 ib) iv bf
    packageProcedure' (IterateW16W8E iv bf) ib = packageIterateProcedure EXPR_WORD16 EXPR_WORD8 ib (RemBindW16 ib) iv bf
    packageProcedure' (IterateW16W16E iv bf) ib = packageIterateProcedure EXPR_WORD16 EXPR_WORD16 ib (RemBindW16 ib) iv bf
    packageProcedure' (IterateW16W32E iv bf) ib = packageIterateProcedure EXPR_WORD16 EXPR_WORD32 ib (RemBindW16 ib) iv bf
    packageProcedure' (IterateW16I8E iv bf) ib = packageIterateProcedure EXPR_WORD16 EXPR_INT8 ib (RemBindW16 ib) iv bf
    packageProcedure' (IterateW16I16E iv bf) ib = packageIterateProcedure EXPR_WORD16 EXPR_INT16 ib (RemBindW16 ib) iv bf
    packageProcedure' (IterateW16I32E iv bf) ib = packageIterateProcedure EXPR_WORD16 EXPR_INT32 ib (RemBindW16 ib) iv bf
    packageProcedure' (IterateW16L8E iv bf) ib = packageIterateProcedure EXPR_WORD16 EXPR_LIST8 ib (RemBindW16 ib) iv bf
    packageProcedure' (IterateW16FloatE iv bf) ib = packageIterateProcedure EXPR_WORD16 EXPR_FLOAT ib (RemBindW16 ib) iv bf
    packageProcedure' (IterateW32UnitE iv bf) ib = packageIterateProcedure EXPR_WORD32 EXPR_UNIT ib (RemBindW32 ib) iv bf
    packageProcedure' (IterateW32BoolE iv bf) ib = packageIterateProcedure EXPR_WORD32 EXPR_BOOL ib (RemBindW32 ib) iv bf
    packageProcedure' (IterateW32W8E iv bf) ib = packageIterateProcedure EXPR_WORD32 EXPR_WORD8 ib (RemBindW32 ib) iv bf
    packageProcedure' (IterateW32W16E iv bf) ib = packageIterateProcedure EXPR_WORD32 EXPR_WORD16 ib (RemBindW32 ib) iv bf
    packageProcedure' (IterateW32W32E iv bf) ib = packageIterateProcedure EXPR_WORD32 EXPR_WORD32 ib (RemBindW32 ib) iv bf
    packageProcedure' (IterateW32I8E iv bf) ib = packageIterateProcedure EXPR_WORD32 EXPR_INT8 ib (RemBindW32 ib) iv bf
    packageProcedure' (IterateW32I16E iv bf) ib = packageIterateProcedure EXPR_WORD32 EXPR_INT16 ib (RemBindW32 ib) iv bf
    packageProcedure' (IterateW32I32E iv bf) ib = packageIterateProcedure EXPR_WORD32 EXPR_INT32 ib (RemBindW32 ib) iv bf
    packageProcedure' (IterateW32L8E iv bf) ib = packageIterateProcedure EXPR_WORD32 EXPR_LIST8 ib (RemBindW32 ib) iv bf
    packageProcedure' (IterateW32FloatE iv bf) ib = packageIterateProcedure EXPR_WORD32 EXPR_FLOAT ib (RemBindW32 ib) iv bf
    packageProcedure' (IterateI8UnitE iv bf) ib = packageIterateProcedure EXPR_INT8 EXPR_UNIT ib (RemBindI8 ib) iv bf
    packageProcedure' (IterateI8BoolE iv bf) ib = packageIterateProcedure EXPR_INT8 EXPR_BOOL ib (RemBindI8 ib) iv bf
    packageProcedure' (IterateI8W8E iv bf) ib = packageIterateProcedure EXPR_INT8 EXPR_WORD8 ib (RemBindI8 ib) iv bf
    packageProcedure' (IterateI8W16E iv bf) ib = packageIterateProcedure EXPR_INT8 EXPR_WORD16 ib (RemBindI8 ib) iv bf
    packageProcedure' (IterateI8W32E iv bf) ib = packageIterateProcedure EXPR_INT8 EXPR_WORD32 ib (RemBindI8 ib) iv bf
    packageProcedure' (IterateI8I8E iv bf) ib = packageIterateProcedure EXPR_INT8 EXPR_INT8 ib (RemBindI8 ib) iv bf
    packageProcedure' (IterateI8I16E iv bf) ib = packageIterateProcedure EXPR_INT8 EXPR_INT16 ib (RemBindI8 ib) iv bf
    packageProcedure' (IterateI8I32E iv bf) ib = packageIterateProcedure EXPR_INT8 EXPR_INT32 ib (RemBindI8 ib) iv bf
    packageProcedure' (IterateI8L8E iv bf) ib = packageIterateProcedure EXPR_INT8 EXPR_LIST8 ib (RemBindI8 ib) iv bf
    packageProcedure' (IterateI8FloatE iv bf) ib = packageIterateProcedure EXPR_INT8 EXPR_FLOAT ib (RemBindI8 ib) iv bf
    packageProcedure' (IterateI16UnitE iv bf) ib = packageIterateProcedure EXPR_INT16 EXPR_UNIT ib (RemBindI16 ib) iv bf
    packageProcedure' (IterateI16BoolE iv bf) ib = packageIterateProcedure EXPR_INT16 EXPR_BOOL ib (RemBindI16 ib) iv bf
    packageProcedure' (IterateI16W8E iv bf) ib = packageIterateProcedure EXPR_INT16 EXPR_WORD8 ib (RemBindI16 ib) iv bf
    packageProcedure' (IterateI16W16E iv bf) ib = packageIterateProcedure EXPR_INT16 EXPR_WORD16 ib (RemBindI16 ib) iv bf
    packageProcedure' (IterateI16W32E iv bf) ib = packageIterateProcedure EXPR_INT16 EXPR_WORD32 ib (RemBindI16 ib) iv bf
    packageProcedure' (IterateI16I8E iv bf) ib = packageIterateProcedure EXPR_INT16 EXPR_INT8 ib (RemBindI16 ib) iv bf
    packageProcedure' (IterateI16I16E iv bf) ib = packageIterateProcedure EXPR_INT16 EXPR_INT16 ib (RemBindI16 ib) iv bf
    packageProcedure' (IterateI16I32E iv bf) ib = packageIterateProcedure EXPR_INT16 EXPR_INT32 ib (RemBindI16 ib) iv bf
    packageProcedure' (IterateI16L8E iv bf) ib = packageIterateProcedure EXPR_INT16 EXPR_LIST8 ib (RemBindI16 ib) iv bf
    packageProcedure' (IterateI16FloatE iv bf) ib = packageIterateProcedure EXPR_INT16 EXPR_FLOAT ib (RemBindI16 ib) iv bf
    packageProcedure' (IterateI32UnitE iv bf) ib = packageIterateProcedure EXPR_INT32 EXPR_UNIT ib (RemBindI32 ib) iv bf
    packageProcedure' (IterateI32BoolE iv bf) ib = packageIterateProcedure EXPR_INT32 EXPR_BOOL ib (RemBindI32 ib) iv bf
    packageProcedure' (IterateI32W8E iv bf) ib = packageIterateProcedure EXPR_INT32 EXPR_WORD8 ib (RemBindI32 ib) iv bf
    packageProcedure' (IterateI32W16E iv bf) ib = packageIterateProcedure EXPR_INT32 EXPR_WORD16 ib (RemBindI32 ib) iv bf
    packageProcedure' (IterateI32W32E iv bf) ib = packageIterateProcedure EXPR_INT32 EXPR_WORD32 ib (RemBindI32 ib) iv bf
    packageProcedure' (IterateI32I8E iv bf) ib = packageIterateProcedure EXPR_INT32 EXPR_INT8 ib (RemBindI32 ib) iv bf
    packageProcedure' (IterateI32I16E iv bf) ib = packageIterateProcedure EXPR_INT32 EXPR_INT16 ib (RemBindI32 ib) iv bf
    packageProcedure' (IterateI32I32E iv bf) ib = packageIterateProcedure EXPR_INT32 EXPR_INT32 ib (RemBindI32 ib) iv bf
    packageProcedure' (IterateI32L8E iv bf) ib = packageIterateProcedure EXPR_INT32 EXPR_LIST8 ib (RemBindI32 ib) iv bf
    packageProcedure' (IterateI32FloatE iv bf) ib = packageIterateProcedure EXPR_INT32 EXPR_FLOAT ib (RemBindI32 ib) iv bf
    packageProcedure' (IterateL8UnitE iv bf) ib = packageIterateProcedure EXPR_LIST8 EXPR_UNIT ib (RemBindList8 ib) iv bf
    packageProcedure' (IterateL8BoolE iv bf) ib = packageIterateProcedure EXPR_LIST8 EXPR_BOOL ib (RemBindList8 ib) iv bf
    packageProcedure' (IterateL8W8E iv bf) ib = packageIterateProcedure EXPR_LIST8 EXPR_WORD8 ib (RemBindList8 ib) iv bf
    packageProcedure' (IterateL8W16E iv bf) ib = packageIterateProcedure EXPR_LIST8 EXPR_WORD16 ib (RemBindList8 ib) iv bf
    packageProcedure' (IterateL8W32E iv bf) ib = packageIterateProcedure EXPR_LIST8 EXPR_WORD32 ib (RemBindList8 ib) iv bf
    packageProcedure' (IterateL8I8E iv bf) ib = packageIterateProcedure EXPR_LIST8 EXPR_INT8 ib (RemBindList8 ib) iv bf
    packageProcedure' (IterateL8I16E iv bf) ib = packageIterateProcedure EXPR_LIST8 EXPR_INT16 ib (RemBindList8 ib) iv bf
    packageProcedure' (IterateL8I32E iv bf) ib = packageIterateProcedure EXPR_LIST8 EXPR_INT32 ib (RemBindList8 ib) iv bf
    packageProcedure' (IterateL8L8E iv bf) ib = packageIterateProcedure EXPR_LIST8 EXPR_LIST8 ib (RemBindList8 ib) iv bf
    packageProcedure' (IterateL8FloatE iv bf) ib = packageIterateProcedure EXPR_LIST8 EXPR_FLOAT ib (RemBindList8 ib) iv bf
    packageProcedure' (IterateFloatUnitE iv bf) ib = packageIterateProcedure EXPR_FLOAT EXPR_UNIT ib (RemBindFloat ib) iv bf
    packageProcedure' (IterateFloatBoolE iv bf) ib = packageIterateProcedure EXPR_FLOAT EXPR_BOOL ib (RemBindFloat ib) iv bf
    packageProcedure' (IterateFloatW8E iv bf) ib = packageIterateProcedure EXPR_FLOAT EXPR_WORD8 ib (RemBindFloat ib) iv bf
    packageProcedure' (IterateFloatW16E iv bf) ib = packageIterateProcedure EXPR_FLOAT EXPR_WORD16 ib (RemBindFloat ib) iv bf
    packageProcedure' (IterateFloatW32E iv bf) ib = packageIterateProcedure EXPR_FLOAT EXPR_WORD32 ib (RemBindFloat ib) iv bf
    packageProcedure' (IterateFloatI8E iv bf) ib = packageIterateProcedure EXPR_FLOAT EXPR_INT8 ib (RemBindFloat ib) iv bf
    packageProcedure' (IterateFloatI16E iv bf) ib = packageIterateProcedure EXPR_FLOAT EXPR_INT16 ib (RemBindFloat ib) iv bf
    packageProcedure' (IterateFloatI32E iv bf) ib = packageIterateProcedure EXPR_FLOAT EXPR_INT32 ib (RemBindFloat ib) iv bf
    packageProcedure' (IterateFloatL8E iv bf) ib = packageIterateProcedure EXPR_FLOAT EXPR_LIST8 ib (RemBindFloat ib) iv bf
    packageProcedure' (IterateFloatFloatE iv bf) ib = packageIterateProcedure EXPR_FLOAT EXPR_FLOAT ib (RemBindFloat ib) iv bf
    packageProcedure' DebugListen ib = return B.empty

packageReadRefProcedure :: ExprType -> Int -> Int -> State CommandState B.ByteString
packageReadRefProcedure t ib i = 
  addCommand REF_CMD_READ [toW8 t, fromIntegral ib, toW8 EXPR_WORD8, toW8 EXPR_LIT, fromIntegral i]

packageIfThenElseProcedure :: ExprType -> Int -> Expr Bool -> Arduino (Expr a) -> Arduino (Expr a) -> State CommandState B.ByteString
packageIfThenElseProcedure rt b e cb1 cb2 = do
    (r1, pc1) <- packageCodeBlock cb1
    let rc1 = buildCommand EXPR_CMD_RET $ (fromIntegral b) : packageExpr r1
    let pc1'  = B.append pc1 $ lenPackage rc1
    (r2, pc2) <- packageCodeBlock cb2
    let rc2 = buildCommand EXPR_CMD_RET $ (fromIntegral b) : packageExpr r2
    let pc2'  = B.append pc2 $ lenPackage rc2
    let thenSize = word16ToBytes $ fromIntegral (B.length pc1')
    i <- addCommand BC_CMD_IF_THEN_ELSE ([fromIntegral $ fromEnum rt, fromIntegral $ fromEnum rt, fromIntegral b] ++ thenSize ++ (packageExpr e))
    return $ B.append i (B.append pc1' pc2')

packageIfThenElseEitherProcedure :: (ExprB a, ExprB b) => ExprType -> ExprType -> Int -> Expr Bool -> Arduino (ExprEither a b) -> Arduino (ExprEither a b) -> State CommandState B.ByteString
packageIfThenElseEitherProcedure rt1 rt2 b e cb1 cb2 = do
    (r1, pc1) <- packageCodeBlock cb1
    let rc1 = buildCommand EXPR_CMD_RET $ (fromIntegral b) : packageExprEither rt1 rt2 r1
    let pc1'  = B.append pc1 $ lenPackage rc1
    (r2, pc2) <- packageCodeBlock cb2
    let rc2 = buildCommand EXPR_CMD_RET $ (fromIntegral b) : packageExprEither rt1 rt2 r2
    let pc2'  = B.append pc2 $ lenPackage rc2
    let thenSize = word16ToBytes $ fromIntegral (B.length pc1')
    i <- addCommand BC_CMD_IF_THEN_ELSE ([fromIntegral $ fromEnum rt1, fromIntegral $ fromEnum rt2, fromIntegral b] ++ thenSize ++ (packageExpr e))
    return $ B.append i (B.append pc1' pc2')

packageIterateProcedure :: ExprType -> ExprType -> Int -> Expr a -> 
                           Expr a -> (Expr a -> Arduino(ExprEither a b)) ->
                           State CommandState B.ByteString
packageIterateProcedure ta tb ib be iv bf = do
    (r, pc) <- packageCodeBlock $ bf be
    w <- addCommand BC_CMD_ITERATE ([fromIntegral $ fromEnum ta, fromIntegral $ fromEnum tb, fromIntegral ib, fromIntegral $ length ive] ++ ive)
    return $ B.append w pc
  where
    ive = packageExpr iv

packageRemoteBinding' :: ExprType -> Expr a -> State CommandState B.ByteString
packageRemoteBinding' rt e = do
    s <- get
    addCommand REF_CMD_NEW ([fromIntegral $ fromEnum rt, fromIntegral (ib s), fromIntegral (ix s)] ++ (packageExpr e))

packageRemoteBinding :: ArduinoPrimitive a -> State CommandState B.ByteString
packageRemoteBinding (NewRemoteRefB e) =  packageRemoteBinding' EXPR_BOOL e
packageRemoteBinding (NewRemoteRefW8 e) =  packageRemoteBinding' EXPR_WORD8 e
packageRemoteBinding (NewRemoteRefW16 e) =  packageRemoteBinding' EXPR_WORD16 e
packageRemoteBinding (NewRemoteRefW32 e) =  packageRemoteBinding' EXPR_WORD32 e
packageRemoteBinding (NewRemoteRefI8 e) =  packageRemoteBinding' EXPR_INT8 e
packageRemoteBinding (NewRemoteRefI16 e) =  packageRemoteBinding' EXPR_INT16 e
packageRemoteBinding (NewRemoteRefI32 e) =  packageRemoteBinding' EXPR_INT32 e
packageRemoteBinding (NewRemoteRefL8 e) =  packageRemoteBinding' EXPR_LIST8 e
packageRemoteBinding (NewRemoteRefFloat e) =  packageRemoteBinding' EXPR_FLOAT e
packageRemoteBinding _ = error "packageRemoteBinding: Unsupported primitive"

packageSubExpr :: [Word8] -> Expr a -> [Word8]
packageSubExpr ec e = ec ++ packageExpr e

packageTwoSubExpr :: [Word8] -> Expr a -> Expr b -> [Word8]
packageTwoSubExpr ec e1 e2 = ec ++ (packageExpr e1) ++ (packageExpr e2)

packageIfBSubExpr :: [Word8] -> Expr a -> Expr b -> Expr b -> [Word8]
packageIfBSubExpr ec e1 e2 e3 = ec ++ thenSize ++ elseSize ++ pcond ++ pthen ++ pelse
  where
    pcond = packageExpr e1
    pthen = packageExpr e2
    pelse = packageExpr e3
    thenSize = word16ToBytes $ fromIntegral $ length pthen
    elseSize = word16ToBytes $ fromIntegral $ length pelse

packageMathExpr :: ExprFloatOp -> Expr a -> [Word8]
packageMathExpr o e = (exprFCmdVal o) ++ (packageExpr e)

packageTwoMathExpr :: ExprFloatOp -> Expr a -> Expr b -> [Word8]
packageTwoMathExpr o e1 e2 = (exprFCmdVal o) ++ (packageExpr e1) ++ (packageExpr e2)

packageRef :: Int -> [Word8] -> [Word8]
packageRef n ec = ec ++ [fromIntegral n]

packageExprEither :: (ExprB a, ExprB b) => ExprType -> ExprType -> ExprEither a b -> [Word8]
packageExprEither t1  _t2 (ExprLeft  el) = [toW8 t1, toW8 EXPR_LEFT] ++ packageExpr el
packageExprEither _t1 _t2 (ExprRight er) = packageExpr er

packageExpr :: Expr a -> [Word8]
packageExpr (LitB b) = [toW8 EXPR_BOOL, toW8 EXPR_LIT, if b then 1 else 0]
packageExpr (ShowB e) = packageSubExpr (exprCmdVal EXPR_BOOL EXPR_SHOW) e 
packageExpr (RefB n) = packageRef n (exprCmdVal EXPR_BOOL EXPR_REF)
packageExpr (RemBindB b) = (exprCmdVal EXPR_BOOL EXPR_BIND) ++ [fromIntegral b]
packageExpr (NotB e) = packageSubExpr (exprCmdVal EXPR_BOOL EXPR_NOT) e 
packageExpr (AndB e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_BOOL EXPR_AND) e1 e2 
packageExpr (OrB e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_BOOL EXPR_OR) e1 e2 
packageExpr (EqB e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_BOOL EXPR_EQ) e1 e2 
packageExpr (LessB e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_BOOL EXPR_LESS) e1 e2 
packageExpr (IfB e1 e2 e3) = packageIfBSubExpr (exprCmdVal EXPR_BOOL EXPR_IF) e1 e2 e3
packageExpr (EqW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_EQ) e1 e2 
packageExpr (LessW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_LESS) e1 e2 
packageExpr (EqW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_EQ) e1 e2 
packageExpr (LessW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_LESS) e1 e2 
packageExpr (EqW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_EQ) e1 e2 
packageExpr (LessW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_LESS) e1 e2 
packageExpr (EqI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_EQ) e1 e2 
packageExpr (LessI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_LESS) e1 e2 
packageExpr (EqI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_EQ) e1 e2 
packageExpr (LessI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_LESS) e1 e2 
packageExpr (EqI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_EQ) e1 e2 
packageExpr (LessI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_LESS) e1 e2 
packageExpr (EqL8 e1 e2) = packageTwoSubExpr (exprLCmdVal EXPRL_EQ) e1 e2 
packageExpr (LessL8 e1 e2) = packageTwoSubExpr (exprLCmdVal EXPRL_LESS) e1 e2 
packageExpr (EqFloat e1 e2) = packageTwoSubExpr (exprFCmdVal EXPRF_EQ) e1 e2 
packageExpr (LessFloat e1 e2) = packageTwoSubExpr (exprFCmdVal EXPRF_LESS) e1 e2 
packageExpr (LitW8 w) = (exprCmdVal EXPR_WORD8 EXPR_LIT) ++ [w]
packageExpr (ShowW8 e) = packageSubExpr (exprCmdVal EXPR_WORD8 EXPR_SHOW) e
packageExpr (RefW8 n) = packageRef n (exprCmdVal EXPR_WORD8 EXPR_REF)
packageExpr (RemBindW8 b) = (exprCmdVal EXPR_WORD8 EXPR_BIND) ++ [fromIntegral b]
packageExpr (FromIntW8 e) = packageSubExpr (exprCmdVal EXPR_WORD8 EXPR_FINT) e
packageExpr (ToIntW8 e) = packageSubExpr (exprCmdVal EXPR_WORD8 EXPR_TINT) e
packageExpr (NegW8 e) = packageSubExpr (exprCmdVal EXPR_WORD8 EXPR_NEG) e
packageExpr (SignW8 e) = packageSubExpr (exprCmdVal EXPR_WORD8 EXPR_SIGN) e
packageExpr (AddW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_ADD) e1 e2 
packageExpr (SubW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_SUB) e1 e2 
packageExpr (MultW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_MULT) e1 e2 
packageExpr (DivW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_DIV) e1 e2 
packageExpr (RemW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_REM) e1 e2 
packageExpr (QuotW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_QUOT) e1 e2 
packageExpr (ModW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_MOD) e1 e2 
packageExpr (AndW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_AND) e1 e2 
packageExpr (OrW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_OR) e1 e2 
packageExpr (XorW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_XOR) e1 e2 
packageExpr (CompW8 e) = packageSubExpr (exprCmdVal EXPR_WORD8 EXPR_COMP) e 
packageExpr (ShfLW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_SHFL) e1 e2 
packageExpr (ShfRW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_SHFR) e1 e2 
packageExpr (IfW8 e1 e2 e3) = packageIfBSubExpr (exprCmdVal EXPR_WORD8 EXPR_IF) e1 e2 e3
packageExpr (TestBW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_TSTB) e1 e2 
packageExpr (SetBW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_SETB) e1 e2 
packageExpr (ClrBW8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD8 EXPR_CLRB) e1 e2 
packageExpr (LitW16 w) = (exprCmdVal EXPR_WORD16 EXPR_LIT) ++ word16ToBytes w
packageExpr (ShowW16 e) = packageSubExpr (exprCmdVal EXPR_WORD16 EXPR_SHOW) e
packageExpr (RefW16 n) = packageRef n (exprCmdVal EXPR_WORD16 EXPR_REF)
packageExpr (RemBindW16 b) = (exprCmdVal EXPR_WORD16 EXPR_BIND) ++ [fromIntegral b]
packageExpr (FromIntW16 e) = packageSubExpr (exprCmdVal EXPR_WORD16 EXPR_FINT) e
packageExpr (ToIntW16 e) = packageSubExpr (exprCmdVal EXPR_WORD16 EXPR_TINT) e
packageExpr (NegW16 e) = packageSubExpr (exprCmdVal EXPR_WORD16 EXPR_NEG) e
packageExpr (SignW16 e) = packageSubExpr (exprCmdVal EXPR_WORD16 EXPR_SIGN) e
packageExpr (AddW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_ADD) e1 e2 
packageExpr (SubW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_SUB) e1 e2 
packageExpr (MultW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_MULT) e1 e2 
packageExpr (DivW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_DIV) e1 e2 
packageExpr (RemW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_REM) e1 e2 
packageExpr (QuotW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_QUOT) e1 e2 
packageExpr (ModW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_MOD) e1 e2 
packageExpr (AndW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_AND) e1 e2 
packageExpr (OrW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_OR) e1 e2 
packageExpr (XorW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_XOR) e1 e2 
packageExpr (CompW16 e) = packageSubExpr (exprCmdVal EXPR_WORD16 EXPR_COMP) e 
packageExpr (ShfLW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_SHFL) e1 e2 
packageExpr (ShfRW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_SHFR) e1 e2 
packageExpr (IfW16 e1 e2 e3) = packageIfBSubExpr (exprCmdVal EXPR_WORD16 EXPR_IF) e1 e2 e3
packageExpr (TestBW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_TSTB) e1 e2 
packageExpr (SetBW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_SETB) e1 e2 
packageExpr (ClrBW16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD16 EXPR_CLRB) e1 e2 
packageExpr (LitW32 w) = (exprCmdVal EXPR_WORD32 EXPR_LIT) ++ word32ToBytes w
packageExpr (ShowW32 e) = packageSubExpr (exprCmdVal EXPR_WORD32 EXPR_SHOW) e
packageExpr (RefW32 n) = packageRef n (exprCmdVal EXPR_WORD32 EXPR_REF)
packageExpr (RemBindW32 b) = (exprCmdVal EXPR_WORD32 EXPR_BIND) ++ [fromIntegral b]
packageExpr (FromIntW32 e) = packageSubExpr (exprCmdVal EXPR_WORD32 EXPR_FINT) e
packageExpr (ToIntW32 e) = packageSubExpr (exprCmdVal EXPR_WORD32 EXPR_TINT) e
packageExpr (NegW32 e) = packageSubExpr (exprCmdVal EXPR_WORD32 EXPR_NEG) e
packageExpr (SignW32 e) = packageSubExpr (exprCmdVal EXPR_WORD32 EXPR_SIGN) e
packageExpr (AddW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_ADD) e1 e2 
packageExpr (SubW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_SUB) e1 e2 
packageExpr (MultW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_MULT) e1 e2 
packageExpr (DivW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_DIV) e1 e2 
packageExpr (RemW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_REM) e1 e2 
packageExpr (QuotW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_QUOT) e1 e2 
packageExpr (ModW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_MOD) e1 e2 
packageExpr (AndW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_AND) e1 e2 
packageExpr (OrW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_OR) e1 e2 
packageExpr (XorW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_XOR) e1 e2 
packageExpr (CompW32 e) = packageSubExpr (exprCmdVal EXPR_WORD32 EXPR_COMP) e
packageExpr (ShfLW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_SHFL) e1 e2 
packageExpr (ShfRW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_SHFR) e1 e2 
packageExpr (IfW32 e1 e2 e3) = packageIfBSubExpr (exprCmdVal EXPR_WORD32 EXPR_IF) e1 e2 e3
packageExpr (TestBW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_TSTB) e1 e2 
packageExpr (SetBW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_SETB) e1 e2 
packageExpr (ClrBW32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_WORD32 EXPR_CLRB) e1 e2 
packageExpr (LitI8 w) = (exprCmdVal EXPR_INT8 EXPR_LIT) ++ [fromIntegral w]
packageExpr (ShowI8 e) = packageSubExpr (exprCmdVal EXPR_INT8 EXPR_SHOW) e
packageExpr (RefI8 n) = packageRef n (exprCmdVal EXPR_INT8 EXPR_REF)
packageExpr (RemBindI8 b) = (exprCmdVal EXPR_INT8 EXPR_BIND) ++ [fromIntegral b]
packageExpr (FromIntI8 e) = packageSubExpr (exprCmdVal EXPR_INT8 EXPR_FINT) e
packageExpr (ToIntI8 e) = packageSubExpr (exprCmdVal EXPR_INT8 EXPR_TINT) e
packageExpr (NegI8 e) = packageSubExpr (exprCmdVal EXPR_INT8 EXPR_NEG) e
packageExpr (SignI8 e) = packageSubExpr (exprCmdVal EXPR_INT8 EXPR_SIGN) e
packageExpr (AddI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_ADD) e1 e2 
packageExpr (SubI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_SUB) e1 e2 
packageExpr (MultI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_MULT) e1 e2 
packageExpr (DivI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_DIV) e1 e2 
packageExpr (RemI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_REM) e1 e2 
packageExpr (QuotI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_QUOT) e1 e2 
packageExpr (ModI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_MOD) e1 e2 
packageExpr (AndI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_AND) e1 e2 
packageExpr (OrI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_OR) e1 e2 
packageExpr (XorI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_XOR) e1 e2 
packageExpr (CompI8 e) = packageSubExpr (exprCmdVal EXPR_INT8 EXPR_COMP) e 
packageExpr (ShfLI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_SHFL) e1 e2 
packageExpr (ShfRI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_SHFR) e1 e2 
packageExpr (IfI8 e1 e2 e3) = packageIfBSubExpr (exprCmdVal EXPR_INT8 EXPR_IF) e1 e2 e3
packageExpr (TestBI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_TSTB) e1 e2 
packageExpr (SetBI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_SETB) e1 e2 
packageExpr (ClrBI8 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT8 EXPR_CLRB) e1 e2 
packageExpr (LitI16 w) = (exprCmdVal EXPR_INT16 EXPR_LIT) ++ word16ToBytes (fromIntegral w)
packageExpr (ShowI16 e) = packageSubExpr (exprCmdVal EXPR_INT16 EXPR_SHOW) e
packageExpr (RefI16 n) = packageRef n (exprCmdVal EXPR_INT16 EXPR_REF)
packageExpr (RemBindI16 b) = (exprCmdVal EXPR_INT16 EXPR_BIND) ++ [fromIntegral b]
packageExpr (FromIntI16 e) = packageSubExpr (exprCmdVal EXPR_INT16 EXPR_FINT) e
packageExpr (ToIntI16 e) = packageSubExpr (exprCmdVal EXPR_INT16 EXPR_TINT) e
packageExpr (NegI16 e) = packageSubExpr (exprCmdVal EXPR_INT16 EXPR_NEG) e
packageExpr (SignI16 e) = packageSubExpr (exprCmdVal EXPR_INT16 EXPR_SIGN) e
packageExpr (AddI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_ADD) e1 e2 
packageExpr (SubI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_SUB) e1 e2 
packageExpr (MultI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_MULT) e1 e2 
packageExpr (DivI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_DIV) e1 e2 
packageExpr (RemI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_REM) e1 e2 
packageExpr (QuotI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_QUOT) e1 e2 
packageExpr (ModI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_MOD) e1 e2 
packageExpr (AndI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_AND) e1 e2 
packageExpr (OrI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_OR) e1 e2 
packageExpr (XorI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_XOR) e1 e2 
packageExpr (CompI16 e) = packageSubExpr (exprCmdVal EXPR_INT16 EXPR_COMP) e 
packageExpr (ShfLI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_SHFL) e1 e2 
packageExpr (ShfRI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_SHFR) e1 e2 
packageExpr (IfI16 e1 e2 e3) = packageIfBSubExpr (exprCmdVal EXPR_INT16 EXPR_IF) e1 e2 e3
packageExpr (TestBI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_TSTB) e1 e2 
packageExpr (SetBI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_SETB) e1 e2 
packageExpr (ClrBI16 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT16 EXPR_CLRB) e1 e2 
packageExpr (LitI32 w) = (exprCmdVal EXPR_INT32 EXPR_LIT) ++ word32ToBytes (fromIntegral w)
packageExpr (ShowI32 e) = packageSubExpr (exprCmdVal EXPR_INT32 EXPR_SHOW) e
packageExpr (RefI32 n) = packageRef n (exprCmdVal EXPR_INT32 EXPR_REF)
packageExpr (RemBindI32 b) = (exprCmdVal EXPR_INT32 EXPR_BIND) ++ [fromIntegral b]
packageExpr (NegI32 e) = packageSubExpr (exprCmdVal EXPR_INT32 EXPR_NEG) e
packageExpr (SignI32 e) = packageSubExpr (exprCmdVal EXPR_INT32 EXPR_SIGN) e
packageExpr (AddI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_ADD) e1 e2 
packageExpr (SubI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_SUB) e1 e2 
packageExpr (MultI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_MULT) e1 e2 
packageExpr (DivI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_DIV) e1 e2 
packageExpr (RemI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_REM) e1 e2 
packageExpr (QuotI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_QUOT) e1 e2 
packageExpr (ModI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_MOD) e1 e2 
packageExpr (AndI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_AND) e1 e2 
packageExpr (OrI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_OR) e1 e2 
packageExpr (XorI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_XOR) e1 e2 
packageExpr (CompI32 e) = packageSubExpr (exprCmdVal EXPR_INT32 EXPR_COMP) e
packageExpr (ShfLI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_SHFL) e1 e2 
packageExpr (ShfRI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_SHFR) e1 e2 
packageExpr (IfI32 e1 e2 e3) = packageIfBSubExpr (exprCmdVal EXPR_INT32 EXPR_IF) e1 e2 e3
packageExpr (TestBI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_TSTB) e1 e2 
packageExpr (SetBI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_SETB) e1 e2 
packageExpr (ClrBI32 e1 e2) = packageTwoSubExpr (exprCmdVal EXPR_INT32 EXPR_CLRB) e1 e2 
packageExpr (LitList8 ws) = (exprLCmdVal EXPRL_LIT) ++ [fromIntegral $ length ws] ++ ws
packageExpr (RefList8 n) = packageRef n (exprLCmdVal EXPRL_REF)
packageExpr (RemBindList8 b) = (exprLCmdVal EXPRL_BIND) ++ [fromIntegral b]
packageExpr (IfL8 e1 e2 e3) = packageIfBSubExpr (exprLCmdVal EXPRL_IF) e1 e2 e3
packageExpr (ElemList8 e1 e2) = packageTwoSubExpr (exprLCmdVal EXPRL_ELEM) e1 e2 
packageExpr (LenList8 e) = packageSubExpr (exprLCmdVal EXPRL_LEN) e
packageExpr (ConsList8 e1 e2) = packageTwoSubExpr (exprLCmdVal EXPRL_CONS) e1 e2 
packageExpr (ApndList8 e1 e2) = packageTwoSubExpr (exprLCmdVal EXPRL_APND) e1 e2
packageExpr (PackList8 es) = (exprLCmdVal EXPRL_PACK) ++ [fromIntegral $ length es] ++ (foldl (++) [] (map packageExpr es))
packageExpr (LitFloat f) = (exprFCmdVal EXPRF_LIT) ++ floatToBytes f
packageExpr (ShowFloat e1 e2) = packageTwoSubExpr (exprFCmdVal EXPRF_SHOW) e1 e2
packageExpr (RefFloat n) = packageRef n (exprFCmdVal EXPRF_REF)
packageExpr (RemBindFloat b) = (exprFCmdVal EXPRF_BIND) ++ [fromIntegral b]
packageExpr (FromIntFloat e) = packageSubExpr (exprFCmdVal EXPRF_FINT) e
packageExpr (NegFloat e) = packageSubExpr (exprFCmdVal EXPRF_NEG) e
packageExpr (SignFloat e) = packageSubExpr (exprFCmdVal EXPRF_SIGN) e
packageExpr (AddFloat e1 e2) = packageTwoSubExpr (exprFCmdVal EXPRF_ADD) e1 e2 
packageExpr (SubFloat e1 e2) = packageTwoSubExpr (exprFCmdVal EXPRF_SUB) e1 e2 
packageExpr (MultFloat e1 e2) = packageTwoSubExpr (exprFCmdVal EXPRF_MULT) e1 e2 
packageExpr (DivFloat e1 e2) = packageTwoSubExpr (exprFCmdVal EXPRF_DIV) e1 e2 
packageExpr (IfFloat e1 e2 e3) = packageIfBSubExpr (exprFCmdVal EXPRF_IF) e1 e2 e3
packageExpr (TruncFloat e) = packageMathExpr EXPRF_TRUNC e 
packageExpr (FracFloat e) = packageMathExpr EXPRF_FRAC e 
packageExpr (RoundFloat e) = packageMathExpr EXPRF_ROUND e 
packageExpr (CeilFloat e) = packageMathExpr EXPRF_CEIL e 
packageExpr (FloorFloat e) = packageMathExpr EXPRF_FLOOR e 
packageExpr PiFloat = exprFCmdVal EXPRF_PI
packageExpr (ExpFloat e) = packageMathExpr EXPRF_EXP e 
packageExpr (LogFloat e) = packageMathExpr EXPRF_LOG e 
packageExpr (SqrtFloat e) = packageMathExpr EXPRF_SQRT e 
packageExpr (SinFloat e) = packageMathExpr EXPRF_SIN e 
packageExpr (CosFloat e) = packageMathExpr EXPRF_COS e 
packageExpr (TanFloat e) = packageMathExpr EXPRF_TAN e 
packageExpr (AsinFloat e) = packageMathExpr EXPRF_ASIN e 
packageExpr (AcosFloat e) = packageMathExpr EXPRF_ACOS e 
packageExpr (AtanFloat e) = packageMathExpr EXPRF_ATAN e 
packageExpr (Atan2Float e1 e2) = packageTwoMathExpr EXPRF_ATAN2 e1 e2 
packageExpr (SinhFloat e) = packageMathExpr EXPRF_SINH e 
packageExpr (CoshFloat e) = packageMathExpr EXPRF_COSH e 
packageExpr (TanhFloat e) = packageMathExpr EXPRF_TANH e 
packageExpr (PowerFloat e1 e2) = packageTwoMathExpr EXPRF_POWER e1 e2 
packageExpr (IsNaNFloat e) = packageMathExpr EXPRF_ISNAN e 
packageExpr (IsInfFloat e) = packageMathExpr EXPRF_ISINF e 

-- | Unpackage a Haskino Firmware response
unpackageResponse :: [Word8] -> Response
unpackageResponse [] = Unimplemented (Just "<EMPTY-REPLY>") []
unpackageResponse (cmdWord:args)
  | Right cmd <- getFirmwareReply cmdWord
  = case (cmd, args) of
      (BC_RESP_DELAY, [])               -> DelayResp
      (BC_RESP_IF_THEN_ELSE , [t,l,b]) | t == toW8 EXPR_BOOL && l == toW8 EXPR_LIT
                                      -> IfThenElseBReply (if b == 0 then False else True)
      (BC_RESP_IF_THEN_ELSE , [t,l,b]) | t == toW8 EXPR_WORD8 && l == toW8 EXPR_LIT
                                      -> IfThenElseW8Reply b
      (BC_RESP_IF_THEN_ELSE , [t,l,b1,b2]) | t == toW8 EXPR_WORD16 && l == toW8 EXPR_LIT
                                      -> IfThenElseW16Reply (bytesToWord16 (b1, b2))
      (BC_RESP_IF_THEN_ELSE , [t,l,b1,b2,b3,b4]) | t == toW8 EXPR_WORD32 && l == toW8 EXPR_LIT
                                      -> IfThenElseW32Reply (bytesToWord32 (b1, b2, b3, b4))
      (BC_RESP_IF_THEN_ELSE , [t,l,b]) | t == toW8 EXPR_INT8 && l == toW8 EXPR_LIT
                                      -> IfThenElseI8Reply $ fromIntegral b
      (BC_RESP_IF_THEN_ELSE , [t,l,b1,b2]) | t == toW8 EXPR_INT16 && l == toW8 EXPR_LIT
                                      -> IfThenElseI16Reply $ fromIntegral (bytesToWord16 (b1, b2))
      (BC_RESP_IF_THEN_ELSE , [t,l,b1,b2,b3,b4]) | t == toW8 EXPR_INT32 && l == toW8 EXPR_LIT
                                      -> IfThenElseI32Reply $ fromIntegral (bytesToWord32 (b1, b2, b3, b4))
      (BC_RESP_IF_THEN_ELSE , t:l:_:bs) | t == toW8 EXPR_LIST8 && l == toW8 EXPR_LIT
                                      -> IfThenElseL8Reply bs
      (BC_RESP_IF_THEN_ELSE , [t,l,b1,b2,b3,b4]) | t == toW8 EXPR_FLOAT && l == toW8 EXPR_LIT
                                      -> IfThenElseFloatReply $ bytesToFloat (b1, b2, b3, b4)
      (BC_RESP_IF_THEN_ELSE , [t,l,b]) | t == (toW8 EXPR_BOOL  + 0x80) && l == toW8 EXPR_LIT
                                      -> IfThenElseBLeftReply (if b == 0 then False else True)
      (BC_RESP_IF_THEN_ELSE , [t,l,b]) | t == (toW8 EXPR_WORD8 + 0x80) && l == toW8 EXPR_LIT
                                      -> IfThenElseW8LeftReply b
      (BC_RESP_ITERATE , [t,l,b]) | t == toW8 EXPR_BOOL && l == toW8 EXPR_LIT
                                      -> IterateBReply (if b == 0 then False else True)
      (BC_RESP_ITERATE , [t,l,b]) | t == toW8 EXPR_WORD8 && l == toW8 EXPR_LIT
                                      -> IterateW8Reply b
      (BS_RESP_DEBUG, [])                    -> DebugResp
      (BS_RESP_VERSION, [majV, minV])        -> Firmware (bytesToWord16 (majV,minV))
      (BS_RESP_TYPE, [p])                    -> ProcessorType p
      (BS_RESP_MICROS, [m0,m1,m2,m3])        -> MicrosReply (bytesToWord32 (m0,m1,m2,m3))
      (BS_RESP_MILLIS, [m0,m1,m2,m3])        -> MillisReply (bytesToWord32 (m0,m1,m2,m3))
      (BS_RESP_STRING, rest)                 -> StringMessage (getString rest)
      (DIG_RESP_READ_PIN, [_t,_l,b])         -> DigitalReply b
      (DIG_RESP_READ_PORT, [_t,_l,b])        -> DigitalPortReply b
      (ALG_RESP_READ_PIN, [_t,_l,bl,bh])     -> AnalogReply (bytesToWord16 (bl,bh))
      (I2C_RESP_READ, _:_:_:xs)              -> I2CReply xs
      (STEP_RESP_2PIN, [_t,_l,st])           -> Stepper2PinReply st
      (STEP_RESP_4PIN, [_t,_l,st])           -> Stepper4PinReply st
      (STEP_RESP_STEP, [])                   -> StepperStepReply
      (SRVO_RESP_ATTACH, [_t,_l,sv])         -> ServoAttachReply sv
      (SRVO_RESP_READ, [_t,_l,il,ih])        -> ServoReadReply (fromIntegral (bytesToWord16 (il,ih)))
      (SRVO_RESP_READ_MICROS, [_t,_l,il,ih]) -> ServoReadMicrosReply (fromIntegral (bytesToWord16 (il,ih)))
      (SCHED_RESP_BOOT, [_t,_l,b])           -> BootTaskResp b
      (SCHED_RESP_QUERY_ALL, _:_:_:ts)       -> QueryAllTasksReply ts
      (SCHED_RESP_QUERY, ts) | length ts == 0 -> 
          QueryTaskReply Nothing
      (SCHED_RESP_QUERY, ts) | length ts >= 9 -> 
          let ts0:ts1:tl0:tl1:tp0:tp1:tt0:tt1:tt2:tt3:rest = ts
          in QueryTaskReply (Just (bytesToWord16 (ts0,ts1), 
                                   bytesToWord16 (tl0,tl1),
                                   bytesToWord16 (tp0,tp1), 
                                   bytesToWord32 (tt0,tt1,tt2,tt3)))  
      (REF_RESP_READ , [t,l,b]) | t == toW8 EXPR_BOOL && l == toW8 EXPR_LIT
                                      -> ReadRefBReply (if b == 0 then False else True)
      (REF_RESP_READ , [t,l,b]) | t == toW8 EXPR_WORD8 && l == toW8 EXPR_LIT
                                      -> ReadRefW8Reply b
      (REF_RESP_READ , [t,l,b1,b2]) | t == toW8 EXPR_WORD16 && l == toW8 EXPR_LIT
                                      -> ReadRefW16Reply (bytesToWord16 (b1, b2))
      (REF_RESP_READ , [t,l,b1,b2,b3,b4]) | t == toW8 EXPR_WORD32 && l == toW8 EXPR_LIT
                                      -> ReadRefW32Reply (bytesToWord32 (b1, b2, b3, b4))
      (REF_RESP_READ , [t,l,b]) | t == toW8 EXPR_INT8 && l == toW8 EXPR_LIT
                                      -> ReadRefI8Reply $ fromIntegral b
      (REF_RESP_READ , [t,l,b1,b2]) | t == toW8 EXPR_INT16 && l == toW8 EXPR_LIT
                                      -> ReadRefI16Reply $ fromIntegral (bytesToWord16 (b1, b2))
      (REF_RESP_READ , [t,l,b1,b2,b3,b4]) | t == toW8 EXPR_INT32 && l == toW8 EXPR_LIT
                                      -> ReadRefI32Reply $ fromIntegral (bytesToWord32 (b1, b2, b3, b4))
      (REF_RESP_READ , t:l:_:bs) | t == toW8 EXPR_LIST8 && l == toW8 EXPR_LIT
                                      -> ReadRefL8Reply bs
      (REF_RESP_READ , [t,l,b1,b2,b3,b4]) | t == toW8 EXPR_FLOAT && l == toW8 EXPR_LIT
                                      -> ReadRefFloatReply $ bytesToFloat (b1, b2, b3, b4)
      (REF_RESP_NEW , [_t,_l,w])      -> NewReply w
      (REF_RESP_NEW , [])             -> FailedNewRef
      _                               -> Unimplemented (Just (show cmd)) args
  | True
  = Unimplemented Nothing (cmdWord : args)

-- This is how we match responses with queries
parseQueryResult :: ArduinoPrimitive a -> Response -> Maybe a
parseQueryResult QueryFirmware (Firmware v) = Just v
parseQueryResult QueryFirmwareE (Firmware v) = Just (lit v)
parseQueryResult QueryProcessor (ProcessorType pt) = Just $ toEnum $ fromIntegral pt
parseQueryResult QueryProcessorE (ProcessorType pt) = Just $ (lit pt)
parseQueryResult Micros (MicrosReply m) = Just m
parseQueryResult MicrosE (MicrosReply m) = Just (lit m)
parseQueryResult Millis (MillisReply m) = Just m
parseQueryResult MillisE (MillisReply m) = Just (lit m)
parseQueryResult (DelayMicros _) DelayResp = Just ()
parseQueryResult (DelayMicrosE _) DelayResp = Just ()
parseQueryResult (DelayMillis _) DelayResp = Just ()
parseQueryResult (DelayMillisE _) DelayResp = Just ()
parseQueryResult (DebugE _) DebugResp = Just ()
parseQueryResult (DigitalRead _) (DigitalReply d) = Just (if d == 0 then False else True)
parseQueryResult (DigitalReadE _) (DigitalReply d) = Just (if d == 0 then lit False else lit True)
parseQueryResult (DigitalPortRead _ _) (DigitalPortReply d) = Just d
parseQueryResult (DigitalPortReadE _ _) (DigitalPortReply d) = Just (lit d)
parseQueryResult (AnalogRead _) (AnalogReply a) = Just a
parseQueryResult (AnalogReadE _) (AnalogReply a) = Just (lit a)
parseQueryResult (I2CRead _ _) (I2CReply ds) = Just ds
parseQueryResult (I2CReadE _ _) (I2CReply ds) = Just (lit ds)
parseQueryResult (Stepper2Pin _ _ _) (Stepper2PinReply st) = Just st
parseQueryResult (Stepper2PinE _ _ _) (Stepper2PinReply st) = Just (lit st)
parseQueryResult (Stepper4Pin _ _ _ _ _) (Stepper4PinReply st) = Just st
parseQueryResult (Stepper4PinE _ _ _ _ _) (Stepper4PinReply st) = Just (lit st)
parseQueryResult (StepperStepE _ _) StepperStepReply = Just ()
parseQueryResult QueryAllTasks (QueryAllTasksReply ts) = Just ts
parseQueryResult QueryAllTasksE (QueryAllTasksReply ts) = Just (lit ts)
parseQueryResult (QueryTask _) (QueryTaskReply tr) = Just tr
parseQueryResult (QueryTaskE _) (QueryTaskReply tr) = Just tr
parseQueryResult (BootTaskE _) (BootTaskResp b) = Just (if b == 0 then lit False else lit True)
parseQueryResult (NewRemoteRefB _) (NewReply r) = Just $ RemoteRefB $ fromIntegral r
parseQueryResult (NewRemoteRefW8 _) (NewReply r) = Just $ RemoteRefW8 $ fromIntegral r
parseQueryResult (NewRemoteRefW16 _) (NewReply r) = Just $ RemoteRefW16 $ fromIntegral r
parseQueryResult (NewRemoteRefW32 _) (NewReply r) = Just $ RemoteRefW32 $ fromIntegral r
parseQueryResult (NewRemoteRefI8 _) (NewReply r) = Just $ RemoteRefI8 $ fromIntegral r
parseQueryResult (NewRemoteRefI16 _) (NewReply r) = Just $ RemoteRefI16 $ fromIntegral r
parseQueryResult (NewRemoteRefI32 _) (NewReply r) = Just $ RemoteRefI32 $ fromIntegral r
parseQueryResult (NewRemoteRefL8 _) (NewReply r) = Just $ RemoteRefL8 $ fromIntegral r
parseQueryResult (NewRemoteRefFloat _) (NewReply r) = Just $ RemoteRefFloat$ fromIntegral r
parseQueryResult (ReadRemoteRefB _) (ReadRefBReply r) = Just $ lit r
parseQueryResult (ReadRemoteRefW8 _) (ReadRefW8Reply r) = Just $ lit r
parseQueryResult (ReadRemoteRefW16 _) (ReadRefW16Reply r) = Just $ lit r
parseQueryResult (ReadRemoteRefW32 _) (ReadRefW32Reply r) = Just $ lit r
parseQueryResult (ReadRemoteRefI8 _) (ReadRefI8Reply r) = Just $ lit r
parseQueryResult (ReadRemoteRefI16 _) (ReadRefI16Reply r) = Just $ lit r
parseQueryResult (ReadRemoteRefI32 _) (ReadRefI32Reply r) = Just $ lit r
parseQueryResult (ReadRemoteRefL8 _) (ReadRefL8Reply r) = Just $ lit r
parseQueryResult (ReadRemoteRefFloat _) (ReadRefFloatReply r) = Just $ lit r
parseQueryResult (IfThenElseBoolE _ _ _) (IfThenElseBReply r) = Just $ lit r
parseQueryResult (IfThenElseWord8E _ _ _) (IfThenElseW8Reply r) = Just $ lit r
parseQueryResult (IfThenElseWord16E _ _ _) (IfThenElseW16Reply r) = Just $ lit r
parseQueryResult (IfThenElseWord32E _ _ _) (IfThenElseW32Reply r) = Just $ lit r
parseQueryResult (IfThenElseInt8E _ _ _) (IfThenElseI8Reply r) = Just $ lit r
parseQueryResult (IfThenElseInt16E _ _ _) (IfThenElseI16Reply r) = Just $ lit r
parseQueryResult (IfThenElseInt32E _ _ _) (IfThenElseI32Reply r) = Just $ lit r
parseQueryResult (IfThenElseL8E _ _ _) (IfThenElseL8Reply r) = Just $ lit r
parseQueryResult (IfThenElseFloatE _ _ _) (IfThenElseFloatReply r) = Just $ lit r
parseQueryResult (IfThenElseW8Bool _ _ _) (IfThenElseBReply r) = Just $ ExprRight $ lit r
parseQueryResult (IfThenElseW8Bool _ _ _) (IfThenElseW8LeftReply r) = Just $ ExprLeft $ lit r
parseQueryResult (IfThenElseW8W8 _ _ _) (IfThenElseW8Reply r) = Just $ ExprRight $ lit r
parseQueryResult (IfThenElseW8W8 _ _ _) (IfThenElseW8LeftReply r) = Just $ ExprLeft $ lit r
parseQueryResult (IterateW8UnitE _ _) (IterateUReply) = Just $ LitUnit
parseQueryResult (IterateW8BoolE _ _) (IterateBReply r) = Just $ lit r
parseQueryResult (IterateW8W8E _ _) (IterateW8Reply r) = Just $ lit r
parseQueryResult (IterateW8W16E _ _) (IterateW16Reply r) = Just $ lit r
parseQueryResult (IterateW8W32E _ _) (IterateW32Reply r) = Just $ lit r
parseQueryResult (IterateW8I8E _ _) (IterateI8Reply r) = Just $ lit r
parseQueryResult (IterateW8I16E _ _) (IterateI16Reply r) = Just $ lit r
parseQueryResult (IterateW8I32E _ _) (IterateI32Reply r) = Just $ lit r
parseQueryResult (IterateW8L8E _ _) (IterateL8Reply r) = Just $ lit r
parseQueryResult (IterateW8FloatE _ _) (IterateFloatReply r) = Just $ lit r
parseQueryResult _q _r = Nothing
