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
module System.Hardware.Haskino.Utils where

import           Data.Bits              (shiftL, shiftR, (.&.), (.|.))
import           Data.Char              (chr, isAlphaNum, isAscii, isSpace, ord)
import           Data.IORef             (newIORef, readIORef, writeIORef)
import           Data.List              (intercalate)
import           Data.Serialize         (runGet, runPut)
import           Data.Serialize.IEEE754 (getFloat32le, putFloat32le)
import           Data.Time              (getCurrentTime, utctDayTime)
import           Data.Word              (Word16, Word32, Word8)
import           Numeric                (showHex, showIntAtBase)

import qualified Data.ByteString        as B

-- | A simple printer that can keep track of sequence numbers. Used for debugging purposes.
mkDebugPrinter :: Bool -> IO (String -> IO ())
mkDebugPrinter False = return (const (return ()))
mkDebugPrinter True  = do
        cnt <- newIORef (1::Int)
        let f s = do i <- readIORef cnt
                     writeIORef cnt (i+1)
                     tick <- utctDayTime `fmap` getCurrentTime
                     let precision = 1000000 :: Integer
                         micro = round . (fromIntegral precision *) . toRational $ tick
                     putStrLn $ "[" ++ show i ++ ":" ++ show (micro :: Integer) ++ "] Haskino: " ++ s
        return f

-- | Show a byte in a visible format.
showByte :: Word8 -> String
showByte i | isVisible = [c]
           | i <= 0xf  = '0' : showHex i ""
           | True      = showHex i ""
  where c = chr $ fromIntegral i
        isVisible = isAscii c && isAlphaNum c && isSpace c

-- | Show a list of bytes
showByteList :: [Word8] -> String
showByteList bs =  "[" ++ intercalate ", " (map showByte bs) ++ "]"

-- | Show a number as a binary value
showBin :: (Integral a, Show a) => a -> String
showBin n = showIntAtBase 2 (head . show) n ""

-- | Turn a lo/hi encoded Arduino string constant into a Haskell string
getString :: [Word8] -> String
getString s = map (chr . fromIntegral) s

-- | Convert a word to it's bytes, as would be required by Arduino comms
-- | Note: Little endian format, which is Arduino native
word32ToBytes :: Word32 -> [Word8]
word32ToBytes i = map fromIntegral [ i .&. 0xFF, (i `shiftR` 8) .&. 0xFF,
                                    (i `shiftR` 16) .&. 0xFF,
                                    (i `shiftR`  24) .&. 0xFF]

-- | Inverse conversion for word32ToBytes
-- | Note: Little endian format, which is Arduino native
bytesToWord32 :: (Word8, Word8, Word8, Word8) -> Word32
bytesToWord32 (a, b, c, d) = fromIntegral d `shiftL` 24 .|.
                             fromIntegral c `shiftL` 16 .|.
                             fromIntegral b `shiftL`  8 .|.
                             fromIntegral a

-- | Convert a word to it's bytes, as would be required by Arduino comms
-- | Note: Little endian format, which is Arduino native
word16ToBytes :: Word16 -> [Word8]
word16ToBytes i = map fromIntegral [ i .&. 0xFF, (i `shiftR`  8) .&. 0xFF ]

-- | Inverse conversion for word16ToBytes
-- | Note: Little endian format, which is Arduino native
bytesToWord16 :: (Word8, Word8) -> Word16
bytesToWord16 (a, b) = fromIntegral a .|. fromIntegral b `shiftL` 8

-- | Convert a float to it's bytes, as would be required by Arduino comms
-- | Note: Little endian format, which is Arduino native
floatToBytes :: Float -> [Word8]
floatToBytes f = B.unpack $ runPut $ putFloat32le f

-- | Inverse conversion for floatToBytes
-- | Note: Little endian format, which is Arduino native
bytesToFloat :: (Word8, Word8, Word8, Word8) -> Float
bytesToFloat (a,b,c,d) = case e of
        Left  _ -> 0.0
        Right f -> f
    where
        bString = B.pack [a,b,c,d]
        e = runGet getFloat32le bString

stringToBytes :: String -> [Word8]
stringToBytes s = map (\d -> fromIntegral $ ord d) s
