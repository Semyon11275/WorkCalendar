"""Import through the running application's authenticated loopback API; never write its JSON directly."""
import argparse, json, pathlib, hashlib, http.client, urllib.parse, sys

def main():
    p=argparse.ArgumentParser(description='工作日历 Agent 一键导入')
    p.add_argument('--connection',required=True,help='userdata/agent_connection.json')
    group=p.add_mutually_exclusive_group(required=True)
    group.add_argument('--import',dest='file',help='JSON 或 Markdown 文件')
    group.add_argument('--import-awards',dest='awards',help='获奖 JSON 文件')
    group.add_argument('--import-dir',dest='directory',help='旧版 data 目录，含原始凭证')
    p.add_argument('--update-existing',action='store_true')
    p.add_argument('--preview',action='store_true',help='仅解析预览，不上传凭证或写入记录')
    args=p.parse_args()
    cfg=json.loads(pathlib.Path(args.connection).read_text(encoding='utf-8-sig'))
    base=urllib.parse.urlsplit(cfg['url'])
    if base.scheme!='http' or base.hostname not in ('127.0.0.1','localhost','::1'):
        raise ValueError('只允许本机回环 API')
    token=pathlib.Path(cfg['token_file']).read_text(encoding='utf-8-sig').strip()
    def request(path,body,content_type='application/json',length=None):
        conn=http.client.HTTPConnection(base.hostname,base.port,timeout=120)
        headers={'X-API-Token':token,'Content-Type':content_type}
        if length is not None: headers['Content-Length']=str(length)
        try:
            conn.request('POST',path,body=body,headers=headers)
            response=conn.getresponse();data=json.loads(response.read())
            if response.status>=300:raise RuntimeError(data)
            return data
        finally:conn.close()
    if args.directory:
        root=pathlib.Path(args.directory).resolve();payload={}
        for key in ('competitions','awards'):
            path=root/(key+'.json')
            data=json.loads(path.read_text(encoding='utf-8-sig')) if path.exists() else []
            payload[key]=data.get(key,[]) if isinstance(data,dict) else data
        names={n for a in payload['awards'] for n in a.get('certificate_files',[])}
        sources={}
        for name in names:
            source=(root/'certificates'/name).resolve()
            if not source.is_relative_to(root/'certificates') or not source.is_file():
                raise ValueError('凭证路径无效或缺失：'+name)
            sources[name]=source
        if not args.preview:
            mapping={}
            for i,(name,source) in enumerate(sorted(sources.items())):
                with source.open('rb') as f: digest=hashlib.file_digest(f,'sha256').hexdigest()
                with source.open('rb') as f:
                    result=request('/api/certificates?'+urllib.parse.urlencode({'name':name,'sha256':digest}),f,'application/octet-stream',source.stat().st_size)
                mapping[name]=result['name'];print(f'凭证 {i+1}/{len(sources)} 已校验',file=sys.stderr)
            for a in payload['awards']:a['certificate_files']=[mapping[n] for n in a.get('certificate_files',[])]
    else:
        text=pathlib.Path(args.awards or args.file).read_text(encoding='utf-8-sig')
        if args.awards:
            data=json.loads(text)
            payload={'awards':data.get('awards',[data]) if isinstance(data,dict) else data}
        else:payload=text
    result=request('/api/import',json.dumps({'data':payload,'preview':args.preview,'update_existing':args.update_existing},ensure_ascii=False).encode('utf-8'))
    print(json.dumps(result,ensure_ascii=False,indent=2))
    if result.get('ok') is False: return 1
    return 0
if __name__=='__main__':
    try:sys.exit(main())
    except Exception as e:print('导入未完成：'+str(e),file=sys.stderr);sys.exit(1)
