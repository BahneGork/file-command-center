// Tests for the deadlines/recurrences in index.html. Run with: node --test (from the repo root)
// The page has no modules, so the script is run in a sandbox without init(), and the tested functions are taken out afterwards.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const src = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>')).replace(/\ninit\(\);\s*$/, '\n');
const ctx = { navigator: { language: 'da' }, addEventListener() {}, TextEncoder };
vm.runInNewContext(src + ';globalThis.F={nextOcc,firstOcc,occurrences,danishHolidays,easter,normRecur,icsRule,icsText,ymd,pd,setHolidays:h=>{S={settings:{holidays:h}}}};', ctx);
const F = ctx.F;
const day = s => F.pd(s);
const dues = (f, from, to) => [...F.occurrences(f, day(from), day(to))].map(o => o.date);

test('Easter and Danish public holidays', () => {
  assert.equal(F.ymd(F.easter(2024)), '2024-03-31');
  assert.equal(F.ymd(F.easter(2025)), '2025-04-20');
  assert.equal(F.ymd(F.easter(2026)), '2026-04-05');
  assert.deepEqual([...F.danishHolidays(2026)], [
    '2026-01-01 Nytårsdag', '2026-04-02 Skærtorsdag', '2026-04-03 Langfredag', '2026-04-06 2. påskedag',
    '2026-05-14 Kristi himmelfartsdag', '2026-05-25 2. pinsedag', '2026-12-25 Juledag', '2026-12-26 2. juledag']);
});

test('monthly on the 31st becomes the last day of the month', () => {
  F.setHolidays([]);
  const f = { due: '2026-01-31', recur: { unit: 'month', every: 1 } };
  assert.deepEqual(dues(f, '2026-01-01', '2026-04-30'), ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
});

test('weekly on given weekdays and every 2nd week', () => {
  F.setHolidays([]);
  // 2026-10-05 is a Monday
  const f = { due: '2026-10-05', recur: { unit: 'week', every: 2, days: [1, 4] } };
  assert.deepEqual(dues(f, '2026-10-01', '2026-10-31'), ['2026-10-05', '2026-10-08', '2026-10-19', '2026-10-22']);
});

test('nextOcc: inclusive and "until"', () => {
  F.setHolidays([]);
  const r = { unit: 'day', every: 3, until: '2026-10-10' };
  assert.deepEqual({ ...F.nextOcc('2026-10-01', r, day('2026-10-04'), true) }, { due: '2026-10-04', anchor: '2026-10-04' });
  assert.equal(F.nextOcc('2026-10-01', r, day('2026-10-04'), false).due, '2026-10-07');
  assert.equal(F.nextOcc('2026-10-01', r, day('2026-10-10'), false), null);
});

test('last workday of the month skips public holidays', () => {
  F.setHolidays(F.danishHolidays(2026));
  // 31 Dec 2026 is a Thursday; 25/26 Dec are public holidays
  const f = { due: '2026-12-01', recur: { unit: 'month', every: 1, of: 'workday', pos: -1 } };
  assert.deepEqual(dues(f, '2026-12-01', '2026-12-31'), ['2026-12-31']);
  // 2nd workday of April 2026: 1 April (Wednesday) is the first; 2-6 April are public holidays or weekend
  const g = { due: '2026-04-01', recur: { unit: 'month', every: 1, of: 'workday', pos: 2 } };
  assert.deepEqual(dues(g, '2026-04-01', '2026-04-30'), ['2026-04-07']);
});

test('move off a day off: the moved date may be before the start date', () => {
  F.setHolidays([]);
  // 2026-11-01 is a Sunday; "before" moves it to Friday 30 Oct
  const f = { due: '2026-11-01', recur: { unit: 'month', every: 1, shift: 'before' } };
  assert.deepEqual(dues(f, '2026-10-01', '2026-12-31'), ['2026-10-30', '2026-12-01']);
});

test('normRecur translates old formats', () => {
  assert.deepEqual({ ...F.normRecur('daily') }, { unit: 'day', every: 1 });
  assert.deepEqual({ ...F.normRecur({ kind: 'monthly' }, '2026-03-15') }, { unit: 'month', every: 1, of: 'date', pos: 15 });
  assert.deepEqual({ ...F.normRecur({ kind: 'lastWorkday' }) }, { unit: 'month', every: 1, of: 'workday', pos: -1 });
  assert.deepEqual({ ...F.normRecur({ unit: 'week', every: 1, from: 'done', anchor: 'x' }) }, { unit: 'week', every: 1 });
  assert.equal(F.normRecur(null), '');
});

test('icsRule: rules that can be expressed exactly, otherwise null', () => {
  F.setHolidays([]);
  assert.equal(F.icsRule({ recur: { unit: 'week', every: 2, days: [1, 4] } }, '2026-10-05'), 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH;WKST=MO');
  assert.equal(F.icsRule({ recur: { unit: 'month', every: 1, of: 'workday', pos: -1 } }, '2026-10-30'), 'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1');
  assert.equal(F.icsRule({ recur: { unit: 'month', every: 1, pos: 31 } }, '2026-01-31'), 'FREQ=MONTHLY;BYMONTHDAY=28,29,30,31;BYSETPOS=-1');
  assert.equal(F.icsRule({ recur: { unit: 'month', every: 1, shift: 'after' } }, '2026-10-05'), null);
  F.setHolidays(['2026-12-25']);
  assert.equal(F.icsRule({ recur: { unit: 'month', every: 1, of: 'workday', pos: 1 } }, '2026-10-01'), null);
});

test('icsText: valid calendar with CRLF and folded lines', () => {
  F.setHolidays([]);
  const files = [{ id: 'a', title: 'Rapport '.repeat(20), path: 'C:\\x;y,z.xlsx', due: '2026-10-05', recur: { unit: 'week', every: 1 } }];
  const ics = F.icsText(files, day('2026-10-01'));
  assert.ok(ics.startsWith('BEGIN:VCALENDAR\r\n') && ics.endsWith('END:VCALENDAR\r\n'));
  assert.ok(ics.includes('RRULE:FREQ=WEEKLY'));
  assert.ok(ics.includes('DESCRIPTION:C:\\\\x\\;y\\,z.xlsx'));
  for (const line of ics.split('\r\n')) assert.ok(Buffer.byteLength(line) <= 75, line);
});
