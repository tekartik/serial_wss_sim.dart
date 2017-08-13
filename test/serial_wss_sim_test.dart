// Copyright (c) 2017, alex. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
@TestOn("vm")
import 'dart:async';
import 'package:tekartik_common_utils/async_utils.dart';
import 'package:tekartik_serial_wss_sim/serial_wss_sim.dart';
import 'package:tekartik_serial_wss_client/constant.dart';
import 'package:tekartik_serial_wss_client/serial_wss_client.dart';
import 'package:tekartik_serial_wss_client/service/io.dart';
import 'package:tekartik_serial_wss_client/service/serial_wss_client_service.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  group('serial_server', () {
    test('start_connect_and_close', () async {
      var server = await SerialServer.start(port: 0);
      print(server.port);

      String url = "ws://localhost:${server.port}";
      IOWebSocketChannel channel = new IOWebSocketChannel.connect(url);
      Serial serial = new Serial(channel);
      await serial.connected;
      await server.close();
    });

    test('service', () async {
      var server = await SerialServer.start(port: 0);
      int port = server.port;
      await server.close();

      SerialWssClientService service = new SerialWssClientService(
          ioWebSocketChannelFactory,
          retryDelay: new Duration(milliseconds: 300),
          url: getSerialWssUrl(port: port));
      service.start();
      await Future.wait([
        () async {
          for (int i = 0; i < 50; i++) {
            await sleep(50);
            print("connected: ${service.isConnected}");
          }
        }(),
        () async {
          await sleep(500);
          expect(service.isConnected, isFalse);
          server = await SerialServer.start(port: port);
          await sleep(500);
          expect(service.isConnected, isTrue);
          print("closing server");
          await server.close();
          print("server closed");
          await sleep(500);
          expect(service.isConnected, isFalse);
          server = await SerialServer.start(port: port);
          await sleep(500);
          expect(service.isConnected, isTrue);
          await server.close();
        }(),
      ]);
    });
  });
}
