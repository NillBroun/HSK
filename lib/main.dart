import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const String kGithubReleaseBaseUrl =
    'https://github.com/NillBroun/HSK/releases/download/v1.0.0/';

const Color kImperialRed = Color(0xFFB71C1C);
const Color kImperialDeepRed = Color(0xFF7F0000);
const Color kImperialGold = Color(0xFFD4AF37);
const Color kPorcelainWhite = Color(0xFFF9F7F2);
const Color kWarmCream = Color(0xFFF7F2E9);
const Color kNightDark = Color(0xFF121212);
const Color kNightCard = Color(0xFF1E1E1E);

final GlobalKey<NavigatorState> kRootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.ahm.hsk.channel.audio',
      androidNotificationChannelName: 'HSK Study Audio',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
      notificationColor: kImperialRed,
    );
  } catch (_) {}
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
  final String section;
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
  final String pinKey;
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

// --- Dialogue Models (Supports Both Legacy HSK 1 & New HSK 2 / HSK 3 Schemas) ---

class DialogueNewWord {
  final String hanzi;
  final String pinyin;
  final String pron;
  final String bn;
  final String en;

  const DialogueNewWord({
    required this.hanzi,
    required this.pinyin,
    required this.pron,
    required this.bn,
    this.en = '',
  });

  factory DialogueNewWord.fromJson(Map<String, dynamic> json) {
    return DialogueNewWord(
      hanzi: (json['hanzi'] ?? '').toString(),
      pinyin: (json['pinyin'] ?? '').toString(),
      pron: (json['pron'] ?? '').toString(),
      bn: (json['bn'] ?? '').toString(),
      en: (json['en'] ?? '').toString(),
    );
  }
}

class DialogueLine {
  final String speaker;
  final String hanzi;
  final String pinyin;
  final String pron;
  final String bn;
  final String en;
  final String wordByWord;

  const DialogueLine({
    required this.speaker,
    required this.hanzi,
    required this.pinyin,
    required this.pron,
    required this.bn,
    this.en = '',
    this.wordByWord = '',
  });

  factory DialogueLine.fromJson(Map<String, dynamic> json) {
    return DialogueLine(
      speaker: (json['speaker'] ?? '').toString(),
      hanzi: (json['hanzi'] ?? '').toString(),
      pinyin: (json['pinyin'] ?? '').toString(),
      pron: (json['pron'] ?? '').toString(),
      bn: (json['bn'] ?? '').toString(),
      en: (json['en'] ?? '').toString(),
      wordByWord: (json['wordByWord'] ?? '').toString(),
    );
  }
}

class DialogueLesson {
  final String lessonTitle;
  final List<DialogueNewWord> newWords;
  final List<DialogueLine> dialogues;

  const DialogueLesson({
    required this.lessonTitle,
    required this.newWords,
    required this.dialogues,
  });

  factory DialogueLesson.fromJson(Map<String, dynamic> json) {
    final code = (json['lessonCode'] ?? '').toString().trim();
    final rawTitle =
        (json['lessonTitle'] ?? json['title'] ?? '').toString().trim();
    final combinedTitle =
        code.isNotEmpty && rawTitle.isNotEmpty ? '$code • $rawTitle' : rawTitle;

    final rawLines =
        (json['dialogues'] ?? json['lines']) as List<dynamic>? ?? [];

    return DialogueLesson(
      lessonTitle: combinedTitle,
      newWords: (json['newWords'] as List<dynamic>? ?? [])
          .map((e) => DialogueNewWord.fromJson(e as Map<String, dynamic>))
          .toList(),
      dialogues: rawLines
          .map((e) => DialogueLine.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class DialogueChapter {
  final int chapter;
  final String title;
  final String subtitle;
  final List<DialogueLesson> lessons;

  const DialogueChapter({
    required this.chapter,
    required this.title,
    required this.subtitle,
    required this.lessons,
  });

  factory DialogueChapter.fromJson(Map<String, dynamic> json) {
    final rawSub = (json['subtitle'] ?? '').toString().trim();
    final pinyin = (json['pinyin'] ?? '').toString().trim();
    final pron = (json['pron'] ?? '').toString().trim();
    final bn = (json['bn'] ?? '').toString().trim();
    final en = (json['en'] ?? '').toString().trim();

    String computedSubtitle = rawSub;
    if (computedSubtitle.isEmpty) {
      final parts = <String>[];
      if (pinyin.isNotEmpty) {
        parts.add(pron.isNotEmpty ? '$pinyin ($pron)' : pinyin);
      }
      if (bn.isNotEmpty) parts.add(bn);
      if (en.isNotEmpty) parts.add(en);
      computedSubtitle = parts.join('\n');
    }

    return DialogueChapter(
      chapter: (json['chapter'] is int)
          ? json['chapter'] as int
          : int.tryParse((json['chapter'] ?? '1').toString()) ?? 1,
      title: (json['title'] ?? '').toString(),
      subtitle: computedSubtitle,
      lessons: (json['lessons'] as List<dynamic>? ?? [])
          .map((e) => DialogueLesson.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// --- Pinyin Chart Models ---

class PinyinToneInfo {
  final String tone;
  final String mark;
  final String example;
  final String bnMeaning;
  final String pitch;

  const PinyinToneInfo({
    required this.tone,
    required this.mark,
    required this.example,
    required this.bnMeaning,
    required this.pitch,
  });

  factory PinyinToneInfo.fromJson(Map<String, dynamic> json) {
    return PinyinToneInfo(
      tone: (json['tone'] ?? '').toString(),
      mark: (json['mark'] ?? '').toString(),
      example: (json['example'] ?? '').toString(),
      bnMeaning: (json['bnMeaning'] ?? '').toString(),
      pitch: (json['pitch'] ?? '').toString(),
    );
  }
}

class PinyinElementInfo {
  final String code;
  final String bnPron;
  final String detail;

  const PinyinElementInfo({
    required this.code,
    required this.bnPron,
    required this.detail,
  });

  factory PinyinElementInfo.fromJson(Map<String, dynamic> json) {
    return PinyinElementInfo(
      code: (json['code'] ?? '').toString(),
      bnPron: (json['bnPron'] ?? '').toString(),
      detail: (json['tip'] ?? json['example'] ?? '').toString(),
    );
  }
}

class PinyinSyllableItem {
  final String finalCode;
  final String pinyin;
  final String bnPron;

  const PinyinSyllableItem({
    required this.finalCode,
    required this.pinyin,
    required this.bnPron,
  });

  factory PinyinSyllableItem.fromJson(Map<String, dynamic> json) {
    return PinyinSyllableItem(
      finalCode: (json['final'] ?? '').toString(),
      pinyin: (json['pinyin'] ?? '').toString(),
      bnPron: (json['bnPron'] ?? '').toString(),
    );
  }
}

class PinyinCombinationGroup {
  final String initial;
  final String initialBn;
  final List<PinyinSyllableItem> syllables;

  const PinyinCombinationGroup({
    required this.initial,
    required this.initialBn,
    required this.syllables,
  });

  factory PinyinCombinationGroup.fromJson(Map<String, dynamic> json) {
    return PinyinCombinationGroup(
      initial: (json['initial'] ?? '').toString(),
      initialBn: (json['initialBn'] ?? '').toString(),
      syllables: (json['syllables'] as List<dynamic>? ?? [])
          .map((e) => PinyinSyllableItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PinyinRuleItem {
  final String title;
  final String detail;

  const PinyinRuleItem({required this.title, required this.detail});

  factory PinyinRuleItem.fromJson(Map<String, dynamic> json) {
    return PinyinRuleItem(
      title: (json['title'] ?? '').toString(),
      detail: (json['detail'] ?? '').toString(),
    );
  }
}

class PinyinChartData {
  final String title;
  final String subtitle;
  final List<PinyinToneInfo> tones;
  final List<PinyinElementInfo> initials;
  final List<PinyinElementInfo> finals;
  final List<PinyinCombinationGroup> combinations;
  final List<PinyinRuleItem> rules;

  const PinyinChartData({
    required this.title,
    required this.subtitle,
    required this.tones,
    required this.initials,
    required this.finals,
    required this.combinations,
    required this.rules,
  });

  factory PinyinChartData.fromJson(Map<String, dynamic> json) {
    return PinyinChartData(
      title: (json['title'] ?? 'Pinyin Chart').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      tones: (json['tones'] as List<dynamic>? ?? [])
          .map((e) => PinyinToneInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      initials: (json['initials'] as List<dynamic>? ?? [])
          .map((e) => PinyinElementInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      finals: (json['finals'] as List<dynamic>? ?? [])
          .map((e) => PinyinElementInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      combinations: (json['combinations'] as List<dynamic>? ?? [])
          .map(
              (e) => PinyinCombinationGroup.fromJson(e as Map<String, dynamic>))
          .toList(),
      rules: (json['rules'] as List<dynamic>? ?? [])
          .map((e) => PinyinRuleItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// --- Hanzi Course Models ---

class HanziCourseChar {
  final String char;
  final String pinyin;
  final String pron;
  final String bn;
  final int strokes;
  final String ruleTip;
  final List<String> steps;

  const HanziCourseChar({
    required this.char,
    required this.pinyin,
    required this.pron,
    required this.bn,
    required this.strokes,
    required this.ruleTip,
    required this.steps,
  });

  factory HanziCourseChar.fromJson(Map<String, dynamic> json) {
    return HanziCourseChar(
      char: (json['char'] ?? '一').toString(),
      pinyin: (json['pinyin'] ?? '').toString(),
      pron: (json['pron'] ?? '').toString(),
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

class DownloadTaskStatus {
  final bool isDownloading;
  final double progress;
  final String statusText;

  const DownloadTaskStatus({
    this.isDownloading = false,
    this.progress = 0.0,
    this.statusText = '',
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
// 2. PINYIN NORMALIZER & UNIFIED REPOSITORY
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
  final List<DialogueChapter> hsk1DialogueChapters = [];
  final List<DialogueChapter> hsk2DialogueChapters = [];
  final List<DialogueChapter> hsk3DialogueChapters = [];
  PinyinChartData? pinyinChart;
  bool _loaded = false;

  Future<List<DialogueChapter>> _loadDialogueAsset(String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      List<dynamic> rawChapters = [];
      if (decoded is List<dynamic>) {
        rawChapters = decoded;
      } else if (decoded is Map<String, dynamic>) {
        rawChapters = (decoded['chapters'] as List<dynamic>? ?? []);
      }
      return rawChapters
          .map((ch) => DialogueChapter.fromJson(ch as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    groups.clear();
    allWords.clear();
    hanziChapters.clear();
    hsk1DialogueChapters.clear();
    hsk2DialogueChapters.clear();
    hsk3DialogueChapters.clear();

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

    hsk1DialogueChapters
        .addAll(await _loadDialogueAsset('assets/vocab/hsk1_dialogues.json'));
    hsk2DialogueChapters
        .addAll(await _loadDialogueAsset('assets/vocab/hsk2_dialogues.json'));
    hsk3DialogueChapters
        .addAll(await _loadDialogueAsset('assets/vocab/hsk3_dialogues.json'));

    for (final path in [
      'assets/vocab/pinin-chart.json',
      'assets/vocab/pinyin_chart.json',
    ]) {
      try {
        final pRaw = await rootBundle.loadString(path);
        final decoded = jsonDecode(pRaw) as Map<String, dynamic>;
        pinyinChart = PinyinChartData.fromJson(decoded);
        break;
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
// 4. GLOBAL BACKGROUND AUDIO SERVICE (LOCK-SCREEN & FULL PERSISTENT PLAYER)
// ============================================================================

class GlobalAudioService extends ChangeNotifier {
  static final GlobalAudioService instance = GlobalAudioService._();
  GlobalAudioService._() {
    _init();
  }

  final AudioPlayer player = AudioPlayer();

  String courseId = '';
  String courseTitle = '';
  List<String> allLessonNames = [];
  Map<String, List<File>> allLessonTracks = {};
  int lessonIndex = 0;
  int trackIndex = 0;

  double speed = 1.0;
  bool singleTrackLoop = false;
  bool allLessonsContinuous = false;
  int shadowingGapSeconds = 0;
  bool _waitingGap = false;

  /// Automatically hides global persistent player when PDF reader or full audio player is open
  bool hideGlobalMiniPlayer = false;

  /// Explicitly dismissed by user via Close (×) button on global player
  bool isMiniPlayerDismissed = false;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;

  void Function({
    required String courseId,
    required String label,
    required String type,
    int lessonIndex,
  })? onTrackPlayedCallback;

  List<File> get currentTracks {
    if (allLessonNames.isEmpty) return [];
    final safeIdx = lessonIndex.clamp(0, allLessonNames.length - 1);
    return allLessonTracks[allLessonNames[safeIdx]] ?? [];
  }

  String get currentLessonName {
    if (allLessonNames.isEmpty) return '';
    return allLessonNames[lessonIndex.clamp(0, allLessonNames.length - 1)];
  }

  String get currentTrackCleanName {
    final list = currentTracks;
    if (list.isEmpty) return '';
    final idx = trackIndex.clamp(0, list.length - 1);
    return list[idx]
        .uri
        .pathSegments
        .last
        .replaceAll('.mp3', '')
        .replaceAll('.m4a', '')
        .replaceAll('.wav', '');
  }

  bool get hasLoadedLesson => currentTracks.isNotEmpty;

  bool get shouldShowGlobalMiniPlayer =>
      hasLoadedLesson && !hideGlobalMiniPlayer && !isMiniPlayerDismissed;

  void setHideGlobalMiniPlayer(bool hide) {
    if (hideGlobalMiniPlayer == hide) return;
    hideGlobalMiniPlayer = hide;
    notifyListeners();
  }

  Future<void> dismissAndStopMiniPlayer() async {
    isMiniPlayerDismissed = true;
    await player.stop();
    isPlaying = false;
    position = Duration.zero;
    notifyListeners();
  }

  Future<void> _init() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}

    player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });

    player.durationStream.listen((d) {
      if (d != null) {
        duration = d;
        notifyListeners();
      }
    });

    player.playingStream.listen((playing) {
      isPlaying = playing;
      if (playing) {
        isMiniPlayerDismissed = false;
      }
      notifyListeners();
    });

    player.currentIndexStream.listen((idx) {
      if (idx != null && idx != trackIndex && idx < currentTracks.length) {
        trackIndex = idx;
        _notifyProgressSaved();
        notifyListeners();
      }
    });

    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handlePlaylistCompleted();
      }
    });
  }

  Future<void> loadLessonAndPlay({
    required String courseId,
    required String courseTitle,
    required List<String> allLessonNames,
    required Map<String, List<File>> allLessonTracks,
    required int lessonIndex,
    int initialTrackIndex = 0,
    bool autoPlay = true,
  }) async {
    this.courseId = courseId;
    this.courseTitle = courseTitle;
    this.allLessonNames = allLessonNames;
    this.allLessonTracks = allLessonTracks;
    this.lessonIndex = lessonIndex.clamp(0, allLessonNames.length - 1);
    trackIndex = initialTrackIndex;
    isMiniPlayerDismissed = false;

    final tracks = currentTracks;
    if (tracks.isEmpty) return;

    final sources = <AudioSource>[];
    for (int i = 0; i < tracks.length; i++) {
      final f = tracks[i];
      final clean = f.uri.pathSegments.last
          .replaceAll('.mp3', '')
          .replaceAll('.m4a', '');
      sources.add(
        AudioSource.uri(
          Uri.file(f.path),
          tag: MediaItem(
            id: '${courseId}_${currentLessonName}_$i',
            album: '$courseTitle • $currentLessonName',
            title: 'Track ${i + 1} ($clean)',
            artist: 'HSK Study • AHM',
            playable: true,
          ),
        ),
      );
    }

    try {
      final playlist = ConcatenatingAudioSource(children: sources);
      await player.setAudioSource(
        playlist,
        initialIndex: trackIndex.clamp(0, tracks.length - 1),
      );
      await player.setLoopMode(
        singleTrackLoop ? LoopMode.one : LoopMode.off,
      );
      await player.setSpeed(speed);
      if (autoPlay) {
        await player.play();
        _notifyProgressSaved();
      }
      notifyListeners();
    } catch (_) {}
  }

  void _notifyProgressSaved() {
    onTrackPlayedCallback?.call(
      courseId: courseId,
      label: '$courseTitle • $currentLessonName',
      type: 'audio',
      lessonIndex: lessonIndex,
    );
  }

  Future<void> _handlePlaylistCompleted() async {
    if (_waitingGap) return;
    if (shadowingGapSeconds > 0) {
      _waitingGap = true;
      await Future.delayed(Duration(seconds: shadowingGapSeconds));
      _waitingGap = false;
    }

    if (allLessonsContinuous && allLessonNames.length > 1) {
      final nextLesson = (lessonIndex + 1) % allLessonNames.length;
      await loadLessonAndPlay(
        courseId: courseId,
        courseTitle: courseTitle,
        allLessonNames: allLessonNames,
        allLessonTracks: allLessonTracks,
        lessonIndex: nextLesson,
        initialTrackIndex: 0,
        autoPlay: true,
      );
    } else {
      await player.seek(Duration.zero, index: 0);
      await player.play();
    }
  }

  Future<void> playTrackAt(int idx) async {
    if (currentTracks.isEmpty) return;
    final safe = idx.clamp(0, currentTracks.length - 1);
    trackIndex = safe;
    isMiniPlayerDismissed = false;
    await player.seek(Duration.zero, index: safe);
    await player.play();
    _notifyProgressSaved();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await player.pause();
    } else {
      isMiniPlayerDismissed = false;
      await player.play();
    }
    notifyListeners();
  }

  Future<void> nextTrack() async {
    if (player.hasNext) {
      await player.seekToNext();
      await player.play();
    } else if (allLessonsContinuous && allLessonNames.length > 1) {
      final nextLesson = (lessonIndex + 1) % allLessonNames.length;
      await loadLessonAndPlay(
        courseId: courseId,
        courseTitle: courseTitle,
        allLessonNames: allLessonNames,
        allLessonTracks: allLessonTracks,
        lessonIndex: nextLesson,
      );
    }
  }

  Future<void> previousTrack() async {
    if (player.hasPrevious) {
      await player.seekToPrevious();
      await player.play();
    } else {
      await player.seek(Duration.zero);
    }
  }

  Future<void> rewindSeconds(int sec) async {
    final target = position - Duration(seconds: sec);
    await player.seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> cycleSpeed() async {
    const speeds = [0.75, 1.0, 1.25];
    final nextIdx = (speeds.indexOf(speed) + 1) % speeds.length;
    speed = speeds[nextIdx];
    await player.setSpeed(speed);
    notifyListeners();
  }

  Future<void> toggleSingleTrackLoop() async {
    singleTrackLoop = !singleTrackLoop;
    await player.setLoopMode(singleTrackLoop ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }
}

// ============================================================================
// 5. APP STATE, PREFERENCES & GLOBAL PARALLEL BACKGROUND DOWNLOAD MANAGER
// ============================================================================

class AppState extends ChangeNotifier {
  bool isDarkMode = false;
  bool allLessonsContinuous = false;
  double defaultSpeed = 1.0;
  int shadowingGapSeconds = 0;
  Set<String> favoriteSliceKeys = {};
  Set<String> favoriteWordKeys = {};

  String lastStudiedLabel = '';
  String lastStudiedCourseId = '';
  String lastStudiedType = '';
  int lastLessonIndex = 0;

  final Map<String, DownloadTaskStatus> activeDownloads = {};
  final Map<String, String> downloadErrors = {};
  int offlineVersionCounter = 0;

  DownloadTaskStatus getTaskStatus(String courseId, {required bool isZip}) {
    final key = '${courseId}_${isZip ? 'audio' : 'pdf'}';
    return activeDownloads[key] ?? const DownloadTaskStatus();
  }

  Future<void> startBackgroundDownload({
    required HskCourseItem course,
    required bool isZip,
  }) async {
    final key = '${course.id}_${isZip ? 'audio' : 'pdf'}';
    if (activeDownloads[key]?.isDownloading == true) return;

    downloadErrors.remove(key);
    activeDownloads[key] = const DownloadTaskStatus(
      isDownloading: true,
      progress: 0.0,
      statusText: 'Connecting to server...',
    );
    notifyListeners();

    final client = http.Client();
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/hsk_offline/${course.id}');
      if (!await dir.exists()) await dir.create(recursive: true);

      final candidates =
          isZip ? course.audioZipCandidates : course.pdfCandidates;
      http.StreamedResponse? validResp;
      String matchedName = candidates.first;

      for (final candidate in candidates) {
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
        throw Exception('File not found on release ($matchedName)');
      }

      final total = validResp.contentLength ?? 0;
      final bytes = <int>[];
      int received = 0;
      int lastNotifyMs = 0;

      await for (final chunk in validResp.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotifyMs > 180) {
          lastNotifyMs = now;
          final pct = total > 0 ? (received / total) : 0.0;
          final pctLabel =
              total > 0 ? ' (${(pct * 100).toStringAsFixed(0)}%)' : '';
          activeDownloads[key] = DownloadTaskStatus(
            isDownloading: true,
            progress: pct,
            statusText: 'Downloading $matchedName$pctLabel...',
          );
          notifyListeners();
        }
      }

      if (isZip) {
        activeDownloads[key] = const DownloadTaskStatus(
          isDownloading: true,
          progress: 0.98,
          statusText: 'Extracting audio lessons...',
        );
        notifyListeners();

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
        final outFile = File('${dir.path}/${course.primaryPdfName}');
        await outFile.writeAsBytes(bytes);
      }

      activeDownloads.remove(key);
      offlineVersionCounter++;
      notifyListeners();
    } catch (e) {
      activeDownloads.remove(key);
      downloadErrors[key] = e.toString();
      notifyListeners();
    } finally {
      client.close();
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkMode = prefs.getBool('dark_mode') ?? false;
    allLessonsContinuous = prefs.getBool('all_lessons_continuous') ?? false;
    defaultSpeed = prefs.getDouble('default_speed') ?? 1.0;
    shadowingGapSeconds = prefs.getInt('shadowing_gap') ?? 0;

    final audioSvc = GlobalAudioService.instance;
    audioSvc.allLessonsContinuous = allLessonsContinuous;
    audioSvc.speed = defaultSpeed;
    audioSvc.shadowingGapSeconds = shadowingGapSeconds;
    audioSvc.onTrackPlayedCallback = updateLastStudied;

    final rawSlices = prefs.getStringList('fav_groups') ?? [];
    favoriteSliceKeys =
        rawSlices.map((e) => e.contains('::') ? e : '$e::All').toSet();
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
    GlobalAudioService.instance.allLessonsContinuous = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('all_lessons_continuous', val);
    notifyListeners();
  }

  Future<void> setDefaultSpeed(double spd) async {
    defaultSpeed = spd;
    GlobalAudioService.instance.speed = spd;
    await GlobalAudioService.instance.player.setSpeed(spd);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('default_speed', spd);
    notifyListeners();
  }

  Future<void> setShadowingGap(int sec) async {
    shadowingGapSeconds = sec;
    GlobalAudioService.instance.shadowingGapSeconds = sec;
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
// 6. ROOT APPLICATION & FULL-SIZE PERSISTENT GLOBAL AUDIO PLAYER
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
          navigatorKey: kRootNavigatorKey,
          title: 'HSK Study • AHM',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: _state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            return GlobalMiniAudioShell(
              appState: _state,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: HomeScreen(appState: _state),
        );
      },
    );
  }
}

class GlobalMiniAudioShell extends StatelessWidget {
  final AppState appState;
  final Widget child;

  const GlobalMiniAudioShell({
    super.key,
    required this.appState,
    required this.child,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _openFullPlayer() {
    final audio = GlobalAudioService.instance;
    final nav = kRootNavigatorKey.currentState;
    if (nav != null && audio.allLessonNames.isNotEmpty) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => LessonAudioPlayerScreen(
            courseId: audio.courseId,
            courseTitle: audio.courseTitle,
            allLessonNames: audio.allLessonNames,
            allLessonTracks: audio.allLessonTracks,
            initialLessonIndex: audio.lessonIndex,
            appState: appState,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final audio = GlobalAudioService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([appState, audio]),
      builder: (context, _) {
        final showBar = audio.shouldShowGlobalMiniPlayer;
        final isDark = appState.isDarkMode;
        final totalMs = audio.duration.inMilliseconds;
        final posMs = audio.position.inMilliseconds;
        final progress =
            totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;

        return Column(
          children: [
            Expanded(child: child),
            if (showBar)
              Material(
                elevation: 14,
                color: isDark ? kNightCard : Colors.white,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    decoration: BoxDecoration(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(18)),
                      border: Border(
                        top: BorderSide(
                          color: kImperialRed.withValues(alpha: 0.35),
                          width: 1.4,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: _openFullPlayer,
                              child: const Icon(
                                Icons.headphones_rounded,
                                color: kImperialRed,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: _openFullPlayer,
                                child: Text(
                                  '${audio.courseTitle} • ${audio.currentLessonName}  •  Track ${audio.trackIndex + 1}/${audio.currentTracks.length} (${audio.currentTrackCleanName})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? const Color(0xFFEF5350)
                                        : kImperialRed,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: audio.dismissAndStopMiniPlayer,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color:
                                      isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(_fmt(audio.position),
                                style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final barWidth = constraints.maxWidth;
                                  void seekAt(double dx) {
                                    if (totalMs <= 0 || barWidth <= 0) return;
                                    final ratio =
                                        (dx / barWidth).clamp(0.0, 1.0);
                                    audio.player.seek(Duration(
                                        milliseconds:
                                            (totalMs * ratio).toInt()));
                                  }

                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (d) =>
                                        seekAt(d.localPosition.dx),
                                    onHorizontalDragUpdate: (d) =>
                                        seekAt(d.localPosition.dx),
                                    child: SizedBox(
                                      height: 20,
                                      child: Stack(
                                        alignment: Alignment.centerLeft,
                                        children: [
                                          Container(
                                            height: 3.5,
                                            width: barWidth,
                                            decoration: BoxDecoration(
                                              color: kImperialRed.withValues(
                                                  alpha: 0.22),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          Container(
                                            height: 3.5,
                                            width: barWidth * progress,
                                            decoration: BoxDecoration(
                                              color: kImperialRed,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          Positioned(
                                            left: (barWidth * progress - 6)
                                                .clamp(
                                                    0.0,
                                                    (barWidth - 12)
                                                        .clamp(0.0, barWidth)),
                                            child: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: const BoxDecoration(
                                                color: kImperialRed,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(_fmt(audio.duration),
                                style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(42, 30),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: audio.cycleSpeed,
                              child: Text(
                                '${audio.speed}x',
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
                              icon: const Icon(Icons.fast_rewind_rounded,
                                  size: 22),
                              onPressed: () => audio.rewindSeconds(3),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.skip_previous_rounded,
                                  size: 26),
                              onPressed: audio.previousTrack,
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
                              onPressed: audio.togglePlayPause,
                              child: Icon(
                                audio.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 24,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.skip_next_rounded,
                                  size: 26),
                              onPressed: audio.nextTrack,
                            ),
                            IconButton(
                              tooltip: audio.singleTrackLoop
                                  ? 'Repeat Single Track (Active)'
                                  : 'Lesson Loop (Tap for Single Repeat)',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                audio.singleTrackLoop
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                size: 22,
                                color: audio.singleTrackLoop
                                    ? kImperialRed
                                    : Colors.grey,
                              ),
                              onPressed: audio.toggleSingleTrackLoop,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// 7. HOME SCREEN & DRAWER (WITH HSK 1-3 DIALOGUES, PINYIN CHART & HANZI)
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
                      const Text(
                        'Select HSK Level',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: kHskLevelCards.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 13,
                          crossAxisSpacing: 13,
                          childAspectRatio: 1.36,
                        ),
                        itemBuilder: (context, index) {
                          final level = kHskLevelCards[index];
                          return _build3dHskLevelCard(level, isDark);
                        },
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Personal Study Space',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _build3dGrammarCard(isDark),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _build3dHskLevelCard(HskLevelCard level, bool isDark) {
    if (isDark) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onLevelTap(level),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: kNightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    level.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEF5350),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kImperialRed.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      level.chineseBadge,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFEF5350),
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                level.subtitle,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _onLevelTap(level),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFC62828),
              Color(0xFF9B111E),
              Color(0xFF7A0C14),
            ],
          ),
          border: Border.all(
            color: kImperialGold.withValues(alpha: 0.78),
            width: 1.5,
          ),
          boxShadow: [
            const BoxShadow(
              color: Color(0xFF5A060B),
              offset: Offset(0, 4),
              blurRadius: 0,
            ),
            BoxShadow(
              color: kImperialRed.withValues(alpha: 0.28),
              offset: const Offset(0, 7),
              blurRadius: 12,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 36,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        level.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF6E27A), Color(0xFFD4AF37)],
                          ),
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              offset: const Offset(0, 2),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: Text(
                          level.chineseBadge,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF5D090E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        level.subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFFECB3),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 13,
                        color: kImperialGold.withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build3dGrammarCard(bool isDark) {
    if (isDark) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PersonalPdfNotesScreen(appState: widget.appState),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kNightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kImperialRed.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: kImperialRed,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Grammar & Notes',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Import & read your own PDF notes from phone/SD card',
                      style: TextStyle(fontSize: 12.5, color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PersonalPdfNotesScreen(appState: widget.appState),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFFBF2),
              Color(0xFFF6E7CE),
            ],
          ),
          border: Border.all(
            color: kImperialRed.withValues(alpha: 0.55),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: kImperialRed.withValues(alpha: 0.22),
              offset: const Offset(0, 4),
              blurRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              offset: const Offset(0, 7),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kImperialRed, kImperialDeepRed],
                ),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: kImperialGold, width: 1),
              ),
              child: const Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Grammar & Notes',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A070B),
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Import & read your own PDF notes from phone/SD card',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: kImperialRed,
              size: 26,
            ),
          ],
        ),
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
              color: kImperialRed.withValues(alpha: 0.35),
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

    const boldDrawerTitle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 15,
    );

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
                  'Curated by AHM • v1.2.3',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.star_rounded, color: Colors.amber),
            title: const Text('My Favorites', style: boldDrawerTitle),
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
            title: const Text('Quick Study Notes', style: boldDrawerTitle),
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
          ExpansionTile(
            initiallyExpanded: false,
            leading: const Icon(Icons.forum_rounded, color: kImperialRed),
            title: const Text(
              'Dialogues & Pinyin Chart',
              style: boldDrawerTitle,
            ),
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.chat_bubble_outline_rounded,
                    size: 19, color: kImperialRed),
                title: const Text(
                  'HSK 1 Dialogues (Ch 1–15)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('New Words + Dialogue + বাংলা উচ্চারণ'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DialogueCourseScreen(
                        levelTitle: 'HSK 1 Dialogues',
                        chapters: repo.hsk1DialogueChapters,
                        appState: widget.appState,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.chat_bubble_outline_rounded,
                    size: 19, color: kImperialRed),
                title: const Text(
                  'HSK 2 Dialogues (Ch 1–15)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('New Words + Dialogue + বাংলা ও ইংরেজি'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DialogueCourseScreen(
                        levelTitle: 'HSK 2 Dialogues',
                        chapters: repo.hsk2DialogueChapters,
                        appState: widget.appState,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.chat_bubble_outline_rounded,
                    size: 19, color: kImperialRed),
                title: const Text(
                  'HSK 3 Dialogues (Ch 1–20)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('New Words + Dialogue + বাংলা ও ইংরেজি'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DialogueCourseScreen(
                        levelTitle: 'HSK 3 Dialogues',
                        chapters: repo.hsk3DialogueChapters,
                        appState: widget.appState,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.grid_on_rounded,
                    size: 19, color: kImperialRed),
                title: const Text(
                  'Pinyin Initials & Finals Chart',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('২১টি Initial, ৩৬টি Final ও কম্বিনেশন'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PinyinChartScreen(
                        chartData: repo.pinyinChart,
                        appState: widget.appState,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          ExpansionTile(
            initiallyExpanded: false,
            leading: const Icon(Icons.school_rounded, color: kImperialRed),
            title: const Text(
              'HSK Vocabulary Bank (1–6)',
              style: boldDrawerTitle,
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
                          title: Text(
                            g.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('${g.words.length} Words'),
                          trailing:
                              widget.appState.isAnySlicePinnedForGroup(g.id)
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
            initiallyExpanded: false,
            leading: const Icon(Icons.work_rounded, color: kImperialRed),
            title: const Text(
              'Professions & Designations',
              style: boldDrawerTitle,
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
                          title: Text(
                            g.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(g.subtitle),
                          trailing:
                              widget.appState.isAnySlicePinnedForGroup(g.id)
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
            initiallyExpanded: false,
            leading: const Icon(Icons.eco_rounded, color: kImperialRed),
            title: const Text(
              'Daily Life & Nature',
              style: boldDrawerTitle,
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
                          title: Text(
                            g.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(g.subtitle),
                          trailing:
                              widget.appState.isAnySlicePinnedForGroup(g.id)
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
          ListTile(
            leading: const Icon(Icons.brush_rounded, color: kImperialRed),
            title: const Text('Hanzi Writing Course', style: boldDrawerTitle),
            subtitle: const Text('HSK 1–2 (300 Hanzi) • Stroke steps + grid'),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: const Text('Settings & About', style: boldDrawerTitle),
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
// 7B. HSK 1, HSK 2 & HSK 3 DIALOGUES SCREEN
// ============================================================================

class DialogueCourseScreen extends StatefulWidget {
  final String levelTitle;
  final List<DialogueChapter> chapters;
  final AppState appState;

  const DialogueCourseScreen({
    super.key,
    required this.levelTitle,
    required this.chapters,
    required this.appState,
  });

  @override
  State<DialogueCourseScreen> createState() => _DialogueCourseScreenState();
}

class _DialogueCourseScreenState extends State<DialogueCourseScreen> {
  int _selectedChapterIdx = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.appState.isDarkMode;

    if (widget.chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.levelTitle)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Dialogue JSON file not loaded yet. Check pubspec.yaml assets.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final chapter = widget
        .chapters[_selectedChapterIdx.clamp(0, widget.chapters.length - 1)];

    return Scaffold(
      appBar: AppBar(title: Text(widget.levelTitle)),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: widget.chapters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = widget.chapters[i];
                final selected = i == _selectedChapterIdx;
                return ChoiceChip(
                  label: Text('অধ্যায় ${c.chapter}'),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedChapterIdx = i),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: isDark ? kNightCard : const Color(0xFFFFEFEF),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapter.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                  ),
                ),
                if (chapter.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    chapter.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: chapter.lessons.length,
              itemBuilder: (_, lIdx) {
                final lesson = chapter.lessons[lIdx];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? kNightCard : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white12
                          : kImperialRed.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.lessonTitle,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: kImperialRed,
                        ),
                      ),
                      if (lesson.newWords.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.black26
                                : const Color(0xFFFDF8EE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: kImperialGold.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'New Words (নতুন শব্দসমূহ):',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: kImperialRed,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: lesson.newWords
                                    .map((nw) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? kNightCard
                                                : Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isDark
                                                  ? Colors.white12
                                                  : Colors.black12,
                                            ),
                                          ),
                                          child: Text(
                                            nw.en.isNotEmpty
                                                ? '${nw.hanzi} (${nw.pinyin} • ${nw.pron}) — ${nw.bn} [${nw.en}]'
                                                : '${nw.hanzi} (${nw.pinyin} • ${nw.pron}) — ${nw.bn}',
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ...lesson.dialogues.map((d) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF242424)
                                  : const Color(0xFFFAF7F2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (d.speaker == 'A' ||
                                            d.speaker == '小丽' ||
                                            d.speaker == '周太太')
                                        ? kImperialRed
                                        : const Color(0xFF2E7D32),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    d.speaker,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        d.hanzi,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${d.pinyin}  (${d.pron})',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? const Color(0xFFEF5350)
                                              : kImperialRed,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        d.bn,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (d.en.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          d.en,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black87,
                                          ),
                                        ),
                                      ],
                                      if (d.wordByWord.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'শব্দে শব্দে: ${d.wordByWord}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? Colors.white60
                                                : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
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

// ============================================================================
// 7C. PINYIN INITIALS & FINALS COMBINATION CHART SCREEN
// ============================================================================

class PinyinChartScreen extends StatelessWidget {
  final PinyinChartData? chartData;
  final AppState appState;

  const PinyinChartScreen({
    super.key,
    required this.chartData,
    required this.appState,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = appState.isDarkMode;

    if (chartData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pinyin Initials & Finals Chart')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Please ensure assets/vocab/pinyin_chart.json is listed in pubspec.yaml.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final data = chartData!;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pinyin Initials & Finals'),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.amber,
            tabs: [
              Tab(text: 'Combinations'),
              Tab(text: '21 Initials'),
              Tab(text: '36 Finals'),
              Tab(text: 'Tones & Rules'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: data.combinations.length,
              itemBuilder: (_, i) {
                final grp = data.combinations[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? kNightCard : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white12
                          : kImperialRed.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: kImperialRed,
                            foregroundColor: Colors.white,
                            child: Text(
                              grp.initial,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Initial "${grp.initial}" (${grp.initialBn})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: kImperialRed,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: grp.syllables
                            .map((s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.black26
                                        : const Color(0xFFFDF8EE),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color:
                                          kImperialGold.withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Text(
                                    '${s.pinyin} (${s.bnPron})',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: data.initials.length,
              itemBuilder: (_, i) {
                final item = data.initials[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: kImperialRed,
                      foregroundColor: Colors.white,
                      child: Text(
                        item.code,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      '${item.code}  →  উচ্চারণ: ${item.bnPron}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(item.detail),
                  ),
                );
              },
            ),
            ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: data.finals.length,
              itemBuilder: (_, i) {
                final item = data.finals[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: kImperialDeepRed,
                      foregroundColor: Colors.white,
                      child: Text(
                        item.code,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      '${item.code}  →  উচ্চারণ: ${item.bnPron}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('উদাহরণ: ${item.detail}'),
                  ),
                );
              },
            ),
            ListView(
              padding: const EdgeInsets.all(14),
              children: [
                const Text(
                  'Mandarin 4 Tones + Neutral Tone',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kImperialRed,
                  ),
                ),
                const SizedBox(height: 8),
                ...data.tones.map((t) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          '${t.tone}: ${t.example} — ${t.bnMeaning}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(t.pitch),
                      ),
                    )),
                const SizedBox(height: 14),
                const Text(
                  'Important Pinyin Rules (গুরুত্বপূর্ণ নিয়মাবলি)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kImperialRed,
                  ),
                ),
                const SizedBox(height: 8),
                ...data.rules.map((r) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          r.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(r.detail),
                      ),
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 8. PART A & PART B SELECTION SCREEN (FOR HSK 4, 5, 6)
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
// 9. VOCABULARY LIST SCREEN
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
                    ? const Center(
                        child: Text('No words found in this category.'))
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
// 10A. FLASHCARD PRACTICE + CLEAN DIAGONAL HANZI WRITING PAD (米字格)
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
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
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
            SizedBox(height: _isWritingMode ? 10 : 18),
            if (_isWritingMode)
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? kNightCard : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: kImperialRed.withValues(alpha: 0.35),
                            width: 1.4,
                          ),
                        ),
                        child: showBack
                            ? Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()..rotateY(math.pi),
                                child: _buildCompactCardBack(word, isDark),
                              )
                            : _buildCompactCardFront(word),
                      ),
                    );
                  },
                ),
              )
            else
              Expanded(
                child: GestureDetector(
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
                                  transform: Matrix4.identity()
                                    ..rotateY(math.pi),
                                  child: _buildCardBack(word, isDark),
                                )
                              : _buildCardFront(word),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (_isWritingMode) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Draw Hanzi below:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _strokes.isEmpty
                            ? null
                            : () => setState(() => _strokes.removeLast()),
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: const Text('Undo'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
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
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                      border: Border.all(color: kImperialRed, width: 1.6),
                      borderRadius: BorderRadius.circular(16),
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
                          showDiagonalGuides: true,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
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
                      padding: const EdgeInsets.symmetric(vertical: 13),
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

  Widget _buildCompactCardFront(VocabWord w) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          w.bn,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          '${w.en} • Tap card to reveal Hanzi',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildCompactCardBack(VocabWord w, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          w.hanzi,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                w.pinyin,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                ),
              ),
              Text(
                w.bn,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardFront(VocabWord w) {
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
// 10B. FAVORITES FULL-SCREEN HANZI WRITING
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
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  String? _feedbackText;
  bool _feedbackIsError = false;

  List<String> get _chars {
    final chars = widget.word.hanzi.runes
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
            'ভুল হয়েছে! আগে বর্গাকার ঘরে হানজি লিখুন, তারপর আবার চেষ্টা করো।';
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
            'ভুল হয়েছে! অক্ষরের আকৃতি বা দাগ ঠিক হয়নি — আবার চেষ্টা করো।';
        _strokes.clear();
        _currentStroke = [];
      });
    } else {
      HapticFeedback.lightImpact();
      setState(() {
        _feedbackIsError = false;
        _feedbackText = 'সঠিক হয়েছে! "$_targetChar" সুন্দরভাবে লেখা হয়েছে।';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorite Hanzi Writing'),
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
// 10C. HANZI WRITING COURSE SCREEN (3-STEP FLIP: TRACE -> SELF-TEST -> CHECK)
// ============================================================================

class HanziWritingCourseScreen extends StatefulWidget {
  final AppState appState;
  const HanziWritingCourseScreen({super.key, required this.appState});

  @override
  State<HanziWritingCourseScreen> createState() =>
      _HanziWritingCourseScreenState();
}

class _HanziWritingCourseScreenState extends State<HanziWritingCourseScreen>
    with SingleTickerProviderStateMixin {
  int _chapterIdx = 0;
  int _charIdx = 0;
  int _activeStep = 0;
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];

  bool _isSelfTestMode = false;
  bool _showColoredCheckChar = false;

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  List<HanziCourseChapter> get _chapters =>
      VocabRepository.instance.hanziChapters;

  HanziCourseChapter get _chapter =>
      _chapters[_chapterIdx.clamp(0, _chapters.length - 1)];

  HanziCourseChar get _char =>
      _chapter.characters[_charIdx.clamp(0, _chapter.characters.length - 1)];

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _flipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _selectChar(int idx) {
    _flipController.reset();
    setState(() {
      _charIdx = idx;
      _activeStep = 0;
      _strokes.clear();
      _currentStroke = [];
      _isSelfTestMode = false;
      _showColoredCheckChar = false;
    });
  }

  void _toggleFlipSelfTest() {
    HapticFeedback.selectionClick();
    final nextMode = !_isSelfTestMode;
    if (nextMode) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
    setState(() {
      _isSelfTestMode = nextMode;
      _strokes.clear();
      _currentStroke = [];
      _showColoredCheckChar = false;
    });
  }

  void _revealColoredReference() {
    HapticFeedback.lightImpact();
    setState(() {
      _showColoredCheckChar = !_showColoredCheckChar;
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
                  onSelected: (_) {
                    _flipController.reset();
                    setState(() {
                      _chapterIdx = i;
                      _charIdx = 0;
                      _activeStep = 0;
                      _strokes.clear();
                      _currentStroke = [];
                      _isSelfTestMode = false;
                      _showColoredCheckChar = false;
                    });
                  },
                );
              },
            ),
          ),
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
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: kImperialRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kImperialRed.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        currentChar.char,
                        style: const TextStyle(
                          fontSize: 30,
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
                            currentChar.pron.isNotEmpty
                                ? '${currentChar.pinyin} (${currentChar.pron}) • ${currentChar.bn}'
                                : '${currentChar.pinyin} • ${currentChar.bn}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'মোট স্ট্রোক: ${currentChar.strokes}টি',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (currentChar.steps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: currentChar.steps.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, sIdx) {
                        final active = sIdx == _activeStep;
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => _activeStep = sIdx),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: active
                                  ? kImperialRed
                                  : (isDark ? Colors.black26 : Colors.white),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: active ? kImperialRed : Colors.black26,
                                width: active ? 1.5 : 1.0,
                              ),
                            ),
                            child: Text(
                              currentChar.steps[sIdx],
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: active
                                    ? Colors.white
                                    : (isDark ? Colors.white : Colors.black87),
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
          Expanded(
            child: Center(
              child: AnimatedBuilder(
                animation: _flipAnimation,
                builder: (context, child) {
                  final angle = _flipAnimation.value * math.pi;
                  final isBack = angle > math.pi / 2;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..rotateY(isBack ? math.pi : 0.0),
                      child: child,
                    ),
                  );
                },
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF191919) : Colors.white,
                      border: Border.all(
                        color: _isSelfTestMode
                            ? const Color(0xFF2E7D32)
                            : kImperialRed,
                        width: 2.2,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
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
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final boxSize = math.min(
                                constraints.maxWidth, constraints.maxHeight);
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                if (!_isSelfTestMode && !_showColoredCheckChar)
                                  IgnorePointer(
                                    child: Text(
                                      currentChar.char,
                                      style: TextStyle(
                                        fontSize: boxSize * 0.72,
                                        height: 1.0,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.white.withValues(alpha: 0.14)
                                            : Colors.black.withValues(alpha: 0.13),
                                      ),
                                    ),
                                  ),
                                if (_showColoredCheckChar)
                                  IgnorePointer(
                                    child: Text(
                                      currentChar.char,
                                      style: TextStyle(
                                        fontSize: boxSize * 0.72,
                                        height: 1.0,
                                        fontWeight: FontWeight.bold,
                                        color: kImperialRed.withValues(
                                            alpha: isDark ? 0.55 : 0.42),
                                      ),
                                    ),
                                  ),
                                CustomPaint(
                                  painter: _HanziPadPainter(
                                    strokes: _strokes,
                                    strokeColor: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    showDiagonalGuides: true,
                                  ),
                                  size: Size.infinite,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Undo',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.undo_rounded),
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(() {
                            _strokes.removeLast();
                          }),
                ),
                IconButton(
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: _strokes.isEmpty && !_showColoredCheckChar
                      ? null
                      : () => setState(() {
                            _strokes.clear();
                            _currentStroke = [];
                            _showColoredCheckChar = false;
                          }),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          _isSelfTestMode ? kImperialRed : const Color(0xFF2E7D32),
                      side: BorderSide(
                        color: _isSelfTestMode
                            ? kImperialRed
                            : const Color(0xFF2E7D32),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 11),
                    ),
                    onPressed: _toggleFlipSelfTest,
                    icon: const Icon(Icons.flip_rounded, size: 18),
                    label: Text(
                      _isSelfTestMode ? 'দেখে লিখুন' : 'নিজে লিখুন',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _showColoredCheckChar
                          ? const Color(0xFF2E7D32)
                          : kImperialRed,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 11),
                    ),
                    onPressed: _revealColoredReference,
                    icon: const Icon(Icons.visibility_rounded, size: 17),
                    label: const Text(
                      'Check',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 11),
                  ),
                  onPressed: _charIdx < _chapter.characters.length - 1
                      ? () => _selectChar(_charIdx + 1)
                      : (_chapterIdx < _chapters.length - 1
                          ? () {
                              _flipController.reset();
                              setState(() {
                                _chapterIdx++;
                                _selectChar(0);
                              });
                            }
                          : null),
                  child: const Text('Next', style: TextStyle(fontSize: 12.5)),
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
  final bool showDiagonalGuides;

  _HanziPadPainter({
    required this.strokes,
    required this.strokeColor,
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
        ..color = Colors.red.withValues(alpha: 0.22)
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
// 11. FAVORITES SCREEN
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
                              title: Text(
                                s.displayTitle,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
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
// 12. COURSE DETAIL SCREEN
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
  Map<String, List<File>> _lessonTracks = {};
  int _lastKnownVersion = -1;

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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        if (_lastKnownVersion != widget.appState.offlineVersionCounter) {
          _lastKnownVersion = widget.appState.offlineVersionCounter;
          Future.microtask(_checkLocalFiles);
        }

        final pdfTask =
            widget.appState.getTaskStatus(widget.course.id, isZip: false);
        final audioTask =
            widget.appState.getTaskStatus(widget.course.id, isZip: true);
        final pdfErr =
            widget.appState.downloadErrors['${widget.course.id}_pdf'];
        final audioErr =
            widget.appState.downloadErrors['${widget.course.id}_audio'];

        final lessonNames = _lessonTracks.keys.toList()..sort();

        return Scaffold(
          appBar: AppBar(title: Text(widget.course.title)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.picture_as_pdf_rounded,
                            color: kImperialRed, size: 32),
                        title: Text(
                          '${widget.course.title} Textbook (PDF)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          pdfTask.isDownloading
                              ? pdfTask.statusText
                              : (_pdfReady
                                  ? 'Ready offline • Tap to open reader'
                                  : (pdfErr != null
                                      ? 'Failed: $pdfErr'
                                      : 'Download textbook for offline reading')),
                        ),
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: kImperialRed),
                          onPressed: pdfTask.isDownloading
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
                                    widget.appState.startBackgroundDownload(
                                      course: widget.course,
                                      isZip: false,
                                    );
                                  }
                                },
                          child: Text(pdfTask.isDownloading
                              ? 'Downloading...'
                              : (_pdfReady ? 'Open PDF' : 'Download')),
                        ),
                      ),
                      if (pdfTask.isDownloading)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: LinearProgressIndicator(
                            color: kImperialRed,
                            value:
                                pdfTask.progress > 0 ? pdfTask.progress : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.folder_special_rounded,
                            color: kImperialRed, size: 32),
                        title: Text(
                          '${widget.course.title} Audio Lessons',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          audioTask.isDownloading
                              ? audioTask.statusText
                              : (_audioReady
                                  ? '${lessonNames.length} Lessons inside • Tap to open folder'
                                  : (audioErr != null
                                      ? 'Failed: $audioErr'
                                      : 'Download native audio pack (ZIP)')),
                        ),
                        onTap: _audioReady && !audioTask.isDownloading
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
                                style: FilledButton.styleFrom(
                                    backgroundColor: kImperialRed),
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
                                icon: const Icon(Icons.headphones_rounded,
                                    size: 18),
                                label: const Text('Open'),
                              )
                            : FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: kImperialRed),
                                onPressed: audioTask.isDownloading
                                    ? null
                                    : () =>
                                        widget.appState.startBackgroundDownload(
                                          course: widget.course,
                                          isZip: true,
                                        ),
                                child: Text(audioTask.isDownloading
                                    ? 'Downloading...'
                                    : 'Download'),
                              ),
                      ),
                      if (audioTask.isDownloading)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: LinearProgressIndicator(
                            color: kImperialRed,
                            value: audioTask.progress > 0
                                ? audioTask.progress
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (pdfTask.isDownloading || audioTask.isDownloading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Downloads continue safely in the background even if you navigate back.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
// 12B. COURSE AUDIO LESSONS FOLDER SCREEN
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
              title: Text(
                '${course.title} • $lessonTitle',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
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
// 13. PDF READER (TRACK DROPDOWN + REPEAT ONE / LESSON LOOP BUTTON)
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
  final GlobalAudioService _audio = GlobalAudioService.instance;

  int _currentPage = 1;
  int _totalPages = 0;
  bool _ready = false;

  bool _showAudioBar = true;
  int _lessonIdx = 0;

  bool get _hasAudio => widget.lessonNames.isNotEmpty;

  List<File> get _tracks => _hasAudio
      ? (widget.lessonTracks[widget.lessonNames[_lessonIdx]] ?? [])
      : [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _audio.setHideGlobalMiniPlayer(true));
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
    if (_audio.courseId != widget.courseId || !_audio.hasLoadedLesson) {
      _audio.loadLessonAndPlay(
        courseId: widget.courseId,
        courseTitle: widget.title,
        allLessonNames: widget.lessonNames,
        allLessonTracks: widget.lessonTracks,
        lessonIndex: _lessonIdx,
        autoPlay: false,
      );
    } else {
      _lessonIdx = _audio.lessonIndex.clamp(0, widget.lessonNames.length - 1);
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
    if (_totalPages <= 0) return;
    final ctrl = TextEditingController(text: '$_currentPage');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Jump to Page',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kImperialRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Total Pages: $_totalPages  •  Current: $_currentPage',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: kImperialRed,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Enter page number (1 – $_totalPages)',
                hintText: '1 – $_totalPages',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
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
    _audio.setHideGlobalMiniPlayer(false);
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.appState.isDarkMode;
    return AnimatedBuilder(
      animation: _audio,
      builder: (context, _) {
        final activeTracks = _tracks;
        final safeTrackIdx = activeTracks.isEmpty
            ? 0
            : _audio.trackIndex.clamp(0, activeTracks.length - 1);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (_totalPages > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _showJumpDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.find_in_page_rounded,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            '$_currentPage / $_totalPages',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                  },
                ),
            ],
          ),
          body: !_ready || _pdfController == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Container(
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
                    ),
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
                            Row(
                              children: [
                                const Icon(Icons.menu_book_rounded,
                                    size: 15, color: kImperialRed),
                                const SizedBox(width: 6),
                                DropdownButton<int>(
                                  value: _lessonIdx,
                                  isDense: true,
                                  underline: const SizedBox(),
                                  iconEnabledColor:
                                      isDark ? Colors.white : kImperialRed,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        isDark ? Colors.white : kImperialRed,
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
                                      _audio.loadLessonAndPlay(
                                        courseId: widget.courseId,
                                        courseTitle: widget.title,
                                        allLessonNames: widget.lessonNames,
                                        allLessonTracks: widget.lessonTracks,
                                        lessonIndex: v,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                if (activeTracks.isNotEmpty)
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: DropdownButton<int>(
                                        value: safeTrackIdx,
                                        isDense: true,
                                        isExpanded: true,
                                        underline: const SizedBox(),
                                        iconEnabledColor:
                                            isDark ? Colors.white : kImperialRed,
                                        alignment: AlignmentDirectional.centerEnd,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.white
                                              : kImperialRed,
                                        ),
                                        items: List.generate(
                                          activeTracks.length,
                                          (i) {
                                            final name = activeTracks[i]
                                                .uri
                                                .pathSegments
                                                .last
                                                .replaceAll('.mp3', '')
                                                .replaceAll('.m4a', '');
                                            return DropdownMenuItem(
                                              value: i,
                                              alignment:
                                                  AlignmentDirectional.centerEnd,
                                              child: Text(
                                                'Track ${i + 1}/${activeTracks.length} ($name)',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            );
                                          },
                                        ),
                                        onChanged: (v) {
                                          if (v != null) {
                                            if (_audio.courseId !=
                                                    widget.courseId ||
                                                _audio.lessonIndex !=
                                                    _lessonIdx) {
                                              _audio.loadLessonAndPlay(
                                                courseId: widget.courseId,
                                                courseTitle: widget.title,
                                                allLessonNames:
                                                    widget.lessonNames,
                                                allLessonTracks:
                                                    widget.lessonTracks,
                                                lessonIndex: _lessonIdx,
                                                initialTrackIndex: v,
                                                autoPlay: true,
                                              );
                                            } else {
                                              _audio.playTrackAt(v);
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
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
                                  value: _audio.position.inMilliseconds
                                      .toDouble()
                                      .clamp(
                                          0,
                                          _audio.duration.inMilliseconds
                                                  .toDouble() +
                                              1),
                                  max: _audio.duration.inMilliseconds
                                          .toDouble() +
                                      1,
                                  onChanged: (v) => _audio.player
                                      .seek(Duration(milliseconds: v.toInt())),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                TextButton(
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(44, 32),
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: _audio.cycleSpeed,
                                  child: Text(
                                    '${_audio.speed}x',
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
                                  onPressed: () => _audio.rewindSeconds(5),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon:
                                      const Icon(Icons.skip_previous_rounded),
                                  onPressed: _audio.previousTrack,
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: _audio.togglePlayPause,
                                  child: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: const BoxDecoration(
                                      color: kImperialRed,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _audio.isPlaying
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
                                  onPressed: _audio.nextTrack,
                                ),
                                IconButton(
                                  tooltip: _audio.singleTrackLoop
                                      ? 'Repeat One (Current Track)'
                                      : 'Lesson Loop (All Tracks in Lesson)',
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                    _audio.singleTrackLoop
                                        ? Icons.repeat_one_rounded
                                        : Icons.repeat_rounded,
                                    color: _audio.singleTrackLoop
                                        ? kImperialRed
                                        : (isDark
                                            ? Colors.white70
                                            : Colors.black87),
                                  ),
                                  onPressed: _audio.toggleSingleTrackLoop,
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
// 14. GLOBAL BACKGROUND AUDIO PLAYER SCREEN (LOCK-SCREEN & BLUETOOTH)
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
  final GlobalAudioService _audio = GlobalAudioService.instance;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _audio.setHideGlobalMiniPlayer(true));
    final alreadyPlayingSame = _audio.courseId == widget.courseId &&
        _audio.lessonIndex == widget.initialLessonIndex &&
        _audio.hasLoadedLesson;

    if (!alreadyPlayingSame) {
      _audio.loadLessonAndPlay(
        courseId: widget.courseId,
        courseTitle: widget.courseTitle,
        allLessonNames: widget.allLessonNames,
        allLessonTracks: widget.allLessonTracks,
        lessonIndex: widget.initialLessonIndex,
        initialTrackIndex: 0,
        autoPlay: true,
      );
    }
  }

  @override
  void dispose() {
    _audio.setHideGlobalMiniPlayer(false);
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.appState.isDarkMode;

    return AnimatedBuilder(
      animation: Listenable.merge([widget.appState, _audio]),
      builder: (context, _) {
        final isAllMode = widget.appState.allLessonsContinuous;
        final tracks = _audio.currentTracks;
        final activeLessonName = _audio.currentLessonName.isNotEmpty
            ? _audio.currentLessonName
            : widget.allLessonNames[widget.initialLessonIndex];

        return Scaffold(
          appBar: AppBar(
            title: Text('${widget.courseTitle} • $activeLessonName'),
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
                  itemCount: tracks.length,
                  itemBuilder: (_, i) {
                    final f = tracks[i];
                    final rawName = f.uri.pathSegments.last
                        .replaceAll('.mp3', '')
                        .replaceAll('.m4a', '');
                    final active = i == _audio.trackIndex;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: active
                            ? (isDark
                                ? const Color(0xFF3E2723)
                                : const Color(0xFFFFEBEE))
                            : (isDark ? kNightCard : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? kImperialRed
                              : (isDark
                                  ? Colors.white24
                                  : const Color(0xFFD6CBBF)),
                          width: active ? 1.6 : 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          active
                              ? Icons.graphic_eq_rounded
                              : Icons.music_note_rounded,
                          color: active ? kImperialRed : Colors.grey.shade600,
                        ),
                        title: Text(
                          'Track ${i + 1} ($rawName)',
                          style: TextStyle(
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.w600,
                            color: active ? kImperialRed : null,
                          ),
                        ),
                        onTap: () => _audio.playTrackAt(i),
                      ),
                    );
                  },
                ),
              ),
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
                        Text(_fmt(_audio.position),
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
                                value: _audio.position.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                        0,
                                        _audio.duration.inMilliseconds
                                                .toDouble() +
                                            1),
                                max: _audio.duration.inMilliseconds.toDouble() +
                                    1,
                                onChanged: (v) => _audio.player
                                    .seek(Duration(milliseconds: v.toInt())),
                              ),
                            ),
                          ),
                        ),
                        Text(_fmt(_audio.duration),
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
                          onPressed: _audio.cycleSpeed,
                          child: Text(
                            '${_audio.speed}x',
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
                          onPressed: () => _audio.rewindSeconds(3),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.skip_previous_rounded,
                              size: 26),
                          onPressed: _audio.previousTrack,
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
                          onPressed: _audio.togglePlayPause,
                          child: Icon(
                            _audio.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 24,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.skip_next_rounded, size: 26),
                          onPressed: _audio.nextTrack,
                        ),
                        IconButton(
                          tooltip: 'Repeat Single Track',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.repeat_one_rounded,
                            size: 22,
                            color: _audio.singleTrackLoop
                                ? kImperialRed
                                : Colors.grey,
                          ),
                          onPressed: _audio.toggleSingleTrackLoop,
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
// 15A. PERSONAL PDF GRAMMAR & NOTES
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
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
              itemCount: _pdfs.length,
              onReorder: (oldIndex, newIndex) async {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _pdfs.removeAt(oldIndex);
                  _pdfs.insert(newIndex, item);
                });
                await _savePdfs();
              },
              itemBuilder: (_, i) {
                final item = _pdfs[i];
                return Card(
                  key: ValueKey('${item.path}_$i'),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_rounded,
                        color: kImperialRed),
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle:
                        const Text('Tap to read • Hold & drag to reorder'),
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
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
                        const Icon(Icons.drag_handle_rounded,
                            color: Colors.grey),
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
// 15B. QUICK TEXT STUDY NOTES SCREEN
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
// 16. OFFLINE STORAGE MANAGER
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
                                title: const Text(
                                  'Textbook PDF',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
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
                                title: const Text(
                                  'Audio Lessons Pack',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
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
// 17. SETTINGS & ABOUT SCREEN
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
    final optionTitleStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 15,
      color: isDark ? Colors.white : const Color(0xFF1F1F1F),
    );

    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings & About')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'APPEARANCE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  letterSpacing: 0.8,
                  color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Night Study Dark Mode', style: optionTitleStyle),
                subtitle: const Text(
                    'Switch between Porcelain White and Dark Theme'),
                value: widget.appState.isDarkMode,
                onChanged: widget.appState.toggleDarkMode,
              ),
              const Divider(),
              const SizedBox(height: 6),
              Text(
                'AUDIO STUDY PREFERENCES',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  letterSpacing: 0.8,
                  color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Audio Playback Mode', style: optionTitleStyle),
                subtitle: Text(
                  widget.appState.allLessonsContinuous
                      ? 'All Lessons Continuous (1 → End)'
                      : 'Lesson-by-Lesson Loop (Current Lesson)',
                ),
                trailing: DropdownButton<bool>(
                  value: widget.appState.allLessonsContinuous,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
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
                title: Text('Default Playback Speed', style: optionTitleStyle),
                trailing: DropdownButton<double>(
                  value: widget.appState.defaultSpeed,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
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
                title: Text('Pause Gap Between Tracks (Shadowing)',
                    style: optionTitleStyle),
                subtitle:
                    const Text('Extra pause in audio mode to repeat aloud'),
                trailing: DropdownButton<int>(
                  value: widget.appState.shadowingGapSeconds,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
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
              const SizedBox(height: 6),
              Text(
                'OFFLINE STORAGE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  letterSpacing: 0.8,
                  color: isDark ? const Color(0xFFEF5350) : kImperialRed,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sd_storage_rounded,
                    color: kImperialRed),
                title: Text('Manage Offline Storage', style: optionTitleStyle),
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
