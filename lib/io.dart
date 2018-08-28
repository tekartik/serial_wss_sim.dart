import 'dart:async';
import 'dart:convert';
import 'package:tekartik_web_socket_io/web_socket_io.dart';
import 'package:tekartik_serial_wss_sim/serial_wss_sim.dart';
import 'dart:io';

main() async {
  // ignore: deprecated_member_use
  // SerialServer.debug.on = true;
  SerialServer serialServer =
      await SerialServer.start(webSocketChannelFactoryIo.server);
  print("started: ${serialServer.deviceInfos}\n[q] [ENTER] to quit");
  StreamSubscription subscription;
  subscription = stdin
      .transform(utf8.decoder)
      .transform(new LineSplitter())
      .listen((data) {
    if (data == 'q') {
      print("stopping server...");
      serialServer.close();
      subscription.cancel();
    }
  });
}
