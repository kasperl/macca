// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

//MQTT needs these.
import monitor
import mqtt
import mqtt.packets as mqtt
import net
//import system.services
import ds18b20 show Ds18b20
import one_wire
import one_wire.family show FAMILY_DS18B20 family_id family_to_string
import gpio


HOST ::= "10.0.2.35"
PORT ::= 1883


TOPIC_PREFIX ::= "/HwsMonitor"
CLIENT_ID ::= "Hws-client"
GPIO_PIN_NUM ::= 26
devices := []

main:
  transport := mqtt.TcpTransport net.open --host=HOST --port=PORT
  client := mqtt.FullClient --transport=transport
  options := mqtt.SessionOptions --client_id=CLIENT_ID
  unsubscribed_latch := monitor.Latch
  task:: MEASURE_TEMPERATURE
  task:: MQTT client unsubscribed_latch

  // Wait for the client to be ready.
  // Note that the client can be used outside the `when_running` block, but
  // users should wait for the client to be ready before using it.
  // For example:
  // ```
  // client.when_running: null
  // client.subscribe ...
  // ```
  client.when_running:
    client.subscribe "$TOPIC_PREFIX/#"
    client.publish "$TOPIC_PREFIX/foo" "hello_world".to_byte_array
    client.publish "$TOPIC_PREFIX/bar" "hello_world".to_byte_array --qos=1
    client.unsubscribe "$TOPIC_PREFIX/#"

    // Wait for the confirmation that we have unsubscribed.
    unsubscribed_latch.get
    client.close

MQTT client/mqtt.FullClient unsubscribed_latch/monitor.Latch:
  client.handle: | packet /mqtt.Packet |
    // Send an ack back (for the packets that need it).
    // One should send acks as soon as possible, especially, if handling
    //   the packet could take time.
    // Note that the client may not send the ack if it is already closed.
    client.ack packet
    if packet is mqtt.PublishPacket:
      publish := packet as mqtt.PublishPacket
      print "Incoming: $publish.topic $publish.payload.to_string"
    else if packet is mqtt.SubAckPacket:
      print "Subscribed"
    else if packet is mqtt.UnsubAckPacket:
      unsubscribed_latch.set true
      print "Unsubscribed"
    else:
      print "Unknown packet of type $packet.type"

// ------------------------------------------------------------------

MEASURE_TEMPERATURE:
  while true:
    sleep --ms=1_000

    pin := gpio.Pin GPIO_PIN_NUM
    bus := one_wire.Bus pin
    // A broadcast device to address all devices on the bus.
    broadcast := Ds18b20.broadcast --bus=bus

    bus.do: | id/int |
      family := family_id --device_id = id
      if family != FAMILY_DS18B20:
        print """
          This example uses a broadcast device which only works if all
          devices on the bus are DS18B20 sensors.
          """
        throw "Wrong device family: $(family_to_string family)"
      devices.add (Ds18b20 --bus=bus --id=id)

    // Start a conversion on all devices.
    print "Starting a conversion on all devices."
    broadcast.do_conversion

    print "Reading the temperatures from the scratchpads."
    temperatures := []
    devices.do: | ds18b20/Ds18b20 |
      temperature := ds18b20.read_temperature_from_scratchpad
      temperatures.add temperature
      print "$(%x ds18b20.id): $(%.2f temperature) C"

    // Start a conversion on all devices.
    print "Starting a conversion on all devices."
    broadcast.do_conversion

    devices.do: it.close
    broadcast.close
    bus.close
    pin.close
