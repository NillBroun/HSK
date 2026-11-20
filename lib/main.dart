import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

const String githubUser = "NillBroun";
const String repoName = "HSK";
const String releaseTag = "v1.0.0";
const String developerFacebookUrl = "https://www.facebook.com/ahm.79316";
const String academyFacebookUrl = "https://www.facebook.com/profile.php?id=61581738629512";

String releaseUrl(String fileName) =>
    "https://github.com/$githubUser/$repoName/releases/download/$releaseTag/$fileName";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(HSKApp(prefs: prefs));
}

class HSKModule {
  final String id;
  final String levelTitle;
  final String subTitle;
  final String chineseBadge;
  final String audioZipName;
  final String pdfFileName;

  const HSKModule({
    required this.id,
    required this.levelTitle,
    required this.subTitle,
    required this.chineseBadge,
    required this.audioZipName,
    required this.pdfFileName,
  });
}

const List<HSKModule> allModules = [
  HSKModule(id: "hsk1", levelTitle: "HSK 1", subTitle: "Beginner", chineseBadge: "一级", audioZipName: "hsk1textbookaudios.zip", pdfFileName: "HSK-1-Textbook.pdf"),
  HSKModule(id: "hsk2", levelTitle: "HSK 2", subTitle: "Elementary", chineseBadge: "二级", audioZipName: "hsk2textbookaudios.zip", pdfFileName: "HSK-2-Textbook.pdf"),
  HSKModule(id: "hsk3", levelTitle: "HSK 3", subTitle: "Intermediate", chineseBadge: "三级", audioZipName: "hsk3textbookaudios.zip", pdfFileName: "HSK-3-Textbook.pdf"),
  HSKModule(id: "hsk4A", levelTitle: "HSK 4 — Part A", subTitle: "Upper-Intermediate (上)", chineseBadge: "四级上", audioZipName: "hsk4Atextbookaudios.zip", pdfFileName: "hSK-4A-textbook.pdf"),
  HSKModule(id: "hsk4B", levelTitle: "HSK 4 — Part B", subTitle: "Upper-Intermediate (下)", chineseBadge: "四级下", audioZipName: "hsk4Btextbookaudios.zip", pdfFileName: "HSK-4B-Textbook.pdf"),
  HSKModule(id: "hsk5A", levelTitle: "HSK 5 — Part A", subTitle: "Advanced (上)", chineseBadge: "五级上", audioZipName: "hsk5Atextbookaudios.zip", pdfFileName: "HSK-5A-Textbook.pdf"),
  HSKModule(id: "hsk5B", levelTitle: "HSK 5 — Part B", subTitle: "Advanced (下)", chineseBadge: "五级下", audioZipName: "hsk5Btextbookaudios.zip", pdfFileName: "HSK-5B-Textbook.pdf"),
  HSKModule(id: "hsk6A", levelTitle: "HSK 6 — Part A", subTitle: "Mastery (上)", chineseBadge: "六级上", audioZipName: "hsk6Atextbookaudios.zip", pdfFileName: "HSK-6A-Textbook.pdf"),
  HSKModule(id: "hsk6B", levelTitle: "HSK 6 — Part B", subTitle: "Mastery (下)", chineseBadge: "六级下", audioZipName: "hsk6Btextbookaudios.zip", pdfFileName: "HSK-6B-Textbook.pdf"),
];

Future scanModuleAudios(String moduleId) async {
  final dir = await getApplicationDocumentsDirectory();
  final audioDir = Directory('${dir.path}/audios/$moduleId');
  Map<String, List<File>> scanned = {};
  if (await audioDir.exists()) {
    await for (var entity in audioDir.list(recursive: true)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.mp3')) {
        final parentName = entity.parent.uri.pathSegments.where((s) => s.isNotEmpty).last;
        scanned.putIfAbsent(parentName, () => []).add(entity);
      }
    }
    for (var key in scanned.keys) {
      scanned[key]!.sort((a, b) => a.path.compareTo(b.path));
    }
  }
  final sortedKeys = scanned.keys.toList()..sort();
  return {for (var k in sortedKeys) k: scanned[k]!};
}

class HSKApp extends StatefulWidget {
  final SharedPreferences prefs;
  const HSKApp({super.key, required this.prefs});

  @override
  State<HSKApp> createState() => _HSKAppState();
}

class _HSKAppState extends State<HSKApp> {
  late bool isDarkMode;

  @override
  void initState() {
    super.initState();
    isDarkMode = widget.prefs.getBool('dark_mode') ?? false;
  }

  void toggleTheme(bool val) {
    setState(() => isDarkMode = val);
    widget.prefs.setBool('dark_mode', val);
  }

  @override
  Widget build(BuildContext context) {
    const imperialRed = Color(0xFFB71C1C);
    const porcelainWhite = Color(0xFFFAF9F6);

    return MaterialApp(
      title: 'HSK',
      debugShowCheckedModeBanner: false,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: porcelainWhite,
        colorScheme: ColorScheme.fromSeed(
          seedColor: imperialRed,
          primary: imperialRed,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: imperialRed,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: imperialRed,
          brightness: Brightness.dark,
          primary: const Color(0xFFE53935),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: HomeScreen(
        prefs: widget.prefs,
        isDarkMode: isDarkMode,
        onThemeChanged: toggleTheme,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  const HomeScreen({
    super.key,
    required this.prefs,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String lastPlayed = "";

  @override
  void initState() {
    super.initState();
    _loadLastPlayed();
  }

  void _loadLastPlayed() {
    setState(() {
      lastPlayed = widget.prefs.getString('last_played') ?? "";
    });
  }

  Future<void> _resumeLastStudied() async {
    final savedModuleId = widget.prefs.getString('last_module_id') ?? "";
    final savedFolder = widget.prefs.getString('last_folder_key') ?? "";

    HSKModule? targetModule;
    for (var m in allModules) {
      if (m.id == savedModuleId) {
        targetModule = m;
        break;
      }
    }

    if (targetModule == null && lastPlayed.isNotEmpty) {
      for (var m in allModules) {
        if (lastPlayed.startsWith(m.levelTitle)) {
          targetModule = m;
          break;
        }
      }
    }

    if (targetModule == null) return;

    final folders = await scanModuleAudios(targetModule.id);
    if (!mounted) return;

    String? matchedFolderKey;
    if (savedFolder.isNotEmpty && folders.containsKey(savedFolder)) {
      matchedFolderKey = savedFolder;
    } else if (lastPlayed.contains('•')) {
      final part = lastPlayed.split('•').last.trim().toLowerCase();
      for (var k in folders.keys) {
        if (k.replaceAll('-', ' ').toLowerCase() == part) {
          matchedFolderKey = k;
          break;
        }
      }
    }

    if (folders.isNotEmpty && matchedFolderKey != null) {
      final displayTitle = matchedFolderKey.replaceAll('-', ' ').toUpperCase();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChapterAudioPlayerScreen(
            moduleTitle: targetModule!.levelTitle,
            chapterTitle: displayTitle,
            tracks: folders[matchedFolderKey]!,
            prefs: widget.prefs,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ModuleDashboardScreen(module: targetModule!, prefs: widget.prefs),
        ),
      );
    }
    _loadLastPlayed();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text("汉语", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(width: 10),
            const Text("HSK", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: "Settings",
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    prefs: widget.prefs,
                    isDarkMode: widget.isDarkMode,
                    onThemeChanged: widget.onThemeChanged,
                  ),
                ),
              );
              _loadLastPlayed();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (lastPlayed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _resumeLastStudied,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: primary.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, color: primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Last Studied (Tap to Resume)", style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
                            Text(lastPlayed, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                      Icon(Icons.play_circle_fill_rounded, color: primary, size: 28),
                    ],
                  ),
                ),
              ),
            ),

          const Text("Select HSK Level", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: [
              _buildLevelTile(context, "HSK 1", "Beginner", "一级", [allModules[0]]),
              _buildLevelTile(context, "HSK 2", "Elementary", "二级", [allModules[1]]),
              _buildLevelTile(context, "HSK 3", "Intermediate", "三级", [allModules[2]]),
              _buildLevelTile(context, "HSK 4", "Part A & B", "四级", [allModules[3], allModules[4]]),
              _buildLevelTile(context, "HSK 5", "Part A & B", "五级", [allModules[5], allModules[6]]),
              _buildLevelTile(context, "HSK 6", "Part A & B", "六级", [allModules[7], allModules[8]]),
            ],
          ),

          const SizedBox(height: 20),
          const Text("Personal Study Space", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              leading: CircleAvatar(
                backgroundColor: primary.withOpacity(0.12),
                child: Icon(Icons.menu_book_rounded, color: primary),
              ),
              title: const Text("My Grammar & Notes", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Import & read your own PDF notes from phone/SD card"),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PersonalGrammarScreen(prefs: widget.prefs)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelTile(BuildContext context, String title, String sub, String hanzi, List<HSKModule> modules) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        if (modules.length == 1) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ModuleDashboardScreen(module: modules.first, prefs: widget.prefs)),
          );
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PartSelectorScreen(title: title, parts: modules, prefs: widget.prefs)),
          );
        }
        _loadLastPlayed();
      },
      child: Card(
        elevation: 1.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: primary.withOpacity(0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: primary)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(hanzi, style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
                  ),
                ],
              ),
              Text(sub, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }
}

class PartSelectorScreen extends StatelessWidget {
  final String title;
  final List<HSKModule> parts;
  final SharedPreferences prefs;

  const PartSelectorScreen({super.key, required this.title, required this.parts, required this.prefs});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: parts.map((m) {
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  child: Text(m.chineseBadge.substring(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                title: Text(m.levelTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                subtitle: Text(m.subTitle),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ModuleDashboardScreen(module: m, prefs: prefs)),
                  );
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class ModuleDashboardScreen extends StatefulWidget {
  final HSKModule module;
  final SharedPreferences prefs;

  const ModuleDashboardScreen({super.key, required this.module, required this.prefs});

  @override
  State<ModuleDashboardScreen> createState() => _ModuleDashboardScreenState();
}

class _ModuleDashboardScreenState extends State<ModuleDashboardScreen> {
  bool audioReady = false;
  bool pdfReady = false;
  bool downloadingAudio = false;
  bool downloadingPdf = false;
  double progress = 0.0;
  Map<String, List<File>> lessonFolders = {};
  late String pdfLocalPath;

  @override
  void initState() {
    super.initState();
    _checkLocalFiles();
  }

  Future<void> _checkLocalFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final pdfFile = File('${dir.path}/pdfs/${widget.module.pdfFileName}');
    pdfLocalPath = pdfFile.path;

    final sortedMap = await scanModuleAudios(widget.module.id);

    setState(() {
      lessonFolders = sortedMap;
      audioReady = sortedMap.isNotEmpty;
      pdfReady = pdfFile.existsSync();
    });
  }

  Future<void> _downloadAndExtractAudio() async {
    setState(() {
      downloadingAudio = true;
      progress = 0.0;
    });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final zipFile = File('${dir.path}/${widget.module.audioZipName}');
      final extractDir = Directory('${dir.path}/audios/${widget.module.id}');

      await Dio().download(
        releaseUrl(widget.module.audioZipName),
        zipFile.path,
        onReceiveProgress: (rec, total) {
          if (total > 0) setState(() => progress = rec / total);
        },
      );

      if (await extractDir.exists()) await extractDir.delete(recursive: true);
      await extractDir.create(recursive: true);
      await extractFileToDisk(zipFile.path, extractDir.path);
      if (await zipFile.exists()) await zipFile.delete();

      await _checkLocalFiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Download failed. Check internet connection: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => downloadingAudio = false);
    }
  }

  Future<void> _downloadPdf() async {
    setState(() {
      downloadingPdf = true;
      progress = 0.0;
    });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final pdfDir = Directory('${dir.path}/pdfs');
      if (!await pdfDir.exists()) await pdfDir.create(recursive: true);
      final pdfFile = File('${pdfDir.path}/${widget.module.pdfFileName}');

      await Dio().download(
        releaseUrl(widget.module.pdfFileName),
        pdfFile.path,
        onReceiveProgress: (rec, total) {
          if (total > 0) setState(() => progress = rec / total);
        },
      );
      await _checkLocalFiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("PDF download failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => downloadingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: Text(widget.module.levelTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (downloadingAudio || downloadingPdf)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  LinearProgressIndicator(value: progress, color: primary),
                  const SizedBox(height: 6),
                  Text("Downloading... ${(progress * 100).toStringAsFixed(0)}%"),
                ],
              ),
            ),

          _buildOptionCard(
            icon: Icons.headphones_rounded,
            title: "Only Audio (Chapter Loop Mode)",
            subtitle: audioReady
                ? "${lessonFolders.length} chapters ready • Loops continuously until paused"
                : "Download audio pack from GitHub to listen offline",
            actionLabel: audioReady ? "Listen" : "Download",
            isReady: audioReady,
            onTap: () {
              if (!audioReady) {
                _downloadAndExtractAudio();
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChapterListScreen(
                      module: widget.module,
                      lessonFolders: lessonFolders,
                      prefs: widget.prefs,
                    ),
                  ),
                );
              }
            },
          ),

          const SizedBox(height: 14),

          _buildOptionCard(
            icon: Icons.picture_as_pdf_rounded,
            title: "Standard Textbook (PDF)",
            subtitle: pdfReady
                ? (audioReady ? "Read PDF with built-in Lesson Audio Player" : "Available offline (Download audio pack to listen while reading)")
                : "Download textbook PDF from GitHub",
            actionLabel: pdfReady ? "Read PDF" : "Download",
            isReady: pdfReady,
            onTap: () {
              if (!pdfReady) {
                _downloadPdf();
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PdfViewerScreen(
                      title: widget.module.levelTitle,
                      filePath: pdfLocalPath,
                      prefs: widget.prefs,
                      lessonFolders: lessonFolders,
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required bool isReady,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: primary.withOpacity(0.12),
          child: Icon(icon, color: primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(fontSize: 13)),
        ),
        trailing: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: isReady ? primary : Colors.grey[800],
          ),
          onPressed: onTap,
          child: Text(actionLabel),
        ),
      ),
    );
  }
}

class ChapterListScreen extends StatelessWidget {
  final HSKModule module;
  final Map<String, List<File>> lessonFolders;
  final SharedPreferences prefs;

  const ChapterListScreen({
    super.key,
    required this.module,
    required this.lessonFolders,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final keys = lessonFolders.keys.toList();
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: Text("${module.levelTitle} • Only Audio")),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final folderName = keys[index];
          final tracks = lessonFolders[folderName]!;
          final displayTitle = folderName.replaceAll('-', ' ').toUpperCase();

          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: primary.withOpacity(0.12),
                child: Text("${index + 1}", style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
              ),
              title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${tracks.length} audio tracks"),
              trailing: Icon(Icons.play_circle_fill_rounded, color: primary, size: 32),
              onTap: () {
                prefs.setString('last_played', "${module.levelTitle} • $displayTitle");
                prefs.setString('last_module_id', module.id);
                prefs.setString('last_folder_key', folderName);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChapterAudioPlayerScreen(
                      moduleTitle: module.levelTitle,
                      chapterTitle: displayTitle,
                      tracks: tracks,
                      prefs: prefs,
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

class ChapterAudioPlayerScreen extends StatefulWidget {
  final String moduleTitle;
  final String chapterTitle;
  final List<File> tracks;
  final SharedPreferences prefs;

  const ChapterAudioPlayerScreen({
    super.key,
    required this.moduleTitle,
    required this.chapterTitle,
    required this.tracks,
    required this.prefs,
  });

  @override
  State<ChapterAudioPlayerScreen> createState() => _ChapterAudioPlayerScreenState();
}

class _ChapterAudioPlayerScreenState extends State<ChapterAudioPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();
  int currentIndex = 0;
  bool isPlaying = false;
  bool singleTrackLoop = false;
  late double speed;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    speed = widget.prefs.getDouble('default_speed') ?? 1.0;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _player.positionStream.listen((p) {
      if (mounted) setState(() => position = p);
    });
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => duration = d);
    });
    _player.playerStateStream.listen((state) async {
      if (!mounted) return;
      setState(() => isPlaying = state.playing);

      if (state.processingState == ProcessingState.completed) {
        if (singleTrackLoop) {
          await _playTrack(currentIndex);
        } else {
          final gapSec = widget.prefs.getInt('pause_gap') ?? 0;
          if (gapSec > 0) await Future.delayed(Duration(seconds: gapSec));
          final nextIndex = (currentIndex + 1) % widget.tracks.length;
          await _playTrack(nextIndex);
        }
      }
    });

    await _playTrack(0);
  }

  Future<void> _playTrack(int index) async {
    setState(() => currentIndex = index);
    await _player.setFilePath(widget.tracks[index].path);
    await _player.setSpeed(speed);
    await _player.play();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: Text("${widget.moduleTitle} • ${widget.chapterTitle}")),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: primary.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.repeat_rounded, size: 18, color: primary),
                const SizedBox(width: 8),
                Text(
                  "Chapter Loop Mode: Playing continuously until paused",
                  style: TextStyle(color: primary, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: widget.tracks.length,
              itemBuilder: (context, idx) {
                final fileName = widget.tracks[idx].uri.pathSegments.last.replaceAll('.mp3', '');
                final active = idx == currentIndex;
                return Card(
                  color: active ? primary.withOpacity(0.12) : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: active ? BorderSide(color: primary, width: 1.5) : BorderSide.none,
                  ),
                  child: ListTile(
                    leading: Icon(
                      active && isPlaying ? Icons.graphic_eq_rounded : Icons.audiotrack_rounded,
                      color: active ? primary : Colors.grey,
                    ),
                    title: Text(
                      "Track ${idx + 1}  ($fileName)",
                      style: TextStyle(fontWeight: active ? FontWeight.bold : FontWeight.normal),
                    ),
                    onTap: () => _playTrack(idx),
                  ),
                );
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -2))],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  activeColor: primary,
                  value: position.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble() + 1),
                  max: (duration.inMilliseconds.toDouble() > 0) ? duration.inMilliseconds.toDouble() : 1.0,
                  onChanged: (val) => _player.seek(Duration(milliseconds: val.toInt())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(position), style: const TextStyle(fontSize: 12)),
                      Text(_formatDuration(duration), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        const speeds = [0.75, 0.85, 1.0, 1.25];
                        final next = speeds[(speeds.indexOf(speed) + 1) % speeds.length];
                        setState(() => speed = next);
                        _player.setSpeed(speed);
                      },
                      child: Text("${speed}x", style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.replay_5_rounded),
                      tooltip: "Rewind 3s",
                      onPressed: () {
                        final target = position - const Duration(seconds: 3);
                        _player.seek(target < Duration.zero ? Duration.zero : target);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, size: 30),
                      onPressed: currentIndex > 0 ? () => _playTrack(currentIndex - 1) : null,
                    ),
                    FloatingActionButton(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      onPressed: () => isPlaying ? _player.pause() : _player.play(),
                      child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 30),
                      onPressed: currentIndex + 1 < widget.tracks.length ? () => _playTrack(currentIndex + 1) : null,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.repeat_one_rounded,
                        color: singleTrackLoop ? primary : Colors.grey,
                      ),
                      tooltip: "Repeat Current Track",
                      onPressed: () => setState(() => singleTrackLoop = !singleTrackLoop),
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

class PdfViewerScreen extends StatefulWidget {
  final String title;
  final String filePath;
  final SharedPreferences prefs;
  final Map<String, List<File>> lessonFolders;

  const PdfViewerScreen({
    super.key,
    required this.title,
    required this.filePath,
    required this.prefs,
    this.lessonFolders = const {},
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  final AudioPlayer _miniPlayer = AudioPlayer();

  late String pagePrefKey;
  int savedPage = 1;
  int currentPage = 1;

  bool showAudioPanel = true;
  String? selectedLesson;
  int trackIndex = 0;
  bool isPlaying = false;
  late double speed;

  @override
  void initState() {
    super.initState();
    final fileName = File(widget.filePath).uri.pathSegments.last;
    pagePrefKey = 'pdf_last_page_$fileName';
    savedPage = widget.prefs.getInt(pagePrefKey) ?? 1;
    currentPage = savedPage;
    speed = widget.prefs.getDouble('default_speed') ?? 1.0;

    if (widget.lessonFolders.isNotEmpty) {
      selectedLesson = widget.lessonFolders.keys.first;
    }

    _miniPlayer.playerStateStream.listen((state) async {
      if (!mounted) return;
      setState(() => isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed && selectedLesson != null) {
        final tracks = widget.lessonFolders[selectedLesson] ?? [];
        if (trackIndex + 1 < tracks.length) {
          await _playMiniTrack(trackIndex + 1);
        }
      }
    });
  }

  Future<void> _playMiniTrack(int index) async {
    if (selectedLesson == null) return;
    final tracks = widget.lessonFolders[selectedLesson] ?? [];
    if (index < 0 || index >= tracks.length) return;

    setState(() => trackIndex = index);
    await _miniPlayer.setFilePath(tracks[index].path);
    await _miniPlayer.setSpeed(speed);
    await _miniPlayer.play();
  }

  @override
  void dispose() {
    _miniPlayer.dispose();
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final hasLessons = widget.lessonFolders.isNotEmpty;
    final currentTracks = (hasLessons && selectedLesson != null)
        ? (widget.lessonFolders[selectedLesson] ?? [])
        : [];
    final currentTrackName = currentTracks.isNotEmpty
        ? currentTracks[trackIndex].uri.pathSegments.last.replaceAll('.mp3', '')
        : "";

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.title} (Page $currentPage)"),
        actions: [
          if (hasLessons)
            IconButton(
              icon: Icon(showAudioPanel ? Icons.headphones_rounded : Icons.headset_off_rounded),
              tooltip: showAudioPanel ? "Hide Audio Bar" : "Show Audio Bar",
              onPressed: () => setState(() => showAudioPanel = !showAudioPanel),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SfPdfViewer.file(
              File(widget.filePath),
              controller: _pdfController,
              onDocumentLoaded: (details) {
                if (savedPage > 1 && savedPage <= details.document.pages.count) {
                  _pdfController.jumpToPage(savedPage);
                }
              },
              onPageChanged: (details) {
                setState(() => currentPage = details.newPageNumber);
                widget.prefs.setInt(pagePrefKey, details.newPageNumber);
              },
            ),
          ),

          if (hasLessons && showAudioPanel)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  )
                ],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.menu_book_rounded, size: 18, color: primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            isDense: true,
                            value: selectedLesson,
                            items: widget.lessonFolders.keys.map((k) {
                              return DropdownMenuItem(
                                value: k,
                                child: Text(
                                  k.replaceAll('-', ' ').toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) async {
                              if (val != null) {
                                await _miniPlayer.stop();
                                setState(() {
                                  selectedLesson = val;
                                  trackIndex = 0;
                                  isPlaying = false;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currentTracks.isNotEmpty
                            ? "Track ${trackIndex + 1}/${currentTracks.length} ($currentTrackName)"
                            : "",
                        style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () {
                          const speeds = [0.75, 0.85, 1.0, 1.25];
                          final next = speeds[(speeds.indexOf(speed) + 1) % speeds.length];
                          setState(() => speed = next);
                          _miniPlayer.setSpeed(speed);
                        },
                        child: Text("${speed}x", style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.replay_5_rounded),
                        tooltip: "Rewind 3s",
                        onPressed: () {
                          final target = _miniPlayer.position - const Duration(seconds: 3);
                          _miniPlayer.seek(target < Duration.zero ? Duration.zero : target);
                        },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.skip_previous_rounded, size: 28),
                        onPressed: trackIndex > 0 ? () => _playMiniTrack(trackIndex - 1) : null,
                      ),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: primary,
                        child: IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          onPressed: () {
                            if (isPlaying) {
                              _miniPlayer.pause();
                            } else if (_miniPlayer.processingState == ProcessingState.idle) {
                              _playMiniTrack(trackIndex);
                            } else {
                              _miniPlayer.play();
                            }
                          },
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.skip_next_rounded, size: 28),
                        onPressed: trackIndex + 1 < currentTracks.length
                            ? () => _playMiniTrack(trackIndex + 1)
                            : null,
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

class PersonalGrammarScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const PersonalGrammarScreen({super.key, required this.prefs});

  @override
  State<PersonalGrammarScreen> createState() => _PersonalGrammarScreenState();
}

class _PersonalGrammarScreenState extends State<PersonalGrammarScreen> {
  List notes = [];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  void _loadNotes() {
    final raw = widget.prefs.getString('personal_pdfs');
    if (raw != null) {
      final List decoded = jsonDecode(raw);
      setState(() {
        notes = decoded.map((e) => Map<String, String>.from(e)).toList();
      });
    }
  }

  Future<void> _saveNotes() async {
    await widget.prefs.setString('personal_pdfs', jsonEncode(notes));
  }

  Future<void> _pickAndImportPdf() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      final sourceFile = File(result.files.single.path!);
      final dir = await getApplicationDocumentsDirectory();
      final notesDir = Directory('${dir.path}/personal_notes');
      if (!await notesDir.exists()) await notesDir.create(recursive: true);

      final fileName = result.files.single.name;
      final savedFile = await sourceFile.copy('${notesDir.path}/${DateTime.now().millisecondsSinceEpoch}_$fileName');

      setState(() {
        notes.add({'title': fileName.replaceAll('.pdf', ''), 'path': savedFile.path});
      });
      await _saveNotes();
    }
  }

  Future<void> _confirmAndDeleteNote(int idx) async {
    final item = notes[idx];
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete PDF?"),
        content: Text("Are you sure you want to delete '${item['title']}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      final f = File(item['path']!);
      if (await f.exists()) await f.delete();
      setState(() => notes.removeAt(idx));
      await _saveNotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text("My Grammar & Notes")),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        onPressed: _pickAndImportPdf,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text("Add PDF"),
      ),
      body: notes.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "No personal grammar PDFs added yet.\nTap '+ Add PDF' to import notes from your phone or SD card.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notes.length,
              itemBuilder: (context, idx) {
                final item = notes[idx];
                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf_rounded, color: primary),
                    title: Text(item['title']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                      onPressed: () => _confirmAndDeleteNote(idx),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfViewerScreen(
                            title: item['title']!,
                            filePath: item['path']!,
                            prefs: widget.prefs,
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

class StorageManagerScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const StorageManagerScreen({super.key, required this.prefs});

  @override
  State<StorageManagerScreen> createState() => _StorageManagerScreenState();
}

class _StorageManagerScreenState extends State<StorageManagerScreen> {
  bool loading = true;
  List> downloadedItems = [];

  @override
  void initState() {
    super.initState();
    _scanDownloads();
  }

  int _dirSize(Directory dir) {
    int total = 0;
    if (dir.existsSync()) {
      for (var entity in dir.listSync(recursive: true)) {
        if (entity is File) total += entity.lengthSync();
      }
    }
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 MB";
    final mb = bytes / (1024 * 1024);
    return "${mb.toStringAsFixed(1)} MB";
  }

  Future<void> _scanDownloads() async {
    setState(() => loading = true);
    final dir = await getApplicationDocumentsDirectory();
    List> items = [];

    for (var m in allModules) {
      final audioDir = Directory('${dir.path}/audios/${m.id}');
      final pdfFile = File('${dir.path}/pdfs/${m.pdfFileName}');

      final hasAudio = audioDir.existsSync() && audioDir.listSync(recursive: true).whereType<File>().isNotEmpty;
      final hasPdf = pdfFile.existsSync();

      if (hasAudio || hasPdf) {
        final audioBytes = hasAudio ? _dirSize(audioDir) : 0;
        final pdfBytes = hasPdf ? pdfFile.lengthSync() : 0;
        items.add({
          'module': m,
          'hasAudio': hasAudio,
          'hasPdf': hasPdf,
          'audioBytes': audioBytes,
          'pdfBytes': pdfBytes,
          'audioDir': audioDir,
          'pdfFile': pdfFile,
        });
      }
    }

    if (mounted) {
      setState(() {
        downloadedItems = items;
        loading = false;
      });
    }
  }

  Future<void> _deleteTarget({
    required String label,
    Directory? audioDir,
    File? pdfFile,
    String? moduleIdToClearHistory,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Offline Files?"),
        content: Text("Are you sure you want to delete $label? You can re-download it anytime."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (audioDir != null && await audioDir.exists()) {
        await audioDir.delete(recursive: true);
        if (moduleIdToClearHistory != null &&
            widget.prefs.getString('last_module_id') == moduleIdToClearHistory) {
          await widget.prefs.remove('last_played');
          await widget.prefs.remove('last_module_id');
          await widget.prefs.remove('last_folder_key');
        }
      }
      if (pdfFile != null && await pdfFile.exists()) {
        await pdfFile.delete();
      }
      await _scanDownloads();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text("Manage Offline Storage")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : downloadedItems.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "No downloaded HSK audio packs or textbooks found on your phone.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: downloadedItems.length,
                  itemBuilder: (context, idx) {
                    final item = downloadedItems[idx];
                    final HSKModule m = item['module'];
                    final bool hasAudio = item['hasAudio'];
                    final bool hasPdf = item['hasPdf'];
                    final int audioBytes = item['audioBytes'];
                    final int pdfBytes = item['pdfBytes'];
                    final int totalBytes = audioBytes + pdfBytes;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: primary.withOpacity(0.12),
                                      child: Text(m.chineseBadge, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primary)),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(m.levelTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        Text("Total: ${_formatBytes(totalBytes)}", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                      ],
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                                  tooltip: "Delete All for ${m.levelTitle}",
                                  onPressed: () => _deleteTarget(
                                    label: "all files for ${m.levelTitle}",
                                    audioDir: hasAudio ? item['audioDir'] : null,
                                    pdfFile: hasPdf ? item['pdfFile'] : null,
                                    moduleIdToClearHistory: m.id,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 18),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (hasAudio)
                                  ActionChip(
                                    avatar: const Icon(Icons.headphones_rounded, size: 16, color: Colors.red),
                                    label: Text("Delete Audio (${_formatBytes(audioBytes)})", style: const TextStyle(fontSize: 12)),
                                    onPressed: () => _deleteTarget(
                                      label: "${m.levelTitle} Audio Pack",
                                      audioDir: item['audioDir'],
                                      moduleIdToClearHistory: m.id,
                                    ),
                                  ),
                                if (hasPdf)
                                  ActionChip(
                                    avatar: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Colors.red),
                                    label: Text("Delete PDF (${_formatBytes(pdfBytes)})", style: const TextStyle(fontSize: 12)),
                                    onPressed: () => _deleteTarget(
                                      label: "${m.levelTitle} Textbook PDF",
                                      pdfFile: item['pdfFile'],
                                    ),
                                  ),
                              ],
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

class SettingsScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  const SettingsScreen({
    super.key,
    required this.prefs,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double defaultSpeed;
  late int pauseGap;
  int _photoPage = 0;

  final List<String> groupPhotos = const [
    'assets/group1.jpg',
    'assets/group2.jpg',
    'assets/group3.jpg',
  ];

  @override
  void initState() {
    super.initState();
    defaultSpeed = widget.prefs.getDouble('default_speed') ?? 1.0;
    pauseGap = widget.prefs.getInt('pause_gap') ?? 0;
  }

  Future<void> _launchExternal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open link")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text("Settings & About")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Appearance", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SwitchListTile(
            title: const Text("Night Study Dark Mode"),
            subtitle: const Text("Switch between Porcelain White and Dark Theme"),
            value: widget.isDarkMode,
            activeColor: primary,
            onChanged: widget.onThemeChanged,
          ),

          const Divider(),
          const Text("Audio Study Preferences", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ListTile(
            title: const Text("Default Playback Speed"),
            trailing: DropdownButton<double>(
              value: defaultSpeed,
              items: const [
                DropdownMenuItem(value: 0.75, child: Text("0.75x")),
                DropdownMenuItem(value: 0.85, child: Text("0.85x")),
                DropdownMenuItem(value: 1.0, child: Text("1.0x (Normal)")),
                DropdownMenuItem(value: 1.25, child: Text("1.25x")),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => defaultSpeed = v);
                  widget.prefs.setDouble('default_speed', v);
                }
              },
            ),
          ),
          ListTile(
            title: const Text("Pause Gap Between Tracks (Shadowing)"),
            subtitle: const Text("Extra pause in Only Audio mode to repeat aloud"),
            trailing: DropdownButton<int>(
              value: pauseGap,
              items: const [
                DropdownMenuItem(value: 0, child: Text("0 sec")),
                DropdownMenuItem(value: 1, child: Text("1 sec")),
                DropdownMenuItem(value: 2, child: Text("2 sec")),
                DropdownMenuItem(value: 3, child: Text("3 sec")),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => pauseGap = v);
                  widget.prefs.setInt('pause_gap', v);
                }
              },
            ),
          ),

          const Divider(),
          const Text("Offline Storage", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ListTile(
            leading: Icon(Icons.folder_delete_rounded, color: primary),
            title: const Text("Manage Offline Storage"),
            subtitle: const Text("Select and delete individual HSK levels, audio packs, or PDFs"),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StorageManagerScreen(prefs: widget.prefs)),
              );
            },
          ),

          const Divider(),
          const SizedBox(height: 8),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("About HSK", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary)),
                  const SizedBox(height: 10),
                  const Text(
                    "The first step to mastering Mandarin Chinese is tuning your ear to authentic native pronunciation, tones, and natural speech rhythm. HSK is designed as a clean, distraction-free companion for learners around the world—bringing structured HSK 1–6 textbook lessons, continuous chapter-by-chapter audio playback, and the ability to add your own personal grammar PDFs in one place.\n\n"
                    "Study at your own pace, repeat difficult dialogues effortlessly, and build real listening confidence.",
                    style: TextStyle(height: 1.5, fontSize: 14),
                  ),
                  const SizedBox(height: 14),
                  const Text("Curated & Initiated by: AHM", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => _launchExternal(developerFacebookUrl),
                      icon: const Icon(Icons.facebook_rounded),
                      label: const Text("Follow AHM on Facebook", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Mentors & Learning Community", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primary)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: PageView.builder(
                        itemCount: groupPhotos.length,
                        onPageChanged: (idx) => setState(() => _photoPage = idx),
                        itemBuilder: (context, idx) {
                          return Image.asset(groupPhotos[idx], fit: BoxFit.cover);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(groupPhotos.length, (idx) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _photoPage == idx ? 16 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _photoPage == idx ? primary : Colors.grey.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Guided & Mentored by:",
                    style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "Mr. Jaman & Mr. Mahabub",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Chinese Hatekhari",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Heartfelt gratitude to our respected teachers, Mr. Jaman and Mr. Mahabub, and the Chinese Hatekhari community, whose dedicated guidance, patience, and inspiration made our Mandarin learning journey possible.",
                    style: TextStyle(height: 1.45, fontSize: 13.5),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: BorderSide(color: primary, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => _launchExternal(academyFacebookUrl),
                      icon: const Icon(Icons.facebook_rounded),
                      label: const Text("Visit Chinese Hatekhari on Facebook", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
