import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:personal_bahi_khata/presentation/homepage.dart';
import 'package:personal_bahi_khata/presentation/opened_file.dart';

class FileHandler extends StatefulWidget {
  const FileHandler({super.key});

  @override
  State<FileHandler> createState() => _FileHandlerState();
}

class _FileHandlerState extends State<FileHandler> with WidgetsBindingObserver {
  static const platform = MethodChannel(
    'com.vins.bahi_khata/open_file',
  );

  String? openFileUrl;

  @override
  void initState() {
    super.initState();
    Platform.isAndroid ? getOpenFileUrl() : null;
    // Listen to lifecycle events.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Platform.isAndroid ? getOpenFileUrl() : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center());
  }

  void getOpenFileUrl() async {
    dynamic url = await platform.invokeMethod("handleOpenFileUrl");
    if (!mounted) {
      return;
    }
    debugPrint("handleOpenFileUrl $url");
    if (url != null && url != openFileUrl) {
      setState(() {
        openFileUrl = url;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) {
          return;
        }
        final navigator = Navigator.of(context);
        var intent = url; //await IntentHandler.getIntent();
        debugPrint("intent data $intent");
        if (intent != null) {
          String filePath = intent.toString();
          await navigator.pushReplacement(
            MaterialPageRoute(
              builder: (context) => OpenedFilePage(filePath: filePath),
            ),
          );
        } else {
          if (!mounted) {
            return;
          }
          await navigator.pushReplacement(
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        }
      } on PlatformException catch (e) {
        debugPrint("Failed to get intent: '${e.message}'.");
      }
    });
  }
}

class IntentHandler {
  static const MethodChannel _channel = MethodChannel('intent_handler');

  static Future<IntentData?> getIntent() async {
    final dynamic result = await _channel.invokeMethod('getIntent');
    if (result == null) {
      return null;
    }
    return IntentData.fromJson(result);
  }
}

class IntentData {
  final Uri? data;

  IntentData({required this.data});

  factory IntentData.fromJson(Map<String, dynamic> json) {
    return IntentData(data: Uri.parse(json['data'] ?? ''));
  }
}

class FileHandlerWR {
  static const MethodChannel _channel = MethodChannel(
    'com.vins.bahi_khata/write_file',
  );
  static Future<void> writeToFile(String fileName, String content) async {
    try {
      debugPrint(content);
      await _channel.invokeMethod('writeToFile', {
        'fileName': fileName,
        'content': content,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to write to file: '${e.message}'.");
    }
  }
}
