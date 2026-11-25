"""Pure Python rule engine: no YOLO/OpenCV dependency.

An entry is counted only when a tracked person was first seen outside a zone,
then remains inside long enough. One record per entrance, not per video frame.
Unknown visual evidence never becomes an asserted violation.
"""
from collections import deque
from dataclasses import dataclass, field


def point_in_polygon(point, polygon):
    x, y = point
    inside = False
    n = len(polygon)
    for i in range(n):
        x1, y1 = polygon[i]
        x2, y2 = polygon[(i + 1) % n]
        if ((y1 > y) != (y2 > y)) and (x < (x2-x1)*(y-y1)/(y2-y1)+x1):
            inside = not inside
    return inside


@dataclass
class Visit:
    seen_outside: bool = False
    inside_streak: int = 0
    outside_streak: int = 0
    active: bool = False
    committed: bool = False
    episode: int = 0
    age: int = 0
    votes: dict = field(default_factory=dict)
    last_frame: int = 0


class EntryEngine:
    def __init__(self, zones, min_inside=3, min_outside=3,
                 min_votes=3, max_pending_frames=35, vote_window=12):
        self.zones = zones
        self.min_inside = min_inside
        self.min_outside = min_outside
        self.min_votes = min_votes
        self.max_pending_frames = max_pending_frames
        self.vote_window = vote_window
        self.state = {}

    def _decision(self, st, required):
        statuses = {}
        for item in required:
            values = list(st.votes.get(item, []))
            good = values.count('yes')
            bad = values.count('no')
            total = good + bad
            if total < self.min_votes:
                statuses[item] = 'unknown'
            elif bad / total >= 0.70:
                statuses[item] = 'no'
            elif good / total >= 0.70:
                statuses[item] = 'yes'
            else:
                statuses[item] = 'unknown'
        if 'no' in statuses.values():
            return 'violation', statuses
        if all(v == 'yes' for v in statuses.values()):
            return 'compliant', statuses
        return None, statuses

    def observe(self, track_id, footpoint, observations, frame_no):
        """Return list of entry events for this tracked person at this frame.

        observations: {'helmet':'yes'|'no'|'unknown', 'mask':...}
        Points and polygon vertices are normalized 0..1 coordinates.
        """
        emitted = []
        for z in self.zones:
            name = z['name']
            required = z['required']
            inside = point_in_polygon(footpoint, z['polygon'])
            key = (name, int(track_id))
            st = self.state.setdefault(key, Visit())
            st.last_frame = frame_no
            if inside:
                st.inside_streak += 1
                st.outside_streak = 0
                if st.seen_outside and not st.active and st.inside_streak >= self.min_inside:
                    st.active = True
                    st.committed = False
                    st.episode += 1
                    st.age = 0
                    st.votes = {item: deque(maxlen=self.vote_window) for item in required}
                if st.active and not st.committed:
                    st.age += 1
                    for item in required:
                        st.votes[item].append(observations.get(item, 'unknown'))
                    outcome, statuses = self._decision(st, required)
                    if outcome is not None or st.age >= self.max_pending_frames:
                        emitted.append(dict(zone=name, track_id=int(track_id), episode=st.episode,
                                            outcome=outcome or 'unknown', statuses=statuses,
                                            missing=[item for item, value in statuses.items() if value == 'no']))
                        st.committed = True
            else:
                st.outside_streak += 1
                st.inside_streak = 0
                if st.outside_streak >= self.min_outside:
                    st.seen_outside = True
                    if st.active:
                        if not st.committed:
                            _, statuses = self._decision(st, required)
                            emitted.append(dict(zone=name, track_id=int(track_id), episode=st.episode,
                                                outcome='unknown', statuses=statuses, missing=[]))
                        st.active = False
                        st.committed = False
        return emitted

    def cleanup(self, frame_no, max_idle=120):
        self.state = {key: st for key, st in self.state.items() if frame_no - st.last_frame < max_idle}
