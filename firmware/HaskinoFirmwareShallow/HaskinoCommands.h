#ifndef HaskinoCommandsH
#define HaskinoCommandsH

// Base Expression Types
#define EXPR_BOOL           0x01
#define EXPR_WORD8          0x02
#define EXPR_WORD16         0x03
#define EXPR_WORD32         0x04
#define EXPR_INT8           0x05
#define EXPR_INT16          0x06
#define EXPR_INT32          0x07
#define EXPR_LIST8          0x08
#define EXPR_FLOAT          0x09

// Base Expression Ops
#define EXPR_LIT            0x00

// Note:  None of the CMD_TYPE's should be 0x7x, so that there
// is no possibility of sending an HDLC frame or escape as
// a command and causing an extra escape to be sent.
// Also, not using 0x0x as a command type to avoid sending an
// all zero message.

#define CMD_TYPE_MASK           0xF0
#define CMD_SUBTYPE_MASK        0x0F

// Board Control commands
#define BC_CMD_TYPE             0x10
#define BC_CMD_SYSTEM_RESET     (BC_CMD_TYPE | 0x0)
#define BC_CMD_SET_PIN_MODE     (BC_CMD_TYPE | 0x1)
#define BC_CMD_DELAY_MILLIS     (BC_CMD_TYPE | 0x2)
#define BC_CMD_DELAY_MICROS     (BC_CMD_TYPE | 0x3)
#define BC_CMD_ITERATE          (BC_CMD_TYPE | 0x4)
#define BC_CMD_IF_THEN_ELSE     (BC_CMD_TYPE | 0x5)

// Board Control responses
#define BC_RESP_DELAY           (BC_CMD_TYPE | 0x8)
#define BC_RESP_IF_THEN_ELSE    (BC_CMD_TYPE | 0x9)
#define BC_RESP_ITERATE         (BC_CMD_TYPE | 0xA)

// Board Status commands
#define BS_CMD_TYPE             0x20
#define BS_CMD_REQUEST_VERSION  (BS_CMD_TYPE | 0x0)
#define BS_CMD_REQUEST_TYPE     (BS_CMD_TYPE | 0x1)
#define BS_CMD_REQUEST_MICROS   (BS_CMD_TYPE | 0x2)
#define BS_CMD_REQUEST_MILLIS   (BS_CMD_TYPE | 0x3)
#define BS_CMD_DEBUG            (BS_CMD_TYPE | 0x4)

// Board Status responses
#define BS_RESP_VERSION         (BS_CMD_TYPE | 0x8)
#define BS_RESP_TYPE            (BS_CMD_TYPE | 0x9)
#define BS_RESP_MICROS          (BS_CMD_TYPE | 0xA)
#define BS_RESP_MILLIS          (BS_CMD_TYPE | 0xB)
#define BS_RESP_STRING          (BS_CMD_TYPE | 0xC)
#define BS_RESP_DEBUG           (BS_CMD_TYPE | 0xD)

// Digital commands
#define DIG_CMD_TYPE            0x30
#define DIG_CMD_READ_PIN        (DIG_CMD_TYPE | 0x0)
#define DIG_CMD_WRITE_PIN       (DIG_CMD_TYPE | 0x1)
#define DIG_CMD_READ_PORT       (DIG_CMD_TYPE | 0x2)
#define DIG_CMD_WRITE_PORT      (DIG_CMD_TYPE | 0x3)

// Digital responses
#define DIG_RESP_READ_PIN       (DIG_CMD_TYPE | 0x8)
#define DIG_RESP_READ_PORT      (DIG_CMD_TYPE | 0x9)

// Analog commands
#define ALG_CMD_TYPE            0x40
#define ALG_CMD_READ_PIN        (ALG_CMD_TYPE | 0x0)
#define ALG_CMD_WRITE_PIN       (ALG_CMD_TYPE | 0x1)
#define ALG_CMD_TONE_PIN        (ALG_CMD_TYPE | 0x2)
#define ALG_CMD_NOTONE_PIN      (ALG_CMD_TYPE | 0x3)

// Analog responses
#define ALG_RESP_READ_PIN       (ALG_CMD_TYPE | 0x8)

// I2C commands
#define I2C_CMD_TYPE            0x50
#define I2C_CMD_CONFIG          (I2C_CMD_TYPE | 0x0)
#define I2C_CMD_READ            (I2C_CMD_TYPE | 0x1)
#define I2C_CMD_WRITE           (I2C_CMD_TYPE | 0x2)

// I2C responses
#define I2C_RESP_READ           (I2C_CMD_TYPE | 0x8)

// Servo commands
#define SRVO_CMD_TYPE           0x80
#define SRVO_CMD_ATTACH         (SRVO_CMD_TYPE | 0x0)
#define SRVO_CMD_DETACH         (SRVO_CMD_TYPE | 0x1)
#define SRVO_CMD_WRITE          (SRVO_CMD_TYPE | 0x2)
#define SRVO_CMD_WRITE_MICROS   (SRVO_CMD_TYPE | 0x3)
#define SRVO_CMD_READ           (SRVO_CMD_TYPE | 0x4)
#define SRVO_CMD_READ_MICROS    (SRVO_CMD_TYPE | 0x5)

// Servo responses
#define SRVO_RESP_ATTACH        (SRVO_CMD_TYPE | 0x8)
#define SRVO_RESP_READ          (SRVO_CMD_TYPE | 0x9)
#define SRVO_RESP_READ_MICROS   (SRVO_CMD_TYPE | 0xA)

// Stepper commands
#define STEP_CMD_TYPE           0x90
#define STEP_CMD_2PIN           (STEP_CMD_TYPE | 0x0)
#define STEP_CMD_4PIN           (STEP_CMD_TYPE | 0x1)
#define STEP_CMD_SET_SPEED      (STEP_CMD_TYPE | 0x2)
#define STEP_CMD_STEP           (STEP_CMD_TYPE | 0x3)

// Stepper responses
#define STEP_RESP_2PIN          (STEP_CMD_TYPE | 0x8)
#define STEP_RESP_4PIN          (STEP_CMD_TYPE | 0x9)
#define STEP_RESP_STEP          (STEP_CMD_TYPE | 0xA)

// Serial commands
#define SER_CMD_TYPE            0xE0

#define SER_CMD_BEGIN           (SER_CMD_TYPE | 0x0)
#define SER_CMD_END             (SER_CMD_TYPE | 0x1)
#define SER_CMD_AVAIL           (SER_CMD_TYPE | 0x2)
#define SER_CMD_READ            (SER_CMD_TYPE | 0x3)
#define SER_CMD_READ_LIST       (SER_CMD_TYPE | 0x4)
#define SER_CMD_WRITE           (SER_CMD_TYPE | 0x5)
#define SER_CMD_WRITE_LIST      (SER_CMD_TYPE | 0x6)

// Serial responses
#define SER_RESP_AVAIL          (SER_CMD_TYPE | 0x8)
#define SER_RESP_READ           (SER_CMD_TYPE | 0x9)
#define SER_RESP_READ_LIST      (SER_CMD_TYPE | 0xA)

#endif /* HaskinoCommandsH */

