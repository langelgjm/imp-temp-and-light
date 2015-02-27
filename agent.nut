function format_datetime(datetime) {
    // return a formatted datetime string
    datetime = date(datetime)
    // for human readable printing
    local sec = format("%02u",datetime["sec"])
    local min = format("%02u",datetime["min"])
    local hour = format("%02u",datetime["hour"])
    local day = format("%02u",datetime["day"])
    // Remember to add 1 to the month so that it ranges from 1-12 instead of 1-11
    local month = datetime["month"]+1
    local year = datetime["year"]
    return year+"-"+month+"-"+day+" "+hour+":"+min+":"+sec
}

// When Device sends new readings, Run this!
device.on("new_reading" function(sensor_data) {
    
    // Convert from UNIX time to human and plotly readable format
    local unixtime = sensor_data.timestamp
    sensor_data.timestamp = format_datetime(sensor_data.timestamp)
    // Convert from Celsius to Fahrenheit
    sensor_data.temp = sensor_data.temp * 1.8 + 32.0
    // Change raw light value to a proportion
    //sensor_data.light = sensor_data.light / 4.0
    
    //[{"x": [0, 1, 2], "y": [3, 1, 6], "name": "Experimental", "marker": {"symbol": "square", "color": "purple"}}, {"x": [1, 2, 3], "y": [3, 4, 5], "name": "Control"}]
    
    //Plotly Data Object
    local data = [{
        x = sensor_data.timestamp,
        y = sensor_data.temp,
        name = "Temperature (F)"
    }]
    
    local data2 = [{
        x = sensor_data.timestamp,
        y = sensor_data.light,
        name = "Light",
        yaxis = "y2"
    }]
    
    data.extend(data2)
    //data.extend(data2)

    // make Plotly's x_range the last two days (48 hours); Plotly needs milliseconds
    server.log(unixtime)
    local x_range = array(2)
    x_range[0] = (unixtime-(48*3600)).tostring()+"000"
    x_range[1] = unixtime.tostring()+"000"
    server.log(x_range[0])
    server.log(x_range[1])

    // Plotly Layout Object
    local layout = {
        fileopt = "extend",
        filename = "temp-and-light",
        //traces = [0, 1],
        //{"title": "my plot title", "xaxis": {"name": "Time (ms)"}, "yaxis": {"name": "Voltage (mV)"}}
        layout = {
            "xaxis": {"title": "Date and Time", "range": x_range},
            "yaxis": {"title": "Temperature (F)", "range": [-25, 125]} ,
            "yaxis2": {"title": "Light", "range": [-1, 5], "side": "right", "overlaying": "y"},
            "title": "Temperature and Light"
        }
    }

    // Setting up Data to be POSTed
    local payload = {
    // Put your plotly username here
    un = "",
    // Put your plotly API key here
    key = "",
    origin = "plot",
    platform = "electricimp",
    args = http.jsonencode(data),
    kwargs = http.jsonencode(layout)
    }

    // encode data and log
    local headers = { "Content-Type" : "application/json" }
    local body = http.urlencode(payload)
    local url = "https://plot.ly/clientresp"
    HttpPostWrapper(url, headers, body, true)
    
    //server.log(payload.args)
    //server.log(payload.kwargs)
})


// Http Request Handler
function HttpPostWrapper (url, headers, string, log) {
  local request = http.post(url, headers, string)
  local response = request.sendsync()
  if (log)
    server.log(http.jsonencode(response))
  return response
}
