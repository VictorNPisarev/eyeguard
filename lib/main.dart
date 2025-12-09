import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';



late List<CameraDescription> cameras;

Future<void> main() async 
{
  WidgetsFlutterBinding.ensureInitialized();

  // Запрос разрешений
  await Permission.camera.request();
  cameras = await availableCameras();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget 
{
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) 
  {
    return MaterialApp
    (
      home: CameraScreen
      (
        camera: cameras.firstWhere
        (
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        ),
      ),
    );
  }
}


class CameraScreen extends StatefulWidget 
{
  final CameraDescription camera;
  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> 
{
  late CameraController _controller;
  late FaceDetector _faceDetector;
  String _status = "Ожидание...";
  bool _isAutoAnalysisRunning = false;
  int _analysisIntervalSeconds = 30;
  int tempInterval = 30;
  Timer? _analysisTimer;

  @override
  void initState() 
  {
    super.initState();

    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    _controller.initialize().then((_) 
    {
      if (!mounted) return;
      setState(() {});
      _startPeriodicAnalysis(); // ← запуск автоматического анализа
    });

    _faceDetector = FaceDetector
    (
      options: FaceDetectorOptions
      (
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
        enableClassification: true,
      ),
    );
  }

  void _startDetection() 
  {
    _updateStatus("Запуск анализа потока...");
    _controller.startImageStream
    (
      (image) async 
      {
        _updateStatus("befor _inputImageFromCameraImage");
        final inputImage = _inputImageFromCameraImage(image);
        _updateStatus("after _inputImageFromCameraImage");

        if (inputImage == null) 
        {
          _updateStatus("inputImage == null");
          // Можно добавить логирование, если не удалось создать изображение
          return;
        }
      
        _updateStatus("inputImage != null");

        final faces = await _faceDetector.processImage(inputImage);

        _updateStatus("_faceDetector.processImage");

        if (faces.isEmpty) 
        {
          _updateStatus("Лицо не найдено");
          return;
        }

          _updateStatus("faces is not Empty");

        final face = faces.first;
        final leftOpen = face.leftEyeOpenProbability ?? 0.5;
        final rightOpen = face.rightEyeOpenProbability ?? 0.5;

        if (leftOpen < 0.2 && rightOpen < 0.2) 
        {
          _updateStatus("⚠️ ГЛАЗА ЗАКРЫТЫ!");
        } 
        else 
        {
          _updateStatus("Глаза открыты");
        }
      }
    );
  }

  Future<void> _analyzeCurrentFrame() async {
    if (!_controller.value.isInitialized) return;

    _updateStatus("📸 Делаем снимок...");

    try {
      final XFile photo = await _controller.takePicture();
      final inputImage = InputImage.fromFilePath(photo.path);

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        _updateStatus("👀 Лицо не найдено");
        return;
      }

      final face = faces.first;

      // === Глаза ===
      final leftOpen = face.leftEyeOpenProbability ?? 0.5;
      final rightOpen = face.rightEyeOpenProbability ?? 0.5;
      final eyesStatus = (leftOpen < 0.2 && rightOpen < 0.2)
          ? "⚠️ Глаза закрыты"
          : "✅ Глаза открыты";

      // === "GUID" на основе landmarks ===
      final signature = _computeFaceSignature(face.landmarks);
      final faceHash = _vectorToHash(signature);

      _updateStatus("$eyesStatus\n👤 ID: $faceHash");
    } catch (e) {
      _updateStatus("💥 Ошибка: $e");
    }
  }

  void _startPeriodicAnalysis() {
    _analysisTimer = Timer.periodic(
      Duration(seconds: _analysisIntervalSeconds),
      (_) => _analyzeCurrentFrame(),
    );
  }

  void _stopAutoAnalysis() {
    _analysisTimer?.cancel();
    _analysisTimer = null;
  }

  void _toggleAutoAnalysis() 
  {
    if (_isAutoAnalysisRunning) {
      _stopAutoAnalysis();
      _updateStatus("Автоанализ остановлен");
    } else {
      _startPeriodicAnalysis();
      _updateStatus("Автоанализ запущен");
    }
    setState(() {
      _isAutoAnalysisRunning = !_isAutoAnalysisRunning;
    });
  }

  void _updateStatus(String status) 
  {
    if (mounted) 
    {
      setState
      (
        () 
        {
          _status = status;
        }
      );
    }
  }

  @override
  void dispose() 
  {
    _stopAutoAnalysis();
    _controller.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) 
  {
    if (!_controller.value.isInitialized) 
    {
      return const Scaffold(body: Center(child: Text("Инициализация камеры...")));
    }

    return Scaffold
    (
      body: Stack
      (
        children: 
        [
          CameraPreview(_controller),
          Positioned
          (
            top: 80,
            left: 0,
            right: 0,
            child: Text
            (
              _status,
              textAlign: TextAlign.center,
              style: TextStyle
              (
                color: _status.contains("ГЛАЗА ЗАКРЫТЫ") ? Colors.red : Colors.green,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column
      (
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _toggleAutoAnalysis,
            child: Icon(_isAutoAnalysisRunning ? Icons.stop : Icons.play_arrow),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            onPressed: _showIntervalDialog,
            child: const Icon(Icons.timer),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            onPressed: _analyzeCurrentFrame, // ручной запуск
            child: const Icon(Icons.camera),
          ),
        ],
      ),
    );
  }

  void _showIntervalDialog() 
  {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Интервал анализа"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Каждые $tempInterval секунд"),
            Slider(
              value: tempInterval.toDouble(),
              min: 5,
              max: 120,
              divisions: 115,
              label: "$tempInterval сек",
              onChanged: (value) {
                setState(() {
                  tempInterval = value.toInt();
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
          TextButton(
            onPressed: () {
              // Применяем новое значение
              setState(() {
                _analysisIntervalSeconds = tempInterval;
              });
              // Если автоанализ запущен — перезапускаем с новым интервалом
              if (_isAutoAnalysisRunning) {
                _stopAutoAnalysis();
                _startPeriodicAnalysis();
              }
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  ///функции анализа контрольных точек
  List<double> _computeFaceSignature(Map<FaceLandmarkType, FaceLandmark?> landmarksMap) {
    // Получаем нужные точки из map
    final FaceLandmark? nose = landmarksMap[FaceLandmarkType.noseBase];
    final FaceLandmark? leftEye = landmarksMap[FaceLandmarkType.leftEye];
    final FaceLandmark? rightEye = landmarksMap[FaceLandmarkType.rightEye];

    if (nose == null || leftEye == null || rightEye == null) {
      return List.filled(72, 0.0);
    }

    final Point<num> nosePoint = nose.position;
    final Point<num> leftEyePoint = leftEye.position;
    final Point<num> rightEyePoint = rightEye.position;

    // Масштаб: расстояние между глазами
    final eyeDistance = sqrt(
      pow(rightEyePoint.x - leftEyePoint.x, 2) +
      pow(rightEyePoint.y - leftEyePoint.y, 2),
    );
    final scale = eyeDistance == 0 ? 1.0 : eyeDistance;

    // Теперь обрабатываем ВСЕ 36 точки из FaceLandmarkType.values
    final List<double> normalized = [];
    for (final type in FaceLandmarkType.values) {
      final FaceLandmark? landmark = landmarksMap[type];
      if (landmark != null) {
        final dx = (landmark.position.x - nosePoint.x) / scale;
        final dy = (landmark.position.y - nosePoint.y) / scale;
        normalized.add(dx.toDouble());
        normalized.add(dy.toDouble());
      } else {
        normalized.add(0.0);
        normalized.add(0.0);
      }
    }

    return normalized;
  }

  String _vectorToHash(List<double> vec) 
  {
    // Суммируем координаты с весом, чтобы получить стабильное число
    double hashValue = 0.0;
    for (int i = 0; i < vec.length; i++) {
      hashValue += vec[i] * (i + 1);
    }
    // Берём дробную часть и делаем строку
    final int intHash = (hashValue * 1000000).abs().toInt() % 99999999;
    return intHash.toString().padLeft(8, '0');
  }


  /// ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ КОНВЕРТАЦИИ
  /// Преобразует CameraImage из плагина camera в InputImage для ML Kit
  InputImage? _inputImageFromCameraImage(CameraImage image) 
  {
    _updateStatus("внутри _inputImageFromCameraImage");
    // ИСПРАВЛЕНИЕ: Используем специальное расширение InputImageFormatValue.fromRawValue
    final InputImageFormat? format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (format == null) 
    {
      // Если формат не распознан, возвращаем null
      _updateStatus("Неподдерживаемый формат изображения: ${image.format.raw}");
      return null;
    }
    
    _updateStatus("format != null");
    
    // Определяем поворот (оставляем заглушку, но в реальном приложении это важно)
    const InputImageRotation rotation = InputImageRotation.rotation0deg; 

    // Метаданные изображения
    final InputImageMetadata metadata = InputImageMetadata
    (
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow, 
    );

    // Создаем InputImage через fromBytes
    return InputImage.fromBytes
    (
      bytes: image.planes.first.bytes, 
      metadata: metadata,
    );
  }

}