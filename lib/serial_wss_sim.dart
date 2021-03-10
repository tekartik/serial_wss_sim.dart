// Copyright (c) 2017, alex. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
import 'dart:core' hide Error;

import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_serial_wss_client/constant.dart';
import 'package:tekartik_serial_wss_client/message.dart';
import 'package:tekartik_serial_wss_client/serial_wss_client.dart';
import 'package:tekartik_web_socket/web_socket.dart';

// version 0.1.0 as info
// version 0.2.0 has init support
// version 0.3.0 has support data in hex
// version 0.5.0 has busy support on real server
Version version = Version(0, 5, 0);

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
      'jsonrpc': '2.0',
      'method': 'info',
      'params': {
        'package': 'com.tekartik.serial_wss_sim',
        'version': version.toString()
      }
    }));
    */
    sendMessage(Notification(methodInfo, {
      'package': 'com.tekartik.serial_wss_sim',
      'version': version.toString()
    }));

    // Wait for 10s for _initReceived or close the channel
    Future.value().timeout(Duration(seconds: 10), onTimeout: () {
      if (!_initReceived) {
        _markChannelDisconnected();
      }
    });
    _streamChannel.stream.listen((data) {
      if (SerialServer.debug.on) {
        print('recv[$id] $data');
      }
      //webSocketChannel.sink.add('echo $message');
      Map<String, dynamic> map;
      try {
        map = parseJsonObject(data as String);
      } catch (e) {
        print(e);
      }

      map ??= {};

      try {
        var message = Message.parseMap(map);
        if (message is Request) {
          if (!_initReceived) {
            if (message.method == methodInit) {
              var params = (message.params as Map) ?? {};
              _clientName = params['name'] as String;
              _clientVersion = params['version'] as String;
              _initReceived = true;
              if (SerialServer.debug.on) {
                print('client connected: $_clientName $_clientVersion');
              }
              sendMessage(Response(message.id, true));
            }
          } else {
            if (message.method == methodGetDevices) {
              // send: {jsonrpc: 2.0, id: 1, method: getDevices}
              // recv: {'jsonrpc':'2.0','id':1,'result':[{'path':'/null/a','productId':null,'displayName':'Null Model a->b'},{'path':'/null/b','productId':null,'displayName':'Null Model b->a'}]}
              var list = [];
              for (var deviceInfo in serialServer.deviceInfos) {
                list.add(deviceInfo.toMap());
              }
              var response = Response(message.id, list);
              sendMessage(response);
            } else if (message.method == methodConnect) {
              // recv[4] {'jsonrpc':'2.0','id':2,'method':'connect','params':{'path':'/null/b'}}
              // send[1]: {jsonrpc: 2.0, id: 2, result: {connectionId: 1}}
              var params = (message.params as Map) ?? {};
              final path = params['path']?.toString();
              if (path == null) {
                sendMessage(ErrorResponse(message.id,
                    Error(errorCodeInvalidPath, "'path' cannot be null")));
                return;
              }

              // busy
              if (serialServer._connectedPathIds.containsKey(path)) {
                sendMessage(ErrorResponse(
                    message.id, Error(errorCodePortBusy, 'busy path: $path')));
                return;
              }

              var connectionId = serialServer._generateNextId();

              if (path == serialWssSimMasterPortPath) {
                masterChannel = this;
                masterConnectionId = connectionId;
              } else if (path == serialWssSimSlavePortPath) {
                slaveChannel = this;
                slaveConnectionId = connectionId;
              } else {
                sendMessage(ErrorResponse(message.id,
                    Error(errorCodeInvalidPath, 'invalid path: $path')));
                return;
              }
              var connectionInfo = (params['options'] as Map) ?? {};
              // copy connection info from options;
              connectionInfo['connectionId'] = connectionId;
              sendMessage(Response(message.id, connectionInfo));

              serialServer._connectedPathIds[path] = connectionId;
              connectedPaths[connectionId] = path;
            } else if (message.method == methodDisconnect) {
              final connectionId = message.params['connectionId'] as int;

              if (_checkConnectionId(connectionId)) {
                _markPortDisconnected(connectionId);
                sendMessage(Response(message.id, true));
              } else {
                sendMessage(ErrorResponse(message.id,
                    Error(errorCodeInvalidId, 'invalid id: $connectionId')));
              }

              // recv[4] {'jsonrpc':'2.0','id':4,'method':'disconnect','params':{'connectionId':1

            } else if (message.method == methodSend) {
              final connectionId = message.params['connectionId'] as int;

              var hasPipe = false;
              if (_checkConnectionId(connectionId)) {
                // send to other null modem?
                if (masterChannel == this &&
                    masterConnectionId == connectionId) {
                  if (slaveChannel != null) {
                    hasPipe = true;
                    slaveChannel.sendMessage(Notification(methodReceive, {
                      'connectionId': slaveConnectionId,
                      'data': message.params['data']
                    }));
                  }
                } else if (slaveChannel == this &&
                    slaveConnectionId == connectionId) {
                  if (masterChannel != null) {
                    hasPipe = true;
                    masterChannel.sendMessage(Notification(methodReceive, {
                      'connectionId': masterConnectionId,
                      'data': message.params['data']
                    }));
                  }
                }
                sendMessage(Response(message.id, {
                  'bytesSent': hasPipe ? message.params['data'].length ~/ 2 : 0
                }));
              } else {
                sendMessage(ErrorResponse(message.id,
                    Error(errorCodeInvalidId, 'invalid id: $connectionId')));
              }
            } else {
              sendMessage(ErrorResponse(
                  message.id,
                  Error(errorCodeMethodNotSupported,
                      "method '${message.method}' not supported")));
            }
          }
        }
      } catch (e) {
        print('error receiving $e');
      }
    }, onDone: () {
      if (SerialServer.debug.on) {
        print('socket done [$id]');
      }
      _markChannelDisconnected();
    });
  }

  void _markPortDisconnected(int connectionId) {
    var path = connectedPaths[connectionId];
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
      var connectionIds = List<int>.from(connectedPaths.keys);
      for (var connectionId in connectionIds) {
        _markPortDisconnected(connectionId);
      }
      // remove ourself
      serialServer.channels.remove(this);
    }
  }

  void sendMessage(Message message) {
    Map msgMap = message.toMap();
    if (SerialServer.debug.on) {
      print('send[$id]: ${json.encode(msgMap)}');
    }
    _streamChannel.sink.add(json.encode(msgMap));
    //webSocketChannel.sink.done
  }

  Future close() async {
    if (SerialServer.debug.on) {
      print('closing channel');
    }
    await _streamChannel.sink.close();
  }

  @override
  String toString() {
    return 'channel-$id';
  }
}

abstract class SerialServerFactory {
  Future start({address, int port});
}

class SerialServer {
  // Set to true to get debug logs
  static DevFlag debug = DevFlag('SerialService.debug');

  final WebSocketChannelServer _wsServer;

  SerialServer._(this._wsServer) {
    _wsServer.stream.listen((WebSocketChannel webSocketChannel) {
      var serverChannel =
          SerialServerConnection(this, ++lastId, webSocketChannel);

      channels.add(serverChannel);
      if (SerialServer.debug.on) {
        print('[SerialServer] adding channel: $channels');
      }
    });
  }

  static Future<SerialServer> start(WebSocketChannelServerFactory factory,
      {address, int port}) async {
    // default port
    port ??= serialWssPortDefault;

    var serialServer =
        SerialServer._(await factory.serve(address: address, port: port));
    if (debug.on) {
      print('[SerialServer] serving $serialServer');
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

  final _connectedPathIds = <String, int>{};

  List<DeviceInfo> get deviceInfos {
    var list = <DeviceInfo>[];
    list.add(DeviceInfo()
      ..displayName = 'Master'
      ..path = serialWssSimMasterPortPath);
    list.add(DeviceInfo()
      ..displayName = 'Slave'
      ..path = serialWssSimSlavePortPath);
    return list;
  }

  Future close() async {
    await _wsServer.close();
    if (SerialServer.debug.on) {
      print('[SerialServer] close channel: $channels');
    }
    var connections = List<SerialServerConnection>.from(channels);
    for (var connection in connections) {
      await connection.close();
    }
  }

  @override
  String toString() => 'WssSerialSim $url';
}
