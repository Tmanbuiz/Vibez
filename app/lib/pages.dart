import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'widgets.dart';

const _pad = EdgeInsets.fromLTRB(16, 4, 16, 32);

Future<bool> confirmSingingConversion(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Convert the song to your singing voice?'),
      content: const Text(
        'Vibez sends your saved singing sample and the generated song to the configured SoulX-Singer service. '
        'It separates the lead vocal, converts the singer, and mixes the vocal back in. Your GPU host may charge compute fees.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
      ],
    ),
  );
  return result == true;
}

Widget studioHero({
  required IconData icon,
  required String eyebrow,
  required String title,
  required String subtitle,
}) {
  return Container(
    margin: const EdgeInsets.only(top: 10, bottom: 18),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF211633), Color(0xFF121826), Color(0xFF11121A)],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFF39304A)),
      boxShadow: const [
        BoxShadow(color: Color(0x221C0E31), blurRadius: 22, offset: Offset(0, 10)),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            gradient: const LinearGradient(
              colors: [Color(0xFFB55CFF), Color(0xFF36CFE8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 27),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(fontSize: 9, letterSpacing: 1.7, fontWeight: FontWeight.w800, color: Color(0xFFCDB2FF)),
              ),
              const SizedBox(height: 5),
              Text(title, style: const TextStyle(fontSize: 19, height: 1.12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFFB4B2C2))),
            ],
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- Music
class MusicPage extends StatefulWidget {
  const MusicPage({super.key});
  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  final prompt = TextEditingController();
  final lyrics = TextEditingController();
  List<ModelInfo> models = [];
  String? model;
  String? loadErr;
  int duration = 30;
  bool instrumental = false;
  bool revoiceWithSinger = false;
  List<Map<String, dynamic>> singers = [];
  String? singerId;
  bool busy = false;
  Map<String, dynamic>? result;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSingers();
    libraryTick.addListener(_loadSingers);
  }

  @override
  void dispose() {
    libraryTick.removeListener(_loadSingers);
    super.dispose();
  }

  Future<void> _loadSingers() async {
    if (!Api.ready) return;
    try {
      final list = await Api.singers();
      if (!mounted) return;
      setState(() {
        singers = list;
        if (singerId == null || !list.any((s) => s['id'] == singerId)) {
          singerId = list.isNotEmpty ? list.first['id'].toString() : null;
        }
      });
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _load() async {
    if (!Api.ready) return;
    try {
      final m = await Api.models('music');
      if (!mounted) return;
      setState(() {
        models = m;
        model = m.isNotEmpty ? m.first.id : null;
        loadErr = null;
      });
    } catch (e) {
      if (mounted) setState(() => loadErr = errText(e));
    }
  }

  Future<void> _run() async {
    if (!Api.ready) return snack(context, 'Add your Worker URL and token in Settings (top right).');
    if (model == null || prompt.text.trim().isEmpty) return snack(context, 'Pick a model and describe the song.');
    if (revoiceWithSinger && (singerId == null || singers.isEmpty)) {
      return snack(context, 'Create a singing profile under the Voice tab first.');
    }
    final shouldRevoice = revoiceWithSinger;
    final selectedSinger = singerId;
    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt.text.trim(),
      'duration_seconds': duration,
      if (lyrics.text.trim().isNotEmpty) 'lyrics_prompt': lyrics.text.trim(),
      if (instrumental) 'force_instrumental': true,
    };
    try {
      final q = await Api.quote('music', body);
      if (!mounted) return;
      if (!await confirmCost(context, q)) return;
      if (shouldRevoice && !await confirmSingingConversion(context)) return;
      setState(() {
        busy = true;
        result = null;
      });
      final r = await Api.queue('music', body);
      setState(() => result = {'id': r['id'], 'kind': 'music', 'status': 'PROCESSING', 'title': prompt.text.trim(), 'cost': r['quote']});
      libraryTick.value++;
      final done = await waitForJob(r['id'].toString(), cancelled: () => !mounted);
      if (!mounted) return;
      if (shouldRevoice) {
        final converted = await Api.revoice(done['id'].toString(), selectedSinger!);
        if (!mounted) return;
        setState(() => result = {
          'id': converted['id'],
          'kind': 'music',
          'status': 'PROCESSING',
          'title': converted['title'] ?? prompt.text.trim(),
        });
        libraryTick.value++;
        final finalSong = await waitForJob(converted['id'].toString(), cancelled: () => !mounted);
        if (!mounted) return;
        setState(() => result = finalSong);
      } else {
        setState(() => result = done);
      }
      libraryTick.value++;
    } catch (e) {
      if (mounted) snack(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: _pad, children: [
      studioHero(
        icon: Icons.graphic_eq_rounded,
        eyebrow: 'Music studio',
        title: 'Your sound, your story.',
        subtitle: 'Shape a vibe, add lyrics, and make a track that feels like you.',
      ),
      ModelPicker(models: models, value: model, error: loadErr, onChanged: (v) => setState(() => model = v)),
      const SizedBox(height: 12),
      TextField(controller: prompt, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Describe the song (style, mood, genre)')),
      const SizedBox(height: 12),
      TextField(controller: lyrics, minLines: 3, maxLines: 10, decoration: const InputDecoration(labelText: 'Lyrics (optional)')),
      const SizedBox(height: 12),
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Length'),
        for (final d in [15, 30, 60, 120])
          ChoiceChip(label: Text('${d}s'), selected: duration == d, onSelected: (_) => setState(() => duration = d)),
      ]),
      if (!instrumental)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sing in my voice'),
          subtitle: const Text('Convert the generated vocal using a saved singing sample.'),
          value: revoiceWithSinger,
          onChanged: busy ? null : (v) => setState(() => revoiceWithSinger = v),
        ),
      if (revoiceWithSinger && singers.isNotEmpty)
        DropdownButtonFormField<String>(
          value: singerId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Singing voice'),
          items: singers.map((s) => DropdownMenuItem(
            value: s['id'].toString(),
            child: Text(s['name'].toString(), overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: busy ? null : (v) => setState(() => singerId = v),
        ),
      if (revoiceWithSinger && singers.isEmpty)
        const Text('Add a singing profile under the Voice tab first.', style: TextStyle(color: Colors.white54)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Instrumental only'),
        value: instrumental,
        onChanged: busy ? null : (v) => setState(() {
          instrumental = v;
          if (v) revoiceWithSinger = false;
        }),
      ),
      FilledButton.icon(onPressed: busy ? null : _run, icon: const Icon(Icons.auto_awesome), label: Text(busy ? 'Generating…' : 'Create song')),
      if (result != null) MediaCard(item: result!),
    ]);
  }
}

// ---------------------------------------------------------------- Image
class ImagePage extends StatefulWidget {
  const ImagePage({super.key});
  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  final prompt = TextEditingController();
  final negative = TextEditingController();
  List<ModelInfo> models = [];
  String? model;
  String? loadErr;
  String aspect = 'Model default';
  bool busy = false;
  Map<String, dynamic>? result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Api.ready) return;
    try {
      final m = await Api.models('image');
      if (!mounted) return;
      setState(() {
        models = m;
        model = m.isNotEmpty ? m.first.id : null;
        loadErr = null;
      });
    } catch (e) {
      if (mounted) setState(() => loadErr = errText(e));
    }
  }

  Future<void> _run() async {
    if (!Api.ready) return snack(context, 'Add your Worker URL and token in Settings (top right).');
    if (model == null || prompt.text.trim().isEmpty) return snack(context, 'Pick a model and describe the image.');
    setState(() {
      busy = true;
      result = null;
    });
    try {
      final r = await Api.image({
        'model': model,
        'prompt': prompt.text.trim(),
        if (negative.text.trim().isNotEmpty) 'negative_prompt': negative.text.trim(),
        if (aspect != 'Model default') 'aspect_ratio': aspect,
      });
      if (!mounted) return;
      setState(() => result = {'id': r['id'], 'kind': 'image', 'status': 'DONE', 'title': prompt.text.trim()});
      libraryTick.value++;
    } catch (e) {
      if (mounted) snack(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: _pad, children: [
      studioHero(
        icon: Icons.auto_awesome_mosaic_rounded,
        eyebrow: 'Visual studio',
        title: 'Give the idea a look.',
        subtitle: 'Turn a short description into artwork for your next release.',
      ),
      ModelPicker(models: models, value: model, error: loadErr, onChanged: (v) => setState(() => model = v)),
      const SizedBox(height: 12),
      TextField(controller: prompt, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Describe the image')),
      const SizedBox(height: 12),
      TextField(controller: negative, decoration: const InputDecoration(labelText: 'Avoid (optional)')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: aspect,
        decoration: const InputDecoration(labelText: 'Aspect ratio'),
        items: const ['Model default', '1:1', '16:9', '9:16', '4:3', '3:4']
            .map((a) => DropdownMenuItem(value: a, child: Text(a)))
            .toList(),
        onChanged: (v) => setState(() => aspect = v ?? aspect),
      ),
      const SizedBox(height: 8),
      const Text('Some models only accept a fixed size. If you get an error, set this back to Model default.',
          style: TextStyle(color: Colors.white38, fontSize: 12)),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: busy ? null : _run, icon: const Icon(Icons.brush), label: Text(busy ? 'Generating…' : 'Create image')),
      if (result != null) MediaCard(item: result!),
    ]);
  }
}

// ---------------------------------------------------------------- Video
class VideoPage extends StatefulWidget {
  const VideoPage({super.key});
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final prompt = TextEditingController();
  List<ModelInfo> models = [];
  String? model;
  String? loadErr;
  String duration = '5s';
  String resolution = 'Default';
  String aspect = 'Model default';
  bool busy = false;
  Map<String, dynamic>? result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Api.ready) return;
    try {
      final m = await Api.models('video');
      if (!mounted) return;
      setState(() {
        models = m;
        model = m.isNotEmpty ? m.first.id : null;
        loadErr = null;
      });
    } catch (e) {
      if (mounted) setState(() => loadErr = errText(e));
    }
  }

  Future<void> _run() async {
    if (!Api.ready) return snack(context, 'Add your Worker URL and token in Settings (top right).');
    if (model == null || prompt.text.trim().isEmpty) return snack(context, 'Pick a model and describe the video.');
    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt.text.trim(),
      'duration': duration,
      if (resolution != 'Default') 'resolution': resolution,
      if (aspect != 'Model default') 'aspect_ratio': aspect,
    };
    try {
      final q = await Api.quote('video', body);
      if (!mounted) return;
      if (!await confirmCost(context, q)) return;
      setState(() {
        busy = true;
        result = null;
      });
      final r = await Api.queue('video', body);
      setState(() => result = {'id': r['id'], 'kind': 'video', 'status': 'PROCESSING', 'title': prompt.text.trim(), 'cost': r['quote']});
      libraryTick.value++;
      final done = await waitForJob(r['id'].toString(), cancelled: () => !mounted);
      if (!mounted) return;
      setState(() => result = done);
      libraryTick.value++;
    } catch (e) {
      if (mounted) snack(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: _pad, children: [
      studioHero(
        icon: Icons.movie_creation_outlined,
        eyebrow: 'Motion studio',
        title: 'Bring the scene to life.',
        subtitle: 'Describe a moment and create a short visual to go with your sound.',
      ),
      ModelPicker(models: models, value: model, error: loadErr, onChanged: (v) => setState(() => model = v)),
      const SizedBox(height: 12),
      TextField(controller: prompt, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Describe the video')),
      const SizedBox(height: 12),
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Length'),
        for (final d in ['5s', '10s'])
          ChoiceChip(label: Text(d), selected: duration == d, onSelected: (_) => setState(() => duration = d)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: resolution,
            decoration: const InputDecoration(labelText: 'Resolution'),
            items: const ['Default', '720p', '1080p'].map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
            onChanged: (v) => setState(() => resolution = v ?? resolution),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: aspect,
            decoration: const InputDecoration(labelText: 'Aspect'),
            items: const ['Model default', '16:9', '9:16', '1:1'].map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
            onChanged: (v) => setState(() => aspect = v ?? aspect),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: busy ? null : _run, icon: const Icon(Icons.movie_creation), label: Text(busy ? 'Generating…' : 'Create video')),
      if (result != null) MediaCard(item: result!),
    ]);
  }
}

// ---------------------------------------------------------------- Voice
class VoicePage extends StatefulWidget {
  const VoicePage({super.key});
  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final name = TextEditingController(text: 'My voice');
  final singerName = TextEditingController(text: 'My singing voice');
  final text = TextEditingController();
  List<Map<String, dynamic>> voices = [];
  List<Map<String, dynamic>> singerProfiles = [];
  String? voice;
  PlatformFile? sample;
  PlatformFile? singerSample;
  bool consent = false;
  bool singerConsent = false;
  bool busy = false;
  Map<String, dynamic>? result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Api.ready) return;
    try {
      final v = await Api.voices();
      final singerList = await Api.singers();
      if (!mounted) return;
      setState(() {
        voices = v;
        singerProfiles = singerList;
        final usable = v.where((x) => x['expired'] != true).toList();
        if (voice == null || !usable.any((x) => x['id'] == voice)) {
          voice = usable.isNotEmpty ? usable.first['id'].toString() : null;
        }
      });
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3', 'm4a', 'flac', 'mp4'],
      withData: true,
    );
    if (r != null && r.files.isNotEmpty) setState(() => sample = r.files.first);
  }

  Future<void> _pickSinger() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3', 'm4a', 'flac'],
      withData: true,
    );
    if (r != null && r.files.isNotEmpty) setState(() => singerSample = r.files.first);
  }

  Future<void> _createSinger() async {
    if (!Api.ready) return snack(context, 'Add your Worker URL and token in Settings (top right).');
    final f = singerSample;
    if (f == null || f.bytes == null) return snack(context, 'Choose a clean singing sample first.');
    setState(() => busy = true);
    try {
      await Api.createSinger(
        singerName.text.trim().isEmpty ? 'My singing voice' : singerName.text.trim(),
        f.bytes!,
        f.name,
      );
      if (!mounted) return;
      snack(context, 'Singing profile saved to your media bucket.');
      setState(() {
        singerSample = null;
        singerConsent = false;
      });
      await _load();
      libraryTick.value++;
    } catch (e) {
      if (mounted) snack(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _create() async {
    if (!Api.ready) return snack(context, 'Add your Worker URL and token in Settings (top right).');
    final f = sample;
    if (f == null || f.bytes == null) return snack(context, 'Choose a clean 5–10 second voice sample first.');
    setState(() => busy = true);
    try {
      await Api.createVoice(name.text.trim().isEmpty ? 'My voice' : name.text.trim(), f.bytes!, f.name);
      if (!mounted) return;
      snack(context, 'Voice created.');
      setState(() => sample = null);
      await _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _speak() async {
    if (voice == null || text.text.trim().isEmpty) return snack(context, 'Pick a voice and type some text.');
    setState(() {
      busy = true;
      result = null;
    });
    try {
      final r = await Api.speak(voice!, text.text.trim());
      if (!mounted) return;
      setState(() => result = {'id': r['id'], 'kind': 'speech', 'status': 'DONE', 'title': text.text.trim()});
      libraryTick.value++;
    } catch (e) {
      if (mounted) snack(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usable = voices.where((x) => x['expired'] != true).toList();
    return ListView(padding: _pad, children: [
      studioHero(
        icon: Icons.mic_none_rounded,
        eyebrow: 'Voice studio',
        title: 'Make it sound like you.',
        subtitle: 'Keep speech cloning and singing profiles separate, with clear controls for each.',
      ),
      if (usable.isEmpty)
        const Text('No voices yet. Add one below.', style: TextStyle(color: Colors.white54))
      else
        DropdownButtonFormField<String>(
          value: voice,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Voice'),
          items: usable
              .map((v) => DropdownMenuItem(value: v['id'].toString(), child: Text('${v['name']} · ${v['days_left']}d left')))
              .toList(),
          onChanged: (v) => setState(() => voice = v),
        ),
      const SizedBox(height: 12),
      TextField(controller: text, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'What should it say?')),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: busy ? null : _speak, icon: const Icon(Icons.record_voice_over), label: Text(busy ? 'Working…' : 'Generate speech')),
      if (result != null) MediaCard(item: result!),
      section('Clone a voice'),
      const Text('Upload one clean 5–10 second clip: one speaker, no music, no background noise. Voices last 7 days, then re-upload.',
          style: TextStyle(color: Colors.white54)),
      const SizedBox(height: 12),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Name this voice')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.upload_file), label: Text(sample?.name ?? 'Choose audio file')),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: consent,
        onChanged: (v) => setState(() => consent = v ?? false),
        title: const Text('This is my own voice, or the speaker clearly agreed.', style: TextStyle(fontSize: 14)),
      ),
      FilledButton(onPressed: (busy || !consent || sample == null) ? null : _create, child: const Text('Create voice')),
      section('Singing profile for songs'),
      const Text(
        'Upload 10–30 seconds of your own clean singing, preferably without music. This sample stays stored until you delete it. '
        'It is separate from the short voice clone used for speech.',
        style: TextStyle(color: Colors.white54),
      ),
      const SizedBox(height: 12),
      TextField(controller: singerName, decoration: const InputDecoration(labelText: 'Name this singing profile')),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _pickSinger,
        icon: const Icon(Icons.music_note),
        label: Text(singerSample?.name ?? 'Choose singing sample'),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: singerConsent,
        onChanged: (v) => setState(() => singerConsent = v ?? false),
        title: const Text('This is my voice, or I have the singer’s permission.', style: TextStyle(fontSize: 14)),
      ),
      FilledButton(
        onPressed: (busy || !singerConsent || singerSample == null) ? null : _createSinger,
        child: Text(busy ? 'Saving…' : 'Save singing profile'),
      ),
      if (singerProfiles.isNotEmpty) section('Saved singing profiles'),
      for (final s in singerProfiles)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s['name'].toString()),
          subtitle: const Text('Stored in your media bucket until deleted'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              try {
                await Api.deleteSinger(s['id'].toString());
                await _load();
                libraryTick.value++;
              } catch (e) {
                if (mounted) snack(context, errText(e));
              }
            },
          ),
        ),
      if (voices.isNotEmpty) section('Saved voices'),
      for (final v in voices)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(v['name'].toString()),
          subtitle: Text(v['expired'] == true ? 'Expired' : '${v['days_left']} days left'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              try {
                await Api.deleteVoice(v['id'].toString());
                await _load();
              } catch (e) {
                if (mounted) snack(context, errText(e));
              }
            },
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- Library
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<Map<String, dynamic>> items = [];
  bool loading = false;
  String filter = 'all';

  @override
  void initState() {
    super.initState();
    libraryTick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    libraryTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!Api.ready) return;
    setState(() => loading = true);
    try {
      var list = await Api.library();
      // advance any jobs that finished while the app was closed
      var changed = false;
      // (only jobs older than 90s, so we never race the create page's own polling)
      final cutoff = DateTime.now().millisecondsSinceEpoch - 90000;
      for (final it in list.where((x) => x['status'] == 'PROCESSING' && ((x['created'] as num?) ?? 0) < cutoff)) {
        try {
          await Api.job(it['id'].toString());
          changed = true;
        } catch (_) {}
      }
      if (changed) list = await Api.library();
      if (mounted) setState(() => items = list);
    } catch (e) {
      if (mounted) snack(context, errText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = filter == 'all' ? items : items.where((x) => x['kind'] == filter).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: _pad, children: [
        studioHero(
          icon: Icons.library_music_rounded,
          eyebrow: 'Your library',
          title: 'All your creations, together.',
          subtitle: 'Pick up where you left off and replay finished tracks.',
        ),
        Wrap(spacing: 8, children: [
          for (final k in ['all', 'music', 'image', 'video', 'speech'])
            ChoiceChip(label: Text(k), selected: filter == k, onSelected: (_) => setState(() => filter = k)),
        ]),
        if (loading) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (!loading && shown.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('Nothing here yet.', style: TextStyle(color: Colors.white54)))),
        for (final it in shown)
          MediaCard(
            key: ValueKey(it['id']),
            item: it,
            onDelete: () async {
              try {
                await Api.deleteItem(it['id'].toString());
                await _load();
              } catch (e) {
                if (mounted) snack(context, errText(e));
              }
            },
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Settings
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final url = TextEditingController(text: Api.base);
  final token = TextEditingController(text: Api.token);
  String status = '';

  Future<void> _save() async {
    await Api.save(url.text, token.text);
    setState(() => status = 'Testing…');
    try {
      await Api.library();
      setState(() => status = 'Connected ✓');
      libraryTick.value++;
    } catch (e) {
      setState(() => status = 'Could not connect: ${errText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Point the app at your deployed Cloudflare Worker.', style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 16),
        TextField(
          controller: url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Worker URL', hintText: 'https://tmanvibez-ai-api.<you>.workers.dev'),
        ),
        const SizedBox(height: 12),
        TextField(controller: token, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'App token (APP_TOKEN)')),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save & test')),
        const SizedBox(height: 12),
        Text(status),
      ]),
    );
  }
}
