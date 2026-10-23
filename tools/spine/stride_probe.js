// 估算走路动画的步速：脚落地（最低）那几帧里，脚相对身体往后移的速度就是行走速度
const fs = require("fs"), path = require("path");
const spine = new Function(fs.readFileSync(path.join(__dirname, "spine-core-3.8.js"), "utf8") + "\nreturn spine;")();
const [skel, atlasPath] = process.argv.slice(2);
class Tex extends spine.Texture { constructor() { super({ width: 1024, height: 1024 }); } setFilters() {} setWraps() {} dispose() {} }
const atlas = new spine.TextureAtlas(fs.readFileSync(atlasPath, "utf8"), () => new Tex());
const data = new spine.SkeletonBinary(new spine.AtlasAttachmentLoader(atlas)).readSkeletonData(new Uint8Array(fs.readFileSync(skel)));
const sk = new spine.Skeleton(data), anim = data.findAnimation("Move"), N = 240;
const feet = data.bones.filter((b) => /foot|toe|shoe|ankle/i.test(b.name)).map((b) => b.name);
console.log("脚部骨骼:", feet.join(", "));
const speeds = [];
for (const name of feet) {
  const track = [];
  for (let i = 0; i <= N; i++) {
    const t = anim.duration * i / N; sk.setToSetupPose();
    anim.apply(sk, t, t, true, null, 1, spine.MixBlend.setup, spine.MixDirection.mixIn); sk.updateWorldTransform();
    const b = sk.findBone(name); track.push([t, b.worldX, b.worldY]);
  }
  const minY = Math.min(...track.map((p) => p[2]));
  // 落地帧：离最低点 3 个单位以内，取相邻落地帧之间的水平速度
  const v = [];
  for (let i = 1; i < track.length; i++) if (track[i][2] - minY < 3 && track[i - 1][2] - minY < 3) v.push((track[i - 1][1] - track[i][1]) / (track[i][0] - track[i - 1][0]));
  if (v.length) { const m = v.sort((a, b) => a - b)[Math.floor(v.length / 2)]; speeds.push(Math.abs(m)); console.log(`${name}: 落地 ${v.length} 帧，中位速度 ${m.toFixed(1)} 单位/秒`); }
}
if (speeds.length) console.log("估计步速 ≈", (speeds.reduce((a, b) => a + b) / speeds.length).toFixed(0), "单位/秒");
