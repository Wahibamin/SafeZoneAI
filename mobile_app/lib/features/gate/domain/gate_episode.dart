import '../../detection/domain/detection_result.dart';
import '../../safety/domain/safety_decision.dart';

/// Distinguishes between a face visibility episode in doorway ROI
/// vs an unverified single frame (ROADMAP P05).
enum PassageEpisodeType {
  faceVisibilityEpisode, // ظهور وجه مرصود داخل نطاق البوابة
  insufficientEvidence, // ظهور عابر أقل من الحد الأدنى للأدلة (يُصنف REVIEW)
}

class RoiRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const RoiRect({
    this.left = 0.15,
    this.top = 0.10,
    this.right = 0.85,
    this.bottom = 0.90,
  });

  bool containsCenterOf(NormalizedBox box) {
    final cx = box.centerX;
    final cy = box.centerY;
    return cx >= left && cx <= right && cy >= top && cy <= bottom;
  }
}

class PassageEpisode {
  final String episodeId;
  final int startedAtMs;
  final int endedAtMs;
  final SafetyStatus finalStatus;
  final String dominantLabel;
  final double aggregatedConfidence;
  final int evidenceFrames;
  final PassageEpisodeType episodeType;
  final String explanationAr;

  const PassageEpisode({
    required this.episodeId,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.finalStatus,
    required this.dominantLabel,
    required this.aggregatedConfidence,
    required this.evidenceFrames,
    required this.episodeType,
    required this.explanationAr,
  });

  int get durationMs => (endedAtMs - startedAtMs).clamp(0, 3600000);
}
