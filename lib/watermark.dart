import 'dart:math';
import 'package:flutter/material.dart';

// Diagonal repeated identity across confidential screens. Even inside
// a FLAG_SECURE app, a second phone can photograph the screen; the
// watermark makes that photo a signed confession.
class Watermark extends StatelessWidget {
  final String text;
  const Watermark({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, c) {
        return Transform.rotate(
          angle: -pi / 7,
          child: OverflowBox(
            maxWidth: c.maxWidth * 2,
            maxHeight: c.maxHeight * 2,
            child: Wrap(
              spacing: 42,
              runSpacing: 56,
              children: List.generate(
                60,
                (_) => Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.06),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
