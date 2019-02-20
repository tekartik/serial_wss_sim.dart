import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tekartik_serial_wss_sim/serial_wss_sim.dart';
import 'package:tekartik_web_socket_io/web_socket_io.dart';

Future main() async {
  // ignore: deprecated_member_use
  // SerialServer.debug.on = true;
  SerialServer serialServer =
      await SerialServer.start(webSocketChannelFactoryIo.server);
  print("started: ${serialServer.deviceInfos}\n[q] [ENTER] to quit");
  StreamSubscription subscription;
  subscription = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((data) {
    if (data == 'q') {
      print("stopping server...");
      serialServer.close();
      subscription.cancel();
    }
  });
}
