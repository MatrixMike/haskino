-------------------------------------------------------------------------------
-- |
-- Module      :  System.Hardware.Haskino.Expr
--                Based on System.Hardware.Arduino.Expr
-- Copyright   :  (c) University of Kansas
--                System.Hardware.Arduino (c) Levent Erkok
-- License     :  BSD3
-- Stability   :  experimental
--
-- Underlying data structures
-------------------------------------------------------------------------------
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstrainedClassMethods #-}
module System.Hardware.Haskino.Expr where

import       Data.Int (Int8, Int16, Int32)
import       Data.Word (Word8, Word16, Word32)
import       Data.Boolean as B
import       Data.Boolean.Numbers as BN
import       Data.Boolean.Bits as BB
import       System.Hardware.Haskino.Utils

data RemoteRef a where
    RemoteRefB   :: Int -> RemoteRef Bool
    RemoteRefW8  :: Int -> RemoteRef Word8
    RemoteRefW16 :: Int -> RemoteRef Word16
    RemoteRefW32 :: Int -> RemoteRef Word32
    RemoteRefI8  :: Int -> RemoteRef Int8
    RemoteRefI16 :: Int -> RemoteRef Int16
    RemoteRefI32 :: Int -> RemoteRef Int32
    RemoteRefI   :: Int -> RemoteRef Int
    RemoteRefL8  :: Int -> RemoteRef [Word8]
    RemoteRefFloat :: Int -> RemoteRef Float

deriving instance Show a => Show (RemoteRef a)

data Expr a where
  LitUnit      :: Expr ()
  LitB         :: Bool -> Expr Bool
  LitW8        :: Word8 -> Expr Word8
  LitW16       :: Word16 -> Expr Word16
  LitW32       :: Word32 -> Expr Word32
  LitI8        :: Int8 -> Expr Int8
  LitI16       :: Int16 -> Expr Int16
  LitI32       :: Int32 -> Expr Int32
  LitI         :: Int   -> Expr Int
  LitList8     :: [Word8] -> Expr [Word8]
  LitFloat     :: Float -> Expr Float
  ShowB        :: Expr Bool -> Expr [Word8]
  ShowW8       :: Expr Word8 -> Expr [Word8]
  ShowW16      :: Expr Word16 -> Expr [Word8]
  ShowW32      :: Expr Word32 -> Expr [Word8]
  ShowI8       :: Expr Int8 -> Expr [Word8]
  ShowI16      :: Expr Int16 -> Expr [Word8]
  ShowI32      :: Expr Int32 -> Expr [Word8]
  ShowI        :: Expr Int   -> Expr [Word8]
  ShowFloat    :: Expr Float -> Expr Word8 -> Expr [Word8]
  ShowUnit     :: Expr () -> Expr [Word8]
  RefB         :: Int -> Expr Bool
  RefW8        :: Int -> Expr Word8
  RefW16       :: Int -> Expr Word16
  RefW32       :: Int -> Expr Word32
  RefI8        :: Int -> Expr Int8
  RefI16       :: Int -> Expr Int16
  RefI32       :: Int -> Expr Int32
  RefI         :: Int -> Expr Int
  RefList8     :: Int -> Expr [Word8]
  RefFloat     :: Int -> Expr Float
  RemBindB     :: Int -> Expr Bool
  RemBindW8    :: Int -> Expr Word8
  RemBindW16   :: Int -> Expr Word16
  RemBindW32   :: Int -> Expr Word32
  RemBindI8    :: Int -> Expr Int8
  RemBindI16   :: Int -> Expr Int16
  RemBindI32   :: Int -> Expr Int32
  RemBindI     :: Int -> Expr Int
  RemBindList8 :: Int -> Expr [Word8]
  RemBindFloat :: Int -> Expr Float
  RemBindUnit  :: Int -> Expr ()
  FromIntW8    :: Expr Int -> Expr Word8
  FromIntW16   :: Expr Int -> Expr Word16
  FromIntW32   :: Expr Int -> Expr Word32
  FromIntI8    :: Expr Int -> Expr Int8
  FromIntI16   :: Expr Int -> Expr Int16
  FromIntI32   :: Expr Int -> Expr Int32
  FromIntFloat :: Expr Int -> Expr Float
  ToIntW8      :: Expr Word8  -> Expr Int
  ToIntW16     :: Expr Word16 -> Expr Int
  ToIntW32     :: Expr Word32 -> Expr Int
  ToIntI8      :: Expr Int8  -> Expr Int
  ToIntI16     :: Expr Int16 -> Expr Int
  ToIntI32     :: Expr Int32 -> Expr Int
  NotB         :: Expr Bool -> Expr Bool
  AndB         :: Expr Bool -> Expr Bool -> Expr Bool
  OrB          :: Expr Bool -> Expr Bool -> Expr Bool
  EqB          :: Expr Bool -> Expr Bool -> Expr Bool
  LessB        :: Expr Bool -> Expr Bool -> Expr Bool
  IfB          :: Expr Bool  -> Expr Bool -> Expr Bool -> Expr Bool
  NegW8        :: Expr Word8 -> Expr Word8
  SignW8       :: Expr Word8 -> Expr Word8
  AddW8        :: Expr Word8 -> Expr Word8 -> Expr Word8
  SubW8        :: Expr Word8 -> Expr Word8 -> Expr Word8
  MultW8       :: Expr Word8 -> Expr Word8 -> Expr Word8
  DivW8        :: Expr Word8 -> Expr Word8 -> Expr Word8
  RemW8        :: Expr Word8 -> Expr Word8 -> Expr Word8
  QuotW8       :: Expr Word8 -> Expr Word8 -> Expr Word8
  ModW8        :: Expr Word8 -> Expr Word8 -> Expr Word8
  AndW8        :: Expr Word8 -> Expr Word8 -> Expr Word8
  OrW8         :: Expr Word8 -> Expr Word8 -> Expr Word8
  XorW8        :: Expr Word8 -> Expr Word8 -> Expr Word8
  CompW8       :: Expr Word8 -> Expr Word8
  ShfLW8       :: Expr Word8 -> Expr Int -> Expr Word8
  ShfRW8       :: Expr Word8 -> Expr Int -> Expr Word8
  EqW8         :: Expr Word8 -> Expr Word8 -> Expr Bool
  LessW8       :: Expr Word8 -> Expr Word8 -> Expr Bool
  IfW8         :: Expr Bool  -> Expr Word8 -> Expr Word8 -> Expr Word8
  TestBW8      :: Expr Word8 -> Expr Int -> Expr Bool
  SetBW8       :: Expr Word8 -> Expr Int -> Expr Word8
  ClrBW8       :: Expr Word8 -> Expr Int -> Expr Word8
  NegW16       :: Expr Word16 -> Expr Word16
  SignW16      :: Expr Word16 -> Expr Word16
  AddW16       :: Expr Word16 -> Expr Word16 -> Expr Word16
  SubW16       :: Expr Word16 -> Expr Word16 -> Expr Word16
  MultW16      :: Expr Word16 -> Expr Word16 -> Expr Word16
  DivW16       :: Expr Word16 -> Expr Word16 -> Expr Word16
  RemW16       :: Expr Word16 -> Expr Word16 -> Expr Word16
  QuotW16      :: Expr Word16 -> Expr Word16 -> Expr Word16
  ModW16       :: Expr Word16 -> Expr Word16 -> Expr Word16
  AndW16       :: Expr Word16 -> Expr Word16 -> Expr Word16
  OrW16        :: Expr Word16 -> Expr Word16 -> Expr Word16
  XorW16       :: Expr Word16 -> Expr Word16 -> Expr Word16
  CompW16      :: Expr Word16 -> Expr Word16
  ShfLW16      :: Expr Word16 -> Expr Int -> Expr Word16
  ShfRW16      :: Expr Word16 -> Expr Int -> Expr Word16
  EqW16        :: Expr Word16 -> Expr Word16 -> Expr Bool
  LessW16      :: Expr Word16 -> Expr Word16 -> Expr Bool
  IfW16        :: Expr Bool   -> Expr Word16 -> Expr Word16 -> Expr Word16
  TestBW16     :: Expr Word16  -> Expr Int -> Expr Bool
  SetBW16      :: Expr Word16 -> Expr Int -> Expr Word16
  ClrBW16      :: Expr Word16 -> Expr Int -> Expr Word16
  NegW32       :: Expr Word32 -> Expr Word32
  SignW32      :: Expr Word32 -> Expr Word32
  AddW32       :: Expr Word32 -> Expr Word32 -> Expr Word32
  SubW32       :: Expr Word32 -> Expr Word32 -> Expr Word32
  MultW32      :: Expr Word32 -> Expr Word32 -> Expr Word32
  DivW32       :: Expr Word32 -> Expr Word32 -> Expr Word32
  RemW32       :: Expr Word32 -> Expr Word32 -> Expr Word32
  QuotW32      :: Expr Word32 -> Expr Word32 -> Expr Word32
  ModW32       :: Expr Word32 -> Expr Word32 -> Expr Word32
  AndW32       :: Expr Word32 -> Expr Word32 -> Expr Word32
  OrW32        :: Expr Word32 -> Expr Word32 -> Expr Word32
  XorW32       :: Expr Word32 -> Expr Word32 -> Expr Word32
  CompW32      :: Expr Word32 -> Expr Word32
  ShfLW32      :: Expr Word32 -> Expr Int -> Expr Word32
  ShfRW32      :: Expr Word32 -> Expr Int -> Expr Word32
  EqW32        :: Expr Word32 -> Expr Word32 -> Expr Bool
  LessW32      :: Expr Word32 -> Expr Word32 -> Expr Bool
  IfW32        :: Expr Bool   -> Expr Word32 -> Expr Word32 -> Expr Word32
  TestBW32     :: Expr Word32 -> Expr Int -> Expr Bool
  SetBW32      :: Expr Word32 -> Expr Int -> Expr Word32
  ClrBW32      :: Expr Word32 -> Expr Int -> Expr Word32
  NegI8        :: Expr Int8 -> Expr Int8
  SignI8       :: Expr Int8 -> Expr Int8
  AddI8        :: Expr Int8 -> Expr Int8 -> Expr Int8
  SubI8        :: Expr Int8 -> Expr Int8 -> Expr Int8
  MultI8       :: Expr Int8 -> Expr Int8 -> Expr Int8
  DivI8        :: Expr Int8 -> Expr Int8 -> Expr Int8
  RemI8        :: Expr Int8 -> Expr Int8 -> Expr Int8
  QuotI8       :: Expr Int8 -> Expr Int8 -> Expr Int8
  ModI8        :: Expr Int8 -> Expr Int8 -> Expr Int8
  AndI8        :: Expr Int8 -> Expr Int8 -> Expr Int8
  OrI8         :: Expr Int8 -> Expr Int8 -> Expr Int8
  XorI8        :: Expr Int8 -> Expr Int8 -> Expr Int8
  CompI8       :: Expr Int8 -> Expr Int8
  ShfLI8       :: Expr Int8 -> Expr Int -> Expr Int8
  ShfRI8       :: Expr Int8 -> Expr Int -> Expr Int8
  EqI8         :: Expr Int8 -> Expr Int8 -> Expr Bool
  LessI8       :: Expr Int8 -> Expr Int8 -> Expr Bool
  IfI8         :: Expr Bool -> Expr Int8 -> Expr Int8 -> Expr Int8
  TestBI8      :: Expr Int8 -> Expr Int -> Expr Bool
  SetBI8       :: Expr Int8 -> Expr Int -> Expr Int8
  ClrBI8       :: Expr Int8 -> Expr Int -> Expr Int8
  NegI16       :: Expr Int16 -> Expr Int16
  SignI16      :: Expr Int16 -> Expr Int16
  AddI16       :: Expr Int16 -> Expr Int16 -> Expr Int16
  SubI16       :: Expr Int16 -> Expr Int16 -> Expr Int16
  MultI16      :: Expr Int16 -> Expr Int16 -> Expr Int16
  DivI16       :: Expr Int16 -> Expr Int16 -> Expr Int16
  RemI16       :: Expr Int16 -> Expr Int16 -> Expr Int16
  QuotI16      :: Expr Int16 -> Expr Int16 -> Expr Int16
  ModI16       :: Expr Int16 -> Expr Int16 -> Expr Int16
  AndI16       :: Expr Int16 -> Expr Int16 -> Expr Int16
  OrI16        :: Expr Int16 -> Expr Int16 -> Expr Int16
  XorI16       :: Expr Int16 -> Expr Int16 -> Expr Int16
  CompI16      :: Expr Int16 -> Expr Int16
  ShfLI16      :: Expr Int16 -> Expr Int -> Expr Int16
  ShfRI16      :: Expr Int16 -> Expr Int -> Expr Int16
  EqI16        :: Expr Int16 -> Expr Int16 -> Expr Bool
  LessI16      :: Expr Int16 -> Expr Int16 -> Expr Bool
  IfI16        :: Expr Bool   -> Expr Int16 -> Expr Int16 -> Expr Int16
  TestBI16     :: Expr Int16  -> Expr Int -> Expr Bool
  SetBI16      :: Expr Int16 -> Expr Int -> Expr Int16
  ClrBI16      :: Expr Int16 -> Expr Int -> Expr Int16
  NegI32       :: Expr Int32 -> Expr Int32
  SignI32      :: Expr Int32 -> Expr Int32
  AddI32       :: Expr Int32 -> Expr Int32 -> Expr Int32
  SubI32       :: Expr Int32 -> Expr Int32 -> Expr Int32
  MultI32      :: Expr Int32 -> Expr Int32 -> Expr Int32
  DivI32       :: Expr Int32 -> Expr Int32 -> Expr Int32
  RemI32       :: Expr Int32 -> Expr Int32 -> Expr Int32
  QuotI32      :: Expr Int32 -> Expr Int32 -> Expr Int32
  ModI32       :: Expr Int32 -> Expr Int32 -> Expr Int32
  AndI32       :: Expr Int32 -> Expr Int32 -> Expr Int32
  OrI32        :: Expr Int32 -> Expr Int32 -> Expr Int32
  XorI32       :: Expr Int32 -> Expr Int32 -> Expr Int32
  CompI32      :: Expr Int32 -> Expr Int32
  ShfLI32      :: Expr Int32 -> Expr Int -> Expr Int32
  ShfRI32      :: Expr Int32 -> Expr Int -> Expr Int32
  EqI32        :: Expr Int32 -> Expr Int32 -> Expr Bool
  LessI32      :: Expr Int32 -> Expr Int32 -> Expr Bool
  IfI32        :: Expr Bool   -> Expr Int32 -> Expr Int32 -> Expr Int32
  TestBI32     :: Expr Int32 -> Expr Int -> Expr Bool
  SetBI32      :: Expr Int32 -> Expr Int -> Expr Int32
  ClrBI32      :: Expr Int32 -> Expr Int -> Expr Int32
  NegI         :: Expr Int -> Expr Int
  SignI        :: Expr Int -> Expr Int
  AddI         :: Expr Int -> Expr Int -> Expr Int
  SubI         :: Expr Int -> Expr Int -> Expr Int
  MultI        :: Expr Int -> Expr Int -> Expr Int
  DivI         :: Expr Int -> Expr Int -> Expr Int
  RemI         :: Expr Int -> Expr Int -> Expr Int
  QuotI        :: Expr Int -> Expr Int -> Expr Int
  ModI         :: Expr Int -> Expr Int -> Expr Int
  AndI         :: Expr Int -> Expr Int -> Expr Int
  OrI          :: Expr Int -> Expr Int -> Expr Int
  XorI         :: Expr Int -> Expr Int -> Expr Int
  CompI        :: Expr Int -> Expr Int
  ShfLI        :: Expr Int -> Expr Int -> Expr Int
  ShfRI        :: Expr Int -> Expr Int -> Expr Int
  EqI          :: Expr Int -> Expr Int -> Expr Bool
  LessI        :: Expr Int -> Expr Int -> Expr Bool
  IfI          :: Expr Bool  -> Expr Int -> Expr Int -> Expr Int
  TestBI       :: Expr Int -> Expr Int -> Expr Bool
  SetBI        :: Expr Int -> Expr Int -> Expr Int
  ClrBI        :: Expr Int -> Expr Int -> Expr Int
  NegFloat     :: Expr Float -> Expr Float
  SignFloat    :: Expr Float -> Expr Float
  AddFloat     :: Expr Float -> Expr Float -> Expr Float
  SubFloat     :: Expr Float -> Expr Float -> Expr Float
  MultFloat    :: Expr Float -> Expr Float -> Expr Float
  DivFloat     :: Expr Float -> Expr Float -> Expr Float
  EqFloat      :: Expr Float -> Expr Float -> Expr Bool
  LessFloat    :: Expr Float -> Expr Float -> Expr Bool
  IfFloat      :: Expr Bool  -> Expr Float -> Expr Float -> Expr Float
  TruncFloat   :: Expr Float -> Expr Int32
  FracFloat    :: Expr Float -> Expr Float
  RoundFloat   :: Expr Float -> Expr Int32
  CeilFloat    :: Expr Float -> Expr Int32
  FloorFloat   :: Expr Float -> Expr Int32
  PiFloat      :: Expr Float
  ExpFloat     :: Expr Float -> Expr Float
  LogFloat     :: Expr Float -> Expr Float
  SqrtFloat    :: Expr Float -> Expr Float
  SinFloat     :: Expr Float -> Expr Float
  CosFloat     :: Expr Float -> Expr Float
  TanFloat     :: Expr Float -> Expr Float
  AsinFloat    :: Expr Float -> Expr Float
  AcosFloat    :: Expr Float -> Expr Float
  AtanFloat    :: Expr Float -> Expr Float
  Atan2Float   :: Expr Float -> Expr Float -> Expr Float
  SinhFloat    :: Expr Float -> Expr Float
  CoshFloat    :: Expr Float -> Expr Float
  TanhFloat    :: Expr Float -> Expr Float
  PowerFloat   :: Expr Float -> Expr Float -> Expr Float
  IsNaNFloat   :: Expr Float -> Expr Bool
  IsInfFloat   :: Expr Float -> Expr Bool
  ElemList8    :: Expr [Word8] -> Expr Int   -> Expr Word8
  LenList8     :: Expr [Word8] -> Expr Int
  ConsList8    :: Expr Word8   -> Expr [Word8] -> Expr [Word8]
  ApndList8    :: Expr [Word8] -> Expr [Word8] -> Expr [Word8]
  PackList8    :: [Expr Word8] -> Expr [Word8]
  SliceList8   :: Expr [Word8] -> Expr Int -> Expr Int -> Expr [Word8]
  EqL8         :: Expr [Word8] -> Expr [Word8] -> Expr Bool
  LessL8       :: Expr [Word8] -> Expr [Word8] -> Expr Bool
  IfL8         :: Expr Bool  -> Expr [Word8] -> Expr [Word8] -> Expr [Word8]

deriving instance Show a => Show (Expr a)

data ExprEither a b where
    ExprLeft   :: (ExprB a, ExprB b) => Expr a -> ExprEither a b
    ExprRight  :: (ExprB a, ExprB b) => Expr b -> ExprEither a b

deriving instance (Show a, Show b) => Show (ExprEither a b)

class ExprB a where
    lit      :: a -> Expr a
    eval'    :: Expr a -> a
    remBind  :: Int -> Expr a
    showE    :: Expr a -> Expr [Word8]
    lessE    :: Expr a -> Expr a -> Expr Bool
    lesseqE  :: Expr a -> Expr a -> Expr Bool
    {-# INLINE lesseqE #-}
    lesseqE a b = notB (lessE b a)
    greatE   :: Expr a -> Expr a -> Expr Bool
    {-# INLINE greatE #-}
    greatE a b = lessE b a
    greateqE :: Expr a -> Expr a -> Expr Bool
    {-# INLINE greateqE #-}
    greateqE a b = notB (lessE a b)
    eqE      :: Expr a -> Expr a -> Expr Bool
    neqE     :: Expr a -> Expr a -> Expr Bool
    {-# INLINE neqE #-}
    neqE a b = notB (eqE a b)
    ifBE     :: Expr Bool -> Expr a -> Expr a -> Expr a

instance ExprB () where
    lit _ = LitUnit
    eval' = evalExprUnit
    remBind = RemBindUnit
    showE = ShowUnit
    {-# INLINE lessE #-}
    lessE _ _ = false
    {-# INLINE eqE #-}
    eqE _ _ = true
    {-# INLINE ifBE #-}
    ifBE _ _ _ = LitUnit

instance ExprB Word8 where
    lit = LitW8
    eval' = evalExprW8
    remBind = RemBindW8
    showE = ShowW8
    {-# INLINE lessE #-}
    lessE = (B.<*)
    {-# INLINE eqE #-}
    eqE = (==*)
    {-# INLINE ifBE #-}
    ifBE = ifB

instance ExprB Word16 where
    lit = LitW16
    eval' = evalExprW16
    remBind = RemBindW16
    showE = ShowW16
    {-# INLINE lessE #-}
    lessE = (B.<*)
    {-# INLINE eqE #-}
    eqE = (==*)
    {-# INLINE ifBE #-}
    ifBE = ifB

instance ExprB Word32 where
    lit = LitW32
    eval' = evalExprW32
    remBind = RemBindW32
    showE = ShowW32
    {-# INLINE lessE #-}
    lessE = (B.<*)
    {-# INLINE eqE #-}
    eqE = (==*)
    {-# INLINE ifBE #-}
    ifBE = ifB

instance ExprB Int8 where
    lit = LitI8
    eval' = evalExprI8
    remBind = RemBindI8
    showE = ShowI8
    {-# INLINE lessE #-}
    lessE = (B.<*)
    {-# INLINE eqE #-}
    eqE = (==*)
    {-# INLINE ifBE #-}
    ifBE = ifB

instance ExprB Int16 where
    lit = LitI16
    eval' = evalExprI16
    remBind = RemBindI16
    showE = ShowI16
    {-# INLINE lessE #-}
    lessE = (B.<*)
    {-# INLINE eqE #-}
    eqE = (==*)
    {-# INLINE ifBE #-}
    ifBE = ifB

instance ExprB Int32 where
    lit = LitI32
    eval' = evalExprI32
    remBind = RemBindI32
    showE = ShowI32
    {-# INLINE lessE #-}
    lessE = (B.<*)
    {-# INLINE eqE #-}
    eqE = (==*)
    {-# INLINE ifBE #-}
    ifBE = ifB

instance ExprB Int where
    lit = LitI
    eval' = evalExprI
    remBind = RemBindI
    showE = ShowI
    {-# INLINE lessE #-}
    lessE = (B.<*)
    {-# INLINE eqE #-}
    eqE = (==*)
    {-# INLINE ifBE #-}
    ifBE = ifB

instance ExprB Bool where
    lit = LitB
    eval' = evalExprB
    remBind = RemBindB
    showE = ShowB
    {-# INLINE lessE #-}
    lessE = (B.<*)
    {-# INLINE eqE #-}
    eqE = (==*)
    {-# INLINE ifBE #-}
    ifBE = ifB

instance ExprB [Word8] where
    lit = LitList8
    eval' = evalExprL8
    remBind = RemBindList8
    showE = id
    {-# INLINE lessE #-}
    lessE = (B.<*)
    {-# INLINE eqE #-}
    eqE = (==*)
    {-# INLINE ifBE #-}
    ifBE = ifB

instance ExprB Float where
    lit = LitFloat
    eval' = evalExprFloat
    remBind = RemBindFloat
    showE = showFFloatE Nothing
    {-# INLINE lessE #-}
    lessE = (B.<*)
    {-# INLINE eqE #-}
    eqE = (==*)
    {-# INLINE ifBE #-}
    ifBE = ifB

litString :: String -> [Word8]
litString = stringToBytes

litStringE :: String -> Expr [Word8]
litStringE s = LitList8 $ stringToBytes s

showB :: Show a => a -> [Word8]
showB = litString . show

showFFloatE :: Maybe (Expr Word8) -> Expr Float -> Expr [Word8]
showFFloatE Nothing ef = showFFloatE (Just 2) ef
showFFloatE (Just ep) ef = ShowFloat ef ep

instance B.Boolean (Expr Bool) where
  true  = LitB True
  false = LitB False
  notB  = NotB
  (&&*) = AndB
  (||*) = OrB

type instance BooleanOf (Expr Bool) = Expr Bool

instance B.EqB (Expr Bool) where
  (==*) = EqB

instance B.OrdB (Expr Bool) where
  (<*) = LessB

instance B.IfB (Expr Bool) where
  ifB = IfB

instance Num (Expr Word8) where
  (+) x y = AddW8 x y
  (-) x y = SubW8 x y
  (*) x y = MultW8 x y
  negate x = NegW8 x
  abs x  = x
  signum x = SignW8 x
  fromInteger x = LitW8 $ fromInteger x

instance  Bounded (Expr Word8) where
    minBound = lit 0
    maxBound = lit 255

type instance BooleanOf (Expr Word8) = Expr Bool

instance B.EqB (Expr Word8) where
  (==*) = EqW8

instance B.OrdB (Expr Word8) where
  (<*) = LessW8

instance B.IfB (Expr Word8) where
  ifB = IfW8

instance BN.NumB (Expr Word8) where
  type IntegerOf (Expr Word8) = (Expr Int)
  fromIntegerB e = FromIntW8 e

instance BN.IntegralB (Expr Word8) where
  div = DivW8
  rem = RemW8
  quot = QuotW8
  mod = ModW8
  toIntegerB e = ToIntW8 e

instance BB.BitsB (Expr Word8) where
  type IntOf (Expr Word8) = Expr Int
  (.&.) = AndW8
  (.|.) = OrW8
  xor = XorW8
  complement = CompW8
  shiftL = ShfLW8
  shiftR = ShfRW8
  isSigned = (\_ -> lit False)
  bitSize = (\_ -> lit 8)
  bit = \i -> 1 `shiftL` i
  setBit = SetBW8
  clearBit = ClrBW8
  testBit = TestBW8

instance  Num (Expr Word16) where
  (+) x y = AddW16 x y
  (-) x y = SubW16 x y
  (*) x y = MultW16 x y
  negate x = NegW16 x
  abs x  = x
  signum x = SignW16 x
  fromInteger x = LitW16 $ fromInteger x

type instance BooleanOf (Expr Word16) = Expr Bool

instance B.EqB (Expr Word16) where
  (==*) = EqW16

instance B.OrdB (Expr Word16) where
  (<*) = LessW16

instance B.IfB (Expr Word16) where
  ifB = IfW16

instance BN.NumB (Expr Word16) where
  type IntegerOf (Expr Word16) = (Expr Int)
  fromIntegerB e = FromIntW16 e

instance BN.IntegralB (Expr Word16) where
  div = DivW16
  rem = RemW16
  quot = QuotW16
  mod = ModW16
  toIntegerB e = ToIntW16 e

instance BB.BitsB (Expr Word16) where
  type IntOf (Expr Word16) = Expr Int
  (.&.) = AndW16
  (.|.) = OrW16
  xor = XorW16
  complement = CompW16
  shiftL = ShfLW16
  shiftR = ShfRW16
  isSigned = (\_ -> lit False)
  bitSize = (\_ -> lit 16)
  bit = \i -> 1 `shiftL` i
  setBit = SetBW16
  clearBit = ClrBW16
  testBit = TestBW16

instance  Num (Expr Word32) where
  (+) x y = AddW32 x y
  (-) x y = SubW32 x y
  (*) x y = MultW32 x y
  negate x = NegW32 x
  abs x  = x
  signum x = SignW32 x
  fromInteger x = LitW32 $ fromInteger x

type instance BooleanOf (Expr Word32) = Expr Bool

instance B.EqB (Expr Word32) where
  (==*) = EqW32

instance B.OrdB (Expr Word32) where
  (<*) = LessW32

instance B.IfB (Expr Word32) where
  ifB = IfW32

instance BN.NumB (Expr Word32) where
  type IntegerOf (Expr Word32) = (Expr Int)
  fromIntegerB e = FromIntW32 e

instance BN.IntegralB (Expr Word32) where
  div = DivW32
  rem = RemW32
  quot = QuotW32
  mod = ModW32
  toIntegerB e = ToIntW32 e

instance BB.BitsB (Expr Word32) where
  type IntOf (Expr Word32) = Expr Int
  (.&.) = AndW32
  (.|.) = OrW32
  xor = XorW32
  complement = CompW32
  shiftL = ShfLW32
  shiftR = ShfRW32
  isSigned = (\_ -> lit False)
  bitSize = (\_ -> lit 32)
  bit = \i -> 1 `shiftL` i
  setBit = SetBW32
  clearBit = ClrBW32
  testBit = TestBW32

instance Num (Expr Int8) where
  (+) x y = AddI8 x y
  (-) x y = SubI8 x y
  (*) x y = MultI8 x y
  negate x = NegI8 x
  abs x  = x * signum x
  signum x = SignI8 x
  fromInteger x = LitI8 $ fromInteger x

type instance BooleanOf (Expr Int8) = Expr Bool

instance B.EqB (Expr Int8) where
  (==*) = EqI8

instance B.OrdB (Expr Int8) where
  (<*) = LessI8

instance B.IfB (Expr Int8) where
  ifB = IfI8

instance BN.NumB (Expr Int8) where
  type IntegerOf (Expr Int8) = (Expr Int)
  fromIntegerB e = FromIntI8 e

instance BN.IntegralB (Expr Int8) where
  div = DivI8
  rem = RemI8
  quot = QuotI8
  mod = ModI8
  toIntegerB e = ToIntI8 e

instance BB.BitsB (Expr Int8) where
  type IntOf (Expr Int8) = Expr Int
  (.&.) = AndI8
  (.|.) = OrI8
  xor = XorI8
  complement = CompI8
  shiftL = ShfLI8
  shiftR = ShfRI8
  isSigned = (\_ -> lit False)
  bitSize = (\_ -> lit 8)
  bit = \i -> 1 `shiftL` i
  setBit = SetBI8
  clearBit = ClrBI8
  testBit = TestBI8

instance  Num (Expr Int16) where
  (+) x y = AddI16 x y
  (-) x y = SubI16 x y
  (*) x y = MultI16 x y
  negate x = NegI16 x
  abs x  = x * signum x
  signum x = SignI16 x
  fromInteger x = LitI16 $ fromInteger x

type instance BooleanOf (Expr Int16) = Expr Bool

instance B.EqB (Expr Int16) where
  (==*) = EqI16

instance B.OrdB (Expr Int16) where
  (<*) = LessI16

instance B.IfB (Expr Int16) where
  ifB = IfI16

instance BN.NumB (Expr Int16) where
  type IntegerOf (Expr Int16) = (Expr Int)
  fromIntegerB e = FromIntI16 e

instance BN.IntegralB (Expr Int16) where
  div = DivI16
  rem = RemI16
  quot = QuotI16
  mod = ModI16
  toIntegerB e = ToIntI16 e

instance BB.BitsB (Expr Int16) where
  type IntOf (Expr Int16) = Expr Int
  (.&.) = AndI16
  (.|.) = OrI16
  xor = XorI16
  complement = CompI16
  shiftL = ShfLI16
  shiftR = ShfRI16
  isSigned = (\_ -> lit False)
  bitSize = (\_ -> lit 16)
  bit = \i -> 1 `shiftL` i
  setBit = SetBI16
  clearBit = ClrBI16
  testBit = TestBI16

instance  Num (Expr Int32) where
  (+) x y = AddI32 x y
  (-) x y = SubI32 x y
  (*) x y = MultI32 x y
  negate x = NegI32 x
  abs x  = x * signum x
  signum x = SignI32 x
  fromInteger x = LitI32 $ fromInteger x

type instance BooleanOf (Expr Int32) = Expr Bool

instance B.EqB (Expr Int32) where
  (==*) = EqI32

instance B.OrdB (Expr Int32) where
  (<*) = LessI32

instance B.IfB (Expr Int32) where
  ifB = IfI32

instance BN.NumB (Expr Int32) where
  type IntegerOf (Expr Int32) = (Expr Int)
  fromIntegerB e = FromIntI32 e

instance BN.IntegralB (Expr Int32) where
  div = DivI32
  rem = RemI32
  quot = QuotI32
  mod = ModI32
  toIntegerB e = ToIntI32 e

instance BB.BitsB (Expr Int32) where
  type IntOf (Expr Int32) = Expr Int
  (.&.) = AndI32
  (.|.) = OrI32
  xor = XorI32
  complement = CompI32
  shiftL = ShfLI32
  shiftR = ShfRI32
  isSigned = (\_ -> lit False)
  bitSize = (\_ -> lit 32)
  bit = \i -> 1 `shiftL` i
  setBit = SetBI32
  clearBit = ClrBI32
  testBit = TestBI32

instance  Num (Expr Int) where
  (+) x y = AddI x y
  (-) x y = SubI x y
  (*) x y = MultI x y
  negate x = NegI x
  abs x  = x * signum x
  signum x = SignI x
  fromInteger x = LitI $ fromInteger x

type instance BooleanOf (Expr Int) = Expr Bool

instance B.EqB (Expr Int) where
  (==*) = EqI

instance B.OrdB (Expr Int) where
  (<*) = LessI

instance B.IfB (Expr Int) where
  ifB = IfI

instance BN.NumB (Expr Int) where
  type IntegerOf (Expr Int) = (Expr Int)
  fromIntegerB e = e

instance BN.IntegralB (Expr Int) where
  div = DivI
  rem = RemI
  quot = QuotI
  mod = ModI
  toIntegerB e = e

instance BB.BitsB (Expr Int) where
  type IntOf (Expr Int) = Expr Int
  (.&.) = AndI
  (.|.) = OrI
  xor = XorI
  complement = CompI
  shiftL = ShfLI
  shiftR = ShfRI
  isSigned = (\_ -> lit False)
  bitSize = (\_ -> lit 32)
  bit = \i -> 1 `shiftL` i
  setBit = SetBI
  clearBit = ClrBI
  testBit = TestBI

type instance BooleanOf (Expr Float) = Expr Bool

instance B.EqB (Expr Float) where
  (==*) = EqFloat

instance B.OrdB (Expr Float) where
  (<*) = LessFloat

instance B.IfB (Expr Float) where
  ifB = IfFloat

instance Num (Expr Float) where
  (+) x y = AddFloat x y
  (-) x y = SubFloat x y
  (*) x y = MultFloat x y
  negate x = NegFloat x
  abs x  = x * signum x
  signum x = SignFloat x
  fromInteger x = LitFloat $ fromInteger x

instance Fractional (Expr Float) where
  (/) x y = DivFloat x y
  fromRational x = LitFloat $ fromRational x

instance BN.NumB (Expr Float) where
  type IntegerOf (Expr Float) = Expr Int
  fromIntegerB e = FromIntFloat e

instance Floating (Expr Float) where
  pi          = PiFloat
  exp x       = ExpFloat x
  log x       = LogFloat x
  sqrt x      = SqrtFloat x
  sin x       = SinFloat x
  cos x       = CosFloat x
  tan x       = TanFloat x
  asin x      = AsinFloat x
  acos x      = AcosFloat x
  atan x      = AtanFloat x
  sinh x      = SinhFloat x
  cosh x      = CoshFloat x
  tanh x      = TanhFloat x
  (**) x y    = PowerFloat x y
  logBase x y = LogFloat y / LogFloat x
  asinh x     = LogFloat (x + SqrtFloat (1.0+x*x))
  acosh x     = LogFloat (x + (x+1.0) * SqrtFloat ((x-1.0)/(x+1.0)))
  atanh x     = 0.5 * LogFloat ((1.0+x) / (1.0-x))

instance BN.RealFracB (Expr Float) where
  properFraction f = (fromIntegralB $ TruncFloat f, FracFloat f)
  truncate f = fromIntegralB $ TruncFloat f
  round f = fromIntegralB $ RoundFloat f
  ceiling f = fromIntegralB $ CeilFloat f
  floor f = fromIntegralB $ FloorFloat f

instance RealFloatB (Expr Float) where
  isNaN = IsNaNFloat
  isInfinite = IsInfFloat
  isNegativeZero f = BN.isInfinite f &&* f B.<* 0
  isIEEE _ = true -- AFAIK
  atan2 x y = Atan2Float x y

type instance BooleanOf (Expr [Word8]) = Expr Bool

instance B.EqB (Expr [Word8]) where
  (==*) = EqL8

instance B.OrdB (Expr [Word8]) where
  (<*) = LessL8

instance B.IfB (Expr [Word8]) where
  ifB = IfL8

infixl 9 !!*
infixl 5 *:, ++*

(!!*) :: Expr [Word8] -> Expr Int -> Expr Word8
(!!*) l i = ElemList8 l i

(*:) :: Expr Word8 -> Expr [Word8] -> Expr [Word8]
(*:) n l = ConsList8 n l

(++*) :: Expr [Word8] -> Expr [Word8] -> Expr [Word8]
(++*) l1 l2 = ApndList8 l1 l2

headE :: Expr [Word8] -> Expr Word8
headE l = ElemList8 l 0

tailE :: Expr [Word8] -> Expr [Word8]
tailE l = SliceList8 l 1 0

dropE :: Expr Int -> Expr [Word8] -> Expr [Word8]
dropE n l = SliceList8 l n 0

takeE :: Expr Int -> Expr [Word8] -> Expr [Word8]
takeE n l = SliceList8 l 0 n

nullE :: Expr [Word8] -> Expr Bool
nullE l = len l ==* 0

-- ToDo: overload length (or implement foldable class)
len :: Expr [Word8] -> Expr Int
len l = LenList8 l

pack :: [Expr Word8] -> Expr [Word8]
pack l = PackList8 l

-- | Haskino Firmware expresions, see:tbd
data ExprType = EXPR_UNIT
              | EXPR_BOOL
              | EXPR_WORD8
              | EXPR_WORD16
              | EXPR_WORD32
              | EXPR_INT8
              | EXPR_INT16
              | EXPR_INT32
              | EXPR_LIST8
              | EXPR_FLOAT
            deriving (Show, Enum, Ord, Eq)

data ExprEitherType = EXPRE_RIGHT
              | EXPRE_LEFT
            deriving (Show, Enum, Ord, Eq)

data ExprOp = EXPR_LIT
            | EXPR_REF
            | EXPR_BIND
            | EXPR_EQ
            | EXPR_LESS
            | EXPR_IF
            | EXPR_LEFT
            | EXPR_FINT
            | EXPR_NEG
            | EXPR_SIGN
            | EXPR_ADD
            | EXPR_SUB
            | EXPR_MULT
            | EXPR_DIV
            | EXPR_SHOW
            | EXPR_NOT
            | EXPR_AND
            | EXPR_OR
            | EXPR_TINT
            | EXPR_XOR
            | EXPR_REM
            | EXPR_COMP
            | EXPR_SHFL
            | EXPR_SHFR
            | EXPR_TSTB
            | EXPR_SETB
            | EXPR_CLRB
            | EXPR_QUOT
            | EXPR_MOD
          deriving (Show, Enum, Ord, Eq)

data ExprListOp = EXPRL_LIT
            | EXPRL_REF
            | EXPRL_BIND
            | EXPRL_EQ
            | EXPRL_LESS
            | EXPRL_IF
            | EXPRL_LEFT
            | EXPRL_ELEM
            | EXPRL_LEN
            | EXPRL_CONS
            | EXPRL_APND
            | EXPRL_PACK
            | EXPRL_SLIC
          deriving (Show, Enum, Ord, Eq)

data ExprFloatOp = EXPRF_LIT
            | EXPRF_REF
            | EXPRF_BIND
            | EXPRF_EQ
            | EXPRF_LESS
            | EXPRF_IF
            | EXPRF_LEFT
            | EXPRF_FINT
            | EXPRF_NEG
            | EXPRF_SIGN
            | EXPRF_ADD
            | EXPRF_SUB
            | EXPRF_MULT
            | EXPRF_DIV
            | EXPRF_SHOW
            | EXPRF_TRUNC
            | EXPRF_FRAC
            | EXPRF_ROUND
            | EXPRF_CEIL
            | EXPRF_FLOOR
            | EXPRF_PI
            | EXPRF_EXP
            | EXPRF_LOG
            | EXPRF_SQRT
            | EXPRF_SIN
            | EXPRF_COS
            | EXPRF_TAN
            | EXPRF_ASIN
            | EXPRF_ACOS
            | EXPRF_ATAN
            | EXPRF_ATAN2
            | EXPRF_SINH
            | EXPRF_COSH
            | EXPRF_TANH
            | EXPRF_POWER
            | EXPRF_ISNAN
            | EXPRF_ISINF
          deriving (Show, Enum, Ord, Eq)

exprCmdVal :: ExprType -> ExprOp -> [Word8]
exprCmdVal t o = [toW8 t, toW8 o]

exprLCmdVal :: ExprListOp -> [Word8]
exprLCmdVal o = [toW8 EXPR_LIST8, toW8 o]

exprFCmdVal :: ExprFloatOp -> [Word8]
exprFCmdVal o = [toW8 EXPR_FLOAT, toW8 o]

evalError :: Show a => Expr a -> a
evalError e = error $ "Error: Can't evaluate non literal - " ++ show e

evalExprUnit :: Expr () -> ()
evalExprUnit _ = ()

evalExprB :: Expr Bool -> Bool
evalExprB (LitB v) = v
evalExprB v        = evalError v

evalExprW8 :: Expr Word8 -> Word8
evalExprW8 (LitW8 v) = v
evalExprW8 v         = evalError v

evalExprW16 :: Expr Word16 -> Word16
evalExprW16 (LitW16 v) = v
evalExprW16 v          = evalError v

evalExprW32 :: Expr Word32 -> Word32
evalExprW32 (LitW32 v) = v
evalExprW32 v          = evalError v

evalExprI8 :: Expr Int8 -> Int8
evalExprI8 (LitI8 v) = v
evalExprI8 v         = evalError v

evalExprI16 :: Expr Int16 -> Int16
evalExprI16 (LitI16 v) = v
evalExprI16 v          = evalError v

evalExprI32 :: Expr Int32 -> Int32
evalExprI32 (LitI32 v) = v
evalExprI32 v          = evalError v

evalExprI :: Expr Int -> Int
evalExprI (LitI v) = v
evalExprI v        = evalError v

evalExprL8 :: Expr [Word8] -> [Word8]
evalExprL8 (LitList8 v) = v
evalExprL8 v            = evalError v

evalExprFloat :: Expr Float -> Float
evalExprFloat (LitFloat v) = v
evalExprFloat v            = evalError v

{-# NOINLINE abs_ #-}
abs_ :: Expr a -> a
abs_ _ = error "Internal error: abs_ called"

{-# NOINLINE rep_ #-}
rep_ :: ExprB a => a -> Expr a
rep_ w = lit w
