-------------------------------------------------------------------------------
-- |
-- Module      :  System.Hardware.KansasAmber.SamplePrograms.Blink
--                Based on System.Hardware.Arduino.comm
-- Copyright   :  (c) University of Kansas
--                System.Hardware.Arduino (c) Levent Erkok
-- License     :  BSD3
-- Stability   :  experimental
--
-- KansasAmber allows Haskell programs to control Arduino boards 
-- (<http://www.arduino.cc>)
-- and peripherals, using the Firmata protocol (<http://firmata.org>).
--
-- For details, see: <http://kufpg.github.com/KansasAmber>.
-------------------------------------------------------------------------------
module System.Hardware.KansasAmber (
  -- * Communication functions
  openArduino, closeArduino, withArduino, send, ArduinoConnection
  -- * Deep embeddings
  , Arduino(..) , Command(..), Procedure(..), Local(..)
  -- * Programming the Arduino
  -- ** Pins
  , Pin, Port, pin, digital, analog, pinPort, PinMode(..), setPinMode
  -- ** Gereral utils
  , systemReset, queryFirmware, capabilityQuery, analogMappingQuery
  ,samplingInterval
  -- ** Digital IO
  , digitalReport, digitalPortReport, digitalPortWrite, digitalWrite
  , digitalPortRead, digitalRead 
  -- ** Programming with triggers
  , waitFor, waitAny, waitAnyHigh, waitAnyLow
  -- ** Analog IO
  , analogReport, analogWrite, analogExtendedWrite, analogRead
  -- ** I2C
  , SlaveAddress, SlaveRegister, i2cRead, i2cWrite, i2cConfig
  -- ** Pulse
  , pulse
  -- ** Servo
  , MinPulse, MaxPulse, servoConfig
  -- ** Scheduler
  , TaskLength, TaskID, TaskTime, TaskPos, queryAllTasks, queryTask, createTask
  , deleteTask, delay, scheduleTask, scheduleReset
  -- ** Stepper
  , StepDevice, StepType(..), NumSteps, StepSpeed, StepAccel, StepPerRev
  , StepDelay(..), StepDir(..), stepperConfig, stepperStep
  -- ** Control structures
  , loop
 )
 where

import System.Hardware.KansasAmber.Data
import System.Hardware.KansasAmber.Comm