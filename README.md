imp-temp-and-light
==================

Reports time, temperature, and light values from an Electric Imp and ADT7410

The [ADT7410](http://www.analog.com/en/mems-sensors/digital-temperature-sensors/adt7410/products/product.html) is a high-accuracy temperature sensor in a narrow SOIC package. Its ADC can output 13- and 16-bit temperature values. It has several operation modes, including continuous, one sample-per-second, and one-shot.

These device and agent nuts allow an [Electric Imp](https://electricimp.com/) (in this case, an imp001) to interface with the ADT7410 over the Imp's I2C bus. The device nut configures the ADT7410 for one-shot mode and 13-bit output (default), and gets temperature readings every 5 minutes. It also gets a 2 bit value from a photoresistor attached to one of the Imp's ADCs.

Both these values along with the time are logged and sent to the agent. The agent nut graphs the values using [Plotly](http://plot.ly). An example graph can be found [here](https://plot.ly/~langelgjm/29/temperature-and-light/).
