import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { FaceLandmarker, FilesetResolver } from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/+esm";

const LEFT_IRIS = 468;
const RIGHT_IRIS = 473;
const eye = { x: 0, y: 0.02, z: 0.55 };
let mode = "demo";
let modelId = "orrery";
let tracking = false;
let sample = { left: null, right: null, face: null, ipd: 0 };
let stream = null;
let landmarker = null;
let camRaf = 0;
let demoT = 0;
let mouse = null;
let world = null;

const stage = document.getElementById("stage");
const statusEl = document.getElementById("status");
const lockEl = document.getElementById("lock");
const coordsEl = document.getElementById("coords");
const errEl = document.getElementById("err");
const video = document.getElementById("video");
const trackCanvas = document.getElementById("track");
const tctx = trackCanvas.getContext("2d");

function metal(color) {
  return new THREE.MeshPhysicalMaterial({
    color, metalness: 0.92, roughness: 0.28, clearcoat: 0.4,
  });
}

function applyOffAxis(camera, e, sw, sh) {
  const z = Math.max(0.12, e.z);
  const near = Math.min(Math.max(0.04, z * 0.08), z * 0.45);
  const l = (near * (-sw / 2 - e.x)) / z;
  const r = (near * (sw / 2 - e.x)) / z;
  const b = (near * (-sh / 2 - e.y)) / z;
  const t = (near * (sh / 2 - e.y)) / z;
  camera.position.set(e.x, e.y, e.z);
  camera.quaternion.identity();
  camera.projectionMatrix.makePerspective(l, r, t, b, near, 8);
  camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert();
  camera.updateMatrixWorld();
}

function buildRoom(sw, sh) {
  const g = new THREE.Group();
  const d = 1.15;
  const wall = new THREE.MeshStandardMaterial({ color: 0x101218, roughness: 0.86, metalness: 0.08 });
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(sw, d), wall);
  floor.rotation.x = -Math.PI / 2;
  floor.position.set(0, -sh / 2, -d / 2);
  const back = new THREE.Mesh(new THREE.PlaneGeometry(sw, sh), wall);
  back.position.z = -d;
  const left = new THREE.Mesh(new THREE.PlaneGeometry(d, sh), wall);
  left.rotation.y = Math.PI / 2;
  left.position.set(-sw / 2, 0, -d / 2);
  const right = left.clone();
  right.rotation.y = -Math.PI / 2;
  right.position.set(sw / 2, 0, -d / 2);
  g.add(floor, back, left, right);
  const grid = new THREE.GridHelper(Math.min(sw, d) * 0.9, 10, 0x3a4048, 0x1c2028);
  grid.position.set(0, -sh / 2 + 0.001, -d * 0.42);
  g.add(grid);
  const frameM = metal(0x8b939e);
  const t = 0.012;
  [[sw + t * 2, t, 0, sh / 2 + t / 2], [sw + t * 2, t, 0, -sh / 2 - t / 2], [t, sh + t * 2, -sw / 2 - t / 2, 0], [t, sh + t * 2, sw / 2 + t / 2, 0]].forEach(([bw, bh, x, y]) => {
    const bar = new THREE.Mesh(new THREE.BoxGeometry(bw, bh, 0.028), frameM);
    bar.position.set(x, y, 0);
    g.add(bar);
  });
  return g;
}

function orrery() {
  const root = new THREE.Group();
  const sun = new THREE.Mesh(new THREE.SphereGeometry(0.048, 48, 32), new THREE.MeshPhysicalMaterial({
    color: 0xf2d6b3, emissive: 0xe8c39a, emissiveIntensity: 1.6, roughness: 0.35,
  }));
  root.add(sun);
  root.userData.core = sun;
  const rings = [
    [0.11, 0.18, 0.22, "y"],
    [0.155, 1.05, -0.16, "x"],
    [0.2, 0.55, 0.12, "y"],
    [0.245, -0.7, -0.09, "z"],
  ];
  root.userData.rings = [];
  for (const [r, tilt, spin, axis] of rings) {
    const mesh = new THREE.Mesh(new THREE.TorusGeometry(r, 0.0032, 12, 80), metal(0xc5ccd6));
    mesh.rotation.x = tilt;
    mesh.userData = { spin, axis };
    root.add(mesh);
    root.userData.rings.push(mesh);
  }
  root.userData.planets = [];
  [0.11, 0.155, 0.2, 0.245].forEach((radius, i) => {
    const p = new THREE.Mesh(new THREE.SphereGeometry(0.012 + i * 0.003, 20, 14), metal(0xb7c4d4));
    root.add(p);
    root.userData.planets.push({ mesh: p, radius, speed: 0.35 - i * 0.05, phase: i * 1.2 });
  });
  return root;
}

function relic() {
  const root = new THREE.Group();
  const knot = new THREE.Mesh(new THREE.TorusKnotGeometry(0.075, 0.022, 140, 16), metal(0xc5ccd6));
  root.add(knot);
  root.userData.core = knot;
  const cage = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.IcosahedronGeometry(0.175, 1)), new THREE.LineBasicMaterial({ color: 0x9aa4b0 }));
  cage.userData = { spin: 0.12, axis: "y" };
  root.add(cage);
  root.userData.rings = [cage];
  root.userData.planets = [];
  return root;
}

function vessel() {
  const root = new THREE.Group();
  const body = metal(0xc5ccd6);
  const hull = new THREE.Mesh(new THREE.CapsuleGeometry(0.038, 0.16, 8, 18), body);
  hull.rotation.z = Math.PI / 2;
  const nose = new THREE.Mesh(new THREE.ConeGeometry(0.038, 0.08, 18), body);
  nose.rotation.z = -Math.PI / 2;
  nose.position.x = 0.13;
  const engine = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.024, 0.03, 16), new THREE.MeshPhysicalMaterial({
    color: 0xf2d6b3, emissive: 0xf2d6b3, emissiveIntensity: 2,
  }));
  engine.rotation.z = Math.PI / 2;
  engine.position.x = -0.12;
  root.add(hull, nose, engine);
  root.userData.core = engine;
  root.userData.rings = [];
  root.userData.planets = [];
  root.rotation.y = -0.35;
  return root;
}

const builders = { orrery, relic, vessel };

const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: "high-performance" });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.domElement.className = "hologram";
stage.appendChild(renderer.domElement);
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x07080a);
scene.fog = new THREE.FogExp2(0x07080a, 0.22);
const camera = new THREE.PerspectiveCamera(32, 1, 0.05, 8);
scene.add(new THREE.AmbientLight(0xb8c0ca, 0.22));
const key = new THREE.DirectionalLight(0xf2f4f7, 1.3);
key.position.set(0.4, 0.55, 0.7);
scene.add(key, new THREE.PointLight(0xe8c39a, 1.5, 1.4, 2));
let room = new THREE.Group();
let model = new THREE.Group();
scene.add(room, model);
let composer = null;
let screenW = 0.4;
let screenH = 0.25;

function resize() {
  const w = innerWidth;
  const h = innerHeight;
  renderer.setSize(w, h, false);
  composer?.setSize(w, h);
  screenH = 0.235;
  screenW = screenH * (w / h);
  scene.remove(room);
  room = buildRoom(screenW, screenH);
  scene.add(room);
  if (!composer) {
    composer = new EffectComposer(renderer);
    composer.addPass(new RenderPass(scene, camera));
    composer.addPass(new UnrealBloomPass(new THREE.Vector2(w, h), 0.38, 0.55, 0.78));
    composer.addPass(new OutputPass());
  }
}

function setModel(id) {
  modelId = id;
  scene.remove(model);
  model = builders[id]();
  scene.add(model);
  document.querySelectorAll("[data-model]").forEach((b) => b.classList.toggle("active", b.dataset.model === id));
}

function fmt(n) {
  return `${n < 0 ? "−" : "+"}${Math.abs(n).toFixed(3)}`;
}

function drawTrack() {
  const w = trackCanvas.width;
  const h = trackCanvas.height;
  tctx.clearRect(0, 0, w, h);
  if (video.readyState >= 2) {
    tctx.save();
    tctx.translate(w, 0);
    tctx.scale(-1, 1);
    tctx.drawImage(video, 0, 0, w, h);
    tctx.restore();
  } else {
    tctx.fillStyle = "#12141a";
    tctx.fillRect(0, 0, w, h);
    tctx.fillStyle = "#8b939e";
    tctx.font = "500 11px IBM Plex Mono, monospace";
    tctx.fillText("Kamera aus  ·  Demo aktiv", 16, h / 2);
  }
  const mx = (x) => (1 - x) * w;
  const my = (y) => y * h;
  if (sample.left && sample.right) {
    const lx = mx(sample.left.x), ly = my(sample.left.y);
    const rx = mx(sample.right.x), ry = my(sample.right.y);
    tctx.strokeStyle = "rgba(197,204,214,0.7)";
    tctx.beginPath(); tctx.moveTo(lx, ly); tctx.lineTo(rx, ry); tctx.stroke();
    for (const [x, y, lab] of [[lx, ly, "L"], [rx, ry, "R"]]) {
      tctx.beginPath(); tctx.arc(x, y, 7, 0, Math.PI * 2); tctx.strokeStyle = "#c5ccd6"; tctx.stroke();
      tctx.beginPath(); tctx.arc(x, y, 2.2, 0, Math.PI * 2); tctx.fillStyle = "#f4f4f5"; tctx.fill();
      tctx.fillStyle = "#c5ccd6"; tctx.font = "600 9px IBM Plex Mono, monospace"; tctx.fillText(lab, x + 9, y - 8);
    }
  }
}

let last = performance.now();
function tick(now) {
  const dt = Math.min((now - last) / 1000, 0.1);
  last = now;
  let target = { ...eye };
  if (mode === "camera" && tracking && world) target = world;
  else if (mode === "mouse" && mouse) target = { x: (mouse.x - 0.5) * 0.48, y: (0.5 - mouse.y) * 0.28, z: 0.55 };
  else {
    demoT += dt;
    target = { x: Math.sin(demoT * 0.55) * 0.16, y: Math.sin(demoT * 0.37) * 0.07 + 0.02, z: 0.54 + Math.sin(demoT * 0.22) * 0.07 };
  }
  const k = 1 - Math.exp(-10 * dt);
  eye.x += (target.x - eye.x) * k;
  eye.y += (target.y - eye.y) * k;
  eye.z += (target.z - eye.z) * k;
  applyOffAxis(camera, eye, screenW, screenH);
  if (model.userData.rings) for (const r of model.userData.rings) r.rotation[r.userData.axis] += r.userData.spin * dt;
  if (model.userData.planets) for (const p of model.userData.planets) {
    p.phase += p.speed * dt;
    p.mesh.position.set(Math.cos(p.phase) * p.radius, 0, Math.sin(p.phase) * p.radius);
  }
  if (model.userData.core) model.userData.core.rotation.y += dt * 0.2;
  composer ? composer.render() : renderer.render(scene, camera);
  drawTrack();
  coordsEl.textContent = `X ${fmt(eye.x)}  Y ${fmt(eye.y)}  Z ${fmt(eye.z)}`;
  requestAnimationFrame(tick);
}

function setStatus() {
  const live = mode === "camera" && tracking;
  statusEl.classList.toggle("live", live);
  statusEl.lastChild.textContent = live ? " Tracking live" : mode === "mouse" ? " Maus-Parallax" : " Demo-Orbit";
  lockEl.textContent = live ? "IRIS LOCK" : "IDLE";
  lockEl.style.color = live ? "var(--live)" : "var(--muted)";
}

async function startCam() {
  errEl.hidden = true;
  try {
    stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user", width: { ideal: 1280 } }, audio: false });
    video.srcObject = stream;
    await video.play();
    const fileset = await FilesetResolver.forVisionTasks("https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/wasm");
    landmarker = await FaceLandmarker.createFromOptions(fileset, {
      baseOptions: {
        modelAssetPath: "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task",
        delegate: "GPU",
      },
      runningMode: "VIDEO",
      numFaces: 1,
    });
    mode = "camera";
    const loop = () => {
      if (!landmarker || video.readyState < 2) { camRaf = requestAnimationFrame(loop); return; }
      const res = landmarker.detectForVideo(video, performance.now());
      const face = res.faceLandmarks?.[0];
      if (face && face[LEFT_IRIS] && face[RIGHT_IRIS]) {
        const L = face[LEFT_IRIS], R = face[RIGHT_IRIS];
        sample = { left: { x: L.x, y: L.y }, right: { x: R.x, y: R.y }, ipd: Math.hypot(L.x - R.x, L.y - R.y) };
        const midX = (L.x + R.x) / 2, midY = (L.y + R.y) / 2;
        const z = Math.min(1.25, Math.max(0.28, 0.56 * (0.078 / Math.max(sample.ipd, 0.02))));
        world = { x: (0.5 - midX) * 2 * screenW * 0.8, y: (0.5 - midY) * 2 * screenH * 0.7, z };
        tracking = true;
      } else tracking = false;
      setStatus();
      camRaf = requestAnimationFrame(loop);
    };
    camRaf = requestAnimationFrame(loop);
    setStatus();
  } catch (e) {
    errEl.hidden = false;
    errEl.textContent = e.name === "NotAllowedError" ? "Kamera blockiert." : (e.message || "Kamera nicht verfügbar");
  }
}

function stopCam() {
  cancelAnimationFrame(camRaf);
  stream?.getTracks().forEach((t) => t.stop());
  stream = null;
  landmarker?.close();
  landmarker = null;
  video.srcObject = null;
  tracking = false;
  mode = "demo";
  setStatus();
}

document.getElementById("cam").onclick = () => (stream ? stopCam() : startCam());
document.getElementById("demo").onclick = stopCam;
document.querySelectorAll("[data-model]").forEach((b) => { b.onclick = () => setModel(b.dataset.model); });
window.addEventListener("pointermove", (e) => {
  mouse = { x: e.clientX / innerWidth, y: e.clientY / innerHeight };
  if (mode === "demo") { mode = "mouse"; setStatus(); }
});
window.addEventListener("resize", resize);
resize();
setModel("orrery");
setStatus();
requestAnimationFrame(tick);
