import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'widgets.dart';

const _pad = EdgeInsets.fromLTRB(16, 4, 16, 32);

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
      setState(() {
        busy = true;
        result = null;
      });
      final r = await Api.queue('music', body);
      setState(() => result = {'id': r['id'], 'kind': 'music', 'status': 'PROCESSING', 'title': prompt.text.trim(), 'cost': r['quote']});
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
      section('Music'),
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
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Instrumental only'), value: instrumental, onChanged: (v) => setState(() => instrumental = v)),
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
      section('Image'),
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
      section('Video'),
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
  final text = TextEditingController();
  List<Map<String, dynamic>> voices = [];
  String? voice;
  PlatformFile? sample;
  bool consent = false;
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
      if (!mounted) return;
      setState(() {
        voices = v;
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
      section('Speak in your voice'),
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
        section('Library'),
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
