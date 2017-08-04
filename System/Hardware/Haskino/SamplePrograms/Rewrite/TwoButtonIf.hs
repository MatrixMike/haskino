{-# OPTIONS_GHC -fplugin=System.Hardware.Haskino.ShallowDeepPlugin #-}
-- {-# OPTIONS_GHC -fenable-rewrite-rules #-}
-------------------------------------------------------------------------------
-- |
-- Module      :  System.Hardware.Haskino.SamplePrograms.Rewrite.TwoButtonIf
--                Based on System.Hardware.Arduino
-- Copyright   :  (c) University of Kansas
-- License     :  BSD3
-- Stability   :  experimental
--
-- The /hello world/ of the arduino world, blinking the led.
-------------------------------------------------------------------------------

module Main where

import Prelude hiding (abs)

import System.Hardware.Haskino
import Control.Monad
import Data.Word
import Data.Boolean
import System.Hardware.Haskino.SamplePrograms.Rewrite.TwoButtonIfE

twoButtonProg1 :: Arduino ()
twoButtonProg1 = do
    let led1 = 12
    let led2 = 13
    let button1 = 2
    let button2 = 3
    setPinMode led1 OUTPUT
    setPinMode led2 OUTPUT
    setPinMode button1 INPUT
    setPinMode button2 INPUT
    loop $ do
        a <- digitalRead button1
        digitalWrite led1 True
        b <- digitalRead button2
        if a || b
        then do
          digitalWrite led1 a
          digitalWrite led2 b
          return (not a)
        else do
          digitalWrite led1 (not a)
          digitalWrite led2 (not b)
          a' <- digitalRead led1
          return (a' && b)
        delayMillis 1000

twoButtonProg2 :: Arduino ()
twoButtonProg2 = do
    let led1 = 12
    let led2 = 13
    let button1 = 2
    let button2 = 3
    setPinMode led1 OUTPUT
    setPinMode led2 OUTPUT
    setPinMode button1 INPUT
    setPinMode button2 INPUT
    loop $ do
        a <- digitalRead button1
        b <- digitalRead button2
        if a || b
        then do
          digitalWrite led1 a
          digitalWrite led2 b
          return True
        else do
          c <- digitalRead led1
          digitalWrite led1 (not a)
          digitalWrite led2 (not b)
          digitalRead led1
          return c
        delayMillis 1000

twoButtonProg3 :: Arduino ()
twoButtonProg3 = do
    let led1 = 12
    let led2 = 13
    let button1 = 2
    let button2 = 3
    setPinMode led1 OUTPUT
    setPinMode led2 OUTPUT
    setPinMode button1 INPUT
    setPinMode button2 INPUT
    loop $ do
        a <- digitalRead button1
        b <- digitalRead button2
        if a || b
        then do
          digitalWrite led1 a
          digitalWrite led2 b
        else do
          digitalWrite led1 (not a)
          digitalWrite led2 (not b)
        delayMillis 1000

twoButtonProg4 :: Arduino ()
twoButtonProg4 = do
    let led1 = 12
    let led2 = 13
    let button1 = 2
    let button2 = 3
    setPinMode led1 OUTPUT
    setPinMode led2 OUTPUT
    setPinMode button1 INPUT
    setPinMode button2 INPUT
    loop $ do
        a <- digitalRead button1
        digitalWrite led1 True
        b <- digitalRead button2
        c <- if a || b
             then do
               digitalWrite led1 a
               digitalWrite led2 b
               return (not a)
             else do
               digitalWrite led1 (not a)
               digitalWrite led2 (not b)
               a' <- digitalRead led1
               return (a' && b)
        digitalWrite led2 c
        delayMillis 1000

twoButtonProg5 :: Arduino ()
twoButtonProg5 = do
    let led1 = 12 :: Word8
    let led2 = 13 :: Word8
    let button1 = 2
    setPinMode led1 OUTPUT
    setPinMode led2 OUTPUT
    setPinMode button1 INPUT
    loop $ do
        a <- digitalRead button1
        if led1 > led2
        then do
          digitalWrite led1 a
        else do
          digitalWrite led1 (not a)
        delayMillis 1000

test1 :: Bool
test1 = (show twoButtonProg1) == (show twoButtonProg1E)

test2 :: Bool
test2 = (show twoButtonProg2) == (show twoButtonProg2E)

test3 :: Bool
test3 = (show twoButtonProg3) == (show twoButtonProg3E)

test4 :: Bool
test4 = (show twoButtonProg4) == (show twoButtonProg4E)

main :: IO ()
main = do
  if test1
  then putStrLn "*** Test1 Passed"
  else do
      putStrLn "*** Test1 Failed"
      putStrLn $ show twoButtonProg1
      putStrLn "-----------------"
      putStrLn $ show twoButtonProg1E
  if test2
  then putStrLn "*** Test2 Passed"
  else do
      putStrLn "*** Test2 Failed"
      putStrLn $ show twoButtonProg2
      putStrLn "-----------------"
      putStrLn $ show twoButtonProg2E
{-
  if test3
  then putStrLn "*** Test3 Passed"
  else do
      putStrLn "*** Test3 Failed"
      putStrLn $ show twoButtonProg3
      putStrLn "-----------------"
      putStrLn $ show twoButtonProg3E
-}
  if test4
  then putStrLn "*** Test4 Passed"
  else do
      putStrLn "*** Test4 Failed"
      putStrLn $ show twoButtonProg4
      putStrLn "-----------------"
      putStrLn $ show twoButtonProg4E

