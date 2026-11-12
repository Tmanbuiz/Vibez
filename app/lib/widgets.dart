import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';

/// Bump this to make the Library tab reload.
final ValueNotifier<int> libraryTick = ValueNotifier<int>(0);

void snack(BuildContext c, String msg) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
}

/// Shows the price and asks before any money is spent. Returns true to go ahead.
Future<bool> confirmCost(BuildContext c, Map<String, dynamic> q) async {
  final quote = (q['quote'] as num).toDouble();
  final limit = (q['limit'] as num?)?.toDouble() ?? 1.0;
  if (quote > limit) {
    snack(c, 'Quote \$${quote.toStringAsFixed(2)} is over your \$${limit.toStringAsFixed(2)} per-job limit.');
    return false;
  }
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm cost'),
      content: Text('This will cost about \$${quote.toStringAsFixed(2)}.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Generate')),
      ],
    ),
  );
  return r == true;
}

/// Polls a music/video job until it is DONE (or throws if it FAILED).
Future<Map<String, dynamic>> waitForJob(
  String id, {
  void Function(Map<String, dynamic>)? onTick,
  bool Function()? cancelled,
}) async {
  var errors = 0;
  while (true) {
    await Future.delayed(const Duration(seconds: 4));
    if (cancelled != null && cancelled()) throw ApiError('Cancelled', 0);
    try {
      final j = await Api.job(id);
      errors = 0;
      onTick?.call(j);
      final s = j['status'];
      if (s == 'DONE') return j;
      if (s == 'FAILED') throw ApiError(j['error']?.toString() ?? 'Generation failed', 0);
    } on ApiError {
      rethrow;
    } catch (_) {
      errors++;
      if (errors >= 4) rethrow;
    }
  }
}

Widget section(String t) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(t.toUpperCase(),
          style: const TextStyle(fontSize: 12, letterSpacing: 1.2, color: Colors.white54, fontWeight: FontWeight.w600)),
    );

IconData kindIcon(String k) {
  switch (k) {
    case 'music':
      return Icons.music_note;
    case 'image':
      return Icons.image;
    case 'video':
      return Icons.movie;
    default:
      return Icons.record_voice_over;
  }
}

class MediaCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onDelete;
  const MediaCard({super.key, required this.item, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final id = item['id'].toString();
    final kind = (item['kind'] ?? '').toString();
    final status = (item['status'] ?? '').toString();
    final cost = item['cost'];
    Widget body;
    if (status == 'FAILED') {
      body = Text(item['error']?.toString() ?? 'Failed', style: const TextStyle(color: Colors.redAccent));
    } else if (status != 'DONE') {
      body = const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LinearProgressIndicator(),
        SizedBox(height: 6),
        Text('Generating… this can take a minute or two.', style: TextStyle(color: Colors.white54)),
      ]);
    } else if (kind == 'image') {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(Api.mediaUrl(id), fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('Could not load image')),
      );
    } else if (kind == 'video') {
      body = VideoTile(url: Api.mediaUrl(id));
    } else {
      body = AudioTile(url: Api.mediaUrl(id));
    }
    return Container(
      key: ValueKey('card-$id'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF14151F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF292838)),
        boxShadow: const [BoxShadow(color: Color(0x16000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF261C37),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(kindIcon(kind), size: 18, color: const Color(0xFFD6B5FF)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              (item['title'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
            ),
          ),
          if (cost is num) Text('\$${cost.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white54)),
        ]),
        const SizedBox(height: 10),
        body,
        if (status == 'DONE' || onDelete != null)
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (status == 'DONE')
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(Api.mediaUrl(id)), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Open / save'),
              ),
            if (onDelete != null)
              IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 20)),
          ]),
      ]),
    );
  }
}

class AudioTile extends StatefulWidget {
  final String url;
  const AudioTile({super.key, required this.url});
  @override
  State<AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<AudioTile> {
  final AudioPlayer _p = AudioPlayer();
  bool playing = false;
  bool loaded = false;
  Duration pos = Duration.zero;
  Duration dur = Duration.zero;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(_p.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => playing = s == PlayerState.playing);
    }));
    _subs.add(_p.onPositionChanged.listen((d) {
      if (mounted) setState(() => pos = d);
    }));
    _subs.add(_p.onDurationChanged.listen((d) {
      if (mounted) setState(() => dur = d);
    }));
    _subs.add(_p.onPlayerComplete.listen((_) {
      if (mounted) setState(() {
        playing = false;
        loaded = false;
        pos = Duration.zero;
      });
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (playing) {
      await _p.pause();
    } else if (loaded) {
      await _p.resume();
    } else {
      loaded = true;
      await _p.play(UrlSource(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
    final double val = pos.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
    return Row(children: [
      IconButton.filledTonal(
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF35204B),
          foregroundColor: const Color(0xFFE5C7FF),
        ),
        onPressed: _toggle,
        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
      Expanded(
        child: Slider(
          value: val,
          max: max,
          onChanged: loaded ? (v) => _p.seek(Duration(milliseconds: v.toInt())) : null,
        ),
      ),
    ]);
  }
}

class VideoTile extends StatefulWidget {
  final String url;
  const VideoTile({super.key, required this.url});
  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  late final VideoPlayerController c;
  bool ready = false;
  String? err;

  @override
  void initState() {
    super.initState();
    c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    c.addListener(() {
      if (mounted) setState(() {});
    });
    c.initialize().then((_) {
      if (mounted) setState(() => ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => err = e.toString());
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (err != null) return Text('Could not play video: $err');
    if (!ready) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
      ),
      Row(children: [
        IconButton(
          onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
          icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
        ),
        Expanded(child: VideoProgressIndicator(c, allowScrubbing: true)),
      ]),
    ]);
  }
}

/// Dropdown of Venice models for a given type, loaded from your Worker.
class ModelPicker extends StatelessWidget {
  final List<ModelInfo> models;
  final String? value;
  final String? error;
  final ValueChanged<String?> onChanged;
  const ModelPicker({super.key, required this.models, required this.value, required this.onChanged, this.error});

  @override
  Widget build(BuildContext context) {
    if (error != null) return Text('Could not load models: $error', style: const TextStyle(color: Colors.redAccent));
    if (models.isEmpty) return const LinearProgressIndicator();
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Model'),
      items: models.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }
}
