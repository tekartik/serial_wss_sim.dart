// Copyright (c) 2017, alex. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
import 'dart:core' hide Error;
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_web_socket/web_socket.dart';
import 'package:tekartik_serial_wss_client/message.dart';
import 'package:tekartik_serial_wss_client/constant.dart';
import 'package:tekartik_serial_wss_client/serial_wss_client.dart';

// version 0.1.0 as info
// version 0.2.0 has init support
// version 0.3.0 has support data in hex
// version 0.5.0 has busy support on real server
Version version = new Version(0, 5, 0);

SerialServerConnection masterChannel;
int masterConnectionId;
SerialServerConnection slaveChannel;
int slaveConnectionId;

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
    if (SerialServer.debug.on) {
      print('[SerialServerConnection] connected');
    }
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
      if (SerialServer.debug.on) {
        print('recv[$id] $data');
      }
      //webSocketChannel.sink.add("echo $message");
      Map<String, dynamic> map;
      try {
        map = parseJsonObject(data as String);
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
              _clientName = params["name"] as String;
              _clientVersion = params["version"] as String;
              _initReceived = true;
              if (SerialServer.debug.on) {
                print("client connected: $_clientName $_clientVersion");
              }
              sendMessage(new Response(message.id, true));
            }
          } else {
            if (message.method == methodGetDevices) {
              // send: {jsonrpc: 2.0, id: 1, method: getDevices}
              // recv: {"jsonrpc":"2.0","id":1,"result":[{"path":"/null/a","productId":null,"displayName":"Null Model a->b"},{"path":"/null/b","productId":null,"displayName":"Null Model b->a"}]}
              var list = [];
              for (DeviceInfo deviceInfo in serialServer.deviceInfos) {
                list.add(deviceInfo.toMap());
              }
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

              if (path == serialWssSimMasterPortPath) {
                masterChannel = this;
                masterConnectionId = connectionId;
              } else if (path == serialWssSimSlavePortPath) {
                slaveChannel = this;
                slaveConnectionId = connectionId;
              } else {
                sendMessage(new ErrorResponse(message.id,
                    new Error(errorCodeInvalidPath, "invalid path: $path")));
                return;
              }
              Map connectionInfo = params['options'] ?? {};
              // copy connection info from options;
              connectionInfo['connectionId'] = connectionId;
              sendMessage(new Response(message.id, connectionInfo));

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

              bool hasPipe = false;
              if (_checkConnectionId(connectionId)) {
                // send to other null modem?
                if (masterChannel == this &&
                    masterConnectionId == connectionId) {
                  if (slaveChannel != null) {
                    hasPipe = true;
                    slaveChannel.sendMessage(new Notification(methodReceive, {
                      'connectionId': slaveConnectionId,
                      'data': message.params['data']
                    }));
                  }
                } else if (slaveChannel == this &&
                    slaveConnectionId == connectionId) {
                  if (masterChannel != null) {
                    hasPipe = true;
                    masterChannel.sendMessage(new Notification(methodReceive, {
                      'connectionId': masterConnectionId,
                      'data': message.params['data']
                    }));
                  }
                }
                sendMessage(new Response(message.id, {
                  'bytesSent': hasPipe ? message.params['data'].length ~/ 2 : 0
                }));
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
      if (SerialServer.debug.on) {
        print('socket done [$id]');
      }
      _markChannelDisconnected();
    });
  }

  void _markPortDisconnected(int connectionId) {
    String path = connectedPaths[connectionId];
    if (SerialServer.debug.on) {
      print('closing connection $connectionId $path');
    }
    if (path == serialWssSimMasterPortPath) {
      masterChannel = null;
    } else if (path == serialWssSimSlavePortPath) {
      slaveChannel = null;
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
    if (SerialServer.debug.on) {
      print("send[$id]: ${json.encode(msgMap)}");
    }
    _streamChannel.sink.add(json.encode(msgMap));
    //webSocketChannel.sink.done
  }

  Future close() async {
    if (SerialServer.debug.on) {
      print("closing channel");
    }
    await _streamChannel.sink.close();
  }

  toString() {
    return "channel-$id";
  }
}

abstract class SerialServerFactory {
  Future start({address, int port});
}

class SerialServer {
  // Set to true to get debug logs
  static DevFlag debug = new DevFlag("SerialService.debug");

  final WebSocketChannelServer _wsServer;

  SerialServer._(this._wsServer) {
    _wsServer.stream.listen((WebSocketChannel webSocketChannel) {
      SerialServerConnection serverChannel =
          new SerialServerConnection(this, ++lastId, webSocketChannel);

      channels.add(serverChannel);
      if (SerialServer.debug.on) {
        print("[SerialServer] adding channel: ${channels}");
      }
    });
  }

  static Future<SerialServer> start(WebSocketChannelServerFactory factory,
      {address, int port}) async {
    // default port
    port ??= serialWssPortDefault;

    SerialServer serialServer =
        new SerialServer._(await factory.serve(address: address, port: port));
    if (debug.on) {
      print("[SerialServer] serving $serialServer");
    }
    return serialServer;
  }

  // get the server url
  String get url => _wsServer.url;
  int get port => _wsServer.port;

  List<SerialServerConnection> channels = [];

  int _generateNextId() {
    return ++lastId;
  }

  int lastId = 0;

  Map<String, int> _connectedPathIds = {};

  List<DeviceInfo> get deviceInfos {
    var list = <DeviceInfo>[];
    list.add(new DeviceInfo()
      ..displayName = "Master"
      ..path = serialWssSimMasterPortPath);
    list.add(new DeviceInfo()
      ..displayName = "Slave"
      ..path = serialWssSimSlavePortPath);
    return list;
  }

  Future close() async {
    await _wsServer.close();
    if (SerialServer.debug.on) {
      print("[SerialServer] close channel: ${channels}");
    }
    List<SerialServerConnection> connections = new List.from(channels);
    for (SerialServerConnection connection in connections) {
      await connection.close();
    }
  }

  toString() => "WssSerialSim $url";
}
