-------------------------------------------------------------------------------
-- |
-- Module      :  System.Hardware.Haskino.Utils
--                Based on System.Hardware.Arduino.Utils
-- Copyright   :  (c) University of Kansas
--                System.Hardware.Arduino (c) Levent Erkok
-- License     :  BSD3
-- Stability   :  experimental
--
-- Internal utilities
-------------------------------------------------------------------------------
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ViewPatterns #-}

module System.Hardware.Haskino.Decode where

import           Data.Bits
import qualified Data.ByteString                  as B
import           Data.ByteString.Base16           (encode)
import           Data.Int
import           Data.Word
import           System.Hardware.Haskino.Data
import           System.Hardware.Haskino.Expr
import           System.Hardware.Haskino.Protocol
import           System.Hardware.Haskino.Utils

infixr 5 :<

pattern (:<) :: Word8 -> B.ByteString -> B.ByteString
pattern b :< bs <- (B.uncons -> Just (b, bs))

pattern Empty :: B.ByteString
pattern Empty   <- (B.uncons -> Nothing)

decodeFrame :: B.ByteString -> String
decodeFrame bs = decodeCmds $ condenseAddToTasks $ deframe bs

deframe :: B.ByteString -> [B.ByteString]
deframe bs = map unescape (deframe' bs [])
  where
    notFrameChar :: Word8 -> Bool
    notFrameChar b = b /= 0x7e

    deframe' :: B.ByteString -> [B.ByteString] -> [B.ByteString]
    deframe' Empty xs = xs
    deframe' bs'   xs = deframe' (tailFrame bs') (xs ++ [headFrame bs'])

    headFrame :: B.ByteString -> B.ByteString
    headFrame bs' = B.init $ B.takeWhile notFrameChar bs'

    tailFrame :: B.ByteString -> B.ByteString
    tailFrame bs' = B.tail $ B.dropWhile notFrameChar bs'

    unescape :: B.ByteString -> B.ByteString
    unescape Empty        = B.empty
    unescape (x :< Empty) = B.singleton x
    unescape (x :< y :< xs)
      | x == 0x7d && y == 0x5d =  B.cons 0x7d (unescape xs)
      | x == 0x7d && y == 0x5e =  B.cons 0x7e (unescape xs)
      | otherwise              =  B.cons x (unescape (B.cons y xs))
    unescape _            = B.empty

decodeCmds :: [B.ByteString] -> String
decodeCmds cs = concat $ map decodeCmd cs

condenseAddToTasks :: [B.ByteString] -> [B.ByteString]
condenseAddToTasks cs = scanForAdd cs Nothing B.empty
  where
    scanForAdd :: [B.ByteString] -> Maybe Word8 -> B.ByteString -> [B.ByteString]
    scanForAdd bss tid bs =
      case tid of
        Nothing -> case bss of
                     []       -> []
                     (x : xs) -> case (getCmd x) of
                                   SCHED_CMD_ADD_TO_TASK -> if (B.length x < 5)
                                                            then scanForAdd xs Nothing B.empty
                                                            else scanForAdd xs (Just (B.head (B.drop 2 x))) (B.drop 5 x)
                                   _                     -> x : scanForAdd xs Nothing B.empty
        Just t  -> case bss of
                     []       -> [buildCondensed t bs]
                     (x : xs) -> case (getCmd x) of
                                   SCHED_CMD_ADD_TO_TASK -> if (B.length x < 5)
                                                            then scanForAdd xs tid bs
                                                            else scanForAdd xs tid (B.append bs (B.drop 5 x))
                                   _                     -> (buildCondensed t bs) : scanForAdd xs Nothing B.empty

    buildCondensed :: Word8 -> B.ByteString -> B.ByteString
    buildCondensed t bs = B.cons (firmwareCmdVal SCHED_CMD_ADD_TO_TASK)
                            (B.pack ((packageExpr (LitW8 $ fromIntegral t)) ++
                                     (packageExpr (LitW16 (fromIntegral (B.length bs)))) ++
                                     (B.unpack bs)))

    getCmd :: B.ByteString -> FirmwareCmd
    getCmd Empty = UNKNOWN_COMMAND
    getCmd bs = firmwareValCmd $ B.head bs

decodeCmd :: B.ByteString -> String
decodeCmd Empty        = "Empty Command"
decodeCmd (x :< Empty) = show (firmwareValCmd x)
decodeCmd (x :< xs)    = show cmd ++ decoded ++ "\n"
  where
    cmd = firmwareValCmd x
    (dec, bs) = decodeCmdArgs cmd x xs
    decoded = case bs of
                Empty -> dec
                _     -> dec ++ show (encode bs)
decodeCmd _            = "decodeCmd - Decode Error"

decodeCmdArgs :: FirmwareCmd -> Word8 -> B.ByteString -> (String, B.ByteString)
decodeCmdArgs BC_CMD_SYSTEM_RESET _ xs = ("", xs)
decodeCmdArgs BC_CMD_SET_PIN_MODE _ xs = decodeExprCmd 1 xs
decodeCmdArgs BC_CMD_DELAY_MILLIS _ xs = decodeExprProc 1 xs
decodeCmdArgs BC_CMD_DELAY_MICROS _ xs = decodeExprProc 1 xs
decodeCmdArgs BC_CMD_ITERATE _ Empty = decodeErr B.empty
decodeCmdArgs BC_CMD_ITERATE _ xs | B.length xs < 5 = decodeErr xs
decodeCmdArgs BC_CMD_ITERATE _ (_ :< _ :< b :< _ :< xs) = (prc ++ dec ++ "\n" ++ dec', B.empty)
  where
    prc = " (Bind " ++ show b ++ ") <-"
    (dec, xs') = decodeExprCmd 1 xs
    dec' = decodeCodeBlock xs' "Iterate"
decodeCmdArgs BC_CMD_ITERATE _ bs = decodeErr bs
decodeCmdArgs BC_CMD_IF_THEN_ELSE _ Empty = decodeErr B.empty
decodeCmdArgs BC_CMD_IF_THEN_ELSE _ xs | B.length xs < 6 = decodeErr xs
decodeCmdArgs BC_CMD_IF_THEN_ELSE _ (rt1 :< rt2 :< b :< xs) = (cmd ++ dec ++ "\n" ++ dec' ++ dec'', B.empty)
  where
    cmd = "-" ++ (show ((toEnum (fromIntegral rt1))::ExprType)) ++ (show ((toEnum (fromIntegral rt2))::ExprType)) ++ " (Bind " ++ show b ++ ") <-"
    thenSize = bytesToWord16 (B.head xs, B.head (B.tail xs))
    (dec, xs') = decodeExprCmd 1 (B.drop 2 xs)
    dec' = decodeCodeBlock (B.take (fromIntegral thenSize) xs') "Then"
    dec'' = decodeCodeBlock (B.drop (fromIntegral thenSize) xs') "Else"
decodeCmdArgs BC_CMD_IF_THEN_ELSE _ bs = decodeErr bs
decodeCmdArgs BS_CMD_REQUEST_VERSION _ xs = decodeExprProc 0 xs
decodeCmdArgs BS_CMD_REQUEST_TYPE _ xs = decodeExprProc 0 xs
decodeCmdArgs BS_CMD_REQUEST_MICROS _ xs = decodeExprProc 0 xs
decodeCmdArgs BS_CMD_REQUEST_MILLIS _ xs = decodeExprProc 0 xs
decodeCmdArgs BS_CMD_DEBUG _ xs = decodeExprProc 1 xs
decodeCmdArgs DIG_CMD_READ_PIN _ xs = decodeExprProc 1 xs
decodeCmdArgs DIG_CMD_WRITE_PIN _ xs = decodeExprCmd 2 xs
decodeCmdArgs DIG_CMD_READ_PORT _ xs = decodeExprProc 2 xs
decodeCmdArgs DIG_CMD_WRITE_PORT _ xs = decodeExprCmd 3 xs
decodeCmdArgs ALG_CMD_READ_PIN _ xs = decodeExprProc 1 xs
decodeCmdArgs ALG_CMD_WRITE_PIN _ xs = decodeExprCmd 2 xs
decodeCmdArgs ALG_CMD_TONE_PIN _ xs = decodeExprCmd 3 xs
decodeCmdArgs ALG_CMD_NOTONE_PIN _ xs = decodeExprCmd 1 xs
decodeCmdArgs I2C_CMD_CONFIG _ xs = decodeExprCmd 0 xs
decodeCmdArgs I2C_CMD_READ _ xs = decodeExprProc 2 xs
decodeCmdArgs I2C_CMD_WRITE _ xs = decodeExprCmd 2 xs
decodeCmdArgs SER_CMD_BEGIN _ xs = decodeExprCmd 2 xs
decodeCmdArgs SER_CMD_END _ xs = decodeExprCmd 1 xs
decodeCmdArgs SER_CMD_WRITE _ xs = decodeExprCmd 2 xs
decodeCmdArgs SER_CMD_WRITE_LIST _ xs = decodeExprCmd 2 xs
decodeCmdArgs SER_CMD_AVAIL _ xs = decodeExprProc 1 xs
decodeCmdArgs SER_CMD_READ _ xs = decodeExprProc 1 xs
decodeCmdArgs SER_CMD_READ_LIST _ xs = decodeExprProc 1 xs
decodeCmdArgs STEP_CMD_2PIN _ xs = decodeExprCmd 3 xs
decodeCmdArgs STEP_CMD_4PIN _ xs = decodeExprCmd 5 xs
decodeCmdArgs STEP_CMD_SET_SPEED _ xs = decodeExprCmd 2 xs
decodeCmdArgs STEP_CMD_STEP _ xs = decodeExprCmd 2 xs
decodeCmdArgs SRVO_CMD_ATTACH _ xs = decodeExprCmd 3 xs
decodeCmdArgs SRVO_CMD_DETACH _ xs = decodeExprCmd 1 xs
decodeCmdArgs SRVO_CMD_WRITE _ xs = decodeExprCmd 2 xs
decodeCmdArgs SRVO_CMD_WRITE_MICROS _ xs = decodeExprCmd 2 xs
decodeCmdArgs SRVO_CMD_READ _ xs = decodeExprProc 1 xs
decodeCmdArgs SRVO_CMD_READ_MICROS _ xs = decodeExprProc 1 xs
decodeCmdArgs SCHED_CMD_CREATE_TASK _ xs = decodeExprCmd 3 xs
decodeCmdArgs SCHED_CMD_DELETE_TASK _ xs = decodeExprCmd 1 xs
decodeCmdArgs SCHED_CMD_ADD_TO_TASK _ xs = (dec ++ "\n" ++ dec', B.empty)
  where
    (dec, xs') = decodeExprCmd 2 xs
    dec' = decodeCodeBlock xs' "AddToTask"
decodeCmdArgs SCHED_CMD_SCHED_TASK _ xs = decodeExprCmd 2 xs
decodeCmdArgs SCHED_CMD_ATTACH_INT _ xs = decodeExprCmd 3 xs
decodeCmdArgs SCHED_CMD_DETACH_INT _ xs = decodeExprCmd 1 xs
decodeCmdArgs SCHED_CMD_QUERY_ALL _ xs = decodeExprProc 0 xs
decodeCmdArgs SCHED_CMD_QUERY _ xs = decodeExprProc 1 xs
decodeCmdArgs SCHED_CMD_RESET _ xs =  decodeExprCmd 0 xs
decodeCmdArgs SCHED_CMD_BOOT_TASK _ xs = decodeExprCmd 1 xs
decodeCmdArgs SCHED_CMD_GIVE_SEM _ xs = decodeExprCmd 1 xs
decodeCmdArgs SCHED_CMD_TAKE_SEM _ xs = decodeExprCmd 1 xs
decodeCmdArgs SCHED_CMD_INTERRUPTS _ xs = decodeExprCmd 0 xs
decodeCmdArgs SCHED_CMD_NOINTERRUPTS _ xs = decodeExprCmd 0 xs
decodeCmdArgs REF_CMD_NEW _ xs = decodeRefNew 1 xs
decodeCmdArgs REF_CMD_READ _ xs =  decodeRefProc 1 xs
decodeCmdArgs REF_CMD_WRITE _ xs = decodeRefCmd 2 xs
decodeCmdArgs EXPR_CMD_RET _ xs = decodeExprProc 1 xs
decodeCmdArgs UNKNOWN_COMMAND x xs = ("-" ++ show x, xs)

decodeExprCmd :: Int -> B.ByteString -> (String, B.ByteString)
decodeExprCmd cnt bs = decodeExprCmd' cnt "" bs
  where
    decodeExprCmd' :: Int -> String -> B.ByteString -> (String, B.ByteString)
    decodeExprCmd' cnt' _ bss =
        if (cnt' == 0)
        then ("", bss)
        else (dec' ++ dec'', bs'')
      where
        (dec', bs') = decodeExpr bss
        (dec'', bs'') = decodeExprCmd' (cnt'-1) dec' bs'

decodeExprProc :: Int -> B.ByteString -> (String, B.ByteString)
decodeExprProc _   Empty = decodeErr B.empty
decodeExprProc cnt bs = (" (Bind " ++ show b ++ ") <-" ++ c, bs')
  where
    b = B.head bs
    (c, bs') = decodeExprCmd cnt (B.tail bs)

decodeRefCmd :: Int -> B.ByteString -> (String, B.ByteString)
decodeRefCmd cnt bs =
  case bs of
    (x :< _)  -> ("-" ++ (show ((toEnum (fromIntegral x))::ExprType)) ++ " " ++ dec, bs')
    _         -> decodeErr bs
  where
    (dec, bs') = decodeExprCmd cnt (B.tail bs)

decodeRefProc :: Int -> B.ByteString -> (String, B.ByteString)
decodeRefProc cnt bs =
  case bs of
    (_ :< Empty)   -> decodeErr bs
    (x :< y :< _)  -> ("-" ++ (show ((toEnum (fromIntegral x))::ExprType)) ++ " (Bind " ++ show y ++ ") <-"++ dec, bs')
    _              -> decodeErr bs
  where
    (dec, bs') = decodeExprCmd cnt (B.tail $ B.tail bs)

decodeRefNew :: Int -> B.ByteString -> (String, B.ByteString)
decodeRefNew cnt bs =
  case bs of
    (_x :< Empty)        -> decodeErr bs
    (_x :< _y :< Empty)  -> decodeErr bs
    (x :< _ :< z :< _)   -> ("-" ++ (show ((toEnum (fromIntegral x))::ExprType)) ++ " (Ref Index " ++ show z ++ ") "++ dec, bs')
    _                    -> decodeErr bs
  where
    (dec, bs') = decodeExprCmd cnt (B.drop 3 bs)

decodeErr :: B.ByteString -> (String, B.ByteString)
decodeErr bs = ("Decode Error, remaining=" ++ show (encode bs), B.empty)

decodeCodeBlock :: B.ByteString -> String -> String
decodeCodeBlock bs desc =
  "*** Start of " ++ desc ++ " body (Size: " ++ (show $ B.length bs) ++ " bytes) :\n" ++
  (decodeCmds $ decodeCodeBlock' bs []) ++
  "*** End of " ++ desc ++ " body\n"
    where
      decodeCodeBlock' :: B.ByteString -> [B.ByteString] -> [B.ByteString]
      decodeCodeBlock' bs' cmds =
        case bs' of
          Empty                  -> cmds
          (x :< xs) | x < 0xFF   -> decodeCodeBlock' (B.drop (fromIntegral x) xs) (cmds ++ [B.take (fromIntegral x) xs])
          (0xFF :< x :< y :< xs) -> decodeCodeBlock' (B.drop (fromIntegral len') xs) (cmds ++ [B.take (fromIntegral len') xs])
                                    where
                                      len' :: Word16
                                      len' = ((fromIntegral y) `shiftL` 8) .|. (fromIntegral x)
          _                      -> cmds

decodeExpr :: B.ByteString -> (String, B.ByteString)
decodeExpr (ty :< Empty)    = decodeErr $ B.singleton ty
decodeExpr (ty :< op :< bs) = (" (" ++ opStr ++ ")", bs')
  where
    etype = ty .&. 0x7F
    (opStr, bs') = decodeTypeOp (toEnum $ fromIntegral etype) (fromIntegral op) bs
decodeExpr _                = decodeErr B.empty

decodeTypeOp :: ExprType -> Int -> B.ByteString -> (String, B.ByteString)
decodeTypeOp etype op bs =
  case etype of
    EXPR_LIST8 -> (show etype ++ "-" ++ show elop ++ delop, bs'')
    EXPR_FLOAT -> (show etype ++ "-" ++ show efop ++ defop, bs''')
    _          -> (show etype ++ "-" ++ show eop  ++ deop,  bs')
  where
    eop  = toEnum op::ExprOp
    elop = toEnum op::ExprListOp
    efop = toEnum op::ExprFloatOp
    (deop, bs')    = decodeOp etype eop bs
    (delop, bs'')  = decodeListOp elop bs
    (defop, bs''') = decodeFloatOp efop bs

decodeOp :: ExprType -> ExprOp -> B.ByteString -> (String, B.ByteString)
decodeOp etype eop bs =
  case eop of
    EXPR_LIT   -> decodeLit etype bs
    EXPR_REF   -> decodeRefBind bs
    EXPR_BIND  -> decodeRefBind bs
    EXPR_EQ    -> decodeExprOps 2 "" bs
    EXPR_LESS  -> decodeExprOps 2 "" bs
    EXPR_IF    -> decodeExprOps 3 "" bs
    EXPR_FINT  -> decodeExprOps 1 "" bs
    EXPR_NEG   -> decodeExprOps 1 "" bs
    EXPR_SIGN  -> decodeExprOps 1 "" bs
    EXPR_ADD   -> decodeExprOps 2 "" bs
    EXPR_SUB   -> decodeExprOps 2 "" bs
    EXPR_MULT  -> decodeExprOps 2 "" bs
    EXPR_DIV   -> decodeExprOps 2 "" bs
    EXPR_NOT   -> decodeExprOps 1 "" bs
    EXPR_AND   -> decodeExprOps 2 "" bs
    EXPR_OR    -> decodeExprOps 2 "" bs
    EXPR_TINT  -> decodeExprOps 1 "" bs
    EXPR_XOR   -> decodeExprOps 2 "" bs
    EXPR_REM   -> decodeExprOps 2 "" bs
    EXPR_COMP  -> decodeExprOps 2 "" bs
    EXPR_SHFL  -> decodeExprOps 2 "" bs
    EXPR_SHFR  -> decodeExprOps 2 "" bs
    EXPR_TSTB  -> decodeExprOps 2 "" bs
    EXPR_SETB  -> decodeExprOps 2 "" bs
    EXPR_CLRB  -> decodeExprOps 2 "" bs
    EXPR_QUOT  -> decodeExprOps 2 "" bs
    EXPR_MOD   -> decodeExprOps 2 "" bs
    EXPR_SHOW  -> decodeExprOps 1 "" bs
    EXPR_LEFT  -> decodeExprOps 1 "" bs

decodeRefBind :: B.ByteString -> (String, B.ByteString)
decodeRefBind bs =
  case bs of
    (x :< xs) -> (show x, xs)
    _         -> decodeErr bs

decodeLit :: ExprType -> B.ByteString -> (String, B.ByteString)
decodeLit etype bs =
  case etype of
    EXPR_UNIT   -> (" ()", bs)
    EXPR_BOOL   -> case bs of
                     (x :< xs) -> (if x==0 then " False" else " True", xs)
                     _         -> decodeErr bs
    EXPR_WORD8  -> case bs of
                     (x :< xs) -> (" " ++ show x, xs)
                     _         -> decodeErr bs
    EXPR_WORD16 -> case bs of
                     (_ :< Empty)   -> decodeErr bs
                     (x :< y :< xs) -> (" " ++ (show $ bytesToWord16 (x,y)), xs)
                     _              -> decodeErr bs
    EXPR_WORD32 -> case bs of
                     (_ :< xs)
                      | B.length xs < 3  -> decodeErr bs
                     (x :< y :< z :< a :< xs) -> (" " ++ (show $ bytesToWord32 (x,y,z,a)), xs)
                     _                   -> decodeErr bs
    EXPR_INT8   -> case bs of
                     (x :< xs) -> (" " ++ show ((fromIntegral x)::Int8), xs)
                     _         -> decodeErr bs
    EXPR_INT16  -> case bs of
                     (_ :< Empty)   -> decodeErr bs
                     (x :< y :< xs) -> (" " ++ show ((fromIntegral $ bytesToWord16 (x,y))::Int16), xs)
                     _         -> decodeErr bs
    EXPR_INT32  -> case bs of
                     (_ :< xs)
                      | B.length xs < 3  -> decodeErr bs
                     (x :< y :< z :< a :< xs) -> (" " ++ show ((fromIntegral $ bytesToWord32 (x,y,z,a))::Int32), xs)
                     _                   -> decodeErr bs
    EXPR_FLOAT  -> case bs of
                     (_ :< xs)
                      | B.length xs < 3  -> decodeErr bs
                     (x :< y :< z :< a :< xs) -> (" " ++ show (bytesToFloat (x,y,z,a)), xs)
                     _                   -> decodeErr bs
    EXPR_LIST8  -> case bs of
                     (x :< Empty) | x == 0        -> decodeErr bs
                     (x :< xs) | x /= (fromIntegral $ B.length xs) -> decodeErr bs
                     (l :< xs)                    -> (" " ++ show (B.unpack $ B.take (fromIntegral l) xs), B.drop (fromIntegral l) xs)
                     _                            -> decodeErr bs

decodeExprOps :: Int -> String -> B.ByteString -> (String, B.ByteString)
decodeExprOps cnt _ bs =
    if (cnt == 0)
    then ("", bs)
    else (dec' ++ dec'', bs'')
  where
    (dec', bs') = decodeExpr bs
    (dec'', bs'') = decodeExprOps (cnt-1) dec' bs'

decodeListOp :: ExprListOp -> B.ByteString -> (String, B.ByteString)
decodeListOp elop bs =
  case elop of
    EXPRL_LIT  -> case bs of
                    (x :< xs) -> decodeListLit (fromIntegral x) xs
                    _         -> decodeErr bs
    EXPRL_REF  -> decodeRefBind bs
    EXPRL_BIND -> decodeRefBind bs
    EXPRL_EQ   -> decodeExprOps 2 "" bs
    EXPRL_LESS -> decodeExprOps 2 "" bs
    EXPRL_IF   -> decodeExprOps 3 "" bs
    EXPRL_ELEM -> decodeExprOps 2 "" bs
    EXPRL_LEN  -> decodeExprOps 1 "" bs
    EXPRL_CONS -> decodeExprOps 2 "" bs
    EXPRL_APND -> decodeExprOps 2 "" bs
    EXPRL_SLIC -> decodeExprOps 3 "" bs
    EXPRL_LEFT -> decodeExprOps 1 "" bs
    EXPRL_PACK -> case bs of
                    (_ :< Empty) -> ("[]", B.tail bs)
                    (x :< xs)    -> decodeListPack (fromIntegral x) xs
                    _            -> decodeErr bs
  where
    decodeListLit :: Int -> B.ByteString -> (String, B.ByteString)
    decodeListLit cnt bsl = (show $ B.unpack $ B.take cnt bsl, B.drop cnt bsl)

    decodeListPack :: Int -> B.ByteString -> (String, B.ByteString)
    decodeListPack cnt bsp = ("[" ++ dec ++ "]", bs')
      where
        (dec, bs') = decodeExprOps cnt "" bsp

decodeFloatOp :: ExprFloatOp -> B.ByteString -> (String, B.ByteString)
decodeFloatOp efop bs =
  case efop of
    EXPRF_LIT   -> case bs of
                     (_ :< xs)
                      | B.length xs < 3  -> decodeErr bs
                     (x :< y :< z :< a :< xs) -> (" " ++ show (bytesToFloat (x,y,z,a)), xs)
                     _                   -> decodeErr bs
    EXPRF_REF   -> decodeRefBind bs
    EXPRF_BIND  -> decodeRefBind bs
    EXPRF_EQ    -> decodeExprOps 2 "" bs
    EXPRF_LESS  -> decodeExprOps 2 "" bs
    EXPRF_IF    -> decodeExprOps 3 "" bs
    EXPRF_FINT  -> decodeExprOps 1 "" bs
    EXPRF_NEG   -> decodeExprOps 1 "" bs
    EXPRF_SIGN  -> decodeExprOps 1 "" bs
    EXPRF_ADD   -> decodeExprOps 2 "" bs
    EXPRF_SUB   -> decodeExprOps 2 "" bs
    EXPRF_MULT  -> decodeExprOps 2 "" bs
    EXPRF_DIV   -> decodeExprOps 2 "" bs
    EXPRF_SHOW  -> decodeExprOps 2 "" bs
    EXPRF_TRUNC  -> decodeExprOps 1 "" bs
    EXPRF_FRAC   -> decodeExprOps 1 "" bs
    EXPRF_ROUND  -> decodeExprOps 1 "" bs
    EXPRF_CEIL   -> decodeExprOps 1 "" bs
    EXPRF_FLOOR  -> decodeExprOps 1 "" bs
    EXPRF_PI     -> decodeExprOps 0 "" bs
    EXPRF_EXP    -> decodeExprOps 1 "" bs
    EXPRF_LOG    -> decodeExprOps 1 "" bs
    EXPRF_SQRT   -> decodeExprOps 1 "" bs
    EXPRF_SIN    -> decodeExprOps 1 "" bs
    EXPRF_COS    -> decodeExprOps 1 "" bs
    EXPRF_TAN    -> decodeExprOps 1 "" bs
    EXPRF_ASIN   -> decodeExprOps 1 "" bs
    EXPRF_ACOS   -> decodeExprOps 1 "" bs
    EXPRF_ATAN   -> decodeExprOps 1 "" bs
    EXPRF_ATAN2  -> decodeExprOps 2 "" bs
    EXPRF_SINH   -> decodeExprOps 1 "" bs
    EXPRF_COSH   -> decodeExprOps 1 "" bs
    EXPRF_TANH   -> decodeExprOps 1 "" bs
    EXPRF_POWER  -> decodeExprOps 2 "" bs
    EXPRF_ISNAN  -> decodeExprOps 1 "" bs
    EXPRF_ISINF  -> decodeExprOps 1 "" bs
    EXPRF_LEFT   -> decodeExprOps 1 "" bs

