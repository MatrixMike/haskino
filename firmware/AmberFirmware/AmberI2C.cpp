#include <Arduino.h>
#include <Wire.h>
#include "AmberComm.h"
#include "AmberCommands.h"
#include "AmberI2C.h"

static bool handleRead(int size, byte *msg);
static bool handleReadReg(int size, byte *msg);
static bool handleWrite(int size, byte *msg);

bool parseI2CMessage(int size, byte *msg)
    {
    switch (msg[0] ) 
        {
        case I2C_CMD_READ:
            return handleRead(size, msg);
            break;
        case I2C_CMD_READ_REG:
            return handleReadReg(size, msg);
            break;
        case I2C_CMD_WRITE:
            return handleWrite(size, msg);
            break;
        }
    return false;
    }

static int readFrom(byte address, byte wordCount)
    {
    int byteAvail;

    Wire.requestFrom((int) address, (int) wordCount*2);
    byteAvail = Wire.available();

    startReplyFrame(I2C_RESP_READ);

    for (int i = 0; i < byteAvail; i++) 
        {
        sendReplyByte(Wire.read());
        }

    endReplyFrame();    
    }

static bool handleRead(int size, byte *msg)
    {
    byte slaveAddress = msg[1];
    byte wordCount = msg[2];

    readFrom(slaveAddress, wordCount);
    return false;
    }

static bool handleReadReg(int size, byte *msg)
    {
    byte slaveAddress = msg[1];
    unsigned int slaveRegister;
    memcpy(&slaveRegister, &msg[2], 2);
    byte wordCount = msg[4];

    Wire.beginTransmission(slaveAddress);
    Wire.write(slaveRegister); // TBD size and byte order
    Wire.endTransmission();
    delayMicroseconds(70);

    readFrom(slaveAddress, wordCount);
    return false;
    }

static bool handleWrite(int size, byte *msg)
    {
    byte slaveAddress = msg[1];
    byte wordCount = msg[2];
    uint16_t *data = (uint16_t *) &msg[3];

    if (wordCount > (size - 2) / 2)
        wordCount = (size - 2) / 2;

    Wire.beginTransmission(slaveAddress);
    for (int i = 0; i < wordCount; i++) 
        {
        Wire.write(*data++);
        }
    Wire.endTransmission();
    delayMicroseconds(70);
    return false;
    }
