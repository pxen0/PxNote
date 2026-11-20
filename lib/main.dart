import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ---------------------------------------------------------------------------
// Dil sistemi
// ---------------------------------------------------------------------------
final ValueNotifier<String> langNotifier = ValueNotifier<String>('en');
final ValueNotifier<ThemeMode> themeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.dark);

const List<String> kLangs = ['tr', 'en', 'es'];
const String kLangKey = 'lang_v1';
const String kThemeKey = 'theme_v1';

const Map<String, Map<String, String>> _strings = {
  'tr': {
    'new': 'Yeni',
    'empty': 'Henüz not yok',
    'newReminder': 'Yeni not',
    'title': 'Başlık',
    'note': 'Not (isteğe bağlı)',
    'onlyNotif': 'Sadece Bildirim',
    'alarm': 'Alarm',
    'save': 'Kaydet',
    'enterTitle': 'Başlık gerekli',
    'pastTime': 'Seçilen zaman geçmişte. İleri bir zaman seç.',
    'stopAlarm': 'Alarmı durdur',
    'alarmStopped': 'Alarm durduruldu',
    'delete': 'Sil',
    'stop': 'Durdur',
    'alarmDefault': 'Alarm',
    'reminderDefault': 'Hatırlatıcı',
    'language': 'Dil',
    'noteDeleted': 'Not silindi',
    'undo': 'Geri Al',
    'pin': 'Sabitle',
    'unpin': 'Sabitlemeyi kaldır',
    'markDone': 'Tamamlandı olarak işaretle',
    'close': 'Kapat',
    'pinned': 'Sabitlenenler',
    'others': 'Diğer notlar',
    'completed': 'Tamamlananlar',
    'toLight': 'Açık tema',
    'toDark': 'Koyu tema',
  },
  'en': {
    'new': 'New',
    'empty': 'No notes yet',
    'newReminder': 'New note',
    'title': 'Title',
    'note': 'Note (optional)',
    'onlyNotif': 'Notification only',
    'alarm': 'Alarm',
    'save': 'Save',
    'enterTitle': 'Title is required',
    'pastTime': 'That time has passed. Pick a later time.',
    'stopAlarm': 'Stop alarm',
    'alarmStopped': 'Alarm stopped',
    'delete': 'Delete',
    'stop': 'Stop',
    'alarmDefault': 'Alarm',
    'reminderDefault': 'Reminder',
    'language': 'Language',
    'noteDeleted': 'Note deleted',
    'undo': 'Undo',
    'pin': 'Pin',
    'unpin': 'Unpin',
    'markDone': 'Mark as done',
    'close': 'Close',
    'pinned': 'Pinned',
    'others': 'Other notes',
    'completed': 'Completed',
    'toLight': 'Light theme',
    'toDark': 'Dark theme',
  },
  'es': {
    'new': 'Nuevo',
    'empty': 'Aún no hay notas',
    'newReminder': 'Nueva nota',
    'title': 'Título',
    'note': 'Nota (opcional)',
    'onlyNotif': 'Solo notificación',
    'alarm': 'Alarma',
    'save': 'Guardar',
    'enterTitle': 'El título es obligatorio',
    'pastTime': 'Esa hora ya pasó. Elige una posterior.',
    'stopAlarm': 'Detener alarma',
    'alarmStopped': 'Alarma detenida',
    'delete': 'Eliminar',
    'stop': 'Detener',
    'alarmDefault': 'Alarma',
    'reminderDefault': 'Recordatorio',
    'language': 'Idioma',
    'noteDeleted': 'Nota eliminada',
    'undo': 'Deshacer',
    'pin': 'Fijar',
    'unpin': 'Quitar fijado',
    'markDone': 'Marcar como hecha',
    'close': 'Cerrar',
    'pinned': 'Fijadas',
    'others': 'Otras notas',
    'completed': 'Completadas',
    'toLight': 'Tema claro',
    'toDark': 'Tema oscuro',
  },
};

const Map<String, List<String>> _months = {
  'tr': ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'],
  'en': ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
  'es': ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'],
};

String t(String key) =>
    _strings[langNotifier.value]?[key] ?? _strings['en']![key] ?? key;

String two(int n) => n.toString().padLeft(2, '0');

String fmt(DateTime d) {
  final m = _months[langNotifier.value] ?? _months['en']!;
  return '${d.day} ${m[d.month - 1]} ${d.year} · ${two(d.hour)}:${two(d.minute)}';
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class Reminder {
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final bool alarm; // true: alarm, false: sadece bildirim
  bool done;
  bool pinned;

  Reminder({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.alarm,
    this.done = false,
    this.pinned = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'when': when.millisecondsSinceEpoch,
        'alarm': alarm,
        'done': done,
        'pinned': pinned,
      };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'] as int,
        title: j['title'] as String,
        body: (j['body'] ?? '') as String,
        when: DateTime.fromMillisecondsSinceEpoch(j['when'] as int),
        alarm: j['alarm'] as bool,
        done: (j['done'] ?? false) as bool,
        pinned: (j['pinned'] ?? false) as bool,
      );
}

// ---------------------------------------------------------------------------
// Bildirim servisi
// ---------------------------------------------------------------------------
// Uygulama kapalıyken "Durdur" aksiyonu bu fonksiyonu çalıştırır.
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  final id = response.id;
  if (id == null) return;
  try {
    await FlutterLocalNotificationsPlugin().cancel(id);
  } catch (_) {}
}

class NotifService {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  // Android kanal ayarlarını sonradan değiştirmeye izin vermez.
  // Bu yüzden ses ayarı değiştiğinde ID'yi (v2, v3...) artır.
  static const String _alarmChannelId = 'pxnote_alarm_v2';
  static const String _notifChannelId = 'pxnote_notif_v2';

  /// Bildirime dokunulunca açılacak notun id'si.
  static final ValueNotifier<int?> openNoteId = ValueNotifier<int?>(null);

  static AndroidNotificationDetails get _alarmDetails =>
      AndroidNotificationDetails(
        _alarmChannelId,
        'Alarms',
        channelDescription: 'Ringing alarms',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        playSound: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        timeoutAfter: 120000, // 2 dk sonra kendiliğinden durur
        // 4 = FLAG_INSISTENT: durdurulana kadar ses tekrar eder
        additionalFlags: Int32List.fromList(<int>[4]),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'stop',
            t('stop'),
            cancelNotification: true,
            showsUserInterface: false,
          ),
        ],
      );

  static const AndroidNotificationDetails _notifDetails =
      AndroidNotificationDetails(
    _notifChannelId,
    'Reminders',
    channelDescription: 'Reminder notifications',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final String name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Eski (sessiz kalan) kanalları temizle.
    try {
      await android?.deleteNotificationChannel('alarm_channel_v1');
      await android?.deleteNotificationChannel('notif_channel_v1');
    } catch (_) {}

    // sound verilmezse sistemin varsayılan sesi çalar (en güvenilir yol).
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _alarmChannelId,
        'Alarms',
        description: 'Ringing alarms',
        importance: Importance.max,
        playSound: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _notifChannelId,
        'Reminders',
        description: 'Reminder notifications',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// Uygulama açıkken: bildirime dokunma veya "Durdur" aksiyonu.
  static void _onResponse(NotificationResponse r) {
    final id = r.id;
    if (id == null) return;
    plugin.cancel(id); // ses ve bildirim kapanır
    if (r.actionId == 'stop') return;
    openNoteId.value = id; // ilgili notu göster
  }

  /// Uygulama kapalıyken bildirime dokunularak açıldıysa.
  static Future<void> handleLaunch() async {
    try {
      final d = await plugin.getNotificationAppLaunchDetails();
      final r = d?.notificationResponse;
      if (d != null && d.didNotificationLaunchApp && r != null) {
        _onResponse(r);
      }
    } catch (_) {}
  }

  static Future<void> requestPermissions() async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    final canExact = await android?.canScheduleExactNotifications() ?? true;
    if (!canExact) {
      await android?.requestExactAlarmsPermission();
    }
  }

  static Future<void> schedule(Reminder r) async {
    final tz.TZDateTime when = tz.TZDateTime.from(r.when, tz.local);
    final details = NotificationDetails(
      android: r.alarm ? _alarmDetails : _notifDetails,
    );
    final String body = r.body.trim().isEmpty
        ? (r.alarm ? t('alarmDefault') : t('reminderDefault'))
        : r.body;

    Future<void> doSchedule(AndroidScheduleMode mode) {
      return plugin.zonedSchedule(
        r.id,
        r.title,
        body,
        when,
        details,
        androidScheduleMode: mode,
        payload: '${r.id}',
      );
    }

    try {
      await doSchedule(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException {
      // Tam zaman izni yoksa yaklaşık zamanlı kur (yine de çalışır).
      await doSchedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  static Future<void> cancel(int id) => plugin.cancel(id);
}

// ---------------------------------------------------------------------------
// Veri deposu (liste + kalıcı kayıt)
// ---------------------------------------------------------------------------
class NoteStore extends ChangeNotifier {
  static const String _key = 'reminders_v1';
  final List<Reminder> items = [];
  bool loaded = false;
  SharedPreferences? _prefs;

  static int genId() => DateTime.now().microsecondsSinceEpoch % 2000000000;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw != null) {
      try {
        items
          ..clear()
          ..addAll((jsonDecode(raw) as List)
              .map((e) => Reminder.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        items.clear();
      }
    }
    _sort();
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  // Sabitlenmiş (tamamlanmamış) > diğerleri > tamamlananlar; içte tarihe göre.
  void _sort() {
    items.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return a.when.compareTo(b.when);
    });
  }

  Future<void> add(Reminder r) async {
    items.add(r);
    _sort();
    notifyListeners();
    await _persist();
    try {
      await NotifService.schedule(r);
    } catch (_) {}
  }

  Future<void> setDone(Reminder r, bool value) async {
    r.done = value;
    _sort();
    notifyListeners();
    await _persist();
    try {
      if (value) {
        await NotifService.cancel(r.id);
      } else if (r.when.isAfter(DateTime.now())) {
        await NotifService.schedule(r);
      }
    } catch (_) {}
  }

  Future<void> togglePin(Reminder r) async {
    r.pinned = !r.pinned;
    _sort();
    notifyListeners();
    await _persist();
  }

  /// Önce listeden ve kalıcı kayıttan sil, sonra bildirimi iptal et.
  Future<void> remove(Reminder r) async {
    items.removeWhere((e) => e.id == r.id);
    notifyListeners();
    await _persist();
    try {
      await NotifService.cancel(r.id);
    } catch (_) {}
  }

  /// "Geri Al": notu (ve geleceğe aitse bildirimini) geri getirir.
  Future<void> restore(Reminder r) async {
    if (items.any((e) => e.id == r.id)) return;
    items.add(r);
    _sort();
    notifyListeners();
    await _persist();
    try {
      if (!r.done && r.when.isAfter(DateTime.now())) {
        await NotifService.schedule(r);
      }
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Tema
// ---------------------------------------------------------------------------
ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6C8CFF),
    brightness: b,
  );
  final scheme = base.copyWith(
    surface: dark ? const Color(0xFF000000) : const Color(0xFFF5F5F7),
    onSurface: dark ? const Color(0xFFEDEDF0) : const Color(0xFF111114),
    onSurfaceVariant: dark ? const Color(0xFF9A9AA3) : const Color(0xFF6A6A74),
    outlineVariant: dark ? const Color(0xFF222226) : const Color(0xFFE2E2E8),
    surfaceContainerLowest: dark ? const Color(0xFF000000) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF0D0D0F) : Colors.white,
    surfaceContainer: dark ? const Color(0xFF111114) : Colors.white,
    surfaceContainerHigh: dark ? const Color(0xFF151519) : Colors.white,
    surfaceContainerHighest:
        dark ? const Color(0xFF1A1A1F) : const Color(0xFFEDEDF1),
  );

  final overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: scheme.surface,
    systemNavigationBarIconBrightness:
        dark ? Brightness.light : Brightness.dark,
  );

  OutlineInputBorder border(Color c, [double w = 0]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    splashFactory: InkRipple.splashFactory, // shader takılmasını önler
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      systemOverlayStyle: overlay,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF17171B) : const Color(0xFFF0F0F4),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(scheme.primary, 1.5),
      errorBorder: border(scheme.error, 1.2),
      focusedErrorBorder: border(scheme.error, 1.5),
    ),
  );
}

// ---------------------------------------------------------------------------
// Uygulama
// ---------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final savedLang = prefs.getString(kLangKey);
  final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  langNotifier.value = kLangs.contains(savedLang)
      ? savedLang!
      : (kLangs.contains(device) ? device : 'en');
  themeNotifier.value =
      prefs.getString(kThemeKey) == 'light' ? ThemeMode.light : ThemeMode.dark;

  await NotifService.init();
  await NotifService.handleLaunch();
  runApp(const PxNoteApp());
}

class PxNoteApp extends StatelessWidget {
  const PxNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final light = buildTheme(Brightness.light);
    final dark = buildTheme(Brightness.dark);
    return ListenableBuilder(
      listenable: Listenable.merge([langNotifier, themeNotifier]),
      builder: (context, _) {
        return MaterialApp(
          title: 'PxNote',
          debugShowCheckedModeBanner: false,
          locale: Locale(langNotifier.value),
          supportedLocales: const [Locale('tr'), Locale('en'), Locale('es')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: light,
          darkTheme: dark,
          themeMode: themeNotifier.value,
          themeAnimationDuration: const Duration(milliseconds: 150),
          home: const HomePage(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Soldan sağa kaydırınca çöp kutusu gösteren satır
// ---------------------------------------------------------------------------
class SwipeRevealTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onDelete;
  const SwipeRevealTile({
    super.key,
    required this.child,
    required this.onDelete,
  });

  @override
  State<SwipeRevealTile> createState() => _SwipeRevealTileState();
}

class _SwipeRevealTileState extends State<SwipeRevealTile> {
  static const double _reveal = 72;
  double _dx = 0;
  bool _dragging = false;

  void _settle() => setState(() {
        _dragging = false;
        _dx = _dx > _reveal / 2 ? _reveal : 0;
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Stack(
        children: [
          // Arkadaki çöp kutusu
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Material(
                  color: cs.errorContainer,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onDelete,
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Tooltip(
                        message: t('delete'),
                        child: Icon(Icons.delete_outline,
                            color: cs.onErrorContainer),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Öndeki kart: sürükleme algılayıcısı kartın İÇİNDE, kartla kayar.
          AnimatedContainer(
            duration:
                _dragging ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: GestureDetector(
              onTap: _dx > 0 ? () => setState(() => _dx = 0) : null,
              onHorizontalDragStart: (_) => setState(() => _dragging = true),
              onHorizontalDragUpdate: (d) => setState(() {
                _dx = (_dx + d.delta.dx).clamp(0.0, _reveal).toDouble();
              }),
              onHorizontalDragEnd: (_) => _settle(),
              onHorizontalDragCancel: _settle,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Not kartı
// ---------------------------------------------------------------------------
class NoteCard extends StatelessWidget {
  final Reminder r;
  final ValueChanged<bool> onDone;
  final VoidCallback onPin;
  final VoidCallback onStop;

  const NoteCard({
    super.key,
    required this.r,
    required this.onDone,
    required this.onPin,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final overdue = !r.done && r.when.isBefore(now);
    final ringing = r.alarm &&
        overdue &&
        now.difference(r.when) < const Duration(minutes: 2);

    final titleColor = r.done ? cs.onSurface.withOpacity(0.45) : cs.onSurface;
    final bodyColor = r.done
        ? cs.onSurfaceVariant.withOpacity(0.5)
        : cs.onSurfaceVariant;
    final metaColor = overdue ? cs.error : cs.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: r.done,
            shape: const CircleBorder(),
            visualDensity: VisualDensity.compact,
            onChanged: (v) => onDone(v ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 9, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                      decoration: r.done ? TextDecoration.lineThrough : null,
                      decorationColor: titleColor,
                    ),
                  ),
                  if (r.body.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        r.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          color: bodyColor,
                          decoration:
                              r.done ? TextDecoration.lineThrough : null,
                          decorationColor: bodyColor,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        r.alarm
                            ? Icons.alarm
                            : Icons.notifications_none_outlined,
                        size: 14,
                        color: metaColor,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          fmt(r.when),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: metaColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (ringing)
            IconButton(
              tooltip: t('stopAlarm'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.alarm_off, color: cs.error, size: 22),
              onPressed: onStop,
            ),
          IconButton(
            tooltip: r.pinned ? t('unpin') : t('pin'),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              r.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 20,
              color: r.pinned ? cs.primary : cs.onSurfaceVariant,
            ),
            onPressed: onPin,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ana sayfa
// ---------------------------------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final NoteStore store = NoteStore();

  @override
  void initState() {
    super.initState();
    NotifService.openNoteId.addListener(_checkOpenRequest);
    NotifService.requestPermissions();
    _init();
  }

  Future<void> _init() async {
    await store.load();
    _checkOpenRequest(); // bildirimle açıldıysa ilgili notu göster
  }

  @override
  void dispose() {
    NotifService.openNoteId.removeListener(_checkOpenRequest);
    store.dispose();
    super.dispose();
  }

  // --- Bildirimden gelen "notu göster" isteği ---
  void _checkOpenRequest() {
    final id = NotifService.openNoteId.value;
    if (id == null || !store.loaded || !mounted) return;
    NotifService.openNoteId.value = null;
    final i = store.items.indexWhere((e) => e.id == id);
    if (i == -1) return;
    _showOpened(store.items[i]);
  }

  Future<void> _showOpened(Reminder r) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.body.trim().isNotEmpty) ...[
              Text(r.body),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Icon(r.alarm ? Icons.alarm : Icons.notifications_none_outlined,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(fmt(r.when),
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('close')),
          ),
          if (!r.done)
            FilledButton(
              onPressed: () {
                store.setDone(r, true);
                Navigator.pop(ctx);
              },
              child: Text(t('markDone')),
            ),
        ],
      ),
    );
  }

  // --- Eylemler ---
  Future<void> _openAddSheet() async {
    final cs = Theme.of(context).colorScheme;
    final Reminder? r = await showModalBottomSheet<Reminder>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: cs.surfaceContainerLow,
      builder: (_) => const AddSheet(),
    );
    if (r != null) await store.add(r);
  }

  void _delete(Reminder r) {
    store.remove(r);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(t('noteDeleted')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: t('undo'),
            onPressed: () => store.restore(r),
          ),
        ),
      );
  }

  Future<void> _stopAlarm(Reminder r) async {
    await NotifService.cancel(r.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(t('alarmStopped')),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _setLang(String code) async {
    langNotifier.value = code;
    final p = await SharedPreferences.getInstance();
    await p.setString(kLangKey, code);
  }

  Future<void> _toggleTheme() async {
    final next = themeNotifier.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    themeNotifier.value = next;
    final p = await SharedPreferences.getInstance();
    await p.setString(kThemeKey, next == ThemeMode.dark ? 'dark' : 'light');
  }

  // --- Görünüm ---
  List<Object> _rows() {
    final pinned = store.items.where((e) => e.pinned && !e.done).toList();
    final others = store.items.where((e) => !e.pinned && !e.done).toList();
    final done = store.items.where((e) => e.done).toList();
    final rows = <Object>[];
    if (pinned.isNotEmpty) {
      rows.add('pinned');
      rows.addAll(pinned);
      if (others.isNotEmpty) rows.add('others');
    }
    rows.addAll(others);
    if (done.isNotEmpty) {
      rows.add('completed');
      rows.addAll(done);
    }
    return rows;
  }

  Widget _langMenu() {
    return PopupMenuButton<String>(
      tooltip: t('language'),
      icon: const Icon(Icons.translate),
      onSelected: _setLang,
      itemBuilder: (_) => [
        for (final e in const {
          'tr': 'Türkçe',
          'en': 'English',
          'es': 'Español',
        }.entries)
          PopupMenuItem<String>(
            value: e.key,
            child: Row(
              children: [
                Icon(
                  langNotifier.value == e.key
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(e.value),
              ],
            ),
          ),
      ],
    );
  }

  Widget _empty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note, size: 56, color: cs.outlineVariant),
          const SizedBox(height: 10),
          Text(t('empty'),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _list(ColorScheme cs) {
    final rows = _rows();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Text(
              t(row),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: cs.onSurfaceVariant,
              ),
            ),
          );
        }
        final r = row as Reminder;
        return SwipeRevealTile(
          key: ValueKey(r.id),
          onDelete: () => _delete(r),
          child: NoteCard(
            r: r,
            onDone: (v) => store.setDone(r, v),
            onPin: () => store.togglePin(r),
            onStop: () => _stopAlarm(r),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: langNotifier,
      builder: (context, _) {
        return Scaffold(
          // Bu sayfada metin alanı yok; klavye açılınca yeniden boyutlanmasın.
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: const Text(
              'PxNote',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            actions: [
              IconButton(
                tooltip: isDark ? t('toLight') : t('toDark'),
                icon: Icon(isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined),
                onPressed: _toggleTheme,
              ),
              _langMenu(),
              const SizedBox(width: 4),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openAddSheet,
            elevation: 0,
            highlightElevation: 0,
            icon: const Icon(Icons.add),
            label: Text(t('new')),
          ),
          body: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              if (!store.loaded) {
                return const Center(child: CircularProgressIndicator());
              }
              if (store.items.isEmpty) return _empty(cs);
              return _list(cs);
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Ekleme paneli
// Dış widget sadece klavye boşluğunu yönetir (her karede ucuz yeniden çizim),
// form ayrı bir widget olduğu için klavye animasyonunda yeniden kurulmaz.
// ---------------------------------------------------------------------------
class AddSheet extends StatelessWidget {
  const AddSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: const SingleChildScrollView(child: _SheetForm()),
    );
  }
}

class _SheetForm extends StatefulWidget {
  const _SheetForm();

  @override
  State<_SheetForm> createState() => _SheetFormState();
}

class _SheetFormState extends State<_SheetForm> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _titleFocus = FocusNode();
  late DateTime _date;
  late TimeOfDay _time;
  bool _alarm = false;
  String? _titleError;
  String? _timeError;

  @override
  void initState() {
    super.initState();
    final soon = DateTime.now().add(const Duration(minutes: 5));
    _date = DateTime(soon.year, soon.month, soon.day);
    _time = TimeOfDay(hour: soon.hour, minute: soon.minute);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus(); // klavye kapanırken pencere açılmasın
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: DateTime(now.year + 5),
    );
    if (d != null && mounted) {
      setState(() {
        _date = d;
        _timeError = null;
      });
    }
  }

  Future<void> _pickTime() async {
    FocusScope.of(context).unfocus();
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _time = picked;
        _timeError = null;
      });
    }
  }

  void _save() {
    final title = _title.text.trim();
    final when =
        DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

    final String? te = title.isEmpty ? t('enterTitle') : null;
    final String? tme = when.isAfter(DateTime.now()) ? null : t('pastTime');

    if (te != null || tme != null) {
      // Hatalar panelin İÇİNDE gösterilir, bu yüzden hiçbir zaman arkada kalmaz.
      setState(() {
        _titleError = te;
        _timeError = tme;
      });
      if (te != null) _titleFocus.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    Navigator.pop(
      context,
      Reminder(
        id: NoteStore.genId(),
        title: title,
        body: _body.text.trim(),
        when: when,
        alarm: _alarm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('newReminder'),
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            focusNode: _titleFocus,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
            decoration: InputDecoration(
              hintText: t('title'),
              errorText: _titleError,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: t('note')),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _pickDate,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                      '${two(_date.day)}.${two(_date.month)}.${_date.year}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _pickTime,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text('${two(_time.hour)}:${two(_time.minute)}'),
                ),
              ),
            ],
          ),
          if (_timeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(_timeError!,
                  style: TextStyle(color: cs.error, fontSize: 12.5)),
            ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.notifications_none_outlined),
                label: Text(t('onlyNotif')),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.alarm),
                label: Text(t('alarm')),
              ),
            ],
            selected: {_alarm},
            onSelectionChanged: (s) => setState(() => _alarm = s.first),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50)),
            child: Text(t('save')),
          ),
        ],
      ),
    );
  }
}