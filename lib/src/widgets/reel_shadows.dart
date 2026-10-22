import 'package:flutter/painting.dart';

/// A hard one-pixel shadow that keeps white text and icons readable on bright
/// video without a blur.
///
/// Blurred shadows look softer but cost far more: they are redrawn on every
/// frame while a post scrolls, and on a mid-range GPU a handful of them was the
/// difference between smooth and stuttering. A [ReelScrim] behind the text does
/// most of the work either way.
const List<Shadow> reelCheapShadow = <Shadow>[Shadow(offset: Offset(0, 1), color: Color(0x8C000000))];
