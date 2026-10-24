#!/usr/bin/env node
// 给 LiveFace 的「桌宠」模式出素材：待机、走路、互动三个动作，各一组透明底精灵帧（pet-relax-0000.png …）和 pet.json。
// 用 Spine 官方 3.8 核心运行时计算骨骼动画，纯 JS 软件光栅化（不依赖原生模块）。
//
// 用法：node render_pet.js <skel> <atlas> <输出目录> [选项]
//   --relax Relax --move Move --interact Interact   三个动作对应的动画名
//   --height 278      角色高度（像素，按 46mm 屏幕 @2x）
//   --fps 30
//   --walk 97         走路速度（骨骼单位/秒），和 Move 的步幅对上脚才不打滑
//   --ss 2            超采样倍数（抗锯齿）
//   --pma             贴图是预乘 alpha
const fs = require("fs");
const path = require("path");
const { PNG } = require("pngjs");

const spine = new Function(fs.readFileSync(path.join(__dirname, "spine-core-3.8.js"), "utf8") + "\nreturn spine;")();

const [skelPath, atlasPath, outDir] = process.argv.slice(2, 5);
const opts = {};
for (let i = 5; i < process.argv.length; i++) {
  const k = process.argv[i].replace(/^--/, "");
  const next = process.argv[i + 1];
  if (next === undefined || next.startsWith("--")) opts[k] = true; else { opts[k] = next; i++; }
}
if (!skelPath || !atlasPath || !outDir) { console.error("用法：node render_pet.js <skel> <atlas> <输出目录> [选项]"); process.exit(1); }

// ---------- 贴图与骨骼（同 render_spine.js） ----------
const pma = !!opts.pma;
const pages = {};
function loadPage(name) {
  const png = PNG.sync.read(fs.readFileSync(path.join(path.dirname(atlasPath), name)));
  const { width, height, data } = png;
  const f = new Float32Array(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    const a = data[i * 4 + 3] / 255;
    const k = pma ? 1 / 255 : a / 255;
    f[i * 4] = data[i * 4] * k; f[i * 4 + 1] = data[i * 4 + 1] * k; f[i * 4 + 2] = data[i * 4 + 2] * k; f[i * 4 + 3] = a;
  }
  return { width, height, f };
}
const atlasText = fs.readFileSync(atlasPath, "utf8");
const atlasSizes = {};
{
  const lines = atlasText.split(/\r?\n/).map((l) => l.trim());
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i + 1] && lines[i + 1].match(/^size:\s*(\d+)\s*,\s*(\d+)/);
    if (/\.png$/i.test(lines[i]) && m) atlasSizes[lines[i]] = { width: Number(m[1]), height: Number(m[2]) };
  }
}
class Tex extends spine.Texture {
  constructor(name, size) { super(size); this.name = name; }
  setFilters() {} setWraps() {} dispose() {}
}
const atlas = new spine.TextureAtlas(atlasText, (name) => {
  pages[name] = loadPage(name);
  return new Tex(name, atlasSizes[name] || { width: pages[name].width, height: pages[name].height });
});
const skeletonData = new spine.SkeletonBinary(new spine.AtlasAttachmentLoader(atlas))
  .readSkeletonData(new Uint8Array(fs.readFileSync(skelPath)));
const skeleton = new spine.Skeleton(skeletonData);

const roles = {
  relax: typeof opts.relax === "string" ? opts.relax : (skeletonData.findAnimation("Relax") ? "Relax" : "Idle"),
  move: typeof opts.move === "string" ? opts.move : "Move",
  interact: typeof opts.interact === "string" ? opts.interact : "Interact",
  sit: typeof opts.sit === "string" ? opts.sit : "Sit",          // 可选：坐（原点是椅面）
  sleep: typeof opts.sleep === "string" ? opts.sleep : "Sleep",  // 可选：睡觉（原点是床面）
};
const fps = Number(opts.fps || 30);
const slowFps = Number(opts["slow-fps"] || 15);   // 坐、睡动作慢，用低帧率省空间
const SS = Number(opts.ss || 2);
const clips = {};
for (const [role, name] of Object.entries(roles)) {
  const animation = skeletonData.findAnimation(name);
  if (!animation) {
    if (role === "sit" || role === "sleep") continue;
    console.error(`没有这个动画：${name}（${role}）`); process.exit(1);
  }
  const f = role === "sit" || role === "sleep" ? slowFps : fps;
  clips[role] = { animation, fps: f, frames: Math.max(1, Math.round(animation.duration * f)) };
}

function pose(animation, frames, i) {
  skeleton.setToSetupPose();
  const t = (animation.duration * i) / frames;
  animation.apply(skeleton, t, t, true, null, 1, spine.MixBlend.setup, spine.MixDirection.mixIn);
  skeleton.updateWorldTransform();
}

const clipper = new spine.SkeletonClipping();
const quad = [0, 1, 2, 2, 3, 0];
let worldVerts = new Float32Array(2048);
function forEachMesh(fn) {
  const sc = skeleton.color;
  for (const slot of skeleton.drawOrder) {
    if (!slot.bone.active) { clipper.clipEndWithSlot(slot); continue; }
    const att = slot.getAttachment();
    let n, uvs, tris, region;
    if (att instanceof spine.RegionAttachment) {
      n = 8; att.computeWorldVertices(slot.bone, worldVerts, 0, 2); uvs = att.uvs; tris = quad; region = att.region;
    } else if (att instanceof spine.MeshAttachment) {
      n = att.worldVerticesLength;
      if (worldVerts.length < n) worldVerts = new Float32Array(n * 2);
      att.computeWorldVertices(slot, 0, n, worldVerts, 0, 2); uvs = att.uvs; tris = att.triangles; region = att.region;
    } else if (att instanceof spine.ClippingAttachment) {
      clipper.clipStart(slot, att); continue;
    } else { clipper.clipEndWithSlot(slot); continue; }
    const ac = att.color, cc = slot.color;
    const color = new spine.Color(sc.r * cc.r * ac.r, sc.g * cc.g * ac.g, sc.b * cc.b * ac.b, sc.a * cc.a * ac.a);
    const page = pages[region.page.name];
    const blend = slot.data.blendMode;
    if (color.a > 0) {
      if (clipper.isClipping()) {
        clipper.clipTriangles(worldVerts, n, tris, tris.length, uvs, color, color, false);
        const v = clipper.clippedVertices, t = clipper.clippedTriangles;
        fn({ count: t.length, idx: (k) => t[k] * 8, xy: v, uv: v, page, color, blend });
      } else {
        fn({ count: tris.length, idx: (k) => tris[k], xy: worldVerts, uv: uvs, page, color, blend, plain: true });
      }
    }
    clipper.clipEndWithSlot(slot);
  }
  clipper.clipEnd();
}
function vert(m, k) {
  if (m.plain) { const j = m.idx(k); return [m.xy[j * 2], m.xy[j * 2 + 1], m.uv[j * 2], m.uv[j * 2 + 1]]; }
  const o = m.idx(k); return [m.xy[o], m.xy[o + 1], m.uv[o + 6], m.uv[o + 7]];
}

// ---------- 每个动作一张画布，记下骨骼原点在图里的像素位置（锚点） ----------
// 缩放统一按待机和走路的最大身高算，坐、睡、互动和站着时一样大（互动常有跳起、挥武器，不算进去，不然人会被缩小）
let poseHeight = 0;
for (const [role, clip] of Object.entries(clips)) {
  clip.minX = Infinity; clip.minY = Infinity; clip.maxX = -Infinity; clip.maxY = -Infinity;
  for (let i = 0; i < clip.frames; i++) {
    pose(clip.animation, clip.frames, i);
    let lo = Infinity, hi = -Infinity;
    forEachMesh((m) => { for (let k = 0; k < m.count; k++) { const [x, y] = vert(m, k);
      clip.minX = Math.min(clip.minX, x); clip.maxX = Math.max(clip.maxX, x);
      clip.minY = Math.min(clip.minY, y); clip.maxY = Math.max(clip.maxY, y);
      lo = Math.min(lo, y); hi = Math.max(hi, y); } });
    if (role === "relax" || role === "move") poseHeight = Math.max(poseHeight, hi - lo);
  }
}
const scale = Number(opts.height || 278) / poseHeight;   // 像素/骨骼单位
const pad = 2;

// ---------- 光栅化（透明底，预乘 alpha）；画布随当前动作切换 ----------
let cur, W, H, BW, BH, buf;
function useClip(clip) {
  cur = clip;
  W = Math.ceil((clip.maxX - clip.minX) * scale) + pad * 2; H = Math.ceil((clip.maxY - clip.minY) * scale) + pad * 2;
  BW = W * SS; BH = H * SS; buf = new Float32Array(BW * BH * 4);
}
const toX = (x) => ((x - cur.minX) * scale + pad) * SS;
const toY = (y) => ((cur.maxY - y) * scale + pad) * SS;
function sample(page, u, v, out) {
  const { width: tw, height: th, f } = page;
  const x = u * tw - 0.5, y = v * th - 0.5;
  const x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;
  const cx0 = Math.min(Math.max(x0, 0), tw - 1), cx1 = Math.min(Math.max(x0 + 1, 0), tw - 1);
  const cy0 = Math.min(Math.max(y0, 0), th - 1), cy1 = Math.min(Math.max(y0 + 1, 0), th - 1);
  const a = (cy0 * tw + cx0) * 4, b = (cy0 * tw + cx1) * 4, c = (cy1 * tw + cx0) * 4, d = (cy1 * tw + cx1) * 4;
  for (let i = 0; i < 4; i++) out[i] = (f[a + i] * (1 - fx) + f[b + i] * fx) * (1 - fy) + (f[c + i] * (1 - fx) + f[d + i] * fx) * fy;
}
const texel = new Float32Array(4);
function triangle(m, p0, p1, p2) {
  const x0 = toX(p0[0]), y0 = toY(p0[1]), x1 = toX(p1[0]), y1 = toY(p1[1]), x2 = toX(p2[0]), y2 = toY(p2[1]);
  const area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
  if (Math.abs(area) < 1e-9) return;
  const xs = Math.max(0, Math.floor(Math.min(x0, x1, x2))), xe = Math.min(BW - 1, Math.ceil(Math.max(x0, x1, x2)));
  const ys = Math.max(0, Math.floor(Math.min(y0, y1, y2))), ye = Math.min(BH - 1, Math.ceil(Math.max(y0, y1, y2)));
  const { r, g, b, a } = m.color, blend = m.blend;
  for (let py = ys; py <= ye; py++) {
    const sy = py + 0.5;
    for (let px = xs; px <= xe; px++) {
      const sx = px + 0.5;
      const w0 = ((x1 - sx) * (y2 - sy) - (x2 - sx) * (y1 - sy)) / area;
      const w1 = ((x2 - sx) * (y0 - sy) - (x0 - sx) * (y2 - sy)) / area;
      const w2 = 1 - w0 - w1;
      if (w0 < 0 || w1 < 0 || w2 < 0) continue;
      sample(m.page, w0 * p0[2] + w1 * p1[2] + w2 * p2[2], w0 * p0[3] + w1 * p1[3] + w2 * p2[3], texel);
      const sa = texel[3] * a;
      if (sa <= 0 && blend !== spine.BlendMode.Additive) continue;
      const sr = texel[0] * r * a, sg = texel[1] * g * a, sb = texel[2] * b * a;
      const o = (py * BW + px) * 4;
      if (blend === spine.BlendMode.Additive) {
        buf[o] += sr; buf[o + 1] += sg; buf[o + 2] += sb;
      } else if (blend === spine.BlendMode.Multiply) {
        buf[o] = sr * buf[o] + buf[o] * (1 - sa); buf[o + 1] = sg * buf[o + 1] + buf[o + 1] * (1 - sa); buf[o + 2] = sb * buf[o + 2] + buf[o + 2] * (1 - sa);
      } else if (blend === spine.BlendMode.Screen) {
        buf[o] = sr + buf[o] * (1 - sr); buf[o + 1] = sg + buf[o + 1] * (1 - sg); buf[o + 2] = sb + buf[o + 2] * (1 - sb);
        buf[o + 3] = sa + buf[o + 3] * (1 - sa);
      } else {
        buf[o] = sr + buf[o] * (1 - sa); buf[o + 1] = sg + buf[o + 1] * (1 - sa); buf[o + 2] = sb + buf[o + 2] * (1 - sa);
        buf[o + 3] = sa + buf[o + 3] * (1 - sa);
      }
    }
  }
}

fs.mkdirSync(outDir, { recursive: true });
for (const f of fs.readdirSync(outDir)) if (/^pet-.*\.png$/.test(f)) fs.unlinkSync(path.join(outDir, f));
let bytes = 0;
for (const [role, clip] of Object.entries(clips)) {
  const { animation, frames } = clip;
  useClip(clip);
  const png = new PNG({ width: W, height: H });
  clip.size = [W, H];
  clip.anchor = [(0 - clip.minX) * scale + pad, (clip.maxY - 0) * scale + pad];
  for (let i = 0; i < frames; i++) {
    pose(animation, frames, i);
    buf.fill(0);
    forEachMesh((m) => { for (let k = 0; k + 2 < m.count; k += 3) triangle(m, vert(m, k), vert(m, k + 1), vert(m, k + 2)); });
    // 超采样下采样，转回非预乘 alpha 存 PNG
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let dy = 0; dy < SS; dy++) for (let dx = 0; dx < SS; dx++) {
        const o = ((y * SS + dy) * BW + x * SS + dx) * 4; r += buf[o]; g += buf[o + 1]; b += buf[o + 2]; a += buf[o + 3];
      }
      const n = SS * SS, o = (y * W + x) * 4, al = Math.min(1, a / n);
      const k = al > 0 ? 255 / (n * al) : 0;
      png.data[o] = Math.min(255, Math.round(r * k)); png.data[o + 1] = Math.min(255, Math.round(g * k));
      png.data[o + 2] = Math.min(255, Math.round(b * k)); png.data[o + 3] = Math.round(al * 255);
    }
    const file = path.join(outDir, `pet-${role}-${String(i).padStart(4, "0")}.png`);
    fs.writeFileSync(file, PNG.sync.write(png));
    bytes += fs.statSync(file).size;
  }
}

const walkUnits = Number(opts.walk || 97);
const round1 = (v) => Math.round(v * 10) / 10;
const manifest = {
  kind: "pet",
  pixelsPerPoint: 2,
  walkSpeed: round1((walkUnits * scale) / 2),   // 46mm 屏幕上每秒走多少点
  animations: Object.fromEntries(Object.entries(clips).map(([role, c]) => [role, {
    name: c.animation.name, count: c.frames, fps: c.fps, size: c.size, anchor: c.anchor.map(round1),
    // 坐、睡的原点是椅面/床面：原点要抬离地面多少像素，身体最低点才刚好贴地
    lift: role === "sit" || role === "sleep" ? round1(Math.max(0, -c.minY) * scale) : 0,
  }])),
};
fs.writeFileSync(path.join(outDir, "pet.json"), JSON.stringify(manifest, null, 2));
console.log(`走速 ${manifest.walkSpeed} 点/秒；` + Object.entries(manifest.animations)
  .map(([r, c]) => `${r}=${c.name}×${c.count}@${c.fps} ${c.size.join("×")} 抬高${c.lift}`).join("；") + `；共 ${(bytes / 1024).toFixed(0)} KB → ${outDir}`);
