import 'package:flutter/material.dart';

extension ThemeDataExt on ThemeData {
  Color get cardColorWithElevation {
    return ElevationOverlay.applySurfaceTint(cardColor, colorScheme.surfaceTint, 1);
  }
}
