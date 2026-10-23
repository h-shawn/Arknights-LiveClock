#!/usr/bin/env node
// 用 Spine 官方 3.8 核心运行时计算骨骼动画，再用纯 JS 软件光栅化成 PNG 序列（不依赖任何原生模块）。
//
// 用法：node render_spine.js <skel> <atlas> <输出目录> [选项]
//   --list            只列出动画名和时长
//   --anim 名称       要渲染的动画，默认依次找 Relax / Idle / Default
//   --fps 30          帧率
//   --size 416x496    输出尺寸（手表 46mm 原生分辨率）
//   --height 0.6      角色占画面高度的比例
//   --cx 0.5 --cy 0.5 角色包围盒中心在画面里的位置（比例）
//   --ss 2            超采样倍数（抗锯齿）
//   --bg 1a1f2b,05070a 背景竖向渐变：上,下
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
if (!skelPath || !atlasPath || !outDir) { console.error("用法：node render_spine.js <skel> <atlas> <输出目录> [选项]"); process.exit(1); }

// ---------- 贴图与骨骼 ----------
const pma = !!opts.pma;
const pages = {};
function loadPage(name) {
  const png = PNG.sync.read(fs.readFileSync(path.join(path.dirname(atlasPath), name)));
  const { width, height, data } = png;
  const f = new Float32Array(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    const a = data[i * 4 + 3] / 255;
    const k = pma ? 1 / 255 : a / 255;   // 统一转成预乘 alpha，双线性过滤才不会有黑边
    f[i * 4] = data[i * 4] * k; f[i * 4 + 1] = data[i * 4 + 1] * k; f[i * 4 + 2] = data[i * 4 + 2] * k; f[i * 4 + 3] = a;
  }
  return { width, height, f };
}
// 3.8 运行时用贴图对象的宽高去归一化 UV。PRTS 上的贴图常被缩小过（比如图集写 516，实际 344），
// 所以这里报图集里写的原始尺寸，采样时再按实际像素尺寸换算。
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
const binary = new spine.SkeletonBinary(new spine.AtlasAttachmentLoader(atlas));
const skeletonData = binary.readSkeletonData(new Uint8Array(fs.readFileSync(skelPath)));
const skeleton = new spine.Skeleton(skeletonData);

if (opts.list) {
  for (const a of skeletonData.animations) console.log(`${a.name}\t${a.duration.toFixed(3)}s`);
  process.exit(0);
}
const fps = Number(opts.fps || 30);
const [W, H] = String(opts.size || "416x496").split("x").map(Number);
const SS = Number(opts.ss || 2);

// 两种模式：单个动画循环；或 --seq 动作序列（JSON 数组，每段 {anim, dur, dx?, face?}）。
// dx 是这一段里水平移动的距离（骨骼单位），负数往左走并转身；face 强制朝向（1 右，-1 左）。
const seq = typeof opts.seq === "string" ? JSON.parse(opts.seq)
  : [{ anim: typeof opts.anim === "string" ? opts.anim
      : (["Relax", "Idle", "Default"].find((n) => skeletonData.findAnimation(n)) || skeletonData.animations[0].name) }];
for (const s of seq) {
  const a = skeletonData.findAnimation(s.anim);
  if (!a) { console.error(`没有这个动画：${s.anim}`); process.exit(1); }
  if (!s.dur) s.dur = a.duration;
}
const total = seq.reduce((sum, s) => sum + s.dur, 0);
const frames = Math.max(1, Math.round(total * fps));
const starts = [], xStarts = [];
{ let t = 0, x = 0; for (const s of seq) { starts.push(t); xStarts.push(x); t += s.dur; x += s.dx || 0; } }

// 逐帧推进 AnimationState，段与段之间按 --mix 秒混合过渡
function simulate(onFrame) {
  const stateData = new spine.AnimationStateData(skeletonData);
  stateData.defaultMix = seq.length > 1 ? Number(opts.mix || 0.15) : 0;
  const state = new spine.AnimationState(stateData);
  skeleton.setToSetupPose();
  let seg = -1, facing = 1;
  for (let i = 0; i < frames; i++) {
    const t = (total * i) / frames;
    while (seg + 1 < seq.length && t >= starts[seg + 1] - 1e-9) {
      seg++;
      state.setAnimation(0, seq[seg].anim, true);
      if (seq[seg].face) facing = seq[seg].face; else if (seq[seg].dx) facing = Math.sign(seq[seg].dx);
    }
    state.update(i === 0 ? 0 : total / frames);
    const s = seq[seg];
    skeleton.x = xStarts[seg] + (s.dx || 0) * Math.min(1, (t - starts[seg]) / s.dur);
    skeleton.scaleX = facing;
    state.apply(skeleton);
    skeleton.updateWorldTransform();
    onFrame(i);
  }
}

// ---------- 遍历可见网格 ----------
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
        fn({ count: t.length, idx: (k) => t[k] * 8, xy: v, uv: v, uvOff: 6, xyStride: 8, page, color, blend });
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

// ---------- 整段动画的包围盒，保证角色在画面里不乱跑 ----------
let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
simulate(() => {
  forEachMesh((m) => { for (let k = 0; k < m.count; k++) { const [x, y] = vert(m, k);
    if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y; } });
});
const bw = maxX - minX, bh = maxY - minY;
const scale = Math.min((H * Number(opts.height || 0.6)) / bh, (W * 0.92) / bw) * SS;
const cx = W * SS * Number(opts.cx || 0.5), cy = H * SS * Number(opts.cy || 0.5);
const mx = (minX + maxX) / 2, my = (minY + maxY) / 2;
const toX = (x) => cx + (x - mx) * scale;
const toY = (y) => cy - (y - my) * scale;   // Spine 是 y 向上

// ---------- 光栅化 ----------
const BW = W * SS, BH = H * SS;
const buf = new Float32Array(BW * BH * 4);
const [bgTop, bgBottom] = String(opts.bg || "1a1f2b,05070a").split(",").map((h) => [0, 2, 4].map((o) => parseInt(h.slice(o, o + 2), 16) / 255));
function clear() {
  for (let y = 0; y < BH; y++) {
    const t = y / (BH - 1);
    const r = bgTop[0] + (bgBottom[0] - bgTop[0]) * t, g = bgTop[1] + (bgBottom[1] - bgTop[1]) * t, b = bgTop[2] + (bgBottom[2] - bgTop[2]) * t;
    for (let x = 0; x < BW; x++) { const o = (y * BW + x) * 4; buf[o] = r; buf[o + 1] = g; buf[o + 2] = b; buf[o + 3] = 1; }
  }
}
function sample(page, u, v, out) {
  const { width: tw, height: th, f } = page;
  let x = u * tw - 0.5, y = v * th - 0.5;
  const x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;
  const cx0 = Math.min(Math.max(x0, 0), tw - 1), cx1 = Math.min(Math.max(x0 + 1, 0), tw - 1);
  const cy0 = Math.min(Math.max(y0, 0), th - 1), cy1 = Math.min(Math.max(y0 + 1, 0), th - 1);
  const a = (cy0 * tw + cx0) * 4, b = (cy0 * tw + cx1) * 4, c = (cy1 * tw + cx0) * 4, d = (cy1 * tw + cx1) * 4;
  for (let i = 0; i < 4; i++) {
    out[i] = (f[a + i] * (1 - fx) + f[b + i] * fx) * (1 - fy) + (f[c + i] * (1 - fx) + f[d + i] * fx) * fy;
  }
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
      } else {
        buf[o] = sr + buf[o] * (1 - sa); buf[o + 1] = sg + buf[o + 1] * (1 - sa); buf[o + 2] = sb + buf[o + 2] * (1 - sa);
      }
    }
  }
}

fs.mkdirSync(outDir, { recursive: true });
for (const f of fs.readdirSync(outDir)) if (/^frame-\d+\.png$/.test(f)) fs.unlinkSync(path.join(outDir, f));
// 脚下的影子：以骨骼原点（脚底）为中心的柔和椭圆
function shadow() {
  const sx = toX(skeleton.x), sy = toY(0), rx = bh * 0.15 * scale, ry = rx * 0.22;
  for (let y = Math.max(0, Math.floor(sy - ry)); y <= Math.min(BH - 1, Math.ceil(sy + ry)); y++) {
    for (let x = Math.max(0, Math.floor(sx - rx)); x <= Math.min(BW - 1, Math.ceil(sx + rx)); x++) {
      const d = ((x + 0.5 - sx) / rx) ** 2 + ((y + 0.5 - sy) / ry) ** 2;
      if (d >= 1) continue;
      const k = 1 - 0.45 * (1 - d) ** 1.5, o = (y * BW + x) * 4;
      buf[o] *= k; buf[o + 1] *= k; buf[o + 2] *= k;
    }
  }
}

const png = new PNG({ width: W, height: H });
simulate((i) => {
  clear();
  if (opts.shadow) shadow();
  forEachMesh((m) => { for (let k = 0; k + 2 < m.count; k += 3) triangle(m, vert(m, k), vert(m, k + 1), vert(m, k + 2)); });
  // 超采样下采样到输出尺寸
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    let r = 0, g = 0, b = 0;
    for (let dy = 0; dy < SS; dy++) for (let dx = 0; dx < SS; dx++) {
      const o = ((y * SS + dy) * BW + x * SS + dx) * 4; r += buf[o]; g += buf[o + 1]; b += buf[o + 2];
    }
    const n = SS * SS, o = (y * W + x) * 4;
    png.data[o] = Math.min(255, Math.round((r / n) * 255)); png.data[o + 1] = Math.min(255, Math.round((g / n) * 255));
    png.data[o + 2] = Math.min(255, Math.round((b / n) * 255)); png.data[o + 3] = 255;
  }
  fs.writeFileSync(path.join(outDir, `frame-${String(i).padStart(4, "0")}.png`), PNG.sync.write(png));
});
console.log(`${seq.map((s) => s.anim).join(" → ")}：${frames} 帧，${total.toFixed(3)} 秒一圈，${fps} fps，包围盒 ${bw.toFixed(0)}×${bh.toFixed(0)} → ${outDir}`);
