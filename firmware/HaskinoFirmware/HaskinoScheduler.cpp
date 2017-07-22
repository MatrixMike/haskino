#include <Arduino.h>
#include <EEPROM.h>
#include "HaskinoCodeBlock.h"
#include "HaskinoComm.h"
#include "HaskinoCommands.h"
#include "HaskinoConfig.h"
#include "HaskinoExpr.h"
#include "HaskinoScheduler.h"

#define BOOT_TASK_INDEX_START   5

static bool handleQueryAll(int size, const byte *msg, CONTEXT *context);
static bool handleCreateTask(int size, const byte *msg, CONTEXT *context);
static bool handleDeleteTask(int size, const byte *msg, CONTEXT *context);
static bool handleAddToTask(int size, const byte *msg, CONTEXT *context);
static bool handleScheduleTask(int size, const byte *msg, CONTEXT *context);
static bool handleAttachInterrupt(int size, const byte *msg, CONTEXT *context);
static bool handleDetachInterrupt(int size, const byte *msg, CONTEXT *context);
static bool handleInterrupts(int size, const byte *msg, CONTEXT *context);
static bool handleNoInterrupts(int size, const byte *msg, CONTEXT *context);
static bool handleQuery(int size, const byte *msg, CONTEXT *context);
static bool handleReset(int size, const byte *msg, CONTEXT *context);
static bool handleBootTask(int size, const byte *msg, CONTEXT *context);
static bool handleTakeSem(int size, const byte *msg, CONTEXT *context);
static bool handleGiveSem(int size, const byte *msg, CONTEXT *context);
static void deleteTask(TASK* task);
static TASK *findTask(int id);
static bool createById(byte id, unsigned int taskSize, unsigned int bindSize);
static bool scheduleById(byte id, unsigned long deltaMillis);
static void handleISR(int intNum);
static void ISR0(void);
static void ISR1(void);
static void ISR2(void);
static void ISR3(void);
static void ISR4(void);
static void ISR5(void);

static TASK *firstTask = NULL;
static TASK *runningTask = NULL;
static CONTEXT *defaultContext = NULL;
static int taskCount = 0;
static SEMAPHORE semaphores[NUM_SEMAPHORES];
static TASK *intTasks[MAX_INTERRUPTS];

int getTaskCount()
    {
    return taskCount;
    }

bool parseSchedulerMessage(int size, const byte *msg, CONTEXT *context)
    {
    switch (msg[0]) 
        {
        case SCHED_CMD_QUERY_ALL:
            return handleQueryAll(size, msg, context);
            break;
        case SCHED_CMD_CREATE_TASK:
            return handleCreateTask(size, msg, context);
            break;
        case SCHED_CMD_DELETE_TASK:
            return handleDeleteTask(size, msg, context);
            break;
        case SCHED_CMD_ADD_TO_TASK:
            return handleAddToTask(size, msg, context);
            break;
        case SCHED_CMD_SCHED_TASK:
            return handleScheduleTask(size, msg, context);
            break;
        case SCHED_CMD_ATTACH_INT:
            return handleAttachInterrupt(size, msg, context);
            break;
        case SCHED_CMD_DETACH_INT:
            return handleDetachInterrupt(size, msg, context);
            break;
        case SCHED_CMD_INTERRUPTS:
            return handleInterrupts(size, msg, context);
            break;
        case SCHED_CMD_NOINTERRUPTS:
            return handleNoInterrupts(size, msg, context);
            break;
        case SCHED_CMD_QUERY:
            return handleQuery(size, msg, context);
            break;
        case SCHED_CMD_RESET:
            return handleReset(size, msg, context);
            break;
        case SCHED_CMD_BOOT_TASK:
            return handleBootTask(size, msg, context);
            break;
        case SCHED_CMD_TAKE_SEM:
            return handleTakeSem(size, msg, context);
            break;
        case SCHED_CMD_GIVE_SEM:
            return handleGiveSem(size, msg, context);
            break;
       }
    return false;
    }

CONTEXT *schedulerDefaultContext()
    {
    if (defaultContext == NULL)
        {
        defaultContext = (CONTEXT *) calloc(1, sizeof(CONTEXT));
        defaultContext->bind = (byte *) calloc(1, DEFAULT_BIND_COUNT * BIND_SPACING);
        defaultContext->bindSize = DEFAULT_BIND_COUNT;
        defaultContext->currBlockLevel = -1;
        defaultContext->recallBlockLevel = -1;
        }
    return defaultContext;
    }

static TASK *findTask(int id)
    {
    TASK *task = firstTask;

    while (task != NULL)
        {
        if (id == task->id)
            return task;
        task = task->next;
        }
    return NULL;
    }

static bool createById(byte id, unsigned int taskSize, unsigned int bindSize)
    {
    TASK *newTask;
    CONTEXT *newContext;
    byte *bind;

    if ((findTask(id) == NULL) &&
         ((newTask = (TASK *) malloc(taskSize + sizeof(TASK))) != NULL ))
        {
        if ((newContext = (CONTEXT *) malloc(sizeof(CONTEXT))) == NULL)
            {
            free(newTask);
            }
        else if ((bind = (byte *) calloc(1,bindSize*BIND_SPACING)) == NULL)
            {
            free(newContext);
            free(newTask);
            }
        else
            {
            newTask->next = firstTask;
            newTask->prev = NULL;
            newTask->context = newContext;
            firstTask = newTask;
            newTask->id = id;
            newTask->size = taskSize;
            newTask->currLen = 0;
            newTask->currPos = 0;
            newTask->ready = false;
            newTask->rescheduled = false;
            newTask->endData = newTask->data + newTask->size;
            newContext->currBlockLevel = -1;
            newContext->recallBlockLevel = -1;
            newContext->task = newTask;
            newContext->bindSize = bindSize;
            newContext->bind = bind;
            }
        taskCount++;
        }

    return false;
    }

static bool handleCreateTask(int size, const byte *msg, CONTEXT *context)
    {
    byte *expr = (byte *) &msg[1];
    byte id = evalWord8Expr(&expr, context);
    unsigned int taskSize = evalWord16Expr(&expr, context);
    unsigned int bindSize = evalWord16Expr(&expr, context);

    return createById(id, taskSize, bindSize);
    }

static void deleteTask(TASK* task)
    {
    if (task->prev != NULL)
        task->prev->next = task->next;
    else
        firstTask = task->next;
    if (task->next != NULL)
        task->next->prev = task->prev;
    taskCount--;
    free(task->context);
    free(task);
    }

static bool handleDeleteTask(int size, const byte *msg, CONTEXT *context)
    {
    byte *expr = (byte *) &msg[1];
    byte id = evalWord8Expr(&expr, context);
    TASK *task;

    if ((task = findTask(id)) != NULL)
        {
        deleteTask(task);
        }
    return false;
    }

static bool handleAddToTask(int size, const byte *msg, CONTEXT *context)
    {
    byte *expr = (byte *) &msg[1];
    byte id = evalWord8Expr(&expr, context);
    byte addSize = evalWord8Expr(&expr, context);
    const byte *data = expr;
    TASK *task;

    if ((task = findTask(id)) != NULL)
        {
        if (addSize + task->currLen <= task->size)
            {
            memcpy(&task->data[task->currLen], data, addSize);
            task->currLen += addSize;
            }
        }
    return false;
    }

static bool scheduleById(byte id, unsigned long deltaMillis)
    {
    TASK *task;

    if ((task = findTask(id)) != NULL)
        {
        task->millis = millis() + deltaMillis;
        task->ready = true;
        }
    return false;
    }

static bool handleScheduleTask(int size, const byte *msg, CONTEXT *context)
    {
    byte *expr = (byte *) &msg[1];
    byte id = evalWord8Expr(&expr, context);
    unsigned long deltaMillis = evalWord32Expr(&expr, context);
    return scheduleById(id, deltaMillis);
    }

static bool handleAttachInterrupt(int size, const byte *msg, CONTEXT *context)
    {
    byte *expr = (byte *) &msg[1];
    byte pin = evalWord8Expr(&expr, context);
    byte id = evalWord8Expr(&expr, context);
    byte mode = evalWord8Expr(&expr, context);
    byte intNum;
    TASK *task;
    void (*isr)(void);

    if ((intNum = digitalPinToInterrupt(pin)) < MAX_INTERRUPTS)
        {
        if ((task = findTask(id)) != NULL)
            {
            switch(intNum)
                {
                case 0:
                    isr = ISR0;
                    break;
                case 1:
                    isr = ISR1;
                    break;
                case 2:
                    isr = ISR2;
                    break;
                case 3:
                    isr = ISR3;
                    break;
                case 4:
                    isr = ISR4;
                    break;
                case 5:
                    isr = ISR5;
                    break;
                }
            intTasks[intNum] = task;
            attachInterrupt(intNum, isr, mode);
            }
        }
    return false;
    }

static bool handleDetachInterrupt(int size, const byte *msg, CONTEXT *context)
    {
    byte *expr = (byte *) &msg[1];
    byte pin = evalWord8Expr(&expr, context);
    byte intNum;

    if ((intNum = digitalPinToInterrupt(pin)) < MAX_INTERRUPTS)
        {
        detachInterrupt(intNum);
        intTasks[intNum] = NULL;
        }
    return false;
    }

static bool handleInterrupts(int size, const byte *msg, CONTEXT *context)
    {
    interrupts();
    return false;
    }

static bool handleNoInterrupts(int size, const byte *msg, CONTEXT *context)
    {
    noInterrupts();
    return false;
    }

static bool handleQuery(int size, const byte *msg, CONTEXT *context)
    {
    byte *expr = (byte *) &msg[2];
    byte id = evalWord8Expr(&expr, context);
    byte queryReply[10];
    uint16_t *sizeReply = (uint16_t *) queryReply;
    uint16_t *lenReply = (uint16_t *) &queryReply[2];
    uint16_t *posReply = (uint16_t *) &queryReply[4];
    uint32_t *millisReply = (uint32_t *) &queryReply[6];
    TASK *task;
    if ((task = findTask(id)) != NULL)
        {
        *sizeReply = task->size;
        *lenReply = task->currLen;
        *posReply = task->currPos;
        *millisReply = task->millis - millis();
        sendReply(sizeof(queryReply), SCHED_RESP_QUERY, queryReply, context, 0);
        }
    else
        {
        sendReply(0, SCHED_RESP_QUERY, queryReply, context, 0);
        }
    return false;
    }

static bool handleQueryAll(int size, const byte *msg, CONTEXT *context)
    {
    byte bind = msg[1];
    TASK *task = firstTask;
    int taskCount = getTaskCount();
    byte* localMem = (byte *) malloc(taskCount+3);
    byte* local = &localMem[3];
    int i = 0;

    if (!localMem)
        {
#ifdef DEBUG
        sendStringf("hQA: M");
#endif
        return false;
        }

    localMem[0] = EXPR_LIST8;
    localMem[0] = EXPR_LIT;

    while(task != NULL && i < taskCount)
        {
        *local++ = task->id;
        task = task->next;
        i++;
        }

    localMem[2] = i;

    if (context->currBlockLevel >= 0)
        {
        putBindListPtr(context, bind, localMem);
        }
    else
        {
        sendReply(i+3, SCHED_RESP_QUERY_ALL, localMem, context, bind);
        free(localMem);    
        }
    return false;
    }

static bool handleReset(int size, const byte *msg, CONTEXT *context)
    {
    while(firstTask != NULL)
        {
        deleteTask(firstTask);
        }
    runningTask = NULL;
    // Clear any stored task in EEPROM
    if (EEPROM[ 0 ] == 'H')
        {
        EEPROM[ 0 ] = 0;
        EEPROM[ 1 ] = 0;
        EEPROM[ 2 ] = 0;
        EEPROM[ 3 ] = 0;
        }
    return false;
    }

static bool handleBootTask(int size, const byte *msg, CONTEXT *context)
    {
    byte bind = msg[1];
    byte *expr = (byte *) &msg[2];
    bool alloc;
    byte *ids = evalList8Expr(&expr, context, &alloc);
    byte bootReply[3];
    byte status = 1;
    unsigned int index = BOOT_TASK_INDEX_START;
    unsigned int idsLen = ids[1];
    unsigned int taskCount = 0;

    /* Write the Magic pattern */
    EEPROM[ 0 ] = 'H';
    EEPROM[ 1 ] = 'A';
    EEPROM[ 2 ] = 'S';
    EEPROM[ 3 ] = 'K';

    for (unsigned int i=0; i<idsLen; i++)
        {
        TASK *task;
        byte id = ids[2+i];

        if ((task = findTask(id)) != NULL)
            {
            unsigned int taskBodyStart;
            uint32_t startTime;
            uint32_t now = millis();

            if (task->millis == 0 || task->millis < now)
                {
                startTime = 0;
                }
            else
                {
                startTime = now;
                }

            /* Write the task ID */
            EEPROM[ index++ ] = id;

            /* Write the length of the task */
            EEPROM[ index++ ] = task->currLen & 0xFF;
            EEPROM[ index++ ] = task->currLen >> 8;

            /* Write the number of binds in the task */
            EEPROM[ index++ ] = task->context->bindSize & 0xFF;
            EEPROM[ index++ ] = task->context->bindSize >> 8;

            /* Write the scheduled time of the task */
            EEPROM[ index++ ] = startTime & 0xFF;
            EEPROM[ index++ ] = (startTime >> 8) & 0xFF;
            EEPROM[ index++ ] = (startTime >> 16) & 0xFF;
            EEPROM[ index++ ] = startTime >> 24;            

            /* Write the body of the task */
            taskBodyStart = index;
            for (unsigned int i=0;i<task->currLen;i++,index++)
                {
                EEPROM[ index ] = task->data[i];
                }

            /* Validate body writing */
            index = taskBodyStart;
            for (unsigned int i=0;i<task->currLen;i++,index++)
                {
                if (EEPROM[ index ] != task->data[i])
                    status = 0;
                }
            }

            taskCount++;
        }

    /* Write the number of boot tasks */
    EEPROM[ 4 ] = taskCount;

    bootReply[0] = EXPR_BOOL;
    bootReply[1] = EXPR_LIT;
    bootReply[2] = status;

    sendReply(sizeof(bootReply), SCHED_RESP_BOOT_TASK, 
              bootReply, context, bind);

    if (alloc)
        free(ids);

    return false;
    }

// Critical Region global lock routines

static inline uint8_t lock()
    {
    uint8_t statReg = SREG;
    cli();
    return statReg;
    }

static inline void unlock(uint8_t statReg)
    {
    SREG = statReg;
    }

static bool handleTakeSem(int size, const byte *msg, CONTEXT *context)
    {
    byte *expr = (byte *) &msg[1];
    byte id = evalWord8Expr(&expr, context);

    if (id < NUM_SEMAPHORES)
        {
        uint8_t reg;

        reg = lock();
        // Semaphore is already full, take it and do not reschedule
        if (semaphores[id].full)
            {
            semaphores[id].full = false;
            unlock(reg);
            return false;
            }
        else
            // Semaphore is not full, we need to add ourselves to waiting
            // and reschedule
            {
            TASK *task = context->task;

            if (task)
                {
                semaphores[id].waiting = task;
                task->ready = false;
                }
            unlock(reg);
            return true;
            }
        }
    else
        {
        return false;
        }
    }

static bool handleGiveSem(int size, const byte *msg, CONTEXT *context)
    {
    byte *expr = (byte *) &msg[1];
    byte id = evalWord8Expr(&expr, context);

    if (id < NUM_SEMAPHORES)
        {
        uint8_t reg;

        reg = lock();
        // Semaphore is already full, do nothing
        if (semaphores[id].full)
            {
            }
        // Semaphore has a task waiting, ready it to run 
        else if (semaphores[id].waiting)
            {
            TASK* task = semaphores[id].waiting;

            task->ready = true;
            task->millis = millis();
            semaphores[id].waiting = NULL;
            }
        // Otherwise mark the semphore as full
        else
            {
            semaphores[id].full = true;
            }
        unlock(reg);
        }
        return false;
    }

void schedulerBootTask()
    {
    if (EEPROM[ 0 ] == 'H' && EEPROM[ 1 ] == 'A' &&
        EEPROM[ 2 ] == 'S' && EEPROM[ 3 ] == 'K')
        {
        TASK *task;
        unsigned int taskCount = EEPROM[ 4 ];
        unsigned int index = BOOT_TASK_INDEX_START;

        for (unsigned int t=0; t<taskCount; t++)
            {
            uint32_t low, high, midl, midh;
            uint16_t taskSize, bindSize;
            uint32_t taskMillis;
            byte id = EEPROM[ index++ ];

            low = EEPROM[ index++ ];
            high = EEPROM[ index++ ];
            taskSize = low | high << 8;
            low = EEPROM[ index++ ];
            high = EEPROM[ index++ ];
            bindSize = low | high << 8;
            low = EEPROM[ index++ ];
            midl = EEPROM[ index++ ];
            midh = EEPROM[ index++ ];
            high = EEPROM[ index++ ];
            taskMillis = low | midl << 8 | midh << 16 | high << 24;

            createById(id, taskSize, bindSize);
            task = findTask(id);
            for (unsigned int i=0;i<taskSize;i++,index++)
                {
                task->data[i] = EEPROM[ index ];
                }
            task->currLen = taskSize;           
            scheduleById(id, taskMillis);
            }
        }
    }

void schedulerRunTasks()
    {
    if (firstTask) 
        {
        unsigned long now = millis();
        TASK *current = firstTask;
        TASK *next = NULL;

        while (current) 
            {
            next = current->next;
            if (current->ready && 
                now - current->millis < 0x80000000UL)
                {
                runningTask = current;
                if (!runCodeBlock(current->currLen, 
                                  current->data, current->context))
                    {
                    deleteTask(current);
                    }
                runningTask = NULL;
                }
            current = next;
            }
        }
    }

bool isRunningTask()
    {
    return runningTask != NULL;
    }

void delayRunningTask(unsigned long ms)
    {
    runningTask->millis = millis() + ms; 
    }

static void handleISR(int intNum)
    {
    TASK *task = intTasks[intNum];

    if (task)
        {
        runCodeBlock(task->currLen, task->data, task->context);
        }
    }

static void ISR0(void)
    {
    handleISR(0);
    }

static void ISR1(void)
    {
    handleISR(1);
    }

static void ISR2(void)
    {
    handleISR(2);
    }

static void ISR3(void)
    {
    handleISR(3);
    }

static void ISR4(void)
    {
    handleISR(4);
    }

static void ISR5(void)
    {
    handleISR(5);
    }

