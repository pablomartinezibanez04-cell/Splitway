# Mejora de detección de tiempo de reacción — Calibración de gravedad

**Fecha:** 2026-06-01
**Feature:** Speed test → Reaction time
**Archivo principal:** `lib/src/services/speed/speed_measurement_service.dart`

## Problema

El tiempo de reacción se registra con valores artificialmente altos (150-400ms de más). Causas:

1. **Gravedad restada con constante fija (9.81)**: varía por dispositivo, orientación y ubicación. Introduce ruido que enmascara aceleraciones reales pequeñas.
2. **Umbral de acelerómetro demasiado alto (1.0 m/s²)**: un coche arrancando suavemente genera 0.3-0.5 m/s² iniciales, que no se detectan.
3. **Sustain de 100ms**: añade latencia innecesaria cuando la señal es limpia.
4. **GPS a ~1 Hz**: demasiado lento como detector primario de movimiento.

## Solución: Calibración de gravedad + ajuste de umbrales

### Calibración de gravedad en fase armed

Durante la fase `armed` el coche está obligatoriamente quieto (si no, salta false start). Se aprovecha ese tiempo para calibrar la gravedad real del dispositivo.

**Mecanismo:**
- Al suscribir sensores en `liveArm()`, se empiezan a acumular las magnitudes raw del acelerómetro (sqrt(x² + y² + z²)) en un buffer circular de 50 muestras (~0.5-1s a 50-100 Hz).
- Se calcula la media de ese buffer como `_calibratedGravity`.
- Fallback: si no hay suficientes muestras, se usa 9.81.
- Al entrar en fase `running` (`liveStart()`), se congela `_calibratedGravity` y se usa para restar en cada muestra.

**Nuevos campos en `SpeedMeasurementService`:**
- `double _calibratedGravity = 9.81` — gravedad calibrada, inicializada con fallback
- `List<double> _calibrationSamples = []` — buffer circular de magnitudes en reposo (se descartan las más antiguas al superar `_calibrationWindowSize`)
- `static const int _calibrationWindowSize = 50` — tamaño del buffer

### Nuevos umbrales de reaction time

| Parámetro | Antes | Después |
|-----------|-------|---------|
| `_reactionAccelMs2` | 1.0 m/s² | 0.3 m/s² |
| `_reactionSpeedKmh` | 0.5 km/h | 0.5 km/h (sin cambio) |
| `_reactionSustain` | 100ms | 50ms |

**Justificación:**
- Con gravedad calibrada, el ruido en reposo baja a <0.1 m/s². Umbral de 0.3 m/s² da 3x de margen sobre el ruido.
- 50ms de sustain = 2-5 muestras consecutivas a 50-100 Hz. Suficiente para filtrar picos aislados.

### False start: sin cambios

Los umbrales de false start se mantienen en 1.5 m/s² / 1.5 km/h / 150ms. Son conservadores por diseño — un false start falso es peor que uno no detectado.

## Flujo de datos

```
liveArm()
  └─ Suscribe acelerómetro + GPS
  └─ Fase armed:
       ├─ Acelerómetro → alimenta _calibrationSamples → actualiza _calibratedGravity
       └─ Acelerómetro → _checkFalseStart() (sin cambios)

liveStart()
  └─ Congela _calibratedGravity
  └─ Resetea distancia y reloj
  └─ Fase running:
       ├─ Acelerómetro → resta _calibratedGravity → genera SpeedSample
       ├─ Reaction: accel ≥ 0.3 m/s² OR GPS ≥ 0.5 km/h, sustain 50ms
       └─ Milestones: sin cambios
```

## Archivos afectados

| Archivo | Cambio |
|---------|--------|
| `speed_measurement_service.dart` | Calibración de gravedad, nuevos umbrales |
| `speed_measurement_service_test.dart` | Tests para calibración y nuevos umbrales |

## Archivos NO afectados

- `speed_sample.dart` — sin cambios
- `speed_session_controller.dart` — no sabe de sensores
- `speed_session.dart` — modelo de datos sin cambios
- `speed_metric.dart` — enum sin cambios

## Ganancia estimada

- Reducción de 150-400ms en la latencia de detección del tiempo de reacción
- Detección uniforme en Android e iOS (basada en acelerómetro, no en GPS)
- Sin impacto en batería (misma frecuencia de muestreo)

## Testing

- Test de calibración: inyectar muestras en fase armed, verificar que `_calibratedGravity` se calcula correctamente
- Test de reaction time con nuevos umbrales: verificar detección con aceleración de 0.3-0.5 m/s²
- Test de que false start no se ve afectado por los cambios
- Tests existentes de milestones deben seguir pasando sin modificación
