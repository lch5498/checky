// Optional local PostgreSQL integration test. Never connects to the app database.
// PG_BIN=/opt/homebrew/opt/postgresql@14/bin node apps/api/test/coupon-quota.integration.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawn } = require('node:child_process');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'checky-coupon-quota-'));
const bin = name => path.join(process.env.PG_BIN || '', name);
const port = '55439';
const args = ['-X', '-h', root, '-p', port, '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-Atq'];
const sql = query => execFileSync(bin('psql'), args, { input: query, encoding: 'utf8' }).trim();
function parallelSql(query) {
  return new Promise((resolve, reject) => {
    const child = spawn(bin('psql'), args);
    let error = '';
    child.stderr.on('data', data => error += data);
    child.stdout.resume();
    child.on('error', reject);
    child.on('exit', code => resolve({ code, error }));
    child.stdin.end(query);
  });
}
const family = '11111111-1111-1111-1111-111111111111';
const insert = `insert into public.coupons(family_id,title,image_path) values('${family}','커피',gen_random_uuid()::text)`;
let started = false;
(async () => {
  try {
    execFileSync(bin('initdb'), ['-D', root, '-A', 'trust', '--no-locale', '-E', 'UTF8'], { stdio: 'pipe' });
    execFileSync(bin('pg_ctl'), ['-D', root, '-l', path.join(root, 'server.log'), '-o', `-k ${root} -p ${port} -h ''`, '-w', 'start'], { stdio: 'pipe' });
    started = true;
    sql(`create table public.families(id uuid primary key); create table public.users(id uuid primary key);
      create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
      insert into public.families values('${family}');`);
    for (const file of ['202610070001_add_group_coupons.sql', '202610080001_limit_group_coupon_images.sql']) {
      sql(fs.readFileSync(path.join(__dirname, '../../../supabase/migrations', file), 'utf8'));
    }
    sql(`insert into public.coupons(family_id,title,image_path,used_at,expires_on)
      select '${family}','used and expired',gen_random_uuid()::text,now(),'2020-01-01' from generate_series(1,99);`);
    const results = await Promise.all([parallelSql(`${insert};`), parallelSql(`${insert};`)]);
    assert.equal(results.filter(r => r.code === 0).length, 1, JSON.stringify(results));
    assert.equal(sql('select count(*) from public.coupons'), '100');
    assert.equal(sql('select count(distinct image_slot) from public.coupons'), '100');
    // A pending Storage deletion still occupies a slot.
    sql('update public.coupons set deleted_at=now() where image_slot=1;');
    assert.match((await parallelSql(`${insert};`)).error, /coupon_limit_reached/);
    sql('delete from public.coupons where image_slot=1;');
    sql(`${insert};`);
    assert.equal(sql('select count(*) from public.coupons'), '100');
    assert.match((await parallelSql('update public.coupons set image_slot=101 where image_slot=1;')).error, /coupon_image_slot_immutable/);
    console.log('PASS: 99 + concurrent registrations stays at 100; cleanup-pending counts; deletion releases slot.');
  } finally {
    if (started) execFileSync(bin('pg_ctl'), ['-D', root, '-m', 'immediate', '-w', 'stop'], { stdio: 'pipe' });
    fs.rmSync(root, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
