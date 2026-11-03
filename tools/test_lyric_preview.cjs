const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(root,'material/lyrics_preview/preview.html'),'utf8');
const template=fs.readFileSync(path.join(root,'tools/lyric_preview.template.html'),'utf8');
const payload=JSON.parse(html.match(/const D=(.*);\r?\n/)[1]);
const begin=template.indexOf('    function chooseLine(');
const end=template.indexOf('    function render(',begin);
assert(begin>=0&&end>begin,'Missing sentence selection helper');
const choose=vm.runInNewContext(template.slice(begin,end)+';chooseLine',{D:{lines:payload.lines}});
let checks=0;
function check(condition,message){assert(condition,message);checks++;}
check(choose(payload.lines[0].s-.01).line===null,'Lyrics appeared before first sung word');
for(let i=0;i<payload.lines.length;i++){
  const line=payload.lines[i];
  check(choose(line.s).index===i,`Line ${i+1} missing at exact start`);
  check(choose(line.s+.02).index===i,`Previous line masks line ${i+1}`);
  check(choose(line.e-.001).index===i,`Line ${i+1} cut before held final note ended`);
  check(choose(line.e-.001).opacity===1,`Line ${i+1} faded before held final note ended`);
  if(i>0)check(choose(line.s-.001).index!==i,`Line ${i+1} selected early`);
  if(i===payload.lines.length-1 || payload.lines[i+1].s>line.e+.31)
    check(choose(line.e+.301).line===null,`Line ${i+1} retained too long in instrumental gap`);
}
const result={checks,phrases:payload.lines.length,status:'PASS',
  cases:'Exact starts, 20ms after starts, no early next sentence, full long-note visibility, 300ms maximum post-roll'};
fs.writeFileSync(path.join(root,'material/lyrics_preview/sentence_timing_tests.json'),JSON.stringify(result,null,2));
console.log(result);
