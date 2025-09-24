import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Representa el estado observable del flujo de liveness.
class LivenessData {
  final int stepIndex; // 0 rostro, 1 parpadeo, 2 cabeza izq, 3 cabeza der
  final String instruction;
  final bool livenessConfirmed;
  final int faceStableFrames;
  final int noFaceFrames;

  const LivenessData({
    required this.stepIndex,
    required this.instruction,
    required this.livenessConfirmed,
    required this.faceStableFrames,
    required this.noFaceFrames,
  });

  LivenessData copyWith({
    int? stepIndex,
    String? instruction,
    bool? livenessConfirmed,
    int? faceStableFrames,
    int? noFaceFrames,
  }) => LivenessData(
    stepIndex: stepIndex ?? this.stepIndex,
    instruction: instruction ?? this.instruction,
    livenessConfirmed: livenessConfirmed ?? this.livenessConfirmed,
    faceStableFrames: faceStableFrames ?? this.faceStableFrames,
    noFaceFrames: noFaceFrames ?? this.noFaceFrames,
  );
}

class FaceLivenessService {
  FaceLivenessService({
    this.requiredStableFrames = 5,
    this.maxNoFaceFrames = 20,
    this.blinkThreshold = 0.3,
    this.turnLeftThreshold = -15,
    this.turnRightThreshold = 15,
  });

  // Configuraciones
  final int requiredStableFrames;
  final int maxNoFaceFrames;
  final double blinkThreshold;
  final double turnLeftThreshold;
  final double turnRightThreshold;

  final ValueNotifier<LivenessData> data = ValueNotifier(
    const LivenessData(
      stepIndex: 0,
      instruction: 'Acerca tu rostro y míralo de frente',
      livenessConfirmed: false,
      faceStableFrames: 0,
      noFaceFrames: 0,
    ),
  );

  late final CameraController _cameraController;
  CameraController get cameraController => _cameraController;
  late final bool _isFrontCamera;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.15,
    ),
  );

  bool _isDetecting = false;
  bool get isDetecting => _isDetecting;

  bool _initialized = false;
  bool get initialized => _initialized;

  // (cooldown removido)

  Future<void> initialize(CameraDescription camera) async {
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _isFrontCamera = camera.lensDirection == CameraLensDirection.front;
    await _cameraController.initialize();
    await _cameraController.startImageStream(_processCameraImage);
    _initialized = true;
  }

  void reset({String? message}) {
    data.value = LivenessData(
      stepIndex: 0,
      instruction: message ?? 'Acerca tu rostro y míralo de frente',
      livenessConfirmed: false,
      faceStableFrames: 0,
      noFaceFrames: 0,
    );
  }

  void dispose() {
    if (_initialized) {
      _cameraController.dispose();
    }
    _faceDetector.close();
    data.dispose();
  }

  // ---------- Procesamiento principal ----------
  void _processCameraImage(CameraImage image) async {
    if (_isDetecting || data.value.livenessConfirmed) return;
    _isDetecting = true;

    try {
      InputImageFormat? mappedFormat;
      Uint8List? bytes;
      switch (image.format.group) {
        case ImageFormatGroup.bgra8888:
          mappedFormat = InputImageFormat.bgra8888;
          bytes = image.planes.first.bytes;
          break;
        case ImageFormatGroup.nv21:
          mappedFormat = InputImageFormat.nv21;
          final WriteBuffer allBytes = WriteBuffer();
          for (final plane in image.planes) {
            allBytes.putUint8List(plane.bytes);
          }
          bytes = allBytes.done().buffer.asUint8List();
          break;
        case ImageFormatGroup.yuv420:
          try {
            bytes = _convertYUV420ToNV21(image);
            mappedFormat = InputImageFormat.nv21;
          } catch (e) {
            if (kDebugMode) debugPrint('[Liveness][ERR] YUV->NV21: $e');
          }
          break;
        default:
          mappedFormat = null;
      }

      if (mappedFormat == null || bytes == null) {
        return;
      }

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation:
              InputImageRotation.rotation0deg, // asumido frontal (rotación ajustada no crítica para blink/head angles)
          format: mappedFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final current = data.value;
        final face = faces.first;
        int faceStable = current.faceStableFrames;
        int step = current.stepIndex;

        // Reset noFace
        int noFace = 0;

        switch (step) {
          case 0:
            faceStable++;
            if (faceStable >= requiredStableFrames) {
              step = 1;
              data.value = current.copyWith(
                stepIndex: step,
                instruction: '✅ Rostro detectado. Ahora parpadea',
                faceStableFrames: faceStable,
                noFaceFrames: noFace,
              );
              return;
            } else {
              data.value = current.copyWith(
                faceStableFrames: faceStable,
                instruction: 'Mantén tu rostro quieto ($faceStable/$requiredStableFrames)',
                noFaceFrames: noFace,
              );
              return;
            }
          case 1:
            if (_detectBlink(face)) {
              step = 2;
              data.value = current.copyWith(
                stepIndex: step,
                instruction: '✅ Bien, ahora gira la cabeza a la izquierda',
                noFaceFrames: noFace,
              );
              return;
            }
            break;
          case 2:
            if (_detectHeadTurnLeft(face)) {
              step = 3;
              data.value = current.copyWith(
                stepIndex: step,
                instruction: '✅ Perfecto, ahora gira la cabeza a la derecha',
                noFaceFrames: noFace,
              );
              return;
            }
            break;
          case 3:
            if (_detectHeadTurnRight(face)) {
              data.value = current.copyWith(
                instruction: '🎉 Validación completada con éxito',
                livenessConfirmed: true,
                noFaceFrames: noFace,
              );
              return;
            }
            break;
        }

        // Si no avanzó paso, mantener estado estable (sin cambiar instrucción) salvo counters
        data.value = current.copyWith(faceStableFrames: faceStable, noFaceFrames: noFace);
      } else {
        final current = data.value;
        final newNoFace = current.noFaceFrames + 1;
        if (current.stepIndex == 0) {
          // Reiniciar estabilidad si estaba acumulando
          final resetStable = current.faceStableFrames > 0 ? 0 : current.faceStableFrames;
          data.value = current.copyWith(
            faceStableFrames: resetStable,
            noFaceFrames: newNoFace,
            instruction: 'Acerca tu rostro y míralo de frente',
          );
        } else if (!current.livenessConfirmed && newNoFace >= maxNoFaceFrames) {
          reset(message: 'Rostro perdido. Reiniciando. Acerca tu rostro de nuevo');
        } else {
          data.value = current.copyWith(noFaceFrames: newNoFace);
        }
      }
    } finally {
      _isDetecting = false;
    }
  }

  // ---------- Detectores simples ----------
  bool _detectBlink(Face face) {
    final l = face.leftEyeOpenProbability ?? 1.0;
    final r = face.rightEyeOpenProbability ?? 1.0;
    return l < blinkThreshold && r < blinkThreshold;
  }

  bool _detectHeadTurnLeft(Face face) {
    final angleY = face.headEulerAngleY ?? 0.0;
    final adj = _isFrontCamera ? -angleY : angleY; // invertir para cámara frontal (imagen espejada)
    return adj < turnLeftThreshold;
  }

  bool _detectHeadTurnRight(Face face) {
    final angleY = face.headEulerAngleY ?? 0.0;
    final adj = _isFrontCamera ? -angleY : angleY;
    return adj > turnRightThreshold;
  }

  // ---------- Utilidad conversión NV21 ----------
  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];
    final int ySize = width * height;
    final int uvSize = width * height ~/ 4;
    final Uint8List nv21 = Uint8List(ySize + 2 * uvSize);
    int offset = 0;
    for (int row = 0; row < height; row++) {
      final int rowStart = row * yPlane.bytesPerRow;
      nv21.setRange(offset, offset + width, yPlane.bytes.sublist(rowStart, rowStart + width));
      offset += width;
    }
    final int uvHeight = height ~/ 2;
    final int uvWidth = width ~/ 2;
    int vuOffset = ySize;
    final int uRowStride = uPlane.bytesPerRow;
    final int vRowStride = vPlane.bytesPerRow;
    final int uPixelStride = uPlane.bytesPerPixel ?? 1;
    final int vPixelStride = vPlane.bytesPerPixel ?? 1;
    for (int row = 0; row < uvHeight; row++) {
      final int uRowStart = row * uRowStride;
      final int vRowStart = row * vRowStride;
      for (int col = 0; col < uvWidth; col++) {
        final int uIndex = uRowStart + col * uPixelStride;
        final int vIndex = vRowStart + col * vPixelStride;
        nv21[vuOffset++] = vPlane.bytes[vIndex];
        nv21[vuOffset++] = uPlane.bytes[uIndex];
      }
    }
    return nv21;
  }
}
