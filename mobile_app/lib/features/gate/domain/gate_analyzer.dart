import '../../detection/domain/detection_result.dart';
import '../../models/domain/model_entry.dart';
import '../../safety/domain/safety_decision.dart';
import '../../safety/domain/safety_policy.dart';
import 'gate_episode.dart';

abstract class GateAnalyzer {
  RoiRect get doorwayRoi;
  void setDoorwayRoi(RoiRect roi);

  /// Consumes frame detections at [timestampMs].
  /// Returns a completed [PassageEpisode] ONLY when an episode finishes,
  /// preventing duplicate counting of every video frame.
  PassageEpisode? consumeFrameDetections({
    required List<DetectionResult> detections,
    required ModelProfile profile,
    required int timestampMs,
  });

  /// Forces closing an open episode if the stream stops or gap exceeds maxGapMs.
  PassageEpisode? flushOpenEpisode({
    required ModelProfile profile,
    required int currentTimestampMs,
  });

  List<PassageEpisode> get completedEpisodes;
  void resetEpisodes();
}

/// GateModeProcessor (Phase 05 Deliverable):
/// Aggregates frame-by-frame detections inside the doorway ROI into single passage episodes.
/// - Separates sequential passes when time gap > profile.maxGapMs
/// - Aggregates confidence and class votes across frames
/// - Emits REVIEW when evidenceFrames < profile.minEvidenceFrames or votes conflict
/// - Never claims biometric identity recognition
class GateModeProcessor implements GateAnalyzer {
  final SafetyPolicy _safetyPolicy;
  RoiRect _doorwayRoi;

  int? _openStartMs;
  int? _lastSeenMs;
  int _episodeCounter = 0;
  final List<SafetyDecision> _openFrameDecisions = [];
  final List<PassageEpisode> _completed = [];

  GateModeProcessor({
    SafetyPolicy safetyPolicy = const DefaultSafetyPolicy(),
    RoiRect initialRoi = const RoiRect(),
  })  : _safetyPolicy = safetyPolicy,
        _doorwayRoi = initialRoi;

  @override
  RoiRect get doorwayRoi => _doorwayRoi;

  @override
  void setDoorwayRoi(RoiRect roi) {
    _doorwayRoi = roi;
  }

  @override
  List<PassageEpisode> get completedEpisodes => List.unmodifiable(_completed);

  @override
  PassageEpisode? consumeFrameDetections({
    required List<DetectionResult> detections,
    required ModelProfile profile,
    required int timestampMs,
  }) {
    PassageEpisode? emittedFromClosedPrevious;

    // 1. Check if an open episode has timed out (gap > profile.maxGapMs)
    if (_openStartMs != null &&
        _lastSeenMs != null &&
        (timestampMs - _lastSeenMs!) > profile.maxGapMs) {
      emittedFromClosedPrevious = _finalizeOpenEpisode(profile);
    }

    // 2. Filter detections inside the Doorway ROI
    final inRoi =
        detections.where((d) => _doorwayRoi.containsCenterOf(d.bbox)).toList();

    if (inRoi.isEmpty) {
      return emittedFromClosedPrevious;
    }

    // 3. Evaluate frame decision using SafetyPolicy
    final frameDecision = _safetyPolicy.decide(
      detections: inRoi,
      profile: profile,
      timestampMs: timestampMs,
    );

    _openStartMs ??= timestampMs;
    _lastSeenMs = timestampMs;
    _openFrameDecisions.add(frameDecision);

    return emittedFromClosedPrevious;
  }

  @override
  PassageEpisode? flushOpenEpisode({
    required ModelProfile profile,
    required int currentTimestampMs,
  }) {
    if (_openStartMs == null || _openFrameDecisions.isEmpty) {
      return null;
    }
    return _finalizeOpenEpisode(profile);
  }

  PassageEpisode _finalizeOpenEpisode(ModelProfile profile) {
    _episodeCounter++;
    final epId = 'gate-ep-${_episodeCounter.toString().padLeft(3, '0')}';
    final startMs = _openStartMs!;
    final endMs = _lastSeenMs ?? startMs;
    final totalFrames = _openFrameDecisions.length;

    var compliantVotes = 0;
    var violationVotes = 0;
    var reviewVotes = 0;
    var confidenceSum = 0.0;
    var confidenceCount = 0;
    final labelCounts = <String, int>{};

    for (final d in _openFrameDecisions) {
      switch (d.status) {
        case SafetyStatus.compliant:
          compliantVotes++;
          break;
        case SafetyStatus.violation:
          violationVotes++;
          break;
        case SafetyStatus.review:
          reviewVotes++;
          break;
      }
      if (d.representativeConfidence != null) {
        confidenceSum += d.representativeConfidence!;
        confidenceCount++;
      }
      if (d.dominantLabel != null) {
        labelCounts[d.dominantLabel!] =
            (labelCounts[d.dominantLabel!] ?? 0) + 1;
      }
    }

    final avgConfidence =
        confidenceCount > 0 ? (confidenceSum / confidenceCount) : 0.0;
    String dominantLabel = 'unknown';
    if (labelCounts.isNotEmpty) {
      dominantLabel =
          labelCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    SafetyStatus finalStatus;
    PassageEpisodeType episodeType;
    String explanation;

    if (totalFrames < profile.minEvidenceFrames) {
      finalStatus = SafetyStatus.review;
      episodeType = PassageEpisodeType.insufficientEvidence;
      explanation =
          'عدد إطارات الدليل ($totalFrames) أقل من الحد الأدنى المطلوب (${profile.minEvidenceFrames}) — يُسجّل كمراجعة (REVIEW).';
    } else if (violationVotes > compliantVotes &&
        violationVotes >= profile.minEvidenceFrames) {
      finalStatus = SafetyStatus.violation;
      episodeType = PassageEpisodeType.faceVisibilityEpisode;
      explanation =
          'مرور مرصود بمخالفة ($dominantLabel) عبر $totalFrames إطارات متتابعة.';
    } else if (compliantVotes > violationVotes &&
        compliantVotes >= profile.minEvidenceFrames) {
      finalStatus = SafetyStatus.compliant;
      episodeType = PassageEpisodeType.faceVisibilityEpisode;
      explanation =
          'مرور مرصود بالتزام ($dominantLabel) عبر $totalFrames إطارات متتابعة.';
    } else {
      finalStatus = SafetyStatus.review;
      episodeType = PassageEpisodeType.insufficientEvidence;
      explanation =
          'تعارض أو عدم كفاية الأدلة خلال المرور ($compliantVotes ملتزم / $violationVotes مخالف / $reviewVotes مراجعة).';
    }

    final episode = PassageEpisode(
      episodeId: epId,
      startedAtMs: startMs,
      endedAtMs: endMs,
      finalStatus: finalStatus,
      dominantLabel: dominantLabel,
      aggregatedConfidence: avgConfidence,
      evidenceFrames: totalFrames,
      episodeType: episodeType,
      explanationAr: explanation,
    );

    _completed.add(episode);
    _openStartMs = null;
    _lastSeenMs = null;
    _openFrameDecisions.clear();

    return episode;
  }

  @override
  void resetEpisodes() {
    _openStartMs = null;
    _lastSeenMs = null;
    _openFrameDecisions.clear();
    _completed.clear();
    _episodeCounter = 0;
  }
}
