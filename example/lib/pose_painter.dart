import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// Custom painter untuk menggambar pose landmarks dan connections
class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;

  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (poses.isEmpty || imageSize == Size.zero) return;
    
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    final paintLandmark = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 4.0
      ..color = Colors.green;

    final paintLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.yellow;

    for (final pose in poses) {
      final landmarks = pose.landmarks;
      
      // Draw connections between landmarks
      _drawPoseConnections(canvas, landmarks, paintLine, scaleX, scaleY);
      
      // Draw all landmarks
      landmarks.forEach((type, landmark) {
        canvas.drawCircle(
          Offset(landmark.x * scaleX, landmark.y * scaleY),
          4.0,
          paintLandmark,
        );
      });
    }
  }

  void _drawPoseConnections(Canvas canvas, Map<PoseLandmarkType, PoseLandmark> landmarks,
      Paint paint, double scaleX, double scaleY) {
    // Define connections between landmarks
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
    _drawConnection(canvas, landmarks, paint, scaleX, scaleY,
        PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
  }

  void _drawConnection(Canvas canvas, Map<PoseLandmarkType, PoseLandmark> landmarks,
      Paint paint, double scaleX, double scaleY, PoseLandmarkType from, PoseLandmarkType to) {
    if (landmarks.containsKey(from) && landmarks.containsKey(to)) {
      canvas.drawLine(
        Offset(landmarks[from]!.x * scaleX, landmarks[from]!.y * scaleY),
        Offset(landmarks[to]!.x * scaleX, landmarks[to]!.y * scaleY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PosePainter oldDelegate) {
    return oldDelegate.poses != poses ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation;
  }
}
