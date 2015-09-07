#include <Arduino.h>
#include "HaskinoComm.h"

static bool codeBlock = false;

void runCodeBlock(int blockSize, const byte * block, byte *local)
    {
    int currPos = 0;
    codeBlock = true;

    while (currPos < blockSize)
        {
        const byte *msg = &block[currPos];
        byte cmdSize = msg[0];
        const byte *cmd = &msg[1];

        parseMessage(cmdSize, cmd, (byte *) local);  

        currPos += cmdSize + 1;
        }
    codeBlock = false;
    }

bool isCodeBlock()
    {
    return codeBlock;
    }
