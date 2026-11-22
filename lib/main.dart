import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const String kGithubReleaseBaseUrl =
    'https://github.com/NillBroun/HSK/releases/download/v1.0.0/';

const Color kImperialRed = Color(0xFFB71C1C);
const Color kPorcelainWhite = Color(0xFFF9F7F2);
const Color kWarmCream = Color(0xFFF7F2E9);
const Color kNightDark = Color(0xFF121212);
const Color kNightCard = Color(0xFF1E1E1E);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HskApp());
}

// ============================================================================
// 1. DATA MODELS
// ============================================================================

class VocabWord {
  final String hanzi;
  final String pinyin;
  final String en;
  final String bn;
  final String pron;
  final String tag;
  final String groupId;
  final String groupTitle;

  const VocabWord({
    required this.hanzi,
    required this.pinyin,
    required this.en,
    required this.bn,
    required this.pron,
    required this.tag,
    required this.groupId,
    required this.groupTitle,
  });

  String get uniqueKey => '$groupId::$hanzi::$pinyin';

  factory VocabWord.fromJson(
    Map<String, dynamic> json,
    String groupId,
    String groupTitle,
  ) {
    return VocabWord(
      hanzi: (json['hanzi'] ?? '').toString(),
      pinyin: (json['pinyin'] ?? '').toString(),
      en: (json['en'] ?? '').toString(),
      bn: (json['bn'] ?? '').toString(),
      pron: (json['pron'] ?? '').toString(),
      tag: (json['tag'] ?? 'All').toString(),
      groupId: groupId,
      groupTitle: groupTitle,
    );
  }
}

class VocabGroup {
  final String id;
  final String section; // 'hsk', 'collins', 'department'
  final String title;
  final String subtitle;
  final List<VocabWord> words;

  const VocabGroup({
    required this.id,
    required this.section,
    required this.title,
    required this.subtitle,
    required this.words,
  });

  List<String> get tags {
    final set = <String>{};
    for (final w in words) {
      if (w.tag.isNotEmpty) set.add(w.tag);
    }
    return ['All', ...set];
  }
}

class UserNote {
  final String title;
  final String body;

  const UserNote({required this.title, required this.body});

  Map<String, String> toJson() => {'title': title, 'body': body};

  factory UserNote.fromJson(Map<String, dynamic> json) {
    return UserNote(
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
    );
  }
}

class ImportedPdfItem {
  final String name;
  final String path;

  const ImportedPdfItem({required this.name, required this.path});

  Map<String, String> toJson() => {'name': name, 'path': path};

  factory ImportedPdfItem.fromJson(Map<String, dynamic> json) {
    return ImportedPdfItem(
      name: (json['name'] ?? 'Document.pdf').toString(),
      path: (json['path'] ?? '').toString(),
    );
  }
}

class HskCourseItem {
  final String id;
  final String title;
  final String partLabel;
  final String subtitle;
  final List<String> pdfCandidates;
  final List<String> audioZipCandidates;

  const HskCourseItem({
    required this.id,
    required this.title,
    required this.partLabel,
    required this.subtitle,
    required this.pdfCandidates,
    required this.audioZipCandidates,
  });

  String get primaryPdfName => pdfCandidates.first;
  String get primaryZipName => audioZipCandidates.first;
}

class HskLevelCard {
  final String title;
  final String chineseBadge;
  final String subtitle;
  final List<HskCourseItem> courses;

  const HskLevelCard({
    required this.title,
    required this.chineseBadge,
    required this.subtitle,
    required this.courses,
  });
}

const List<HskLevelCard> kHskLevelCards = [
  HskLevelCard(
    title: 'HSK 1',
    chineseBadge: '一级',
    subtitle: 'Beginner',
    courses: [
      HskCourseItem(
        id: 'hsk1',
        title: 'HSK 1',
        partLabel: 'Standard Course (1–15)',
        subtitle: 'Beginner • Lessons 1–15',
        pdfCandidates: ['HSK-1-Textbook.pdf', 'hsk1.pdf'],
        audioZipCandidates: ['hsk1textbookaudios.zip', 'HSK-1-Audio.zip'],
      ),
    ],
  ),
  HskLevelCard(
    title: 'HSK 2',
    chineseBadge: '二级',
    subtitle: 'Elementary',
    courses: [
      HskCourseItem(
        id: 'hsk2',
        title: 'HSK 2',
        partLabel: 'Standard Course (1–15)',
        subtitle: 'Elementary • Lessons 1–15',
        pdfCandidates: ['HSK-2-Textbook.pdf', 'hsk2.pdf'],
        audioZipCandidates: ['hsk2textbookaudios.zip', 'HSK-2-Audio.zip'],
      ),
    ],
  ),
  HskLevelCard(
    title: 'HSK 3',
    chineseBadge: '三级',
    subtitle: 'Intermediate',
    courses: [
      HskCourseItem(
        id: 'hsk3',
        title: 'HSK 3',
        partLabel: 'Standard Course (1–20)',
        subtitle: 'Intermediate • Lessons 1–20',
        pdfCandidates: ['HSK-3-Textbook.pdf', 'hsk3.pdf'],
        audioZipCandidates: ['hsk3textbookaudios.zip', 'HSK-3-Audio.zip'],
      ),
    ],
  ),
  HskLevelCard(
    title: 'HSK 4',
    chineseBadge: '四级',
    subtitle: 'Part A & B',
    courses: [
      HskCourseItem(
        id: 'hsk4a',
        title: 'HSK 4 — Part A',
        partLabel: '上',
        subtitle: 'Upper-Intermediate (上) • Lessons 1–10',
        pdfCandidates: ['HSK-4A-Textbook.pdf', 'HSK-4-Part-A.pdf'],
        audioZipCandidates: ['hsk4Atextbookaudios.zip', 'HSK-4A-Audio.zip'],
      ),
      HskCourseItem(
        id: 'hsk4b',
        title: 'HSK 4 — Part B',
        partLabel: '下',
        subtitle: 'Upper-Intermediate (下) • Lessons 11–20',
        pdfCandidates: ['HSK-4B-Textbook.pdf', 'HSK-4-Part-B.pdf'],
        audioZipCandidates: ['hsk4Btextbookaudios.zip', 'HSK-4B-Audio.zip'],
      ),
    ],
  ),
  HskLevelCard(
    title: 'HSK 5',
    chineseBadge: '五级',
    subtitle: 'Part A & B',
    courses: [
      HskCourseItem(
        id: 'hsk5a',
        title: 'HSK 5 — Part A',
        partLabel: '上',
        subtitle: 'Advanced (上) • Lessons 1–18',
        pdfCandidates: ['HSK-5A-Textbook.pdf', 'HSK-5-Part-A.pdf'],
        audioZipCandidates: ['hsk5Atextbookaudios.zip', 'HSK-5A-Audio.zip'],
      ),
      HskCourseItem(
        id: 'hsk5b',
        title: 'HSK 5 — Part B',
        partLabel: '下',
        subtitle: 'Advanced (下) • Lessons 19–36',
        pdfCandidates: ['HSK-5B-Textbook.pdf', 'HSK-5-Part-B.pdf'],
        audioZipCandidates: ['hsk5Btextbookaudios.zip', 'HSK-5B-Audio.zip'],
      ),
    ],
  ),
  HskLevelCard(
    title: 'HSK 6',
    chineseBadge: '六级',
    subtitle: 'Part A & B',
    courses: [
      HskCourseItem(
        id: 'hsk6a',
        title: 'HSK 6 — Part A',
        partLabel: '上',
        subtitle: 'Mastery (上) • Lessons 1–20',
        pdfCandidates: ['HSK-6A-Textbook.pdf', 'HSK-6-Part-A.pdf'],
        audioZipCandidates: ['hsk6Atextbookaudios.zip', 'HSK-6A-Audio.zip'],
      ),
      HskCourseItem(
        id: 'hsk6b',
        title: 'HSK 6 — Part B',
        partLabel: '下',
        subtitle: 'Mastery (下) • Lessons 21–40',
        pdfCandidates: ['HSK-6B-Textbook.pdf', 'HSK-6-Part-B.pdf'],
        audioZipCandidates: ['hsk6Btextbookaudios.zip', 'HSK-6B-Audio.zip'],
      ),
    ],
  ),
];

List<HskCourseItem> get kAllCourses =>
    kHskLevelCards.expand((level) => level.courses).toList();

// ============================================================================
// 2. PINYIN NORMALIZER & VOCAB REPOSITORY (100% OFFLINE JSON - HSK 1-6 READY)
// ============================================================================

String stripPinyinTones(String input) {
  const map = {
    'ā': 'a', 'á': 'a', 'ǎ': 'a', 'à': 'a',
    'ē': 'e', 'é': 'e', 'ě': 'e', 'è': 'e',
    'ī': 'i', 'í': 'i', 'ǐ': 'i', 'ì': 'i',
    'ō': 'o', 'ó': 'o', 'ǒ': 'o', 'ò': 'o',
    'ū': 'u', 'ú': 'u', 'ǔ': 'u', 'ù': 'u',
    'ǖ': 'u', 'ǘ': 'u', 'ǚ': 'u', 'ǜ': 'u', 'ü': 'u',
  };
  final sb = StringBuffer();
  for (final ch in input.toLowerCase().split('')) {
    if (ch == ' ' || ch == "'" || ch == '-') continue;
    sb.write(map[ch] ?? ch);
  }
  return sb.toString();
}

class VocabRepository {
  static final VocabRepository instance = VocabRepository._();
  VocabRepository._();

  final List<VocabGroup> groups = [];
  final List<VocabWord> allWords = [];
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    groups.clear();
    allWords.clear();

    const files = [
      ('assets/vocab/hsk1.json', 'hsk'),
      ('assets/vocab/hsk2.json', 'hsk'),
      ('assets/vocab/hsk3.json', 'hsk'),
      ('assets/vocab/hsk4.json', 'hsk'),
      ('assets/vocab/hsk5.json', 'hsk'),
      ('assets/vocab/hsk6.json', 'hsk'),
      ('assets/vocab/collins_3000.json', 'collins'),
      ('assets/vocab/departments.json', 'department'),
    ];

    for (final entry in files) {
      try {
        final raw = await rootBundle.loadString(entry.$1);
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final rawGroups = (decoded['groups'] as List<dynamic>? ?? []);
        for (final g in rawGroups) {
          final gm = g as Map<String, dynamic>;
          final gid = (gm['id'] ?? '').toString();
          final gTitle = (gm['title'] ?? '').toString();
          final gSub = (gm['subtitle'] ?? '').toString();
          final rawWords = (gm['words'] as List<dynamic>? ?? []);
          final parsedWords = rawWords
              .map((w) => VocabWord.fromJson(
                    w as Map<String, dynamic>,
                    gid,
                    gTitle,
                  ))
              .toList();
          groups.add(VocabGroup(
            id: gid,
            section: entry.$2,
            title: gTitle,
            subtitle: gSub,
            words: parsedWords,
          ));
          allWords.addAll(parsedWords);
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  List<VocabGroup> bySection(String section) =>
      groups.where((g) => g.section == section).toList();

  VocabGroup? byId(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  List<VocabWord> search(String query, {List<VocabWord>? pool}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final qClean = stripPinyinTones(q);
    final source = pool ?? allWords;

    return source.where((w) {
      if (w.hanzi.contains(q)) return true;
      if (w.bn.toLowerCase().contains(q)) return true;
      if (w.pron.toLowerCase().contains(q)) return true;
      if (w.en.toLowerCase().contains(q)) return true;
      if (w.pinyin.toLowerCase().contains(q)) return true;
      if (qClean.isNotEmpty && stripPinyinTones(w.pinyin).contains(qClean)) {
        return true;
      }
      return false;
    }).toList();
  }
}

// ============================================================================
// 3. SHARED AUDIO GROUPING HELPER & CONFIRM DELETE DIALOG
// ============================================================================

Future>> scanCourseAudioTracks(String courseId) async {
  final base = await getApplicationDocumentsDirectory();
  final audioDir = Directory('${base.path}/hsk_offline/$courseId/audio');
  final grouped = <String, List<File>>{};
  if (await audioDir.exists()) {
    final files = audioDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.toLowerCase().endsWith('.mp3') ||
            f.path.toLowerCase().endsWith('.m4a') ||
            f.path.toLowerCase().endsWith('.wav'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final match = RegExp(r'(\d{2})').firstMatch(name);
      final lessonKey =
          match != null ? 'LESSON ${match.group(1)}' : 'AUDIO TRACKS';
      grouped.putIfAbsent(lessonKey, () => []).add(f);
    }
  }
  return grouped;
}

Future<bool> showConfirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ============================================================================
// 4. APP STATE & PREFERENCES CONTROLLER
// ============================================================================

class AppState extends ChangeNotifier {
  bool isDarkMode = false;
  bool allLessonsContinuous = false;
  double defaultSpeed = 1.0;
  int shadowingGapSeconds = 0;
  Set<String> favoriteGroupIds = {};
  Set<String> favoriteWordKeys = {};

  // Smart Direct Resume State
  String lastStudiedLabel = '';
  String lastStudiedCourseId = '';
  String lastStudiedType = ''; // 'pdf' or 'audio'
  int lastLessonIndex = 0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkMode = prefs.getBool('dark_mode') ?? false;
    allLessonsContinuous = prefs.getBool('all_lessons_continuous') ?? false;
    defaultSpeed = prefs.getDouble('default_speed') ?? 1.0;
    shadowingGapSeconds = prefs.getInt('shadowing_gap') ?? 0;
    favoriteGroupIds = (prefs.getStringList('fav_groups') ?? []).toSet();
    favoriteWordKeys = (prefs.getStringList('fav_words') ?? []).toSet();
    lastStudiedLabel = prefs.getString('last_studied_label') ?? '';
    lastStudiedCourseId = prefs.getString('last_studied_course') ?? '';
    lastStudiedType = prefs.getString('last_studied_type') ?? 'pdf';
    lastLessonIndex = prefs.getInt('last_lesson_index') ?? 0;
    await VocabRepository.instance.ensureLoaded();
    notifyListeners();
  }

  Future<void> toggleDarkMode(bool val) async {
    isDarkMode = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', val);
    notifyListeners();
  }

  Future<void> setAllLessonsContinuous(bool val) async {
    allLessonsContinuous = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('all_lessons_continuous', val);
    notifyListeners();
  }

  Future<void> setDefaultSpeed(double spd) async {
    defaultSpeed = spd;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('default_speed', spd);
    notifyListeners();
  }

  Future<void> setShadowingGap(int sec) async {
    shadowingGapSeconds = sec;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shadowing_gap', sec);
    notifyListeners();
  }

  Future<void> toggleFavoriteGroup(String groupId) async {
    if (favoriteGroupIds.contains(groupId)) {
      favoriteGroupIds.remove(groupId);
    } else {
      favoriteGroupIds.add(groupId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('fav_groups', favoriteGroupIds.toList());
    notifyListeners();
  }

  Future<void> toggleFavoriteWord(String wordKey) async {
    if (favoriteWordKeys.contains(wordKey)) {
      favoriteWordKeys.remove(wordKey);
    } else {
      favoriteWordKeys.add(wordKey);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('fav_words', favoriteWordKeys.toList());
    notifyListeners();
  }

  Future<void> updateLastStudied({
    required String courseId,
    required String label,
    required String type,
    int lessonIndex = 0,
  }) async {
    lastStudiedCourseId = courseId;
    lastStudiedLabel = label;
    lastStudiedType = type;
    lastLessonIndex = lessonIndex;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_studied_course', courseId);
    await prefs.setString('last_studied_label', label);
    await prefs.setString('last_studied_type', type);
    await prefs.setInt('last_lesson_index', lessonIndex);
    notifyListeners();
  }
}

// ============================================================================
// 5. ROOT APPLICATION
// ============================================================================

class HskApp extends StatefulWidget {
  const HskApp({super.key});

  @override
  State<HskApp> createState() => _HskAppState();
}

class _HskAppState extends State<HskApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        final lightTheme = ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: kPorcelainWhite,
          colorScheme: ColorScheme.fromSeed(
            seedColor: kImperialRed,
            primary: kImperialRed,
            surface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: kImperialRed,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        );

        final darkTheme = ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kNightDark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: kImperialRed,
            brightness: Brightness.dark,
            primary: const Color(0xFFEF5350),
            surface: kNightCard,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF8E0000),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        );

        return MaterialApp(
          title: 'HSK Study • AHM',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: _state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: HomeScreen(appState: _state),
        );
      },
    );
  }
}

// ============================================================================
// 6. HOME SCREEN (SMART DIRECT RESUME + 6-LEVEL GRID + CLEAN DRAWER)
// ============================================================================

class HomeScreen extends StatefulWidget {
  final AppState appState;
  const HomeScreen({super.key, required this.appState});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<VocabWord> _searchResults = [];

  void _onSearchChanged(String q) {
    setState(() {
      _searchResults = VocabRepository.instance.search(q);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openGroup(VocabGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VocabListScreen(
          group: group,
          appState: widget.appState,
        ),
      ),
    );
  }

  void _onLevelTap(HskLevelCard level) {
    if (level.courses.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CourseDetailScreen(
            course: level.courses.first,
            appState: widget.appState,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PartSelectionScreen(
            level: level,
            appState: widget.appState,
          ),
        ),
      );
    }
  }

  Future<void> _handleSmartDirectResume() async {
    final courseId = widget.appState.lastStudiedCourseId;
    final type = widget.appState.lastStudiedType;

    // 1. Personal PDF Resume
    if (courseId.startsWith('personal_')) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('imported_pdf_notes');
      if (raw != null) {
        final list = (jsonDecode(raw) as List<dynamic>)
            .map((e) => ImportedPdfItem.fromJson(e as Map<String, dynamic>))
            .toList();
        for (final item in list) {
          if ('personal_${item.name.hashCode}' == courseId &&
              File(item.path).existsSync()) {
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FastPdfReaderScreen(
                  courseId: courseId,
                  title: item.name,
                  filePath: item.path,
                  appState: widget.appState,
                ),
              ),
            );
            return;
          }
        }
      }
    }

    // 2. Standard HSK Course Resume (Direct PDF Page or Direct Audio Lesson)
    final course = kAllCourses.firstWhere(
      (c) => c.id == courseId,
      orElse: () => kAllCourses.first,
    );
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/hsk_offline/${course.id}');
    final pdfFile = File('${dir.path}/${course.primaryPdfName}');
    final tracks = await scanCourseAudioTracks(course.id);
    final lessonNames = tracks.keys.toList()..sort();

    if (!mounted) return;

    if (type == 'audio' && lessonNames.isNotEmpty) {
      final safeIdx =
          widget.appState.lastLessonIndex.clamp(0, lessonNames.length - 1);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LessonAudioPlayerScreen(
            courseId: course.id,
            courseTitle: course.title,
            allLessonNames: lessonNames,
            allLessonTracks: tracks,
            initialLessonIndex: safeIdx,
            appState: widget.appState,
          ),
        ),
      );
      return;
    }

    if (type == 'pdf' && pdfFile.existsSync()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FastPdfReaderScreen(
            courseId: course.id,
            title: course.title,
            filePath: pdfFile.path,
            lessonNames: lessonNames,
            lessonTracks: tracks,
            appState: widget.appState,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourseDetailScreen(
          course: course,
          appState: widget.appState,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.appState.isDarkMode;
    final repo = VocabRepository.instance;
    final pinnedGroups = widget.appState.favoriteGroupIds
        .map((id) => repo.byId(id))
        .whereType<VocabGroup>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '汉语 HSK',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'My Favorites',
            icon: const Icon(Icons.star_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FavoritesScreen(appState: widget.appState),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Settings & About',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(appState: widget.appState),
                ),
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: Column(
        children: [
          Container(
            color: isDark ? const Color(0xFF8E0000) : kImperialRed,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search words (English / Pinyin / Hanzi / Bangla)...',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.white60 : Colors.black45,
                ),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? kNightCard : Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _searchController.text.trim().isNotEmpty
                ? _buildSearchResultsList()
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (widget.appState.lastStudiedLabel.isNotEmpty)
                        _buildSmartResumeBanner(isDark),
                      if (pinnedGroups.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8, top: 2),
                          child: Text(
                            'Pinned Vocabulary',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 42,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: pinnedGroups.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final g = pinnedGroups[i];
                              return ActionChip(
                                avatar: const Icon(
                                  Icons.star_rounded,
                                  size: 18,
                                  color: Colors.amber,
                                ),
                                label: Text(g.title),
                                onPressed: () => _openGroup(g),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      const Text(
                        'Select HSK Level',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: kHskLevelCards.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.38,
                        ),
                        itemBuilder: (context, index) {
                          final level = kHskLevelCards[index];
                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _onLevelTap(level),
                            child: Container(
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? kNightCard
                                    : const Color(0xFFFFF7F7),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white12
                                      : const Color(0xFFEEDDDD),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        level.title,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? const Color(0xFFEF5350)
                                              : kImperialRed,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: kImperialRed
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          level.chineseBadge,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? const Color(0xFFEF5350)
                                                : kImperialRed,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    level.subtitle,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Personal Study Space',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PersonalPdfNotesScreen(
                                  appState: widget.appState),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? kNightCard
                                : const Color(0xFFFFF7F7),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white12
                                  : const Color(0xFFEEDDDD),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: kImperialRed.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: kImperialRed,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'My Grammar & Notes',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Import & read your own PDF notes from phone/SD card',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartResumeBanner(bool isDark) {
    final isAudio = widget.appState.lastStudiedType == 'audio';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _handleSmartDirectResume,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2B1919) : const Color(0xFFFFEFEF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: kImperialRed.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isAudio ? Icons.headphones_rounded : Icons.history_rounded,
                color: kImperialRed,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAudio ? 'Continue Listening' : 'Continue Reading',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.appState.lastStudiedLabel,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.play_circle_fill_rounded,
                color: kImperialRed,
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultsList() {
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('No matching words found. Try another keyword.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final w = _searchResults[index];
        return VocabCardWidget(
          word: w,
          showSourceBadge: true,
          appState: widget.appState,
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final repo = VocabRepository.instance;
    final hskGroups = repo.bySection('hsk');
    final collinsGroups = repo.bySection('collins');
    final deptGroups = repo.bySection('department');

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: kImperialRed),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '汉语 HSK Study',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'HSK 1–6 • Collins 3000 • Workplace Chinese',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                Text(
                  'Curated by AHM • v1.1.0',
                  style: TextStyle(color: Colors.white60, fontSize: 11.5),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.star_rounded, color: Colors.amber),
            title: const Text('My Favorites'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FavoritesScreen(appState: widget.appState),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_rounded, color: kImperialRed),
            title: const Text('Quick Study Notes'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const QuickNotesScreen(),
                ),
              );
            },
          ),
          const Divider(),
          // 1. HSK 1-6 Vocabulary Bank at the very top
          ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.school_rounded, color: kImperialRed),
            title: const Text(
              'HSK Vocabulary Bank (1–6)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            children: hskGroups.isEmpty
                ? [
                    const ListTile(
                      title: Text(
                        'Add hsk1–6.json to assets/vocab/',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  ]
                : hskGroups
                    .map((g) => ListTile(
                          dense: true,
                          title: Text(g.title),
                          subtitle: Text('${g.words.length} Words'),
                          trailing: widget.appState.favoriteGroupIds
                                  .contains(g.id)
                              ? const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 18)
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            _openGroup(g);
                          },
                        ))
                    .toList(),
          ),
          // 2. Collins 3000 Words below HSK Vocabulary
          ExpansionTile(
            leading: const Icon(Icons.auto_stories_rounded, color: kImperialRed),
            title: const Text(
              'Collins 3000 Words (10 Topics)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            children: collinsGroups.isEmpty
                ? [
                    const ListTile(
                      title: Text(
                        'Add collins_3000.json to assets/vocab/',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  ]
                : collinsGroups
                    .map((g) => ListTile(
                          dense: true,
                          title: Text(g.title),
                          subtitle: Text(g.subtitle),
                          trailing: widget.appState.favoriteGroupIds
                                  .contains(g.id)
                              ? const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 18)
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            _openGroup(g);
                          },
                        ))
                    .toList(),
          ),
          // 3. Workplace & Designations
          ExpansionTile(
            leading: const Icon(Icons.work_rounded, color: kImperialRed),
            title: const Text(
              'Workplace & Designations (13 Depts)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            children: deptGroups.isEmpty
                ? [
                    const ListTile(
                      title: Text(
                        'Add departments.json to assets/vocab/',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  ]
                : deptGroups
                    .map((g) => ListTile(
                          dense: true,
                          title: Text(g.title),
                          subtitle: Text(g.subtitle),
                          trailing: widget.appState.favoriteGroupIds
                                  .contains(g.id)
                              ? const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 18)
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            _openGroup(g);
                          },
                        ))
                    .toList(),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: const Text('Settings & About'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(appState: widget.appState),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 6B. PART A & PART B SELECTION SCREEN (FOR HSK 4, 5, 6)
// ============================================================================

class PartSelectionScreen extends StatelessWidget {
  final HskLevelCard level;
  final AppState appState;

  const PartSelectionScreen({
    super.key,
    required this.level,
    required this.appState,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = appState.isDarkMode;
    return Scaffold(
      appBar: AppBar(title: Text(level.title)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: level.courses.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final course = level.courses[index];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CourseDetailScreen(
                    course: course,
                    appState: appState,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? kNightCard : const Color(0xFFFFF7F7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFEEDDDD),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: kImperialRed,
                    foregroundColor: Colors.white,
                    child: Text(
                      course.partLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          course.subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// 7. VOCABULARY LIST SCREEN (4-LAYER CARD + FILTER + FLASHCARD BUTTON)
// ============================================================================

class VocabListScreen extends StatefulWidget {
  final VocabGroup group;
  final AppState appState;

  const VocabListScreen({
    super.key,
    required this.group,
    required this.appState,
  });

  @override
  State<VocabListScreen> createState() => _VocabListScreenState();
}

class _VocabListScreenState extends State<VocabListScreen> {
  String _selectedTag = 'All';
  String _localQuery = '';

  List<VocabWord> get _filteredWords {
    Iterable<VocabWord> list = widget.group.words;
    if (_selectedTag != 'All') {
      list = list.where((w) => w.tag == _selectedTag);
    }
    if (_localQuery.trim().isNotEmpty) {
      return VocabRepository.instance.search(_localQuery, pool: list.toList());
    }
    return list.toList();
  }

  @override
  Widget build(BuildContext context) {
    final words = _filteredWords;
    final tags = widget.group.tags;

    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final isPinned =
            widget.appState.favoriteGroupIds.contains(widget.group.id);
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.group.title),
            actions: [
              IconButton(
                tooltip: 'Pin to Favorites',
                icon: Icon(
                  isPinned ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isPinned ? Colors.amber : Colors.white,
                ),
                onPressed: () {
                  widget.appState.toggleFavoriteGroup(widget.group.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 1),
                      content: Text(
                        isPinned
                            ? 'Removed from Favorites'
                            : 'Pinned to Favorites',
                      ),
                    ),
                  );
                },
              ),
              if (words.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FlashcardPracticeScreen(
                          title: widget.group.title,
                          words: words,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.style_rounded, color: Colors.white),
                  label: const Text(
                    'Practice',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _localQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Filter in this list (English / Pinyin / Hanzi)...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (tags.length > 2)
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    scrollDirection: Axis.horizontal,
                    itemCount: tags.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final t = tags[i];
                      final selected = t == _selectedTag;
                      return ChoiceChip(
                        label: Text(t),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedTag = t),
                      );
                    },
                  ),
                ),
              Expanded(
                child: words.isEmpty
                    ? const Center(child: Text('No words found in this category.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: words.length,
                        itemBuilder: (_, index) => VocabCardWidget(
                          word: words[index],
                          appState: widget.appState,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class VocabCardWidget extends StatelessWidget {
  final VocabWord word;
  final AppState appState;
  final bool showSourceBadge;

  const VocabCardWidget({
    super.key,
    required this.word,
    required this.appState,
    this.showSourceBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = appState.isDarkMode;
    final isSaved = appState.favoriteWordKeys.contains(word.uniqueKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? kNightCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE8DFD3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSourceBadge)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${word.groupTitle} • ${word.tag}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ),
                Text(
                  word.hanzi,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  word.pinyin,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  word.en,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  word.pron.isNotEmpty
                      ? '${word.bn} (${word.pron})'
                      : word.bn,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Save Word',
            icon: Icon(
              isSaved ? Icons.star_rounded : Icons.star_border_rounded,
              color: isSaved ? Colors.amber : Colors.grey,
            ),
            onPressed: () => appState.toggleFavoriteWord(word.uniqueKey),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 8. FLASHCARD PRACTICE + HANZI WRITING PAD (田字格)
// ============================================================================

class FlashcardPracticeScreen extends StatefulWidget {
  final String title;
  final List<VocabWord> words;

  const FlashcardPracticeScreen({
    super.key,
    required this.title,
    required this.words,
  });

  @override
  State<FlashcardPracticeScreen> createState() =>
      _FlashcardPracticeScreenState();
}

class _FlashcardPracticeScreenState extends State<FlashcardPracticeScreen>
    with SingleTickerProviderStateMixin {
  late List<VocabWord> _queue;
  int _masteredCount = 0;
  bool _isWritingMode = false;
  bool _isFlipped = false;

  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];

  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;

  @override
  void initState() {
    super.initState();
    _queue = List<VocabWord>.from(widget.words)..shuffle();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _flipAnim = Tween<double>(begin: 0, end: math.pi).animate(
      CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    if (_isFlipped) {
      _flipCtrl.reverse();
    } else {
      _flipCtrl.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  void _nextCard({required bool gotIt}) {
    final current = _queue.removeAt(0);
    if (gotIt) {
      _masteredCount++;
    } else {
      _queue.add(current);
    }
    _flipCtrl.reset();
    setState(() {
      _isFlipped = false;
      _strokes.clear();
      _currentStroke = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Practice • ${widget.title}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_rounded,
                    size: 72, color: Colors.amber),
                const SizedBox(height: 14),
                const Text(
                  'Session Complete!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('You reviewed all $_masteredCount words.'),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _queue = List<VocabWord>.from(widget.words)..shuffle();
                      _masteredCount = 0;
                    });
                  },
                  child: const Text('Practice Again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final word = _queue.first;

    return Scaffold(
      appBar: AppBar(
        title: Text('Practice ($_masteredCount/${widget.words.length})'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.visibility_rounded),
                  label: Text('Reading Mode'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.draw_rounded),
                  label: Text('Hanzi Writing'),
                ),
              ],
              selected: {_isWritingMode},
              onSelectionChanged: (s) {
                _flipCtrl.reset();
                setState(() {
                  _isWritingMode = s.first;
                  _isFlipped = false;
                  _strokes.clear();
                });
              },
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _toggleFlip,
              child: AnimatedBuilder(
                animation: _flipAnim,
                builder: (context, _) {
                  final angle = _flipAnim.value;
                  final showBack = angle > math.pi / 2;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 200),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark ? kNightCard : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: kImperialRed.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: showBack
                          ? Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..rotateY(math.pi),
                              child: _buildCardBack(word, isDark),
                            )
                          : _buildCardFront(word),
                    ),
                  );
                },
              ),
            ),
            if (_isWritingMode) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Draw Hanzi character below:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _strokes.isEmpty
                            ? null
                            : () => setState(() => _strokes.removeLast()),
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: const Text('Undo'),
                      ),
                      TextButton.icon(
                        onPressed: _strokes.isEmpty
                            ? null
                            : () => setState(() => _strokes.clear()),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _currentStroke = [details.localPosition];
                        _strokes.add(_currentStroke);
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _currentStroke.add(details.localPosition);
                      });
                    },
                    onPanEnd: (_) => _currentStroke = [],
                    child: CustomPaint(
                      painter: _HanziPadPainter(
                        strokes: _strokes,
                        strokeColor: isDark ? Colors.white : Colors.black87,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _nextCard(gotIt: false),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Study Again'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kImperialRed,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _nextCard(gotIt: true),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Got It'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardFront(VocabWord w) {
    if (_isWritingMode) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            w.bn,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            w.en,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 18),
          const Text(
            'Write the Hanzi, then tap card to check',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          w.hanzi,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 18),
        const Text(
          'Tap card to reveal meaning',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildCardBack(VocabWord w, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          w.hanzi,
          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          w.pinyin,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFEF5350) : kImperialRed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          w.pron.isNotEmpty ? '${w.bn} (${w.pron})' : w.bn,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          w.en,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ],
    );
  }
}

class _HanziPadPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color strokeColor;

  _HanziPadPainter({required this.strokes, required this.strokeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      guidePaint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      guidePaint,
    );

    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HanziPadPainter oldDelegate) => true;
}

// ============================================================================
// 9. FAVORITES SCREEN (PINNED FOLDERS + SAVED WORDS)
// ============================================================================

class FavoritesScreen extends StatelessWidget {
  final AppState appState;
  const FavoritesScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final repo = VocabRepository.instance;
        final favGroups = appState.favoriteGroupIds
            .map((id) => repo.byId(id))
            .whereType<VocabGroup>()
            .toList();
        final favWords = repo.allWords
            .where((w) => appState.favoriteWordKeys.contains(w.uniqueKey))
            .toList();

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('My Favorites'),
              bottom: const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.amber,
                tabs: [
                  Tab(text: 'Pinned Folders'),
                  Tab(text: 'Saved Words'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                favGroups.isEmpty
                    ? const Center(
                        child: Text(
                            'Tap the star icon in any category to pin it here.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: favGroups.length,
                        itemBuilder: (_, i) {
                          final g = favGroups[i];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.star_rounded,
                                  color: Colors.amber),
                              title: Text(g.title),
                              subtitle: Text(g.subtitle),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VocabListScreen(
                                    group: g,
                                    appState: appState,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                favWords.isEmpty
                    ? const Center(
                        child:
                            Text('Tap the star icon on any word to save it here.'),
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: kImperialRed,
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FlashcardPracticeScreen(
                                        title: 'Saved Words',
                                        words: favWords,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.style_rounded),
                                label: Text(
                                    'Practice Saved Words (${favWords.length})'),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(14),
                              itemCount: favWords.length,
                              itemBuilder: (_, i) => VocabCardWidget(
                                word: favWords[i],
                                appState: appState,
                                showSourceBadge: true,
                              ),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// 10. COURSE DETAIL SCREEN (OFFLINE PDF & AUDIO ZIP + LESSON LIST)
// ============================================================================

class CourseDetailScreen extends StatefulWidget {
  final HskCourseItem course;
  final AppState appState;

  const CourseDetailScreen({
    super.key,
    required this.course,
    required this.appState,
  });

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  bool _pdfReady = false;
  bool _audioReady = false;
  bool _downloading = false;
  double _progress = 0;
  String _statusMsg = '';
  Map<String, List<File>> _lessonTracks = {};

  @override
  void initState() {
    super.initState();
    _checkLocalFiles();
  }

  Future<Directory> _courseDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/hsk_offline/${widget.course.id}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _checkLocalFiles() async {
    final dir = await _courseDir();
    final pdfFile = File('${dir.path}/${widget.course.primaryPdfName}');
    final grouped = await scanCourseAudioTracks(widget.course.id);

    if (!mounted) return;
    setState(() {
      _pdfReady = pdfFile.existsSync();
      _audioReady = grouped.isNotEmpty;
      _lessonTracks = grouped;
    });
  }

  Future<void> _downloadFromCandidates(
    List<String> fileNames, {
    required bool isZip,
  }) async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _statusMsg = 'Connecting to server...';
    });

    final client = http.Client();
    try {
      final dir = await _courseDir();
      http.StreamedResponse? validResp;
      String matchedName = fileNames.first;

      for (final candidate in fileNames) {
        final url = Uri.parse('$kGithubReleaseBaseUrl$candidate');
        final req = http.Request('GET', url);
        final resp = await client.send(req);
        if (resp.statusCode == 200) {
          validResp = resp;
          matchedName = candidate;
          break;
        }
      }

      if (validResp == null) {
        throw Exception('File not found on GitHub Release ($matchedName)');
      }

      setState(() => _statusMsg = 'Downloading $matchedName...');
      final total = validResp.contentLength ?? 0;
      final bytes = <int>[];
      int received = 0;

      await for (final chunk in validResp.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      }

      if (isZip) {
        setState(() => _statusMsg = 'Extracting audio lessons...');
        final archive = ZipDecoder().decodeBytes(bytes);
        final audioDir = Directory('${dir.path}/audio');
        if (!await audioDir.exists()) await audioDir.create(recursive: true);
        for (final item in archive) {
          if (item.isFile) {
            final cleanName = item.name.split('/').last;
            if (cleanName.isEmpty || cleanName.startsWith('.')) continue;
            final outFile = File('${audioDir.path}/$cleanName');
            await outFile.writeAsBytes(item.content as List<int>);
          }
        }
      } else {
        final outFile = File('${dir.path}/${widget.course.primaryPdfName}');
        await outFile.writeAsBytes(bytes);
      }

      await _checkLocalFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download completed!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() {
          _downloading = false;
          _statusMsg = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lessonNames = _lessonTracks.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: Text(widget.course.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_downloading) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 6),
            Text(_statusMsg, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 14),
          ],
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded,
                  color: kImperialRed, size: 32),
              title: Text('${widget.course.title} Textbook (PDF)'),
              subtitle: Text(_pdfReady
                  ? 'Ready offline • Tap to open reader'
                  : 'Download textbook for offline reading'),
              trailing: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kImperialRed),
                onPressed: _downloading
                    ? null
                    : () async {
                        if (_pdfReady) {
                          final dir = await _courseDir();
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FastPdfReaderScreen(
                                courseId: widget.course.id,
                                title: widget.course.title,
                                filePath:
                                    '${dir.path}/${widget.course.primaryPdfName}',
                                lessonNames: lessonNames,
                                lessonTracks: _lessonTracks,
                                appState: widget.appState,
                              ),
                            ),
                          );
                        } else {
                          _downloadFromCandidates(
                            widget.course.pdfCandidates,
                            isZip: false,
                          );
                        }
                      },
                child: Text(_pdfReady ? 'Open PDF' : 'Download'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.headphones_rounded,
                  color: kImperialRed, size: 32),
              title: Text('${widget.course.title} Audio Lessons'),
              subtitle: Text(_audioReady
                  ? '${lessonNames.length} Lessons ready offline'
                  : 'Download native audio pack (ZIP)'),
              trailing: _audioReady
                  ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                  : FilledButton(
                      style:
                          FilledButton.styleFrom(backgroundColor: kImperialRed),
                      onPressed: _downloading
                          ? null
                          : () => _downloadFromCandidates(
                                widget.course.audioZipCandidates,
                                isZip: true,
                              ),
                      child: const Text('Download'),
                    ),
            ),
          ),
          if (_audioReady) ...[
            const SizedBox(height: 18),
            const Text(
              'Listening Lessons',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...List.generate(lessonNames.length, (idx) {
              final lessonTitle = lessonNames[idx];
              final count = _lessonTracks[lessonTitle]?.length ?? 0;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: kImperialRed,
                    foregroundColor: Colors.white,
                    child: Text('${idx + 1}'),
                  ),
                  title: Text('${widget.course.title} • $lessonTitle'),
                  subtitle: Text('$count Tracks'),
                  trailing: const Icon(Icons.play_arrow_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LessonAudioPlayerScreen(
                          courseId: widget.course.id,
                          courseTitle: widget.course.title,
                          allLessonNames: lessonNames,
                          allLessonTracks: _lessonTracks,
                          initialLessonIndex: idx,
                          appState: widget.appState,
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// 11. EDGE-TO-EDGE FULL-WIDTH PDF READER + HEADPHONE TOGGLE + MINI AUDIO BAR
// ============================================================================

class FastPdfReaderScreen extends StatefulWidget {
  final String courseId;
  final String title;
  final String filePath;
  final List<String> lessonNames;
  final Map<String, List<File>> lessonTracks;
  final AppState appState;

  const FastPdfReaderScreen({
    super.key,
    required this.courseId,
    required this.title,
    required this.filePath,
    required this.appState,
    this.lessonNames = const [],
    this.lessonTracks = const {},
  });

  @override
  State<FastPdfReaderScreen> createState() => _FastPdfReaderScreenState();
}

class _FastPdfReaderScreenState extends State<FastPdfReaderScreen> {
  PdfControllerPinch? _pdfController;
  final AudioPlayer _miniPlayer = AudioPlayer();

  int _currentPage = 1;
  int _totalPages = 0;
  bool _ready = false;

  bool _showAudioBar = true;
  int _lessonIdx = 0;
  int _trackIdx = 0;
  bool _isPlaying = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<bool>? _playSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool get _hasAudio => widget.lessonNames.isNotEmpty;

  List<File> get _tracks =>
      _hasAudio ? (widget.lessonTracks[widget.lessonNames[_lessonIdx]] ?? []) : [];

  @override
  void initState() {
    super.initState();
    _initPdf();
    _initMiniAudio();
  }

  Future<void> _initPdf() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('pdf_page_${widget.courseId}') ?? 1;
    final docFuture = PdfDocument.openFile(widget.filePath);
    final doc = await docFuture;
    if (!mounted) return;
    setState(() {
      _totalPages = doc.pagesCount;
      final safePage = saved.clamp(1, _totalPages > 0 ? _totalPages : 1);
      _currentPage = safePage;
      _pdfController = PdfControllerPinch(
        document: docFuture,
        initialPage: safePage,
      );
      _ready = true;
    });
    _savePage(_currentPage);
  }

  void _initMiniAudio() {
    if (!_hasAudio) return;
    _posSub = _miniPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _durSub = _miniPlayer.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _dur = d);
    });
    _playSub = _miniPlayer.playingStream.listen((pl) {
      if (mounted) setState(() => _isPlaying = pl);
    });
    _stateSub = _miniPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _nextMiniTrack();
      }
    });
    _loadMiniTrack(0, autoPlay: false);
  }

  Future<void> _loadMiniTrack(int idx, {bool autoPlay = true}) async {
    if (_tracks.isEmpty) return;
    _trackIdx = idx.clamp(0, _tracks.length - 1);
    try {
      await _miniPlayer.setFilePath(_tracks[_trackIdx].path);
      await _miniPlayer.setSpeed(widget.appState.defaultSpeed);
      if (autoPlay) await _miniPlayer.play();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _nextMiniTrack() {
    if (_trackIdx + 1 < _tracks.length) {
      _loadMiniTrack(_trackIdx + 1);
    } else if (widget.appState.allLessonsContinuous &&
        widget.lessonNames.length > 1) {
      setState(() {
        _lessonIdx = (_lessonIdx + 1) % widget.lessonNames.length;
      });
      _loadMiniTrack(0);
    } else {
      _loadMiniTrack(0, autoPlay: false);
    }
  }

  Future<void> _savePage(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pdf_page_${widget.courseId}', page);
    widget.appState.updateLastStudied(
      courseId: widget.courseId,
      label: '${widget.title} • Page $page',
      type: 'pdf',
    );
  }

  void _showJumpDialog() {
    final ctrl = TextEditingController(text: '$_currentPage');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jump to Page'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Enter page (1 - $_totalPages)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kImperialRed),
            onPressed: () {
              final p = int.tryParse(ctrl.text.trim());
              if (p != null && p >= 1 && p <= _totalPages) {
                _pdfController?.jumpToPage(p);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _stateSub?.cancel();
    _miniPlayer.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.appState.isDarkMode;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} (Page $_currentPage)'),
        actions: [
          if (_hasAudio)
            IconButton(
              tooltip: _showAudioBar ? 'Hide Audio Bar' : 'Show Audio Bar',
              icon: Icon(
                _showAudioBar
                    ? Icons.headset_rounded
                    : Icons.headset_off_rounded,
              ),
              onPressed: () {
                setState(() => _showAudioBar = !_showAudioBar);
                if (!_showAudioBar && _isPlaying) {
                  _miniPlayer.pause();
                }
              },
            ),
        ],
      ),
      body: !_ready || _pdfController == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      // Edge-to-Edge Full-Width PDF View (Zero side margins)
                      Container(
                        color: isDark ? kNightDark : Colors.white,
                        child: PdfViewPinch(
                          controller: _pdfController!,
                          padding: 0,
                          onPageChanged: (page) {
                            if (page != _currentPage) {
                              setState(() => _currentPage = page);
                              _savePage(page);
                            }
                          },
                        ),
                      ),
                      // Right-side Page Indicator Pill (tap to jump)
                      Positioned(
                        right: 12,
                        top: 16,
                        child: GestureDetector(
                          onTap: _totalPages > 0 ? _showJumpDialog : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 7),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black87
                                  : Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.black12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.unfold_more_rounded,
                                    size: 14, color: kImperialRed),
                                Text(
                                  '$_currentPage',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Bottom Mini Audio Player Bar inside PDF Reader
                if (_hasAudio && _showAudioBar)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    decoration: BoxDecoration(
                      color: isDark ? kNightCard : const Color(0xFFFFF5F5),
                      border: Border(
                        top: BorderSide(
                          color: kImperialRed.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.headphones_rounded,
                                size: 16, color: kImperialRed),
                            const SizedBox(width: 6),
                            DropdownButton<int>(
                              value: _lessonIdx,
                              isDense: true,
                              underline: const SizedBox(),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : kImperialRed,
                              ),
                              items: List.generate(
                                widget.lessonNames.length,
                                (i) => DropdownMenuItem(
                                  value: i,
                                  child: Text(widget.lessonNames[i]),
                                ),
                              ),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _lessonIdx = v);
                                  _loadMiniTrack(0);
                                }
                              },
                            ),
                            const Spacer(),
                            Text(
                              'Track ${_trackIdx + 1}/${_tracks.length}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.skip_previous_rounded),
                              onPressed: _trackIdx > 0
                                  ? () => _loadMiniTrack(_trackIdx - 1)
                                  : null,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                _isPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                color: kImperialRed,
                                size: 32,
                              ),
                              onPressed: () => _isPlaying
                                  ? _miniPlayer.pause()
                                  : _miniPlayer.play(),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.skip_next_rounded),
                              onPressed: _trackIdx + 1 < _tracks.length
                                  ? () => _loadMiniTrack(_trackIdx + 1)
                                  : null,
                            ),
                            Expanded(
                              child: Slider(
                                activeColor: kImperialRed,
                                value: _pos.inMilliseconds.toDouble().clamp(
                                    0, _dur.inMilliseconds.toDouble() + 1),
                                max: _dur.inMilliseconds.toDouble() + 1,
                                onChanged: (v) => _miniPlayer
                                    .seek(Duration(milliseconds: v.toInt())),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ============================================================================
// 12. FULL AUDIO PLAYER SCREEN (LESSON LOOP vs ALL LESSONS CONTINUOUS)
// ============================================================================

class LessonAudioPlayerScreen extends StatefulWidget {
  final String courseId;
  final String courseTitle;
  final List<String> allLessonNames;
  final Map<String, List<File>> allLessonTracks;
  final int initialLessonIndex;
  final AppState appState;

  const LessonAudioPlayerScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
    required this.allLessonNames,
    required this.allLessonTracks,
    required this.initialLessonIndex,
    required this.appState,
  });

  @override
  State<LessonAudioPlayerScreen> createState() =>
      _LessonAudioPlayerScreenState();
}

class _LessonAudioPlayerScreenState extends State<LessonAudioPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();
  late int _lessonIndex;
  int _trackIndex = 0;
  late double _speed;
  bool _singleTrackLoop = false;
  bool _waitingGap = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<bool>? _playSub;
  StreamSubscription<PlayerState>? _stateSub;

  List<File> get _currentTracks =>
      widget.allLessonTracks[widget.allLessonNames[_lessonIndex]] ?? [];

  String get _currentLessonName => widget.allLessonNames[_lessonIndex];

  @override
  void initState() {
    super.initState();
    _lessonIndex = widget.initialLessonIndex;
    _speed = widget.appState.defaultSpeed;

    _posSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _playSub = _player.playingStream.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      }
    });

    _playTrack(0);
  }

  Future<void> _playTrack(int index) async {
    if (_currentTracks.isEmpty) return;
    _trackIndex = index.clamp(0, _currentTracks.length - 1);
    final file = _currentTracks[_trackIndex];
    try {
      await _player.setFilePath(file.path);
      await _player.setSpeed(_speed);
      await _player.play();
      widget.appState.updateLastStudied(
        courseId: widget.courseId,
        label: '${widget.courseTitle} • $_currentLessonName',
        type: 'audio',
        lessonIndex: _lessonIndex,
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _handleTrackCompleted() async {
    if (_waitingGap) return;
    final gap = widget.appState.shadowingGapSeconds;
    if (gap > 0) {
      _waitingGap = true;
      await Future.delayed(Duration(seconds: gap));
      _waitingGap = false;
      if (!mounted) return;
    }

    if (_singleTrackLoop) {
      await _playTrack(_trackIndex);
      return;
    }

    if (_trackIndex + 1 < _currentTracks.length) {
      await _playTrack(_trackIndex + 1);
    } else if (widget.appState.allLessonsContinuous) {
      setState(() {
        _lessonIndex = (_lessonIndex + 1) % widget.allLessonNames.length;
      });
      await _playTrack(0);
    } else {
      await _playTrack(0);
    }
  }

  void _cycleSpeed() {
    const speeds = [0.75, 1.0, 1.25];
    final nextIdx = (speeds.indexOf(_speed) + 1) % speeds.length;
    _speed = speeds[nextIdx];
    _player.setSpeed(_speed);
    setState(() {});
  }

  void _rewind3s() {
    final target = _position - const Duration(seconds: 3);
    _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.appState.isDarkMode;

    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final isAllMode = widget.appState.allLessonsContinuous;
        return Scaffold(
          appBar: AppBar(
            title: Text('${widget.courseTitle} • $_currentLessonName'),
          ),
          body: Column(
            children: [
              InkWell(
                onTap: () {
                  widget.appState.setAllLessonsContinuous(!isAllMode);
                },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: isDark
                      ? const Color(0xFF2B1919)
                      : const Color(0xFFFFEFEF),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isAllMode
                            ? Icons.playlist_play_rounded
                            : Icons.repeat_rounded,
                        size: 18,
                        color: kImperialRed,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isAllMode
                              ? 'All Lessons Continuous (1 → End • Tap to switch)'
                              : 'Lesson-by-Lesson Loop (Current Lesson • Tap to switch)',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: kImperialRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _currentTracks.length,
                  itemBuilder: (_, i) {
                    final f = _currentTracks[i];
                    final name = f.uri.pathSegments.last
                        .replaceAll('.mp3', '')
                        .replaceAll('.m4a', '');
                    final active = i == _trackIndex;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: active
                            ? (isDark
                                ? const Color(0xFF3E2723)
                                : const Color(0xFFD7CCC8))
                            : (isDark ? kNightCard : const Color(0xFFFFF5F5)),
                        borderRadius: BorderRadius.circular(14),
                        border: active
                            ? Border.all(color: kImperialRed, width: 1.5)
                            : null,
                      ),
                      child: ListTile(
                        leading: Icon(
                          active
                              ? Icons.graphic_eq_rounded
                              : Icons.music_note_rounded,
                          color: active ? kImperialRed : Colors.grey,
                        ),
                        title: Text(
                          'Track ${i + 1} ($name)',
                          style: TextStyle(
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        onTap: () => _playTrack(i),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
                decoration: BoxDecoration(
                  color: isDark ? kNightCard : Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Slider(
                      activeColor: kImperialRed,
                      value: _position.inMilliseconds
                          .toDouble()
                          .clamp(0, _duration.inMilliseconds.toDouble() + 1),
                      max: _duration.inMilliseconds.toDouble() + 1,
                      onChanged: (v) =>
                          _player.seek(Duration(milliseconds: v.toInt())),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(_position),
                              style: const TextStyle(fontSize: 12)),
                          Text(_fmt(_duration),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: _cycleSpeed,
                          child: Text(
                            '${_speed}x',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: kImperialRed,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '-3s Rewind',
                          icon: const Icon(Icons.fast_rewind_rounded),
                          onPressed: _rewind3s,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded,
                              size: 30),
                          onPressed: () {
                            if (_trackIndex > 0) {
                              _playTrack(_trackIndex - 1);
                            }
                          },
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: kImperialRed,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(14),
                          ),
                          onPressed: () =>
                              _isPlaying ? _player.pause() : _player.play(),
                          child: Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 30,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, size: 30),
                          onPressed: () {
                            if (_trackIndex + 1 < _currentTracks.length) {
                              _playTrack(_trackIndex + 1);
                            } else if (isAllMode) {
                              setState(() {
                                _lessonIndex = (_lessonIndex + 1) %
                                    widget.allLessonNames.length;
                              });
                              _playTrack(0);
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Repeat Single Track',
                          icon: Icon(
                            Icons.repeat_one_rounded,
                            color: _singleTrackLoop ? kImperialRed : Colors.grey,
                          ),
                          onPressed: () => setState(
                              () => _singleTrackLoop = !_singleTrackLoop),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// 13A. PERSONAL PDF GRAMMAR & NOTES (WITH CONFIRM DELETE)
// ============================================================================

class PersonalPdfNotesScreen extends StatefulWidget {
  final AppState appState;
  const PersonalPdfNotesScreen({super.key, required this.appState});

  @override
  State<PersonalPdfNotesScreen> createState() => _PersonalPdfNotesScreenState();
}

class _PersonalPdfNotesScreenState extends State<PersonalPdfNotesScreen> {
  final List<ImportedPdfItem> _pdfs = [];

  @override
  void initState() {
    super.initState();
    _loadPdfs();
  }

  Future<void> _loadPdfs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('imported_pdf_notes');
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      setState(() {
        _pdfs
          ..clear()
          ..addAll(list.map(
              (e) => ImportedPdfItem.fromJson(e as Map<String, dynamic>)));
      });
    }
  }

  Future<void> _savePdfs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'imported_pdf_notes',
      jsonEncode(_pdfs.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      final src = File(result.files.single.path!);
      final name = result.files.single.name;
      final base = await getApplicationDocumentsDirectory();
      final folder = Directory('${base.path}/personal_pdfs');
      if (!await folder.exists()) await folder.create(recursive: true);
      final dest =
          File('${folder.path}/${DateTime.now().millisecondsSinceEpoch}_$name');
      await src.copy(dest.path);
      setState(() {
        _pdfs.insert(0, ImportedPdfItem(name: name, path: dest.path));
      });
      await _savePdfs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Grammar & Notes')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kImperialRed,
        foregroundColor: Colors.white,
        onPressed: _pickPdf,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Import PDF'),
      ),
      body: _pdfs.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Tap "Import PDF" below to add your own grammar books or study notes from your phone/SD card.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: _pdfs.length,
              itemBuilder: (_, i) {
                final item = _pdfs[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_rounded,
                        color: kImperialRed),
                    title: Text(item.name),
                    subtitle: const Text('Tap to open in PDF reader'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FastPdfReaderScreen(
                            courseId: 'personal_${item.name.hashCode}',
                            title: item.name,
                            filePath: item.path,
                            appState: widget.appState,
                          ),
                        ),
                      );
                    },
                    trailing: IconButton(
                      tooltip: 'Delete PDF',
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.red),
                      onPressed: () async {
                        final ok = await showConfirmDeleteDialog(
                          context,
                          title: 'Delete Grammar PDF?',
                          message:
                              'Are you sure you want to delete "${item.name}"?',
                        );
                        if (!ok) return;
                        final f = File(item.path);
                        if (await f.exists()) await f.delete();
                        setState(() => _pdfs.removeAt(i));
                        await _savePdfs();
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================================
// 13B. QUICK TEXT STUDY NOTES SCREEN (WITH CONFIRM DELETE)
// ============================================================================

class QuickNotesScreen extends StatefulWidget {
  const QuickNotesScreen({super.key});

  @override
  State<QuickNotesScreen> createState() => _QuickNotesScreenState();
}

class _QuickNotesScreenState extends State<QuickNotesScreen> {
  final List<UserNote> _notes = [];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_notes_list');
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      setState(() {
        _notes
          ..clear()
          ..addAll(list
              .map((e) => UserNote.fromJson(e as Map<String, dynamic>)));
      });
    }
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_notes.map((n) => n.toJson()).toList());
    await prefs.setString('user_notes_list', encoded);
  }

  void _openEditor({int? index}) {
    final titleCtrl =
        TextEditingController(text: index != null ? _notes[index].title : '');
    final bodyCtrl =
        TextEditingController(text: index != null ? _notes[index].body : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'New Study Note' : 'Edit Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bodyCtrl,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kImperialRed),
            onPressed: () {
              final item = UserNote(
                title: titleCtrl.text.trim().isEmpty
                    ? 'Untitled Note'
                    : titleCtrl.text.trim(),
                body: bodyCtrl.text.trim(),
              );
              setState(() {
                if (index == null) {
                  _notes.insert(0, item);
                } else {
                  _notes[index] = item;
                }
              });
              _saveNotes();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Study Notes')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kImperialRed,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add_rounded),
      ),
      body: _notes.isEmpty
          ? const Center(
              child: Text('Tap + to write quick Mandarin grammar notes.'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: _notes.length,
              itemBuilder: (_, i) {
                final n = _notes[i];
                return Card(
                  child: ListTile(
                    title: Text(
                      n.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      n.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _openEditor(index: i),
                    trailing: IconButton(
                      tooltip: 'Delete Note',
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.red),
                      onPressed: () async {
                        final ok = await showConfirmDeleteDialog(
                          context,
                          title: 'Delete Study Note?',
                          message:
                              'Are you sure you want to delete "${n.title}"?',
                        );
                        if (!ok) return;
                        setState(() => _notes.removeAt(i));
                        await _saveNotes();
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================================
// 14. OFFLINE STORAGE MANAGER (SEPARATE PDF & AUDIO DELETE + CONFIRM DIALOG)
// ============================================================================

class _CourseStorageEntry {
  final HskCourseItem course;
  final File? pdfFile;
  final double pdfMb;
  final Directory? audioDir;
  final double audioMb;

  const _CourseStorageEntry({
    required this.course,
    required this.pdfFile,
    required this.pdfMb,
    required this.audioDir,
    required this.audioMb,
  });
}

class StorageManagerScreen extends StatefulWidget {
  const StorageManagerScreen({super.key});

  @override
  State<StorageManagerScreen> createState() => _StorageManagerScreenState();
}

class _StorageManagerScreenState extends State<StorageManagerScreen> {
  List<_CourseStorageEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  double _dirSizeMb(Directory dir) {
    int total = 0;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) total += entity.lengthSync();
    }
    return total / (1024 * 1024);
  }

  Future<void> _scan() async {
    final base = await getApplicationDocumentsDirectory();
    final found = <_CourseStorageEntry>[];

    for (final course in kAllCourses) {
      final courseDir = Directory('${base.path}/hsk_offline/${course.id}');
      if (!await courseDir.exists()) continue;

      final pdf = File('${courseDir.path}/${course.primaryPdfName}');
      final hasPdf = pdf.existsSync();
      final pdfMb = hasPdf ? pdf.lengthSync() / (1024 * 1024) : 0.0;

      final audioDir = Directory('${courseDir.path}/audio');
      final hasAudio =
          audioDir.existsSync() && audioDir.listSync().isNotEmpty;
      final audioMb = hasAudio ? _dirSizeMb(audioDir) : 0.0;

      if (hasPdf || hasAudio) {
        found.add(_CourseStorageEntry(
          course: course,
          pdfFile: hasPdf ? pdf : null,
          pdfMb: pdfMb,
          audioDir: hasAudio ? audioDir : null,
          audioMb: audioMb,
        ));
      }
    }

    if (!mounted) return;
    setState(() {
      _entries = found;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Offline Storage')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('No offline files downloaded yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _entries.length,
                  itemBuilder: (_, i) {
                    final item = _entries[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.course.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: kImperialRed,
                              ),
                            ),
                            const Divider(),
                            if (item.pdfFile != null)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                leading: const Icon(
                                    Icons.picture_as_pdf_rounded,
                                    color: kImperialRed),
                                title: const Text('Textbook PDF'),
                                subtitle: Text(
                                    '${item.pdfMb.toStringAsFixed(1)} MB'),
                                trailing: IconButton(
                                  tooltip: 'Delete PDF',
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: Colors.red),
                                  onPressed: () async {
                                    final ok = await showConfirmDeleteDialog(
                                      context,
                                      title: 'Delete Textbook PDF?',
                                      message:
                                          'Delete ${item.course.title} PDF (${item.pdfMb.toStringAsFixed(1)} MB)?',
                                    );
                                    if (!ok) return;
                                    await item.pdfFile!.delete();
                                    _scan();
                                  },
                                ),
                              ),
                            if (item.audioDir != null)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                leading: const Icon(Icons.headphones_rounded,
                                    color: kImperialRed),
                                title: const Text('Audio Lessons Pack'),
                                subtitle: Text(
                                    '${item.audioMb.toStringAsFixed(1)} MB'),
                                trailing: IconButton(
                                  tooltip: 'Delete Audio',
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: Colors.red),
                                  onPressed: () async {
                                    final ok = await showConfirmDeleteDialog(
                                      context,
                                      title: 'Delete Audio Pack?',
                                      message:
                                          'Delete ${item.course.title} Audio (${item.audioMb.toStringAsFixed(1)} MB)?',
                                    );
                                    if (!ok) return;
                                    await item.audioDir!
                                        .delete(recursive: true);
                                    _scan();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ============================================================================
// 15. SETTINGS & ABOUT SCREEN (WARM CREAM CARDS + FULL RED FACEBOOK BUTTONS)
// ============================================================================

class SettingsScreen extends StatefulWidget {
  final AppState appState;
  const SettingsScreen({super.key, required this.appState});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final PageController _photoController = PageController();
  int _photoIndex = 0;

  static const List<String> _groupPhotos = [
    'assets/group1.jpg',
    'assets/group2.jpg',
    'assets/group3.jpg',
  ];

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.appState.isDarkMode;

    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings & About')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Appearance',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Night Study Dark Mode'),
                subtitle: const Text(
                    'Switch between Porcelain White and Dark Theme'),
                value: widget.appState.isDarkMode,
                onChanged: widget.appState.toggleDarkMode,
              ),
              const Divider(),
              const SizedBox(height: 4),
              Text(
                'Audio Study Preferences',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Audio Playback Mode'),
                subtitle: Text(
                  widget.appState.allLessonsContinuous
                      ? 'All Lessons Continuous (1 → End)'
                      : 'Lesson-by-Lesson Loop (Current Lesson)',
                ),
                trailing: DropdownButton<bool>(
                  value: widget.appState.allLessonsContinuous,
                  items: const [
                    DropdownMenuItem(
                        value: false, child: Text('Lesson Loop')),
                    DropdownMenuItem(
                        value: true, child: Text('All Lessons')),
                  ],
                  onChanged: (v) {
                    if (v != null) widget.appState.setAllLessonsContinuous(v);
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Default Playback Speed'),
                trailing: DropdownButton<double>(
                  value: widget.appState.defaultSpeed,
                  items: const [
                    DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                    DropdownMenuItem(
                        value: 1.0, child: Text('1.0x (Normal)')),
                    DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                  ],
                  onChanged: (v) {
                    if (v != null) widget.appState.setDefaultSpeed(v);
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pause Gap Between Tracks (Shadowing)'),
                subtitle: const Text(
                    'Extra pause in audio mode to repeat aloud'),
                trailing: DropdownButton<int>(
                  value: widget.appState.shadowingGapSeconds,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('0 sec')),
                    DropdownMenuItem(value: 2, child: Text('2 sec')),
                    DropdownMenuItem(value: 4, child: Text('4 sec')),
                  ],
                  onChanged: (v) {
                    if (v != null) widget.appState.setShadowingGap(v);
                  },
                ),
              ),
              const Divider(),
              const SizedBox(height: 4),
              Text(
                'Offline Storage',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sd_storage_rounded,
                    color: kImperialRed),
                title: const Text('Manage Offline Storage'),
                subtitle: const Text(
                    'Select and delete individual HSK levels, audio packs, or PDFs'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const StorageManagerScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),
              // About HSK Card (Warm Cream Background)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? kNightCard : kWarmCream,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFE5DCCB),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About HSK',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'The first step to mastering Mandarin Chinese is tuning your ear to authentic native pronunciation, tones, and natural speech rhythm. HSK is designed as a clean, distraction-free companion for learners around the world—bringing structured HSK 1–6 textbook lessons, continuous chapter-by-chapter audio playback, and the ability to add your own personal grammar PDFs in one place.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Study at your own pace, repeat difficult dialogues effortlessly, and build real listening confidence.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Curated & Initiated by: AHM',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kImperialRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          final uri =
                              Uri.parse('https://www.facebook.com/ahm.79316');
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.facebook_rounded),
                        label: const Text('Follow AHM on Facebook'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Mentors & Learning Community Card (Warm Cream + Full Red Button)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? kNightCard : kWarmCream,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFE5DCCB),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mentors & Learning Community',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 185,
                        width: double.infinity,
                        child: PageView.builder(
                          controller: _photoController,
                          itemCount: _groupPhotos.length,
                          onPageChanged: (i) => setState(() => _photoIndex = i),
                          itemBuilder: (_, i) {
                            return Image.asset(
                              _groupPhotos[i],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.black12,
                                alignment: Alignment.center,
                                child: const Text('Chinese Hatekhari Class'),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _groupPhotos.length,
                        (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: _photoIndex == i ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _photoIndex == i
                                ? kImperialRed
                                : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Guided & Mentored by:',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Mr. Jaman & Mr. Mahabub',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Chinese Hatekhari',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Heartfelt gratitude to our respected teachers, Mr. Jaman and Mr. Mahabub, and the Chinese Hatekhari community, whose dedicated guidance, patience, and inspiration made our Mandarin learning journey possible.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kImperialRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          final uri = Uri.parse(
                              'https://www.facebook.com/chinesehatekhari');
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.facebook_rounded),
                        label: const Text('Visit Chinese Hatekhari on Facebook'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
