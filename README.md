# face_detection

Aplicación Flutter para demostración de detección facial y flujo de "liveness" (parpadeo + giros de cabeza).

## Descripción

Este proyecto integra la cámara de dispositivo con el detector de rostros de ML Kit y expone una pequeña máquina de estados para validar "liveness" en 4 pasos:

- Paso 0: Estabilidad del rostro (mantener la cara quieta durante N frames).
- Paso 1: Detectar parpadeo (blink) mediante la probabilidad de ojos abiertos.
- Paso 2: Girar la cabeza a la izquierda (umbral de yaw).
- Paso 3: Girar la cabeza a la derecha (umbral de yaw).

## Arquitectura

- `lib/services/face_liveness_service.dart`: encapsula la inicialización de la cámara, conversión de imagen (YUV420 -> NV21) y la lógica de detección y pasos.
- `lib/cubit/liveness_cubit.dart`: capa ligera (Cubit) que expone el estado al UI.
- `lib/main.dart`: interfaz de usuario y wiring con `BlocProvider` / `BlocBuilder`.

## Dependencias clave

- camera
- google_mlkit_face_detection
- flutter_bloc

## Version Flutter

```bash
3.35.1
```

## Cómo ejecutar (macOS / iOS / Android)

1. Asegúrate de tener Flutter configurado y disponible en tu PATH.
2. Desde la raíz del proyecto ejecuta:

```bash
flutter pub get
```

3. Conecta un dispositivo o inicia un emulador/simulador que tenga cámara.
4. Ejecuta la app:

```bash
flutter run
```

## Permisos necesarios

- Android: asegúrate de tener los permisos de cámara en `AndroidManifest.xml`.
- iOS: configura la clave `NSCameraUsageDescription` en `Info.plist`.

## Notas de uso y pruebas

- La vista previa de la cámara está basada en `camera` y el procesamiento de frames ocurre en `FaceLivenessService`.
- Si la app no detecta rostros, intenta las siguientes acciones:
  - Asegúrate de buena iluminación.
  - Mantén la cámara enfocada al rostro a una distancia razonable.
  - Prueba con y sin modo de cámara frontal/trasera.
