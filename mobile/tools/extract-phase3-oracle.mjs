// Oracle độc lập lấy từ hàm React thật; chỉ ghi test fixture trong dự án Flutter.
import {register} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
register('file:///D:/UI%20AI%20Review/tests/ts-loader.mjs',import.meta.url);
const {mockEvaluation}=await import('file:///D:/UI%20AI%20Review/src/lib/rubric.ts');
const s=JSON.parse(await readFile('D:/SRS-Review-AI-Mobile/assets/fixtures/academic.json','utf8'));
const cases=[];
for(const rule of s.ruleSets)for(const title of Object.keys(s.documentSamples)){
  const input={id:'oracle',reviewId:'oracle-review',documentId:'oracle-doc',documentVersionId:'oracle-v1',documentVersion:'v1',
    ruleSetId:rule.id,ruleSetVersion:rule.version??1,ruleSnapshot:rule,evaluationStatus:'loading',criterionResults:[],overallScore:null,maxScore:0,findings:[],createdAt:'oracle-time'};
  cases.push({title,input,expected:mockEvaluation(input,title)});
}
await mkdir('D:/SRS-Review-AI-Mobile/test/fixtures',{recursive:true});
await writeFile('D:/SRS-Review-AI-Mobile/test/fixtures/react-review-oracle.json',JSON.stringify(cases,null,2));
console.log(`${cases.length} kịch bản từ React`);
