// Copyright (c) 2017, alex. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
import 'dart:async';

import 'package:tekartik_serial_wss_client/constant.dart';
import 'package:tekartik_serial_wss_client/message.dart' as swss;
import 'package:tekartik_serial_wss_client/serial_wss_client.dart';
import 'package:tekartik_serial_wss_client/service/serial_wss_client_service.dart';
import 'package:tekartik_serial_wss_sim/serial_wss_sim.dart';
import 'package:tekartik_web_socket/web_socket.dart';
import 'package:test/test.dart';

void main() {
  testMain(webSocketChannelFactoryMemory);
}

void testMain(WebSocketChannelFactory factory) {
  group('serial_server', () {
    test('start_connect_and_close', () async {
      var server = await SerialServer.start(factory.server, port: 0);
      //devPrint(server.port);

      //String url = 'ws://localhost:${server.port}';
      var channel = factory.client.connect(server.url);
      var serial = Serial(channel);
      await serial.connected;
      await server.close();
    });

    test('options', () async {
      //SerialServer.debug.on = true;
      var server = await SerialServer.start(factory.server, port: 0);
      //devPrint(server.port);
      var service = SerialWssClientService(factory.client, url: server.url);
      service.start();
      await service.waitForConnected(true);

      var options = ConnectionOptions()..bitrate = 1234;
      var info = await service.serial
          .connect(serialWssSimMasterPortPath, options: options);
      expect(info.bitrate, 1234);
      await server.close();
    });

    test('master_slave', () async {
      // Serial.debug.on = true;
      var server = await SerialServer.start(factory.server, port: 0);

      var service = SerialWssClientService(factory.client, url: server.url);
      service.start();

      var masterReceiveCompleter = Completer();
      var slaveReceiveCompleter = Completer();

      service.onConnected.listen((bool connected) async {
        if (connected) {
          var masterChannel =
              await service.serial.createChannel(serialWssSimMasterPortPath);
          var slaveChannel =
              await service.serial.createChannel(serialWssSimSlavePortPath);

          masterChannel.sink.add([1, 2, 3, 4]);
          slaveChannel.sink.add([5, 6, 7, 8]);

          masterChannel.stream.listen((List<int> data) {
            expect(data, [5, 6, 7, 8]);
            //print(data);
            masterReceiveCompleter.complete();
          });

          slaveChannel.stream.listen((List<int> data) {
            expect(data, [1, 2, 3, 4]);
            //print(data);
            slaveReceiveCompleter.complete();
          });
        }
      });

      await masterReceiveCompleter.future;
      await slaveReceiveCompleter.future;
      //await service.stop();
      await server.close();
    });

    test('busy', () async {
      var server = await SerialServer.start(factory.server, port: 0);

      var service = SerialWssClientService(factory.client, url: server.url);
      service.start();

      var completer = Completer();

      service.onConnected.listen((bool connected) async {
        if (connected) {
          // connect once ok
          await service.serial.connect(serialWssSimMasterPortPath);

          try {
            print(await service.serial.connect(serialWssSimMasterPortPath));
            fail('should fail');
          } on swss.Error catch (e) {
            expect(e.code, errorCodePortBusy);
          }
          completer.complete();
        }
      });

      await completer.future;
      //await service.stop();
      await server.close();
    });
  });
}
