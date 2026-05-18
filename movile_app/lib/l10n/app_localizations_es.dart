// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Splitway';

  @override
  String get appTagline => 'Cronómetro inteligente para rutas';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonBack => 'Volver';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonClose => 'Entendido';

  @override
  String get commonRefresh => 'Recargar';

  @override
  String get commonDiscard => 'Descartar';

  @override
  String get languageEnglish => 'Inglés';

  @override
  String get languageSpanish => 'Español';

  @override
  String get navEditor => 'Editor';

  @override
  String get navSession => 'Sesión';

  @override
  String get navHistory => 'Historial';

  @override
  String get drawerMenu => 'Menú';

  @override
  String get drawerDefaultUser => 'Usuario';

  @override
  String get drawerSettings => 'Configuración';

  @override
  String get drawerStats => 'Estadísticas';

  @override
  String get drawerHelp => 'Ayuda';

  @override
  String get drawerSignOut => 'Cerrar sesión';

  @override
  String get drawerSignIn => 'Iniciar sesión';

  @override
  String drawerAppVersion(String version) {
    return 'v$version';
  }

  @override
  String get drawerSyncSynced => 'SINCRONIZADO';

  @override
  String get drawerSyncSyncedNow => 'SINCRONIZADO · ahora';

  @override
  String drawerSyncSyncedMinutes(int minutes) {
    return 'SINCRONIZADO · hace $minutes min';
  }

  @override
  String drawerSyncSyncedAt(String time) {
    return 'SINCRONIZADO · $time';
  }

  @override
  String get drawerSyncSyncing => 'SINCRONIZANDO…';

  @override
  String get drawerSyncError => 'ERROR DE SYNC';

  @override
  String get drawerSyncOffline => 'SIN CONEXIÓN';

  @override
  String get drawerSyncNow => 'Sincronizar ahora';

  @override
  String get loginBannerDefault => 'Inicia sesión para continuar';

  @override
  String get loginEmailHint => 'Email';

  @override
  String get loginPasswordHint => 'Contraseña';

  @override
  String get loginEmailRequired => 'Introduce un email';

  @override
  String get loginEmailInvalid => 'Email no válido';

  @override
  String get loginPasswordRequired => 'Introduce una contraseña';

  @override
  String get loginPasswordMinLength => 'Mínimo 6 caracteres';

  @override
  String get loginSignInButton => 'Iniciar sesión';

  @override
  String get loginSignUpButton => 'Crear cuenta';

  @override
  String get loginOrSeparator => '— o —';

  @override
  String get loginContinueWithGoogle => 'Continuar con Google';

  @override
  String get loginToggleToSignUp => '¿No tienes cuenta? ';

  @override
  String get loginToggleToSignIn => '¿Ya tienes cuenta? ';

  @override
  String get loginToggleSignUpAction => 'Regístrate';

  @override
  String get loginToggleSignInAction => 'Inicia sesión';

  @override
  String get loginSkipButton => 'Continuar sin cuenta';

  @override
  String get loginConfirmationTitle => '¡Revisa tu correo!';

  @override
  String loginConfirmationBody(String email) {
    return 'Te hemos enviado un enlace de confirmación a\n$email\n\nHaz clic en el enlace para activar tu cuenta y poder iniciar sesión.';
  }

  @override
  String get authErrorGoogleToken => 'No se pudo obtener el token de Google.';

  @override
  String get authErrorEmailAlreadyRegistered =>
      'Este email ya está registrado. Inicia sesión.';

  @override
  String get authErrorInvalidCredentials => 'Email o contraseña incorrectos.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Confirma tu email antes de iniciar sesión.';

  @override
  String get authErrorPasswordTooShort =>
      'La contraseña debe tener al menos 6 caracteres.';

  @override
  String get authErrorNoConnection => 'Sin conexión. Inténtalo de nuevo.';

  @override
  String get authErrorUnexpected => 'Error inesperado. Inténtalo de nuevo.';

  @override
  String get editorTitle => 'Editor de rutas';

  @override
  String get editorNewRouteTooltip => 'Nueva ruta';

  @override
  String get editorNewRouteButton => 'Nueva ruta';

  @override
  String get editorNoRoutesTitle => 'Aún no tienes rutas';

  @override
  String get editorNoRoutesMessage =>
      'Crea tu primera ruta para empezar a cronometrar.';

  @override
  String get editorSectorsLabel => 'Sectores';

  @override
  String editorSectorCenter(String lat, String lng) {
    return 'Centro: $lat, $lng';
  }

  @override
  String get editorStartFinishLabel => 'Inicio / meta';

  @override
  String editorCreatedAt(String date) {
    return 'Creada el $date';
  }

  @override
  String get editorDeleteRouteButton => 'Eliminar ruta';

  @override
  String get editorDeleteRouteTitle => 'Eliminar ruta';

  @override
  String editorDeleteRouteConfirm(String routeName) {
    return '¿Borrar \"$routeName\" y todas sus sesiones?';
  }

  @override
  String get editorModeAppendPath => 'Trazado';

  @override
  String get editorModeStartGate => 'Inicio / meta';

  @override
  String get editorModeSectorGate => 'Añadir sector';

  @override
  String editorDrawingTitle(String draftName) {
    return 'Dibujando: $draftName';
  }

  @override
  String get editorCancelTooltip => 'Cancelar';

  @override
  String get editorCancelDrawingTitle => 'Cancelar dibujo';

  @override
  String get editorCancelDrawingWarning =>
      'Se descartarán los puntos sin guardar.';

  @override
  String get editorNoMapboxToken =>
      'Sin Mapbox token configurado. El mapa interactivo está desactivado; para probar el dibujo, añade un token y reinicia.';

  @override
  String get editorSegmentPath => 'Trazado';

  @override
  String get editorSegmentStartFinish => 'Inicio / meta';

  @override
  String get editorSegmentAddSector => 'Añadir sector';

  @override
  String get editorSegmentFreehand => 'A mano';

  @override
  String get editorModeFreehand => 'Dibujo a mano alzada';

  @override
  String get editorUndoFreehand => 'Deshacer trazo';

  @override
  String get editorUndoPoint => 'Deshacer punto';

  @override
  String editorPathPoints(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count puntos',
      one: '1 punto',
      zero: 'Sin puntos',
    );
    return '$_temp0';
  }

  @override
  String get editorStartGateUndefined => 'Sin inicio';

  @override
  String get editorStartGateDefined => 'Inicio definido';

  @override
  String editorSectorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sectores',
      one: '1 sector',
      zero: 'Sin sectores',
    );
    return '$_temp0';
  }

  @override
  String get editorWaitingSecondPoint => 'Falta el 2º punto…';

  @override
  String get editorDifficultyEasy => 'Fácil';

  @override
  String get editorDifficultyMedium => 'Media';

  @override
  String get editorDifficultyHard => 'Difícil';

  @override
  String get editorHideSectors => 'Ocultar sectores';

  @override
  String get editorShowSectors => 'Ver sectores';

  @override
  String get editorNoSectorsHint => 'Sin sectores';

  @override
  String get editorClosedLoop => 'Circuito cerrado';

  @override
  String get editorOpenRoute => 'Circuito abierto';

  @override
  String editorRouteSavedSnack(String name) {
    return 'Guardada \"$name\"';
  }

  @override
  String get editorSnapFailedMessage =>
      'No se pudo conectar con el servidor para ajustar la ruta a las carreteras. Se muestran segmentos rectos hasta que la conexión se restablezca.';

  @override
  String get editorNewRouteDialogTitle => 'Nueva ruta';

  @override
  String get editorNameLabel => 'Nombre';

  @override
  String get editorDescriptionLabel => 'Descripción (opcional)';

  @override
  String get editorDifficultyLabel => 'Dificultad';

  @override
  String get editorStartDrawingButton => 'Empezar a dibujar';

  @override
  String get historyTitle => 'Historial';

  @override
  String get historyNoSessionsTitle => 'Aún no has grabado ninguna sesión';

  @override
  String get historyNoSessionsMessage =>
      'Ve a la pestaña Sesión, elige una ruta y pulsa \"Comenzar\".';

  @override
  String get historyDeletedRoute => 'Ruta eliminada';

  @override
  String historySessionSubtitle(String date, int lapCount, String bestLap) {
    String _temp0 = intl.Intl.pluralLogic(
      lapCount,
      locale: localeName,
      other: '$lapCount vueltas',
      one: '1 vuelta',
    );
    return '$date · $_temp0$bestLap';
  }

  @override
  String get historySessionTitle => 'Sesión';

  @override
  String get historyDeleteSessionTitle => 'Eliminar sesión';

  @override
  String get historyIrreversibleWarning => 'Esta acción no se puede deshacer.';

  @override
  String get historySessionNotFound => 'Sesión no encontrada';

  @override
  String get historyLapsLabel => 'Vueltas';

  @override
  String get historySectorsLabel => 'Sectores';

  @override
  String historySectorSubtitle(int lapNum, String speed) {
    return 'Vuelta $lapNum · $speed';
  }

  @override
  String get historyDistanceLabel => 'Distancia';

  @override
  String get historyMaxSpeedLabel => 'Vel. máx';

  @override
  String get historyAvgSpeedLabel => 'Vel. media';

  @override
  String get sessionTitle => 'Sesión en vivo';

  @override
  String get sessionNoRoutesTitle => 'No hay rutas para correr';

  @override
  String get sessionNoRoutesMessage =>
      'Crea una ruta primero en la pestaña Editor para poder grabar una sesión.';

  @override
  String get sessionSelectRoute => 'Selecciona una ruta';

  @override
  String get sessionTelemetrySource => 'Fuente de telemetría';

  @override
  String get sessionSourceSimulated => 'Simulada';

  @override
  String get sessionSourceRealGps => 'GPS real';

  @override
  String get sessionStartButton => 'Comenzar grabación';

  @override
  String get sessionSimulatedHint =>
      'Pulsa \"Simular punto\" para avanzar, o \"Auto vuelta\" para correr una vuelta automáticamente.';

  @override
  String get sessionRealGpsHint =>
      'Asegúrate de tener la ubicación activada. Los puntos se capturan cada segundo.';

  @override
  String get sessionSavedSnackBar => 'Sesión guardada';

  @override
  String get sessionFinishButton => 'Finalizar y guardar';

  @override
  String get sessionCompleteTitle => 'Sesión completa';

  @override
  String sessionRouteLabel(String routeName) {
    return 'Ruta: $routeName';
  }

  @override
  String get sessionLapsLabel => 'Vueltas';

  @override
  String get sessionNewSessionButton => 'Nueva sesión';

  @override
  String get sessionCurrentLapLabel => 'Vuelta actual';

  @override
  String sessionLapNumber(int n) {
    return '#$n';
  }

  @override
  String get sessionNoLapYet => '–';

  @override
  String get sessionLapTimeLabel => 'Tiempo en vuelta';

  @override
  String get sessionBestLapLabel => 'Mejor vuelta';

  @override
  String get sessionAwaitingStart => 'Esperando primer cruce de meta…';

  @override
  String get sessionCrossingSectors => 'Cruzando sectores…';

  @override
  String sessionLastSector(String sectorId) {
    return 'Último sector: $sectorId';
  }

  @override
  String get sessionDistanceLabel => 'Distancia';

  @override
  String get sessionMaxSpeedLabel => 'Vel. máx.';

  @override
  String get sessionAvgSpeedLabel => 'Vel. media';

  @override
  String get sessionLapsCountLabel => 'Vueltas';

  @override
  String get sessionPermissionGranted => 'Permiso de ubicación concedido.';

  @override
  String get sessionPermissionDenied =>
      'Permiso de ubicación denegado. Acepta el diálogo del sistema o cambia a \"Simulada\".';

  @override
  String get sessionPermissionPermanentlyDenied =>
      'Permiso bloqueado permanentemente. Actívalo manualmente en los ajustes del sistema.';

  @override
  String get sessionServicesDisabled =>
      'Servicios de ubicación desactivados. Enciéndelos en los ajustes del sistema.';

  @override
  String sessionGpsStatus(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count muestras',
      one: '1 muestra',
    );
    return 'GPS real · $_temp0';
  }

  @override
  String sessionGpsAccuracy(String accuracy, String lat, String lng) {
    return 'Precisión: $accuracy m · $lat, $lng';
  }

  @override
  String get sessionAwaitingFirstFix => 'Esperando primer fix…';

  @override
  String get sessionSimulatePoint => 'Simular punto';

  @override
  String get sessionPauseAuto => 'Parar auto';

  @override
  String get sessionAutoLap => 'Auto vuelta';

  @override
  String get sessionSpeedLabel => 'Velocidad:';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsLanguageSection => 'Idioma';

  @override
  String get settingsLanguageDescription => 'Elige el idioma de la interfaz.';

  @override
  String unitMeters(String value) {
    return '$value m';
  }

  @override
  String unitKilometers(String value) {
    return '$value km';
  }

  @override
  String unitKmh(String value) {
    return '$value km/h';
  }

  @override
  String get mapNoRoute => 'Sin ruta';

  @override
  String historyBestLapSuffix(String duration) {
    return ' · mejor $duration';
  }
}
