import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/download_helper.dart';
import '../../data/repositories/media_repository.dart';
import '../../domain/models/post.dart';

IconData resourceKindIcon(CirclePost r) {
  switch (r.kind) {
    case 'googleDoc':
      return Icons.description_outlined;
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'audio':
      return Icons.audiotrack_outlined;
    case 'video':
      return Icons.videocam_outlined;
    case 'link':
    default:
      return Icons.link;
  }
}

String resourceKindLabel(CirclePost r) {
  switch (r.kind) {
    case 'googleDoc':
      final status = r.meta['exportStatus']?.toString() ?? '';
      if (status == 'pending') return 'Converting to PDF…';
      if (status == 'failed') return 'PDF export failed';
      return 'Google Doc';
    case 'pdf':
      return 'PDF';
    case 'audio':
      return 'Audio';
    case 'video':
      return 'Video';
    case 'link':
      return 'Link';
    default:
      return 'Resource';
  }
}

String resourceTitle(CirclePost r) {
  if (r.body.trim().isNotEmpty) return r.body.trim();
  if (r.fileName != null && r.fileName!.isNotEmpty) return r.fileName!;
  final url = r.meta['url']?.toString();
  if (url != null && url.isNotEmpty) return url;
  return resourceKindLabel(r);
}

Future<void> openResourcePost(WidgetRef ref, CirclePost r) async {
  final kind = r.kind;
  if (kind == 'link' || kind == 'googleDoc' || kind.isEmpty) {
    final url = r.meta['url']?.toString() ?? r.body;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }
  final openUrl = r.mediaUrl;
  if (openUrl != null && openUrl.isNotEmpty) {
    final uri = Uri.tryParse(openUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
  }
  if (r.isPdfMedia || r.hasMediaRef) {
    final bytes = await ref.read(mediaRepositoryProvider).downloadBytes(
          storagePath: r.storagePath,
          downloadUrl: r.mediaUrl,
        );
    final name = r.fileName ??
        (r.isPdfMedia
            ? 'document.pdf'
            : r.isAudioMedia
                ? 'audio.m4a'
                : 'video.mp4');
    await saveOrShareFile(
      bytes: bytes,
      fileName: name,
      mimeType: r.meta['contentType']?.toString() ?? 'application/octet-stream',
    );
  }
}
