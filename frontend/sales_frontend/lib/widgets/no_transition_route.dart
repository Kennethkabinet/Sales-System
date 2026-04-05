import 'package:flutter/material.dart';

PageRouteBuilder<T> noTransitionRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, __, ___, child) => child,
  );
}
