/* Gesture behavior checks; browser layout is checked separately in the preview. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let now=1000, frame,resizeCallback,mutationCallback;
const changes=[], boundaries=[], handlers={};
const context={
 window:{matchMedia:()=>({matches:true})},
 ResizeObserver:class{constructor(fn){resizeCallback=fn;}observe(){}}, MutationObserver:class{constructor(fn){mutationCallback=fn;}observe(){}},
 requestAnimationFrame:fn=>{frame=fn;return 1;}, cancelAnimationFrame(){},setTimeout:fn=>{context.layoutFallback=fn;return 1;},clearTimeout(){},performance:{now:()=>now}
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(__dirname+'/../web/pagination.js','utf8'),context);
const viewport={clientWidth:700,clientHeight:850,
 addEventListener:(name,fn)=>{handlers[name]=fn;},setPointerCapture(){},
 getBoundingClientRect:()=>({left:0,right:700,top:0,bottom:850})};
const article={hidden:false,scrollWidth:2180,style:{setProperty(){}},
 addEventListener(){},querySelectorAll:()=>[],getBoundingClientRect:()=>({left:0})};
const pager=new context.EbookPager(viewport,article,(p,n)=>changes.push([p,n]),d=>boundaries.push(d));
const text={closest:()=>null};
const control={closest:selector=>selector.startsWith('input')?{}:null};
const wideCode={closest:selector=>selector==='pre,.table-wrap'?{scrollWidth:900,clientWidth:500}:null};
function point(type,x,y,target=text){handlers[type]({type,pointerId:1,pointerType:'touch',isPrimary:true,clientX:x,clientY:y,target,preventDefault(){}});}
function swipe(from,to,target=text){point('pointerdown',from,300,target);point('pointermove',to,300,target);point('pointerup',to,300,target);}
pager.refresh({page:0});frame();assert.equal(pager.total,3);
swipe(500,250);assert.equal(pager.page,1,'left swipe moves one sheet');
swipe(250,500);assert.equal(pager.page,0,'right swipe returns one sheet');
swipe(500,250,control);assert.equal(pager.page,0,'controls do not turn sheets');
swipe(500,250,wideCode);assert.equal(pager.page,0,'wide code can scroll horizontally');
point('pointerdown',500,300);point('pointermove',490,500);point('pointerup',200,500);
assert.equal(pager.page,0,'vertical scrolling does not turn sheets');
point('pointerdown',500,300);point('pointermove',200,300);point('pointercancel',200,300);
assert.equal(pager.page,0,'cancelled gesture stays on its sheet');
swipe(250,500);assert.deepEqual(boundaries,[-1],'boundary requests previous topic once');
function wheel(dx,dy=0,target=text,gap=500){now+=gap;handlers.wheel({deltaX:dx,deltaY:dy,deltaMode:0,ctrlKey:false,target,preventDefault(){}});}
wheel(100);assert.equal(pager.page,1,'horizontal trackpad advances');
// One physical gesture can keep producing momentum events well beyond 450 ms.
for(const delta of [110,100,90,80,70,60,50,40,35,30,25,20,15,10,5])wheel(delta,0,text,60);
assert.equal(pager.page,1,'long momentum tail must not turn a second sheet');
wheel(-100,0,text,40);assert.equal(pager.page,1,'bounce in the same gesture must not turn back');
for(const delta of [80,65,50])wheel(delta,0,text,20);
assert.equal(pager.page,1,'recovering from a single reverse spike must not look like a new stroke');
// Vertical tail events must keep the same gesture locked too.
for(let i=0;i<6;i++)wheel(0,20,text,80);
wheel(100,0,text,80);assert.equal(pager.page,1,'vertical tail must not rearm a gesture');
wheel(0,100);assert.equal(pager.page,1,'vertical wheel does not advance');
wheel(100,0,wideCode);assert.equal(pager.page,1,'code wheel stays in code');
wheel(100);assert.equal(pager.page,2);wheel(100);assert.deepEqual(boundaries,[-1,1]);
for(let i=0;i<15;i++)wheel(100,0,text,60);
assert.deepEqual(boundaries,[-1,1],'one gesture must not cross multiple topic boundaries');
pager.refresh({page:0});frame();
wheel(100,0,text,60);assert.equal(pager.page,0,'momentum after rendering a new topic stays locked');
wheel(25);wheel(25,0,text,30);assert.equal(pager.page,0,'small deltas wait for the threshold');
wheel(25,0,text,30);assert.equal(pager.page,1,'small deltas within one gesture accumulate');
wheel(100);assert.equal(pager.page,2,'a new gesture after an idle gap can advance');
wheel(-100);assert.equal(pager.page,1,'a new reverse gesture can go back');
// A fresh finger stroke can arrive while the previous stroke still has inertia.
for(const delta of [-55,-30,-12,-4])wheel(delta,0,text,20);
wheel(-85,0,text,20);wheel(-80,0,text,16);
assert.equal(pager.page,0,'a strong new stroke can continue immediately during inertia');
for(const delta of [-50,-25,-9,-3])wheel(delta,0,text,20);
wheel(85,0,text,20);wheel(80,0,text,16);
assert.equal(pager.page,1,'a new forward stroke need not wait for the inertia to end');
for(const delta of [50,25,9,3])wheel(delta,0,text,20);
wheel(90,0,text,20);wheel(75,0,text,16);
assert.equal(pager.page,2,'two quick strokes in the same direction turn two sheets');
for(const delta of [60,40,25,14,8,4,2,3,2,1])wheel(delta,0,text,20);
assert.deepEqual(boundaries,[-1,1],'small fluctuations in the tail must not add a turn');
wheel(-90,0,text,90);wheel(-80,0,text,16);
assert.equal(pager.page,1,'a fast reverse stroke can interrupt forward inertia');
wheel(90,0,text,90);wheel(80,0,text,16);
assert.equal(pager.page,2,'a fast direction change need not wait for a decaying tail');
for(const delta of [40,15,5,100,5,3])wheel(delta,0,text,20);
assert.deepEqual(boundaries,[-1,1],'an isolated large tail spike must not add a turn');
pager.refresh({page:99});frame();assert.equal(pager.page,2,'saved page clamps after reflow');
article.scrollWidth=700;pager.refresh();frame();assert.equal(pager.page,0);assert.equal(pager.total,1);
console.log('Pagination: swipe, cancellation, trackpad, control exclusion, boundaries and reflow checks passed.');

// Reflow caused by UI controls must not navigate using a moved content anchor.
article.scrollWidth=2180;pager.refresh({page:1});frame();
let visualOrigin=0,labColumn=1;
article.getBoundingClientRect=()=>({left:visualOrigin});
const atColumn=n=>({left:visualOrigin+n*pager.stride,right:visualOrigin+n*pager.stride+700,top:0,bottom:100});
const heading={isConnected:true,getClientRects:()=>[atColumn(0)]};
const lab={isConnected:true,getClientRects:()=>[atColumn(labColumn)]};
article.querySelectorAll=()=>[heading,lab];
pager.anchor=lab;labColumn=0;mutationCallback();frame();
assert.equal(pager.page,1,'a shorter step moving its block to column 0 cannot navigate away from sheet 2');
pager.refresh({page:0});frame();pager.anchor=lab;labColumn=1;viewport.clientHeight=650;resizeCallback();frame();
assert.equal(pager.page,0,'Q&A panel growth moving an anchor to column 1 cannot turn sheet 1 into sheet 2');
pager.refresh({anchor:lab});frame();assert.equal(pager.page,1,'saved-block restoration still navigates explicitly');
labColumn=1;pager.refresh({page:0});frame();visualOrigin=0;pager.turn(1);
assert.equal(pager.anchor,lab,'an in-progress slide remembers the target sheet, not the still-visible old sheet');
console.log('Reflow checks: step updates, Q&A panel resizing, explicit restoration and animation-independent anchors passed.');
pager.refresh({page:1});context.layoutFallback();assert.equal(pager.page,1,'background Mac timer completes deferred initial layout');const completed=changes.length;frame();assert.equal(changes.length,completed,'late animation frame does not repeat layout');
console.log('Background window: deferred animation frame fallback and single-layout guard passed.');
