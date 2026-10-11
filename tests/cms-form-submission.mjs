import fs from 'node:fs';
import assert from 'node:assert/strict';
const {JSDOM,VirtualConsole}=await import(process.env.JSDOM_MODULE||'jsdom');
const errors=[];const vc=new VirtualConsole();vc.on('jsdomError',err=>errors.push(err));
const html='<dialog id="modal"><div id="modalContent"></div></dialog><div id="toast"></div>';
const dom=new JSDOM(html,{url:'https://example.invalid',runScripts:'dangerously',virtualConsole:vc});
const w=dom.window;w.OCCCI_SUPABASE_CONFIG={url:'https://example.invalid',publishableKey:'test'};
w.HTMLDialogElement.prototype.showModal=function(){this.open=true};w.HTMLDialogElement.prototype.close=function(){this.open=false};
const script=w.document.createElement('script');script.textContent=fs.readFileSync('dist/ui.js','utf8')+'\n'+fs.readFileSync('dist/reports.js','utf8')+'\n'+fs.readFileSync('dist/staff-invites.js','utf8')+'\n'+fs.readFileSync('dist/finance.js','utf8')+'\n'+fs.readFileSync('dist/app.js','utf8').replace(/init\(\);\s*$/,'');w.document.body.append(script);
const calls=[];w.api=async(path,data)=>{calls.push({path,...data});if(path.includes('grant_type=password'))return {access_token:'fresh-test-token',user:{id:'staff'}};if(path.includes('occci_begin_position_confirmation'))return 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';return null};w.reload=async()=>{};w.render=()=>{};w.loadBranches=async()=>{};w.toast=()=>{};
w.eval(`S.session={user:{id:'staff',email:'admin@example.invalid'},expires_at:9999999999};S.role='BM';S.branches=[{id:'a',name:'Ormoc',district:1,active:true}];S.assignment={role:'BM',branch_id:'a'};S.profiles=[{id:'member',branch_id:'a',full_name:'Test Member',account_number:null,membership_status:'Pending verification',first_name:'Test',last_name:'Member',middle_name:'',contact_number:'09123456789',address:'Ormoc City',avatar:'man'}];`);
async function submit(values){const form=w.document.querySelector('form');for(const [name,value] of Object.entries(values))form.elements[name].value=value;assert(form.checkValidity(),'Form must be valid');form.requestSubmit();await new Promise(r=>setTimeout(r,10));assert.equal(errors.length,0,errors.map(e=>e.message).join('\n'));}
w.membershipDialog('member');await submit({account:'OCCCI-0001',reason:'Verified membership register'});assert.equal(calls.at(-1).path,'/rest/v1/rpc/occci_approve_member');assert.equal(calls.at(-1).data.account,'OCCCI-0001');
w.eval(`S.role='Admin'`);w.removeDialog('Member','member');w.document.querySelector('[data-admin-password]').value='fixture-password';await submit({reason:'Duplicate profile archived'});assert.equal(calls.findLast(c=>c.path==='/rest/v1/rpc/occci_manage_record').data.remove_record,true);assert(calls.some(c=>c.path==='/auth/v1/logout?scope=local'));
w.eval(`S.role='BM'`);w.accountDialog('member');await submit({account:'OCCCI-0002',reason:'Official branch number'});assert.equal(calls.at(-1).path,'/rest/v1/rpc/occci_assign_account');
w.eval(`S.role='Staff'`);w.editDialog('member');assert(!w.document.querySelector('[name=first_name]'),'Staff cannot edit before permission');await submit({reason:'Request contact correction'});assert.equal(calls.at(-1).data.values_json.permission_only,true);
w.eval(`S.requests=[{id:'permission',branch_id:'a',member_id:'member',kind:'Profile edit',status:'BM approved',submitted_by:'staff',proposed:{permission_only:true}}]`);w.requestDialog('permission');assert(w.document.querySelector('button[onclick*="editDialog"]'));w.editDialog('member','permission');await submit({reason:'Updated from official form'});assert.equal(calls.at(-1).path,'/rest/v1/rpc/occci_apply_authorized_edit');assert.equal(calls.at(-1).data.request_id,'permission');
w.eval(`S.profiles[0].revision=2;S.requests[0].base_revision=1`);w.editPermissionDialog('member');assert(w.document.querySelector('textarea[name=reason]'),'A stale approval must allow a fresh permission request');assert(!w.document.querySelector('[name=first_name]'));
w.eval(`S.role='DM';S.assignment={role:'DM',district:1}`);assert(w.canReview({member_id:'member',branch_id:'a',kind:'Profile edit',status:'Pending',submitted_by:'other'}));
w.eval(`S.role='Staff';S.assignment={role:'Staff',branch_id:'a'}`);w.syncDialog('member');assert(w.document.querySelector('[name=evidence]').multiple);assert(!w.document.querySelector('[name=source_reference]').required);
const docs=[{name:'ledger.xlsx',size:1024},{name:'form.docx',size:2048}];w.validateDocuments(docs);assert.throws(()=>w.validateDocuments([]));assert.throws(()=>w.validateDocuments([{size:11*1024*1024}]));
// Exercise the actual multi-file handler with native File/FormData objects.
w.eval(`S.role='Staff';S.profiles[0].membership_status='Active';S.profiles[0].account_number='OCCCI-0002'`);
const NativeFormData=w.FormData;const originalFiles=[new w.File(['ledger'],'ledger.xlsx',{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}),new w.File(['form'],'form.docx',{type:'application/vnd.openxmlformats-officedocument.wordprocessingml.document'})];
w.syncDialog('member');
function addFiles(files){const input=w.document.querySelector('[name=evidence]');Object.defineProperty(input,'files',{configurable:true,value:files});w.showSelectedDocuments(input);}
addFiles([originalFiles[0]]);addFiles([originalFiles[1]]);
assert.equal(w.document.querySelectorAll('#selectedDocuments li').length,2,'Selections accumulate');
assert.equal(w.document.querySelector('#documentCount').textContent,'2 / 10 files');
assert.equal(w.document.querySelector('.document-remove').type,'button');
w.document.querySelector('.document-remove').click();
assert.equal(w.document.querySelectorAll('#selectedDocuments li').length,1);
assert(w.document.querySelector('#selectedDocuments').textContent.includes('form.docx'));
addFiles([originalFiles[0]]);
addFiles(Array.from({length:8},(_,i)=>new w.File(['test'],`record-${i}.pdf`)));
assert.equal(w.document.querySelectorAll('#selectedDocuments li').length,10);
assert(w.document.querySelector('.document-add').disabled);
addFiles([new w.File(['extra'],'extra.pdf')]);
assert.equal(w.document.querySelectorAll('#selectedDocuments li').length,10);
assert(!w.document.querySelector('#documentError').hidden);
w.removeSelectedDocument(w.document.querySelector('form'),9);
assert(!w.document.querySelector('.document-add').disabled);
for(let i=8;i>=2;i--)w.removeSelectedDocument(w.document.querySelector('form'),i);
addFiles([{name:'oversize.pdf',size:11*1024*1024}]);
assert.equal(w.document.querySelectorAll('#selectedDocuments li').length,2,'Invalid selections preserve the draft');
// Removed files must not be uploaded; accumulated actual File objects must be uploaded.
await w.handleCmsAction(w.document.querySelector('form'),'sync','member');assert.equal(calls.at(-1).path,'/rest/v1/rpc/occci_submit_financial_documents');assert.equal(calls.at(-1).data.documents.length,2);assert(calls.at(-1).data.documents[0].path.endsWith('.docx'));assert(calls.at(-1).data.documents[1].path.endsWith('.xlsx'));assert.equal(calls.at(-1).data.values_json.source_reference,'form.docx; ledger.xlsx');
w.syncDialog('member');const beforeEmpty=calls.length;await w.handleCmsAction(w.document.querySelector('form'),'sync','member');assert.equal(calls.length,beforeEmpty);assert(w.document.getElementById('actionMessage').textContent.includes('1 to 10'));
addFiles(originalFiles);w.api=async()=>{throw Error('Temporary upload failure');};await w.handleCmsAction(w.document.querySelector('form'),'sync','member');assert.equal(w.document.querySelectorAll('#selectedDocuments li').length,2);assert(!w.document.querySelector('.document-add').disabled);assert(!w.document.querySelector('.document-remove').disabled);
w.FormData=NativeFormData;w.api=async()=>{throw Error('This account number is already assigned.');};w.eval(`S.role='BM'`);w.membershipDialog('member');await submit({account:'OCCCI-0002',reason:'Check duplicate recovery'});assert(w.document.getElementById('actionMessage').textContent.includes('already assigned'));assert(!w.document.querySelector('button[type=submit]').disabled);
// Confirm the original collision independently, without real requests or data.
const oldErrors=[];const oldVc=new VirtualConsole();oldVc.on('jsdomError',e=>oldErrors.push(e));const old=new JSDOM('<form onsubmit="event.preventDefault();action(this)"><button>Confirm</button></form><script>function action(){}</script>',{runScripts:'dangerously',virtualConsole:oldVc});old.window.document.querySelector('form').requestSubmit();assert(oldErrors.some(e=>e.message.includes('action is not a function')),'Reproduce original browser form-property collision');
console.log('PASS: native form submission for approval/archive/ID assignment, original action collision reproduced, Staff permission before fields, approved edit RPC, DM review, cumulative multi-file selection, remove buttons, 10-file boundary, empty/oversize validation, exact submitted files and upload-error retry.');
dom.window.close();old.window.close();
