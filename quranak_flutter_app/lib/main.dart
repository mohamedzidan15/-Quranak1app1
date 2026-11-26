import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:adhan/adhan.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final AudioPlayer globalAdhanPlayer = AudioPlayer();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    if (message.notification != null) {
      await AdhanAlarmService.showAdminBroadcast(
        message.notification!.title ?? 'قرآنك',
        message.notification!.body ?? '',
      );
    }
  } catch (_) {}
}

@pragma('vm:entry-point')
Future<void> onAdhanAlarmFired(int alarmId, Map<String, dynamic> params) async {
  final prayerName = (params['prayerName'] ?? 'الصلاة').toString();
  final cityName = (params['cityName'] ?? 'القاهرة').toString();

  final notifPlugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifPlugin.initialize(
    const InitializationSettings(android: androidInit),
    onDidReceiveNotificationResponse: (details) async {
      if (details.actionId == 'stop_adhan') {
        await AdhanAlarmService.stopAdhanAudioAndAlert();
      } else {
        AdhanAlarmService.openAdhanScreen('صلاة $prayerName');
      }
    },
  );

  await notifPlugin.show(
    9500 + (alarmId % 50),
    '🕌 حان الآن موعد صلاة $prayerName ($cityName)',
    'الله أكبر الله أكبر • حيّ على الصلاة • حيّ على الفلاح',
    NotificationDetails(
      android: AndroidNotificationDetails(
        AdhanAlarmService.adhanAlarmChannelId,
        'منبه الأذان التلقائي',
        channelDescription: 'تنبيه الأذان عند دخول وقت الصلاة حتى في وضع السكون أو بدون إنترنت',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('adhan'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        additionalFlags: Int32List.fromList(<int>[4]),
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'stop_adhan',
            'إيقاف الأذان',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      ),
    ),
    payload: 'adhan:صلاة $prayerName',
  );

  try {
    final player = AudioPlayer();
    await player.setAudioSource(
      AudioSource.asset(
        'assets/audio/adhan.mp3',
        tag: MediaItem(
          id: 'adhan_alarm_$alarmId',
          album: 'قرآنك',
          title: 'أذان صلاة $prayerName',
          artist: cityName,
        ),
      ),
    );
    await player.play();
  } catch (_) {}

  AdhanAlarmService.openAdhanScreen('صلاة $prayerName');
}

Future<void> _initializePlatformServices() async {
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.quranak.app.channel.audio',
      androidNotificationChannelName: 'تلاوات قرآنك',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ).timeout(const Duration(seconds: 5));
  } catch (_) {}
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 5));
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {}
  try {
    tz.initializeTimeZones();
    await AndroidAlarmManager.initialize().timeout(const Duration(seconds: 5));
    await AdhanAlarmService.init().timeout(const Duration(seconds: 5));
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  try {
    runApp(const QuranakApp());

  // Platform services initialize after the first frame. A missing network,
  // Firebase response, or alarm permission must never hold the app on a black screen.
  unawaited(_initializePlatformServices());
}

class AdhanAlarmService {
  static const String adhanAlarmChannelId = 'quranak_adhan_alarm_v8';
  static const String adminChannelId = 'quranak_admin_broadcast_v8';
  static bool _screenOpen = false;

  static void openAdhanScreen(String prayerTitle) {
    if (_screenOpen) return;
    _screenOpen = true;
    navigatorKey.currentState
        ?.push(
          MaterialPageRoute(
            builder: (_) => AdhanAlarmScreen(prayerName: prayerTitle),
          ),
        )
        .then((_) => _screenOpen = false);
  }

  static Future<void> stopAdhanAudioAndAlert() async {
    try {
      if (globalAdhanPlayer.playing) {
        await globalAdhanPlayer.stop();
      }
    } catch (_) {}
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (_) {}
    _screenOpen = false;
  }

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (NotificationResponse details) async {
        if (details.actionId == 'stop_adhan') {
          await stopAdhanAudioAndAlert();
          return;
        }
        if ((details.payload ?? '').startsWith('adhan:')) {
          final prayerName = details.payload!.replaceFirst('adhan:', '');
          openAdhanScreen(prayerName);
        }
      },
    );

    final androidExt = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidExt?.requestNotificationsPermission();
    await androidExt?.requestExactAlarmsPermission();

    await androidExt?.createNotificationChannel(
      const AndroidNotificationChannel(
        adhanAlarmChannelId,
        'منبه الأذان التلقائي',
        description: 'تنبيه الأذان عند دخول وقت الصلاة حتى لو الهاتف مغلق أو بدون إنترنت',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('adhan'),
        enableVibration: true,
        enableLights: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    await androidExt?.createNotificationChannel(
      const AndroidNotificationChannel(
        adminChannelId,
        'إشعارات تطبيق قرآنك',
        description: 'رسائل وتنبيهات الإدارة',
        importance: Importance.high,
      ),
    );

    try {
      await FirebaseMessaging.instance.requestPermission();
      await FirebaseMessaging.instance.subscribeToTopic('quranak_all_users');
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        final n = msg.notification;
        if (n != null) {
          showAdminBroadcast(n.title ?? 'قرآنك', n.body ?? '');
        }
      });
    } catch (_) {}
  }

  static Future<void> showAdminBroadcast(String title, String body) async {
    try {
      await flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            adminChannelId,
            'إشعارات تطبيق قرآنك',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  static Future<Map<String, DateTime>> schedule7DaysForCity(
    double lat,
    double lng,
    String cityAr,
  ) async {
    final coords = Coordinates(lat, lng);
    final params = CalculationMethod.egyptian.getParameters();
    params.madhab = Madhab.shafi;

    final now = DateTime.now();
    int alarmSlotId = 8000;
    int notifId = 7000;

    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (_) {}

    for (int day = 0; day < 7; day++) {
      final dt = now.add(Duration(days: day));
      final pt = PrayerTimes(coords, DateComponents.from(dt), params);
      final prayers = [
        MapEntry('الفجر', pt.fajr),
        MapEntry('الظهر', pt.dhuhr),
        MapEntry('العصر', pt.asr),
        MapEntry('المغرب', pt.maghrib),
        MapEntry('العشاء', pt.isha),
      ];

      for (final p in prayers) {
        alarmSlotId++;
        notifId++;
        if (p.value.isAfter(now)) {
          try {
            await AndroidAlarmManager.oneShotAt(
              p.value,
              alarmSlotId,
              onAdhanAlarmFired,
              exact: true,
              wakeup: true,
              alarmClock: true,
              rescheduleOnReboot: true,
              params: {
                'prayerName': p.key,
                'cityName': cityAr,
              },
            );
          } catch (_) {}

          try {
            final scheduled = tz.TZDateTime.from(p.value, tz.local);
            await flutterLocalNotificationsPlugin.zonedSchedule(
              notifId,
              '🕌 حان الآن موعد صلاة ${p.key} ($cityAr)',
              'الله أكبر الله أكبر • حيّ على الصلاة • حيّ على الفلاح',
              scheduled,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  adhanAlarmChannelId,
                  'منبه الأذان التلقائي',
                  importance: Importance.max,
                  priority: Priority.max,
                  category: AndroidNotificationCategory.alarm,
                  fullScreenIntent: true,
                  ongoing: true,
                  autoCancel: false,
                  playSound: true,
                  sound: const RawResourceAndroidNotificationSound('adhan'),
                  audioAttributesUsage: AudioAttributesUsage.alarm,
                  additionalFlags: Int32List.fromList(<int>[4]),
                  actions: const <AndroidNotificationAction>[
                    AndroidNotificationAction(
                      'stop_adhan',
                      'إيقاف الأذان',
                      showsUserInterface: true,
                      cancelNotification: true,
                    ),
                  ],
                ),
                iOS: const DarwinNotificationDetails(
                  presentAlert: true,
                  presentSound: true,
                  sound: 'adhan.mp3',
                  interruptionLevel: InterruptionLevel.timeSensitive,
                ),
              ),
              payload: 'adhan:صلاة ${p.key}',
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          } catch (_) {}
        }
      }
    }

    final today = PrayerTimes.today(coords, params);
    return {
      'Fajr': today.fajr,
      'Sunrise': today.sunrise,
      'Dhuhr': today.dhuhr,
      'Asr': today.asr,
      'Maghrib': today.maghrib,
      'Isha': today.isha,
    };
  }
}

class AdhanAlarmScreen extends StatefulWidget {
  final String prayerName;
  const AdhanAlarmScreen({super.key, required this.prayerName});

  @override
  State<AdhanAlarmScreen> createState() => _AdhanAlarmScreenState();
}

class _AdhanAlarmScreenState extends State<AdhanAlarmScreen> {
  @override
  void initState() {
    super.initState();
    _playAdhan();
  }

  Future<void> _playAdhan() async {
    try {
      await globalAdhanPlayer.stop();
      await globalAdhanPlayer.setAudioSource(
        AudioSource.asset(
          'assets/audio/adhan.mp3',
          tag: MediaItem(
            id: 'adhan_screen_player',
            album: 'قرآنك',
            title: 'أذان ${widget.prayerName}',
            artist: 'منبه الأذان',
          ),
        ),
      );
      await globalAdhanPlayer.play();
    } catch (_) {
      // The bundled asset is the offline source of truth. Never require network
      // access for the adhan screen to initialize.
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A2A25), Color(0xFF0D2B35), Color(0xFF07131C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mosque_rounded, size: 88, color: Color(0xFFC9A959)),
              const SizedBox(height: 20),
              const Text('حان الآن موعد', style: TextStyle(fontSize: 20, color: Colors.white70)),
              const SizedBox(height: 8),
              Text(
                widget.prayerName,
                style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Color(0xFFC9A959)),
              ),
              const SizedBox(height: 16),
              const Text(
                'اللَّهُ أَكْبَرُ اللَّهُ أَكْبَرُ • حَيَّ عَلَى الصَّلَاةِ',
                style: TextStyle(fontSize: 18, color: Color(0xFFE2C78A)),
              ),
              const SizedBox(height: 54),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC9A959),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                ),
                onPressed: () async {
                  await AdhanAlarmService.stopAdhanAudioAndAlert();
                  if (mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.alarm_off_rounded, size: 26),
                label: const Text('إيقاف الأذان', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReciterAvatarImage extends StatelessWidget {
  final Map<String, dynamic> data;
  final double size;
  final double borderWidth;

  const ReciterAvatarImage({
    super.key,
    required this.data,
    this.size = 76,
    this.borderWidth = 2.5,
  });

  static String extractBestImage(Map<String, dynamic> m) {
    final candidates = [
      m['image'],
      m['reciter_image'],
      m['avatar'],
      m['photo'],
      m['img'],
      m['picture'],
    ];
    for (final c in candidates) {
      if (c != null && c.toString().trim().isNotEmpty && c.toString().trim() != 'null') {
        String s = c.toString().trim();
        if (!s.startsWith('http://') &&
            !s.startsWith('https://') &&
            !s.startsWith('data:image') &&
            !File(s).existsSync()) {
          if (s.startsWith('uploads/')) {
            s = 'https://quran1.kesug.com/$s';
          } else {
            s = 'https://quran1.kesug.com/uploads/$s';
          }
        }
        return s;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final src = extractBestImage(data);
    Widget inner;

    if (src.isEmpty) {
      inner = _fallback();
    } else if (src.startsWith('data:image')) {
      try {
        final bytes = base64Decode(src.split(',').last);
        inner = Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        );
      } catch (_) {
        inner = _fallback();
      }
    } else if (File(src).existsSync()) {
      inner = Image.file(
        File(src),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    } else {
      inner = Image.network(
        src,
        width: size,
        height: size,
        fit: BoxFit.cover,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _fallback();
        },
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(borderWidth),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFC9A959), Color(0xFFA8893A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: ClipOval(
        child: Container(
          color: const Color(0xFF0A0F1E),
          child: inner,
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFF0D2B35),
      child: Icon(Icons.person_rounded, color: const Color(0xFFC9A959), size: size * 0.48),
    );
  }
}


/// Quranak website API integration. Public read endpoints are cached locally so
/// the previously synchronized catalog remains visible without connectivity.
class QuranakApi {
  static const String baseUrl = 'https://quran1.kesug.com/index.php';
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 25),
    sendTimeout: const Duration(seconds: 20),
    headers: const {'Accept': 'application/json', 'User-Agent': 'Quranak-Android/1.0'},
  ));

  static Future<List<Map<String, dynamic>>> getList(
    String action, {Map<String, dynamic> params = const {}, String? cacheKey}
  ) async {
    final key = cacheKey ?? 'quranak_api_$action';
    try {
      final response = await _dio.get(baseUrl, queryParameters: {'action': action, ...params});
      final body = response.data;
      List<Map<String, dynamic>>? rows;
      if (body is List) {
        rows = body.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } else if (body is String) {
        final decoded = jsonDecode(body);
        if (decoded is List) {
          rows = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
      if (rows != null) {
        await _save(key, rows);
        return rows;
      }
    } catch (_) {
      // Network failure is expected in offline mode: return the last good snapshot.
    }
    return _load(key);
  }

  static Future<List<Map<String, dynamic>>> getAudiosForReciter(dynamic reciterId) {
    final id = reciterId.toString();
    return getList('get_audios',
      params: {'reciter_id': id},
      cacheKey: 'cached_audios_reciter_$id',
    );
  }

  static Future<void> _save(String key, List<Map<String, dynamic>> rows) async {
    try { final p = await SharedPreferences.getInstance(); await p.setString(key, jsonEncode(rows)); } catch (_) {}
  }
  static Future<List<Map<String, dynamic>>> _load(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw != null) return (jsonDecode(raw) as List).whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
    } catch (_) {}
    return [];
  }

  static Future<void> syncCatalogs() async {
    // Sequential, bounded requests are friendlier to free shared hosting.
    final reciters = await getList('get_reciters', cacheKey: 'cached_reciters_v8');
    final videos = await getList('get_videos', cacheKey: 'cached_videos_v8');
    // Audio API is keyed by the SQL reciter ID, not by reciter name.
    for (final reciter in reciters) {
      final reciterId = reciter['id'];
      if (reciterId != null) {
        await getAudiosForReciter(reciterId);
      }
    }
    await getList('get_books', params: {'status': 1}, cacheKey: 'cached_books_v1');
    await getList('get_azkar_categories', cacheKey: 'cached_azkar_categories_v1');
    await getList('get_hadiths', cacheKey: 'cached_hadiths_v1');
    // Preserve API-native fields while providing aliases used by older widgets.
    final normalized = videos.map((v) {
      final m = Map<String, dynamic>.from(v);
      m['url'] ??= m['video_url'] ?? m['videoUrl'] ?? '';
      m['videoUrl'] ??= m['video_url'] ?? m['url'] ?? '';
      var thumb = (m['thumbnail'] ?? m['thumbnail_path'] ?? m['thumbnail_url'] ?? '').toString().trim();
      if (thumb.isNotEmpty && !thumb.startsWith('http://') && !thumb.startsWith('https://')) {
        if (thumb.startsWith('/')) thumb = thumb.substring(1);
        if (!thumb.startsWith('uploads/')) thumb = 'uploads/thumbnails/$thumb';
        thumb = 'https://quran1.kesug.com/$thumb';
      }
      m['thumbnail'] = thumb;
      m['reciter'] ??= m['reciter_name'] ?? m['title'] ?? 'مقطع قرآني';
      return m;
    }).toList();
    await _save('cached_videos_v8', normalized);
    await _save('cached_reciters_v8', reciters);
  }
}

class OfflineAudioManager extends ChangeNotifier {
  static final OfflineAudioManager instance = OfflineAudioManager._();
  OfflineAudioManager._();

  final Dio _dio = Dio();
  final Map<String, double> progressMap = {};
  List<Map<String, dynamic>> tracks = [];

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('offline_tracks_v8');
      if (raw != null) {
        final decoded = jsonDecode(raw) as List;
        tracks = decoded.cast<Map<String, dynamic>>();
        tracks.removeWhere((e) => !File(e['localPath'] ?? '').existsSync());
        await _save();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_tracks_v8', jsonEncode(tracks));
  }

  bool isSaved(String id) => tracks.any((e) => e['id'] == id);

  String? localPathOf(String id) {
    final m = tracks.where((e) => e['id'] == id).toList();
    return m.isEmpty ? null : m.first['localPath'] as String?;
  }

  Future<void> downloadTrack({
    required String id,
    required String title,
    required String reciter,
    required String url,
  }) async {
    if (progressMap.containsKey(id) || url.isEmpty) return;
    try {
      final base = await getApplicationDocumentsDirectory();
      final folder = Directory('${base.path}/quranak_offline_v8');
      if (!folder.existsSync()) folder.createSync(recursive: true);

      final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final dest = '${folder.path}/$safeId.mp3';

      progressMap[id] = 0.05;
      notifyListeners();

      await _dio.download(
        url,
        dest,
        options: Options(headers: {'User-Agent': 'Mozilla/5.0'}),
        onReceiveProgress: (rec, total) {
          if (total > 0) {
            progressMap[id] = rec / total;
            notifyListeners();
          }
        },
      );

      tracks.removeWhere((e) => e['id'] == id);
      tracks.insert(0, {'id': id, 'title': title, 'reciter': reciter, 'localPath': dest});
      await _save();
    } finally {
      progressMap.remove(id);
      notifyListeners();
    }
  }
}

class OfflineCacheService {
  static Future<void> saveReciters(List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_reciters_v8', jsonEncode(list));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> loadReciters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_reciters_v8');
      if (raw != null) return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    return [];
  }

  static Future<void> saveVideos(List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_videos_v8', jsonEncode(list));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> loadVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_videos_v8');
      if (raw != null) return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    return [];
  }
}

class CityInfo {
  final String ar;
  final double lat;
  final double lng;
  const CityInfo(this.ar, this.lat, this.lng);
}

const List<CityInfo> egyptianCities = [
  CityInfo('القاهرة', 30.0444, 31.2357),
  CityInfo('الإسكندرية', 31.2001, 29.9187),
  CityInfo('الجيزة', 30.0131, 31.2089),
  CityInfo('القليوبية', 30.4590, 31.1786),
  CityInfo('بورسعيد', 31.2653, 32.3019),
  CityInfo('السويس', 29.9668, 32.5498),
  CityInfo('الأقصر', 25.6872, 32.6396),
  CityInfo('أسوان', 24.0889, 32.8998),
  CityInfo('الغربية', 30.8754, 31.0335),
  CityInfo('الدقهلية', 31.0409, 31.3785),
  CityInfo('الشرقية', 30.5877, 31.5020),
  CityInfo('الإسماعيلية', 30.5965, 32.2715),
  CityInfo('كفر الشيخ', 31.1107, 30.9388),
  CityInfo('أسيوط', 27.1783, 31.1859),
  CityInfo('بني سويف', 29.0661, 31.0994),
  CityInfo('الفيوم', 29.3084, 30.8428),
  CityInfo('دمياط', 31.4175, 31.8144),
  CityInfo('البحيرة', 31.0341, 30.4682),
  CityInfo('المنيا', 28.0871, 30.7618),
  CityInfo('قنا', 26.1551, 32.7160),
  CityInfo('سوهاج', 26.5591, 31.6957),
  CityInfo('البحر الأحمر', 27.2579, 33.8116),
  CityInfo('مطروح', 31.3543, 27.2373),
  CityInfo('المنوفية', 30.5972, 30.9876),
];

const List<String> arabicMonths = [
  '',
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

const List<String> arabicWeekdaysFull = [
  '',
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

const List<String> arabicWeekdaysShort = [
  'الأحد',
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
];

String formatHijriArabic(HijriCalendar h) {
  String monthName = h.longMonthName;
  if (h.hMonth == 6 && !monthName.contains('الآخرة')) {
    monthName = 'جمادى الآخرة';
  }
  return '${h.hDay} $monthName ${h.hYear} هـ';
}

const List<Map<String, dynamic>> all114Surahs = [
  {"n": 1, "name": "سُورَةُ ٱلْفَاتِحَةِ", "plain": "الفاتحة", "ayahs": 7, "page": 1},
  {"n": 2, "name": "سُورَةُ البَقَرَةِ", "plain": "البقرة", "ayahs": 286, "page": 2},
  {"n": 3, "name": "سُورَةُ آلِ عِمْرَانَ", "plain": "آل عمران", "ayahs": 200, "page": 50},
  {"n": 4, "name": "سُورَةُ النِّسَاءِ", "plain": "النساء", "ayahs": 176, "page": 77},
  {"n": 5, "name": "سُورَةُ المَائِدَةِ", "plain": "المائدة", "ayahs": 120, "page": 106},
  {"n": 6, "name": "سُورَةُ الأَنْعَامِ", "plain": "الأنعام", "ayahs": 165, "page": 128},
  {"n": 7, "name": "سُورَةُ الأَعْرَافِ", "plain": "الأعراف", "ayahs": 206, "page": 151},
  {"n": 8, "name": "سُورَةُ الأَنْفَالِ", "plain": "الأنفال", "ayahs": 75, "page": 177},
  {"n": 9, "name": "سُورَةُ التَّوْبَةِ", "plain": "التوبة", "ayahs": 129, "page": 187},
  {"n": 10, "name": "سُورَةُ يُونُسَ", "plain": "يونس", "ayahs": 109, "page": 209},
  {"n": 11, "name": "سُورَةُ هُودٍ", "plain": "هود", "ayahs": 123, "page": 221},
  {"n": 12, "name": "سُورَةُ يُوسُفَ", "plain": "يوسف", "ayahs": 111, "page": 235},
  {"n": 13, "name": "سُورَةُ الرَّعْدِ", "plain": "الرعد", "ayahs": 43, "page": 249},
  {"n": 14, "name": "سُورَةُ إِبْرَاهِيمَ", "plain": "إبراهيم", "ayahs": 52, "page": 255},
  {"n": 15, "name": "سُورَةُ الحِجْرِ", "plain": "الحجر", "ayahs": 99, "page": 262},
  {"n": 16, "name": "سُورَةُ النَّحْلِ", "plain": "النحل", "ayahs": 128, "page": 267},
  {"n": 17, "name": "سُورَةُ الإِسْرَاءِ", "plain": "الإسراء", "ayahs": 111, "page": 282},
  {"n": 18, "name": "سُورَةُ الكَهْفِ", "plain": "الكهف", "ayahs": 110, "page": 293},
  {"n": 19, "name": "سُورَةُ مَرْيَمَ", "plain": "مريم", "ayahs": 98, "page": 305},
  {"n": 20, "name": "سُورَةُ طه", "plain": "طه", "ayahs": 135, "page": 312},
  {"n": 21, "name": "سُورَةُ الأَنْبِيَاءِ", "plain": "الأنبياء", "ayahs": 112, "page": 322},
  {"n": 22, "name": "سُورَةُ الحَجِّ", "plain": "الحج", "ayahs": 78, "page": 332},
  {"n": 23, "name": "سُورَةُ المُؤْمِنُونَ", "plain": "المؤمنون", "ayahs": 118, "page": 342},
  {"n": 24, "name": "سُورَةُ النُّورِ", "plain": "النور", "ayahs": 64, "page": 350},
  {"n": 25, "name": "سُورَةُ الفُرْقَانِ", "plain": "الفرقان", "ayahs": 77, "page": 359},
  {"n": 26, "name": "سُورَةُ الشُّعَرَاءِ", "plain": "الشعراء", "ayahs": 227, "page": 367},
  {"n": 27, "name": "سُورَةُ النَّمْلِ", "plain": "النمل", "ayahs": 93, "page": 377},
  {"n": 28, "name": "سُورَةُ القَصَصِ", "plain": "القصص", "ayahs": 88, "page": 385},
  {"n": 29, "name": "سُورَةُ العَنْكَبُوتِ", "plain": "العنكبوت", "ayahs": 69, "page": 396},
  {"n": 30, "name": "سُورَةُ الرُّومِ", "plain": "الروم", "ayahs": 60, "page": 404},
  {"n": 31, "name": "سُورَةُ لُقْمَانَ", "plain": "لقمان", "ayahs": 34, "page": 411},
  {"n": 32, "name": "سُورَةُ السَّجْدَةِ", "plain": "السجدة", "ayahs": 30, "page": 415},
  {"n": 33, "name": "سُورَةُ الأَحْزَابِ", "plain": "الأحزاب", "ayahs": 73, "page": 418},
  {"n": 34, "name": "سُورَةُ سَبَإٍ", "plain": "سبإ", "ayahs": 54, "page": 428},
  {"n": 35, "name": "سُورَةُ فَاطِرٍ", "plain": "فاطر", "ayahs": 45, "page": 434},
  {"n": 36, "name": "سُورَةُ يس", "plain": "يس", "ayahs": 83, "page": 440},
  {"n": 37, "name": "سُورَةُ الصَّافَّاتِ", "plain": "الصافات", "ayahs": 182, "page": 446},
  {"n": 38, "name": "سُورَةُ ص", "plain": "ص", "ayahs": 88, "page": 453},
  {"n": 39, "name": "سُورَةُ الزُّمَرِ", "plain": "الزمر", "ayahs": 75, "page": 458},
  {"n": 40, "name": "سُورَةُ غَافِرٍ", "plain": "غافر", "ayahs": 85, "page": 467},
  {"n": 41, "name": "سُورَةُ فُصِّلَتْ", "plain": "فصلت", "ayahs": 54, "page": 477},
  {"n": 42, "name": "سُورَةُ الشُّورَىٰ", "plain": "الشورى", "ayahs": 53, "page": 483},
  {"n": 43, "name": "سُورَةُ الزُّخْرُفِ", "plain": "الزخرف", "ayahs": 89, "page": 489},
  {"n": 44, "name": "سُورَةُ الدُّخَانِ", "plain": "الدخان", "ayahs": 59, "page": 496},
  {"n": 45, "name": "سُورَةُ الجَاثِيَةِ", "plain": "الجاثية", "ayahs": 37, "page": 499},
  {"n": 46, "name": "سُورَةُ الأَحْقَافِ", "plain": "الأحقاف", "ayahs": 35, "page": 502},
  {"n": 47, "name": "سُورَةُ مُحَمَّدٍ", "plain": "محمد", "ayahs": 38, "page": 507},
  {"n": 48, "name": "سُورَةُ الفَتْحِ", "plain": "الفتح", "ayahs": 29, "page": 511},
  {"n": 49, "name": "سُورَةُ الحُجُرَاتِ", "plain": "الحجرات", "ayahs": 18, "page": 515},
  {"n": 50, "name": "سُورَةُ ق", "plain": "ق", "ayahs": 45, "page": 518},
  {"n": 51, "name": "سُورَةُ الذَّارِيَاتِ", "plain": "الذاريات", "ayahs": 60, "page": 520},
  {"n": 52, "name": "سُورَةُ الطُّورِ", "plain": "الطور", "ayahs": 49, "page": 523},
  {"n": 53, "name": "سُورَةُ النَّجْمِ", "plain": "النجم", "ayahs": 62, "page": 526},
  {"n": 54, "name": "سُورَةُ القَمَرِ", "plain": "القمر", "ayahs": 55, "page": 528},
  {"n": 55, "name": "سُورَةُ الرَّحْمَٰن", "plain": "الرحمن", "ayahs": 78, "page": 531},
  {"n": 56, "name": "سُورَةُ الوَاقِعَةِ", "plain": "الواقعة", "ayahs": 96, "page": 534},
  {"n": 57, "name": "سُورَةُ الحَدِيدِ", "plain": "الحديد", "ayahs": 29, "page": 537},
  {"n": 58, "name": "سُورَةُ المُجَادَلَةِ", "plain": "المجادلة", "ayahs": 22, "page": 542},
  {"n": 59, "name": "سُورَةُ الحَشْرِ", "plain": "الحشر", "ayahs": 24, "page": 545},
  {"n": 60, "name": "سُورَةُ المُمْتَحَنَةِ", "plain": "الممتحنة", "ayahs": 13, "page": 549},
  {"n": 61, "name": "سُورَةُ الصَّفِّ", "plain": "الصف", "ayahs": 14, "page": 551},
  {"n": 62, "name": "سُورَةُ الجُمُعَةِ", "plain": "الجمعة", "ayahs": 11, "page": 553},
  {"n": 63, "name": "سُورَةُ المُنَافِقُونَ", "plain": "المنافقون", "ayahs": 11, "page": 554},
  {"n": 64, "name": "سُورَةُ التَّغَابُنِ", "plain": "التغابن", "ayahs": 18, "page": 556},
  {"n": 65, "name": "سُورَةُ الطَّلَاقِ", "plain": "الطلاق", "ayahs": 12, "page": 558},
  {"n": 66, "name": "سُورَةُ التَّحْرِيمِ", "plain": "التحريم", "ayahs": 12, "page": 560},
  {"n": 67, "name": "سُورَةُ المُلْكِ", "plain": "الملك", "ayahs": 30, "page": 562},
  {"n": 68, "name": "سُورَةُ القَلَمِ", "plain": "القلم", "ayahs": 52, "page": 564},
  {"n": 69, "name": "سُورَةُ الحَاقَّةِ", "plain": "الحاقة", "ayahs": 52, "page": 566},
  {"n": 70, "name": "سُورَةُ المَعَارِجِ", "plain": "المعارج", "ayahs": 44, "page": 568},
  {"n": 71, "name": "سُورَةُ نُوحٍ", "plain": "نوح", "ayahs": 28, "page": 570},
  {"n": 72, "name": "سُورَةُ الجِنِّ", "plain": "الجن", "ayahs": 28, "page": 572},
  {"n": 73, "name": "سُورَةُ المُزَّمِّلِ", "plain": "المزمل", "ayahs": 20, "page": 574},
  {"n": 74, "name": "سُورَةُ المُدَّثِّرِ", "plain": "المدثر", "ayahs": 56, "page": 575},
  {"n": 75, "name": "سُورَةُ القِيَامَةِ", "plain": "القيامة", "ayahs": 40, "page": 577},
  {"n": 76, "name": "سُورَةُ الإِنْسَانِ", "plain": "الإنسان", "ayahs": 31, "page": 578},
  {"n": 77, "name": "سُورَةُ المُرْسَلَاتِ", "plain": "المرسلات", "ayahs": 50, "page": 580},
  {"n": 78, "name": "سُورَةُ النَّبَإِ", "plain": "النبإ", "ayahs": 40, "page": 581},
  {"n": 79, "name": "سُورَةُ النَّازِعَاتِ", "plain": "النازعات", "ayahs": 46, "page": 583},
  {"n": 80, "name": "سُورَةُ عَبَسَ", "plain": "عبس", "ayahs": 42, "page": 584},
  {"n": 81, "name": "سُورَةُ التَّكْوِيرِ", "plain": "التكوير", "ayahs": 29, "page": 585},
  {"n": 82, "name": "سُورَةُ الانْفِطَارِ", "plain": "الانفطار", "ayahs": 19, "page": 586},
  {"n": 83, "name": "سُورَةُ المُطَفِّفِينَ", "plain": "المطففين", "ayahs": 36, "page": 587},
  {"n": 84, "name": "سُورَةُ الانْشِقَاقِ", "plain": "الانشقاق", "ayahs": 25, "page": 589},
  {"n": 85, "name": "سُورَةُ البُرُوجِ", "plain": "البروج", "ayahs": 22, "page": 590},
  {"n": 86, "name": "سُورَةُ الطَّارِقِ", "plain": "الطارق", "ayahs": 17, "page": 591},
  {"n": 87, "name": "سُورَةُ الأَعْلَىٰ", "plain": "الأعلى", "ayahs": 19, "page": 591},
  {"n": 88, "name": "سُورَةُ الغَاشِيَةِ", "plain": "الغاشية", "ayahs": 26, "page": 592},
  {"n": 89, "name": "سُورَةُ الفَجْرِ", "plain": "الفجر", "ayahs": 30, "page": 593},
  {"n": 90, "name": "سُورَةُ البَلَدِ", "plain": "البلد", "ayahs": 20, "page": 594},
  {"n": 91, "name": "سُورَةُ الشَّمْسِ", "plain": "الشمس", "ayahs": 15, "page": 595},
  {"n": 92, "name": "سُورَةُ اللَّيْلِ", "plain": "الليل", "ayahs": 21, "page": 595},
  {"n": 93, "name": "سُورَةُ الضُّحَىٰ", "plain": "الضحى", "ayahs": 11, "page": 596},
  {"n": 94, "name": "سُورَةُ الشَّرْحِ", "plain": "الشرح", "ayahs": 8, "page": 596},
  {"n": 95, "name": "سُورَةُ التِّينِ", "plain": "التين", "ayahs": 8, "page": 597},
  {"n": 96, "name": "سُورَةُ العَلَقِ", "plain": "العلق", "ayahs": 19, "page": 597},
  {"n": 97, "name": "سُورَةُ القَدْرِ", "plain": "القدر", "ayahs": 5, "page": 598},
  {"n": 98, "name": "سُورَةُ البَيِّنَةِ", "plain": "البينة", "ayahs": 8, "page": 598},
  {"n": 99, "name": "سُورَةُ الزَّلْزَلَةِ", "plain": "الزلزلة", "ayahs": 8, "page": 599},
  {"n": 100, "name": "سُورَةُ العَادِيَاتِ", "plain": "العاديات", "ayahs": 11, "page": 599},
  {"n": 101, "name": "سُورَةُ القَارِعَةِ", "plain": "القارعة", "ayahs": 11, "page": 600},
  {"n": 102, "name": "سُورَةُ التَّكَاثُرِ", "plain": "التكاثر", "ayahs": 8, "page": 600},
  {"n": 103, "name": "سُورَةُ العَصْرِ", "plain": "العصر", "ayahs": 3, "page": 601},
  {"n": 104, "name": "سُورَةُ الهُمَزَةِ", "plain": "الهمزة", "ayahs": 9, "page": 601},
  {"n": 105, "name": "سُورَةُ الفِيلِ", "plain": "الفيل", "ayahs": 5, "page": 601},
  {"n": 106, "name": "سُورَةُ قُرَيْشٍ", "plain": "قريش", "ayahs": 4, "page": 602},
  {"n": 107, "name": "سُورَةُ المَاعُونِ", "plain": "الماعون", "ayahs": 7, "page": 602},
  {"n": 108, "name": "سُورَةُ الكَوْثَرِ", "plain": "الكوثر", "ayahs": 3, "page": 602},
  {"n": 109, "name": "سُورَةُ الكَافِرُونَ", "plain": "الكافرون", "ayahs": 6, "page": 603},
  {"n": 110, "name": "سُورَةُ النَّصْرِ", "plain": "النصر", "ayahs": 3, "page": 603},
  {"n": 111, "name": "سُورَةُ المَسَدِ", "plain": "المسد", "ayahs": 5, "page": 603},
  {"n": 112, "name": "سُورَةُ الإِخْلَاصِ", "plain": "الإخلاص", "ayahs": 4, "page": 604},
  {"n": 113, "name": "سُورَةُ الفَلَقِ", "plain": "الفلق", "ayahs": 5, "page": 604},
  {"n": 114, "name": "سُورَةُ النَّاسِ", "plain": "الناس", "ayahs": 6, "page": 604},
];

class QuranakApp extends StatelessWidget {
  const QuranakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'قرآنك',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF07131C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFC9A959),
          secondary: Color(0xFF0D2B35),
          surface: Color(0xFF0F2B3D),
        ),
        useMaterial3: true,
      ),
      home: const QuranakIntroScreen(),
    );
  }
}

class QuranakIntroScreen extends StatefulWidget {
  const QuranakIntroScreen({super.key});

  @override
  State<QuranakIntroScreen> createState() => _QuranakIntroScreenState();
}

class _QuranakIntroScreenState extends State<QuranakIntroScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    Timer(const Duration(milliseconds: 1700), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const OriginalMainShell()),
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D2B35), Color(0xFF071915), Color(0xFF07131C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFFC9A959), Color(0xFFA8893A)]),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFC9A959).withOpacity(0.35), blurRadius: 24),
                  ],
                ),
                child: const Icon(Icons.menu_book_rounded, size: 54, color: Colors.black),
              ),
              const SizedBox(height: 22),
              const Text(
                'قُرْآنَك',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFC9A959),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'القرآن الكريم • مواقيت الصلاة • صوتيات وريلز',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OriginalMainShell extends StatefulWidget {
  const OriginalMainShell({super.key});

  @override
  State<OriginalMainShell> createState() => _OriginalMainShellState();
}

class _OriginalMainShellState extends State<OriginalMainShell> {
  int _tabIndex = 0;
  CityInfo _selectedCity = egyptianCities.first;
  Map<String, DateTime> _prayerTimes = {};
  Timer? _countdownTimer;
  String _nextPrayerName = 'العصر';
  String _nextPrayerKey = 'Asr';
  String _countdownStr = '--:--:--';

  final AudioPlayer _audioPlayer = AudioPlayer();
  String _playingSurah = '';
  String _playingReciter = '';
  Map<String, dynamic> _playingReciterData = {};
  bool _isPlaying = false;
  StreamSubscription? _adminSub;
  String? _lastNotifId;

  @override
  void initState() {
    super.initState();
    _audioPlayer.playerStateStream.listen((s) {
      if (mounted) setState(() => _isPlaying = s.playing);
    });
    _initEverything();
  }

  Future<void> _initEverything() async {
    // Render the shell immediately; disk/network services are non-blocking.
    unawaited(OfflineAudioManager.instance.init());
    unawaited(QuranakApi.syncCatalogs().then((_) { if (mounted) setState(() {}); }));
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCity = prefs.getString('selectedCity') ?? 'القاهرة';
      _selectedCity = egyptianCities.firstWhere(
        (c) => c.ar == savedCity,
        orElse: () => egyptianCities.first,
      );
    } catch (_) {}
    // Prayer times are calculated locally; alarm scheduling is best-effort.
    unawaited(_refreshCityAndAdhan(_selectedCity));
  }

  Future<void> _refreshCityAndAdhan(CityInfo city) async {
    _selectedCity = city;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedCity', city.ar);
    final times = await AdhanAlarmService.schedule7DaysForCity(city.lat, city.lng, city.ar);
    if (mounted) {
      setState(() => _prayerTimes = times);
      _startLiveCountdown();
    }
  }

  void _startLiveCountdown() {
    _countdownTimer?.cancel();
    void tick() {
      if (_prayerTimes.isEmpty) return;
      final now = DateTime.now();
      final order = [
        MapEntry('Fajr', 'الفجر'),
        MapEntry('Sunrise', 'الشروق'),
        MapEntry('Dhuhr', 'الظهر'),
        MapEntry('Asr', 'العصر'),
        MapEntry('Maghrib', 'المغرب'),
        MapEntry('Isha', 'العشاء'),
      ];
      DateTime? target;
      String tName = 'الفجر';
      String tKey = 'Fajr';

      for (final item in order) {
        final dt = _prayerTimes[item.key];
        if (dt != null && dt.isAfter(now)) {
          target = dt;
          tName = item.value;
          tKey = item.key;
          break;
        }
      }
      if (target == null && _prayerTimes['Fajr'] != null) {
        target = _prayerTimes['Fajr']!.add(const Duration(days: 1));
        tName = 'الفجر';
        tKey = 'Fajr';
      }
      if (target != null && mounted) {
        final diff = target.difference(now);
        final h = diff.inHours.toString().padLeft(2, '0');
        final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
        final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
        setState(() {
          _nextPrayerName = tName;
          _nextPrayerKey = tKey;
          _countdownStr = '$h : $m : $s';
        });
      }
    }

    tick();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _listenAdminBroadcasts() {
    // Firebase is optional for this build. The website API remains the source
    // of truth; do not touch Firestore unless a Firebase app was configured.
    if (Firebase.apps.isEmpty) return;
    try {
      _adminSub = FirebaseFirestore.instance
          .collection('admin_notifications')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots()
          .listen((snap) async {
        if (snap.docs.isEmpty) return;
        final doc = snap.docs.first;
        final prefs = await SharedPreferences.getInstance();
        final seen = prefs.getString('last_admin_notif_v8');
        if (doc.id != seen && doc.id != _lastNotifId) {
          _lastNotifId = doc.id;
          await prefs.setString('last_admin_notif_v8', doc.id);
          final d = doc.data();
          await AdhanAlarmService.showAdminBroadcast(
            d['title'] ?? 'قرآنك',
            d['body'] ?? '',
          );
        }
      });
    } catch (_) {}
  }

  String _resolveReciterAudioUrl(Map<String, dynamic> reciterData, int surahNum) {
    final p3 = surahNum.toString().padLeft(3, '0');
    final directKeys = [
      'audio_$surahNum',
      'audio_$p3',
      'surah_$surahNum',
      'surah_$p3',
      'url_$surahNum',
      'url_$p3',
    ];
    for (final k in directKeys) {
      final v = reciterData[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }

    final rawBase = (reciterData['server'] ??
            reciterData['serverUrl'] ??
            reciterData['base_url'] ??
            reciterData['audio_url'] ??
            reciterData['url'] ??
            '')
        .toString()
        .trim();

    if (rawBase.isNotEmpty) {
      if (rawBase.contains('{surah3}')) {
        return rawBase.replaceAll('{surah3}', p3).replaceAll('{surah}', '$surahNum');
      }
      if (rawBase.contains('{surah}')) {
        return rawBase.replaceAll('{surah}', '$surahNum');
      }
      if (RegExp(r'\d+\.mp3$', caseSensitive: false).hasMatch(rawBase)) {
        return rawBase.replaceFirst(RegExp(r'\d+\.mp3$', caseSensitive: false), '$p3.mp3');
      }
      final clean = rawBase.endsWith('/') ? rawBase : '$rawBase/';
      return '$clean$p3.mp3';
    }

    return ''; // Never invent a reciter URL; use the exact audio_url saved by the admin.
  }

  Future<void> _playSurahAudio({
    required String id,
    required String title,
    required String reciter,
    required Map<String, dynamic> reciterData,
    required String url,
  }) async {
    try {
      await _audioPlayer.stop();
      setState(() {
        _playingSurah = title;
        _playingReciter = reciter;
        _playingReciterData = reciterData;
      });
      final imgStr = ReciterAvatarImage.extractBestImage(reciterData);
      final mediaItem = MediaItem(
        id: id,
        album: reciter,
        title: title,
        artist: reciter,
        artUri: imgStr.startsWith('http') ? Uri.parse(imgStr) : null,
      );
      final local = OfflineAudioManager.instance.localPathOf(id);
      if (local != null && File(local).existsSync()) {
        await _audioPlayer.setAudioSource(AudioSource.file(local, tag: mediaItem));
      } else {
        await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(url), tag: mediaItem));
      }
      await _audioPlayer.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تشغيل الصوت: $e')));
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _adminSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      OriginalHomeTab(
        selectedCity: _selectedCity,
        onCityChanged: _refreshCityAndAdhan,
        prayerTimes: _prayerTimes,
        nextPrayerName: _nextPrayerName,
        nextPrayerKey: _nextPrayerKey,
        countdownStr: _countdownStr,
        onSwitchTab: (i) => setState(() => _tabIndex = i),
        onPlayAudio: _playSurahAudio,
        resolveAudioUrl: _resolveReciterAudioUrl,
      ),
      const OriginalQuranSurahsTab(),
      const OriginalJuzTab(),
      OriginalAudiosTab(
        onPlayAudio: _playSurahAudio,
        resolveAudioUrl: _resolveReciterAudioUrl,
      ),
      OriginalReelsTab(isActive: _tabIndex == 4),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF07131C),
      body: IndexedStack(index: _tabIndex, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_playingSurah.isNotEmpty)
            InkWell(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => FullSpotifyPlayerSheet(
                  player: _audioPlayer,
                  title: _playingSurah,
                  reciter: _playingReciter,
                  reciterData: _playingReciterData,
                ),
              ),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF1A3A4A), Color(0xFF0F2530)]),
                  border: Border(top: BorderSide(color: Color(0xFFC9A959), width: 0.8)),
                ),
                child: Row(
                  children: [
                    ReciterAvatarImage(data: _playingReciterData, size: 40, borderWidth: 1.5),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_playingSurah, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                          Text(_playingReciter, style: const TextStyle(fontSize: 11, color: Colors.white60)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          color: Colors.white, size: 34),
                      onPressed: () => _isPlaying ? _audioPlayer.pause() : _audioPlayer.play(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () {
                        _audioPlayer.stop();
                        setState(() => _playingSurah = '');
                      },
                    ),
                  ],
                ),
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0F2B3D),
              border: Border(top: BorderSide(color: Color(0xFFC9A959), width: 0.9)),
            ),
            child: BottomNavigationBar(
              currentIndex: _tabIndex,
              onTap: (i) => setState(() => _tabIndex = i),
              backgroundColor: const Color(0xFF0F2B3D),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: const Color(0xFFC9A959),
              unselectedItemColor: const Color(0xFF7F8C8D),
              selectedFontSize: 11,
              unselectedFontSize: 10,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'الرئيسية'),
                BottomNavigationBarItem(icon: Icon(Icons.menu_book_rounded), label: 'القرآن'),
                BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'أجزاء'),
                BottomNavigationBarItem(icon: Icon(Icons.headphones_rounded), label: 'صوتيات'),
                BottomNavigationBarItem(icon: Icon(Icons.movie_filter_rounded), label: 'ريلز'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OriginalHomeTab extends StatelessWidget {
  final CityInfo selectedCity;
  final ValueChanged<CityInfo> onCityChanged;
  final Map<String, DateTime> prayerTimes;
  final String nextPrayerName;
  final String nextPrayerKey;
  final String countdownStr;
  final ValueChanged<int> onSwitchTab;
  final Function({required String id, required String title, required String reciter, required Map<String, dynamic> reciterData, required String url}) onPlayAudio;
  final String Function(Map<String, dynamic> reciterData, int surahNum) resolveAudioUrl;

  const OriginalHomeTab({
    super.key,
    required this.selectedCity,
    required this.onCityChanged,
    required this.prayerTimes,
    required this.nextPrayerName,
    required this.nextPrayerKey,
    required this.countdownStr,
    required this.onSwitchTab,
    required this.onPlayAudio,
    required this.resolveAudioUrl,
  });

  String _fmt12(DateTime? dt) {
    if (dt == null) return '--:--';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final suf = dt.hour >= 12 ? 'م' : 'ص';
    return '$h:$m $suf';
  }

  String _heroBgForPrayer(String key) {
    switch (key) {
      case 'Fajr':
        return 'assets/images/20.png';
      case 'Sunrise':
        return 'assets/images/22.png';
      case 'Maghrib':
        return 'assets/images/24.png';
      case 'Isha':
        return 'assets/images/23.png';
      default:
        return 'assets/images/21.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hijri = HijriCalendar.now();
    final hijriStr = formatHijriArabic(hijri);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 295,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A2A25), Color(0xFF071915)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  _heroBgForPrayer(nextPrayerKey),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF07131C).withOpacity(0.45),
                        const Color(0xFF07131C).withOpacity(0.28),
                        const Color(0xFF07131C).withOpacity(0.85),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () => _openCityDialog(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.42),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_rounded, color: Color(0xFFC9A959), size: 15),
                                    const SizedBox(width: 5),
                                    Text(selectedCity.ar, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white70),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.42),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white.withOpacity(0.16)),
                              ),
                              child: Text(hijriStr, style: const TextStyle(fontSize: 12, color: Colors.white)),
                            ),
                          ],
                        ),
                        const Spacer(),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                            children: [
                              const TextSpan(text: 'المتبقي على صلاة '),
                              TextSpan(
                                text: nextPrayerName,
                                style: const TextStyle(color: Color(0xFFC9A959), fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            countdownStr,
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: Colors.white,
                              shadows: [Shadow(color: Colors.black87, blurRadius: 18)],
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.48),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withOpacity(0.12)),
                          ),
                          child: Row(
                            children: [
                              _prayerCol('الفجر', _fmt12(prayerTimes['Fajr']), nextPrayerKey == 'Fajr'),
                              _prayerCol('الشروق', _fmt12(prayerTimes['Sunrise']), nextPrayerKey == 'Sunrise'),
                              _prayerCol('الظهر', _fmt12(prayerTimes['Dhuhr']), nextPrayerKey == 'Dhuhr'),
                              _prayerCol('العصر', _fmt12(prayerTimes['Asr']), nextPrayerKey == 'Asr'),
                              _prayerCol('المغرب', _fmt12(prayerTimes['Maghrib']), nextPrayerKey == 'Maghrib'),
                              _prayerCol('العشاء', _fmt12(prayerTimes['Isha']), nextPrayerKey == 'Isha'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.mic_rounded, color: Color(0xFFC9A959), size: 20),
                    SizedBox(width: 6),
                    Text('القراء', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFFC9A959))),
                  ],
                ),
                GestureDetector(
                  onTap: () => onSwitchTab(3),
                  child: const Row(
                    children: [
                      Text('عرض الكل', style: TextStyle(fontSize: 12, color: Color(0xFFA0B9C4))),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFA0B9C4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 112,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: QuranakApi.getList('get_reciters', cacheKey: 'cached_reciters_v8'),
              builder: (context, snap) {
                final reciters = snap.data ?? const <Map<String, dynamic>>[];
                if (reciters.isEmpty) {
                  return const Center(child: Text('لا يوجد قراء محفوظون بعد أول اتصال بالإنترنت', style: TextStyle(color: Colors.white54)));
                }
                return _buildRecitersRow(context, reciters);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.access_time_filled_rounded, color: Color(0xFFC9A959), size: 19),
                    SizedBox(width: 6),
                    Text('أضيف حديثاً', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFFC9A959))),
                  ],
                ),
                GestureDetector(
                  onTap: () => onSwitchTab(4),
                  child: const Row(
                    children: [
                      Text('عرض الكل', style: TextStyle(fontSize: 12, color: Color(0xFFA0B9C4))),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFA0B9C4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 225,
            child: StreamBuilder<QuerySnapshot>(
              stream: QuranakApi.watchCollection('videos'),
              builder: (context, snap) {
                final liveDocs = snap.data?.docs ?? [];
                if (liveDocs.isNotEmpty) {
                  final mapped = liveDocs
                      .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
                      .toList();
                  OfflineCacheService.saveVideos(mapped);
                  return _buildVideosRow(context, mapped);
                }
                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: OfflineCacheService.loadVideos(),
                  builder: (_, cSnap) {
                    final cached = cSnap.data ?? [];
                    if (cached.isEmpty) {
                      return const Center(child: Text('لا توجد مقاطع مضافة حديثاً', style: TextStyle(color: Colors.white54)));
                    }
                    return _buildVideosRow(context, cached);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.35,
              children: [
                _quickCard(context, 'الأذكار', Icons.volunteer_activism_rounded, const Color(0xFF10B981),
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OriginalAzkarScreen()))),
                _quickCard(context, 'المسبحة', Icons.radio_button_checked_rounded, const Color(0xFFC9A959),
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OriginalTasbihScreen()))),
                _quickCard(context, 'الأحاديث', Icons.menu_book_rounded, const Color(0xFF38BDF8),
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OriginalHadithScreen()))),
                _quickCard(context, 'التقويم', Icons.calendar_month_rounded, const Color(0xFFF59E0B),
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => OriginalCalendarScreen(selectedCity: selectedCity)))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecitersRow(BuildContext context, List<Map<String, dynamic>> items) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 14),
      itemBuilder: (context, i) {
        final r = items[i];
        final name = (r['name'] ?? '').toString();
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OriginalReciterDetailScreen(
                reciterData: r,
                onPlayAudio: onPlayAudio,
                resolveAudioUrl: resolveAudioUrl,
              ),
            ),
          ),
          child: SizedBox(
            width: 78,
            child: Column(
              children: [
                ReciterAvatarImage(data: r, size: 74, borderWidth: 2.5),
                const SizedBox(height: 6),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideosRow(BuildContext context, List<Map<String, dynamic>> items) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, i) {
        final v = items[i];
        return GestureDetector(
          onTap: () => onSwitchTab(4),
          child: Container(
            width: 132,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC9A959).withOpacity(0.35), width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if ((v['thumbnail'] ?? '').toString().isNotEmpty)
                    Image.network(v['thumbnail'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => _videoThumbBg())
                  else
                    _videoThumbBg(),
                  Center(
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFC9A959), width: 1.8),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Color(0xFFC9A959), size: 24),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        (v['duration'] ?? '00:45').toString(),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _prayerCol(String name, String time, bool active) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFC9A959).withOpacity(0.24) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                color: active ? const Color(0xFFC9A959) : Colors.white70,
              ),
            ),
            const SizedBox(height: 3),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                time,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoThumbBg() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A4755), Color(0xFF0D2B35)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(child: Icon(Icons.mosque_rounded, color: Color(0xFFC9A959), size: 36)),
    );
  }

  Widget _quickCard(BuildContext ctx, String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1A4755), Color(0xFF0F2B3D)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC9A959).withOpacity(0.25), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                color: color.withOpacity(0.12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _openCityDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D2B35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFC9A959)),
        ),
        title: const Text('اختر المدينة', style: TextStyle(color: Color(0xFFC9A959), fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.7,
            ),
            itemCount: egyptianCities.length,
            itemBuilder: (_, i) {
              final c = egyptianCities[i];
              final sel = c.ar == selectedCity.ar;
              return InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  onCityChanged(c);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFC9A959) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFC9A959).withOpacity(0.3)),
                  ),
                  child: Text(
                    c.ar,
                    style: TextStyle(
                      color: sel ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class OriginalQuranSurahsTab extends StatefulWidget {
  const OriginalQuranSurahsTab({super.key});

  @override
  State<OriginalQuranSurahsTab> createState() => _OriginalQuranSurahsTabState();
}

class _OriginalQuranSurahsTabState extends State<OriginalQuranSurahsTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = all114Surahs.where((s) {
      if (_q.trim().isEmpty) return true;
      return s['plain'].toString().contains(_q.trim()) ||
          s['name'].toString().contains(_q.trim()) ||
          s['n'].toString() == _q.trim();
    }).toList();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: '🔍 ابحث عن سورة...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF07131C),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Color(0xFFC9A959), width: 1.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Color(0xFFC9A959), width: 2),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final s = list[i];
                return InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MushafPageViewerScreen(
                        initialPage: s['page'] as int,
                        title: s['name'] as String,
                      ),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 76,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1A4755), Color(0xFF0F2B3D)]),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFC9A959).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFC9A959), Color(0xFFA8893A)]),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '${s['n']}',
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 19),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                s['name'] as String,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${s['ayahs']} آية',
                                style: const TextStyle(fontSize: 12, color: Color(0xFFA0B9C4)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 50),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MushafPageViewerScreen extends StatefulWidget {
  final int initialPage;
  final String title;
  const MushafPageViewerScreen({super.key, required this.initialPage, required this.title});

  @override
  State<MushafPageViewerScreen> createState() => _MushafPageViewerScreenState();
}

class _MushafPageViewerScreenState extends State<MushafPageViewerScreen> {
  late PageController _pc;
  late int _page;
  String _currentSurahName = '';
  String _cacheDir = '';

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(1, 604).toInt();
    _currentSurahName = _surahNameForPage(_page);
    _pc = PageController(initialPage: _page - 1);
    _initCacheDir();
  }

  Future<void> _initCacheDir() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final mushafDir = Directory('${dir.path}/mushaf_pages_offline');
      if (!mushafDir.existsSync()) mushafDir.createSync(recursive: true);
      if (mounted) setState(() => _cacheDir = mushafDir.path);
      _cachePage(_page);
      if (_page < 604) _cachePage(_page + 1);
    } catch (_) {}
  }

  String _surahNameForPage(int page) {
    String name = all114Surahs.first['name'] as String;
    for (final s in all114Surahs) {
      if (page >= (s['page'] as int)) {
        name = s['name'] as String;
      } else {
        break;
      }
    }
    return name;
  }

  Future<File?> _cachePage(int pageNum) async {
    if (_cacheDir.isEmpty) return null;
    final pStr = pageNum.toString().padLeft(3, '0');
    final file = File('$_cacheDir/$pStr.png');
    if (file.existsSync() && file.lengthSync() > 1000) return file;
    try {
      final url = 'https://quran.yousefheiba.com/api/quran-pages/$pStr.png';
      await Dio().download(url, file.path);
      return file;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2B35),
        title: Text(
          _currentSurahName,
          style: const TextStyle(color: Color(0xFFC9A959), fontWeight: FontWeight.bold),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Text(
                '$_page / 604',
                style: const TextStyle(color: Color(0xFFE2C78A), fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: 604,
        onPageChanged: (idx) {
          final newPage = idx + 1;
          setState(() {
            _page = newPage;
            _currentSurahName = _surahNameForPage(newPage);
          });
          _cachePage(newPage);
          if (newPage < 604) _cachePage(newPage + 1);
        },
        itemBuilder: (context, idx) {
          final pageNum = idx + 1;
          final pStr = pageNum.toString().padLeft(3, '0');
          final localFile = _cacheDir.isNotEmpty ? File('$_cacheDir/$pStr.png') : null;
          final url = 'https://quran.yousefheiba.com/api/quran-pages/$pStr.png';

          if (localFile != null && localFile.existsSync() && localFile.lengthSync() > 1000) {
            return InteractiveViewer(
              child: Center(child: Image.file(localFile, fit: BoxFit.contain)),
            );
          }

          return FutureBuilder<File?>(
            future: _cachePage(pageNum),
            builder: (context, snap) {
              if (snap.data != null && snap.data!.existsSync()) {
                return InteractiveViewer(
                  child: Center(child: Image.file(snap.data!, fit: BoxFit.contain)),
                );
              }
              return InteractiveViewer(
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (c, child, prog) =>
                        prog == null ? child : const CircularProgressIndicator(color: Color(0xFFC9A959)),
                    errorBuilder: (_, __, ___) => const Text(
                      'الصفحة غير محفوظة أوفلاين، اتصل بالإنترنت لتحميلها',
                      style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

const List<int> juzStartPages = [
  1, 22, 42, 62, 82, 102, 121, 142, 162, 182,
  201, 222, 242, 262, 282, 302, 322, 342, 362, 382,
  402, 422, 442, 462, 482, 502, 522, 542, 562, 582
];

class OriginalJuzTab extends StatelessWidget {
  const OriginalJuzTab({super.key});

  List<Map<String, dynamic>> _surahsInJuz(int juz) {
    final start = juzStartPages[juz - 1];
    final end = juz < 30 ? juzStartPages[juz] - 1 : 604;
    return all114Surahs.where((s) {
      final p = s['page'] as int;
      return p >= start && p <= end;
    }).toList();
  }

  void _openJuzSurahsSheet(BuildContext context, int juz) {
    final surahs = _surahsInJuz(juz);
    final startPage = juzStartPages[juz - 1];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D2B35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: Color(0xFFC9A959), width: 1),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('سور الجزء $juz',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFC9A959))),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MushafPageViewerScreen(initialPage: startPage, title: 'الجزء $juz'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.menu_book_rounded, color: Color(0xFFC9A959), size: 18),
                    label: Text('بداية الجزء (ص $startPage)', style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: surahs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = surahs[i];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: const Color(0xFFC9A959).withOpacity(0.25)),
                      ),
                      tileColor: const Color(0xFF0F2B3D),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFC9A959),
                        child: Text('${s['n']}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(s['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text('${s['ayahs']} آية • صفحة ${s['page']}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFC9A959), size: 16),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MushafPageViewerScreen(
                              initialPage: s['page'] as int,
                              title: s['name'] as String,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GridView.builder(
        padding: const EdgeInsets.all(14),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
        ),
        itemCount: 30,
        itemBuilder: (context, i) {
          final juz = i + 1;
          return InkWell(
            onTap: () => _openJuzSurahsSheet(context, juz),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1A4755), Color(0xFF0F2B3D)]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC9A959).withOpacity(0.3)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$juz',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFC9A959))),
                  const SizedBox(height: 4),
                  Text('الجزء $juz', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class FullSpotifyPlayerSheet extends StatelessWidget {
  final AudioPlayer player;
  final String title;
  final String reciter;
  final Map<String, dynamic> reciterData;

  const FullSpotifyPlayerSheet({
    super.key,
    required this.player,
    required this.title,
    required this.reciter,
    required this.reciterData,
  });

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A4755), Color(0xFF0D2B35), Color(0xFF07131C)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0xFFC9A959), width: 1.2)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Column(
            children: [
              Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 18),
              const Text('جاري التشغيل الآن', style: TextStyle(color: Color(0xFFC9A959), fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              ReciterAvatarImage(data: reciterData, size: 205, borderWidth: 3.5),
              const SizedBox(height: 26),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 6),
              Text(reciter, style: const TextStyle(fontSize: 15, color: Color(0xFFE2C78A), fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (_, posSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = player.duration ?? Duration.zero;
                  final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                  final curMs = pos.inMilliseconds.clamp(0, dur.inMilliseconds > 0 ? dur.inMilliseconds : 1).toDouble();
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFFC9A959),
                          inactiveTrackColor: Colors.white24,
                          thumbColor: const Color(0xFFC9A959),
                        ),
                        child: Slider(
                          value: curMs,
                          max: maxMs,
                          onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmtDur(pos), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                          Text(_fmtDur(dur), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  StreamBuilder<LoopMode>(
                    stream: player.loopModeStream,
                    builder: (_, snap) {
                      final isOne = snap.data == LoopMode.one;
                      return IconButton(
                        icon: Icon(Icons.repeat_one_rounded, color: isOne ? const Color(0xFFC9A959) : Colors.white54, size: 26),
                        onPressed: () => player.setLoopMode(isOne ? LoopMode.off : LoopMode.one),
                      );
                    },
                  ),
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (_, snap) {
                      final playing = snap.data?.playing ?? false;
                      return InkWell(
                        onTap: () => playing ? player.pause() : player.play(),
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [Color(0xFFC9A959), Color(0xFFA8893A)]),
                          ),
                          child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 38),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined, color: Colors.white70, size: 28),
                    onPressed: () {
                      player.stop();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class OriginalReelsTab extends StatefulWidget {
  final bool isActive;
  const OriginalReelsTab({super.key, this.isActive = true});

  @override
  State<OriginalReelsTab> createState() => _OriginalReelsTabState();
}

class _OriginalReelsTabState extends State<OriginalReelsTab> {
  VideoPlayerController? _vc;
  int _currentIdx = 0;
  String _currentUrl = '';

  @override
  void didUpdateWidget(covariant OriginalReelsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _disposeController();
    }
  }

  Future<void> _loadVideo(String url) async {
    if (!widget.isActive || url.isEmpty) return;
    if (_currentUrl == url && _vc != null && _vc!.value.isInitialized) {
      if (!_vc!.value.isPlaying) await _vc!.play();
      return;
    }
    _disposeController();
    _currentUrl = url;
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      _vc = ctrl;
      await ctrl.initialize();
      await ctrl.setLooping(true);
      if (widget.isActive && mounted) {
        setState(() {});
        await ctrl.play();
      }
    } catch (_) {}
  }

  void _disposeController() {
    _currentUrl = '';
    final old = _vc;
    _vc = null;
    old?.pause();
    old?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return const Center(
        child: Text('افتح تبويب الريلز لعرض المقاطع', style: TextStyle(color: Colors.white60)),
      );
    }

    return SafeArea(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: QuranakApi.getList('get_videos', cacheKey: 'cached_videos_v8'),
        builder: (context, snap) {
          final docs = snap.data ?? const <Map<String, dynamic>>[];
          if (docs.isEmpty) {
            return Center(child: Text(snap.connectionState == ConnectionState.waiting ? 'جاري تحميل المقاطع…' : 'لا توجد مقاطع محفوظة أو متاحة حالياً', style: const TextStyle(color: Colors.white60)));
          }
          final firstData = docs[_currentIdx.clamp(0, docs.length - 1).toInt()];
          final firstUrl = (firstData['videoUrl'] ?? firstData['video_url'] ?? firstData['url'] ?? '').toString();
          if (firstUrl.isNotEmpty && _currentUrl != firstUrl) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadVideo(firstUrl));
          }
          return PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: docs.length,
            onPageChanged: (i) {
              setState(() => _currentIdx = i);
              final d = docs[i];
              final u = (d['videoUrl'] ?? d['video_url'] ?? d['url'] ?? '').toString();
              _loadVideo(u);
            },
            itemBuilder: (context, i) {
              final d = docs[i];
              final title = (d['title'] ?? d['reciter_name'] ?? d['reciter'] ?? 'مقطع قرآني').toString();
              final isReady = i == _currentIdx && _vc != null && _vc!.value.isInitialized;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  if (isReady)
                    Center(child: AspectRatio(aspectRatio: _vc!.value.aspectRatio > 0 ? _vc!.value.aspectRatio : 9 / 16, child: VideoPlayer(_vc!)))
                  else
                    const Center(child: Icon(Icons.play_circle_outline, size: 64, color: Colors.white54)),
                  Positioned(bottom: 24, right: 16, left: 16, child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class OriginalCalendarScreen extends StatefulWidget {
  final CityInfo selectedCity;
  const OriginalCalendarScreen({super.key, required this.selectedCity});

  @override
  State<OriginalCalendarScreen> createState() => _OriginalCalendarScreenState();
}

class _OriginalCalendarScreenState extends State<OriginalCalendarScreen> {
  late DateTime _selectedDate;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _visibleMonth = DateTime(now.year, now.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final hijri = HijriCalendar.fromDate(_selectedDate);
    final weekdayName = arabicWeekdaysFull[_selectedDate.weekday];
    final gregorianFull =
        '${_selectedDate.day} ${arabicMonths[_selectedDate.month]} ${_selectedDate.year}';
    final monthTitle =
        '${arabicMonths[_visibleMonth.month]} ${_visibleMonth.year}';

    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leadingEmpty = firstOfMonth.weekday % 7;

    final totalCells = ((leadingEmpty + daysInMonth + 6) ~/ 7) * 7;

    return Scaffold(
      backgroundColor: const Color(0xFF071915),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A221C),
        elevation: 0,
        title: const Text(
          'التقويم',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0B241E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1B4D3E).withOpacity(0.6)),
              ),
              child: Column(
                children: [
                  Text(
                    weekdayName,
                    style: const TextStyle(fontSize: 16, color: Color(0xFF8CC4B3), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatHijriArabic(hijri),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    gregorianFull,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF9ECBB9)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _circleNavBtn(Icons.chevron_left_rounded, () {
                  setState(() {
                    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
                  });
                }),
                Text(
                  monthTitle,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                _circleNavBtn(Icons.chevron_right_rounded, () {
                  setState(() {
                    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
                  });
                }),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A211B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF184538).withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Row(
                    children: arabicWeekdaysShort
                        .map(
                          (d) => Expanded(
                            child: Center(
                              child: Text(
                                d.substring(0, 2),
                                style: const TextStyle(
                                  color: Color(0xFF5FA58E),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: totalCells,
                    itemBuilder: (context, idx) {
                      final dayOffset = idx - leadingEmpty;
                      DateTime cellDate;
                      bool isCurrentMonth = true;
                      if (dayOffset < 0) {
                        isCurrentMonth = false;
                        cellDate = firstOfMonth.add(Duration(days: dayOffset));
                      } else if (dayOffset >= daysInMonth) {
                        isCurrentMonth = false;
                        cellDate = DateTime(_visibleMonth.year, _visibleMonth.month, dayOffset + 1);
                      } else {
                        cellDate = DateTime(_visibleMonth.year, _visibleMonth.month, dayOffset + 1);
                      }

                      final isSelected = cellDate.year == _selectedDate.year &&
                          cellDate.month == _selectedDate.month &&
                          cellDate.day == _selectedDate.day;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedDate = cellDate;
                            if (!isCurrentMonth) {
                              _visibleMonth = DateTime(cellDate.year, cellDate.month, 1);
                            }
                          });
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF199E6B) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF199E6B).withOpacity(0.45),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            '${cellDate.day}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : (isCurrentMonth ? Colors.white : Colors.white24),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleNavBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF0D2821),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF1E5242)),
        ),
        child: Icon(icon, color: Colors.white70),
      ),
    );
  }
}

class OriginalAzkarScreen extends StatelessWidget {
  const OriginalAzkarScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final azkar = [
      'أصبحنا وأصبح الملك لله، والحمد لله، لا إله إلا الله وحده لا شريك له.',
      'اللهم بك أصبحنا، وبك أمسينا، وبك نحيا، وبك نموت، وإليك النشور.',
      'سبحان الله وبحمده عدد خلقه، ورضا نفسه، وزنة عرشه، ومداد كلماته.',
      'أستغفر الله العظيم الذي لا إله إلا هو الحي القيوم وأتوب إليه.',
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF07131C),
      appBar: AppBar(backgroundColor: const Color(0xFF0D2B35), title: const Text('الأذكار', style: TextStyle(color: Color(0xFFC9A959)))),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: azkar.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF0F2B3D), borderRadius: BorderRadius.circular(14)),
          child: Text(azkar[i], style: const TextStyle(fontSize: 16, height: 1.7, color: Colors.white)),
        ),
      ),
    );
  }
}

class OriginalTasbihScreen extends StatefulWidget {
  const OriginalTasbihScreen({super.key});
  @override
  State<OriginalTasbihScreen> createState() => _OriginalTasbihScreenState();
}

class _OriginalTasbihScreenState extends State<OriginalTasbihScreen> {
  int _count = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07131C),
      appBar: AppBar(backgroundColor: const Color(0xFF0D2B35), title: const Text('المسبحة الإلكترونية', style: TextStyle(color: Color(0xFFC9A959)))),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('سُبْحَانَ اللَّهِ وَبِحَمْدِهِ', style: TextStyle(fontSize: 22, color: Color(0xFFC9A959), fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Text('$_count', style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC9A959),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: () => setState(() => _count++),
              child: const Text('سبّح', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            TextButton(
              onPressed: () => setState(() => _count = 0),
              child: const Text('تصفير العداد', style: TextStyle(color: Colors.white60)),
            ),
          ],
        ),
      ),
    );
  }
}

class OriginalHadithScreen extends StatelessWidget {
  const OriginalHadithScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final hadiths = [
      'قال رسول الله ﷺ: «خيركم من تعلم القرآن وعلمه» رواه البخاري.',
      'قال رسول الله ﷺ: «من قرأ حرفاً من كتاب الله فله به حسنة، والحسنة بعشر أمثالها» رواه الترمذي.',
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF07131C),
      appBar: AppBar(backgroundColor: const Color(0xFF0D2B35), title: const Text('الأحاديث النبوية', style: TextStyle(color: Color(0xFFC9A959)))),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: hadiths.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF0F2B3D), borderRadius: BorderRadius.circular(14)),
          child: Text(hadiths[i], style: const TextStyle(fontSize: 16, height: 1.7, color: Colors.white)),
        ),
      ),
    );
  }
}

class OriginalAudiosTab extends StatelessWidget {
  final Function({required String id, required String title, required String reciter, required Map<String, dynamic> reciterData, required String url}) onPlayAudio;
  final String Function(Map<String, dynamic> reciterData, int surahNum) resolveAudioUrl;

  const OriginalAudiosTab({
    super.key,
    required this.onPlayAudio,
    required this.resolveAudioUrl,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: QuranakApi.getList('get_reciters', cacheKey: 'cached_reciters_v8'),
        builder: (context, snap) {
          final items = snap.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return Center(child: Text(snap.connectionState == ConnectionState.waiting ? 'جاري تحميل القراء…' : 'لا يوجد قراء محفوظون أوفلاين بعد أول اتصال', style: const TextStyle(color: Colors.white60)));
          }
          return _buildList(context, items);
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Map<String, dynamic>> items) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = items[i];
        final name = (r['name'] ?? 'قارئ').toString();
        return ListTile(
          tileColor: const Color(0xFF0F2B3D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: const Color(0xFFC9A959).withOpacity(0.25)),
          ),
          leading: ReciterAvatarImage(data: r, size: 50, borderWidth: 2),
          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: const Text('اضغط لاستعراض السور الصوتية', style: TextStyle(color: Colors.white60, fontSize: 12)),
          trailing: const Icon(Icons.chevron_left_rounded, color: Color(0xFFC9A959)),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OriginalReciterDetailScreen(
                reciterData: r,
                onPlayAudio: onPlayAudio,
                resolveAudioUrl: resolveAudioUrl,
              ),
            ),
          ),
        );
      },
    );
  }
}

class OriginalReciterDetailScreen extends StatelessWidget {
  final Map<String, dynamic> reciterData;
  final Function({required String id, required String title, required String reciter, required Map<String, dynamic> reciterData, required String url}) onPlayAudio;
  final String Function(Map<String, dynamic> reciterData, int surahNum) resolveAudioUrl;

  const OriginalReciterDetailScreen({
    super.key,
    required this.reciterData,
    required this.onPlayAudio,
    required this.resolveAudioUrl,
  });

  @override
  Widget build(BuildContext context) {
    final name = (reciterData['name'] ?? 'قارئ').toString();
    final reciterKey = (reciterData['id'] ?? name).toString();

    return Scaffold(
      backgroundColor: const Color(0xFF07131C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2B35),
        title: Text(name, style: const TextStyle(color: Color(0xFFC9A959), fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          ReciterAvatarImage(data: reciterData, size: 96, borderWidth: 3),
          const SizedBox(height: 10),
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: QuranakApi.getAudiosForReciter(reciterData['id']),
              builder: (context, audioSnap) {
                final apiRows = audioSnap.data ?? const <Map<String, dynamic>>[];
                final count = apiRows.length;
                if (audioSnap.connectionState == ConnectionState.waiting && count == 0) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFC9A959)));
                }
                if (count == 0) {
                  return const Center(child: Text('لا توجد تلاوات محفوظة لهذا القارئ حتى الآن', style: TextStyle(color: Colors.white60)));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: count,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final apiRow = apiRows[i];
                    final sNumInt = int.tryParse((apiRow['surah_number'] ?? (i + 1)).toString()) ?? (i + 1);
                    final sNum = sNumInt.toString().padLeft(3, '0');
                    final title = (apiRow['surah_name'] ?? apiRow['title'] ?? apiRow['name'] ?? 'سورة $sNumInt').toString();
                    var url = (apiRow['audio_url'] ?? apiRow['file_path'] ?? '').toString().trim();
                    if (url.isEmpty) url = resolveAudioUrl(reciterData, sNumInt);
                    if (url.isNotEmpty && !url.startsWith('http://') && !url.startsWith('https://')) {
                      url = 'https://quran1.kesug.com/${url.startsWith('/') ? url.substring(1) : url}';
                    }
                    final id = '${reciterKey}_$sNum';
                    return AnimatedBuilder(
                      animation: OfflineAudioManager.instance,
                      builder: (context, _) {
                        final saved = OfflineAudioManager.instance.isSaved(id);
                        final prog = OfflineAudioManager.instance.progressMap[id];
                        return ListTile(
                          tileColor: const Color(0xFF0F2B3D),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: CircleAvatar(backgroundColor: const Color(0xFFC9A959), child: Text('$sNumInt', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
                          title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(saved ? 'محفوظ بدون نت' : (apiRow['duration']?.toString().isNotEmpty == true ? apiRow['duration'].toString() : '${fallback['ayahs'] ?? ''} آية'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                          trailing: prog != null
                              ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(value: prog, strokeWidth: 2.5, color: const Color(0xFFC9A959)))
                              : IconButton(
                                  icon: Icon(saved ? Icons.download_done_rounded : Icons.download_rounded, color: saved ? const Color(0xFF10B981) : const Color(0xFFC9A959)),
                                  onPressed: url.isEmpty ? null : () => OfflineAudioManager.instance.downloadTrack(id: id, title: title, reciter: name, url: url),
                                ),
                          onTap: url.isEmpty ? null : () => onPlayAudio(id: id, title: title, reciter: name, reciterData: reciterData, url: url),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
