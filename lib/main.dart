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
  final String section; // 'hsk', 'department', 'daily_nature'
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
    final ordered = <String>[];
    final extra = <String>[];
    for (final w in words) {
      if (w.tag.isEmpty) continue;
      if (w.tag.toLowerCase().contains('extra')) {
        if (!extra.contains(w.tag)) extra.add(w.tag);
      } else {
        if (!ordered.contains(w.tag)) ordered.add(w.tag);
      }
    }
    return ['All', ...ordered, ...extra];
  }
}

class PinnedVocabSlice {
  final String pinKey; // format: groupId::tag
  final String groupId;
  final String tag;
  final String displayTitle;
  final VocabGroup group;
  final List<VocabWord> words;

  const PinnedVocabSlice({
    required this.pinKey,
    required this.groupId,
    required this.tag,
    required this.displayTitle,
    required this.group,
    required this.words,
  });
}

class HanziCourseChar {
  final String char;
  final String pinyin;
  final String bn;
  final int strokes;
  final String ruleTip;
  final List<String> steps;

  const HanziCourseChar({
    required this.char,
    required this.pinyin,
    required this.bn,
    required this.strokes,
    required this.ruleTip,
    required this.steps,
  });

  factory HanziCourseChar.fromJson(Map<String, dynamic> json) {
    return HanziCourseChar(
      char: (json['char'] ?? '一').toString(),
      pinyin: (json['pinyin'] ?? '').toString(),
      bn: (json['bn'] ?? '').toString(),
      strokes: (json['strokes'] is int)
          ? json['strokes'] as int
          : int.tryParse((json['strokes'] ?? '1').toString()) ?? 1,
      ruleTip: (json['ruleTip'] ?? '').toString(),
      steps: (json['steps'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class HanziCourseChapter {
  final String title;
  final String subtitle;
  final List<HanziCourseChar> characters;

  const HanziCourseChapter({
    required this.title,
    required this.subtitle,
    required this.characters,
  });

  factory HanziCourseChapter.fromJson(Map<String, dynamic> json) {
    final rawChars = (json['characters'] as List<dynamic>? ?? []);
    return HanziCourseChapter(
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      characters: rawChars
          .map((e) => HanziCourseChar.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
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
// 2. PINYIN NORMALIZER & VOCAB + HANZI COURSE REPOSITORY
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
  final List<HanziCourseChapter> hanziChapters = [];
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    groups.clear();
    allWords.clear();
    hanziChapters.clear();

    const files = [
      ('assets/vocab/hsk1.json', 'hsk'),
      ('assets/vocab/hsk2.json', 'hsk'),
      ('assets/vocab/hsk3.json', 'hsk'),
      ('assets/vocab/hsk4_a.json', 'hsk'),
      ('assets/vocab/hsk4_b.json', 'hsk'),
      ('assets/vocab/hsk5_a.json', 'hsk'),
      ('assets/vocab/hsk5_b.json', 'hsk'),
      ('assets/vocab/hsk6_a.json', 'hsk'),
      ('assets/vocab/hsk6_b.json', 'hsk'),
      ('assets/vocab/departments.json', 'department'),
      ('assets/vocab/daily_nature_a.json', 'daily_nature'),
      ('assets/vocab/daily_nature_b.json', 'daily_nature'),
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

    // Load 300+ HSK 1-2 Hanzi Writing Course from external JSON
    try {
      final hanziRaw =
          await rootBundle.loadString('assets/vocab/hanzi_course_300.json');
      final decoded = jsonDecode(hanziRaw) as Map<String, dynamic>;
      final rawChapters = (decoded['chapters'] as List<dynamic>? ?? []);
      for (final ch in rawChapters) {
        hanziChapters
            .add(HanziCourseChapter.fromJson(ch as Map<String, dynamic>));
      }
    } catch (_) {}

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

  PinnedVocabSlice? resolvePinnedSlice(String pinKey) {
    final parts = pinKey.split('::');
    final groupId = parts.first;
    final tag = parts.length > 1 ? parts[1] : 'All';
    final g = byId(groupId);
    if (g == null) return null;
    final words =
        tag == 'All' ? g.words : g.words.where((w) => w.tag == tag).toList();
    final title = tag == 'All' ? g.title : '${g.title} • $tag';
    return PinnedVocabSlice(
      pinKey: pinKey,
      groupId: groupId,
      tag: tag,
      displayTitle: title,
      group: g,
      words: words,
    );
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

scanCourseAudioTracks(String courseId) async {
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
  Set<String> favoriteSliceKeys = {}; // stores "groupId::tag"
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

    final rawSlices = prefs.getStringList('fav_groups') ?? [];
    favoriteSliceKeys = rawSlices
        .map((e) => e.contains('::') ? e : '$e::All')
        .toSet();
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

  String makeSliceKey(String groupId, String tag) => '$groupId::$tag';

  bool isSlicePinned(String groupId, String tag) =>
      favoriteSliceKeys.contains(makeSliceKey(groupId, tag));

  bool isAnySlicePinnedForGroup(String groupId) =>
      favoriteSliceKeys.any((k) => k.startsWith('$groupId::'));

  Future<void> toggleFavoriteSlice(String groupId, String tag) async {
    final key = makeSliceKey(groupId, tag);
    if (favoriteSliceKeys.contains(key)) {
      favoriteSliceKeys.remove(key);
    } else {
      favoriteSliceKeys.add(key);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('fav_groups', favoriteSliceKeys.toList());
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
// 6. HOME SCREEN (ONLY STAR IN APPBAR + SMART RESUME + 6-LEVEL GRID + DRAWER)
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

  void _openGroup(VocabGroup group, {String initialTag = 'All'}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VocabListScreen(
          group: group,
          appState: widget.appState,
          initialTag: initialTag,
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
            initialLessonIndex: safeIdx.toInt(),
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
    final pinnedSlices = widget.appState.favoriteSliceKeys
        .map((k) => repo.resolvePinnedSlice(k))
        .whereType<PinnedVocabSlice>()
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
                      if (pinnedSlices.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8, top: 2),
                          child: Text(
                            'Pinned Lessons & Topics',
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
                            itemCount: pinnedSlices.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final s = pinnedSlices[i];
                              return ActionChip(
                                avatar: const Icon(
                                  Icons.star_rounded,
                                  size: 18,
                                  color: Colors.amber,
                                ),
                                label: Text(s.displayTitle),
                                onPressed: () =>
                                    _openGroup(s.group, initialTag: s.tag),
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
    final deptGroups = repo.bySection('department');
    final dailyGroups = repo.bySection('daily_nature');

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
                  'Curated by AHM • v1.2.0',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
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
          // 1. HSK 1-6 Vocabulary Bank
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
                        'Add hsk1.json – hsk6_b.json to assets/vocab/',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  ]
                : hskGroups
                    .map((g) => ListTile(
                          dense: true,
                          title: Text(g.title),
                          subtitle: Text('${g.words.length} Words'),
                          trailing: widget.appState
                                  .isAnySlicePinnedForGroup(g.id)
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
          // 2. Professions & Designations
          ExpansionTile(
            leading: const Icon(Icons.work_rounded, color: kImperialRed),
            title: const Text(
              'Professions & Designations',
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
                          trailing: widget.appState
                                  .isAnySlicePinnedForGroup(g.id)
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
          // 3. Daily Life & Nature (Part A & Part B)
          ExpansionTile(
            leading: const Icon(Icons.eco_rounded, color: kImperialRed),
            title: const Text(
              'Daily Life & Nature',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            children: dailyGroups.isEmpty
                ? [
                    const ListTile(
                      title: Text(
                        'Add daily_nature_a.json & b.json to assets/vocab/',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  ]
                : dailyGroups
                    .map((g) => ListTile(
                          dense: true,
                          title: Text(g.title),
                          subtitle: Text(g.subtitle),
                          trailing: widget.appState
                                  .isAnySlicePinnedForGroup(g.id)
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
          // Hanzi Writing Course placed right above Settings & About as the final step
          ListTile(
            leading: const Icon(Icons.brush_rounded, color: kImperialRed),
            title: const Text('Hanzi Writing Course'),
            subtitle: const Text('HSK 1–2 (300 Hanzi) • Tianzige grid'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      HanziWritingCourseScreen(appState: widget.appState),
                ),
              );
            },
          ),
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
// 7. VOCABULARY LIST SCREEN (SMART LESSON/CATEGORY FAVORITE + FILTER)
// ============================================================================

class VocabListScreen extends StatefulWidget {
  final VocabGroup group;
  final AppState appState;
  final String initialTag;

  const VocabListScreen({
    super.key,
    required this.group,
    required this.appState,
    this.initialTag = 'All',
  });

  @override
  State<VocabListScreen> createState() => _VocabListScreenState();
}

class _VocabListScreenState extends State<VocabListScreen> {
  late String _selectedTag;
  String _localQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedTag = widget.group.tags.contains(widget.initialTag)
        ? widget.initialTag
        : 'All';
  }

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
            widget.appState.isSlicePinned(widget.group.id, _selectedTag);
        final pinLabel = _selectedTag == 'All'
            ? widget.group.title
            : '${widget.group.title} • $_selectedTag';

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _selectedTag == 'All'
                  ? widget.group.title
                  : '${widget.group.title} ($_selectedTag)',
            ),
            actions: [
              IconButton(
                tooltip: 'Pin "$pinLabel" to Favorites',
                icon: Icon(
                  isPinned ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isPinned ? Colors.amber : Colors.white,
                ),
                onPressed: () {
                  widget.appState
                      .toggleFavoriteSlice(widget.group.id, _selectedTag);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 1),
                      content: Text(
                        isPinned
                            ? 'Removed "$pinLabel" from Favorites'
                            : 'Pinned "$pinLabel" to Favorites',
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
                          title: pinLabel,
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
  final bool showWriteButton;

  const VocabCardWidget({
    super.key,
    required this.word,
    required this.appState,
    this.showSourceBadge = false,
    this.showWriteButton = false,
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
          Column(
            children: [
              IconButton(
                tooltip: 'Save Word',
                icon: Icon(
                  isSaved ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isSaved ? Colors.amber : Colors.grey,
                ),
                onPressed: () => appState.toggleFavoriteWord(word.uniqueKey),
              ),
              if (showWriteButton)
                IconButton(
                  tooltip: 'Write Hanzi Full-Screen',
                  icon: const Icon(Icons.brush_rounded, color: kImperialRed),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullScreenFavoriteWritingScreen(
                          word: word,
                          isDark: isDark,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 8A. FLASHCARD PRACTICE + HANZI WRITING PAD (田字格)
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
                        showDiagonalGuides: false,
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

// ============================================================================
// 8B. FAVORITES FULL-SCREEN HANZI WRITING + SMART ERROR CORRECTION
// ============================================================================

class FullScreenFavoriteWritingScreen extends StatefulWidget {
  final VocabWord word;
  final bool isDark;

  const FullScreenFavoriteWritingScreen({
    super.key,
    required this.word,
    required this.isDark,
  });

  @override
  State<FullScreenFavoriteWritingScreen> createState() =>
      _FullScreenFavoriteWritingScreenState();
}

class _FullScreenFavoriteWritingScreenState
    extends State<FullScreenFavoriteWritingScreen> {
  int _charIdx = 0;
  bool _showHintChar = true;
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  String? _feedbackText;
  bool _feedbackIsError = false;

  List<String> get _chars {
    final chars = widget.word.hanzi
        .runes
        .map((r) => String.fromCharCode(r).trim())
        .where((c) => c.isNotEmpty)
        .toList();
    return chars.isEmpty ? ['一'] : chars;
  }

  String get _targetChar => _chars[_charIdx.clamp(0, _chars.length - 1)];

  void _validateWriting() {
    if (_strokes.isEmpty) {
      HapticFeedback.vibrate();
      setState(() {
        _feedbackIsError = true;
        _feedbackText =
            'ভুল হয়েছে! আগে বর্গাকার ঘরে হানজি লিখুন, তারপর আবার চেষ্টা করো।';
      });
      return;
    }

    double minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    int totalPoints = 0;

    for (final s in _strokes) {
      for (final p in s) {
        totalPoints++;
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }

    final spanW = maxX - minX;
    final spanH = maxY - minY;
    final looksValid = totalPoints >= 10 && spanW >= 24 && spanH >= 24;

    if (!looksValid) {
      HapticFeedback.vibrate();
      setState(() {
        _feedbackIsError = true;
        _feedbackText =
            'ভুল হয়েছে! অক্ষরের আকৃতি বা দাগ ঠিক হয়নি — আবার চেষ্টা করো।';
        _strokes.clear();
        _currentStroke = [];
      });
    } else {
      HapticFeedback.lightImpact();
      setState(() {
        _feedbackIsError = false;
        _feedbackText =
            'সঠিক হয়েছে! "$_targetChar" সুন্দরভাবে লেখা হয়েছে।';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorite Hanzi Writing'),
        actions: [
          IconButton(
            tooltip: _showHintChar ? 'Hide Guide' : 'Show Guide',
            icon: Icon(
              _showHintChar
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
            ),
            onPressed: () => setState(() => _showHintChar = !_showHintChar),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: isDark ? kNightCard : const Color(0xFFFFF5F5),
            child: Row(
              children: [
                Text(
                  widget.word.hanzi,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.word.pinyin} • ${widget.word.bn}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        widget.word.en,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (_chars.length > 1)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: _charIdx > 0
                            ? () => setState(() {
                                  _charIdx--;
                                  _strokes.clear();
                                  _feedbackText = null;
                                })
                            : null,
                      ),
                      Text('${_charIdx + 1}/${_chars.length}'),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: _charIdx < _chars.length - 1
                            ? () => setState(() {
                                  _charIdx++;
                                  _strokes.clear();
                                  _feedbackText = null;
                                })
                            : null,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (_feedbackText != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: _feedbackIsError
                  ? Colors.red.shade700
                  : Colors.green.shade700,
              child: Text(
                _feedbackText!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF191919) : Colors.white,
                    border: Border.all(color: kImperialRed, width: 1.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _feedbackText = null;
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
                        watermarkChar: _showHintChar ? _targetChar : null,
                        showDiagonalGuides: true,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(() {
                            _strokes.removeLast();
                            _feedbackText = null;
                          }),
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Undo'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _strokes.isEmpty && _feedbackText == null
                      ? null
                      : () => setState(() {
                            _strokes.clear();
                            _currentStroke = [];
                            _feedbackText = null;
                          }),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Clear'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kImperialRed,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _validateWriting,
                    icon: const Icon(Icons.fact_check_rounded),
                    label: const Text('Check Writing'),
                  ),
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
// 8C. HANZI WRITING COURSE SCREEN (LOADED FROM assets/vocab/hanzi_course_300.json)
// ============================================================================

class HanziWritingCourseScreen extends StatefulWidget {
  final AppState appState;
  const HanziWritingCourseScreen({super.key, required this.appState});

  @override
  State<HanziWritingCourseScreen> createState() =>
      _HanziWritingCourseScreenState();
}

class _HanziWritingCourseScreenState extends State<HanziWritingCourseScreen> {
  int _chapterIdx = 0;
  int _charIdx = 0;
  int _activeStep = 0;
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  String? _statusMsg;
  bool _isError = false;

  List<HanziCourseChapter> get _chapters =>
      VocabRepository.instance.hanziChapters;

  HanziCourseChapter get _chapter =>
      _chapters[_chapterIdx.clamp(0, _chapters.length - 1)];

  HanziCourseChar get _char =>
      _chapter.characters[_charIdx.clamp(0, _chapter.characters.length - 1)];

  void _selectChar(int idx) {
    setState(() {
      _charIdx = idx;
      _activeStep = 0;
      _strokes.clear();
      _currentStroke = [];
      _statusMsg = null;
    });
  }

  void _checkPractice() {
    if (_strokes.isEmpty || _strokes.first.length < 8) {
      HapticFeedback.vibrate();
      setState(() {
        _isError = true;
        _statusMsg =
            'ভুল হয়েছে! বর্গাকার ঘরে দাগ টেনে প্র্যাকটিস করুন, তারপর আবার চেষ্টা করো।';
        _strokes.clear();
      });
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _isError = false;
      _statusMsg =
          'চমৎকার! "${_char.char}" (${_char.pinyin}) অনুশীলন সম্পন্ন হয়েছে।';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.appState.isDarkMode;

    if (_chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hanzi Writing Course')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Please ensure assets/vocab/hanzi_course_300.json is present.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final currentChar = _char;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Hanzi Writing (${_charIdx + 1}/${_chapter.characters.length})',
        ),
      ),
      body: Column(
        children: [
          // Chapter Selector Chips
          SizedBox(
            height: 46,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _chapters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final selected = i == _chapterIdx;
                return ChoiceChip(
                  label: Text(_chapters[i].title.split(':').first),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _chapterIdx = i;
                    _charIdx = 0;
                    _activeStep = 0;
                    _strokes.clear();
                    _statusMsg = null;
                  }),
                );
              },
            ),
          ),
          // Character Selector Strip (Easy -> Harder)
          SizedBox(
            height: 52,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: _chapter.characters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _chapter.characters[i];
                final selected = i == _charIdx;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _selectChar(i),
                  child: Container(
                    width: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? kImperialRed
                          : (isDark ? kNightCard : Colors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? kImperialRed : Colors.black12,
                      ),
                    ),
                    child: Text(
                      c.char,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: selected
                            ? Colors.white
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Top Section: Character Info + Step-by-Step Stroke Sequence
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? kNightCard : kWarmCream,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : const Color(0xFFE5DCCB),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: kImperialRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        currentChar.char,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: kImperialRed,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${currentChar.pinyin} • ${currentChar.bn}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${currentChar.strokes} Strokes • ${currentChar.ruleTip}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (currentChar.steps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: currentChar.steps.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, sIdx) {
                        final active = sIdx == _activeStep;
                        return InkWell(
                          onTap: () => setState(() => _activeStep = sIdx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: active
                                  ? kImperialRed
                                  : (isDark ? Colors.black26 : Colors.white),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: active ? kImperialRed : Colors.black26,
                              ),
                            ),
                            child: Text(
                              currentChar.steps[sIdx],
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black87),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_statusMsg != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _isError ? Colors.red.shade700 : Colors.green.shade700,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _statusMsg!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          // Bottom Square Tianzige Grid with Diagonal Dotted Lines
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF191919) : Colors.white,
                    border: Border.all(color: kImperialRed, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: GestureDetector(
                      onPanStart: (details) {
                        setState(() {
                          _statusMsg = null;
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
                          watermarkChar: currentChar.char,
                          showDiagonalGuides: true,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Bottom Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Undo',
                  icon: const Icon(Icons.undo_rounded),
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(() {
                            _strokes.removeLast();
                            _statusMsg = null;
                          }),
                ),
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(() {
                            _strokes.clear();
                            _currentStroke = [];
                            _statusMsg = null;
                          }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kImperialRed,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    onPressed: _checkPractice,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Check'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _charIdx < _chapter.characters.length - 1
                      ? () => _selectChar(_charIdx + 1)
                      : (_chapterIdx < _chapters.length - 1
                          ? () => setState(() {
                                _chapterIdx++;
                                _selectChar(0);
                              })
                          : null),
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HanziPadPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color strokeColor;
  final String? watermarkChar;
  final bool showDiagonalGuides;

  _HanziPadPainter({
    required this.strokes,
    required this.strokeColor,
    this.watermarkChar,
    this.showDiagonalGuides = true,
  });

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dashLen = 6,
    double gapLen = 5,
  }) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalLen = math.sqrt(dx * dx + dy * dy);
    if (totalLen == 0) return;
    final ux = dx / totalLen;
    final uy = dy / totalLen;
    double dist = 0;
    while (dist < totalLen) {
      final start = Offset(p1.dx + ux * dist, p1.dy + uy * dist);
      final endDist = math.min(dist + dashLen, totalLen);
      final end = Offset(p1.dx + ux * endDist, p1.dy + uy * endDist);
      canvas.drawLine(start, end, paint);
      dist += dashLen + gapLen;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.28)
      ..strokeWidth = 1.2;

    _drawDashedLine(
      canvas,
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      guidePaint,
    );
    _drawDashedLine(
      canvas,
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      guidePaint,
    );

    if (showDiagonalGuides) {
      final diagPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.20)
        ..strokeWidth = 1.1;
      _drawDashedLine(
        canvas,
        Offset.zero,
        Offset(size.width, size.height),
        diagPaint,
      );
      _drawDashedLine(
        canvas,
        Offset(size.width, 0),
        Offset(0, size.height),
        diagPaint,
      );
    }

    if (watermarkChar != null && watermarkChar!.isNotEmpty) {
      final fontSize = math.min(size.width, size.height) * 0.58;
      final tp = TextPainter(
        text: TextSpan(
          text: watermarkChar,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            color: strokeColor.withValues(alpha: 0.14),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (size.width - tp.width) / 2,
          (size.height - tp.height) / 2,
        ),
      );
    }

    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = 5.5
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
// 9. FAVORITES SCREEN (PINNED LESSONS/TOPICS + SAVED WORDS)
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
        final favSlices = appState.favoriteSliceKeys
            .map((k) => repo.resolvePinnedSlice(k))
            .whereType<PinnedVocabSlice>()
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
                  Tab(text: 'Pinned Lessons'),
                  Tab(text: 'Saved Words'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                favSlices.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Select any lesson or category chip inside a vocabulary list and tap the star icon to pin it here.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: favSlices.length,
                        itemBuilder: (_, i) {
                          final s = favSlices[i];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.star_rounded,
                                  color: Colors.amber),
                              title: Text(s.displayTitle),
                              subtitle: Text('${s.words.length} Words'),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VocabListScreen(
                                    group: s.group,
                                    appState: appState,
                                    initialTag: s.tag,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                favWords.isEmpty
                    ? const Center(
                        child: Text(
                            'Tap the star icon on any word to save it here.'),
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
                                    'Flashcard Practice (${favWords.length})'),
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
                                showWriteButton: true,
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
// 10. COURSE DETAIL SCREEN (CLEAN 2 CARDS: PDF + AUDIO LESSONS FOLDER)
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
          // 1. Textbook PDF Card
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
          // 2. Audio Lessons Folder Card (Lessons stay neatly inside!)
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_special_rounded,
                  color: kImperialRed, size: 32),
              title: Text('${widget.course.title} Audio Lessons'),
              subtitle: Text(_audioReady
                  ? '${lessonNames.length} Lessons inside • Tap to open folder'
                  : 'Download native audio pack (ZIP)'),
              onTap: _audioReady
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CourseAudioFolderScreen(
                            course: widget.course,
                            lessonNames: lessonNames,
                            lessonTracks: _lessonTracks,
                            appState: widget.appState,
                          ),
                        ),
                      );
                    }
                  : null,
              trailing: _audioReady
                  ? FilledButton.icon(
                      style:
                          FilledButton.styleFrom(backgroundColor: kImperialRed),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CourseAudioFolderScreen(
                              course: widget.course,
                              lessonNames: lessonNames,
                              lessonTracks: _lessonTracks,
                              appState: widget.appState,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.headphones_rounded, size: 18),
                      label: const Text('Open'),
                    )
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
        ],
      ),
    );
  }
}

// ============================================================================
// 10B. COURSE AUDIO LESSONS FOLDER SCREEN (INSIDE AUDIO CARD)
// ============================================================================

class CourseAudioFolderScreen extends StatelessWidget {
  final HskCourseItem course;
  final List<String> lessonNames;
  final Map<String, List<File>> lessonTracks;
  final AppState appState;

  const CourseAudioFolderScreen({
    super.key,
    required this.course,
    required this.lessonNames,
    required this.lessonTracks,
    required this.appState,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${course.title} • Audio Lessons')),
      body: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: lessonNames.length,
        itemBuilder: (context, idx) {
          final lessonTitle = lessonNames[idx];
          final count = lessonTracks[lessonTitle]?.length ?? 0;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: kImperialRed,
                foregroundColor: Colors.white,
                child: Text('${idx + 1}'),
              ),
              title: Text('${course.title} • $lessonTitle'),
              subtitle: Text('$count Tracks'),
              trailing: const Icon(Icons.play_arrow_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LessonAudioPlayerScreen(
                      courseId: course.id,
                      courseTitle: course.title,
                      allLessonNames: lessonNames,
                      allLessonTracks: lessonTracks,
                      initialLessonIndex: idx,
                      appState: appState,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// 11. PDF READER + V1.0.0 FULL AUDIO BAR + DUAL DRAG & TAP PAGE PILL
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
  double _miniSpeed = 1.0;
  bool _isPlaying = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  double _dragAccumDy = 0;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<bool>? _playSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool get _hasAudio => widget.lessonNames.isNotEmpty;

  List<File> get _tracks =>
      _hasAudio ? (widget.lessonTracks[widget.lessonNames[_lessonIdx]] ?? []) : [];

  String get _currentTrackCleanName {
    if (_tracks.isEmpty) return '';
    return _tracks[_trackIdx]
        .uri
        .pathSegments
        .last
        .replaceAll('.mp3', '')
        .replaceAll('.m4a', '');
  }

  @override
  void initState() {
    super.initState();
    _miniSpeed = widget.appState.defaultSpeed;
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
      await _miniPlayer.setSpeed(_miniSpeed);
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

  void _cycleMiniSpeed() {
    const speeds = [0.75, 1.0, 1.25];
    final next = (speeds.indexOf(_miniSpeed) + 1) % speeds.length;
    _miniSpeed = speeds[next];
    _miniPlayer.setSpeed(_miniSpeed);
    setState(() {});
  }

  void _rewindMini5s() {
    final target = _pos - const Duration(seconds: 5);
    _miniPlayer.seek(target < Duration.zero ? Duration.zero : target);
  }

  void _openTrackPickerSheet() {
    if (_tracks.isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '${widget.lessonNames[_lessonIdx]} • Select Track',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: kImperialRed,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _tracks.length,
                itemBuilder: (_, i) {
                  final name = _tracks[i]
                      .uri
                      .pathSegments
                      .last
                      .replaceAll('.mp3', '')
                      .replaceAll('.m4a', '');
                  final active = i == _trackIdx;
                  return ListTile(
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
                        color: active ? kImperialRed : null,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _loadMiniTrack(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
          autofocus: true,
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
                      // Right-side Dual Page Pill: Tap to Search + Drag Up/Down to Scroll
                      Positioned(
                        right: 12,
                        top: 16,
                        child: GestureDetector(
                          onTap: _totalPages > 0 ? _showJumpDialog : null,
                          onVerticalDragStart: (_) => _dragAccumDy = 0,
                          onVerticalDragUpdate: (details) {
                            if (_totalPages <= 1) return;
                            _dragAccumDy += details.delta.dy;
                            const stepPx = 14.0;
                            if (_dragAccumDy.abs() >= stepPx) {
                              final deltaPages = (_dragAccumDy / stepPx).truncate();
                              _dragAccumDy -= deltaPages * stepPx;
                              final target = (_currentPage + deltaPages)
                                  .clamp(1, _totalPages);
                              if (target != _currentPage) {
                                _pdfController?.jumpToPage(target);
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black87
                                  : Colors.white.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.black12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.unfold_more_rounded,
                                    size: 15, color: kImperialRed),
                                Text(
                                  '$_currentPage',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
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
                // Version 1.0.0 Full Audio Bar inside PDF Reader
                if (_hasAudio && _showAudioBar)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    decoration: BoxDecoration(
                      color: isDark ? kNightCard : const Color(0xFFFFF5F5),
                      border: Border(
                        top: BorderSide(
                          color: kImperialRed.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Row 1: Lesson Dropdown + Track Selector with Track Name
                        Row(
                          children: [
                            const Icon(Icons.menu_book_rounded,
                                size: 15, color: kImperialRed),
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
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: _openTrackPickerSheet,
                                child: Text(
                                  'Track ${_trackIdx + 1}/${_tracks.length} ($_currentTrackCleanName)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Thin Progress Slider
                        SizedBox(
                          height: 18,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2.5,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5.5),
                            ),
                            child: Slider(
                              activeColor: kImperialRed,
                              value: _pos.inMilliseconds.toDouble().clamp(
                                  0, _dur.inMilliseconds.toDouble() + 1),
                              max: _dur.inMilliseconds.toDouble() + 1,
                              onChanged: (v) => _miniPlayer
                                  .seek(Duration(milliseconds: v.toInt())),
                            ),
                          ),
                        ),
                        // Row 2: Speed (1.0x) + Rewind (-5s) + Prev + Big Red Play/Pause + Next
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(44, 32),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: _cycleMiniSpeed,
                              child: Text(
                                '${_miniSpeed}x',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: kImperialRed,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '-5s Rewind',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.replay_5_rounded),
                              onPressed: _rewindMini5s,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.skip_previous_rounded),
                              onPressed: _trackIdx > 0
                                  ? () => _loadMiniTrack(_trackIdx - 1)
                                  : null,
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => _isPlaying
                                  ? _miniPlayer.pause()
                                  : _miniPlayer.play(),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(
                                  color: kImperialRed,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.skip_next_rounded),
                              onPressed: _trackIdx + 1 < _tracks.length
                                  ? () => _loadMiniTrack(_trackIdx + 1)
                                  : null,
                            ),
                            IconButton(
                              tooltip: 'Track List',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.queue_music_rounded),
                              onPressed: _openTrackPickerSheet,
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
// 12. COMPACT FULL AUDIO PLAYER SCREEN (NO BLUR ICON + SLIM BOTTOM PLAYER)
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
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                        size: 17,
                        color: kImperialRed,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isAllMode
                              ? 'All Lessons Continuous (1 → End • Tap to switch)'
                              : 'Lesson-by-Lesson Loop (Current Lesson • Tap to switch)',
                          style: const TextStyle(
                            fontSize: 12,
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
                  padding: const EdgeInsets.all(12),
                  itemCount: _currentTracks.length,
                  itemBuilder: (_, i) {
                    final f = _currentTracks[i];
                    final rawName = f.uri.pathSegments.last
                        .replaceAll('.mp3', '')
                        .replaceAll('.m4a', '');
                    final active = i == _trackIndex;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 7),
                      decoration: BoxDecoration(
                        color: active
                            ? (isDark
                                ? const Color(0xFF3E2723)
                                : const Color(0xFFD7CCC8))
                            : (isDark ? kNightCard : const Color(0xFFFFF5F5)),
                        borderRadius: BorderRadius.circular(12),
                        border: active
                            ? Border.all(color: kImperialRed, width: 1.5)
                            : null,
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          active
                              ? Icons.graphic_eq_rounded
                              : Icons.music_note_rounded,
                          color: active ? kImperialRed : Colors.grey,
                        ),
                        title: Text(
                          'Track ${i + 1} ($rawName)',
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
              // Compact Slim Bottom Audio Bar
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                decoration: BoxDecoration(
                  color: isDark ? kNightCard : Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(_fmt(_position),
                            style: const TextStyle(fontSize: 11)),
                        Expanded(
                          child: SizedBox(
                            height: 22,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.5,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                              ),
                              child: Slider(
                                activeColor: kImperialRed,
                                value: _position.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                        0, _duration.inMilliseconds.toDouble() + 1),
                                max: _duration.inMilliseconds.toDouble() + 1,
                                onChanged: (v) => _player
                                    .seek(Duration(milliseconds: v.toInt())),
                              ),
                            ),
                          ),
                        ),
                        Text(_fmt(_duration),
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(42, 30),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: _cycleSpeed,
                          child: Text(
                            '${_speed}x',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: kImperialRed,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '-3s Rewind',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.fast_rewind_rounded, size: 22),
                          onPressed: _rewind3s,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.skip_previous_rounded,
                              size: 26),
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
                              borderRadius: BorderRadius.circular(12),
                            ),
                            minimumSize: const Size(46, 38),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ),
                          onPressed: () =>
                              _isPlaying ? _player.pause() : _player.play(),
                          child: Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 24,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.skip_next_rounded, size: 26),
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
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.repeat_one_rounded,
                            size: 22,
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
// 15. SETTINGS & ABOUT SCREEN (CLEAN + WARM CREAM CARDS + GROUP PHOTOS)
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
