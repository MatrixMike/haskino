-------------------------------------------------------------------------------
-- |
-- Module      :  System.Hardware.Haskino.SamplePrograms.Strong.Blink
--                Based on System.Hardware.Arduino
-- Copyright   :  (c) University of Kansas
--                System.Hardware.Arduino (c) Levent Erkok
-- License     :  BSD3
-- Stability   :  experimental
--
-- The /hello world/ of the arduino world, blinking the led.
-------------------------------------------------------------------------------

module System.Hardware.Haskino.SamplePrograms.Strong.Blink where

import Control.Monad (forever)

import System.Hardware.Haskino

blink :: IO ()
blink = withArduino False "/dev/cu.usbmodem1421" $ do
           let led = 13
           setPinMode led OUTPUT
           loop $ do digitalWrite led True
                     delayMillis 1000
                     digitalWrite led False
                     delayMillis 1000

