#include <Arduino.h>
#include "HaskinoBoardStatus.h"
#include "HaskinoComm.h"
#include "HaskinoCommands.h"
#include "HaskinoConfig.h"
#include "HaskinoFirmware.h"

static void handleRequestVersion(int size, const byte *msg);
static void handleRequestType(int size, const byte *msg);
static void handleRequestMicros(int size, const byte *msg);
static void handleRequestMillis(int size, const byte *msg);

void parseBoardStatusMessage(int size, const byte *msg)
    {
    switch (msg[0] ) 
        {
        case BS_CMD_REQUEST_VERSION:
            handleRequestVersion(size, msg);
            break;
        case BS_CMD_REQUEST_TYPE:
            handleRequestType(size, msg);
            break;
        case BS_CMD_REQUEST_MICROS:
            handleRequestMicros(size, msg);
            break;
        case BS_CMD_REQUEST_MILLIS:
            handleRequestMillis(size, msg);
            break;
        }
    }

static void handleRequestVersion(int size, const byte *msg)
    {
    static byte versionReply[2] = {FIRMWARE_MINOR,
                                   FIRMWARE_MAJOR};
        
    sendReply(sizeof(versionReply), BS_RESP_VERSION, versionReply);
    }

static void handleRequestType(int size, const byte *msg)
    {
    static byte typeReply[1] = {
#if defined(__AVR_ATmega8__)
                                ATmega8_TYPE};
#elif defined(__AVR_ATmega168__)
                                ATmega168_TYPE};
#elif defined(__AVR_ATmega328P__)
                                ATmega328P_TYPE};
#elif defined(__AVR_ATmega1280__)
                                ATmega1280_TYPE};
#elif defined(__AVR_ATmega2560__)
                                ATmega256_TYPE};
#elif defined(__AVR_ATmega32U4__)
                                ATmega32U4_TYPE};
#elif defined(__AVR_ATmega644P__)
                                ATmega644P_TYPE};
#elif defined(__AVR_ATmega644__)
                                ATmega644_TYPE};
#elif defined(__AVR_ATmega645__)
                                ATmega645_TYPE};
#elif defined(__SAM3X8E__)
                                SAM3X8E_TYPE};
#elif defined(ARDUINO_LINUX)
                                X86_TYPE};
#elif defined(INTEL_EDISON)
                                QUARK_TYPE};
#else
#error "Please define a new processor type board"
#endif
    sendReply(sizeof(typeReply), BS_RESP_TYPE, typeReply);
    }

static void handleRequestMicros(int size, const byte *msg)
    {
    uint32_t ms;
    byte microReply[6];

    microReply[0] = EXPR_WORD32;
    microReply[1] = EXPR_LIT;
    ms = micros();
    memcpy(&microReply[2], &ms, sizeof(ms));

    sendReply(2 + sizeof(microReply), BS_RESP_MICROS, (byte *) &microReply);
    }

static void handleRequestMillis(int size, const byte *msg)
    {
    uint32_t ms;
    byte milliReply[6];

    milliReply[0] = EXPR_WORD32;
    milliReply[1] = EXPR_LIT;
    ms = millis();
    memcpy(&milliReply[2], &ms, sizeof(ms));

    sendReply(2 + sizeof(uint32_t), BS_RESP_MILLIS, (byte *) &milliReply);
    }
