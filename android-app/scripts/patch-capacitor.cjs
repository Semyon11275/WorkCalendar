// Capacitor 6 imports tar's removed default export; retain its runtime API with tar 7.
const fs = require('fs');
const path = require('path');
const root = path.dirname(require.resolve('@capacitor/cli/package.json'));
const version = require('@capacitor/cli/package.json').version;
if (version !== '6.2.2') throw new Error('Review tar compatibility patch for CLI ' + version);
const file = path.join(root, 'dist/util/template.js');
const from = 'const tar_1 = tslib_1.__importDefault(require("tar"));';
const to = 'const tar_1 = { default: require("tar") };';
const text = fs.readFileSync(file, 'utf8');
if (!text.includes(from) && !text.includes(to)) throw new Error('Unexpected Capacitor template implementation');
fs.writeFileSync(file, text.replace(from, to));
