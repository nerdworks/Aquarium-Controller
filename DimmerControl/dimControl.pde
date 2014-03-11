#include <Wire.h>
#include <avr/eeprom.h>
#define RTC_ADDRESS 0x68

byte now[6]; // Index: 0=year, 1=month, 2=day, 3=hour, 4=minute, 5=second

uint8_t * heapptr, * stackptr; // Used by the check_mem function


/*************** Stuff to copy to main program ********************************/

#define maxAq 16 // Max number of aquariums

/* Datatype to use for variables stored in flash
 Reand only in runtime!!!!!
 See: http://www.arduino.cc/en/Reference/PROGMEM
 prog_char      - signed char (1 byte) -127 to 128
 prog_uchar     - unsigned char (1 byte) 0 to 255
 prog_int16_t   - signed int (2 bytes) -32.767 to 32.768
 prog_uint16_t  - unsigned int (2 bytes) 0 to 65.535
 prog_int32_t   - signed long (4 bytes) -2.147.483.648 to 2.147.483.647.
 prog_uint32_t  - unsigned long (4 bytes) 0 to 4.294.967.295
*/

// Start addresses of arrays stored in eeprom
#define timeShift_StartAddr 0          // int  - End addr = 16 aaquariums * 2 byte - 1 = 31. Next start address = 32
#define timeReduce_StartAddr 32        // byte - End addr = 16 + 31 = 47
#define fixedSunSet_StartAddr 48       // byte - End addr = 16 + 47 = 63
#define fixedSunRise_StartAddr 64      // byte - End addr = 16 + 63 = 79
#define fixedSunSetHour_StartAddr 80   // byte - End addr = 16 + 79 = 95
#define fixedSunSetMinute_StartAddr 96 // byte - End addr = 16 + 95 = 111
#define fadeMinutes_StartAddr 112      // byte - End addr = 16 + 111 = 127




// Make quasi two dimensional arrays in eeprom chip on I2C bus
// to store sunrise and sunset for each aquarium
int sunRiseArr[maxAq][365];
int sunSetArr[maxAq][365];

// Make array in internal eeprom to store values for each aquaruim
//int timeShift[maxAq]; // Minutes to shift time forward when fixed sunset if not used (may be negative)
//byte timeReduce[maxAq]; // percent reduction of sunMinutes
//byte fixedSunSet[maxAq]; // Turn fixed sunset on/off
//byte fixedSunRise[maxAq]; // Turn fixed sunrise on/off
//byte fixedSunSetHour[maxAq]; // sunSetHour if fixed sunset is set
//byte fixedSunSetMinute[maxAq]; // sunSetMinute if fixed sunset is set
//byte fadeMinutes[maxAq]; // Minutes used to fade light in and out



/*******************************************************************/
/******** Function bcd2dec *****************************************/
/*******************************************************************/
// Convert from BCD to DEC when reading from RTC
static byte bcd2dec (byte val) {
    return val - 6 * (val >> 4);
} /****** End bcd2dec **********************************************/
/*******************************************************************/

/*******************************************************************/
/******** Function getDate *****************************************/
/*******************************************************************/
// Fetch time and date from RTC clock
//Index 0=yy, 1=mm, 2=dd, 3=h, 4=m, 5=s
static void getDate (byte* buf) {
    Wire.beginTransmission(RTC_ADDRESS);
    Wire.send(0);
    Wire.endTransmission();
    Wire.requestFrom(RTC_ADDRESS, 7);
    buf[5] = bcd2dec(Wire.receive()); // s
    buf[4] = bcd2dec(Wire.receive()); // m
    buf[3] = bcd2dec(Wire.receive()); // h
    Wire.receive();
    buf[2] = bcd2dec(Wire.receive()); // dd
    buf[1] = bcd2dec(Wire.receive()); // mm
    buf[0] = bcd2dec(Wire.receive()); // yy
} /****** End getDate **********************************************/
/*******************************************************************/

/*******************************************************************/
/******** Function serialReader ************************************/
/*******************************************************************/
static void serialReader () {
/*
Function to read the serial port and take the appropriate action
Structure of serial communication from host computer
|----|---------|------|----|
| ID | Command | data | ID |
|----|---------|------|----|
The first and last byte of any serial communication from the connected computer is an ID byte (%).
The second byte is a command identifier. The command identifier dictates the length of the message.
Please note that there may be more then one message in queue....
*/

/*
Table of commands:
Comm Command   Action
Char int(DEC)       
a    97    Read fadeMinutes int for each aquarium
d          Run resetToDefaults function
F    70    Read fixedSunSet byte for each aquarium
f    102   Read fixedSunRise byte for each aquarium
H    72    Read fixedSunSetHour byte for each aquarium
h    104   Read fixedSunRiseHour byte for each aquarium
M    77    Read fixedSunSetMinute byte for each aquarium
m    109   Read fixedSunRiseMinute byte for each aquarium
R    82    Read sunRise arrays for each aquarium
r    114   Read timeReduce byte for each aquarium
S    83    Read sunSet arrays for each aquarium
s    115   Read timeShift int for each aquarium
T    84    Read RTC TimeSet unsigned long.
t    116   Read tempSet int for each aquarium
*/
    char ID = '%'; // All messages must start and end with this char.
    if (Serial.available()) {
        int i = 0;
        byte serialBuffer[50];
        while (Serial.available()) {
            serialBuffer[i] = Serial.read();
            // Stop reading the buffer when it has content and the first and last char is the ID.
            if (i > 1 && serialBuffer[0] == ID && serialBuffer[i] == ID) {
                break;
            }
            i++;
        }

        if (serialBuffer[0] == ID && serialBuffer[i] == ID) {
            // Data ok. Strip off the ID bytes and put message into a new array of the right size
            byte sb[i-1];
            int sbi;
            for (sbi = 0; sbi < (i - 1); sbi++) {
                sb[sbi] = serialBuffer[sbi + 1];
                //Serial.println(sb[sbi]); // See what is read into sb[]
                Serial.println(sbi); // Look at the bytecount
            }
            int value;
            unsigned int eaddr;
            
            switch (sb[0]) {
                case 'a':
                    Serial.print("fadeMinutes Command:  ");
                    if (i == 6) {
                        value = ((sb[2] - 48) * 100) + ((sb[3] - 48) * 10) + (sb[4] - 48);
                    }
                    if (i == 5) {
                        value = ((sb[2] - 48) * 10) + (sb[3] - 48);
                    }
                    if (i == 4) {
                        value = sb[2] - 48;
                    }
                    Serial.print("Aquarium No="); Serial.print(sb[1]);
                    Serial.print("  fadeMinutes="); Serial.print(value);
                    eaddr = fadeMinutes_StartAddr + (sb[1] - 48); 
                    eeprom_write_byte((unsigned byte *)eaddr, value);
                    Serial.print("  eeprom werify-read="); Serial.print(eeprom_read_byte((unsigned byte *)eaddr), DEC);
                    Serial.print("  eeprom address to write to="); Serial.println(eaddr);
                    break;
                case 'd':
                    // Add ability to reset single aquariums to resetToDefaults
                    if (sbi == 1) {
                        // No aquarium number supplied. Reset all
                        Serial.println("Reset All EEPROM To Defaults!");
                        resetToDefaults(254); // 254 = code to reset all
                    }
                    else {
                        Serial.print("Reset aquarium "); Serial.print(sb[1]); Serial.println(" To Defaults!");
                        resetToDefaults(sb[1]-48); // Reset single aquarium
                    }
                    break;
                case 'F': //fixedSunSet byte for each aquarium
                    if (sbi == 2) {
                        Serial.print("fixedSunSet Command: ");
                        value = sb[2] - 48;
                        if (value == 0) {
                            Serial.print("Off for aquarium "); Serial.print(sb[1]);
                        }
                            
                    }
                        
                    
                    break;    
                case 'T':
                    Serial.print("TimeSet Command: ");
                    // TimeSet Command Format: 100228234150 = 2010 feb 28 - 23:41:50
                    if (sbi == 13) {
                        Serial.println("data OK. Setting new time/date");
                        //setDate(sb);
                    }
                    else
                    {
                        Serial.println("Data fault. Exiting");
                    }
                    break;
                case 't':
                    Serial.println("TempSet Command");
                    break;
                default:
                    Serial.println("Unknown Serial Command");
                }
            }
        else
        { // Data NOT ok.
            Serial.println("Unknown Serial Signal");
        }  
    }
} /****** End serialReader *****************************************/
/*******************************************************************/

/*******************************************************************/
/******** Function resetToDefaults *********************************/
/*******************************************************************/
static void resetToDefaults (int aqNo) {
    // Write default arrays to eeprom
    int aqN = aqNo;
    if (aqN == 254) { // 254 = code to reset all aquariums
        for (int i = timeShift_StartAddr; i < 32; i++) {
            eeprom_write_word((unsigned int *)i, 0); 
        }
        for (int i = timeReduce_StartAddr; i < 48; i++) {
            eeprom_write_byte((unsigned byte *)i, 0); 
        }
        for (int i = fixedSunSet_StartAddr; i < 64; i++) {
            eeprom_write_byte((unsigned byte *)i, 0); 
        }
        for (int i = fixedSunRise_StartAddr; i < 80; i++) {
            eeprom_write_byte((unsigned byte *)i, 0); 
        }
        for (int i = fixedSunSetHour_StartAddr; i < 96; i++) {
            eeprom_write_byte((unsigned byte *)i, 0); 
        }
        for (int i = fixedSunSetMinute_StartAddr; i < 112; i++) {
            eeprom_write_byte((unsigned byte *)i, 0); 
        }
        for (int i = fadeMinutes_StartAddr; i < 128; i++) {
            eeprom_write_byte((unsigned byte *)i, 45); 
        }
    }
    else {
        eeprom_write_word((unsigned int *)timeShift_StartAddr + aqN, 0);
        eeprom_write_byte((unsigned byte *)timeReduce_StartAddr + aqN, 0);
        eeprom_write_byte((unsigned byte *)fixedSunSet_StartAddr + aqN, 0);
        eeprom_write_byte((unsigned byte *)fixedSunRise_StartAddr + aqN, 0);
        eeprom_write_byte((unsigned byte *)fixedSunSetHour_StartAddr + aqN, 0);
        eeprom_write_byte((unsigned byte *)fixedSunSetMinute_StartAddr + aqN, 0);
        eeprom_write_byte((unsigned byte *)fadeMinutes_StartAddr + aqN, 45);
    }
        

} /****** End resetToDefaults **************************************/
/*******************************************************************/




void setup () {
    Serial.begin(57600);
    Wire.begin();
    //if (eeprom_read_byte((unsigned byte *)1023) != 2) {
    //    resetToDefaults();
    // Mark eeprom as written
    //eeprom_write_byte((unsigned byte *) 1023, 2);
    //}
    
}


/////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////
void loop () {
    getDate(now);
    Serial.print("rtcTime: ");
    if (now[2]<10) {
        Serial.print("0");
    }
    Serial.print((int)now[2]); 
    Serial.print("/");
    if (now[1]<10) {
       Serial.print("0");
    } 
    Serial.print((int)now[1]);
    Serial.print("/"); 
    Serial.print(2000 + (int)now[0]);
    Serial.print(" ");
    if (now[3]<10) {
       Serial.print("0");
    } 
    Serial.print((int)now[3]); 
    Serial.print(":");
    if (now[4]<10) {
       Serial.print("0");
    } 
    Serial.print((int)now[4]);
    Serial.print(":");
    if (now[5]<10) {
        Serial.print("0");
    }
    Serial.print((int)now[5]);


    lightControl(0);
    serialReader();
    delay(1000);
    // check_mem();
} ///////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////


/********************************************************************/
/******** Function lightControl *************************************/
/********************************************************************/
void lightControl (int aqu) {  
 
    byte aq = aqu;    // aq is the aquarium to control
    
    int timeShift = eeprom_read_byte((unsigned byte *)timeShift_StartAddr + aq);; // Minutes to shift time forward when fixed sunset if not used (may be negative)
    byte timeReduce = eeprom_read_byte((unsigned byte *)timeReduce_StartAddr + aq);; // percent reduction of sunMinutes (0-100)
    byte fixedSunSet = eeprom_read_byte((unsigned byte *)fixedSunSet_StartAddr + aq);; // Turn fixed sunset on/off
    byte fixedSunSetHour = eeprom_read_byte((unsigned byte *)fixedSunSetHour_StartAddr + aq);;
    byte fixedSunSetMinute = eeprom_read_byte((unsigned byte *)fixedSunSetMinute_StartAddr + aq);;
    byte fadeMinutes = eeprom_read_byte((unsigned byte *)fadeMinutes_StartAddr + aq); // Minutes to fade in and out


    // Find day of the year
    int dayOfYear = (275 * now[1] / 9)-(((now[1] + 9) / 12)* 1 + ((now[0] - 4 * (now[0] / 4) + 2) / 3))+ now[2] - 30;
    // Serial.print("  dayOfYear="); Serial.println(dayOfYear);


    //int sunRise = sunRiseArr[aq][dayOfYear]; // Brukes når arrayet er på plass
    //int sunSet = sunSetArr[aq][dayOfYear]; // Brukes når arrayet er på plass
    int sunRise = 493; //08:13
    int sunSet = 1106; //18:26
    // 23:00 = 1380

    // Handle reduced length of day.
    sunRise = sunRise + (sunRise * timeReduce / 100);
    sunSet = sunSet - (sunSet * timeReduce / 100);

    int sunMinutes;
    sunMinutes = sunSet - sunRise;
    //Serial.print("   sunMinutes= "); Serial.print(sunMinutes);

    boolean sunPastMidnight = 0;
    // Adjust sunrise if fixed sunset time is set
    if (fixedSunSet == 0) {
        if (sunSet + timeShift > 1440) { // Bruk sunSetArr[aq][dayOfYear - 1] + timeShift
            sunPastMidnight = 1;
            sunSet = sunSet - 1440;
        }
        sunRise = sunRise + timeShift;
        sunSet = sunSet + timeShift;
    }
    else
    {
        sunSet = (fixedSunSetHour * 60) + fixedSunSetMinute;
        if (sunSet < sunMinutes) {
            sunPastMidnight = 1;
            sunRise = 1440 + sunSet - sunMinutes;
        }
        else
        {
            sunRise = sunSet - sunMinutes;
        }
    }


    //unsigned int fadeSec = fadeMinutes[aq] * 60;
    unsigned int fadeSec = (unsigned int)fadeMinutes * 60;

    // Convert sunRise and sunSet from minutes to seconds to obtain better granularity for short fadeMinutes
    long sunRiseSec = (long)sunRise * 60;
    long sunSetSec = (long)sunSet * 60;
    long nowSec = (long)now[3] * 3600 + (long)now[4] * 60 + (long)now[5];

    int lightLevel;

    boolean sunRiseNextEvent;
    // For sunRise
    // Er dette lurt?
    // Er det bedre å skifte midt i mellom rise og set og midt i mellom set og rise,
    // og samtidig ta hensyn til sun past midnight?
    // Da er vi uavhengige av at skifte fra 0 til 1 foregår ved midnatt.
    lightLevel = ((nowSec - sunRiseSec) * 255) / fadeSec;
    //Serial.print("\nTest="); Serial.println(lightLevel);
    sunRiseNextEvent = 1;
    // Find if next upcoming event is sunRise or sunSet
    if (lightLevel > 255) {
        // Next event is sunSet
        sunRiseNextEvent = 0;
        if (sunPastMidnight == 1) {
            lightLevel = (((sunSetSec + 86400) - nowSec) * 255) / fadeSec;
        }
        else {
            lightLevel = ((sunSetSec - nowSec) * 255) / fadeSec;
        }
    }

    // Handle sun past midnight
    // Just need to handle fading that starts before midnight and ends after midnight.
    // Fading after midnight seems ok.
    if (sunPastMidnight == 1 && fadeSec - sunSetSec > 0) {
        //Serial.println("\n Fading starts before midnight and end after.");
        if (nowSec <= 86400 && nowSec >= (86400 - (fadeSec - sunSetSec))) {
            //Serial.println("\n Fading started, and it is still not midnight");
            lightLevel = (((sunSetSec + 86400) - nowSec) * 255) / fadeSec;
        }
    }

    // Avoid lightlevels below 0 and above 255
    int lightLevelRaw = lightLevel; // For debugging
    if ( lightLevel > 255) {
        lightLevel = 255;
    }
    if (lightLevel < 0) {
        lightLevel = 0;
    }


    Serial.print("  sunRiseSec="); 
    Serial.print(sunRiseSec);
    Serial.print("  nowSec="); 
    Serial.print(nowSec);
    Serial.print("  sunSetSec="); 
    Serial.print(sunSetSec);
    Serial.print("  fadeSec="); 
    Serial.print(fadeSec);
    Serial.print("  sunRiseNextEvent="); 
    Serial.print((int)sunRiseNextEvent);
    Serial.print("  lightLevelRaw="); 
    Serial.print(lightLevelRaw);
    Serial.print("  Light Level="); 
    Serial.print(lightLevel);
    //Serial.print("  Free Mem="); Serial.print(stackptr - heapptr);
    Serial.println();

} /****** End lightControl *****************************************/
/*******************************************************************/

/********************************************************************/
/******** Function check_mem ****************************************/
/********************************************************************/
void check_mem() {
    stackptr = (uint8_t *)malloc(4);          // use stackptr temporarily
    heapptr = stackptr;                     // save value of heap pointer
    free(stackptr);      // free up the memory again (sets stackptr to 0)
    stackptr =  (uint8_t *)(SP);           // save value of stack pointer
} /****** End check_mem ********************************************/
/*******************************************************************/




