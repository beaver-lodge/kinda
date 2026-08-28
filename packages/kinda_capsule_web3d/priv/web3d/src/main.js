import * as THREE from 'three';
import './style.css';

const params = new URLSearchParams(location.search);
let broken = params.get('mode') === 'broken';
const container = document.querySelector('#viewer');
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(34, container.clientWidth / container.clientHeight, 0.1, 100);
camera.position.set(0, .25, 4.2);
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(container.clientWidth, container.clientHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
container.prepend(renderer.domElement);

scene.add(new THREE.HemisphereLight(0xdbe8ff, 0x1a2029, 2.1));
const key = new THREE.DirectionalLight(0xffe7cf, 4.2); key.position.set(3, 4, 5); scene.add(key);
const rim = new THREE.PointLight(0x91b7ff, 24, 8); rim.position.set(-3, 1, 1); scene.add(rim);

const product = new THREE.Group();
const bodyMaterial = new THREE.MeshPhysicalMaterial({ color: 0x303641, metalness: .78, roughness: .24, clearcoat: .7 });
const body = new THREE.Mesh(new THREE.CylinderGeometry(.84, .84, 1.05, 48), bodyMaterial);
body.rotation.z = Math.PI / 2; product.add(body);
for (const x of [-.525, .525]) { const cap = new THREE.Mesh(new THREE.SphereGeometry(.84, 32, 24), bodyMaterial); cap.scale.x = .62; cap.position.x = x; product.add(cap); }
const grille = new THREE.Mesh(new THREE.CylinderGeometry(.62, .62, 1.76, 64, 1, true), new THREE.MeshStandardMaterial({ color: 0x11151b, metalness: .4, roughness: .65, wireframe: true }));
grille.rotation.z = Math.PI / 2; product.add(grille);
for (const x of [-.93,.93]) { const ring = new THREE.Mesh(new THREE.TorusGeometry(.61,.035,16,64),new THREE.MeshStandardMaterial({color:0x9ba4b2,metalness:.9,roughness:.2})); ring.rotation.y=Math.PI/2; ring.position.x=x; product.add(ring); }
product.rotation.set(-.12,.35,.08); scene.add(product);
const floor = new THREE.Mesh(new THREE.CircleGeometry(2.3,64),new THREE.MeshBasicMaterial({color:0x0c1016,transparent:true,opacity:.75}));floor.rotation.x=-Math.PI/2;floor.position.y=-1.05;scene.add(floor);

const pointer = new THREE.Vector2();
const velocity = new THREE.Vector2();
let dragging = false; let lastX = 0; let lastY = 0; let lastTime = performance.now();
const frames = []; let allocations = 0; let resizeProjectionCount = 0; let hotspotClicks = 0;
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
if (broken) new THREE.TextureLoader().load('/Users/demo/product-finish.jpg');

renderer.domElement.addEventListener('pointerdown', event => { dragging=true;lastX=event.clientX;lastY=event.clientY;velocity.set(0,0);renderer.domElement.setPointerCapture(event.pointerId); });
renderer.domElement.addEventListener('pointermove', event => {
  if (!dragging) return;
  const scale = broken ? (event.pointerType === 'touch' ? .018 : .006) : .006;
  const dx=(event.clientX-lastX)*scale, dy=(event.clientY-lastY)*scale;
  product.rotation.y += dx; product.rotation.x = THREE.MathUtils.clamp(product.rotation.x + dy,-.7,.7);
  velocity.set(dx,dy);lastX=event.clientX;lastY=event.clientY;
});
renderer.domElement.addEventListener('pointerup', () => { dragging=false;if(broken) velocity.multiplyScalar(2.5); });
renderer.domElement.addEventListener('wheel', event => { event.preventDefault(); camera.position.z += event.deltaY*.003; if(!broken) camera.position.z=THREE.MathUtils.clamp(camera.position.z,2.5,6.2); }, {passive:false});
window.addEventListener('resize', () => { renderer.setSize(container.clientWidth,container.clientHeight);camera.aspect=container.clientWidth/container.clientHeight;if(!broken){camera.updateProjectionMatrix();resizeProjectionCount++;} });
document.querySelectorAll('.hotspot').forEach(button => button.addEventListener('click',()=>{hotspotClicks++;document.querySelector('#product-note').classList.toggle('open');}));

function render(now) {
  const dt=Math.min((now-lastTime)/1000,.05);lastTime=now;frames.push(dt*1000);if(frames.length>1200)frames.shift();
  if(!dragging&&(broken||!reduced.matches)){ if(broken){const waste=new THREE.Vector2(velocity.x,velocity.y);allocations++;product.rotation.y+=waste.x;product.rotation.x+=waste.y;velocity.multiplyScalar(velocity.length()<.012?.45:.93);}else{const decay=Math.exp(-7.5*dt);product.rotation.y+=velocity.x;product.rotation.x=THREE.MathUtils.clamp(product.rotation.x+velocity.y,-.7,.7);velocity.multiplyScalar(decay);} }
  product.rotation.x=THREE.MathUtils.clamp(product.rotation.x,-.7,.7);renderer.render(scene,camera);
  document.querySelector('#camera-distance').textContent=`${camera.position.z.toFixed(2)}m`;
  document.querySelector('#draw-calls').textContent=renderer.info.render.calls;
  document.querySelector('#frame-p95').textContent=`${percentile(frames,.95).toFixed(1)}ms`;
  document.querySelector('#motion-status').textContent=reduced.matches?'REDUCED':'FULL';
  requestAnimationFrame(render);
}
requestAnimationFrame(render);

function percentile(values,p){const sorted=[...values].sort((a,b)=>a-b);return sorted[Math.floor((sorted.length-1)*p)]||0;}
window.__web3dEpisode={
  snapshot:()=>({mode:broken?'broken':'repaired',cameraDistance:camera.position.z,rotation:{x:product.rotation.x,y:product.rotation.y},projectionUpdates:resizeProjectionCount,hotspotClicks,reducedMotion:reduced.matches,metrics:{frameCount:frames.length,frameP50:percentile(frames,.5),frameP95:percentile(frames,.95),longFrames:frames.filter(x=>x>32).length,drawCalls:renderer.info.render.calls,geometries:renderer.info.memory.geometries,textures:renderer.info.memory.textures,renderAllocations:allocations}}),
  resetMetrics:()=>{frames.length=0;allocations=0;},
  setMode:value=>{broken=value==='broken';document.body.classList.toggle('broken',broken);document.querySelector('#mode-label').textContent=broken?'BROKEN':'REPAIRED';}
};
window.__web3dEpisode.setMode(broken?'broken':'repaired');
document.querySelector('#mode-toggle').addEventListener('click',()=>{broken=!broken;window.__web3dEpisode.setMode(broken?'broken':'repaired');});
const evidenceDetails={
  4:['INTERACTION · VIDEO','Inertia tail has a visible deceleration knee','The pointer trace and video isolate a small discontinuity near the end of inertial motion.','interaction.webm','04:10–04:14'],
  5:['PERFORMANCE · TRACE','Residual response under reduced motion','The final interaction snapshot records the post-toggle response and the render-loop allocation counter.','interaction.json','fragment: final'],
  6:['EXPERT RUBRIC · COMPOSITION','Hotspot 02 competes with the product silhouette','At 768px width the annotation crosses the high-contrast enclosure edge. The interaction remains usable, but the hierarchy is less clear.','after.png','viewport: 768×720'],
  7:['SEALED EPISODE · MANIFEST','Evidence bundle is digest-addressed','The manifest binds episode identity, verifier version, trace documents, and every projected browser artifact.','manifest.json','sha256 verified']
};
document.querySelectorAll('[data-step]').forEach(button=>button.addEventListener('click',()=>{
  document.querySelectorAll('.timeline-event').forEach(x=>x.classList.remove('selected'));
  document.querySelectorAll('.finding').forEach(x=>x.classList.toggle('active',x===button));
  const target=document.querySelector(`.timeline-event[data-step="${button.dataset.step}"]`);if(target)target.classList.add('selected');
  const detail=evidenceDetails[button.dataset.step];if(detail){const panel=document.querySelector('#evidence-detail');panel.querySelector('.evidence-kind').textContent=detail[0];panel.querySelector('h3').textContent=detail[1];panel.querySelector('p').textContent=detail[2];const link=panel.querySelector('.evidence-links button');link.childNodes[0].textContent=`${detail[3]} `;link.querySelector('span').textContent=detail[4];}
}));
