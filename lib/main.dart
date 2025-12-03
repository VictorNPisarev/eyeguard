import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';


late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Запрос разрешений
  await Permission.camera.request();
  cameras = await availableCameras();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraScreen(
        camera: cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        ),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late FaceDetector _faceDetector;
  String _status = "Ожидание...";

  @override
  void initState() {
    super.initState();

    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _startDetection();
    });

    // Настройка детектора лиц
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true, // ← включает точки глаз
        enableClassification: true, // ← включает open/closed
      ),
    );
  }

  void _startDetection() {
    _controller.startImageStream((image) async {
    final inputImage = _inputImageFromCameraImage(image);

    if (inputImage == null) {
      // Можно добавить логирование, если не удалось создать изображение
      return;
    }
    
final faces = await _faceDetector.processImage(inputImage);
if (faces.isEmpty) {
  _updateStatus("Лицо не найдено");
  return;
}

final face = faces.first;
final leftOpen = face.leftEyeOpenProbability ?? 0.5;
final rightOpen = face.rightEyeOpenProbability ?? 0.5;

if (leftOpen < 0.2 && rightOpen < 0.2) {
  _updateStatus("⚠️ ГЛАЗА ЗАКРЫТЫ!");
} else {
  _updateStatus("Глаза открыты");
}    });
  }

  void _updateStatus(String status) {
    if (mounted) {
      setState(() {
        _status = status;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(body: Center(child: Text("Инициализация камеры...")));
    }

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_controller),
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _status.contains("ГЛАЗА ЗАКРЫТЫ") ? Colors.red : Colors.green,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ КОНВЕРТАЦИИ
  /// Преобразует CameraImage из плагина camera в InputImage для ML Kit
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    // ИСПРАВЛЕНИЕ: Используем специальное расширение InputImageFormatValue.fromRawValue
    final InputImageFormat? format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (format == null) {
      // Если формат не распознан, возвращаем null
      print("Неподдерживаемый формат изображения: ${image.format.raw}");
      return null;
    }
    
    // Определяем поворот (оставляем заглушку, но в реальном приложении это важно)
    const InputImageRotation rotation = InputImageRotation.rotation0deg; 

    // Метаданные изображения
    final InputImageMetadata metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow, 
    );

    // Создаем InputImage через fromBytes
    return InputImage.fromBytes(
      bytes: image.planes.first.bytes, 
      metadata: metadata,
    );
  }

}