"""Deterministic, one-face-only state-change logger for SafeZone AI Lite.

A log event means an observation episode / state change, NOT a unique person
and NOT a physical doorway entry. Unknown never means 'without_mask'.
"""
from dataclasses import dataclass

STATES = {'with_mask', 'without_mask', 'incorrect_mask', 'unknown'}


def normalize_class(label):
    """Map common YOLO mask labels to fixed statuses. Unrecognized => unknown."""
    key = str(label).lower().strip().replace('-', '_').replace(' ', '_')
    aliases = {
        'with_mask': 'with_mask', 'mask': 'with_mask', 'mask_on': 'with_mask',
        'without_mask': 'without_mask', 'no_mask': 'without_mask', 'mask_off': 'without_mask',
        'mask_weared_incorrect': 'incorrect_mask',
        'mask_worn_incorrect': 'incorrect_mask',
        'mask_weared_incorrectly': 'incorrect_mask',
        'incorrect_mask': 'incorrect_mask',
    }
    return aliases.get(key, 'unknown')


def event_category(status):
    if status == 'with_mask':
        return 'compliant'
    if status in ('without_mask', 'incorrect_mask'):
        return 'violation'
    return None


@dataclass
class MaskEvent:
    episode: int
    status: str
    outcome: str


class MaskEpisodeCounter:
    """Logs one event when a stable mask status CATEGORY changes.

    The demo assumes a single visible face. If it disappears for a sustained
    time, the session is re-armed, not personally re-identified.
    """
    def __init__(self, stable_frames=4, cooldown_seconds=2.0,
                 absent_reset_seconds=3.0):
        if stable_frames < 1 or cooldown_seconds < 0 or absent_reset_seconds <= 0:
            raise ValueError('Invalid stability/cooldown configuration')
        self.stable_frames = stable_frames
        self.cooldown_seconds = cooldown_seconds
        self.absent_reset_seconds = absent_reset_seconds
        self.candidate = None
        self.streak = 0
        self.last_logged_category = None
        self.last_event_time = None
        self.last_seen_time = None
        self.episode = 0

    def observe(self, status, now):
        if status not in STATES:
            raise ValueError(f'Unknown input status: {status}')
        if status == 'unknown':
            self.candidate = None
            self.streak = 0
            if self.last_seen_time is not None and now - self.last_seen_time >= self.absent_reset_seconds:
                self.last_logged_category = None
            return None

        # A detection after a long gap starts a new observation episode.
        if self.last_seen_time is not None and now - self.last_seen_time >= self.absent_reset_seconds:
            self.last_logged_category = None
            self.candidate = None
            self.streak = 0
        self.last_seen_time = now

        if status == self.candidate:
            self.streak += 1
        else:
            self.candidate = status
            self.streak = 1
        if self.streak < self.stable_frames:
            return None

        category = event_category(status)
        if category == self.last_logged_category:
            return None
        if self.last_event_time is not None and now - self.last_event_time < self.cooldown_seconds:
            return None

        self.last_logged_category = category
        self.last_event_time = now
        self.episode += 1
        return MaskEvent(episode=self.episode, status=status, outcome=category)
