import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/rows.dart';

/// A small preview of a screenshot. Decodes at reduced size so long lists stay smooth.
class ImageThumb extends ConsumerWidget {
  const ImageThumb({super.key, required this.image, this.size, this.onTap});

  final Rec image;
  final double? size;
  final VoidCallback? onTap;

  Widget _placeholder(BuildContext context, IconData icon) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(icon, color: Theme.of(context).colorScheme.outline),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(imageStoreProvider);
    final rel = image.sn('local_path');
    final Widget content = rel == null
        ? _placeholder(context, Icons.cloud_download_outlined)
        : Image.file(
            File(store.absolutePath(rel)),
            fit: BoxFit.cover,
            cacheWidth: 360,
            errorBuilder: (_, __, ___) => _placeholder(context, Icons.broken_image_outlined),
          );
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: size, height: size, child: content),
      ),
    );
  }
}
