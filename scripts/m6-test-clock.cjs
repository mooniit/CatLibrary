// Test harness only: loopback host advances recorded synthetic cats, never production RPCs.
const fs=require('node:fs'),http=require('node:http'),assert=require('node:assert/strict'),{execFileSync}=require('node:child_process');
const f=JSON.parse(fs.readFileSync('.tooling/m6-test-fixture.json')),config=JSON.parse(fs.readFileSync('.tooling/m6-integration-defines.json'));
assert.equal(f.scope,'isolated-local-M6');assert.match(f.home,/^[0-9a-f-]{36}$/);f.cats.forEach(id=>assert.match(id,/^[0-9a-f-]{36}$/));assert(config.M6_CLOCK_NONCE);
const server=http.createServer(async(req,res)=>{
  try{
    assert.equal(req.method,'POST');assert.equal(req.url,'/m6/return');
    let body='';for await(const part of req){body+=part;assert(body.length<1024);}
    const p=JSON.parse(body);assert.equal(p.nonce,config.M6_CLOCK_NONCE);assert(f.cats.includes(p.cat));
    const sql=`update public.cat_trips set destination='palace',started_at=now()-interval '25 hours',ends_at=now()-interval '1 hour' where family_id='${f.home}' and cat_id='${p.cat}' and returned_at is null`;
    const out=execFileSync('docker',['exec','supabase_db_CatLibrary','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atc',sql],{encoding:'utf8'}).trim();assert.equal(out,'UPDATE 1');
    res.writeHead(200,{'Content-Type':'application/json'});res.end('{"advanced":true}');
  }catch(_){res.writeHead(403);res.end('{"advanced":false}');}
});
server.listen(54329,'127.0.0.1',()=>console.log('Isolated M6 test clock ready on loopback; two recorded cats only'));
