import 'package:tekartik_serial_wss_sim/serial_wss_sim.dart';
import 'package:tekartik_serial_wss_sim/io.dart' as io;

Future main() async {
  // ignore: deprecated_member_use
  SerialServer.debug.on = true;
  await io.main();
}
