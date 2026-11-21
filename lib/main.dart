import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// তোমার GitHub Release-এর Base URL
const String kGithubReleaseBaseUrl =
    'https://github.com/NillBroun/HSK/releases/download/v1.0.0/';

const Color kImperialRed = Color(0xFFB71C1C);
const Color kPorcelainWhite = Color(0xFFF9F7F2);
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

class HskCourseItem {
  final String id;
  final String title;
  final String subtitle;
  final String pdfFileName;
  final String audioZipName;

  const HskCourseItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.pdfFileName,
    required this.audioZipName,
  });
}

const List<HskCourseItem> kHskCourses = [
  HskCourseItem(
    id: 'hsk1',
    title: 'HSK 1',
    subtitle: 'Lessons 1–15 • 150+ Words',
    pdfFileName: 'HSK-1-Textbook.pdf',
    audioZipName: 'hsk1-audio.zip',
  ),
  HskCourseItem(
    id: 'hsk2',
    title: 'HSK 2',
    subtitle: 'Lessons 1–15 • 300+ Words',
    pdfFileName: 'HSK-2-Textbook.pdf',
    audioZipName: 'hsk2-audio.zip',
  ),
  HskCourseItem(
    id: 'hsk3',
    title: 'HSK 3',
    subtitle: 'Lessons 1–20 • 600+ Words',
    pdfFileName: 'HSK-3-Textbook.pdf',
    audioZipName: 'hsk3-audio.zip',
  ),
  HskCourseItem(
    id: 'hsk4a',
    title: 'HSK 4 (Part A)',
    subtitle: 'Upper Textbook • 1–10',
    pdfFileName: 'HSK-4A-Textbook.pdf',
    audioZipName: 'hsk4a-audio.zip',
  ),
  HskCourseItem(
    id: 'hsk4b',
    title: 'HSK 4 (Part B)',
    subtitle: 'Lower Textbook • 11–20',
    pdfFileName: 'HSK-4B-Textbook.pdf',
    audioZipName: 'hsk4b-audio.zip',
  ),
  HskCourseItem(
    id: 'hsk5a',
    title: 'HSK 5 (Part A)',
    subtitle: 'Upper Textbook • 1–18',
    pdfFileName: 'HSK-5A-Textbook.pdf',
    audioZipName: 'hsk5a-audio.zip',
  ),
  HskCourseItem(
    id: 'hsk5b',
    title: 'HSK 5 (Part B)',
    subtitle: 'Lower Textbook • 19–36',
    pdfFileName: 'HSK-5B-Textbook.pdf',
    audioZipName: 'hsk5b-audio.zip',
  ),
  HskCourseItem(
    id: 'hsk6a',
    title: 'HSK 6 (Part A)',
    subtitle: 'Upper Textbook • 1–20',
    pdfFileName: 'HSK-6A-Textbook.pdf',
    audioZipName: 'hsk6a-audio.zip',
  ),
  HskCourseItem(
    id: 'hsk6b',
    title: 'HSK 6 (Part B)',
    subtitle: 'Lower Textbook • 21–40',
    pdfFileName: 'HSK-6B-Textbook.pdf',
    audioZipName: 'hsk6b-audio.zip',
  ),
];

// ============================================================================
// 2. PINYIN NORMALIZER & VOCAB REPOSITORY (100% OFFLINE JSON)
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
// 3. APP STATE & PREFERENCES CONTROLLER
// ============================================================================

class AppState extends ChangeNotifier {
  bool isDarkMode = false;
  bool allLessonsContinuous = false;
  int shadowingGapSeconds = 0;
  Set<String> favoriteGroupIds = {};
  Set<String> favoriteWordKeys = {};
  String lastStudiedLabel = '';
  String lastStudiedCourseId = '';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkMode = prefs.getBool('dark_mode') ?? false;
    allLessonsContinuous = prefs.getBool('all_lessons_continuous') ?? false;
    shadowingGapSeconds = prefs.getInt('shadowing_gap') ?? 0;
    favoriteGroupIds = (prefs.getStringList('fav_groups') ?? []).toSet();
    favoriteWordKeys = (prefs.getStringList('fav_words') ?? []).toSet();
    lastStudiedLabel = prefs.getString('last_studied_label') ?? '';
    lastStudiedCourseId = prefs.getString('last_studied_course') ?? '';
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

  Future<void> updateLastStudied(String courseId, String label) async {
    lastStudiedCourseId = courseId;
    lastStudiedLabel = label;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_studied_course', courseId);
    await prefs.setString('last_studied_label', label);
    notifyListeners();
  }
}

// ============================================================================
// 4. ROOT APPLICATION
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
// 5. HOME SCREEN + GLOBAL SEARCH + DRAWER MENU (☰)
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
          '汉语 HSK Study',
          style: TextStyle(fontWeight: FontWeight.bold),
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
            tooltip: 'Settings',
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
                hintText: 'শব্দ খুঁজুন (বাংলা / Pinyin / 汉字 / English)...',
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
                        _buildResumeBanner(isDark),
                      if (pinnedGroups.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8, top: 4),
                          child: Text(
                            '⭐ My Favorites',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 44,
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
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _quickCard(
                              isDark: isDark,
                              icon: Icons.edit_note_rounded,
                              title: 'My Grammar & Notes',
                              subtitle: 'নিজের নোট ও গ্রামার',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const GrammarNotesScreen(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Builder(
                              builder: (ctx) => _quickCard(
                                isDark: isDark,
                                icon: Icons.menu_book_rounded,
                                title: 'Vocabulary Bank',
                                subtitle: 'HSK • 3000 • কর্মক্ষেত্র',
                                onTap: () => Scaffold.of(ctx).openDrawer(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'HSK Standard Courses (1–6)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: kHskCourses.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.42,
                        ),
                        itemBuilder: (context, index) {
                          final course = kHskCourses[index];
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CourseDetailScreen(
                                    course: course,
                                    appState: widget.appState,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? kNightCard : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white12
                                      : const Color(0xFFE8DFD3),
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
                                        course.title,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? const Color(0xFFEF5350)
                                              : kImperialRed,
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 14,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                      ),
                                    ],
                                  ),
                                  Text(
                                    course.subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
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
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumeBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
          const Icon(Icons.history_rounded, color: kImperialRed),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Last Studied',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
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
          TextButton(
            onPressed: () {
              final course = kHskCourses.firstWhere(
                (c) => c.id == widget.appState.lastStudiedCourseId,
                orElse: () => kHskCourses.first,
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CourseDetailScreen(
                    course: course,
                    appState: widget.appState,
                  ),
                ),
              );
            },
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }

  Widget _quickCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isDark ? kNightCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFE8DFD3),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: kImperialRed, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsList() {
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('কোনো শব্দ পাওয়া যায়নি। অন্যভাবে লিখে চেষ্টা করো।'),
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
          DrawerHeader(
            decoration: const BoxDecoration(color: kImperialRed),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
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
                  'By AHM • v1.1.0',
                  style: TextStyle(color: Colors.white60, fontSize: 11.5),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.star_rounded, color: Colors.amber),
            title: const Text('My Favorites (পিন করা তালিকা)'),
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
          const Divider(),
          ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.school_rounded, color: kImperialRed),
            title: const Text(
              'HSK Vocabulary Bank (1–3)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            children: hskGroups.isEmpty
                ? [
                    const ListTile(
                      title: Text(
                        'assets/vocab/hsk1–3.json যোগ হলে এখানে দেখাবে',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  ]
                : hskGroups
                    .map((g) => ListTile(
                          dense: true,
                          title: Text(g.title),
                          subtitle: Text('${g.words.length} শব্দ'),
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
          ExpansionTile(
            leading: const Icon(Icons.auto_stories_rounded, color: kImperialRed),
            title: const Text(
              'Collins 3000 Words (১০ বিভাগ)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            children: collinsGroups.isEmpty
                ? [
                    const ListTile(
                      title: Text(
                        'assets/vocab/collins_3000.json যোগ হলে এখানে দেখাবে',
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
          ExpansionTile(
            leading: const Icon(Icons.work_rounded, color: kImperialRed),
            title: const Text(
              'Workplace & Designations (১৩ বিভাগ)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            children: deptGroups.isEmpty
                ? [
                    const ListTile(
                      title: Text(
                        'assets/vocab/departments.json যোগ হলে এখানে দেখাবে',
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
            leading: const Icon(Icons.sd_storage_rounded),
            title: const Text('Manage Offline Storage'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StorageManagerScreen()),
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
// 6. VOCABULARY LIST SCREEN (CLEAN 4-LAYER CARD + FILTER + FLASHCARD BUTTON)
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
                            ? 'Favorites থেকে সরানো হয়েছে'
                            : '⭐ Favorites-এ পিন করা হয়েছে',
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
                    hintText: 'এই তালিকায় খুঁজুন (বাংলা / Pinyin / 汉字)...',
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
                    ? const Center(child: Text('এই বিভাগে কোনো শব্দ পাওয়া যায়নি।'))
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
// 7. FLASHCARD PRACTICE + HANZI WRITING PAD (田字格)
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
                  'অসাধারণ! সব শব্দ প্র্যাকটিস শেষ!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('মোট $_masteredCount টি শব্দ সফলভাবে রিভিশন দিয়েছো।'),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _queue = List<VocabWord>.from(widget.words)..shuffle();
                      _masteredCount = 0;
                    });
                  },
                  child: const Text('আবার প্র্যাকটিস করো'),
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
                    'আঙুল দিয়ে হানজি লিখে প্র্যাকটিস করো:',
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
                    label: const Text('আবার পড়ব'),
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
                    label: const Text('পারলাম'),
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
            'হানজি লেখার পর উত্তর দেখতে কার্ডে ট্যাপ করো',
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
          'উত্তর দেখতে কার্ডে ট্যাপ করো (Tap to Flip)',
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
// 8. FAVORITES SCREEN (PINNED CATEGORIES + SAVED WORDS)
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
              title: const Text('⭐ My Favorites'),
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
                            'যেকোনো ডিপার্টমেন্ট বা লেভেল খুলে ⭐ আইকনে চাপলে এখানে সেভ হবে।'),
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
                        child: Text(
                            'যেকোনো শব্দের পাশে ⭐ আইকনে চাপলে এখানে জমে থাকবে।'),
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
// 9. COURSE DETAIL SCREEN (OFFLINE PDF & AUDIO ZIP DOWNLOAD + LESSON LIST)
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
    final pdfFile = File('${dir.path}/${widget.course.pdfFileName}');
    final audioDir = Directory('${dir.path}/audio');

    final grouped = <String, List<File>>{};
    if (await audioDir.exists()) {
      final files = audioDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.toLowerCase().endsWith('.mp3') ||
              f.path.toLowerCase().endsWith('.m4a'))
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

    if (!mounted) return;
    setState(() {
      _pdfReady = pdfFile.existsSync();
      _audioReady = grouped.isNotEmpty;
      _lessonTracks = grouped;
    });
  }

  Future<void> _downloadFile(String fileName, {required bool isZip}) async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _statusMsg = 'ডাউনলোড হচ্ছে: $fileName...';
    });

    try {
      final dir = await _courseDir();
      final url = Uri.parse('$kGithubReleaseBaseUrl$fileName');
      final req = http.Request('GET', url);
      final resp = await http.Client().send(req);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final total = resp.contentLength ?? 0;
      final bytes = <int>[];
      int received = 0;

      await for (final chunk in resp.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      }

      if (isZip) {
        setState(() => _statusMsg = 'অডিও ফাইল আনজিপ হচ্ছে...');
        final archive = ZipDecoder().decodeBytes(bytes);
        final audioDir = Directory('${dir.path}/audio');
        if (!await audioDir.exists()) await audioDir.create(recursive: true);
        for (final item in archive) {
          if (item.isFile) {
            final cleanName = item.name.split('/').last;
            if (cleanName.isEmpty) continue;
            final outFile = File('${audioDir.path}/$cleanName');
            await outFile.writeAsBytes(item.content as List<int>);
          }
        }
      } else {
        final outFile = File('${dir.path}/$fileName');
        await outFile.writeAsBytes(bytes);
      }

      await _checkLocalFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ডাউনলোড সম্পন্ন হয়েছে!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ডাউনলোড ব্যর্থ: $e')),
        );
      }
    } finally {
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
                  ? 'অফলাইনে প্রস্তুত • সুপার-ফাস্ট PDF রিডার'
                  : 'অফলাইনে পড়ার জন্য ডাউনলোড করো'),
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
                                    '${dir.path}/${widget.course.pdfFileName}',
                                appState: widget.appState,
                              ),
                            ),
                          );
                        } else {
                          _downloadFile(widget.course.pdfFileName,
                              isZip: false);
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
                  ? '${lessonNames.length}টি লেসন অফলাইনে প্রস্তুত'
                  : 'নেটিভ অডিও প্যাক (ZIP) ডাউনলোড করো'),
              trailing: _audioReady
                  ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                  : FilledButton(
                      style:
                          FilledButton.styleFrom(backgroundColor: kImperialRed),
                      onPressed: _downloading
                          ? null
                          : () => _downloadFile(widget.course.audioZipName,
                              isZip: true),
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
// 10. SUPER-FAST PDF READER (GOOGLE PDFIUM VIA PDFRX + PAGE MEMORY)
// ============================================================================

class FastPdfReaderScreen extends StatefulWidget {
  final String courseId;
  final String title;
  final String filePath;
  final AppState appState;

  const FastPdfReaderScreen({
    super.key,
    required this.courseId,
    required this.title,
    required this.filePath,
    required this.appState,
  });

  @override
  State<FastPdfReaderScreen> createState() => _FastPdfReaderScreenState();
}

class _FastPdfReaderScreenState extends State<FastPdfReaderScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  int _initialPage = 1;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPage();
  }

  Future<void> _loadSavedPage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('pdf_page_${widget.courseId}') ?? 1;
    if (!mounted) return;
    setState(() {
      _initialPage = saved;
      _currentPage = saved;
      _ready = true;
    });
  }

  Future<void> _savePage(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pdf_page_${widget.courseId}', page);
    widget.appState
        .updateLastStudied(widget.courseId, '${widget.title} • Page $page');
  }

  void _showJumpDialog() {
    final ctrl = TextEditingController(text: '$_currentPage');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('পেজে যান (Jump to Page)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '1 - $_totalPages',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(ctrl.text.trim());
              if (p != null && p >= 1 && p <= _totalPages) {
                _pdfController.goToPage(pageNumber: p);
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
  Widget build(BuildContext context) {
    final isDark = widget.appState.isDarkMode;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${widget.title} ($_currentPage/${_totalPages == 0 ? "..." : _totalPages})'),
        actions: [
          IconButton(
            tooltip: 'Jump to Page',
            icon: const Icon(Icons.find_in_page_rounded),
            onPressed: _totalPages > 0 ? _showJumpDialog : null,
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : PdfViewer.file(
              widget.filePath,
              controller: _pdfController,
              initialPageNumber: _initialPage,
              params: PdfViewerParams(
                backgroundColor: isDark ? kNightDark : const Color(0xFFEAE6DF),
                onViewerReady: (document, controller) {
                  if (mounted) {
                    setState(() => _totalPages = document.pages.length);
                  }
                },
                onPageChanged: (int? pageNumber) {
                  if (pageNumber != null && pageNumber != _currentPage) {
                    setState(() => _currentPage = pageNumber);
                    _savePage(pageNumber);
                  }
                },
              ),
            ),
    );
  }
}

// ============================================================================
// 11. AUDIO PLAYER (LESSON LOOP vs ALL LESSONS CONTINUOUS + SHADOWING GAP)
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
  double _speed = 1.0;
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
        widget.courseId,
        '${widget.courseTitle} • $_currentLessonName (Track ${_trackIndex + 1})',
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
                              ? 'All Lessons Continuous (Auto-next Lesson • Tap to switch)'
                              : 'Lesson Loop Mode (Current Lesson • Tap to switch)',
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
                          icon: const Icon(Icons.replay_5_rounded),
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
// 12. MY GRAMMAR & NOTES SCREEN
// ============================================================================

class GrammarNotesScreen extends StatefulWidget {
  const GrammarNotesScreen({super.key});

  @override
  State<GrammarNotesScreen> createState() => _GrammarNotesScreenState();
}

class _GrammarNotesScreenState extends State<GrammarNotesScreen> {
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
        title: Text(index == null ? 'নতুন নোট' : 'নোট এডিট করো'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'শিরোনাম'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bodyCtrl,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'বিস্তারিত নোট'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
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
      appBar: AppBar(title: const Text('My Grammar & Notes')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kImperialRed,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add_rounded),
      ),
      body: _notes.isEmpty
          ? const Center(
              child: Text('নিচের + বাটনে চেপে তোমার গ্রামার ও পড়াশোনার নোট রাখো।'),
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
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () {
                        setState(() => _notes.removeAt(i));
                        _saveNotes();
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
// 13. OFFLINE STORAGE MANAGER SCREEN
// ============================================================================

class StorageManagerScreen extends StatefulWidget {
  const StorageManagerScreen({super.key});

  @override
  State<StorageManagerScreen> createState() => _StorageManagerScreenState();
}

class _StorageManagerScreenState extends State<StorageManagerScreen> {
  List<Directory> _folders = [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}/hsk_offline');
    if (await root.exists()) {
      setState(() {
        _folders = root.listSync().whereType<Directory>().toList();
      });
    } else {
      setState(() => _folders = []);
    }
  }

  double _dirSizeMb(Directory dir) {
    int total = 0;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) total += entity.lengthSync();
    }
    return total / (1024 * 1024);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Offline Storage')),
      body: _folders.isEmpty
          ? const Center(child: Text('এখনও কোনো অফলাইন ফাইল ডাউনলোড করা হয়নি।'))
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: _folders.length,
              itemBuilder: (_, i) {
                final d = _folders[i];
                final name = d.uri.pathSegments
                    .where((s) => s.isNotEmpty)
                    .last
                    .toUpperCase();
                final mb = _dirSizeMb(d).toStringAsFixed(1);
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_rounded,
                        color: kImperialRed),
                    title: Text(name),
                    subtitle: Text('$mb MB ব্যবহৃত'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_forever_rounded,
                          color: Colors.red),
                      onPressed: () async {
                        await d.delete(recursive: true);
                        _scan();
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
// 14. SETTINGS & ABOUT SCREEN
// ============================================================================

class SettingsScreen extends StatelessWidget {
  final AppState appState;
  const SettingsScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings & About')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Display Theme',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SwitchListTile(
                title: const Text('Night Study Dark Mode'),
                subtitle: const Text('রাতে পড়ার জন্য চোখের আরামদায়ক ডার্ক থিম'),
                value: appState.isDarkMode,
                onChanged: appState.toggleDarkMode,
              ),
              const Divider(),
              const Text(
                'Audio Study Preferences',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SwitchListTile(
                title: const Text('All Lessons Continuous Mode (1 → 15)'),
                subtitle: Text(
                  appState.allLessonsContinuous
                      ? 'চালু: এক লেসন শেষে স্বয়ংক্রিয়ভাবে পরের লেসন বাজবে'
                      : 'বন্ধ: শুধু বর্তমান লেসনের অডিও লুপ হয়ে বাজবে',
                ),
                value: appState.allLessonsContinuous,
                onChanged: appState.setAllLessonsContinuous,
              ),
              ListTile(
                title: const Text('Shadowing Pause Gap'),
                subtitle: const Text('প্রতি ট্র্যাকের পর মুখে বলার জন্য বিরতি'),
                trailing: DropdownButton<int>(
                  value: appState.shadowingGapSeconds,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Off (0s)')),
                    DropdownMenuItem(value: 2, child: Text('2 sec')),
                    DropdownMenuItem(value: 4, child: Text('4 sec')),
                  ],
                  onChanged: (v) {
                    if (v != null) appState.setShadowingGap(v);
                  },
                ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'About HSK Study App (v1.1.0)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Created by: AHM',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Mentors: Mr. Jaman & Mr. Mahabub'),
                      SizedBox(height: 4),
                      Text('Community: Chinese Hatekhari'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse('https://www.facebook.com/ahm.79316');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.facebook_rounded),
                label: const Text('Connect with AHM on Facebook'),
              ),
            ],
          ),
        );
      },
    );
  }
}
