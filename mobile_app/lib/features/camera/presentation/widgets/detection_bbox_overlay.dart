import 'package:flutter/material.dart';
import '../../../detection/domain/detection_result.dart';
import '../../../safety/domain/safety_decision.dart';

class DetectionBboxOverlay extends StatelessWidget {
  final List<DetectionResult> detections;
  final SafetyStatus overallStatus;
  final bool mirrored;

  const DetectionBboxOverlay({
    super.key,
    required this.detections,
    required this.overallStatus,
    this.mirrored = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: detections.map((d) {
            final left = (mirrored ? 1 - d.bbox.right : d.bbox.left) *
                constraints.maxWidth;
            final top = d.bbox.top * constraints.maxHeight;
            final width = d.bbox.width * constraints.maxWidth;
            final height = d.bbox.height * constraints.maxHeight;

            final Color boxColor;
            if (d.label == 'with_mask' && d.confidence >= 0.45) {
              boxColor = const Color(0xFFB8F66A);
            } else if (d.confidence < 0.45) {
              boxColor = const Color(0xFFF5CA74);
            } else {
              boxColor = const Color(0xFFFF8699);
            }

            return Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: boxColor, width: 2.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.topRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: boxColor.withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    '${d.label} ${(d.confidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Color(0xFF080E19),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
