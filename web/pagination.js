/* Viewport-based book pagination. Learning controls remain live DOM elements. */
(() => {
'use strict';
class EbookPager {
 constructor(viewport, article, onChange, onBoundary) {
  this.viewport=viewport;this.article=article;this.onChange=onChange;this.onBoundary=onBoundary;
  this.page=0;this.total=1;this.stride=1;this.anchor=null;this.pending=null;this.frame=0;
  this.reduced=window.matchMedia('(prefers-reduced-motion: reduce)');
  this.resize=new ResizeObserver(()=>this.refresh());this.resize.observe(viewport);
  // Content mutations and panel resizing retain the current sheet. Restoring a
  // saved block is an explicit navigation operation, not automatic reflow.
  this.mutations=new MutationObserver(()=>this.refresh());
  this.mutations.observe(article,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['open']});
  this.article.addEventListener('focusin',e=>{
   if(e.target===this.article)return;
   const rect=e.target.getBoundingClientRect(),view=this.viewport.getBoundingClientRect();
   if(rect.left<view.left-2||rect.left>=view.right){
    const origin=this.article.getBoundingClientRect().left;
    this.page=Math.max(0,Math.min(this.total-1,Math.round((rect.left-origin)/this.stride)));
    this.apply(false);this.remember();this.onChange(this.page,this.total);
   }
  });
  this.bindGestures();
 }
 blocks(){return [...this.article.querySelectorAll('.lesson-heading,[data-block],.reading>p,.visual,.code-panel,.table-wrap,.lab,.takeaway,.quiz,.page-tools,.notes,.sources,.exam-score')];}
 remember(){
  const view=this.viewport.getBoundingClientRect(),origin=this.article.getBoundingClientRect().left;
  const start=this.page*this.stride;
  // Compare layout coordinates: an in-progress slide still displays the old
  // sheet, but the anchor must belong to the newly selected logical sheet.
  this.anchor=this.blocks().find(el=>[...el.getClientRects()].some(r=>r.left-origin>=start-2&&r.left-origin<start+view.right-view.left-2&&r.top<view.bottom&&r.bottom>view.top))||null;
 }
 refresh(options={}){
  if(Object.keys(options).length)this.pending=options;
  if(this.frame)return;
  // WKWebView can defer animation frames when a Mac window opens in the
  // background. A timer completes the same layout once, without turning pages.
  const run=()=>{if(!this.frame)return;cancelAnimationFrame(this.frame);this.frame=0;clearTimeout(this.layoutTimer);this.measure();};
  this.frame=requestAnimationFrame(run);
  this.layoutTimer=setTimeout(run,80);
 }
 measure(){
  const options=this.pending||{};this.pending=null;
  const width=this.viewport.clientWidth,height=this.viewport.clientHeight;
  if(width<1||height<1||this.article.hidden)return;
  const gap=40;
  this.article.style.width=`${width}px`;this.article.style.height=`${height}px`;
  this.article.style.columnWidth=`${width}px`;this.article.style.columnGap=`${gap}px`;
  this.article.style.setProperty('--sheet-height',`${height}px`);
  this.stride=width+gap;
  this.total=Math.max(1,Math.ceil((this.article.scrollWidth+gap-2)/this.stride));
  let page=this.page;
  if(options.last)page=this.total-1;
  else if(Number.isInteger(options.page))page=options.page;
  else if(options.anchor?.isConnected){
   const rect=this.article.getBoundingClientRect();
   const first=options.anchor.getClientRects()[0];
   if(first)page=Math.round((first.left-rect.left)/this.stride);
  }
  this.page=Math.max(0,Math.min(this.total-1,page));
  this.apply(false);this.remember();this.onChange(this.page,this.total);
  if(options.direction&&!this.reduced.matches){
   const base=-this.page*this.stride;
   this.article.animate([{transform:`translateX(${base+options.direction*width}px)`},{transform:`translateX(${base}px)`}],{duration:210,easing:'ease-out'});
  }
 }
 apply(animate,drag=0){
  this.article.style.transition=animate&&!this.reduced.matches?'transform 210ms ease-out':'none';
  this.article.style.transform=`translateX(${-this.page*this.stride+drag}px)`;
 }
 turn(direction){
  const next=this.page+direction;
  if(next<0||next>=this.total)return false;
  this.page=next;this.apply(true);this.remember();this.onChange(this.page,this.total);return true;
 }
 excluded(target){return !!target.closest('input,textarea,select,button,a,summary,[data-no-swipe]');}
 horizontalScroll(target){
  const el=target.closest('pre,.table-wrap');return el&&el.scrollWidth>el.clientWidth+1;
 }
 bindGestures(){
  let gesture=null,wheel=0,lastWheel=-Infinity,wheelCommitted=false;
  let wheelPeak=0,previousDelta=0,lastTurn=-Infinity,committedDirection=0,renewed=null;
  this.viewport.addEventListener('pointerdown',e=>{
   if(e.pointerType==='mouse'||!e.isPrimary||this.excluded(e.target)||this.horizontalScroll(e.target))return;
   gesture={id:e.pointerId,x:e.clientX,y:e.clientY,dx:0,locked:false};
  });
  this.viewport.addEventListener('pointermove',e=>{
   if(!gesture||e.pointerId!==gesture.id)return;
   const dx=e.clientX-gesture.x,dy=e.clientY-gesture.y;
   if(!gesture.locked&&Math.abs(dy)>12&&Math.abs(dy)>Math.abs(dx)){gesture=null;return;}
   if(!gesture.locked&&Math.abs(dx)>12&&Math.abs(dx)>Math.abs(dy)*1.3){
    gesture.locked=true;this.viewport.setPointerCapture(e.pointerId);
   }
   if(gesture.locked){gesture.dx=dx;e.preventDefault();this.apply(false,dx);}
  });
  const end=e=>{
   if(!gesture||e.pointerId!==gesture.id)return;
   const g=gesture;gesture=null;
   if(g.locked){
    if(e.type==='pointerup'&&Math.abs(g.dx)>Math.min(80,this.viewport.clientWidth*.16)){
     const direction=g.dx<0?1:-1;
     if(!this.turn(direction)){this.apply(true);this.onBoundary(direction);}
    }else this.apply(true);
   }
  };
  this.viewport.addEventListener('pointerup',end);this.viewport.addEventListener('pointercancel',end);
  this.viewport.addEventListener('wheel',e=>{
   const now=performance.now();
   const gap=now-lastWheel;
   // A quiet gap starts a stroke; renewed force can also start one during inertia.
   if(gap>140){wheel=0;wheelCommitted=false;wheelPeak=0;previousDelta=0;renewed=null;}
   lastWheel=now;
   if(e.ctrlKey||Math.abs(e.deltaX)<=Math.abs(e.deltaY)||this.horizontalScroll(e.target)){renewed=null;return;}
   e.preventDefault();
   const delta=e.deltaX*(e.deltaMode===1?16:e.deltaMode===2?this.viewport.clientWidth:1);
   const magnitude=Math.abs(delta),direction=Math.sign(delta),previous=Math.abs(previousDelta);
   if(wheelCommitted){
    if(renewed){
     if(gap<=100&&direction===renewed.direction&&magnitude>=renewed.minimum){
      renewed.distance+=magnitude;renewed.count++;renewed.peak=Math.max(renewed.peak,magnitude);
     }else renewed=null;
    }
    if(!renewed){
     const reversal=direction!==committedDirection&&magnitude>=18;
     const acceleration=direction===committedDirection&&Math.sign(previousDelta)===direction&&previous<=wheelPeak*.55&&magnitude>=Math.max(18,previous*1.8)&&magnitude-previous>=12;
     if(reversal||acceleration)renewed={direction,distance:magnitude,count:1,minimum:reversal?18:Math.max(12,previous*1.35),peak:magnitude};
    }
    previousDelta=delta;wheelPeak=Math.max(wheelPeak,magnitude);
    // Two substantial packets distinguish a fresh stroke from a single tail spike.
    if(!renewed||renewed.count<2||renewed.distance<70||now-lastTurn<80)return;
    wheel=renewed.direction*renewed.distance;wheelPeak=renewed.peak;renewed=null;
   }else{
    if(Math.sign(wheel)!==direction)wheel=0;
    wheel+=delta;wheelPeak=Math.max(wheelPeak,magnitude);previousDelta=delta;
   }
   if(Math.abs(wheel)>=70){
    const turnDirection=Math.sign(wheel);wheel=0;wheelCommitted=true;lastTurn=now;committedDirection=turnDirection;
    if(!this.turn(turnDirection))this.onBoundary(turnDirection);
   }
  },{passive:false});
 }
}
globalThis.EbookPager=EbookPager;
})();
