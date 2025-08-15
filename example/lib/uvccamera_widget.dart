import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uvccamera/uvccamera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image/image.dart' as img;

import 'pose_painter.dart';

class UvcCameraWidget extends StatefulWidget {
  final UvcCameraDevice device;

  const UvcCameraWidget({super.key, required this.device});

  @override
  State<UvcCameraWidget> createState() => _UvcCameraWidgetState();
}

class _UvcCameraWidgetState extends State<UvcCameraWidget> with WidgetsBindingObserver {
  bool _isAttached = false;
  bool _hasDevicePermission = false;
  bool _hasCameraPermission = false;
  bool _isDeviceAttached = false;
  bool _isDeviceConnected = false;
  UvcCameraController? _cameraController;
  Future<void>? _cameraControllerInitializeFuture;
  StreamSubscription<UvcCameraErrorEvent>? _errorEventSubscription;
  StreamSubscription<UvcCameraStatusEvent>? _statusEventSubscription;
  StreamSubscription<UvcCameraButtonEvent>? _buttonEventSubscription;
  StreamSubscription<UvcCameraDeviceEvent>? _deviceEventSubscription;
  StreamSubscription<UvcCameraFrameEvent>? _frameEventSubscription;
  String _log = '';

  // ML Kit pose detection
  late PoseDetector _poseDetector;
  bool _isDetecting = false;
  List<Pose> _detectedPoses = [];
  Size _imageSize = Size.zero;

  // Frame throttling for Android 14 compatibility
  DateTime _lastFrameProcessed = DateTime.now();
  static const int _frameProcessingIntervalMs = 100; // Process max 10 FPS
  bool _isStreamActive = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Initialize ML Kit pose detector
    final options = PoseDetectorOptions(mode: PoseDetectionMode.stream, model: PoseDetectionModel.base);
    _poseDetector = PoseDetector(options: options);

    _attach();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _detach(force: true);

    // Cleanup ML Kit pose detector
    _poseDetector.close();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _attach();
    } else if (state == AppLifecycleState.paused) {
      _detach();
    }
  }

  void _attach({bool force = false}) {
    if (_isAttached && !force) {
      return;
    }

    UvcCamera.getDevices().then((devices) {
      if (!devices.containsKey(widget.device.name)) {
        return;
      }

      setState(() {
        _isDeviceAttached = true;
      });

      _requestPermissions();
    });

    _deviceEventSubscription = UvcCamera.deviceEventStream.listen((event) {
      if (event.device.name != widget.device.name) {
        return;
      }

      if (event.type == UvcCameraDeviceEventType.attached && !_isDeviceAttached) {
        // NOTE: Requesting UVC device permission will trigger connection request
        _requestPermissions();
      }

      setState(() {
        if (event.type == UvcCameraDeviceEventType.attached) {
          // _hasCameraPermission - maybe
          // _hasDevicePermission - maybe
          _isDeviceAttached = true;
          _isDeviceConnected = false;
        } else if (event.type == UvcCameraDeviceEventType.detached) {
          _hasCameraPermission = false;
          _hasDevicePermission = false;
          _isDeviceAttached = false;
          _isDeviceConnected = false;
        } else if (event.type == UvcCameraDeviceEventType.connected) {
          _hasCameraPermission = true;
          _hasDevicePermission = true;
          _isDeviceAttached = true;
          _isDeviceConnected = true;

          _log = '';

          _cameraController = UvcCameraController(device: widget.device);
          _cameraControllerInitializeFuture = _cameraController!.initialize().then((_) async {
            _errorEventSubscription = _cameraController!.cameraErrorEvents.listen((event) {
              setState(() {
                _log = 'error: ${event.error}\n$_log';
              });

              if (event.error.type == UvcCameraErrorType.previewInterrupted) {
                _detach();
                _attach();
              }
            });

            _statusEventSubscription = _cameraController!.cameraStatusEvents.listen((event) {
              setState(() {
                _log = 'status: ${event.payload}\n$_log';
              });
            });

            _buttonEventSubscription = _cameraController!.cameraButtonEvents.listen((event) {
              setState(() {
                _log = 'btn(${event.button}): ${event.state}\n$_log';
              });
            });
            log('_cameraController!.cameraFrameEvents');

            // _frameEventSubscription = _cameraController!.cameraFrameEvents.listen((event) {
            //   log('frame: ${event.imageData.length}');
            //   setState(() {
            //     _log = 'frame: ${event.imageData.length}\n$_log';
            //   });
            // });
          });
        } else if (event.type == UvcCameraDeviceEventType.disconnected) {
          _hasCameraPermission = false;
          _hasDevicePermission = false;
          // _isDeviceAttached - maybe?
          _isDeviceConnected = false;

          _buttonEventSubscription?.cancel();
          _buttonEventSubscription = null;

          _frameEventSubscription?.cancel();
          _frameEventSubscription = null;

          _statusEventSubscription?.cancel();
          _statusEventSubscription = null;

          _errorEventSubscription?.cancel();
          _errorEventSubscription = null;

          _cameraController?.dispose();
          _cameraController = null;
          _cameraControllerInitializeFuture = null;

          _log = '';
        }
      });
    });

    _isAttached = true;
  }

  void _detach({bool force = false}) {
    if (!_isAttached && !force) {
      return;
    }

    _hasDevicePermission = false;
    _hasCameraPermission = false;
    _isDeviceAttached = false;
    _isDeviceConnected = false;

    _buttonEventSubscription?.cancel();
    _buttonEventSubscription = null;

    _statusEventSubscription?.cancel();
    _statusEventSubscription = null;

    _frameEventSubscription?.cancel();
    _frameEventSubscription = null;

    _cameraController?.dispose();
    _cameraController = null;
    _cameraControllerInitializeFuture = null;

    _deviceEventSubscription?.cancel();
    _deviceEventSubscription = null;

    _isAttached = false;
  }

  Future<void> _requestPermissions() async {
    final hasCameraPermission = await _requestCameraPermission().then((value) {
      setState(() {
        _hasCameraPermission = value;
      });

      return value;
    });

    // NOTE: Requesting UVC device permission can be made only after camera permission is granted
    if (!hasCameraPermission) {
      return;
    }

    _requestDevicePermission().then((value) {
      setState(() {
        _hasDevicePermission = value;
      });

      return value;
    });
  }

  Future<bool> _requestDevicePermission() async {
    final devicePermissionStatus = await UvcCamera.requestDevicePermission(widget.device);
    return devicePermissionStatus;
  }

  Future<bool> _requestCameraPermission() async {
    var cameraPermissionStatus = await Permission.camera.status;
    if (cameraPermissionStatus.isGranted) {
      return true;
    } else if (cameraPermissionStatus.isDenied || cameraPermissionStatus.isRestricted) {
      cameraPermissionStatus = await Permission.camera.request();
      return cameraPermissionStatus.isGranted;
    } else {
      // NOTE: Permission is permanently denied
      return false;
    }
  }

  Future<void> _startVideoRecording(UvcCameraMode videoRecordingMode) async {
    await _cameraController!.startVideoRecording(videoRecordingMode);
  }

  Future<void> _takePicture() async {
    final XFile outputFile = await _cameraController!.takePicture();

    outputFile.length().then((length) {
      setState(() {
        _log = 'image file: ${outputFile.path} ($length bytes)\n$_log';
      });
    });
  }

  Future<void> _stopVideoRecording() async {
    final XFile outputFile = await _cameraController!.stopVideoRecording();

    outputFile.length().then((length) {
      setState(() {
        _log = 'video file: ${outputFile.path} ($length bytes)\n$_log';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDeviceAttached) {
      return Center(child: Text('Device is not attached', style: TextStyle(fontSize: 18)));
    }

    if (!_hasCameraPermission) {
      return Center(child: Text('Camera permission is not granted', style: TextStyle(fontSize: 18)));
    }

    if (!_hasDevicePermission) {
      return Center(child: Text('Device permission is not granted', style: TextStyle(fontSize: 18)));
    }

    if (!_isDeviceConnected) {
      return Center(child: Text('Device is not connected', style: TextStyle(fontSize: 18)));
    }

    return FutureBuilder<void>(
      future: _cameraControllerInitializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: UvcCameraPreview(
                  _cameraController!,
                  child: Stack(
                    children: [
                      // Log text overlay
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _log,
                            style: TextStyle(color: Colors.red, fontFamily: 'Courier', fontSize: 10.0),
                          ),
                        ),
                      ),
                      // Pose detection overlay
                      if (_detectedPoses.isNotEmpty)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: PosePainter(
                              poses: _detectedPoses,
                              imageSize: _imageSize,
                              rotation: InputImageRotation.rotation0deg,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 50.0),
                  child: ValueListenableBuilder<UvcCameraControllerState>(
                    valueListenable: _cameraController!,
                    builder: (context, value, child) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          FloatingActionButton(
                            backgroundColor: Colors.white,
                            onPressed:
                                value.isTakingPicture
                                    ? null
                                    : () async {
                                      await _takePicture();
                                    },
                            child: Icon(Icons.camera_alt, color: Colors.black),
                          ),
                          FloatingActionButton(
                            backgroundColor: value.isRecordingVideo ? Colors.red : Colors.white,
                            onPressed: () async {
                              if (value.isRecordingVideo) {
                                await _stopVideoRecording();
                              } else {
                                await _startVideoRecording(value.previewMode!);
                              }
                            },
                            child: Icon(
                              value.isRecordingVideo ? Icons.stop : Icons.videocam,
                              color: value.isRecordingVideo ? Colors.white : Colors.black,
                            ),
                          ),
                          FloatingActionButton(
                            backgroundColor: Colors.white,
                            onPressed: () async {
                              try {
                                // Prevent multiple stream starts
                                if (_isStreamActive) {
                                  log('Stream already active, ignoring request');
                                  return;
                                }

                                _isStreamActive = true;

                                // Start streaming with pose detection
                                await _cameraController!.startImageStream((UvcCameraFrameEvent frameEvent) {
                                  // Frame throttling for Android 14 compatibility
                                  final now = DateTime.now();
                                  if (now.difference(_lastFrameProcessed).inMilliseconds < _frameProcessingIntervalMs) {
                                    return; // Skip this frame
                                  }
                                  _lastFrameProcessed = now;

                                  log('Frame received: ${frameEvent.imageData.length} bytes');
                                  log('Resolution: ${frameEvent.width}x${frameEvent.height}');

                                  // Process raw image data with ML Kit pose detection (async)
                                  _processFrameForPoseDetection(frameEvent);
                                });
                              } catch (e) {
                                _isStreamActive = false;
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                }
                                log('Error starting image stream: $e');
                              }
                            },
                            child: Icon(Icons.play_arrow, color: Colors.black),
                          ),
                          FloatingActionButton(
                            backgroundColor: Colors.white,
                            onPressed: () async {
                              try {
                                // Stop streaming
                                await _cameraController!.stopImageStream();
                                _isStreamActive = false;

                                // Clear pose detection state
                                if (mounted) {
                                  setState(() {
                                    _detectedPoses.clear();
                                  });
                                }
                              } catch (e) {
                                _isStreamActive = false;
                                if (context.mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(SnackBar(content: Text('Error stopping stream: $e')));
                                }
                                log('Error stopping image stream: $e');
                              }
                            },
                            child: Icon(Icons.stop, color: Colors.black),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }

  // Process frame for pose detection using ML Kit
  Future<void> _processFrameForPoseDetection(UvcCameraFrameEvent frameEvent) async {
    // Skip if already processing
    if (_isDetecting) {
      log('Skipping frame - already processing');
      return;
    }

    _isDetecting = true;
    final startTime = DateTime.now().millisecondsSinceEpoch;

    try {
      final imageData = frameEvent.imageData;
      final width = frameEvent.width;
      final height = frameEvent.height;
      final format = frameEvent.format;

      log('Processing frame: format=$format, size=${width}x${height}, bytes=${imageData.length}');

      // Update image size for overlay
      _imageSize = Size(width.toDouble(), height.toDouble());

      // Create InputImage
      final inputImage = InputImage.fromBytes(
        bytes: imageData,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );

      // Run pose detection with timeout protection for Android 14
      final poses = await _poseDetector
          .processImage(inputImage)
          .timeout(
            Duration(milliseconds: 800), // Max 800ms for pose detection
            onTimeout: () {
              log('Pose detection timeout - skipping frame');
              return <Pose>[];
            },
          );

      final processingTime = DateTime.now().millisecondsSinceEpoch - startTime;
      log('Pose detection completed in ${processingTime}ms, found ${poses.length} poses');

      // Update UI only if widget is still mounted and processing time is reasonable
      if (mounted && processingTime < 1000) {
        setState(() {
          _detectedPoses = poses;
        });
      }
    } catch (e) {
      // Handle different types of errors appropriately
      if (e.toString().contains('TimeoutException')) {
        log('Frame processing timeout - this is normal on slower devices');
      } else {
        log('_processFrameForPoseDetection => ERROR: $e');
        // Only show error SnackBar for serious errors, not timeouts
        if (mounted && !e.toString().contains('TimeoutException')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Pose detection error: ${e.toString().substring(0, 50)}...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } finally {
      _isDetecting = false;
    }
  }
}
