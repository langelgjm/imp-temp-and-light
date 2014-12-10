// seconds to wait before looping
nap <- 300

const ADT7410_UNIT_13 = 0.0625
const ADT7410_UNIT_16 = 0.0078

// Configure the Analog Devices ADT7410 temperature sensor
// Note: Imp I2C command values are strings with
// the \x escape character to indicate a hex value
// These constants define the address registers
const ADT7410_T_MSB = "\x00"
const ADT7410_T_LSB = "\x01"
const ADT7410_STATUS = "\x02"
const ADT7410_CONF = "\x03"
const ADT7410_T_HIGH_MSB = "\x04"
const ADT7410_T_HIGH_LSB = "\x05"
const ADT7410_T_LOW_MSB = "\x06"
const ADT7410_T_LOW_LSB = "\x07"
const ADT7410_T_CRIT_MSB = "\x08"
const ADT7410_T_CRIT_LSB = "\x09"
const ADT7410_T_HYST = "\x0A"
const ADT7410_ID = "\x0B"
const ADT7410_RESET = "\x2F"

// Configuration modes: continuous, one-shot mode, 1 sample per second, or off
const ADT7410_CONF_CON = "\x00"
const ADT7410_CONF_OSM = "\x20"
const ADT7410_CONF_SPS = "\x40"
const ADT7410_CONF_OFF = "\x60"
 
// Note: Imp I2C address values are integers
const ADT7410_ADDR_00 = 0x48 // A0 and A1 ground
const ADT7410_ADDR_01 = 0x49 // A0 ground, A1 Vdd
const ADT7410_ADDR_10 = 0x4A // A0 Vdd, A1 ground
const ADT7410_ADDR_11 = 0x4B // A0 and A1 Vdd

// DEFINE FUNCTIONS

// Pass a float, return it rounded
function round(n) {
    local f = math.floor(n)
    local r = n - f
    if (r >= 0.5) {
        return f + 1
    }
    else {
        return f
    }
}

function get_light()
{
    // Even though pin.read returns a 16 bit value, it is only accurate to 12 bits
    // Furthermore, with this crappy photoresistor, I'm only going to bother with 2 bits
    local light = photo.read()
    //local light_voltage = (light / 65536.0) * hardware.voltage()
    //server.log("Debug: Photo voltage = " + light_voltage)
    // Discard 14 LSB
    local temp = light >> 8
    server.log("Photoresistor 8 bit value = " + temp)
    light = light >> 14
    return light
}

// take num_readings of the light and return the average
function avg_light(num_readings, catnap) {
    local avg_light = 0.0
    for (local i = 0; i < num_readings; i += 1) {
        avg_light += get_light()
        imp.sleep(catnap)
    }
    return round(avg_light / num_readings)
}

// returns time string, -14400 is for -4 GMT (Montreal)
// use 3600 and multiply by the hours +/- GMT.
// e.g for +5 GMT local date = date(time()+18000, "u")
function get_datetime() {
    // return UNIX time in seconds, adjusted for timezone (but not daylight savings)
    // fix daylight savings and time zone stuff later
    local datetime = time()-18000
    return datetime
}

function format_datetime(datetime) {
    // return a formatted datetime string
    datetime = date(datetime)
    // for human readable printing
    local sec = format("%02u",datetime["sec"])
    local min = format("%02u",datetime["min"])
    local hour = format("%02u",datetime["hour"])
    local day = format("%02u",datetime["day"])
    // Remember to add 1 to the month so that it ranges from 1-12 instead of 0-11
    local month = datetime["month"]+1
    local year = datetime["year"]
    return year+"-"+month+"-"+day+" "+hour+":"+min+":"+sec
}

// Check status register to see if the temperature registers are ready to be read
function is_temp_rdy(i2c_addr) {
    local status = i2c_read(i2c_addr, ADT7410_STATUS, 1)
    // Discard all but MSB
    status = status[0] >> 7
    if (status) // check if MSB is 1, which means NOT ready
    {
        server.log("Error: temperature registers not ready.")
        return 0
    } else {
        return 1
    }     
}

function twos_complement_13_bit(t) {
    if (t & 0x1000) // check if MSB is 1
    {
        // Negative two's complement value
        // Negate the value, AND with 13 1s, and add 1; add a negative sign
        return -((~t & 0x1FFF) + 1)
    } else {
        // Positive value
        return t
    } 
}

// Try to read bytes from the specified I2C address and register
// On failure, report the error code
function i2c_read(i2c_addr, register, num_bytes) {
    local b = i2c.read(i2c_addr, register, num_bytes)
    if (b == null) {
        server.log("Error: I2C read error " + i2c.readerror())
        return null
    } else {
        return b
    }
}

// Return a table with manufacturer ID and silicon revision
function get_dev_id(i2c_addr) {
    local id = {}
    local b = i2c_read(i2c_addr, ADT7410_ID, 1)
    // top 5 bits indicate manufacturer ID
    id.manuf_id <- b[0] >> 3
    // lowest 3 bits indicate silicon revision
    id.si_rev <- b[0] & 0x07
    return id
}

// Return a byte with device configuration information
function get_dev_conf(i2c_addr) {
    local b = i2c_read(i2c_addr, ADT7410_CONF, 1)
    return b[0]
}

function read_13_bit_temp(i2c_addr) {
    local temp_raw
    if (is_temp_rdy(i2c_addr)) {
        // Return the number of ticks above/below 0 in ADT7410 13 bit increments
        local temp_msb = i2c_read(i2c_addr, ADT7410_T_MSB, 1)
        local temp_lsb = i2c_read(i2c_addr, ADT7410_T_LSB, 1)
        // Combine the two bytes into a word
        temp_raw = (temp_msb[0] << 8) + temp_lsb[0]
        // Discard 3 LSBs, which indicate threshold faults in 13 bit mode and are unused here
        temp_raw = temp_raw >> 3
        // Convert from a 13 bit integer to a celsius temperature
        temp_raw = twos_complement_13_bit(temp_raw)
    } else {
        temp_raw = 0
    }
    return temp_raw
}

function normal_temp_read(i2c_addr) {
    // configure in one sample per second mode
    i2c.write(i2c_addr, ADT7410_CONF + ADT7410_CONF_SPS)
    imp.sleep(0.5)
    // check if ready here
    local temp_raw
    // Return the number of ticks above/below 0 in ADT7410 13 bit increments
    temp_raw = read_13_bit_temp(i2c_addr)
    return temp_raw
}

function one_shot_temp_read(i2c_addr) {
    i2c.write(i2c_addr, ADT7410_CONF + ADT7410_CONF_OSM)
    // ADT7410 datasheet says to wait at least 240 ms after setting OSM before reading
    imp.sleep(0.5)
    local temp_raw
    // Return the number of ticks above/below 0 in ADT7410 13 bit increments
    temp_raw = read_13_bit_temp(i2c_addr)
    return temp_raw
}

function report_temp() {
    local temp_raw
    if (mode == 0) {
        temp_raw = normal_temp_read(i2c_addr)
    } else {
        temp_raw = one_shot_temp_read(i2c_addr)
    }
    
    local timestamp = get_datetime()
    
    //local light = avg_light(8, 0.125)
    local light = get_light()
    
    // multiply by 13 bit tick size
    local temp_c = temp_raw * ADT7410_UNIT_13
    local temp_f = temp_c * 1.8 + 32.0
    
    // What we send to the agent: UNIX time, temp in C, and raw light value
    local sensor_data = {
        timestamp = timestamp,
        temp = temp_c,
        light = light
    }
    
    server.log(format_datetime(timestamp) + " " + temp_f)
    server.log(sensor_data.timestamp + " " + sensor_data.temp)
    server.log("Photoresistor value = " + light)
    agent.send("new_reading", sensor_data)
    imp.wakeup(nap, report_temp)
}

// PROGRAM START POINT
photo <- hardware.pin5
photo.configure(ANALOG_IN)

// Set to desired I2C bus
i2c <- hardware.i2c12
i2c.configure(CLOCK_SPEED_100_KHZ)
// Set sensor's address by shifting 7-bit address 1 bit leftward as per imp I2C spec
i2c_addr <- ADT7410_ADDR_00 << 1
//i2c_addr <- 0x90
// 0 is one sample per second, anything else is one shot mode
mode <- 0

server.log(format("ADT7410 device address: 0x%02X", i2c_addr))
local id = get_dev_id(i2c_addr)
server.log("ADT7410 manufacturer ID: " + format("0x%02X", id.manuf_id))
server.log("ADT7410 silicon revision: " + format("0x%02X", id.si_rev))
report_temp()
