// import 'dart:developer';
// import 'dart:typed_data';
// import 'dart:io';
// import 'dart:ui' as ui;

// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_uvc_camera/flutter_uvc_camera.dart';
// import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
// import 'package:path_provider/path_provider.dart';

// import 'pose_painter.dart';

// class MLKitCamera extends StatefulWidget {
//   const MLKitCamera({super.key});

//   @override
//   State<MLKitCamera> createState() => _MLKitCameraState();
// }

// class _MLKitCameraState extends State<MLKitCamera> {
//   late UVCCameraController cameraController;
//   bool isCameraOpen = false;
//   bool isStreaming = false;
//   bool isRecording = false;

//   // Streaming stats
//   int videoFramesReceived = 0;
//   int audioFramesReceived = 0;
//   int lastVideoFrameSize = 0;
//   String recordingTime = "00:00:00";
//   String streamState = "Not started";

//   // FPS values
//   int _currentFps = 0;
//   int _renderFps = 0; // GL render FPS

//   // ML Kit pose detection
//   late PoseDetector _poseDetector;
//   bool _isDetecting = false;
//   bool _poseDetectionEnabled = false;
//   List<Pose> _detectedPoses = [];
//   Size _imageSize = Size.zero;

//   // Processing stats
//   int _mlKitProcessingTime = 0;
//   int _frameSkipCounter = 0;
//   int _decodeTime = 0;

//   // Paths for temporary files
//   String _tempInputFilePath = '';
//   String _tempOutputFilePath = '';

//   @override
//   void initState() {
//     super.initState();
//     cameraController = UVCCameraController();

//     // Inisialisasi ML Kit pose detector
//     final options = PoseDetectorOptions(
//       mode: PoseDetectionMode.stream, // Optimal untuk video stream
//       model: PoseDetectionModel.base,
//     );
//     _poseDetector = PoseDetector(options: options);

//     // Inisialisasi temporary file paths
//     _initTempFilePaths();

//     // Set up callbacks BEFORE attempting to open the camera
//     cameraController.msgCallback = (state) {
//       debugPrint("Camera message: $state");
//       showCustomToast(state);
//     };

//     cameraController.cameraStateCallback = (state) {
//       debugPrint("Camera state changed: $state");
//       if (mounted) {
//         setState(() {
//           isCameraOpen = state == UVCCameraState.opened;
//         });
//       }
//     };

//     cameraController.onVideoFrameCallback = (frame) {
//       debugPrint("Video frame received: size=${frame.size}, fps=${frame.fps}");
//       setState(() {
//         videoFramesReceived++;
//         lastVideoFrameSize = frame.size;

//         // Use the FPS from the frame directly
//         if (frame.fps > 0) {
//           _currentFps = frame.fps;
//         }
//       });
//       // H264 frames are not used for ML Kit. NV21 callback handles ML processing.
//       _frameSkipCounter++;
//     };

//     cameraController.onAudioFrameCallback = (frame) {
//       log("Audio frame received: size=${frame.size}, fps=${frame.fps}");
//       setState(() {
//         audioFramesReceived++;
//       });
//     };

//     // Receive NV21 raw preview frames for ML Kit
//     cameraController.onNv21FrameCallback = (nv21) {
//       debugPrint("NV21 frame received: ${nv21.width}x${nv21.height}, size=${nv21.size}, fps=${nv21.fps}");
//       setState(() {
//         videoFramesReceived++;
//         lastVideoFrameSize = nv21.size;
//         if (nv21.fps > 0) {
//           _currentFps = nv21.fps;
//         }
//         _imageSize = Size(nv21.width.toDouble(), nv21.height.toDouble());
//       });

//       if (_poseDetectionEnabled && !_isDetecting) {
//         _processNv21FrameWithMLKit(nv21);
//       } else {
//         _frameSkipCounter++;
//       }
//     };

//     cameraController.onRecordingTimeCallback = (timeEvent) {
//       log("Recording time changed: ${timeEvent.formattedTime}");
//       setState(() {
//         recordingTime = timeEvent.formattedTime;

//         // 如果收到了最终的录制时间更新，那么录制已结束
//         if (timeEvent.isFinal && isRecording) {
//           isRecording = false;
//         }
//       });
//     };

//     cameraController.onStreamStateCallback = (stateEvent) {
//       log("Stream state changed: ${stateEvent.state}");
//       setState(() {
//         streamState = stateEvent.state;

//         if (stateEvent.state == 'STARTED' || stateEvent.state == 'STREAM_STARTED') {
//           isStreaming = true;
//         } else if (stateEvent.state == 'STOPPED' || stateEvent.state == 'STREAM_STOPPED') {
//           isStreaming = false;
//           // Reset render FPS when streaming stops
//           _renderFps = 0;
//         } else if (stateEvent.state == 'RENDER_FPS' && stateEvent.data != null) {
//           // Update render FPS from native side
//           final renderFps = stateEvent.data?['renderFps'];
//           if (renderFps is int && renderFps > 0) {
//             debugPrint("Received GL render FPS: $renderFps");
//             _renderFps = renderFps;
//           }
//         }
//       });
//     };

//     // After initializing camera
//     cameraController.setVideoFrameRateLimit(20); // Lower than default 30
//     cameraController.setVideoFrameSizeLimit(1024 * 1024); // Limit frame size
//   }

//   @override
//   void dispose() {
//     cameraController.closeCamera();
//     cameraController.dispose();
//     _poseDetector.close();
//     super.dispose();
//   }

//   // Inisialisasi temporary file paths untuk proses decoding
//   Future<void> _initTempFilePaths() async {
//     final tempDir = await getTemporaryDirectory();
//     _tempInputFilePath = '${tempDir.path}/temp_frame.h264';
//     _tempOutputFilePath = '${tempDir.path}/decoded_frame.jpg';
//     debugPrint('Temp files path initialized: $_tempInputFilePath, $_tempOutputFilePath');
//   }

//   // Process NV21 raw preview frames with ML Kit
//   Future<void> _processNv21FrameWithMLKit(Nv21FrameEvent nv21) async {
//     if (_isDetecting) return;

//     _isDetecting = true;
//     final startTime = DateTime.now().millisecondsSinceEpoch;

//     try {
//       final bytes = nv21.data;
//       final width = nv21.width;
//       final height = nv21.height;

//       // Validate buffer size for NV21 (YUV420SP): w*h*3/2
//       final expected = (width * height * 3) >> 1; // integer division by 2
//       if (bytes.lengthInBytes != expected) {
//         log('NV21 buffer size mismatch: got ${bytes.lengthInBytes}, expected $expected for ${width}x$height');
//         // Still attempt processing; ML Kit may handle stride differences, but we log for diagnostics
//       }

//       // Update image size for overlay
//       _imageSize = Size(width.toDouble(), height.toDouble());

//       final inputImage = InputImage.fromBytes(
//         bytes: bytes,
//         metadata: InputImageMetadata(
//           size: Size(width.toDouble(), height.toDouble()),
//           rotation: InputImageRotation.rotation0deg,
//           format: InputImageFormat.nv21,
//           bytesPerRow: width, // stride for Y plane in NV21
//         ),
//       );

//       // Run pose detection
//       final poses = await _poseDetector.processImage(inputImage);

//       if (mounted) {
//         setState(() {
//           _detectedPoses = poses;
//           _mlKitProcessingTime = DateTime.now().millisecondsSinceEpoch - startTime;
//         });
//       }
//     } catch (e) {
//       log('_processNv21FrameWithMLKit => ERROR: $e');
//     } finally {
//       _isDetecting = false;
//     }
//   }

//   // Fungsi untuk mendekode H264 frame menggunakan ffmpeg
//   Future<ui.Image?> _decodeH264Frame(Uint8List frameData) async {
//     // FFmpeg decoding disabled to allow build without ffmpeg dependency
//     // TODO: Re-enable with a working FFmpeg kit native artifact
//     return null;
//   }

//   // Konversi ui.Image ke InputImage untuk ML Kit
//   Future<InputImage?> _convertToInputImage(ui.Image image) async {
//     try {
//       // Convert ui.Image ke byte data
//       final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
//       if (byteData == null) return null;

//       // Buat file JPEG dari byte data untuk InputImage
//       // Untuk use case production, konversi langsung memory-to-memory lebih efisien
//       final buffer = byteData.buffer;
//       final jpegFile = File(_tempOutputFilePath);
//       await jpegFile.writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes), flush: true);

//       // Buat InputImage dari path file
//       return InputImage.fromFilePath(_tempOutputFilePath);
//     } catch (e) {
//       debugPrint('Error converting to InputImage: $e');
//       return null;
//     }
//   }

//   void showCustomToast(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         behavior: SnackBarBehavior.floating,
//         margin: const EdgeInsets.all(16),
//         duration: const Duration(seconds: 2),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//       ),
//     );
//   }

//   void toggleStreaming() {
//     debugPrint("Toggle streaming called, current state: ${isStreaming ? 'streaming' : 'not streaming'}");
//     if (isStreaming) {
//       debugPrint("Stopping stream");
//       cameraController.captureStreamStop();
//     } else {
//       debugPrint("Starting stream");
//       cameraController.captureStreamStart();
//     }
//   }

//   Future<void> captureVideo() async {
//     if (isRecording) {
//       // 如果正在录制，则停止录制
//       setState(() {
//         isRecording = false;
//       });
//       final path = await cameraController.captureVideo();
//       if (path != null) {
//         showCustomToast('Video saved to: $path');
//       }
//     } else {
//       // 开始录制
//       setState(() {
//         isRecording = true;
//         recordingTime = "00:00:00"; // 重置录制时间
//       });
//       final path = await cameraController.captureVideo();
//       if (path != null) {
//         showCustomToast('Video saved to: $path');
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Camera Streaming'),
//         backgroundColor: Theme.of(context).colorScheme.primaryContainer,
//       ),
//       body: Column(
//         children: [
//           Container(
//             margin: const EdgeInsets.all(16),
//             height: 250,
//             decoration: BoxDecoration(
//               color: Colors.black,
//               borderRadius: BorderRadius.circular(16),
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black.withOpacity(0.2),
//                   spreadRadius: 1,
//                   blurRadius: 5,
//                   offset: const Offset(0, 3),
//                 ),
//               ],
//             ),
//             child: Stack(
//               children: [
//                 ClipRRect(
//                   borderRadius: BorderRadius.circular(16),
//                   child: UVCCameraView(
//                     cameraController: cameraController,
//                     params: const UVCCameraViewParamsEntity(frameFormat: 0, rawPreviewData: true),
//                     width: 300,
//                     height: 300,
//                     autoDispose: false,
//                   ),
//                 ),
//                 // Pose detection overlay
//                 if (_poseDetectionEnabled && _detectedPoses.isNotEmpty)
//                   Positioned.fill(
//                     child: CustomPaint(
//                       painter: PosePainter(
//                         poses: _detectedPoses,
//                         imageSize: _imageSize,
//                         rotation: InputImageRotation.rotation0deg,
//                       ),
//                     ),
//                   ),

//                 Positioned(
//                   top: 10,
//                   right: 10,
//                   child: Container(
//                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                     decoration: BoxDecoration(
//                       color: isStreaming ? Colors.green.withOpacity(0.7) : Colors.black54,
//                       borderRadius: BorderRadius.circular(4),
//                     ),
//                     child: Text(
//                       '$_currentFps FPS',
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontWeight: isStreaming ? FontWeight.bold : FontWeight.normal,
//                         fontSize: isStreaming ? 14 : 12,
//                       ),
//                     ),
//                   ),
//                 ),
//                 if (isStreaming)
//                   Positioned(
//                     top: 10,
//                     left: 10,
//                     child: Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                       decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
//                       child: Row(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           Container(
//                             width: 8,
//                             height: 8,
//                             decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
//                           ),
//                           const SizedBox(width: 4),
//                           const Text(
//                             'LIVE',
//                             style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 if (isRecording)
//                   Positioned(
//                     bottom: 10,
//                     left: 0,
//                     right: 0,
//                     child: Container(
//                       margin: const EdgeInsets.symmetric(horizontal: 20),
//                       padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
//                       decoration: BoxDecoration(
//                         color: Colors.red.withOpacity(0.8),
//                         borderRadius: BorderRadius.circular(20),
//                       ),
//                       child: Row(
//                         mainAxisSize: MainAxisSize.min,
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           Container(
//                             width: 12,
//                             height: 12,
//                             decoration: BoxDecoration(
//                               color: Colors.white,
//                               shape: BoxShape.circle,
//                               border: Border.all(color: Colors.red.shade700, width: 2),
//                             ),
//                           ),
//                           const SizedBox(width: 8),
//                           Text(
//                             'RECORDING $recordingTime',
//                             style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//           ),

//           // Camera open/close buttons
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 16.0),
//             child: Row(
//               children: [
//                 Expanded(
//                   child: ElevatedButton.icon(
//                     onPressed: isCameraOpen ? null : () => cameraController.openUVCCamera(),
//                     icon: const Icon(Icons.camera),
//                     label: const Text('Open Camera'),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.green,
//                       foregroundColor: Colors.white,
//                       disabledBackgroundColor: Colors.grey.shade300,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: ElevatedButton.icon(
//                     onPressed: isCameraOpen ? () => cameraController.closeCamera() : null,
//                     icon: const Icon(Icons.close),
//                     label: const Text('Close Camera'),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.red,
//                       foregroundColor: Colors.white,
//                       disabledBackgroundColor: Colors.grey.shade300,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           // Streaming controls
//           Padding(
//             padding: const EdgeInsets.all(16.0),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.stretch,
//               children: [
//                 ElevatedButton.icon(
//                   onPressed: isCameraOpen ? toggleStreaming : null,
//                   icon: Icon(isStreaming ? Icons.stop : Icons.play_arrow),
//                   label: Text(isStreaming ? 'Stop Streaming' : 'Start Streaming'),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: isStreaming ? Colors.red : Colors.blue,
//                     foregroundColor: Colors.white,
//                     padding: const EdgeInsets.symmetric(vertical: 12),
//                   ),
//                 ),
//                 // const SizedBox(height: 8),
//                 // ElevatedButton.icon(
//                 //   onPressed: (isCameraOpen && isStreaming) ? captureVideo : null,
//                 //   icon: Icon(isRecording ? Icons.stop : Icons.videocam),
//                 //   label: Text(isRecording ? 'Stop Recording' : 'Record Video'),
//                 //   style: ElevatedButton.styleFrom(
//                 //     backgroundColor: isRecording ? Colors.red : Colors.orange,
//                 //     foregroundColor: Colors.white,
//                 //     padding: const EdgeInsets.symmetric(vertical: 12),
//                 //   ),
//                 // ),
//                 const SizedBox(height: 8),
//                 ElevatedButton.icon(
//                   onPressed: isStreaming ? togglePoseDetection : null,
//                   icon: Icon(_poseDetectionEnabled ? Icons.person_off : Icons.person),
//                   label: Text(_poseDetectionEnabled ? 'Disable Pose Detection' : 'Enable Pose Detection'),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: _poseDetectionEnabled ? Colors.purple : Colors.indigo,
//                     foregroundColor: Colors.white,
//                     padding: const EdgeInsets.symmetric(vertical: 12),
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           // Streaming stats
//           Expanded(
//             child: Container(
//               margin: const EdgeInsets.all(16),
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: Colors.grey.shade100,
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(color: Colors.grey.shade300),
//               ),
//               child: SingleChildScrollView(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Text('Streaming Statistics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
//                     const SizedBox(height: 16),
//                     _buildStatRow('Stream State', streamState),
//                     _buildStatRow('Current FPS', _currentFps.toString()),
//                     if (_renderFps > 0) _buildStatRow('GL Render FPS', _renderFps.toString(), highlight: true),
//                     if (_poseDetectionEnabled)
//                       _buildStatRow('ML Kit Processing Time', '$_mlKitProcessingTime ms', highlight: true),
//                     if (_poseDetectionEnabled) _buildStatRow('Decode Time', '$_decodeTime ms'),
//                     if (_poseDetectionEnabled) _buildStatRow('Frames Skipped', '$_frameSkipCounter'),
//                     if (_poseDetectionEnabled) _buildPoseDetectionInfo(),
//                     _buildStatRow(
//                       'Recording Status',
//                       isRecording ? 'Recording' : 'Not Recording',
//                       highlight: isRecording,
//                     ),
//                     _buildStatRow('Recording Time', recordingTime, highlight: isRecording),
//                     _buildStatRow('Video Frames', videoFramesReceived.toString()),
//                     _buildStatRow('Audio Frames', audioFramesReceived.toString()),
//                     _buildStatRow('Last Frame Size', '$lastVideoFrameSize bytes'),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildStatRow(String label, String value, {bool highlight = false}) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 4.0),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
//           Text(
//             value,
//             style: TextStyle(
//               fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
//               color: highlight ? Colors.blue.shade700 : Colors.black87,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildPoseDetectionInfo() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const SizedBox(height: 8),
//         const Text(
//           'Pose Detection Info',
//           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple),
//         ),
//         const SizedBox(height: 8),
//         Text('Decode time: $_decodeTime ms', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
//         Text('Image size: ${_imageSize.width.toInt()}x${_imageSize.height.toInt()}', style: TextStyle(fontSize: 12)),
//         Text('Poses detected: ${_detectedPoses.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
//         if (_detectedPoses.isNotEmpty) ..._buildPoseDetailsList(),
//       ],
//     );
//   }

//   List<Widget> _buildPoseDetailsList() {
//     final List<Widget> poseWidgets = [];

//     for (var i = 0; i < _detectedPoses.length; i++) {
//       final pose = _detectedPoses[i];
//       final landmarks = pose.landmarks;

//       poseWidgets.add(Text('Pose $i - ${landmarks.length} landmarks', style: TextStyle(fontSize: 12)));

//       // Tampilkan beberapa landmark utama jika tersedia
//       final List<String> keyLandmarks = [];

//       if (landmarks.containsKey(PoseLandmarkType.nose)) {
//         keyLandmarks.add('Nose');
//       }
//       if (landmarks.containsKey(PoseLandmarkType.leftShoulder) &&
//           landmarks.containsKey(PoseLandmarkType.rightShoulder)) {
//         keyLandmarks.add('Shoulders');
//       }
//       if (landmarks.containsKey(PoseLandmarkType.leftElbow) && landmarks.containsKey(PoseLandmarkType.rightElbow)) {
//         keyLandmarks.add('Elbows');
//       }

//       if (keyLandmarks.isNotEmpty) {
//         poseWidgets.add(
//           Text(
//             '   Key landmarks: ${keyLandmarks.join(', ')}',
//             style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
//           ),
//         );
//       }
//     }

//     return poseWidgets;
//   }

//   void togglePoseDetection() {
//     setState(() {
//       _poseDetectionEnabled = !_poseDetectionEnabled;
//       _frameSkipCounter = 0;

//       if (_poseDetectionEnabled) {
//         // Kurangi frame rate untuk performa yang lebih baik
//         cameraController.setVideoFrameRateLimit(15);
//         showCustomToast('Pose detection enabled (15 FPS)');
//       } else {
//         // Kembalikan ke frame rate default
//         cameraController.setVideoFrameRateLimit(30);
//         _detectedPoses = [];
//         showCustomToast('Pose detection disabled');
//       }
//     });
//   }
// }
