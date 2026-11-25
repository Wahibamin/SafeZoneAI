"""SafeZone AI video monitor.

Examples:
 python monitor.py --profile machines --source 0 --helmet-model runs/detect/helmet_train/weights/best.pt
 python monitor.py --profile food --source food.mp4 --mask-model runs/detect/mask_train/weights/best.pt
 python monitor.py --profile demo --helmet-model ... --mask-model ...
"""
import argparse
import json
import uuid
from pathlib import Path
from datetime import datetime, timezone
import cv2
from ultralytics import YOLO
from safety_logic import EntryEngine
from storage import EventStore

HELMET_YES = {'helmet', 'hardhat', 'hard_hat', 'with_helmet'}
HELMET_NO = {'no_helmet', 'without_helmet', 'no_hardhat', 'no_hard_hat'}
MASK_YES = {'with_mask', 'mask', 'mask_proper', 'mask_correct', 'wearing_mask'}
MASK_NO = {'without_mask', 'no_mask', 'mask_none', 'mask_improper',
           'mask_weared_incorrect', 'mask_incorrect'}


def clean_name(s):
    return str(s).lower().strip().replace(' ', '_').replace('-', '_')


def parse_args():
    p = argparse.ArgumentParser(description='SafeZone AI - zone-specific PPE monitoring')
    p.add_argument('--config', default='config.json')
    p.add_argument('--profile', default='demo', help='demo | machines | food | maintenance')
    p.add_argument('--source', default=None, help='0 for webcam or path to a video')
    p.add_argument('--person-model', default='yolo26n.pt')
    p.add_argument('--helmet-model', default=None, help='Path to trained helmet best.pt')
    p.add_argument('--mask-model', default=None, help='Path to trained face mask best.pt')
    p.add_argument('--database', default='safezone.db')
    p.add_argument('--save-snapshots', action='store_true', help='Saves violation frames only (off by default)')
    p.add_argument('--conf', type=float, default=0.35)
    p.add_argument('--no-window', action='store_true')
    p.add_argument('--output-video', default=None)
    return p.parse_args()


def model_detections(model, frame, conf):
    if model is None:
        return []
    result = model.predict(frame, conf=conf, verbose=False)[0]
    out = []
    for box in result.boxes:
        x1, y1, x2, y2 = map(float, box.xyxy[0].tolist())
        label = clean_name(result.names[int(box.cls.item())])
        out.append((label, float(box.conf.item()), (x1, y1, x2, y2)))
    return out


def bbox_center(box):
    x1, y1, x2, y2 = box
    return (x1+x2)/2, (y1+y2)/2


def associate(people, detections, positive, negative):
    """Associate head/face detections only to plausible head regions.
    Returns track_id -> yes/no/unknown.
    """
    candidates = {pid: [] for pid, _ in people}
    for label, conf, b in detections:
        if label not in positive and label not in negative:
            continue
        x, y = bbox_center(b)
        options = []
        for pid, (x1, y1, x2, y2) in people:
            w, h = max(1., x2-x1), max(1., y2-y1)
            # Objects must occur near the tracked person's head, not in their hands.
            if (x1-0.10*w <= x <= x2+0.10*w and
                    y1-0.15*h <= y <= y1+0.42*h):
                dx = abs(x-(x1+x2)/2)/w
                dy = abs(y-(y1+0.13*h))/h
                options.append((dx+dy, pid))
        if options:
            _, selected_pid = min(options)
            candidates[selected_pid].append((conf, 'yes' if label in positive else 'no'))
    statuses = {}
    for pid, matches in candidates.items():
        if not matches:
            statuses[pid] = 'unknown'
            continue
        matches.sort(reverse=True)
        top_conf, top_label = matches[0]
        # Conflicting head detections with nearly equal confidence need review.
        if any(lbl != top_label and abs(top_conf-other_conf) < 0.15
               for other_conf, lbl in matches[1:]):
            statuses[pid] = 'unknown'
        else:
            statuses[pid] = top_label
    return statuses


def read_people(person_model, frame, conf):
    result = person_model.track(frame, persist=True, classes=[0],
                                tracker='bytetrack.yaml', conf=conf, verbose=False)[0]
    out = []
    if result.boxes is None or result.boxes.id is None:
        return out
    for box in result.boxes:
        x1, y1, x2, y2 = map(float, box.xyxy[0].tolist())
        track_id = int(box.id.item())
        out.append((track_id, (x1, y1, x2, y2)))
    return out


def draw_zones(frame, zones):
    h, w = frame.shape[:2]
    for z in zones:
        points = [(round(x*w), round(y*h)) for x,y in z['polygon']]
        for a,b in zip(points, points[1:]+points[:1]):
            cv2.line(frame, a, b, (0, 210, 255), 2)
        x,y = points[0]
        cv2.putText(frame, f"{z['name']}: {' + '.join(z['required'])}",
                    (max(0,x),max(24,y+22)), cv2.FONT_HERSHEY_SIMPLEX,
                    0.58,(0,210,255),2,cv2.LINE_AA)


def draw_status(frame, pid, box, statuses):
    x1,y1,x2,y2 = map(int,box)
    vals = list(statuses.values())
    if 'no' in vals:
        color = (25,25,235)
    elif vals and all(v == 'yes' for v in vals):
        color = (30,190,40)
    else:
        color = (0,190,255)
    cv2.rectangle(frame, (x1,y1),(x2,y2),color,2)
    label = f'ID {pid} ' + ' '.join(f'{k}:{v}' for k,v in statuses.items())
    cv2.putText(frame,label,(max(0,x1),max(15,y1-9)),cv2.FONT_HERSHEY_SIMPLEX,
                0.48,color,2,cv2.LINE_AA)


def main():
    a = parse_args()
    cfg = json.loads(Path(a.config).read_text(encoding='utf-8'))
    if a.profile not in cfg['profiles']:
        raise ValueError(f'Unknown profile {a.profile}; choose from {list(cfg["profiles"])}')
    current = cfg['profiles'][a.profile]
    zones = current['zones']
    required = set().union(*(set(z['required']) for z in zones))
    if 'helmet' in required and not a.helmet_model:
        raise SystemExit('This profile requires --helmet-model path/to/best.pt (train it first).')
    if 'mask' in required and not a.mask_model:
        raise SystemExit('This profile requires --mask-model path/to/best.pt (train it first).')
    person_model = YOLO(a.person_model)
    helmet_model = YOLO(a.helmet_model) if 'helmet' in required else None
    mask_model = YOLO(a.mask_model) if 'mask' in required else None
    src = a.source if a.source is not None else current['source']
    source = int(src) if str(src).isdigit() else src
    cap = cv2.VideoCapture(source)
    if not cap.isOpened():
        raise SystemExit(f'Cannot open source: {source}')
    engine = EntryEngine(zones)
    db = EventStore(a.database)
    run_id = uuid.uuid4().hex[:16]
    frame_no = 0
    writer = None
    print(f'Started {a.profile} (run_id={run_id}) from {source}. Press Q to exit.')
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            frame_no += 1
            height,width = frame.shape[:2]
            people = read_people(person_model,frame,a.conf)
            helmet_dets = model_detections(helmet_model,frame,a.conf)
            mask_dets = model_detections(mask_model,frame,a.conf)
            helmet = associate(people,helmet_dets,HELMET_YES,HELMET_NO) if helmet_model else {}
            mask = associate(people,mask_dets,MASK_YES,MASK_NO) if mask_model else {}
            draw_zones(frame,zones)
            for pid,box in people:
                x1,y1,x2,y2 = box
                # The footpoint (not the box center) crosses the doorway polygon.
                footpoint = ((x1+x2)/2/width, y2/height)
                obs = {'helmet':helmet.get(pid,'unknown'), 'mask':mask.get(pid,'unknown')}
                events = engine.observe(pid,footpoint,obs,frame_no)
                draw_status(frame,pid,box,{key:obs[key] for key in required})
                for event in events:
                    snapshot = ''
                    if a.save_snapshots and event['outcome'] == 'violation':
                        folder = Path('snapshots')
                        folder.mkdir(exist_ok=True)
                        name = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
                        snapshot = str(folder / f'{a.profile}_{pid}_{name}.jpg')
                        cv2.imwrite(snapshot,frame)
                    db.add(run_id,a.profile,event,snapshot)
                    print(f'ENTRY {a.profile} zone={event["zone"]} '
                          f'id={pid} outcome={event["outcome"]} missing={event["missing"]}')
            if frame_no%120==0:
                engine.cleanup(frame_no)
            stats = db.totals(camera=a.profile)
            cv2.rectangle(frame,(0,max(0,height-35)),(min(width,620),height),(28,28,28),-1)
            text = f'Entries: {sum(stats.values())}  OK: {stats["compliant"]}  VIOL: {stats["violation"]}  REVIEW: {stats["unknown"]}'
            cv2.putText(frame,text,(8,height-12),cv2.FONT_HERSHEY_SIMPLEX,
                        0.56,(255,255,255),2,cv2.LINE_AA)
            if a.output_video:
                if writer is None:
                    fps=cap.get(cv2.CAP_PROP_FPS)
                    if fps<1 or fps>120:
                        fps=20
                    writer=cv2.VideoWriter(a.output_video,cv2.VideoWriter_fourcc(*'mp4v'),fps,(width,height))
                writer.write(frame)
            if not a.no_window:
                cv2.imshow(f'SafeZone AI: {a.profile}',frame)
                if cv2.waitKey(1)&0xFF == ord('q'):
                    break
    finally:
        cap.release()
        if writer is not None:
            writer.release()
        if not a.no_window:
            cv2.destroyAllWindows()
        print('Final totals:',db.totals(camera=a.profile))
        db.close()


if __name__ == '__main__':
    main()
