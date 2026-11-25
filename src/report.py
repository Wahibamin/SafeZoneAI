import argparse
from collections import Counter
from storage import EventStore,export_csv


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--database',default='safezone.db')
    p.add_argument('--csv',default='safezone_report.csv')
    a=p.parse_args()
    store=EventStore(a.database)
    for zone,outcome,n in store.db.execute('SELECT zone,outcome,COUNT(*) FROM events GROUP BY zone,outcome ORDER BY zone,outcome'):
        print(f'{zone:28s} {outcome:12s}: {n}')
    print('TOTAL:',store.totals())
    store.close()
    print('CSV exported:',export_csv(a.database,a.csv))


if __name__=='__main__':
    main()
