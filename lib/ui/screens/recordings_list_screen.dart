import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../models/recording_model.dart';
import '../../services/recording_storage_service.dart';
import 'sound_detail_screen.dart';

class RecordingsListScreen extends StatefulWidget {
  final VoidCallback onGoToRecordTab;

  const RecordingsListScreen({
    super.key,
    required this.onGoToRecordTab,
  });

  @override
  State<RecordingsListScreen> createState() => _RecordingsListScreenState();
}

class _RecordingsListScreenState extends State<RecordingsListScreen> {
  final RecordingStorageService _storageService = RecordingStorageService();
  final AudioPlayer _inlinePlayer = AudioPlayer();

  List<RecordingModel> _recordings = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _currentlyPlayingId;

  @override
  void initState() {
    super.initState();
    _loadRecordings();

    _inlinePlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _currentlyPlayingId = null);
      }
    });
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    final list = await _storageService.loadRecordings();
    if (mounted) {
      setState(() {
        _recordings = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleInlinePlay(RecordingModel recording) async {
    if (_currentlyPlayingId == recording.id) {
      await _inlinePlayer.stop();
      setState(() => _currentlyPlayingId = null);
    } else {
      await _inlinePlayer.stop();
      final fileToPlay = recording.hasCleanedVersion ? recording.cleanedFile! : recording.rawFile;
      if (await fileToPlay.exists()) {
        await _inlinePlayer.play(DeviceFileSource(fileToPlay.path));
        setState(() => _currentlyPlayingId = recording.id);
      }
    }
  }

  void _openSoundDetail(RecordingModel recording) async {
    await _inlinePlayer.stop();
    setState(() => _currentlyPlayingId = null);

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => SoundDetailScreen(
          recording: recording,
          onRecordingChanged: _loadRecordings,
        ),
      ),
    );

    _loadRecordings();
  }

  Future<void> _deleteRecording(RecordingModel recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recording?'),
        content: Text('Delete "${recording.title}" and its associated files?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_currentlyPlayingId == recording.id) {
        await _inlinePlayer.stop();
        _currentlyPlayingId = null;
      }
      await _storageService.deleteRecording(recording);
      _loadRecordings();
    }
  }

  @override
  void dispose() {
    _inlinePlayer.dispose();
    super.dispose();
  }

  List<RecordingModel> get _filteredRecordings {
    if (_searchQuery.isEmpty) return _recordings;
    return _recordings.where((r) {
      return r.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.formattedDate.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredRecordings;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        title: const Text(
          'Recordings',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadRecordings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _recordings.isEmpty
              ? _buildEmptyState(colorScheme)
              : Column(
                  children: [
                    // Minimalist Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        decoration: InputDecoration(
                          hintText: 'Search recordings...',
                          hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
                          prefixIcon: Icon(Icons.search_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                          isDense: true,
                          filled: true,
                          fillColor: colorScheme.surfaceVariant.withOpacity(0.35),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),

                    // Header counter
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 4.0),
                      child: Row(
                        children: [
                          Text(
                            '${filtered.length} ${filtered.length == 1 ? "SOUND" : "SOUNDS"} RECORDED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // List of recordings
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadRecordings,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final recording = filtered[index];
                            final bool isPlaying = _currentlyPlayingId == recording.id;

                            return _buildRecordingCard(recording, isPlaying, colorScheme);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildRecordingCard(RecordingModel recording, bool isPlaying, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlaying ? colorScheme.primary : colorScheme.outlineVariant.withOpacity(0.4),
          width: isPlaying ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openSoundDetail(recording),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                // Quick Play Button
                GestureDetector(
                  onTap: () => _toggleInlinePlay(recording),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPlaying
                          ? colorScheme.primary
                          : (recording.hasCleanedVersion ? const Color(0xFF00897B).withOpacity(0.12) : colorScheme.surfaceVariant.withOpacity(0.5)),
                    ),
                    child: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: isPlaying
                          ? Colors.white
                          : (recording.hasCleanedVersion ? const Color(0xFF00897B) : colorScheme.onSurface),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Title & Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              recording.title,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (recording.hasCleanedVersion) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '10x ✨',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${recording.formattedDate} • ${recording.formattedDuration} • ${recording.formattedFileSize}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // More Options / Delete popup
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                  onSelected: (val) {
                    if (val == 'open') {
                      _openSoundDetail(recording);
                    } else if (val == 'delete') {
                      _deleteRecording(recording);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          Icon(Icons.analytics_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Open & Compare'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                          SizedBox(width: 10),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.surfaceVariant.withOpacity(0.4),
              ),
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 56,
                color: colorScheme.primary.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Recordings Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Your recorded auscultation sounds will be saved here for playback, 10x amplification, and ML diagnostics.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: widget.onGoToRecordTab,
              icon: const Icon(Icons.mic_rounded, size: 18),
              label: const Text('Record Lung Sound'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
