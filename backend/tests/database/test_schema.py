import json
from pathlib import Path
import uuid
from concurrent.futures import ThreadPoolExecutor

import psycopg
from psycopg import sql
import pytest
from conftest import downgrade_database, insert, upgrade_database, upgrade_database_cli

CONTRACT = json.loads(Path(__file__).with_name('schema_contract.json').read_text())


def test_exact_dictionary_and_foreign_keys(dsn):
    with psycopg.connect(dsn) as conn:
        rows = conn.execute('''SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod), NOT a.attnotnull
            FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='nowave' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped
            ORDER BY c.relname,a.attnum''').fetchall()
        expected=[]
        for table, fields in sorted(CONTRACT.items()):
            for field in fields:
                ty=field['type'].replace('varchar','character varying').replace('char(', 'character(').replace('timestamptz','timestamp with time zone')
                expected.append((table,field['name'],ty,field['nullable']))
        assert rows == expected
        assert len(rows) == 99
        fk=conn.execute("SELECT confdeltype,count(*) FROM pg_constraint WHERE contype='f' AND connamespace='nowave'::regnamespace GROUP BY 1").fetchall()
        assert dict(fk)=={'c':9,'n':5}
        assert conn.execute("SELECT count(*) FROM pg_constraint WHERE contype='p' AND connamespace='nowave'::regnamespace").fetchone()[0]==10


def test_spatial_indexes_and_distance(db):
    conn, ids=db
    indexes=dict(conn.execute("SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='nowave'"))
    for name in ['reports_final_position_gist','device_positions_position_gist']:
        assert 'USING gist' in indexes[name]
    for name in ['reports_author_idx','reports_status_expiry_idx','devices_user_idx','notifications_schedule_idx']:
        assert name in indexes
    conn.execute('SET LOCAL enable_seqscan=off')
    plan=conn.execute("EXPLAIN SELECT * FROM nowave.device_positions WHERE ST_DWithin(position,'SRID=4326;POINT(5 43)'::geography,18520)").fetchall()
    assert 'device_positions_position_gist' in str(plan)
    assert conn.execute("SELECT ST_DWithin('POINT(0 0)'::geography, ST_Project('POINT(0 0)'::geography,18519,0),18520), ST_DWithin('POINT(0 0)'::geography, ST_Project('POINT(0 0)'::geography,18521,0),18520)").fetchone()==(True,False)


INVALID=[('users','role','owner'),('users','status','deleted'),('boats','boat_type','yacht'),('devices','platform','web'),
 ('reports','category','fish'),('reports','positioning_mode','gps'),('reports','status','draft'),('reports','version',0),
 ('report_photos','upload_status','done'),('report_photos','size_bytes',0),('report_photos','size_bytes',500001),
 ('report_photos','mime_type','image/png'),('notifications','status','queued'),('notifications','report_version',0),
 ('notifications','attempt_count',-1),('alert_history','category','fish'),('alert_history','report_version',0),
 ('alert_history','distance_m',-1),('device_positions','accuracy_m',-1),('device_positions','accuracy_m',50.01),
 ('device_positions','heading_deg',-1),('device_positions','heading_deg',360),('report_positioning','gps_accuracy_m',-1),
 ('report_positioning','gps_accuracy_m',51),('report_positioning','azimuth_deg',360),('report_positioning','camera_height_m',0),
 ('report_positioning','camera_height_m','NaN'),('report_positioning','camera_height_uncertainty_m',-1),
 ('report_positioning','focal_length_mm',0),('report_positioning','zoom_ratio',0),('report_positioning','estimated_distance_m',-1)]
for table, fields in CONTRACT.items():
    for field in fields:
        if field['type']=='double precision':
            INVALID.extend((table,field['name'],value) for value in ['NaN','Infinity','-Infinity'])


@pytest.mark.parametrize('table,field,value',INVALID)
def test_invalid_values_rejected(db,table,field,value):
    conn,_=db
    with pytest.raises(psycopg.errors.CheckViolation):
        conn.execute(sql.SQL('UPDATE nowave.{} SET {}=%s').format(sql.Identifier(table),sql.Identifier(field)),(value,))


@pytest.mark.parametrize('table,field',[('users','firebase_uid'),('users','username'),('users','email'),('boats','user_id'),('devices','installation_id'),('devices','fcm_token'),('reports','client_report_id'),('report_photos','object_key'),('notifications','device_id'),('alert_history','user_id')])
def test_unique_keys(db,table,field):
    conn,ids=db
    # Clone a valid row, preserving the unique key while replacing its PK.
    if field in ['email','fcm_token','object_key']:
        conn.execute(sql.SQL('UPDATE nowave.{} SET {}=%s WHERE {}=%s').format(sql.Identifier(table),sql.Identifier(field),sql.Identifier('report_id' if table=='report_photos' else 'id')),(str(uuid.uuid4()),ids[{'users':'user','devices':'device','report_photos':'report'}[table]]))
    row_id=ids[{'users':'user','boats':'boat','devices':'device','reports':'report','report_photos':'report','notifications':'notification','alert_history':'history'}[table]]
    row=conn.execute(sql.SQL('SELECT * FROM nowave.{} WHERE {}=%s').format(sql.Identifier(table),sql.Identifier('report_id' if table=='report_photos' else 'id')),(row_id,))
    values=dict(zip([x.name for x in row.description],row.fetchone()))
    pk='report_id' if table=='report_photos' else 'id'
    values[pk]=ids['manual'] if table=='report_photos' else uuid.uuid4()
    if table=='devices' and field=='fcm_token': values['installation_id']=uuid.uuid4()
    if table=='users':
        for other in ['firebase_uid','username','email']:
            if other!=field: values[other]=str(uuid.uuid4())
    with pytest.raises(psycopg.errors.UniqueViolation):
        insert(conn,table,**values)


@pytest.mark.parametrize('child',['report_photos','report_positioning'])
def test_missing_child_fails_at_commit(db,child):
    conn,ids=db
    conn.execute(sql.SQL('DELETE FROM nowave.{} WHERE report_id=%s').format(sql.Identifier(child)),(ids['report'],))
    with pytest.raises(psycopg.errors.CheckViolation): conn.commit()
    assert conn.execute(sql.SQL('SELECT count(*) FROM nowave.{} WHERE report_id=%s').format(sql.Identifier(child)),(ids['report'],)).fetchone()[0]==1


def test_photo_creation_without_children_fails(db):
    conn,ids=db
    conn.execute("UPDATE nowave.reports SET positioning_mode='photo' WHERE id=%s",(ids['manual'],))
    with pytest.raises(psycopg.errors.CheckViolation): conn.commit()


def test_manual_cannot_keep_children(db):
    conn,ids=db
    conn.execute("UPDATE nowave.reports SET positioning_mode='manual' WHERE id=%s",(ids['report'],))
    with pytest.raises(psycopg.errors.CheckViolation): conn.commit()


@pytest.mark.parametrize('child',['report_photos','report_positioning'])
def test_reparent_checks_old_and_new_report(db,child):
    conn,ids=db
    conn.execute(sql.SQL('UPDATE nowave.{} SET report_id=%s WHERE report_id=%s').format(sql.Identifier(child)),(ids['manual'],ids['report']))
    with pytest.raises(psycopg.errors.CheckViolation): conn.commit()


def test_valid_mode_conversion_is_atomic(db):
    conn,ids=db
    conn.execute("UPDATE nowave.reports SET positioning_mode='manual' WHERE id=%s",(ids['report'],))
    conn.execute('DELETE FROM nowave.report_photos WHERE report_id=%s',(ids['report'],))
    conn.execute('DELETE FROM nowave.report_positioning WHERE report_id=%s',(ids['report'],))
    conn.commit()


def test_failed_upload_and_retry_same_row(db):
    conn,ids=db
    conn.execute("UPDATE nowave.report_photos SET upload_status='failed' WHERE report_id=%s",(ids['report'],));conn.commit()
    conn.execute("UPDATE nowave.report_photos SET upload_status='uploaded',object_key=%s,size_bytes=500000,mime_type='image/jpeg',uploaded_at=now() WHERE report_id=%s",(str(uuid.uuid4()),ids['report']));conn.commit()
    assert conn.execute('SELECT count(*) FROM nowave.report_photos WHERE report_id=%s',(ids['report'],)).fetchone()[0]==1


@pytest.mark.parametrize('statement',[
 "UPDATE nowave.report_photos SET upload_status='uploaded'",
 "UPDATE nowave.notifications SET next_attempt_at=NULL",
 "UPDATE nowave.notifications SET status='sent'",
 "UPDATE nowave.reports SET expires_at=expires_at+interval '1 second'",
 "UPDATE nowave.reports SET observed_at=observed_at+interval '1 second',expires_at=expires_at+interval '1 second'",
 "UPDATE nowave.reports SET author_id=NULL",
 "UPDATE nowave.devices SET installation_id=gen_random_uuid()",
 "UPDATE nowave.moderation_actions SET reason='changed'",
 "UPDATE nowave.moderation_actions SET admin_user_id=NULL",
 "DELETE FROM nowave.moderation_actions"])
def test_state_and_immutability_guards(db,statement):
    conn,_=db
    with pytest.raises(psycopg.errors.CheckViolation): conn.execute(statement)


def test_user_deletion_cascades_and_keeps_report_and_audit(db):
    conn,ids=db
    conn.execute('DELETE FROM nowave.users WHERE id=%s',(ids['user'],));conn.commit()
    assert conn.execute('SELECT author_id FROM nowave.reports WHERE id=%s',(ids['report'],)).fetchone()==(None,)
    for table,key,value in [('boats','id',ids['boat']),('devices','id',ids['device']),('device_positions','device_id',ids['device']),('notifications','id',ids['notification']),('alert_history','id',ids['history'])]:
        assert conn.execute(sql.SQL('SELECT count(*) FROM nowave.{} WHERE {}=%s').format(sql.Identifier(table),sql.Identifier(key)),(value,)).fetchone()[0]==0
    conn.execute('DELETE FROM nowave.users WHERE id=%s',(ids['admin'],));conn.commit()
    assert conn.execute('SELECT admin_user_id FROM nowave.moderation_actions WHERE id=%s',(ids['audit'],)).fetchone()==(None,)


def test_report_deletion_cascades_and_nulls_audit(db):
    conn,ids=db
    conn.execute('DELETE FROM nowave.reports WHERE id=%s',(ids['report'],));conn.commit()
    for table in ['report_photos','report_positioning','notifications','alert_history']:
        assert conn.execute(sql.SQL('SELECT count(*) FROM nowave.{} WHERE report_id=%s').format(sql.Identifier(table)),(ids['report'],)).fetchone()[0]==0
    assert conn.execute('SELECT target_report_id FROM nowave.moderation_actions WHERE id=%s',(ids['audit'],)).fetchone()==(None,)


@pytest.mark.parametrize('change',[{'admin_user_id':None},{'action':'invalid'},{'reason':' \t\n'}, {'target_user_id':'user'}, {'action':'hide_photo'}])
def test_audit_creation_contract(db,change):
    conn,ids=db
    values=dict(id=uuid.uuid4(),admin_user_id=ids['admin'],target_report_id=ids['report'],action='remove_report',reason='reason',created_at='2026-09-16T00:00:00Z')
    values.update({k:ids.get(v,v) for k,v in change.items()})
    with pytest.raises(psycopg.errors.CheckViolation):insert(conn,'moderation_actions',**values)


def test_historical_versions_are_not_foreign_keys(db):
    conn,ids=db
    conn.execute('UPDATE nowave.reports SET version=2 WHERE id=%s',(ids['report'],));conn.commit()
    assert conn.execute('SELECT report_version FROM nowave.alert_history WHERE id=%s',(ids['history'],)).fetchone()==(1,)


def test_migration_replay(dsn):
    upgrade_database(dsn)
    with psycopg.connect(dsn) as conn:
        assert conn.execute('SELECT version_num FROM alembic_version').fetchone()==('20260917_0001',)


def test_migrations_roundtrip(dsn):
    with psycopg.connect(dsn) as conn:
        before=conn.execute("SELECT tablename,indexdef FROM pg_indexes WHERE schemaname='nowave' ORDER BY tablename,indexname").fetchall()
    downgrade_database(dsn)
    upgrade_database(dsn)
    with psycopg.connect(dsn) as conn:
        after=conn.execute("SELECT tablename,indexdef FROM pg_indexes WHERE schemaname='nowave' ORDER BY tablename,indexname").fetchall()
        assert conn.execute('SELECT count(*) FROM alembic_version').fetchone()==(1,)
    assert before==after


def test_foreign_keys_reject_missing_parents(db):
    conn,ids=db
    with pytest.raises(psycopg.errors.ForeignKeyViolation):
        conn.execute('UPDATE nowave.notifications SET device_id=%s WHERE id=%s',(uuid.uuid4(),ids['notification']))


def test_nullable_unique_values_and_defaults(db):
    conn,ids=db
    assert conn.execute('SELECT show_user_name,show_boat_info,notifications_enabled FROM nowave.users WHERE id=%s',(ids['user'],)).fetchone()==(False,False,False)
    assert conn.execute('SELECT version FROM nowave.reports WHERE id=%s',(ids['report'],)).fetchone()==(1,)
    assert conn.execute('SELECT attempt_count FROM nowave.notifications WHERE id=%s',(ids['notification'],)).fetchone()==(0,)

    with pytest.raises(psycopg.errors.NotNullViolation):
        conn.execute(
            'UPDATE nowave.users SET email=NULL WHERE id=%s',
            (ids['user'],),
        )


@pytest.mark.parametrize('table,field',[('reports','final_position'),('device_positions','position'),('report_positioning','observer_position'),('report_positioning','estimated_position'),('alert_history','position')])
def test_geography_rejects_non_points(db,table,field):
    conn,_=db
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        conn.execute(sql.SQL('UPDATE nowave.{} SET {}=%s').format(sql.Identifier(table),sql.Identifier(field)),('SRID=4326;LINESTRING(0 0,1 1)',))


def test_missing_author_on_insert(db):
    conn,ids=db
    row=conn.execute('SELECT * FROM nowave.reports WHERE id=%s',(ids['manual'],))
    values=dict(zip([x.name for x in row.description],row.fetchone()))
    values.update(id=uuid.uuid4(),author_id=None)
    with pytest.raises(psycopg.errors.CheckViolation):insert(conn,'reports',**values)


def test_both_audit_target_kinds_survive_deletion(db):
    conn,ids=db
    actions=[]
    for action,key,target in [('hide_photo','target_photo_report_id','report'),('suspend_user','target_user_id','user')]:
        uid=uuid.uuid4();actions.append((uid,key))
        insert(conn,'moderation_actions',id=uid,admin_user_id=ids['admin'],action=action,reason='Valid reason',created_at='2026-09-16T00:00:00Z',**{key:ids[target]})
    conn.commit()
    conn.execute('DELETE FROM nowave.reports WHERE id=%s',(ids['report'],))
    conn.execute('DELETE FROM nowave.users WHERE id=%s',(ids['user'],));conn.commit()
    for uid,key in actions:
        assert conn.execute(sql.SQL('SELECT {} FROM nowave.moderation_actions WHERE id=%s').format(sql.Identifier(key)),(uid,)).fetchone()==(None,)


def test_concurrent_migrations_apply_once(dsn):
    downgrade_database(dsn)
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(upgrade_database_cli,[dsn,dsn]))
    with psycopg.connect(dsn) as conn:
        assert conn.execute('SELECT count(*) FROM alembic_version').fetchone()==(1,)
        assert conn.execute("SELECT to_regclass('nowave.users') IS NOT NULL").fetchone()==(True,)
