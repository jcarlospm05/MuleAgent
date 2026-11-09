import 'package:flutter/material.dart';

/// Estilo Mule: approved tokens, applied to screens in the UI stage.
abstract final class MulePalette {
  static const navy = Color(0xFF0B132B);
  static const deepBlue = Color(0xFF1C2541);
  static const mutedBlue = Color(0xFF3A506B);
  static const cyan = Color(0xFF5BC0DE);
  static const cream = Color(0xFFF4D6B0);
  static const orange = Color(0xFFD97706);
  static const lightBackground = Color(0xFFF8F6F3);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSecondaryText = Color(0xFF596273);
  static const lightBorder = Color(0xFFD7DADF);
  static const darkText = Color(0xFFF5F5F2);
  static const darkSecondaryText = Color(0xFFBBC5D3);
  static const darkBorder = Color(0xFF41516A);
  static const pending = Color(0xFFE53935);
  static const successLightBackground = Color(0xFFE0EBDC);
  static const successLightText = Color(0xFF355C43);
  static const successDarkBackground = Color(0xFF213C34);
  static const successDarkText = Color(0xFFB7D6BF);
}

abstract final class MuleMetrics {
  static const pageMargin = 24.0;
  static const spacingUnit = 8.0;
  static const componentGap = 16.0;
  static const secondaryGroupGap = 40.0;
  static const buttonRadius = 16.0;
  static const cardRadius = 16.0;
  static const fieldRadius = 12.0;
  static const borderWidth = 1.0;
  static const primaryMinHeight = 72.0;
  static const secondaryMinHeight = 48.0;
}

abstract final class MuleTypography {
  static const family = 'Roboto';
  static const brandSize = 24.0;
  static const titleSize = 30.0;
  static const sectionSize = 22.0;
  static const primaryButtonSize = 22.0;
  static const bodySize = 18.0;
  static const secondarySize = 16.0;
  static const auxiliarySize = 14.0;
  static const timeValueSize = 40.0;
}
