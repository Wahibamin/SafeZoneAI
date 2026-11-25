"""Minimal event logging, no personal identity stored."""
import csv
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


class EventStore:
    def __init__(self, path='safezone.db'):
        self.path = str(path)
        self.db = sqlite3.connect(self.path, timeout=20)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('''CREATE TABLE IF NOT EXISTS events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          time_utc TEXT NOT NULL,
          run_id TEXT NOT NULL,
          camera TEXT NOT NULL,
          zone TEXT NOT NULL,
          track_id INTEGER NOT NULL,
          episode INTEGER NOT NULL,
          outcome TEXT NOT NULL,
          helmet TEXT NOT NULL,
          mask TEXT NOT NULL,
          missing TEXT NOT NULL,
          snapshot TEXT NOT NULL DEFAULT '',
          UNIQUE (run_id,camera,zone,track_id,episode)
        )''')
        self.db.commit()

    def add(self, run_id, camera, event, snapshot=''):
        self.db.execute('''INSERT OR IGNORE INTO events (
            time_utc,run_id,camera,zone,track_id,episode,outcome,
            helmet,mask,missing,snapshot
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?)''', (
            datetime.now(timezone.utc).isoformat(timespec='seconds'), run_id, camera,
            event['zone'], event['track_id'], event['episode'], event['outcome'],
            event['statuses'].get('helmet', 'not_required'),
            event['statuses'].get('mask', 'not_required'),
            ','.join(event['missing']), snapshot
        ))
        self.db.commit()

    def totals(self, camera=None):
        if camera:
            rows = self.db.execute('SELECT outcome, COUNT(*) FROM events WHERE camera=? GROUP BY outcome', (camera,))
        else:
            rows = self.db.execute('SELECT outcome, COUNT(*) FROM events GROUP BY outcome')
        d = {'compliant': 0, 'violation': 0, 'unknown': 0}
        d.update(dict(rows.fetchall()))
        return d

    def close(self):
        self.db.close()


def export_csv(database='safezone.db', output='events.csv'):
    if not Path(database).exists():
        raise FileNotFoundError(f'No events database at {database}')
    db = sqlite3.connect(database)
    cur = db.execute('SELECT time_utc,camera,zone,track_id,episode,outcome,helmet,mask,missing,snapshot FROM events ORDER BY id')
    with open(output, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow([x[0] for x in cur.description])
        writer.writerows(cur.fetchall())
    db.close()
    return output
