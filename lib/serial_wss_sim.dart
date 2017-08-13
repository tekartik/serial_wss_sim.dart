// Copyright (c) 2017, alex. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
import 'dart:io' hide sleep;
import 'dart:core' hide Error;
import 'package:tekartik_serial_wss_client/message.dart';
import 'package:tekartik_serial_wss_client/constant.dart';
import 'package:tekartik_serial_wss_client/serial_wss_client.dart';
import 'package:tekartik_test_menu/test_menu_io.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// version 0.1.0 as info
// version 0.2.0 has init support
// version 0.3.0 has support data in hex
Version version = new Version(0, 3, 0);

const nullModemPathA = "/null/a";
const nullModemPathB = "/null/b";
SerialServerConnection nullModemAChannel;
int nullModemAConnectionId;
SerialServerConnection nullModemBChannel;
int nullModemBConnectionId;

const errorCodeInvalidPath = 1;
const errorCodePortBusy = 2;
const errorCodeNotConnected = 3;
const errorCodeInvalidId = 4;
const errorCodeMethodNotSupported = 5;

class SerialServerConnection {
  final SerialServer serialServer;
  final int id;
  final WebSocketChannel _streamChannel;

  Map<int, String> connectedPaths = {};

  bool _checkConnectionId(int connectionId) {
    return connectedPaths.containsKey(connectionId);
  }

  bool _initReceived = false;

  // Set when closed
  bool _channelDisconnected = false;
  String _clientName;
  String _clientVersion;

  SerialServerConnection(this.serialServer, this.id, this._streamChannel) {
    print('connected');
    /*
    webSocketChannel.sink.add(JSON.encode({
      "jsonrpc": "2.0",
      "method": "info",
      "params": {
        "package": "com.tekartik.serial_wss_sim",
        "version": version.toString()
      }
    }));
    */
    sendMessage(new Notification(methodInfo, {
      "package": "com.tekartik.serial_wss_sim",
      "version": version.toString()
    }));

    // Wait for 10s for _initReceived or close the channel
    new Future.value().timeout(new Duration(seconds: 10), onTimeout: () {
      if (!_initReceived) {
        _markChannelDisconnected();
      }
    });
    _streamChannel.stream.listen((data) {
      print('recv[$id] $data');
      //webSocketChannel.sink.add("echo $message");
      Map<String, dynamic> map;
      try {
        map = parseJsonObject(data);
      } catch (e) {
        print(e);
      }

      map ??= {};

      try {
        Message message = Message.parseMap(map);
        if (message is Request) {
          if (!_initReceived) {
            if (message.method == methodInit) {
              Map params = message.params ?? {};
              _clientName = params["name"];
              _clientVersion = params["version"];
              _initReceived = true;
              print("client connected: $_clientName $_clientVersion");
              sendMessage(new Response(message.id, true));
            }
          } else {
            if (message.method == methodGetDevices) {
              // send: {jsonrpc: 2.0, id: 1, method: getDevices}
              // recv: {"jsonrpc":"2.0","id":1,"result":[{"path":"/null/a","productId":null,"displayName":"Null Model a->b"},{"path":"/null/b","productId":null,"displayName":"Null Model b->a"}]}

              var list = [];
              list.add((new DeviceInfo()
                    ..displayName = "Null Model a->b"
                    ..path = nullModemPathA)
                  .toMap());
              list.add((new DeviceInfo()
                    ..displayName = "Null Model b->a"
                    ..path = nullModemPathB)
                  .toMap());
              Response response = new Response(message.id, list);
              sendMessage(response);
            } else if (message.method == methodConnect) {
              // recv[4] {"jsonrpc":"2.0","id":2,"method":"connect","params":{"path":"/null/b"}}
              // send[1]: {jsonrpc: 2.0, id: 2, result: {connectionId: 1}}
              Map params = message.params ?? {};
              String path = params['path'];
              if (path == null) {
                sendMessage(new ErrorResponse(message.id,
                    new Error(errorCodeInvalidPath, "'path' cannot be null")));
                return;
              }

              // busy
              if (serialServer._connectedPathIds.containsKey(path)) {
                sendMessage(new ErrorResponse(message.id,
                    new Error(errorCodePortBusy, "busy path: $path")));
                return;
              }

              int connectionId = serialServer._generateNextId();

              if (path == nullModemPathA) {
                nullModemAChannel = this;
                nullModemAConnectionId = connectionId;
              } else if (path == nullModemPathB) {
                nullModemBChannel = this;
                nullModemBConnectionId = connectionId;
              } else {
                sendMessage(new ErrorResponse(message.id,
                    new Error(errorCodeInvalidPath, "invalid path: $path")));
                return;
              }
              sendMessage(
                  new Response(message.id, {'connectionId': connectionId}));

              serialServer._connectedPathIds[path] = connectionId;
              connectedPaths[connectionId] = path;
            } else if (message.method == methodDisconnect) {
              int connectionId = message.params['connectionId'];

              if (_checkConnectionId(connectionId)) {
                _markPortDisconnected(connectionId);
                sendMessage(new Response(message.id, true));
              } else {
                sendMessage(new ErrorResponse(
                    message.id,
                    new Error(
                        errorCodeInvalidId, "invalid id: $connectionId")));
              }

              // recv[4] {"jsonrpc":"2.0","id":4,"method":"disconnect","params":{"connectionId":1

            } else if (message.method == methodSend) {
              int connectionId = message.params['connectionId'];

              if (_checkConnectionId(connectionId)) {
                // send to other null modem?
                if (nullModemAChannel == this &&
                    nullModemAConnectionId == connectionId) {
                  if (nullModemBChannel != null) {
                    nullModemBChannel.sendMessage(new Notification(
                        methodReceive, {
                      'connectionId': nullModemBConnectionId,
                      'data': message.params['data']
                    }));
                  }
                } else if (nullModemBChannel == this &&
                    nullModemBConnectionId == connectionId) {
                  if (nullModemAChannel != null) {
                    nullModemAChannel.sendMessage(new Notification(
                        methodReceive, {
                      'connectionId': nullModemAConnectionId,
                      'data': message.params['data']
                    }));
                  }
                }
                sendMessage(new Response(message.id, {'bytesSent': 0}));
              } else {
                sendMessage(new ErrorResponse(
                    message.id,
                    new Error(
                        errorCodeInvalidId, "invalid id: $connectionId")));
              }
            } else {
              sendMessage(new ErrorResponse(
                  message.id,
                  new Error(errorCodeMethodNotSupported,
                      "method '${message.method}' not supported")));
            }
          }
        }
      } catch (e) {
        print("error receiving $e");
      }
    }, onDone: () {
      print('socket done [$id]');
      _markChannelDisconnected();
    });
  }

  void _markPortDisconnected(int connectionId) {
    String path = connectedPaths[connectionId];
    print('closing connection $connectionId $path');
    if (path == nullModemPathA) {
      nullModemAChannel = null;
    } else if (path == nullModemPathA) {
      nullModemBChannel = null;
    }
    if (path != null) {
      connectedPaths.remove(connectionId);
      serialServer._connectedPathIds.remove(path);
    }
  }

  void _markChannelDisconnected() {
    if (!_channelDisconnected) {
      _channelDisconnected = true;
      List<int> connectionIds = new List.from(connectedPaths.keys);
      for (int connectionId in connectionIds) {
        _markPortDisconnected(connectionId);
      }
      // remove ourself
      serialServer.channels.remove(this);
    }
  }

  void sendMessage(Message message) {
    Map msgMap = message.toMap();
    print("send[$id]: ${msgMap}");
    _streamChannel.sink.add(JSON.encode(msgMap));
    //webSocketChannel.sink.done
  }

  Future close() async {
    print("closing channel");
    await _streamChannel.sink.close();
  }

  toString() {
    return "channel-$id";
  }
}

class SerialServer {
  Map<String, int> _connectedPathIds = {};

  int get port => httpServer.port;

  int _generateNextId() {
    return ++lastId;
  }

  int lastId = 0;
  final HttpServer httpServer;

  List<SerialServerConnection> channels = [];

  SerialServer(this.httpServer);

  static Future<SerialServer> start({address, int port}) async {
    port ??= serialWssPortDefault;
    address ??= InternetAddress.ANY_IP_V6;
    HttpServer httpServer;

    SerialServer serialServer;

    var handler = webSocketHandler((WebSocketChannel webSocketChannel) {
      SerialServerConnection serverChannel = new SerialServerConnection(
          serialServer, ++serialServer.lastId, webSocketChannel);

      serialServer.channels.add(serverChannel);
      print("adding channel: ${serialServer.channels}");
    });

    httpServer = await shelf_io.serve(handler, address, port);
    serialServer =
        //new SerialServer(await shelf_io.serve(handler, 'localhost', 8988));
        new SerialServer(httpServer);
    print(
        'Serving at ws://${serialServer.httpServer.address.host}:${serialServer
            .httpServer.port}');
    return serialServer;
  }

  close() async {
    await httpServer.close(force: true);
    print("close channel: ${channels}");
    List<SerialServerConnection> connections = new List.from(channels);
    for (SerialServerConnection connection in connections) {
      await connection.close();
    }
  }
}
