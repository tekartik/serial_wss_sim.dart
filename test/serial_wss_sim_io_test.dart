@TestOn('vm')

// Copyright (c) 2017, alex. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
import 'package:tekartik_web_socket_io/web_socket_io.dart';
import 'package:tekartik_serial_wss_client/constant.dart';
import 'package:tekartik_serial_wss_client/serial_wss_client.dart';
import 'package:tekartik_serial_wss_client/service/serial_wss_client_service.dart';
import 'package:tekartik_serial_wss_sim/serial_wss_sim.dart';
import 'package:test/test.dart';
import 'serial_wss_sim_test.dart';

void main() {
  testMain(webSocketChannelFactoryIo);

  group('serial_server_io', () {
    test('start_connect_and_close', () async {
      var server =
          await SerialServer.start(webSocketChannelFactoryIo.server, port: 0);
      //devPrint(server.url);

      var url = server.url; //'ws://localhost:${server.port}';
      //devPrint('URL: ${url}');
      var channel = webSocketChannelClientFactoryIo.connect<String>(url);
      //Serial.debug.on = true;
      var serial = Serial(channel);
      await serial.connected;
      await server.close();
    });

    test('options', () async {
      var server =
          await SerialServer.start(webSocketChannelFactoryIo.server, port: 0);
      //devPrint(server.port);
      var service = SerialWssClientService(webSocketChannelClientFactoryIo,
          url: getSerialWssUrl(port: server.port));
      service.start();
      await service.waitForConnected(true);

      var options = ConnectionOptions()..bitrate = 1234;
      var info = await service.serial
          .connect(serialWssSimMasterPortPath, options: options);
      expect(info.bitrate, 1234);
      await server.close();
    });
  });
}
