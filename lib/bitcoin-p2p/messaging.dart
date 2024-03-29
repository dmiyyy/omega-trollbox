// Copyright (c) 2021 Kolby Moroz Liebl
// Distributed under the MIT software license, see the accompanying
// file LICENSE or http://www.opensource.org/licenses/mit-license.php.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'util.dart';
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';

// global vars used for testing
List<int> ipExample = [0xc6, 0x1b, 0x64, 0x09];
List<int> test = [0x76, 0x65, 0x72, 0x73, 0x69, 0x6F, 0x6E, 0x00, 0x00, 0x00, 0x00, 0x00];
List<int> heightt = [0x55, 0x81, 0x01, 0x00];

// Actually use global vars
const int DEFAULT_PORT = 7777;
List<int> IPV4_COMPAT = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff];
List<int> magic = [0xbf, 0x0c, 0x6b, 0xbd];
Map<String, int> nodeList = Map<String, int>();
List<MessageNodes> nodes = [];
Map<List<int>, CAnonMsg> mapAnonMsg = Map<List<int>, CAnonMsg>();
ServerSocket server;
const String CHARS_ALPHA_NUM = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,;-_/:?@()";


// Message Types
String version = "version";
String verack = "verack";
String anonmsg = "anonmsg";
String getanonmsg = "getanonmsg";
String ping = "ping";
String pong = "pong";
String inv = "inv";
String getdata = "getdata";
String addr = "addr";
String getaddr = "getaddr";
String reject = "reject";

class CAnonMsg {
  int msgTime;
  String msgData;

  CAnonMsg() {
    msgTime = 0;
  }

  void setMessage(String msgContent) {
    msgTime = new DateTime.now().millisecondsSinceEpoch ~/ 1000;
    msgData = msgContent;
  }

  String getMessage() {
    return msgData;
  }

  int getTimestamp() {
    return msgTime;
  }

  String toString() {
    String string = ('CAnonMsg msgTime: $msgTime, msgData: $msgData');
    return string;
  }

  List<int> getHash() {
    return sha256.convert(sha256.convert(serialize()).bytes).bytes;
  }
  List<int> serialize() {
    List<int> messageData = uint64ToListIntLE(msgTime) + uint8ToListIntLE(msgData.length) + utf8.encode(msgData);
    return messageData;
  }

  void deserialize(List<int> data) {
    msgTime = listIntToUint64LE(data.sublist(0, 8));
    int msgDataLength = listIntToUint8LE(data.sublist(8, 9));
    msgData = utf8.decode(data.sublist(9, 9 + msgDataLength.abs()), allowMalformed: true);
  }
}

class MsgPing {
  int nonce;

  MsgPing() {
    nonce = getrandbits64();
  }

  List<int> serialize() {
    List<int> messageData = uint64ToListIntLE(nonce);
    return messageData;
  }

  void deserialize(List<int> data) {
    nonce = listIntToUint64LE(data.sublist(0,8));
  }
}

class MsgReject {
  String message;
  int ccode;
  String reason;

  MsgReject() {
    ccode = 0;
  }

  List<int> serialize() {
    List<int> messageData = uint8ToListIntLE(message.length) + utf8.encode(message) + uint8ToListIntLE(ccode) + uint8ToListIntLE(reason.length) + utf8.encode(reason);
    return messageData;
  }

  void deserialize(List<int> data) {
    int messageLength = listIntToUint8LE(data.sublist(0, 1));
    if (messageLength == 0) {
      message = "";
    } else {
      message = utf8.decode(data.sublist(1, 1 + messageLength));
    }
    ccode = listIntToUint8LE(data.sublist(1 + messageLength, 1 + messageLength + 1));
    int reasonLength = listIntToUint8LE(data.sublist(1 + messageLength + 1, 1 + messageLength + 2));
    if (reasonLength == 0) {
      reason = "";
    } else {
      reason = utf8.decode(data.sublist(1 + messageLength + 2, 1 + messageLength + 2 + reasonLength));
    }
  }
}

class CInv {
  int type;
  List<int> hash;

  CInv() {
    type = 0;
  }

  void setTypeAndHash(int inputType, List<int> inputHash) {
    type = inputType;
    hash = inputHash;
  }

  List<int> serialize() {
    List<int> messageData = uint32ToListIntLE(type) + hash;
    return messageData;
  }
}

class MsgInv {
  List<CInv> invVector;

  MsgInv() {
    invVector = [];
  }

  void deserialize(List<int> data) {
    int invCount = listIntToUint8LE(data.sublist(0, 1));
    for (var i=0; i < invCount; i++) {
      CInv cInv = CInv();
      cInv.setTypeAndHash(listIntToUint32LE(data.sublist(1 + (36 * i), 5 + (36 * i))), data.sublist(5 + (36 * i), 37 + (36 * i)));
      invVector.add(cInv);
    }
  }
}

class MsgGetData {
  List<CInv> invVector;

  MsgGetData() {
    invVector = [];
  }

  List<int> serialize() {
    List<int> messageData = uint8ToListIntLE(invVector.length);
    for (var i=0; i < invVector.length; i++) {
      messageData += invVector[i].serialize();
    }
    return messageData;
  }

  void deserialize(List<int> data) {
    int invCount = listIntToUint8LE(data.sublist(0, 1));
    for (var i=0; i < invCount; i++) {
      CInv cInv = CInv();
      cInv.setTypeAndHash(listIntToUint32LE(data.sublist(1 + (36 * i), 5 + (36 * i))), data.sublist(5 + (36 * i), 37 + (36 * i)));
      invVector.add(cInv);
    }
  }
}

class MsgVersion {
  int version;
  int services;
  int timestamp;
  CAddress addr_recv;
  CAddress addr_from;
  int nonce;
  String user_agent;
  int start_height;
  int relay;

  MsgVersion() {
    version = 70210;
    services = 0;
    timestamp = new DateTime.now().millisecondsSinceEpoch ~/ 1000;
    addr_recv = CAddress.data("127.0.0.1");
    addr_from = CAddress();
    nonce = getrandbits64();
    user_agent = "/Omega TrollBox:1.0.0/";
    start_height = 0;
    relay = 0;
  }

  List<int> serialize() {
    List<int> messageData = uint32ToListIntLE(version) + uint64ToListIntLE(services) + uint64ToListIntLE(timestamp) + addr_recv.serialize() + addr_from.serialize() + uint64ToListIntLE(nonce) + uint8ToListIntLE(user_agent.length) + utf8.encode(user_agent) + uint32ToListIntLE(start_height) + [relay];
    return messageData;
  }

  void deserialize(List<int> data) {
    version = listIntToUint32LE(data.sublist(0, 4));
    services = listIntToUint64LE(data.sublist(4, 12));
    timestamp = listIntToUint64LE(data.sublist(12, 20));
    addr_recv = CAddress.data("127.0.0.1");
    addr_from = CAddress();
    nonce = listIntToUint64LE(data.sublist(72,80));
    int userAgentLength = listIntToUint8LE(data.sublist(80, 81));
    if (userAgentLength == 0) {
      user_agent = "";
    } else {
      user_agent = utf8.decode(data.sublist(81, 81 + userAgentLength));
    }
    start_height = listIntToUint32LE(data.sublist(81 + userAgentLength, 81 + userAgentLength + 4));
    relay = listIntToUint8LE(data.sublist(81 + userAgentLength + 4, 81 + userAgentLength + 5));
  }
}

class MsgHeader {
  List<int> _magic;
  String _command;
  int _length;
  int _checksum;
  List<int> _payload;

  MsgHeader() {
    _magic = magic;
    _command = "";
    _length = 0;
    _checksum = 0;
    _payload = new List<int>();
  }

  List<int> serialize() {
    List<int> checksum = sha256.convert(sha256.convert(_payload).bytes).bytes.sublist(0, 4);
    List<int> messageData = _magic + getPaddedCommand(_command) + uint32ToListIntLE(_payload.length) + checksum + _payload;
    return messageData;
  }

  void deserialize(List<int> data) {
    _command = utf8.decode(removeTrailingZeros(data.sublist(4,16)));
    _length = listIntToUint32LE(data.sublist(16,20));
    _checksum = listIntToUint32LE(data.sublist(20,24));
    _payload = data.sublist(24, 24 + _length);
  }
}

class MessageNodes {
  Socket socket;
  String ip;
  int port;
  bool fSuccessfullyConnected;
  bool didWeSendVersion;

  MessageNodes(Socket inputsocket) {
    socket = inputsocket;
    ip = socket.remoteAddress.address;
    port = socket.remotePort;
    fSuccessfullyConnected = false;
    didWeSendVersion = false;

    socket.listen(processMessages,
        onError: errorHandler,
        onDone: finishedHandler);
  }

  void processMessages(List<int> data) {
    //
    // Message format
    //  (4) message start
    //  (12) command
    //  (4) size
    //  (4) checksum
    //  (x) data
    //
    List<int> mutableDataList = new List<int>.from(data);
    Map<int, List<int>> listOfTcpPackets = new Map<int, List<int>>();
    List<int> dataTmp = [];
    int k = 0;

    while (mutableDataList.isNotEmpty) {
      if (IterableEquality().equals([mutableDataList[0], mutableDataList[1], mutableDataList[2], mutableDataList[3]], magic)) {
        int size = listIntToUint32LE(mutableDataList.sublist(16,20));
        int checksum = listIntToUint32LE(mutableDataList.sublist(20,24));
        List<int> payloadData =  mutableDataList.sublist(24, 24 + size);
        int checksumCalculated = listIntToUint32LE(sha256.convert(sha256.convert(payloadData).bytes).bytes.sublist(0, 4));

        if (checksum == checksumCalculated) {
          listOfTcpPackets[k] = [];
          listOfTcpPackets[k] = mutableDataList.sublist(0, 24 + size);
          k += 1;

          if (mutableDataList.length > 24 + size) {
            dataTmp.clear();
            dataTmp = new List<int>.from(mutableDataList.sublist(24 + size));
            mutableDataList.clear();
            mutableDataList = new List<int>.from(dataTmp);
          } else {
            mutableDataList.clear();
          }
        }
      }
    }

    listOfTcpPackets.values.forEach((element) {
      processMessage(element);
    });
   }

  void processMessage(List<int> data){
    MsgHeader msgHeader = new MsgHeader();
    msgHeader.deserialize(data);
    String strCommand = msgHeader._command;
    print('ProcessMessage: Message Command: $strCommand');


    if (msgHeader._command == version) {
      if (!didWeSendVersion) {
        MsgHeader versionMessage = new MsgHeader();
        MsgVersion versionPayload = new MsgVersion();
        versionPayload.addr_from = CAddress.data(ip);
        versionMessage._command = version;
        versionMessage._payload = versionPayload.serialize();

        // send the message
        pushMessage(versionMessage.serialize());
        didWeSendVersion = true;
      }

      MsgHeader verackMessage = new MsgHeader();
      verackMessage._command = verack;

      // send the message
      pushMessage(verackMessage.serialize());

      sendGetAnonMessage();
      //sendAnonMessage('Lunar Lander Space man 123321 hello lamda');

    } else if (msgHeader._command == verack) {
      fSuccessfullyConnected = true;
    } else if (msgHeader._command == ping) {
      MsgHeader pongMessage = new MsgHeader();
      MsgPing pongPayload = new MsgPing();
      pongPayload.deserialize(msgHeader._payload);
      pongMessage._command = pong;
      pongMessage._payload = pongPayload.serialize();

      // send the message
      pushMessage(pongMessage.serialize());
    } else if (msgHeader._command == pong) {
      // We don't check so we will never get this as we don't care
    } else if (msgHeader._command == inv) {
      MsgInv msgInv = MsgInv();
      msgInv.deserialize(msgHeader._payload);

      List<CInv> msgInvData = msgInv.invVector;

      MsgGetData msgGetData = MsgGetData();

      for (CInv k in msgInvData) {
        if (k.type == 20) {
          for (List<int> i in mapAnonMsg.keys) {
            if (IterableEquality().equals(k.hash, i)) {
              break;
            }
          }
          msgGetData.invVector.add(k);
        }
      }

      if (msgGetData.invVector.isNotEmpty) {
        MsgHeader msgGetMessage = new MsgHeader();
        msgGetMessage._command = getdata;
        msgGetMessage._payload = msgGetData.serialize();

        pushMessage(msgGetMessage.serialize());
      }

    } else if (msgHeader._command == getdata) {
      // We don't check so we will never get this as we don't care
    } else if (msgHeader._command == addr) {
      MsgAddr msgAddr = MsgAddr();
      msgAddr.deserialize(msgHeader._payload);

      List<CAddress> okAddr = msgAddr.addrList;
      List<CAddressLite> okAddrG = [];

      for (int i = 0; i < okAddr.length; i++) {
        if (okAddr[i].port == 7777) {
          okAddrG.add(CAddressLite(okAddr[i].ip, okAddr[i].port));
        }
      }

      List<CAddressLite> okAddrGG = okAddrG.toSet().toList();

      // any nodes we get try to add.
      for (int i = 0; i < okAddrGG.length; i++) {
        if (nodes.length <= 6) {
          addNode(okAddrGG[i].ip, okAddrGG[i].port);
        }
      }
    } else if (msgHeader._command == reject) {
      MsgReject msgReject = new MsgReject();
      msgReject.deserialize(msgHeader._payload);
      String message = msgReject.message;
      int ccode = msgReject.ccode;
      String reason = msgReject.reason;

      print('ERROR code: $ccode\n'
          'message: $message\n'
          'reason: $reason\n');
    } else if (msgHeader._command == anonmsg) {
      CAnonMsg cAnonMsg = new CAnonMsg();
      cAnonMsg.deserialize(msgHeader._payload);

      // If we already have this message return and don't add it.
      if (mapAnonMsg.isNotEmpty) {
        for (var k in mapAnonMsg.keys) {
          if (IterableEquality().equals(k, cAnonMsg.getHash())) {
            return;
          }
        }
      }

      // Don't add message if it is over a day old
      if ((cAnonMsg.msgTime + 24*60*60) < DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        return;
      }

      mapAnonMsg[cAnonMsg.getHash()] = cAnonMsg;

      MsgHeader anonMsgMessage = new MsgHeader();
      anonMsgMessage._command = anonmsg;
      anonMsgMessage._payload = cAnonMsg.serialize();
      relayMessage(anonMsgMessage.serialize());


    } else if (msgHeader._command == getanonmsg) {
      mapAnonMsg.values.forEach((cAnonMsg) {
        MsgHeader anonMsgMessage = new MsgHeader();
        anonMsgMessage._command = anonmsg;
        anonMsgMessage._payload = cAnonMsg.serialize();

        // send the message
        pushMessage(anonMsgMessage.serialize());
      });
    } else {
      // We don't support this command add code to tell the node to ignore us for it or something
    }
  }

  void errorHandler(error){
    print('$ip:$port Error: $error');
    removeNode(this);
    socket.close();
  }

  void finishedHandler() {
    print('$ip:$port Disconnected');
    removeNode(this);
    socket.close();
  }

  void pushMessage(List<int> data) {
    socket.add(data);
  }
}

void startServerSocket() {
  ServerSocket.bind(InternetAddress.anyIPv4, DEFAULT_PORT)
      .then((ServerSocket socket) {
    server = socket;
    server.listen((node) {
      handleConnection(node, false);
    });
  });
}

void startNode() {
  print('hi');

  // getnode list
  fetchNodeList().then((value) {
    nodeList = value.listOfNodes;

    // code start

    for (var k in nodeList.keys) {
      addNode(k, nodeList[k]);
    }

    for (var i = 0; i < nodes.length; i++) {
      sendGetAddrMessage(nodes[i]);
    }

    Timer.periodic(Duration(seconds: 20), (timer) {
      if (nodes.length <= 6) {
        for (var i = 0; i < nodes.length; i++) {
          sendGetAddrMessage(nodes[i]);
        }
      }
      // if nodes are ever zero try to add nodes from nodes list again
      if (nodes.length == 0) {
        for (var k in nodeList.keys) {
          addNode(k, nodeList[k]);
        }
      }
    });

    // code end


  });

  //end get node list

  //addNode(nodeList[1]);
  //addNode(nodeList[3]);
  //addNode(nodeList[2]);
  //addNode('192.168.0.193');
}

int periodCount = 0;
bool addNode(String ip, [port = DEFAULT_PORT]) {
  periodCount++;
  if (periodCount >= 6) {
    periodCount--;
    return false;
  }
  if (nodes.length > 6) {
    periodCount--;
    return false;
  }

  // If node is already connected don't add it
  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i].ip == ip) {
      periodCount--;
      return false;
    }
  }

  Socket.connect(ip, port).then((Socket socket) {
    handleConnection(socket, true);
    periodCount--;
    return true;
  }, onError: (e) {
    // If we get a error connections failed return false
    print('Error $e');
    periodCount--;
    return false;
  });
}

void handleConnection(Socket node, bool didWeInitiateConnection){
  MessageNodes messageNodes = new MessageNodes(node);
  nodes.add(messageNodes);

  if (didWeInitiateConnection) {
    MsgHeader versionMessage = new MsgHeader();
    MsgVersion versionPayload = new MsgVersion();
    versionPayload.addr_from = CAddress.data(messageNodes.ip);
    versionMessage._command = version;
    versionMessage._payload = versionPayload.serialize();

    // send the message
    messageNodes.pushMessage(versionMessage.serialize());
    messageNodes.didWeSendVersion = true;
  }
}

void removeNode(MessageNodes messageNodes) {
  nodes.remove(messageNodes);
}

void relayMessage(List<int> message) {
  nodes.forEach((messageNodes) {
    messageNodes.pushMessage(message);
  });
}

void sendGetAddrMessage(MessageNodes messageNodes) {
  MsgHeader getAddrMessage = new MsgHeader();
  getAddrMessage._command = getaddr;

  // send the message
  messageNodes.pushMessage(getAddrMessage.serialize());
}

void sendGetAnonMessage() {
  nodes.forEach((messageNodes) {
    MsgHeader getAnonMessage = new MsgHeader();
    getAnonMessage._command = getanonmsg;

    // send the message
    messageNodes.pushMessage(getAnonMessage.serialize());
  });
}

void sendAnonMessage(String message) {
  bool didWeAddMessage = false;
  nodes.forEach((messageNodes) {
    MsgHeader sendAnonMessage = new MsgHeader();
    CAnonMsg cAnonMsg = CAnonMsg();
    sendAnonMessage._command = anonmsg;
    cAnonMsg.setMessage(message);
    sendAnonMessage._payload = cAnonMsg.serialize();

    if (!didWeAddMessage) {
      mapAnonMsg[cAnonMsg.getHash()] = cAnonMsg;
      didWeAddMessage = true;
    }

    // send the message
    messageNodes.pushMessage(sendAnonMessage.serialize());
  });
}

void updateAnonMessage() {
  nodes.forEach((messageNodes) {
    MsgHeader getanonMessage = new MsgHeader();
    getanonMessage._command = getanonmsg;

    // send the message
    messageNodes.pushMessage(getanonMessage.serialize());
  });
}

void removeOldAnonMessage() {
 mapAnonMsg.keys.forEach((element) {
   if (((mapAnonMsg[element].getTimestamp() + 24*60*60) < (DateTime.now().millisecondsSinceEpoch ~/ 1000))) {
     mapAnonMsg.remove(element);
   }
 });
}

class MsgAddr {
  List<CAddress> addrList;

  MsgAddr() {
    addrList = [];
  }

  void deserialize(List<int> data) {
    int addrCount = listIntToUint8LE(data.sublist(0, 1));
    for (var i=0; i < addrCount; i++) {
      CAddress cAddress = CAddress.notVersion();

      String ip;
      if (IterableEquality().equals(data.sublist(13 + (30 * i), 25 + (30 * i)), IPV4_COMPAT)) {
        ip = getIPv4String(data.sublist(25, 29));
      } else {
        ip; // I didn't write code to support IPv6, but if I did it would be here.
        // we are passing cause we don't want to handle IPv6 nodes
        continue;
      }
      cAddress.setData(listIntToUint32LE(data.sublist(1 + (30 * i), 5 + (30 * i))), listIntToUint64LE(data.sublist(5 + (30 * i), 13 + (30 * i))), ip, listIntToUint16BE(data.sublist(29 + (30 * i), 31 + (30 * i))).abs());
      addrList.add(cAddress);
    }
  }
}

class CAddress {
  int nServices;
  int nTime;
  String ip;
  int port;
  bool isVersionMessage;

  CAddress() {
    nServices = 0;
    ip = "0.0.0.0";
    port = DEFAULT_PORT;
    nTime = new DateTime.now().millisecondsSinceEpoch ~/ 1000;
    isVersionMessage = true;
  }

  CAddress.data(String ipIn, [int portIn = DEFAULT_PORT, int nServicesIn = 0]) {
    nServices = nServicesIn;
    ip = ipIn;
    port = portIn;
    nTime = new DateTime.now().millisecondsSinceEpoch ~/ 1000;
    isVersionMessage = true;
  }

  CAddress.notVersion() {
    nServices = 0;
    ip = "0.0.0.0";
    port = DEFAULT_PORT;
    nTime = new DateTime.now().millisecondsSinceEpoch ~/ 1000;
    isVersionMessage = false;
  }

  void setData(int inputTime, int inputService, String inputIp, int inputPort) {
    nServices = inputService;
    ip = inputIp;
    port = inputPort;
    nTime = inputTime;
  }

  List<int> serialize() {
    List<int> messageData;
    if (isVersionMessage) {
      messageData = uint64ToListIntLE(nServices) + getIPv4ListInt(ip) + uint16ToListIntBE(port);
    } else {
      messageData = uint32ToListIntLE(nTime) + uint64ToListIntLE(nServices) + getIPv4ListInt(ip) + uint16ToListIntBE(port);
    }
    return messageData;
  }

  void deserialize(List<int> data) {
    if (isVersionMessage) {
      nServices = listIntToUint64LE(data.sublist(0, 8));
      if (data.sublist(8, 20) == IPV4_COMPAT) {
        ip = getIPv4String(data.sublist(20, 24));
      } else {
        ip; // I didn't write code to support IPv6, but if I did it would be here.
      }
      port = listIntToUint16BE(data.sublist(24, 26));
    } else {
      nTime = listIntToUint32LE(data.sublist(0, 4));
      nServices = listIntToUint64LE(data.sublist(4, 12));
      if (IterableEquality().equals(data.sublist(12, 24), IPV4_COMPAT)) {
        ip = getIPv4String(data.sublist(24, 28));
      } else {
        ip; // I didn't write code to support IPv6, but if I did it would be here.
      }
      port = listIntToUint16BE(data.sublist(28, 30));
    }
  }
}

class CAddressLite {
  String ip;
  int port;

  CAddressLite(String inputIp, int inputPort) {
    ip = inputIp;
    port = inputPort;
  }
}

