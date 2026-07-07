import 'dart:math';
import 'package:flutter/material.dart';

// A DENSE diagonal flood of the reader's identity across confidential
// content. Repeated many times, overlapping the material, so a photo
// taken with a second phone is drenched in the leaker's name and matric
// and cannot be cropped clean. Inside the app screenshots are already
// blocked (FLAG_SECURE); this defeats the second-camera trick too.
class Watermark extends StatelessWidget {
  final String text;
  const Watermark({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = (dark ? Colors.white : Colors.black).withOpacity(0.10);
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, c) {
        return Transform.rotate(
          angle: -pi / 6.5,
          child: OverflowBox(
            maxWidth: c.maxWidth * 2.2,
            maxHeight: c.maxHeight * 2.2,
            child: Wrap(
              spacing: 26,
              runSpacing: 34,
              children: List.generate(
                180,
                (_) => Text(
                  text,
                  style: TextStyle(
                    color: ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
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
