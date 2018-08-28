@TestOn("vm")
library _;

// Copyright (c) 2017, alex. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
import 'package:tekartik_serial_wss_client/channel/io.dart';
import 'package:tekartik_serial_wss_client/channel/web_socket_channel.dart';
import 'package:tekartik_serial_wss_client/constant.dart';
import 'package:tekartik_serial_wss_client/serial_wss_client.dart';
import 'package:tekartik_serial_wss_client/service/serial_wss_client_service.dart';
import 'package:tekartik_serial_wss_sim/serial_wss_sim.dart';
import 'package:test/test.dart';
import 'serial_wss_sim_test.dart';

void main() {
  test_main(ioWebSocketChannelFactory);

  group('serial_server_io', () {
    test('start_connect_and_close', () async {
      var server =
          await SerialServer.start(ioWebSocketChannelFactory.server, port: 0);
      //devPrint(server.url);

      String url = server.url; //"ws://localhost:${server.port}";
      //devPrint("URL: ${url}");
      WebSocketChannel channel = ioWebSocketChannelFactory.client.connect(url);
      //Serial.debug.on = true;
      Serial serial = new Serial(channel);
      await serial.connected;
      await server.close();
    });

    test('options', () async {
      var server =
          await SerialServer.start(ioWebSocketChannelFactory.server, port: 0);
      //devPrint(server.port);
      SerialWssClientService service = new SerialWssClientService(
          ioWebSocketChannelFactory.client,
          url: getSerialWssUrl(port: server.port));
      service.start();
      await service.waitForConnected(true);

      ConnectionOptions options = new ConnectionOptions()..bitrate = 1234;
      ConnectionInfo info = await service.serial
          .connect(serialWssSimMasterPortPath, options: options);
      expect(info.bitrate, 1234);
      await server.close();
    });
  });
}
