import fs from 'node:fs';
import assert from 'node:assert/strict';
const {JSDOM,VirtualConsole}=await import(process.env.JSDOM_MODULE||'jsdom');
const errors=[],vc=new VirtualConsole();vc.on('jsdomError',e=>errors.push(e));
const html=['sidebar','topbar','workspaceTabs','demoBar','main','bottomnav','toast'].map(id=>`<div id="${id}"></div>`).join('')+'<dialog id="modal"><div id="modalContent"></div></dialog>';
const dom=new JSDOM(html,{url:'https://example.invalid/',runScripts:'dangerously',virtualConsole:vc});
const w=dom.window,doc=w.document,run=s=>w.eval(s),tick=()=>new Promise(r=>setTimeout(r,20));
w.scrollTo=()=>{};w.OCCCI_SUPABASE_CONFIG={url:'https://example.invalid',publishableKey:'test'};
w.HTMLDialogElement.prototype.showModal=function(){this.open=true};w.HTMLDialogElement.prototype.close=function(){this.open=false};
const style=doc.createElement('style');style.textContent=fs.readFileSync('dist/styles.css','utf8');doc.head.append(style);
const script=doc.createElement('script');script.textContent=['ui','reports','staff-invites','app'].map(n=>fs.readFileSync('dist/'+n+'.js','utf8').replace(/init\(\);\s*$/,'')).join('\n');doc.body.append(script);

const profile=(id,full_name,branch_id='a',extra={})=>({id,full_name,first_name:full_name.split(' ')[0],last_name:full_name.split(' ').at(-1),branch_id,registration_kind:'Member',membership_status:'Active',account_number:'ACC-'+id,avatar:'man',onboarding_complete:true,...extra});
const admin=profile('admin','Test Administrator',null,{registration_kind:'Staff'});
const profiles=[admin,profile('current','Current Member'),profile('new','New Member','a',{membership_status:'Pending verification',account_number:null}),profile('archived','Archived Member','a',{archived_at:'2026-10-10T02:00:00Z'}),profile('foreign','Other District Member','b'),profile('other-branch','Other Branch Member','c')];
const ledger={savings:100,loan_balance:0,loan_status:'No active loan',annual_interest:0,schedule:[],source_reference:'Fixture ledger',as_of:'2026-10-11'};
const document={path:'fixture/original.pdf',name:'original.pdf',size:100,type:'application/pdf'};
const request=(id,member_id,kind='Financial sync',status='Pending',branch_id='a')=>({id,member_id,branch_id,kind,status,submitted_by:'branch-staff',bm_reviewer:status==='BM approved'?'bm':null,proposed:kind==='Financial sync'?{...ledger}:{permission_only:true},evidence_files:[document],note:id+' fixture note',created_at:'2026-10-11T02:00:00Z'});
const requests=[request('current-pending','current'),request('current-screened','current','Financial sync','BM approved'),request('current-applied','current','Financial sync','Applied'),request('current-edit','current','Profile edit'),request('archived-pending','archived'),request('archived-applied','archived','Financial sync','Applied'),request('archived-edit','archived','Profile edit'),request('missing-pending','missing'),request('missing-edit','missing','Profile edit'),request('foreign-screened','foreign','Financial sync','BM approved','b'),request('other-branch-screened','other-branch','Financial sync','BM approved','c')];
const audit=Array.from({length:33},(_,i)=>({id:i+1,member_id:'current',subject_name:'Current Member',actor:'admin',actor_name:'Test Administrator',actor_role:'Admin',branch_id:'a',action:'Record updated '+(i+1),note:'Verified fixture note '+(i+1),before_data:{contact_number:'09100000000'},after_data:{contact_number:'09200000000'},created_at:'2026-10-11T02:00:00Z'}));
audit.push({id:34,member_id:'archived',subject_name:'Archived Member',actor:'admin',actor_name:'Test Administrator',actor_role:'Admin',branch_id:'a',action:'Member archived',note:'Duplicate record',created_at:'2026-10-10T02:00:00Z'});
const financials=[{member_id:'current',...ledger,evidence_files:[document]},{member_id:'archived',...ledger,evidence_files:[document]}];
const team=[{user_id:'admin',role:'Admin'}];
run(`S.session={access_token:'original-session',expires_at:9999999999,user:{id:'admin',email:'admin@example.invalid'}};S.me=${JSON.stringify(admin)};S.role='Admin';S.assignment={role:'Admin'};S.branches=[{id:'a',name:'Ormoc',district:1,active:true},{id:'b',name:'Tacloban',district:2,active:true},{id:'c',name:'Baybay',district:1,active:true}];S.profiles=${JSON.stringify(profiles)};S.requests=${JSON.stringify(requests)};S.audit=${JSON.stringify(audit)};S.financials=${JSON.stringify(financials)};S.team=${JSON.stringify(team)};S.scope='a';S.page='Members';render()`);

// The real button hides every activity date and row until a native click.
w.memberDialog('current');
let toggle=doc.getElementById('memberActivityToggle'),panel=doc.getElementById('memberActivityDetails');
assert.equal(toggle.tagName,'BUTTON');assert.equal(toggle.type,'button');assert.equal(toggle.getAttribute('aria-expanded'),'false');assert.equal(toggle.getAttribute('aria-controls'),panel.id);assert(panel.hidden);assert.equal(w.getComputedStyle(panel).display,'none');assert.equal(w.getComputedStyle(toggle).minHeight,'44px');
assert.equal(doc.querySelectorAll('.member-record-activity time').length,20);assert(doc.querySelector('.member-activity-count').textContent.includes('33 entries'));
toggle.click();assert.equal(toggle.getAttribute('aria-expanded'),'true');assert(!panel.hidden);assert.notEqual(w.getComputedStyle(panel).display,'none');
assert.equal(panel.querySelectorAll('.activity-list-item').length,20);assert(!panel.querySelector('details').open);
panel.querySelector('summary').click();assert(panel.querySelector('details').open);assert(panel.querySelector('.activity-body').textContent.includes('Verified fixture note 1'));assert(panel.querySelector('.activity-body').textContent.includes('09100000000'));assert(panel.querySelector('.activity-body').textContent.includes('09200000000'));
panel.querySelector('[aria-label="Next activity page"]').click();
toggle=doc.getElementById('memberActivityToggle');panel=doc.getElementById('memberActivityDetails');
assert.equal(toggle.getAttribute('aria-expanded'),'true');assert(!panel.hidden,'Changing activity pages must keep the panel open');assert.equal(panel.querySelectorAll('.activity-list-item').length,13);assert(panel.textContent.includes('Page 2 of 2'));assert(panel.textContent.includes('Record updated 21'));
panel.querySelector('[aria-label="Previous activity page"]').click();assert.equal(doc.querySelectorAll('.member-activity-details .activity-list-item').length,20);
toggle=doc.getElementById('memberActivityToggle');toggle.click();assert(doc.getElementById('memberActivityDetails').hidden);w.memberDialog('current');assert(doc.getElementById('memberActivityDetails').hidden,'Reopening the record starts collapsed');
w.memberDialog('new');assert(doc.getElementById('memberActivityDetails').hidden);doc.getElementById('memberActivityToggle').click();assert(doc.getElementById('memberActivityDetails').textContent.includes('No activity yet'));

// Removed profiles cannot create anonymous requests, controls or notification counts.
const currentIds=['current-pending','current-screened','current-applied','current-edit'];
assert.deepEqual(Array.from(run('currentMemberRequests().map(q=>q.id)')),currentIds);
doc.getElementById('main').innerHTML=w.financialView();assert.equal(doc.querySelectorAll('.request-list-row').length,3);assert([...doc.querySelectorAll('.request-list-row h2')].every(n=>n.textContent==='Current Member'));assert(!doc.getElementById('main').textContent.includes('archived-pending fixture note'));assert(!doc.getElementById('main').textContent.includes('missing-pending fixture note'));
assert(w.financialRecordRows().some(p=>p.id==='new'),'New members without financial records remain visible');assert(!w.financialRecordRows().some(p=>p.id==='archived'));assert(!w.directoryRows().some(p=>p.id==='archived'));
doc.getElementById('main').innerHTML=w.approvalsView();assert.equal(doc.querySelectorAll('.request-list-row').length,1);
doc.getElementById('workspaceTabs').innerHTML=w.approvalPortals();
const portal=label=>[...doc.querySelectorAll('.approval-portals button')].find(b=>b.querySelector('.portal-label').textContent===label);
assert.equal(portal('Review Actual Balances').querySelector('.portal-count').textContent,'2');assert(portal('Review Actual Balances').querySelector('.portal-count').classList.contains('has-pending'));assert.equal(portal('Review Staff Edits').querySelector('.portal-count').textContent,'1');
run(`S.page='Overview'`);doc.getElementById('main').innerHTML=w.cmsView();
const metric=label=>[...doc.querySelectorAll('.admin-metric')].find(n=>n.querySelector('.eyebrow').textContent===label).querySelector('.big-number').textContent;
assert.equal(metric('Members'),'1');assert.equal(metric('Financial sync'),'2');assert.equal(metric('Edit requests'),'1');
const beforeRequests=JSON.stringify(run('S.requests')),beforeFinancials=JSON.stringify(run('S.financials')),beforeAudit=JSON.stringify(run('S.audit'));
run(`S.profiles=S.profiles.filter(p=>p.id!=='archived');S.role='DM';S.assignment={role:'DM',district:1};S.scope='all'`);
assert.deepEqual(Array.from(run('currentMemberRequests().map(q=>q.id)')),[...currentIds,'other-branch-screened']);assert(w.canReview(requests[1]));assert(!w.canReview(requests[4]));assert(!w.canReview(requests[7]));assert(!w.canReview(requests[9]));
w.requestDialog('current-screened');assert(doc.querySelector('.document-list').textContent.includes('original.pdf'));assert(doc.querySelector('button[type=submit]').textContent.includes('Approve and synchronize'));
run(`S.role='BM';S.assignment={role:'BM',branch_id:'a'}`);assert.deepEqual(Array.from(run('currentMemberRequests().map(q=>q.id)')),currentIds);assert(w.canReview(requests[0]));assert(!w.canReview(requests[10]));
run(`S.role='Staff';S.assignment={role:'Staff',branch_id:'a'}`);assert.deepEqual(Array.from(run('currentMemberRequests().map(q=>q.id)')),currentIds);
w.requestDialog('missing-pending');assert(!doc.getElementById('modal').open);assert(doc.getElementById('toast').textContent.includes('archived or no longer available'));w.requestDialog('archived-pending');assert(!doc.getElementById('modal').open);w.memberDialog('archived');assert(!doc.getElementById('modal').open);
run(`S.role='Admin';S.assignment={role:'Admin'};S.scope='a';S.requests=S.requests.filter(q=>['archived','missing'].includes(q.member_id))`);doc.getElementById('workspaceTabs').innerHTML=w.approvalPortals();
for(const label of ['Review Actual Balances','Review Staff Edits']){const count=portal(label).querySelector('.portal-count');assert.equal(count.textContent,'0');assert(!count.classList.contains('has-pending'));}
assert.equal(JSON.stringify(run('S.financials')),beforeFinancials);assert.equal(JSON.stringify(run('S.audit')),beforeAudit);run(`S.requests=${beforeRequests}`);
assert(w.auditRows(run('S.audit.filter(a=>a.member_id==="archived")')).includes('Archived Member'),'Captured archived identity remains readable in audit history');

// Exercise native password-confirmed archive -> real reload -> active views.
const calls=[];w.loadReports=async()=>{};w.loadStaffInvites=async()=>{};w.loadBranches=async()=>{};
w.api=async(path,options={})=>{
 calls.push({path,...options});
 if(path==='/auth/v1/user')return {id:'admin',email:'admin@example.invalid'};
 if(path.includes('occci_begin_position_confirmation'))return 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 if(path.includes('grant_type=password'))return {access_token:'fresh-archive-token',user:{id:'admin'}};
 if(path==='/auth/v1/logout?scope=local')return {};
 if(path.endsWith('/occci_manage_record')){assert.equal(options.data.record_kind,'Member');assert.equal(options.data.record_id,'current');assert.equal(options.data.remove_record,true);profiles.find(p=>p.id==='current').archived_at='2026-10-11T03:00:00Z';audit.push({id:35,member_id:'current',subject_name:'Current Member',actor:'admin',actor_name:'Test Administrator',actor_role:'Admin',branch_id:'a',action:'Member archived',note:options.data.reason,created_at:'2026-10-11T03:00:00Z'});return {};}
 if(path.includes('/occci_profiles?')){assert(path.includes('archived_at=is.null'));return profiles.filter(p=>!p.archived_at);}
 if(path.includes('/occci_financials?'))return financials;
 if(path.includes('/occci_change_requests?'))return requests;
 if(path.includes('/rpc/occci_activity'))return audit;
 if(path.includes('/occci_staff_assignments?'))return team;
 if(path.includes('/occci_content?')||path.includes('/occci_staff_applications?'))return [];
 throw Error('Unexpected fixture API '+path);
};
run(`S.page='Financial sync'`);w.removeDialog('Member','current');
const form=doc.querySelector('#modalContent form');form.elements.reason.value='Duplicate membership archived';form.querySelector('[data-admin-password]').value='fixture-password';assert(form.checkValidity());form.requestSubmit(form.querySelector('button[type=submit]'));await tick();
const archivedCall=calls.find(c=>c.path.endsWith('/occci_manage_record'));assert(archivedCall);assert.equal(archivedCall.headers.Authorization,'Bearer fresh-archive-token');assert.equal(archivedCall.data.values_json.position_confirmation,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');assert(!JSON.stringify(archivedCall).includes('fixture-password'));assert(calls.some(c=>c.path==='/auth/v1/logout?scope=local'));assert.equal(run('S.session.access_token'),'original-session');assert.equal(run('S.error'),'');
assert(!run('S.profiles.some(p=>p.id==="current")'));assert.equal(run('currentMemberRequests().length'),0);assert.equal(doc.querySelectorAll('#main .request-list-row').length,0);assert(!doc.getElementById('main').textContent.includes('Current Member'));assert(!w.financialRecordRows().some(p=>p.id==='current'));
assert.equal(run('S.requests.length'),requests.length,'Archive hides queues without deleting request history');assert.equal(run('S.financials.length'),financials.length);assert.equal(run('S.requests.find(q=>q.id==="current-applied").evidence_files[0].name'),'original.pdf');assert.equal(run('S.financials.find(f=>f.member_id==="current").evidence_files[0].name'),'original.pdf');assert(run('S.audit.some(a=>a.member_id==="current"&&a.action==="Member archived")'));
assert.equal(portal('Review Actual Balances').querySelector('.portal-count').textContent,'0');assert(!portal('Review Actual Balances').querySelector('.portal-count').classList.contains('has-pending'));
assert.equal(errors.length,0,errors.map(e=>e.message).join('\n'));
console.log('PASS: native collapsed activity button and dates, entry details, 20-entry pages staying open, empty/reopened records, archived/missing request exclusion, scoped controls and counters, preserved history/documents, and password-confirmed archive followed by real data reload.');
w.close();
