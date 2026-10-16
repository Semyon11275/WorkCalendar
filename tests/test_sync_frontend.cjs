const fs = require('fs'), vm = require('vm'), assert = require('assert');
const code = fs.readFileSync(require('path').join(__dirname,'../web/core.js'),'utf8');
async function scenario(preview, fail=false) {
  const files=new Map([['wc_data/certificates/a.png','ORIGINAL']]), calls=[], messages=[];
  const plugin={mkdir:async()=>{},readFile:async({path})=>{if(!files.has(path))throw Error('ENOENT');return {data:files.get(path)};},
    stat:async({path})=>{if(!files.has(path))throw Error('ENOENT');return {};},
    writeFile:async({path,data})=>files.set(path,data),rename:async({from,to})=>{files.set(to,files.get(from));files.delete(from);},readdir:async()=>({files:[]})};
  const ctx={console,URL,URLSearchParams,Date,JSON,Math,Promise,setTimeout,clearTimeout,
    localStorage:{getItem:()=>JSON.stringify({token:'phone'}),setItem:()=>{}},location:{search:'',protocol:'https:',hostname:'localhost'},
    document:{addEventListener:()=>{},getElementById:()=>null,documentElement:{classList:{contains:()=>false}}},
    toast:m=>messages.push(m),fetch:()=>{throw Error('Browser fetch must not be used');},
    window:{addEventListener:()=>{},Capacitor:{isNativePlatform:()=>true,Plugins:{Filesystem:plugin,CapacitorHttp:{request:async opts=>{
      calls.push(opts);assert.equal(opts.headers['X-Sync-Token'],'phone');
      return {data: fail?{ok:false,error:'unauthorized'}:opts.url.includes('preview=1')?{ok:preview,preview:true,data:'/9j/PREVIEW'}:{ok:true,preview:false,data:'JVBERPDF'}};
    }}}}}};
  vm.createContext(ctx);vm.runInContext(code,ctx);
  const result=await vm.runInContext("syncCertificates('http://192.168.1.2:17865',[{certificate_files:['a.png','b.pdf','../private']}])",ctx);
  assert.equal(files.get('wc_data/certificates/a.png'),'ORIGINAL');
  assert.equal(result.failed,fail?2:1);assert(!calls.some(c=>c.url.includes('private')));
  if(preview&&!fail){assert.equal(files.get('wc_data/certificates/a.png.preview.jpg'),'/9j/PREVIEW');assert((await vm.runInContext("certUrl('a.png')",ctx)).startsWith('data:image/jpeg;'));}
  if(!fail)assert.equal(files.get('wc_data/certificates/b.pdf'),'JVBERPDF');
  assert(messages.at(-1).includes('失败'));
}
(async()=>{await scenario(true);await scenario(false);await scenario(false,true);console.log('PASS native sync, preview separation, original preservation, missing preview fallback, path validation and visible failures');})().catch(e=>{console.error(e);process.exitCode=1;});
