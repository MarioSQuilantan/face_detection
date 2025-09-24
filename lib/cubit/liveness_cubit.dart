import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:camera/camera.dart';
import '../services/face_liveness_service.dart';

// Estado expuesto por el Cubit (duplicamos datos necesarios para desacoplar UI del servicio)
class LivenessState {
  final int stepIndex;
  final String instruction;
  final bool livenessConfirmed;
  final int faceStableFrames;
  final int noFaceFrames;
  final bool loadingService;

  const LivenessState({
    required this.stepIndex,
    required this.instruction,
    required this.livenessConfirmed,
    required this.faceStableFrames,
    required this.noFaceFrames,
    required this.loadingService,
  });

  factory LivenessState.initial() => const LivenessState(
    stepIndex: 0,
    instruction: 'Acerca tu rostro y míralo de frente',
    livenessConfirmed: false,
    faceStableFrames: 0,
    noFaceFrames: 0,
    loadingService: true,
  );

  LivenessState copyWith({
    int? stepIndex,
    String? instruction,
    bool? livenessConfirmed,
    int? faceStableFrames,
    int? noFaceFrames,
    bool? loadingService,
  }) => LivenessState(
    stepIndex: stepIndex ?? this.stepIndex,
    instruction: instruction ?? this.instruction,
    livenessConfirmed: livenessConfirmed ?? this.livenessConfirmed,
    faceStableFrames: faceStableFrames ?? this.faceStableFrames,
    noFaceFrames: noFaceFrames ?? this.noFaceFrames,
    loadingService: loadingService ?? this.loadingService,
  );
}

class LivenessCubit extends Cubit<LivenessState> {
  final FaceLivenessService _service;
  late final void Function() _listenerDisposer;

  LivenessCubit(this._service) : super(LivenessState.initial()) {
    // Suscribirnos al ValueNotifier del servicio
    _listenerDisposer = _bindService();
  }

  void markServiceReady() {
    emit(state.copyWith(loadingService: false));
  }

  void reset() {
    _service.reset();
    // El listener actualizará el estado automáticamente
  }

  CameraController get cameraController => _service.cameraController;
  bool get initialized => _service.initialized;

  void dispose() {
    _listenerDisposer();
    _service.dispose();
  }

  void _onServiceDataChanged() {
    final d = _service.data.value;
    emit(
      state.copyWith(
        stepIndex: d.stepIndex,
        instruction: d.instruction,
        livenessConfirmed: d.livenessConfirmed,
        faceStableFrames: d.faceStableFrames,
        noFaceFrames: d.noFaceFrames,
      ),
    );
  }

  void Function() _bindService() {
    void listener() => _onServiceDataChanged();
    _service.data.addListener(listener);
    return () => _service.data.removeListener(listener);
  }
}
