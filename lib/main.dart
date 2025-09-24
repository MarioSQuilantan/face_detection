import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'services/face_liveness_service.dart';
import 'cubit/liveness_cubit.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, home: LivenessCheckScreen());
  }
}

class LivenessCheckScreen extends StatefulWidget {
  const LivenessCheckScreen({super.key});

  @override
  State<LivenessCheckScreen> createState() => _LivenessCheckScreenState();
}

class _LivenessCheckScreenState extends State<LivenessCheckScreen> {
  LivenessCubit? _cubit;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final service = FaceLivenessService();
    final front = _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
    await service.initialize(front);
    final cubit = LivenessCubit(service);
    cubit.markServiceReady();
    if (mounted) {
      setState(() => _cubit = cubit);
    } else {
      cubit.dispose();
    }
  }

  @override
  void dispose() {
    _cubit?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _cubit;
    if (cubit == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final service = cubit.cameraController; // using exposed cameraController getter
    return BlocProvider.value(
      value: cubit,
      child: BlocBuilder<LivenessCubit, LivenessState>(
        builder: (context, state) {
          if (state.loadingService) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Prueba de Vida')),
            body: SafeArea(
              child: Column(
                children: [
                  AspectRatio(aspectRatio: service.value.aspectRatio, child: CameraPreview(service)),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(state.instruction, style: const TextStyle(fontSize: 20), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 12),
                  _buildProgressIndicators(state),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.read<LivenessCubit>().reset(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reiniciar proceso'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgressIndicators(LivenessState d) {
    final steps = const ['Rostro', 'Parpadeo', 'Cabeza Izq.', 'Cabeza Der.'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(steps.length, (i) {
        final done = i < d.stepIndex || d.livenessConfirmed;
        final current = i == d.stepIndex && !d.livenessConfirmed;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: done
                ? Colors.green
                : current
                ? Colors.amber
                : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              if (done) const Icon(Icons.check, size: 14, color: Colors.white),
              if (done) const SizedBox(width: 4),
              Text(steps[i], style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        );
      }),
    );
  }
}
