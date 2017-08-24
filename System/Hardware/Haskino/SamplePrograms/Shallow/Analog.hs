-------------------------------------------------------------------------------
-- |
-- Module      :  System.Hardware.Haskino.SamplePrograms.Strong.Analog
--                Based on System.Hardware.Arduino
-- Copyright   :  (c) University of Kansas
--                System.Hardware.Arduino (c) Levent Erkok
-- License     :  BSD3
-- Stability   :  experimental
--
-- Reads the value of an analog input, controlled by a 10K potentiometer.
-------------------------------------------------------------------------------

module System.Hardware.Haskino.SamplePrograms.Strong.Analog where

import Control.Monad (when)
import Control.Monad.Trans (liftIO)

import System.Hardware.Haskino

-- | Read the value of an analog input line. We will print the value
-- on the screen, and also blink a led on the Arduino based on the
-- value. The smaller the value, the faster the blink.
--
-- The circuit simply has a 10K potentiometer between 5V and GND, with
-- the wiper line connected to analog input 3. We also have a led between
-- pin 13 and GND.
--
--  <<http://http://github.com/ku-fpg/arduino-lab/raw/master/System/Hardware/Haskino/SamplePrograms/Schematics/Analog.png>>
analogVal :: IO ()
analogVal = withArduino False "/dev/cu.usbmodem1421" $ do
               setPinMode led OUTPUT
               setPinMode pot INPUT
               cur <- analogRead pot
               liftIO $ print cur
               go cur
  where led = 13
        pot = 3
        go cur = do digitalWrite led True
                    delayMillis $ fromIntegral cur
                    digitalWrite led False
                    delayMillis $ fromIntegral cur
                    new <- analogRead pot
                    when (cur /= new) $ liftIO $ print new
                    go new

