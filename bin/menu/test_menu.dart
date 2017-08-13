import 'dart:io';
import 'package:tekartik_test_menu/test_menu_io.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Version version = new Version(0, 1, 0);

main(List<String> args) async {
  mainMenu(args, () {
    menu('main', () {
      item("write hola", () async {
        write('Hola');
      }, cmd: "a");
      item("echo prompt", () async {
        write('RESULT prompt: ${await prompt()}');
      });
      item("print hi", () {
        print('hi');
      });
      menu('sub', () {
        item("print hi", () => print('hi'));
      }, cmd: 's');
    });

    menu('wss', () {
      HttpServer httpServer;
      item("server", () async {
        if (httpServer == null) {
          var handler = webSocketHandler((WebSocketChannel webSocketChannel) {
            write('connected');
            webSocketChannel.sink.add(JSON.encode({
              "jsonrpc": "2.0",
              "method": "info",
              "params": {
                "package": "com.tekartik.serial_wss_sim",
                "version": version.toString()
              }
            }));
            webSocketChannel.stream.listen((message) {
              webSocketChannel.sink.add("echo $message");
            }, onDone: () {
              write('socket done');
            });
          });

          httpServer = await shelf_io.serve(handler, 'localhost', 8080);
          write(
              'Serving at ws://${httpServer.address.host}:${httpServer.port}');
        }
      });
      item("stop", () async {
        if (httpServer != null) {
          await httpServer.close(force: true);
          httpServer = null;
          write('server stopped');
        }
      });
    });
  });
}
