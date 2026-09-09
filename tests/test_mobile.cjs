const fs = require('fs'), vm = require('vm'), assert = require('assert');
const source = fs.readFileSync(require('path').join(__dirname,'../web/core.js'),'utf8');
async function check(label, initial, expectedError, expectedCount) {
  const files = new Map(Object.entries(initial)), writes = [];
  const plugin = {
    mkdir:async()=>{},
    readFile:async ({path})=> { if (!files.has(path)) throw new Error('ENOENT'); return {data:files.get(path)}; },
    writeFile:async ({path,data})=> { writes.push(path); files.set(path,data); },
    rename:async ({from,to})=> {files.set(to,files.get(from));files.delete(from);},
    readdir:async ({path})=>({files:[...files.keys()].filter(p=>p.startsWith(path+'/')).map(p=>({name:p.slice(path.length+1)}))}),
    deleteFile:async ({path})=>files.delete(path),
  };
  const context={console,URL,Date,JSON,Math,Promise,setTimeout,clearTimeout,
    localStorage:{getItem:()=>null,setItem:()=>{}}, location:{search:'',protocol:'https:',hostname:'localhost'},
    document:{addEventListener:()=>{},getElementById:()=>null,documentElement:{classList:{contains:()=>false}}},
    window:{addEventListener:()=>{},Capacitor:{isNativePlatform:()=>true,Plugins:{Filesystem:plugin}}}};
  vm.createContext(context);vm.runInContext(source,context);
  let error;
  try {await vm.runInContext('LOC.init()',context);} catch(e){error=e;}
  assert.equal(!!error, expectedError,label);
  if (expectedError) {
    assert.equal(files.get('wc_data/competitions.json'),'{broken',label);
    assert(writes.some(p=>p.endsWith('.corrupt')),label);
  } else assert.equal(vm.runInContext('LOC.comps.length',context),expectedCount,label);
  console.log('PASS',label);
}
(async()=>{
  await check('first launch creates empty files',{},false,0);
  await check('corruption without backup preserves original',{'wc_data/competitions.json':'{broken'},true);
  await check('recover latest valid backup, skipping corrupt backup',{
    'wc_data/competitions.json':'{broken',
    'wc_data/backups/competitions_999.json':'{broken',
    'wc_data/backups/competitions_998.json':JSON.stringify({competitions:[{id:'a',name:'Recovered'}]}),
  },false,1);
  const xlsx=require('../web/assets/xlsx.full.min.js');
  assert.equal(xlsx.version,'0.20.3');
  const book=xlsx.utils.book_new();xlsx.utils.book_append_sheet(book,xlsx.utils.aoa_to_sheet([['Name'],['Test']]),'Test');
  const restored=xlsx.read(xlsx.write(book,{type:'buffer',bookType:'xlsx'}),{type:'buffer'});
  assert.equal(xlsx.utils.sheet_to_json(restored.Sheets.Test)[0].Name,'Test');
  console.log('PASS SheetJS version and workbook roundtrip');
})().catch(e=>{console.error(e);process.exitCode=1;});
