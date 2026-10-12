import fs from 'node:fs';
import assert from 'node:assert/strict';
const {JSDOM,VirtualConsole}=await import(process.env.JSDOM_MODULE||'jsdom');
const errors=[],vc=new VirtualConsole();vc.on('jsdomError',error=>errors.push(error));
const dom=new JSDOM(['sidebar','topbar','workspaceTabs','demoBar','main','bottomnav','toast'].map(id=>`<div id="${id}"></div>`).join('')+'<dialog id="modal"><div id="modalContent"></div></dialog>',{url:'https://example.invalid/',runScripts:'dangerously',virtualConsole:vc});
const w=dom.window,doc=w.document,run=code=>w.eval(code),observers=[];
let fine=true,reduced=false;
w.matchMedia=query=>({matches:query.includes('prefers-reduced-motion')?reduced:fine});
w.ResizeObserver=class{constructor(callback){this.callback=callback;observers.push(this);}observe(){}disconnect(){this.disconnected=true;}};
w.scrollTo=()=>{};w.OCCCI_SUPABASE_CONFIG={url:'https://example.invalid',publishableKey:'test'};
w.HTMLDialogElement.prototype.showModal=function(){this.open=true;};w.HTMLDialogElement.prototype.close=function(){this.open=false;};
const script=doc.createElement('script');script.textContent=['ui','reports','staff-invites','finance','cashier-password','notifications','announcements','app'].map(name=>fs.readFileSync('dist/'+name+'.js','utf8').replace(/init\(\);\s*$/,'')).join('\n');doc.body.append(script);
w.signedUrl=async()=> 'https://example.invalid/poster.webp';
run(`S.session={access_token:'token',refresh_token:'refresh',user:{id:'member-a'}};S.role='Member';S.assignment=null;S.accountState='registered';S.page='Home';S.me={id:'member-a',branch_id:'a',full_name:'Test Member',first_name:'Test',registration_kind:'Member',onboarding_complete:true,membership_status:'Active',avatar:'man'};S.profiles=[S.me];S.branches=[{id:'a',name:'Ormoc',district:1},{id:'b',name:'Baybay',district:1},{id:'c',name:'Tacloban',district:2}];S.content=[
 {id:'latest',kind:'Announcement',branch_id:'a',published:true,title:'Latest branch update',body:'Full text for the current announcement.',poster_path:'manager/latest.webp',updated_at:'2026-10-12T12:00:00Z'},
 {id:'district',kind:'Announcement',district:1,published:true,title:'District announcement',body:'District 1 details.',updated_at:'2026-10-11T12:00:00Z'},
 {id:'global',kind:'Announcement',published:true,title:'Cooperative announcement',body:'<img src=x onerror=alert(1)>',updated_at:'2026-10-10T12:00:00Z'},
 {id:'draft',kind:'Announcement',branch_id:'a',published:false,title:'Draft secret',body:'Not published.'},
 {id:'removed',kind:'Announcement',branch_id:'a',published:true,archived_at:'2026-10-12',title:'Removed announcement'},
 {id:'other-branch',kind:'Announcement',branch_id:'b',published:true,title:'Another branch'},
 {id:'other-district',kind:'Announcement',district:2,published:true,title:'Another district'},
 {id:'event',kind:'Event',branch_id:'a',published:true,title:'Branch assembly',body:'Event details',event_date:'2026-10-14'}
];render();`);
let root=doc.querySelector('[data-member-announcements]');
assert(root);assert.equal(root.dataset.selectedAnnouncement,'latest');
const previews=()=>[...root.querySelector('.announcement-preview-group').children];
assert.deepEqual(previews().map(node=>node.dataset.announcementId),['latest','district','global']);
assert(root.querySelector('.announcement-feature').textContent.includes('Full text for the current announcement.'));
assert(doc.querySelector('.member-other-updates').textContent.includes('Branch assembly'));
assert(!doc.getElementById('main').textContent.includes('Draft secret'));
assert(!root.querySelector('.content-card-actions'),'Member previews have no CMS actions');
previews()[1].click();assert.equal(root.dataset.selectedAnnouncement,'district');
assert.equal(root.querySelector('#currentAnnouncementTitle').textContent,'District announcement');
assert.equal(previews()[1].getAttribute('aria-pressed'),'true');
root.querySelector('[data-announcement-step="1"]').click();assert.equal(root.dataset.selectedAnnouncement,'global');
assert(!root.querySelector('.announcement-feature-content img'),'Announcement text is escaped');
assert(root.querySelector('.announcement-feature-body').textContent.includes('<img'));
root.querySelector('[data-announcement-step="1"]').click();assert.equal(root.dataset.selectedAnnouncement,'latest','Next wraps to the first announcement');
root.querySelector('[data-announcement-step="-1"]').click();assert.equal(root.dataset.selectedAnnouncement,'global','Previous wraps to the last announcement');
const oldObserver=observers.at(-1);
run(`S.content.find(c=>c.id==='global').body='Live revised announcement';render()`);
root=doc.querySelector('[data-member-announcements]');assert(oldObserver.disconnected);assert.equal(root.dataset.selectedAnnouncement,'global');
assert(root.querySelector('.announcement-feature-body').textContent.includes('Live revised announcement'));
run(`S.content=S.content.filter(c=>c.id!=='global');render()`);root=doc.querySelector('[data-member-announcements]');assert.equal(root.dataset.selectedAnnouncement,'latest','Removal falls back to the latest visible record');
const viewport=root.querySelector('.announcement-preview-viewport'),group=root.querySelector('.announcement-preview-group'),copy=root.querySelector('[data-announcement-copy]');
Object.defineProperty(viewport,'clientHeight',{value:260});Object.defineProperty(group,'scrollHeight',{value:800});
observers.at(-1).callback();assert(root.classList.contains('is-looping'));assert(!copy.hidden);assert.equal(copy.getAttribute('aria-hidden'),'true');assert(!copy.querySelector('button'),'Loop copies do not duplicate keyboard controls');
viewport.dispatchEvent(new w.WheelEvent('wheel',{bubbles:true}));assert(root.classList.contains('is-browsing'));assert(copy.hidden,'Manual scrolling uses only the canonical list');
root.dispatchEvent(new w.Event('pointerleave'));assert(!root.classList.contains('is-browsing'));assert(!copy.hidden);
reduced=true;observers.at(-1).callback();assert(!root.classList.contains('is-looping'));assert(copy.hidden);
reduced=false;fine=false;observers.at(-1).callback();assert(!root.classList.contains('is-looping'),'Touch browsing does not run hover motion');
run(`S.me.branch_id='c';render()`);root=doc.querySelector('[data-member-announcements]');assert.equal(root.dataset.selectedAnnouncement,'other-district');assert(!root.textContent.includes('Latest branch update'));
run(`S.content=[{id:'one',kind:'Announcement',published:true,title:'Only announcement',body:'One update'}];render()`);root=doc.querySelector('[data-member-announcements]');assert.equal(root.querySelector('.announcement-current-count').textContent,'1 / 1');assert([...root.querySelectorAll('[data-announcement-step]')].every(node=>node.disabled));
run(`S.content=[];render()`);assert(!doc.querySelector('[data-member-announcements]'));assert(doc.getElementById('main').textContent.includes('No content published'));
run(`S.role='Admin';S.assignment={role:'Admin'};S.page='Content';S.content=[{id:'cms',kind:'Announcement',published:true,title:'CMS content',body:'Admin editor'}];render()`);assert(!doc.querySelector('[data-member-announcements]'));assert(doc.querySelector('.content-card-actions button'),'CMS action alignment remains intact');
assert.equal(errors.length,0,errors.map(error=>error.message).join('\n'));w.close();
console.log('PASS: branch/district publication scope, preview selection, navigation wrap, escaped text, live selection retention/removal, hover overflow, manual/touch/reduced-motion browsing, single/empty states and preserved CMS controls.');
