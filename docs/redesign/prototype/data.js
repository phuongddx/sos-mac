/* SOS Mac — prototype sample data.
   Every value below fills a field that exists in the current engine (current-ui-inventory.md §4.1).
   Names, paths and sizes are made-up samples, not data from a real Mac. */
'use strict';

window.SOS = window.SOS || {};

SOS.MODS = {
  dashboard:   { label: 'Dashboard',        icon: 'sparkles', hue: '#8B5CF6', ink: '#fff', desc: '' },
  smartcare:   { label: 'Smart Care',       icon: 'wand',     hue: '#8B5CF6', ink: '#fff', desc: 'Junk and duplicates in one pass' },
  junk:        { label: 'Junk & Cache',     icon: 'trash',    hue: '#6366F1', ink: '#fff', desc: 'Caches and old logs' },
  duplicates:  { label: 'Duplicate Finder', icon: 'docs',     hue: '#3B82F6', ink: '#fff', desc: 'Exact copies and similar images' },
  spacelens:   { label: 'Space Lens',       icon: 'grid',     hue: '#E879F9', ink: '#140F26', desc: 'See what fills your disk' },
  cloud:       { label: 'Cloud Cleanup',    icon: 'cloud',    hue: '#38BDF8', ink: '#140F26', desc: 'Duplicates in iCloud Drive' },
  uninstaller: { label: 'Uninstaller',      icon: 'appx',     hue: '#FB923C', ink: '#140F26', desc: 'Remove apps and their files' },
  updater:     { label: 'Updater',          icon: 'updater',  hue: '#FBBF24', ink: '#140F26', desc: 'See which apps have updates' },
  performance: { label: 'Performance',      icon: 'gauge',    hue: '#2DD4BF', ink: '#140F26', desc: 'Live system metrics' },
  protection:  { label: 'Protection',       icon: 'shield',   hue: '#22D3EE', ink: '#140F26', desc: 'Known-signature malware scan' },
};

SOS.ORDER = [
  [null, ['dashboard', 'smartcare']],
  ['Clean', ['junk', 'duplicates', 'spacelens', 'cloud']],
  ['Manage', ['uninstaller', 'updater']],
  ['Speed', ['performance']],
  ['Protect', ['protection']],
];

SOS.STATES = {
  dashboard: ['default'],
  smartcare: ['start', 'scanning', 'results', 'review', 'cleaning', 'done', 'empty', 'error'],
  junk: ['start', 'scanning', 'results', 'review', 'cleaning', 'done', 'empty', 'error'],
  duplicates: ['start', 'scanning', 'results', 'review', 'cleaning', 'done', 'empty', 'error'],
  spacelens: ['start', 'scanning', 'results', 'review', 'cleaning', 'done', 'empty', 'error'],
  cloud: ['start', 'scanning', 'results', 'review', 'cleaning', 'done', 'empty', 'error', 'drive'],
  uninstaller: ['start', 'scanning', 'results', 'review', 'cleaning', 'done', 'empty', 'error'],
  updater: ['start', 'scanning', 'results', 'empty'],
  performance: ['live', 'running', 'approval', 'actiondone', 'actionerror', 'unavailable'],
  protection: ['start', 'scanning', 'results', 'review', 'cleaning', 'done', 'empty', 'error', 'quarantine'],
};

SOS.STATE_LABEL = {
  default: 'Default', start: 'Start', scanning: 'Scanning', results: 'Results', review: 'Review', cleaning: 'Cleaning',
  done: 'Done', empty: 'Empty', error: 'Error', drive: 'Drive (target)', quarantine: 'Quarantine list',
  live: 'Live', running: 'Action running', approval: 'Helper approval', actiondone: 'Action done',
  actionerror: 'Action error', unavailable: 'No data',
};

/* ---------- system ---------- */
SOS.SYS = {
  volume: 'Macintosh HD', used: 460.11e9, total: 494.38e9, free: 34.27e9,
  cpu: 23,
  mem: { total: 16e9, wired: 2.84e9, active: 5.61e9, compressed: 2.79e9, inactive: 3.92e9, free: 0.84e9 },
  swap: { used: 1.25e9, total: 2.15e9 },
  thermal: 'Nominal',
  load: [2.41, 2.88, 3.02],
  arch: 'Apple Silicon',
  bootTime: 'Nov 19, 2026 at 08:14',
  agents: [
    ['com.raycast.macos.helper.plist', '~/Library/LaunchAgents'],
    ['com.docker.helper.plist', '~/Library/LaunchAgents'],
    ['us.zoom.updater.plist', '~/Library/LaunchAgents'],
  ],
};
SOS.SYS.inUse = SOS.SYS.mem.wired + SOS.SYS.mem.active + SOS.SYS.mem.compressed;

/* ---------- Junk & Cache: 4 rules, files only (engine returns files, not folder totals) ---------- */
SOS.JUNK = [
  { id: 'uc', label: 'User App Caches', short: 'User App Caches', root: '~/Library/Caches', helper: false, files: [
    ['Cache.db', 'com.spotify.client/Data', 612480000],
    ['data_3', 'Google/Chrome/Default/Cache/Cache_Data', 341220000],
    ['CachedExtensionVSIXs.zip', 'com.microsoft.VSCode.ShipIt', 218600000],
    ['fsCachedData.db', 'com.tinyspeck.slackmacgap', 188940000],
    ['Cache.db', 'com.apple.Safari', 96310000],
    ['index-v3.dat', 'com.figma.Desktop', 74820000],
    ['data_1', 'us.zoom.xos/Cache', 41270000],
    ['Cache.db-wal', 'com.apple.Music', 18450000],
    ['icons.cache', 'com.raycast.macos', 9620000],
  ] },
  { id: 'ul', label: 'User Logs (7+ days old)', short: 'User Logs', root: '~/Library/Logs', helper: false, files: [
    ['Xcode-2026-10-29.log', 'Xcode', 61540000],
    ['zoom_stdout_stderr.log', 'zoom.us', 12330000],
    ['docker-desktop.log', 'Docker Desktop', 8920000, 'caution'],
    ['diagnostic-2026-11-02.ips', 'DiagnosticReports', 4810000],
    ['slack-main.log', 'Slack', 2240000, 'caution'],
  ] },
  { id: 'as', label: 'App Support Cache Folders', short: 'App Support Caches', root: '~/Library/Application Support', helper: false, files: [
    ['data_2', 'Slack/Cache/Cache_Data', 402180000],
    ['CachedData.bin', 'Code/CachedData', 266410000],
    ['index', 'Notion/Cache', 184520000],
    ['f_000a91', 'Figma/DesktopProfile/Cache', 93610000],
    ['js-cache.bin', 'Spotify/PersistentCache', 57230000],
  ] },
  { id: 'sc', label: 'System Caches (requires additional permission)', short: 'System Caches', root: '/Library/Caches', helper: true, files: [
    ['store.index', 'com.apple.iconservices.store', 182400000, 'caution'],
    ['Cache.db', 'com.apple.cloudkit', 96200000, 'caution'],
    ['update-cache.db', 'com.microsoft.autoupdate.helper', 41700000, 'caution'],
    ['data.bin', 'com.apple.amsengagementd', 11300000, 'caution'],
  ] },
].map(r => ({
  ...r,
  items: r.files.map((f, i) => ({
    id: r.id + i, name: f[0], dir: r.root + '/' + f[1], size: f[2], sev: f[3] || 'safe', helper: r.helper, rule: r.label, ruleShort: r.short,
  })),
}));

/* ---------- Duplicates (exact): first copy = newest by modified date = Keep ---------- */
SOS.DUPS = [
  { id: 'd1', name: 'onboarding-walkthrough.mov', size: 1240310000, copies: [['~/Movies/Exports', 'Nov 21, 2026 at 16:02'], ['~/Downloads', 'Nov 14, 2026 at 09:41']] },
  { id: 'd2', name: 'design-assets-v4.zip', size: 612300000, copies: [['~/Documents/Projects/Brand', 'Nov 18, 2026 at 14:20'], ['~/Downloads', 'Nov 18, 2026 at 14:05'], ['~/Desktop/Old', 'Nov 2, 2026 at 10:12']] },
  { id: 'd3', name: 'Figma-Installer.dmg', size: 214600000, copies: [['~/Downloads', 'Nov 10, 2026 at 11:30'], ['~/Downloads/Installers', 'Sep 30, 2026 at 17:44']] },
  { id: 'd4', name: 'node-v24.11.0.pkg', size: 78900000, copies: [['~/Downloads', 'Nov 4, 2026 at 08:03'], ['~/Desktop', 'Oct 29, 2026 at 19:20']] },
  { id: 'd5', name: 'Q3-report.pdf', size: 48200000, copies: [['~/Documents/Reports', 'Oct 20, 2026 at 15:55'], ['~/Downloads', 'Oct 12, 2026 at 12:10'], ['~/Desktop', 'Oct 12, 2026 at 12:09']] },
  { id: 'd6', name: 'IMG_4821.HEIC', size: 3400000, copies: [['~/Pictures/2026-10', 'Oct 3, 2026 at 18:31'], ['~/Desktop', 'Oct 3, 2026 at 18:30']] },
];
SOS.SIMILAR = [
  { id: 's1', name: 'IMG_5104.HEIC', copies: [['~/Pictures/2026-11', 'IMG_5104.HEIC', 3810000, 'Nov 9, 2026 at 17:22'], ['~/Pictures/2026-11', 'IMG_5103.HEIC', 3790000, 'Nov 9, 2026 at 17:22'], ['~/Pictures/2026-11', 'IMG_5102.HEIC', 3820000, 'Nov 9, 2026 at 17:21']] },
  { id: 's2', name: 'Screenshot 2026-11-12 at 10.14.08.png', copies: [['~/Desktop', 'Screenshot 2026-11-12 at 10.14.08.png', 1240000, 'Nov 12, 2026 at 10:14'], ['~/Desktop', 'Screenshot 2026-11-12 at 10.13.51.png', 1230000, 'Nov 12, 2026 at 10:13']] },
];
SOS.dupModel = (list, similar) => list.map(s => ({
  id: s.id, title: s.name, similar: !!similar,
  items: s.copies.map((c, i) => similar
    ? { id: s.id + '-' + i, name: c[1], dir: c[0], size: c[2], mod: c[3], keep: i === 0 }
    : { id: s.id + '-' + i, name: s.name, dir: c[0], size: s.size, mod: c[1], keep: i === 0 }),
}));

/* ---------- Uninstaller ---------- */
SOS.APPS = [
  { id: 'xcode', name: 'Xcode', ver: '16.4', bid: 'com.apple.dt.Xcode', store: true, size: 11820000000, support: 2140000000, cache: 864000000, c: '#3B82F6' },
  { id: 'docker', name: 'Docker', ver: '4.50.0', bid: 'com.docker.docker', store: false, size: 2310000000, support: 1420000000, cache: 96000000, c: '#38BDF8' },
  { id: 'keynote', name: 'Keynote', ver: '14.4', bid: 'com.apple.iWork.Keynote', store: true, size: 735200000, support: 41000000, cache: 12000000, c: '#6366F1' },
  { id: 'vscode', name: 'Visual Studio Code', ver: '1.106.2', bid: 'com.microsoft.VSCode', store: false, size: 627400000, support: 266400000, cache: 218600000, c: '#3B82F6' },
  { id: 'figma', name: 'Figma', ver: '125.10.4', bid: 'com.figma.Desktop', store: false, size: 512400000, support: 93600000, cache: 74800000, c: '#8B5CF6' },
  { id: 'slack', name: 'Slack', ver: '4.46.101', bid: 'com.tinyspeck.slackmacgap', store: false, size: 498200000, support: 402200000, cache: 188900000, c: '#E879F9' },
  { id: 'notion', name: 'Notion', ver: '4.22.1', bid: 'notion.id', store: false, size: 431000000, support: 184500000, cache: 22100000, c: '#7A73A8' },
  { id: 'spotify', name: 'Spotify', ver: '1.2.74', bid: 'com.spotify.client', store: false, size: 352900000, support: 57200000, cache: 612500000, c: '#2DD4BF' },
  { id: 'zoom', name: 'zoom.us', ver: '6.6.2', bid: 'us.zoom.xos', store: false, size: 287500000, support: 31000000, cache: 41300000, c: '#38BDF8' },
  { id: 'raycast', name: 'Raycast', ver: '1.104.0', bid: 'com.raycast.macos', store: false, size: 214800000, support: 88000000, cache: 9600000, c: '#F87171' },
];
SOS.appItems = a => {
  const b = a.bid;
  const base = a.store ? '~/Library/Containers/' : '~/Library/Application Support/';
  return [
    { id: a.id + '-app', name: a.name + '.app', dir: '/Applications', size: a.size, src: 'Application bundle' },
    { id: a.id + '-sup', name: b, dir: base.replace(/\/$/, ''), size: null, folder: true, src: 'Associated with ' + b },
    { id: a.id + '-cac', name: b, dir: '~/Library/Caches', size: null, folder: true, src: 'Associated with ' + b },
    { id: a.id + '-pre', name: b + '.plist', dir: '~/Library/Preferences', size: 12400, src: 'Associated with ' + b },
    { id: a.id + '-sav', name: b + '.savedState', dir: '~/Library/Saved Application State', size: null, folder: true, src: 'Associated with ' + b },
  ];
};
/* Folder sizes are not trustworthy today (inventory D1), so folders carry no size and totals read "at least". */
SOS.appTotal = a => SOS.appItems(a).reduce((s, i) => s + (i.size || 0), 0);
SOS.appFolders = items => items.filter(i => i.folder).length;

/* ---------- Updater ---------- */
SOS.UPD = {
  updates: [['slack', '4.45.64', '4.46.101'], ['zoom', '6.5.11', '6.6.2'], ['raycast', '1.103.2', '1.104.0']],
  store: [['xcode', '16.4'], ['keynote', '14.4']],
  current: [['figma', '125.10.4'], ['notion', '4.22.1'], ['spotify', '1.2.74'], ['vscode', '1.106.2']],
  nofeed: [['docker', '4.50.0']],
};

/* ---------- Space Lens ---------- */
SOS.LENS = {
  home: { label: 'Home', path: '~', children: [
    ['Library', 182410000000, 412903, 'Nov 26, 2026 at 09:12', 'library', 'protected'],
    ['Documents', 64200000000, 18233, 'Nov 25, 2026 at 18:40'],
    ['Movies', 58940000000, 612, 'Nov 21, 2026 at 11:02'],
    ['Pictures', 41730000000, 23411, 'Nov 22, 2026 at 20:15'],
    ['Developer', 37520000000, 284190, 'Nov 26, 2026 at 08:55'],
    ['Downloads', 22810000000, 1204, 'Nov 26, 2026 at 10:41', 'downloads'],
    ['Music', 12340000000, 3920, 'Oct 30, 2026 at 21:07'],
    ['Desktop', 8620000000, 388, 'Nov 25, 2026 at 16:30'],
    ['Applications', 3100000000, 2, 'Sep 14, 2026 at 10:00'],
    ['Public', 1200000, 2, 'Aug 2, 2026 at 09:00'],
  ] },
  downloads: { label: 'Downloads', path: '~/Downloads', children: [
    ['raw-footage-2026-09.zip', 6420000000, null, 'Sep 28, 2026 at 19:04', null, 'file'],
    ['Old Installers', 4180000000, 37, 'Oct 30, 2026 at 12:15'],
    ['Xcode_16.4.xip', 3210000000, null, 'Aug 21, 2026 at 09:12', null, 'file'],
    ['conference-talk.mov', 2860000000, null, 'Oct 14, 2026 at 17:40', null, 'file'],
    ['Archive 2025', 2260000000, 512, 'Jan 6, 2026 at 10:02'],
    ['dataset-export.csv.gz', 1940000000, null, 'Nov 19, 2026 at 15:33', null, 'file'],
    ['Screenshots', 1120000000, 612, 'Nov 26, 2026 at 10:41'],
    ['design-assets-v4.zip', 612300000, null, 'Nov 18, 2026 at 14:05', null, 'file'],
    ['Figma-Installer.dmg', 214600000, null, 'Nov 10, 2026 at 11:30', null, 'file'],
  ] },
  library: { label: 'Library', path: '~/Library', children: [
    ['Containers', 64100000000, 98211, 'Nov 26, 2026 at 09:12'],
    ['Application Support', 48300000000, 120384, 'Nov 26, 2026 at 09:10'],
    ['Developer', 31900000000, 141022, 'Nov 26, 2026 at 08:55'],
    ['Caches', 18200000000, 39120, 'Nov 26, 2026 at 09:12'],
    ['Group Containers', 9400000000, 8412, 'Nov 25, 2026 at 22:01'],
    ['Mail', 6100000000, 4210, 'Nov 26, 2026 at 07:30'],
    ['Messages', 3300000000, 1650, 'Nov 25, 2026 at 21:44'],
    ['Logs', 910000000, 512, 'Nov 26, 2026 at 09:00'],
    ['Preferences', 200000000, 1384, 'Nov 26, 2026 at 09:11'],
  ] },
};
SOS.TYPES = [
  ['Other', 165400000000, '#7A73A8', 'doc'],
  ['Video', 71300000000, '#8B5CF6', 'film'],
  ['Documents', 52100000000, '#3B82F6', 'doc'],
  ['Images', 48600000000, '#E879F9', 'photo'],
  ['Code', 33800000000, '#6366F1', 'code'],
  ['Archives', 27500000000, '#38BDF8', 'box'],
  ['Applications', 18900000000, '#A78BFA', 'app'],
  ['Audio', 14200000000, '#2DD4BF', 'music'],
];

/* ---------- Cloud ---------- */
SOS.ICLOUD = [
  { id: 'c1', name: 'Team-offsite-photos.zip', size: 1380000000, copies: [['iCloud Drive/Shared', 'Nov 16, 2026 at 12:40'], ['iCloud Drive/Downloads', 'Nov 16, 2026 at 12:38']] },
  { id: 'c2', name: 'Podcast-ep12.m4a', size: 96400000, copies: [['iCloud Drive/Audio', 'Nov 3, 2026 at 09:15'], ['iCloud Drive/Desktop', 'Oct 28, 2026 at 18:02']] },
  { id: 'c3', name: 'Brand-guidelines.pdf', size: 22600000, copies: [['iCloud Drive/Documents/Brand', 'Oct 22, 2026 at 11:00'], ['iCloud Drive/Documents', 'Oct 22, 2026 at 10:58'], ['iCloud Drive/Desktop', 'Sep 9, 2026 at 14:31']] },
  { id: 'c4', name: 'Budget-2026.numbers', size: 4200000, copies: [['iCloud Drive/Numbers', 'Nov 24, 2026 at 17:05'], ['iCloud Drive/Documents', 'Nov 1, 2026 at 08:47']] },
];
SOS.DRIVE = [
  { id: 'g1', name: 'Product-demo-final.mp4', size: 842000000, copies: [['', 'Nov 20, 2026 at 15:10'], ['', 'Nov 19, 2026 at 09:02']] },
  { id: 'g2', name: 'Contract-template.docx', size: 1800000, copies: [['', 'Nov 12, 2026 at 10:21'], ['', 'Oct 2, 2026 at 16:45'], ['', 'Sep 18, 2026 at 11:30']] },
];

/* ---------- Protection ---------- */
SOS.LOCATIONS = ['Downloads', 'User Login Items', 'System Login Items', 'System Daemons', 'Chrome Extensions', 'Firefox Extensions'];
SOS.FINDINGS = [
  { id: 'f1', name: 'eicar_test.com', dir: '~/Downloads', size: 68, method: 'Known signature', ident: 'EICAR-Test-File', date: 'Nov 26, 2026 at 10:42' },
];
SOS.QUAR = [
  { id: 'q1', name: 'eicar.com.txt', from: '~/Downloads/old', date: 'Nov 24, 2026 at 16:08' },
  { id: 'q2', name: 'eicar_com.zip', from: '~/Downloads', date: 'Nov 24, 2026 at 16:08' },
];
