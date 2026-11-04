// Copy complete faces from Forge's existing cache, without changing Forge or its decks.
import {readFileSync, readdirSync, existsSync, mkdirSync, copyFileSync, writeFileSync} from 'node:fs';
import {join, resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cache = join(process.env.LOCALAPPDATA, 'Forge/Cache/pics/cards');
const decks = join(process.env.APPDATA, 'Forge/decks/commander');
const downloadMissing = process.argv.includes('--download-missing');
const names = process.argv.slice(2).filter(arg => arg !== '--download-missing');
if (!names.length) names.push('Atraxa', 'AtraxaV2', 'Doom Commander');
const clean = name => name.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/["/:?]/g, '');
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const patternFor = name => new RegExp('^' + escape(clean(name)) + '(\\d*)\\.full(?:border)?\\.(jpg|png)$', 'i');
// Forge stores flavor-name printings under their displayed names in its cache.
const editions = new Map();
const editionRoot = resolve(root, '../forge/forge-gui/res/editions');
if (existsSync(editionRoot)) for (const file of readdirSync(editionRoot).filter(file => file.endsWith('.txt'))) {
  const text = readFileSync(join(editionRoot, file), 'utf8');
  const code = text.match(/^Code=(.+)\r?$/m)?.[1].trim();
  if (code) editions.set(code, text.split(/\r?\n/));
}
const target = join(root, 'assets/cards');
mkdirSync(target, {recursive:true});
const manifest = {byKey:{}, byName:{}, decks:{}, source:'Existing local Forge card-image cache; artwork copyright Wizards of the Coast and respective licensors.'};
const missing = [];
let bytes = 0;
const imported = new Set();
const downloadIndexPath = join(target, 'downloads.json');
const downloads = existsSync(downloadIndexPath) ? JSON.parse(readFileSync(downloadIndexPath, 'utf8')) : {};
const availableSets = readdirSync(cache).sort();
for (const deck of names) {
  const entries = readFileSync(join(decks, deck + '.dck'), 'utf8').split(/\r?\n/).flatMap(line => {
    const match = line.match(/^\d+ (.+?)\|([^|]+)\|\[([^\]]+)\]/);
    return match ? [{name:match[1].replace(/\+$/, ''), set:match[2], collector:match[3]}] : [];
  });
  if (!entries.length) throw Error('No card entries in ' + deck);
  manifest.decks[deck] = entries;
  for (const entry of entries) {
    let imageSet = entry.set;
    let folder = join(cache, imageSet);
    const printings = (editions.get(entry.set) || []).filter(line => new RegExp('^\\S+ [A-Z] ' + escape(entry.name) + '(?: @| \\$|$)').test(line));
    const printing = printings.find(line => line.startsWith(entry.collector + ' '));
    const properties = printing?.includes('${') ? JSON.parse(printing.slice(printing.indexOf('${') + 1)) : {};
    const displayName = properties.flavorName || entry.name;
    let pattern = patternFor(displayName);
    let matches = existsSync(folder) ? readdirSync(folder).filter(file => pattern.test(file)).sort() : [];
    if (!matches.length) {
      pattern = patternFor(entry.name);
      for (const set of availableSets) {
        const other = join(cache, set);
        let candidates;
        try {candidates = readdirSync(other).filter(file => pattern.test(file)).sort();} catch {continue;}
        if (candidates.length) {imageSet = set; folder = other; matches = candidates.slice(0, 1); break;}
      }
    }
    if (!matches.length) {
      if (!downloads[entry.name] && downloadMissing) {
        await new Promise(ok => setTimeout(ok, 150));
        const headers = {'User-Agent':'ForgeUIPrototype/1.0 (local card-image importer)', 'Accept':'application/json'};
        let response = await fetch(`https://api.scryfall.com/cards/${entry.set.toLowerCase()}/${encodeURIComponent(entry.collector)}`, {headers});
        if (!response.ok) {
          await new Promise(ok => setTimeout(ok, 150));
          response = await fetch('https://api.scryfall.com/cards/named?exact=' + encodeURIComponent(entry.name), {headers});
        }
        if (!response.ok) throw Error(`No image metadata for ${entry.name}: HTTP ${response.status}`);
        const card = await response.json();
        if (card.name !== entry.name && !card.name.startsWith(entry.name + ' // ')) throw Error('Card name mismatch: ' + card.name);
        const url = (card.image_uris ?? card.card_faces?.[0]?.image_uris)?.large;
        if (!url) throw Error('No complete front image for ' + entry.name);
        const picture = await fetch(url, {headers:{'User-Agent':headers['User-Agent']}});
        if (!picture.ok || !picture.headers.get('content-type')?.startsWith('image/')) throw Error('Image download failed: ' + entry.name);
        const file = createHash('sha256').update(url).digest('hex').slice(0, 20) + '.jpg';
        writeFileSync(join(target, file), Buffer.from(await picture.arrayBuffer()));
        downloads[entry.name] = {path:'res://assets/cards/' + file, source:card.scryfall_uri, image:url, set:card.set, collector:card.collector_number, artist:card.artist};
        writeFileSync(downloadIndexPath, JSON.stringify(downloads, null, 2) + '\n');
        console.log('Downloaded: ' + entry.name);
      }
      if (downloads[entry.name]) manifest.byName[entry.name] = downloads[entry.name].path;
      else missing.push(entry);
      continue;
    }
    for (const file of matches) {
      const match = file.match(pattern);
      const id = createHash('sha256').update(imageSet + '/' + file).digest('hex').slice(0, 20) + '.' + match[2].toLowerCase();
      const resource = 'res://assets/cards/' + id;
      if (!imported.has(id)) {
        copyFileSync(join(folder, file), join(target, id));
        bytes += readFileSync(join(target, id)).length;
        imported.add(id);
      }
      const artIndex = displayName !== entry.name && imageSet === entry.set ? printings.indexOf(printing) + 1 : match[1] || '1';
      manifest.byKey[`c:${entry.name}|${imageSet}|${artIndex}`] = resource;
      manifest.byName[entry.name] ??= resource;
      if (imageSet === entry.set) manifest.byName[displayName] ??= resource;
    }
  }
}
writeFileSync(join(target, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Imported ${imported.size} faces (${(bytes/1048576).toFixed(1)} MB) for ${names.join(', ')}.`);
console.log(`Coverage: ${Object.keys(manifest.byName).length} unique names; ${missing.length} missing deck entries.`);
if (missing.length) {console.log(JSON.stringify(missing, null, 2)); process.exitCode = 1;}
