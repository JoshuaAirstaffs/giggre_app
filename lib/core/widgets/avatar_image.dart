import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// A network avatar decoded at its on-screen size instead of the full photo
/// (a 24 px chat avatar was decoding a whole profile picture). Width only,
/// so the aspect ratio is kept for CircleAvatar's cover crop. Disk-cached
/// like any CachedNetworkImageProvider.
ImageProvider avatarImage(BuildContext context, String url, double radius) =>
    ResizeImage(
      CachedNetworkImageProvider(url),
      width: (radius * 2 * MediaQuery.devicePixelRatioOf(context)).ceil(),
      allowUpscaling: false,
    );
