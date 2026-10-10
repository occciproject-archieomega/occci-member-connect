import fs from 'node:fs';
import assert from 'node:assert/strict';
const {JSDOM,VirtualConsole}=await import(process.env.JSDOM_MODULE||'jsdom');
const errors=[];const vc=new VirtualConsole();vc.on('jsdomError',err=>errors.push(err));
const html='<dialog id="modal"><div id="modalContent"></div></dialog><div id="toast"></div>';
const dom=new JSDOM(html,{url:'https://example.invalid',runScripts:'dangerously',virtualConsole:vc});
const w=dom.window;w.OCCCI_SUPABASE_CONFIG={url:'https://example.invalid',publishableKey:'test'};
w.HTMLDialogElement.prototype.showModal=function(){this.open=true};w.HTMLDialogElement.prototype.close=function(){this.open=false};
const script=w.document.createElement('script');script.textContent=fs.readFileSync('dist/ui.js','utf8')+'\n'+fs.readFileSync('dist/app.js','utf8').replace(/init\(\);\s*$/,'');w.document.body.append(script);
const calls=[];w.api=async(path,data)=>{calls.push({path,...data});return null};w.reload=async()=>{};w.render=()=>{};w.loadBranches=async()=>{};w.toast=()=>{};
w.eval(`S.session={user:{id:'staff'},expires_at:9999999999};S.role='Admin';S.profiles=[{id:'member',full_name:'Test Member',account_number:null,membership_status:'Pending verification',first_name:'Test',last_name:'Member',middle_name:'',contact_number:'09123456789',address:'Ormoc City',avatar:'man'}];`);
async function submit(values){const form=w.document.querySelector('form');for(const [name,value] of Object.entries(values))form.elements[name].value=value;assert(form.checkValidity(),'Form must be valid');form.requestSubmit();await new Promise(r=>setTimeout(r,10));assert.equal(errors.length,0,errors.map(e=>e.message).join('\n'));}
w.membershipDialog('member');await submit({account:'OCCCI-0001',reason:'Verified membership register'});assert.equal(calls.at(-1).path,'/rest/v1/rpc/occci_approve_member');assert.equal(calls.at(-1).data.account,'OCCCI-0001');
w.removeDialog('Member','member');await submit({reason:'Duplicate profile archived'});assert.equal(calls.at(-1).path,'/rest/v1/rpc/occci_manage_record');assert.equal(calls.at(-1).data.remove_record,true);
w.accountDialog('member');await submit({account:'OCCCI-0002',reason:'Official branch number'});assert.equal(calls.at(-1).path,'/rest/v1/rpc/occci_assign_account');
w.eval(`S.role='Staff'`);w.editDialog('member');assert(!w.document.querySelector('[name=first_name]'),'Staff cannot edit before permission');await submit({reason:'Request contact correction'});assert.equal(calls.at(-1).data.values_json.permission_only,true);
w.eval(`S.requests=[{id:'permission',member_id:'member',kind:'Profile edit',status:'BM approved',submitted_by:'staff',proposed:{permission_only:true}}]`);w.requestDialog('permission');assert(w.document.querySelector('button[onclick*="editDialog"]'));w.editDialog('member','permission');await submit({reason:'Updated from official form'});assert.equal(calls.at(-1).path,'/rest/v1/rpc/occci_apply_authorized_edit');assert.equal(calls.at(-1).data.request_id,'permission');
w.eval(`S.role='DM'`);assert(w.canReview({kind:'Profile edit',status:'Pending',submitted_by:'other'}));
w.syncDialog('member');assert(w.document.querySelector('[name=evidence]').multiple);assert(!w.document.querySelector('[name=source_reference]').required);
const docs=[{name:'ledger.xlsx',size:1024},{name:'form.docx',size:2048}];w.validateDocuments(docs);assert.throws(()=>w.validateDocuments([]));assert.throws(()=>w.validateDocuments([{size:11*1024*1024}]));
// Confirm the original collision independently, without real requests or data.
const oldErrors=[];const oldVc=new VirtualConsole();oldVc.on('jsdomError',e=>oldErrors.push(e));const old=new JSDOM('<form onsubmit="event.preventDefault();action(this)"><button>Confirm</button></form><script>function action(){}</script>',{runScripts:'dangerously',virtualConsole:oldVc});old.window.document.querySelector('form').requestSubmit();assert(oldErrors.some(e=>e.message.includes('action is not a function')),'Reproduce original browser form-property collision');
console.log('PASS: native form submission for approval/archive/ID assignment, original action collision reproduced, Staff permission before fields, approved edit RPC, DM review, multiple files and limits.');
dom.window.close();old.window.close();
